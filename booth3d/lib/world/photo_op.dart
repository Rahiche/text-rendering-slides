import 'dart:math' as math;

import 'package:text_slides/booth/model.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'crew.dart';
import 'crew_breaks.dart' show OffDuty;
import 'glyph_works.dart';
import 'kit.dart';
import 'motion.dart';
import 'prop_pool.dart';
import 'shot.dart';
import 'site_fx.dart';
import 'site_plan.dart';
import 'walk.dart';

/// What the team photo puts on screen (the 2D overlay): the countdown and
/// the flash. Refreshed every frame by the site.
class PhotoCue {
  /// The number being counted (3, 2, 1, or 0 for "say cheese"), or −1; and
  /// how far into it (0..1).
  int count = -1;
  double countF = 0;

  /// 0..1: the flash's white.
  double flash = 0;
}

/// The finale with the Glyph Works' mini name: its pixel board.
///
/// As the wall's last letter goes in, two makers lift the board off its
/// stand (upright in their hands) and carry it round to the front of the
/// wall, the third following with the tripod. A few seconds into the
/// celebration the team gathers in front of the big name — the six
/// builders, the foreman, the makers — the makers holding the board by its
/// sides, the foreman steadying its top from behind. The photographer counts
/// down (3, 2, 1, a raised hand each), the flash goes, hats fly and the
/// board goes up over their heads. The camera goes back and forth between
/// the mini name in their hands and the big name with the team in front,
/// ending on the flash. Then everyone goes back to their places and the
/// board goes home to the works, safe before the wrecking ball.
///
/// A pure function of scene time, planned once per build: the carry from
/// the build's end, the photo from the celebration's start. Called off
/// early (a sample giving way to a visitor's name, or skipped), everyone
/// turns back from wherever they are: no countdown, no flash, the board home
/// the way it came (never lifted, it stays on its stand).
class PhotoOp {
  PhotoOp(this.crew, this.works, this.fx, this.parts);

  final Crew3D crew;
  final GlyphWorks works;
  final Fx3D fx;
  final PropPool parts;

  final cue = PhotoCue();

  /// The board's bottom edge in the carriers' hands (its sides at their
  /// waists), and raised in the cheer.
  static const _hold = 0.85, _raised = 1.45;

  /// Where the board is held for the photo (the middle of its bottom edge),
  /// and where the tripod stands.
  static final _spot = vm.Vector3(0, _hold, -2.75), _tripod = vm.Vector3(-1.55, 0, -6.15);

  /// The photo's beats after [_Now.ready] (everyone in place): the
  /// countdown, "say cheese", the flash, the cheering.
  static const _counts = [2.8, 3.8, 4.8], _cheese = 5.6, _flash = 6.1, _cheers = 3.3;

  // ── Per build ─────────────────────────────────────────────────────────────

  BuildPlan? _planned;
  _Plan? _p;
  _Now? _now, _cached;
  double _t = 0;

  _Plan _plan(BuildPlan plan) {
    if (identical(plan, _planned) && _p != null) return _p!;
    _planned = plan;
    _cached = null;
    final p = _p = _Plan(plan, works, crew);
    if (const String.fromEnvironment('BOOTH3D_TIMES') != '') {
      String f(double v) => v.toStringAsFixed(1);
      final c = plan.t0 + plan.len + CityPace.reveal;
      // ignore: avoid_print
      print(
        'PLAN photo lift=${f(p.lift)} there=${f(p.out.end)} tripod=${f(p.toSpot.end)} (if the celebration starts at ${f(c)}: ready=${f(p.readyAt(c))} flash=${f(p.readyAt(c) + _flash)} back=${f(p.backAt(c))})',
      );
    }
    return p;
  }

