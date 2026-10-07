import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/craft/extrude.dart' show GlyphMesh;
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';
import 'shot.dart';
import 'vignette.dart';

/// 混在 · One mixed paragraph, hung in the air over the city while a talk
/// calls on it: nine runs in eight scripts, each in its own colour, laid
/// out by the real text stack over two lines (the two right-to-left words
/// in the order the bidi algorithm puts them, not the order they were
/// typed). They come in one by one; the cuts between runs are drawn
/// (itemize: a run a script, a direction, a font), then each run's
/// direction over it.
class TalkMix extends Vignette {
  TalkMix(super.kit);

  @override
  String get name => 'mix';
  @override
  String get kick => '混在 · MIXING';
  @override
  String get line => _runs.map((r) => r.$1).join(' ');
  @override
  String get note => 'nine runs, two directions, eight scripts';

  @override
  bool get talkOnly => true;

  @override
  double get loop => 20;
  @override
  double get visit => 16;

  /// Set in the world itself (placed for its camera).
  @override
  final frame = vm.Matrix4.identity();

  /// The runs: text, right to left, colour.
  static const _runs = [
    ('Hello', false, 0x2F6BFF),
    ('مرحبا', true, 0x10B981),
    ('שלום', true, 0x8B5CF6),
    ('नमस्ते', false, 0xF59E0B),
    ('สวัสดี', false, 0x06B6D4),
    ('こんにちは', false, 0xEC4899),
    ('世界', false, 0xEF4444),
    ('👋🏽🌍', false, 0xFFFFFF),
    ('world', false, 0xF97316),
  ];
  static const _emoji = 7;

  /// The camera, and where the paragraph hangs in its frame: across and up
  /// (of the half frame), how far (m), how wide (of the frame's width).
  static final _shot = Shot(vm.Vector3(0, 30, -30), vm.Vector3(0, 18, 40), fov: 60, settle: 1.0, drift: 0.6);
  static const _across = 0.3, _up = 0.02, _far = 20.0, _wide = 0.52;

  static const _px = 120.0, _depth = 0.16;

  static TextStyle _style() => const TextStyle(
    fontFamily: BP.display,
    fontFamilyFallback: [BP.arabic],
    fontSize: _px,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
  );

  /// The paragraph's middle and facing, its scale (m a pixel).
  late vm.Vector3 _at;
  late final vm.Matrix4 _facing;
  double _upp = 0.01;

  /// Each run: its node (and, for the emoji, its picture's size), where its
  /// ink's middle sits (paragraph px, y down), its box (px), its line's
  /// baseline.
  final _nodes = <Node>[];
  final _mids = <Offset>[];
  final _boxes = <Rect>[];
  final _heights = <double>[];

  /// Each run's line: its number, top and bottom (px).
  final _lines = <(int, double, double)>[];
  bool _ready = false;
  int _act = 0;

  static const _hold = 8.0, _end = 9.6;

  @override
  List<(String, TextStyle)> get fontRuns => [(_runs.map((r) => r.$1).join(' '), _style().copyWith(fontSize: 40))];

