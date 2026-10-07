import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/craft/extrude.dart';
import 'package:text_slides/booth/craft/geometry.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';
import 'shot.dart';
import 'vignette.dart';

/// 端末 · Phones, hung over the lawn behind the site, only while a talk
/// calls on them: big enough to read from the back of a room, their
/// screens laid out by the real text stack. Two turns:
///
/// * line breaking (0–8 s): one phone, a paragraph filled up to its
///   maxWidth (an amber line at the right margin); turned on its side, the
///   width more than doubles and the same words break into fewer, longer
///   lines;
/// * the same everywhere (20–32 s): an iPhone in SF Pro and an Android
///   phone in Roboto, each laying the paragraph out its own way (the lines
///   break in different places); both turn round once and come back as
///   Flutter draws them, in the app's own font with its own line breaker:
///   line for line the same.
class TalkPhones extends Vignette {
  TalkPhones(super.kit);

  @override
  String get name => 'phones';
  @override
  String get kick => '端末 · PHONES';
  @override
  String get line => 'the same words, the same lines';
  @override
  String get note => 'native fonts break lines their own way; Flutter brings its own';

  @override
  bool get talkOnly => true;

  /// (The talk holds its camera within a visit: both turns.)
  @override
  double get loop => 40;
  @override
  double get visit => 36;

  /// Over the lawn behind the site, facing the plaza.
  @override
  final frame = trs(vm.Vector3(-1.0, 0, 21.0));

  /// A phone's size (m), its screen's, the screen's pixels; how high they
  /// hang (their middles); the two phones' places in the second turn.
  static const _w = 1.62, _h = 3.4, _depth = 0.16, _sw = 1.5, _sh = 3.26, _px = 540, _py = 1174;
  static const _y = 8.5, _apart = 1.4;

  /// The turns: the first held at [_hold1], gone by [_end1]; the second
  /// from [_from2], held at [_hold2].
  static const _turn0 = 3.4, _turn1 = 4.5, _hold1 = 7.0, _end1 = 8.4;
  static const _from2 = 20.0, _spin0 = 25.6, _spin1 = 26.5, _hold2 = 31.0, _end2 = 32.4;

  static const _lineText = 'Each line is filled up to maxWidth; the next word that won\'t fit starts a new one.';
  static const _sameText = 'These words wrap at different places on each phone\'s own text engine.';

  late final Node _a, _b, _aScreen, _bScreen, _aWide;
  late final PhysicallyBasedMaterial _aMat, _bMat;
  late final Texture2D _tall, _iosNative, _androidNative, _flutter;
  bool _ready = false;
  int _act = 0;

  @override
  List<(String, TextStyle)> get fontRuns => [(_sameText, const TextStyle(fontFamily: 'Roboto', fontSize: 40))];

  @override
  Future<void> init() async {
    final body = _slab(_w, _h, 0.2, _depth);
    // (Titanium, not mirror silver: a bright frame blooms over the screen.)
    final silver = pbr(Vignette.c(0x8E9298), metallic: 0.7, roughness: 0.42);
    final graphite = pbr(Vignette.c(0x2A2E35), metallic: 0.7, roughness: 0.34);
    // The paragraph for the same-everywhere turn, at a size where the two
    // platforms' own fonts break it in different places.
    final size = _differingSize();
    final textures = await Future.wait([
      _screen(_lineText, 'Notes', 'maxWidth', const TextStyle(fontFamily: BP.display), 62, guide: true),
      _screen(_lineText, 'Notes', 'maxWidth', const TextStyle(fontFamily: BP.display), 62, guide: true, wide: true),
      _screen(_sameText, 'iOS', 'SF Pro · its own layout', const TextStyle(), size),
      _screen(_sameText, 'Android', 'Roboto · its own layout', const TextStyle(fontFamily: 'Roboto'), size),
      _screen(_sameText, 'Flutter', 'Space Grotesk · one layout', const TextStyle(fontFamily: BP.display), size, flutter: true),
    ]);
    _tall = textures[0];
    _iosNative = textures[2];
    _androidNative = textures[3];
    _flutter = textures[4];
    _aMat = _screenMat(_tall);
    _bMat = _screenMat(_androidNative);
    final wideMat = _screenMat(textures[1]);
    _a = _phone(body, silver);
    _b = _phone(body, graphite);
    _aScreen = _screenNode(_aMat, _sw, _sh);
    _bScreen = _screenNode(_bMat, _sw, _sh);
    _aWide = _screenNode(wideMat, _sh, _sw);
    _ready = true;
  }