  /// Poses the makers, places the board and the tripod, and fills [cue], for
  /// [j] at [t]. Call before the works' and the crew's updates.
  void update(BoothModel m, Job j, BuildPlan? plan, double t) {
    _t = t;
    cue
      ..count = -1
      ..flash = 0;
    _now = null;
    if (plan == null || !identical(plan.job, j) || works.boardDone == null) return;
    if (j.phase.index < Phase.build.index) return;
    final p = _plan(plan);
    // The celebration's start: as it happened, or (before) as it will be;
    // and when the demolition came (the finale called off, if it was early).
    if (j.phase == Phase.celebrate) p.celebrate = j.phaseStart;
    if (j.phase.index >= Phase.demolish.index && p.over.isNaN) p.over = j.phaseStart;
    if (t < math.min(p.lift - 3.5, math.min(p.toBoard[0].start, p.toBoard[1].start))) return;
    final c = j.phase.index >= Phase.celebrate.index && !p.celebrate.isNaN ? p.celebrate : plan.t0 + plan.len + m.pace.phaseLen(Phase.reveal);
    final away = math.min(p.over.isNaN ? double.infinity : p.over, p.backAt(c));
    var now = _cached;
    if (now == null || !identical(now.p, p) || now.c != c || now.away != away) {
      now = _cached = _Now(
        p,
        c,
        away,
        boardW: works.boardWidth,
        watch: {for (var z = 0; z < Crew3D.builders; z++) z: crew.watchSpot(z, p.w), Crew3D.foreman: vm.Vector3(p.w / 2 + 0.75, 0, -1.55)},
      );
    }
    if (t >= now.done) return;
    _now = now;
    _board(now, t);
    _makers(now, t);
    _tripodAt(now, t);
    _cue(now, t);
  }

  // ── The board ─────────────────────────────────────────────────────────────

  /// The board at [t] (null: on its stand): the middle of its bottom edge,
  /// which way its carriers face, and how far it leans back (as on its
  /// stand; upright in their hands). The board itself never turns: the mini
  /// name always reads to the front (they carry it side by side going out
  /// and in, one behind the other along the wall).
  ({double x, double z, double yaw, double y, double tilt})? _boardAt(_Now n, double t) {
    final p = n.p;
    if (t < p.lift || t >= n.home) return null;
    if (t < math.min(p.out.end, n.away)) {
      final k = p.out.at(t);
      final up = eio(seg(t, p.lift, p.lift + 0.6));
      return (x: k.x, z: k.z, yaw: k.yaw, y: lerp(WorksLayout.boardY, _hold, up), tilt: WorksLayout.boardTilt * (1 - up));
    }
    if (t < n.away) {
      // Held for the photo, raised in the cheer.
      final f = n.flash;
      final up = eio(seg(t, f + 0.25, f + 0.9)) * (1 - eio(seg(t, f + 2.6, f + 3.2)));
      return (x: _spot.x, z: _spot.z, yaw: 0.0, y: lerp(_hold, _raised, up) - 0.02 * math.sin(t * 2.2) * (1 - up), tilt: 0.0);
    }
    // (Lifted before [_Now.away], so there's a way back.)
    final back = n.back!;
    final k = back.at(t);
    final down = eio(seg(t, back.end - 0.6, back.end));
    return (x: k.x, z: k.z, yaw: k.yaw, y: lerp(_hold, WorksLayout.boardY, down), tilt: WorksLayout.boardTilt * down);
  }

  void _board(_Now n, double t) {
    final k = _boardAt(n, t);
    if (k == null) return;
    works.held = (at: vm.Vector3(k.x, k.y, k.z), yaw: 0.0, tilt: k.tilt);
  }

  /// Where the board's side at [side] (−1 left, +1 right) is, [inset] in
  /// from its edge, a third of the way up.
  vm.Vector3 _side(({double x, double z, double yaw, double y, double tilt}) k, double side, double inset, vm.Vector3 out) {
    final up = works.boardHeight * 0.35;
    return out..setValues(k.x + side * (works.boardWidth / 2 - inset), k.y + up * math.cos(k.tilt), k.z + up * math.sin(k.tilt));
  }

  // ── The makers ────────────────────────────────────────────────────────────

  final _a = vm.Vector3.zero(), _b = vm.Vector3.zero();
  static final _onStand = (x: WorksLayout.boardX, z: WorksLayout.boardZ, yaw: 0.0, y: WorksLayout.boardY, tilt: WorksLayout.boardTilt);

