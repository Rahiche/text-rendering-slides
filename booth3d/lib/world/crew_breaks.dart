import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/model.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'crew.dart';
import 'figure.dart';
import 'motion.dart';
import 'kit.dart';
import 'shot.dart';
import 'site_fx.dart';
import 'site_geo.dart';
import 'site_plan.dart';
import 'site_props.dart';

/// Debug (`--dart-define=BOOTH3D_FAKE_BREAKS=true`): gives every builder
/// some time off during the build — and lets them climb off a raised deck —
/// to see the breaks before the build's own schedule frees anyone.
const fakeBreaks = bool.fromEnvironment('BOOTH3D_FAKE_BREAKS');

/// What a break is spent on.
enum BreakKind { coffee, smoke, chat, stretch }

/// The delivery driver's time off at the truck: [from]–[to], starting and
/// ending at [door] (on the ground by the cab).
class DriverBreak {
  DriverBreak(this.from, this.to, this.door);
  final double from, to;
  final vm.Vector3 door;
}

/// The crew's time off during a build.
///
/// Builders the build doesn't need ([BuildPlan.busyWindows]) take a break:
/// a can of coffee from the vending machines, a smoke at the 喫煙所, a chat
/// on the bench — or, when there's no time to go anywhere (or the platform
/// is raised and there's no way down), a stretch and a word with the
/// neighbour on the platform. They set off when the deck is down, and walk
/// back in time to be at their place when they're needed again. The
/// delivery driver joins in at the machines between unloading and leaving.
///
/// Everything is planned once per build and posed as a pure function of
/// scene time. Cans and cigarettes are one instanced draw, speech bubbles
/// another; the smoke and the embers come from the site's particle pools.
class CrewBreaks {
  CrewBreaks(this.scene, this.fx, this.crew);

  final Scene scene;
  final Fx3D fx;

  /// (For the hands: on the rail, the machine's buttons, the ashtray.)
  final Crew3D crew;

  /// The driver, among the people on a break (after the six builders).
  static const driver = Crew3D.builders;

  late final InstancedMesh _held, _bubbles;
  final _bubbleNode = Node(name: 'speech bubbles');
  static const _maxHeld = 16, _maxBubbles = 4;
  int _nHeld = 0, _hiHeld = 0, _nBubbles = 0, _hiBubbles = 0;

  /// Where the camera is (last frame): speech bubbles turn to face it.
  final camera = vm.Vector3(0, 8, -30);

  void init() {
    _held = InstancedMesh(
      geometry: CylinderGeometry(bottomRadius: 1, topRadius: 1, height: 1, radialSegments: 10),
      material: pbr(rgb(1, 1, 1), roughness: 0.4, metallic: 0.3),
    );
    for (var i = 0; i < _maxHeld; i++) {
      _held.addInstance(hidden);
    }
    scene.add(
      Node(name: 'cans and cigarettes')
        ..castsShadows = false
        ..addComponent(InstancedMeshComponent(_held)),
    );
    // A white speech bubble with a tail and three dots ("…").
    final white = vm.Vector4(1, 1, 1, 1), ink = v4(hex3(0x1B2233));
    final bubble = merged([
      part(CuboidGeometry(vm.Vector3(0.34, 0.2, 0.025)), vm.Matrix4.identity(), white),
      part(CuboidGeometry(vm.Vector3(0.3, 0.24, 0.025)), vm.Matrix4.identity(), white),
      part(CuboidGeometry(vm.Vector3(0.07, 0.07, 0.025)), trs(vm.Vector3(-0.06, -0.12, 0), rotZ: math.pi / 4), white),
      for (final x in [-0.08, 0.0, 0.08]) part(SphereGeometry(radius: 0.025, segments: 8, rings: 5), trs(vm.Vector3(x, 0, -0.02)), ink),
    ]);
    _bubbles = InstancedMesh(
      geometry: bubble,
      material: pbr(rgb(1, 1, 1), roughness: 0.6, emissive: rgb(0.35, 0.35, 0.35), emissiveStrength: 1),
    );
    for (var i = 0; i < _maxBubbles; i++) {
      _bubbles.addInstance(hidden);
    }
    scene.add(
      _bubbleNode
        ..castsShadows = false
        ..visible = false
        ..addComponent(InstancedMeshComponent(_bubbles)),
    );
  }

  // ── Planning ──────────────────────────────────────────────────────────────

  BuildPlan? _plan;
  final _breaks = <_Break>[];
  final _taken = <int, List<(double, double)>>{}; // spot → reserved intervals
  final _machines = [<(double, double)>[], <(double, double)>[]];
  final _follows = <_Follow>[];
  final _down = <(double, double)>[]; // when the deck is down (on the ground)
  double _w = 12;

  /// Plans the build's breaks (once per build, when its plan is ready), the
  /// driver's [driverBreaks] among them. The camera keeps clear of [busyCam]
  /// (the delivery's own follow shots) and of the kerning close-ups.
  void planFor(BuildPlan plan, {List<DriverBreak> driverBreaks = const [], List<(double, double)> busyCam = const []}) {
    _plan = plan;
    _cutAt = null;
    _w = plan.width;
    _breaks.clear();
    _taken.clear();
    for (final m in _machines) {
      m.clear();
    }
    _findDown(plan);
    final t0 = plan.t0, end = t0 + plan.len;
    final serial = plan.job.serial;
    // Each builder's free windows, in time order across the crew (so the
    // places at the machines and the ashtray go first come, first served).
    final free = <(int, double, double)>[];
    for (var z = 0; z < Crew3D.builders; z++) {
      var from = t0;
      for (final (a, e) in [..._busy(plan, z), (end, end + 1)]) {
        final fa = math.max(from, t0), fb = math.min(a, end);
        if (fb - fa > 2.5) free.add((z, fa, fb));
        from = math.max(from, e);
      }
    }
    free.sort((a, b) => a.$2.compareTo(b.$2));
    var n = 0;
    for (final (z, fa, fb) in free) {
      _fill(plan, z, fa, fb, z * 31 + n++ * 7 + serial * 13);
    }
    for (final d in driverBreaks) {
      if (d.to - d.from <= 6) continue;
      final b = _Break(driver, d.from, d.to, 97 + serial * 13)..door = d.door;
      _choose(b, plan, d.from, d.to);
      _breaks.add(b);
    }
    _breaks.sort((a, b) => a.from.compareTo(b.from));
    _planFollows(plan, busyCam);
    // The plan, in capture mode's log.
    if (const String.fromEnvironment('BOOTH3D_TIMES') == '') return;
    for (final b in _breaks) {
      // ignore: avoid_print
      print(
        'PLAN break who=${b.who} ${b.kind.name} ${b.from.toStringAsFixed(1)}-${b.to.toStringAsFixed(1)} leave=${b.leave.toStringAsFixed(1)} arrive=${b.arrive.toStringAsFixed(1)} depart=${b.depart.toStringAsFixed(1)} on=${b.stepOn.toStringAsFixed(1)} spot=${b.spotIndex} m=${b.machine}',
      );
    }
    for (final f in _follows) {
      // ignore: avoid_print
      print('PLAN follow who=${f.b.who} ${f.b.kind.name} ${f.from.toStringAsFixed(1)}-${f.to.toStringAsFixed(1)}');
    }
  }

