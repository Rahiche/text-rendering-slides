import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../method.dart';

/// Laser cutting · レーザー切断. PLACEHOLDER: fills the glyph from the bottom up.
class LaserCraft extends CraftMethod {
  const LaserCraft();

  @override
  String get id => 'laser';

  @override
  String get en => 'Laser cutting';

  @override
  String get ja => 'レーザー切断';

  @override
  Color get color => Mat.steel;

  @override
  double get weight => 0.9;

  @override
  void paintMaking(CraftContext x, double p) {
    x.c.drawPath(x.s.outline, x.st(BP.lineFaint, 1.2));
    x.fillRowsUp(p, Paint()..color = color);
  }

  @override
  void paintFinished(CraftContext x) => x.fillGlyph(Paint()..color = color);
}
