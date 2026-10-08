import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:text_slides/booth/model.dart';
import 'package:text_slides/booth/ui/ink.dart';
import 'package:text_slides/deck/theme.dart';

import 'world/glyph_works.dart' show WorksCaption, worksSteps;

/// The Glyph Works' lower third while the camera visits it, over the plaza
/// on the right (where the kerning caption goes; they never show together):
///
///   ③ フォント · FONT · CMAP     ●●●○○○○     文字工場 · GLYPH WORKS
///   よ   U+3088   Space Grotesk ✕  Noto Kufi Arabic ✕  system font ✓
///        cmap: found by fallback
///
/// the step being looked at, the letter in the name's face, and the step's
/// real values for it. Driven by the works' [caption], repainted with the
/// model.
class WorksChip extends StatefulWidget {
  const WorksChip({super.key, required this.model, required this.caption});

  final BoothModel model;
  final WorksCaption caption;

  @override
  State<WorksChip> createState() => _WorksChipState();
}

class _WorksChipState extends State<WorksChip> {
  final _text = UiText(max: 64);

  @override
  void dispose() {
    _text.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(child: CustomPaint(painter: _WorksPainter(widget.model, widget.caption, _text))),
  );
}

class _WorksPainter extends CustomPainter {
  _WorksPainter(this.m, this.c, this.text) : super(repaint: m);

  final BoothModel m;
  final WorksCaption c;
  final UiText text;

  /// Right edge and bottom of the chip (above the ticker in the bottom
  /// band, as the kerning caption).
  static const _right = 1564.0, _bottom = 798.0, _h = 96.0;

  @override
  void paint(Canvas canvas, Size size) {
    final show = c.show;
    if (show <= 0.01 || c.step < 0) return;
    text.frame(m.t);
    final k = UiInk(canvas, text);
    final kick = k.tp(worksSteps[c.step], UT.mono(14, color: BP.amber, weight: 600, ls: 1.2));
    final where = k.tp(
      c.journey ? "A LETTER'S JOURNEY" : 'GLYPH WORKS',
      UT.mono(11, color: c.journey ? BP.amber : BP.inkDim, weight: 500, ls: 1.0),
    );
    final glyph = k.tp(c.letter, UT.name(40, color: BP.ink, height: 1.0));
    final value = k.tp(c.value, UT.mono(22, color: BP.amber, weight: 700));
    final note = k.tp(c.note, UT.mono(12, color: BP.inkDim, weight: 500));
    // At the font step, each font looked in, ✕ or ✓.
    final fonts = [for (final (name, hit) in c.fonts) (k.tp(name, UT.mono(15, color: hit ? BP.green : BP.red, weight: 600)), hit)];
    const mark = 16.0, gap = 14.0, pad = 18.0, num = 26.0;
    // Where the letter is down the line: a dot per step, this one lit.
    const dot = 9.0, dotGap = 5.0, stripW = 7 * dot + 6 * dotGap;
    var fontsW = 0.0;
    for (final (p, _) in fonts) {
      fontsW += p.width + mark + 6 + gap;
    }
    final valueW = value.width + (fonts.isEmpty ? 0 : gap + fontsW);
    final w = pad * 2 + math.max(num + 8 + kick.width + 20 + stripW + 16 + where.width, glyph.width + 18 + math.max(valueW, note.width));
    final slide = 36 * (1 - Curves.easeOutCubic.transform(show));
    final box = Rect.fromLTWH(_right - w + slide, _bottom - _h, w, _h);
    k.faded(show, () {
      final rr = RRect.fromRectAndRadius(box, const Radius.circular(10));
      canvas.drawRRect(rr, k.fl(BP.panel.withValues(alpha: 0.92)));
      canvas.drawRRect(rr, k.st(BP.amber, 1.6));
      // The step's number in a ring, as on its sign.
      final o = Offset(box.left + pad + num / 2, box.top + 8 + num / 2 - 4);
      canvas.drawCircle(o, num / 2 - 2, k.st(BP.amber, 1.6));
      final n = k.tp('${c.step + 1}', UT.mono(13, color: BP.amber, weight: 700));
      n.paint(canvas, o - Offset(n.width / 2, n.height / 2));
      kick.paint(canvas, Offset(box.left + pad + num + 8, box.top + 8));
      where.paint(canvas, Offset(box.right - pad - where.width, box.top + 10));
      final sx = box.right - pad - where.width - 16 - stripW, sy = box.top + 10 + where.height / 2;
      for (var i = 0; i < 7; i++) {
        final o = Offset(sx + i * (dot + dotGap) + dot / 2, sy);
        if (i == c.step) {
          canvas.drawCircle(o, dot / 2, k.fl(BP.amber));
        } else if (i < c.step) {
          canvas.drawCircle(o, dot / 2 - 1, k.fl(BP.amber.withValues(alpha: 0.4)));
        } else {
          canvas.drawCircle(o, dot / 2 - 1.5, k.st(BP.inkFaint, 1.2));
        }
      }
      // The letter on its baseline, its values beside it, the note under them.
      final base = box.bottom - 22;
      final x0 = box.left + pad;
      k.putBase(glyph, x0, base);
      final vx = x0 + glyph.width + 18;
      final vy = box.top + 36;
      value.paint(canvas, Offset(vx, vy));
      var fx = vx + value.width + gap;
      for (final (p, hit) in fonts) {
        final cy = vy + value.height / 2;
        p.paint(canvas, Offset(fx, cy - p.height / 2));
        fx += p.width + 6;
        if (hit) {
          k.tick(Offset(fx + mark / 2, cy), mark * 0.8, BP.green, 2.2);
        } else {
          final st = k.st(BP.red, 2.2);
          canvas.drawLine(Offset(fx + 3, cy - 5), Offset(fx + 13, cy + 5), st);
          canvas.drawLine(Offset(fx + 13, cy - 5), Offset(fx + 3, cy + 5), st);
        }
        fx += mark + gap;
      }
      note.paint(canvas, Offset(vx, vy + value.height + 2));
    });
  }

  @override
  bool shouldRepaint(_WorksPainter old) => old.m != m || old.c != c || old.text != text;
}
