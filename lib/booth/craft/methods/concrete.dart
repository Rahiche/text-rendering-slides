import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../method.dart';

/// Concrete pour · コンクリート. PLACEHOLDER: fills the glyph from the bottom up.
class ConcreteCraft extends CraftMethod {
  const ConcreteCraft();

  @override
  String get id => 'concrete';

  @override
  String get en => 'Concrete pour';

  @override
  String get ja => 'コンクリート';

  @override
  Color get color => Mat.concrete;

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
