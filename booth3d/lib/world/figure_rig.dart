import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' as vm;

import 'ease.dart';

// The figures' poses and skeleton, in plain Dart (no Flutter: they're
// tested on their own). figure.dart draws them.

/// One figure's pose: where it stands, which way it faces (yaw 0 = towards
/// −z, the camera side), and its joints.
class FigurePose {
  final pos = vm.Vector3.zero();
  double yaw = 0;

  /// Eased aside from whoever's in the way (metres along x and z, on top of
  /// [pos]): [Figures] works it out from the frame before; kept from frame
  /// to frame ([rest] leaves it).
  double nudgeX = 0, nudgeZ = 0;

  /// Whether it steers round others ([nudgeX]): false for a crowd with its
  /// own steering (they're still walked round).
  bool steer = true;

  /// Torso pitch forward (radians) and a vertical bob.
  double lean = 0, bob = 0;

  /// Per side (0 = −x, 1 = +x): arm pitch (0 down, π/2 forward, π up) and
  /// roll (outwards), leg pitch (forward swing).
  final armPitch = [0.0, 0.0], armRoll = [0.0, 0.0], legPitch = [0.0, 0.0];
  bool visible = true;
  bool clipboard = false;

  /// The hard hat tossed in the air: how high above the head, and its spin.
  double hatUp = 0, hatSpin = 0;

  /// Optional joints, NaN to have them follow from the rest of the pose
  /// (see [FigureRig]): per side, the elbow's and the knee's bend (0
  /// straight; [Crew3D.aim] sets the elbow so the hand reaches), and the
  /// foot's pitch (toe up +; a walk rolls it).
  final elbow = [double.nan, double.nan], knee = [double.nan, double.nan], foot = [double.nan, double.nan];

  /// Per side, the thigh's pitch a stand set along with the knee and the
  /// foot (the leg easy, see [Idle.shift]; NaN: none): if the pose then
  /// moves the leg on, its knee and foot are the rig's own again.
  final eased = [double.nan, double.nan];

  /// Per side, standing: the foot moved from where it would be (metres:
  /// forward, out from the middle line) and lifted off the ground (a step
  /// to the side, say). The other foot stays put.
  final footAhead = [0.0, 0.0], footOut = [0.0, 0.0], footLift = [0.0, 0.0];

  /// Per side, while [reaching]: where the hand is to be (world), and the
  /// arm's pitch and roll [Crew3D.aim] worked out for it. The hand gets
  /// there even while the rest of the figure is still turning or settling
  /// (see [FigureMotion]); unless the pose then moves the arm on (a pat, a
  /// blend), when it goes as posed.
  final reach = [vm.Vector3.zero(), vm.Vector3.zero()];
  final reaching = [false, false];
  final reachPitch = [0.0, 0.0], reachRoll = [0.0, 0.0];

  /// Marks arm [s] as aimed at [target] (world), as it's now posed.
  void aimed(int s, vm.Vector3 target) {
    reaching[s] = true;
    reach[s].setFrom(target);
    reachPitch[s] = armPitch[s];
    reachRoll[s] = armRoll[s];
  }

  /// Whether arm [s] is still where it was aimed.
  bool reachingWith(int s) => reaching[s] && armPitch[s] == reachPitch[s] && armRoll[s] == reachRoll[s];

  /// Puts hand [s] at (x, y, z) in the chest's frame (size 1, metres: x to
  /// the figure's right, y up from the hips, z back; the shoulders are at
  /// ±0.185, 0.5, 0) by setting the arm's pitch, roll and elbow, [k] (0..1)
  /// of the way from how it was. (Where the chest is doesn't matter: for
  /// hands that go with it, clapping, holding a phone up, explaining.)
  void handTo(int s, double x, double y, double z, [double k = 1]) {
    if (k <= 0) return;
    final side = s == 0 ? -1.0 : 1.0;
    final dx = x - side * FigureRig.shoulderX, dy = y - FigureRig.shoulderY, dz = z;
    final r = math.max(1e-6, math.sqrt(dx * dx + dy * dy + dz * dz));
    final pitch = math.asin((-dz / r).clamp(-1.0, 1.0)), roll = side * math.atan2(dx / r, -dy / r);
    final bend = FigureRig.bendFor(r.clamp(FigureRig.minReach, FigureRig.maxReach));
    final was = elbow[s].isNaN ? 0.58 : elbow[s];
    armPitch[s] = armPitch[s] + (pitch - armPitch[s]) * k;
    armRoll[s] = armRoll[s] + (roll - armRoll[s]) * k;
    elbow[s] = was + (bend - was) * k;
  }

  /// The head turned (to the left +) and nodded (down +), and the shoulders
  /// turned against the hips.
  double headYaw = 0, headPitch = 0, twist = 0;

  /// More weight on one foot than the other: the hips moved over it
  /// (metres, towards +x) and rolled (the +x hip up). The feet stay where
  /// they are, the shoulders tilt back against the hips, [tilt] more (the
  /// +x shoulder up).
  double sway = 0, hipRoll = 0, tilt = 0;

  /// Leaning into a turn (towards +x), and the breath (0 out … 1 in).
  double bank = 0, breath = 0;

  /// While walking, the stride's phase (radians, π a step; leg 0 is
  /// forward at π/2): the knees, the feet and the hips follow it. NaN
  /// standing.
  double stride = double.nan;

  /// How much lower the hips go to reach something low (metres: a crouch,
  /// and a bend forward with it); [Crew3D.aim] sets it.
  double stoop = 0;

  /// What last drew this pose (see [FigureMotion]), if anything: where a
  /// hand is ([FigureRig.solve] with it) is where it's drawn.
  FigureMotion? motion;

