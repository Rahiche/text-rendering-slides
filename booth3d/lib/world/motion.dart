import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import 'ease.dart';
import 'figure_rig.dart';

// How people move: a walk (and a run) worked out from how fast they go,
// standing about (breathing, the weight on one foot, a look round, a
// fidget), each in their own manner. Plain Dart (tested on its own); it
// writes [FigurePose]s.

/// Someone's own way of moving, from a seed: longer or shorter steps, a
/// bigger or smaller arm swing, how they hold themselves, how much their
/// hips go, how often they breathe, look round, shift their weight, fidget.
class Manner {
  Manner(this.seed)
    : step = 0.93 + 0.14 * rnd(seed, 41),
      arms = 0.7 + 0.6 * rnd(seed, 42),
      posture = -0.015 + 0.05 * rnd(seed, 43),
      hips = 0.7 + 0.7 * rnd(seed, 44),
      elbows = 0.1 * rnd(seed, 45),
      breath = 3.3 + 1.7 * rnd(seed, 46),
      glance = 1.9 + 2.6 * rnd(seed, 47),
      settle = 5.5 + 8 * rnd(seed, 48),
      restless = rnd(seed, 49);

  final int seed;
  final double step, arms, posture, hips, elbows, breath, glance, settle, restless;

  static final _all = <int, Manner>{};

  /// The manner for [seed] (made once).
  static Manner of(int seed) => _all[seed] ??= Manner(seed);
}

/// Walking and running.
///
/// The phase is π a step (leg 0 forward, its heel striking, at π/2) and
/// goes with the distance walked: [phaseAt] for an even pace, or add up
/// distance ÷ [stepLength] × π step by step. A walk's stance takes 60 % of
/// the cycle (both feet down for a moment at each step), a run's a third
/// (it leaves the ground between steps).
///
/// The foot on the ground stays put: it lands on its heel, rolls flat, the
/// heel comes up and it pushes off its toe, and the leg reaches it from
/// the hips wherever they are (the knee giving as the weight comes on, then
/// near straight as the body vaults over it). The hips ride that leg (in a
/// run, they fly between steps), move over it and drop on the other side.
/// The leg in the air leaves where its push-off left it and comes through
/// to where its heel strikes, the knee folding to clear the ground (high in
/// a run). The arms swing against the legs, a little behind them, the
/// elbows bending as they come forward (a run pumps them, bent square).
abstract final class Gait {
  /// How fast a walk becomes a run (m/s, for size 1; a smaller person runs
  /// sooner).
  static const runFrom = 2.0, runBy = 2.35;

  /// How much of a run going at [speed] is.
  static double running(double speed, [double size = 1]) => smooth(runFrom, runBy, speed / math.sqrt(size));

  /// How long a step is (metres) at [speed] (m/s) for someone [size] tall
  /// (1: 1.72 m) walking in manner [m]: longer the faster they go (and
  /// quicker); a run's steps are longer still. (Bigger people's steps are
  /// longer, the same for the same speed relative to their size.)
  static double stepLength(double speed, [double size = 1, Manner? m]) {
    final rel = math.max(speed, 0.05) / math.sqrt(size);
    final walk = 0.63 * math.sqrt(rel), run = rel / (2.6 + 0.1 * (rel - 2.5));
    return lerp(walk, run, smooth(runFrom, runBy, rel)) * size * (m?.step ?? 1);
  }

  /// The phase after [dist] metres at an even [speed].
  static double phaseAt(double dist, double speed, [double size = 1, Manner? m]) => dist / stepLength(speed, size, m) * math.pi;

  /// The phase after [dist] metres of a walk [total] long at [speed]: the
  /// steps stretched or shrunk a touch so that it ends with the feet
  /// passing (no step left half taken).
  static double phaseOver(double dist, double total, double speed, [double size = 1, Manner? m]) {
    final step = stepLength(speed, size, m);
    final n = math.max(1, (total / step).round());
    return dist / (total / n) * math.pi + math.pi / 2;
  }

  static final _g = _Stride();

