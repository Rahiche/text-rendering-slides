import 'dart:math' as math;
import 'dart:ui';

import '../layout.dart';
import '../model.dart';
import 'site_crane.dart';
import 'site_crew.dart';
import 'site_fx.dart';
import 'site_plan.dart';
import 'site_rubble.dart';
import 'site_vehicles.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The site's simulation, stepped with the model (so live frames, fast-forward
// and capture agree). It owns everything with state: the crane's planned
// moves and the hook's sway, the crew walking and climbing, the rubble, the
// cleanup machines. Painters only read it.
// ─────────────────────────────────────────────────────────────────────────────

/// Safe spots (on the ground, clear of the wall) for builders 0..5.
const _safeX = [604.0, 618.0, 632.0, 1508.0, 1522.0, 1546.0];
const foremanX = 1532.0;
const riggerX = 588.0;
const mixerX = 1574.0;

class SiteSim extends BoothSystem {
  Job? job;
  SitePlan? site;
  BuildPlan? build;
  double _builtFrom = double.nan;
  double t = 0;

  final crane = CraneTimeline();
  final ball = BallScript();

  /// The ball hangs on the hook during [ballOn, ballOff).
  double ballOn = double.infinity;
  double ballOff = double.infinity;

  // Hook sway (a damped pendulum driven by the trolley's acceleration).
  double swayTh = 0, _swayOm = 0, _lastX = double.nan, _lastV = 0;

  final builders = [for (var z = 0; z < zoneCount; z++) Mover(_safeX[z], z < 3 ? 1 : -1)];
  final _cursor = List.filled(zoneCount, 0);

  Rubble? rubble;
  final dust = Dust();
  final loader = Loader();
  final truck = Truck();

  /// Phase bookkeeping for painters.
  double revealAt = double.infinity;
  double celebrateAt = double.infinity;
  double celebrateLen = 0;
  double demolishAt = double.infinity;
  double demolishLen = 0;
  double cleanupAt = double.infinity;
  double scaffoldGone = double.infinity;
  double cutAt = double.infinity;
  final impacts = <double>[];
  Offset? _lastBall;
  Offset ballPos = const Offset(ballParkX, BL.groundY - ballR);
  bool ballHung = false;

  bool get demolishing => job?.phase == Phase.demolish;

  // ── Phases ────────────────────────────────────────────────────────────────

  @override
  void onPhase(BoothModel m, Job job, Phase phase) {
    t = m.t;
    switch (phase) {
      case Phase.intake:
        _newJob(job, m.t);
      case Phase.build:
        if (this.job != job) _newJob(job, m.t);
        _ensurePlans(job, m.t);
      case Phase.reveal:
        revealAt = m.t;
        _present(m.t);
      case Phase.celebrate:
        celebrateAt = m.t;
        celebrateLen = job.phaseLen;
        _celebrate(m.t, job.phaseLen);
      case Phase.demolish:
        _demolish(job, m.t);
      case Phase.cleanup:
        cleanupAt = m.t;
    }
  }

  void _newJob(Job j, double now) {
    job = j;
    site = null;
    build = null;
    _builtFrom = double.nan;
    rubble = null;
    revealAt = celebrateAt = demolishAt = cleanupAt = scaffoldGone = cutAt = double.infinity;
    celebrateLen = demolishLen = 0;
    impacts.clear();
    _cursor.fillRange(0, zoneCount, 0);
    for (final b in builders) {
      b.climbing = false;
      if (b.y < BL.groundY - 0.5) b.drop();
      b.deck = 0;
    }
    // The hook: put the ball back if it is still on, then wait over the
    // landing for the first pallets.
    crane.truncate(now);
    ball.clear();
    if (_ballOnHook(now)) _returnBall(now);
    crane.goTo(now, Offset(stageX, hookFor(palletFloor, palletH) - 26), clear: 50);
  }

  bool _ballOnHook(double at) => at >= ballOn && at < ballOff;

  void _returnBall(double from) {
    final park = Offset(ballParkX, BL.groundY - 2 * ballR - ballChain);
    var tt = crane.goTo(from, park, clear: 70);
    tt = crane.hold(tt, 0.35, grounded: true);
    ballOff = tt - 0.15;
  }

  void _ensurePlans(Job j, double now) {
    final r = j.raster;
    if (r == null) return;
    site ??= SitePlan(r);
    final start = j.buildStart;
    if (start == null || j.cutAt != null || site!.total == 0) return;
    if (j.phase != Phase.intake && j.phase != Phase.build) return;
    final b = build;
    if (b != null && (start - _builtFrom).abs() < 0.25) {
      // The build began a frame later than predicted: keep the plan.
      b.start = start;
      _builtFrom = start;
      return;
    }
    final replan = b != null;
    if (replan) crane.truncate(now);
    final ready = math.max(now, crane.end) + (replan ? 1.2 : 0.2);
    build = BuildPlan(site!, start, j.buildLen, ready);
    _builtFrom = start;
    _cursor.fillRange(0, zoneCount, 0);
    _planTrips(build!, now);
  }

  void _planTrips(BuildPlan bp, double now) {
    final s = bp.site;
    for (final trip in bp.trips) {
      if (trip.freeAt < now) continue;
      final ready = Offset(stageX, hookFor(palletFloor, trip.height) - 22);
      final grab = Offset(stageX, hookFor(palletFloor, trip.height));
      final base = s.deckY(trip.deck) - 1.5;
      final land = Offset(trip.bayX, hookFor(base, trip.height));
      // Over to the landing in good time, wait, lower onto the stack.
      final t0 = math.max(now, crane.end);
      final travel = 0.8 + (crane.endPose.dx - stageX).abs() / 700;
      final arrive = math.max(t0 + 0.5, math.min(t0 + travel, trip.attachAt - 0.05));
      crane.add(CraneMove.arch(t0, arrive - t0, crane.endPose, ready, math.min(ready.dy, crane.endPose.dy) - 30));
      crane.hold(arrive, math.max(0, trip.attachAt - arrive));
      crane.line(trip.attachAt, grab, attachTime * 0.7, grounded: true);
      crane.hold(trip.attachAt + attachTime * 0.7, attachTime * 0.3, grounded: true);
      // Lift, travel, set down on the deck.
      final top = s.deckY(_erectedAt(bp, trip.landAt)) - 16;
      final apex = math.min(math.min(grab.dy, land.dy) - 26, top - 14 - slingH - trip.height).clamp(trolleyY + 26, 900.0);
      crane.add(CraneMove.arch(trip.departAt, trip.landAt - trip.departAt, grab, land, apex));
      crane.hold(trip.landAt, releaseTime, grounded: true);
      // Hook back up a little.
      crane.line(trip.freeAt, land + const Offset(0, -24), 0.35);
    }
  }

  int _erectedAt(BuildPlan bp, double at) {
    var k = 0;
    for (var i = 1; i < bp.erectAt.length; i++) {
      if (bp.erectAt[i] <= at) k = i;
    }
    return k;
  }

  /// Reveal: the hook rises out of the way, over the site.
  void _present(double now) {
    final s = site;
    final x = s == null ? 1100.0 : (s.wall.right + 40).clamp(900.0, 1460.0);
    crane.goTo(math.max(now, crane.end), Offset(x, 250), clear: 40);
  }

  /// Celebrate: the hook bobs along; near the end it fetches the ball.
  void _celebrate(double now, double len) {
    final t0 = math.max(now, crane.end);
    final p = crane.endPose;
    var tt = t0;
    while (tt < now + len - 4.2) {
      tt = crane.line(tt, p + const Offset(0, -18), 0.45);
      tt = crane.line(tt, p, 0.45);
    }
    if (len >= 4) _fetchBall(now + len - 3.4);
  }

  double _fetchBall(double from, {bool quick = false}) {
    final park = Offset(ballParkX, BL.groundY - 2 * ballR - ballChain);
    var tt = crane.goTo(from, park, clear: 60, dur: quick ? 0.9 : 1.5);
    tt = crane.hold(tt, quick ? 0.2 : 0.3, grounded: true);
    ballOn = tt - 0.1;
    ballOff = double.infinity;
    return tt;
  }

  // ── Demolition (and the cleanup that follows, planned at once) ────────────

  void _demolish(Job j, double now) {
    demolishAt = now;
    final d = j.phaseLen;
    demolishLen = d;
    final cut = j.cutAt != null;
    if (cut) cutAt = now;
    scaffoldGone = now + math.min(1.0, 0.15 * math.max(d, 1));
    for (final b in builders) {
      b.hurry = true;
      if (b.y < BL.groundY - 0.5) b.drop();
    }
    final s = site;
    if (d <= 0 || s == null) {
      crane.truncate(now);
      ball.clear();
      if (_ballOnHook(now)) _returnBall(now);
      return;
    }
    final standing = j.laid(now).clamp(0, s.total);
    final bp = build;
    // Bricks in the builders' hands when a build is cut short drop too.
    var count = standing;
    if (cut && bp != null) {
      while (count < s.total && bp.landTime(count) - flightTime <= now) {
        count++;
      }
    }
    final rb = Rubble(s, count, standing: standing);
    for (var i = standing; i < count; i++) {
      rb.y[i] = s.cy[i] - 20 - 10 * rb.rv[i];
      rb.vx[i] = (rb.ru[i] - 0.5) * 60;
      rb.vy[i] = -60;
      rb.since[i] = now;
    }
    rubble = rb;

    // Standing wall bounds.
    var l = double.infinity, r = double.negativeInfinity, top = double.infinity;
    for (var i = 0; i < standing; i++) {
      l = math.min(l, s.cx[i] - s.b / 2);
      r = math.max(r, s.cx[i] + s.b / 2);
      top = math.min(top, s.cy[i] - s.b / 2);
    }
    final k = d / 12;
    crane.truncate(now);
    ball.clear();
    if (standing > 0) {
      final h = BL.groundY - top;
      // A short demolition (a sample making way) moves briskly.
      final quick = d < 9;
      var tt = _ballOnHook(now) ? now : _fetchBall(now, quick: quick);
      final highY = math.min(top - 120, 420.0);
      // Swing 1: from the right, through the upper part of the wall.
      final y1 = top + math.max(ballR + 4, 0.42 * h);
      final x1 = (r - math.min(0.32 * (r - l), 230)).clamp(trolleyMin + 40, trolleyMax - 30);
      final len1 = y1 - trolleyY;
      final th1 = math.asin(((r + ballR + 28 - x1) / len1).clamp(0.2, 0.75));
      tt = crane.goTo(tt, Offset(x1, highY), dur: quick ? 0.65 : 1.2, clear: 40);
      final pull = quick ? 0.28 : 0.5;
      ball.segs.add(SwingSeg.ease(tt, tt + pull, 0, th1));
      tt = crane.hold(tt, pull);
      final lower = quick ? 0.25 : 0.45;
      ball.segs.add(SwingSeg.ease(tt, tt + lower, th1, th1));
      tt = crane.line(tt, Offset(x1, y1 - ballR - ballChain), lower);
      final release = tt;
      final swing1 = d >= 9 ? 2.3 : 2.0;
      ball.segs.add(SwingSeg.swing(tt, tt + swing1, th1, len1));
      tt = crane.hold(tt, swing1);
      if (d >= 9 && r - l > 120) {
        // Swing 2: shift left, lower, through the rest.
        final y2 = top + math.max(ballR + 4, 0.7 * h);
        final x2 = (l + math.min(0.34 * (r - l), 230)).clamp(trolleyMin + 40, trolleyMax - 30);
        final len2 = y2 - trolleyY;
        const th2 = 0.55;
        final from = ball.theta(tt) ?? 0;
        ball.segs.add(SwingSeg.ease(tt, tt + 1.3, from, th2));
        tt = crane.line(tt, Offset(x2, y2 - ballR - ballChain), 1.3);
        ball.segs.add(SwingSeg.swing(tt, tt + 2.1, th2, len2));
        tt = crane.hold(tt, 2.1);
      }
      final last = ball.theta(tt) ?? 0;
      ball.segs.add(SwingSeg.ease(tt, tt + 0.9, last, 0));
      crane.goTo(tt, Offset((r + 50).clamp(900.0, trolleyMax - 30), 300), dur: 1.4, clear: 30);
      // Whatever still stands topples, after the first blow and in time to
      // settle before the phase ends.
      final fall = math.min(math.max(now + 0.6 * d, release + 0.8), now + d - 1.6);
      rb.collapse(fall, 0.55 * math.max(0.6, k));
    }

    // Cleanup, planned now (its length is known: 5 s after a cut).
    final dc = cut ? (count == 0 ? 0.0 : 5.0) : phaseSeconds[Phase.cleanup]!;
    final c0 = now + d;
    if (dc <= 0) return;
    final kc = dc / 10;
    // Loader: drives in once the rubble has mostly settled, pushes it to the
    // pile, scoops it into the truck, leaves.
    loader.x.clear();
    loader.lift.clear();
    loader.tip.clear();
    loader.scooped = false;
    loader.dumped = false;
    final enter = now + 0.72 * d;
    final xStart = math.min(1540.0, r + 70);
    loader.from = enter;
    loader.pushFrom = enter + 0.6 * math.max(0.5, k);
    loader.pushTo = c0 + 0.24 * dc;
    loader.scoopAt = loader.pushTo + 0.1;
    loader.dumpAt = loader.scoopAt + 0.75 * math.max(0.55, kc);
    loader.x
      ..key(enter, 1700)
      ..key(loader.pushFrom, xStart)
      ..key(loader.pushTo, pileX)
      ..key(loader.scoopAt, pileX + 4)
      ..key(loader.dumpAt + 0.9, pileX + 6)
      ..key(loader.dumpAt + 5.2, 1710);
    loader.lift
      ..key(loader.scoopAt, 0)
      ..key(loader.dumpAt - 0.05, 1)
      ..key(loader.dumpAt + 0.6, 1)
      ..key(loader.dumpAt + 1.1, 0.2);
    loader.tip
      ..key(loader.dumpAt, 0)
      ..key(loader.dumpAt + 0.3, 1)
      ..key(loader.dumpAt + 0.6, 1)
      ..key(loader.dumpAt + 0.95, 0);
    loader.to = loader.dumpAt + 5.3;

    // Truck: comes from the factory, waits by the pile, is loaded, backs up
    // to the factory's hopper, tips, pours, drives off.
    truck.x.clear();
    truck.tilt.clear();
    final arrive = math.max(now + 0.6, c0 - 0.4);
    truck.from = arrive - 4.2;
    truck.reverseFrom = loader.dumpAt + 0.75;
    truck.reverseTo = math.max(truck.reverseFrom + 1.2, c0 + 0.58 * dc);
    truck.pourFrom = truck.reverseTo + 0.45;
    truck.pourTo = math.max(truck.pourFrom + 1.0, c0 + 0.93 * dc);
    truck.x
      ..key(truck.from, -200)
      ..key(arrive, truckLoadX)
      ..key(truck.reverseFrom, truckLoadX)
      ..key(truck.reverseTo, truckDumpX)
      ..key(truck.pourTo + 0.7, truckDumpX)
      ..key(truck.pourTo + 6.5, 1780);
    truck.tilt
      ..key(truck.reverseTo + 0.05, 0)
      ..key(truck.pourFrom + 0.2, 1)
      ..key(truck.pourTo - 0.1, 1)
      ..key(truck.pourTo + 0.6, 0);
    truck.to = truck.pourTo + 6.6;

    // The crane puts the ball back while the truck is away.
    final back = c0 + 0.32 * dc;
    _returnBallAt(back);
    crane.goTo(back + 2.0, Offset(stageX, hookFor(palletFloor, palletH) - 26), clear: 50);
  }

  void _returnBallAt(double from) {
    final park = Offset(ballParkX, BL.groundY - 2 * ballR - ballChain);
    var tt = crane.goTo(from, park, clear: 70, dur: 1.4);
    tt = crane.hold(tt, 0.35, grounded: true);
    ballOff = tt - 0.15;
  }

  // ── Stepping ──────────────────────────────────────────────────────────────

  @override
  void update(BoothModel m, double dt) {
    t = m.t;
    final j = m.job;
    if (j == null) return;
    if (j != job) _newJob(j, t);
    _ensurePlans(j, t);
    crane.prune(t);
    _sway(dt);
    _crew(j, dt);
    _ball(dt);
    final rb = rubble;
    if (rb != null) {
      if (j.phase == Phase.demolish && ballHung && dt > 0) {
        final prev = _lastBall;
        if (prev != null) {
          final v = (ballPos - prev) / dt;
          final before = rb.standingCount;
          rb.hit(ballPos, v, t);
          if (rb.standingCount < before - 3 && (impacts.isEmpty || t - impacts.last > 0.6)) {
            impacts.add(t);
            if (impacts.length > 8) impacts.removeAt(0);
          }
        }
      }
      rb.step(t, dt);
      if (loader.visible(t)) {
        if (t >= loader.pushFrom && t <= loader.pushTo + 0.05) rb.push(loader.x.at(t), t);
        if (!loader.scooped && t >= loader.scoopAt) {
          loader.scooped = true;
          rb.scoop(t);
        }
        rb.follow(t, loader.x.at(t), loader.bucketFloor(t));
        if (!loader.dumped && t >= loader.dumpAt + 0.15) {
          loader.dumped = true;
          rb.dump(t, loader.bucketFloor(t));
        }
      }
      if (truck.visible(t)) {
        rb.land(t, truck);
        if (t >= truck.pourFrom) rb.pour(t, truck.pourFrom, truck.pourTo, truck);
      }
      for (final (x, y, s) in rb.dust) {
        dust.add(x, y, s, t);
      }
      rb.dust.clear();
    }
    _lastBall = ballHung ? ballPos : null;
  }

  void _sway(double dt) {
    if (dt <= 1e-4) return;
    final p = crane.at(t);
    final x = p.dx;
    if (_lastX.isNaN) {
      _lastX = x;
      _lastV = 0;
      return;
    }
    final v = (x - _lastX) / dt;
    final a = (v - _lastV) / dt;
    _lastX = x;
    _lastV = v;
    if (crane.grounded(t)) {
      swayTh *= math.max(0, 1 - 12 * dt);
      _swayOm = 0;
      return;
    }
    final len = math.max(40.0, p.dy - trolleyY);
    _swayOm += (-(gravity / len) * swayTh - 0.045 * a.clamp(-8000.0, 8000.0) / len - 2.6 * _swayOm) * dt;
    swayTh = (swayTh + _swayOm * dt).clamp(-0.12, 0.12);
  }

  /// Hook position with sway, and the line it hangs from.
  (double, Offset) hookAt(double at) {
    final p = crane.at(at);
    final th = demolishing && _ballOnHook(at) ? (ball.theta(at) ?? swayTh) : swayTh;
    final len = p.dy - trolleyY;
    return (p.dx, Offset(p.dx + len * math.sin(th), trolleyY + len * math.cos(th)));
  }

  void _ball(double dt) {
    ballHung = _ballOnHook(t);
    if (!ballHung) {
      ballPos = const Offset(ballParkX, BL.groundY - ballR);
      return;
    }
    final p = crane.at(t);
    final th = ball.theta(t) ?? swayTh;
    final len = p.dy - trolleyY + ballChain + ballR;
    ballPos = Offset(p.dx + len * math.sin(th), trolleyY + len * math.cos(th));
  }

  // ── Crew goals ────────────────────────────────────────────────────────────

  void _crew(Job j, double dt) {
    final s = site;
    final u = j.since(t);
    final len = j.phaseLen;
    final maxDeck = s?.lifts ?? 0;
    double deckY(int k) => s == null ? BL.groundY : s.deckY(k);
    double ladderAt(double x) {
      if (s == null) return x;
      return (x - s.sL).abs() < (x - s.sR).abs() ? s.sL + 9 : s.sR - 9;
    }

    for (var z = 0; z < zoneCount; z++) {
      final b = builders[z];
      b.gFace = 0;
      switch (j.phase) {
        case Phase.intake:
          _prep(b, z, j, s);
        case Phase.build:
          final bp = build;
          if (bp == null || s == null) {
            _prep(b, z, j, s);
          } else {
            _work(b, z, s, bp);
          }
        case Phase.reveal:
          b.hurry = false;
          b.gDeck = maxDeck;
          b.gx = s == null ? b.x : s.clampX(s.zoneMid(z));
          b.gFace = z < 3 ? 1 : -1;
          b.act = Act.watch;
        case Phase.celebrate:
          if (u < len - 3.2) {
            b.hurry = false;
            b.gDeck = maxDeck;
            b.gx = s == null ? b.x : s.clampX(s.zoneMid(z));
            b.act = Act.cheer;
          } else {
            _toSafety(b, z);
          }
        case Phase.demolish:
          _toSafety(b, z);
          b.act = Act.watch;
        case Phase.cleanup:
          _toSafety(b, z);
          b.hurry = false;
          b.act = Act.coffee;
      }
      if (s == null && b.y < BL.groundY - 0.5 && !b.falling) b.drop();
      b.step(dt, deckY, ladderAt, maxDeck);
    }
  }

  void _toSafety(Mover b, int z) {
    b.gDeck = 0;
    b.gx = _safeX[z];
    b.hurry = true;
    b.gFace = z < 3 ? 1 : -1;
    b.act = Act.idle;
  }

  /// Intake: walk in, get ready on the ground behind the plot.
  void _prep(Mover b, int z, Job j, SitePlan? s) {
    final u = t - j.startedAt;
    b.gDeck = 0;
    b.hurry = false;
    if (u < 0.3 + z * 0.3) {
      b.gx = b.x;
      b.act = Act.idle;
      return;
    }
    if (z == 5 && u < 5.8) {
      b.gx = mixerX - 18;
      b.gFace = 1;
      b.act = Act.shovel;
      return;
    }
    final home = s == null ? 720 + z * 120.0 : s.clampX(s.zoneL[z] + 8);
    b.gx = home;
    b.act = switch (z) {
      0 => Act.stretch,
      1 || 4 => Act.hammer,
      2 => Act.plank,
      _ => Act.idle,
    };
    b.gFace = 1;
  }

  /// Build: follow your own bricks along your stretch, climb with the wall.
  void _work(Mover b, int z, SitePlan s, BuildPlan bp) {
    final list = s.zoneBricks[z];
    var k = _cursor[z];
    while (k < list.length && bp.landTime(list[k]) <= t) {
      k++;
    }
    _cursor[z] = k;
    final lift = bp.liftAt(t);
    b.hurry = false;
    if (k < list.length) {
      final n = list[k];
      final wait = bp.landTime(n) - t;
      b.gx = s.clampX(s.cx[n] - 4);
      b.gDeck = wait < 2.5 ? s.liftOf(n) : lift;
      b.hurry = (b.x - b.gx).abs() > 30;
      b.act = wait < 1.4 ? Act.work : Act.hammer;
    } else {
      // Nothing (more) to lay in this stretch: keep out of the others' way.
      b.gx = list.isEmpty ? s.clampX(mix(s.sL + 10, s.sR - 10, z / (zoneCount - 1))) : b.x;
      b.gDeck = lift;
      b.act = Act.hammer;
    }
  }
}