  void rest() {
    hatUp = 0;
    hatSpin = 0;
    for (var s = 0; s < 2; s++) {
      elbow[s] = knee[s] = foot[s] = eased[s] = double.nan;
      footAhead[s] = footOut[s] = footLift[s] = 0;
      reaching[s] = false;
      armPitch[s] = 0.08;
      armRoll[s] = 0.12;
      legPitch[s] = 0;
    }
    headYaw = headPitch = twist = stoop = 0;
    sway = hipRoll = tilt = bank = breath = 0;
    stride = double.nan;
    lean = 0;
    bob = 0;
    clipboard = false;
    visible = true;
    steer = true;
  }

  /// [q]'s pose, joint by joint.
  void copyFrom(FigurePose q) => blendTo(q, 1);

  /// [k] (0..1) of the way from this pose to [q], joint by joint (the
  /// optional joints, the walk and the hands' targets: the nearer pose's).
  void blendTo(FigurePose q, double k) {
    double mix(double a, double b) => k >= 1 ? b : a + (b - a) * k;
    pos.setValues(mix(pos.x, q.pos.x), mix(pos.y, q.pos.y), mix(pos.z, q.pos.z));
    var dy = (q.yaw - yaw) % (2 * math.pi);
    if (dy > math.pi) dy -= 2 * math.pi;
    yaw = k >= 1 ? q.yaw : yaw + dy * k;
    lean = mix(lean, q.lean);
    bob = mix(bob, q.bob);
    hatUp = mix(hatUp, q.hatUp);
    hatSpin = mix(hatSpin, q.hatSpin);
    headYaw = mix(headYaw, q.headYaw);
    headPitch = mix(headPitch, q.headPitch);
    twist = mix(twist, q.twist);
    stoop = mix(stoop, q.stoop);
    sway = mix(sway, q.sway);
    hipRoll = mix(hipRoll, q.hipRoll);
    tilt = mix(tilt, q.tilt);
    bank = mix(bank, q.bank);
    breath = mix(breath, q.breath);
    final near = k >= 0.5;
    for (var s = 0; s < 2; s++) {
      armPitch[s] = mix(armPitch[s], q.armPitch[s]);
      armRoll[s] = mix(armRoll[s], q.armRoll[s]);
      legPitch[s] = mix(legPitch[s], q.legPitch[s]);
      footAhead[s] = mix(footAhead[s], q.footAhead[s]);
      footOut[s] = mix(footOut[s], q.footOut[s]);
      footLift[s] = mix(footLift[s], q.footLift[s]);
      if (near) {
        elbow[s] = q.elbow[s];
        knee[s] = q.knee[s];
        foot[s] = q.foot[s];
        reaching[s] = q.reaching[s];
        reach[s].setFrom(q.reach[s]);
        reachPitch[s] = q.reachPitch[s];
        reachRoll[s] = q.reachRoll[s];
        eased[s] = q.eased[s];
      }
    }
    if (near) {
      stride = q.stride;
      clipboard = q.clipboard;
      steer = q.steer;
    }
  }
}

// ── The skeleton ────────────────────────────────────────────────────────────

/// A figure's skeleton in one pose: the world transform of each part,
/// worked out from a [FigurePose] (the poses were written for a toy with a
/// big head and short arms; this reads them for a grown-up).
///
/// What the pose leaves unset follows from what it does set:
/// - Arms: pitch and roll point from the shoulder to the hand. How far the
///   hand is (the elbow's bend) follows from where it points: near straight
///   hanging or raised, bent to hold something out, folded to bring a can
///   to the mouth or a hand to the hat; arms rolled back and out are hands
///   on hips, rolled in at chest height are folded arms. [FigurePose.elbow]
///   sets the bend instead ([Crew3D.aim] does, so the hand gets to the
///   target). The elbow points out and back, or down for a hand at the
///   face.
/// - Legs: the feet stay on the ground, hip-width apart (walking, nearer a
///   line), the toes turned out a little: moving or rolling the hips over
///   them splays the legs instead of dragging the feet. A walk
///   ([FigurePose.stride]) sets the hips' height from the leg that's
///   longest down (the one bearing the weight). Standing, each foot is on
///   the ground where the leg's pitch would put it (or moved, or lifted:
///   [FigurePose.footAhead] and the like), the hips as high as both feet
///   down allow (back over the heels, bending forward), the legs reaching
///   the feet; a negative bob is a crouch (the knees bend), a positive one
///   a jump (they tuck); both thighs raised forward is sitting, the hips
///   where the toy's were (on the seat), the shins hanging.
/// - The head leans back a little to look ahead from a deep bend, keeps
///   looking forward as the shoulders swing, and stays level as they tilt.
///
/// The pose is first worked out as numbers ([joints]: angles, heights, the
/// hands' places), which a [FigureMotion] may smooth, then the parts are
/// placed from them.
class FigureRig {
  /// Measurements (metres) of a figure of size 1, 1.72 m tall: the ankle
  /// above the sole, the shin and the thigh; the hip joints' spread.
  static const ankle = 0.08, shin = 0.41, thigh = 0.42, hipX = 0.09;

  /// The hip joints' height standing (the spine's pivot), 0.91 m.
  static const hip = ankle + shin + thigh;

  /// The shoulder joints (out from the middle, above the hips) and the neck.
  static const shoulderX = 0.185, shoulderY = 0.5, neckY = 0.555;

  /// The arm: shoulder to elbow, elbow to wrist, wrist to the palm's middle.
  static const upperArm = 0.29, forearm = 0.25, palm = 0.07;
  static const lowerArm = forearm + palm;

  /// The mouth (in the head's frame, from the neck).
  static const mouthY = 0.066, mouthZ = -0.098;

  /// Where the toy's hips were: seated poses put them there (on the seat).
  static const _toyHip = 0.36;

  /// Each foot's middle out from the body's middle line standing, and
  /// walking (size 1); how far the toes turn out.
  static const stance = 0.105, track = 0.055, toeOut = 0.1;

  /// The root (feet, facing), the pelvis (the legs hang from it), the
  /// chest (the torso, the arms hang from it) and the head.
  final root = vm.Matrix4.identity(), pelvis = vm.Matrix4.identity(), chest = vm.Matrix4.identity(), head = vm.Matrix4.identity();