  void _makers(_Now n, double t) {
    final p = n.p;
    final k = _boardAt(n, t);
    for (var i = 0; i < 2; i++) {
      final to = p.toBoard[i], home = n.toHome[i];
      if (home == null || t < to.start || t >= home.end) continue;
      works.finaleMakers |= 1 << i;
      final f = crew.poses[Crew3D.makers + i]
        ..rest()
        ..visible = true;
      final side = i == 0 ? -1.0 : 1.0;
      final seed = 40 + i * 7;
      if (t < to.end) {
        // To their side of the board on its stand.
        to.pose(f, t, seed);
        continue;
      }
      if (k == null && t >= home.start) {
        // Home again.
        home.pose(f, t, seed);
        continue;
      }
      if (k == null) {
        // At the stand, hands on the board's sides: about to lift it (or
        // just set it down).
        to.pose(f, t, seed);
        _grip(f, _side(_onStand, side, 0.02, _a));
        f.lean = 0.2;
        continue;
      }
      // At their side of the board, facing where it goes, holding it.
      f.pos.setValues(k.x + side * (works.boardWidth / 2 + 0.17), 0, k.z);
      f.yaw = k.yaw;
      final walking = _moving(n, t);
      if (walking) {
        OffDuty.walk(f, t, 1.4, seed);
      } else {
        OffDuty.stand(f, t, seed);
      }
      _grip(f, _side(k, side, 0.03, _a));
      if (!walking) _cheer(f, t, n.flash, seed, hands: true);
    }
  }

  /// Both of [f]'s hands on the board's side at [at], one above the other.
  void _grip(FigurePose f, vm.Vector3 at) {
    for (var s = 0; s < 2; s++) {
      _b
        ..setFrom(at)
        ..y += s == 0 ? -0.07 : 0.07;
      crew.aim(f, s, _b);
    }
  }

  bool _moving(_Now n, double t) {
    final p = n.p, back = n.back;
    if (t >= p.lift + 0.6 && t < math.min(p.out.end - 0.3, n.away)) return true;
    return back != null && t >= n.away && t < back.end - 0.6;
  }

  /// Both of [f]'s hands on [at] (a little either side of it).
  void _hands(FigurePose f, vm.Vector3 at) {
    for (var s = 0; s < 2; s++) {
      _b
        ..setFrom(at)
        ..z += s == 0 ? -0.06 : 0.06;
      crew.aim(f, s, _b);
    }
  }

  /// The cheer after the [flash]: a happy bounce and a round of applause
  /// (just the bounce, when the hands are on the board).
  void _cheer(FigurePose f, double t, double flash, int seed, {bool hands = false}) {
    final u = t - flash;
    if (u < 0) return;
    final k = seg(u, 0.1, 0.35) * (1 - seg(u, 3.0, 3.6)), rate = 2.4 + 0.3 * (seed % 3);
    f.bob = -0.025 * k * (0.5 + 0.5 * math.sin((t * rate + seed * 0.1) * 2 * math.pi));
    if (!hands) Idle.clap(f, t, rate, k, seed * 0.1);
  }

  // ── The photographer and the tripod ───────────────────────────────────────

  static final _dark = v4(hex3(0x1B2233)), _steel = v4(hex3(0x8A96A6)), _body = v4(hex3(0x2A3344)), _white = vm.Vector4(1, 1, 1, 1);
  final _head = vm.Vector3.zero();

