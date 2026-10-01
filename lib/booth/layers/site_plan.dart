import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../layout.dart';
import '../model.dart';
import '../raster.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The construction site's geometry and schedule for one name.
//
// [SitePlan] is everything that follows from the raster (wall, zones,
// scaffold lifts). [BuildPlan] adds the timing: the shared brick schedule
// from the model, and the crane's trips (which pallets go together, when
// they are hooked, where they land on the scaffold). Both are immutable once
// made, so painters and the simulation can read them freely.
// ─────────────────────────────────────────────────────────────────────────────

/// Pallets slide off the belt's end (at [BL.pickup]) onto this landing and
/// stack up until the crane takes them.
const stageX = 638.0;

/// A pallet: 6×4 bricks on a wooden base.
const palletW = 24.0;
const palletH = 18.0;

/// Bottom of a pallet standing on the belt or the landing.
const palletFloor = 685.0;

/// Seconds a pallet takes to slide from the pickup onto the landing stack.
const hopTime = 0.35;

/// Seconds to hook / unhook a load.
const attachTime = 0.3;
const releaseTime = 0.3;

/// A brick leaves its pallet this long before it is set in the wall.
const pickLead = 0.65;

/// Seconds a brick travels from a builder's hands into its cell.
const flightTime = 0.5;

/// Slings between the hook and the top of a load.
const slingH = 14.0;

/// Where the hoist cables leave the trolley.
const trolleyY = BL.craneJibY + 8;

/// Wrecking ball: radius, chain under the hook, where it rests.
const ballR = 15.0;
const ballChain = 12.0;
const ballParkX = 1500.0;

/// Builders' height in px.
const crewH = 30.0;

/// The crew's hard hats, one per zone.
const zoneCount = NameRaster.zones;

/// Bottom of the hook block when a load of height [h] hangs with its base
/// at [base].
double hookFor(double base, double h) => base - h - slingH;

/// Rubble falls and settles with this gravity (px/s²).
const gravity = 1500.0;

double c01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
double seg(double t, double a, double b) => b <= a ? (t >= b ? 1 : 0) : c01((t - a) / (b - a));
double mix(double a, double b, double t) => a + (b - a) * t;
double eio(double t) {
  final x = c01(t);
  return x < 0.5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3) / 2;
}

double eo(double t) {
  final x = 1 - c01(t);
  return 1 - x * x * x;
}

double ei(double t) {
  final x = c01(t);
  return x * x * x;
}

double bump(double t) => t <= 0 || t >= 1 ? 0 : math.sin(t * math.pi);

/// Deterministic pseudo-random in [0, 1).
double hash(num a, [num b = 0, num c = 0]) {
  final v = math.sin(a * 12.9898 + b * 78.233 + c * 37.719 + 0.5) * 43758.5453;
  return v - v.floorToDouble();
}

/// Geometry that follows from one name's raster.
class SitePlan {
  SitePlan(this.r) {
    b = r.brick;
    final bounds = r.bounds;
    wall = Rect.fromLTRB(bounds.left, bounds.top, bounds.right, BL.groundY);
    rows = r.rows;
    cols = r.cols;
    rpl = math.max(1, (28 / b).round());
    liftH = rpl * b;
    lifts = math.max(1, (rows + rpl - 1) ~/ rpl);
    sL = math.max(BL.site.left, wall.left - 40);
    sR = math.min(ballParkX - 18, wall.right + 40);
    final nb = math.max(2, ((sR - sL) / 96).round());
    standards = [for (var i = 0; i <= nb; i++) sL + (sR - sL) * i / nb];
    bays = [for (var i = 0; i < nb; i++) (standards[i] + standards[i + 1]) / 2];

    zoneL = Float64List(zoneCount);
    zoneR = Float64List(zoneCount);
    int firstCol(int z) => z >= zoneCount ? cols : (z * cols / zoneCount).ceil();
    for (var z = 0; z < zoneCount; z++) {
      zoneL[z] = wall.left + firstCol(z) * b;
      zoneR[z] = wall.left + firstCol(z + 1) * b;
    }

    final n = r.bricks.length;
    course = Int32List(n);
    cx = Float64List(n);
    cy = Float64List(n);
    final perZone = List.generate(zoneCount, (_) => <int>[]);
    grid = Int32List(cols * rows)..fillRange(0, cols * rows, -1);
    for (var i = 0; i < n; i++) {
      final k = r.bricks[i];
      course[i] = rows - 1 - k.row;
      cx[i] = wall.left + (k.col + 0.5) * b;
      cy[i] = wall.top + (k.row + 0.5) * b;
      perZone[k.zone].add(i);
      grid[k.row * cols + k.col] = i;
    }
    zoneBricks = [for (final z in perZone) Int32List.fromList(z)];
    liftFirst = Int32List(lifts + 1)..fillRange(0, lifts + 1, -1);
    for (var i = 0; i < n; i++) {
      final k = course[i] ~/ rpl;
      if (k <= lifts && liftFirst[k] < 0) liftFirst[k] = i;
    }
  }