  /// Builder [z]'s free window [fa, fb): trips off the platform (a coffee,
  /// a smoke, a chat), each from one time the deck is down to a later one,
  /// with spells back at their rest spot between; whatever is too short to
  /// go anywhere is a break on the platform.
  void _fill(BuildPlan plan, int z, double fa, double fb, int seed) {
    var t = fa;
    for (var k = 0; fb - t > 2.5; k++) {
      final s = seed + k * 101;
      final leave = _nextDown(t + 0.05, _step + 0.15);
      _Break? trip;
      if (leave != null && fb - leave > 16) {
        // Out for half a minute or so (or the rest of the window, if what
        // would be left is too short to bother).
        final want = 20 + 24 * rnd(s, 5);
        final latest = fb - leave < want + 30 ? fb : leave + want;
        trip = _Break(z, leave - 0.05, fb, s);
        if (!_choose(trip, plan, leave, latest, window: fb)) trip = null;
      }
      if (trip == null) {
        // Not going anywhere: a stretch and a word on the platform.
        _breaks.add(_Break(z, t, fb, s));
        return;
      }
      if (trip.from - t > 6) _breaks.add(_Break(z, t, trip.from, s + 1));
      _breaks.add(trip);
      // Back at their rest spot for a while before going again.
      t = math.min(fb, trip.to + 10 + 12 * rnd(s, 6));
      if (t - trip.to > 6) _breaks.add(_Break(z, trip.to, t, s + 2));
    }
  }

  /// When builder [z] is needed at the wall: the plan's windows, or (debug)
  /// a made-up shift pattern with time off.
  List<(double, double)> _busy(BuildPlan plan, int z) {
    if (!fakeBreaks) return plan.busyWindows(z);
    final t0 = plan.t0, end = t0 + plan.len, s = plan.job.serial;
    final out = <(double, double)>[];
    var t = t0 - 1.5;
    for (var k = 0; t < end; k++) {
      final work = 6 + 16 * rnd(z, k, s);
      final off = k == 1 && z.isEven ? 7.0 : 22 + 22 * rnd(z, k, s + 5);
      out.add((t, math.min(end, t + work)));
      t += work + off;
    }
    return out;
  }

  /// When the platform is down during the build: builders step on and off
  /// only then (there's no ladder).
  void _findDown(BuildPlan plan) {
    _down.clear();
    final a = plan.t0 - 1.5, e = plan.t0 + plan.len + 1;
    if (fakeBreaks) {
      _down.add((a, e));
      return;
    }
    double? from;
    for (var t = a; t <= e; t += 0.1) {
      final down = plan.deckY(t) <= 0.02;
      if (down && from == null) from = t;
      if (!down && from != null) {
        _down.add((from, t - 0.1));
        from = null;
      }
    }
    if (from != null) _down.add((from, e));
  }

  /// The first time ≥ [t] the deck is down for the next [d] seconds.
  double? _nextDown(double t, double d) {
    for (final (a, e) in _down) {
      final s = math.max(a, t);
      if (s + d <= e) return s;
    }
    return null;
  }

  /// The last time ≤ [t] (and ≥ [floor]) the deck is down from a moment
  /// before until [d] seconds after.
  double? _lastDown(double t, double d, double floor) {
    for (final (a, e) in _down.reversed) {
      final s = math.min(e - d, t);
      if (s >= a + 0.1 && s >= floor) return s;
      if (e < floor) return null;
    }
    return null;
  }

  /// Seconds to step off (or on) the platform at the rest spot, and the
  /// walking speeds.
  static const _step = 0.7, _vOut = 1.9, _vHome = 2.2;

  /// Decides what [b] does and where, stepping off at [leave] and back on
  /// by [latest] (or the end of the [window]), reserving a spot (and a
  /// machine). False if nothing fits.
  bool _choose(_Break b, BuildPlan plan, double leave, double latest, {double? window}) {
    for (final kind in _prefs(b)) {
      if (kind == BreakKind.stretch) break;
      if (_tryAway(b, plan, kind, leave, latest)) return true;
      if (window != null && latest < window && _tryAway(b, plan, kind, leave, window)) return true;
    }
    b.kind = BreakKind.stretch;
    return false;
  }

  /// What [b]'s person would rather do, best first: coffee, a smoke (the
  /// smokers) or a chat on the bench, the nearer the better, something the
  /// others haven't gone for yet (all three show up in a build), a chat
  /// rather where there's someone to chat with.
  List<BreakKind> _prefs(_Break b) {
    if (b.who == driver) return const [BreakKind.coffee, BreakKind.stretch];
    final plan = _plan!;
    final s = plan.job.serial;
    final right = plan.restX(b.who) > 0;
    final smoker = (b.who == 1 || b.who == 4) != (s % 5 == 0);
    double score(BreakKind k) {
      var v = switch (k) {
        BreakKind.coffee => 1.0 + (right ? 0.6 : 0),
        BreakKind.smoke => smoker ? 1.2 + (right ? 0 : 0.6) : -9,
        _ => 0.8 + (right ? 0 : 0.6),
      };
      for (final o in _breaks) {
        if (o.kind != k || o.spot == null) continue;
        v -= 0.7;
        if (k == BreakKind.chat && o.depart > b.from + 10 && o.arrive < b.from + 25) v += 0.5;
      }
      return v + rnd(b.seed, k.index, s) * 0.9;
    }

    final order = [BreakKind.coffee, BreakKind.smoke, BreakKind.chat]..sort((x, y) => score(y).compareTo(score(x)));
    return [...order.where((k) => score(k) > 0), BreakKind.stretch];
  }

