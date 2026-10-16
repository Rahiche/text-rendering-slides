import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show FontWeight, FontVariation, Locale;

import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'city_plan.dart';
import 'kit.dart';

/// The skyline: "glyph towers" — buildings that are giant extruded
/// characters from many scripts, in glass and stone — with plain blocks
/// along the side streets (some carrying rooftop signs). All of it stands
/// behind and beside the plaza, never between it and the camera.
///
/// The facades are photographed walls with windows drawn into them
/// (tool/textures/facades.py: curtain-wall glass, dark panels, pale
/// cladding, old stone, concrete tile), laid at a real bay and storey. It is
/// all static, so it is merged: a draw a facade style for the whole skyline.
class CityTowers {
  CityTowers(this.scene);

  final Scene scene;

  /// Flat roofs facing the plaza, for rooftop signs: centre, roof height,
  /// facing (rotY), usable width.
  final roofs = <({vm.Vector3 at, double rotY, double width})>[];

  /// What a camera mustn't go into or look through: each building's box
  /// (centre, half extents; a glyph tower's, round its letter).
  final solids = <(vm.Vector3, vm.Vector3)>[];

  /// Where the Unicode tower (v_tower.dart) stands and the camera that
  /// visits it comes from: no glyph tower in the way.
  static final _towerView = (vm.Vector3(33, 0, 92), vm.Vector3(18.5, 0, 69));

  final _batch = Batch();
  final _styles = <PhysicallyBasedMaterial>[];
  late final _roofMat = pbr(rgb(1, 1, 1), roughness: 0.85);

  /// Window cell size in metres (a bay × a storey); a facade texture holds
  /// [_cells]×[_cells] of them.
  static const _cellW = 1.7, _cellH = 2.6, _cells = 8;

  /// The facade styles (assets/textures/facade_*).
  static const _styleNames = ['facade_glass', 'facade_panel', 'facade_clad', 'facade_stone', 'facade_tile'];

  // Facades: a style and a tint over it (sRGB; white: as photographed).
  static const _facades = [
    (0, 0xFFFFFF), // glass, neutral
    (1, 0xFFFFFF), // dark panels
    (2, 0xF2F0EC), // pale cladding
    (3, 0xFFFFFF), // old stone
    (4, 0xFFFFFF), // concrete tile
    (0, 0xD6E6E2), // glass, green-tinted
  ];

  Future<void> init() async {
    _styles.addAll(await Future.wait([for (final n in _styleNames) photoPbr(n)]));
    _blocks();
    await _glyphTowers();
    _batch.build(scene, 'skyline', lightChannelMask: 0x01);
  }

  PhysicallyBasedMaterial _facadeMat(int kind) => _styles[_facades[kind % _facades.length].$1];

  vm.Vector4 _facadeColor(int kind) => v4(hex3(_facades[kind % _facades.length].$2));

  // ── Blocks along the side streets ─────────────────────────────────────────

