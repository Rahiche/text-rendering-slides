import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:characters/characters.dart';

import '../../deck/scripts.dart';
import '../layout.dart';
import '../model.dart';
import '../raster.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Geometry. Everything stays inside BL.factory, plus the exit belt.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class FG {
  static const floor = BL.groundY;
  static const left = 24.0;
  static const right = 560.0;

  static const roofTop = 404.0;
  static const roofBot = 412.0;
  static const trussY = 421.0;
  static const wall = 7.0;

  /// The lesson screen, hung from the truss above the line.
  static const screen = Rect.fromLTRB(154, 425, 466, 501);

  /// Machine name plates (centre line).
  static const plateY = 515.0;

  /// The line inside the hall: belt surface, stations [pitch] apart.
  static const lineY = 624.0;
  static const lineL = 68.0;
  static const lineR = 398.0;
  static const pitch = 80.0;

  /// Station [s]: 0 text (hopper), 1 itemize, 2 fonts, 3 shape, 4 raster
  /// (inside the kiln).
  static double sx(num s) => 102 + pitch * s;

  static const machineX = [102.0, 182.0, 262.0, 342.0, 430.0];
  static const machineNames = ['text', 'itemize', 'fonts', 'shape', 'raster'];

  // Hopper (text).
  static const hopperBody = Rect.fromLTRB(72, 560, 132, 598);
  static const hopperPile = Rect.fromLTRB(84, 537, 120, 554);
  static const hopperReader = Rect.fromLTRB(80, 565, 124, 592);
  static const funnelTop = 531.0;

  // Kiln (raster). The belt runs into its left mouth; pallets leave its
  // right door onto the exit belt.
  static const kiln = Rect.fromLTRB(390, 529, 470, floor);
  static const kilnWin = Rect.fromLTRB(397, 545, 463, 591);
  static const flueX = 480.0;

  // Recycling: bucket elevator up the left wall, its bin on the floor.
  static const elevX = 45.0;
  static const elevTop = 526.0;
  static const elevBot = 686.0;
  static const elevR = 8.0;
  static const binTop = 670.0;

  // The right wall's door for the exit belt.
  static const doorTop = 648.0;

  static const crateH = 20.0;
  static const lessonH = 22.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// The exit belt: steady pace, plus a rush while a new name's first pallets
// hurry out (pallet 0 must be at the pickup 3 s after the name arrives).
// ─────────────────────────────────────────────────────────────────────────────

abstract final class FBelt {
  static const x0 = BL.beltStart;
  static final x1 = BL.pickup.dx;
  static final length = x1 - x0;

  /// Steady speed, px/s.
  static final v = length / beltLead;

  /// Speed factor during the rush.
  static const rush = 2.5;
  static const _in = 0.4, _hold = 3.2, _out = 0.8;

  /// 0..1: how much of the rush applies [tau] s after the name arrived.
  static double window(double tau) {
    if (tau <= 0 || tau >= _hold + _out) return 0;
    if (tau < _in) return tau / _in;
    if (tau <= _hold) return 1;
    return 1 - (tau - _hold) / _out;
  }

  /// ∫ window from 0 to [tau].
  static double _w(double tau) {
    if (tau <= 0) return 0;
    if (tau < _in) return tau * tau / (2 * _in);
    var e = _in / 2;
    if (tau <= _hold) return e + tau - _in;
    e += _hold - _in;
    final u = math.min(tau - _hold, _out);
    return e + u - u * u / (2 * _out);
  }

  /// Belt travel (px) [tau] s after the name arrived.
  static double travel(double tau) => v * (tau + (rush - 1) * _w(tau));

