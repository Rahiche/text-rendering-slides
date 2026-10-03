import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/model.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'crew.dart';
import 'crew_breaks.dart' show OffDuty;
import 'kit.dart';
import 'motion.dart';
import 'prop_pool.dart';
import 'shot.dart';
import 'site_fx.dart';
import 'site_plan.dart';
import 'walk.dart';

/// A stretch of the wall one pair finishes in one go: a letter, or a strip
/// of a wide one (its brick columns [col0]…[col1]) when there are too few
/// letters to go round.
class FinishUnit {
  FinishUnit(this.letter, this.strip, this.col0, this.col1);

  /// The plan's letter, and which of its strips (left to right).
  final int letter, strip, col0, col1;

  /// Its bricks' extent (world): x from [x0] to [x1], y from [y0] to [y1];
  /// their rows (from the bottom) [row0]…[row1], and per row the ink's
  /// left and right (world x), where the tools work.
  double x0 = 0, x1 = 0, y0 = 0, y1 = 0;
  int row0 = 0, row1 = -1;
  Float64List left = Float64List(0), right = Float64List(0);

  /// No bricks in it (a strip of a letter with a gap): it takes its times
  /// from its neighbour in the letter.
  bool empty = true;

  /// The pair that does it, and when (seconds into the reveal) the plaster
  /// and the paint start down from its top.
  int pair = -1;
  double plaster = 0, paint = 0;

  double get width => x1 - x0;
  double get cx => (x0 + x1) / 2;

  /// The fronts run from a little above its top to a little below its foot.
  double get top => y1 + 0.05;
  double get run => y1 - y0 + 0.1;

  /// The time of a swing of the tools from edge to edge and back.
  double get period => (1.1 * width).clamp(1.2, 2.6);
}

/// One stretch of a finisher's time: a walk, or work at a unit.
class _Leg {
  _Leg.walk(Walk this.walk) : unit = null, from = walk.start, to = walk.end;
  _Leg.work(FinishUnit this.unit, this.from, this.to) : walk = null;
  final Walk? walk;
  final FinishUnit? unit;
  final double from, to;
}

/// 仕上げ · The finish, planned: the crew turn the pixel wall into the name
/// the way a real one is finished. Three pairs — a plasterer and a painter
/// each (builders 0–1, 2–3, 4–5) — come round the ends of the wall with
/// their tools and take the letters between them, left, middle and right,
/// each working its share from the end it came round. On every letter the
/// plasterer goes first, top-down, smoothing the stair-stepped edges with a
/// long-handled float (and, low down, a hawk and trowel): the jaggies fill
/// in (real-world anti-aliasing). The painter follows a little above with
/// a roller on an extension pole in the letter's colour. Then they walk
/// round to the front right to watch the celebration, and the foreman, who
/// has been checking each letter as it's done, goes back to his corner.
///
/// Times are seconds into the reveal. The work goes at the pace that fits
/// the reveal (the slowest pair finishing a couple of seconds early): the
/// split of the letters and which pair takes which share are the ones that
/// let them work slowest (the pair from the middle of the platform has
/// furthest to walk). A name of one or two letters is cut into strips, so
/// every pair has work. A pure function of the build plan.
class FinishPlan {
  FinishPlan(this.plan, {required this.len, required List<vm.Vector3> watch, required this.corner}) : b = plan.b, w = plan.width {
    final clock = Stopwatch()..start();
    per = math.max(1, (plan.r.rows / 12).ceil());
    _makeUnits();
    _measure();
    _schedule(watch);
    _hide();
    _tracks(watch);
    _ms = clock.elapsedMicroseconds / 1000;
  }

  /// How long the planning took (for the capture log).
  double _ms = 0;

  final BuildPlan plan;

  /// The reveal's length.
  final double len;

  /// The foreman's place beside the wall.
  final vm.Vector3 corner;
  final double b, w;

  /// Brick rows per band of the smooth letters (as the site cuts them).
  late final int per;

  /// The work fronts' speed (metres a second, down the wall). (Tried out
  /// while planning; fixed after.)
  double v = 1;

  final units = <FinishUnit>[];

  /// Letter k's units are [first] k … [first] k + 1.
  final first = <int>[];

  /// Per brick (laying order): its unit, and when the plaster passes it
  /// (its band goes smooth over it: it's gone).
  late final Int16List unitOf;
  late final Float64List hideAt;

  /// The paint trails the plaster by this much (metres).
  static const lag = 0.85;

  /// Loading the float or the roller at each unit (seconds).
  static const load = 0.45;

  /// Where they stand: the plasterer (with the pole, and up close by hand),
  /// the painter (further back, the pole longer), and the lane behind them
  /// they walk off along.
  static const zPole = -1.15, zHand = -0.62, zPaint = -1.95, zLane = -3.4;

  /// Below this, the plasterer puts the pole down and uses hawk and trowel.
  static const lowHand = 1.3;

  /// Walking: round to the work, from one letter to the next, off.
  static const jog = 4.0, step = 2.4, off = 3.8;

  /// The widest unit a pair takes on, and the narrowest strip.
  static const _maxWidth = 4.6, _minStrip = 1.4;

  /// The painting is done this long before the reveal ends, and the walk
  /// off may run this far into the celebration.
  static const _spare = 2.0, overrun = 3.6;

  // ── Units ─────────────────────────────────────────────────────────────────

  void _makeUnits() {
    final ls = plan.letters.letters, nl = ls.length;
    double widthOf(int k) => (ls[k].col1 + 1 - ls[k].col0) * b;
    final strips = [for (var k = 0; k < nl; k++) math.max(1, (widthOf(k) / _maxWidth).ceil())];
    // Three pairs: a name of one or two letters is shared out in strips.
    while (strips.fold<int>(0, (a, s) => a + s) < 3) {
      var best = -1;
      var most = _minStrip;
      for (var k = 0; k < nl; k++) {
        final sw = widthOf(k) / strips[k];
        if (sw > most) {
          most = sw;
          best = k;
        }
      }
      if (best < 0) break;
      strips[best]++;
    }
    for (var k = 0; k < nl; k++) {
      final l = ls[k], cols = l.col1 + 1 - l.col0;
      first.add(units.length);
      for (var s = 0; s < strips[k]; s++) {
        final c0 = l.col0 + (cols * s / strips[k]).round(), c1 = l.col0 + (cols * (s + 1) / strips[k]).round() - 1;
        units.add(FinishUnit(k, s, c0, c1));
      }
    }
    first.add(units.length);
  }