  /// Plans a trip off the platform for [b] to do [kind], stepping off at
  /// [leave] and back on by [latest], if it fits.
  bool _tryAway(_Break b, BuildPlan plan, BreakKind kind, double leave, double latest) {
    final group = switch (kind) {
      BreakKind.coffee => 0,
      BreakKind.smoke => 1,
      _ => 2,
    };
    // Builders step off the back of the platform at their rest spot (the
    // driver starts by the truck).
    final isDriver = b.who == driver;
    final start = isDriver ? b.door : vm.Vector3(plan.restX(b.who), 0, SiteLayout.crewZ);
    final behind = isDriver ? start : vm.Vector3(start.x, 0, 2.4);
    final step = isDriver ? 0.0 : _step;
    final minStay = switch (kind) {
      BreakKind.coffee => 9.0,
      BreakKind.smoke => 10.0,
      _ => 7.0,
    };
    for (final spotIndex in _spotsOf(group)) {
      final spot = _spots[spotIndex];
      final out = _groundRoute(behind, group, spot, isDriver: isDriver);
      final home = [spot.at, if (kind == BreakKind.coffee) _binStop, ...out.reversed.skip(1)];
      final dOut = _length(out) / _vOut, dHome = _length(home) / _vHome;
      final arrive = leave + step + dOut;
      // Back on the deck as late as it allows (when it's down), after a
      // moment waiting behind it.
      final stepOn = isDriver ? latest - 0.3 : _lastDown(latest - step - 0.3, step + 0.1, arrive + minStay + dHome + 0.3);
      if (stepOn == null) return false;
      final behindAt = isDriver ? stepOn : stepOn - 0.3;
      final depart = behindAt - dHome;
      if (depart - arrive < minStay) return false; // the other spots are no nearer
      // Coffee: a machine free for the purchase on arrival.
      var machine = -1;
      if (kind == BreakKind.coffee) {
        for (var m = 0; m < 2 && machine < 0; m++) {
          if (_free(_machines[m], arrive, arrive + _buyTime)) machine = m;
        }
        if (machine < 0) continue;
      }
      final stay = kind == BreakKind.coffee ? arrive + _buyTime + 0.8 : arrive;
      if (!_free(_taken[spotIndex] ?? const [], stay - 0.5, depart + 0.5)) continue;
      // Taken.
      (_taken[spotIndex] ??= []).add((stay - 0.5, depart + 0.5));
      if (machine >= 0) _machines[machine].add((arrive, arrive + _buyTime));
      b
        ..kind = kind
        ..spot = spot
        ..spotIndex = spotIndex
        ..machine = machine
        ..start = start
        ..behind = behind
        ..leave = leave
        ..arrive = arrive
        ..buyAt = arrive
        ..stay = stay
        ..depart = depart
        ..behindAt = behindAt
        ..stepOn = stepOn
        ..home = stepOn + step
        ..to = isDriver ? b.to : stepOn + step + 0.4
        ..out.addAll(machine >= 0 ? [...out.take(out.length - 1), BreakSpots.buyAt(machine)] : out)
        ..back.addAll(home);
      return true;
    }
    return false;
  }

  static const _buyTime = 3.6;

  static bool _free(List<(double, double)> taken, double a, double b) => taken.every((r) => b <= r.$1 || a >= r.$2);

  static double _length(List<vm.Vector3> pts) {
    var l = 0.0;
    for (var i = 0; i + 1 < pts.length; i++) {
      l += pts[i].distanceTo(pts[i + 1]);
    }
    return l;
  }

  static final _binStop = vm.Vector3(15.75, 0, -5.05);

  /// From behind the platform ([from]) to [spot] of [group]: along the back
  /// of the platform, round the wall's end on the right for the machines.
  List<vm.Vector3> _groundRoute(vm.Vector3 from, int group, _Spot spot, {required bool isDriver}) {
    final w = _w;
    final e = w / 2 + 1.3;
    final pts = <vm.Vector3>[from];
    switch (group) {
      case 0:
        if (isDriver) {
          pts.add(vm.Vector3(15.55, 0, -4.0));
        } else {
          pts
            ..add(vm.Vector3(e, 0, from.z))
            ..add(vm.Vector3(w / 2 + 1.35, 0, -0.6))
            ..add(vm.Vector3(w / 2 + 1.7, 0, -2.62))
            ..add(vm.Vector3(15.55, 0, -2.62));
        }
        pts.add(vm.Vector3(15.55, 0, -5.4));
      case 1:
        pts.add(vm.Vector3(-(w / 2 + 1.6), 0, 2.45));
      default:
        pts
          ..add(vm.Vector3(-e, 0, from.z))
          ..add(vm.Vector3(-17.0, 0, spot.at.z * 0.5));
    }
    pts.add(spot.at);
    return pts;
  }

  // The places to be: the ring by the machines, the ring round the
  // ashtray, the bench and beside it.
  static final _spots = [
    for (final p in BreakSpots.vendRing) _Spot(p, 0),
    for (final p in BreakSpots.smokeRing) _Spot(p, 1),
    for (final p in BreakSpots.seats) _Spot(vm.Vector3(-17.95, 0, p.z), 2, sitX: p.x, face: -math.pi / 2),
    _Spot(BreakSpots.benchSide, 2, face: math.pi / 2),
  ];

  static Iterable<int> _spotsOf(int group) sync* {
    for (var i = 0; i < _spots.length; i++) {
      if (_spots[i].group == group) yield i;
    }
  }

  /// The middle of a group's places (people there face it).
  static final _groupMiddle = [vm.Vector3(15.8, 0, -4.15), BreakSpots.ashtray, vm.Vector3(-18.0, 0, 0)];

  // ── Posing ────────────────────────────────────────────────────────────────

  final _me = FigurePose();
  final _tmp = vm.Vector3.zero(), _aimAt = vm.Vector3.zero();
  double _t = 0, _night = 0;

  /// Starts a frame: the hand-held props and bubbles are re-placed by
  /// [pose]; call [end] after posing everyone.
  void begin(double t, double night) {
    _t = t;
    _night = night;
    _nHeld = 0;
    _nBubbles = 0;
  }

  void end() {
    for (var i = _nHeld; i < _hiHeld; i++) {
      _held.setInstanceTransform(i, hidden);
    }
    for (var i = _nBubbles; i < _hiBubbles; i++) {
      _bubbles.setInstanceTransform(i, hidden);
    }
    _hiHeld = _nHeld;
    _hiBubbles = _nBubbles;
    _bubbleNode.visible = _nBubbles > 0;
  }

  _Break? _breakOf(int who, double t) {
    for (final b in _breaks) {
      if (b.who == who && t >= b.from && t < b.to) return b;
    }
    return null;
  }

