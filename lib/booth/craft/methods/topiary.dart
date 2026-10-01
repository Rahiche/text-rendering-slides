import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../method.dart';

/// Topiary · 植木. PLACEHOLDER: fills the glyph from the bottom up.
class TopiaryCraft extends CraftMethod {
  const TopiaryCraft();

  @override
  String get id => 'topiary';

  @override
  String get en => 'Topiary';

  @override
  String get ja => '植木';

  @override
  Color get color => Mat.leaf;

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
