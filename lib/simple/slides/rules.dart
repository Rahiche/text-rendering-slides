import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../deck/scripts.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Grid: 3 × 2 large panels, each a big glyph demo + one short label.
// ─────────────────────────────────────────────────────────────────────────────

/// Every demo is drawn on this design canvas and scaled to its panel.
const _dw = 440.0;
const _dh = 236.0;
const _design = Size(_dw, _dh);

/// Panels stop short of the content area's bottom: the conveyor ruler.
const _areaH = 612.0;
const _gapX = 28.0;
const _gapY = 44.0;
const _panelTop = 18.0;
const _panelW = (1472 - 2 * _gapX) / 3;
const _panelH = (_areaH - _panelTop - _gapY) / 2;
const _bigH = _areaH - _panelTop;
const _bigW = _bigH * _panelW / _panelH;
const _pad = EdgeInsets.fromLTRB(16, 26, 16, 12);

/// Every demo loops on the same clock: it builds up in ~3 s, holds the
/// finished picture until [_holdEnd], fades, and starts again.
const _period = 8.0;
const _holdEnd = 7.3;

class _Rule {
  const _Rule(this.label, this.color, this.build);

  final String label;
  final Color color;
  final Widget Function() build;
}

final _rules = <_Rule>[
  _Rule('right-to-left', Script.hebrew.color, () => const _Direction()),
  _Rule('joining', Script.arabic.color, () => const _Forms()),
  _Rule('reordering', Script.devanagari.color, () => const _Reorder()),
  _Rule('stacking', Script.thai.color, () => const _Stacking()),
  _Rule('composition', Script.hangul.color, () => const _Hangul()),
  _Rule('vertical · 縦書き', Script.kana.color, () => const _Vertical()),
];

/// Six scripts, six broken assumptions. Click a panel to enlarge + replay.
class ScriptRulesSlide extends StatefulWidget {
  const ScriptRulesSlide({super.key});

  @override
  State<ScriptRulesSlide> createState() => _ScriptRulesSlideState();
}

