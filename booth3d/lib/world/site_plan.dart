import 'dart:math' as math;
import 'dart:typed_data';

import 'package:text_slides/booth/model.dart';
import 'package:text_slides/booth/raster.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';
import 'site_letters.dart';

/// Where the site's fixed things stand (world units; the wall is centred on
/// x = 0 at z = 0, its readable side towards −z).
abstract final class SiteLayout {
  /// Tower crane: mast foot and jib height.
  static const mastX = 13.0, mastZ = 4.3, jibY = 15.0;

  /// The brick yard by the crane: pallet k stands at [yard] (4 × 3, from
  /// the front row).
  static vm.Vector3 yard(int k) => vm.Vector3(11.7 + (k % 4) * 1.55, 0, -1.5 + ((k ~/ 4) % 3) * 1.5);

  /// The climbing platform behind the wall (its floor from [deckZ0] to
  /// [deckZ1]): the brick piles at [stashZ], the builders behind them at
  /// [crewZ], facing the wall; the kerning crew right behind the wall at
  /// [kernZ].
  static const deckZ0 = 0.3, deckZ1 = 1.9, stashZ = 0.92, crewZ = 1.38, kernZ = 0.42;

  /// Gravity for everything that falls.
  static const g = 9.8;

  /// The brick size for [r]: as big as the plaza allows.
  static double brick(NameRaster r) => math.min(0.32, math.min(19.0 / r.cols, 7.6 / r.rows));
}

/// Name City's pace (the model's [BoothModel.pace]): names are built one
/// letter at a time with a kerning step between letters ([BuildSchedule]),
/// in [longest] at most. The celebration is longer than the booth's: the
/// team's photo with the Glyph Works' mini name.
class CityPace extends BuildPace {
  const CityPace();

  /// The longest build at the normal pace (a long name is squeezed).
  static const longest = 210.0;

  /// The celebration: fireworks, then the team's photo (photo_op.dart).
  static const celebrate = 24.0;

  @override
  double nominal(NameRaster r) => math.min(BuildSchedule.of(r).natural, longest);

  /// About six letters.
  @override
  double get typical => 100;

  @override
  double get sample => 0.75;

  @override
  double phaseLen(Phase p) => p == Phase.celebrate ? celebrate : super.phaseLen(p);
}

/// The build's timeline at its natural pace (seconds from the build start),
/// letter by letter, left to right: the letter's team boards while the
/// platform is down, lays it bottom-up (the platform climbing with it), the
/// platform moves to the kerning height, the crew kern it against the
/// letter before, and the platform comes down for the next team. The plan
/// scales it to the build's length. A pure function of the raster.
class BuildSchedule {
  BuildSchedule._(NameRaster r, {required bool quick}) : letters = NameLetters.of(r), b = SiteLayout.brick(r) {
    final ls = letters.letters, n = ls.length;
    layA = Float64List(n);
    layB = Float64List(n);
    kernA = Float64List(n);
    kernB = Float64List(n);
    downB = Float64List(n);
    h0 = Float64List(n);
    hTop = Float64List(n);
    hKern = Float64List(n);
    tapeRow = Int32List(n);
    full = List.filled(n, false);
    // The close-ups: the most kerned pair (the first, when nothing is), and
    // in a longer name the next most kerned.
    if (!quick && n >= 2) {
      final pairs = [for (var k = 1; k < n; k++) k]
        ..sort((a, c) {
          final d = ls[c].kernEm.abs().compareTo(ls[a].kernEm.abs());
          return d != 0 ? d : a - c;
        });
      full[ls[pairs.first].kernEm.abs() >= 0.01 ? pairs.first : 1] = true;
      if (n - 1 >= 4) {
        for (final k in pairs) {
          if (!full[k] && ls[k].kernEm.abs() >= 0.02) {
            full[k] = true;
            break;
          }
        }
      }
    }
    var t = 0.0;
    for (var k = 0; k < n; k++) {
      final l = ls[k];
      h0[k] = stepDeck(l.row0 * b);
      hTop[k] = stepDeck((l.row1 + 1) * b);
      layA[k] = (k == 0 ? lead : t + board) + move(0, h0[k]);
      layB[k] = layA[k] + layTime(l.bricks);
      if (k == 0) {
        kernA[k] = kernB[k] = layB[k];
        downB[k] = layB[k] + move(hTop[k], 0);
      } else {
        // The tape goes a row above the higher of the two letters' feet
        // (at least knee high), where both have ink.
        final p = ls[k - 1];
        final lo = math.max(p.row0, l.row0), hi = math.min(p.row1, l.row1);
        final row = lo <= hi ? math.min(hi, math.max(lo + 1, (0.6 / b).ceil())) : (lo + hi) ~/ 2;
        tapeRow[k] = row;
        hKern[k] = (tapeY(k) - 0.92).clamp(0.0, 9.0);
        kernA[k] = layB[k] + move(hTop[k], hKern[k]);
        kernB[k] = kernA[k] + (full[k] ? fullKern : quickKern);
        downB[k] = kernB[k] + move(hKern[k], 0);
      }
      t = downB[k];
    }
    natural = t + walkOff;
  }

  static final _cache = Expando<BuildSchedule>('BuildSchedule'), _quick = Expando<BuildSchedule>('BuildSchedule quick');

  /// [quick]: every kerning step short (for a hurried build).
  static BuildSchedule of(NameRaster r, {bool quick = false}) =>
      quick ? (_quick[r] ??= BuildSchedule._(r, quick: true)) : (_cache[r] ??= BuildSchedule._(r, quick: false));

  final NameLetters letters;

  /// Brick size.
  final double b;

  /// Per letter: laying from [layA] to [layB], kerning from [kernA] to
  /// [kernB] (none for the first letter), the platform down again at
  /// [downB].
  late final Float64List layA, layB, kernA, kernB, downB;

  /// Per letter: the platform's height for its first row ([h0]), at its
  /// top ([hTop]) and for kerning ([hKern]).
  late final Float64List h0, hTop, hKern;

  /// Per letter: the brick row (from the bottom) the measuring tape is
  /// stretched along, and whether its kerning gets the full close-up.
  late final Int32List tapeRow;
  late final List<bool> full;

  /// The whole build at its natural pace.
  late final double natural;

  double tapeY(int k) => (tapeRow[k] + 0.5) * b;

  /// The first team's first brick, after the start (they boarded in the
  /// intake).
  static const lead = 1.5;

  /// The platform down between letters: the last team steps off (back to
  /// their rest spots), the next one boards.
  static const board = 2.5;

  /// The last team walks back to their places at the end.
  static const walkOff = 1.6;

  /// Kerning steps: the full close-up and the quick one.
  static const fullKern = 7.0, quickKern = 3.4;

