import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../method.dart';

/// 3D printing · 3Dプリント. PLACEHOLDER: fills the glyph from the bottom up.
class Print3dCraft extends CraftMethod {
  const Print3dCraft();

  @override
  String get id => 'print3d';

  @override
  String get en => '3D printing';

  @override
  String get ja => '3Dプリント';

  @override
  Color get color => Mat.plastic;

  @override
  double get weight => 1.0;

  @override
  void paintMaking(CraftContext x, double p) {
    x.c.drawPath(x.s.outline, x.st(BP.lineFaint, 1.2));
    x.fillRowsUp(p, Paint()..color = color);
  }

  @override
  void paintFinished(CraftContext x) => x.fillGlyph(Paint()..color = color);
}
