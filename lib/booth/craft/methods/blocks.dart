import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../method.dart';

/// Toy blocks · ブロック. PLACEHOLDER: fills the glyph from the bottom up.
class BlocksCraft extends CraftMethod {
  const BlocksCraft();

  @override
  String get id => 'blocks';

  @override
  String get en => 'Toy blocks';

  @override
  String get ja => 'ブロック';

  @override
  Color get color => BP.green;

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
