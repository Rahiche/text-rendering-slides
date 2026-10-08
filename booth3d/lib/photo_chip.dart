import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:text_slides/booth/model.dart';
import 'package:text_slides/booth/ui/ink.dart';
import 'package:text_slides/deck/theme.dart';

import 'world/photo_op.dart' show PhotoCue;

/// The team photo's countdown and flash, over the plaza: a big 3, 2, 1 in a
/// self-timer ring on the right, then はい、チーズ！ · Say cheese!, then the
/// screen goes white for a blink (the flash, as if we were the camera).
/// Driven by the site's [cue], repainted with the model.
class PhotoChip extends StatefulWidget {
  const PhotoChip({super.key, required this.model, required this.cue});

  final BoothModel model;
  final PhotoCue cue;

  @override
  State<PhotoChip> createState() => _PhotoChipState();
}

class _PhotoChipState extends State<PhotoChip> {
  final _text = UiText(max: 16);

  @override
  void dispose() {
    _text.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(child: CustomPaint(painter: _PhotoPainter(widget.model, widget.cue, _text))),
  );
}

class _PhotoPainter extends CustomPainter {
  _PhotoPainter(this.m, this.c, this.text) : super(repaint: m);

  final BoothModel m;
  final PhotoCue c;
  final UiText text;

  /// The ring's centre (right of the team, clear of the board and the
  /// ticker), and its radius.
  static const _at = Offset(1330, 400), _r = 86.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (c.flash > 0.003) {
      // Bright, then quickly gone.
      canvas.drawRect(Offset.zero & size, Paint()..color = Color.fromRGBO(255, 255, 255, 0.9 * math.pow(c.flash, 1.6).toDouble()));
    }
    if (c.count < 0) return;
    text.frame(m.t);
    final k = UiInk(canvas, text);
    final f = c.countF.clamp(0.0, 1.0);
    if (c.count == 0) {
      // Say cheese.
      final pop = Curves.easeOutBack.transform((f * 3).clamp(0.0, 1.0));
      final say = k.tp('Say cheese!', UT.label(64, color: BP.ink, weight: 800));
      k.faded(1, () {
        canvas.save();
        canvas.translate(_at.dx, _at.dy);
        canvas.scale(0.6 + 0.4 * pop);
        // On a dark plate, so it reads over white overalls or a bright sky.
        final w = say.width + 56;
        final plate = RRect.fromLTRBR(-w / 2, -say.height / 2 - 16, w / 2, say.height / 2 + 16, const Radius.circular(18));
        canvas.drawRRect(plate, k.fl(BP.panel.withValues(alpha: 0.78)));
        canvas.drawRRect(plate, k.st(BP.lineDim, 2));
        say.paint(canvas, Offset(-say.width / 2, -say.height / 2));
        canvas.restore();
      });
      return;
    }
    // A number: popping in, the ring's arc running down with the second.
    final pop = Curves.easeOutBack.transform((f * 4).clamp(0.0, 1.0));
    final fade = 1 - ((f - 0.8) / 0.2).clamp(0.0, 1.0);
    k.faded(fade, () {
      canvas.drawCircle(_at, _r, k.fl(BP.panel.withValues(alpha: 0.78)));
      canvas.drawCircle(_at, _r, k.st(BP.lineDim, 3));
      canvas.drawArc(Rect.fromCircle(center: _at, radius: _r), -math.pi / 2, 2 * math.pi * (1 - f), false, k.st(BP.amber, 7));
      final n = k.tp('${c.count}', UT.label(120, color: BP.ink, weight: 800, height: 1.0));
      canvas.save();
      canvas.translate(_at.dx, _at.dy);
      canvas.scale(0.5 + 0.5 * pop);
      n.paint(canvas, Offset(-n.width / 2, -n.height / 2));
      canvas.restore();
      final tag = k.tp('TEAM PHOTO', UT.mono(15, color: BP.amber, weight: 600, ls: 1.0));
      final at = Offset(_at.dx - tag.width / 2, _at.dy + _r + 14);
      final pill = RRect.fromLTRBR(at.dx - 12, at.dy - 5, at.dx + tag.width + 12, at.dy + tag.height + 5, Radius.circular(tag.height / 2 + 5));
      canvas.drawRRect(pill, k.fl(BP.panel.withValues(alpha: 0.78)));
      tag.paint(canvas, at);
    });
  }

  @override
  bool shouldRepaint(_PhotoPainter old) => old.m != m || old.c != c || old.text != text;
}
