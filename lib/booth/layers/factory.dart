import 'package:flutter/rendering.dart';

import '../../deck/theme.dart';
import '../layer.dart';
import '../layout.dart';
import '../model.dart';

/// The glyph factory: reads each name (itemize → fonts → shape → raster)
/// and sends bricks down the belt to the crane.
class FactoryLayer extends BoothLayer {
  @override
  CustomPainter painter(BoothModel m) => _FactoryPainter(m);
}

class _FactoryPainter extends CustomPainter {
  _FactoryPainter(this.m) : super(repaint: m);

  final BoothModel m;

  @override
  void paint(Canvas c, Size size) {
    final st = Paint()
      ..style = PaintingStyle.stroke
      ..color = BP.line
      ..strokeWidth = 1.4;
    c.drawRect(BL.factory, st);
    c.drawLine(const Offset(BL.beltStart, BL.beltY), const Offset(BL.beltEnd, BL.beltY), st);
  }

  @override
  bool shouldRepaint(_FactoryPainter old) => false;
}
