import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'noir_kit.dart';

/// Cold open: the bug report pinned to the board, the two 直 side by side
/// (expected JP form vs the reported one), and the question: why?
/// Poke: "overlay" slides the reported glyph onto the expected one.
class CaseOpenSlide extends StatefulWidget {
  const CaseOpenSlide({super.key});

  @override
  State<CaseOpenSlide> createState() => _CaseOpenSlideState();
}

const _photoA = Offset(470, 30);
const _photoB = Offset(840, 58);
const _photoW = 310.0;
const _photoH = 380.0;
const _report = Rect.fromLTWH(0, 44, 390, 372);

class _CaseOpenSlideState extends State<CaseOpenSlide> {
  bool _overlay = false;

  @override
  Widget build(BuildContext context) {
    return SlideFrame(
      title: 'The case of 直',
      trailing: BpSegmented<bool>(
        values: const [false, true],
        selected: _overlay,
        labelOf: (v) => v ? 'overlay' : 'side by side',
        onChanged: (v) => setState(() => _overlay = v),
      ),
      child: CaseFontsBuilder(
        builder: (context, fonts) => LoopBuilder(
          period: const Duration(seconds: 6),
          builder: (context, t, _) => Stack(
            clipBehavior: Clip.none,
            children: [
              // Red string: report → both photos.
              Positioned.fill(
                child: IgnorePointer(
                  child: DrawOn(
                    duration: const Duration(milliseconds: 1400),
                    delay: const Duration(milliseconds: 700),
                    color: BP.red,
                    strokeWidth: 1.8,
                    path: (_) => Path()
                      ..addPath(stringPath(Offset(_report.center.dx, _report.top + 10), _photoA + const Offset(_photoW / 2, 8), sag: 40), Offset.zero)
                      ..addPath(stringPath(_photoA + const Offset(_photoW / 2, 8), _photoB + const Offset(_photoW / 2, 8), sag: 30), Offset.zero),
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: _report,
                child: Reveal(
                  visible: true,
                  offset: const Offset(0, -30),
                  child: Transform.rotate(angle: -0.025, child: const _Report()),
                ),
              ),
              // Expected (JP form).
              Positioned(
                left: _photoA.dx,
                top: _photoA.dy,
                child: Reveal(
                  visible: true,
                  delay: const Duration(milliseconds: 250),
                  offset: const Offset(0, -30),
                  child: PinnedPhoto(
                    width: _photoW,
                    height: _photoH,
                    color: BP.line,
                    caption: const _Caption('expected', 'ja', BP.line),
                    child: CustomPaint(
                      painter: CaseGlyphPainter(
                        cp: caseCp,
                        japanese: true,
                        fill: BP.line.withValues(alpha: 0.85),
                        stroke: BP.line,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              // Reported (SC form); slides onto A in overlay mode.
              AnimatedPositioned(
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeInOutCubic,
                left: _overlay ? _photoA.dx : _photoB.dx,
                top: _overlay ? _photoA.dy : _photoB.dy,
                child: Reveal(
                  visible: true,
                  delay: const Duration(milliseconds: 450),
                  offset: const Offset(0, -30),
                  child: AnimatedRotation(
                    duration: const Duration(milliseconds: 800),
                    turns: _overlay ? 0 : 0.006,
                    child: PinnedPhoto(
                      width: _photoW,
                      height: _photoH,
                      color: BP.amber,
                      fill: _overlay ? Colors.transparent : BP.panel,
                      pin: !_overlay,
                      caption: _overlay ? const SizedBox(height: 26) : const _Caption('reported', '?', BP.amber),
                      child: CustomPaint(
                        painter: CaseGlyphPainter(
                          cp: caseCp,
                          japanese: false,
                          fill: _overlay ? null : BP.amber.withValues(alpha: 0.85),
                          stroke: BP.amber,
                          strokeWidth: _overlay ? 2.5 : 2,
                          diff: _overlay ? 0.35 + 0.35 * math.sin(t * math.pi * 6).abs() : 0,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: _photoA.dx,
                top: _photoA.dy + _photoH + 26,
                child: Row(
                  children: [
                    Text('U+76F4 · U+76F4', style: BT.mono(15, color: BP.inkDim)),
                    const SizedBox(width: 24),
                    Text('demo: Noto Sans JP / SC', style: BT.mono(12, color: BP.inkFaint)),
                  ],
                ),
              ),
              // The question.
              Positioned(
                right: 0,
                top: 20,
                width: 280,
                child: Transform.translate(
                  offset: Offset(0, math.sin(t * 2 * math.pi) * 6),
                  child: Column(
                    children: [
                      Text(
                        '?',
                        style: BT.display(300, weight: 600, height: 1).copyWith(
                          foreground: Paint()
                            ..style = PaintingStyle.stroke
                            ..strokeWidth = 3
                            ..color = BP.amber,
                        ),
                      ),
                      Text('なぜ？', style: NT.jp(60, color: BP.ink, weight: 600)),
                      const SizedBox(height: 6),
                      Text('why?', style: BT.mono(22, color: BP.amber)),
                    ],
                  ),
                ),
              ),
              // A camera flash, now and then.
              Positioned(
                left: _photoA.dx,
                top: _photoA.dy,
                width: _photoB.dx + _photoW - _photoA.dx,
                height: _photoH + 40,
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Colors.white.withValues(alpha: t < 0.04 ? 0.16 * (1 - t / 0.04) : 0),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.label, this.lang, this.color);

  final String label;
  final String lang;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: BT.mono(16, color: color)),
      EvidenceTag(lang, color: color, size: 13),
    ],
  );
}

class _Report extends StatelessWidget {
  const _Report();

  @override
  Widget build(BuildContext context) {
    Widget field(String k, String v, {TextStyle? style}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(width: 92, child: Text(k, style: BT.mono(14, color: BP.inkFaint))),
          Text(v, style: style ?? BT.mono(16, color: BP.ink)),
        ],
      ),
    );
    return CustomPaint(
      painter: _ReportPainter(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 34, 26, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('BUG REPORT', style: BT.mono(15, color: BP.amber, weight: 600)),
                const Spacer(),
                Text('#76F4', style: BT.mono(14, color: BP.inkDim)),
              ],
            ),
            const SizedBox(height: 22),
            Text('「漢字が中国語っぽい…」', style: NT.jp(28, color: BP.ink, weight: 500)),
            const SizedBox(height: 6),
            Text('kanji look Chinese', style: BT.mono(14, color: BP.inkDim)),
            const SizedBox(height: 22),
            Container(height: 1, color: BP.lineDim),
            const SizedBox(height: 18),
            field('device', 'ja-JP'),
            field('app', 'Flutter'),
            field('text', '直', style: NT.jp(20, color: BP.ink)),
            field('status', 'open', style: BT.mono(16, color: BP.red)),
          ],
        ),
      ),
    );
  }
}

class _ReportPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = BP.panel);
    canvas.drawPath(
      dashPath(Path()..addRect(r), dash: 8, gap: 5),
      Paint()
        ..color = BP.inkDim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    // Folded corner.
    final f = Path()
      ..moveTo(size.width - 28, size.height)
      ..lineTo(size.width, size.height - 28)
      ..lineTo(size.width - 28, size.height - 28)
      ..close();
    canvas.drawPath(f, Paint()..color = BP.lineFaint);
    drawPin(canvas, Offset(size.width / 2, 10), r: 6.5);
  }

  @override
  bool shouldRepaint(_ReportPainter old) => false;
}