  /// The units' extents and their ink's edges row by row, from their
  /// bricks.
  void _measure() {
    final r = plan.r, n = plan.total;
    unitOf = Int16List(n);
    for (var i = 0; i < n; i++) {
      final bk = r.bricks[plan.src[i]];
      final k = plan.letter[i];
      var u = first[k];
      while (u + 1 < first[k + 1] && bk.col > units[u].col1) {
        u++;
      }
      unitOf[i] = u;
      final unit = units[u], row = r.rows - 1 - bk.row;
      if (unit.empty) {
        unit
          ..empty = false
          ..row0 = row
          ..row1 = row
          ..x0 = double.infinity
          ..x1 = -double.infinity;
      }
      unit
        ..row0 = math.min(unit.row0, row)
        ..row1 = math.max(unit.row1, row)
        ..x0 = math.min(unit.x0, (bk.col - r.cols / 2) * b)
        ..x1 = math.max(unit.x1, (bk.col + 1 - r.cols / 2) * b);
    }
    for (final u in units) {
      if (u.empty) continue;
      u
        ..y0 = u.row0 * b
        ..y1 = (u.row1 + 1) * b
        ..left = (Float64List(u.row1 - u.row0 + 1)..fillRange(0, u.row1 - u.row0 + 1, double.infinity))
        ..right = (Float64List(u.row1 - u.row0 + 1)..fillRange(0, u.row1 - u.row0 + 1, -double.infinity));
    }
    for (var i = 0; i < n; i++) {
      final bk = r.bricks[plan.src[i]], u = units[unitOf[i]], row = r.rows - 1 - bk.row - u.row0;
      u.left[row] = math.min(u.left[row], (bk.col - r.cols / 2) * b);
      u.right[row] = math.max(u.right[row], (bk.col + 1 - r.cols / 2) * b);
    }
    // Rows without ink (a gap in the letter) take the nearest row's.
    for (final u in units) {
      for (var q = 0; q < u.left.length; q++) {
        if (u.left[q].isFinite) continue;
        for (var d = 1; d < u.left.length; d++) {
          final m = [q - d, q + d].where((s) => s >= 0 && s < u.left.length && u.left[s].isFinite).firstOrNull;
          if (m == null) continue;
          u.left[q] = u.left[m];
          u.right[q] = u.right[m];
          break;
        }
      }
    }
    // An empty strip borrows its neighbour's rows (and, later, times).
    for (var u = 0; u < units.length; u++) {
      final unit = units[u];
      if (!unit.empty) continue;
      final k = unit.letter;
      final m = [for (var q = first[k]; q < first[k + 1]; q++) q].where((q) => !units[q].empty).firstOrNull;
      if (m == null) continue;
      final o = units[m];
      unit
        ..x0 = (unit.col0 - r.cols / 2) * b
        ..x1 = (unit.col1 + 1 - r.cols / 2) * b
        ..y0 = o.y0
        ..y1 = o.y1
        ..row0 = o.row0
        ..row1 = o.row1
        ..left = (Float64List(o.left.length)..fillRange(0, o.left.length, unit.x0))
        ..right = (Float64List(o.right.length)..fillRange(0, o.right.length, unit.x1));
    }
  }

  // ── The tools' and the bodies' paths ──────────────────────────────────────

  final _span = [0.0, 0.0];

  /// The ink's middle and half its width on [u] at height [y].
  List<double> _spanAt(FinishUnit u, double y) {
    if (u.left.isEmpty) {
      _span
        ..[0] = u.cx
        ..[1] = u.width / 2;
      return _span;
    }
    final f = (y / b - 0.5).clamp(u.row0.toDouble(), u.row1.toDouble()) - u.row0;
    final q0 = f.floor(), q1 = math.min(q0 + 1, u.left.length - 1), k = f - q0;
    final l = lerp(u.left[q0], u.left[q1], k), r = lerp(u.right[q0], u.right[q1], k);
    _span
      ..[0] = (l + r) / 2
      ..[1] = math.max(0.06, (r - l) / 2 - 0.05);
    return _span;
  }

  /// Where the plasterer's float (else the painter's roller) is across [u]
  /// [tau] seconds into their run down it: edge to edge and back, at the
  /// ink's edges where the work front is.
  double toolX(FinishUnit u, double tau, {required bool plasterer}) {
    final s = _spanAt(u, u.top - v * tau - (plasterer ? 0 : -0.12));
    return s[0] + s[1] * math.sin(2 * math.pi * tau / u.period + (plasterer ? 0 : math.pi));
  }

  /// Where they stand to reach it: following, a little behind.
  double bodyX(FinishUnit u, double tau, {required bool plasterer}) {
    final s = _spanAt(u, u.top - v * tau);
    return s[0] + 0.55 * s[1] * math.sin(2 * math.pi * tau / u.period + (plasterer ? 0 : math.pi) - 0.45);
  }

  /// The plaster (else the paint) front's height on [u] at [t].
  double frontAt(FinishUnit u, double t, {required bool plaster}) => u.top - v * (t - (plaster ? u.plaster : u.paint));

  // ── Who does what, when ───────────────────────────────────────────────────

  /// Pair p's units in the order they do them, which end of the wall they
  /// come round (−1 left, +1 right), and whether past another pair.
  final _order = List.generate(3, (_) => <FinishUnit>[]);
  final _entry = [-1.0, -1.0, 1.0];
  final _behind = [false, true, false];

  /// The way off the platform (through the builder's gate, along behind
  /// it) round the end [e] of the wall to (x, z), past the others if
  /// [behind].
  List<vm.Vector3> _round(int who, double e, double x, double z, {bool behind = false}) {
    final off = Crew3D.offPlatform(plan.restX(who), w, e), front = off.last;
    return [
      ...off,
      if (behind) ...[vm.Vector3(front.x, 0, -2.7), vm.Vector3(x, 0, -2.7)],
      vm.Vector3(x, 0, z),
    ];
  }

  /// When builder [z] sets off.
  static double _setOff(int z) => 0.2 + 0.06 * z;

  /// The way off from (x, z) to [watch]: back to the lane (the painter, at
  /// the front, a step further: the pair walk side by side, not into each
  /// other), along it past the wall's right end, then up to the place.
  List<vm.Vector3> _off(double x, double z, vm.Vector3 watch) {
    final lane = zLane - (z < zPole - 0.4 ? 0.6 : 0.0);
    return [
      vm.Vector3(x, 0, z),
      vm.Vector3(x, 0, lane),
      vm.Vector3(watch.x, 0, lane),
      watch,
    ];
  }

  /// How long [_round] and [_off] are (without making them: the planning
  /// tries a great many).
  double _roundLength(int who, double e, double x, double z, bool behind) {
    final rx = plan.restX(who), fx = e * Crew3D.endX(w);
    final l = (Crew3D.behindZ - SiteLayout.crewZ) + (fx - rx).abs() + (Crew3D.behindZ + 0.6);
    return l + (behind ? 2.1 + (x - fx).abs() + (z + 2.7).abs() : _dist(fx, -0.6, x, z));
  }

  double _offLength(double x, double z, vm.Vector3 watch) {
    final lane = zLane - (z < zPole - 0.4 ? 0.6 : 0.0);
    return (z - lane).abs() + (watch.x - x).abs() + (watch.z - lane).abs();
  }

  static double _dist(double ax, double az, double bx, double bz) => math.sqrt((bx - ax) * (bx - ax) + (bz - az) * (bz - az));

  final _plasterAt = <double>[];

