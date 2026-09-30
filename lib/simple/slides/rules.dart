import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../deck/scripts.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Grid
// ─────────────────────────────────────────────────────────────────────────────

/// Every mini animation is drawn on this design canvas and scaled to its panel.
const _dw = 320.0;
const _dh = 250.0;
const _design = Size(_dw, _dh);

const _gapX = 24.0;
const _gapY = 34.0;
const _panelTop = 10.0;
const _panelW = (1472 - 3 * _gapX) / 4;
const _panelH = (628 - _panelTop - _gapY) / 2;
const _bigH = 628.0;
const _bigW = _bigH * _panelW / _panelH;

class _Rule {
  const _Rule(this.label, this.script, this.color, this.build);

  final String label;
  final String script;
  final Color color;
  final Widget Function() build;
}

final _rules = <_Rule>[
  _Rule('direction', 'hebrew', Script.hebrew.color, () => const _Direction()),
  _Rule('position forms', 'arabic', Script.arabic.color, () => const _Forms()),
  _Rule('reorder', 'devanagari', Script.devanagari.color, () => const _Reorder()),
  _Rule('stacking', 'thai', Script.thai.color, () => const _Stacking()),
  _Rule('no spaces', 'thai', Script.thai.color, () => const _NoSpaces()),
  _Rule('composition', 'hangul', Script.hangul.color, () => const _Hangul()),
  _Rule('vertical', 'japanese', Script.kana.color, () => const _Vertical()),
  _Rule('combining', 'emoji', Script.emoji.color, () => const _Emoji()),
];

/// Eight scripts, eight broken assumptions. Click a panel to enlarge + replay.
class ScriptRulesSlide extends StatefulWidget {
  const ScriptRulesSlide({super.key});

  @override
  State<ScriptRulesSlide> createState() => _ScriptRulesSlideState();
}

class _ScriptRulesSlideState extends State<ScriptRulesSlide> {
  int? _big;
  int _top = 0;
  int? _hover;
  final _nonce = List<int>.filled(8, 0);

  void _tap(int i) => setState(() {
    if (_big == i) {
      _big = null;
    } else {
      _big = i;
      _top = i;
      _nonce[i]++;
    }
  });

  Rect _rectOf(int i) {
    if (_big == i) return const Rect.fromLTWH((1472 - _bigW) / 2, 0, _bigW, _bigH);
    final c = i % 4;
    final r = i ~/ 4;
    return Rect.fromLTWH(c * (_panelW + _gapX), _panelTop + r * (_panelH + _gapY), _panelW, _panelH);
  }