  /// The hook for [Crew3D.offDuty]: poses builder [z] for their break at
  /// [t] if they're on one (over the work pose already in [p]).
  void pose(FigurePose p, int z, BuildPlan plan, double t, double floor) {
    if (!identical(plan, _plan)) return;
    final j = plan.job;
    if (j.phase == Phase.build) {
      final b = _breakOf(z, t);
      if (b != null) _poseBreak(p, b, t, floor);
      return;
    }
    // A sample cut short: whoever is off the platform stays where they are
    // and watches the wall come down (back in their places for the next
    // name, after the camera's cut).
    if (j.cutAt != null && (j.phase == Phase.demolish || j.phase == Phase.cleanup)) {
      if (j.phase == Phase.demolish) _cutAt ??= j.phaseStart;
      final cut = _cutAt;
      final b = cut == null ? null : _breakOf(z, cut);
      if (b == null || b.spot == null) return;
      final at = _fp..rest();
      _place(b, math.min(cut!, b.depart), at);
      if (cut < b.leave || cut >= b.home || _onDeck(at.pos)) return;
      p
        ..rest()
        ..pos.setFrom(at.pos);
      OffDuty.stand(p, t, b.seed);
      p.yaw = math.atan2(p.pos.x, p.pos.z);
      if (b.kind == BreakKind.smoke && cut > b.arrive) _cigarette(p, b, t, lit: true);
    }
  }

  double? _cutAt;

  /// The driver's break at [t] (true if [p] was posed).
  bool poseDriver(FigurePose p, double t) {
    final b = _breakOf(driver, t);
    if (b == null) return false;
    p.rest();
    p.pos.setFrom(b.door);
    _poseBreak(p, b, t, 0);
    return true;
  }

  void _poseBreak(FigurePose p, _Break b, double t, double floor) {
    final me = _me..rest();
    if (b.spot == null) {
      _platformBreak(me, p, b, t);
    } else {
      _awayBreak(me, p, b, t, floor);
    }
    // Ease out of the work pose at the start and back into it at the end.
    final k = b.who == driver ? 1.0 : eio(seg(t, b.from, b.from + 0.7)) * (1 - eio(seg(t, b.to - 0.6, b.to)));
    p.blendTo(me, k);
  }

  /// A break on the platform: a stretch, a look at the city, a word with
  /// the neighbour.
  void _platformBreak(FigurePose me, FigurePose work, _Break b, double t) {
    me.pos.setFrom(work.pos);
    final u = t - b.from;
    if (b.who == driver) {
      // By the truck: a stretch, a look round.
      OffDuty.stand(me, t, b.seed);
      me.yaw = 2.2 + Idle.facing(t, Manner.of(b.seed), 0.6);
      if ((u % 9) < 4.5) OffDuty.stretch(me, (u % 9) / 4.5, b.seed);
      return;
    }
    // Turn to the nearer neighbour now and then.
    final cycle = (u / 5.5).floor();
    final what = (rnd(b.seed, cycle) * 4).floor();
    final f = (u % 5.5) / 5.5;
    if (cycle == 0 || what == 0) {
      OffDuty.stretch(me, f, b.seed + cycle);
    } else if (what == 1) {
      // Leaning on the back rail, looking out over the park: the hands on
      // its top.
      OffDuty.stand(me, t, b.seed, shift: 0.4);
      me
        ..yaw = math.pi + Idle.facing(t, Manner.of(b.seed), 0.15)
        ..lean = 0.3;
      final k = smooth(0, 0.08, f) * (1 - smooth(0.92, 1, f));
      for (var s = 0; s < 2; s++) {
        _aimAt.setValues(me.pos.x + (s == 0 ? 0.22 : -0.22), me.pos.y + 1.05, SiteLayout.deckZ1 - 0.03);
        crew.aimBy(me, s, _aimAt, k);
      }
    } else {
      OffDuty.stand(me, t, b.seed);
      final n = b.who + (b.who == 0 ? 1 : (b.who == Crew3D.builders - 1 ? -1 : (rnd(b.seed, cycle, 5) < 0.5 ? -1 : 1)));
      final dx = _plan!.zoneX[n] - me.pos.x;
      me.yaw = math.atan2(-dx, 0.35);
      if (what == 2) {
        OffDuty.talk(me, t, b.seed);
      } else {
        OffDuty.listen(me, t, b.seed);
      }
    }
  }

  /// Where [b]'s person is at [t] along their trip (on the ground, before
  /// the deck height is applied); returns whether walking, and the heading.
  (bool, double) _place(_Break b, double t, FigurePose out) {
    if (t < b.leave || t >= b.home) {
      out.pos.setFrom(b.start);
      return (false, 0);
    }
    final off = b.leave + (b.who == driver ? 0 : _step);
    if (t < off) {
      // Stepping off the back of the platform.
      _lerp(b.start, b.behind, eio((t - b.leave) / _step), out.pos);
      return (true, math.pi);
    }
    if (t < b.arrive) return _along(b.out, off, b.arrive, t, out.pos);
    if (t >= b.stepOn) {
      // Stepping back on.
      _lerp(b.behind, b.start, eio((t - b.stepOn) / _step), out.pos);
      return (true, 0);
    }
    if (t >= b.behindAt) {
      // Waiting behind it for the deck to come down.
      out.pos.setFrom(b.behind);
      return (false, 0);
    }
    if (t >= b.depart) return _along(b.back, b.depart, b.behindAt, t, out.pos);
    // Coffee: from the machine to the spot after buying.
    if (b.machine >= 0 && t < b.stay) {
      if (t < b.buyAt + _buyTime) {
        out.pos.setFrom(b.out.last);
        return (false, -math.pi / 2);
      }
      return _along([b.out.last, b.spot!.at], b.buyAt + _buyTime, b.stay, t, out.pos);
    }
    out.pos.setFrom(b.spot!.at);
    return (false, 0);
  }

  static void _lerp(vm.Vector3 a, vm.Vector3 b, double f, vm.Vector3 out) => out.setValues(lerp(a.x, b.x, f), lerp(a.y, b.y, f), lerp(a.z, b.z, f));

  /// Position along a polyline walked from [t0] to [t1] (evenly); returns
  /// whether still walking, and the heading.
  static (bool, double) _along(List<vm.Vector3> pts, double t0, double t1, double t, vm.Vector3 out) {
    final total = _length(pts);
    var s = total * c01((t - t0) / math.max(t1 - t0, 1e-3));
    for (var i = 0; i + 1 < pts.length; i++) {
      final a = pts[i], b = pts[i + 1];
      final l = a.distanceTo(b);
      if (s <= l || i + 2 == pts.length) {
        final f = l > 0 ? c01(s / l) : 1.0;
        out.setValues(a.x + (b.x - a.x) * f, 0, a.z + (b.z - a.z) * f);
        return (t < t1, math.atan2(-(b.x - a.x), -(b.z - a.z)));
      }
      s -= l;
    }
    out.setFrom(pts.last);
    return (false, 0);
  }

