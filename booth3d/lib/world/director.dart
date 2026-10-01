import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/model.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';
import 'site.dart';
import 'shot.dart';
import 'site_plan.dart';

/// The cinematographer. Every phase has its shots — a wide establishing
/// shot of the city while a name comes in, a rotation of framings while the
/// wall goes up (the whole name, the builders up close, the crane's view,
/// the site from afar, a low hero angle), straight on for the reveal, low
/// and looking up for the fireworks, a dramatic low three-quarter for the
/// wrecking ball (with a shake when it hits), and following the truck.
///
/// The camera glides between framings on critically damped springs, drifts
/// a little like it's hand-held, and is kept out of the wall, the crane and
/// the ground. The name stays readable while it's built and celebrated.
class Director {
  PerspectiveCamera camera = PerspectiveCamera(position: vm.Vector3(0, 12, -34), target: vm.Vector3(0, 3, 0));

  final _eye = _Spring3(vm.Vector3(18, 22, -40));
  final _target = _Spring3(vm.Vector3(0, 3, 0));
  final _fov = _Spring(42);
  Job? _job;
  int _jobs = 0;
  String? _focus;
  bool _focusWasCut = false;

  /// How much the camera should care about the typed letters (0..1).
  double typingWeight = 0;

  /// 0 by day … 1 at night (fireworks get the wide sky shot at night).
  double night = 0;

  void update(BoothModel m, double dt, Site3D site) {
    final j = m.job;
    final t = m.t;
    var shot = _keepInFront(_shot(j, t, site));
    // Something worth following (kerning close up, a break, the driver).
    Focus? f;
    for (final r in site.focus) {
      if (f == null || r.priority > f.priority) f = r;
    }
    var cutTo = false;
    if (f != null && f.cut) {
      shot = _keepInFront(f.shot);
      cutTo = f.id != _focus;
    } else if (f != null) {
      shot = _blend(shot, _keepInFront(f.shot), eio(f.weight.clamp(0.0, 1.0)));
    }
    // Back from a cut-to request: cut back too.
    final cutBack = f?.id != _focus && _focusWasCut;
    _focus = f?.id;
    _focusWasCut = f?.cut ?? false;
    // Someone is typing: make sure their letters (dropping in at the front
    // of the plaza, just above the input on screen) are in the picture.
    if (typingWeight > 0.001 && j != null) shot = _blend(shot, _keepInFront(_typingShot(j, t, site)), eio(typingWeight));
    var cut = cutTo || cutBack;
    if (!identical(j, _job)) {
      _job = j;
      _jobs++;
      // A new name: cut to the establishing shot rather than glide there.
      cut = _jobs > 1 && j != null;
    }
    final settle = shot.settle;
    if (cut) {
      _eye.snap(shot.eye);
      _target.snap(shot.target);
      _fov.snap(shot.fov);
    } else {
      _eye.step(shot.eye, settle, dt);
      _target.step(shot.target, settle * 0.8, dt);
      _fov.step(shot.fov, settle, dt);
    }
    // Hand-held: a slow, irregular drift of the eye and the aim.
    final d = 0.07 * shot.drift;
    final eye = _eye.value.clone()
      ..x += d * (math.sin(t * 0.31) + 0.6 * math.sin(t * 0.77 + 1.3))
      ..y += d * 0.7 * (math.sin(t * 0.43 + 0.5) + 0.5 * math.sin(t * 1.13))
      ..z += d * 0.8 * math.sin(t * 0.37 + 2.1);
    final target = _target.value.clone()
      ..x += d * 0.5 * math.sin(t * 0.53 + 0.7)
      ..y += d * 0.4 * math.sin(t * 0.61 + 1.9);
    // The wrecking ball's hit shakes the camera.
    final hit = site.impactAt;
    if (hit != null && t >= hit && t < hit + 1.6) {
      final k = math.pow(1 - (t - hit) / 1.6, 2).toDouble() * 0.28;
      eye
        ..x += k * math.sin(t * 61)
        ..y += k * math.sin(t * 47 + 1);
      target
        ..x += k * 0.6 * math.sin(t * 53 + 2)
        ..y += k * 0.6 * math.sin(t * 59);
    }
    _avoid(eye, site);
    camera = PerspectiveCamera(position: eye, target: target, fovRadiansY: _fov.value * math.pi / 180, fovNear: 0.2, fovFar: 900);
  }