  /// Runs pair [p] through [order] (coming round end [e], past the others
  /// if [behind]) at pace [v0], writing the units' times when [write];
  /// returns how late the pair is for its deadlines (≤ 0: in time).
  double _run(int p, List<FinishUnit> order, double e, bool behind, double v0, List<vm.Vector3> watch, {bool write = false}) {
    if (order.isEmpty) return -1;
    v = v0;
    final pz = 2 * p, cz = 2 * p + 1;
    // The plasterer.
    final u0 = order.first;
    var tp = _setOff(pz) + _roundLength(pz, e, bodyX(u0, 0, plasterer: true), zPole, behind) / jog;
    final plasterAt = _plasterAt..clear();
    for (var i = 0; i < order.length; i++) {
      final u = order[i];
      if (i > 0) {
        final prev = order[i - 1];
        tp += (bodyX(u, 0, plasterer: true) - bodyX(prev, prev.run / v0, plasterer: true)).abs() / step + 0.1;
      }
      plasterAt.add(tp + load);
      tp = plasterAt.last + u.run / v0;
    }
    // The painter, a little above.
    var tc = _setOff(cz) + _roundLength(cz, e, bodyX(u0, 0, plasterer: false), zPaint, behind) / jog;
    for (var i = 0; i < order.length; i++) {
      final u = order[i];
      if (i > 0) {
        final prev = order[i - 1];
        tc += (bodyX(u, 0, plasterer: false) - bodyX(prev, prev.run / v0, plasterer: false)).abs() / step + 0.1;
      }
      final paint = math.max(tc + load, plasterAt[i] + lag / v0);
      if (write) {
        u
          ..pair = p
          ..plaster = plasterAt[i]
          ..paint = paint;
      }
      tc = paint + u.run / v0;
    }
    final last = order.last;
    final offC = _offLength(bodyX(last, last.run / v0, plasterer: false), zPaint, watch[cz]) / off;
    final offP = _offLength(bodyX(last, last.run / v0, plasterer: true), zPole, watch[pz]) / off;
    return math.max(tc - (len - _spare), tc + 0.2 + math.max(offC, offP) - (len + overrun));
  }

  /// Which pair takes the left, middle and right shares.
  static const _perms = [
    [0, 1, 2],
    [0, 2, 1],
    [1, 0, 2],
    [1, 2, 0],
    [2, 0, 1],
    [2, 1, 0],
  ];

  /// The end of the wall share [g] of [runs] is reached from: the left and
  /// right shares from their ends, the middle one from the nearer.
  static double _entryOf(int g, List<List<FinishUnit>> runs) {
    if (g != 1) return g == 0 ? -1 : 1;
    final run = runs[1];
    return run.isEmpty || (run.first.x0 + run.last.x1) / 2 < 0 ? -1 : 1;
  }

  static List<FinishUnit> _orderOf(List<FinishUnit> run, double e) => e < 0 ? run : run.reversed.toList();

