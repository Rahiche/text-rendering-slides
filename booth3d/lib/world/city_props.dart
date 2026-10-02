import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_scene/scene.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'city_plan.dart';
import 'kit.dart';

/// Street furniture: the park's trees (mint greens and sakura), benches,
/// traffic cones round the site, glowing vending machines and a red post
/// box. Everything repeated is one instanced draw.
class CityProps {
  CityProps(this.scene);

  final Scene scene;
  late final UnlitMaterial _vendGlow, _fairyGlow;
  final _fairyNode = Node(name: 'fairy lights');
  final _canopies = <(vm.Vector3, double)>[];

  Future<void> init() async {
    _trees();
    _fairyLights();
    _benches();
    _cones();
    _vending();
    _postBox();
  }

  /// [d] with every triangle given its own vertices, so normals come out
  /// flat (a faceted, low-poly look).
  static MeshGeometry _faceted(MeshData d) {
    final idx = d.indices ?? [for (var i = 0; i < d.vertexCount; i++) i];
    final p = Float32List(idx.length * 3);
    for (var i = 0; i < idx.length; i++) {
      p
        ..[i * 3] = d.positions[idx[i] * 3]
        ..[i * 3 + 1] = d.positions[idx[i] * 3 + 1]
        ..[i * 3 + 2] = d.positions[idx[i] * 3 + 2];
    }
    return MeshGeometry.fromMeshData(MeshData.build(positions: p));
  }

  void _trees() {
    final trunks = InstancedMesh(
      geometry: CylinderGeometry(bottomRadius: 0.17, topRadius: 0.11, height: 2.4, radialSegments: 8),
      material: pbr(lin(const Color(0xFF5A4636)), roughness: 0.9),
    );
    final leaves = InstancedMesh(
      geometry: _faceted(IcosphereGeometry(radius: 1, subdivisions: 1).extractMeshData()),
      material: pbr(rgb(1, 1, 1), roughness: 0.85),
    );
    const greens = [0x22705A, 0x2B8166, 0x338D6E, 0x1F6450, 0x3B9878];
    const sakura = [0xF29AC4, 0xF7B0D2, 0xE889B6];
    var k = 0;
    void tree(double x, double z, {double size = 1, bool? pink}) {
      // (None on the mini world's lots.)
      if (Plan.inLot(x, z, 1.5)) return;
      k++;
      final s = size * (0.85 + 0.35 * rnd(k, 1));
      final isPink = pink ?? rnd(k, 2) < 0.28;
      final c = isPink ? sakura[k % sakura.length] : greens[k % greens.length];
      trunks.addInstance(trs(vm.Vector3(x, 1.2 * s, z), s: vm.Vector3.all(s)));
      final r = 1.5 * s;
      final crown = vm.Vector3(x, 2.4 * s + r * 0.55, z);
      leaves.addInstance(trs(crown, rotY: rnd(k, 3) * 6, s: vm.Vector3.all(r)), color: v4(hex3(c)));
      if (isPink && z < Plan.parkZ0 + 34 && x.abs() < Plan.plazaX + 1) _canopies.add((crown, r));
      leaves.addInstance(
        trs(vm.Vector3(x + (rnd(k, 4) - 0.5) * r, 2.4 * s + r * 1.15, z + (rnd(k, 5) - 0.5) * r), rotY: rnd(k, 6) * 6, s: vm.Vector3.all(r * 0.68)),
        color: v4(hex3(c, 1.12)),
      );
    }

    // The park: loose rows, kept low and open right behind the wall (the
    // name reads against a calm ground), sakura at its edges.
    for (var z = Plan.parkZ0 + 3.5; z < Plan.parkZ1 - 2; z += 5.4) {
      for (var x = -Plan.plazaX + 2.2; x < Plan.plazaX - 1.5; x += 5.0) {
        final jx = x + (rnd(x.round(), z.round(), 7) - 0.5) * 2.0;
        final jz = z + (rnd(x.round(), z.round(), 8) - 0.5) * 2.0;
        if (jx.abs() < 3.6) continue; // the central path
        if ((jz - (Plan.parkZ0 + 15.5)).abs() < 2.6) continue; // the cross path
        final near = jz < Plan.parkZ0 + 12;
        // An open lawn behind the wall, trees along its sides: the name
        // reads against calm ground and the skyline.
        if (jx.abs() < (jz < Plan.parkZ0 + 44 ? 10.5 : 6)) continue;
        tree(jx, jz, size: near ? 0.8 : 1.05, pink: near ? true : (jx.abs() > 12 ? rnd(k, 9) < 0.45 : null));
      }
    }
    // Beyond the park, more trees to the skyline's feet.
    for (var i = 0; i < 40; i++) {
      final x = (rnd(i, 21) - 0.5) * 60;
      final z = Plan.parkZ1 + 4 + rnd(i, 22) * 30;
      tree(x, z, size: 1.2 + 0.4 * rnd(i, 23));
    }
    // Street trees along the outer blocks.
    for (final s in [-1.0, 1.0]) {
      for (var z = 2.5; z < 88; z += 13) {
        tree(s * (Plan.walkBlock - 0.5), z, size: 0.8, pink: false);
      }
    }
    for (final (name, m) in [('trunks', trunks), ('leaves', leaves)]) {
      scene.add(
        Node(name: name)
          ..lightChannelMask = 0x01
          ..addComponent(InstancedMeshComponent(m)),
      );
    }
  }

