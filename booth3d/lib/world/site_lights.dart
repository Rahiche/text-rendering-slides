import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../tuning.dart';
import 'kit.dart';
import 'site_geo.dart';

/// The site after dark: two floodlight towers that switch on at dusk and
/// light the wall, and coloured flashes from the fireworks.
class SiteLights {
  SiteLights(this.scene);

  final Scene scene;

  final _towers = <(Node, SpotLight, PhysicallyBasedMaterial)>[];
  final _flashNodes = <Node>[];
  final _flashLights = <PointLight>[];

  static final _towerAt = [vm.Vector3(-17.2, 0, -8.6), vm.Vector3(17.6, 0, -8.2)];

  void init() {
    final steel = pbr(rgb(0.18, 0.2, 0.24), roughness: 0.5, metallic: 0.6);
    for (final at in _towerAt) {
      final tower = Node(name: 'floodlight tower', localTransform: trs(at));
      final mast = MeshBatch();
      latticeMast(mast, w: 0.5, y0: 0, y1: 8.2, section: 0.9, post: 0.07, brace: 0.035);
      mast
        ..box(vm.Vector3(0, 0.15, 0), vm.Vector3(1.1, 0.3, 1.1))
        ..box(vm.Vector3(0, 8.3, 0), vm.Vector3(1.6, 0.12, 0.5));
      tower.add(Node(mesh: Mesh(mast.build(), steel))..shadowStatic = Tuning.staticShadows);
      // Lamp heads, tilted down towards the wall.
      final lens = pbr(rgb(1, 0.95, 0.85), emissive: rgb(1, 0.92, 0.75), emissiveStrength: 0);
      final heads = MeshBatch();
      final lenses = MeshBatch();
      for (final dx in [-0.5, 0.0, 0.5]) {
        heads.box(vm.Vector3(dx, 8.75, 0), vm.Vector3(0.42, 0.42, 0.3));
        lenses.box(vm.Vector3(dx, 8.75, 0.16), vm.Vector3(0.34, 0.34, 0.04));
      }
      final aim = math.atan2(-at.x, -at.z); // towards the wall's centre
      final head = Node(localTransform: trs(vm.Vector3(0, 0, 0), rotY: aim));
      head
        ..add(Node(mesh: Mesh(heads.build(), steel)))
        ..add(Node(mesh: Mesh(lenses.build(), lens))..castsShadows = false);
      tower.add(head);
      // The light itself: aimed at the middle of the wall.
      final dir = vm.Vector3(0, 2.6, 0) - (at + vm.Vector3(0, 8.75, 0));
      final spot = SpotLight(
        color: vm.Vector3(1.0, 0.9, 0.75),
        intensity: 0,
        range: 70,
        direction: dir,
        innerConeAngle: 0.28,
        outerConeAngle: 0.62,
      );
      // The actual light on the wall comes from the city's plaza floods
      // (local to the plaza, one shadow map); these towers are the fixtures,
      // their lenses glowing. A second pair of unmasked spots lit the whole
      // city every frame and cost ~15 fps.
      final lamp = Node(name: 'floodlight', localTransform: trs(vm.Vector3(0, 8.75, 0)));
      tower.add(lamp);
      scene.add(tower);
      _towers.add((lamp, spot, lens));
    }
    for (var i = 0; i < 2; i++) {
      final light = PointLight(intensity: 0, range: 40);
      final node = Node(name: 'firework flash $i')..addComponent(PointLightComponent(light));
      node.visible = false;
      _flashLights.add(light);
      _flashNodes.add(node);
      scene.add(node);
    }
  }

  /// [night] 0 (day) … 1 (night); [flashes] are the fireworks' bursts this
  /// frame (position, colour and strength), brightest first.
  void update(double night, double t, List<(vm.Vector3, vm.Vector4, double)> flashes) {
    final on = c01((night - 0.15) / 0.4);
    for (final (lamp, spot, lens) in _towers) {
      lamp.visible = on > 0;
      // A slight warm-up flicker as they come on.
      final warm = on < 1 ? on * (0.85 + 0.15 * math.sin(t * 23)) : 1.0;
      spot.intensity = 420 * warm;
      lens.emissiveStrength = 9 * warm;
    }
    for (var i = 0; i < _flashNodes.length; i++) {
      final node = _flashNodes[i];
      if (i >= flashes.length || night < 0.2) {
        node.visible = false;
        continue;
      }
      final (p, c, s) = flashes[i];
      node
        ..visible = true
        ..place((m) => setTrs(m, p.x, p.y, p.z));
      _flashLights[i]
        ..color = vm.Vector3(c.x, c.y, c.z)
        ..intensity = 260 * s * night;
    }
  }
}