  /// The slowest pace (metres a second) at which the pairs [perm] doing
  /// [runs] make their deadlines.
  double _paceFor(List<List<FinishUnit>> runs, List<int> perm, List<vm.Vector3> watch) {
    final orders = [for (var g = 0; g < 3; g++) _orderOf(runs[g], _entryOf(g, runs))];
    final entries = [for (var g = 0; g < 3; g++) _entryOf(g, runs)];
    bool fits(double v) {
      for (var g = 0; g < 3; g++) {
        if (_run(perm[g], orders[g], entries[g], g == 1, v, watch) > 0) return false;
      }
      return true;
    }

    var lo = 0.2, hi = 12.0;
    if (!fits(hi)) return hi;
    for (var k = 0; k < 22; k++) {
      final mid = (lo + hi) / 2;
      if (fits(mid)) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return hi;
  }

  void _schedule(List<vm.Vector3> watch) {
    final work = [
      for (final u in units)
        if (!u.empty) u,
    ];
    final n = work.length;
    // Every split of the units (left to right) into three shares, and every
    // way of handing them to the pairs: keep the one that lets them work
    // slowest.
    var best = (0, 0, 0);
    var bestV = double.infinity;
    for (var a = 0; a <= n; a++) {
      for (var c = a; c <= n; c++) {
        final runs = [work.sublist(0, a), work.sublist(a, c), work.sublist(c)];
        for (var q = 0; q < _perms.length; q++) {
          final pace = _paceFor(runs, _perms[q], watch);
          // (Ties: the most even split.)
          if (pace < bestV - 1e-6 || (pace < bestV + 1e-6 && _spread(a, c, n) < _spread(best.$1, best.$2, n))) {
            bestV = pace;
            best = (a, c, q);
          }
        }
      }
    }
    final pace = math.max(bestV, 0.55);
    final runs = [work.sublist(0, best.$1), work.sublist(best.$1, best.$2), work.sublist(best.$2)];
    for (var g = 0; g < 3; g++) {
      final p = _perms[best.$3][g], e = _entryOf(g, runs);
      _entry[p] = e;
      _behind[p] = g == 1;
      _order[p]
        ..clear()
        ..addAll(_orderOf(runs[g], e));
      _run(p, _order[p], e, g == 1, pace, watch, write: true);
    }
    v = pace;
    // Empty strips go with their neighbours.
    for (final unit in units) {
      if (!unit.empty) continue;
      final k = unit.letter;
      for (var q = first[k]; q < first[k + 1]; q++) {
        if (units[q].empty) continue;
        unit
          ..pair = units[q].pair
          ..plaster = units[q].plaster
          ..paint = units[q].paint;
        break;
      }
    }
  }

  static int _spread(int a, int c, int n) {
    final s = [a, c - a, n - c];
    return s.reduce(math.max) - s.reduce(math.min);
  }

  // ── Bands, bricks, letters ────────────────────────────────────────────────

  /// The top and the foot of global band [g] (rows from the bottom, [per]
  /// a band) within [u].
  double _bandTop(FinishUnit u, int g) => math.min((g + 1) * per * b, u.y1);
  double _bandFoot(FinishUnit u, int g) => math.max(g * per * b, u.y0);

  /// When the plaster reaches the top of band [g] of unit [u] (its piece of
  /// smooth letter goes on).
  double plasterAt(int u, int g) {
    final unit = units[u];
    return unit.plaster + (unit.top - math.min(_bandTop(unit, g), unit.top)) / v;
  }

  /// Likewise the paint.
  double paintAt(int u, int g) {
    final unit = units[u];
    return unit.paint + (unit.top - math.min(_bandTop(unit, g), unit.top)) / v;
  }

  /// How long the fronts take to cross band [g] of unit [u].
  double bandTime(int u, int g) => math.max(0.08, (_bandTop(units[u], g) - _bandFoot(units[u], g)) / v);

  /// Letter [k]'s units' last paint, and the plaster at their feet.
  double doneAt(int k) => [for (var u = first[k]; u < first[k + 1]; u++) units[u].paint + units[u].run / v].reduce(math.max);
  double footAt(int k) => [for (var u = first[k]; u < first[k + 1]; u++) units[u].plaster + units[u].run / v].reduce(math.max);

  /// The last of the painting.
  late final double end = [for (var k = 0; k < plan.letterCount; k++) doneAt(k)].fold(0.0, math.max);

  /// The world x where letter [k] is cut into strips (none: whole).
  List<double> stripCuts(int k) => [for (var u = first[k] + 1; u < first[k + 1]; u++) (units[u].col0 - plan.r.cols / 2) * b];

  /// Letter [k]'s unit for strip [s].
  int unitFor(int k, int s) => first[k] + s.clamp(0, first[k + 1] - first[k] - 1);

  /// The bricks go as the plaster passes them: a band at a time, in the
  /// direction the float is going.
  void _hide() {
    final r = plan.r, n = plan.total;
    hideAt = Float64List(n);
    for (var i = 0; i < n; i++) {
      final bk = r.bricks[plan.src[i]];
      final u = unitOf[i], unit = units[u], row = r.rows - 1 - bk.row;
      final g = row ~/ per;
      final start = plasterAt(u, g), dur = bandTime(u, g);
      final tau = start + dur / 2 - unit.plaster;
      final right = math.cos(2 * math.pi * tau / unit.period) >= 0;
      final q = (row - unit.row0).clamp(0, math.max(0, unit.left.length - 1)).toInt();
      final l = unit.left.isEmpty ? unit.x0 : unit.left[q], rt = unit.right.isEmpty ? unit.x1 : unit.right[q];
      final fx = rt - l <= 1e-6 ? 0.5 : c01((plan.cellX[i] - l) / (rt - l));
      hideAt[i] = start + dur * (0.08 + 0.8 * (right ? fx : 1 - fx));
    }
  }

  // ── The crew's tracks ─────────────────────────────────────────────────────

  final _legs = List.generate(Crew3D.builders, (_) => <_Leg>[]);
  late final Walk _foremanIn, _foremanOut;

  /// When builders and the foreman are back where the celebration has them
  /// (seconds into the reveal; may be after it).
  final arrive = List.filled(Crew3D.builders + 1, 0.0);

  void _tracks(List<vm.Vector3> watch) {
    for (var p = 0; p < 3; p++) {
      final order = _order[p], e = _entry[p];
      for (final plasterer in const [true, false]) {
        final z = 2 * p + (plasterer ? 0 : 1), legs = _legs[z];
        final zr = plasterer ? zPole : zPaint;
        if (order.isEmpty) {
          // Nothing for them: round to their place to watch.
          final walk = Walk(_round(z, 1, watch[z].x, watch[z].z), _setOff(z), jog, face: math.atan2(watch[z].x, watch[z].z));
          legs.add(_Leg.walk(walk));
          arrive[z] = walk.end;
          continue;
        }
        double endOf(FinishUnit u) => (plasterer ? u.plaster : u.paint) + u.run / v;
        final u0 = order.first;
        legs.add(
          _Leg.walk(
            Walk(
              _round(z, e, bodyX(u0, 0, plasterer: plasterer), zr, behind: _behind[p]),
              _setOff(z),
              jog,
              face: math.pi,
            ),
          ),
        );
        for (var i = 0; i < order.length; i++) {
          final u = order[i];
          if (i > 0) {
            final prev = order[i - 1];
            final a = bodyX(prev, prev.run / v, plasterer: plasterer), c = bodyX(u, 0, plasterer: plasterer);
            legs.add(_Leg.walk(Walk([vm.Vector3(a, 0, zr), vm.Vector3(c, 0, zr)], endOf(prev), step, face: math.pi)));
          }
          legs.add(_Leg.work(u, legs.last.to, i + 1 < order.length ? endOf(u) : double.infinity));
        }
      }
      if (order.isEmpty) continue;
      // Off together once the painter's done.
      final last = order.last, leave = last.paint + last.run / v + 0.2;
      for (final z in [2 * p, 2 * p + 1]) {
        final plasterer = z.isEven;
        final x = bodyX(last, last.run / v, plasterer: plasterer);
        final work = _legs[z].removeLast();
        _legs[z].add(_Leg.work(work.unit!, work.from, leave));
        final walk = Walk(_off(x, plasterer ? zPole : zPaint, watch[z]), leave, off, face: math.atan2(watch[z].x, watch[z].z));
        _legs[z].add(_Leg.walk(walk));
        arrive[z] = walk.end;
      }
    }
    // The foreman: out to look on from the middle, back to his corner.
    final look = vm.Vector3(0, 0, -4.4), via = vm.Vector3(corner.x, 0, -3.0);
    _foremanIn = Walk([corner, via, look], 0.8, 2.0, face: math.pi);
    final back = [look, via, corner];
    _foremanOut = Walk(back, len - 0.15 - Walk.lengthOf(back) / 2.6, 2.6, face: math.atan2(-(0 - corner.x), -(0.4 - corner.z)) * 0.8);
    arrive[Crew3D.builders] = _foremanOut.end;
  }

  _Leg? _legAt(int z, double t) {
    final legs = _legs[z];
    if (legs.isEmpty) return null;
    for (final l in legs) {
      if (t < l.to) return l;
    }
    return legs.last;
  }

  /// The timeline in words, for the capture log.
  String describe() {
    String f(double x) => x.toStringAsFixed(1);
    final out = StringBuffer(
      'finish ${plan.job.name}: ${units.length} units, pace ${v.toStringAsFixed(2)} m/s, painted by ${f(end)} of ${f(len)} s (planned in ${_ms.toStringAsFixed(1)} ms)\n',
    );
    for (var p = 0; p < 3; p++) {
      out.write('  pair $p (from the ${_entry[p] < 0 ? 'left' : 'right'}${_behind[p] ? ', behind' : ''}):');
      for (final u in _order[p]) {
        final strips = first[u.letter + 1] - first[u.letter];
        out.write(' ${plan.letters.letters[u.letter].text}${strips > 1 ? '/${u.strip}' : ''}');
        out.write(' ${f(u.plaster)}–${f(u.plaster + u.run / v)}|${f(u.paint)}–${f(u.paint + u.run / v)}');
      }
      out.writeln(' · off ${f(arrive[2 * p])}/${f(arrive[2 * p + 1])}');
    }
    return out.toString();
  }
}

/// The finish on screen: the crew posed through it (the crew's stage hook),
/// their tools — floats and rollers on poles, hawks and trowels, plaster
/// buckets and paint trays — the plaster dust and the paint drips, and the
/// camera's close-ups. The letters and the bricks are the site's (it asks
/// the plan when each band is plastered and painted).
class Finish3D {
  Finish3D(this.scene, this.crew, this.fx);

  final Scene scene;
  final Crew3D crew;
  final Fx3D fx;

  /// The tools: a few boxes and cylinders a frame, two draws.
  late final tools = PropPool(scene, 'finish tools', home: vm.Vector3(0, 0.5, -1.5), maxBoxes: 40, maxCyls: 40, maxGlows: 1);

  void init() => tools.init();

  FinishPlan? _plan;
  Job? _job;
  double _u = 0;
  bool _on = false;

  /// The letters' paint (linear), by the plan's letter.
  List<vm.Vector4> paint = const [];

  /// Plans [plan]'s finish (when its plan is ready): [len] the reveal's
  /// length, [watch] the builders' places to watch from, [corner] the
  /// foreman's, [paint] the letters' colours.
  FinishPlan planFor(BuildPlan plan, {required double len, required List<vm.Vector3> watch, required vm.Vector3 corner, required List<vm.Vector4> paint}) {
    this.paint = paint;
    final p = _plan = FinishPlan(plan, len: len, watch: watch, corner: corner);
    _shots = _pickShots(p);
    return p;
  }