  /// A rounded slab [w]×[h]×[depth] (m), corners of radius [r]: a rounded
  /// rectangle traced at a millimetre a pixel and extruded.
  static GlyphMesh _slab(double w, double h, double r, double depth) {
    final mw = w * 1000, mh = h * 1000, mr = r * 1000;
    final pts = <double>[];
    const steps = 10;
    for (final (cx, cy, a0) in [(mw - mr, mh - mr, 0.0), (mr, mh - mr, math.pi / 2), (mr, mr, math.pi), (mw - mr, mr, 1.5 * math.pi)]) {
      for (var k = 0; k <= steps; k++) {
        final a = a0 + k / steps * math.pi / 2;
        pts.addAll([cx + mr * math.cos(a), cy + mr * math.sin(a)]);
      }
    }
    final g = GlyphGeometry(
      w: mw.ceil(),
      h: mh.ceil(),
      contours: [Contour(Float64List.fromList(pts), hole: false, area: mw * mh)],
      strokes: const [],
      spans: const [],
      inkLeft: 0,
      inkTop: 0,
      inkRight: mw,
      inkBottom: mh,
    );
    return extrudeGlyph(g, unitsPerPx: 0.001, depth: depth, simplify: 0);
  }

  Node _phone(GlyphMesh body, Material m) {
    final n = Node(name: 'talk phone', mesh: Mesh(glyphGeometry(body), m))..visible = false;
    detail.add(n);
    return n;
  }

  /// A screen lights itself: barely lit by the sun (its colour mostly its
  /// own glow), so both phones read the same whichever way they face.
  PhysicallyBasedMaterial _screenMat(Texture2D t) => PhysicallyBasedMaterial()
    ..baseColorTexture = t
    ..baseColorFactor = vm.Vector4(0.1, 0.1, 0.1, 1)
    ..alphaMode = AlphaMode.mask
    ..alphaCutoff = 0.5
    ..metallicFactor = 0
    ..roughnessFactor = 0.6
    ..emissiveTexture = t
    ..emissiveFactor = vm.Vector4(1, 1, 1, 1)
    ..emissiveStrength = 0.82;

  Node _screenNode(Material m, double w, double h) {
    final n = Node(name: 'talk phone screen', mesh: Mesh(boardGeometry(w, h, thick: 0.01), m))
      ..castsShadows = false
      ..visible = false;
    detail.add(n);
    return n;
  }

  /// A size (px) at which SF Pro and Roboto break [_sameText] differently
  /// across the screen's width.
  static double _differingSize() {
    for (final s in [62.0, 60.0, 64.0, 58.0, 66.0, 56.0]) {
      if (!_sameBreaks(_breaks(const TextStyle(), s), _breaks(const TextStyle(fontFamily: 'Roboto'), s))) return s;
    }
    return 62;
  }

