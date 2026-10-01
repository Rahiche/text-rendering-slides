import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'craft/plan.dart';
import 'names.dart';
import 'raster.dart';

/// How names are built.
enum BuildMode {
  /// Name Factory: the whole name rasterized into bricks, laid bottom-up.
  bricks,

  /// Name Workshop: one character at a time, each in a different craft.
  craft,
}

/// The stages one name goes through, in order. Then the next name starts.
enum Phase {
  /// The factory reads the name: itemize → fonts → shape → raster → bricks.
  intake,

  /// Bricks ride the belt, the crane lifts them, builders lay them.
  build,

  /// A scan line develops the pixel wall into crisp text.
  reveal,

  /// Done: fireworks, cheering, the name on the sign.
  celebrate,

  /// Wrecking ball; bricks fall.
  demolish,

  /// Bulldozer and trucks haul the rubble back to the factory.
  cleanup,
}

/// Bricks travel in pallets of this many.
const palletSize = 24;

/// A pallet waits at [BL.pickup] this many seconds before its first brick is
/// laid (the crane's trip up to the wall).
const craneLead = 6.0;

/// A pallet leaves the factory's last machine this many seconds before it
/// reaches [BL.pickup] (the belt ride).
const beltLead = 5.0;

/// Fixed phase lengths in seconds ([Phase.build] varies per name).
const phaseSeconds = {
  Phase.intake: 9.0,
  Phase.reveal: 6.0,
  Phase.celebrate: 14.0,
  Phase.demolish: 12.0,
  Phase.cleanup: 10.0,
};

/// How long a name takes to build at the normal pace. An app that builds
/// names its own way sets [BoothModel.pace] (Name City lays one letter at a
/// time, with a kerning step between letters); the default is the booth's.
/// A queue speeds every pace up the same way.
class BuildPace {
  const BuildPace();

  /// Seconds to build [r] with nobody waiting: longer names take longer.
  double nominal(NameRaster r) => forBricks(r.bricks.length);

  /// [nominal] for a typical name (the wait estimate).
  double get typical => forBricks(700);

  /// Samples (built while nobody waits) take this much of [nominal].
  double get sample => 0.7;

  /// Seconds [p] lasts (not [Phase.build]: that's per name): the booth's
  /// [phaseSeconds]. An app with more to show in a phase lengthens it here.
  double phaseLen(Phase p) => phaseSeconds[p]!;

  /// The booth's pace: 35 s plus 0.075 s a brick, 50…140 s.
  static double forBricks(int bricks) => (35 + 0.075 * bricks).clamp(50.0, 140.0);
}

/// One name, from the queue to the rubble.
class Job {
  Job(
    this.name, {
    required this.serial,
    required this.submittedAt,
    this.sample = false,
    this.mode = BuildMode.bricks,
  });

  final BuildMode mode;

  /// The workshop's plan ([BuildMode.craft]), ready after intake.
  CraftPlan? plan;

  /// Build progress when the build was cut short (a sample giving way).
  double? cutFrac;

  bool get ready => mode == BuildMode.craft ? plan != null : raster != null;

  /// 0..1 through the build (0 during intake, 1 once built).
  double buildProgress(double t) {
    if (cutFrac case final f?) return f;
    return switch (phase) {
      Phase.intake => 0,
      Phase.build => progress(t),
      _ => 1,
    };
  }

  final String name;
  final int serial;
  final double submittedAt;

  /// Built while nobody was waiting (gives way to a real name).
  final bool sample;

  NameRaster? raster;
  Phase phase = Phase.intake;
  double phaseStart = 0;
  double phaseLen = phaseSeconds[Phase.intake]!;

  /// Seconds the build takes (set as soon as the raster is ready, i.e.
  /// usually during [Phase.intake]).
  double buildLen = 0;

  /// When the build starts (known once the raster is ready: the end of
  /// intake), or null before that.
  double? buildStart;

  /// Bricks standing when the build was cut short (a sample giving way).
  int? cutAt;

  double startedAt = 0;

