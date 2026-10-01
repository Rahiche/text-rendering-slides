import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../method.dart';

/// Spray stencil · ステンシル. PLACEHOLDER: fills the glyph from the bottom up.
class StencilCraft extends CraftMethod {
  const StencilCraft();

  @override
  String get id => 'stencil';

  @override
  String get en => 'Spray stencil';

  @override
  String get ja => 'ステンシル';

  @override
  Color get color => BP.violet;

  @override
  double get weight => 0.85;

  @override
  void paintMaking(CraftContext x, double p) {
    x.c.drawPath(x.s.outline, x.st(BP.lineFaint, 1.2));
    x.fillRowsUp(p, Paint()..color = color);
  }

  @override
  void paintFinished(CraftContext x) => x.fillGlyph(Paint()..color = color);
}
