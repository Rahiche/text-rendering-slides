import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'noir_kit.dart';

/// Clue 4: the accomplice. One Pan-CJK font holds every regional form; the
/// OpenType `locl` feature, keyed by the language tag given to the shaper,
/// picks which one U+76F4 becomes. Poke: switch the language tag.
class LoclClueSlide extends StatefulWidget {
  const LoclClueSlide({super.key});

  @override
  State<LoclClueSlide> createState() => _LoclClueSlideState();
}

/// BCP 47 language → OpenType language system tag → regional form.
const _systems = [
  ('ja', 'JAN', 'JP'),
  ('zh-Hans', 'ZHS', 'SC'),
  ('zh-Hant', 'ZHT', 'TC'),
  ('zh-HK', 'ZHH', 'HK'),
  ('ko', 'KOR', 'KR'),
];

class _LoclClueSlideState extends State<LoclClueSlide> {
  int _sel = 0;
  double _changedAt = 0;
  bool _touched = false;
  Timer? _auto;
  final _labels = LabelCache();

  @override
  void initState() {
    super.initState();
    // Until the presenter picks one, alternate ja ↔ zh-Hans.
    _auto = Timer.periodic(const Duration(milliseconds: 3200), (_) {
      if (!_touched && mounted) _select(_sel == 0 ? 1 : 0, user: false);
    });
  }