  /// Poses [p] walking (or running) at [phase], at [speed] m/s, in manner
  /// [m]; [amount] (0..1) of it (for easing in and out of a stand).
  static void walk(FigurePose p, double phase, double speed, Manner m, {double size = 1, double amount = 1}) {
    final g = _g..setUp(speed, size, m);
    final run = g.run, a = amount;
    final u0 = _frac((phase - math.pi / 2) / (2 * math.pi));
    p.stride = phase;
    final hip = g.hip(u0), roll = g.roll(u0);
    for (var s = 0; s < 2; s++) {
      final side = s == 0 ? -1.0 : 1.0, u = s == 0 ? u0 : _frac(u0 - 0.5);
      double th, knee, foot;
      if (u < g.duty) {
        // On the ground: the leg reaches the foot from the hips.
        final st = u / g.duty;
        foot = g.footPitch(st);
        (th, knee) = g.reach(st, side, hip, roll);
      } else {
        // In the air: the ankle from where the push-off left it to where
        // the strike will want it (a little past, then back), lifted
        // between (the heel high behind early on, in a run to the seat),
        // the leg reaching it from the hips.
        final x = (u - g.duty) / (1 - g.duty);
        const e = 0.004;
        final (f0, y0) = g.ankle(1);
        final (fb, yb) = g.ankle(1 - e);
        final (f1, y1) = g.ankle(0);
        final (fa, ya) = g.ankle(e);
        final k = (1 - g.duty) / g.duty / e;
        final f = _hermite(x, f0, (f0 - fb) * k, f1, (fa - f1) * k * lerp(0.6, 0.25, run));
        final y = _hermite(x, y0, (y0 - yb) * k, y1, (ya - y1) * k) + g.raise * math.pow(math.sin(math.pi * math.pow(x, 0.6)), 2);
        (th, knee) = g.reachTo(f, y, side, hip, roll);
        final p0 = g.footPitch(1), pb = g.footPitch(1 - e), p1 = g.footPitch(0), pa = g.footPitch(e);
        foot = _hermite(x, p0, (p0 - pb) * k, p1, (pa - p1) * k);
      }
      p.legPitch[s] = th * a;
      p.knee[s] = lerp(0.07, knee, a);
      p.foot[s] = foot * a;
    }
    // A run's flight: the hips carry on up, not down onto the folded legs.
    final top = math.max(FigureRig.extent(p.legPitch[0], p.knee[0], p.foot[0]), FigureRig.extent(p.legPitch[1], p.knee[1], p.foot[1]));
    p.bob = math.max(0.0, hip - top) * size * a;
    // The hips over the foot that carries them, dropping on the other side.
    final over = -math.cos(2 * math.pi * (u0 - g.duty / 2));
    p
      ..sway = g.sway * size * over * a
      ..hipRoll = roll * a;
    // Leaning into it, the faster the more; a nod with each push-off.
    final rel = speed / math.sqrt(size);
    final lean = lerp(m.posture + 0.025 + 0.03 * math.min(rel, 2.0), 0.1 + 0.04 * math.min(rel - 2.3, 2.0), run);
    p.lean = lerp(p.lean, lean + 0.012 * math.cos(4 * math.pi * u0), a);
    p.headPitch = lerp(p.headPitch, lerp(0.02, -0.75 * lean, run), a);
    // The arms against the legs (a little behind them).
    final k = (rel / 1.3).clamp(0.35, 1.3) * m.arms;
    for (var s = 0; s < 2; s++) {
      final u = s == 0 ? u0 : _frac(u0 - 0.5);
      final f = -math.cos(2 * math.pi * (u - 0.035));
      final wPitch = 0.04 + (f > 0 ? 0.36 : 0.22) * f * k, wElbow = 0.3 + m.elbows + 0.35 * math.max(0.0, f) * k, wRoll = 0.1 - 0.05 * math.max(0.0, f);
      final rPitch = 0.22 + (f > 0 ? 0.55 : 0.42) * f, rElbow = 1.45 + 0.22 * f, rRoll = 0.16 - 0.1 * math.max(0.0, f);
      p.armPitch[s] = lerp(p.armPitch[s], lerp(wPitch, rPitch, run), a);
      p.armRoll[s] = lerp(p.armRoll[s], lerp(wRoll, rRoll, run), a);
      p.elbow[s] = lerp(p.elbow[s].isNaN ? 0.58 : p.elbow[s], lerp(wElbow, rElbow, run), a);
    }
  }

