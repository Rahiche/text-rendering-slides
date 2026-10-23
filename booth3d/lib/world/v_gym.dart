import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'devices.dart' show deviceScreen;
import 'kit.dart';
import 'live_screen.dart';
import 'shot.dart';
import 'vignette.dart';

/// 太さジム · Painting text, an outdoor gym on the lawn behind the site
/// (left of the park's path): a lifting platform with a loaded barbell, a
/// rack of hex dumbbells, a bench, and the gym's big screen, which Flutter
/// paints live as the scene runs ([_GymScreen]: a widget, captured into
/// the screen's texture each frame). On it "Flutter" takes a gradient
/// shader, then a stroke, then its weight axis breathes; then each letter
/// lifts a dumbbell, bolder the higher it goes (its wght under it, frame
/// by frame); then a pulse, a rep counter and an emoji are painted in
/// among the letters. Timed to the narration: "…with shaders, with
/// strokes, and with variable fonts. In this gym, the letters are lifting
/// weights… And because it's all just painting, you can mix text with
/// anything else on screen."
class WeightGym extends Vignette {
  WeightGym(super.kit);

  @override
  String get name => 'gym';
  @override
  String get kick => 'PAINTING TEXT';
  @override
  String get line => 'shader · stroke · wght 100 → 800';
  @override
  String get note => 'one font file, any weight in between, painted every frame';

  @override
  double get loop => 24;
  @override
  double get visit => 16;

  /// Facing the park's path.
  @override
  final frame = trs(vm.Vector3(-6.9, 0, 14.6), rotY: -math.pi / 2);

  /// The screen: its middle, its size (16:9).
  static const _screenY = 1.78, _screenZ = 1.82, _screenW = 3.6, _screenH = 2.025;

  @override
  List<(String, TextStyle)> get fontRuns => [
    for (final w in [100.0, 400.0, 800.0]) ('Flutter wght 0123456789', _GymScreen.letterStyle(w)),
    ("Paint()..shader ..style = stroke FontVariation('wght', w) + anything else REPS bpm", const TextStyle(fontFamily: BP.mono)),
    ('wght GYM 💪', const TextStyle(fontFamily: BP.display)),
  ];

  final _u = ValueNotifier<double>(0);
  late final LiveScreen _screen;
  bool _ready = false;

