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
/// As the wall's last letter goes in, the works' drone comes over from its
/// dock by the hall's door, takes the board off its stand, flies it out of
/// the door, over the side street and the plaza, and brings it down in
/// front of the wall.
/// A few seconds into the celebration the team gathers in front of the big
/// name — the six builders and the foreman — the two in the middle taking
/// the board by its sides, the foreman steadying its top from behind; the
/// drone goes up and round to face them: it takes the photo. It counts
/// down (3, 2, 1, its light blinking faster), the flash goes, hats fly and
/// the board goes up over their heads. The camera goes back and forth
/// between the mini name in their hands and the big name with the team in
/// front, ending on the flash. Then the drone takes the board back and
/// flies it home to its stand, safe before the wrecking ball, and goes
/// back to its dock; everyone goes back to their places.
///
/// A pure function of scene time, planned once per build: the flight from
/// the build's end, the photo from the celebration's start. Called off
/// early (a sample giving way to a visitor's name, or skipped), the drone
/// turns back with the board from wherever it is (or comes back for it):
/// no countdown, no flash; never lifted, it stays on its stand (and the
/// drone, if it was on its way over, goes back to its dock).
class PhotoOp {
  PhotoOp(this.crew, this.works, this.fx, this.parts);

  final Crew3D crew;
  final GlyphWorks works;
  final Fx3D fx;
  final PropPool parts;

  final cue = PhotoCue();

  /// The board's bottom edge in the holders' hands (its sides at their
  /// waists), and raised in the cheer.
  static const _hold = 0.85, _raised = 1.05;

  /// Where the board is held for the photo (the middle of its bottom edge),
  /// and where the drone takes it from (hovering, facing the team).
  static final _spot = vm.Vector3(0, _hold, -2.75), _camera = vm.Vector3(-1.55, 1.7, -6.15);

  /// The photo's beats after [_Now.ready] (everyone in place): the
  /// countdown, "say cheese", the flash, the cheering.
  static const _counts = [2.8, 3.8, 4.8], _cheese = 5.6, _flash = 6.1, _cheers = 3.3;

  /// The drone's cruising speed (metres a second, on average), and how
  /// long it takes to come for the board or go from it.
  static const _speed = 3.0, _hop = 1.6;