  static bool _sameBreaks(List<int> a, List<int> b) => a.length == b.length && [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

  /// Where each line of [_sameText] starts, laid out in [style] at [size]
  /// across the screen's text width.
  static List<int> _breaks(TextStyle style, double size) {
    final tp = TextPainter(
      text: TextSpan(text: _sameText, style: style.copyWith(fontSize: size, height: 1.38)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _px - 2 * _margin);
    final starts = [
      for (final m in tp.computeLineMetrics()) tp.getPositionForOffset(Offset(1, m.baseline - m.ascent + 1)).offset,
    ];
    tp.dispose();
    return starts;
  }

  static const _margin = 44.0;

  /// A screen: the status bar, an app bar ([title], [sub]), [text] laid out
  /// in [style] at [size] across the screen's width (on its side if
  /// [wide]); [guide]: the maxWidth line at the right margin. Corners round
  /// (see-through), as a phone's screen is.
  Future<Texture2D> _screen(String text, String title, String sub, TextStyle style, double size, {bool guide = false, bool wide = false, bool flutter = false}) async {
    final w = wide ? _py : _px, h = wide ? _px : _py;
    return paintedTexture(w, h, (c, s) {
      final r = RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(54));
      c
        ..clipRRect(r)
        ..drawRect(Offset.zero & s, Paint()..color = const Color(0xFFF7F8FA));
      // The status bar.
      _label(c, '9:41', const Offset(_margin, 26), 26, const Color(0xFF16181D), weight: FontWeight.w600);
      final bx = s.width - _margin - 46;
      c
        ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(bx, 30, 42, 20), const Radius.circular(5)), Paint()
          ..color = const Color(0xFF16181D)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4)
        ..drawRect(Rect.fromLTWH(bx + 4, 34, 30, 12), Paint()..color = const Color(0xFF16181D));
      // The app bar: what's drawing it.
      final accent = flutter ? const Color(0xFF1565C0) : const Color(0xFF4A505C);
      c.drawRect(Rect.fromLTWH(0, 84, s.width, 116), Paint()..color = flutter ? const Color(0xFFE6F1FD) : const Color(0xFFEDEEF1));
      _label(c, title, const Offset(_margin, 100), 44, const Color(0xFF16181D), weight: FontWeight.w700);
      _label(c, sub, const Offset(_margin, 154), 24, accent, weight: FontWeight.w600, family: BP.mono);
      // The paragraph, as this text stack lays it out; each line's last
      // word marked (where it broke).
      final maxWidth = s.width - 2 * _margin;
      final tp = TextPainter(
        text: _marked(text, style.copyWith(fontSize: size, height: 1.38, color: const Color(0xFF16181D)), maxWidth),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth);
      tp.paint(c, const Offset(_margin, 236));
      if (guide) {
        // maxWidth: the line the words fill up to.
        final x = _margin + maxWidth;
        for (var y = 226.0; y < 236 + tp.height + 10; y += 22) {
          c.drawLine(Offset(x, y), Offset(x, y + 12), Paint()
            ..color = const Color(0xFFF5A524)
            ..strokeWidth = 4);
        }
        _label(c, 'maxWidth', Offset(x - 150, 236 + tp.height + 24), 24, const Color(0xFFE0901A), weight: FontWeight.w700, family: BP.mono);
      }
      tp.dispose();
      // The home indicator.
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(s.width / 2, s.height - 22), width: 170, height: 9), const Radius.circular(5)), Paint()..color = const Color(0xFF16181D));
    });
  }

  /// [text] in [style], each line's last word (as laid out across
  /// [maxWidth]) on an amber highlight: only colours change, so the lines
  /// break where they did.
  static TextSpan _marked(String text, TextStyle style, double maxWidth) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout(maxWidth: maxWidth);
    final ends = [
      for (final m in tp.computeLineMetrics()) tp.getPositionForOffset(Offset(maxWidth + 20, m.baseline - m.ascent / 2)).offset,
    ];
    tp.dispose();
    final mark = TextStyle(background: Paint()..color = const Color(0x66F5A524), color: const Color(0xFF7A4A00));
    final spans = <TextSpan>[];
    var at = 0;
    for (final e in ends) {
      if (e <= at) continue;
      final line = text.substring(at, e).trimRight();
      final cut = at + line.lastIndexOf(' ') + 1;
      spans
        ..add(TextSpan(text: text.substring(at, cut)))
        ..add(TextSpan(text: text.substring(cut, at + line.length), style: mark))
        ..add(TextSpan(text: text.substring(at + line.length, e)));
      at = e;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: style, children: spans);
  }

  static void _label(Canvas c, String s, Offset at, double size, Color color, {FontWeight weight = FontWeight.w500, String? family}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontFamily: family ?? BP.display, fontSize: size, color: color, fontWeight: weight)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, at);
    tp.dispose();
  }

  // ── Posing ────────────────────────────────────────────────────────────────

  @override
  void pose(double u, double t, double night) {
    if (!_ready) return;
    if (visited) _act = u < 15 ? 1 : 2;
    for (final n in [_a, _b, _aScreen, _bScreen, _aWide]) {
      n.visible = false;
    }
    if (_act == 1 && u < _end1) _rotate(u, t);
    if (_act == 2 && u >= _from2 && u < _end2) _same(u, t);
  }

  /// 0 → 1, a little past 1 before it settles.
  static double _overshoot(double k) {
    if (k <= 0) return 0;
    if (k >= 1) return 1;
    const c1 = 1.70158, c3 = c1 + 1;
    final x = k - 1;
    return 1 + c3 * x * x * x + c1 * x * x;
  }

  final _m = vm.Matrix4.identity();

  /// [n] at (x, y, z) of the frame, turned by yaw and roll, scaled [s].
  void _put(Node n, double x, double y, double z, {double s = 1, double yaw = 0, double roll = 0}) {
    if (s <= 0.001) return;
    _m.setFromTranslationRotationScale(vm.Vector3(x, y, z), vm.Quaternion.euler(yaw, 0, roll), vm.Vector3.all(s));
    n
      ..visible = true
      ..localTransform = frame * _m;
  }

  /// A phone and its screen, its middle at (x, y): the body stands on its
  /// bottom edge (the slab's ink), the screen just in front of its face.
  void _phoneAt(Node body, Node screen, double x, double y, {double s = 1, double yaw = 0, double roll = 0, bool face = true}) {
    if (s <= 0.001) return;
    final q = vm.Quaternion.euler(yaw, 0, roll);
    final down = q.rotated(vm.Vector3(0, -_h * s / 2, 0));
    _put(body, x + down.x, y + down.y, down.z, s: s, yaw: yaw, roll: roll);
    if (!face) return;
    final front = q.rotated(vm.Vector3(0, 0, -(_depth / 2 + 0.008) * s));
    _put(screen, x + front.x, y + front.y, front.z, s: s, yaw: yaw, roll: roll);
  }

  void _rotate(double u, double t) {
    final s = _overshoot(seg(u, 0.2, 1.0)) * (1 - eio(seg(u, _hold1, _hold1 + 0.5)));
    final bob = 0.06 * math.sin(t * 1.3);
    final turn = eio(seg(u, _turn0, _turn1));
    final wide = u >= _turn1;
    // On its side: the screen laid out again at the new width (upright).
    _aMat.baseColorTexture = _aMat.emissiveTexture = _tall;
    _phoneAt(_a, _aScreen, 0, _y + bob, s: s, roll: math.pi / 2 * turn, face: !wide);
    if (wide && s > 0.001) {
      _put(_aWide, 0, _y + bob, -(_depth / 2 + 0.008) * s, s: s);
    }
  }

  void _same(double u, double t) {
    final s = _overshoot(seg(u, _from2 + 0.2, _from2 + 1.0)) * (1 - eio(seg(u, _hold2, _hold2 + 0.5)));
    final apart = eio(seg(u, _from2 + 0.1, _from2 + 1.1));
    // A turn round each, the screens swapped as they're edge on: native,
    // then Flutter.
    final spin = 2 * math.pi * eio(seg(u, _spin0, _spin1));
    final flutter = u >= (_spin0 + _spin1) / 2;
    _aMat.baseColorTexture = _aMat.emissiveTexture = flutter ? _flutter : _iosNative;
    _bMat.baseColorTexture = _bMat.emissiveTexture = flutter ? _flutter : _androidNative;
    for (final (i, (body, screen)) in [(_a, _aScreen), (_b, _bScreen)].indexed) {
      final side = i == 0 ? -1.0 : 1.0;
      final bob = 0.06 * math.sin(t * 1.3 + i * 1.7);
      _phoneAt(body, screen, side * _apart * apart, _y + bob, s: s, yaw: spin + side * 0.08 * (1 - smooth(_spin0, _spin1, u)));
    }
  }

  // ── The camera ────────────────────────────────────────────────────────────

  @override
  Shot shot(double u) {
    if (u < 15) {
      // A little closer as it turns.
      final k = smooth(_turn0 - 0.5, _turn1 + 1.0, u);
      return Shot(vm.Vector3(-1.1, lerp(7.5, 7.7, k), lerp(-6.4, -6.0, k)), vm.Vector3(0, 8.45, 0), fov: 40, settle: 1.0, drift: 0.4);
    }
    return Shot(vm.Vector3(-0.9, 7.6, -7.6), vm.Vector3(0, 8.45, 0), fov: 40, settle: 1.0, drift: 0.4);
  }
}
