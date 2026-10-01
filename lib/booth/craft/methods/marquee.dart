import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../method.dart';

/// Light bulbs · 電飾. PLACEHOLDER: fills the glyph from the bottom up.
class MarqueeCraft extends CraftMethod {
  const MarqueeCraft();

  @override
  String get id => 'marquee';

  @override
  String get en => 'Light bulbs';

  @override
  String get ja => '電飾';

  @override
  Color get color => BP.amber;

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
