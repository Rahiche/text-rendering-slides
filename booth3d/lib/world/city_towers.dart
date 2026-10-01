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
/// characters from many scripts, in glass and stone, their windows lighting
/// up at night and their outlines traced in neon — with plain blocks along
/// the side streets (some carrying rooftop signs). All of it stands behind
/// and beside the plaza, never between it and the camera.
///
/// It is all static, so it is merged: facades share a few materials (their
/// colours are vertex colours), outlines take their neon colour from a
/// swatch texture — a few draws for the whole skyline.
class CityTowers {
  CityTowers(this.scene);

  final Scene scene;

  /// Flat roofs facing the plaza, for rooftop signs: centre, roof height,
  /// facing (rotY), usable width.
  final roofs = <({vm.Vector3 at, double rotY, double width})>[];

  final _batch = Batch();
  late final Texture2D _paneBase, _paneGlow, _paneMR, _edges;

  /// Light groups: buildings come on through dusk in three waves.
  static const _waves = [0.12, 0.3, 0.5];
  final _glass = <PhysicallyBasedMaterial>[], _stone = <PhysicallyBasedMaterial>[], _sides = <PhysicallyBasedMaterial>[];
  late final _roofMat = pbr(rgb(1, 1, 1), roughness: 0.85);

  /// Window cell size in metres (a bay × a storey); the window texture holds
  /// [_cells]×[_cells] of them.
  static const _cellW = 1.7, _cellH = 2.6, _cells = 16;

  // Facades: colour and whether it is glass (metallic panes).
  static const _facades = [
    (0x23456E, true), // navy glass
    (0x2D5C80, true), // teal glass
    (0x3A4C6E, true), // slate glass
    (0xAFBDCC, false), // pale concrete
    (0xC9B9A2, false), // sand stone
    (0x8FA3BA, false), // blue-grey
  ];
  static const _neon = [BP.amber, BP.coral, BP.green, BP.violet, BP.pink, BP.line];

  Future<void> init() async {
    _paneBase = _windowTexture(_PaneLayer.base);
    _paneGlow = _windowTexture(_PaneLayer.glow);
    _paneMR = _windowTexture(_PaneLayer.mr);
    _edges = swatchTexture([for (final c in _neon) lin3(c), vm.Vector3.zero()], rows: 64, profile: (v) => v < 0.07 || v > 0.93 ? 1 : 0);
    for (var w = 0; w < _waves.length; w++) {
      _glass.add(_facade(0.85));
      _stone.add(_facade(0.28));
      _sides.add(
        PhysicallyBasedMaterial()
          ..metallicFactor = 0.2
          ..roughnessFactor = 0.55
          ..emissiveTexture = _edges
          ..emissiveFactor = vm.Vector4(1, 1, 1, 1)
          ..emissiveStrength = 0,
      );
    }
    _blocks();
    await _glyphTowers();
    _batch.build(scene, 'skyline', lightChannelMask: 0x01);
  }

  // ── Textures ──────────────────────────────────────────────────────────────

  static const _px = 16;