  void _select(int i, {bool user = true}) {
    setState(() {
      _sel = i;
      _changedAt = noirSeconds;
      if (user) _touched = true;
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _labels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideFrame(
      title: 'The accomplice: locl',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('language', style: BT.mono(14, color: BP.inkDim)),
          const SizedBox(width: 12),
          BpSegmented<int>(
            values: const [0, 1, 2, 3, 4],
            selected: _sel,
            color: BP.amber,
            labelOf: (i) => _systems[i].$1,
            onChanged: _select,
          ),
        ],
      ),
      child: ElapsedBuilder(
        builder: (context, _) => CustomPaint(
          painter: _LoclPainter(sel: _sel, age: noirSeconds - _changedAt, clock: noirSeconds, labels: _labels),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _LoclPainter extends CustomPainter {
  _LoclPainter({required this.sel, required this.age, required this.clock, required this.labels});

  final int sel;
  final double age;
  final double clock;
  final LabelCache labels;

  static const _file = Rect.fromLTWH(430, 40, 640, 490);
  static const _out = Rect.fromLTWH(1180, 150, 292, 300);

  TextPainter _t(String s, TextStyle st) => labels.get(s, st);

  @override
  void paint(Canvas canvas, Size size) {
    final (lang, tag, region) = _systems[sel];
    final ink = Paint()
      ..color = BP.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final dim = Paint()
      ..color = BP.lineDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Input: the code point + the language tag, into the shaper.
    final inBox = const Rect.fromLTWH(0, 150, 230, 300);
    canvas.drawRect(inBox, Paint()..color = BP.panel);
    canvas.drawRect(inBox, dim);
    _t('shaper input', BT.mono(14, color: BP.inkDim)).paint(canvas, inBox.topLeft + const Offset(0, -26));
    final g = _t('直', NT.jp(96, color: BP.ink));
    g.paint(canvas, Offset(inBox.center.dx - g.width / 2, inBox.top + 26));
    _t(hexOf(caseCp), BT.mono(16, color: BP.inkDim)).paint(canvas, Offset(inBox.left + 20, inBox.top + 160));
    final lt = _t('lang: $lang', BT.mono(18, color: BP.amber));
    final lr = Rect.fromLTWH(inBox.left + 16, inBox.top + 206, lt.width + 34, lt.height + 10);
    paintTag(canvas, lr, color: BP.amber);
    lt.paint(canvas, Offset(lr.left + 26, lr.top + 5));
    _t('→ $tag', BT.mono(18, color: BP.amber)).paint(canvas, Offset(inBox.left + 20, inBox.top + 252));

    // HarfBuzz gear between input and font.
    final gc = Offset((inBox.right + _file.left) / 2, inBox.center.dy);
    _gear(canvas, gc, 46, clock * 0.9);
    _t('HarfBuzz', BT.mono(14, color: BP.line)).paint(canvas, gc + const Offset(-34, 60));
    drawArrow(canvas, Offset(inBox.right + 6, gc.dy), gc - const Offset(56, 0), Paint()
      ..color = BP.lineDim
      ..strokeWidth = 1.2);
    drawArrow(canvas, gc + const Offset(56, 0), Offset(_file.left - 6, gc.dy), Paint()
      ..color = BP.lineDim
      ..strokeWidth = 1.2);

    // The font file: one Pan-CJK font.
    final fold = Path()
      ..moveTo(_file.left, _file.top)
      ..lineTo(_file.right - 40, _file.top)
      ..lineTo(_file.right, _file.top + 40)
      ..lineTo(_file.right, _file.bottom)
      ..lineTo(_file.left, _file.bottom)
      ..close();
    canvas.drawPath(fold, Paint()..color = BP.panel);
    canvas.drawPath(fold, ink);
    canvas.drawLine(Offset(_file.right - 40, _file.top), Offset(_file.right - 40, _file.top + 40), dim);
    canvas.drawLine(Offset(_file.right - 40, _file.top + 40), Offset(_file.right, _file.top + 40), dim);
    _t('Pan-CJK · one font', BT.mono(16, color: BP.line)).paint(canvas, _file.topLeft + const Offset(24, 20));

    // cmap: one code point → one default glyph.
    final cy = _file.top + 76.0;
    _t('cmap', BT.mono(14, color: BP.inkFaint)).paint(canvas, Offset(_file.left + 24, cy));
    _t('${hexOf(caseCp)}  →  default glyph', BT.mono(17, color: BP.ink)).paint(canvas, Offset(_file.left + 110, cy - 2));
    canvas.drawLine(Offset(_file.left + 24, cy + 40), Offset(_file.right - 24, cy + 40), dim);

    // GSUB locl: one row per language system.
    final gy = cy + 58;
    _t('GSUB · locl', BT.mono(14, color: BP.inkFaint)).paint(canvas, Offset(_file.left + 24, gy));
    final flash = segOut(age, 0, 0.5);
    for (var i = 0; i < _systems.length; i++) {
      final (_, t2, reg) = _systems[i];
      final y = gy + 34 + i * 62.0;
      final on = i == sel;
      final row = Rect.fromLTWH(_file.left + 20, y, _file.width - 40, 50);
      if (on) {
        canvas.drawRect(row, Paint()..color = BP.amber.withValues(alpha: 0.08 + 0.12 * (1 - flash)));
        canvas.drawRect(row, Paint()
          ..color = BP.amber
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
      }
      _t(t2, BT.mono(20, color: on ? BP.amber : BP.inkDim, weight: on ? 600 : 400)).paint(canvas, Offset(row.left + 16, y + 12));
      _t('default  →  $reg form', BT.mono(17, color: on ? BP.ink : BP.inkFaint)).paint(canvas, Offset(row.left + 110, y + 14));
      if (i < 2) {
        final mini = _t('直', i == 0 ? NT.caseJP(36, color: on ? BP.line : BP.lineDim) : NT.caseSC(36, color: on ? BP.amber : BP.lineDim));
        mini.paint(canvas, Offset(row.right - 56, y + 7));
      }
    }

    // Output: the regional glyph.
    drawArrow(canvas, Offset(_file.right + 8, _out.center.dy), Offset(_out.left - 8, _out.center.dy), Paint()
      ..color = BP.amber
      ..strokeWidth = 1.5);
    canvas.drawRect(_out, Paint()..color = BP.panel);
    canvas.drawRect(_out, Paint()
      ..color = sel < 2 ? (sel == 0 ? BP.line : BP.amber) : BP.lineDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
    _t('$region form', BT.mono(16, color: BP.ink)).paint(canvas, _out.topLeft + const Offset(0, -28));
    final pop = Curves.easeOutBack.transform(segOut(age, 0, 0.45));
    if (sel < 2) {
      final big = _t('直', sel == 0 ? NT.caseJP(210, color: BP.line) : NT.caseSC(210, color: BP.amber));
      canvas.save();
      canvas.translate(_out.center.dx, _out.center.dy);
      canvas.scale(0.7 + 0.3 * pop);
      big.paint(canvas, Offset(-big.width / 2, -big.height / 2));
      canvas.restore();
    } else {
      final r = _out.deflate(40);
      canvas.drawPath(dashPath(Path()..addRect(r), dash: 6, gap: 5), dim);
      final n = _t('not in demo', BT.mono(14, color: BP.inkFaint));
      n.paint(canvas, r.center - Offset(n.width / 2, n.height / 2));
    }
    _t('demo: Noto Sans JP / SC', BT.mono(12, color: BP.inkFaint)).paint(canvas, _out.bottomLeft + const Offset(0, 14));
  }

  void _gear(Canvas canvas, Offset c, double r, double a) {
    final p = Path();
    const teeth = 10;
    for (var i = 0; i < teeth * 2; i++) {
      final ang = a + i * math.pi / teeth;
      final rr = i.isEven ? r : r * 0.8;
      final q = c + Offset(math.cos(ang), math.sin(ang)) * rr;
      if (i == 0) {
        p.moveTo(q.dx, q.dy);
      } else {
        p.lineTo(q.dx, q.dy);
      }
    }
    p.close();
    canvas.drawPath(p, Paint()..color = BP.paper);
    canvas.drawPath(p, Paint()
      ..color = BP.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
    canvas.drawCircle(c, r * 0.3, Paint()
      ..color = BP.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_LoclPainter old) => true;
}