  final NameRaster r;
  late final double b;

  /// The wall: the raster's bounds, standing on the ground.
  late final Rect wall;
  late final int rows, cols;

  /// Raster rows per scaffold lift, and the lift height in px.
  late final int rpl;
  late final double liftH;

  /// Number of working lifts; deck [lifts] is the top deck above the wall.
  late final int lifts;

  /// Scaffold extent, standards (poles) and the bays between them.
  late final double sL, sR;
  late final List<double> standards;
  late final List<double> bays;

  /// Each zone's stretch of wall in x.
  late final Float64List zoneL, zoneR;

  /// Per brick (build order): course (0 = bottom row) and cell centre.
  late final Int32List course;
  late final Float64List cx, cy;

  /// Brick indices of each zone, in build order.
  late final List<Int32List> zoneBricks;

  /// Raster cell (row-major) → brick index, or -1.
  late final Int32List grid;

  /// First brick of each lift (or -1).
  late final Int32List liftFirst;

  int get total => r.bricks.length;

  double deckY(int k) => BL.groundY - k * liftH;
  int liftOf(int n) => math.min(lifts - 1, course[n] ~/ rpl);
  double zoneMid(int z) => (zoneL[z] + zoneR[z]) / 2;

  /// Builders stay on the scaffold between these.
  double clampX(double x) => x.clamp(sL + 6, sR - 6);
}

/// One crane trip: [count] pallets hooked together off the landing stack.
class Trip {
  Trip(this.index, this.first, this.count);
  final int index;

  /// First pallet and how many.
  final int first;
  final int count;

  /// The last pallet of the trip has landed on the stack.
  double stagedAt = 0;

  /// Hook lowered onto the stack / lifted off / set down / unhooked.
  double attachAt = 0;
  double departAt = 0;
  double landAt = 0;
  double freeAt = 0;

  /// Where the stack lands.
  double bayX = 0;
  int deck = 0;

  /// Bricks in this trip, and when the last one has left the stack.
  int brickFrom = 0;
  int brickTo = 0;
  double emptyAt = 0;

  double get height => count * palletH;
}

/// The build's timing: brick schedule and crane trips.
class BuildPlan {
  BuildPlan(this.site, this.start, this.len, double now) : total = site.total {
    interval = len / total;
    pallets = (total + palletSize - 1) ~/ palletSize;
    _planTrips(now);
  }

  final SitePlan site;

  /// Follows [Job.buildStart] (which settles to the exact frame the build
  /// began on); the trips keep their planned times.
  double start;
  final double len;
  final int total;
  late final double interval;
  late final int pallets;
  late final int perTrip;
  late final double tripTime;
  final trips = <Trip>[];
  late final Int32List tripOfPallet;
  late final Int32List slotOfPallet;

  /// When each lift's deck is put up (index = lift; the top deck last).
  late final Float64List erectAt;

  double brickTime(int n) => start + len * n / total;
  double palletAt(int i) => brickTime(i * palletSize) - craneLead;
  double get end => start + len;

  /// Bricks standing in the wall at [t], exactly as [Job.laid] counts them.
  int laidAt(double t) => t <= start ? 0 : math.min(total, ((t - start) / interval).floor());

  /// When brick [n] joins the standing wall (the moment [laidAt] passes it,
  /// one schedule step after [brickTime]).
  double landTime(int n) => start + interval * (n + 1);

  /// Bricks that have left their pallets by [t].
  int pickedAt(double t) => laidAt(t + pickLead);

  /// Builders work on this lift at [t] (the lift of the next brick).
  int liftAt(double t) {
    final n = laidAt(t);
    return n >= total ? site.lifts - 1 : site.liftOf(n);
  }