  /// The close-ups in words, for the capture log.
  String describeShots() => [
    for (final s in _shots ?? const <_CloseUp>[])
      '  close-up: ${s.plaster ? 'plaster' : 'paint'} ${_plan!.plan.letters.letters[s.unit.letter].text} ${s.from.toStringAsFixed(1)}–${s.to.toStringAsFixed(1)}',
  ].join('\n');

  /// [j] at [t], [revealAt] when its reveal started (or will): poses
  /// follow in the crew's update, tools after it ([drawTools]).
  void update(Job j, BuildPlan? plan, double t, double revealAt) {
    _job = j;
    final p = _plan;
    _on = false;
    _calledOff = null;
    if (p == null || plan == null || !identical(p.plan, plan)) return;
    _u = t - revealAt;
    // The reveal, and the walk off into the celebration.
    _on = (j.phase == Phase.reveal || (j.phase == Phase.celebrate && _u < p.len + FinishPlan.overrun + 0.5)) && j.cutAt == null;
    // Called off in it (a sample giving way): the builders walk off with
    // their tools (the crew's walk, from where the finish had them), the
    // foreman back to his corner from where he was looking on.
    if (j.cutAt != null && j.phase == Phase.demolish) {
      final c = j.phaseStart - revealAt;
      if (c < 0 || c >= p.len) return;
      _calledOff = c;
      if (_offFor != j) {
        _offFor = j;
        final at = (c < p._foremanOut.start ? p._foremanIn : p._foremanOut).posAt(c, vm.Vector3.zero());
        _foremanOff = Walk([at, p.corner], c + 0.4, 2.6, face: math.atan2(-(0 - p.corner.x), -(0.4 - p.corner.z)) * 0.8);
      }
    }
  }

  /// When (seconds into the finish) it was called off, and the foreman's way
  /// back then.
  double? _calledOff;
  Job? _offFor;
  Walk? _foremanOff;

  // ── The crew ──────────────────────────────────────────────────────────────

  final _a = vm.Vector3.zero(), _b = vm.Vector3.zero(), _c = vm.Vector3.zero(), _d = vm.Vector3.zero();

  /// Where builder [z] is at [t] (scene time), if the finish has them: for
  /// the crew walking off when it's called off.
  vm.Vector3? whereAt(int z, double t, double revealAt) {
    final p = _plan;
    if (p == null || z >= Crew3D.builders) return null;
    final u = t - revealAt;
    final leg = p._legAt(z, u);
    if (leg == null) return null;
    final out = vm.Vector3.zero();
    if (leg.walk case final walk?) return walk.posAt(u, out);
    final unit = leg.unit!;
    final plasterer = z.isEven;
    final tau = (u - (plasterer ? unit.plaster : unit.paint)).clamp(0.0, unit.run / p.v);
    return out..setValues(p.bodyX(unit, tau, plasterer: plasterer), 0, _bodyZ(p, unit, u, plasterer));
  }

  double _bodyZ(FinishPlan p, FinishUnit unit, double u, bool plasterer) {
    if (!plasterer) return FinishPlan.zPaint;
    return lerp(FinishPlan.zPole, FinishPlan.zHand, _handMode(p, unit, u));
  }

  /// 0 working with the pole … 1 up close with hawk and trowel.
  static double _handMode(FinishPlan p, FinishUnit unit, double u) {
    if (u < unit.plaster) return 0;
    final y = p.frontAt(unit, math.min(u, unit.plaster + unit.run / p.v), plaster: true);
    return smooth(FinishPlan.lowHand + 0.22, FinishPlan.lowHand - 0.02, y);
  }

  /// The crew's stage hook: the builders and the foreman through the finish.
  void pose(int who, FigurePose f) {
    final p = _plan, back = _foremanOff, off = _calledOff;
    if (off != null && p != null) {
      if (who == Crew3D.foreman && back != null && _u < back.end) {
        f
          ..rest()
          ..clipboard = true;
        back.pose(f, _u, 3);
        f.armPitch[0] = 1.0;
      } else if (who < Crew3D.builders && _u < off + 4.5 && off < p.arrive[who]) {
        // Walking off with their tools.
        _carrying(f);
      }
      return;
    }
    if (!_on || p == null) return;
    if (who == Crew3D.foreman) {
      if (_u < p.arrive[Crew3D.builders]) _foreman(p, f);
      return;
    }
    if (who >= Crew3D.builders || _u >= p.arrive[who]) return;
    final leg = p._legAt(who, _u);
    if (leg == null) return;
    final seed = who * 13 + 3;
    final plasterer = who.isEven;
    f
      ..rest()
      ..clipboard = false;
    if (leg.walk case final walk?) {
      walk.pose(f, _u, seed);
      // On the deck at first (it's down, resting a step up), then a step
      // down off its back.
      f.pos.y = Crew3D.standY(f.pos, p.w, SiteLayout.deckRest + 0.05);
      _carrying(f);
      return;
    }
    _work(p, leg.unit!, f, plasterer, seed);
  }

  /// The pole held out in front, low, the bucket or the tray in the other
  /// hand.
  static void _carrying(FigurePose f) {
    f
      ..handTo(1, 0.24, 0.15, -0.22)
      ..armPitch[0] = 0.05
      ..elbow[0] = 0.2;
  }

  void _work(FinishPlan p, FinishUnit unit, FigurePose f, bool plasterer, int seed) {
    final u = _u, start = plasterer ? unit.plaster : unit.paint, runEnd = start + unit.run / p.v;
    final tau = (u - start).clamp(0.0, unit.run / p.v);
    f.pos.setValues(p.bodyX(unit, tau, plasterer: plasterer), 0, _bodyZ(p, unit, u, plasterer));
    OffDuty.stand(f, u, seed);
    if (u < start - FinishPlan.load || u >= runEnd + 0.15) {
      // Waiting their turn, or done: an eye on the letter, the pole up.
      _face(f, unit.cx, 0);
      f
        ..armPitch[1] = 0.55
        ..armRoll[1] = -0.05;
      if (u >= runEnd + 0.15 && !plasterer) f.lean = -0.06; // a step back to look at it
      return;
    }
    if (u < start) {
      // Loading: the float into the bucket, the roller through the tray.
      final k = math.sin(math.pi * c01((u - start + FinishPlan.load) / FinishPlan.load));
      _ground(p, unit, plasterer, _a);
      _face(f, _a.x, _a.z);
      f
        ..lean = 0.55 * k
        ..bob = -0.06 * k;
      _a.y = 0.1;
      crew.aim(f, 0, _a);
      crew.aim(f, 1, _a);
      return;
    }
    final tool = _toolAt(p, unit, u, plasterer, _b);
    if (plasterer && _handMode(p, unit, u) > 0.5) {
      // Up close: the trowel on the wall, the hawk held out.
      _face(f, tool.x, tool.z);
      final low = c01((1.0 - tool.y) / 0.9);
      f
        ..lean = 0.18 + 0.4 * low
        ..bob = -0.16 * low
        ..legPitch[0] = 0.5 * low
        ..legPitch[1] = -0.15 * low;
      crew.aim(f, 1, tool);
      _c.setValues(f.pos.x - 0.25, 1.05 - 0.3 * low, f.pos.z + 0.3);
      crew.aim(f, 0, _c);
      return;
    }
    // Working the pole: both hands on it, low; leaning back to reach high.
    _face(f, tool.x, tool.z);
    _grip(f, tool, _c, _d);
    crew.aim(f, 0, _c);
    crew.aim(f, 1, _d);
    f.lean = 0.05 - 0.14 * c01((tool.y - 2.0) / 3.0);
    // Stepping sideways as they go along.
    Gait.sideways(f, (f.pos.x - p.bodyX(unit, 0, plasterer: plasterer)) * math.cos(f.yaw));
  }