  void _tripodAt(_Now n, double t) {
    final go = n.p.toSpot, home = n.spotHome;
    if (home == null || t < go.start || t >= home.end) return;
    works.finaleMakers |= 4;
    final w2 = crew.poses[Crew3D.makers + 2]
      ..rest()
      ..visible = true;
    final f = n.flash;
    final setUp = go.end, fold = n.fold;
    if (n.away <= setUp || t < setUp || t >= n.packed) {
      // Walking there (or home: turned back on the way, if it was called
      // off) with the tripod folded on the shoulder.
      (t < math.min(setUp, n.away) ? go : home).pose(w2, t, 61);
      w2.handTo(1, 0.2, 0.52, -0.1);
      OffDuty.hand(w2, 1, _a);
      _b.setValues(_a.x + math.sin(w2.yaw) * 0.6, _a.y + 0.55, _a.z + math.cos(w2.yaw) * 0.6);
      parts.rod(_a, _b, 0.025, _dark);
      return;
    }
    // Set up: legs out, the camera on top, pointed at the team.
    final open = eio(seg(t, setUp, setUp + 1.2)) * (1 - eio(seg(t, fold, n.packed)));
    _head.setValues(_tripod.x, 0.5 + 0.55 * open, _tripod.z);
    final head = _head;
    final aim = math.atan2(-(_spot.x - head.x), -(_spot.z - head.z));
    final ax = -math.sin(aim), az = -math.cos(aim);
    for (var leg = 0; leg < 3; leg++) {
      final a = aim + (leg - 1) * 2.1;
      _a.setValues(head.x + math.sin(a) * 0.36 * open, 0, head.z + math.cos(a) * 0.36 * open);
      parts.rod(head, _a, 0.012, _dark);
    }
    if (open > 0.5) {
      parts
        ..box(head.x, head.y + 0.07, head.z, 0.16, 0.11, 0.09, _body, yaw: aim)
        ..cyl(head.x + ax * 0.08, head.y + 0.07, head.z + az * 0.08, 0.035, 0.08, _steel, yaw: aim, pitch: math.pi / 2)
        ..box(head.x, head.y + 0.15, head.z, 0.06, 0.04, 0.03, _white, yaw: aim);
      // The self-timer's red light blinks faster as it counts down.
      if (t >= n.ready + _counts[0] - 0.4 && t < math.min(f, n.away)) {
        final rate = 2.0 + 3 * seg(t, n.ready + _counts[0], f);
        if ((t * rate) % 1.0 < 0.5) parts.glow(head.x + ax * 0.05, head.y + 0.1, head.z + az * 0.05, 0.015, 0.015, 0.015, _red);
      }
      // The flash, and its light on the team (after dark, as a firework's).
      if (t >= f && t < f + 0.14) {
        parts.glow(head.x + ax * 0.02, head.y + 0.15, head.z + az * 0.02, 0.07, 0.05, 0.035, _blaze);
        fx.spark(head.x + ax * 0.05, head.y + 0.15, head.z + az * 0.05, 0.5 * (1 - (t - f) / 0.14), _white, 18);
      }
      if (t >= f && t < f + 0.5) {
        fx.flashes.insert(0, (vm.Vector3(head.x + ax * 0.4, head.y + 0.3, head.z + az * 0.4), _white, 2.4 * math.pow(1 - (t - f) / 0.5, 2).toDouble()));
      }
    }
    // The photographer: unfolding it, at the viewfinder, counting down on
    // the fingers of a hand held out, a thumbs up after.
    w2.pos.setValues(head.x - ax * 0.5, 0, head.z - az * 0.5);
    OffDuty.stand(w2, t, 61);
    w2.yaw = aim;
    if (t < setUp + 1.3 || t >= fold) {
      w2.lean = 0.45;
      _hands(w2, head);
      return;
    }
    w2.lean = 0.3;
    _b.setValues(head.x, head.y + 0.08, head.z);
    crew.aim(w2, 0, _b);
    if (t < f + 0.4) {
      crew.aim(w2, 1, _b);
      // A hand held out for each number.
      for (final c in _counts) {
        final k = math.sin(math.pi * seg(t, n.ready + c - 0.15, n.ready + c + 0.55));
        if (k > 0) {
          w2.handTo(1, 0.3, 0.3, -0.32, k);
          w2.lean = lerp(w2.lean, 0.1, k);
        }
      }
    } else {
      w2
        ..lean = 0.05
        ..handTo(1, 0.2, 0.28, -0.3);
      _cheer(w2, t, f, 61, hands: true);
    }
  }

  static final _red = vm.Vector4(8, 0.4, 0.3, 1), _blaze = vm.Vector4(30, 30, 30, 1);

  // ── The 2D overlay's cue ──────────────────────────────────────────────────

  void _cue(_Now n, double t) {
    if (t >= n.away) return;
    final f = n.ready + _flash;
    for (var i = 0; i < 3; i++) {
      final a = n.ready + _counts[i];
      if (t >= a && t < a + 1.0) {
        cue
          ..count = 3 - i
          ..countF = t - a;
      }
    }
    if (t >= n.ready + _cheese && t < f) {
      cue
        ..count = 0
        ..countF = (t - n.ready - _cheese) / (f - n.ready - _cheese);
    }
    if (t >= f) cue.flash = 1 - seg(t, f, f + 0.55);
  }