  @override
  Future<void> init() async {
    final b = Batch();
    final m = pbr(rgb(1, 1, 1), roughness: 0.85);
    final coat = pbr(rgb(1, 1, 1), roughness: 0.45, metallic: 0.55);
    final steel = pbr(rgb(1, 1, 1), roughness: 0.3, metallic: 0.9);
    // The rubber floor, its tiles' seams.
    box(b, m, 6.3, 0.05, 4.1, 0.15, 0.025, 0.45, Vignette.c(0x2B3038));
    for (var k = -2; k <= 2; k++) {
      box(b, m, 0.014, 0.004, 4.1, k * 1.2 + 0.15, 0.052, 0.45, Vignette.c(0x3A414C));
    }
    for (var k = 0; k < 3; k++) {
      box(b, m, 6.3, 0.004, 0.014, 0.15, 0.052, -0.55 + 1.3 * k, Vignette.c(0x3A414C));
    }
    // The screen's rig: two uprights on their feet, a bar over them, the
    // bezel between.
    for (final x in [-1.98, 1.98]) {
      box(b, coat, 0.12, 3.05, 0.12, x, 1.525, 1.88, Vignette.c(0x2A2E35));
      box(b, coat, 0.16, 0.06, 0.9, x, 0.08, 1.88, Vignette.c(0x2A2E35));
    }
    box(b, coat, 4.08, 0.12, 0.12, 0, 3.0, 1.88, Vignette.c(0x2A2E35));
    box(b, m, _screenW + 0.14, _screenH + 0.14, 0.07, 0, _screenY, 1.87, Vignette.c(0x101216));
    // The lifting platform (right of the screen, out of the talk's
    // picture: it's the screen's): oak in the middle, rubber either side;
    // the barbell along it, loaded (red 25s, blue 20s).
    const platX = 2.85, platZ = 0.1;
    box(b, m, 1.0, 0.05, 1.2, platX, 0.08, platZ, Vignette.c(0xA27C55));
    for (final z in [-0.9, 0.9]) {
      box(b, m, 1.0, 0.05, 0.6, platX, 0.08, platZ + z, Vignette.c(0x1E2227));
    }
    const barY = 0.105 + 0.225;
    cylinder(b, steel, 0.014, 2.2, platX, barY, platZ, Vignette.c(0xB8BEC6), rotX: math.pi / 2, sides: 10);
    for (final s in [-1.0, 1.0]) {
      cylinder(b, steel, 0.025, 0.42, platX, barY, platZ + s * 0.91, Vignette.c(0xC9CED6), rotX: math.pi / 2, sides: 12);
      cylinder(b, steel, 0.04, 0.03, platX, barY, platZ + s * 0.69, Vignette.c(0x9AA1AB), rotX: math.pi / 2, sides: 12);
      cylinder(b, m, 0.225, 0.065, platX, barY, platZ + s * 0.74, Vignette.c(0xC8323C), rotX: math.pi / 2, sides: 28);
      cylinder(b, m, 0.225, 0.055, platX, barY, platZ + s * 0.805, Vignette.c(0x2D5DA8), rotX: math.pi / 2, sides: 28);
      cylinder(b, steel, 0.035, 0.03, platX, barY, platZ + s * 0.85, Vignette.c(0x9AA1AB), rotX: math.pi / 2, sides: 12);
    }
    // The dumbbell rack (behind it, by the rig): two tiers of rails on its
    // ends, hex dumbbells across them, heavier towards the back.
    const rackX = 2.6;
    for (final z in [1.15, 2.35]) {
      box(b, coat, 0.5, 0.86, 0.06, rackX, 0.43, z, Vignette.c(0x2A2E35));
    }
    for (final y in [0.42, 0.78]) {
      for (final side in [-0.13, 0.13]) {
        box(b, coat, 0.04, 0.04, 1.26, rackX + side, y, 1.75, Vignette.c(0x2A2E35));
      }
    }
    for (final (tier, y) in [(0, 0.42), (1, 0.78)]) {
      for (var k = 0; k < 3; k++) {
        final r = 0.05 + 0.01 * k + 0.012 * tier;
        final z = 1.4 + 0.35 * k;
        final top = y + 0.02 + r;
        cylinder(b, steel, 0.016, 0.14, rackX, top, z, Vignette.c(0xB8BEC6), rotZ: math.pi / 2, sides: 8);
        for (final s in [-1.0, 1.0]) {
          cylinder(b, m, r, 0.075, rackX + s * 0.105, top, z, Vignette.c(0x1E2125), rotZ: math.pi / 2, sides: 6);
        }
      }
    }
    b.buildInto(detail, 'weight gym', castsShadows: false, lightChannelMask: 0x01);

    // The sign over the rig.
    await sign(2.6, 0.46, vm.Matrix4.translation(vm.Vector3(0, 3.33, 1.88)), (c, s) {
      c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFE8505F));
      Vignette.text(c, 'wght GYM', Offset.zero & s, s.height * 0.58, const Color(0xFFFFFFFF), family: BP.display);
    }, glow: 0.4);

    // The screen: dark until its first capture, then whatever Flutter
    // painted last.
    final dark = await paintedTexture(4, 4, (c, s) => c.drawRect(Offset.zero & s, Paint()..color = _GymScreen.bg));
    final mat = deviceScreen(dark);
    detail.add(
      Node(
        name: 'gym screen',
        mesh: Mesh(boardGeometry(_screenW, _screenH, thick: 0.01), mat),
        localTransform: place(vm.Matrix4.translation(vm.Vector3(0, _screenY, _screenZ))),
      )..castsShadows = false,
    );
    _screen = LiveScreen(
      _GymScreen.w,
      _GymScreen.h,
      CustomPaint(painter: _GymScreen(_u)),
      pixelRatio: kIsWeb ? 0.6 : 1.25,
    )..show(mat);
    _ready = true;
  }

  @override
  void pose(double u, double t, double night) {
    if (!_ready || !visited) return;
    // (Only while the camera's here: a capture paints the screen whole.)
    _u.value = u;
    _screen.capture();
  }

  // ── The camera ────────────────────────────────────────────────────────────

  /// Square on to the screen, from the platform's front: the barbell along
  /// the bottom.
  @override
  Shot shot(double u) => Shot(vm.Vector3(-0.35, 1.6, -2.75), vm.Vector3(0.0, _screenY - 0.05, _screenZ), fov: 46, settle: 1.0, drift: 0.3);
}