  bool _onDeck(vm.Vector3 p) => p.z > SiteLayout.deckZ0 && p.z < SiteLayout.deckZ1 && p.x.abs() < _w / 2 + 1.05;

  /// A trip off the platform: step off, walk there, the activity, walk
  /// back, wait for the deck to come down, step on.
  void _awayBreak(FigurePose me, FigurePose work, _Break b, double t, double floor) {
    final spot = b.spot!;
    final (walking, heading) = _place(b, t, me);
    me.pos.y = b.who != driver && _onDeck(me.pos) ? floor : 0;
    if (walking) {
      OffDuty.walk(me, t, t < b.arrive ? _vOut : _vHome, b.seed);
      me.yaw = heading;
      if (b.kind == BreakKind.coffee && t >= b.arrive && t < b.stepOn) {
        // With the can; it goes in the bin on the way past.
        final toss = b.depart + (b.behindAt - b.depart) * _binStop.distanceTo(spot.at) / _length(b.back);
        if (t < b.depart) {
          OffDuty.hold(me, 1, 1);
          _can(me, b, t);
        } else if (t < toss + 0.5) {
          _can(me, b, t, flyTo: t >= toss ? BreakSpots.bin : null, flyFrom: toss);
        }
      }
      return;
    }
    if (t < b.leave || t >= b.home) {
      // On the platform at their rest spot, about to go or just back.
      OffDuty.stand(me, t, b.seed);
      me.yaw = Idle.facing(t, Manner.of(b.seed), 0.15);
      return;
    }
    if (t >= b.behindAt) {
      // Behind the platform, waiting for it to come down.
      OffDuty.stand(me, t, b.seed);
      me
        ..yaw = Idle.facing(t, Manner.of(b.seed), 0.2)
        ..lean = -0.12;
      return;
    }
    switch (b.kind) {
      case BreakKind.coffee:
        _coffee(me, b, t);
      case BreakKind.smoke:
        _smoke(me, b, t);
      default:
        _chat(me, b, t);
    }
  }

  /// Faces the middle of [b]'s group, or (with company) whoever's talking.
  void _faceGroup(FigurePose me, _Break b) {
    final spot = b.spot!;
    final m = spot.face != null ? null : _groupMiddle[spot.group];
    me.yaw = spot.face ?? math.atan2(-(m!.x - me.pos.x), -(m.z - me.pos.z));
  }

  /// Who else is at [group] at [t] (the people there, sorted).
  List<int> _company(int group, double t) {
    final out = <int>[];
    for (final o in _breaks) {
      final s = o.spot;
      if (s == null || s.group != group || t < o.stay || t >= o.depart) continue;
      out.add(o.who);
    }
    return out..sort();
  }

  /// Talk, listen, laugh: [who] among [company] at [t].
  void _conversation(FigurePose me, _Break b, List<int> company, double t, {bool hands = true}) {
    final turn = (t / 3.8).floor();
    final talker = company[(turn + b.spot!.group) % company.length];
    final laugh = rnd(turn, b.spot!.group, 9) < 0.22 && (t % 3.8) > 2.6;
    if (laugh) {
      OffDuty.laugh(me, t, b.seed);
    } else if (talker == b.who) {
      if (hands) OffDuty.talk(me, t, b.seed);
      _bubble(me, t, turn);
    } else {
      OffDuty.listen(me, t, b.seed);
    }
    if (company.length == 2 && talker != b.who) {
      // Face the one talking.
      for (final o in _breaks) {
        if (o.who == talker && o.spot != null && _t >= o.stay && _t < o.depart) {
          me.yaw = math.atan2(-(o.spot!.at.x - me.pos.x), -(o.spot!.at.z - me.pos.z));
        }
      }
    }
  }

  void _coffee(FigurePose me, _Break b, double t) {
    if (t < b.buyAt + _buyTime) {
      // At the machine: choose, press, the can drops; bend for it.
      final u = t - b.buyAt;
      me.yaw = -math.pi / 2;
      OffDuty.buy(me, u, b.seed);
      // A finger to a button on the front, then a hand down to the tray.
      final mz = BreakSpots.vendZ[b.machine];
      crew.aimBy(me, 1, _aimAt..setValues(BreakSpots.vendX - 0.41, 1.12, mz + 0.14), math.sin(math.pi * c01((u - 0.5) / 0.9)));
      crew.aimBy(me, 1, _aimAt..setValues(BreakSpots.vendX - 0.47, 0.34, mz), math.sin(math.pi * c01((u - 1.9) / 1.4)));
      if (u > 2.0) {
        if (u < 2.75) {
          // In the tray.
          _tmp.setValues(BreakSpots.vendX - 0.43, 0.27, BreakSpots.vendZ[b.machine]);
          _heldAt(_tmp, 0, b.seed);
        } else {
          _can(me, b, t);
        }
      }
      return;
    }
    if (t < b.stay) {
      // Walking over with it.
      _can(me, b, t);
      return;
    }
    OffDuty.stand(me, t, b.seed);
    _faceGroup(me, b);
    final company = _company(0, t);
    final u = t - b.stay;
    // Open it, then a sip every few seconds.
    final sip = u > 1.2 && ((u - 1.2) % 4.6) < 1.5;
    if (company.length > 1 && !sip) _conversation(me, b, company, t, hands: false);
    var tilt = 0.0;
    if (u < 1.2) {
      OffDuty.hold(me, 1, 0.9);
    } else {
      tilt = OffDuty.drink(me, ((u - 1.2) % 4.6) / 1.5, sip);
    }
    _can(me, b, t, tilt: tilt);
  }

  void _smoke(FigurePose me, _Break b, double t) {
    OffDuty.stand(me, t, b.seed);
    _faceGroup(me, b);
    final u = t - b.arrive, left = b.depart - t;
    final company = _company(1, t);
    if (u < 2.2) {
      // Lighting up: both hands to the mouth, a flicker of flame.
      OffDuty.light(me, u / 2.2);
      _cigarette(me, b, t, lit: u > 1.3);
      if (u > 1.0 && u < 1.6) {
        OffDuty.mouth(me, _tmp);
        fx.spark(_tmp.x, _tmp.y - 0.02, _tmp.z, 0.05 + 0.02 * math.sin(t * 40), vm.Vector4(1, 0.55, 0.15, 1), 5);
      }
      return;
    }
    if (left < 1.4) {
      // Stubbing it out in the ashtray.
      final f = 1 - left / 1.4;
      OffDuty.stub(me, f);
      final a = BreakSpots.ashtray, dx = me.pos.x - a.x, dz = me.pos.z - a.z, d = math.max(0.05, math.sqrt(dx * dx + dz * dz));
      crew.aimBy(me, 1, _aimAt..setValues(a.x + dx / d * 0.07, 1.0, a.z + dz / d * 0.07), math.sin(math.pi * c01(f)));
      if (left > 0.5) _cigarette(me, b, t, lit: false);
      return;
    }
    final v = (u - 2.2) % 5.2;
    final drag = v < 1.3;
    if (company.length > 1 && !drag) _conversation(me, b, company, t, hands: false);
    OffDuty.smoking(me, v);
    _cigarette(me, b, t, lit: true, drag: drag && v > 0.5);
    // The exhale: a puff from the mouth, drifting up.
    final age = (v - 1.4) / 1.6;
    if (age >= 0 && age < 1) {
      OffDuty.mouth(me, _tmp);
      final fwdX = -math.sin(me.yaw), fwdZ = -math.cos(me.yaw);
      fx.puff(_tmp.x + fwdX * 0.25 * age, _tmp.y + 0.15 * age, _tmp.z + fwdZ * 0.25 * age, age, 0.16, seed: b.seed + (u / 5.2).floor(), n: 2, tint: _smokeTint);
    }
  }

