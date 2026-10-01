import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../method.dart';

/// Kintsugi · 金継ぎ. PLACEHOLDER: fills the glyph from the bottom up.
class KintsugiCraft extends CraftMethod {
  const KintsugiCraft();

  @override
  String get id => 'kintsugi';

  @override
  String get en => 'Kintsugi';

  @override
  String get ja => '金継ぎ';

  @override
  Color get color => Mat.gold;

  @override
  double get weight => 1.05;

  @override
  void paintMaking(CraftContext x, double p) {
    x.c.drawPath(x.s.outline, x.st(BP.lineFaint, 1.2));
    x.fillRowsUp(p, Paint()..color = color);
  }

  @override
  void paintFinished(CraftContext x) => x.fillGlyph(Paint()..color = color);
}
