import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui show ImageByteFormat, PictureRecorder;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart';
import 'package:flutter_scene/gpu.dart' as gpu show MinMagFilter;
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/craft/extrude.dart' show GlyphMesh;
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';
import 'shot.dart';
import 'vignette.dart';

/// フラッター · The talk's own word, hung over the park's alley only while a
/// talk calls on it: "Flutter" in its six glyphs (F l u tt e r: the t t a
/// ligature) as solid letters, their faces a gradient that flows (a
/// shader), their returns brushed metal. Two turns:
///
/// * what only Flutter can do (0–8 s): the letters arrive one by one; a box
///   for each grapheme is drawn round them as Flutter's debug paint would
///   (seven boxes for six glyphs: the ligature's split in two), over the
///   alphabetic baseline; then each glyph turns on its own, a Matrix4 with
///   nothing laid out again (the baseline stays put);
/// * Slug (20–35 s): the word first as an atlas draws it, a small bitmap
///   blown up, the camera coming in on the e until its pixels are blocks;
///   the pixels drop away to the curves behind, sharp however close, and
///   from the side too.
class TalkWord extends Vignette {
  TalkWord(super.kit);

  @override
  String get name => 'word';
  @override
  String get kick => 'ONLY IN FLUTTER';
  @override
  String get line => 'a box for each grapheme';
  @override
  String get note => 'seven graphemes, six glyphs: t t is one';

  @override
  bool get talkOnly => true;

  @override
  double get loop => 40;
  /// (The talk holds its camera within a visit: both turns.)
  @override
  double get visit => 36;

  /// Over the alley, facing the plaza.
  @override
  final frame = trs(vm.Vector3(0, 0, 36));

  static const _word = 'Flutter';

  /// The glyphs it shapes to (their text), and each grapheme's glyph.
  static const _pieces = [(0, 1), (1, 2), (2, 3), (3, 5), (5, 6), (6, 7)];
  static const _glyphOf = [0, 1, 2, 3, 3, 4, 5];

  /// An em (m), the size it's traced at and the atlas's (px), the
  /// baseline's height, the letters' depth; the gradient's period (m).
  static const _em = 4.2, _px = 400.0, _atlasPx = 80.0, _base = 9.4, _depth = 0.8, _period = 15.0;
  static const _upp = _em / _px;

  /// The turns: the first held at [_hold1], gone by [_end1]; the second
  /// from [_from2], its pixels going at [_dissolve], held at [_hold2].
  static const _hold1 = 7.0, _end1 = 8.4;
  static const _from2 = 20.0, _dissolve = 28.0, _hold2 = 33.5, _end2 = 34.8;

  static TextStyle _style(double size) => TextStyle(
    fontFamily: BP.display,
    fontSize: size,
    fontWeight: FontWeight.w700,
    fontVariations: const [FontVariation('wght', 700)],
  );

  /// Flutter's debug paint: boxes cyan, the alphabetic baseline green.
  static final _cyan = vm.Vector4(0.3, 2.0, 2.6, 1), _green = vm.Vector4(0.2, 2.6, 0.4, 1);