class _ScriptRulesSlideState extends State<ScriptRulesSlide> {
  int? _big;
  int _top = 0;
  int? _hover;
  final _nonce = List<int>.filled(_rules.length, 0);

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
    if (_big == i) return const Rect.fromLTWH((1472 - _bigW) / 2, _panelTop, _bigW, _bigH);
    final c = i % 3;
    final r = i ~/ 3;
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
            child: CustomPaint(
              painter: _PanelPainter(hot ? rule.color : BP.lineDim),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Tight constraints so the design canvas scales up when enlarged.
                  Positioned.fill(
                    child: Padding(
                      padding: _pad,
                      child: FittedBox(
                        child: SizedBox.fromSize(
                          size: _design,
                          child: KeyedSubtree(key: ValueKey(_nonce[i]), child: rule.build()),
                        ),
                      ),
                    ),
                  ),
                  // The label, notched into the top edge.
                  Positioned(
                    left: 18,
                    top: -17,
                    child: Container(
                      color: BP.paper,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(rule.label, style: BT.display(24, color: rule.color)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opaque blueprint panel (panels overlap while one is enlarged).
class _PanelPainter extends CustomPainter {
  _PanelPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = BP.paper);
    canvas.drawRect(r, Paint()..color = BP.panel.withValues(alpha: 0.85));
    canvas.drawRect(r, _stroke(color, color == BP.lineDim ? 1 : 1.6));
    final t = Paint()
      ..color = BP.line
      ..strokeWidth = 2;
    const l = 10.0;
    for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      final dx = c.dx == 0 ? l : -l;
      final dy = c.dy == 0 ? l : -l;
      canvas.drawLine(c, c + Offset(dx, 0), t);
      canvas.drawLine(c, c + Offset(0, dy), t);
    }
  }

  @override
  bool shouldRepaint(_PanelPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// The shared demo clock, in seconds since the demo appeared (0 … [_period]).
class _Clock extends StatelessWidget {
  const _Clock({required this.builder});

  final Widget Function(BuildContext context, double s) builder;

  @override
  Widget build(BuildContext context) => LoopBuilder(
    period: Duration(milliseconds: (_period * 1000).round()),
    builder: (context, t, _) => builder(context, t * _period),
  );
}

/// 1 while the finished picture holds, fading to 0 before the loop restarts.
double _out(double s) => 1 - _seg(s, _holdEnd, _holdEnd + 0.5);

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

void _dashRect(Canvas c, Rect r, Color color, {double width = 1, double dash = 5, double gap = 4}) =>
    c.drawPath(dashPath(Path()..addRect(r), dash: dash, gap: gap), _stroke(color, width));

void _dashLine(
  Canvas c,
  Offset a,
  Offset b,
  Color color, {
  double width = 1,
  double dash = 5,
  double gap = 4,
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
// 1 · right-to-left — Hebrew typed from the right
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
    final style = BT.sample(112, weight: 500, height: 1.1);
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
  Widget build(BuildContext context) => _Clock(
    builder: (context, s) => CustomPaint(size: _design, painter: _DirectionPainter(_probe, _letters, s)),
  );
}

class _DirectionPainter extends CustomPainter {
  _DirectionPainter(this.probe, this.letters, this.s);

  final TextProbe probe;
  final List<TextPainter> letters;
  final double s;

  static const _starts = [0.4, 0.95, 1.5, 2.05];

  @override
  void paint(Canvas canvas, Size size) {
    final w = probe.size.width;
    final lines = probe.lines;
    if (lines.isEmpty) return;
    final o = Offset((size.width - w) / 2, 88 - probe.size.height / 2);
    final baseY = o.dy + lines.first.baseline;
    final fade = _out(s);

    _dashLine(canvas, Offset(10, baseY), Offset(size.width - 10, baseY), BP.lineFaint);

    var caretX = o.dx + w;
    var typed = 0;
    var boxBottom = o.dy + probe.size.height;
    var boxTop = o.dy;
    for (var i = 0; i < letters.length; i++) {
      final boxes = probe.boxes(i, i + 1);
      if (boxes.isEmpty) continue;
      final box = boxes.first.toRect().shift(o);
      boxTop = box.top;
      boxBottom = box.bottom;
      final p = _seg(s, _starts[i], _starts[i] + 0.35);
      caretX = ui.lerpDouble(caretX, box.left, Curves.easeOutCubic.transform(p))!;
      if (p <= 0) continue;
      typed = i + 1;
      final a = p * fade;
      final e = Curves.easeOutBack.transform(p);
      _dashRect(canvas, box, BP.lineDim.withValues(alpha: a));
      final l = letters[i];
      _paintAlpha(canvas, l, Offset(box.left + (box.width - l.width) / 2, o.dy - (1 - e) * 22), a);
    }

    // Typing direction: an arrow growing leftwards behind the caret.
    if (typed > 0 && fade > 0) {
      final y = boxBottom + 30;
      drawArrow(
        canvas,
        Offset(o.dx + w + 10, y),
        Offset(caretX - 6, y),
        Paint()
          ..color = BP.amber.withValues(alpha: fade)
          ..strokeWidth = 3,
        head: 14,
      );
    }

    // Caret
    if (fade > 0 && s > 0.2) {
      canvas.drawRect(
        Rect.fromLTRB(caretX - 2, boxTop, caretX + 2, boxBottom),
        Paint()..color = BP.amber.withValues(alpha: fade),
      );
    }
  }

  @override
  bool shouldRepaint(_DirectionPainter old) => old.s != s || old.probe != probe;
}

// ─────────────────────────────────────────────────────────────────────────────
// 2 · joining — Arabic ع takes four shapes (forced with ZWJ)
// ─────────────────────────────────────────────────────────────────────────────

TextStyle _kufi(double size, Color color) =>
    TextStyle(fontFamily: BP.arabic, fontSize: size, color: color, height: 1.25);

/// One letter, four shapes, side by side in reading order (right to left).
/// The highlight walks isolated → initial → medial → final; each shape shows
/// the sides where it joins its neighbours.
class _Forms extends StatelessWidget {
  const _Forms();

  @override
  Widget build(BuildContext context) => LoopBuilder(
    period: const Duration(milliseconds: 8000),
    // Offset by half a step so a form is fully lit at ~4.2 s (the export still).
    builder: (context, t, _) => CustomPaint(size: _design, painter: _FormsPainter((t * 4 + 0.5) % 4)),
  );
}

class _FormsPainter extends CustomPainter {
  _FormsPainter(this.pos);

  /// 0..4: which form is lit (fractional while the highlight moves on).
  final double pos;

  static const _forms = ['ع', 'ع‍', '‍ع‍', '‍ع'];
  static const _cellW = 98.0;
  static const _cellGap = 12.0;
  static const _top = 14.0;
  static const _cellH = 184.0;
  static const _baseY = _top + 124;
  static const _fs = 88.0;

  /// Cells laid out right-to-left: isolated is rightmost, like reading order.
  static double _cellX(int k) {
    const row = 4 * _cellW + 3 * _cellGap;
    const left = (_dw - row) / 2;
    return left + (3 - k) * (_cellW + _cellGap);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final i = pos.floor().clamp(0, 3);
    final m = Curves.easeInOutCubic.transform(_seg(pos - i, 0.85, 1));
    final next = (i + 1) % 4;

    for (var k = 0; k < 4; k++) {
      final lit = k == i ? 1 - m : (k == next ? m : 0.0);
      final cell = Rect.fromLTWH(_cellX(k), _top, _cellW, _cellH);
      canvas.drawRect(cell, Paint()..color = Color.lerp(BP.panel, BP.amber.withValues(alpha: 0.12), lit)!);
      canvas.drawRect(cell, _stroke(Color.lerp(BP.lineDim, BP.amber, lit)!, 1 + lit));
      _dashLine(
        canvas,
        Offset(cell.left + 4, _baseY),
        Offset(cell.right - 4, _baseY),
        Color.lerp(BP.lineFaint, BP.amber.withValues(alpha: 0.6), lit)!,
      );

      final tp = TextPainter(
        text: TextSpan(text: _forms[k], style: _kufi(_fs, Color.lerp(BP.inkDim, BP.ink, lit)!)),
        textDirection: TextDirection.rtl,
      )..layout();
      final base = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      final s = 1 + 0.08 * Curves.easeOut.transform(lit);
      canvas.save();
      canvas.translate(cell.center.dx, _baseY);
      canvas.scale(s);
      tp.paint(canvas, Offset(-tp.width / 2, -base));
      canvas.restore();
      tp.dispose();

      // Where this form joins its neighbours (RTL: the next letter is to the left).
      final joinLeft = k == 1 || k == 2;
      final joinRight = k == 2 || k == 3;
      final c = Color.lerp(BP.lineDim, BP.amber, lit)!;
      if (joinLeft) _diamond(canvas, Offset(cell.left, _baseY), 6 + 2 * lit, c);
      if (joinRight) _diamond(canvas, Offset(cell.right, _baseY), 6 + 2 * lit, c);
    }

    // The highlight bar under the lit form.
    final x = ui.lerpDouble(_cellX(i), _cellX(next), m)!;
    canvas.drawRect(Rect.fromLTWH(x, _top + _cellH + 10, _cellW, 5), Paint()..color = BP.amber);
  }

  @override
  bool shouldRepaint(_FormsPainter old) => old.pos != pos;
}

// ─────────────────────────────────────────────────────────────────────────────
// 3 · reordering — Devanagari कि: the vowel sign is stored after, drawn before
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
    _word = TextProbe(TextSpan(text: 'कि', style: BT.sample(96, height: 1.15)));
    _ka = _tp('क', BT.sample(46));
    _i = _tp('ि', BT.sample(46, color: Script.devanagari.color));
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
  Widget build(BuildContext context) => _Clock(
    builder: (context, s) => CustomPaint(size: _design, painter: _ReorderPainter(_word, _ka, _i, s)),
  );
}

class _ReorderPainter extends CustomPainter {
  _ReorderPainter(this.word, this.ka, this.i, this.s);

  final TextProbe word;
  final TextPainter ka;
  final TextPainter i;
  final double s;

  static const _cx = 262.0;
  static const _memY = 42.0;
  static const _screenY = 174.0;

  @override
  void paint(Canvas canvas, Size size) {
    final vColor = Script.devanagari.color;
    final chipsIn = _seg(s, 0.2, 0.7);
    final fly = _ease(s, 1.0, 2.4);
    final land = _seg(s, 1.9, 2.7);
    final fade = _out(s);

    // Row labels
    _label(canvas, 'memory', BT.mono(18, color: BP.inkDim), const Offset(0, _memY), ax: 0, ay: 0.5);
    _label(canvas, 'screen', BT.mono(18, color: BP.inkDim), const Offset(0, _screenY), ax: 0, ay: 0.5);

    // Memory: two code points in logical order.
    final kaChip = Rect.fromCenter(center: const Offset(_cx - 46, _memY), width: 80, height: 80);
    final iChip = Rect.fromCenter(center: const Offset(_cx + 46, _memY), width: 80, height: 80);
    final a = chipsIn * fade;
    if (a > 0) {
      canvas.drawRect(kaChip, _stroke(BP.lineDim.withValues(alpha: a), 1.2));
      canvas.drawRect(iChip, _stroke(vColor.withValues(alpha: a), 2));
      // The glyphs leave their slots while in flight, and are back once landed.
      final away = 1 - 0.8 * math.min(1.0, fly * 4) * (1 - land);
      _paintCentered(canvas, ka, kaChip.center, 1, a * away);
      _paintCentered(canvas, i, iChip.center, 1, a * away);
    }

    // Screen: the real shaped cluster.
    final ws = word.size;
    final wo = Offset(_cx - ws.width / 2, _screenY - ws.height / 2);
    final r = word.rectFor(0, 2)?.shift(wo) ?? (wo & ws);
    final kaTarget = Offset(r.left + r.width * 0.64, r.center.dy);
    final iTarget = Offset(r.left + r.width * 0.24, r.center.dy);

    // Crossing construction lines: memory order ≠ visual order.
    if (fly > 0 && fade > 0) {
      final kaFrom = kaChip.bottomCenter;
      final iFrom = iChip.bottomCenter;
      final kaTo = Offset(kaTarget.dx, r.top);
      final iTo = Offset(iTarget.dx, r.top);
      _dashLine(canvas, kaFrom, Offset.lerp(kaFrom, kaTo, fly)!, BP.line.withValues(alpha: 0.7 * fade), width: 1.5);
      _dashLine(canvas, iFrom, Offset.lerp(iFrom, iTo, fly)!, vColor.withValues(alpha: 0.9 * fade), width: 2);
    }

    // Flying copies grow and dissolve into the real cluster as they arrive.
    final scale = ui.lerpDouble(1, 2, fly)!;
    final copyA = fly > 0 ? (1 - _seg(fly, 0.5, 0.95)) * fade : 0.0;
    if (copyA > 0) {
      final kaPos = Offset.lerp(kaChip.center, kaTarget, fly)!;
      final arc = -math.sin(fly * math.pi) * 30;
      final iPos = Offset.lerp(iChip.center, iTarget, fly)! + Offset(0, arc);
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
  bool shouldRepaint(_ReorderPainter old) => old.s != s || old.word != word;
}

// ─────────────────────────────────────────────────────────────────────────────
// 4 · stacking — Thai ป + ั + ่: marks drop onto the base and stack.
//
// The pieces are cut out of the engine's own rendering: we rasterize ป, ปั and
// ปั่ and subtract, so every mark lands exactly where HarfBuzz put it.
// ─────────────────────────────────────────────────────────────────────────────

/// Max filter with radius [r] (separable), on an alpha mask.
Uint8List _grow(Uint8List a, int w, int h, int r) {
  final tmp = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var m = 0;
      for (var d = math.max(0, x - r); d <= math.min(w - 1, x + r); d++) {
        m = math.max(m, a[y * w + d]);
      }
      tmp[y * w + x] = m;
    }
  }
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var m = 0;
      for (var d = math.max(0, y - r); d <= math.min(h - 1, y + r); d++) {
        m = math.max(m, tmp[d * w + x]);
      }
      out[y * w + x] = m;
    }
  }
  return out;
}

/// [a] where [mask] is (nearly) empty.
Uint8List _minus(Uint8List a, Uint8List mask) {
  final out = Uint8List(a.length);
  for (var i = 0; i < a.length; i++) {
    out[i] = mask[i] > 24 ? 0 : a[i];
  }
  return out;
}

class _Layer {
  _Layer(this.image, this.bounds);

  final ui.Image image;

  /// Ink bounds in raster pixels, or null if the layer is empty.
  final Rect? bounds;

  static Future<_Layer> make(Uint8List a, int w, int h) async {
    final px = Uint8List(w * h * 4);
    var minX = w, minY = h, maxX = -1, maxY = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        var v = a[i];
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

  /// base, vowel, tone.
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
      for (final s in const ['ป', 'ปั', 'ปั่']) _tp(s, style),
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
    // Each piece = the longer string minus the shorter one. Subtracting a
    // slightly grown copy of the shorter one drops the anti-aliasing fringe.
    final r = (k * 3).ceil();
    final layers = [
      await _Layer.make(alphas[0], w, h),
      await _Layer.make(_minus(alphas[1], _grow(alphas[0], w, h, r)), w, h),
      await _Layer.make(_minus(alphas[2], _grow(alphas[1], w, h, r)), w, h),
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
  static const _size = 190.0;
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
    final r = await _Raster.build(_size, 2);
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
    child: _Clock(
      builder: (context, s) => CustomPaint(size: _design, painter: _StackPainter(_probe, _raster, s)),
    ),
  );
}

class _StackPainter extends CustomPainter {
  _StackPainter(this.probe, this.raster, this.s);

  final TextProbe probe;
  final _Raster? raster;
  final double s;

  static final _colors = [BP.ink, Script.thai.color, BP.amber];

  @override
  void paint(Canvas canvas, Size size) {
    final ps = probe.size;
    final lines = probe.lines;
    if (lines.isEmpty) return;
    // Sit the baseline low in the panel: the marks stack upwards.
    const by = 222.0;
    final o = Offset((size.width - ps.width) / 2, by - lines.first.baseline);
    final fade = _out(s);
    final rs = raster;

    _dashLine(canvas, Offset(10, by), Offset(size.width - 10, by), BP.lineFaint);

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
      (_seg(s, 0.2, 0.8), 50.0, Curves.easeOutCubic),
      (_seg(s, 1.0, 2.0), 170.0, Curves.bounceOut),
      (_seg(s, 2.1, 3.1), 190.0, Curves.bounceOut),
    ];
    final settled = _seg(s, 3.1, 3.5) * fade;

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
      // Ink box once everything has landed.
      final b = boundsOf(layer, dy);
      if (b != null && settled > 0) {
        _dashRect(canvas, b.inflate(3), _colors[li].withValues(alpha: settled * 0.8), width: 1.3);
      }
    }
  }

  @override
  bool shouldRepaint(_StackPainter old) => old.s != s || old.raster != raster || old.probe != probe;
}

// ─────────────────────────────────────────────────────────────────────────────
// 5 · composition — Hangul jamo assemble into one syllable block
// ─────────────────────────────────────────────────────────────────────────────

class _Hangul extends StatelessWidget {
  const _Hangul();