  /// Seconds to lay a letter of [n] bricks.
  static double layTime(int n) => n < 20 ? 3 + 0.2 * n : (5 + 0.04 * math.min(n, 150) + 0.02 * math.max(0, n - 150)).clamp(7.0, 18.0);

  /// Seconds for the platform to move between two heights.
  static double move(double a, double e) => (a - e).abs() < 0.01 ? 0 : 0.3 + (a - e).abs() / 1.6;

  /// The platform's height for a wall built up to [level]: it lifts a step
  /// whenever the wall gets out of comfortable reach.
  static double stepDeck(double level) {
    const step = 0.8;
    final x = math.max(0.0, level - 0.45) / step;
    final k = x.floorToDouble();
    // Rises during the last 20% of each interval, smoothly.
    return (k + eio(seg(x - k, 0.8, 1.0))) * step;
  }
}

/// What a builder is doing (see [BuildPlan.crewAt]).
enum CrewMode {
  /// Not needed: at their rest spot (or on a break).
  free,

  /// Laying their share of a letter.
  work,

  /// At their place, watching the kerning (or done with their share).
  watch,

  /// Holding the tape's hook on the letter before.
  hook,

  /// Holding the tape's case on the new letter.
  holdCase,

  /// Pushing the letter into place (first in line), or pushing the one in
  /// front (second).
  push1,
  push2,
}

/// Where a builder is and what they're doing at one moment.
class CrewPlace {
  double x = 0, z = SiteLayout.crewZ;

  /// Walking there (and which way: yaw, 0 towards −z).
  bool walking = false;
  double heading = 0;
  CrewMode mode = CrewMode.free;

  /// The letter they work on (or kern), or −1.
  int letter = -1;
}

/// One kerning step: the crew measure the gap between letter [letter] − 1
/// and the new [letter] (built [slide] too far right), push it into the
/// place the text engine laid it out, tap it home and let the tape go.
class KernStep {
  KernStep._(this.letter, this.full);

  final int letter;
  final bool full;

  /// The pair and the font's kerning for it (em).
  late final String left, right;
  late final double em;

  /// The phases (absolute): the crew walk over from [a]; the tape comes
  /// out over [tapeA, tapeB); the foreman checks until [checkB]; the push
  /// runs over [pushA, pushB); the tap until [tapB]; the tape retracts
  /// until [retractB]; the step ends at [e].
  late final double a, tapeA, tapeB, checkB, pushA, pushB, tapB, retractB, e;

  /// How far right of its place the letter was built.
  late final double slide;

  /// The gap: the letter before's edge and the new letter's (in place) at
  /// the tape's height [tapeY], with the platform at [deck].
  late final double gapL, gapR, tapeY, deck;

  /// Where the pushers' hands go: the letter's right edge (in place) at
  /// [pushY].
  late final double pushX, pushY;

  /// Who does what (builder ids, −1: nobody).
  late final int hook, holdCase, push1, push2;

  /// Fractions of a full and a quick step at each phase boundary.
  static const _fullAt = [0.0, 0.8, 1.6, 2.8, 3.8, 5.6, 6.1, 6.6, 7.0];
  static const _quickAt = [0.0, 0.45, 0.95, 1.35, 1.55, 2.55, 2.85, 3.25, 3.4];

  void _times(double from, double to) {
    final at = full ? _fullAt : _quickAt;
    double f(int i) => from + (to - from) * at[i] / at.last;
    a = from;
    tapeA = f(1);
    tapeB = f(2);
    checkB = f(3);
    pushA = f(4);
    pushB = f(5);
    tapB = f(6);
    retractB = f(7);
    e = to;
  }

  /// How far the letter still is from its place at [t].
  double offset(double t) {
    if (t < pushA) return slide;
    if (t >= pushB) return 0;
    final f = seg(t, pushA, pushB);
    // Heaved along in shoves.
    return slide * (1 - c01(eio(f) + 0.025 * math.sin(f * math.pi * 3) * math.sin(f * math.pi)));
  }
}

class _Leg {
  _Leg(this.t, this.x, this.z, this.mode, {this.follow = -1, this.letter = -1, this.until = 1e9});
  final double t, x, z;
  final CrewMode mode;

  /// Moves with this letter's slide (−1: stays put).
  final int follow;
  final int letter;

  /// Must be there by then.
  final double until;

  /// How long the walk there takes.
  double walk = 0;
}