  /// 16×16 window cells: frame and pane (base colour), lit panes (glow),
  /// glossy metallic panes on rough frames (metallic-roughness).
  Texture2D _windowTexture(_PaneLayer layer) {
    const n = _cells * _px;
    final px = Uint8List(n * n * 4);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final cx = x ~/ _px, cy = y ~/ _px;
        final ix = x % _px, iy = y % _px;
        final pane = ix >= 2 && ix <= 13 && iy >= 3 && iy <= 13;
        final mullion = pane && (ix == 7 || ix == 8);
        final glass = pane && !mullion;
        // Floors light up together-ish: a per-floor mood and a per-window coin.
        final floor = rnd(cy, 3, 11);
        final lit = rnd(cx, cy, 17) < 0.18 + 0.42 * floor;
        final warm = rnd(cx, cy, 29);
        final curtain = rnd(cx, cy, 41);
        final i = (y * n + x) * 4;
        int r, g, b;
        switch (layer) {
          case _PaneLayer.base:
            final v = glass ? (40 + 50 * curtain).round() : 225;
            r = g = b = v;
          case _PaneLayer.glow:
            if (!glass || !lit) {
              r = g = b = 0;
            } else if (warm < 0.62) {
              (r, g, b) = (255, 196, 120); // warm lamps
            } else if (warm < 0.86) {
              (r, g, b) = (200, 226, 255); // cool office light
            } else if (warm < 0.94) {
              (r, g, b) = (255, 150, 200); // a pink room
            } else {
              (r, g, b) = (140, 255, 210); // a mint screen glow
            }
            final dim = 0.55 + 0.45 * rnd(cx, cy, 53);
            r = (r * dim).round();
            g = (g * dim).round();
            b = (b * dim).round();
          case _PaneLayer.mr:
            r = 255;
            g = glass ? 34 : 210; // roughness
            b = glass ? 230 : 10; // metallic
        }
        px
          ..[i] = r
          ..[i + 1] = g
          ..[i + 2] = b
          ..[i + 3] = 255;
      }
    }
    return Texture2D.fromPixels(px, n, n, content: layer == _PaneLayer.mr ? TextureContent.data : TextureContent.color);
  }

  PhysicallyBasedMaterial _facade(double gloss) => PhysicallyBasedMaterial()
    ..baseColorTexture = _paneBase
    ..metallicRoughnessTexture = _paneMR
    ..metallicFactor = gloss
    ..roughnessFactor = 1
    ..emissiveTexture = _paneGlow
    ..emissiveFactor = vm.Vector4(1, 1, 1, 1)
    ..emissiveStrength = 0;

  PhysicallyBasedMaterial _facadeMat(int kind, int seed) {
    final wave = seed % _waves.length;
    return _facades[kind % _facades.length].$2 ? _glass[wave] : _stone[wave];
  }

  vm.Vector4 _facadeColor(int kind) => v4(hex3(_facades[kind % _facades.length].$1));

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
        _box(vm.Vector3(x, 0, z + len / 2), len, h, d, rotY: faceRot, seed: seed, kind: _blockKinds[seed % _blockKinds.length]);
        // Signs on every other front roof (the taller row behind carries the
        // rest, so from the plaza they stack at different heights).
        if ((front++).isEven) roofs.add((at: vm.Vector3(x, h + 0.5, z + len / 2), rotY: math.atan2(x, z + len / 2), width: math.min(len, d) * 0.92));
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
    final ou = (rnd(seed, 1) * _cells).floorToDouble() / _cells, ov = (rnd(seed, 2) * _cells).floorToDouble() / _cells;
    _batch.add(_facadeMat(kind, seed), painted(_boxData(len, h, d, ou, ov).transformed(xf), _facadeColor(kind)));
    _batch.add(_roofMat, part(CuboidGeometry(vm.Vector3(len * 0.98, 0.5, d * 0.98)), trs(at + vm.Vector3(0, h + 0.25, 0), rotY: rotY), v4(hex3(0x3B4A60))));
    // A little machinery on some roofs.
    if (rnd(seed, 6) < 0.6) {
      final mx = (rnd(seed, 7) - 0.5) * len * 0.5, mz = (rnd(seed, 8) - 0.5) * d * 0.4;
      final m = trs(at + vm.Vector3(0, h + 0.5, 0), rotY: rotY) * vm.Matrix4.translation(vm.Vector3(mx, 0.7, mz + d * 0.15));
      _batch.add(_roofMat, part(CuboidGeometry(vm.Vector3(2.2, 1.4, 1.8)), m, v4(hex3(0x56657C))));
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
      if (at.z < 4) continue;
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
      final neon = s.k % _neon.length;
      final outlined = rnd(s.k, 7) < 0.7;
      // Faces: windows at world scale; sides: the neon swatch, banded across
      // the depth (the outline at both edges).
      final su = m.width / (_cellW * _cells), sv = m.height / (_cellH * _cells);
      final ou = (rnd(s.k, 1) * _cells).floorToDouble() / _cells, ov = (rnd(s.k, 2) * _cells).floorToDouble() / _cells;
      final uv = Float32List.fromList(m.uvs);
      final faces = <int>[], sides = <int>[];
      for (var t = 0; t + 2 < m.indices.length; t += 3) {
        final v = m.indices[t];
        (m.normals[v * 3 + 2].abs() > 0.5 ? faces : sides).addAll([m.indices[t], m.indices[t + 1], m.indices[t + 2]]);
      }
      final swatch = swatchU(outlined ? neon : _neon.length, _neon.length + 1);
      for (var v = 0; v < m.vertexCount; v++) {
        if (m.normals[v * 3 + 2].abs() > 0.5) {
          uv[v * 2] = ou + m.uvs[v * 2] * su;
          uv[v * 2 + 1] = ov + m.uvs[v * 2 + 1] * sv;
        } else {
          uv[v * 2] = swatch;
        }
      }
      final xf = trs(s.at, rotY: math.atan2(s.at.x, s.at.z));
      final wave = s.k % _waves.length;
      _batch.add(_facadeMat(kind, s.k), painted(glyphData(m, faces, uv).transformed(xf), _facadeColor(kind)));
      _batch.add(_sides[wave], painted(glyphData(m, sides, uv).transformed(xf), v4(mix3(hex3(_facades[kind].$1), lin3(_neon[neon]), 0.55))));
      // A plinth so the letter stands on something.
      _batch.add(_roofMat, part(CuboidGeometry(vm.Vector3(m.width + 3, 1.2, s.depth + 3)), xf * vm.Matrix4.translation(vm.Vector3(0, 0.6, 0)), v4(hex3(0x243650))));
    }
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

  // ── Night ────────────────────────────────────────────────────────────────

  /// Windows come on in waves through dusk; outlines glow and hum.
  void update(double night, double t) {
    for (var w = 0; w < _waves.length; w++) {
      final at = _waves[w];
      final on = smooth(at, at + 0.25, night);
      _glass[w].emissiveStrength = 1.15 * on;
      _stone[w].emissiveStrength = 1.15 * on;
      final buzz = 0.9 + 0.1 * math.sin(t * 1.3 + w * 2.1);
      _sides[w].emissiveStrength = 5.5 * smooth(at + 0.1, at + 0.3, night) * buzz;
    }
  }
}

enum _PaneLayer { base, glow, mr }
