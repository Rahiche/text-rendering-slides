part of 'factory_draw.dart';

/// The crew on the factory floor: the hopper and press operators, the
/// stoker, the forklift driver and the foreman with his clipboard. They cheer
/// when a name is done.
extension _Crew on _Frame {
  bool get _cheer => j?.phase == Phase.celebrate && (j!.since(t)) < 10;

  void crew() {
    hopperOperator();
    pressOperator();
    forklifter();
    stoker();
    foreman();
  }

  /// Keeps the kiln's fire up: a poke into the firebox right as it flares
  /// (every 2.6 s, see kilnLive), and sweat to wipe in between.
  void stoker() {
    const feet = Offset(455, FG.floor);
    final q = ((t / 2.6 - 0.3 + 0.18) % 1 + 1) % 1; // 0.18 at the flare
    final thrust = bump(seg(q, 0, 0.36));
    final f = Pose()
      ..lean = 0.08 + 0.3 * thrust
      ..upA = lerp(0.85, 1.5, thrust)
      ..foA = lerp(1.2, 1.55, thrust)
      ..upB = lerp(0.55, 1.25, thrust)
      ..foB = lerp(1.0, 1.5, thrust);
    final ep = (t / 7.8).floor();
    final resting = thrust == 0 && rnd(ep, 61) < 0.4 && q > 0.45;
    if (resting) f.wipe(t);
    if (_cheer) f.cheer(t, 6);
    final g = worker(feet, 31, -1, f);
    if (!resting && !_cheer) {
      // The poker, from the back hand through the front one into the fire.
      final d = g.handA - g.handB;
      final n = d.distance;
      if (n > 0.1) {
        final u = d / n;
        final tip = g.handA + u * 15;
        c.drawLine(g.handB - u * 2, tip, st(BP.inkDim, 1.4));
        c.drawLine(tip, tip + Offset(u.dy, -u.dx) * 3, st(BP.inkDim, 1.4));
      }
    }
    if (resting) sweat(g.head, t - ep * 7.8, -1);
  }

  /// Pulls the hopper's gate lever for every crate; sweeps stray rubble
  /// into the bin while the recycling comes in.
  void hopperOperator() {
    const feet = Offset(158, FG.floor);
    final ce = sys.cleanupEnd;
    final sweeping = sys.cleanupLen > 0 && t > ce - 4.6 && t < ce + 2.6 && gate == 0;
    if (sweeping) {
      final x = 160 + 5 * math.sin(t * 4.5);
      final f = Pose()
        ..upA = 1.1
        ..foA = 0.6
        ..upB = 0.9
        ..foB = 0.5
        ..lean = 0.3;
      final g = worker(Offset(x, FG.floor), 31, -1, f);
      broom(g.handA, g.elbowA, FG.floor, -6 * math.sin(t * 4.5));
      c.drawLine(const Offset(138, 688), const Offset(146, 674), st(BP.line, 1.6));
      c.drawCircle(const Offset(146, 674), 2.4, fl(BP.amber));
      return;
    }
    final f = Pose();
    final pull = gate;
    f
      ..upA = lerp(2.4, 1.25, pull)
      ..foA = lerp(2.75, 1.6, pull)
      ..lean = 0.12 * pull;
    if (_cheer) f.cheer(t, 1);
    if (work[0] >= 0 && pull == 0) {
      // Watching the reader.
      f
        ..head = -0.35
        ..upB = 0.9
        ..foB = 2.2;
    } else if (pull == 0 && rnd((t / 8).floor(), 33) < 0.35) {
      // Coffee between names.
      f
        ..upB = 0.4
        ..foB = 2.6
        ..head = 0.1;
    }
    final g = worker(feet, 31, -1, f);
    final knob = _cheer ? const Offset(146, 674) : g.handA;
    c.drawLine(const Offset(138, 688), knob, st(BP.line, 1.6));
    c.drawCircle(knob, 2.4, fl(BP.amber));
    if (!_cheer && work[0] < 0 && pull == 0 && rnd((t / 8).floor(), 33) < 0.35) coffee(g.handB, t);
  }