  /// Strings of tiny lights in the park's sakura (イルミネーション), lit after
  /// dusk.
  void _fairyLights() {
    _fairyGlow = UnlitMaterial()..baseColorFactor = vm.Vector4(0, 0, 0, 1);
    final bulbs = InstancedMesh(geometry: IcosphereGeometry(radius: 0.07, subdivisions: 0), material: _fairyGlow);
    const tints = [0xFFE2B0, 0xFFF4E0, 0xFFC8E6, 0xBFE4FF];
    var k = 0;
    for (final (c, r) in _canopies) {
      for (var i = 0; i < 26; i++) {
        k++;
        // Over the crown's outer shell, more on the sides than the top.
        final a = rnd(k, 1) * math.pi * 2, e = (rnd(k, 2) - 0.35) * 1.3;
        final d = vm.Vector3(math.cos(a) * math.cos(e), math.sin(e) * 0.62, math.sin(a) * math.cos(e));
        bulbs.addInstance(trs(c + d * (r * 1.02)), color: v4(hex3(tints[k % tints.length])));
      }
    }
    scene.add(
      _fairyNode
        ..castsShadows = false
        ..visible = false
        ..addComponent(InstancedMeshComponent(bulbs)),
    );
  }

  void _benches() {
    final wood = v4(hex3(0xB97A4A));
    final iron = v4(hex3(0x1F2A3C));
    final geo = merged([
      part(CuboidGeometry(vm.Vector3(1.7, 0.07, 0.46)), vm.Matrix4.translation(vm.Vector3(0, 0.46, 0)), wood),
      part(CuboidGeometry(vm.Vector3(1.7, 0.36, 0.06)), vm.Matrix4.translation(vm.Vector3(0, 0.74, 0.22)), wood),
      for (final x in [-0.72, 0.72]) part(CuboidGeometry(vm.Vector3(0.07, 0.46, 0.44)), vm.Matrix4.translation(vm.Vector3(x, 0.23, 0.02)), iron),
    ]);
    final benches = InstancedMesh(geometry: geo, material: pbr(rgb(1, 1, 1), roughness: 0.7));
    // Facing the paths in the park (front = local −Z); none in front of
    // the tofu shop and the forge (vignettes).
    for (var z = Plan.parkZ0 + 5.0; z < Plan.parkZ1; z += 9) {
      if ((z - 49).abs() > 1) benches.addInstance(trs(vm.Vector3(-3.4, 0, z), rotY: -math.pi / 2));
      if ((z + 4 - 44).abs() > 1) benches.addInstance(trs(vm.Vector3(3.4, 0, z + 4), rotY: math.pi / 2));
    }
    // On the plaza's flanks, facing the build.
    for (final s in [-1.0, 1.0]) {
      for (final z in [0.0, 6.6]) {
        benches.addInstance(trs(vm.Vector3(s * (Plan.lampFlank - 0.05), 0, z), rotY: s * math.pi / 2));
      }
    }
    scene.add(
      Node(name: 'benches')
        ..lightChannelMask = 0x01
        ..addComponent(InstancedMeshComponent(benches)),
    );
  }

