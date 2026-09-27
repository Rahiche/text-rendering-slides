import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'noir_kit.dart';

/// Clue 1: the code point is innocent. Two evidence bags, the same
/// U+76F4 and the same UTF-8 bytes, two different glyphs. The bytes are
/// decoded live (payload bits → code point). Poke: pick another exhibit.
class CodePointClueSlide extends StatefulWidget {
  const CodePointClueSlide({super.key});

  @override
  State<CodePointClueSlide> createState() => _CodePointClueSlideState();
}

class _CodePointClueSlideState extends State<CodePointClueSlide> {
  int _cp = caseCp;
  final _labels = LabelCache();

  @override
  void dispose() {
    _labels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = utf8.encode(String.fromCharCode(_cp));
    final hexBytes = bytes.map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0')).join(' ');
    return SlideFrame(
      title: 'The code point: innocent',
      trailing: CaseCharPicker(selected: _cp, onChanged: (c) => setState(() => _cp = c)),
      child: LoopBuilder(
        period: const Duration(seconds: 6),
        builder: (context, t, _) {
          final scan = seg(t, 0.05, 0.55);
          Widget row(int i, String label, String value) {
            final lit = scan > (i + 1) / 4;
            return SizedBox(
              height: 40,
              child: Row(
                children: [
                  SizedBox(width: 480, child: Center(child: Text(value, style: BT.mono(24, color: BP.ink)))),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 150,
                          child: Text(label, textAlign: TextAlign.right, style: BT.mono(14, color: BP.inkFaint)),
                        ),
                        const SizedBox(width: 18),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: lit ? BP.green.withValues(alpha: 0.15) : Colors.transparent,
                            border: Border.all(color: lit ? BP.green : BP.lineFaint),
                          ),
                          child: Text('=', style: BT.mono(24, color: lit ? BP.green : BP.inkFaint)),
                        ),
                        const SizedBox(width: 168),
                      ],
                    ),
                  ),
                  SizedBox(width: 480, child: Center(child: Text(value, style: BT.mono(24, color: BP.ink)))),
                ],
              ),
            );
          }

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 60,
                top: 0,
                child: _Bag(
                  label: 'EXHIBIT A',
                  lang: 'ja',
                  color: BP.line,
                  glyph: Text(String.fromCharCode(_cp), style: NT.caseJP(190, color: BP.line)),
                ),
              ),
              Positioned(
                right: 60,
                top: 0,
                child: _Bag(
                  label: 'EXHIBIT B',
                  lang: 'zh-Hans',
                  color: BP.amber,
                  glyph: Text(String.fromCharCode(_cp), style: NT.caseSC(190, color: BP.amber)),
                ),
              ),
              // The glyphs differ.
              Positioned(
                left: 0,
                right: 0,
                top: 40,
                child: Column(
                  children: [
                    Transform.scale(
                      scale: 1 + 0.06 * math.sin(t * math.pi * 4),
                      child: Text('≠', style: BT.display(170, color: BP.red, height: 1)),
                    ),
                    Text('glyph', style: BT.mono(15, color: BP.red)),
                    const SizedBox(height: 4),
                    Text('demo: Noto Sans JP / SC', style: BT.mono(12, color: BP.inkFaint)),
                  ],
                ),
              ),
              // The data is identical.
              Positioned(
                left: 0,
                right: 0,
                top: 300,
                child: Column(
                  children: [
                    row(0, 'code point', hexOf(_cp)),
                    row(1, 'UTF-8', hexBytes),
                    row(2, 'UTF-16', _cp.toRadixString(16).toUpperCase()),
                  ],
                ),
              ),
              // Scanner sweeping over both rows of data.
              Positioned(
                left: 60 + 1352 * scan - 2,
                top: 296,
                width: 3,
                height: 128,
                child: IgnorePointer(
                  child: ColoredBox(color: BP.green.withValues(alpha: scan > 0 && scan < 1 ? 0.8 : 0)),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 430,
                height: 198,
                child: CustomPaint(painter: _DecodePainter(bytes, _cp, t, _labels)),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// An evidence bag: zip-lock strip, label, the glyph inside.
class _Bag extends StatelessWidget {
  const _Bag({required this.label, required this.lang, required this.color, required this.glyph});

  final String label;
  final String lang;
  final Color color;
  final Widget glyph;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 360,
    height: 296,
    child: CustomPaint(
      painter: _BagPainter(color),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 12),
        child: Column(
          children: [
            Row(
              children: [
                Text(label, style: BT.mono(14, color: color, weight: 600)),
                const Spacer(),
                EvidenceTag(lang, color: color, size: 13),
              ],
            ),
            Expanded(child: Center(child: glyph)),
          ],
        ),
      ),
    ),
  );
}

class _BagPainter extends CustomPainter {
  _BagPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(0, 12, size.width, size.height - 12);
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(10)), Paint()..color = color.withValues(alpha: 0.05));
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(10)),
      Paint()
        ..color = color.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    // Zip strip with teeth.
    final z = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1.2;
    canvas.drawLine(const Offset(0, 4), Offset(size.width, 4), z);
    canvas.drawLine(const Offset(0, 12), Offset(size.width, 12), z);
    for (var x = 6.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, 4), Offset(x + 3, 12), z..color = color.withValues(alpha: 0.35));
    }
    // Sheen.
    canvas.drawLine(
      Offset(size.width - 40, 40),
      Offset(size.width - 22, 120),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_BagPainter old) => old.color != color;
}