  // ── The rest of the team ──────────────────────────────────────────────────

  /// The crew's stage hook: the builders and the foreman walk over for the
  /// photo, pose, cheer, and walk back to their places.
  void pose(int who, FigurePose f) {
    final n = _now;
    if (n == null || (who >= Crew3D.builders && who != Crew3D.foreman)) return;
    final walk = n.crew[who];
    final t = _t;
    if (walk == null || t < walk.go.start || t >= walk.back.end) return;
    final seed = who * 13 + 5;
    f
      ..rest()
      ..clipboard = false;
    if (t >= walk.back.start) {
      walk.back.pose(f, t, seed);
      return;
    }
    if (t < walk.go.end) {
      walk.go.pose(f, t, seed);
      return;
    }
    // In place, facing the camera.
    f.pos.setFrom(walk.go.last);
    OffDuty.stand(f, t, seed);
    f.yaw = Idle.facing(t, Manner.of(seed), 0.15) * (1 - seg(t, n.ready + _counts[0] - 0.5, n.ready + _counts[0]));
    final fl = n.flash;
    if (who == Crew3D.foreman) {
      // Hands on the board's top edge from behind, steadying it (and up
      // with it in the cheer).
      final k = _boardAt(n, t);
      if (k != null) {
        final top = works.boardHeight;
        for (var s = 0; s < 2; s++) {
          crew.aim(f, s, _b..setValues(k.x + (s == 0 ? -0.2 : 0.2), k.y + top * math.cos(k.tilt) + 0.01, k.z + top * math.sin(k.tilt) + 0.04));
        }
      }
      _cheer(f, t, fl, seed, hands: true);
      return;
    }
    if (t >= fl) {
      _cheer(f, t, fl, seed);
      return;
    }
    // Waiting: a word with the neighbour; for the countdown, a pose each
    // (a V, both arms up, a thumbs up, arms folded, hands on hips, a wave).
    final strike = t < n.away ? eio(seg(t, n.ready + _counts[0] - 0.6, n.ready + _counts[0])) : 0.0;
    if (strike <= 0) {
      if ((t / 3).floor() % 3 == who % 3) OffDuty.talk(f, t, seed);
      return;
    }
    final (p0, r0, p1, r1) = switch ((who + n.p.serial) % 6) {
      0 => (0.1, 0.12, 2.9, 0.28),
      1 => (2.8, 0.35, 2.8, 0.35),
      2 => (-0.3, 0.85, 1.55, -0.1),
      3 => (1.0, -0.75, 1.0, -0.75),
      4 => (-0.3, 0.85, -0.3, 0.85),
      _ => (0.1, 0.12, 2.6 + 0.25 * math.sin(t * 9), 0.35),
    };
    f.armPitch[0] = lerp(f.armPitch[0], p0, strike);
    f.armRoll[0] = lerp(f.armRoll[0], r0, strike);
    f.armPitch[1] = lerp(f.armPitch[1], p1, strike);
    f.armRoll[1] = lerp(f.armRoll[1], r1, strike);
  }

  /// Where the finale has [who] (a builder or the foreman) at [t], or null
  /// if it doesn't have them then: for whoever takes them over next (still
  /// walking back from a photo called off, say).
  vm.Vector3? whereAt(int who, double t) {
    final walk = _now?.crew[who];
    if (walk == null || t < walk.go.start || t >= walk.back.end) return null;
    if (t >= walk.back.start) return walk.back.posAt(t, vm.Vector3.zero());
    if (t < walk.go.end) return walk.go.posAt(t, vm.Vector3.zero());
    return walk.go.last.clone();
  }

  // ── The camera ────────────────────────────────────────────────────────────

