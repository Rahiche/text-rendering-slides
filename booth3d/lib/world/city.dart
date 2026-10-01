import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/craft/extrude.dart';
import 'package:text_slides/booth/craft/plan.dart' show vectorizeText;
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';

/// The city around the plaza: streets, sidewalks, lamps, and "glyph
/// towers" — buildings that are giant extruded characters from many scripts,
/// their windows lighting up at night.
class City3D {
  City3D(this.scene);

  final Scene scene;

  /// Characters the towers are made of (one per tower).
  static const towerGlyphs = [
    '日', 'A', '字', 'あ', 'Ж', 'ب', 'क', 'ก', '한', 'ש', 'Ω', '文', 'ア', 'g', '語', '&', '本', 'R', '凸', 'ي',
  ];

  final _towerMats = <PhysicallyBasedMaterial>[];
  final _lampMats = <PhysicallyBasedMaterial>[];
  late final Texture2D _windows;

  Future<void> init() async {
    _ground();
    _windows = _windowTexture();
    _lamps();
    await _towers();
  }

  void _ground() {
    void slab(double x0, double z0, double x1, double z1, double y, vm.Vector4 c, {double rough = 0.9}) {
      scene.add(
        Node(
          mesh: Mesh(CuboidGeometry(vm.Vector3(x1 - x0, 0.2, z1 - z0)), pbr(c, roughness: rough)),
          localTransform: trs(vm.Vector3((x0 + x1) / 2, y - 0.1, (z0 + z1) / 2)),
        ),
      );
    }

    // Ground and asphalt.
    slab(-160, -160, 160, 160, -0.02, rgb(0.035, 0.05, 0.08));
    slab(-120, -19, 120, -11, 0.0, rgb(0.05, 0.06, 0.08), rough: 0.7); // front avenue
    slab(-26, -120, -19, 120, 0.0, rgb(0.05, 0.06, 0.08), rough: 0.7); // side street
    slab(19, -120, 26, 120, 0.0, rgb(0.05, 0.06, 0.08), rough: 0.7);
    // Plaza (the build site) and sidewalks.
    slab(-19, -11, 19, 8, 0.04, lin(const Color(0xFF223042)), rough: 0.85);
    slab(-19, -23, 19, -19, 0.04, lin(const Color(0xFF1C2838)));
    // Lane markings.
    final marks = InstancedMesh(geometry: CuboidGeometry(vm.Vector3(2.2, 0.02, 0.18)), material: pbr(rgb(0.8, 0.75, 0.55), emissive: rgb(0.4, 0.36, 0.2), emissiveStrength: 0.3));
    for (var x = -118.0; x < 118; x += 5) {
      marks.addInstance(trs(vm.Vector3(x, 0.03, -15)));
    }
    scene.add(Node(name: 'lane marks')..addComponent(InstancedMeshComponent(marks)));
    // Safety barriers round the plaza edge (amber and dark stripes).
    final barrier = InstancedMesh(geometry: CuboidGeometry(vm.Vector3(1.8, 0.5, 0.15)), material: pbr(lin(BP.amber), roughness: 0.6));
    for (var x = -18.0; x <= 18; x += 2.4) {
      barrier.addInstance(trs(vm.Vector3(x, 0.3, -10.4)), color: (x / 2.4).round().isEven ? rgb(1, 1, 1) : rgb(0.12, 0.12, 0.14));
    }
    scene.add(Node(name: 'barriers')..addComponent(InstancedMeshComponent(barrier)));
  }