  /// Keeps the camera above ground, out of the wall and its platform, the
  /// crane's mast and the brick yard.
  void _avoid(vm.Vector3 eye, Site3D site) {
    eye.y = math.max(eye.y, 0.9);
    final w = site.wallWidth, h = site.wallHeight;
    if (eye.x.abs() < w / 2 + 1.6 && eye.z > -1.6 && eye.z < SiteLayout.deckZ1 + 0.8 && eye.y < h + 2.5) {
      eye.z = -1.6;
    }
    final dx = eye.x - SiteLayout.mastX, dz = eye.z - SiteLayout.mastZ;
    final r = math.sqrt(dx * dx + dz * dz);
    if (r < 2.6 && eye.y < SiteLayout.jibY + 3) {
      final f = 2.6 / math.max(r, 1e-3);
      eye
        ..x = SiteLayout.mastX + dx * f
        ..z = SiteLayout.mastZ + dz * f;
    }
    if (eye.x > 10.5 && eye.x < 17.5 && eye.z > -2.6 && eye.z < 3 && eye.y < 3.2) eye.y = 3.2;
  }

  /// How far back to stand to frame [w] × [h] (with room for the board
  /// and the input band over the picture).
  static double fit(double w, double h, double fovDeg) {
    final tv = math.tan(fovDeg * math.pi / 360);
    final th = tv * 16 / 9;
    return math.max(w / (2 * 0.8 * th), h / (2 * 0.44 * tv));
  }

  /// The avenue's street lamps stand at z ≈ −19.6: a low camera further
  /// back than that would have a lamp in its face. Such a shot comes in
  /// closer along its line of sight and widens its lens to keep the framing.
  static Shot _keepInFront(Shot s) {
    const limit = -18.6;
    final e = s.eye, tg = s.target;
    if (e.z >= limit || e.y > 11 || e.x.abs() > 30 || tg.z <= limit) return s;
    final k = (tg.z - limit) / (tg.z - e.z); // new distance / old
    final eye = tg + (e - tg) * k;
    final fov = 2 * math.atan(math.tan(s.fov * math.pi / 360) / k) * 180 / math.pi;
    return Shot(eye, tg, fov: math.min(fov, 62), settle: s.settle, drift: s.drift);
  }

  /// A camera at azimuth [a] (0 = straight in front, + to the right),
  /// distance [r], looking at [target] from [up] above it.
  static vm.Vector3 orbit(vm.Vector3 target, double a, double r, double up) =>
      vm.Vector3(target.x + math.sin(a) * r, target.y + up, target.z - math.cos(a) * r);

