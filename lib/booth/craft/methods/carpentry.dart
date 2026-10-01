import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../method.dart';

/// Carpentry · 木工. PLACEHOLDER: fills the glyph from the bottom up.
class CarpentryCraft extends CraftMethod {
  const CarpentryCraft();

  @override
  String get id => 'carpentry';

  @override
  String get en => 'Carpentry';

  @override
  String get ja => '木工';

  @override
  Color get color => Mat.wood;

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
