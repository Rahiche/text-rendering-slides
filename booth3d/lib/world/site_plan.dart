import 'dart:math' as math;
import 'dart:typed_data';

import 'package:text_slides/booth/model.dart';
import 'package:text_slides/booth/raster.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';

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
  /// [crewZ], facing the wall.
  static const deckZ0 = 0.3, deckZ1 = 1.9, stashZ = 0.74, crewZ = 1.38;

  /// Gravity for everything that falls.
  static const g = 9.8;
}

/// The build choreography for one name, as pure functions of scene time:
/// every brick's journey (yard pallet → crane → a builder's pile on the
/// platform → the builder's hands → its cell in the wall), the crane's
/// trips, and the platform's height. Pure, so frames, fast-forward and
/// capture always agree.
class BuildPlan {
  BuildPlan(this.job, this.r, this.b) {
    final n = r.bricks.length;
    cellX = Float32List(n);
    cellY = Float32List(n);
    zone = Int8List(n);
    trip = Int16List(n);
    pile = Int16List(n);
    palletSlot = Int16List(n);
    dropRel = Float32List(n);
    fallTime = Float32List(n);
    for (var i = 0; i < n; i++) {
      final k = r.bricks[i];
      cellX[i] = (k.col - r.cols / 2 + 0.5) * b;
      cellY[i] = (r.rows - k.row - 0.5) * b;
      zone[i] = k.zone;
    }
    // Rows from the bottom: where each starts in the build order.
    rowStart = Int32List(r.rows + 1);
    var rr = 0;
    for (var i = 0; i < n; i++) {
      final row = r.rows - 1 - r.bricks[i].row;
      while (rr < row) {
        rowStart[++rr] = i;
      }
    }
    while (rr < r.rows) {
      rowStart[++rr] = n;
    }
    zoneX = Float32List(NameRaster.zones);
    for (var z = 0; z < NameRaster.zones; z++) {
      zoneX[z] = ((z + 0.5) / NameRaster.zones - 0.5) * r.cols * b;
    }
    // Trips: one crane round per ~10 s of building.
    trips = (len / 10).round().clamp(1, 12);
    tripStart = Int32List(trips + 1);
    for (var k = 0; k <= trips; k++) {
      tripStart[k] = math.min(n, (n * k + trips - 1) ~/ trips);
    }
    for (var k = 0; k < trips; k++) {
      final a = tripStart[k], e = tripStart[k + 1];
      final byZone = List.generate(NameRaster.zones, (_) => <int>[]);
      for (var i = a; i < e; i++) {
        trip[i] = k;
        byZone[zone[i]].add(i);
      }
      // Drop order: zone 5 (nearest the crane) first; within a zone, the
      // last to be laid first, so it ends up at the bottom of the pile.
      // Pallet slots count from the top, so the first dropped is on top.
      var s = 0;
      final count = e - a;
      for (var z = NameRaster.zones - 1; z >= 0; z--) {
        final list = byZone[z];
        final c = list.length;
        final dt = math.min(0.06, 0.42 / math.max(c, 1));
        for (var j = c - 1; j >= 0; j--) {
          final i = list[j];
          pile[i] = c - 1 - j;
          palletSlot[i] = s++;
          dropRel[i] = tripA(k) + (tripB(k) - tripA(k)) * visit(z) + (c - 1 - j) * dt;
          final palletLayer = (count - 1 - palletSlot[i]) ~/ 16;
          final h = dropGap + (palletLayer - pile[i] ~/ 6) * b;
          fallTime[i] = math.sqrt(2 * math.max(0.3, h) / SiteLayout.g);
        }
      }
    }
    zoneBricks = List.generate(NameRaster.zones, (_) => <int>[]);
    for (var i = 0; i < n; i++) {
      zoneBricks[zone[i]].add(i);
    }
  }

  final Job job;
  final NameRaster r;

  /// Brick size.
  final double b;

  late final Float32List cellX, cellY;
  late final Int8List zone;
  late final Int16List trip, pile, palletSlot;

  /// When each brick drops off the crane's pallet (relative to [t0]), and
  /// how long it falls.
  late final Float32List dropRel, fallTime;
  late final Int32List rowStart;
  late final Float32List zoneX;
  late final List<List<int>> zoneBricks;
  late final int trips;
  late final Int32List tripStart;

  /// Height of the pallet's base above the platform when dropping.
  static const dropGap = 2.7;

  /// Seconds from a builder's pile to the wall.
  static const flight = 0.5;

  int get total => r.bricks.length;
  double get width => r.cols * b;
  double get height => r.rows * b;