  /// Per side (0 = −x, 1 = +x): the upper arm (from the shoulder), the
  /// forearm (from the elbow) and the hand (from the wrist), each along its
  /// −y; the thigh, the shin (along −y) and the foot (from the ankle).
  final upper = [vm.Matrix4.identity(), vm.Matrix4.identity()], lower = [vm.Matrix4.identity(), vm.Matrix4.identity()];
  final hand = [vm.Matrix4.identity(), vm.Matrix4.identity()];
  final thighs = [vm.Matrix4.identity(), vm.Matrix4.identity()], shins = [vm.Matrix4.identity(), vm.Matrix4.identity()];
  final feet = [vm.Matrix4.identity(), vm.Matrix4.identity()];

  /// Each palm's middle (world).
  final palms = [vm.Vector3.zero(), vm.Vector3.zero()];

  // ── The joints as numbers ───────────────────────────────────────────────

  /// Facing (yaw), the hips' height (metres), the pelvis's and the chest's
  /// turn, the lean, the head's nod and turn (on the chest), the hips moved
  /// sideways (metres) and rolled, the chest's tilt, the lean into a turn,
  /// the breath, the hips moved back (metres).
  static const jYaw = 0,
      jHipY = 1,
      jPelvisYaw = 2,
      jChestYaw = 3,
      jLean = 4,
      jNod = 5,
      jHeadYaw = 6,
      jSway = 7,
      jHipRoll = 8,
      jChestTilt = 9,
      jBank = 10,
      jBreath = 11,
      jHipZ = 12;

  /// Per leg, from [jLeg] + 4 × side: the thigh's pitch, the knee's bend,
  /// the foot's pitch, the leg's splay (out from the vertical, towards +x).
  static const jLeg = 13;

  /// Per arm, from [jArm] + 6 × side: the palm's middle, then where the
  /// elbow points (the chest's frame, size 1).
  static const jArm = 21;
  static const channels = 33;

  /// The last pose, as numbers.
  final joints = Float64List(channels);

  // Scratch.
  final _l = vm.Matrix4.identity();
  final _knee = [0.0, 0.0], _thigh = [0.0, 0.0], _foot = [0.0, 0.0], _ext = [0.0, 0.0], _splay = [0.0, 0.0];
  final _ahead = [0.0, 0.0], _out = [0.0, 0.0], _ankleY = [0.0, 0.0];

  /// The lowest the hips go in a crouch (size 1).
  static const _squat = 0.46;

  /// A leg's length (hip joint to ankle, size 1) standing: the knee just
  /// short of straight.
  static final _straight = math.sqrt(thigh * thigh + shin * shin + 2 * thigh * shin * math.cos(0.07));

  /// Poses the skeleton for [p]. [size] scales it (1: 1.72 m); [width] the
  /// shoulders. Without [arms], only the trunk, the head and the legs.
  /// With [motion], what it shows (smoothed; [commit] false just looks,
  /// leaving it as it was).
  void solve(FigurePose p, {double size = 1, double width = 1, bool arms = true, FigureMotion? motion, bool commit = true}) {
    _measure(p, size, width, arms);
    motion?.filter(this, p, arms: arms, commit: commit);
    _place(p, size, width, arms, motion);
    // The lower foot on the ground: the smoothing blends the hips and the
    // legs each on their own (out of a crouch, setting off), and they
    // needn't meet the ground between; the hips go up or down the
    // difference. (In a run's flight, or a jump, only ever up: never
    // through the ground.)
    if (motion != null && math.min(p.legPitch[0], p.legPitch[1]) < 0.95) {
      final walking = p.stride.isFinite, flight = p.bob > 0.02;
      var err = double.infinity;
      for (var s = 0; s < 2; s++) {
        final want = p.pos.y + (_ankleY[s] + (walking ? 0 : p.footLift[s] / size)) * size;
        err = math.min(err, feet[s].storage[13] - want);
      }
      if (err < -0.004 || (!flight && err > 0.004)) {
        joints[jHipY] -= err;
        _place(p, size, width, arms, motion);
      }
    }
  }