  static double _hermite(double x, double y0, double m0, double y1, double m1) {
    final x2 = x * x, x3 = x2 * x;
    return (2 * x3 - 3 * x2 + 1) * y0 + (x3 - 2 * x2 + x) * m0 + (-2 * x3 + 3 * x2) * y1 + (x3 - x2) * m1;
  }

  static double _frac(double v) => v - v.floorToDouble();
}

/// One gait's numbers (a speed, a manner), and where its feet and hips are
/// through a cycle (size 1; [Gait.walk]).
class _Stride {
  double run = 0, duty = 0.6, cycle = 1.4, heelAhead = 0.3, strike = 0.24, pushOff = -0.6, rock2 = 0.6, raise = 0.09, sway = 0, rollBy = 0;
  static const _rock1 = 0.15;

  void setUp(double speed, double size, Manner m) {
    final rel = speed / math.sqrt(size);
    run = smooth(Gait.runFrom, Gait.runBy, rel);
    duty = lerp(0.6, 0.36 - 0.08 * smooth(2.5, 5, rel), run);
    final step = Gait.stepLength(speed, size, m) / size;
    cycle = 2 * step;
    // The foot rolls less for short steps (and lands flatter in a run).
    final k = c01(step / 0.7);
    strike = lerp(0.24, 0.05, run) * k;
    pushOff = lerp(-0.6, -0.75, run) * k;
    rock2 = lerp(0.6, 0.45, run);
    // The heel lands far enough ahead that the hips pass over the middle
    // of the foot halfway through the stance (a run lands nearer under the
    // body and pushes off further behind).
    heelAhead = duty * step - (0.055 + 0.065 * k) - 0.12 * run;
    raise = lerp(0.07, 0.26, run) * c01(step / 0.5);
    sway = lerp(0.022, 0.008, run) * m.hips;
    rollBy = lerp(0.06, 0.035, run) * m.hips;
  }

  /// The hips' roll at leg 0's cycle point [u0] (the side on the ground up).
  double roll(double u0) => -rollBy * math.cos(2 * math.pi * (u0 - duty * 0.2));

  /// A foot on the ground [s] of the way through its stance: its pitch.
  double footPitch(double s) {
    if (s < _rock1) return strike * (1 - smooth(0, _rock1, s));
    if (s < rock2) return 0;
    return pushOff * math.pow(c01((s - rock2) / (1 - rock2)), 1.6);
  }

  /// …and its ankle: how far ahead of the hips (the hips having gone on
  /// since the strike) and how high, as it pivots on its heel, then its toe.
  (double, double) ankle(double s) {
    final phi = footPitch(s), c = math.cos(phi), n = math.sin(phi);
    final heel = heelAhead - s * duty * cycle;
    if (s < _rock1) return (heel + 0.055 * c - 0.08 * n, 0.08 * c + 0.055 * n);
    if (s < rock2) return (heel + 0.055, 0.08);
    return (heel + 0.24 - 0.185 * c - 0.08 * n, 0.08 * c - 0.185 * n);
  }

  /// The knee's bend wanted on the ground: a give as the weight comes on,
  /// near straight as the body goes over (a run's deeper).
  double knee(double s) {
    final walk = s < 0.2 ? lerp(0.07, 0.25, smooth(0, 0.2, s)) : lerp(0.25, 0.1, smooth(0.2, 0.5, s));
    final runK = s < 0.42 ? lerp(0.36, 0.7, smooth(0, 0.42, s)) : lerp(0.7, 0.4, smooth(0.42, 1, s));
    return lerp(walk, runK, run);
  }

  static double _leg(double knee) {
    const a = FigureRig.thigh, b = FigureRig.shin;
    return math.sqrt(a * a + b * b + 2 * a * b * math.cos(knee));
  }

