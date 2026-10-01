import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/model.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';

/// The cinematographer: a slow orbit that changes shot with the build —
/// wide while a name comes in, close on the wall while bricks drop, a push
/// in for the reveal, a low hero angle for the fireworks, the side for the
/// wrecking ball, and wide again while the rubble goes.
class Director {
  double angle = 0.4, radius = 34, height = 13;
  vm.Vector3 target = vm.Vector3(0, 3, 0);

  PerspectiveCamera camera = PerspectiveCamera(position: vm.Vector3(0, 12, 34), target: vm.Vector3(0, 3, 0));

  void update(BoothModel m, double dt, {required double wallWidth, required double wallHeight}) {
    final j = m.job;
    final t = m.t;
    final drift = 0.18 * math.sin(t * 0.05);
    var a = 0.35 + drift, r = 34.0, h = 13.0, settle = 3.0;
    var tgt = vm.Vector3(0, 3, 0);
    final w = wallWidth, wh = wallHeight;
    switch (j?.phase) {
      case null || Phase.intake:
        a = 0.6 * math.sin(t * 0.04) + 0.2;
        r = 36;
        h = 14;
      case Phase.build:
        final p = j!.progress(t);
        a = 0.55 * math.sin(t * 0.06) + drift;
        r = 7 + w * 0.8;
        h = 3.5 + wh * (0.6 + 0.3 * p);
        tgt = vm.Vector3(0, wh * (0.35 + 0.4 * p), 0);
      case Phase.reveal:
        a = 0.12 + 0.1 * math.sin(t * 0.3);
        r = 5 + w * 0.72;
        h = 2.2 + wh * 0.45;
        tgt = vm.Vector3(0, wh * 0.5, 0);
        settle = 2.2;
      case Phase.celebrate:
        final u = j!.progress(t);
        a = lerp(0.6, -0.6, u);
        r = 6 + w * 0.8;
        h = 1.6 + wh * 0.25;
        tgt = vm.Vector3(0, wh * 0.75 + 1.5, 0);
        settle = 2.0;
      case Phase.demolish:
        a = -0.95;
        r = 10 + w * 0.7;
        h = 4 + wh * 0.4;
        tgt = vm.Vector3(-w * 0.15, wh * 0.35, 0);
        settle = 1.6;
      case Phase.cleanup:
        a = -0.4 + 0.4 * j!.progress(t);
        r = 30;
        h = 12;
        tgt = vm.Vector3(-w * 0.25, 1.5, -2);
    }
    angle = approach(angle, a, dt, settle);
    radius = approach(radius, r, dt, settle);
    height = approach(height, h, dt, settle);
    target = vm.Vector3(
      approach(target.x, tgt.x, dt, settle),
      approach(target.y, tgt.y, dt, settle),
      approach(target.z, tgt.z, dt, settle),
    );
    // In front of the wall = the −Z side (text reads left to right looking +Z).
    final pos = target + vm.Vector3(math.sin(angle) * radius, height, -math.cos(angle) * radius);
    camera = PerspectiveCamera(position: pos, target: target, fovRadiansY: 40 * math.pi / 180, fovFar: 900);
  }
}