  void pressOperator() {
    const feet = Offset(378, FG.floor);
    final w = work[3];
    final pull = w >= 0 ? eo(seg(w, 0, 0.2)) * (1 - eio(seg(w, 0.5, 0.85))) : 0.0;
    final f = Pose()
      ..upA = lerp(2.4, 1.25, pull)
      ..foA = lerp(2.75, 1.6, pull)
      ..lean = 0.12 * pull;
    if (w < 0) {
      final ep = (t / 6).floor();
      final r = rnd(ep, 41);
      if (r < 0.3) {
        f.wipe(t);
      } else if (r < 0.55) {
        f.watch();
      }
    }
    if (_cheer) f.cheer(t, 3);
    final g = worker(feet, 31, -1, f);
    final knob = _cheer || (w < 0 && rnd((t / 6).floor(), 41) < 0.3) ? const Offset(368, 676) : g.handA;
    c.drawLine(const Offset(360, 688), knob, st(BP.line, 1.6));
    c.drawCircle(knob, 2.4, fl(BP.amber));
    if (w < 0 && rnd((t / 6).floor(), 41) < 0.3) sweat(g.head, t - (t / 6).floor() * 6, -1);
  }

  /// Shuttles crates of fonts from the stack by the hopper to the one by the
  /// press (the fonts machine's supply).
  void forklifter() {
    const xa = 216.0, xb = 302.0, speed = 26.0, pause = 3.0;
    const leg = (xb - xa) / speed;
    const per = 2 * leg + 2 * pause + 6;
    final u = t % per;
    double x;
    int dir;
    var lift = 4.0;
    var load = true;
    var moving = true;
    if (u < leg) {
      x = xa + speed * u;
      dir = 1;
    } else if (u < leg + pause) {
      x = xb;
      dir = 1;
      moving = false;
      final a = (u - leg) / pause;
      lift = 4 + 26 * bump(a);
      load = a < 0.5;
    } else if (u < 2 * leg + pause) {
      x = xb - speed * (u - leg - pause);
      dir = -1;
      load = false;
    } else {
      x = xa;
      dir = -1;
      moving = false;
      final a = (u - 2 * leg - pause) / (pause + 6);
      lift = 4 + 4 * bump(seg(a, 0.1, 0.5));
      load = a > 0.3;
    }
    c.save();
    c.translate(x, FG.floor);
    c.scale(0.78);
    final driver = Pose()..sit(20, 6);
    driver
      ..upA = 1.3
      ..foA = 1.6
      ..head = moving ? 0 : -0.3;
    if (_cheer) driver.cheer(t, 4);
    final tip = forklift(Offset.zero, dir, lift, moving ? x / 4 : 0, driver: driver, t: t);
    if (load) {
      final r = Rect.fromLTWH(tip.dx - 11, tip.dy - 14, 22, 14);
      crate(r, BP.lineDim, w: 1.2);
      paintFit(tx.get('あ', FS.name(10, BP.inkDim), key: 'fl'), r.deflate(3), fitHeight: true);
    }
    c.restore();
  }

  /// Checks every pallet that leaves, ticks it off.
  void foreman() {
    const feet = Offset(524, FG.floor);
    final f = Pose()
      ..upB = 0.55
      ..foB = 1.55
      ..upA = 0.65
      ..foA = 1.75 + 0.2 * math.sin(t * 11)
      ..head = 0.15;
    // Nods as each pallet passes.
    var nod = 0.0;
    final deps = d?.departs;
    if (deps != null) {
      for (final dep in deps) {
        if (dep > t) break;
        if (cutAt != null && dep > cutAt!) break;
        nod = math.max(nod, bump(seg(t, dep + 1.4, dep + 1.9)));
      }
    }
    f.head += 0.3 * nod;
    final ep = (t / 9).floor();
    if (nod == 0 && rnd(ep, 51) < 0.3 && t - ep * 9 > 6) f.watch();
    if (_cheer) f.cheer(t, 5);
    final g = worker(feet, 32, -1, f, hat: BP.green);
    clipboard(g.handB, done: nod > 0.3);
  }
}