/// UTF-8 → code point: prefix bits dim, payload bits drop into place.
class _DecodePainter extends CustomPainter {
  _DecodePainter(this.bytes, this.cp, this.t, this.labels);

  final List<int> bytes;
  final int cp;
  final double t;
  final LabelCache labels;

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 22.0;
    final n = bytes.length;
    // Prefix length per byte (lead byte: n ones + 0; continuation: 10).
    final prefix = [for (var i = 0; i < n; i++) i == 0 ? (n == 1 ? 1 : n + 1) : 2];
    const gap = 26.0;
    final total = n * 8 * cell + (n - 1) * gap;
    final x0 = (size.width - total) / 2;
    const yTop = 24.0;
    const yBot = 100.0;
    final drop = seg(t, 0.55, 0.8);

    final lbl = labels.get('UTF-8 bytes', BT.mono(13, color: BP.inkFaint));
    lbl.paint(canvas, Offset(x0 - lbl.width - 20, yTop + 2));
    final lbl2 = labels.get('code point', BT.mono(13, color: BP.inkFaint));
    lbl2.paint(canvas, Offset(x0 - lbl2.width - 20, yBot + 2));

    final payload = <(Offset, String)>[];
    for (var i = 0; i < n; i++) {
      final bx = x0 + i * (8 * cell + gap);
      final hex = labels.get(bytes[i].toRadixString(16).toUpperCase().padLeft(2, '0'), BT.mono(14, color: BP.inkDim));
      hex.paint(canvas, Offset(bx + 4 * cell - hex.width / 2, yTop - 22));
      for (var b = 0; b < 8; b++) {
        final bit = (bytes[i] >> (7 - b)) & 1;
        final r = Rect.fromLTWH(bx + b * cell, yTop, cell - 2, cell + 4);
        final isPrefix = b < prefix[i];
        canvas.drawRect(r, Paint()..color = isPrefix ? BP.lineFaint.withValues(alpha: 0.5) : BP.line.withValues(alpha: 0.14));
        final tp = labels.get('$bit', BT.mono(15, color: isPrefix ? BP.inkFaint : BP.ink));
        tp.paint(canvas, Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2));
        if (!isPrefix) payload.add((r.topLeft, '$bit'));
      }
    }
    // Target slots: the payload bits, grouped in nibbles → hex digits.
    final bits = payload.length;
    final pad = (4 - bits % 4) % 4;
    const nib = 10.0;
    final slots = bits + pad;
    final w = slots * cell + (slots ~/ 4 - 1) * nib;
    final tx0 = (size.width - w) / 2;
    Offset slot(int k) => Offset(tx0 + k * cell + (k ~/ 4) * nib, yBot);
    for (var k = 0; k < pad; k++) {
      final tp = labels.get('0', BT.mono(15, color: BP.inkFaint));
      tp.paint(canvas, slot(k) + Offset((cell - 2) / 2 - tp.width / 2, 4));
    }
    final line = Paint()
      ..color = BP.amber.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    for (var k = 0; k < bits; k++) {
      final from = payload[k].$1;
      final to = slot(k + pad);
      if (drop < 1) canvas.drawLine(from + const Offset(cell / 2, cell + 4), to + const Offset(cell / 2, 0), line);
      final p = Offset.lerp(from, to, drop)!;
      final r = Rect.fromLTWH(p.dx, p.dy, cell - 2, cell + 4);
      canvas.drawRect(r, Paint()..color = BP.amber.withValues(alpha: 0.12 + 0.1 * drop));
      final tp = labels.get(payload[k].$2, BT.mono(15, color: drop > 0 ? BP.amber : BP.ink));
      tp.paint(canvas, Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2));
    }
    // Hex digits under each nibble, then the answer.
    final show = seg(t, 0.8, 0.9);
    if (show > 0) {
      final hex = cp.toRadixString(16).toUpperCase().padLeft(slots ~/ 4, '0');
      for (var k = 0; k < slots ~/ 4; k++) {
        final c = slot(k * 4) + Offset(2 * cell - 1, cell + 12);
        final tp = labels.get(hex[k], BT.mono(22, color: BP.green.withValues(alpha: show)));
        tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy));
      }
      final ans = labels.get('→ ${hexOf(cp)}', BT.mono(22, color: BP.green.withValues(alpha: show)));
      ans.paint(canvas, Offset(tx0 + w + 30, yBot));
    }
  }

  @override
  bool shouldRepaint(_DecodePainter old) => old.t != t || old.cp != cp;
}

/// Chips for the case characters, rendered with the Japanese case font.
class CaseCharPicker extends StatelessWidget {
  const CaseCharPicker({super.key, required this.selected, required this.onChanged, this.chars = '直今画骨海誤'});

  final int selected;
  final ValueChanged<int> onChanged;
  final String chars;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final c in chars.runes) ...[
        const SizedBox(width: 8),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => onChanged(c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c == selected ? BP.amber.withValues(alpha: 0.15) : Colors.transparent,
                border: Border.all(color: c == selected ? BP.amber : BP.lineDim),
              ),
              child: Text(String.fromCharCode(c), style: NT.caseJP(28, color: c == selected ? BP.ink : BP.inkDim)),
            ),
          ),
        ),
      ],
    ],
  );
}
