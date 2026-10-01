import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../method.dart';

/// Casting · 鋳造. PLACEHOLDER: fills the glyph from the bottom up.
class CastingCraft extends CraftMethod {
  const CastingCraft();

  @override
  String get id => 'casting';

  @override
  String get en => 'Casting';

  @override
  String get ja => '鋳造';

  @override
  Color get color => Mat.bronze;

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