  /// The τ at which the belt has travelled [p] px.
  static double inverse(double p) {
    if (p <= 0) return p / v;
    var lo = p / (v * rush), hi = p / v;
    for (var i = 0; i < 40; i++) {
      final mid = (lo + hi) / 2;
      if (travel(mid) < p) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  }

  /// When pallet [i] of [j] rolls out of the kiln's door (its centre at
  /// [x0]); it reaches [x1] exactly at `j.palletAtPickup(i)`.
  static double depart(Job j, int i) {
    final t0 = j.startedAt;
    return t0 + inverse(travel(j.palletAtPickup(i)! - t0) - length);
  }

  /// Centre x of pallet [i] at [t] (only meaningful before it is picked up).
  static double x(Job j, int i, double t) {
    final t0 = j.startedAt;
    return x1 - (travel(j.palletAtPickup(i)! - t0) - travel(t - t0));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The factory's memory between frames (stepped with the model).
// ─────────────────────────────────────────────────────────────────────────────

class FactorySystem extends BoothSystem {
  /// Belt travel banked from earlier names (so the rollers never jump).
  double _bank = 0;
  Job? _beltJob;

  /// A name cut short (its crates and pallets fade where they are), and when.
  Job? cut;
  double cutAt = -1e9;

  /// The last cleanup: its rubble pours into the recycling bin during its
  /// last seconds, then rides the elevator up into the hopper.
  double cleanupEnd = -1e9;
  double cleanupLen = 0;
  int rubble = 0;

  /// Elevator travel banked from earlier loads.
  double _lift = 0;

  @override
  void update(BoothModel m, double dt) {}

  @override
  void onPhase(BoothModel m, Job job, Phase phase) {
    switch (phase) {
      case Phase.intake:
        final prev = _beltJob;
        if (prev != null) _bank += FBelt.travel(m.t - prev.startedAt);
        _beltJob = job;
      case Phase.demolish:
        if (job.cutAt != null) {
          cut = job;
          cutAt = m.t;
        }
      case Phase.cleanup:
        if (cleanupLen > 0) _lift += _recycleRun(m.t - (cleanupEnd - 4.4));
        cleanupLen = job.phaseLen;
        cleanupEnd = m.t + job.phaseLen;
        rubble = job.cutAt ?? job.total;
      case Phase.build || Phase.reveal || Phase.celebrate:
        break;
    }
  }

  /// Exit belt travel (px) at [t], for its rollers.
  double belt(double t) {
    final j = _beltJob;
    return j == null ? FBelt.v * t : _bank + FBelt.travel(t - j.startedAt);
  }

  /// ∫ of the elevator's recycling boost (rise 0.4 s, run, fall 0.6 s).
  static double _recycleRun(double tau) {
    if (tau <= 0) return 0;
    if (tau < 0.4) return tau * tau / 0.8;
    if (tau < 6.8) return 0.2 + tau - 0.4;
    final u = math.min(tau - 6.8, 0.6);
    return 6.6 + u - u * u / 1.2;
  }

  /// Bucket elevator travel (px): a slow crawl, fast while rubble comes back.
  double elevator(double t) =>
      16 * t + 34 * (_lift + (cleanupLen > 0 ? _recycleRun(t - (cleanupEnd - 4.4)) : 0));
}

// ─────────────────────────────────────────────────────────────────────────────
// The intake lesson: seconds after the name arrives (intake lasts 9 s).
// ─────────────────────────────────────────────────────────────────────────────

abstract final class FL {
  /// The capsule shoots down the tube; the ticket lands in the hopper.
  static const landed = 0.7;

  /// Code points are read one by one until then.
  static const readEnd = 3.4;

  /// The crate drops through the hopper's gate onto the line.
  static const dropEnd = 3.8;

  /// Station to station.
  static const mv = 0.45;

  /// When the crate leaves stations 0..3.
  static const leave = [3.8, 5.3, 6.8, 7.95];

  /// When it reaches station [s] (1..4; 4 = into the kiln).
  static double arrive(int s) => s == 0 ? dropEnd : leave[s - 1] + mv;

  static const end = 9.0;

  /// The machine the lesson is about (0..4), or -1 before the ticket lands.
  /// It moves on halfway through the crate's ride to the next machine.
  static int step(double s) {
    if (s < landed) return -1;
    for (var k = 0; k < 4; k++) {
      if (s < leave[k] + mv / 2) return k;
    }
    return 4;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Production during the build: one crate per pallet (or every k-th when
// pallets come fast), indexing station to station so that crate m slides
// into the kiln [bake] s before its pallet rolls out.
// ─────────────────────────────────────────────────────────────────────────────

class CrateRun {
  CrateRun._(this.job, this.departs, this.dc, this.k, this.mv, this.bake, this.first);

  final Job job;

  /// When each pallet leaves the kiln ([FBelt.depart]).
  final Float64List departs;

  /// Seconds between crates (one index step).
  final double dc;

  /// A crate for every k-th pallet.
  final int k;

  /// Move time between stations.
  final double mv;

  /// Seconds between a crate entering the kiln and its pallet leaving.
  final double bake;

  /// The pallet the first crate goes with.
  final int first;

  static CrateRun? of(Job j, Float64List? departs) {
    if (departs == null || j.total == 0 || j.buildLen <= 0) return null;
    final delta = j.buildLen * palletSize / j.total;
    final k = math.max(1, (1.4 / delta).ceil());
    final dc = k * delta;
    final mv = (0.3 * dc).clamp(0.3, 0.6);
    final bake = (0.45 * dc).clamp(0.5, 1.4);
    // The first crate drops once the lesson's crate has left the line.
    final earliest = j.startedAt + FL.end + 0.4;
    var i = 0;
    while (i < departs.length && departs[i] - bake - 4 * dc - mv < earliest) {
      i++;
    }
    if (i >= departs.length) return null;
    return CrateRun._(j, departs, dc, k, mv, bake, i);
  }

  int get count => (departs.length - first + k - 1) ~/ k;

  int pallet(int m) => first + m * k;

  /// When crate [m] slides into the kiln.
  double kilnAt(int m) => departs[pallet(m)] - bake;

  /// When crate [m] arrives at station [s] (0 = drops out of the hopper).
  double at(int m, int s) => kilnAt(m) - (4 - s) * dc;
}

// ─────────────────────────────────────────────────────────────────────────────
// What the factory knows about one name.
// ─────────────────────────────────────────────────────────────────────────────

class CodePoint {
  CodePoint(this.cp, this.start, this.end);

  final int cp;

  /// UTF-16 offsets in the name.
  final int start, end;

  static final _mark = RegExp(r'\p{M}', unicode: true);

  String get hex => 'U+${cp.toRadixString(16).toUpperCase().padLeft(4, '0')}';

  /// How the screen shows the character itself.
  String get shown {
    if (cp == 0x20) return '␣';
    final s = String.fromCharCode(cp);
    return _mark.hasMatch(s) ? '◌$s' : s;
  }
}

class Grapheme {
  Grapheme(this.text, this.start, this.end, this.script);

  final String text;
  final int start, end;
  final Script script;

  bool get space => text.trim().isEmpty;
}

/// One font the name needs, and the runs it serves.
class FontUse {
  FontUse(this.font, this.script);

  final String font;

  /// The first run's script (for the colour).
  final Script script;
}

/// The font the engine ends up using for [s] in the booth's name style.
String fontOf(Script s) => switch (s) {
  Script.latin || Script.greek => 'Space Grotesk',
  Script.han || Script.kana => 'Hiragino · system',
  Script.arabic => 'Noto Kufi Arabic',
  Script.hangul => 'Apple SD Gothic · system',
  _ => 'system fallback',
};

/// The fonts machine's cartridge for [s]: 0 Aa, 1 あ, 2 字, 3 other.
int fontCell(Script s) => switch (s) {
  Script.latin || Script.greek => 0,
  Script.kana => 1,
  Script.han => 2,
  _ => 3,
};

class JobData {
  JobData(this.job) {
    final name = job.name;
    var off = 0;
    for (final r in name.runes) {
      final len = r > 0xFFFF ? 2 : 1;
      cps.add(CodePoint(r, off, off + len));
      off += len;
    }
    runs = itemize(name);
    var o = 0;
    for (final g in name.characters) {
      var sc = Script.common;
      for (final r in runs) {
        if (o >= r.start && o < r.end) sc = r.script;
      }
      graphemes.add(Grapheme(g, o, o + g.length, sc));
      o += g.length;
    }
    crateGlyphs = [for (final g in graphemes) if (!g.space) g];
    if (crateGlyphs.isEmpty) crateGlyphs = graphemes;
    for (final r in runs) {
      final f = fontOf(r.script);
      if (fonts.isEmpty || fonts.last.font != f) fonts.add(FontUse(f, r.script));
    }
  }

  final Job job;
  final cps = <CodePoint>[];
  late final List<ScriptRun> runs;
  final graphemes = <Grapheme>[];

  /// What production crates carry, in turn (no spaces).
  late final List<Grapheme> crateGlyphs;
  final fonts = <FontUse>[];

  String get name => job.name;

  /// Which grapheme code point [k] belongs to.
  int graphemeOfCp(int k) {
    final at = cps[k].start;
    for (var i = 0; i < graphemes.length; i++) {
      if (at >= graphemes[i].start && at < graphemes[i].end) return i;
    }
    return graphemes.length - 1;
  }

  // ── Derived once the raster is ready ─────────────────────────────────────

  RasterDots? _dots;
  RasterDots? get dots {
    final r = job.raster;
    if (r == null) return null;
    return _dots ??= RasterDots(r);
  }

  CrateRun? _crates;
  (double?, double, int)? _cratesKey;

  CrateRun? get crates {
    final key = (job.buildStart, job.buildLen, job.total);
    if (key != _cratesKey) {
      _cratesKey = key;
      _crates = CrateRun.of(job, departs);
    }
    return _crates;
  }

  Float64List? _departs;
  (double?, double, int)? _departsKey;

  /// When each pallet leaves the kiln (see [FBelt.depart]), or null before
  /// the schedule is known.
  Float64List? get departs {
    if (job.buildStart == null || job.total == 0) return null;
    final key = (job.buildStart, job.buildLen, job.total);
    if (key != _departsKey) {
      _departsKey = key;
      _departs = Float64List.fromList([for (var i = 0; i < job.pallets; i++) FBelt.depart(job, i)]);
    }
    return _departs;
  }

  /// Graphemes' boxes in a laid-out painter of the name (cached per size).
  final boxes = <double, List<Rect>>{};
}

/// The name's raster as dots, bucketed by coverage, in build order, for
/// drawing thousands of pixels with a handful of draw calls.
class RasterDots {
  RasterDots(NameRaster r) : cols = r.cols, rows = r.rows {
    final xs = List.generate(levels, (_) => <double>[]);
    final os = List.generate(levels, (_) => <int>[]);
    for (var n = 0; n < r.bricks.length; n++) {
      final b = r.bricks[n];
      final l = level(b.cover);
      xs[l]
        ..add(b.col + 0.5)
        ..add(b.row + 0.5);
      os[l].add(n);
    }
    xy = [for (final x in xs) Float32List.fromList(x)];
    order = [for (final o in os) Int32List.fromList(o)];
  }

  static const levels = 4;

  static int level(double cover) => ((cover - 0.12) / 0.88 * levels).floor().clamp(0, levels - 1);

  /// Coverage a level stands for.
  static double coverOf(int l) => 0.12 + 0.88 * (l + 0.75) / levels;

  final int cols, rows;
  late final List<Float32List> xy;
  late final List<Int32List> order;

  /// How many of level [l]'s dots come before brick [n] in build order.
  int before(int l, int n) {
    final o = order[l];
    var lo = 0, hi = o.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (o[mid] < n) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}
