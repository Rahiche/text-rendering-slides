import 'dart:ui';

import 'package:booth3d/quality.dart';
import 'package:flutter_test/flutter_test.dart';

/// [seconds] of frames at [fps], each taking [build] and [raster] ms,
/// starting at [from] seconds.
List<FrameTiming> frames(double from, double seconds, {double fps = 60, double build = 4, double raster = 1}) => [
  for (var i = 0; i < (seconds * fps).round(); i++)
    () {
      final v = ((from + i / fps) * 1e6).round();
      final b = v + (build * 1000).round(), r = b + (raster * 1000).round();
      return FrameTiming(vsyncStart: v, buildStart: v, buildFinish: b, rasterStart: b, rasterFinish: r, rasterFinishWallTime: r);
    }(),
];

void main() {
  RenderQuality fullScreen() => RenderQuality()..screen(native: 2.14, refreshRate: 60);

  test('stays at the start ratio while frames are on time', () {
    final q = fullScreen()..addTimings(frames(0, 60));
    expect(q.ratio, 1.5);
  });

  test('steps down when the GPU falls behind, and stays there while it does', () {
    final q = fullScreen()..addTimings(frames(0, 10));
    // Warmed up: 40 fps with the raster thread waiting on the GPU.
    q.addTimings(frames(10, 5, fps: 40, raster: 22));
    expect(q.ratio, lessThan(1.5));
    final first = q.ratio;
    q.addTimings(frames(15, 20, fps: 40, raster: 22));
    expect(q.ratio, lessThan(first));
    expect(q.ratio, greaterThanOrEqualTo(0.8));
  });

  test('a slow UI thread alone does not lower the resolution', () {
    final q = fullScreen()..addTimings(frames(0, 30, fps: 45, build: 21, raster: 1));
    expect(q.ratio, 1.5);
  });

  test('recovers after a long stretch of headroom, but never above the start', () {
    final q = fullScreen()..addTimings(frames(0, 8, fps: 40, raster: 22));
    final low = q.ratio;
    expect(low, lessThan(1.5));
    q.addTimings(frames(8, 300));
    expect(q.ratio, 1.5);
  });

  test('a step up that brings the trouble back is not retried soon', () {
    final q = fullScreen()..addTimings(frames(0, 8, fps: 40, raster: 22));
    var t = 8.0;
    // Fine at the lowered ratio, struggling whenever it goes higher.
    final settled = q.ratio;
    final changes = <double>[];
    q.addListener(() => changes.add(q.ratio));
    for (var k = 0; k < 120; k++) {
      final bad = q.ratio > settled;
      q.addTimings(bad ? frames(t, 2, fps: 40, raster: 22) : frames(t, 2));
      t += 2;
    }
    // One probe up (and back down) in four minutes, not a see-saw.
    expect(changes.length, lessThanOrEqualTo(2));
    expect(q.ratio, settled);
  });

  test('never renders finer than the window shows', () {
    final q = RenderQuality()..screen(native: 0.4, refreshRate: 60);
    expect(q.ratio, 0.8);
  });
}