  static const _margin = 0.15;

  void _planTrips(double now) {
    final d = palletSize * interval;
    // How many pallets per trip: as few as possible, but the crane must keep
    // up (round trip ≤ n·d) and still land the first pallet in time.
    const uMax = 2.7, vMin = 1.0;
    var n = 1;
    var u = -1.0;
    for (var k = 1; k <= 8; k++) {
      final avail = craneLead - _margin - (k - 1) * d - hopTime - attachTime;
      final thru = k * d - attachTime - releaseTime - vMin;
      final uk = math.min(uMax, math.min(avail, thru));
      if (uk > u + 0.12) {
        n = k;
        u = uk;
      }
    }
    perTrip = n;
    tripTime = math.max(0.9, u);

    tripOfPallet = Int32List(pallets);
    slotOfPallet = Int32List(pallets);
    var ready = now + 1.5;
    var bayTurn = 0;
    final occupied = <(double, double)>[]; // (bay x, free again at)
    for (var first = 0, k = 0; first < pallets; first += n, k++) {
      final count = math.min(n, pallets - first);
      final trip = Trip(k, first, count);
      for (var i = 0; i < count; i++) {
        tripOfPallet[first + i] = k;
        slotOfPallet[first + i] = i;
      }
      trip.brickFrom = first * palletSize;
      trip.brickTo = math.min(total, (first + count) * palletSize);
      trip.stagedAt = palletAt(first + count - 1) + hopTime;
      trip.attachAt = math.max(trip.stagedAt, ready);
      trip.departAt = trip.attachAt + attachTime;
      // Set down before the trip's first brick is due (Job.brickTime).
      final deadline = brickTime(trip.brickFrom) - _margin;
      final ut = (deadline - trip.departAt).clamp(0.9, tripTime);
      trip.landAt = trip.departAt + ut;
      trip.freeAt = trip.landAt + releaseTime;
      trip.deck = site.liftOf(trip.brickFrom);
      trip.emptyAt = landTime(trip.brickTo - 1) - pickLead;
      // Land on a free bay the crane can reach in time, taking turns along
      // the deck so the trolley travels.
      final reach = 360 * ut - 60;
      final bays = site.bays;
      double? pick;
      for (var tries = 0; tries < bays.length * 2 && pick == null; tries++) {
        final x = bays[(bayTurn * 3 + tries) % bays.length];
        final busy = occupied.any((o) => (o.$1 - x).abs() < 4 && o.$2 > trip.landAt);
        if (!busy && (x - stageX).abs() <= reach) pick = x;
      }
      bayTurn++;
      pick ??= bays.reduce((a, b) => (a - stageX).abs() <= (b - stageX).abs() ? a : b);
      trip.bayX = pick;
      occupied.add((pick, trip.emptyAt + 1.2));
      if (occupied.length > 12) occupied.removeAt(0);
      // Back at the landing, ready for the next stack.
      final back = 0.6 + (pick - stageX).abs() / 520;
      ready = trip.freeAt + math.max(vMin, back);
      trips.add(trip);
    }

    // Each lift's deck goes up before anything is set on it.
    erectAt = Float64List(site.lifts + 1);
    for (var k = 1; k <= site.lifts; k++) {
      final f = k < site.liftFirst.length ? site.liftFirst[k] : -1;
      var at = f >= 0 && k < site.lifts ? brickTime(f) - 2.6 : end - 2.2;
      for (final t in trips) {
        if (t.deck == k) at = math.min(at, t.landAt - 1.4);
      }
      erectAt[k] = at;
    }
    for (var k = 2; k <= site.lifts; k++) {
      erectAt[k] = math.max(erectAt[k], erectAt[k - 1] + 0.4);
    }
  }

  /// The trip (if any) whose stack hangs on the hook at [t].
  Trip? hooked(double t) {
    for (final trip in trips) {
      if (t >= trip.departAt && t < trip.landAt) return trip;
      if (trip.departAt > t) break;
    }
    return null;
  }

  /// The trip whose hook is lowered onto / lifted off its load at [t]
  /// (slings visible), if any.
  Trip? slung(double t) {
    for (final trip in trips) {
      if (t >= trip.attachAt + attachTime * 0.5 && t < trip.freeAt - releaseTime * 0.4) return trip;
      if (trip.attachAt > t) break;
    }
    return null;
  }
}