/// The build choreography for one name, as pure functions of scene time:
/// the name goes up one letter at a time, left to right ([BuildSchedule]).
/// Every brick's journey (yard pallet → crane → a builder's pile on the
/// platform → the builder's hands → its cell in the wall), the crane's
/// trips (one a letter, or a share of a big one), the platform's height,
/// each letter's slide into place in its kerning step, and who is needed
/// where. Pure, so frames, fast-forward and capture always agree.
///
/// Bricks are numbered in the order they're laid (brick i is raster brick
/// [src] i); the letters are consecutive runs ([letterStart]).
class BuildPlan {
  BuildPlan(this.job, this.r, this.b) : letters = NameLetters.of(r) {
    var sc = BuildSchedule.of(r);
    if (len / sc.natural < 0.75 && sc.full.contains(true)) sc = BuildSchedule.of(r, quick: true);
    sched = sc;
    s = len / sc.natural;
    final ls = letters.letters, nl = ls.length, n = r.bricks.length;

    // ── Teams: the builders whose stretches of wall a letter covers ──
    teams = [for (final l in ls) _team(l)];
    slides = Float64List(nl);
    for (var k = 1; k < nl; k++) {
      // Built loose: a working gap, plus what kerning will take back.
      slides[k] = (math.max(0.3, 1.25 * b) + math.max(0.0, -ls[k].kernEm) * r.fontSize * b).clamp(0.3, 1.2);
    }
    spots = [
      for (var k = 0; k < nl; k++)
        () {
          final l = ls[k], m = teams[k].length;
          final cx = ((l.col0 + l.col1 + 1) / 2 - r.cols / 2) * b;
          final sp = math.max((l.col1 + 1 - l.col0) * b / m, 0.72);
          return Float64List.fromList([for (var j = 0; j < m; j++) cx + (j - (m - 1) / 2) * sp]);
        }(),
    ];

    // ── When each brick is laid: per letter, each member of its team takes
    // a band of columns bottom-up, a handful of bricks a swing ──
    final lay = Float64List(n);
    final member = Int8List(n);
    final byLetter = List.generate(nl, (_) => <int>[]);
    for (var i = 0; i < n; i++) {
      byLetter[letters.letterOf[i]].add(i);
    }
    for (var k = 0; k < nl; k++) {
      final l = ls[k], m = teams[k].length;
      final bands = List.generate(m, (_) => <int>[]);
      for (final i in byLetter[k]) {
        final bk = r.bricks[i];
        bands[((bk.col + 0.5 - l.col0) / (l.col1 + 1 - l.col0) * m).floor().clamp(0, m - 1)].add(i);
      }
      final a = at(sc.layA[k]), e = at(sc.layB[k]), dur = e - a;
      final swings = math.max(1, (dur / swing).floor());
      for (var j = 0; j < m; j++) {
        final list = bands[j]
          ..sort((x, y) {
            final bx = r.bricks[x], by = r.bricks[y];
            if (bx.row != by.row) return by.row - bx.row; // bottom row first
            // Back and forth along the rows.
            return bx.row.isEven ? bx.col - by.col : by.col - bx.col;
          });
        final c = list.length;
        if (c == 0) continue;
        final h = math.max(1, (c / swings).ceil()), hs = (c / h).ceil();
        final phase = 0.3 + 0.4 * ((j * 0.618) % 1.0);
        final stagger = math.min(0.05, 0.25 / h);
        for (var q = 0; q < c; q++) {
          lay[list[q]] = math.min(e - 0.02, a + dur * (q ~/ h + phase) / hs + (q % h) * stagger);
          member[list[q]] = j;
        }
      }
    }
    // Number the bricks in laying order.
    final order = List<int>.generate(n, (i) => i)
      ..sort((x, y) {
        final c = lay[x].compareTo(lay[y]);
        return c != 0 ? c : x - y;
      });
    src = Int32List.fromList(order);
    cellX = Float32List(n);
    cellY = Float32List(n);
    layT = Float64List(n);
    letter = Int16List(n);
    builder = Int8List(n);
    memberOf = Int8List(n);
    for (var i = 0; i < n; i++) {
      final o = order[i], k = r.bricks[o];
      cellX[i] = (k.col - r.cols / 2 + 0.5) * b;
      cellY[i] = (r.rows - k.row - 0.5) * b;
      layT[i] = lay[o];
      letter[i] = letters.letterOf[o];
      memberOf[i] = member[o];
      builder[i] = teams[letter[i]][member[o]];
    }
    letterStart = Int32List(nl + 1);
    for (var i = 0, k = 0; k <= nl; k++) {
      while (i < n && letter[i] < k) {
        i++;
      }
      letterStart[k] = i;
    }
    // Rows filled so far, per letter (for the platform).
    _rowCum = [
      for (var k = 0; k < nl; k++)
        () {
          final l = ls[k];
          final cum = Int32List(l.row1 - l.row0 + 2);
          for (var i = letterStart[k]; i < letterStart[k + 1]; i++) {
            cum[(cellY[i] / b).floor() - l.row0 + 1]++;
          }
          for (var j = 1; j < cum.length; j++) {
            cum[j] += cum[j - 1];
          }
          return cum;
        }(),
    ];
    _topBefore = Float64List(nl + 1);
    for (var k = 0; k < nl; k++) {
      _topBefore[k + 1] = math.max(_topBefore[k], (ls[k].row1 + 1) * b);
    }
    zoneX = Float32List(NameRaster.zones);
    for (var z = 0; z < NameRaster.zones; z++) {
      zoneX[z] = ((z + 0.5) / NameRaster.zones - 0.5) * r.cols * b;
    }
    zoneBricks = List.generate(NameRaster.zones, (_) => <int>[]);
    for (var i = 0; i < n; i++) {
      zoneBricks[builder[i]].add(i);
    }

    _planTrips();
    _planSteps();
    _planCrew();
  }

  final Job job;
  final NameRaster r;
  final NameLetters letters;

  /// Brick size.
  final double b;

  late final BuildSchedule sched;

  /// The schedule's time scale (the build's length over its natural one).
  late final double s;

  /// A natural schedule time as scene time.
  double at(double natural) => t0 + natural * s;

  /// Per brick (in laying order): its raster brick, its cell in place, when
  /// it's set in the wall, its letter, who lays it (and their place in the
  /// letter's team).
  late final Int32List src;
  late final Float32List cellX, cellY;
  late final Float64List layT;
  late final Int16List letter;
  late final Int8List builder, memberOf;

  /// Letter k's bricks are [letterStart] k … [letterStart] k + 1.
  late final Int32List letterStart;

  /// Per letter: its team (builder ids, left to right) and where they stand
  /// (x in place; the letter's [slides] on top while it's loose).
  late final List<List<int>> teams;
  late final List<Float64List> spots;

  /// How far right of its place each letter is built (0 for the first).
  late final Float64List slides;

  /// The middle of each builder's stretch of wall: where they wait when
  /// not needed.
  late final Float32List zoneX;

  /// The bricks each builder lays, in order.
  late final List<List<int>> zoneBricks;

  late final List<Int32List> _rowCum;
  late final Float64List _topBefore;

  /// The builders whose stretch of wall letter [l] covers well, left to
  /// right: at least two (a narrow letter gets the nearest neighbour too),
  /// and more for a big letter (a builder lays ~110 bricks at most).
  List<int> _team(WallLetter l) {
    const zones = NameRaster.zones;
    final zw = r.cols / zones, lw = (l.col1 + 1 - l.col0).toDouble();
    final out = <int>[];
    for (var z = 0; z < zones; z++) {
      final ov = math.min((z + 1) * zw, l.col1 + 1.0) - math.max(z * zw, l.col0.toDouble());
      if (ov > 0 && (ov >= 0.3 * zw || ov >= 0.5 * lw)) out.add(z);
    }
    final mid = (l.col0 + l.col1 + 1) / 2;
    double dist(int z) => ((z + 0.5) * zw - mid).abs();
    if (out.isEmpty) out.add((mid / zw).floor().clamp(0, zones - 1));
    final want = math.min(zones, math.max(2, (l.bricks / 110).ceil()));
    while (out.length < want) {
      final a = out.first - 1, e = out.last + 1;
      if (a >= 0 && (e >= zones || dist(a) <= dist(e))) {
        out.insert(0, a);
      } else {
        out.add(e);
      }
    }
    return out;
  }

  /// Height of the pallet's base above the platform when dropping.
  static const dropGap = 2.7;

  /// Seconds from a builder's pile to the wall.
  static const flight = 0.5;

  /// Seconds for a builder's swing (pile → wall), a handful at a time.
  static const swing = 0.8;

  int get total => r.bricks.length;
  int get letterCount => letters.length;
  double get width => r.cols * b;
  double get height => r.rows * b;

  /// Build start and length (the model's brick schedule).
  double get t0 => job.buildStart ?? (job.startedAt + phaseSeconds[Phase.intake]!);
  double get len => math.max(job.buildLen, 1);