  /// Turns [f] towards (x, z).
  static void _face(FigurePose f, double x, double z) => f.yaw = math.atan2(-(x - f.pos.x), -(z - f.pos.z));

  /// Where the hands go on a pole from [f] to [tool]: low in front, one
  /// above the other.
  void _grip(FigurePose f, vm.Vector3 tool, vm.Vector3 low, vm.Vector3 high) {
    final fx = -math.sin(f.yaw), fz = -math.cos(f.yaw);
    low.setValues(f.pos.x + fx * 0.3, f.pos.y + 1.0, f.pos.z + fz * 0.3);
    _dir
      ..setFrom(tool)
      ..sub(low)
      ..normalize();
    high
      ..setFrom(_dir)
      ..scale(0.3)
      ..add(low);
  }

  final _dir = vm.Vector3.zero();

  /// The tool's working point on [unit] at [u]: the float's blade on the
  /// plaster front (little swipes), the roller just above the paint front
  /// (strokes up and down).
  vm.Vector3 _toolAt(FinishPlan p, FinishUnit unit, double u, bool plasterer, vm.Vector3 out) {
    final start = plasterer ? unit.plaster : unit.paint;
    final tau = (u - start).clamp(0.0, unit.run / p.v);
    final front = p.frontAt(unit, start + tau, plaster: plasterer);
    final x = p.toolX(unit, tau, plasterer: plasterer);
    final y = plasterer ? front + 0.035 * math.sin(u * 19) : front + 0.12 + 0.16 * math.sin(u * 12.5);
    return out..setValues(x, y.clamp(math.max(0.08, unit.y0 - 0.05), unit.y1 + 0.1), _face0 - (plasterer ? 0.03 : 0.05));
  }

  /// The letters' front face (z), set by the site.
  double _face0 = -0.2;
  set face(double z) => _face0 = z;

  /// Where the plasterer's bucket (else the painter's tray) stands at
  /// [unit].
  void _ground(FinishPlan p, FinishUnit unit, bool plasterer, vm.Vector3 out) {
    final x = p.bodyX(unit, 0, plasterer: plasterer);
    out.setValues(x + (plasterer ? -0.42 : 0.42), 0, plasterer ? -1.6 : -1.45);
  }

  void _foreman(FinishPlan p, FigurePose f) {
    final u = _u;
    f
      ..rest()
      ..clipboard = true;
    final walking = u < p._foremanIn.end || u >= p._foremanOut.start;
    (u < p._foremanOut.start ? p._foremanIn : p._foremanOut).pose(f, u, 3);
    if (walking && u >= p._foremanIn.start) {
      f.armPitch[0] = 1.0;
      return;
    }
    if (u < p._foremanIn.start) {
      f.armPitch[0] = 1.15;
      return;
    }
    // Looking on: towards the letter just done (else the work going on),
    // a check on the clipboard, a thumbs up as each is finished.
    var look = 0.0, at = -1e9;
    for (var k = 0; k < p.plan.letterCount; k++) {
      final d = p.doneAt(k);
      if (d <= u && d > at) {
        at = d;
        final l = p.plan.letters.letters[k];
        look = ((l.col0 + l.col1 + 1) / 2 - p.plan.r.cols / 2) * p.b;
      }
    }
    if (at < -1e8) look = 0;
    _face(f, look, 0);
    f
      ..armPitch[0] = 1.15
      ..armRoll[0] = -0.15
      ..lean = 0.1;
    final thumbs = seg(u, at, at + 0.25) * (1 - seg(u, at + 1.1, at + 1.4));
    if (thumbs > 0) {
      // A thumbs up, a nod.
      f
        ..handTo(1, 0.2, 0.3, -0.3, thumbs)
        ..headPitch += 0.15 * math.sin(math.pi * seg(u, at, at + 0.7));
    } else if ((u / 3.1).floor() % 3 == 1) {
      // Pointing at the work, the hand out low.
      final k = smooth(0, 0.4, (u / 3.1) % 1.0) * (1 - smooth(0.85, 1, (u / 3.1) % 1.0));
      f.handTo(1, 0.28, 0.22, -0.4, k);
    }
  }

  // ── The tools ─────────────────────────────────────────────────────────────

  static final _steel = v4(hex3(0xB8C2CE)), _pole = v4(hex3(0xD9DEE6)), _grip0 = v4(hex3(0x2B3A55)), _hawk = v4(hex3(0x9AA6B4));
  static final _bucket = v4(hex3(0xE87A2E)), _mortar = v4(hex3(0x8E8A84)), _tray = v4(hex3(0x3A4C6E)), _sleeve = v4(hex3(0xF4F1EA));
  static final _dustTint = vm.Vector4(0.92, 0.9, 0.86, 0.4);

  /// Draws the tools for this frame (after the crew's update: carried tools
  /// go where the hands are) and puffs the dust and the drips.
  void drawTools() {
    tools.begin();
    final p = _plan, off = _calledOff;
    if (_on && p != null) {
      for (var z = 0; z < Crew3D.builders; z++) {
        if (_u >= p.arrive[z]) continue;
        final leg = p._legAt(z, _u);
        if (leg == null) continue;
        _toolsOf(p, z, leg);
      }
    } else if (off != null && p != null && _u < off + 4.5) {
      // Called off: carried off (the crew's walk has them).
      for (var z = 0; z < Crew3D.builders; z++) {
        if (off < p.arrive[z]) _carry(p, z);
      }
    }
    tools.end();
  }

  /// Builder [z]'s pole (telescoped in) held out in front, its head up,
  /// and the bucket or the tray in the other hand.
  void _carry(FinishPlan p, int z) {
    final f = crew.poses[z], plasterer = z.isEven;
    OffDuty.hand(f, 1, _a);
    final fx = -math.sin(f.yaw) * 0.8, fz = -math.cos(f.yaw) * 0.8;
    _b.setValues(_a.x + fx * 1.1, _a.y + 0.75, _a.z + fz * 1.1);
    _c.setValues(_a.x - fx * 0.3, _a.y - 0.2, _a.z - fz * 0.3);
    tools.rod(_c, _b, 0.018, _pole);
    _head(plasterer, _b.x, _b.y + 0.04, _b.z, _colourOf(p, z), 0.6);
    OffDuty.hand(f, 0, _a);
    _carried(p, z, plasterer, _a.x, _a.y - 0.08, _a.z, f.yaw);
  }