  static final _smokeTint = vm.Vector4(0.92, 0.94, 0.98, 0.32);

  void _chat(FigurePose me, _Break b, double t) {
    final spot = b.spot!;
    OffDuty.stand(me, t, b.seed);
    _faceGroup(me, b);
    if (spot.sitX case final x?) {
      // Sit down (from the step in front), and get up again at the end.
      final down = eio(seg(t, b.arrive, b.arrive + 0.8)) * (1 - eio(seg(t, b.depart - 0.8, b.depart)));
      OffDuty.sit(me, down);
      me.pos.x = lerp(spot.at.x, x, down);
    }
    final company = _company(2, t);
    if (company.length > 1) {
      _conversation(me, b, company, t);
    } else {
      // On their own: a look at the phone.
      OffDuty.phone(me, t, b.seed);
    }
  }

  // ── Props in hand ─────────────────────────────────────────────────────────

  final _m = vm.Matrix4.identity(), _q = vm.Quaternion.identity();
  static final _cans = [v4(hex3(0x5B3A29)), v4(hex3(0x1E2C52)), v4(hex3(0xC9A227)), v4(hex3(0xE8505F)), v4(hex3(0xF4F1EA))];
  static final _paper = v4(hex3(0xF4F1EA));

  /// A can in [me]'s right hand (or flying from it into the bin).
  void _can(FigurePose me, _Break b, double t, {vm.Vector3? flyTo, double flyFrom = 0, double tilt = 0}) {
    OffDuty.hand(me, 1, _tmp);
    if (flyTo != null) {
      final f = c01((t - flyFrom) / 0.45);
      _tmp.setValues(lerp(_tmp.x, flyTo.x, f), lerp(_tmp.y, 0.82, f) + 0.5 * math.sin(f * math.pi), lerp(_tmp.z, flyTo.z, f));
      tilt = f * 6;
      if (f >= 1) return;
    }
    _heldAt(_tmp, tilt, b.seed, yaw: me.yaw);
  }

  void _heldAt(vm.Vector3 at, double tilt, int seed, {double yaw = 0}) {
    if (_nHeld >= _maxHeld) return;
    // Upright, tipped back towards the face when drinking.
    _q.setEuler(yaw, tilt, 0);
    _held.setInstanceTransform(_nHeld, setTqs(_m, at.x, at.y + 0.02, at.z, _q, 0.03, 0.11, 0.03));
    _held.setInstanceColor(_nHeld, _cans[seed % _cans.length]);
    _nHeld++;
  }

  /// A cigarette between [me]'s right fingers: the ember glows (brighter on
  /// a drag and at night) and a wisp of smoke rises from it.
  void _cigarette(FigurePose me, _Break b, double t, {required bool lit, bool drag = false}) {
    if (_nHeld >= _maxHeld) return;
    OffDuty.hand(me, 1, _tmp);
    // Pointing forward, a little down.
    final fx0 = -math.sin(me.yaw), fz0 = -math.cos(me.yaw);
    _q.setEuler(me.yaw, -math.pi / 2 - 0.25, 0);
    final cx = _tmp.x + fx0 * 0.04, cy = _tmp.y + 0.02, cz = _tmp.z + fz0 * 0.04;
    _held.setInstanceTransform(_nHeld, setTqs(_m, cx, cy, cz, _q, 0.007, 0.075, 0.007));
    _held.setInstanceColor(_nHeld, _paper);
    _nHeld++;
    if (!lit) return;
    final tx = cx + fx0 * 0.038, ty = cy - 0.01, tz = cz + fz0 * 0.038;
    final glow = (drag ? 5.0 : 2.2) * (1 + 2.5 * _night);
    fx.spark(tx, ty, tz, drag ? 0.022 : 0.016, _ember, glow);
    // The wisp: small puffs rising off the tip.
    for (var k = 0; k < 2; k++) {
      final age = ((t * 0.7 + k * 0.5 + b.seed * 0.13) % 1.0);
      fx.puff(tx + 0.03 * math.sin(t * 2 + k), ty + 0.05 + 0.5 * age, tz, age, 0.05, seed: b.seed * 3 + k, n: 1, tint: _wisp);
    }
  }

  static final _ember = vm.Vector4(1, 0.32, 0.06, 1);
  static final _wisp = vm.Vector4(0.9, 0.92, 0.96, 0.22);