/// The gym's screen, painted by Flutter as the scene runs ([u]: its
/// seconds), 1280×720.
class _GymScreen extends CustomPainter {
  _GymScreen(this.u) : super(repaint: u);

  final ValueListenable<double> u;

  static const w = 1280.0, h = 720.0;
  static const bg = Color(0xFF0B1628);

  static const _word = 'Flutter';
  static const _size = 220.0, _base = 540.0;

  /// Each letter's top over the baseline (of the size, JetBrains Mono).
  static const _tops = [0.73, 0.77, 0.55, 0.67, 0.67, 0.55, 0.55];

  /// When each part comes in (seconds into the scene, as the narration
  /// says it: its clip's pauses, from 1.5 s before the scene's start): the
  /// shader, the stroke, the weight axis; the dumbbells, their reps (each
  /// letter a little after the one before); the rest painted in with the
  /// text.
  static const _shaderAt = 1.7, _strokeAt = 2.9, _varyAt = 3.9, _liftAt = 6.0, _mixAt = 15.9;
  static const _period = 2.6, _stagger = 0.2;

  static TextStyle letterStyle(double wght, {Paint? foreground}) => TextStyle(
    fontFamily: BP.mono,
    fontSize: _size,
    height: 1,
    foreground: foreground,
    color: foreground == null ? const Color(0xFFF2F5FA) : null,
    fontVariations: [FontVariation('wght', wght)],
  );

  /// How far letter [i] has lifted its dumbbell at [t] (0 at the chest, 1
  /// overhead).
  static double _lift(int i, double t) {
    final p = t - _liftAt - 0.6 - _stagger * i;
    return p <= 0 ? 0 : 0.5 - 0.5 * math.cos(2 * math.pi * p / _period);
  }

  /// Letter [i]'s weight at [t]: 400, then a breath (800, 100, back), then
  /// 100 at the chest to 800 overhead.
  static double _weight(int i, double t) {
    final k = seg(t, _varyAt, _varyAt + 1.8);
    final s = math.sin(2 * math.pi * k);
    final breath = 400 + (k < 0.5 ? 400 : 300) * s;
    return lerp(breath, 100 + 700 * _lift(i, t), smooth(_liftAt, _liftAt + 0.6, t));
  }

  /// Letter [i]'s weight at [t] in steps of 10 (each step a font instance,
  /// laid out once: [_laid]).
  static int _wght(int i, double t) => (_weight(i, t) / 10).round() * 10;

  /// The first letter's reps: how many (and part of the next) at [t].
  static double _reps(double t) => math.max(0.0, t - _liftAt - 0.6) / _period;

  static final _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.2
    ..strokeJoin = StrokeJoin.round
    ..color = const Color(0xFFEAF3FF);

  /// Laid-out text, kept: the screen's few strings in their few looks are
  /// each laid out once, not every frame (a new weight is a new font
  /// instance to shape with).
  final _laid = <String, TextPainter>{};