  void _measure(FigurePose p, double size, double width, bool arms) {
    final j = joints;
    // Reaching down bends the back as well as the knees.
    final walking = p.stride.isFinite;
    final lean = walking ? p.lean : math.min(1.1, p.lean + 1.2 * p.stoop);
    final roll = p.hipRoll, sr = math.sin(roll), cr = math.cos(roll), sway = p.sway / size;
    var pelvisYaw = 0.0, chestYaw = p.twist, look = 0.0, hipZ = 0.0;
    double hipY;
    if (walking) {
      // The hips turn with the leg going forward, the shoulders against
      // them (and the head against the shoulders).
      final swing = (p.legPitch[0] - p.legPitch[1]) / 2;
      pelvisYaw = -0.15 * swing;
      chestYaw += 0.2 * swing;
      look = -0.85 * 0.2 * swing;
      hipY = 0;
      for (var s = 0; s < 2; s++) {
        final side = s == 0 ? -1.0 : 1.0;
        final psi = p.stride + s * math.pi;
        _thigh[s] = p.legPitch[s];
        _knee[s] = p.knee[s].isNaN ? _gaitKnee(psi) : p.knee[s];
        _foot[s] = p.foot[s].isNaN ? _gaitFoot(psi) : p.foot[s];
        _ankleY[s] = ankleOver(_foot[s]).$1;
        _splay[s] = _splayFor(side, sway, sr, cr, track, _thigh[s], _knee[s]);
        _ext[s] = extent(_thigh[s], _knee[s], _foot[s], _splay[s]);
        // The longest leg down carries the hips.
        hipY = math.max(hipY, (_ext[s] - side * hipX * sr) * size);
      }
      hipY += math.max(0.0, p.bob);
    } else {
      // Standing: each foot on the ground where the pose puts it, the hips
      // as high as both feet down allow (lower for a crouch, up for a jump:
      // the feet tucked under), the legs reaching the feet. Bending over,
      // the hips go back over the heels. Both thighs raised forward is
      // sitting: the hips where the toy's were (on the seat), the legs as
      // posed, the shins hanging.
      final sit = smooth(0.95, 1.35, math.min(p.legPitch[0], p.legPitch[1]));
      final bob = p.bob;
      // (A grown-up bending as low as the toy did squats a little.)
      final squat = 0.3 * smooth(0.45, 0.9, p.lean) * smooth(0.0, -0.04, bob);
      final crouch = (math.max(0.0, -bob) + squat + p.stoop) * (1 - sit) / size;
      final tuck = smooth(0.03, 0.18, bob), up = math.max(0.0, bob) / size;
      hipZ = 0.12 * smooth(0.2, 0.9, lean) * (1 - sit);
      var top = double.infinity;
      for (var s = 0; s < 2; s++) {
        final side = s == 0 ? -1.0 : 1.0;
        final th = p.legPitch[s];
        // (A leg eased by a stand, then posed again: the rig's own knee.)
        final own = p.eased[s].isNaN || p.eased[s] == th;
        final k = own ? p.knee[s] : double.nan;
        _foot[s] = own && !p.foot[s].isNaN ? p.foot[s] : -0.35 * tuck;
        // The ankle: ahead of the hip joint (as far as the leg's swing would
        // have it), out from it.
        final ahead = thigh * math.sin(th) + shin * math.sin(th - (k.isNaN ? 0.07 : k));
        _ahead[s] = (ahead + p.footAhead[s] / size + hipZ).clamp(-0.55, 0.55);
        _out[s] = side * (stance + p.footOut[s] / size) - (sway + side * hipX * cr);
        _ankleY[s] = ankleOver(_foot[s]).$1;
        final reach = _straight * _straight - _out[s] * _out[s] - _ahead[s] * _ahead[s];
        top = math.min(top, _ankleY[s] + math.sqrt(math.max(0.09, reach)) - side * hipX * sr);
      }
      // (No lower than a deep squat.)
      final hy = math.max(top - crouch, _squat) + up;
      for (var s = 0; s < 2; s++) {
        final side = s == 0 ? -1.0 : 1.0;
        final dx = _out[s], dy = hy + side * hipX * sr - (_ankleY[s] + p.footLift[s] / size + up + 0.11 * tuck);
        var (th, knee) = legTo(_ahead[s], math.sqrt(dx * dx + dy * dy));
        var splay = math.atan2(dx, dy).clamp(-0.5, 0.5);
        if (sit > 0) {
          final own = p.eased[s].isNaN || p.eased[s] == p.legPitch[s];
          th = lerp(th, p.legPitch[s], sit);
          knee = lerp(knee, own && !p.knee[s].isNaN ? p.knee[s] : p.legPitch[s], sit);
          splay *= 1 - sit;
        }
        _thigh[s] = th;
        _knee[s] = knee;
        _splay[s] = splay;
      }
      hipY = lerp(hy * size, _toyHip + bob, sit);
    }
    // Looking ahead from a deep bend; a laugh throws the head back.
    final nod = p.headPitch - 0.45 * math.max(0.0, lean - 0.35) + 0.4 * math.min(0.0, lean + 0.05);
    j[jYaw] = p.yaw;
    j[jHipY] = hipY;
    j[jPelvisYaw] = pelvisYaw;
    j[jChestYaw] = chestYaw;
    j[jLean] = lean;
    j[jNod] = nod;
    j[jHeadYaw] = p.headYaw + look;
    j[jSway] = p.sway;
    j[jHipRoll] = roll;
    // The shoulders tilt back against the hips.
    j[jChestTilt] = p.tilt - 0.6 * roll;
    j[jBank] = p.bank;
    j[jBreath] = p.breath;
    j[jHipZ] = hipZ * size;
    for (var s = 0; s < 2; s++) {
      final o = jLeg + 4 * s;
      j[o] = _thigh[s];
      j[o + 1] = _knee[s];
      j[o + 2] = _foot[s];
      j[o + 3] = _splay[s];
      if (arms) _armGoal(p, s, s == 0 ? -1.0 : 1.0, width);
    }
  }

  /// The splay (radians, towards +x) that puts leg [side]'s foot [out] from
  /// the middle line, the hips moved [sway] (size 1) and rolled (sine
  /// [sr], cosine [cr]).
  static double _splayFor(double side, double sway, double sr, double cr, double out, double th, double knee) {
    final hx = sway + side * hipX * cr;
    final reach = math.max(0.3, thigh * math.cos(th) + shin * math.cos(th - knee));
    return math.asin(((side * out - hx) / reach).clamp(-0.45, 0.45));
  }

  /// How far below the hip joint the sole's lowest point is (size 1).
  static double extent(double th, double knee, double foot, [double splay = 0]) {
    final c = math.cos(foot), n = math.sin(foot);
    return (thigh * math.cos(th) + shin * math.cos(th - knee)) * math.cos(splay) + math.max(ankle * c + 0.055 * n, ankle * c - 0.185 * n);
  }

  /// The thigh's pitch and the knee's bend that put a leg's ankle [ahead]
  /// of its hip joint and [down] below it (size 1; as near as it reaches).
  static (double, double) legTo(double ahead, double down) {
    const a = thigh, b = shin;
    final d = math.sqrt(ahead * ahead + down * down).clamp(0.3, a + b - 1e-4);
    final knee = math.pi - math.acos(((a * a + b * b - d * d) / (2 * a * b)).clamp(-1.0, 1.0));
    final at = math.atan2(ahead, down), bend = math.acos(((a * a + d * d - b * b) / (2 * a * d)).clamp(-1.0, 1.0));
    return (at + bend, knee);
  }

