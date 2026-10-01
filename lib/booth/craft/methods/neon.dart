import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../method.dart';

/// Neon · ネオン管. PLACEHOLDER: fills the glyph from the bottom up.
class NeonCraft extends CraftMethod {
  const NeonCraft();

  @override
  String get id => 'neon';

  @override
  String get en => 'Neon';

  @override
  String get ja => 'ネオン管';

  @override
  Color get color => Mat.neon;

  @override
  double get weight => 0.95;

  @override
  void paintMaking(CraftContext x, double p) {
    x.c.drawPath(x.s.outline, x.st(BP.lineFaint, 1.2));
    x.fillRowsUp(p, Paint()..color = color);
  }

  @override
  void paintFinished(CraftContext x) => x.fillGlyph(Paint()..color = color);
}