  /// Build start and length (the model's brick schedule).
  double get t0 => job.buildStart ?? (job.startedAt + phaseSeconds[Phase.intake]!);
  double get len => math.max(job.buildLen, 1);
  double get tripLen => len / trips;

  /// When brick [i] is set in the wall (absolute).
  double layAt(int i) => t0 + len * i / total;

  /// Bricks laid by [t] (fractional, for smooth levels).
  double laidF(double t) => total * c01((t - t0) / len);

  // ── Crane trips ───────────────────────────────────────────────────────────

  /// Trip k runs over [tripA, tripB) (relative to t0), during the lay
  /// window before the one its bricks are laid in. Trip 0 runs during the
  /// intake, as much of it as there is.
  double tripA(int k) {
    if (k > 0) return (k - 1) * tripLen;
    final avail = t0 - job.startedAt - 0.9;
    return -avail.clamp(2.5, tripLen);
  }

  double tripB(int k) => k * tripLen;

  /// Fraction of a trip when the hook passes over zone [z]'s piles.
  static double visit(int z) => 0.34 + (NameRaster.zones - 1 - z) * 0.088;

  /// The trip running at [t] (absolute) and how far through it (0..1), or
  /// null outside the trips.
  (int, double)? tripAt(double t) {
    final rel = t - t0;
    if (rel < tripA(0) || rel >= tripB(trips - 1)) return null;
    final k = rel < 0 ? 0 : math.min(trips - 1, (rel / tripLen).floor() + 1);
    final a = tripA(k), e = tripB(k);
    return (k, c01((rel - a) / (e - a)));
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
  /// before the first), over the first or last yard pallet.
  vm.Vector3 hookPath(double t) {
    if (t == _pathT) return _path;
    _pathT = t;
    final at = tripAt(t);
    if (at == null) {
      _path.setFrom(t - t0 < tripA(0) ? yardHook(0) : yardHook(trips - 1));
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
    vm.Vector3 over(int z) => vm.Vector3(zoneX[z] + pileDx(k), deck + dropGap + hookAbove(k), SiteLayout.stashZ);
    // (u, point, eased?)
    final keys = <(double, vm.Vector3, bool)>[
      (0.0, low, true),
      (0.1, low, true),
      (0.2, high, true),
      (visit(5) - 0.02, over(5), true),
      for (var z = 4; z >= 0; z--) (visit(z), over(z), false),
      (visit(0) + 0.03, over(0), true),
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

  /// The hook's position when brick [i] dropped (not memoised).
  vm.Vector3 hookAtDrop(int i) {
    final t = t0 + dropRel[i];
    final at = tripAt(t);
    return at == null ? yardHook(trip[i]) : _onTrip(at.$1, at.$2, t);
  }

  int tripCount(int k) => tripStart[k + 1] - tripStart[k];

  /// Layers of bricks on pallet [k] (4 × 4 per layer).
  int layers(int k) => (tripCount(k) + 15) ~/ 16;

  /// Where pallet [k]'s base is at [t]: in the yard, or under the hook.
  vm.Vector3 palletBase(int k, double t) {
    final at = tripAt(t);
    if (at != null && at.$1 == k && at.$2 >= 0.1 && at.$2 < 0.94) {
      return hookPath(t) - vm.Vector3(0, hookAbove(k), 0);
    }
    return SiteLayout.yard(k);
  }

  /// x offset of a trip's pile (two piles per zone, alternating trips).
  double pileDx(int k) => (k.isEven ? -1 : 1) * (1.6 * b + 0.07);

  /// Slot [s] (0 = top of the stack) on a pallet of [count] bricks whose
  /// base centre is at [base].
  vm.Vector3 palletSlotPos(vm.Vector3 base, int s, int count, [vm.Vector3? out]) {
    final p = count - 1 - s; // from the bottom
    final layer = p ~/ 16, w = p % 16;
    return (out ?? vm.Vector3.zero())..setValues(base.x + ((w % 4) - 1.5) * b, base.y + 0.14 + (layer + 0.5) * b, base.z + ((w ~/ 4) - 1.5) * b);
  }

  /// Slot [p] (0 = bottom) of zone [z]'s pile for trip [k], on the deck.
  vm.Vector3 pileSlot(int z, int k, int p, double deck, [vm.Vector3? out]) {
    final layer = p ~/ 6, w = p % 6;
    return (out ?? vm.Vector3.zero())..setValues(
      zoneX[z] + pileDx(k) + ((w % 3) - 1) * b * 1.02,
      deck + 0.06 + (layer + 0.5) * b,
      SiteLayout.stashZ + ((w ~/ 3) - 0.5) * b * 1.05,
    );
  }

  // ── Platform ──────────────────────────────────────────────────────────────

  double _levelT = double.nan, _level = 0;

  /// Height of the wall built by [t].
  double level(double t) {
    if (t == _levelT) return _level;
    _levelT = t;
    final nf = laidF(t);
    var rr = 0;
    while (rr < r.rows && rowStart[rr + 1] <= nf) {
      rr++;
    }
    if (rr >= r.rows) return _level = r.rows * b;
    final a = rowStart[rr], e = rowStart[rr + 1];
    final f = e > a ? (nf - a) / (e - a) : 0.0;
    return _level = (rr + f) * b;
  }

  double _deckT = double.nan, _deck = 0;

  /// The climbing platform's floor: it lifts a step whenever the wall gets
  /// out of comfortable reach (0 before the build).
  double deckY(double t) {
    if (t == _deckT) return _deck;
    _deckT = t;
    if (t < t0) return _deck = 0;
    const step = 0.8;
    final x = math.max(0.0, level(t) - 0.45) / step;
    final k = x.floorToDouble();
    // Rises during the last 20% of each interval, smoothly.
    final f = seg(x - k, 0.8, 1.0);
    return _deck = (k + eio(f)) * step;
  }

  // ── Bricks ────────────────────────────────────────────────────────────────

  final _a = vm.Vector3.zero(), _b = vm.Vector3.zero();

  /// Where brick [i] is at [t], how big, and whether it just landed.
  BrickPose brickAt(int i, double t, BrickPose out) {
    final lay = layAt(i);
    final k = trip[i];
    out
      ..landing = -1
      ..scale = 1
      ..spin = 0
      ..spinAxis = (i * 7) % 3;
    if (t >= lay) {
      // In the wall, with a small bounce just after landing.
      final u = (t - lay) / 0.24;
      out.pos.setValues(cellX[i], cellY[i], 0);
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
      pileSlot(zone[i], k, pile[i], deckY(lay - flight), _a);
      final e = eio(f);
      out.pos.setValues(
        _a.x + (cellX[i] - _a.x) * e,
        _a.y + (cellY[i] - _a.y) * e + (0.5 + b) * math.sin(f * math.pi),
        _a.z + (0 - _a.z) * e,
      );
      out.spin = (1 - e) * 3.1;
      return out;
    }
    final drop = t0 + dropRel[i];
    final fall = fallTime[i];
    if (t >= drop) {
      pileSlot(zone[i], k, pile[i], deckY(t), _b);
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
      onPallet(i, hookAtDrop(i), _a);
      // Ballistic: a glide across, gravity down.
      out.pos.setValues(
        _a.x + (_b.x - _a.x) * eo(f),
        _a.y - (_a.y - _b.y) * f * f,
        _a.z + (_b.z - _a.z) * eo(f),
      );
      out.spin = f * 4;
      return out;
    }
    final a = t0 + tripA(k), e = t0 + tripB(k);
    final pickup = a + (e - a) * 0.1;
    if (t >= pickup) {
      onPallet(i, hookPath(t), out.pos);
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
    final pickup = t0 + tripA(k) + (tripB(k) - tripA(k)) * 0.1;
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

  /// The first brick not yet finally in the wall at [t] (the bounce over).
  int settledBy(double t) => math.min(total, math.max(0, ((t - 0.25 - t0) / len * total).floor()));

  // ── Who's needed when ─────────────────────────────────────────────────────

  /// When builder [z] has to be at their place on the platform (absolute
  /// [from, to) windows, in order). Outside them they're free: a coffee, a
  /// smoke, a chat (see the crew's breaks). For now the whole build.
  List<(double, double)> busyWindows(int z) => _busy[z] ??= [if (zoneBricks[z].isNotEmpty) (t0 - 1.5, t0 + len)];
  final _busy = <int, List<(double, double)>>{};

  /// Whether builder [z] is needed at the wall at [t].
  bool busy(int z, double t) => busyWindows(z).any((w) => t >= w.$1 && t < w.$2);

  /// When builder [z] is next needed at or after [t], or null if not again
  /// in this build.
  double? nextBusy(int z, double t) {
    for (final (a, e) in busyWindows(z)) {
      if (t < e) return math.max(a, t);
    }
    return null;
  }
}

/// A brick's place, size and spin at one moment.
class BrickPose {
  final pos = vm.Vector3.zero();
  double scale = 1;
  double spin = 0;
  int spinAxis = 0;

  /// 0..1 through a landing bounce, or -1.
  double landing = -1;
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
