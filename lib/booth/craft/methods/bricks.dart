import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../method.dart';

/// Bricklaying · レンガ積み. PLACEHOLDER: fills the glyph from the bottom up.
class BricksCraft extends CraftMethod {
  const BricksCraft();

  @override
  String get id => 'bricks';

  @override
  String get en => 'Bricklaying';

  @override
  String get ja => 'レンガ積み';

  @override
  Color get color => Mat.brick;

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