  @override
  Future<void> init() async {
    makePool(boxes: 2, cyls: 2, glows: 48);
    final text = _runs.map((r) => r.$1).join(' ');
    // The paragraph as Flutter lays it out: two lines, the runs' boxes.
    final tp = TextPainter(
      text: TextSpan(text: text, style: _style()),
      textDirection: TextDirection.ltr,
    // (Two lines, the second from こんにちは: wider, and the line would
    // break inside it — Japanese may break almost anywhere.)
    )..layout(maxWidth: _px * 13);
    final lines = tp.computeLineMetrics();
    final baselines = <double>[];
    var at = 0;
    for (final (run, _, _) in _runs) {
      final bs = tp.getBoxesForSelection(TextSelection(baseOffset: at, extentOffset: at + run.length));
      final r = bs.isEmpty ? Rect.zero : bs.first.toRect();
      _boxes.add(r);
      // (Its line: the one its box is in.)
      var best = lines.first;
      for (final l in lines) {
        if (r.center.dy > l.baseline - l.ascent && r.center.dy < l.baseline + l.descent) best = l;
      }
      baselines.add(best.baseline);
      _lines.add((best.lineNumber, best.baseline - best.ascent, best.baseline + best.descent));
      at += run.length + 1;
    }
    final width = tp.width, height = tp.height;
    tp.dispose();
    // Placed for the camera: as wide as [_wide] of the frame, facing it.
    final f = (_shot.target - _shot.eye).normalized();
    final right = vm.Vector3(0, 1, 0).cross(f).normalized(), up = f.cross(right);
    final ty = math.tan(_shot.fov * math.pi / 360), tx = ty * 16 / 9;
    _at = _shot.eye + f * _far + right * (_across * _far * tx) + up * (_up * _far * ty);
    _upp = _wide * 2 * _far * tx / width;
    final back = (_at - _shot.eye).normalized();
    final across = vm.Vector3(0, 1, 0).cross(back).normalized(), upright = back.cross(across);
    _facing = vm.Matrix4.identity()
      ..setColumn(0, vm.Vector4(across.x, across.y, across.z, 0))
      ..setColumn(1, vm.Vector4(upright.x, upright.y, upright.z, 0))
      ..setColumn(2, vm.Vector4(back.x, back.y, back.z, 0));
    // The runs, each extruded alone at the paragraph's scale (the emoji
    // painted: its colours are the point).
    final solids = await extrudeTextsAt([
      for (final (i, (run, _, _)) in _runs.indexed) (i == _emoji ? '.' : run, _style()),
    ], unitsPerPx: 1, depth: _depth / _upp);
    final metal = pbr(Vignette.c(0xC9D1DC), metallic: 0.85, roughness: 0.3);
    for (final (i, (_, _, color)) in _runs.indexed) {
      final box = _boxes[i];
      if (i == _emoji) {
        final tex = await paintedTexture(256, 256, (c, s) {
          final tp = TextPainter(
            text: TextSpan(text: _runs[i].$1, style: const TextStyle(fontSize: 150)),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(c, Offset((s.width - tp.width) / 2, (s.height - tp.height) / 2));
          tp.dispose();
        });
        final mat = PhysicallyBasedMaterial()
          ..baseColorTexture = tex
          ..alphaMode = AlphaMode.mask
          ..alphaCutoff = 0.4
          ..roughnessFactor = 0.5
          ..emissiveTexture = tex
          ..emissiveFactor = vm.Vector4(1, 1, 1, 1)
          ..emissiveStrength = 0.25;
        final n = Node(name: 'talk mix emoji', mesh: Mesh(boardGeometry(1, 1, thick: 0.01), mat))
          ..castsShadows = false
          ..visible = false;
        detail.add(n);
        _nodes.add(n);
        _mids.add(box.center);
        _heights.add(box.height * 0.62);
        continue;
      }
      final s = solids[i];
      final face = pbr(Vignette.c(color), roughness: 0.36, metallic: 0.05, emissive: Vignette.c(color), emissiveStrength: 0.16);
      _nodes.add(_node(s.mesh, face, metal));
      // (Its ink's middle: from its pen, at the box's left on its line's
      // baseline, by the ink's offset.)
      _mids.add(Offset(box.left + s.ox, baselines[i] - s.oy - s.mesh.height / 2));
      _heights.add(s.mesh.height);
    }
    _width = width;
    _height = height;
    await _buildPanel();
    _ready = true;
  }

  double _width = 1, _height = 1;

  /// A navy board behind the paragraph: the runs read against it, not
  /// against the skyline.
  late final Node _panel;

  Future<void> _buildPanel() async {
    final pw = _width * _upp + 2.4, ph = _height * _upp + 1.8;
    final tex = await paintedTexture(1024, (1024 * ph / pw).round(), (c, s) {
      final r = Offset.zero & s;
      c
        ..drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(28)),
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF17283F), Color(0xFF0B1626)],
            ).createShader(r),
        )
        ..drawRRect(
          RRect.fromRectAndRadius(r.deflate(6), const Radius.circular(24)),
          Paint()
            ..color = const Color(0x665FB8FF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4,
        );
    });
    final mat = PhysicallyBasedMaterial()
      ..baseColorTexture = tex
      ..alphaMode = AlphaMode.mask
      ..alphaCutoff = 0.5
      ..metallicFactor = 0
      ..roughnessFactor = 0.85
      ..emissiveTexture = tex
      ..emissiveFactor = vm.Vector4(1, 1, 1, 1)
      ..emissiveStrength = 0.35;
    _panel = Node(name: 'talk mix panel', mesh: Mesh(boardGeometry(pw, ph, thick: 0.05), mat))
      ..castsShadows = false
      ..visible = false;
    detail.add(_panel);
  }

  Node _node(GlyphMesh m, Material face, Material side) {
    final f = <int>[], s = <int>[];
    for (var t = 0; t + 2 < m.indices.length; t += 3) {
      final v = m.indices[t];
      (m.normals[v * 3 + 2].abs() > 0.5 ? f : s).addAll([m.indices[t], m.indices[t + 1], m.indices[t + 2]]);
    }
    MeshGeometry geometry(List<int> idx) => MeshGeometry.fromArrays(positions: m.positions, normals: m.normals, texCoords: m.uvs, indices: idx);
    final n = Node(name: 'talk mix run', mesh: Mesh.primitives(primitives: [MeshPrimitive(geometry(f), face), MeshPrimitive(geometry(s), side)]))
      ..visible = false;
    detail.add(n);
    return n;
  }

  // ── Posing ────────────────────────────────────────────────────────────────

  final _m = vm.Matrix4.identity();

  /// A point of the paragraph (px from its top left, y down; [z] px
  /// behind it) in the world.
  vm.Vector3 _world(double x, double y, [double z = 0]) {
    final l = vm.Vector3((x - _width / 2) * _upp, (_height / 2 - y) * _upp, z * _upp);
    return _at + _facing.transform3(l);
  }

  @override
  void pose(double u, double t, double night) {
    if (!_ready) return;
    if (visited) _act = 1;
    pool.begin();
    final on = _act == 1 && u < _end;
    final out = 1 - eio(seg(u, _hold, _hold + 0.9));
    // The board first, then the runs onto it.
    final pe = eo(seg(u, 0.05, 0.7)) * out;
    _panel.visible = on && pe > 0.002;
    if (_panel.visible) {
      _m
        ..setFrom(_facing)
        ..setTranslation(_world(_width / 2, _height / 2, (_depth + 0.35) / _upp));
      _panel.localTransform = _m * vm.Matrix4.diagonal3Values(pe, pe, 1);
    }
    for (var i = 0; i < _nodes.length; i++) {
      final n = _nodes[i];
      final k = seg(u, 0.4 + 0.28 * i, 1.2 + 0.28 * i);
      if (!on || k <= 0 || out <= 0.001) {
        n.visible = false;
        continue;
      }
      // In from behind it, each in turn, rising into place.
      final e = eo(k);
      final mid = _mids[i];
      final p = _world(mid.dx, mid.dy + 40 * (1 - e) + 3 * math.sin(t * 1.1 + i), 260 * (1 - e)) + vm.Vector3(0, 4 * (1 - out), 0);
      final s = _upp * (0.6 + 0.4 * e) * out;
      _m
        ..setFrom(_facing)
        ..setTranslation(p);
      if (i == _emoji) {
        final w = _boxes[i].width * _upp * (0.6 + 0.4 * e) * out;
        n
          ..visible = true
          ..localTransform = _m * vm.Matrix4.diagonal3Values(w, w, w);
      } else {
        n
          ..visible = true
          ..localTransform = _m * vm.Matrix4.diagonal3Values(s, s, s) * vm.Matrix4.translation(vm.Vector3(0, -_heights[i] / 2, 0));
      }
    }
    if (on && out > 0.001) {
      // The cuts between runs (itemize), drawn down each boundary.
      final cut = eo(seg(u, 3.4, 4.2)) * out;
      if (cut > 0.001) {
        for (var i = 0; i + 1 < _boxes.length; i++) {
          if (_lines[i + 1].$1 != _lines[i].$1) continue; // (a line between them)
          // (Between them on screen, as tall as their ink: the line's own
          // box is far taller, for the fallback fonts' ascents.)
          final a = _boxes[i], b = _boxes[i + 1];
          final x = a.right <= b.left ? (a.right + b.left) / 2 : (b.right + a.left) / 2;
          final top = math.min(_inkTop(i), _inkTop(i + 1)) - 12, bottom = math.max(_inkBottom(i), _inkBottom(i + 1)) + 12;
          _bar(x, top, x, top + (bottom - top) * cut, vm.Vector4(0.3, 2.0, 2.6, 1));
        }
      }
      // Each run's direction over it: right to left in coral, else cyan.
      final dir = eo(seg(u, 4.6, 5.4)) * out;
      if (dir > 0.001) {
        for (var i = 0; i < _boxes.length; i++) {
          final b = _boxes[i], rtl = _runs[i].$2;
          // (Drawn on the way it reads: right to left from its right end.)
          final y = _inkTop(i) - 22, len = (b.width - 28) * dir;
          final l = rtl ? b.right - 14 - len : b.left + 14, r = rtl ? b.right - 14 : b.left + 14 + len;
          final c = rtl ? vm.Vector4(2.6, 0.9, 0.5, 1) : vm.Vector4(0.3, 2.0, 2.6, 1);
          _bar(l, y, r, y, c);
          if (dir > 0.9) {
            // The arrowhead, at the end it points to.
            final hx = rtl ? l : r, s = rtl ? 1.0 : -1.0;
            _bar(hx, y, hx + s * 14, y - 10, c);
            _bar(hx, y, hx + s * 14, y + 10, c);
          }
        }
      }
    }
    pool.end();
  }

  /// Run [i]'s ink: its top and bottom (paragraph px, y down).
  double _inkTop(int i) => _mids[i].dy - _heights[i] / 2;
  double _inkBottom(int i) => _mids[i].dy + _heights[i] / 2;

  /// A glowing bar from (x0, y0) to (x1, y1) of the paragraph, in front.
  void _bar(double x0, double y0, double x1, double y1, vm.Vector4 c) {
    final a = _world(x0, y0, -_depth / _upp * 0.8), b = _world(x1, y1, -_depth / _upp * 0.8);
    final d = b - a, len = d.length;
    if (len < 1e-4) return;
    final mid = (a + b) * 0.5;
    // Turned to lie along a→b in the paragraph's plane.
    final ang = math.atan2(-(y1 - y0), x1 - x0);
    final q = vm.Quaternion.fromRotation(_facing.getRotation()) * vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), ang);
    final m = vm.Matrix4.compose(mid, q, vm.Vector3(len, 6 * _upp, 6 * _upp));
    pool.glowAt(m, c);
  }

  // ── The camera ────────────────────────────────────────────────────────────

  @override
  Shot shot(double u) {
    final k = eo(seg(u, 0, 12));
    final back = (_shot.eye - _shot.target).normalized();
    return Shot(_shot.eye + back * 3 * (1 - k), _shot.target, fov: _shot.fov, settle: _shot.settle, drift: _shot.drift);
  }
}