  void _blocks() {
    // Along each side street, a row of blocks facing it (and so the plaza),
    // a taller row behind, and a row along the avenue beyond the corner.
    var seed = 0;
    for (final side in [-1.0, 1.0]) {
      final faceRot = side > 0 ? math.pi / 2 : -math.pi / 2; // face (−Z) towards the street
      var front = 0;
      var z = -8.5;
      while (z < 66) {
        seed++;
        final len = 9 + 6 * rnd(seed, 1);
        final h = 7 + 9 * rnd(seed, 2) + (z > 30 ? 4 : 0);
        final d = 9 + 4 * rnd(seed, 3);
        final x = side * (Plan.walkBlock + 1.2 + d / 2);
        // (A lot of the mini world's: no block.)
        if (!Plan.inLot(x, z + len / 2)) {
          _box(vm.Vector3(x, 0, z + len / 2), len, h, d, rotY: faceRot, seed: seed, kind: _blockKinds[seed % _blockKinds.length]);
          // Signs on every other front roof (the taller row behind carries
          // the rest, so from the plaza they stack at different heights).
          if ((front++).isEven) roofs.add((at: vm.Vector3(x, h + 0.5, z + len / 2), rotY: math.atan2(x, z + len / 2), width: math.min(len, d) * 0.92));
        }
        z += len + 1.2 + 2 * rnd(seed, 4);
      }
      z = 6.0;
      while (z < 72) {
        seed++;
        final len = 10 + 8 * rnd(seed, 1);
        final h = 15 + 12 * rnd(seed, 2);
        final d = 10 + 4 * rnd(seed, 3);
        final x = side * (Plan.walkBlock + 17 + d / 2 + 2 * rnd(seed, 5));
        _box(vm.Vector3(x, 0, z + len / 2), len, h, d, rotY: faceRot, seed: seed, kind: _blockKinds[(seed + 1) % _blockKinds.length]);
        roofs.add((at: vm.Vector3(x, h + 0.5, z + len / 2), rotY: math.atan2(x, z + len / 2), width: math.min(len, d) * 0.92));
        z += len + 2 + 3 * rnd(seed, 4);
      }
      var x = 46.0;
      while (x < 118) {
        seed++;
        final len = 10 + 6 * rnd(seed, 1);
        final h = 6 + 9 * rnd(seed, 2);
        const d = 10.0;
        _box(vm.Vector3(side * (x + len / 2), 0, Plan.aveZ1 + 3.2 + d / 2), len, h, d, rotY: 0, seed: seed, kind: _blockKinds[(seed + 2) % _blockKinds.length]);
        x += len + 1.5;
      }
    }
  }

  static const _blockKinds = [3, 4, 0, 5, 3, 1, 4, 2];

  /// A block of [len] (along its face) × [h] × [d], its face (local −Z)
  /// turned by [rotY]; windows in world scale, a plain roof with a parapet.
  void _box(vm.Vector3 at, double len, double h, double d, {required double rotY, required int seed, required int kind}) {
    final xf = trs(at, rotY: rotY);
    final across = rotY == 0 ? len : d, along = rotY == 0 ? d : len;
    solids.add((vm.Vector3(at.x, h / 2 + 0.5, at.z), vm.Vector3(across / 2, h / 2 + 0.5, along / 2)));
    final ou = (rnd(seed, 1) * _cells).floorToDouble() / _cells, ov = (rnd(seed, 2) * _cells).floorToDouble() / _cells;
    _batch.add(_facadeMat(kind), painted(_boxData(len, h, d, ou, ov).transformed(xf), _facadeColor(kind)));
    _batch.add(_roofMat, part(CuboidGeometry(vm.Vector3(len * 0.98, 0.5, d * 0.98)), trs(at + vm.Vector3(0, h + 0.25, 0), rotY: rotY), v4(hex3(0x8C8B87))));
    // A little machinery on some roofs.
    if (rnd(seed, 6) < 0.6) {
      final mx = (rnd(seed, 7) - 0.5) * len * 0.5, mz = (rnd(seed, 8) - 0.5) * d * 0.4;
      final m = trs(at + vm.Vector3(0, h + 0.5, 0), rotY: rotY) * vm.Matrix4.translation(vm.Vector3(mx, 0.7, mz + d * 0.15));
      _batch.add(_roofMat, part(CuboidGeometry(vm.Vector3(2.2, 1.4, 1.8)), m, v4(hex3(0xA3A5A6))));
    }
  }

