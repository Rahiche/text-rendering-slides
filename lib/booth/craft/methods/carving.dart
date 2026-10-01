import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../method.dart';

/// Stone carving · 石彫. PLACEHOLDER: fills the glyph from the bottom up.
class CarvingCraft extends CraftMethod {
  const CarvingCraft();

  @override
  String get id => 'carving';

  @override
  String get en => 'Stone carving';

  @override
  String get ja => '石彫';

  @override
  Color get color => Mat.stone;

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