  /// How high the ankle is above the sole's lowest point with the foot
  /// pitched [foot] (toe up +), and how far ahead of where it is with the
  /// foot flat when the foot pivots on its heel (toe up) or its toe.
  static (double, double) ankleOver(double foot) {
    final c = math.cos(foot), n = math.sin(foot);
    if (n >= 0) return (ankle * c + 0.055 * n, 0.055 * c - ankle * n - 0.055);
    return (ankle * c - 0.185 * n, 0.185 - 0.185 * c - ankle * n);
  }

  /// The knee's bend that makes a leg (thigh at [th], foot at [foot])
  /// reach [extent] below its hip joint (size 1), as near straight as can
  /// be: for a leg that takes no weight, its hip dropped.
  static double kneeFor(double th, double foot, double extent) {
    final c = math.cos(foot), n = math.sin(foot);
    final leg = extent - math.max(ankle * c + 0.055 * n, ankle * c - 0.185 * n) - thigh * math.cos(th);
    final shinCos = (leg / shin).clamp(-1.0, 1.0);
    return math.max(0.0, th + math.acos(shinCos));
  }

  /// The knee's bend at a leg's walk phase [psi] (its thigh swings as
  /// sin ψ: forward while cos ψ > 0): most early in the swing, straight for
  /// the heel strike, a give as the weight comes on. (For walks that don't
  /// set the knees.)
  static double _gaitKnee(double psi) {
    final swing = math.max(0.0, math.cos(psi + 0.42));
    var k = 0.06 + swing * math.sqrt(swing);
    final w = psi % (2 * math.pi) - math.pi / 2; // since the heel strike
    if (w > 0 && w < math.pi / 2) k += 0.18 * math.sin(2 * w);
    return k;
  }

  /// The foot's pitch (toe up) through the walk: the heel strikes, the foot
  /// goes flat, the heel lifts, it pushes off the toe, swings through.
  static const _footKeys = [0.0, -0.25, 1.2, 0.15, 1.571, 0.22, 2.1, 0.0, 3.8, 0.0, 4.712, -0.68, 5.35, -0.45, 2 * math.pi, -0.25];

  static double _gaitFoot(double psi) {
    final u = psi % (2 * math.pi);
    for (var i = 0; i + 3 < _footKeys.length; i += 2) {
      if (u <= _footKeys[i + 2]) return lerp(_footKeys[i + 1], _footKeys[i + 3], smooth(_footKeys[i], _footKeys[i + 2], u));
    }
    return _footKeys[1];
  }

  // ── Placing the parts ───────────────────────────────────────────────────

  final _inv = vm.Vector3.zero();

  void _place(FigurePose p, double size, double width, bool arms, FigureMotion? motion) {
    final j = joints;
    // The root: the feet, the facing, the lean into a turn.
    _setYawRollPitch(root, p.pos.x + p.nudgeX, p.pos.y, p.pos.z + p.nudgeZ, j[jYaw], -j[jBank], 0);
    final hipY = j[jHipY], hipZ = j[jHipZ], sway = j[jSway], roll = j[jHipRoll], breath = j[jBreath];
    _setYawRollPitch(_l, sway, hipY, hipZ, j[jPelvisYaw], roll, 0);
    pelvis
      ..setFrom(root)
      ..multiply(_l);
    // The chest: turned, tilted, leant; a breath lifts and opens it.
    _setYawRollPitch(_l, sway, hipY + 0.004 * breath * size, hipZ, j[jChestYaw], j[jChestTilt], -j[jLean] + 0.018 * breath);
    chest
      ..setFrom(root)
      ..multiply(_l);
    // The head stays level, and still through the breath.
    _setYawRollPitch(_l, 0, neckY * size, 0, j[jHeadYaw], -0.75 * j[jChestTilt], -j[jNod] - 0.018 * breath);
    head
      ..setFrom(chest)
      ..multiply(_l);
    for (var s = 0; s < 2; s++) {
      final side = s == 0 ? -1.0 : 1.0;
      final o = jLeg + 4 * s;
      // The thigh from the hip joint, the shin from the knee, splayed out
      // (less the hips' roll: the leg's own frame); the foot level and
      // facing the way the figure does (toes out), as the walk rolls it.
      final th = j[o], sh = th - j[o + 1], foot = j[o + 2], splay = j[o + 3];
      final hx = side * hipX * size, r = splay - roll, cr = math.cos(r), sr = math.sin(r);
      _setYawRollPitch(_l, hx, 0, 0, 0, r, th);
      thighs[s]
        ..setFrom(pelvis)
        ..multiply(_l);
      final ky = -thigh * size * math.cos(th), kz = -thigh * size * math.sin(th);
      _setYawRollPitch(_l, hx - sr * ky, cr * ky, kz, 0, r, sh);
      shins[s]
        ..setFrom(pelvis)
        ..multiply(_l);
      final ay = ky - shin * size * math.cos(sh), az = kz - shin * size * math.sin(sh);
      _setYawRollPitch(_l, hx - sr * ay, cr * ay, az, -side * toeOut - j[jPelvisYaw], -roll, foot);
      feet[s]
        ..setFrom(pelvis)
        ..multiply(_l);
    }
    if (!arms) return;
    for (var s = 0; s < 2; s++) {
      final o = jArm + 6 * s;
      if (p.reachingWith(s)) {
        // The hand where it's to be, wherever the chest has got to (and
        // whatever's left of a jump to a new target).
        _toChest(p.reach[s], size, _inv);
        j[o] = _inv.x + (motion?.now[o] ?? 0);
        j[o + 1] = _inv.y + (motion?.now[o + 1] ?? 0);
        j[o + 2] = _inv.z + (motion?.now[o + 2] ?? 0);
      }
      _armPlace(s, s == 0 ? -1.0 : 1.0, size, width, breath);
    }
  }

  /// World point [w] in the chest's frame, size 1.
  void _toChest(vm.Vector3 w, double size, vm.Vector3 out) {
    final c = chest.storage;
    final dx = w.x - c[12], dy = w.y - c[13], dz = w.z - c[14];
    out.setValues((c[0] * dx + c[1] * dy + c[2] * dz) / size, (c[4] * dx + c[5] * dy + c[6] * dz) / size, (c[8] * dx + c[9] * dy + c[10] * dz) / size);
  }