  void _toolsOf(FinishPlan p, int z, _Leg leg) {
    final f = crew.poses[z], plasterer = z.isEven;
    if (leg.walk != null) {
      _carry(p, z);
      return;
    }
    final unit = leg.unit!, u = _u;
    final start = plasterer ? unit.plaster : unit.paint, runEnd = start + unit.run / p.v;
    _ground(p, unit, plasterer, _d);
    _carried(p, z, plasterer, _d.x, plasterer ? 0.15 : 0.03, _d.z, 0);
    final colour = _colourOf(p, z);
    if (u < start - FinishPlan.load || u >= runEnd + 0.15) {
      // Holding the pole upright beside them.
      OffDuty.hand(f, 1, _a);
      _b.setValues(_a.x, 0.02, _a.z);
      _c.setValues(_a.x, _a.y + 1.4, _a.z);
      tools.rod(_b, _c, 0.018, _pole);
      _head(plasterer, _c.x, _c.y + 0.06, _c.z, colour, 0);
      return;
    }
    if (u < start) {
      // Loading: the head in the bucket or the tray.
      OffDuty.hand(f, 1, _a);
      _b.setValues(_d.x, plasterer ? 0.22 : 0.08, _d.z);
      _shaft(_a, _b);
      _head(plasterer, _b.x, _b.y, _b.z, colour, math.pi / 2);
      return;
    }
    final tool = _toolAt(p, unit, u, plasterer, _b);
    if (plasterer && _handMode(p, unit, u) > 0.5) {
      // Hawk in the left hand, trowel on the wall; the pole laid by.
      OffDuty.hand(f, 0, _a);
      tools
        ..box(_a.x, _a.y + 0.04, _a.z, 0.26, 0.012, 0.26, _hawk, yaw: f.yaw)
        ..cyl(_a.x, _a.y - 0.02, _a.z, 0.018, 0.09, _grip0)
        ..box(_a.x, _a.y + 0.06, _a.z, 0.13, 0.03, 0.13, _mortar, yaw: f.yaw);
      tools.box(tool.x, tool.y, tool.z, 0.24, 0.09, 0.008, _steel, roll: 0.25 * math.sin(u * 7));
      _c.setValues(_d.x + 0.3, 0.03, _d.z - 0.1);
      _a.setValues(_d.x + 0.3 + 2.4, 0.03, _d.z - 0.05);
      tools.rod(_c, _a, 0.018, _pole);
      _swipe(tool, unit, u);
      return;
    }
    // The pole from the hands to the head on the wall.
    OffDuty.hand(f, 0, _a);
    OffDuty.hand(f, 1, _c);
    _a
      ..add(_c)
      ..scale(0.5);
    _shaft(_a, tool, behind: true);
    _head(plasterer, tool.x, tool.y, tool.z, colour, 0);
    if (plasterer) {
      _swipe(tool, unit, u);
    } else {
      _drips(p, z, unit, colour);
    }
  }

  /// The pole from [hand] to [head] (on past the hand when [behind]).
  void _shaft(vm.Vector3 hand, vm.Vector3 head, {bool behind = false}) {
    _dir
      ..setFrom(head)
      ..sub(hand);
    final l = _dir.length;
    if (l < 1e-3) return;
    _dir.scale(1 / l);
    // The pole stops short of the head (its bracket or the roller's frame).
    _c.setValues(head.x - _dir.x * 0.1, head.y - _dir.y * 0.1, head.z - _dir.z * 0.1);
    final back = behind ? 0.32 : 0.05;
    _a.setValues(hand.x - _dir.x * back, hand.y - _dir.y * back, hand.z - _dir.z * back);
    tools.rod(_a, _c, 0.017, _pole);
    _e.setValues(_a.x + _dir.x * 0.25, _a.y + _dir.y * 0.25, _a.z + _dir.z * 0.25);
    tools.rod(_a, _e, 0.024, _grip0);
  }

  final _e = vm.Vector3.zero(), _f = vm.Vector3.zero();

  /// A float's blade or a roller at (x, y, z).
  void _head(bool plasterer, double x, double y, double z, vm.Vector4 colour, double pitch) {
    if (plasterer) {
      tools
        ..box(x, y, z - 0.01, 0.46, 0.11, 0.012, _steel, pitch: pitch)
        ..box(x, y, z - 0.045, 0.08, 0.05, 0.06, _grip0, pitch: pitch);
    } else {
      // The roller across, its frame back to the pole.
      tools.cyl(x, y, z - 0.045, 0.047, 0.24, colour, roll: math.pi / 2);
      _e.setValues(x + 0.13, y, z - 0.045);
      _f.setValues(x + 0.13, y - 0.08, z - 0.12);
      tools.rod(_e, _f, 0.008, _steel);
    }
  }

  /// The bucket (plasterer) or the tray with its can (painter) at (x, y, z)
  /// — on the ground, or in hand.
  void _carried(FinishPlan p, int z, bool plasterer, double x, double y, double zz, double yaw) {
    final unit = _unitOf(p, z);
    final colour = unit != null && unit.letter < paint.length ? paint[unit.letter] : _sleeve;
    if (plasterer) {
      tools
        ..cyl(x, y, zz, 0.15, 0.28, _bucket)
        ..cyl(x, y + 0.13, zz, 0.135, 0.02, _mortar);
    } else {
      tools
        ..box(x, y, zz, 0.32, 0.05, 0.38, _tray, yaw: yaw)
        ..box(x, y + 0.02, zz + 0.03, 0.26, 0.02, 0.24, colour, yaw: yaw);
      if (y < 0.1) {
        tools
          ..cyl(x + 0.32, 0.12, zz + 0.12, 0.1, 0.24, _sleeve)
          ..cyl(x + 0.32, 0.245, zz + 0.12, 0.103, 0.015, colour);
      }
    }
  }

  /// The unit builder [z] is at (or on the way to), or null.
  FinishUnit? _unitOf(FinishPlan p, int z) {
    for (final l in p._legs[z]) {
      if (l.unit != null && _u < l.to) return l.unit;
    }
    return null;
  }

  /// The colour on painter [z]'s roller: the last letter they dipped it
  /// for (fresh: the sleeve's own).
  vm.Vector4 _colourOf(FinishPlan p, int z) {
    var c = _sleeve;
    for (final l in p._legs[z]) {
      final unit = l.unit;
      if (unit == null) continue;
      if (_u < unit.paint - FinishPlan.load) break;
      if (unit.letter < paint.length) c = paint[unit.letter];
    }
    return c;
  }

  /// Plaster dust off the blade.
  void _swipe(vm.Vector3 at, FinishUnit unit, double u) {
    final k = (u * 4).floor();
    final age = u * 4 - k;
    fx.puff(at.x + 0.15 * (rnd(k, unit.letter) - 0.5), at.y - 0.05, at.z - 0.08, age, 0.12, seed: k, n: 1, tint: _dustTint);
  }