  /// The camera's requests (priority 2): the team gathering, then back and
  /// forth between the mini name in their hands and the big name with the
  /// team in front, ending on the flash; a low shot of the cheer. [w] and
  /// [h]: the wall's size.
  void focus(List<Focus> out, double t, {required double w, required double h}) {
    final n = _now;
    if (n == null) return;
    final f = n.ready + _flash;
    if (t < n.c + 4.8 || t >= f + 3.4 || t >= n.away) return;
    // (Inside the front barriers or on the pavement just outside them:
    // nothing on the avenue gets between.)
    if (t < n.ready - 0.4) {
      final shot = Shot(vm.Vector3(-5.6, 2.4, -8.6), vm.Vector3(-0.6, 0.95, -2.4), fov: 46, settle: 1.6, drift: 0.6);
      out.add(Focus('photo gather', shot, priority: 2));
      return;
    }
    if (t >= f + 0.4) {
      final tg = vm.Vector3(0, math.max(2.4, h * 0.5), -0.6);
      out.add(Focus('photo cheer', Shot(vm.Vector3(0.7, 0.95, -8.3), tg, fov: 52, settle: 1.6, drift: 0.8), priority: 2));
      return;
    }
    // Back and forth: wide, close, wide, close, wide for the flash.
    final u = t - n.ready;
    final close = (u >= 1.5 && u < 2.9) || (u >= 4.1 && u < 5.1);
    final Shot shot;
    if (close) {
      // The board left of the middle, clear of the countdown (top right).
      final back = math.max(1.6, works.boardWidth * 1.35), s = 0.1 * back;
      shot = Shot(vm.Vector3(0.14 + s, _hold + 0.5, _spot.z - back), vm.Vector3(s, _hold + works.boardHeight * 0.55, _spot.z), fov: 36, settle: 0.7, drift: 0.3);
    } else {
      // From the pavement, a wide lens: the whole name, the team in front.
      final eye = vm.Vector3(0.3, 3.0, -10.0), tg = vm.Vector3(0, h * 0.42 + 0.2, -0.3);
      final d = tg.z - eye.z;
      final across = 2 * math.atan(math.tan(math.atan((w / 2 + 0.5) / d)) * 9 / 16), up = 2 * math.atan((h * 0.62 + 0.9) / d);
      shot = Shot(eye, tg, fov: (math.max(across, up) * 180 / math.pi).clamp(42.0, 56.0), settle: 0.75, drift: 0.4);
    }
    out.add(Focus('photo', shot, priority: 2));
  }
}

/// The board's carry: keys of where its middle is and which way the
/// carriers face; between keys it moves evenly (turning on the spot the
/// shortest way first, unless told which way to face: backing in).
class _Track {
  _Track(double t, double x, double z, double yaw) {
    _key(t, x, z, yaw);
  }

  final _t = <double>[], _x = <double>[], _z = <double>[], _yaw = <double>[];

  double get end => _t.last;

  void _key(double t, double x, double z, double yaw) {
    _t.add(t);
    _x.add(x);
    _z.add(z);
    _yaw.add(yaw);
  }

  void hold(double d) => _key(end + d, _x.last, _z.last, _yaw.last);

  void turn(double yaw) {
    var d = (yaw - _yaw.last) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    if (d.abs() < 1e-3) return;
    _key(end + 0.2 + 0.35 * d.abs() / math.pi, _x.last, _z.last, _yaw.last + d);
  }

  void walk(double x, double z, double speed, {double? facing}) {
    final dx = x - _x.last, dz = z - _z.last;
    final l = math.sqrt(dx * dx + dz * dz);
    if (l < 1e-3) return;
    turn(facing ?? math.atan2(-dx, -dz));
    _key(end + l / speed, x, z, _yaw.last);
  }

  /// The places it has been at by [t] (not counting where it's on its way
  /// to), in order.
  List<(double, double)> placesBy(double t) {
    final out = <(double, double)>[];
    for (var i = 0; i < _t.length && _t[i] <= t; i++) {
      if (out.isEmpty || (out.last.$1 - _x[i]).abs() + (out.last.$2 - _z[i]).abs() > 1e-3) out.add((_x[i], _z[i]));
    }
    return out;
  }

  ({double x, double z, double yaw}) at(double t) {
    if (t <= _t.first) return (x: _x.first, z: _z.first, yaw: _yaw.first);
    for (var i = 0; i + 1 < _t.length; i++) {
      if (t < _t[i + 1]) {
        final f = smooth(0, 1, (t - _t[i]) / math.max(_t[i + 1] - _t[i], 1e-3));
        return (x: lerp(_x[i], _x[i + 1], f), z: lerp(_z[i], _z[i + 1], f), yaw: lerp(_yaw[i], _yaw[i + 1], f));
      }
    }
    return (x: _x.last, z: _z.last, yaw: _yaw.last);
  }
}