  /// 0..1 through the current phase.
  double progress(double t) => phaseLen <= 0 ? 1 : ((t - phaseStart) / phaseLen).clamp(0.0, 1.0);

  /// Seconds since the current phase started.
  double since(double t) => t - phaseStart;

  int get total => raster?.bricks.length ?? 0;

  /// How many bricks are in the wall at [t] (in [NameRaster.bricks] order).
  int laid(double t) {
    if (cutAt case final c?) return c;
    switch (phase) {
      case Phase.intake:
        return 0;
      case Phase.build:
        return (total * progress(t)).floor();
      case Phase.reveal || Phase.celebrate || Phase.demolish || Phase.cleanup:
        return total;
    }
  }

  /// Seconds since the job started (for the "built in m:ss" stat).
  double age(double t) => t - startedAt;

  // ── The brick schedule (shared by the factory and the site) ──────────────

  /// When brick [n] (in [NameRaster.bricks] order) is set in the wall.
  /// Null until the raster and the build timing are known.
  double? brickTime(int n) {
    final s = buildStart;
    if (s == null || total == 0) return null;
    return s + buildLen * n / total;
  }

  int get pallets => (total + palletSize - 1) ~/ palletSize;

  /// When pallet [i] (bricks i·[palletSize]…) sits at [BL.pickup].
  double? palletAtPickup(int i) {
    final b = brickTime(i * palletSize);
    return b == null ? null : b - craneLead;
  }

  /// When pallet [i] leaves the factory onto the belt.
  double? palletLeavesFactory(int i) {
    final p = palletAtPickup(i);
    return p == null ? null : p - beltLead;
  }
}

/// A simulation that lives next to the model (e.g. falling bricks, the
/// crane), stepped with it so frames, fast-forward and capture agree.
abstract class BoothSystem {
  void update(BoothModel m, double dt);

  /// Called when [job] enters [phase] (at time `m.t`).
  void onPhase(BoothModel m, Job job, Phase phase) {}
}

/// Everything the booth scene shows. Advanced by [update]; layers read it
/// and repaint when it notifies.
class BoothModel extends ChangeNotifier {
  /// Scene time in seconds.
  double t = 0;

  /// Names waiting (not including [job]).
  final queue = <Job>[];

  /// The name being built now.
  Job? job;

  /// Names built so far (oldest first), samples excluded.
  final built = <String>[];

  /// Total names ever submitted (for "#12 today").
  int submitted = 0;

  /// How the next names are built (the current one keeps its mode).
  BuildMode mode = BuildMode.bricks;

  /// How long brick builds take (see [BuildPace]).
  BuildPace pace = const BuildPace();

  final systems = <BoothSystem>[];

  /// Called after a real name finishes (to persist history).
  void Function(BoothModel m)? onBuilt;

  int _serial = 0;
  int _sample = 0;
  Future<void>? _pending;

  /// A raster being prepared (capture waits on it).
  Future<void>? get pending => _pending;

  /// Rough wait in seconds for a name submitted now.
  double get estimatedWait {
    final j = job;
    final now = j == null || j.sample ? 0.0 : _remaining(j);
    return now + queue.length * (_overhead + pace.typical / _rush(queue.length));
  }

  /// Every phase but the build, at [pace].
  double get _overhead => phaseSeconds.keys.fold<double>(0, (a, p) => a + pace.phaseLen(p));

  double _remaining(Job j) {
    var s = j.phaseLen - j.since(t);
    var after = false;
    for (final p in Phase.values) {
      if (after) s += p == Phase.build ? j.buildLen : pace.phaseLen(p);
      if (p == j.phase) after = true;
    }
    return math.max(0, s);
  }

  /// The name built after the current one: the first in the queue, or the
  /// next sample when nobody is waiting. (What the next blueprint shows.)
  String get upcoming => queue.isNotEmpty ? queue.first.name : sampleNames[_sample % sampleNames.length];

  /// A queue speeds the crew up: build times are divided by this.
  static double _rush(int waiting) => 1 + 0.22 * math.min(waiting, 6);