  // ── Arms ────────────────────────────────────────────────────────────────

  /// Arm [s]: where its hand goes and where its elbow points (into
  /// [joints]).
  void _armGoal(FigurePose p, int s, double side, double width) {
    final pitch = p.armPitch[s], roll = p.armRoll[s];
    final cp = math.cos(pitch), sp = math.sin(pitch), cr = math.cos(roll), sr = math.sin(roll);
    // Shoulder to hand (chest frame: x out to the right, y up, z back).
    final dx = side * cp * sr, dy = -cp * cr, dz = -sp;
    final sx = side * shoulderX * width, sy = shoulderY + 0.006 * p.breath;
    double tx, ty, tz, px, py, pz;
    final bend = p.elbow[s];
    if (!bend.isNaN) {
      final r = reachOf(bend);
      tx = sx + dx * r;
      ty = sy + dy * r;
      tz = dz * r;
      px = side * 0.4;
      py = -0.45;
      pz = 0.8;
    } else {
      // Out at a natural reach, bent a little more held out in front.
      final rb = 0.585 - 0.09 * smooth(0.2, 0.9, pitch) * (1 - smooth(2.2, 2.8, pitch));
      tx = sx + dx * rb;
      ty = sy + dy * rb;
      tz = dz * rb;
      px = side * 0.4;
      py = -0.45;
      pz = 0.8;
      // Close to the body, the hand goes where the toy's did (the two
      // torsos are much the same): at the face (a can, a cigarette, the
      // hat), or on the chest or belly.
      final ox = side * 0.205 + 0.36 * dx, oy = 0.5 + 0.36 * dy, oz = 0.36 * dz;
      final hy = oy - 0.72, toFace = math.sqrt(ox * ox + hy * hy + oz * oz);
      final wh = smooth(0.3, 0.16, toFace) * smooth(0.45, 0.8, roll);
      final ay = oy.clamp(0.155, 0.425);
      final toBody = math.sqrt(ox * ox + (oy - ay) * (oy - ay) + oz * oz) - 0.155;
      // (In front of it: hanging at the side, the toy's short arm was
      // close to its hips too.)
      final wt = smooth(0.22, 0.08, toBody) * smooth(-0.06, -0.15, oz);
      final w = math.max(wh, wt);
      if (w > 0) {
        final fx = ox * 0.86, fy = 0.685 + hy * 0.86, fz = -0.01 + oz * 0.86;
        final k = 1 / (wh + wt);
        tx = lerp(tx, (wh * fx + wt * ox) * k, w);
        ty = lerp(ty, (wh * fy + wt * oy) * k, w);
        tz = lerp(tz, (wh * fz + wt * oz) * k, w);
        px = lerp(px, side * 0.55, wh);
        py = lerp(py, -0.8, wh);
        pz = lerp(pz, -0.25, wh);
      }
      // Rolled back and out: hands on the hips, elbows out.
      final wa = smooth(0.45, 0.8, roll) * smooth(0.25, -0.15, pitch);
      if (wa > 0) {
        tx = lerp(tx, side * 0.165, wa);
        ty = lerp(ty, 0.12, wa);
        tz = lerp(tz, 0.03, wa);
        px = lerp(px, side, wa);
        py = lerp(py, -0.05, wa);
        pz = lerp(pz, 0.35, wa);
      }
      // Rolled in at chest height: arms folded.
      final wf = smooth(-0.4, -0.65, roll) * smooth(0.5, 0.8, pitch) * smooth(1.55, 1.25, pitch);
      if (wf > 0) {
        tx = lerp(tx, -side * 0.085, wf);
        ty = lerp(ty, 0.33, wf);
        tz = lerp(tz, -0.19, wf);
        px = lerp(px, side * 0.7, wf);
        py = lerp(py, -0.7, wf);
        pz = lerp(pz, 0.1, wf);
      }
    }
    final o = jArm + 6 * s, j = joints;
    j[o] = tx;
    j[o + 1] = ty;
    j[o + 2] = tz;
    j[o + 3] = px;
    j[o + 4] = py;
    j[o + 5] = pz;
  }