  static const _jamo = ['ㅎ', 'ㅏ', 'ㄴ'];
  static const _chipY = 36.0;
  static const _chip = [Offset(128, _chipY), Offset(220, _chipY), Offset(312, _chipY)];
  static const _block = Rect.fromLTWH(154, 96, 132, 132);
  static const _slot = [
    Rect.fromLTWH(160, 102, 64, 62),
    Rect.fromLTWH(228, 102, 52, 62),
    Rect.fromLTWH(160, 168, 120, 54),
  ];
  static const _slotScale = [(1.2, 1.2), (1.0, 1.5), (1.9, 1.0)];

  @override
  Widget build(BuildContext context) => _Clock(
    builder: (context, s) {
      final fade = _out(s);
      final chipsIn = _seg(s, 0.2, 0.6) * fade;
      final pos = _ease(s, 0.9, 2.2);
      final merged = _seg(s, 2.3, 2.9) * fade;
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
            // The jamo stay in their slots (dimmed) while copies fly into the block.
            for (var k = 0; k < 3; k++)
              _jamoAt(_jamo[k], _chip[k], 1, 1, chipsIn * (pos > 0 ? 0.55 : 1), jamoColor),
            if (pos > 0)
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
                    child: Text('한', style: BT.sample(100, color: BP.ink, height: 1.1)),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  static Widget _jamoAt(String j, Offset c, double sx, double sy, double alpha, Color color) => Positioned(
    left: c.dx - 45,
    top: c.dy - 45,
    width: 90,
    height: 90,
    child: Opacity(
      opacity: alpha.clamp(0.0, 1.0),
      child: Center(
        child: Transform.scale(
          scaleX: sx,
          scaleY: sy,
          child: Text(j, style: BT.sample(44, color: color, height: 1)),
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
        Rect.fromCenter(center: _Hangul._chip[k], width: 66, height: 66),
        BP.lineDim.withValues(alpha: chipsIn),
      );
    }
    for (var k = 0; k < 2; k++) {
      final x = (_Hangul._chip[k].dx + _Hangul._chip[k + 1].dx) / 2;
      _label(
        canvas,
        '+',
        BT.mono(26, color: BP.inkDim.withValues(alpha: chipsIn)),
        Offset(x, _Hangul._chipY),
        ay: 0.5,
      );
    }
    // Arrow from the jamo down to the block.
    final arrow = Paint()
      ..color = BP.inkDim.withValues(alpha: chipsIn)
      ..strokeWidth = 1.6;
    drawArrow(canvas, const Offset(220, 72), Offset(220, _Hangul._block.top - 4), arrow, head: 7);

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
// 6 · vertical — Japanese in columns, top→bottom, right→left
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
    _chars = [for (final c in _text.characters) _tp(c, BT.sample(38, color: BP.ink))];
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
  Widget build(BuildContext context) => _Clock(
    builder: (context, s) => CustomPaint(size: _design, painter: _VerticalPainter(_chars, s)),
  );
}

class _VerticalPainter extends CustomPainter {
  _VerticalPainter(this.chars, this.s);

  final List<TextPainter> chars;
  final double s;

  static const _cell = 50.0;
  static const _colGap = 14.0;
  static const _rows = 4;
  static const _cols = 3;
  static const _top = 26.0;

  @override
  void paint(Canvas canvas, Size size) {
    const gridW = _cols * _cell + (_cols - 1) * _colGap;
    final left = (size.width - gridW) / 2 - 10;
    double colX(int c) => left + (_cols - 1 - c) * (_cell + _colGap);
    final fade = _out(s);

    // Manuscript grid
    for (var c = 0; c < _cols; c++) {
      for (var r = 0; r < _rows; r++) {
        canvas.drawRect(Rect.fromLTWH(colX(c), _top + r * _cell, _cell, _cell), _stroke(BP.lineFaint, 1.2));
      }
    }

    // Reading-order arrows: characters go ↓, columns go ←.
    final guide = Paint()
      ..color = BP.amber.withValues(alpha: 0.8)
      ..strokeWidth = 2;
    drawArrow(
      canvas,
      Offset(colX(0) + _cell, _top - 14),
      Offset(colX(_cols - 1), _top - 14),
      guide,
      dashed: true,
      head: 9,
    );
    final ax = colX(0) + _cell + 18;
    drawArrow(canvas, Offset(ax, _top), Offset(ax, _top + _rows * _cell), guide, dashed: true, head: 9);

    var last = -1;
    for (var j = 0; j < chars.length; j++) {
      final st = 0.3 + j * 0.22;
      final p = _seg(s, st, st + 0.3);
      if (p <= 0) continue;
      last = j;
      final c = j ~/ _rows;
      final r = j % _rows;
      final cell = Rect.fromLTWH(colX(c), _top + r * _cell, _cell, _cell);
      final e = Curves.easeOutCubic.transform(p);
      _paintCentered(canvas, chars[j], cell.center - Offset(0, 10 * (1 - e)), 1, p * fade);
    }
    if (last >= 0 && fade > 0) {
      final c = last ~/ _rows;
      final r = last % _rows;
      canvas.drawRect(
        Rect.fromLTWH(colX(c), _top + r * _cell, _cell, _cell),
        _stroke(BP.amber.withValues(alpha: fade), 2),
      );
    }
  }

  @override
  bool shouldRepaint(_VerticalPainter old) => old.s != s || old.chars != chars;
}