  /// The hips' height if leg [side] at stance [s] holds them, its knee bent
  /// [knee].
  double _hipFor(double s, double knee, double side, double roll) {
    final (f, y) = ankle(s);
    final d = _leg(knee);
    return y + math.sqrt(math.max(0.0, d * d - f * f)) - side * FigureRig.hipX * math.sin(roll);
  }

  /// The hips' height at leg 0's cycle point [u0]: held by the leg on the
  /// ground (as it gives, then as the body goes over it); late on it,
  /// settling to where the next strike will have them; with both feet
  /// down, by the one that's just landed; in a run's flight, an arc from
  /// one foot to the next.
  double hip(double u0) {
    if (run <= 0) return _walkHip(u0);
    final h = _runHip(u0);
    return run >= 1 ? h : lerp(_walkHip(u0), h, run);
  }

  /// A run's: down from the strike to halfway through a stance (the knee
  /// giving), up to the push-off, and on up through the flight, down to
  /// the next strike.
  double _runHip(double u0) {
    for (var s = 0; s < 2; s++) {
      final u = s == 0 ? u0 : _frac(u0 - 0.5);
      if (u < duty) return _runStance(u / duty, s == 0 ? -1.0 : 1.0, roll(u0));
    }
    final start = u0 < 0.5 ? duty : 0.5 + duty, end = u0 < 0.5 ? 0.5 : 1.0, off = u0 < 0.5 ? -1.0 : 1.0;
    final f = c01((u0 - start) / math.max(end - start, 1e-6));
    final from = _runStance(1, off, roll(start)), to = _runStance(0, -off, roll(_frac(end)));
    return lerp(from, to, smooth(0, 1, f)) + 0.03 * math.pow(math.sin(math.pi * f), 2);
  }

  double _runStance(double s, double side, double r) {
    final strike = _hipFor(0, 0.25, side, r), mid = _hipFor(0.5, 0.72, side, r), off = _hipFor(1, 0.3, side, r);
    return s < 0.5 ? lerp(strike, mid, smooth(0, 0.5, s)) : lerp(mid, off, smooth(0.5, 1, s));
  }

  double _walkHip(double u0) {
    final r = roll(u0), u1 = _frac(u0 - 0.5);
    final down0 = u0 < duty, down1 = u1 < duty;
    if (down0 && down1) {
      // (The one that's just landed has them.)
      final lead = u0 < u1 ? 0 : 1, sl = (lead == 0 ? u0 : u1) / duty;
      return _hipFor(sl, knee(sl), lead == 0 ? -1.0 : 1.0, r);
    }
    if (down0 || down1) {
      final s = (down0 ? u0 : u1) / duty, side = down0 ? -1.0 : 1.0;
      final h = _hipFor(s, knee(s), side, r);
      final settle = c01((duty - 0.5) / 0.05);
      if (settle <= 0 || s <= 0.5) return h;
      final next = _hipFor(0, knee(0), -side, roll(down0 ? 0.5 : 0));
      return lerp(h, next, smooth(0.5, 0.5 / duty, s) * settle);
    }
    // In the air: from the push-off to the next strike.
    final start = u0 < 0.5 ? duty : 0.5 + duty, end = u0 < 0.5 ? 0.5 : 1.0;
    final f = c01((u0 - start) / math.max(end - start, 1e-6));
    final from = _walkHip(start - 1e-4), to = _walkHip(_frac(end + 1e-4));
    return lerp(from, to, f) + 0.02 * run * 4 * f * (1 - f);
  }

  /// Leg [side] on the ground at stance [s], the hips at [hip] (rolled
  /// [roll]): the thigh's pitch and the knee's bend that reach its ankle.
  (double, double) reach(double s, double side, double hip, double roll) {
    final (f, y) = ankle(s);
    return reachTo(f, y, side, hip, roll);
  }

  /// The thigh's pitch and the knee's bend that put leg [side]'s ankle [f]
  /// ahead of the hips and [y] above the ground.
  (double, double) reachTo(double f, double y, double side, double hip, double roll) {
    return FigureRig.legTo(f, hip + side * FigureRig.hipX * math.sin(roll) - y);
  }