  static const _hues = [Color(0xFF2F6BFF), Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFFF59E0B), Color(0xFF2F6BFF)];

  final _glyphs = <Glyph3D>[];

  /// Each glyph's pen (x) and ink middle (its turn's axis); each
  /// grapheme's box (left, right, top, bottom).
  final _pens = <double>[], _pivots = <double>[];
  final _boxes = <(double, double, double, double)>[];
  double _width = 0;

  /// This frame's turn, bob and size of each glyph.
  final _spin = List.filled(6, 0.0), _bob = List.filled(6, 0.0);

  late final PhysicallyBasedMaterial _faceMat, _sideMat, _atlasMat;
  final _flow = TextureTransform();
  late final Node _atlas;
  vm.Vector3 _atlasAt = vm.Vector3.zero();

  /// Where the camera comes in on the e (its bowl's lower right, on the
  /// atlas's face).
  vm.Vector3 _close = vm.Vector3(3, 10, -0.5);

  /// Which turn the talk last called (0: none yet).
  int _act = 0;
  bool _ready = false;

  @override
  List<(String, TextStyle)> get fontRuns => [(_word, _style(40))];

  @override
  Future<void> init() async {
    makePool(boxes: 2, cyls: 2, glows: 40);
    final grad = _gradient();
    _faceMat = PhysicallyBasedMaterial()
      ..baseColorTexture = grad
      ..baseColorTextureTransform = _flow
      ..metallicFactor = 0.05
      ..roughnessFactor = 0.38
      ..emissiveTexture = grad
      ..emissiveTextureTransform = _flow
      ..emissiveFactor = vm.Vector4(1, 1, 1, 1)
      ..emissiveStrength = 0.18;
    _sideMat = pbr(Vignette.c(0xC9D1DC), metallic: 0.85, roughness: 0.3);

    // The word laid out as Flutter lays it out: the pens, the boxes.
    final tp = TextPainter(
      text: TextSpan(text: _word, style: _style(_px)),
      textDirection: TextDirection.ltr,
    )..layout();
    _width = tp.width * _upp;
    final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    double wx(double px) => px * _upp - _width / 2;
    double wy(double py) => _base + (baseline - py) * _upp;
    for (final (a, _) in _pieces) {
      _pens.add(wx(tp.getOffsetForCaret(TextPosition(offset: a), Rect.zero).dx));
    }
    for (var i = 0; i < _word.length; i++) {
      final bs = tp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
      final l = bs.isEmpty ? 0.0 : bs.map((b) => b.left).reduce(math.min), r = bs.isEmpty ? 0.0 : bs.map((b) => b.right).reduce(math.max);
      final top = bs.isEmpty ? 0.0 : bs.map((b) => b.top).reduce(math.min), bottom = bs.isEmpty ? 0.0 : bs.map((b) => b.bottom).reduce(math.max);
      _boxes.add((wx(l), wx(r), wy(top), wy(bottom)));
    }
    tp.dispose();

    final solids = await extrudeTextsAt([for (final (a, e) in _pieces) (_word.substring(a, e), _style(_px))], unitsPerPx: _upp, depth: _depth, simplify: 0.6);
    for (var i = 0; i < solids.length; i++) {
      final s = solids[i];
      _pivots.add(_pens[i] + s.ox);
      _glyphs.add(Glyph3D(s, _glyphNode(s.mesh, _pivots[i])));
    }
    final e = _glyphs[4];
    _close = vm.Vector3(_pivots[4] + 0.27 * e.width, _base + e.solid.oy + 0.3 * e.height, -(_depth / 2 + 0.06));
    _atlas = await _atlasBoard();
    if (const String.fromEnvironment('BOOTH3D_TIMES') != '') {
      debugPrint('WORD boxes ${[for (final b in _boxes) '${b.$1.toStringAsFixed(2)}…${b.$2.toStringAsFixed(2)}'].join(' ')} · pivots ${_pivots.map((p) => p.toStringAsFixed(2)).join(' ')}');
    }
    _ready = true;
  }

  /// A glyph's node: faces in the flowing gradient (laid along the word),
  /// sides in metal.
  Node _glyphNode(GlyphMesh m, double pivot) {
    final faces = <int>[], sides = <int>[];
    for (var t = 0; t + 2 < m.indices.length; t += 3) {
      final v = m.indices[t];
      (m.normals[v * 3 + 2].abs() > 0.5 ? faces : sides).addAll([m.indices[t], m.indices[t + 1], m.indices[t + 2]]);
    }
    final uv = Float32List(m.vertexCount * 2);
    for (var v = 0; v < m.vertexCount; v++) {
      uv
        ..[v * 2] = (pivot + m.positions[v * 3]) / _period
        ..[v * 2 + 1] = 0.5;
    }
    MeshGeometry geometry(List<int> idx) => MeshGeometry.fromArrays(positions: m.positions, normals: m.normals, texCoords: uv, indices: idx);
    final n = Node(
      name: 'talk word glyph',
      mesh: Mesh.primitives(primitives: [MeshPrimitive(geometry(faces), _faceMat), MeshPrimitive(geometry(sides), _sideMat)]),
    )..visible = false;
    detail.add(n);
    return n;
  }

  /// The gradient's colour [u] periods along (it repeats).
  static Color _hueAt(double u) {
    final f = (u - u.floorToDouble()) * (_hues.length - 1);
    final i = f.floor().clamp(0, _hues.length - 2);
    return Color.lerp(_hues[i], _hues[i + 1], f - i)!;
  }

  Texture2D _gradient() {
    const w = 256, h = 4;
    final px = Uint8List(w * h * 4);
    for (var x = 0; x < w; x++) {
      final c = _hueAt(x / w);
      for (var y = 0; y < h; y++) {
        final i = (y * w + x) * 4;
        px
          ..[i] = (c.r * 255).round()
          ..[i + 1] = (c.g * 255).round()
          ..[i + 2] = (c.b * 255).round()
          ..[i + 3] = 255;
      }
    }
    return Texture2D.fromPixels(px, w, h);
  }

  /// The word as an atlas holds it: drawn small ([_atlasPx]) to a bitmap
  /// (its coverage: grey at the edges), shown as big as the letters, every
  /// pixel a block (nearest, no mips). Each ink pixel's alpha is a coin, so
  /// raising the cutoff drops the pixels away in no order.
  Future<Node> _atlasBoard() async {
    const pad = 4;
    final tp = TextPainter(
      text: TextSpan(text: _word, style: _style(_atlasPx).copyWith(color: const Color(0xFFFFFFFF))),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width.ceil() + 2 * pad, h = tp.height.ceil() + 2 * pad;
    final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final rec = ui.PictureRecorder();
    tp.paint(Canvas(rec), const Offset(pad + 0.0, pad + 0.0));
    tp.dispose();
    final image = await rec.endRecording().toImage(w, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    final a = data!.buffer.asUint8List();
    const upp = _em / _atlasPx, ground = Color(0xFF16233A);
    final x0 = -_width / 2;
    final out = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4, cov = a[i + 3] / 255;
        if (cov < 0.05) continue;
        final c = Color.lerp(ground, _hueAt((x0 + (x + 0.5 - pad) * upp) / _period), cov)!;
        out
          ..[i] = (c.r * 255).round()
          ..[i + 1] = (c.g * 255).round()
          ..[i + 2] = (c.b * 255).round()
          ..[i + 3] = 14 + (rnd(x, y, 5) * 240).floor();
      }
    }
    final tex = Texture2D.fromPixels(
      out,
      w,
      h,
      sampling: const TextureSampling(mipmaps: false, minFilter: gpu.MinMagFilter.nearest, magFilter: gpu.MinMagFilter.nearest),
    );
    _atlasMat = PhysicallyBasedMaterial()
      ..baseColorTexture = tex
      ..alphaMode = AlphaMode.mask
      ..alphaCutoff = 0.03
      ..metallicFactor = 0.05
      ..roughnessFactor = 0.38
      ..emissiveTexture = tex
      ..emissiveFactor = vm.Vector4(1, 1, 1, 1)
      ..emissiveStrength = 0.18;
    _atlasAt = vm.Vector3(x0 + (w / 2 - pad) * upp, _base - (h / 2 - pad - baseline) * upp, -(_depth / 2 + 0.06));
    final n = Node(name: 'talk word atlas', mesh: Mesh(boardGeometry(w * upp, h * upp, thick: 0.02), _atlasMat))
      ..castsShadows = false
      ..visible = false;
    detail.add(n);
    return n;
  }

  // ── Posing ────────────────────────────────────────────────────────────────

  @override
  void pose(double u, double t, double night) {
    if (!_ready) return;
    if (visited) _act = u < 15 ? 1 : 2;
    pool.begin();
    final on = switch (_act) {
      1 => u < _end1,
      2 => u >= _from2 && u < _end2,
      _ => false,
    };
    if (!on) {
      for (final g in _glyphs) {
        g.node.visible = false;
      }
      _atlas.visible = false;
    } else if (_act == 1) {
      _only(u, t);
    } else {
      _slug(u, t);
    }
    // (The shader: the gradient flows along the word; still for Slug, where
    // the atlas's pixels, coloured as it stands, give way to it.)
    _flow.offset.x = _act == 1 ? -0.035 * t : 0;
    pool.end();
  }

  /// 0 → 1, a little past 1 before it settles.
  static double _overshoot(double k) {
    if (k <= 0) return 0;
    if (k >= 1) return 1;
    const c1 = 1.70158, c3 = c1 + 1;
    final x = k - 1;
    return 1 + c3 * x * x * x + c1 * x * x;
  }

  void _only(double u, double t) {
    _atlas.visible = false;
    for (var i = 0; i < _glyphs.length; i++) {
      final g = _glyphs[i];
      // In one by one, rising into place; each turned round once, one after
      // another; then breathing while the presenter talks; out, one by one.
      final a = 0.25 + 0.15 * i, k = seg(u, a, a + 0.8);
      final s = _overshoot(k) * (1 - eio(seg(u, _hold1 + 0.07 * i, _hold1 + 0.07 * i + 0.45)));
      _spin[i] = 2 * math.pi * eio(seg(u, 3.7 + 0.22 * i, 3.7 + 0.22 * i + 1.2));
      _bob[i] = 0.09 * math.sin(t * 1.6 + i * 0.9) * smooth(5.2, 7.0, u);
      put(g, _pivots[i], _base + g.solid.oy + g.height / 2 - 1.4 * (1 - eo(k)) + _bob[i], 0, s: s, yaw: _spin[i]);
    }
    // A box for each grapheme, drawn on one after another, turning with its
    // glyph (the ligature's two together).
    final z = -(_depth / 2 + 0.16);
    for (var j = 0; j < _boxes.length; j++) {
      final gi = _glyphOf[j];
      final d = eo(seg(u, 2.1 + 0.13 * j, 2.7 + 0.13 * j)) * (1 - eio(seg(u, _hold1 + 0.07 * gi, _hold1 + 0.07 * gi + 0.3)));
      if (d <= 0.001) continue;
      final (l, r, top, bottom) = _boxes[j];
      _frame(l, r, top + _bob[gi], bottom + _bob[gi], z, _pivots[gi], _spin[gi], d);
    }
    // The line's baseline: it stays as the glyphs turn.
    final b = eo(seg(u, 3.0, 3.7)) * (1 - eio(seg(u, _hold1, _hold1 + 0.4)));
    if (b > 0.001) {
      final l = _boxes.first.$1 - 0.5, r = _boxes.last.$2 + 0.5;
      pglow(l + (r - l) * b / 2, _base, z - 0.03, (r - l) * b, 0.05, 0.05, _green);
    }
  }

  /// A box's four sides drawn on ([d] 0…1), [z] in front of the letters,
  /// turned [yaw] round x = [p] as its glyph is (put's turn).
  void _frame(double l, double r, double top, double bottom, double z, double p, double yaw, double d) {
    final cs = math.cos(yaw), sn = math.sin(yaw);
    (double, double) turned(double x) => (p + (x - p) * cs + z * sn, -(x - p) * sn + z * cs);
    const th = 0.055;
    final w = r - l, h = top - bottom;
    // The sides, up from the bottom; the bottom and top, across from the left.
    for (final x in [l, r]) {
      final (tx, tz) = turned(x);
      pglow(tx, bottom + h * d / 2, tz, th, h * d, th, _cyan, yaw: yaw);
    }
    final (mx, mz) = turned(l + w * d / 2);
    for (final y in [bottom, top]) {
      pglow(mx, y, mz, w * d, th, th, _cyan, yaw: yaw);
    }
  }

  void _slug(double u, double t) {
    final out = 1 - eio(seg(u, _hold2, _hold2 + 0.5));
    // The atlas's word: in; at the dissolve, its pixels dropping away.
    final b = _overshoot(seg(u, _from2 + 0.15, _from2 + 0.85)) * out;
    final gone = seg(u, _dissolve, _dissolve + 1.4);
    _atlas.visible = b > 0.001 && gone < 1;
    if (_atlas.visible) {
      _atlas.localTransform = place(trs(_atlasAt, s: vm.Vector3.all(b)));
      _atlasMat.alphaCutoff = 0.03 + 0.98 * gone;
    }
    // The curves behind it, extruded as the pixels go; then turning a
    // little, sharp from any side.
    for (var i = 0; i < _glyphs.length; i++) {
      final g = _glyphs[i];
      final k = seg(u, _dissolve - 0.05 + 0.06 * i, _dissolve + 0.9 + 0.06 * i);
      final s = 1 - eio(seg(u, _hold2 + 0.06 * i, _hold2 + 0.06 * i + 0.45));
      if (k <= 0 || s <= 0.001) {
        g.node.visible = false;
        continue;
      }
      final sway = 0.16 * smooth(_dissolve + 1.2, _dissolve + 3.2, u) * math.sin(t * 0.8 + i * 0.7);
      put(g, _pivots[i], _base + g.solid.oy + g.height / 2, 0, s: s, yaw: sway);
      g.node.localTransform = g.node.localTransform * vm.Matrix4.diagonal3Values(1, 1, math.max(0.03, eo(k)));
    }
  }

  // ── The camera ────────────────────────────────────────────────────────────

  @override
  Shot shot(double u) {
    if (u < 15) {
      // Low on the cross path, looking up at the word against the sky.
      return Shot(vm.Vector3(-4.5, 3.4, -15.5), vm.Vector3(-0.5, 10.2, 0), fov: 52, settle: 1.0, drift: 0.5);
    }
    // Wide on the atlas's word; in on the e until its pixels are blocks;
    // once they've gone, round to its side.
    final e = _close;
    final k = eio(seg(u, _from2 + 1.4, _dissolve)), o = eio(seg(u, _dissolve + 1.6, _hold2 - 0.3));
    vm.Vector3 path(vm.Vector3 wide, vm.Vector3 near, vm.Vector3 round) => wide + (near - wide) * k + (round - near) * o;
    return Shot(
      path(vm.Vector3(-2.5, 5.0, -20.0), e + vm.Vector3(-0.3, -0.25, -2.4), e + vm.Vector3(2.2, 0.45, -3.8)),
      path(vm.Vector3(-0.6, 10.6, 0), e, e + vm.Vector3(0.05, 0.35, 0.3)),
      fov: 46 + (32 - 46) * k + (40 - 32) * o,
      settle: 0.6,
      drift: 0.25,
    );
  }
}
