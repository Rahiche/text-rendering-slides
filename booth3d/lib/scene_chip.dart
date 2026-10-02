import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:text_slides/booth/model.dart';
import 'package:text_slides/booth/ui/ink.dart';
import 'package:text_slides/deck/theme.dart';

import 'world/scene_caption.dart';

/// The lower third for the shots without one of their own, where the
/// kerning and the works' captions go (they never show together):
///
///   左官 · PLASTER
///   anti-aliasing
///   the jagged pixel edges, smoothed
///
/// Driven by the site's [caption], repainted with the model.
class SceneChip extends StatefulWidget {
  const SceneChip({super.key, required this.model, required this.caption});

  final BoothModel model;
  final SceneCaption caption;

  @override
  State<SceneChip> createState() => _SceneChipState();
}

class _SceneChipState extends State<SceneChip> {
  final _text = UiText(max: 24);

  @override
  void dispose() {
    _text.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(child: CustomPaint(painter: _ScenePainter(widget.model, widget.caption, _text))),
  );
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.m, this.c, this.text) : super(repaint: m);

  final BoothModel m;
  final SceneCaption c;
  final UiText text;

  /// Right edge and bottom of the chip (above the ticker in the bottom
  /// band, as the kerning caption).
  static const _right = 1564.0, _bottom = 798.0;

  @override
  void paint(Canvas canvas, Size size) {
    final show = c.show;
    if (show <= 0.01) return;
    text.frame(m.t);
    final k = UiInk(canvas, text);
    final kick = k.tp(c.kick, UT.mono(14, color: BP.amber, weight: 600, ls: 1.2));
    final line = k.tp(c.line, UT.name(30, color: BP.ink, height: 1.0));
    final note = k.tp(c.note, UT.mono(12, color: BP.inkDim, weight: 500));
    final swatch = c.swatch;
    const pad = 18.0, chip = 22.0;
    final lead = swatch == null ? 0.0 : chip + 12;
    final w = pad * 2 + math.max(kick.width, math.max(lead + line.width, note.width));
    final h = 10 + kick.height + 8 + line.height + 6 + note.height + 12;
    final slide = 36 * (1 - Curves.easeOutCubic.transform(show));
    final box = Rect.fromLTWH(_right - w + slide, _bottom - h, w, h);
    k.faded(show, () {
      final rr = RRect.fromRectAndRadius(box, const Radius.circular(10));
      canvas.drawRRect(rr, k.fl(BP.panel.withValues(alpha: 0.92)));
      canvas.drawRRect(rr, k.st(BP.amber, 1.6));
      final x0 = box.left + pad;
      var y = box.top + 10;
      kick.paint(canvas, Offset(x0, y));
      y += kick.height + 8;
      if (swatch != null) {
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(x0, y + (line.height - chip) / 2, chip, chip), const Radius.circular(5));
        canvas.drawRRect(r, k.fl(swatch));
        canvas.drawRRect(r, k.st(BP.ink.withValues(alpha: 0.7), 1.2));
      }
      line.paint(canvas, Offset(x0 + lead, y));
      y += line.height + 6;
      note.paint(canvas, Offset(x0, y));
    });
  }

  @override
  bool shouldRepaint(_ScenePainter old) => old.m != m || old.c != c || old.text != text;
}