  static double _frac(double v) => v - v.floorToDouble();
}

/// Standing about (or sitting): never quite still.
abstract final class Idle {
  /// Poses [p] standing at [t] in manner [m] (all of [breathe], [glance],
  /// [shift] and, [fidget] (0..1) of the time, [fiddle]). [size] is the
  /// figure's (1: 1.72 m).
  static void stand(FigurePose p, double t, Manner m, {double size = 1, double look = 1, vm.Vector3? at, double fidget = 0, double shift = 1}) {
    breathe(p, t, m);
    Idle.shift(p, t, m, size: size, amount: shift);
    glance(p, t, m, size: size, look: look, at: at);
    if (fidget > 0) fiddle(p, t, m, fidget);
  }

  /// Breathing.
  static void breathe(FigurePose p, double t, Manner m) {
    p.breath = 0.5 + 0.5 * math.sin(2 * math.pi * t / m.breath + m.seed);
    // The hands hang easy, swaying a little with the breath and the body.
    for (var s = 0; s < 2; s++) {
      p.armPitch[s] += 0.015 * math.sin(t * 0.9 + m.seed + s * 1.3);
    }
  }

  /// The weight on one foot for a while (the hips out over it, the other
  /// knee easy), then the other, now and then on both, shifted across in a
  /// second or so; and the small sway of anyone standing.
  static void shift(FigurePose p, double t, Manner m, {double size = 1, double amount = 1}) {
    final seed = m.seed;
    final tw = t / m.settle + seed * 0.37, k = tw.floor();
    double weight(int i) {
      final r = rnd(seed, i, 7);
      return r < 0.42 ? -1.0 : (r < 0.84 ? 1.0 : 0.0);
    }

    final w = lerp(weight(k - 1), weight(k), smooth(0, 1.1 / m.settle, tw - k)) * amount;
    final drift = 0.006 * math.sin(t * 0.61 + seed) + 0.004 * math.sin(t * 1.43 + seed * 2);
    p
      ..sway += (0.032 * w + drift) * size
      ..hipRoll += 0.05 * w
      ..lean += m.posture + 0.007 * math.sin(t * 0.71 + seed) + 0.004 * math.sin(t * 1.37 + seed * 2)
      ..twist += 0.025 * math.sin(t * 0.43 + seed);
    // The other leg easy: its hip dropped, the knee bent, the heel up a
    // touch, the foot where it was.
    final a = w.abs();
    if (a > 0.01) {
      final free = w > 0 ? 0 : 1, load = 1 - free;
      double kneeOf(int s) => p.knee[s].isNaN ? 0.07 : p.knee[s];
      final carry = FigureRig.extent(p.legPitch[load], kneeOf(load), p.foot[load].isNaN ? 0 : p.foot[load]);
      final th0 = p.legPitch[free], k0 = kneeOf(free), foot = -0.06 * a;
      final (up, ahead) = FigureRig.ankleOver(foot);
      final f = FigureRig.thigh * math.sin(th0) + FigureRig.shin * math.sin(th0 - k0) + ahead;
      final (th, knee) = FigureRig.legTo(f, carry - 2 * FigureRig.hipX * math.sin(p.hipRoll).abs() - up);
      p
        ..legPitch[free] = th
        ..foot[free] = foot
        ..knee[free] = knee
        ..eased[free] = th;
    }
  }

  /// Looking round: a quick turn of the head to something, a look at it,
  /// then something else (or ahead again); [look] 0 keeps looking ahead.
  /// Watching [at] (world): mostly at it, now and then a look away. A big
  /// look turns the shoulders too.
  static void glance(FigurePose p, double t, Manner m, {double size = 1, double look = 1, vm.Vector3? at}) {
    final seed = m.seed;
    final tg = t / m.glance + seed * 0.53, g = tg.floor();
    double gYaw(int i) => rnd(seed, i, 3) < 0.35 ? 0.0 : (rnd(seed, i, 4) - 0.5) * 1.3;
    double gPitch(int i) => (rnd(seed, i, 5) - 0.55) * 0.25;
    final e = smooth(0, 0.3 / m.glance, tg - g);
    var yaw = lerp(gYaw(g - 1), gYaw(g), e) * look, pitch = lerp(gPitch(g - 1), gPitch(g), e) * look;
    if (at != null) {
      final away = lerp(rnd(seed, g - 1, 6) < 0.25 ? 1.0 : 0.3, rnd(seed, g, 6) < 0.25 ? 1.0 : 0.3, e);
      final (ty, tp) = _towards(p, at, size);
      yaw = ty + yaw * away;
      pitch = tp + pitch * away;
    }
    final turn = yaw.clamp(-1.2, 1.2);
    p
      ..headYaw += turn * 0.75
      ..twist += turn * 0.25
      ..headPitch += pitch;
  }