  /// A speech bubble over [me]'s head, turned to the camera.
  void _bubble(FigurePose me, double t, int turn) {
    if (_nBubbles >= _maxBubbles) return;
    final u = t % 3.8;
    final pop = eo(c01(u / 0.25)) * (1 - c01((u - 3.3) / 0.3));
    if (pop <= 0) return;
    final x = me.pos.x, y = me.pos.y + me.bob + 2.0 + 0.03 * math.sin(t * 3), z = me.pos.z;
    final yaw = math.atan2(-(camera.x - x), -(camera.z - z));
    _bubbles.setInstanceTransform(_nBubbles++, setTrs(_m, x + 0.12, y, z, yaw: yaw, roll: 0.06 * math.sin(t * 2 + turn), s: pop));
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  /// Plans which breaks the camera follows: one at a time, for about ten
  /// seconds — the last of the walk there, then the coffee, the smoke or the
  /// chat — at least half a minute apart, clear of the delivery's shots,
  /// a different kind of break each time when there's a choice.
  void _planFollows(BuildPlan plan, List<(double, double)> busyCam) {
    _follows.clear();
    final s = plan.job.serial;
    final end = plan.t0 + plan.len;
    final candidates = <_Follow>[];
    // Not near a kerning close-up (its camera wins).
    final kerns = [
      for (final st in plan.steps)
        if (st != null && st.filmed) (st.a - 2.0, st.e + 1.5),
    ];
    // When the camera is taken (the delivery's shots, with a margin, and
    // the kerning steps), in order.
    final taken = [for (final r in busyCam) (r.$1 - 2, r.$2 + 2), ...kerns]..sort((a, b) => a.$1.compareTo(b.$1));
    for (final b in _breaks) {
      if (b.spot == null) continue;
      final len = 9.0 + 2.5 * rnd(b.seed, s, 42);
      // Best from the last of the walk there; if the camera is busy then,
      // join them later, at the coffee, the smoke or the chat, in a gap.
      final last = math.min(b.depart - 0.3, end - 1);
      for (var from = math.max(math.max(b.leave + 0.3, b.arrive - 4.5), plan.t0 + 5); from + 7 <= last; from += 0.5) {
        if (taken.any((r) => from >= r.$1 && from < r.$2)) continue;
        var to = math.min(from + len, last);
        for (final r in taken) {
          if (r.$1 >= from) to = math.min(to, r.$1);
        }
        if (to - from >= 7) {
          candidates.add(_Follow(b, from, to));
          break;
        }
      }
    }
    candidates.sort((a, b) => a.from.compareTo(b.from));
    var next = plan.t0 + 5.0;
    final shown = <BreakKind>{};
    while (true) {
      final open = candidates.where((c) => c.from >= next).toList();
      if (open.isEmpty) break;
      // Of those starting soon, one of a kind not seen yet this build.
      final soon = open.where((c) => c.from < open.first.from + 15);
      final pick = soon.firstWhere((c) => !shown.contains(c.b.kind), orElse: () => open.first);
      _follows.add(pick);
      shown.add(pick.b.kind);
      next = pick.to + 20 + 12 * rnd(_follows.length, s, 44);
    }
  }

  final _fp = FigurePose();

  /// Adds the camera's request at [t] (priority 1), if a break is being
  /// followed: from behind on the walk there, then a close look at the
  /// coffee, the smoke or the chat. Nothing while something more important
  /// is on (the delivery, a kerning close-up).
  void focus(List<Focus> out, double t) {
    final plan = _plan;
    if (plan == null || plan.job.phase != Phase.build) return;
    if (out.any((f) => f.priority >= 2)) return;
    for (final f in _follows) {
      if (t < f.from || t >= f.to) continue;
      // (The camera cuts in a moment after the plan's start, out a moment
      // before its end.)
      if (t < f.from + 0.7 || t >= f.to - 0.8) return;
      final b = f.b;
      final p = _fp..rest();
      final (walking, heading) = _place(b, t, p);
      // Close up at the spot (blending in as they arrive).
      final at = eio(seg(t, b.arrive - 1.2, b.arrive + 0.6));
      final hx = -math.sin(walking ? heading : 0), hz = -math.cos(walking ? heading : 0);
      final followEye = vm.Vector3(p.pos.x - hx * 6.0, 4.6, p.pos.z - hz * 6.0);
      final followTg = vm.Vector3(p.pos.x + hx * 2.6, 0.8, p.pos.z + hz * 2.6);
      final (closeEye, closeTg, closeFov) = _closeShot(b);
      final eye = followEye + (closeEye - followEye) * at;
      final tg = followTg + (closeTg - followTg) * at;
      out.add(Focus('break ${b.who} ${f.from.round()}', Shot(eye, tg, fov: lerp(42, closeFov, at), settle: 1.5, drift: 0.6), priority: 1));
      return;
    }
  }

  /// A look at [b]'s spot: eye, target and lens.
  (vm.Vector3, vm.Vector3, double) _closeShot(_Break b) {
    switch (b.spot!.group) {
      case 0:
        // The machines' lit fronts from the plaza, the can bin beside them.
        return (vm.Vector3(11.8, 2.4, -7.8), vm.Vector3(16.0, 1.2, -5.4), 42);
      case 1:
        // From high over the way to it: the ashtray, the crate, its sign.
        return (vm.Vector3(-14.2, 5.5, -1.8), vm.Vector3(-16.1, 0.9, 2.5), 38);
      default:
        return (vm.Vector3(-14.8, 2.6, -2.8), vm.Vector3(-18.1, 0.8, 0.0), 36);
    }
  }
}

class _Spot {
  const _Spot(this.at, this.group, {this.sitX, this.face});
  final vm.Vector3 at;

  /// 0: by the vending machines, 1: the smoking corner, 2: the bench.
  final int group;

  /// A seat: sit back onto it, to this x (from [at], in front of it).
  final double? sitX;

  /// A fixed facing (the seats); otherwise people face their group's middle.
  final double? face;
}

/// One person's time off: [who] (a builder, or [CrewBreaks.driver]) is ours
/// to pose over [from]–[to]. A trip away when [spot] is set: stepping off
/// the platform at [start] (their rest spot) at [leave] to [behind] it,
/// along [out] to arrive at [arrive] (coffee: buying at [buyAt], at the
/// spot from [stay]), leaving at [depart] along [back], behind the platform
/// again at [behindAt], stepping on at [stepOn], back at [home]. The
/// driver's trips start and end at [door].
class _Break {
  _Break(this.who, this.from, this.to, this.seed);
  final int who;
  final double from;
  double to;
  final int seed;
  BreakKind kind = BreakKind.stretch;
  vm.Vector3 door = vm.Vector3.zero(), start = vm.Vector3.zero(), behind = vm.Vector3.zero();
  _Spot? spot;
  int spotIndex = -1, machine = -1;
  double leave = 0, arrive = 0, buyAt = 0, stay = 0, depart = 0, behindAt = 0, stepOn = 0, home = 0;
  final out = <vm.Vector3>[], back = <vm.Vector3>[];
}

class _Follow {
  _Follow(this.b, this.from, this.to);
  final _Break b;
  final double from, to;
}

/// Poses for time off, shared by the builders and the delivery driver: in
/// [FigurePose]'s terms (arm pitch 0 down … π up, roll outwards; yaw 0 faces
/// −z).
abstract final class OffDuty {
  /// Standing at ease (see [Idle]): breathing, the weight on one foot then
  /// the other ([shift] of it), a look round ([look] of it).
  static void stand(FigurePose p, double t, int seed, {double shift = 1, double look = 1}) {
    p.lean = 0.02;
    Idle.stand(p, t, Manner.of(seed), shift: shift, look: look);
  }

