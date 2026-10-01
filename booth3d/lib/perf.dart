import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter_scene/scene.dart' show Node;
import 'package:text_slides/booth/model.dart';

import 'perf_stub.dart' if (dart.library.io) 'perf_io.dart';
import 'tuning.dart';
import 'world/world.dart';

/// --dart-define=BOOTH3D_PERF=true: every few seconds, print frame times,
/// memory and the size of the scene, to find what gets slower in a long run.
class PerfLog {
  PerfLog(this.world, this.model, {this.every = const Duration(seconds: 5)});

  static const enabled = bool.fromEnvironment('BOOTH3D_PERF');

  final World3D world;
  final BoothModel model;
  final Duration every;
  final _clock = Stopwatch();
  final _build = <double>[], _raster = <double>[], _update = <double>[];
  int _frames = 0, _late = 0, _jobs = 0;
  Object? _job;
  Duration _last = Duration.zero;

  void start() {
    _clock.start();
    SchedulerBinding.instance.addTimingsCallback(_timings);
    perfLine(
      'config ratio=${Tuning.ratio ?? 'device'} aa=${Tuning.aa.name} cascades=${Tuning.cascades} shadowRes=${Tuning.shadowRes} '
      'ibl=${Tuning.iblInterval ? 'interval' : 'manual'} floodShadow=${Tuning.floodShadow} speed=${Tuning.speed}',
    );
    perfLine('perf   up_s  scene_t   fps  build_avg/max  raster_avg/max  update_avg/max  late  rss_mb  nodes  shown  jobs  night  job');
  }

  void _timings(List<FrameTiming> ts) {
    for (final f in ts) {
      _frames++;
      final b = f.buildDuration.inMicroseconds / 1000, r = f.rasterDuration.inMicroseconds / 1000;
      _build.add(b);
      _raster.add(r);
      if (b > 16.7 || r > 16.7) _late++;
    }
  }

  /// [ms]: how long this frame's world update took.
  void frame(double ms) {
    _update.add(ms);
    if (!identical(model.job, _job)) {
      _job = model.job;
      _jobs++;
    }
    final now = _clock.elapsed;
    if (now - _last < every) return;
    final secs = (now - _last).inMicroseconds / 1e6;
    _last = now;
    var nodes = 0, shown = 0;
    void walk(Node n, bool visible) {
      nodes++;
      final v = visible && n.visible;
      if (v) shown++;
      for (final c in n.children) {
        walk(c, v);
      }
    }

    walk(world.scene.root, true);
    String am(List<double> xs) {
      if (xs.isEmpty) return '    -/-   ';
      final avg = xs.reduce((a, b) => a + b) / xs.length;
      return '${avg.toStringAsFixed(1).padLeft(5)}/${xs.reduce(math.max).toStringAsFixed(1).padRight(5)}';
    }

    final j = model.job;
    perfLine(
      'perf ${now.inSeconds.toString().padLeft(6)} ${model.t.toStringAsFixed(0).padLeft(8)} '
      '${(_frames / secs).toStringAsFixed(1).padLeft(5)}  ${am(_build)}    ${am(_raster)}     ${am(_update)}  '
      '${_late.toString().padLeft(4)}  ${currentRssMb().toString().padLeft(6)}  ${nodes.toString().padLeft(5)}  '
      '${shown.toString().padLeft(5)}  ${_jobs.toString().padLeft(4)}  ${world.sky.night.toStringAsFixed(2)}  '
      '${j == null ? '-' : '${j.name} · ${j.phase.name}'}',
    );
    _frames = 0;
    _late = 0;
    _build.clear();
    _raster.clear();
    _update.clear();
  }
}