  /// Submits a typed name. Returns the check result (and its queue position
  /// via [queue] when accepted).
  NameCheck submit(String raw) {
    final check = checkName(raw);
    if (check is! NameOk) return check;
    submitted++;
    queue.add(Job(check.name, serial: ++_serial, submittedAt: t));
    // A sample gives way: knock it down now.
    final j = job;
    if (j != null &&
        j.sample &&
        (j.phase == Phase.intake || j.phase == Phase.build || j.phase == Phase.reveal)) {
      j.cutAt = j.laid(t);
      j.cutFrac = j.buildProgress(t);
      _enter(j, Phase.demolish);
    } else if (j != null && j.sample && j.phase == Phase.celebrate) {
      _enter(j, Phase.demolish);
    }
    notifyListeners();
    return check;
  }

  /// Operator: drop the current name and go straight to demolition.
  void skip() {
    final j = job;
    if (j == null || j.phase == Phase.demolish || j.phase == Phase.cleanup) return;
    j.cutAt = j.laid(t);
    j.cutFrac = j.buildProgress(t);
    _enter(j, Phase.demolish);
    notifyListeners();
  }

  /// Operator: remove the most recently queued name.
  void dropLast() {
    if (queue.isNotEmpty) queue.removeLast();
    notifyListeners();
  }

  void update(double dt) {
    t += dt;
    _advance(job ?? _startNext());
    for (final s in systems) {
      s.update(this, dt);
    }
    notifyListeners();
  }

  Job _startNext() {
    var next = queue.isNotEmpty
        ? queue.removeAt(0)
        : Job(
            sampleNames[_sample++ % sampleNames.length],
            serial: ++_serial,
            submittedAt: t,
            sample: true,
          );
    if (next.mode != mode) {
      next = Job(
        next.name,
        serial: next.serial,
        submittedAt: next.submittedAt,
        sample: next.sample,
        mode: mode,
      );
    }
    final job = next;
    this.job = job;
    job.startedAt = t;
    _enter(job, Phase.intake);
    if (job.mode == BuildMode.craft) {
      final rush = _rush(queue.length);
      _pending = CraftPlan.of(job.name).then((p) {
        job.plan = p;
        job.buildLen = p.nominal / rush * (job.sample ? 0.7 : 1);
        if (job.phase == Phase.intake) {
          job.buildStart = math.max(t, job.phaseStart + job.phaseLen);
        }
        _pending = null;
      });
      return job;
    }
    _pending = NameRaster.of(next.name).then((r) {
      next.raster = r;
      next.buildLen = pace.nominal(r) / _rush(queue.length) * (next.sample ? pace.sample : 1);
      if (next.phase == Phase.intake) {
        next.buildStart = math.max(t, next.phaseStart + next.phaseLen);
      }
      _pending = null;
    });
    return next;
  }

  void _advance(Job j) {
    if (j.since(t) < j.phaseLen) return;
    switch (j.phase) {
      case Phase.intake:
        if (!j.ready) return; // still rasterizing / planning
        _enter(j, Phase.build);
      case Phase.build:
        _enter(j, Phase.reveal);
      case Phase.reveal:
        _enter(j, Phase.celebrate);
      case Phase.celebrate:
        if (!j.sample) {
          built.add(j.name);
          onBuilt?.call(this);
        }
        _enter(j, Phase.demolish);
      case Phase.demolish:
        _enter(j, Phase.cleanup);
      case Phase.cleanup:
        job = null;
        _startNext();
        return;
    }
  }

  void _enter(Job j, Phase p) {
    j.phase = p;
    j.phaseStart = t;
    j.phaseLen = p == Phase.build ? j.buildLen : pace.phaseLen(p);
    if (p == Phase.build) j.buildStart = t;
    // A sample cut short makes way quickly.
    if (j.cutAt case final c? when p == Phase.demolish || p == Phase.cleanup) {
      j.phaseLen = c == 0 ? 0 : (p == Phase.demolish ? 6 : 5);
    }
    for (final s in systems) {
      s.onPhase(this, j, p);
    }
  }
}