  /// Walking at [speed] (m/s): [dist] metres into a walk [total] long (its
  /// steps fitted to end with the feet passing), or without them, as if
  /// walking since the clock started.
  static void walk(FigurePose p, double t, double speed, int seed, {double? dist, double? total}) {
    final m = Manner.of(seed), d = dist ?? t * speed;
    Gait.walk(p, total == null ? Gait.phaseAt(d, speed, 1, m) : Gait.phaseOver(d, total, speed, 1, m), speed, m);
  }

  /// A stretch: hands on the hips, a lean back, then a twist of the
  /// shoulders ([f] 0..1 through one).
  static void stretch(FigurePose p, double f, int seed) {
    final k = smooth(0, 0.12, f) * (1 - smooth(0.88, 1, f));
    for (var s = 0; s < 2; s++) {
      p.armRoll[s] = lerp(p.armRoll[s], 0.85, k);
      p.armPitch[s] = lerp(p.armPitch[s], -0.3, k);
    }
    p.lean = lerp(p.lean, -0.2, math.sin(math.pi * c01(f / 0.55)));
    if (f > 0.5) p.twist += (seed.isEven ? 0.45 : -0.45) * math.sin((f - 0.5) / 0.5 * math.pi);
  }

  /// At the vending machine, [u] seconds in: a look, (a press,) the can
  /// drops, a bend down to the tray for it, back up. (The hand's the
  /// break's: on the machine.)
  static void buy(FigurePose p, double u, int seed) {
    stand(p, u, seed, shift: 0);
    final bend = math.sin(math.pi * c01((u - 1.9) / 1.4));
    p.lean = lerp(0.02, 0.6, bend);
    p.bob = -0.12 * bend;
    p.legPitch[0] = 0.2 * bend;
    p.legPitch[1] = -0.1 * bend;
  }

  /// Holding something in hand [s] in front of the chest ([k] of it).
  static void hold(FigurePose p, int s, double k) => p.handTo(s, (s == 0 ? -1 : 1) * 0.13, 0.2, -0.27, k);

  /// A drink from the can: [f] 0..1 through a sip (when [sip]), else the
  /// can held at the chest: the hand straight up the front to the mouth.
  /// Returns how far the can's tipped.
  static double drink(FigurePose p, double f, bool sip) {
    final up = sip ? math.sin(math.pi * c01(f)) : 0.0;
    p.handTo(1, lerp(0.13, 0.05, up), lerp(0.2, 0.52, up), lerp(-0.27, -0.17, up));
    p.lean = lerp(p.lean, -0.1, up);
    p.headPitch -= 0.2 * up;
    return 1.9 * smooth(0.4, 1, up);
  }

  /// Lighting a cigarette, [f] 0..1: both hands cupped at the mouth.
  static void light(FigurePose p, double f) {
    final k = math.sin(math.pi * c01(f));
    p.handTo(0, -0.03, 0.53, -0.16, k);
    p.handTo(1, 0.03, 0.53, -0.16, k);
    p.lean = 0.12 * k;
  }

  /// Smoking, [v] seconds into a 5.2 s cycle: a drag (the hand straight up
  /// to the mouth), then the hand down to the chest.
  static void smoking(FigurePose p, double v) {
    final up = math.sin(math.pi * c01(v / 1.3));
    p.handTo(1, lerp(0.17, 0.035, up), lerp(0.18, 0.54, up), lerp(-0.22, -0.15, up));
    p.lean = lerp(p.lean, -0.1, c01((v - 1.3) / 0.4) * (1 - c01((v - 2.6) / 0.6)));
  }

  /// Putting it out in the ashtray, [f] 0..1: a lean to it (the hand's the
  /// break's: on the ashtray).
  static void stub(FigurePose p, double f) {
    p.lean = 0.3 * math.sin(math.pi * c01(f));
  }

  /// Talking: a hand that explains (the forearm out in front, low), a
  /// nodding head.
  static void talk(FigurePose p, double t, int seed) {
    final g = math.sin(t * 4.3 + seed);
    p.armPitch[1] = 0.6 + 0.12 * g;
    p.armRoll[1] = 0.12 + 0.1 * math.sin(t * 2.9 + seed);
    p.elbow[1] = 1.25 + 0.2 * math.sin(t * 3.7 + seed);
    p.lean = 0.04 + 0.03 * math.sin(t * 7 + seed);
    // Turning to one listener and the other.
    p.headYaw += 0.14 * math.sin(t * 1.3 + seed);
    p.twist += 0.08 * math.sin(t * 1.3 + seed - 0.4);
  }

  /// Listening, with a nod now and then.
  static void listen(FigurePose p, double t, int seed) {
    final nod = math.max(0.0, math.sin(t * 1.6 + seed * 1.3));
    p.lean = 0.02 + 0.09 * nod * math.sin(t * 12).abs();
    p.armRoll[0] = p.armRoll[1] = 0.16;
  }

  /// A good laugh: head back, shoulders shaking, a hand on the belly.
  static void laugh(FigurePose p, double t, int seed) {
    p.lean = -0.24 + 0.04 * math.sin(t * 23 + seed);
    p.bob = 0.015 * math.sin(t * 19 + seed).abs();
    p.armPitch[0] = 0.55;
    p.armRoll[0] = -0.55;
    p.armPitch[1] = 0.25;
    p.armRoll[1] = 0.3;
  }

  /// Sitting down ([down] 0..1): onto a bench seat (at 0.5 m: a seated
  /// figure's hips are 0.36 m above where it stands, see [FigureRig]),
  /// legs forward.
  static void sit(FigurePose p, double down) {
    p.pos.y += 0.19 * down;
    p.legPitch[0] = p.legPitch[1] = 1.45 * down;
    p.lean = lerp(p.lean, -0.05, down);
    if (down > 0) {
      // (Off their feet: no weight to shift.)
      p
        ..sway *= 1 - down
        ..hipRoll *= 1 - down;
      for (var s = 0; s < 2; s++) {
        p.knee[s] = p.foot[s] = double.nan;
      }
    }
  }

  /// Looking at a phone: one hand up in front, head down.
  static void phone(FigurePose p, double t, int seed) {
    p.armPitch[1] = 1.0;
    p.armRoll[1] = -0.35;
    p.lean = 0.18 + 0.02 * math.sin(t * 0.7 + seed);
  }

  // ── Where the hands and the mouth are ─────────────────────────────────────

  static final _rig = FigureRig();

  /// The middle of [p]'s hand [s] (0 = −x side, 1 = +x side), world.
  static vm.Vector3 hand(FigurePose p, int s, vm.Vector3 out) {
    _rig.solve(p);
    return out..setFrom(_rig.palms[s]);
  }

  /// [p]'s mouth, world.
  static vm.Vector3 mouth(FigurePose p, vm.Vector3 out) {
    _rig.solve(p, arms: false);
    return _rig.mouth(1, out);
  }
}