  void _cones() {
    final red = v4(lin3(BP.red));
    final white = v4(hex3(0xF4F1EA));
    final base = v4(hex3(0x1B2233));
    final geo = merged([
      part(CuboidGeometry(vm.Vector3(0.46, 0.05, 0.46)), vm.Matrix4.translation(vm.Vector3(0, 0.025, 0)), base),
      part(CylinderGeometry(bottomRadius: 0.19, topRadius: 0.035, height: 0.72, radialSegments: 14), vm.Matrix4.translation(vm.Vector3(0, 0.41, 0)), red),
      part(CylinderGeometry(bottomRadius: 0.152, topRadius: 0.132, height: 0.09, radialSegments: 14), vm.Matrix4.translation(vm.Vector3(0, 0.36, 0)), white),
      part(CylinderGeometry(bottomRadius: 0.105, topRadius: 0.086, height: 0.08, radialSegments: 14), vm.Matrix4.translation(vm.Vector3(0, 0.55, 0)), white),
    ]);
    final cones = InstancedMesh(geometry: geo, material: pbr(rgb(1, 1, 1), roughness: 0.55));
    final spots = <(double, double)>[
      for (final s in [-1.0, 1.0]) ...[
        (s * 16.2, Plan.plazaZ0 + 0.7),
        (s * 15.2, Plan.plazaZ0 + 0.9),
        // (On the right, the vending machines stand there: by the yard.)
        s < 0 ? (s * 16.3, Plan.plazaZ0 + 1.9) : (16.45, -2.75),
        // (On the left, the Glyph Works stands in the back corner.)
        if (s > 0) ...[(s * 16.1, Plan.plazaZ1 - 0.8), (s * 15.0, Plan.plazaZ1 - 0.7)],
      ],
      (-12.5, Plan.plazaZ0 + 0.55),
      (-15.1, Plan.plazaZ0 + 0.5),
    ];
    for (final (x, z) in spots) {
      cones.addInstance(trs(vm.Vector3(x, 0.02, z), rotY: rnd(x.round(), z.round()) * 3));
    }
    scene.add(Node(name: 'cones')..addComponent(InstancedMeshComponent(cones)));
  }

  void _vending() {
    final geo = merged([
      part(CuboidGeometry(vm.Vector3(1.0, 1.85, 0.75)), vm.Matrix4.translation(vm.Vector3(0, 0.925, 0)), vm.Vector4(1, 1, 1, 1)),
      part(CuboidGeometry(vm.Vector3(0.9, 0.12, 0.04)), vm.Matrix4.translation(vm.Vector3(0, 0.35, -0.39)), v4(hex3(0x1B2233))),
    ]);
    final bodies = InstancedMesh(geometry: geo, material: pbr(rgb(1, 1, 1), roughness: 0.45, metallic: 0.1));
    _vendGlow = UnlitMaterial()..baseColorFactor = vm.Vector4(0.8, 0.85, 0.9, 1);
    final fronts = InstancedMesh(geometry: CuboidGeometry(vm.Vector3(0.82, 1.05, 0.03)), material: _vendGlow);
    const colors = [0xF4F1EA, 0xE8505F, 0x2E6DA8, 0xF4F1EA, 0x3AA37E];
    var k = 0;
    void machine(double x, double z, double rotY) {
      k++;
      bodies.addInstance(trs(vm.Vector3(x, 0.02, z), rotY: rotY), color: v4(hex3(colors[k % colors.length])));
      final f = trs(vm.Vector3(x, 0.02, z), rotY: rotY) * vm.Matrix4.translation(vm.Vector3(0, 1.2, -0.385));
      fronts.addInstance(f, color: v4(hex3(k.isEven ? 0xD8ECFF : 0xFFF1D6)));
    }

    // Facing the avenue at the outer blocks' corners.
    for (final s in [-1.0, 1.0]) {
      for (var i = 0; i < 3; i++) {
        machine(s * (31.0 + i * 1.08), Plan.aveZ1 + 2.6, 0);
      }
    }
    for (final (name, m) in [('vending machines', bodies), ('vending fronts', fronts)]) {
      scene.add(
        Node(name: name)
          ..lightChannelMask = 0x01
          ..addComponent(InstancedMeshComponent(m)),
      );
    }
  }

  void _postBox() {
    final red = v4(hex3(0xE8414F));
    final geo = merged([
      part(CylinderGeometry(bottomRadius: 0.26, topRadius: 0.26, height: 1.05, radialSegments: 18), vm.Matrix4.translation(vm.Vector3(0, 0.55, 0)), red),
      part(CylinderGeometry(bottomRadius: 0.3, topRadius: 0.24, height: 0.12, radialSegments: 18), vm.Matrix4.translation(vm.Vector3(0, 1.12, 0)), red),
      part(CuboidGeometry(vm.Vector3(0.3, 0.05, 0.04)), vm.Matrix4.translation(vm.Vector3(0, 0.85, -0.26)), v4(hex3(0x1B2233))),
    ]);
    scene.add(Node(name: 'post box', mesh: Mesh(geo, pbr(rgb(1, 1, 1), roughness: 0.4)), localTransform: trs(vm.Vector3(-17.6, 0.02, Plan.walkFront))));
  }

  void update(double night, double t) {
    final k = 0.75 + 2.4 * smooth(0.1, 0.5, night);
    _vendGlow.baseColorFactor = vm.Vector4(k, k, k, 1);
    final f = 5.0 * smooth(0.35, 0.7, night) * (0.85 + 0.15 * math.sin(t * 2.3));
    _fairyGlow.baseColorFactor = vm.Vector4(f, f, f, 1);
    _fairyNode.visible = f > 0.01;
  }
}