  void _lamps() {
    final pole = InstancedMesh(geometry: CylinderGeometry(bottomRadius: 0.08, topRadius: 0.06, height: 5), material: pbr(rgb(0.1, 0.12, 0.16), metallic: 0.6, roughness: 0.4));
    final bulbMat = pbr(rgb(1, 0.9, 0.7), emissive: rgb(1, 0.82, 0.5), emissiveStrength: 0);
    _lampMats.add(bulbMat);
    final bulb = InstancedMesh(geometry: SphereGeometry(radius: 0.32, segments: 12, rings: 8), material: bulbMat);
    // Along the far side of the avenue, and the plaza's flanks — never
    // between the camera and the wall.
    for (var x = -96.0; x <= 96; x += 12) {
      for (final z in [-19.6, -10.6]) {
        if (z > -15 && x.abs() < 24) continue;
        pole.addInstance(trs(vm.Vector3(x, 2.5, z)));
        bulb.addInstance(trs(vm.Vector3(x, 5.1, z)));
      }
    }
    for (final x in [-20.5, 20.5]) {
      for (var z = -6.0; z <= 6; z += 6) {
        pole.addInstance(trs(vm.Vector3(x, 2.5, z)));
        bulb.addInstance(trs(vm.Vector3(x, 5.1, z)));
      }
    }
    scene.add(Node(name: 'lamp poles')..addComponent(InstancedMeshComponent(pole)));
    scene.add(Node(name: 'lamp bulbs')..addComponent(InstancedMeshComponent(bulb)));
  }

  /// A tile of windows: dark frame, panes lit warm or cool (alpha unused).
  Texture2D _windowTexture() {
    const n = 64, cells = 8;
    final px = Uint8List(n * n * 4);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final cx = x ~/ (n / cells), cy = y ~/ (n / cells);
        final ix = x % (n ~/ cells), iy = y % (n ~/ cells);
        final pane = ix >= 2 && ix <= 5 && iy >= 2 && iy <= 6;
        final lit = rnd(cx, cy, 17) > 0.42;
        final warm = rnd(cx, cy, 29) > 0.35;
        final i = (y * n + x) * 4;
        final v = pane && lit ? 1.0 : 0.0;
        px[i] = (255 * v * (warm ? 1.0 : 0.6)).round();
        px[i + 1] = (255 * v * (warm ? 0.82 : 0.85)).round();
        px[i + 2] = (255 * v * (warm ? 0.5 : 1.0)).round();
        px[i + 3] = 255;
      }
    }
    return Texture2D.fromPixels(px, n, n);
  }

  Future<void> _towers() async {
    final glyphs = await vectorizeText(towerGlyphs.join());
    const tints = [BP.line, BP.violet, BP.green, BP.coral, BP.inkDim, BP.pink, BP.amber];
    for (var i = 0; i < glyphs.length; i++) {
      final g = glyphs[i].$2;
      if (g.isEmpty) continue;
      // Ring the plaza behind and to the sides, never in front of it.
      final a = -math.pi * 0.95 + (i / glyphs.length) * math.pi * 0.9 * 2 / 1.0;
      final ring = 75 + 55 * rnd(i, 1);
      // Behind the plaza (+Z) and to the sides; never between it and the camera.
      var x = math.cos(a) * ring, z = 14 - math.sin(a) * ring * 0.8;
      if (z < 40 && x.abs() < 50) z = 40 + 30 * rnd(i, 2);
      final height = 10 + 16 * rnd(i, 3);
      final mesh = extrudeGlyph(g, unitsPerPx: height / g.inkHeight, depth: 3 + 4 * rnd(i, 4), simplify: 0.8);
      final tint = lin(tints[i % tints.length]);
      final base = rgb(0.03, 0.05, 0.09) + (tint - rgb(0.03, 0.05, 0.09)) * 0.35;
      final mat = pbr(vm.Vector4(base.x, base.y, base.z, 1), roughness: 0.55, metallic: 0.15)
        ..emissiveTexture = _windows
        ..emissiveTextureTransform = TextureTransform(scale: vm.Vector2(3 + mesh.width / 3, 3 + height / 3))
        ..emissiveFactor = rgb(1, 1, 1)
        ..emissiveStrength = 0;
      _towerMats.add(mat);
      // Its readable side (−Z) towards the plaza.
      final face = math.atan2(x, z);
      scene.add(Node(name: 'tower ${glyphs[i].$1}', mesh: Mesh(glyphGeometry(mesh), mat), localTransform: trs(vm.Vector3(x, 0, z), rotY: face)));
    }
  }

  /// [night] 0 (day) … 1 (night): windows and street lamps light up.
  void update(double night, double t) {
    for (var i = 0; i < _towerMats.length; i++) {
      _towerMats[i].emissiveStrength = 2.2 * night * (0.85 + 0.15 * math.sin(t * 0.3 + i));
    }
    for (final m in _lampMats) {
      m.emissiveStrength = 6 * night;
    }
  }
}
