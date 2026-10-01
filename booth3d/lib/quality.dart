import 'dart:math' as math;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Keeps the 3D view smooth on whatever runs the booth all day.
///
/// The scene is laid out on the 1600×900 design canvas and rendered at
/// [ratio] device pixels per canvas pixel. Rendering at the screen's full
/// density (2× on a Retina laptop: 3200×1800, with MSAA, shadows and bloom)
/// is more than a fanless laptop sustains once it has warmed up, and frames
/// start to drop after a while. So this watches the frame times: when frames
/// run late on the GPU (the raster thread waits for it), the ratio steps
/// down; after a long stretch with headroom, it steps back up, never above
/// [start] (a GPU kept busy all day only gets hotter) nor what the screen
/// shows. A step up that brings the trouble back is not retried for a while.
class RenderQuality extends ChangeNotifier {
  RenderQuality({this.start = 1.5, this.floor = 0.8, this.log});

  /// The ratio to begin with (and the most it goes back up to), and the
  /// lowest it goes.
  final double start, floor;

  /// Where to report changes (perf builds).
  final void Function(String)? log;

  late double _ratio = start;
  double _native = 2;
  double _target = 60;

  /// Device pixels per canvas pixel for the scene (`SceneView.pixelRatio`).
  double get ratio => _ratio;

  /// The screen's own ratio (window pixels per canvas pixel) and frame rate:
  /// the ratio never goes above the first, the frame rate aims at the second
  /// (at most 60).
  /// Called while building, so it doesn't notify: the caller uses [ratio]
  /// right after.
  void screen({required double native, required double refreshRate}) {
    _native = native;
    _target = math.min(60, refreshRate > 1 ? refreshRate : 60);
    _ratio = math.min(_ratio, _top);
  }

  double get _top => math.max(floor, math.min(start, _native));

  void attach() => SchedulerBinding.instance.addTimingsCallback(_timings);

  /// Feeds frame timings directly (tests).
  @visibleForTesting
  void addTimings(List<FrameTiming> timings) => _timings(timings);

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    super.dispose();
  }

  // One window of frames at a time.
  static const _window = Duration(seconds: 2);
  final _raster = <int>[], _build = <int>[];
  int? _windowStart, _lastVsync;
  int _frames = 0, _bad = 0, _good = 0;
  int _holdUntil = 0; // µs: no decisions before (after a change)
  int _raisedAt = -1 << 62; // µs: when we last stepped up…
  double _beforeRaise = 0; // …from this ratio
  double _ceiling = double.infinity; // a ratio that brought trouble back…
  int _ceilingUntil = 0; // …not to be tried again before then (µs)
  int _wait = 300000000; // µs: how long, doubling with each failed try

  void _timings(List<FrameTiming> timings) {
    for (final f in timings) {
      final vsync = f.timestampInMicroseconds(FramePhase.vsyncStart);
      // A long gap (window hidden, app idle) starts a fresh window.
      if (_lastVsync == null || vsync - _lastVsync! > 250000) {
        _windowStart = vsync;
        _frames = 0;
        _raster.clear();
        _build.clear();
      }
      _lastVsync = vsync;
      _frames++;
      _raster.add(f.rasterDuration.inMicroseconds);
      _build.add(f.buildDuration.inMicroseconds);
      final span = vsync - _windowStart!;
      if (span >= _window.inMicroseconds) {
        _judge(vsync, span);
        _windowStart = vsync;
        _frames = 0;
        _raster.clear();
        _build.clear();
      }
    }
  }

  void _judge(int now, int span) {
    if (now < _holdUntil || _raster.length < 20) return;
    final budget = 1e6 / _target;
    final fps = _frames * 1e6 / span;
    final raster = _p90(_raster), build = _p90(_build);
    // Late on the GPU: frames missed while the raster thread (which waits
    // for the GPU) is slow. On the web the GPU's work doesn't show in either
    // thread's time, so missed frames are all there is to go by.
    final dropping = fps < _target * 0.9;
    final struggling = dropping && (raster > budget * 0.7 || kIsWeb) || raster > budget * 1.05;
    final roomy = fps >= _target * 0.97 && math.max(raster, build) < budget * 0.55;
    final why = '${fps.toStringAsFixed(0)} fps, p90 build ${(build / 1000).toStringAsFixed(1)} ms, raster ${(raster / 1000).toStringAsFixed(1)} ms';
    if (struggling) {
      _good = 0;
      if (++_bad < 2) return;
      _bad = 0;
      if (now - _raisedAt < 12e6) {
        // The last step up did this: back to where it was fine, and don't
        // try that again for a while (twice as long each time).
        _ceiling = _ratio;
        _ceilingUntil = now + _wait;
        _wait *= 2;
        _set(_beforeRaise, 'struggling after a step up ($why)');
      } else {
        _set(math.max(floor, _ratio * 0.88), 'struggling ($why)');
      }
      _holdUntil = now + 6000000;
    } else if (roomy) {
      _bad = 0;
      if (++_good < 10) return; // ~20 s of headroom
      _good = 0;
      final next = _quantize(math.min(_top, _ratio * 1.06));
      final blocked = now < _ceilingUntil && next >= _ceiling - 0.001;
      if (next > _ratio && !blocked) {
        _beforeRaise = _ratio;
        _set(next, 'headroom ($why)');
        _raisedAt = now;
        _holdUntil = now + 4000000;
      }
    } else {
      _bad = 0;
      _good = 0;
    }
  }

  static double _p90(List<int> xs) {
    final sorted = [...xs]..sort();
    return sorted[(sorted.length * 0.9).floor().clamp(0, sorted.length - 1)].toDouble();
  }

  // Whole steps of 0.05: each change reallocates the scene's targets.
  static double _quantize(double r) => (r * 20).round() / 20;

  void _set(double r, String why) {
    final q = _quantize(r);
    if (q == _ratio) return;
    log?.call('quality ratio ${_ratio.toStringAsFixed(2)} → ${q.toStringAsFixed(2)}: $why');
    _ratio = q;
    notifyListeners();
  }
}