  TextPainter _tp(String key, String text, TextStyle style) {
    final hit = _laid[key];
    if (hit != null) return hit;
    if (_laid.length > 1600) {
      for (final p in _laid.values) {
        p.dispose();
      }
      _laid.clear();
    }
    return _laid[key] = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
  }

  @override
  void paint(Canvas c, Size s) {
    final t = math.max(0.0, u.value);
    final sx = s.width / w;
    c.save();
    c.scale(sx, sx);
    // The screen's ground: navy, a light pooled under the word.
    c.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(0, h), const [Color(0xFF10203A), bg]));
    c.drawOval(
      Rect.fromCenter(center: const Offset(w / 2, _base + 6), width: 980, height: 120),
      Paint()..shader = ui.Gradient.radial(const Offset(w / 2, _base + 6), 490, const [Color(0x332F6FD0), Color(0x002F6FD0)]),
    );
    c.drawRect(Rect.fromLTWH(150, _base + 8, w - 300, 2), Paint()..color = const Color(0xFF243A5C));

    final mix = smooth(_mixAt, _mixAt + 0.8, t);
    if (mix > 0) _pulse(c, t, mix);
    _letters(c, t);
    _chips(c, t);
    if (mix > 0) _extras(c, t, mix);
    c.restore();
  }

  static const _advance = _size * 0.6;
  static const _x0 = (w - _advance * 7) / 2;

  static const _wordBox = Rect.fromLTRB(_x0 - 30, 0, _x0 + _advance * 7 + 30, _base + 40);

  void _letters(Canvas c, double t) {
    // The fill: white, the shader drawn over it (as far as it's swept)
    // into the letters alone; nearly hollow a moment as the stroke comes
    // in, then filled again.
    final sweep = _x0 - 40 + (_advance * 7 + 80) * eio(seg(t, _shaderAt, _shaderAt + 0.9));
    final stroke = 0.9 * smooth(_strokeAt, _strokeAt + 0.3, t);
    final hollow = smooth(_strokeAt + 0.1, _strokeAt + 0.4, t) * (1 - smooth(_strokeAt + 0.9, _strokeAt + 1.3, t));
    c.saveLayer(_wordBox, Paint()..color = Color.fromRGBO(255, 255, 255, 1 - 0.9 * hollow));
    for (var i = 0; i < _word.length; i++) {
      final wq = _wght(i, t);
      _letter(c, i, t, _tp('fill $i $wq', _word[i], letterStyle(wq.toDouble())));
    }
    if (sweep > _wordBox.left) {
      final phase = t * 90;
      c.drawRect(
        Rect.fromLTRB(_wordBox.left, _wordBox.top, math.min(sweep, _wordBox.right), _wordBox.bottom),
        Paint()
          ..blendMode = BlendMode.srcIn
          ..shader = ui.Gradient.linear(
            Offset(_x0 + phase, _base - 180),
            Offset(_x0 + phase + 560, _base),
            const [Color(0xFF13B9FD), Color(0xFF2F7BFF), Color(0xFF9B5CFF)],
            const [0, 0.55, 1],
            TileMode.mirror,
          ),
      );
    }
    c.restore();
    if (stroke > 0) {
      c.saveLayer(_wordBox, Paint()..color = Color.fromRGBO(255, 255, 255, stroke));
      for (var i = 0; i < _word.length; i++) {
        final wq = _wght(i, t);
        _letter(c, i, t, _tp('stroke $i $wq', _word[i], letterStyle(wq.toDouble(), foreground: _stroke)));
      }
      c.restore();
    }
    // Each letter's dumbbell, dropped in, then pressed from its top to
    // overhead and back.
    final drop = seg(t, _liftAt, _liftAt + 0.55);
    if (drop > 0) {
      for (var i = 0; i < _word.length; i++) {
        final lift = _lift(i, t);
        final e = Curves.easeOutBack.transform(seg(drop, 0.05 * i, math.min(1.0, 0.6 + 0.05 * i)));
        final top = _base - _tops[i] * _size;
        _dumbbell(c, _x0 + (i + 0.5) * _advance, top - 34 - 64 * lift - (1 - e) * 520);
      }
    }
    // Each one's weight under it (amber, lifted).
    final shown = smooth(_varyAt - 0.3, _varyAt, t);
    if (shown <= 0) return;
    final fading = shown < 1;
    if (fading) c.saveLayer(const Rect.fromLTRB(0, _base + 20, w, _base + 90), Paint()..color = Color.fromRGBO(255, 255, 255, shown));
    for (var i = 0; i < _word.length; i++) {
      final wq = _wght(i, t), hot = _lift(i, t) > 0.6;
      _put(c, _tp('wght $wq $hot', '$wq', _mono(24, hot ? BP.amber : const Color(0xFF7F93B0))), Offset(_x0 + (i + 0.5) * _advance, _base + 56), center: true);
    }
    _put(c, _tp('wght', 'wght', _mono(24, BP.amber)), const Offset(_x0 - 24, _base + 56), right: true);
    if (fading) c.restore();
  }

  /// Letter [i] laid out ([tp]), standing on the baseline in its cell.
  /// (Not stretched as it lifts: text under a scale that isn't uniform is
  /// drawn from its outlines every frame, not from the glyph atlas.)
  void _letter(Canvas c, int i, double t, TextPainter tp) {
    final x = _x0 + i * _advance;
    tp.paint(c, Offset(x + (_advance - tp.width) / 2, _base - tp.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
  }

  /// A dumbbell: a steel bar, a red plate either end, collars; drawn once
  /// (twice the pixels) and stamped where each one is (drawn whole every
  /// frame, its gradients cost the frame more than all the text did).
  static ui.Image? _bell;

  static ui.Image _bellImage() {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec)..scale(2);
    const cx = 60.0, cy = 43.0;
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(cx, cy), width: 100, height: 11), const Radius.circular(5.5)),
      Paint()..shader = ui.Gradient.linear(const Offset(cx, cy - 6), const Offset(cx, cy + 6), const [Color(0xFFEEF2F6), Color(0xFF808894)]),
    );
    for (final side in [-1.0, 1.0]) {
      final plate = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx + side * 36, cy), width: 22, height: 74), const Radius.circular(6));
      c.drawRRect(
        plate,
        Paint()..shader = ui.Gradient.linear(Offset(cx + side * 36, cy - 37), Offset(cx + side * 36, cy + 37), const [Color(0xFFF0575C), Color(0xFFA8262D)]),
      );
      c.drawRRect(
        plate,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0x66FFFFFF),
      );
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx + side * 51, cy), width: 7, height: 24), const Radius.circular(2)),
        Paint()..color = const Color(0xFFC9D0DA),
      );
    }
    return rec.endRecording().toImageSync(240, 172);
  }

  static final _bellPaint = Paint()..filterQuality = FilterQuality.medium;

  /// A dumbbell centred at ([cx], [cy]).
  void _dumbbell(Canvas c, double cx, double cy) =>
      c.drawImageRect(_bell ??= _bellImage(), const Rect.fromLTWH(0, 0, 240, 172), Rect.fromCenter(center: Offset(cx, cy), width: 120, height: 86), _bellPaint);

  static const _chipNames = ['Paint()..shader', '..style = stroke', "FontVariation('wght', w)", '+ anything else'];

  /// What paints the text, along the top: lit as the narration names it.
  void _chips(Canvas c, double t) {
    const at = [_shaderAt, _strokeAt, _varyAt, _mixAt];
    TextPainter label(int i, int lit) =>
        _tp('chip $i $lit', _chipNames[i], _mono(22, Color.lerp(const Color(0xFF52668A), BP.amber, lit / 10)!));
    final widths = [for (var i = 0; i < _chipNames.length; i++) label(i, 10).width + 30];
    var x = (w - widths.reduce((a, b) => a + b) - 16 * 3) / 2;
    for (var i = 0; i < _chipNames.length; i++) {
      final on = smooth(at[i] - 0.1, at[i] + 0.25, t);
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(x, 44, widths[i], 44), const Radius.circular(10));
      c.drawRRect(r, Paint()..color = Color.lerp(const Color(0xFF13233D), const Color(0xFF3A2E14), on)!);
      c.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Color.lerp(const Color(0xFF2C3F5E), BP.amber, on)!,
      );
      _put(c, label(i, (on * 10).round()), Offset(x + widths[i] / 2, 66), center: true, middle: true);
      x += widths[i] + 16;
    }
  }

  /// A pulse running behind the letters.
  void _pulse(Canvas c, double t, double k) {
    final path = Path();
    const y0 = 470.0, beat = 300.0;
    final off = (t * 220) % beat;
    for (var x = 40.0; x <= w - 40; x += 4) {
      final p = (x + off) % beat;
      final d = p < 150 || p > 210
          ? 0.0
          : p < 165
          ? -(p - 150) * 3.2
          : p < 180
          ? -48 + (p - 165) * 9.6
          : p < 195
          ? 96 - (p - 180) * 8.8
          : -36 + (p - 195) * 2.4;
      x == 40 ? path.moveTo(x, y0 + d) : path.lineTo(x, y0 + d);
    }
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF3DE0C8).withValues(alpha: 0.85 * k);
    c.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
      ..color = const Color(0xFF3DE0C8).withValues(alpha: 0.35 * k));
    c.drawPath(path, line);
  }

  /// A rep counter (a ring, its count in it) and an emoji, painted in with
  /// the text.
  void _extras(Canvas c, double t, double k) {
    final fading = k < 1;
    if (fading) c.saveLayer(const Rect.fromLTWH(0, 0, w, h), Paint()..color = Color.fromRGBO(255, 255, 255, k));
    final grow = 0.85 + 0.15 * Curves.easeOutBack.transform(k);
    c.save();
    c.translate(1170, 214);
    c.scale(grow);
    c.drawCircle(
      Offset.zero,
      64,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = const Color(0xFF22324A),
    );
    final reps = _reps(t);
    c.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: 64),
      -math.pi / 2,
      2 * math.pi * (reps % 12) / 12,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..color = BP.amber,
    );
    final n = reps.floor();
    _put(c, _tp('reps $n', '$n', const TextStyle(fontFamily: BP.display, fontSize: 46, fontWeight: FontWeight.w700, color: Color(0xFFFFFFFF))), const Offset(0, -6), center: true, middle: true);
    _put(c, _tp('REPS', 'REPS', _mono(15, const Color(0xFF8DB7DA))), const Offset(0, 30), center: true, middle: true);
    c.restore();
    c.save();
    c.translate(110, 200);
    c.scale(grow);
    _put(c, _tp('emoji', '💪', const TextStyle(fontSize: 88)), Offset.zero, center: true, middle: true);
    c.restore();
    _put(c, _tp('bpm', '♥ 128 bpm', _mono(20, const Color(0xFF3DE0C8))), const Offset(110, 286), center: true, middle: true);
    if (fading) c.restore();
  }

  static TextStyle _mono(double size, Color color) => TextStyle(fontFamily: BP.mono, fontSize: size, fontWeight: FontWeight.w600, color: color);

  /// [tp] at [at]: its start there (its end, [right]; its middle,
  /// [center]), its baseline there (its middle, [middle]).
  static void _put(Canvas c, TextPainter tp, Offset at, {bool center = false, bool right = false, bool middle = false}) {
    final dx = center ? -tp.width / 2 : (right ? -tp.width : 0.0);
    final dy = middle ? -tp.height / 2 : -tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    tp.paint(c, at + Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_GymScreen old) => old.u != u;
}