  /// A facing that changes now and then (a turn to something else), by up
  /// to [by] either way of straight on.
  static double facing(double t, Manner m, [double by = 0.25]) {
    final tf = t / (m.settle * 1.3) + m.seed * 0.71, k = tf.floor();
    double at(int i) => (rnd(m.seed, i, 9) - 0.5) * 2 * by;
    return lerp(at(k - 1), at(k), smooth(0, 0.9 / (m.settle * 1.3), tf - k));
  }

  /// The head's turn and nod (on a body facing [p.yaw]) to look at [at].
  static (double, double) _towards(FigurePose p, vm.Vector3 at, double size) {
    final dx = at.x - p.pos.x, dz = at.z - p.pos.z, dy = at.y - (p.pos.y + 1.6 * size);
    final yaw = math.atan2(-dx, -dz);
    var d = (yaw - p.yaw) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    final pitch = -math.atan2(dy, math.max(0.3, math.sqrt(dx * dx + dz * dz)));
    return (d.clamp(-1.4, 1.4), pitch.clamp(-0.5, 0.6));
  }

  /// Now and then, something to do with the hands (in [m]'s habits): a
  /// hand to the head, a look at the watch, arms folded, hands on the hips
  /// or behind the back, rubbing them, the phone.
  static void fiddle(FigurePose p, double t, Manner m, double amount) {
    final seed = m.seed;
    final span = 11 + 7 * m.restless;
    final tf = t / span + seed * 0.29, i = tf.floor(), u = (tf - i) * span;
    if (rnd(seed, i, 11) > amount * (0.45 + 0.4 * m.restless)) return;
    final kind = (rnd(seed, i, 12) * 7).floor();
    // How long it lasts, and how far into it we are (in and out ~0.5 s).
    final len = const [2.2, 2.4, 5.5, 7.0, 5.0, 1.8, 4.5][kind], start = 0.5 + (span - len - 1) * rnd(seed, i, 13);
    final k = smooth(start, start + 0.5, u) * (1 - smooth(start + len - 0.5, start + len, u));
    if (k <= 0) return;
    void arm(int s, double pitch, double roll) {
      p.armPitch[s] = lerp(p.armPitch[s], pitch, k);
      p.armRoll[s] = lerp(p.armRoll[s], roll, k);
    }

    switch (kind) {
      case 0:
        // A scratch of the head.
        arm(1, 2.75, 0.62);
        p.headPitch += 0.12 * k;
        p.headYaw -= 0.1 * k;
      case 1:
        // The time.
        arm(0, 1.3, -0.5);
        p.headPitch += 0.42 * k;
        p.headYaw += 0.22 * k;
      case 2:
        // Hands on the hips.
        arm(0, -0.3, 0.9);
        arm(1, -0.3, 0.9);
      case 3:
        // Arms folded.
        arm(0, 0.68, -0.55);
        arm(1, 0.68, -0.55);
      case 4:
        // Hands behind the back.
        arm(0, -0.38, -0.22);
        arm(1, -0.38, -0.22);
        p.lean -= 0.03 * k;
      case 5:
        // Rubbing the hands.
        arm(0, 0.72, -0.38);
        arm(1, 0.72 + 0.05 * math.sin(t * 9), -0.38);
      default:
        // The phone.
        arm(1, 1.0, -0.35);
        arm(0, 0.85, -0.42);
        p.headPitch += 0.45 * k;
    }
  }
}