  /// Arm [s] from [joints]: the hand where it goes, the elbow between (two
  /// bones, the elbow towards the pole).
  void _armPlace(int s, double side, double size, double width, double breath) {
    final o = jArm + 6 * s, j = joints;
    final tx = j[o], ty = j[o + 1], tz = j[o + 2], px = j[o + 3], py = j[o + 4], pz = j[o + 5];
    final sx = side * shoulderX * width, sy = shoulderY + 0.006 * breath;
    var ex = tx - sx, ey = ty - sy, ez = tz;
    var r = math.sqrt(ex * ex + ey * ey + ez * ez);
    if (r < 1e-5) {
      ex = 0;
      ey = -1;
      ez = 0;
      r = 0.3;
    } else {
      ex /= r;
      ey /= r;
      ez /= r;
    }
    r = r.clamp(0.12, upperArm + lowerArm - 0.002);
    const a = upperArm, b = lowerArm;
    final along = (a * a - b * b + r * r) / (2 * r), off = math.sqrt(math.max(0.0, a * a - along * along));
    // The pole, square to the arm.
    final pd = px * ex + py * ey + pz * ez;
    var nx = px - pd * ex, ny = py - pd * ey, nz = pz - pd * ez;
    var nl = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (nl < 1e-4) {
      // Pointing along the pole: the elbow out to the side instead.
      final qd = side * ex;
      nx = side - qd * ex;
      ny = -qd * ey;
      nz = -qd * ez;
      nl = math.max(1e-4, math.sqrt(nx * nx + ny * ny + nz * nz));
    }
    nx /= nl;
    ny /= nl;
    nz /= nl;
    // Shoulder S, elbow E, palm P (size 1, chest frame).
    final elx = sx + ex * along + nx * off, ely = sy + ey * along + ny * off, elz = ez * along + nz * off;
    final pax = sx + ex * r, pay = sy + ey * r, paz = ez * r;
    // Upper arm: y from the elbow up to the shoulder, z towards the pole
    // (the back of the elbow), x the hinge.
    final uyx = (sx - elx) / a, uyy = (sy - ely) / a, uyz = -elz / a;
    final nd = nx * uyx + ny * uyy + nz * uyz;
    var uzx = nx - nd * uyx, uzy = ny - nd * uyy, uzz = nz - nd * uyz;
    final ul = math.sqrt(uzx * uzx + uzy * uzy + uzz * uzz);
    if (ul > 1e-6) {
      uzx /= ul;
      uzy /= ul;
      uzz /= ul;
    } else {
      uzx = 0;
      uzy = 0;
      uzz = 1;
    }
    final hxx = uyy * uzz - uyz * uzy, hxy = uyz * uzx - uyx * uzz, hxz = uyx * uzy - uyy * uzx;
    _setBasis(_l, hxx, hxy, hxz, uyx, uyy, uyz, uzx, uzy, uzz, sx * size, sy * size, 0);
    upper[s]
      ..setFrom(chest)
      ..multiply(_l);
    // Forearm: y from the palm up to the elbow, the same hinge.
    var lyx = elx - pax, lyy = ely - pay, lyz = elz - paz;
    final ll = math.max(1e-6, math.sqrt(lyx * lyx + lyy * lyy + lyz * lyz));
    lyx /= ll;
    lyy /= ll;
    lyz /= ll;
    final lzx = hxy * lyz - hxz * lyy, lzy = hxz * lyx - hxx * lyz, lzz = hxx * lyy - hxy * lyx;
    _setBasis(_l, hxx, hxy, hxz, lyx, lyy, lyz, lzx, lzy, lzz, elx * size, ely * size, elz * size);
    lower[s]
      ..setFrom(chest)
      ..multiply(_l);
    final wx = elx - lyx * forearm, wy = ely - lyy * forearm, wz = elz - lyz * forearm;
    _setBasis(_l, hxx, hxy, hxz, lyx, lyy, lyz, lzx, lzy, lzz, wx * size, wy * size, wz * size);
    hand[s]
      ..setFrom(chest)
      ..multiply(_l);
    palms[s].setValues(pax * size, pay * size, paz * size);
    chest.transform3(palms[s]);
  }

  /// The hand's distance from the shoulder with the elbow bent by [bend].
  static double reachOf(double bend) => math.sqrt(upperArm * upperArm + lowerArm * lowerArm + 2 * upperArm * lowerArm * math.cos(bend));

  /// The elbow's bend that puts the hand [r] from the shoulder.
  static double bendFor(double r) {
    const a = upperArm, b = lowerArm;
    final c = ((a * a + b * b - r * r) / (2 * a * b)).clamp(-1.0, 1.0);
    return math.pi - math.acos(c);
  }

  /// The longest reach, and the shortest.
  static const maxReach = upperArm + lowerArm - 0.002, minReach = 0.12;

  /// Shoulder [s] (world), as posed by the last [solve].
  vm.Vector3 shoulder(int s, double size, vm.Vector3 out) => chest.transform3(out..setValues((s == 0 ? -1 : 1) * shoulderX * size, shoulderY * size, 0));

  /// The mouth (world), as posed by the last [solve].
  vm.Vector3 mouth(double size, vm.Vector3 out) => head.transform3(out..setValues(0, mouthY * size, mouthZ * size));

  // ── Matrices written in place ───────────────────────────────────────────

  static void _setBasis(
    vm.Matrix4 m,
    double xx,
    double xy,
    double xz,
    double yx,
    double yy,
    double yz,
    double zx,
    double zy,
    double zz,
    double tx,
    double ty,
    double tz,
  ) {
    m.storage
      ..[0] = xx
      ..[1] = xy
      ..[2] = xz
      ..[3] = 0
      ..[4] = yx
      ..[5] = yy
      ..[6] = yz
      ..[7] = 0
      ..[8] = zx
      ..[9] = zy
      ..[10] = zz
      ..[11] = 0
      ..[12] = tx
      ..[13] = ty
      ..[14] = tz
      ..[15] = 1;
  }

  /// translate · rotateY(yaw), returned: things that hang.
  static vm.Matrix4 yawAt(vm.Matrix4 m, double x, double y, double z, double yaw) {
    final c = math.cos(yaw), s = math.sin(yaw);
    _setBasis(m, c, 0, -s, 0, 1, 0, s, 0, c, x, y, z);
    return m;
  }

  /// translate · rotateY(yaw) · rotateZ(roll) · rotateX(pitch).
  static void _setYawRollPitch(vm.Matrix4 m, double x, double y, double z, double yaw, double roll, double pitch) {
    final cb = math.cos(yaw), sb = math.sin(yaw), cr = math.cos(roll), sr = math.sin(roll), ca = math.cos(pitch), sa = math.sin(pitch);
    _setBasis(
      m,
      cr * cb,
      sr,
      -cr * sb,
      -ca * sr * cb + sa * sb,
      ca * cr,
      ca * sr * sb + sa * cb,
      sa * sr * cb + ca * sb,
      -sa * cr,
      -sa * sr * sb + ca * cb,
      x,
      y,
      z,
    );
  }
}

// ── Smoothing what's shown ──────────────────────────────────────────────────

/// What one figure last showed, so that a pose that jumps (a scene moving
/// someone on to their next move, a turn on the spot, setting off or
/// stopping) doesn't on screen: the jump becomes an offset from the new
/// pose that dies away, critically damped, in a third of a second
/// ("inertialization"); poses that move smoothly show as they are. Turns
/// taken walking lean the figure into them.
///
/// [Figures] keeps one per person; [clock] is the scene's time.
class FigureMotion {
  /// The scene's clock (seconds), set by the world every frame.
  static double clock = 0;