  @override
  Widget build(BuildContext context) {
    final order = [
      for (var i = 0; i < _rules.length; i++)
        if (i != _top) i,
      _top,
    ];
    return SlideFrame(
      title: 'Every script breaks a rule',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => setState(() => _big = null),
            ),
          ),
          for (final i in order) _panel(i),
        ],
      ),
    );
  }

  Widget _panel(int i) {
    final r = _rectOf(i);
    final big = _big == i;
    final dim = _big != null && !big;
    final hot = big || _hover == i;
    final rule = _rules[i];
    return AnimatedPositioned(
      key: ValueKey(i),
      duration: const Duration(milliseconds: 560),
      curve: Curves.easeInOutCubic,
      left: r.left,
      top: r.top,
      width: r.width,
      height: r.height,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 320),
        opacity: dim ? 0.14 : 1,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = i),
          onExit: (_) => setState(() => _hover = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _tap(i),
            child: ColoredBox(
              // BpPanel's fill is translucent; keep panels behind from showing through.
              color: BP.paper,
              child: BpPanel(
                label: rule.label,
                color: hot ? rule.color : BP.lineDim,
                padding: const EdgeInsets.fromLTRB(14, 22, 14, 12),
                child: SizedBox.expand(
                  child: Stack(
                    children: [
                      // Tight constraints so the design canvas scales up when enlarged.
                      Positioned.fill(
                        child: FittedBox(
                          child: SizedBox.fromSize(
                            size: _design,
                            child: KeyedSubtree(key: ValueKey(_nonce[i]), child: rule.build()),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Text(rule.script, style: BT.mono(11, color: BP.inkFaint)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Rebuilds cached text layouts when fonts arrive (web fallback fonts load late).
mixin _FontAware<T extends StatefulWidget> on State<T> {
  void rebuildText();

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.systemFonts.addListener(_onFonts);
  }

  void _onFonts() {
    if (mounted) setState(rebuildText);
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_onFonts);
    super.dispose();
  }
}

TextPainter _tp(String s, TextStyle style, [TextDirection dir = TextDirection.ltr]) => TextPainter(
  text: TextSpan(text: s, style: style),
  textDirection: dir,
)..layout();

/// Paints a one-off label anchored at [at] by fractions ([ax], [ay]) of its size.
void _label(Canvas c, String s, TextStyle style, Offset at, {double ax = 0.5, double ay = 0}) {
  final tp = _tp(s, style);
  tp.paint(c, at - Offset(tp.width * ax, tp.height * ay));
  tp.dispose();
}

void _paintAlpha(Canvas c, TextPainter tp, Offset at, double alpha) {
  if (alpha <= 0.001) return;
  if (alpha >= 0.999) {
    tp.paint(c, at);
    return;
  }
  c.saveLayer((at & tp.size).inflate(60), Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
  tp.paint(c, at);
  c.restore();
}

/// Paints [tp] centred on [center], scaled by [s].
void _paintCentered(Canvas c, TextPainter tp, Offset center, double s, double alpha) {
  if (alpha <= 0.001 || s <= 0.01) return;
  c.save();
  c.translate(center.dx, center.dy);
  c.scale(s);
  _paintAlpha(c, tp, Offset(-tp.width / 2, -tp.height / 2), alpha);
  c.restore();
}

Paint _stroke(Color c, [double w = 1]) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w;

void _dashRect(Canvas c, Rect r, Color color, {double width = 1, double dash = 4, double gap = 3}) =>
    c.drawPath(dashPath(Path()..addRect(r), dash: dash, gap: gap), _stroke(color, width));

void _dashLine(
  Canvas c,
  Offset a,
  Offset b,
  Color color, {
  double width = 1,
  double dash = 4,
  double gap = 3,
}) => c.drawPath(
  dashPath(
    Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy),
    dash: dash,
    gap: gap,
  ),
  _stroke(color, width),
);

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
double _ease(double t, double a, double b) => Curves.easeInOutCubic.transform(_seg(t, a, b));

void _diamond(Canvas c, Offset o, double r, Color color) {
  c.drawPath(
    Path()
      ..moveTo(o.dx, o.dy - r)
      ..lineTo(o.dx + r, o.dy)
      ..lineTo(o.dx, o.dy + r)
      ..lineTo(o.dx - r, o.dy)
      ..close(),
    Paint()..color = color,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// 1 · direction — Hebrew typed from the right
// ─────────────────────────────────────────────────────────────────────────────

class _Direction extends StatefulWidget {
  const _Direction();

  @override
  State<_Direction> createState() => _DirectionState();
}

class _DirectionState extends State<_Direction> with _FontAware {
  static const _word = 'שלום';
  late TextProbe _probe;
  late List<TextPainter> _letters;

  @override
  void initState() {
    super.initState();
    _make();
  }

  void _make() {
    final style = BT.sample(84, weight: 500);
    _probe = TextProbe(
      TextSpan(text: _word, style: style),
      textDirection: TextDirection.rtl,
    );
    _letters = [for (var i = 0; i < _word.length; i++) _tp(_word[i], style, TextDirection.rtl)];
  }

  void _free() {
    _probe.dispose();
    for (final l in _letters) {
      l.dispose();
    }
  }

  @override
  void rebuildText() {
    _free();
    _make();
  }

  @override
  void dispose() {
    _free();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LoopBuilder(
    period: const Duration(milliseconds: 4600),
    builder: (context, t, _) => CustomPaint(size: _design, painter: _DirectionPainter(_probe, _letters, t)),
  );
}

class _DirectionPainter extends CustomPainter {
  _DirectionPainter(this.probe, this.letters, this.t);

  final TextProbe probe;
  final List<TextPainter> letters;
  final double t;

  static const _starts = [0.08, 0.2, 0.32, 0.44];

  @override
  void paint(Canvas canvas, Size size) {
    final w = probe.size.width;
    final lines = probe.lines;
    if (lines.isEmpty) return;
    final o = Offset((size.width - w) / 2, 92 - probe.size.height / 2);
    final baseY = o.dy + lines.first.baseline;
    final fade = 1 - _seg(t, 0.86, 0.96);

    _dashLine(canvas, Offset(14, baseY), Offset(size.width - 14, baseY), BP.lineFaint, dash: 5, gap: 4);

    var caretX = o.dx + w;
    var typed = 0;
    final latest = _starts.lastIndexWhere((s) => t > s);
    var boxBottom = o.dy + probe.size.height;
    var boxTop = o.dy;
    for (var i = 0; i < letters.length; i++) {
      final boxes = probe.boxes(i, i + 1);
      if (boxes.isEmpty) continue;
      final box = boxes.first.toRect().shift(o);
      boxTop = box.top;
      boxBottom = box.bottom;
      final p = _seg(t, _starts[i], _starts[i] + 0.07);
      caretX = ui.lerpDouble(caretX, box.left, Curves.easeOutCubic.transform(p))!;
      if (p <= 0) continue;
      typed = i + 1;
      final a = p * fade;
      final e = Curves.easeOutBack.transform(p);
      _dashRect(canvas, box, BP.lineDim.withValues(alpha: a));
      final l = letters[i];
      _paintAlpha(canvas, l, Offset(box.left + (box.width - l.width) / 2, o.dy - (1 - e) * 18), a);
      _label(
        canvas,
        '$i',
        BT.mono(14, color: (i == latest ? BP.amber : BP.inkDim).withValues(alpha: a)),
        Offset(box.center.dx, box.bottom + 8),
      );
    }

    // Typing direction: an arrow growing leftwards behind the caret.
    if (typed > 0 && fade > 0) {
      final y = boxBottom + 44;
      drawArrow(
        canvas,
        Offset(o.dx + w + 8, y),
        Offset(caretX - 4, y),
        Paint()
          ..color = BP.amber.withValues(alpha: fade)
          ..strokeWidth = 1.5,
      );
    }

    // Caret (blinks once typing is done).
    final idle = t > 0.52 || t < _starts.first;
    final on = !idle || ((t * 4600) ~/ 420).isEven;
    if (fade > 0 && on) {
      canvas.drawRect(
        Rect.fromLTRB(caretX - 1.5, boxTop, caretX + 1.5, boxBottom),
        Paint()..color = BP.amber.withValues(alpha: fade),
      );
    }
  }

  @override
  bool shouldRepaint(_DirectionPainter old) => old.t != t || old.probe != probe;
}

// ─────────────────────────────────────────────────────────────────────────────
// 2 · position forms — Arabic ع in four shapes (forced with ZWJ)
// ─────────────────────────────────────────────────────────────────────────────

TextStyle _kufi(double size, Color color) =>
    TextStyle(fontFamily: BP.arabic, fontSize: size, color: color, height: 1.25);

class _Forms extends StatelessWidget {
  const _Forms();

  static const _forms = ['ع', 'ع‍', '‍ع‍', '‍ع'];
  static const _tags = ['isol', 'init', 'medi', 'fina'];

  /// Cells laid out right-to-left: isolated is rightmost, like reading order.
  static double _cellX(int k) => 244.0 - k * 76.0;

  @override
  Widget build(BuildContext context) => LoopBuilder(
    period: const Duration(milliseconds: 5200),
    builder: (context, t, _) {
      final pos = t * 4;
      final i = pos.floor().clamp(0, 3);
      final m = Curves.easeInOutCubic.transform(_seg(pos - i, 0.8, 1));
      final mx = ui.lerpDouble(_cellX(i), _cellX((i + 1) % 4), m)!;
      return SizedBox.fromSize(
        size: _design,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: _dw,
              height: 150,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 360),
                child: CustomPaint(
                  key: ValueKey(i),
                  size: const Size(_dw, 150),
                  painter: _ArabicPainter(_forms[i], i),
                ),
              ),
            ),
            for (var k = 0; k < 4; k++) ...[
              Positioned(
                left: _cellX(k),
                top: 162,
                width: 64,
                height: 56,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: k == i ? BP.amber.withValues(alpha: 0.10) : BP.panel,
                    border: Border.all(color: k == i ? BP.amber : BP.lineDim),
                  ),
                  child: Text(
                    _forms[k],
                    textDirection: TextDirection.rtl,
                    style: _kufi(26, k == i ? BP.ink : BP.inkDim),
                  ),
                ),
              ),
              Positioned(
                left: _cellX(k),
                top: 224,
                width: 64,
                child: Text(
                  _tags[k],
                  textAlign: TextAlign.center,
                  style: BT.mono(12, color: k == i ? BP.amber : BP.inkFaint),
                ),
              ),
            ],
            Positioned(
              left: mx,
              top: 157,
              width: 64,
              height: 3,
              child: const ColoredBox(color: BP.amber),
            ),
          ],
        ),
      );
    },
  );
}

class _ArabicPainter extends CustomPainter {
  _ArabicPainter(this.text, this.form);

  final String text;

  /// 0 isol, 1 init, 2 medi, 3 fina.
  final int form;

  @override
  void paint(Canvas canvas, Size size) {
    final probe = TextProbe(
      TextSpan(text: text, style: _kufi(84, BP.ink)),
      textDirection: TextDirection.rtl,
    );
    final lines = probe.lines;
    if (lines.isEmpty) {
      probe.dispose();
      return;
    }
    const baseY = 100.0;
    final o = Offset((size.width - probe.size.width) / 2, baseY - lines.first.baseline);
    _dashLine(
      canvas,
      const Offset(20, baseY),
      Offset(size.width - 20, baseY),
      BP.amber.withValues(alpha: 0.5),
    );
    final adv = probe.rectFor(0, text.length)?.shift(o);
    if (adv != null) {
      // Advance box, trimmed to the glyph's band.
      final r = Rect.fromLTRB(adv.left, baseY - 78, adv.right, baseY + 40);
      _dashRect(canvas, r, BP.lineDim);
      // Where this form joins its neighbours (RTL: the next letter is to the left).
      final joinLeft = form == 1 || form == 2;
      final joinRight = form == 2 || form == 3;
      if (joinLeft) _diamond(canvas, Offset(r.left, baseY), 5, BP.amber);
      if (joinRight) _diamond(canvas, Offset(r.right, baseY), 5, BP.amber);
    }
    probe.paint(canvas, o);
    probe.dispose();
  }

  @override
  bool shouldRepaint(_ArabicPainter old) => old.text != text;
}

// ─────────────────────────────────────────────────────────────────────────────
// 3 · reorder — Devanagari कि: the vowel sign is stored after, drawn before
// ─────────────────────────────────────────────────────────────────────────────

class _Reorder extends StatefulWidget {
  const _Reorder();

  @override
  State<_Reorder> createState() => _ReorderState();
}

class _ReorderState extends State<_Reorder> with _FontAware {
  late TextProbe _word;
  late TextPainter _ka;
  late TextPainter _i;

  @override
  void initState() {
    super.initState();
    _make();
  }

  void _make() {
    _word = TextProbe(TextSpan(text: 'कि', style: BT.sample(80)));
    _ka = _tp('क', BT.sample(34));
    _i = _tp('ि', BT.sample(34, color: Script.devanagari.color));
  }

  void _free() {
    _word.dispose();
    _ka.dispose();
    _i.dispose();
  }

  @override
  void rebuildText() {
    _free();
    _make();
  }

  @override
  void dispose() {
    _free();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LoopBuilder(
    period: const Duration(milliseconds: 5400),
    builder: (context, t, _) => CustomPaint(size: _design, painter: _ReorderPainter(_word, _ka, _i, t)),
  );
}

class _ReorderPainter extends CustomPainter {
  _ReorderPainter(this.word, this.ka, this.i, this.t);

  final TextProbe word;
  final TextPainter ka;
  final TextPainter i;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final vColor = Script.devanagari.color;
    final chipsIn = _seg(t, 0.02, 0.12);
    final fly = _ease(t, 0.18, 0.5);
    final land = _seg(t, 0.36, 0.56);
    final fade = 1 - _seg(t, 0.88, 0.97);

    // Row labels
    _label(canvas, 'memory', BT.mono(11, color: BP.inkFaint), const Offset(8, 58), ax: 0, ay: 0.5);
    _label(canvas, 'screen', BT.mono(11, color: BP.inkFaint), const Offset(8, 188), ax: 0, ay: 0.5);

    // Memory: two code points in logical order.
    final kaChip = Rect.fromCenter(center: const Offset(150, 58), width: 62, height: 74);
    final iChip = Rect.fromCenter(center: const Offset(222, 58), width: 62, height: 74);
    final a = chipsIn * fade;
    if (a > 0) {
      canvas.drawRect(kaChip, _stroke(BP.lineDim.withValues(alpha: a)));
      canvas.drawRect(iChip, _stroke(vColor.withValues(alpha: a), 1.5));
      _label(
        canvas,
        '0',
        BT.mono(11, color: BP.inkDim.withValues(alpha: a)),
        kaChip.topCenter - const Offset(0, 16),
      );
      _label(
        canvas,
        '1',
        BT.mono(11, color: BP.inkDim.withValues(alpha: a)),
        iChip.topCenter - const Offset(0, 16),
      );
      // The glyphs leave their slots while in flight, and are back once landed.
      final away = 1 - 0.8 * math.min(1.0, fly * 4) * (1 - land);
      _paintCentered(canvas, ka, kaChip.center - const Offset(0, 8), 1, a * away);
      _paintCentered(canvas, i, iChip.center - const Offset(0, 8), 1, a * away);
      _label(
        canvas,
        'U+0915',
        BT.mono(10, color: BP.inkFaint.withValues(alpha: a)),
        kaChip.bottomCenter - const Offset(0, 16),
      );
      _label(
        canvas,
        'U+093F',
        BT.mono(10, color: vColor.withValues(alpha: a)),
        iChip.bottomCenter - const Offset(0, 16),
      );
    }

    // Screen: the real shaped cluster.
    final ws = word.size;
    final wo = Offset(186 - ws.width / 2, 188 - ws.height / 2);
    final r = word.rectFor(0, 2)?.shift(wo) ?? (wo & ws);
    final kaTarget = Offset(r.left + r.width * 0.64, r.center.dy);
    final iTarget = Offset(r.left + r.width * 0.24, r.center.dy);

    // Crossing construction lines: memory order ≠ visual order.
    if (fly > 0 && fade > 0) {
      final kaFrom = kaChip.bottomCenter;
      final iFrom = iChip.bottomCenter;
      _dashLine(canvas, kaFrom, Offset.lerp(kaFrom, kaTarget, fly)!, BP.line.withValues(alpha: 0.6 * fade));
      _dashLine(
        canvas,
        iFrom,
        Offset.lerp(iFrom, iTarget, fly)!,
        vColor.withValues(alpha: 0.8 * fade),
        width: 1.5,
      );
    }

    // Flying copies.
    // Copies grow a little and dissolve into the real cluster as they arrive.
    final scale = ui.lerpDouble(1, 1.6, fly)!;
    final copyA = fly > 0 ? (1 - _seg(fly, 0.5, 0.95)) * fade : 0.0;
    if (copyA > 0) {
      final kaPos = Offset.lerp(kaChip.center - const Offset(0, 8), kaTarget, fly)!;
      final arc = -math.sin(fly * math.pi) * 30;
      final iPos = Offset.lerp(iChip.center - const Offset(0, 8), iTarget, fly)! + Offset(0, arc);
      _paintCentered(canvas, ka, kaPos, scale, copyA);
      _paintCentered(canvas, i, iPos, scale, copyA);
    }

    // The real cluster fades in.
    final wa = land * fade;
    if (wa > 0) {
      _dashRect(canvas, r, BP.lineDim.withValues(alpha: wa));
      _paintAlpha(canvas, word.painter, wo, wa);
    }
  }

  @override
  bool shouldRepaint(_ReorderPainter old) => old.t != t || old.word != word;
}

// ─────────────────────────────────────────────────────────────────────────────
// 4 · stacking — Thai ป + ั + ่: marks drop onto the base and stack.
//
// The pieces are cut out of the engine's own rendering: we rasterize ป, ปั,
// ปั่ (and ป่) and subtract, so every mark lands exactly where HarfBuzz put it.
// ─────────────────────────────────────────────────────────────────────────────

class _Layer {
  _Layer(this.image, this.bounds);

  final ui.Image image;

  /// Ink bounds in raster pixels, or null if the layer is empty.
  final Rect? bounds;

  static Future<_Layer> make(Uint8List a, Uint8List? minus, int w, int h) async {
    final px = Uint8List(w * h * 4);
    var minX = w, minY = h, maxX = -1, maxY = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        var v = a[i] - (minus == null ? 0 : minus[i]);
        if (v < 12) v = 0;
        if (v == 0) continue;
        final j = i * 4;
        px[j] = 255;
        px[j + 1] = 255;
        px[j + 2] = 255;
        px[j + 3] = v;
        if (v > 60) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
    final img = await c.future;
    final b = maxX < 0 ? null : Rect.fromLTRB(minX.toDouble(), minY.toDouble(), maxX + 1.0, maxY + 1.0);
    return _Layer(img, b);
  }
}

class _Raster {
  _Raster(this.layers, this.pad, this.w, this.h, this.k);

  /// base, vowel, tone (stacked), tone (on the bare base).
  final List<_Layer> layers;
  final double pad;
  final int w;
  final int h;
  final double k;

  void dispose() {
    for (final l in layers) {
      l.image.dispose();
    }
  }

  static Future<_Raster?> build(double fontSize, double k) async {
    final style = BT.sample(fontSize * k, color: const Color(0xFFFFFFFF));
    final painters = [
      for (final s in const ['ป', 'ปั', 'ปั่', 'ป่']) _tp(s, style),
    ];
    final pad = (fontSize * k * 0.4).ceilToDouble();
    final w = (painters.map((p) => p.width).reduce(math.max) + pad * 2).ceil();
    final h = painters.map((p) => p.height).reduce(math.max).ceil();
    final alphas = <Uint8List>[];
    try {
      for (final p in painters) {
        final rec = ui.PictureRecorder();
        p.paint(Canvas(rec), Offset(pad, 0));
        final pic = rec.endRecording();
        final img = await pic.toImage(w, h);
        pic.dispose();
        final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        img.dispose();
        if (bd == null) return null;
        final bytes = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
        final a = Uint8List(w * h);
        for (var i = 0; i < a.length; i++) {
          a[i] = bytes[i * 4 + 3];
        }
        alphas.add(a);
      }
    } finally {
      for (final p in painters) {
        p.dispose();
      }
    }
    final layers = [
      await _Layer.make(alphas[0], null, w, h),
      await _Layer.make(alphas[1], alphas[0], w, h),
      await _Layer.make(alphas[2], alphas[1], w, h),
      await _Layer.make(alphas[3], alphas[0], w, h),
    ];
    return _Raster(layers, pad, w, h, k);
  }
}

class _Stacking extends StatefulWidget {
  const _Stacking();

  @override
  State<_Stacking> createState() => _StackingState();
}

class _StackingState extends State<_Stacking> with _FontAware {
  static const _size = 116.0;
  late TextProbe _probe;
  _Raster? _raster;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _make();
  }

  void _make() {
    _probe = TextProbe(TextSpan(text: 'ปั่', style: BT.sample(_size)));
    _rasterize();
  }

  Future<void> _rasterize() async {
    final gen = ++_gen;
    final r = await _Raster.build(_size, 3);
    if (!mounted || gen != _gen) {
      r?.dispose();
      return;
    }
    setState(() {
      _raster?.dispose();
      _raster = r;
    });
  }

  @override
  void rebuildText() {
    _probe.dispose();
    _make();
  }

  @override
  void dispose() {
    _gen++;
    _probe.dispose();
    _raster?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: LoopBuilder(
      period: const Duration(milliseconds: 5400),
      builder: (context, t, _) => CustomPaint(size: _design, painter: _StackPainter(_probe, _raster, t)),
    ),
  );
}

class _StackPainter extends CustomPainter {
  _StackPainter(this.probe, this.raster, this.t);

  final TextProbe probe;
  final _Raster? raster;
  final double t;

  static final _colors = [BP.ink, Script.thai.color, BP.amber];
  static const _names = ['base', 'vowel', 'tone'];

  @override
  void paint(Canvas canvas, Size size) {
    final ps = probe.size;
    final o = Offset((size.width - ps.width) / 2 - 34, 132 - ps.height / 2);
    final fade = 1 - _seg(t, 0.9, 0.98);
    final rs = raster;

    // Baseline guide
    final lines = probe.lines;
    if (lines.isNotEmpty) {
      final by = o.dy + lines.first.baseline;
      _dashLine(canvas, Offset(14, by), Offset(size.width - 14, by), BP.lineFaint, dash: 5, gap: 4);
    }

    if (rs == null) {
      probe.paint(canvas, o);
      return;
    }

    final k = rs.k;
    final dst = Rect.fromLTWH(o.dx - rs.pad / k, o.dy, rs.w / k, rs.h / k);
    Rect? boundsOf(_Layer l, double dy) => l.bounds == null
        ? null
        : Rect.fromLTRB(
            dst.left + l.bounds!.left / k,
            dst.top + l.bounds!.top / k + dy,
            dst.left + l.bounds!.right / k,
            dst.top + l.bounds!.bottom / k + dy,
          );

    final drops = [
      (_seg(t, 0.02, 0.14), 40.0, Curves.easeOutCubic),
      (_seg(t, 0.18, 0.40), 150.0, Curves.bounceOut),
      (_seg(t, 0.44, 0.66), 170.0, Curves.bounceOut),
    ];
    final settled = _seg(t, 0.66, 0.74) * fade;

    // Ghost: where the tone mark would sit without the vowel — it would collide.
    final ghost = boundsOf(rs.layers[3], 0);
    final tone = boundsOf(rs.layers[2], 0);
    if (ghost != null && tone != null && (ghost.center.dy - tone.center.dy).abs() > 2 && settled > 0) {
      _dashRect(canvas, ghost.inflate(2), BP.red.withValues(alpha: settled * 0.9));
      drawArrow(
        canvas,
        Offset(ghost.right + 8, ghost.center.dy),
        Offset(tone.right + 8, tone.center.dy),
        Paint()
          ..color = BP.red.withValues(alpha: settled)
          ..strokeWidth = 1.3,
        head: 6,
      );
    }

    for (var li = 0; li < 3; li++) {
      final (p, from, curve) = drops[li];
      if (p <= 0) continue;
      final dy = -from * (1 - curve.transform(p));
      final alpha = math.min(1.0, p * 4) * fade;
      final layer = rs.layers[li];
      canvas.drawImageRect(
        layer.image,
        Rect.fromLTWH(0, 0, rs.w.toDouble(), rs.h.toDouble()),
        dst.shift(Offset(0, dy)),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..colorFilter = ColorFilter.mode(_colors[li].withValues(alpha: alpha), BlendMode.srcIn),
      );
      // Ink box + name once everything has landed.
      final b = boundsOf(layer, dy);
      if (b != null && settled > 0) {
        _dashRect(canvas, b.inflate(2), _colors[li].withValues(alpha: settled * 0.8));
      }
    }

    // Labels on the right, one per level.
    if (settled > 0) {
      final right = [
        for (var li = 0; li < 3; li++) boundsOf(rs.layers[li], 0),
      ].whereType<Rect>().fold<double>(0, (m, r) => math.max(m, r.right));
      final ys = <double>[];
      for (var li = 2; li >= 0; li--) {
        final b = boundsOf(rs.layers[li], 0);
        if (b == null) continue;
        var y = b.center.dy;
        if (ys.isNotEmpty && y < ys.last + 16) y = ys.last + 16;
        ys.add(y);
        final x = right + 34;
        canvas.drawLine(
          Offset(b.right + 4, b.center.dy),
          Offset(x - 4, y),
          _stroke(_colors[li].withValues(alpha: settled * 0.6)),
        );
        _label(
          canvas,
          _names[li],
          BT.mono(12, color: _colors[li].withValues(alpha: settled)),
          Offset(x, y),
          ax: 0,
          ay: 0.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_StackPainter old) => old.t != t || old.raster != raster || old.probe != probe;
}

// ─────────────────────────────────────────────────────────────────────────────
// 5 · no spaces — Thai word boundaries found by a dictionary scan
// ─────────────────────────────────────────────────────────────────────────────

class _NoSpaces extends StatefulWidget {
  const _NoSpaces();

  @override
  State<_NoSpaces> createState() => _NoSpacesState();
}

class _NoSpacesState extends State<_NoSpaces> with _FontAware {
  static const _text = 'ภาษาไทยไม่มีช่องว่าง';
  static const _cuts = [0, 4, 7, 10, 12, 16, 20];

  late TextProbe _probe;
  late List<Rect> _words;

  @override
  void initState() {
    super.initState();
    _make();
  }

  void _make() {
    var fs = 44.0;
    var p = TextProbe(TextSpan(text: _text, style: BT.sample(fs)));
    if (p.size.width > 290) {
      fs = fs * 290 / p.size.width;
      p.dispose();
      p = TextProbe(TextSpan(text: _text, style: BT.sample(fs)));
    }
    _probe = p;
    _words = [for (var i = 0; i < _cuts.length - 1; i++) p.rectFor(_cuts[i], _cuts[i + 1]) ?? Rect.zero];
  }

  @override
  void rebuildText() {
    _probe.dispose();
    _make();
  }

  @override
  void dispose() {
    _probe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LoopBuilder(
    period: const Duration(milliseconds: 5800),
    builder: (context, t, _) => CustomPaint(size: _design, painter: _NoSpacesPainter(_probe, _words, t)),
  );
}

class _NoSpacesPainter extends CustomPainter {
  _NoSpacesPainter(this.probe, this.words, this.t);

  final TextProbe probe;
  final List<Rect> words;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final ps = probe.size;
    final o = Offset((size.width - ps.width) / 2, 112 - ps.height / 2);
    final fade = _seg(t, 0, 0.06) * (1 - _seg(t, 0.92, 0.99));
    final scan = Curves.easeInOutSine.transform(_seg(t, 0.1, 0.66));
    final hx = o.dx + ps.width * scan;
    final spread = _ease(t, 0.7, 0.8) * (1 - _seg(t, 0.92, 0.99));
    final n = words.length;
    double dxOf(int i) => (i - (n - 1) / 2) * 10 * spread;

    // Text: one run, no spaces. Split apart at the found boundaries.
    if (spread <= 0) {
      _paintAlpha(canvas, probe.painter, o, fade);
    } else {
      for (var i = 0; i < n; i++) {
        final r = words[i].shift(o);
        canvas.save();
        canvas.translate(dxOf(i), 0);
        canvas.clipRect(Rect.fromLTRB(r.left, 0, r.right, size.height));
        _paintAlpha(canvas, probe.painter, o, fade);
        canvas.restore();
      }
    }

    for (var i = 0; i < n; i++) {
      final r = words[i].shift(o);
      final q = scan <= 0 ? 0.0 : ((hx - r.right + 1) / 18).clamp(0.0, 1.0) * fade;
      if (q <= 0) continue;
      final dx = dxOf(i);
      final c = (i.isEven ? Script.thai.color : BP.line).withValues(alpha: q);
      final y = r.bottom + 8;
      canvas.drawPath(
        Path()
          ..moveTo(r.left + 3 + dx, y - 6)
          ..lineTo(r.left + 3 + dx, y)
          ..lineTo(r.right - 3 + dx, y)
          ..lineTo(r.right - 3 + dx, y - 6),
        _stroke(c, 2),
      );
      if (i < n - 1) {
        final x = r.right + (dx + dxOf(i + 1)) / 2;
        final grow = Curves.easeOutBack.transform(q);
        final top = r.top - 16;
        _dashLine(
          canvas,
          Offset(x, top),
          Offset(x, top + (r.height + 32) * grow),
          BP.amber.withValues(alpha: q),
          width: 1.5,
        );
        _diamond(canvas, Offset(x, top), 4, BP.amber.withValues(alpha: q));
      }
    }

    // The dictionary scan head.
    if (scan > 0 && scan < 1 && fade > 0) {
      final top = o.dy + ps.height * 0.05 - 22;
      canvas.drawLine(
        Offset(hx, top),
        Offset(hx, o.dy + ps.height + 10),
        Paint()
          ..color = BP.amber.withValues(alpha: fade)
          ..strokeWidth = 2,
      );
      _label(
        canvas,
        'dictionary',
        BT.mono(11, color: BP.amber.withValues(alpha: fade)),
        Offset(hx, top - 4),
        ay: 1,
      );
    }
  }

  @override
  bool shouldRepaint(_NoSpacesPainter old) => old.t != t || old.probe != probe;
}

// ─────────────────────────────────────────────────────────────────────────────
// 6 · composition — Hangul jamo assemble into a syllable block
// ─────────────────────────────────────────────────────────────────────────────

class _Hangul extends StatelessWidget {
  const _Hangul();

  static const _jamo = ['ㅎ', 'ㅏ', 'ㄴ'];
  static const _chip = [Offset(84, 42), Offset(160, 42), Offset(236, 42)];
  static const _block = Rect.fromLTWH(100, 100, 120, 120);
  static const _slot = [
    Rect.fromLTWH(106, 106, 58, 56),
    Rect.fromLTWH(168, 106, 46, 56),
    Rect.fromLTWH(106, 166, 108, 48),
  ];
  static const _slotScale = [(1.2, 1.2), (1.0, 1.5), (1.9, 1.0)];

  @override
  Widget build(BuildContext context) => LoopBuilder(
    period: const Duration(milliseconds: 5800),
    builder: (context, t, _) {
      final chipsIn = _seg(t, 0, 0.08);
      final pos = _ease(t, 0.14, 0.40) * (1 - _ease(t, 0.78, 0.94));
      final merged = _seg(t, 0.40, 0.48) * (1 - _seg(t, 0.70, 0.78));
      final jamoColor = Script.hangul.color;
      return SizedBox.fromSize(
        size: _design,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _HangulGuides(chipsIn: chipsIn, pos: pos, merged: merged),
              ),
            ),
            for (var k = 0; k < 3; k++)
              _jamoAt(
                _jamo[k],
                Offset.lerp(_chip[k], _slot[k].center, pos)!,
                ui.lerpDouble(1, _slotScale[k].$1, pos)!,
                ui.lerpDouble(1, _slotScale[k].$2, pos)!,
                chipsIn * (1 - merged),
                jamoColor,
              ),
            Positioned.fromRect(
              rect: _block,
              child: Opacity(
                opacity: merged,
                child: Center(
                  child: Transform.scale(
                    scale: 0.9 + 0.1 * merged,
                    child: Text('한', style: BT.sample(92, color: BP.ink)),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: _block.bottom + 8,
              child: Opacity(
                opacity: merged,
                child: Text(
                  'U+D55C',
                  textAlign: TextAlign.center,
                  style: BT.mono(12, color: BP.amber),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  static Widget _jamoAt(String j, Offset c, double sx, double sy, double alpha, Color color) => Positioned(
    left: c.dx - 40,
    top: c.dy - 40,
    width: 80,
    height: 80,
    child: Opacity(
      opacity: alpha.clamp(0.0, 1.0),
      child: Center(
        child: Transform.scale(
          scaleX: sx,
          scaleY: sy,
          child: Text(j, style: BT.sample(38, color: color, height: 1)),
        ),
      ),
    ),
  );
}

class _HangulGuides extends CustomPainter {
  _HangulGuides({required this.chipsIn, required this.pos, required this.merged});

  final double chipsIn;
  final double pos;
  final double merged;

  @override
  void paint(Canvas canvas, Size size) {
    for (var k = 0; k < 3; k++) {
      _dashRect(
        canvas,
        Rect.fromCenter(center: _Hangul._chip[k], width: 56, height: 56),
        BP.lineDim.withValues(alpha: chipsIn),
      );
    }
    for (final x in [122.0, 198.0]) {
      _label(canvas, '+', BT.mono(18, color: BP.inkDim.withValues(alpha: chipsIn)), Offset(x, 42), ay: 0.5);
    }
    // Arrow between the jamo and the block, both ways.
    final arrow = Paint()
      ..color = BP.inkFaint
      ..strokeWidth = 1.2;
    canvas.drawLine(const Offset(160, 74), const Offset(160, 94), arrow);
    drawArrowHead(canvas, const Offset(160, 95), const Offset(160, 85), arrow, 5);
    drawArrowHead(canvas, const Offset(160, 73), const Offset(160, 83), arrow, 5);

    canvas.drawRect(_Hangul._block, _stroke(Color.lerp(BP.lineDim, BP.amber, merged)!, 1 + merged));
    final slotA = (0.25 + 0.75 * pos) * (1 - merged);
    for (final s in _Hangul._slot) {
      _dashRect(canvas, s, BP.lineDim.withValues(alpha: slotA), dash: 3, gap: 3);
    }
  }

  @override
  bool shouldRepaint(_HangulGuides old) => old.chipsIn != chipsIn || old.pos != pos || old.merged != merged;
}

// ─────────────────────────────────────────────────────────────────────────────
// 7 · vertical — Japanese in columns, top→bottom, right→left (illustration)
// ─────────────────────────────────────────────────────────────────────────────

class _Vertical extends StatefulWidget {
  const _Vertical();

  @override
  State<_Vertical> createState() => _VerticalState();
}

class _VerticalState extends State<_Vertical> with _FontAware {
  static const _text = '縦書きは右から左へ読む';
  late List<TextPainter> _chars;

  @override
  void initState() {
    super.initState();
    _make();
  }

  void _make() {
    _chars = [for (final c in _text.characters) _tp(c, BT.sample(30, color: BP.ink))];
  }

  void _free() {
    for (final c in _chars) {
      c.dispose();
    }
  }

  @override
  void rebuildText() {
    _free();
    _make();
  }

  @override
  void dispose() {
    _free();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LoopBuilder(
    period: const Duration(milliseconds: 6200),
    builder: (context, t, _) => CustomPaint(size: _design, painter: _VerticalPainter(_chars, t)),
  );
}

class _VerticalPainter extends CustomPainter {
  _VerticalPainter(this.chars, this.t);

  final List<TextPainter> chars;
  final double t;

  static const _cell = 46.0;
  static const _colGap = 14.0;
  static const _rows = 4;
  static const _cols = 3;
  static const _top = 36.0;

  @override
  void paint(Canvas canvas, Size size) {
    const gridW = _cols * _cell + (_cols - 1) * _colGap;
    final left = (size.width - gridW) / 2 - 8;
    double colX(int c) => left + (_cols - 1 - c) * (_cell + _colGap);
    final fade = 1 - _seg(t, 0.9, 0.98);

    // Manuscript grid
    for (var c = 0; c < _cols; c++) {
      for (var r = 0; r < _rows; r++) {
        canvas.drawRect(Rect.fromLTWH(colX(c), _top + r * _cell, _cell, _cell), _stroke(BP.lineFaint));
      }
    }

    // Reading-order arrows: columns go ←, characters go ↓.
    final guide = Paint()
      ..color = BP.amber.withValues(alpha: 0.7)
      ..strokeWidth = 1.3;
    drawArrow(
      canvas,
      Offset(colX(0) + _cell, _top - 16),
      Offset(colX(_cols - 1), _top - 16),
      guide,
      dashed: true,
      head: 6,
    );
    final ax = colX(0) + _cell + 16;
    drawArrow(canvas, Offset(ax, _top), Offset(ax, _top + _rows * _cell), guide, dashed: true, head: 6);

    var last = -1;
    for (var j = 0; j < chars.length; j++) {
      final s = 0.05 + j * 0.055;
      final p = _seg(t, s, s + 0.05);
      if (p <= 0) continue;
      last = j;
      final c = j ~/ _rows;
      final r = j % _rows;
      final cell = Rect.fromLTWH(colX(c), _top + r * _cell, _cell, _cell);
      final e = Curves.easeOutCubic.transform(p);
      _paintCentered(canvas, chars[j], cell.center - Offset(0, 8 * (1 - e)), 1, p * fade);
    }
    if (last >= 0 && fade > 0) {
      final c = last ~/ _rows;
      final r = last % _rows;
      canvas.drawRect(
        Rect.fromLTWH(colX(c), _top + r * _cell, _cell, _cell),
        _stroke(BP.amber.withValues(alpha: fade), 1.5),
      );
    }
  }

  @override
  bool shouldRepaint(_VerticalPainter old) => old.t != t || old.chars != chars;
}

// ─────────────────────────────────────────────────────────────────────────────
// 8 · combining — several code points become one emoji
// ─────────────────────────────────────────────────────────────────────────────

class _Emoji extends StatelessWidget {
  const _Emoji();

  static const _resultX = 266.0;

  @override
  Widget build(BuildContext context) => LoopBuilder(
    period: const Duration(milliseconds: 6400),
    builder: (context, t, _) {
      final fade = 1 - _seg(t, 0.9, 0.98);
      return SizedBox.fromSize(
        size: _design,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ..._row(
              t,
              fade,
              y: 66,
              start: 0.04,
              parts: const ['👋', '🏽'],
              xs: const [52, 116],
              result: '👋🏽',
              note: '2 → 1',
            ),
            ..._row(
              t,
              fade,
              y: 180,
              start: 0.40,
              parts: const ['👩', 'ZWJ', '💻'],
              xs: const [36, 94, 152],
              result: '👩‍💻',
              note: '3 → 1',
            ),
          ],
        ),
      );
    },
  );

  static List<Widget> _row(
    double t,
    double fade, {
    required double y,
    required double start,
    required List<String> parts,
    required List<double> xs,
    required String result,
    required String note,
  }) {
    final appear = _seg(t, start, start + 0.08) * fade;
    final merge = _ease(t, start + 0.12, start + 0.28);
    final pop = _seg(t, start + 0.26, start + 0.34);
    final partA = appear * (1 - _seg(merge, 0.7, 1));
    final flash = 1 - _seg(t, start + 0.34, start + 0.5);
    return [
      // Code point slots
      for (var k = 0; k < parts.length; k++)
        Positioned(
          left: xs[k] - (parts[k] == 'ZWJ' ? 22 : 27),
          top: y - 27,
          width: parts[k] == 'ZWJ' ? 44 : 54,
          height: 54,
          child: Opacity(
            opacity: appear * 0.9,
            child: CustomPaint(painter: DashedRectPainter(color: parts[k] == 'ZWJ' ? BP.amber : BP.lineDim)),
          ),
        ),
      Positioned(
        left: 184,
        top: y - 10,
        width: 40,
        height: 20,
        child: Opacity(
          opacity: appear,
          child: CustomPaint(painter: _ArrowPainter()),
        ),
      ),
      // Parts sliding into one cluster
      for (var k = 0; k < parts.length; k++)
        Positioned(
          left: ui.lerpDouble(xs[k], _resultX, merge)! - 40,
          top: y - 40,
          width: 80,
          height: 80,
          child: Opacity(
            opacity: partA.clamp(0.0, 1.0),
            child: Center(
              child: parts[k] == 'ZWJ'
                  ? Text('ZWJ', style: BT.mono(12, color: BP.amber, weight: 600))
                  : Text(parts[k], style: BT.sample(34, height: 1)),
            ),
          ),
        ),
      // Result
      Positioned(
        left: _resultX - 34,
        top: y - 34,
        width: 68,
        height: 68,
        child: Opacity(
          opacity: (pop * fade).clamp(0.0, 1.0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: BP.amber.withValues(alpha: 0.12 * flash),
              border: Border.all(color: Color.lerp(BP.line, BP.amber, flash)!, width: 1 + flash),
            ),
            child: Center(
              child: Transform.scale(
                scale: 0.6 + 0.4 * Curves.easeOutBack.transform(pop),
                child: Text(result, style: BT.sample(40, height: 1)),
              ),
            ),
          ),
        ),
      ),
      Positioned(
        left: _resultX - 40,
        top: y + 38,
        width: 80,
        child: Opacity(
          opacity: (pop * fade).clamp(0.0, 1.0),
          child: Text(
            note,
            textAlign: TextAlign.center,
            style: BT.mono(12, color: BP.amber),
          ),
        ),
      ),
    ];
  }
}

class _ArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    drawArrow(
      canvas,
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = BP.inkDim
        ..strokeWidth = 1.3,
      dashed: true,
      head: 6,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => false;
}