/// The finale's plan for one build: when the board is lifted, the carry
/// out, the makers' and the photographer's walks there, where everyone
/// stands.
class _Plan {
  _Plan(BuildPlan plan, GlyphWorks works, Crew3D crew) : serial = plan.job.serial, w = plan.width {
    // (As the painting finishes: the reveal's last seconds, as long before
    // the celebration as when it was the booth's.)
    final end = plan.t0 + plan.len + CityPace.reveal - phaseSeconds[Phase.reveal]!;
    final d = works.boardWidth / 2 + 0.17;
    // To their sides of the board on its stand (once done with their
    // letters, from wherever that left them).
    for (var i = 0; i < 2; i++) {
      final side = vm.Vector3(WorksLayout.boardX + (i == 0 ? -1 : 1) * d, 0, WorksLayout.boardZ);
      toBoard.add(Walk(WorksLayout.route(works.freeSpot(i), side), math.max(end - 4.6, works.freeAt(i)), 1.8));
    }
    lift = [end - 1.6, works.boardDone! + 0.6, toBoard[0].end + 0.15, toBoard[1].end + 0.15].reduce(math.max);
    // Out of the front, round the wall's left end, along its front to the
    // middle; then turn to face the camera.
    xa = math.min(WorksLayout.boardX, -(w / 2 + 3.0));
    out = _Track(lift, WorksLayout.boardX, WorksLayout.boardZ, 0)
      ..hold(0.6)
      ..walk(WorksLayout.boardX, 3.0, 1.4)
      ..walk(xa, 1.2, 1.75)
      ..walk(xa, -2.6, 1.75)
      ..walk(PhotoOp._spot.x, PhotoOp._spot.z, 1.75)
      ..turn(0)
      ..hold(0.2);
    // The photographer, with the tripod, after the board (out past its
    // left).
    home = WorksLayout.homes[2];
    toSpot = Walk(
      [
        ...WorksLayout.route(works.freeSpot(2), WorksLayout.exit.first),
        WorksLayout.exit.last,
        vm.Vector3(xa + 1.6, 0, 1.0),
        vm.Vector3(xa + 1.6, 0, -4.4),
        vm.Vector3(PhotoOp._tripod.x - 0.4, 0, PhotoOp._tripod.z - 0.5),
      ],
      math.max(lift + 0.8, works.freeAt(2)),
      1.85,
    );
    // The crew's places in the photo: the makers at the board's sides, the
    // foreman behind its middle, three builders either side (in the order
    // they stand watching, so their ways don't cross).
    final order = List.generate(Crew3D.builders, (z) => z)..sort((a, b) => crew.watchSpot(a, w).x.compareTo(crew.watchSpot(b, w).x));
    for (var r = 0; r < Crew3D.builders; r++) {
      final left = r < 3;
      final k = left ? 2 - r : r - 3;
      slots[order[r]] = vm.Vector3((left ? -1 : 1) * (d + 0.52 * (k + 1)), 0, PhotoOp._spot.z + 0.15 + (k.isOdd ? 0.12 : 0));
    }
    slots[Crew3D.foreman] = vm.Vector3(0, 0, PhotoOp._spot.z + 0.42);
  }

  final int serial;
  final double w;
  final toBoard = <Walk>[];
  late final double lift;

  /// Where the carry turns along the wall (left of its end).
  late final double xa;
  late final _Track out;
  late final Walk toSpot;

  /// Where the photographer goes back to, after.
  late final vm.Vector3 home;
  final slots = <int, vm.Vector3>{};

  /// When the celebration started, and when the demolition did (once seen).
  double celebrate = double.nan, over = double.nan;

  /// When everyone's in place (the countdown follows): ten seconds into
  /// the celebration [c], or as soon as the board and the tripod are there.
  double readyAt(double c) => [c + 10, out.end + 0.8, toSpot.end + 2.0].reduce(math.max);

  /// When the team goes back to their places and the board home.
  double backAt(double c) => readyAt(c) + PhotoOp._flash + PhotoOp._cheers;
}