  /// A box whose UVs count window cells (so every block shares one texture
  /// scale); the roof maps to a frame-coloured corner.
  MeshData _boxData(double w, double h, double d, double ou, double ov) {
    final pos = <double>[], nor = <double>[], uv = <double>[];
    final idx = <int>[];
    void quad(vm.Vector3 o, vm.Vector3 u, vm.Vector3 v, vm.Vector3 n, double uw, double vh, {bool roof = false}) {
      final base = pos.length ~/ 3;
      for (final (a, b) in [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]) {
        final p = o + u * (a * uw) + v * (b * vh);
        pos.addAll([p.x, p.y, p.z]);
        nor.addAll([n.x, n.y, n.z]);
        if (roof) {
          uv.addAll([0.004, 0.004]);
        } else {
          uv.addAll([ou + a * uw / (_cellW * _cells), ov + (1 - b) * vh / (_cellH * _cells)]);
        }
      }
      // Counter-clockwise seen from n.
      if (u.cross(v).dot(n) > 0) {
        idx.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
      } else {
        idx.addAll([base, base + 2, base + 1, base, base + 3, base + 2]);
      }
    }

    final x0 = -w / 2, z0 = -d / 2;
    final ux = vm.Vector3(1, 0, 0), uy = vm.Vector3(0, 1, 0), uz = vm.Vector3(0, 0, 1);
    quad(vm.Vector3(x0, 0, z0), ux, uy, vm.Vector3(0, 0, -1), w, h); // front (−Z)
    quad(vm.Vector3(-x0, 0, -z0), -ux, uy, vm.Vector3(0, 0, 1), w, h); // back
    quad(vm.Vector3(x0, 0, -z0), -uz, uy, vm.Vector3(-1, 0, 0), d, h); // left
    quad(vm.Vector3(-x0, 0, z0), uz, uy, vm.Vector3(1, 0, 0), d, h); // right
    quad(vm.Vector3(x0, h, z0), ux, uz, vm.Vector3(0, 1, 0), w, d, roof: true); // roof
    return MeshData(
      positions: Float32List.fromList(pos),
      vertexCount: pos.length ~/ 3,
      normals: Float32List.fromList(nor),
      texCoords: Float32List.fromList(uv),
      indices: idx,
    );
  }

  // ── Glyph towers ──────────────────────────────────────────────────────────

  /// Characters the towers are made of, from many scripts.
  static const _mid = [
    'あ', 'A', '字', 'Ж', 'ب', 'क', 'ก', '한', 'ש', 'Ω', 'ア', 'g', '&', 'R', 'ñ', 'λ', '語', 'ß', 'ع', '¶',
  ];
  static const _tall = ['日', '目', 'H', '月', '高', 'Ⅲ', '自', 'ا', '門', '8', '#', 'l', 'ह', '凸', '本', 'Я'];

