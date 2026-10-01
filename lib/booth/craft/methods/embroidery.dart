import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../method.dart';

/// Embroidery · 刺繍. PLACEHOLDER: fills the glyph from the bottom up.
class EmbroideryCraft extends CraftMethod {
  const EmbroideryCraft();

  @override
  String get id => 'embroidery';

  @override
  String get en => 'Embroidery';

  @override
  String get ja => '刺繍';

  @override
  Color get color => Mat.thread;

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