/// The finale's times for one celebration (starting at [c]; the team going
/// back at [away]): when everyone's in place, the board's way home,
/// everyone's walks there and back. Called off before the photo ([away]
/// early: the demolition came first), they turn back from wherever they've
/// got to, and whoever hadn't set out stays put.
class _Now {
  _Now(this.p, this.c, this.away, {required double boardW, required Map<int, vm.Vector3> watch}) : ready = p.readyAt(c), calledOff = away < p.backAt(c) - 1e-6 {
    // (Never: far off, not infinite, so the easing over it stays a number.)
    flash = away > ready + PhotoOp._flash ? ready + PhotoOp._flash : 1e9;
    // The board home: back the way it came from where it got to (in a hurry
    // when called off), backing in at the end. Never lifted, it stays.
    if (away > p.lift) {
      final at = p.out.at(math.min(away, p.out.end));
      final way = p.out.placesBy(away);
      final b = back = _Track(away, at.x, at.z, at.yaw);
      for (var i = way.length - 1; i >= 0; i--) {
        final (x, z) = way[i];
        if (i == 0) {
          b.walk(x, z, 1.0, facing: 0);
        } else {
          b.walk(x, z, calledOff ? 2.0 : 1.6);
        }
      }
      b.hold(0.6);
      home = b.end;
    } else {
      back = null;
      home = away;
    }
    for (var i = 0; i < 2; i++) {
      final to = p.toBoard[i];
      if (away <= to.start) {
        toHome.add(null);
        continue;
      }
      final side = vm.Vector3(WorksLayout.boardX + (i == 0 ? -1 : 1) * (boardW / 2 + 0.17), 0, WorksLayout.boardZ);
      toHome.add(Walk(WorksLayout.route(side, WorksLayout.homes[i]), math.max(home, to.end) + 0.2, 1.35));
    }
    // The photographer packs up and follows (or turns back on the way),
    // and goes on home.
    final go = p.toSpot;
    List<vm.Vector3> andHome(List<vm.Vector3> way) => [...way, ...WorksLayout.route(way.last, p.home).skip(1)];
    if (away <= go.start) {
      spotHome = null;
      fold = packed = away;
    } else if (away < go.end) {
      spotHome = Walk(andHome(go.backFrom(away)), away + 0.15, 1.5);
      fold = packed = away;
    } else {
      fold = calledOff ? away : away - 0.9;
      packed = fold + 0.9;
      spotHome = Walk(andHome(go.pts.reversed.toList()), calledOff ? packed + 0.3 : away + 1.2, 1.5);
    }
    // The builders and the foreman: over for the photo (behind the line of
    // the board, then forward into place), and back.
    for (final MapEntry(key: who, value: slot) in p.slots.entries) {
      final from = watch[who]!;
      final start = c + 4.5 + (who == Crew3D.foreman ? 1.2 : 0.18 * who);
      final via = vm.Vector3(slot.x, 0, -1.75);
      final pts = [from, via, slot];
      final go = Walk(pts, start, (Walk.lengthOf(pts) / math.max(1.0, ready - 0.6 - start)).clamp(1.3, 2.6));
      if (away <= go.start) continue;
      final face = who == Crew3D.foreman ? 0.9 : 0.5;
      final Walk back;
      if (away < go.end) {
        final backPts = go.backFrom(away);
        back = Walk(backPts, away, math.max(1.4, Walk.lengthOf(backPts) / 3.6), face: face);
      } else {
        final backPts = [slot, via, from];
        back = Walk(backPts, away + 0.1 + 0.12 * (who % 6), math.max(1.4, Walk.lengthOf(backPts) / 3.6), face: face);
      }
      crew[who] = (go: go, back: back);
    }
    done = [away, home, for (final w in toHome) ?w?.end, ?spotHome?.end, for (final w in crew.values) w.back.end].reduce(math.max);
  }

  final _Plan p;
  final double c, away, ready;

  /// The finale was called off before the photo was done.
  final bool calledOff;

  /// The flash (never, if called off before it: 1e9).
  late final double flash;
  late final _Track? back;
  late final double home, done;

  /// When the photographer starts folding the tripod, and has.
  late final double fold, packed;
  final toHome = <Walk?>[];
  late final Walk? spotHome;
  final crew = <int, ({Walk go, Walk back})>{};
}