  /// How long the drone takes from its dock onto the board's top on its
  /// stand (its rotors spinning up first), or back; and how high its
  /// middle is over what it stands on (on its skids).
  static const _fetch = 2.6, _perch = 0.15;

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
      print('PLAN photo lift=${f(p.lift)} there=${f(p.arrive)} (if the celebration starts at ${f(c)}: ready=${f(p.readyAt(c))} flash=${f(p.readyAt(c) + _flash)} back=${f(p.backAt(c))})');
    }
    return p;
  }

  /// Flies the drone, places the board and fills [cue], for [j] at [t].
  /// Call before the works' and the crew's updates.
  void update(BoothModel m, Job j, BuildPlan? plan, double t) {
    _t = t;
    cue
      ..count = -1
      ..flash = 0;
    _now = null;
    if (plan == null || !identical(plan.job, j) || works.boardDone == null || j.phase.index < Phase.build.index) {
      _docked();
      return;
    }
    final p = _plan(plan);
    // The celebration's start: as it happened, or (before) as it will be;
    // and when the demolition came (the finale called off, if it was early).
    if (j.phase == Phase.celebrate) p.celebrate = j.phaseStart;
    if (j.phase.index >= Phase.demolish.index && p.over.isNaN) p.over = j.phaseStart;
    if (t < p.lift - _fetch) {
      _docked();
      return;
    }
    final c = j.phase.index >= Phase.celebrate.index && !p.celebrate.isNaN ? p.celebrate : plan.t0 + plan.len + m.pace.phaseLen(Phase.reveal);
    final away = math.min(p.over.isNaN ? double.infinity : p.over, p.backAt(c));
    var now = _cached;
    if (now == null || !identical(now.p, p) || now.c != c || now.away != away) {
      now = _cached = _Now(
        p,
        c,
        away,
        watch: {for (var z = 0; z < Crew3D.builders; z++) z: crew.watchSpot(z, p.w), Crew3D.foreman: vm.Vector3(p.w / 2 + 0.75, 0, -1.55)},
      );
    }
    if (t >= now.done) {
      _docked();
      return;
    }
    _now = now;
    _board(now, t);
    _drone(now, t);
    _cue(now, t);
  }

  // ── The board ─────────────────────────────────────────────────────────────

  /// The board at [t] (null: on its stand): the middle of its bottom edge,
  /// and how far it leans back (as on its stand; upright off it). It never
  /// turns: the mini name always reads to the front.
  ({double x, double y, double z, double tilt})? _boardAt(_Now n, double t) {
    final p = n.p;
    if (t < p.lift || t >= n.home) return null;
    // Under the drone: out to the photo, or home.
    final s = n.flownAt(t);
    if (s != null) {
      p.flight.at(s, _a);
      final off = 1 - eio(seg(t, p.lift, p.lift + 0.8)) + eio(seg(t, n.home - 0.8, n.home));
      return (x: _a.x, y: _a.y, z: _a.z, tilt: WorksLayout.boardTilt * off.clamp(0.0, 1.0));
    }
    // In the holders' hands for the photo, raised in the cheer.
    final f = n.flash;
    final up = eio(seg(t, f + 0.25, f + 0.9)) * (1 - eio(seg(t, f + 2.6, f + 3.2)));
    return (x: _spot.x, y: lerp(_hold, _raised, up) - 0.02 * math.sin(t * 2.2) * (1 - up), z: _spot.z, tilt: 0.0);
  }

  void _board(_Now n, double t) {
    final k = _boardAt(n, t);
    if (k == null) return;
    works.held = (at: vm.Vector3(k.x, k.y, k.z), yaw: 0.0, tilt: k.tilt);
  }

  /// Where the board's side at [side] (−1 left, +1 right) is, [inset] in
  /// from its edge, a third of the way up.
  vm.Vector3 _side(({double x, double y, double z, double tilt}) k, double side, double inset, vm.Vector3 out) {
    final up = works.boardHeight * 0.35;
    return out..setValues(k.x + side * (works.boardWidth / 2 - inset), k.y + up * math.cos(k.tilt), k.z + up * math.sin(k.tilt));
  }

  final _a = vm.Vector3.zero(), _b = vm.Vector3.zero();

  /// Both of [f]'s hands on the board's side at [at], one above the other.
  void _grip(FigurePose f, vm.Vector3 at) {
    for (var s = 0; s < 2; s++) {
      _b
        ..setFrom(at)
        ..y += s == 0 ? -0.07 : 0.07;
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

  // ── The drone ─────────────────────────────────────────────────────────────

  static final _dark = v4(hex3(0x1B2233)), _shell = v4(hex3(0xF2F0EA)), _paint = v4(hex3(0xF0862A)), _blur = v4(hex3(0x39404D)), _white = vm.Vector4(1, 1, 1, 1);
  final _at = vm.Vector3.zero(), _to = vm.Vector3.zero();

  /// The drone at rest on its dock in the works, its charging light on.
  void _docked() {
    _at.setValues(WorksLayout.dockX, WorksLayout.dockY + _perch, WorksLayout.dockZ);
    _drawDrone(_at, 0, false, 0);
    parts.glow(WorksLayout.dockX + 0.25, WorksLayout.dockY - 0.03, WorksLayout.dockZ - 0.455, 0.05, 0.02, 0.01, _green * 0.5);
  }

  /// The drone [f] of the way from its dock (0) onto the board's top on its
  /// stand (1): its rotors spinning up on the dock first (down after, back
  /// on it); up off it, along the wall past the door, down onto the board
  /// from in front (under the board's sign).
  void _hopping(double f, double t) {
    final m = eio(seg(f, 0.18, 1)), u = 1 - m;
    final top = works.boardHeight, tilt = WorksLayout.boardTilt;
    _a.setValues(WorksLayout.dockX, WorksLayout.dockY + _perch, WorksLayout.dockZ);
    _b.setValues(WorksLayout.boardX, WorksLayout.boardY + top * math.cos(tilt) + 0.38, WorksLayout.boardZ + top * math.sin(tilt));
    // (A curve through a point over the middle of the way.)
    _to
      ..setFrom(_a)
      ..add(_b)
      ..scale(0.5)
      ..y += 0.9;
    _at
      ..setFrom(_a * (u * u))
      ..add(_to * (2 * u * m))
      ..add(_b * (m * m))
      ..y += 0.025 * math.sin(t * 2.7) * seg(f, 0.18, 0.35);
    _drawDrone(_at, 0, f > 0, t);
  }

  /// The drone at [t]: coming over from its dock or going back to it, with
  /// the board under it, going for it or from it, or hovering where it
  /// takes the photo (facing the team); its light counting down, the flash.
  void _drone(_Now n, double t) {
    if (n.hopAt(t) case final f?) {
      _hopping(f, t);
      return;
    }
    final k = _boardAt(n, t);
    final top = works.boardHeight;
    var face = 0.0;
    var carrying = false;
    if (k != null && n.flownAt(t) != null) {
      // Carrying it: just over its top.
      _at.setValues(k.x, k.y + top * math.cos(k.tilt) + 0.38, k.z + top * math.sin(k.tilt));
      carrying = true;
    } else {
      // Off the board: up and round to where it takes the photo, and back
      // for the board after.
      _to.setValues(_spot.x, _hold + top + 0.38, _spot.z);
      final out = eio(seg(t, n.handoff + 0.2, n.handoff + 0.2 + _hop + 0.6));
      final back = eio(seg(t, n.pickup - _hop, n.pickup));
      final f = out * (1 - back);
      _at.setValues(lerp(_to.x, _camera.x, f), lerp(_to.y, _camera.y, f) + 0.45 * math.sin(math.pi * f), lerp(_to.z, _camera.z, f));
      face = math.atan2(_spot.x - _camera.x, _spot.z - _camera.z) * f;
    }
    final bob = 0.025 * math.sin(t * 2.7);
    _at.y += bob;
    _drawDrone(_at, face, true, t);
    if (carrying) {
      // Its clamps on the board's top edge.
      for (final sd in [-0.32, 0.32]) {
        _b.setValues(_at.x + sd, _at.y - 0.06, _at.z);
        _a.setValues(k!.x + sd, k.y + top * math.cos(k.tilt), k.z + top * math.sin(k.tilt));
        parts.rod(_b, _a, 0.012, _dark);
      }
    }
    // The countdown on its light (faster and faster), the flash, and its
    // light on the team (after dark, as a firework's).
    final f = n.flash;
    final ax = math.sin(face), az = math.cos(face);
    if (t >= n.ready + _counts[0] - 0.4 && t < math.min(f, n.away)) {
      final rate = 2.0 + 3 * seg(t, n.ready + _counts[0], f);
      if ((t * rate) % 1.0 < 0.5) parts.glow(_at.x + ax * 0.2, _at.y + 0.02, _at.z + az * 0.2, 0.03, 0.03, 0.03, _red);
    }
    if (t >= f && t < f + 0.14) {
      parts.glow(_at.x + ax * 0.21, _at.y - 0.08, _at.z + az * 0.21, 0.08, 0.05, 0.04, _blaze);
      fx.spark(_at.x + ax * 0.25, _at.y - 0.08, _at.z + az * 0.25, 0.5 * (1 - (t - f) / 0.14), _white, 18);
    }
    if (t >= f && t < f + 0.5) {
      fx.flashes.insert(0, (vm.Vector3(_at.x + ax * 0.6, _at.y + 0.2, _at.z + az * 0.6), _white, 2.4 * math.pow(1 - (t - f) / 0.5, 2).toDouble()));
    }
  }

  /// A quadcopter at [at] facing [yaw]: a shell, four arms out to its
  /// rotors (a blur while it flies, still blades on the dock), its camera
  /// underneath, the skids it lands on, its lights.
  void _drawDrone(vm.Vector3 at, double yaw, bool flying, double t) {
    final sn = math.sin(yaw), cs = math.cos(yaw);
    parts
      ..box(at.x, at.y, at.z, 0.34, 0.11, 0.42, _shell, yaw: yaw)
      ..box(at.x, at.y + 0.065, at.z, 0.22, 0.03, 0.26, _paint, yaw: yaw)
      ..box(at.x + sn * 0.19, at.y - 0.08, at.z + cs * 0.19, 0.09, 0.08, 0.08, _dark, yaw: yaw);
    for (final sx in [-0.13, 0.13]) {
      parts.box(at.x + cs * sx, at.y - _perch + 0.012, at.z - sn * sx, 0.022, 0.022, 0.4, _dark, yaw: yaw);
      for (final sz in [-0.1, 0.1]) {
        parts.box(at.x + cs * sx + sn * sz, at.y - (_perch + 0.05) / 2, at.z - sn * sx + cs * sz, 0.016, _perch - 0.05, 0.016, _dark, yaw: yaw);
      }
    }
    for (var i = 0; i < 4; i++) {
      final a = yaw + math.pi / 4 + i * math.pi / 2;
      _b.setValues(at.x + math.sin(a) * 0.42, at.y + 0.03, at.z + math.cos(a) * 0.42);
      parts.rod(at, _b, 0.022, _dark);
      if (flying) {
        parts.cyl(_b.x, _b.y + 0.045, _b.z, 0.2, 0.008, _blur);
      } else {
        final r = 0.6 * i;
        parts.box(_b.x, _b.y + 0.045, _b.z, 0.36, 0.006, 0.03, _dark, yaw: r);
      }
      parts.cyl(_b.x, _b.y + 0.015, _b.z, 0.035, 0.05, _paint);
    }
    // (Its lights: green ahead, red behind, steady.)
    parts
      ..glow(at.x + math.sin(yaw) * 0.215, at.y, at.z + math.cos(yaw) * 0.215, 0.025, 0.02, 0.01, _green)
      ..glow(at.x - math.sin(yaw) * 0.215, at.y, at.z - math.cos(yaw) * 0.215, 0.025, 0.02, 0.01, _red * 0.5);
  }

  static final _red = vm.Vector4(8, 0.4, 0.3, 1), _green = vm.Vector4(0.5, 5, 1.6, 1), _blaze = vm.Vector4(30, 30, 30, 1);

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
  /// photo, pose, cheer, and walk back to their places; the two in the
  /// middle take the board from the drone and hold it.
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
    final holder = n.p.holders.indexOf(who);
    if (holder >= 0) {
      // Holding the board by its side, from the drone's handing it over to
      // its taking it back.
      final k = _boardAt(n, t);
      if (k != null && t >= n.handoff - 0.4 && t < n.pickup + 0.3) {
        f.yaw = 0;
        _grip(f, _side(k, holder == 0 ? -1 : 1, 0.03, _a));
        _cheer(f, t, fl, seed, hands: true);
        return;
      }
    }
    if (who == Crew3D.foreman) {
      // Hands on the board's top edge from behind, steadying it (and up
      // with it in the cheer).
      final k = _boardAt(n, t);
      if (k != null && t >= n.handoff && t < n.pickup) {
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
    // (a V at the chest, hands clasped, a thumbs up, arms folded, hands on
    // hips, a little wave).
    final strike = t < n.away ? eio(seg(t, n.ready + _counts[0] - 0.6, n.ready + _counts[0])) : 0.0;
    if (strike <= 0) {
      if ((t / 3).floor() % 3 == who % 3) OffDuty.talk(f, t, seed);
      return;
    }
    void angles(double p0, double r0, double p1, double r1) {
      f.armPitch[0] = lerp(f.armPitch[0], p0, strike);
      f.armRoll[0] = lerp(f.armRoll[0], r0, strike);
      f.armPitch[1] = lerp(f.armPitch[1], p1, strike);
      f.armRoll[1] = lerp(f.armRoll[1], r1, strike);
    }

    switch ((who + n.p.serial) % 6) {
      case 0:
        f.handTo(1, 0.2, 0.36, -0.24, strike);
      case 1:
        f
          ..handTo(0, -0.035, 0.1, -0.21, strike)
          ..handTo(1, 0.035, 0.1, -0.21, strike);
      case 2:
        angles(-0.3, 0.85, f.armPitch[1], f.armRoll[1]);
        f.handTo(1, 0.2, 0.3, -0.3, strike);
      case 3:
        angles(0.68, -0.55, 0.68, -0.55);
      case 4:
        angles(-0.3, 0.85, -0.3, 0.85);
      default:
        f.handTo(1, 0.28, 0.4 + 0.03 * math.sin(t * 9), -0.24, strike);
    }
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

/// The drone's way from the board's stand to the photo (where the middle
/// of the board's bottom edge is along it): a smooth curve through its
/// waypoints, measured along its length.
class _Flight {
  _Flight(List<vm.Vector3> pts) {
    vm.Vector3 p(int i) => pts[i.clamp(0, pts.length - 1)];
    for (var i = 0; i + 1 < pts.length; i++) {
      final a = p(i - 1), b = p(i), c = p(i + 1), d = p(i + 2);
      for (var k = 0; k < 16; k++) {
        final u = k / 16, u2 = u * u, u3 = u2 * u;
        // (Catmull-Rom.)
        _pts.add(
          (b * 2.0 + (c - a) * u + (a * 2.0 - b * 5.0 + c * 4.0 - d) * u2 + (b * 3.0 - a - c * 3.0 + d) * u3) * 0.5,
        );
      }
    }
    _pts.add(pts.last.clone());
    _len.add(0);
    for (var i = 1; i < _pts.length; i++) {
      _len.add(_len.last + _pts[i].distanceTo(_pts[i - 1]));
    }
  }

  final _pts = <vm.Vector3>[];
  final _len = <double>[];

  double get length => _len.last;

  /// How far along it (0..1) the drone is [u] of the way through its time:
  /// speeding up off the stand, a steady cruise, slowing down to land.
  static double pace(double u) {
    const a = 0.18, d = 0.3, v = 1 / (1 - a / 2 - d / 2);
    final x = u.clamp(0.0, 1.0);
    if (x < a) return v * x * x / (2 * a);
    if (x > 1 - d) return 1 - v * (1 - x) * (1 - x) / (2 * d);
    return v * (a / 2 + x - a);
  }

  /// The point [s] metres along it, into [out].
  vm.Vector3 at(double s, vm.Vector3 out) {
    final x = s.clamp(0.0, length);
    var i = 1;
    while (i < _len.length - 1 && _len[i] < x) {
      i++;
    }
    final f = (x - _len[i - 1]) / math.max(1e-6, _len[i] - _len[i - 1]);
    return out
      ..setFrom(_pts[i - 1])
      ..add((_pts[i] - _pts[i - 1]) * f);
  }
}

/// The finale's plan for one build: when the drone lifts the board, its
/// flight to the photo, who stands where.
class _Plan {
  _Plan(BuildPlan plan, GlyphWorks works, Crew3D crew) : serial = plan.job.serial, w = plan.width {
    // (As the painting finishes: the reveal's last seconds, as long before
    // the celebration as when it was the booth's.)
    final end = plan.t0 + plan.len + CityPace.reveal - phaseSeconds[Phase.reveal]!;
    // (Not before the board's arm is back from setting the last letter,
    // and the drone has come over from its dock.)
    lift = math.max(end - 1.6, works.boardDone! + 1.0 + PhotoOp._fetch);
    // Up off the stand, round to the hall's door and out (over the heads of
    // anyone walking by), up over the side street (clear of its traffic),
    // over the plaza's corner, down in front of the wall from its left.
    const door = WorksLayout.doorZ;
    flight = _Flight([
      vm.Vector3(WorksLayout.boardX, WorksLayout.boardY, WorksLayout.boardZ),
      vm.Vector3(WorksLayout.boardX, 1.35, WorksLayout.boardZ - 0.6),
      vm.Vector3(WorksLayout.x1 - 1.3, 1.9, door),
      vm.Vector3(WorksLayout.x1 + 1.0, 2.3, door),
      vm.Vector3(-24.0, 5.0, door + 0.3),
      vm.Vector3(-19.0, 6.6, door + 0.6),
      vm.Vector3(-12.0, 6.6, PhotoOp._spot.z - 1.2),
      vm.Vector3(PhotoOp._spot.x - 1.6, 2.3, PhotoOp._spot.z - 0.35),
      vm.Vector3(PhotoOp._spot.x, PhotoOp._hold, PhotoOp._spot.z),
    ]);
    arrive = lift + flight.length / PhotoOp._speed;
    // The crew's places in the photo: the two in the middle at the board's
    // sides (holding it), the foreman behind its middle, the other builders
    // either side of them (in the order they stand watching, so their ways
    // don't cross).
    final d = works.boardWidth / 2 + 0.17;
    final order = List.generate(Crew3D.builders, (z) => z)..sort((a, b) => crew.watchSpot(a, w).x.compareTo(crew.watchSpot(b, w).x));
    for (var r = 0; r < Crew3D.builders; r++) {
      final left = r < 3;
      final k = left ? 2 - r : r - 3;
      slots[order[r]] = vm.Vector3((left ? -1 : 1) * (d + 0.52 * k), 0, PhotoOp._spot.z + (k == 0 ? 0 : 0.15 + (k.isOdd ? 0.12 : 0)));
      if (k == 0) holders[left ? 0 : 1] = order[r];
    }
    slots[Crew3D.foreman] = vm.Vector3(0, 0, PhotoOp._spot.z + 0.42);
  }

  final int serial;
  final double w;
  late final double lift, arrive;
  late final _Flight flight;

  /// Who holds the board's left and right sides.
  final holders = [-1, -1];
  final slots = <int, vm.Vector3>{};

  /// When the celebration started, and when the demolition did (once seen).
  double celebrate = double.nan, over = double.nan;

  /// When everyone's in place (the countdown follows): ten seconds into
  /// the celebration [c], or as soon as the board's there and the drone's
  /// had time to go round to take the photo.
  double readyAt(double c) => math.max(c + 10, arrive + 0.9);

  /// When the team goes back to their places and the board home.
  double backAt(double c) => readyAt(c) + PhotoOp._flash + PhotoOp._cheers;
}

/// The finale's times for one celebration (starting at [c]; the team going
/// back at [away]): when everyone's in place, when the drone hands the
/// board over and takes it back, its flight home, everyone's walks there
/// and back. Called off before the photo ([away] early: the demolition came
/// first), the drone turns back with the board from where it is (or comes
/// back for it), and whoever hadn't set out stays put.
class _Now {
  _Now(this.p, this.c, this.away, {required Map<int, vm.Vector3> watch}) : ready = p.readyAt(c), calledOff = away < p.backAt(c) - 1e-6 {
    // (Never: far off, not infinite, so the easing over it stays a number.)
    flash = away > ready + PhotoOp._flash ? ready + PhotoOp._flash : 1e9;
    final len = p.flight.length;
    if (away <= p.arrive) {
      // Turned back on the way there, from where it got to.
      handoff = pickup = 1e9;
      backFrom = away;
      backS = len * _Flight.pace(seg(away, p.lift, p.arrive));
    } else {
      handoff = math.max(p.arrive, ready - 0.4);
      pickup = math.max(away, handoff + 0.3) + PhotoOp._hop;
      backFrom = pickup;
      backS = len;
    }
    home = backFrom + backS / PhotoOp._speed + 0.2;
    // The drone back to its dock: off the board's top once it's home, or
    // (called off before it took the board) from where it had got to.
    if (away < p.lift) {
      hopBack = away;
      hopFrom = seg(away, p.lift - PhotoOp._fetch, p.lift);
    } else {
      hopBack = home;
      hopFrom = 1;
    }
    // The builders and the foreman: over for the photo, and back. The
    // builders by the lane in front of their row and up into their places
    // (the nearest the wall going first, to the farthest place: nobody
    // catches anybody up, nobody crosses the foreman's way behind the
    // line); back the same way, the farthest-right place first.
    final right = [for (final MapEntry(key: who, value: slot) in p.slots.entries) if (who != Crew3D.foreman) (who, slot.x)]..sort((a, b) => b.$2.compareTo(a.$2));
    for (final MapEntry(key: who, value: slot) in p.slots.entries) {
      final from = watch[who]!;
      final foreman = who == Crew3D.foreman;
      final start = c + 4.5 + (foreman ? 1.2 : 0.18 * who);
      final via = foreman ? vm.Vector3(slot.x, 0, -1.75) : vm.Vector3(slot.x, 0, Crew3D.watchLane);
      final pts = [from, if (!foreman) vm.Vector3(from.x, 0, Crew3D.watchLane), via, slot];
      final go = Walk(pts, start, (Walk.lengthOf(pts) / math.max(1.0, ready - 0.6 - start)).clamp(1.3, 2.6));
      if (away <= go.start) continue;
      final face = who == Crew3D.foreman ? 0.9 : 0.5;
      final Walk back;
      // (Once the drone has the board again, the holders keeping it till
      // then: all together, as they came, so nobody catches anybody up.)
      final leave = pickup < 1e8 ? pickup + 0.3 : away;
      if (leave < go.end) {
        final backPts = go.backFrom(leave);
        back = Walk(backPts, leave, math.max(1.4, Walk.lengthOf(backPts) / 3.6), face: face);
      } else {
        final backPts = [slot, via, if (!foreman) vm.Vector3(from.x, 0, Crew3D.watchLane), from];
        final rank = foreman ? 6 : right.indexWhere((e) => e.$1 == who);
        back = Walk(backPts, leave + 0.1 + 0.18 * rank, foreman ? math.max(1.4, Walk.lengthOf(backPts) / 3.6) : 2.2, face: face);
      }
      crew[who] = (go: go, back: back);
    }
    done = [away, home, hopBack + hopFrom * PhotoOp._fetch, for (final w in crew.values) w.back.end].reduce(math.max);
  }

  final _Plan p;
  final double c, away, ready;

  /// The finale was called off before the photo was done.
  final bool calledOff;

  /// The flash (never, if called off before it: 1e9).
  late final double flash;

  /// When the drone hands the board to the holders and takes it back (1e9:
  /// never, turned back on the way there); when, and from how far along its
  /// way, it flies it home; when it's back on its stand; when the drone
  /// sets off back to its dock, and from how far along its hop (1: the
  /// board's top); when it's all over.
  late final double handoff, pickup, backFrom, backS, home, hopBack, hopFrom, done;

  /// How far the drone is along its hop from its dock (0) onto the board's
  /// top (1) at [t], while it comes over or goes back; null while it's off
  /// with the board.
  double? hopAt(double t) {
    if (t >= hopBack) return hopFrom * (1 - seg(t, hopBack, hopBack + hopFrom * PhotoOp._fetch));
    if (t < p.lift) return seg(t, p.lift - PhotoOp._fetch, p.lift);
    return null;
  }

  /// How far along the flight the board is at [t] (null: it's not flying,
  /// it's with the holders).
  double? flownAt(double t) {
    if (t < p.lift || t >= home) return null;
    if (t < math.min(handoff, backFrom)) return p.flight.length * _Flight.pace(seg(t, p.lift, p.arrive));
    if (t < backFrom) return null;
    return backS * (1 - _Flight.pace(seg(t, backFrom, home - 0.2)));
  }

  final crew = <int, ({Walk go, Walk back})>{};
}