  Shot _shot(Job? j, double t, Site3D site) {
    final w = site.wallWidth, h = site.wallHeight;
    if (j == null) return _establish(t, 0, 0);
    final since = j.since(t);
    final u = j.progress(t);
    switch (j.phase) {
      case Phase.intake:
        return _establish(t, since, j.serial);
      case Phase.build:
        return _building(j, t, since, u, site);
      case Phase.reveal:
        // Straight on, a slow push in; the scan plane rises through it.
        final tg = vm.Vector3(0, h * 0.5, 0);
        final r = fit(w, h, 38) * lerp(1.02, 0.94, eio(u));
        return Shot(orbit(tg, 0.05 * math.sin(t * 0.2), r, 3.0 + h * 0.3), tg, fov: 38, settle: 1.6, drift: 0.6);
      case Phase.celebrate:
        if (since < 7.5 || night < 0.5) {
          // Low, looking up at the name, the 完成！ sign and the fireworks;
          // by day (when fireworks are faint) a second, closer pass.
          final second = since >= 7.5;
          final f = second ? eio((since - 7.5) / 6.5) : eio(since / 7.5);
          final tg = vm.Vector3(0, (h + 3) * (second ? 0.4 : 0.44), 0);
          final r = math.max(fit(w, h, 42) * (second ? 0.95 : 1.02), (h + 3.4) * 1.18 / (2 * math.tan(21 * math.pi / 180)));
          final a = second ? lerp(0.24, -0.1, f) : lerp(-0.2, 0.18, f);
          return Shot(orbit(tg, a, r, second ? 4.2 : 3.2), tg, fov: 42, settle: 2.0);
        }
        // Wider, at night: fireworks over the city.
        final tg = vm.Vector3(1.0, h * 0.6 + 2.4, 1.5);
        final r = fit(w, h, 46) * 1.32;
        return Shot(orbit(tg, lerp(0.22, 0.36, seg(since, 7.5, 14)), r, 2.4), tg, fov: 46, settle: 2.6, drift: 1.4);
      case Phase.demolish:
        // Low and to the left: the ball comes swinging from the right, the
        // bricks fly towards us.
        final release = j.phaseLen * 0.26;
        final fr = fit(w, h, 46);
        if (since < release - 0.2) {
          // The ball comes down on the right: frame it with the wall.
          final ball = site.ballAt;
          final tg = vm.Vector3(lerp(w * 0.1, ball.x, 0.4), lerp(h * 0.5, math.min(ball.y, h + 6), 0.42), 0);
          return Shot(orbit(tg, -0.5, fr * 0.9, 3.2 - tg.y + 1.0), tg, fov: 48, settle: 1.6, drift: 0.8);
        }
        // Low three-quarters: the ball swings towards us, bricks fly past.
        final tg = vm.Vector3(w * 0.02, h * 0.42, 0);
        return Shot(orbit(tg, -0.6 - 0.1 * seg(since, release, j.phaseLen), fr * lerp(0.74, 0.86, seg(since, release, j.phaseLen)), 2.6 - tg.y + 0.6), tg, fov: 50, settle: 1.3, drift: 1.2);
      case Phase.cleanup:
        // Follow the truck as it loads and drives off, then settle on the
        // empty, swept plaza with the crane (lit at night).
        final truck = site.truckAt;
        final tx = truck.x.clamp(-w / 2 - 12, w / 2 + 2);
        final end = seg(u, 0.8, 1);
        final tg = vm.Vector3(lerp(tx * 0.6 - 1.5, 3, end), lerp(1.4, 2.5, end), lerp(-2.5, 0.5, end));
        final eye = vm.Vector3(tg.x - lerp(5, 2, end), lerp(6.5, 9.5, end), lerp(-17, -24, end));
        return Shot(eye, tg, fov: 44, settle: 2.4);
    }
  }

  /// Straight on, a little higher and further back, so the waiting row of
  /// typed letters sits in the bottom of the frame under the wall.
  Shot _typingShot(Job j, double t, Site3D site) {
    final w = site.wallWidth, h = site.wallHeight;
    final top = j.phase == Phase.celebrate ? h + 3 : h;
    final tg = vm.Vector3(-0.8, top * 0.32 + 0.3, -1.4);
    final r = fit(w, top, 40) * 1.05;
    return Shot(orbit(tg, 0.06 * math.sin(t * 0.07), r, 4.4 + top * 0.22), tg, fov: 40, settle: 1.8, drift: 0.7);
  }

  static Shot _blend(Shot a, Shot b, double f) => Shot(
    a.eye + (b.eye - a.eye) * f,
    a.target + (b.target - a.target) * f,
    fov: lerp(a.fov, b.fov, f),
    settle: lerp(a.settle, b.settle, f),
    drift: lerp(a.drift, b.drift, f),
  );

