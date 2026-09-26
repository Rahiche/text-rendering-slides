import 'dart:async';

import 'package:flutter/material.dart';

import '../deck/theme.dart';
import '../deck/widgets.dart';

/// Title: the word "text" in many scripts, drawn over its real line metrics.
class TitleSlide extends StatefulWidget {
  const TitleSlide({super.key});

  @override
  State<TitleSlide> createState() => _TitleSlideState();
}

class _TitleSlideState extends State<TitleSlide> {
  static const _words = ['Text', 'نص', 'टेक्स्ट', '文字', 'טקסט', 'ข้อความ', '텍스트', 'Текст'];
  static const _baselineY = 400.0;
  static const _left = 64.0;

  int _i = 0;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2600), (_) {
      setState(() => _i = (_i + 1) % _words.length);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final word = _words[_i];
    final probe = TextProbe(TextSpan(text: word, style: BT.sample(210, weight: 500)));
    final line = probe.lines.first;
    final ascentY = _baselineY - line.ascent;
    final descentY = _baselineY + line.descent;
    final codePoints = word.runes
        .map((r) => 'U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}')
        .join(' ');
    final width = probe.size.width;
    probe.dispose();

    return Stack(
      children: [
        // Metric guides, gliding to each script's metrics.
        _Guide(y: ascentY, label: 'ascent', value: line.ascent, dashed: true),
        _Guide(y: _baselineY, label: 'baseline', value: 0, dashed: false),
        _Guide(y: descentY, label: 'descent', value: line.descent, dashed: true),

        // Advance width
        TweenAnimationBuilder<double>(
          tween: Tween(end: width),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOutCubic,
          builder: (context, w, _) => Positioned(
            left: 170,
            top: 64,
            child: DimensionLine(length: w, label: 'advance  ${w.toStringAsFixed(1)}', color: BP.inkDim),
          ),
        ),

        // The word itself
        Positioned(
          left: 170,
          top: 0,
          right: 0,
          height: 620,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 700),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(anim),
                child: child,
              ),
            ),
            layoutBuilder: (cur, prev) => Stack(children: [...prev, ?cur]),
            child: CustomPaint(
              key: ValueKey(word),
              size: const Size(1300, 620),
              painter: _WordPainter(word, _baselineY),
            ),
          ),
        ),

        // Code points
        Positioned(
          left: 170,
          top: 540,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: Text(codePoints, key: ValueKey(word), style: BT.mono(18, color: BP.line)),
          ),
        ),

        // Title
        Positioned(
          left: _left,
          bottom: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Reveal(
                visible: true,
                delay: const Duration(milliseconds: 300),
                child: Text('Text rendering', style: BT.display(88, letterSpacing: -2, height: 1)),
              ),
              const SizedBox(height: 14),
              Reveal(
                visible: true,
                delay: const Duration(milliseconds: 600),
                child: Row(
                  children: [
                    Container(width: 36, height: 1.5, color: BP.amber),
                    const SizedBox(width: 12),
                    Text('from code points to pixels · and how Flutter does it',
                        style: BT.mono(20, color: BP.inkDim)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: _left,
          top: 56,
          child: Text('flutter / text', style: BT.mono(16, color: BP.inkDim)),
        ),
      ],
    );
  }
}

class _Guide extends StatelessWidget {
  const _Guide({required this.y, required this.label, required this.value, required this.dashed});

  final double y;
  final String label;
  final double value;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: y),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOutCubic,
      builder: (context, y, _) => Positioned(
        left: 64,
        right: 64,
        top: y - 14,
        height: 28,
        child: Row(
          children: [
            SizedBox(width: 96, child: Text(label, style: BT.mono(14, color: dashed ? BP.inkDim : BP.line))),
            Expanded(
              child: SizedBox(
                height: 28,
                child: CustomPaint(painter: _LinePainter(dashed: dashed)),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 60,
              child: Text(
                value == 0 ? '0' : value.toStringAsFixed(1),
                textAlign: TextAlign.right,
                style: BT.mono(14, color: BP.inkDim),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.dashed});

  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final path = Path()
      ..moveTo(0, y)
      ..lineTo(size.width, y);
    canvas.drawPath(
      dashed ? dashPath(path, dash: 8, gap: 6) : path,
      Paint()
        ..color = dashed ? BP.lineDim : BP.line
        ..strokeWidth = dashed ? 1 : 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.dashed != dashed;
}

/// Paints the word with its baseline on [baselineY], plus dashed boxes around
/// each grapheme cluster, all from the real paragraph layout.
class _WordPainter extends CustomPainter {
  _WordPainter(this.word, this.baselineY);

  final String word;
  final double baselineY;

  @override
  void paint(Canvas canvas, Size size) {
    final probe = TextProbe(TextSpan(text: word, style: BT.sample(210, weight: 500)));
    final line = probe.lines.first;
    final origin = Offset(0, baselineY - line.baseline);
    final box = Paint()
      ..color = BP.lineDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final (s, e) in probe.graphemes()) {
      for (final b in probe.boxes(s, e)) {
        final r = b.toRect().shift(origin);
        canvas.drawPath(dashPath(Path()..addRect(r), dash: 5, gap: 5), box);
      }
    }
    probe.paint(canvas, origin);
    probe.dispose();
  }

  @override
  bool shouldRepaint(_WordPainter old) => old.word != word;
}