  Future<void> _glyphTowers() async {
    final specs = <({String ch, vm.Vector3 at, double h, double depth, int k})>[];
    var seed = 100;
    // The middle ring: a crescent behind and beside the park.
    const midN = 18;
    for (var i = 0; i < midN; i++) {
      seed++;
      final th = (-1.62 + 3.24 * (i + 0.5) / midN) + (rnd(seed, 1) - 0.5) * 0.12;
      final dist = 88 + 34 * rnd(seed, 2);
      final at = vm.Vector3(math.sin(th) * dist, 0, math.cos(th) * dist + 12);
      if (at.z < 4 || _inTowerView(at)) continue;
      specs.add((ch: _mid[i % _mid.length], at: at, h: 15 + 12 * rnd(seed, 3), depth: 5 + 4 * rnd(seed, 4), k: seed));
    }
    // The far ring: tall towers, the skyline proper.
    const farN = 16;
    for (var i = 0; i < farN; i++) {
      seed++;
      final th = (-1.25 + 2.5 * (i + 0.5) / farN) + (rnd(seed, 1) - 0.5) * 0.1;
      final dist = 165 + 70 * rnd(seed, 2);
      final at = vm.Vector3(math.sin(th) * dist, 0, math.cos(th) * dist + 20);
      specs.add((ch: _tall[i % _tall.length], at: at, h: 30 + 26 * rnd(seed, 3), depth: 7 + 6 * rnd(seed, 4), k: seed));
    }
    final meshes = await extrudeTexts([
      for (final s in specs) TextSolid(s.ch, _towerStyle(s.ch), height: s.h, depth: s.depth, simplify: 0.9),
    ]);
    for (var i = 0; i < specs.length; i++) {
      final s = specs[i];
      final m = meshes[i];
      if (m.vertexCount == 0) continue;
      final kind = s.k % _facades.length;
      // Faces: windows at world scale, over the letter's ink box. Sides:
      // windows too, along the depth and up the height (a side that's
      // nearly level, the top or the underside of a stroke, takes the
      // facade's plain corner).
      final su = m.width / (_cellW * _cells), sv = m.height / (_cellH * _cells);
      final ou = (rnd(s.k, 1) * _cells).floorToDouble() / _cells, ov = (rnd(s.k, 2) * _cells).floorToDouble() / _cells;
      var top = -double.infinity, back = double.infinity;
      for (var v = 0; v < m.vertexCount; v++) {
        top = math.max(top, m.positions[v * 3 + 1]);
        back = math.min(back, m.positions[v * 3 + 2]);
      }
      final uv = Float32List.fromList(m.uvs);
      final faces = <int>[], sides = <int>[];
      for (var t = 0; t + 2 < m.indices.length; t += 3) {
        final v = m.indices[t];
        (m.normals[v * 3 + 2].abs() > 0.5 ? faces : sides).addAll([m.indices[t], m.indices[t + 1], m.indices[t + 2]]);
      }
      for (var v = 0; v < m.vertexCount; v++) {
        if (m.normals[v * 3 + 2].abs() > 0.5) {
          uv[v * 2] = ou + m.uvs[v * 2] * su;
          uv[v * 2 + 1] = ov + m.uvs[v * 2 + 1] * sv;
        } else if (m.normals[v * 3 + 1].abs() > 0.75) {
          uv[v * 2] = 0.004;
          uv[v * 2 + 1] = 0.004;
        } else {
          uv[v * 2] = ou + (m.positions[v * 3 + 2] - back) / (_cellW * _cells);
          uv[v * 2 + 1] = ov + (top - m.positions[v * 3 + 1]) / (_cellH * _cells);
        }
      }
      final yaw = math.atan2(s.at.x, s.at.z), xf = trs(s.at, rotY: yaw);
      final c = math.cos(yaw).abs(), n = math.sin(yaw).abs(), hw = m.width / 2 + 1.5, hd = s.depth / 2 + 1.5;
      solids.add((vm.Vector3(s.at.x, m.height / 2, s.at.z), vm.Vector3(c * hw + n * hd, m.height / 2 + 0.6, n * hw + c * hd)));
      _batch.add(_facadeMat(kind), painted(glyphData(m, [...faces, ...sides], uv).transformed(xf), _facadeColor(kind)));
      // A plinth so the letter stands on something.
      _batch.add(_roofMat, part(CuboidGeometry(vm.Vector3(m.width + 3, 1.2, s.depth + 3)), xf * vm.Matrix4.translation(vm.Vector3(0, 0.6, 0)), v4(hex3(0x6A6B6C))));
    }
  }

  /// Whether a glyph tower at [at] would stand in the Unicode tower's
  /// camera's way (within 13 m of its line of sight, or of the tower).
  static bool _inTowerView(vm.Vector3 at) {
    final (a, b) = _towerView;
    final dx = b.x - a.x, dz = b.z - a.z, l2 = dx * dx + dz * dz;
    final f = c01(((at.x - a.x) * dx + (at.z - a.z) * dz) / l2);
    final px = a.x + dx * f - at.x, pz = a.z + dz * f - at.z;
    return px * px + pz * pz < 13.0 * 13.0;
  }

  TextStyle _towerStyle(String ch) {
    final cjk = ch.codeUnitAt(0) >= 0x3000;
    return TextStyle(
      fontFamily: BP.display,
      fontFamilyFallback: const [BP.arabic],
      fontSize: 150,
      height: 1.2,
      locale: cjk ? const Locale('ja') : null,
      fontWeight: FontWeight.w700,
      fontVariations: const [FontVariation('wght', 700)],
    );
  }

  /// (Always day: nothing on the skyline lights up.)
  void update(double night, double t) {}
}
