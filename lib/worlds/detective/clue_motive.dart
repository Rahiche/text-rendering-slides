import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'noir_kit.dart';

/// Clue 5: the motive. The phone says ja-JP, but MaterialApp only supports
/// what it's told — by default `[Locale('en', 'US')]` — so Localizations,
/// RichText and the paragraph all carry en-US into font fallback.
/// Poke: switch supportedLocales between the default and `[ja, en]`.
class MotiveClueSlide extends StatefulWidget {
  const MotiveClueSlide({super.key});

  @override
  State<MotiveClueSlide> createState() => _MotiveClueSlideState();
}

const _nodes = [
  ('device', 'phone'),
  ('MaterialApp', 'supportedLocales'),
  ('Localizations', 'resolved'),
  ('RichText', 'locale'),
  ('SkParagraph', 'TextStyle'),
  ('fallback', 'font'),
];

const _nodeW = 206.0;
const _nodeH = 128.0;
const _nodeY = 40.0;

double _nodeX(int i) => i * (1472 - _nodeW) / 5;

class _MotiveClueSlideState extends State<MotiveClueSlide> {
  bool _fixed = false;
  final _labels = LabelCache();

  @override
  void dispose() {
    _labels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = _fixed
        ? const [
            ('MaterialApp(', BP.ink),
            ("  supportedLocales: const [Locale('ja'), Locale('en')],", BP.green),
            ('  localizationsDelegates: GlobalMaterialLocalizations.delegates,', BP.green),
            (')', BP.ink),
          ]
        : const [
            ('MaterialApp(', BP.ink),
            ('  // supportedLocales not set: defaults to', BP.inkFaint),
            ("  // const <Locale>[Locale('en', 'US')]", BP.red),
            (')', BP.ink),
          ];
    return SlideFrame(
      title: 'The motive: en_US',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('supportedLocales', style: BT.mono(14, color: BP.inkDim)),
          const SizedBox(width: 12),
          BpSegmented<bool>(
            values: const [false, true],
            selected: _fixed,
            color: BP.amber,
            labelOf: (v) => v ? '[ja, en]' : 'default',
            onChanged: (v) => setState(() => _fixed = v),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: LoopBuilder(
              period: const Duration(milliseconds: 5200),
              builder: (context, t, _) => CustomPaint(
                painter: _ChainPainter(t: t, fixed: _fixed, labels: _labels),
              ),
            ),
          ),
          // The code that decides it.
          Positioned(
            left: 0,
            top: 280,
            child: BpPanel(
              label: 'main.dart',
              color: _fixed ? BP.green : BP.red,
              padding: const EdgeInsets.fromLTRB(26, 22, 26, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (line, color) in code)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(line, style: BT.mono(19, color: color)),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 294,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('RichText', style: BT.mono(14, color: BP.inkFaint)),
                const SizedBox(height: 6),
                Text('locale ?? Localizations.maybeLocaleOf(context)', style: BT.mono(17, color: BP.ink)),
                const SizedBox(height: 22),
                Text('no match → supportedLocales.first', style: BT.mono(17, color: _fixed ? BP.inkFaint : BP.red)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChainPainter extends CustomPainter {
  _ChainPainter({required this.t, required this.fixed, required this.labels});

  final double t;
  final bool fixed;
  final LabelCache labels;

  @override
  void paint(Canvas canvas, Size size) {
    final pos = seg(t, 0.04, 0.8) * 5; // node units
    final gateHit = pos >= 1;
    final tag = !gateHit ? 'ja-JP' : (fixed ? 'ja' : 'en-US');
    final y = _nodeY + _nodeH / 2;

    // Rail.
    canvas.drawLine(Offset(_nodeX(0) + _nodeW / 2, y), Offset(_nodeX(5) + _nodeW / 2, y), Paint()
      ..color = BP.lineDim
      ..strokeWidth = 1.5);

    for (var i = 0; i < _nodes.length; i++) {
      final (name, sub) = _nodes[i];
      final r = Rect.fromLTWH(_nodeX(i), _nodeY, _nodeW, _nodeH);
      final reached = pos >= i - 0.02;
      final gate = i == 1;
      final c = gate && !fixed ? BP.red : (reached ? BP.line : BP.lineDim);
      canvas.drawRect(r, Paint()..color = BP.panel);
      canvas.drawRect(r, Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = reached ? 1.8 : 1);
      labels.get(name, BT.mono(17, color: BP.ink)).paint(canvas, r.topLeft + const Offset(16, 16));
      labels.get(sub, BT.mono(13, color: BP.inkFaint)).paint(canvas, r.topLeft + const Offset(16, 44));
      // What each stage holds once the packet has passed.
      String value;
      switch (i) {
        case 0:
          value = 'ja-JP';
        case 1:
          value = fixed ? '[ja, en]' : '[en_US]';
        case 5:
          value = '';
        default:
          value = reached ? (fixed ? 'ja' : 'en-US') : '…';
      }
      if (value.isNotEmpty) {
        final col = i == 0 ? BP.ink : (fixed ? BP.green : (i == 1 ? BP.red : BP.amber));
        labels.get(value, BT.mono(20, color: reached || i <= 1 ? col : BP.inkFaint)).paint(canvas, r.topLeft + const Offset(16, 80));
      }
      if (i == 0) _phone(canvas, r.topRight + const Offset(-44, 24));
    }

    // The gate: ja-JP rejected (no match) and replaced by the first entry.
    final g = Rect.fromLTWH(_nodeX(1), _nodeY, _nodeW, _nodeH);
    final hit = segOut(pos, 0.9, 1.3);
    if (!fixed && hit > 0 && hit < 1) {
      final a = (1 - hit);
      final p = Paint()
        ..color = BP.red.withValues(alpha: a)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      final c = g.center + const Offset(0, -110);
      canvas.drawLine(c + const Offset(-22, -22), c + const Offset(22, 22), p);
      canvas.drawLine(c + const Offset(22, -22), c + const Offset(-22, 22), p);
    }
    if (!fixed) {
      final m = labels.get('motive', BT.mono(14, color: BP.paper));
      final tr = Rect.fromLTWH(g.right - m.width - 44, g.bottom + 16, m.width + 36, m.height + 8);
      final sway = math.sin(t * math.pi * 4) * 0.05;
      canvas.save();
      canvas.translate(tr.center.dx, g.bottom);
      canvas.rotate(sway);
      canvas.translate(-tr.center.dx, -g.bottom);
      canvas.drawLine(Offset(tr.center.dx, g.bottom), Offset(tr.center.dx, tr.top), Paint()
        ..color = BP.red
        ..strokeWidth = 1.2);
      paintTag(canvas, tr, color: BP.red, filled: true);
      m.paint(canvas, Offset(tr.left + 26, tr.top + 4));
      canvas.restore();
    }

    // The packet carrying the locale.
    if (pos < 5) {
      final x = _nodeX(0) + _nodeW / 2 + pos * (_nodeX(1) - _nodeX(0));
      final tp = labels.get(tag, BT.mono(16, color: BP.paper, weight: 600));
      final col = !gateHit ? BP.ink : (fixed ? BP.green : BP.amber);
      final r = Rect.fromCenter(center: Offset(x, y + _nodeH / 2 + 26), width: tp.width + 24, height: tp.height + 10);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), Paint()..color = col);
      tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
      canvas.drawLine(Offset(x, y), Offset(x, r.top), Paint()
        ..color = col
        ..strokeWidth = 1.5);
      canvas.drawCircle(Offset(x, y), 6, Paint()..color = col);
    }

    // Result glyph inside the last node.
    final last = Rect.fromLTWH(_nodeX(5), _nodeY, _nodeW, _nodeH);
    if (pos >= 4.9) {
      final gl = labels.get('直', fixed ? NT.caseJP(76, color: BP.line) : NT.caseSC(76, color: BP.amber));
      gl.paint(canvas, Offset(last.right - gl.width - 14, last.bottom - gl.height - 12));
      labels.get(fixed ? 'JP form' : 'may be non-JP', BT.mono(13, color: fixed ? BP.line : BP.red))
          .paint(canvas, last.bottomLeft + const Offset(0, 12));
      labels.get('demo: Noto Sans JP / SC', BT.mono(11, color: BP.inkFaint)).paint(canvas, last.bottomLeft + const Offset(0, 32));
    }
  }

  void _phone(Canvas canvas, Offset at) {
    final r = Rect.fromLTWH(at.dx, at.dy, 26, 44);
    final p = Paint()
      ..color = BP.inkDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(5)), p);
    canvas.drawLine(Offset(r.center.dx - 4, r.bottom - 5), Offset(r.center.dx + 4, r.bottom - 5), p);
  }

  @override
  bool shouldRepaint(_ChainPainter old) => old.t != t || old.fixed != fixed;
}