  /// How fast a jump dies away (seconds; about 95 % gone after 4.7 of
  /// these).
  static const settle = 0.07;

  static const _n = FigureRig.channels;
  final _last = Float64List(_n), _rate = Float64List(_n), _off = Float64List(_n), _offRate = Float64List(_n);

  /// This frame's offsets (shown − posed).
  final now = Float64List(_n);
  double _t = double.nan, _x = 0, _z = 0, _shownYaw = 0, _bank = 0;
  bool _arms = false, _walking = false;

  /// Whether the last frame was a jump, of the body (the trunk and the
  /// legs) and of the arms: its rates are the ones from before it, so this
  /// frame's steps (the new pose's own pace) aren't a jump.
  bool _jumpedBody = false, _jumpedArms = false;

  /// How far off where it was going a joint must be to count as a jump.
  static final _jump = Float64List.fromList([
    0.3, 0.05, 0.15, 0.15, 0.12, 0.15, 0.2, 0.03, 0.06, 0.06, 0.06, 2, 0.04, // the trunk
    0.25, 0.35, 0.35, 0.08, 0.25, 0.35, 0.35, 0.08, // the legs
    0.05, 0.05, 0.05, 0.35, 0.35, 0.35, 0.05, 0.05, 0.05, 0.35, 0.35, 0.35, // the arms
  ]);

  /// The fastest a joint moves (a second): faster than this is a jump, and
  /// a jump carries on no faster.
  static final _speed = Float64List.fromList([
    7, 1.6, 3, 4, 3, 4, 6, 0.6, 1.5, 1.5, 1.5, 40, 0.6, // the trunk
    10, 18, 14, 4, 10, 18, 14, 4, // the legs
    4, 4, 4, 10, 10, 10, 4, 4, 4, 10, 10, 10, // the arms
  ]);

  static double _wrap(double a) {
    var d = a % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    return d;
  }

  /// Smooths [rig]'s [FigureRig.joints] for [p] (in place).
  void filter(FigureRig rig, FigurePose p, {required bool arms, required bool commit}) {
    final j = rig.joints;
    final t = clock, dt = t - _t;
    final px = p.pos.x + p.nudgeX, pz = p.pos.z + p.nudgeZ, dx = px - _x, dz = pz - _z;
    if (_t.isNaN || dt < 0 || dt > 0.3 || dx * dx + dz * dz > 0.64 || (arms && !_arms)) {
      // New, back after a while, or somewhere else: as posed.
      now.fillRange(0, _n, 0);
      if (commit) {
        for (var i = 0; i < _n; i++) {
          _last[i] = j[i];
          _rate[i] = _off[i] = _offRate[i] = 0;
        }
        _t = t;
        _x = px;
        _z = pz;
        _shownYaw = j[FigureRig.jYaw];
        _bank = 0;
        _arms = arms;
        _walking = p.stride.isFinite;
        _jumpedBody = _jumpedArms = false;
      }
      return;
    }
    final n = arms ? _n : FigureRig.jArm;
    final e = math.exp(-dt / settle);
    // A jump in the body (or setting off, or stopping) is a new pose for
    // it: every joint of it carries on from where it was; the arms the
    // same, on their own (a hand going somewhere new mustn't throw the
    // legs). A jump is a step faster than anyone moves, or (the rates
    // being the pose's own: not just after a jump) a sudden change of
    // pace; a walk's legs swing fast, so only a bigger one there.
    final walking = p.stride.isFinite;
    var body = dt > 0 && walking != _walking, arms2 = body;
    for (var i = 0; i < n && dt > 0; i++) {
      final arm = i >= FigureRig.jArm;
      if (arm ? arms2 : body) continue;
      var step = j[i] - _last[i];
      if (i == FigureRig.jYaw) step = _wrap(step);
      final legs = walking && i >= FigureRig.jLeg && !arm;
      final after = arm ? _jumpedArms : _jumpedBody;
      if (step.abs() > _jump[i] + _speed[i] * dt || (!after && (step - _rate[i] * dt).abs() > _jump[i] * (legs ? 2.5 : 1))) {
        if (arm) {
          arms2 = true;
        } else {
          body = true;
        }
      }
    }
    for (var i = 0; i < n; i++) {
      final x = j[i], jumped = i >= FigureRig.jArm ? arms2 : body;
      var step = x - _last[i];
      if (i == FigureRig.jYaw) step = _wrap(step);
      final miss = step - _rate[i] * dt;
      // What's left of earlier jumps dies away…
      final o0 = _off[i], v0 = _offRate[i], c = v0 + o0 / settle;
      var o = (o0 + c * dt) * e;
      final ov = (v0 - c * dt / settle) * e;
      double rate;
      if (jumped) {
        // …and a new one is shown carrying on from where it was.
        o -= miss;
        rate = _rate[i];
      } else {
        rate = dt > 0 ? (step / dt).clamp(-_speed[i], _speed[i]) : _rate[i];
      }
      now[i] = o;
      j[i] = x + o;
      if (commit) {
        _last[i] = x;
        _rate[i] = rate;
        _off[i] = o;
        _offRate[i] = ov;
      }
    }
    // Into the turn: leaning the way it turns, the more so the faster.
    final yaw = j[FigureRig.jYaw];
    var bank = _bank;
    if (dt > 0) {
      final turn = _wrap(yaw - _shownYaw) / dt, v = math.sqrt(dx * dx + dz * dz) / dt;
      bank = approach(_bank, (-0.045 * turn * v).clamp(-0.1, 0.1), dt, 0.12);
    }
    j[FigureRig.jBank] += bank;
    if (commit) {
      _t = t;
      _x = px;
      _z = pz;
      _shownYaw = yaw;
      _bank = bank;
      _arms = arms;
      _walking = walking;
      if (dt > 0) {
        _jumpedBody = body;
        _jumpedArms = arms2;
      }
    }
  }
}