  /// The establishing shot while a name comes in: high over the city,
  /// coming down towards the plaza as the bricks pop into the yard.
  Shot _establish(double t, double since, int serial) {
    final f = eio(seg(since, 0, 9));
    if (serial.isEven) {
      // From high on the right, circling down over the yard and the crane.
      final tg = vm.Vector3(lerp(6, 3, f), lerp(3, 2.5, f), lerp(0, 0.5, f));
      return Shot(orbit(tg, lerp(1.05, 0.45, f), lerp(46, 28, f), lerp(24, 10, f)), tg, fov: 42, settle: 2.0, drift: 1.2);
    }
    // From the avenue, low, looking up at the crane and the glyph towers,
    // then rising over the plaza.
    final tg = vm.Vector3(lerp(5, 2, f), lerp(8, 3, f), lerp(6, 0, f));
    return Shot(orbit(tg, lerp(-0.35, 0.15, f), lerp(34, 27, f), lerp(-2.5, 8, f)), tg, fov: 46, settle: 2.0, drift: 1.2);
  }

  /// While the wall goes up: a rotation of framings, each held ~13 s with a
  /// slow move.
  Shot _building(Job j, double t, double since, double u, Site3D site) {
    final w = site.wallWidth, h = site.wallHeight;
    final level = math.max(site.level, 0.6);
    final n = (since / 13).floor();
    final k = since / 13 - n;
    final order = [0, 1, 2, 0, 3, 4, 1, 0, 2, 3];
    final kind = order[(n + j.serial) % order.length];
    final fitR = fit(w, h, 40);
    switch (kind) {
      case 1:
        // The builders up close, three-quarters, on the letter going up.
        final side = (n + j.serial).isEven ? -1.0 : 1.0;
        final x = site.activeX + side * lerp(0.9, 0.3, k);
        final tg = vm.Vector3(x, level * 0.7 + 0.4, 0.4);
        return Shot(orbit(tg, side * 0.32, fitR * 0.72, 2.8), tg, fov: 40, settle: 2.6);
      case 2:
        // From the crane's side, high, looking down over the platform.
        final tg = vm.Vector3(w * 0.05, level * 0.75, 0.5);
        return Shot(orbit(tg, lerp(0.5, 0.38, k), fitR * 0.92, 6.5 + level * 0.4), tg, fov: 42, settle: 2.8);
      case 3:
        // The whole site from afar: the yard, the crane, the city.
        final tg = vm.Vector3(3.0, 3.0, 1.0);
        return Shot(orbit(tg, lerp(0.36, 0.26, k), fitR * 1.3, 7.5), tg, fov: 42, settle: 3.0, drift: 1.3);
      case 4:
        // Three-quarters from the left, along the wall towards the crane.
        final tg = vm.Vector3(w * 0.05, level * 0.55 + 0.6, 0.3);
        return Shot(orbit(tg, lerp(-0.42, -0.32, k), fitR * 0.98, 4.2 + level * 0.3), tg, fov: 42, settle: 2.6);
      default:
        // The whole name, straight on, drifting from side to side.
        final tg = vm.Vector3(0, math.max(level * 0.55, h * 0.4), 0);
        return Shot(orbit(tg, 0.16 * math.sin(t * 0.05 + j.serial), fitR * 1.02, 4.6 + h * 0.2), tg, fov: 40, settle: 2.6);
    }
  }
}

/// A critically damped spring towards a moving goal.
class _Spring {
  _Spring(this.value);
  double value, _v = 0;

  void snap(double to) {
    value = to;
    _v = 0;
  }

  void step(double goal, double settle, double dt) {
    final w = 4.0 / math.max(settle, 0.05);
    var left = math.min(dt, 0.5);
    while (left > 1e-6) {
      final h = math.min(left, 1 / 60);
      left -= h;
      final a = w * w * (goal - value) - 2 * w * _v;
      _v += a * h;
      value += _v * h;
    }
  }
}

class _Spring3 {
  _Spring3(vm.Vector3 v) : _x = _Spring(v.x), _y = _Spring(v.y), _z = _Spring(v.z);
  final _Spring _x, _y, _z;

  vm.Vector3 get value => vm.Vector3(_x.value, _y.value, _z.value);

  void snap(vm.Vector3 v) {
    _x.snap(v.x);
    _y.snap(v.y);
    _z.snap(v.z);
  }

  void step(vm.Vector3 goal, double settle, double dt) {
    _x.step(goal.x, settle, dt);
    _y.step(goal.y, settle, dt);
    _z.step(goal.z, settle, dt);
  }
}
