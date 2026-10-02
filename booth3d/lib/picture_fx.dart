import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:text_slides/booth/model.dart';
import 'package:text_slides/deck/theme.dart';

/// Over the picture, under the overlays: a soft vignette (the eye to the
/// middle, the corners' boards on a darker ground), and a quick dip to dark
/// between one name and the next (out as the cleanup ends, in on the new
/// name's establishing shot). Repainted with the model.
class PictureFx extends StatelessWidget {
  const PictureFx({super.key, required this.model});

  final BoothModel model;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(child: CustomPaint(painter: _FxPainter(model))),
  );
}

class _FxPainter extends CustomPainter {
  _FxPainter(this.m) : super(repaint: m);

  final BoothModel m;

  /// The dip's halves (seconds).
  static const _out = 0.35, _in = 0.45;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    // An ellipse to the frame's shape: clear over the middle, a quarter
    // darker in the corners.
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(size.width / 2, size.height / 2);
    canvas.drawRect(
      const Rect.fromLTRB(-1, -1, 1, 1),
      Paint()..shader = ui.Gradient.radial(Offset.zero, math.sqrt2, const [Color(0x00000000), Color(0x00000000), Color(0x40000000)], const [0, 0.55, 1]),
    );
    canvas.restore();
    final j = m.job;
    if (j == null) return;
    var dark = 1 - ((m.t - j.startedAt) / _in).clamp(0.0, 1.0);
    if (j.phase == Phase.cleanup) dark = math.max(dark, ((m.t - (j.phaseStart + j.phaseLen - _out)) / _out).clamp(0.0, 1.0));
    if (dark > 0.003) canvas.drawRect(r, Paint()..color = BP.bg.withValues(alpha: dark));
  }

  @override
  bool shouldRepaint(_FxPainter old) => old.m != m;
}
