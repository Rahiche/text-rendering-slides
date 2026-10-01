import 'package:flutter/rendering.dart';

import '../../deck/theme.dart';
import '../layer.dart';
import '../layout.dart';
import '../model.dart';

/// The city of text around the factory: sky (day/night), skyline, train,
/// clouds, birds, traffic. Reads only the scene time.
class AmbientLayer extends BoothLayer {
  @override
  CustomPainter painter(BoothModel m) => _AmbientPainter(m);
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.m) : super(repaint: m);

  final BoothModel m;

  @override
  void paint(Canvas c, Size size) {
    c.drawRect(Offset.zero & BL.size, Paint()..color = BP.paper);
    c.drawLine(
      const Offset(0, BL.groundY),
      const Offset(1600, BL.groundY),
      Paint()..color = BP.line,
    );
    c.drawRect(BL.road, Paint()..color = BP.panel);
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => false;
}