  /// When brick [i] is set in the wall (absolute).
  double layAt(int i) => layT[i];

  /// Bricks set by [t] (those laid before: the first [laidBy]).
  int laidBy(double t) => _countTo(t, 0, total);

  int _countTo(double t, int lo, int hi) {
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (layT[mid] <= t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// The first brick not yet finally in the wall at [t] (the bounce over).
  int settledBy(double t) => laidBy(t - 0.25);

  /// The letter being built or kerned at [t] (the last one after the build).
  int letterAt(double t) {
    for (var k = 0; k < letterCount; k++) {
      if (t < at(sched.downB[k])) return k;
    }
    return letterCount - 1;
  }

  /// How far letter [k] is right of its place at [t].
  double offsetAt(int k, double t) => k <= 0 || k >= letterCount ? 0 : steps[k]!.offset(t);

  /// The middle of the letter at work at [t] (x, where it stands now).
  double activeX(double t) {
    final k = letterAt(t), l = letters.letters[k];
    return ((l.col0 + l.col1 + 1) / 2 - r.cols / 2) * b + offsetAt(k, t);
  }

  // ── Crane trips ───────────────────────────────────────────────────────────

  /// Trip k carries bricks [tripStart] k … [tripStart] k + 1 (a letter,
  /// a few small ones, or a share of a big one) and runs over [tripA,
  /// tripB) (relative to t0), done before they're needed. Trip 0 runs
  /// during the intake, as much of it as there is.
  late final int trips;
  late final Int32List tripStart;
  late final Float64List _tripA, _tripB;
  late final Int16List trip, pile, palletSlot;

  /// When each brick drops off the crane's pallet (relative to [t0]), and
  /// how long it falls.
  late final Float32List dropRel, fallTime;

  /// The piles on the platform: one per builder per trip, in front of
  /// where they stand ([pileX]); the crane visits them right to left at
  /// [pileVisit] through its trip. Brick i lands in pile [pileOf] i, at
  /// slot [pile] i (0 = bottom).
  late final Int16List pileOf;
  late final List<double> pileX, pileVisit;
  late final List<int> _pilePer, _pileBuilder;
  late final List<List<int>> _tripPiles;

  double tripA(int k) => _tripA[k];
  double tripB(int k) => _tripB[k];

  void _planTrips() {
    final n = total, nl = letterCount;
    // At most ~128 bricks a trip (eight layers on a pallet), and 12 trips
    // (the yard's pallet slots).
    var cap = 128;
    late List<int> bounds;
    for (var tries = 0; tries < 40; tries++) {
      bounds = [0];
      var open = 0;
      final merge = nl > 12 || tries > 0;
      for (var k = 0; k < nl; k++) {
        final a = letterStart[k], e = letterStart[k + 1], c = e - a;
        if (open > 0 && (!merge || open + c > cap)) {
          bounds.add(a);
          open = 0;
        }
        if (c > cap) {
          final parts = (c / cap).ceil();
          for (var p = 1; p < parts; p++) {
            bounds.add(a + c * p ~/ parts);
          }
          bounds.add(e);
        } else {
          open += c;
        }
      }
      if (bounds.last != n) bounds.add(n);
      if (bounds.length - 1 <= 12) break;
      cap = (cap * 1.25).ceil();
    }
    trips = math.max(1, bounds.length - 1);
    tripStart = Int32List.fromList(bounds.length >= 2 ? bounds : [0, n]);
    trip = Int16List(n);
    _tripA = Float64List(trips);
    _tripB = Float64List(trips);
    // Each trip done before its first brick is wanted at its pile, and the
    // crane does one trip at a time.
    for (var k = 0; k < trips; k++) {
      for (var i = tripStart[k]; i < tripStart[k + 1]; i++) {
        trip[i] = k;
      }
      final first = tripStart[k] < n ? layT[tripStart[k]] - t0 : len;
      var e = first - flight - 0.9;
      if (k == 0) {
        e = math.min(0, e);
        final avail = t0 + e - job.startedAt - 0.9;
        _tripA[0] = e - avail.clamp(2.5, 8.0);
      } else {
        e = math.max(e, _tripB[k - 1] + 3.5);
        _tripA[k] = math.max(_tripB[k - 1] + 0.4, e - 8.0);
      }
      _tripB[k] = e;
    }
    // Piles: per trip, one per builder and letter, beside where they stand.
    pileOf = Int16List(n);
    pile = Int16List(n);
    palletSlot = Int16List(n);
    dropRel = Float32List(n);
    fallTime = Float32List(n);
    pileX = <double>[];
    pileVisit = <double>[];
    _pilePer = <int>[];
    _pileBuilder = <int>[];
    _tripPiles = <List<int>>[];
    final members = <List<int>>[];
    for (var k = 0; k < trips; k++) {
      final ids = <int, int>{};
      for (var i = tripStart[k]; i < tripStart[k + 1]; i++) {
        final key = letter[i] * 16 + memberOf[i];
        final p = ids[key] ??= () {
          pileX.add(spots[letter[i]][memberOf[i]] + slides[letter[i]] + pileDx(k));
          pileVisit.add(0);
          _pilePer.add(6);
          _pileBuilder.add(builder[i]);
          members.add(<int>[]);
          return pileX.length - 1;
        }();
        pileOf[i] = p;
        members[p].add(i);
      }
      // The crane comes from the right: the rightmost pile first.
      final ps = ids.values.toList()..sort((a, c) => pileX[c].compareTo(pileX[a]));
      _tripPiles.add(ps);
      final step = math.min(0.088, 0.44 / math.max(1, ps.length - 1));
      for (var j = 0; j < ps.length; j++) {
        pileVisit[ps[j]] = 0.34 + j * step;
      }
      // Drop order: pile by pile; within a pile the last to be laid first,
      // so it ends up at the bottom. Pallet slots count from the top, so
      // the first dropped is on top.
      var sl = 0;
      final count = tripStart[k + 1] - tripStart[k];
      for (final p in ps) {
        final list = members[p];
        final c = list.length;
        // Two deep, wider rather than taller for a big batch.
        _pilePer[p] = c <= 24 ? 6 : (c <= 48 ? 8 : 10);
        final dt = math.min(0.06, 0.42 / math.max(c, 1));
        for (var j = c - 1; j >= 0; j--) {
          final i = list[j];
          pile[i] = c - 1 - j;
          palletSlot[i] = sl++;
          dropRel[i] = _tripA[k] + (_tripB[k] - _tripA[k]) * pileVisit[p] + (c - 1 - j) * dt;
          final palletLayer = (count - 1 - palletSlot[i]) ~/ 16;
          final h = dropGap + (palletLayer - pile[i] ~/ _pilePer[p]) * b;
          fallTime[i] = math.sqrt(2 * math.max(0.3, h) / SiteLayout.g);
        }
      }
    }
  }

  /// The trip running at [t] (absolute) and how far through it (0..1), or
  /// null between trips.
  (int, double)? tripAt(double t) {
    final rel = t - t0;
    for (var k = 0; k < trips; k++) {
      if (rel < _tripA[k]) return null;
      if (rel < _tripB[k]) return (k, c01((rel - _tripA[k]) / (_tripB[k] - _tripA[k])));
    }
    return null;
  }

  /// The last trip started by [t] (0 before the first).
  int tripNow(double t) {
    final rel = t - t0;
    var k = 0;
    while (k + 1 < trips && rel >= _tripA[k + 1]) {
      k++;
    }
    return k;
  }

  /// Hook height above a pallet's base: clear of its top layer.
  double hookAbove(int k) => 0.14 + layers(k) * b + 0.7;

  /// Where the hook waits over yard pallet [k].
  vm.Vector3 yardHook(int k) {
    final y = SiteLayout.yard(k);
    return vm.Vector3(y.x, hookAbove(k), y.z);
  }

  double _pathT = double.nan;
  final _path = vm.Vector3.zero();

  /// Hook position (world) on the crane's trips at [t]; between trips (and
  /// before the first), over the next yard pallet.
  vm.Vector3 hookPath(double t) {
    if (t == _pathT) return _path;
    _pathT = t;
    final at = tripAt(t);
    if (at == null) {
      final k = tripNow(t);
      _path.setFrom(yardHook(t - t0 < _tripA[k] ? k : math.min(k + 1, trips - 1)));
      return _path;
    }
    final (k, u) = at;
    _path.setFrom(_onTrip(k, u, t));
    return _path;
  }

  vm.Vector3 _onTrip(int k, double u, double t) {
    final deck = deckY(t);
    final low = yardHook(k);
    final high = vm.Vector3(low.x, math.max(8.5, deck + dropGap + hookAbove(k) + 2.5), low.z);
    vm.Vector3 over(int p) => vm.Vector3(pileX[p], deck + dropGap + hookAbove(k), SiteLayout.stashZ);
    final ps = _tripPiles[k];
    // (u, point, eased?)
    final keys = <(double, vm.Vector3, bool)>[
      (0.0, low, true),
      (0.1, low, true),
      (0.2, high, true),
      (pileVisit[ps.first] - 0.02, over(ps.first), true),
      for (final p in ps) (pileVisit[p], over(p), false),
      (pileVisit[ps.last] + 0.03, over(ps.last), true),
      (0.88, vm.Vector3(low.x, high.y, low.z), true),
      (0.94, low, true),
      (0.96, low, true),
      (1.0, yardHook(math.min(k + 1, trips - 1)), true),
    ];
    for (var i = 0; i + 1 < keys.length; i++) {
      final (ua, pa, _) = keys[i];
      final (ub, pb, eased) = keys[i + 1];
      if (u <= ub) {
        final f = ub > ua ? c01((u - ua) / (ub - ua)) : 1.0;
        return polarLerp(pa, pb, eased ? eio(f) : f);
      }
    }
    return keys.last.$2;
  }

  /// The hook's position when brick [i] dropped (worked out once per brick).
  vm.Vector3 hookAtDrop(int i, vm.Vector3 out) {
    if (_dropHook[3 * i].isNaN) {
      final t = t0 + dropRel[i];
      final at = tripAt(t);
      final p = at == null ? yardHook(trip[i]) : _onTrip(at.$1, at.$2, t);
      _dropHook
        ..[3 * i] = p.x
        ..[3 * i + 1] = p.y
        ..[3 * i + 2] = p.z;
    }
    return out..setValues(_dropHook[3 * i], _dropHook[3 * i + 1], _dropHook[3 * i + 2]);
  }

  late final _dropHook = Float32List(3 * total)..fillRange(0, 3 * total, double.nan);

  int tripCount(int k) => tripStart[k + 1] - tripStart[k];

  /// Layers of bricks on pallet [k] (4 × 4 per layer).
  int layers(int k) => (tripCount(k) + 15) ~/ 16;

  /// Where pallet [k]'s base is at [t]: in the yard, under the hook, or
  /// still on its way there ([palletOnTheWay]).
  vm.Vector3 palletBase(int k, double t) {
    final at = tripAt(t);
    if (at != null && at.$1 == k && at.$2 >= 0.1 && at.$2 < 0.94) {
      return hookPath(t) - vm.Vector3(0, hookAbove(k), 0);
    }
    if (palletOnTheWay?.call(k, t, _way) ?? false) return _way.base.clone();
    return SiteLayout.yard(k);
  }

  // ── Deliveries ────────────────────────────────────────────────────────────

  /// Where pallet [k] is at [t] while it's still on its way to the yard (on
  /// the delivery truck, or swinging off it): set by the site (see
  /// delivery.dart). It fills [out] and returns true, or returns false once
  /// the pallet stands in its [SiteLayout.yard] slot — as it must by its
  /// trip's pickup. The pallet's waiting bricks ride on it ([brickAt]).
  /// Unset, every pallet starts in the yard.
  bool Function(int k, double t, PalletPose out)? palletOnTheWay;
  final _way = PalletPose();

  /// x offset of a trip's piles from the builders (alternating sides, so a
  /// new batch doesn't land on the last one).
  double pileDx(int k) => (k.isEven ? -1 : 1) * (1.6 * b + 0.07);

  /// Slot [s] (0 = top of the stack) on a pallet of [count] bricks whose
  /// base centre is at [base].
  vm.Vector3 palletSlotPos(vm.Vector3 base, int s, int count, [vm.Vector3? out]) {
    final p = count - 1 - s; // from the bottom
    final layer = p ~/ 16, w = p % 16;
    return (out ?? vm.Vector3.zero())..setValues(base.x + ((w % 4) - 1.5) * b, base.y + 0.14 + (layer + 0.5) * b, base.z + ((w ~/ 4) - 1.5) * b);
  }

  /// Slot [s] (0 = bottom) of pile [p] on the deck at height [deck].
  vm.Vector3 pileSlot(int p, int s, double deck, [vm.Vector3? out]) {
    final per = _pilePer[p], across = per ~/ 2;
    final layer = s ~/ per, w = s % per;
    return (out ?? vm.Vector3.zero())..setValues(
      pileX[p] + ((w % across) - (across - 1) / 2) * b * 1.02,
      deck + 0.06 + (layer + 0.5) * b,
      SiteLayout.stashZ + ((w ~/ across) - 0.5) * b * 1.05,
    );
  }

  /// When the crane pours a batch onto one of builder [z]'s piles on trip
  /// [k] (absolute; the one nearest [t]), or null if none of them is theirs.
  double? dropFor(int z, int k, double t) {
    double? best;
    for (final p in _tripPiles[k]) {
      if (_pileBuilder[p] != z) continue;
      final d = t0 + _tripA[k] + (_tripB[k] - _tripA[k]) * pileVisit[p];
      if (best == null || (d - t).abs() < (best - t).abs()) best = d;
    }
    return best;
  }

  // ── Platform ──────────────────────────────────────────────────────────────

  /// Height of letter [k] built by [t] (its feet before the first row).
  double _levelOf(int k, double t) {
    final l = letters.letters[k], cum = _rowCum[k];
    final a = letterStart[k], e = letterStart[k + 1];
    final c = _countTo(t, a, e) - a;
    if (c <= 0) return l.row0 * b;
    if (c >= e - a) return (l.row1 + 1) * b;
    var j = 0;
    while (j + 2 < cum.length && cum[j + 1] <= c) {
      j++;
    }
    final f = cum[j + 1] > cum[j] ? (c - cum[j]) / (cum[j + 1] - cum[j]) : 0.0;
    return (l.row0 + j + f) * b;
  }

  double _levelT = double.nan, _level = 0;

  /// Height of the wall built by [t]: the tallest letter so far.
  double level(double t) {
    if (t == _levelT) return _level;
    _levelT = t;
    final k = letterAt(t);
    final now = t >= at(sched.layA[k]) ? _levelOf(k, t) : 0.0;
    return _level = math.max(_topBefore[k], now);
  }

  double _deckT = double.nan, _deck = 0;

  /// The climbing platform's floor: down when a team boards, climbing with
  /// the letter as it's laid, at the kerning height for the kerning, down
  /// again after (0 before and after the build).
  double deckY(double t) {
    if (t == _deckT) return _deck;
    _deckT = t;
    return _deck = _deckAt(t);
  }

  double _deckAt(double t) {
    if (t < t0) return 0;
    final sc = sched;
    for (var k = 0; k < letterCount; k++) {
      final down = at(sc.downB[k]);
      if (t >= down) continue;
      final la = at(sc.layA[k]), lb = at(sc.layB[k]);
      final rise = BuildSchedule.move(0, sc.h0[k]) * s;
      if (t < la - rise) return 0;
      if (t < la) return sc.h0[k] * eio(seg(t, la - rise, la));
      if (t < lb) return BuildSchedule.stepDeck(_levelOf(k, t));
      if (k == 0) return sc.hTop[k] * (1 - eio(seg(t, lb, down)));
      final ka = at(sc.kernA[k]), kb = at(sc.kernB[k]);
      if (t < ka) return lerp(sc.hTop[k], sc.hKern[k], eio(seg(t, lb, ka)));
      if (t < kb) return sc.hKern[k];
      return sc.hKern[k] * (1 - eio(seg(t, kb, down)));
    }
    return 0;
  }

  // ── Bricks ────────────────────────────────────────────────────────────────

  final _a = vm.Vector3.zero(), _b = vm.Vector3.zero(), _h = vm.Vector3.zero();

  /// Where brick [i] is at [t], how big, and whether it just landed.
  BrickPose brickAt(int i, double t, BrickPose out) {
    final lay = layT[i];
    final k = trip[i];
    out
      ..landing = -1
      ..scale = 1
      ..spin = 0
      ..yaw = 0
      ..spinAxis = (src[i] * 7) % 3;
    if (t >= lay) {
      // In the wall, with a small bounce just after landing.
      final u = (t - lay) / 0.24;
      out.pos.setValues(cellX[i] + offsetAt(letter[i], t), cellY[i], 0);
      if (u < 1) {
        out.pos.y += 0.32 * b * math.max(0, math.sin(u * math.pi * 1.5)) * (1 - u);
        out.scale = 1 + 0.2 * (1 - u) * (1 - u);
        out.landing = u;
      }
      return out;
    }
    if (t >= lay - flight) {
      // From the pile to the wall, over the builder's shoulder.
      final f = (t - (lay - flight)) / flight;
      pileSlot(pileOf[i], pile[i], deckY(lay - flight), _a);
      final tx = cellX[i] + offsetAt(letter[i], lay);
      final e = eio(f);
      out.pos.setValues(_a.x + (tx - _a.x) * e, _a.y + (cellY[i] - _a.y) * e + (0.5 + b) * math.sin(f * math.pi), _a.z + (0 - _a.z) * e);
      out.spin = (1 - e) * 3.1;
      return out;
    }
    final drop = t0 + dropRel[i];
    final fall = fallTime[i];
    if (t >= drop) {
      pileSlot(pileOf[i], pile[i], deckY(t), _b);
      final f = (t - drop) / fall;
      if (f >= 1) {
        out.pos.setFrom(_b);
        final u = (t - drop - fall) / 0.3;
        if (u < 1) {
          out.pos.y += 0.1 * math.max(0, math.sin(u * math.pi)) * (1 - u);
          out.landing = u;
        }
        return out;
      }
      onPallet(i, hookAtDrop(i, _h), _a);
      // Ballistic: a glide across, gravity down.
      out.pos.setValues(_a.x + (_b.x - _a.x) * eo(f), _a.y - (_a.y - _b.y) * f * f, _a.z + (_b.z - _a.z) * eo(f));
      out.spin = f * 4;
      return out;
    }
    final a = t0 + _tripA[k], e = t0 + _tripB[k];
    final pickup = a + (e - a) * 0.1;
    if (t >= pickup) {
      onPallet(i, hookPath(t), out.pos);
      return out;
    }
    // Still on its way to the yard (on the delivery truck): on its pallet.
    if (palletOnTheWay?.call(k, t, _way) ?? false) {
      palletSlotPos(_way.base, palletSlot[i], tripCount(k), out.pos);
      _way.turn(out.pos);
      out
        ..yaw = _way.yaw
        ..scale = _way.shown ? 1 : 0;
      return out;
    }
    // Waiting on its pallet in the yard, popping in as the raster arrives.
    final pop = c01((t - appearAt(i)) / 0.3);
    if (pop <= 0) {
      out.scale = 0;
      return out;
    }
    out.scale = pop < 1 ? eo(pop) * (1 + 0.3 * math.sin(pop * math.pi)) : 1;
    palletSlotPos(SiteLayout.yard(k), palletSlot[i], tripCount(k), out.pos);
    return out;
  }

  /// When brick [i] pops into the yard (the raster arriving brick by brick).
  double appearAt(int i) {
    final k = trip[i];
    final pickup = t0 + _tripA[k] + (_tripB[k] - _tripA[k]) * 0.1;
    return math.min(pickup - 0.4, job.startedAt + 0.6 + 3.4 * i / total);
  }

  /// Brick [i]'s place on its pallet hanging from a hook at [hook].
  vm.Vector3 onPallet(int i, vm.Vector3 hook, [vm.Vector3? out]) {
    final k = trip[i];
    _base.setValues(hook.x, hook.y - hookAbove(k), hook.z);
    return palletSlotPos(_base, palletSlot[i], tripCount(k), out);
  }

  final _base = vm.Vector3.zero();

  /// When brick [i] lands in its pile (absolute).
  double pileLandAt(int i) => t0 + dropRel[i] + fallTime[i];

  // ── Kerning ───────────────────────────────────────────────────────────────

  /// The kerning step of each letter after the first (null for the first).
  late final List<KernStep?> steps;

  /// The kerning step running at [t] (from the crew walking over to the
  /// end), or null.
  KernStep? stepAt(double t) {
    for (final st in steps) {
      if (st != null && t >= st.a && t < st.e) return st;
    }
    return null;
  }

  void _planSteps() {
    final ls = letters.letters, sc = sched;
    steps = [
      for (var k = 0; k < letterCount; k++)
        if (k == 0)
          null
        else
          () {
            final st = KernStep._(k, sc.full[k]).._times(at(sc.kernA[k]), at(sc.kernB[k]));
            final p = ls[k - 1], l = ls[k], row = sc.tapeRow[k];
            final team = teams[k], m = team.length;
            st
              ..left = p.text
              ..right = l.text
              ..em = l.kernEm
              ..slide = slides[k]
              ..gapL = (p.edge(1, row - 1, row + 1) + 1 - r.cols / 2) * b
              ..gapR = (l.edge(-1, row - 1, row + 1) - r.cols / 2) * b
              ..tapeY = sc.tapeY(k)
              ..deck = sc.hKern[k];
            // The pushers lean on the letter's right edge at hand height.
            var pr = (((st.deck + 0.8) / b) - 0.5).round().clamp(l.row0, l.row1);
            for (var d = 0; d <= l.row1 - l.row0; d++) {
              if (pr + d <= l.row1 && l.right[pr + d] >= 0) {
                pr += d;
                break;
              }
              if (pr - d >= l.row0 && l.right[pr - d] >= 0) {
                pr -= d;
                break;
              }
            }
            st
              ..pushY = (pr + 0.5) * b
              ..pushX = ((l.right[pr] >= 0 ? l.right[pr] : l.col1) + 1 - r.cols / 2) * b
              ..hook = team.first
              ..holdCase = st.full ? team[1] : -1
              ..push1 = team.last
              ..push2 = m >= 3 ? team[m - 2] : (st.full ? team.first : -1);
            return st;
          }(),
    ];
  }

  // ── Who's needed where ────────────────────────────────────────────────────

  late final List<List<(double, double)>> _windows;
  late final List<List<_Leg>> _legs;

  /// Where builder [z] waits when not needed: the middle of their stretch,
  /// on the platform.
  double restX(int z) => zoneX[z];

  void _planCrew() {
    final sc = sched, nl = letterCount;
    _windows = List.generate(NameRaster.zones, (_) => <(double, double)>[]);
    _legs = List.generate(NameRaster.zones, (_) => <_Leg>[]);
    const cz = SiteLayout.crewZ, kz = SiteLayout.kernZ;
    for (var z = 0; z < NameRaster.zones; z++) {
      final mine = [
        for (var k = 0; k < nl; k++)
          if (teams[k].contains(z)) k,
      ];
      final legs = _legs[z];
      var i = 0;
      while (i < mine.length) {
        // A run of consecutive letters is one window.
        var j = i;
        while (j + 1 < mine.length && mine[j + 1] == mine[j] + 1) {
          j++;
        }
        final from = mine[i] == 0 ? t0 - 1.0 : at(sc.downB[mine[i] - 1]);
        for (var q = i; q <= j; q++) {
          final k = mine[q], m = teams[k].indexOf(z);
          final x = spots[k][m];
          legs.add(_Leg(q == i ? from : at(sc.downB[k - 1]), x, cz, CrewMode.work, follow: k, letter: k));
          final st = steps[k];
          if (st == null) {
            legs.add(_Leg(at(sc.layB[k]), x, cz, CrewMode.watch, follow: k, letter: k));
            continue;
          }
          final px1 = st.pushX + 0.42, px2 = st.pushX + 0.42 + 0.5;
          final pushMode = z == st.push1 ? CrewMode.push1 : (z == st.push2 ? CrewMode.push2 : null);
          final pushX = z == st.push1 ? px1 : px2;
          if (z == st.hook) {
            legs.add(_Leg(st.a, st.gapL - 0.45, kz, CrewMode.hook, letter: k));
            if (pushMode != null) legs.add(_Leg(st.checkB, pushX, kz, pushMode, follow: k, letter: k));
          } else if (z == st.holdCase) {
            legs.add(_Leg(st.a, st.gapR + 0.45, kz, CrewMode.holdCase, follow: k, letter: k));
            legs.add(
              pushMode != null ? _Leg(st.checkB, pushX, kz, pushMode, follow: k, letter: k) : _Leg(st.checkB, x, cz, CrewMode.watch, follow: k, letter: k),
            );
          } else if (pushMode != null) {
            legs.add(_Leg(st.a, pushX, kz, pushMode, follow: k, letter: k));
          } else {
            legs.add(_Leg(st.a, x, cz, CrewMode.watch, follow: k, letter: k));
          }
          legs.add(_Leg(st.retractB, x, cz, CrewMode.watch, follow: k, letter: k));
        }
        // Back to their rest spot once the platform is down.
        final last = mine[j];
        final down = at(sc.downB[last]);
        final end = last == nl - 1 ? t0 + len : down + 1.5 * s;
        legs.add(_Leg(down, restX(z), cz, CrewMode.free, until: end));
        _windows[z].add((from, end));
        i = j + 1;
      }
      // How long each walk takes: at a walking pace, but there before the
      // next move.
      var px = restX(z), pz = cz;
      for (var q = 0; q < legs.length; q++) {
        final leg = legs[q];
        final tx = leg.x + offsetAt(leg.follow, leg.t);
        final d = math.sqrt((tx - px) * (tx - px) + (leg.z - pz) * (leg.z - pz));
        final room = math.min(q + 1 < legs.length ? legs[q + 1].t : 1e9, leg.until) - leg.t - 0.05;
        leg.walk = math.min(d / 2.2, math.max(0.05, room));
        px = tx;
        pz = leg.z;
      }
    }
  }

  /// When builder [z] has to be on the platform (absolute [from, to)
  /// windows, in order). A window runs from the platform coming down before
  /// the first letter of a run of consecutive letters they work on (2.5 s
  /// before its first brick, at the normal pace) to the platform coming
  /// down after the last one is laid and kerned, plus their walk back to
  /// their rest spot. Outside them they're free: a coffee, a smoke, a chat.
  ///
  /// Guaranteed, for every window:
  /// - At its start and its end the platform is down (its floor at ground
  ///   level) and the builder is at their rest spot on it ([restX], at
  ///   [SiteLayout.crewZ]; Crew3D's work spot for them): they step on and
  ///   off there. It stays down from the start until 2.5 s on, and for
  ///   about a second after the end (both × the build's pace, [s]).
  /// - It only leaves the ground inside the windows of the builders on it.
  /// - The first window may start up to 1 s before the build (everyone is
  ///   walking onto the platform in the intake), and the last letter's
  ///   team's ends with the build, everybody back at their rest spots for
  ///   the reveal.
  ///
  /// Outside their windows, without a break to go to, builders wait at
  /// their rest spot on the platform (and ride it).
  List<(double, double)> busyWindows(int z) => _windows[z];

  /// Whether builder [z] is needed on the platform at [t].
  bool busy(int z, double t) => busyWindows(z).any((w) => t >= w.$1 && t < w.$2);

  /// When builder [z] is next needed at or after [t], or null if not again
  /// in this build.
  double? nextBusy(int z, double t) {
    for (final (a, e) in busyWindows(z)) {
      if (t < e) return math.max(a, t);
    }
    return null;
  }

  /// The timeline in words (scene seconds): letters, kerning steps, who's
  /// busy when, the crane's trips. For the capture log.
  String describe() {
    String f(double v) => v.toStringAsFixed(1);
    final sc = sched, out = StringBuffer();
    out.writeln('plan ${job.name}: build ${f(t0)}–${f(t0 + len)} (${f(len)} s, natural ${f(sc.natural)}), $total bricks, b ${b.toStringAsFixed(3)}');
    for (var k = 0; k < letterCount; k++) {
      final l = letters.letters[k], st = steps[k];
      out.write('  ${l.text}  ${l.bricks} bricks  team ${teams[k].join(',')}  laid ${f(at(sc.layA[k]))}–${f(at(sc.layB[k]))}');
      if (st != null) {
        out.write('  kern ${st.left}${st.right} ${st.em.toStringAsFixed(3)} em ${st.full ? 'close-up' : 'quick'} ${f(st.a)}–${f(st.e)}');
        out.write(' (push ${f(st.pushA)}–${f(st.pushB)}, slide ${st.slide.toStringAsFixed(2)} m)');
      }
      out.writeln('  platform down ${f(at(sc.downB[k]))}');
    }
    for (var z = 0; z < NameRaster.zones; z++) {
      out.writeln('  builder $z busy ${busyWindows(z).map((w) => '${f(w.$1)}–${f(w.$2)}').join(', ')}');
    }
    for (var k = 0; k < trips; k++) {
      out.writeln('  trip $k ${f(t0 + tripA(k))}–${f(t0 + tripB(k))}: ${tripCount(k)} bricks');
    }
    return out.toString();
  }

  /// Where builder [z] is at [t] and what they're doing (in the build).
  CrewPlace crewAt(int z, double t, CrewPlace out) {
    final legs = _legs[z];
    var lo = 0, hi = legs.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (legs[mid].t <= t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final q = lo - 1;
    if (q < 0) {
      out
        ..x = restX(z)
        ..z = SiteLayout.crewZ
        ..walking = false
        ..heading = 0
        ..mode = CrewMode.free
        ..letter = -1;
      return out;
    }
    final leg = legs[q];
    final tx = leg.x + offsetAt(leg.follow, t), tz = leg.z;
    out
      ..mode = leg.mode
      ..letter = leg.letter
      ..walking = false
      ..x = tx
      ..z = tz;
    final f = leg.walk > 0 ? (t - leg.t) / leg.walk : 1.0;
    if (f < 1) {
      final prev = q > 0 ? legs[q - 1] : null;
      final fx = prev == null ? restX(z) : prev.x + offsetAt(prev.follow, leg.t);
      final fz = prev?.z ?? SiteLayout.crewZ;
      final e = smooth(0, 1, f);
      out
        ..x = fx + (tx - fx) * e
        ..z = fz + (tz - fz) * e;
      if ((tx - fx).abs() + (tz - fz).abs() > 0.06) {
        out
          ..walking = true
          ..heading = math.atan2(-(tx - fx), -(tz - fz));
      }
    }
    return out;
  }
}

/// A brick's place, size and spin at one moment.
class BrickPose {
  final pos = vm.Vector3.zero();
  double scale = 1;
  double spin = 0;
  int spinAxis = 0;

  /// Turned about y with its pallet (on the delivery truck; a quarter turn
  /// looks the same).
  double yaw = 0;

  /// 0..1 through a landing bounce, or -1.
  double landing = -1;
}

/// Where a pallet is on its way to the yard: its base centre, how it's
/// turned (radians about y, as `setTrs`' yaw) and whether it's in view.
class PalletPose {
  final base = vm.Vector3.zero();
  double yaw = 0;
  bool shown = true;

  /// Turns [p] (placed round [base] as if unturned) with the pallet.
  void turn(vm.Vector3 p) {
    if (yaw == 0) return;
    final c = math.cos(yaw), s = math.sin(yaw);
    final dx = p.x - base.x, dz = p.z - base.z;
    p
      ..x = base.x + dx * c + dz * s
      ..z = base.z - dx * s + dz * c;
  }
}

/// Interpolates two hook positions the way a tower crane moves between
/// them: slewing around the mast, trolleying along the jib, hoisting.
vm.Vector3 polarLerp(vm.Vector3 a, vm.Vector3 b, double f) {
  const mx = SiteLayout.mastX, mz = SiteLayout.mastZ;
  final ra = math.sqrt((a.x - mx) * (a.x - mx) + (a.z - mz) * (a.z - mz));
  final rb = math.sqrt((b.x - mx) * (b.x - mx) + (b.z - mz) * (b.z - mz));
  final ta = math.atan2(a.z - mz, a.x - mx);
  var tb = math.atan2(b.z - mz, b.x - mx);
  while (tb - ta > math.pi) {
    tb -= 2 * math.pi;
  }
  while (tb - ta < -math.pi) {
    tb += 2 * math.pi;
  }
  final th = ta + (tb - ta) * f, rr = ra + (rb - ra) * f;
  // The hoist leads a little going up and lags coming down.
  final fy = b.y > a.y ? eo(c01(f * 1.25)) : f * f * (3 - 2 * f);
  return vm.Vector3(mx + math.cos(th) * rr, a.y + (b.y - a.y) * fy, mz + math.sin(th) * rr);
}
