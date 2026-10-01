import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../../deck/theme.dart';
import '../layer.dart';
import '../model.dart';

/// The construction site: crane, scaffold, builders laying the name brick by
/// brick, the reveal, fireworks, the wrecking ball and the cleanup.
class SiteLayer extends BoothLayer {
  @override
  CustomPainter painter(BoothModel m) => _SitePainter(m);
}

class _SitePainter extends CustomPainter {
  _SitePainter(this.m) : super(repaint: m);

  final BoothModel m;

  @override
  void paint(Canvas c, Size size) {
    final j = m.job;
    final r = j?.raster;
    if (j == null || r == null) return;
    final laid = j.laid(m.t);
    final fall = j.phase == Phase.demolish
        ? j.progress(m.t)
        : (j.phase == Phase.cleanup ? 1.0 : 0.0);
    if (fall >= 1) return;
    final paint = Paint();
    for (var i = 0; i < laid; i++) {
      final b = r.bricks[i];
      paint.color = Color.lerp(BP.panel, BP.ink, b.cover)!.withValues(alpha: 1 - fall);
      c.drawRect(r.rectOf(b).deflate(0.6).shift(Offset(0, fall * fall * 300)), paint);
    }
    if (j.phase == Phase.reveal || j.phase == Phase.celebrate) {
      final tp = r.crisp(color: BP.amber.withValues(alpha: math.min(1, j.progress(m.t) * 2)));
      tp.paint(c, r.textOrigin);
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(_SitePainter old) => false;
}
