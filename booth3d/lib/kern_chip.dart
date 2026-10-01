import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:text_slides/booth/model.dart';
import 'package:text_slides/booth/ui/ink.dart';
import 'package:text_slides/deck/theme.dart';

import 'world/site_kern.dart' show KernCaption;

/// The kerning step's lower third, over the plaza on the right:
///
///   KERNING · カーニング
///   K e   −0.06 em
///
/// the pair in the name's face (the right letter sliding into place as the
/// crew push), and how much the font kerns it, counting up; a pair the font
/// doesn't kern gets "±0 em · ✓ spacing". Driven by the site's [caption],
/// repainted with the model.
class KernChip extends StatefulWidget {
  const KernChip({super.key, required this.model, required this.caption});

  final BoothModel model;
  final KernCaption caption;

  @override
  State<KernChip> createState() => _KernChipState();
}

class _KernChipState extends State<KernChip> {
  final _text = UiText(max: 48);

  @override
  void dispose() {
    _text.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(child: CustomPaint(painter: _KernPainter(widget.model, widget.caption, _text))),
  );
}

class _KernPainter extends CustomPainter {
  _KernPainter(this.m, this.c, this.text) : super(repaint: m);

  final BoothModel m;
  final KernCaption c;
  final UiText text;

  /// Right edge and baseline of the chip (above the ticker in the bottom
  /// band; the toasts rise on the left).
  static const _right = 1564.0, _bottom = 798.0, _h = 76.0;

  @override
  void paint(Canvas canvas, Size size) {
    final show = c.show;
    if (show <= 0.01) return;
    text.frame(m.t);
    final k = UiInk(canvas, text);
    final zero = c.em.abs() < 0.005;
    final kick = k.tp('KERNING · カーニング', UT.mono(14, color: BP.amber, weight: 600, ls: 1.2));
    final l = k.tp(c.left, UT.name(40, color: BP.ink, height: 1.0));
    final r = k.tp(c.right, UT.name(40, color: BP.ink, height: 1.0));
    final shown = c.em * c.count;
    final value = zero ? '±0 em' : (shown.abs() < 0.005 ? '0.00 em' : '${shown < 0 ? '−' : '+'}${shown.abs().toStringAsFixed(2)} em');
    final v = k.tp(value, UT.mono(28, color: zero ? BP.inkDim : BP.amber, weight: 700));
    final note = k.tp(zero ? 'spacing · 字間OK' : 'pair kerning · ペアカーニング', UT.mono(12, color: zero ? BP.green : BP.inkDim, weight: 500));
    // The pair: kerned as the font has it, the right letter a little loose
    // until the crew have pushed it home.
    final kernPx = c.em * 40;
    final loose = 10 * (1 - Curves.easeInOut.transform(c.push.clamp(0.0, 1.0)));
    final pairW = l.width + kernPx + loose + r.width;
    const pad = 18.0, gap = 22.0;
    final tickW = zero ? 16.0 : 0.0;
    final w = pad * 2 + math.max(kick.width, pairW + gap + math.max(v.width, note.width + tickW));
    final slide = 36 * (1 - Curves.easeOutCubic.transform(show));
    final box = Rect.fromLTWH(_right - w + slide, _bottom - _h, w, _h);
    k.faded(show, () {
      final rr = RRect.fromRectAndRadius(box, const Radius.circular(10));
      canvas.drawRRect(rr, k.fl(BP.panel.withValues(alpha: 0.92)));
      canvas.drawRRect(rr, k.st(BP.amber, 1.6));
      kick.paint(canvas, Offset(box.left + pad, box.top + 8));
      // The pair on a baseline, with the gap between them marked.
      final base = box.bottom - 14;
      final x0 = box.left + pad;
      k.putBase(l, x0, base);
      final xr = x0 + l.width + kernPx + loose;
      k.putBase(r, xr, base);
      final tick = k.st(BP.amber.withValues(alpha: 0.8), 1.4);
      canvas.drawLine(Offset(x0 + l.width, base + 4), Offset(x0 + l.width, base + 9), tick);
      canvas.drawLine(Offset(xr, base + 4), Offset(xr, base + 9), tick);
      canvas.drawLine(Offset(x0 + l.width, base + 6.5), Offset(xr, base + 6.5), tick);
      final vx = x0 + pairW + gap;
      v.paint(canvas, Offset(vx, box.top + 24));
      final ny = box.top + 24 + v.height - 2;
      if (zero) k.tick(Offset(vx + 5, ny + note.height / 2), 10, BP.green, 1.8);
      note.paint(canvas, Offset(vx + tickW, ny));
    });
  }

  @override
  bool shouldRepaint(_KernPainter old) => old.m != m || old.c != c || old.text != text;
}