  /// Paint drips off the roller: falling, then specks on the ground.
  void _drips(FinishPlan p, int z, FinishUnit unit, vm.Vector4 colour) {
    const every = 0.33, lie = 3.0;
    final u = _u;
    final from = math.max(unit.paint, u - lie - 1.2), to = math.min(u, unit.paint + unit.run / p.v);
    for (var i = (from / every).ceil(); i * every <= to; i++) {
      final t0 = i * every + 0.1 * rnd(i, z);
      if (t0 < unit.paint || t0 > u) continue;
      final at = _toolAt(p, unit, t0, false, _c);
      final x = at.x + 0.18 * (rnd(i, z, 1) - 0.5), y0 = at.y - 0.05, zz = at.z - 0.02;
      final fall = math.sqrt(2 * math.max(0.05, y0) / SiteLayout.g);
      final tau = u - t0;
      if (tau < fall) {
        fx.confetti(x, y0 - 0.5 * SiteLayout.g * tau * tau, zz, 0, 0, 0, 0.035, colour);
      } else if (tau < fall + lie) {
        final s = 0.05 + 0.04 * rnd(i, z, 2);
        fx.confetti(x, 0.012, zz - 0.15 * rnd(i, z, 3), rnd(i, z, 4) * 6, math.pi / 2, 0, s * (1 - seg(tau, fall + lie - 0.6, fall + lie)), colour);
      }
    }
  }

  // ── The camera ────────────────────────────────────────────────────────────

  List<_CloseUp>? _shots;

  /// The close-ups (priority 3): the plasterer's float smoothing a jagged
  /// edge — the whole letter first, pushing in on the steps filling in —
  /// then a roller turning a letter colourful, the painter below it.
  void focus(List<Focus> out) {
    final p = _plan, j = _job, shots = _shots;
    if (!_on || p == null || j == null || shots == null || j.phase != Phase.reveal) return;
    final u = _u;
    for (final s in shots) {
      if (u < s.from || u >= s.to) continue;
      final unit = s.unit, plasterer = s.plaster;
      final start = plasterer ? unit.plaster : unit.paint;
      final front = p.frontAt(unit, math.min(u, start + unit.run / p.v), plaster: plasterer);
      final mid = (unit.y0 + unit.y1) / 2, tall = unit.y1 - unit.y0;
      final Shot shot;
      if (plasterer) {
        // The whole letter, pushing in on the edge being smoothed: the
        // plaster above the float, the steps still to go below it.
        final k = eio(seg(u, s.from + 0.3, s.to));
        final x = _edgeX(p, unit, front - 0.1, s.side);
        final whole = vm.Vector3(unit.cx, mid, _face0);
        final tg = whole + (vm.Vector3(lerp(x, unit.cx, 0.4), front - 0.25, _face0) - whole) * k;
        final back = lerp(math.max(6.5, tall * 1.5 + 1.6), 5.6, k);
        shot = Shot(vm.Vector3(tg.x + s.side * lerp(1.3, 0.7, k), tg.y + lerp(0.3, 0.6, k), _face0 - back), tg, fov: lerp(40, 34, k), settle: 0.6, drift: 0.2);
      } else {
        // Looking up from eye height: the colour going on, the painter on
        // the pole under it, the rest of the letter still bare.
        final side = unit.cx < 0 ? 1.0 : -1.0;
        final tg = vm.Vector3(unit.cx, lerp(front, mid, 0.45), _face0);
        shot = Shot(vm.Vector3(tg.x + side * 1.8, 1.6, _face0 - math.max(6.2, tall * 1.45 + 1.4)), tg, fov: 40, settle: 0.6, drift: 0.25);
      }
      out.add(Focus('finish ${s.from.toStringAsFixed(1)}', shot, priority: 3));
      return;
    }
  }

  /// The close-up from [from] seconds into the reveal (as its focus names
  /// it), if there is one: whether it's the plaster's, and its letter (the
  /// plan's).
  ({bool plaster, int letter})? closeUpAt(String from) {
    for (final s in _shots ?? const <_CloseUp>[]) {
      if (s.from.toStringAsFixed(1) == from) return (plaster: s.plaster, letter: s.unit.letter);
    }
    return null;
  }

  /// Picks the close-ups: the plasterer on the jaggiest edge of an early
  /// letter; then a painter with a good run of a letter still to go.
  List<_CloseUp> _pickShots(FinishPlan p) {
    final shots = <_CloseUp>[];
    _CloseUp? plaster;
    var most = -1;
    for (final unit in p.units) {
      if (unit.empty || unit.pair < 0 || unit.plaster > 5.5) continue;
      final from = unit.plaster + 0.3, to = math.min(from + 3.2, unit.plaster + unit.run / p.v - 0.2);
      if (to - from < 1.8) continue;
      // The edge with the most steps over the rows the float passes then.
      final l = p.plan.letters.letters[unit.letter];
      final r0 = (p.frontAt(unit, to, plaster: true) / p.b).floor(), r1 = (p.frontAt(unit, from, plaster: true) / p.b).floor();
      int steps(int side) {
        var n = 0, last = -1;
        for (var row = math.max(r0, l.row0); row <= math.min(r1, l.row1); row++) {
          final c = side < 0 ? l.left[row] : l.right[row];
          if (c < 0) continue;
          if (last >= 0 && c != last) n++;
          last = c;
        }
        return n;
      }

      for (final side in const [-1, 1]) {
        final n = steps(side);
        if (n > most) {
          most = n;
          plaster = _CloseUp(unit, from, to, true, side.toDouble());
        }
      }
    }
    if (plaster != null) shots.add(plaster);
    // Then a painter: the first with a good run still to go (a short one
    // only if there's nothing better).
    final t1 = (plaster?.to ?? 3.0) + 0.3;
    FinishUnit? best;
    var score = double.infinity, at = 0.0;
    for (final unit in p.units) {
      if (unit.empty || unit.pair < 0) continue;
      final from = math.max(t1, unit.paint + 0.3), to = unit.paint + unit.run / p.v - 0.2;
      if (to - from < 1.4) continue;
      final s = from + (to - from < 2.2 ? 10 : 0);
      if (s >= score) continue;
      score = s;
      at = from;
      best = unit;
    }
    if (best != null) shots.add(_CloseUp(best, at, math.min(at + 3.2, best.paint + best.run / p.v - 0.2), false, 0));
    return shots;
  }

  /// The x of [unit]'s letter's edge on [side] at height [y], within the
  /// unit.
  double _edgeX(FinishPlan p, FinishUnit unit, double y, double side) {
    final l = p.plan.letters.letters[unit.letter];
    final row = (y / p.b).floor().clamp(l.row0, l.row1);
    final c = side < 0 ? l.left[row] : l.right[row];
    final x = c < 0 ? unit.cx : (side < 0 ? c : c + 1) * p.b - p.plan.r.cols / 2 * p.b;
    return x.clamp(unit.x0, unit.x1);
  }
}

class _CloseUp {
  _CloseUp(this.unit, this.from, this.to, this.plaster, this.side);
  final FinishUnit unit;
  final double from, to;
  final bool plaster;
  final double side;
}

/// A letter's paint: the palette colour, a touch deeper (real paint, not a
/// screen's glow).
vm.Vector4 paintOf(Color hue) {
  final c = lin(hue);
  return vm.Vector4(c.x * 0.8, c.y * 0.8, c.z * 0.8, 1);
}
