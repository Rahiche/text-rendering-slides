import 'dart:ui';

import '../../deck/theme.dart';
import '../model.dart';
import '../raster.dart';
import 'factory_plan.dart';

// Pallets of bricks as the glyph factory draws them on its belt. Public so
// whoever takes a pallet over at BL.pickup (the site's crane) can draw it
// exactly the same: palletHeight tall, standing on BL.beltY, so its centre
// is BL.pickup.

/// Brick colour by coverage (as the placeholder wall on the site).
Color brickColor(double cover) => Color.lerp(BP.panel, BP.ink, cover)!;

/// Deck (4) plus four layers of bricks (3 each). Standing on [BL.beltY], a
/// pallet's centre is at [BL.pickup].
const palletHeight = 16.0;

const _deckColor = Color(0xFF3A3020);

/// How wide [j]'s pallets are: narrower when they come thick and fast, so
/// they never touch on the belt.
double palletWidth(Job j) {
  if (j.total == 0 || j.buildLen <= 0) return 24;
  return (FBelt.v * j.buildLen * palletSize / j.total - 4).clamp(14.0, 24.0);
}

final _deck = Paint();
final _deckEdge = Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = 0.8;
final _fill = Paint();

/// Draws pallet [i] of [raster] (bricks i·[palletSize]…, six to a layer,
/// bottom layer first, each tinted by its coverage) standing with its
/// underside centred on [bottom].
void paintPallet(Canvas c, NameRaster raster, int i, Offset bottom, {double width = 24, double opacity = 1}) {
  final x0 = bottom.dx - width / 2;
  final y = bottom.dy;
  final deck = Rect.fromLTRB(x0, y - 4, x0 + width, y - 1.5);
  _deck.color = _deckColor.withValues(alpha: opacity);
  c.drawRect(deck, _deck);
  _deckEdge.color = BP.amber.withValues(alpha: 0.6 * opacity);
  c.drawRect(deck, _deckEdge);
  _fill.color = BP.amber.withValues(alpha: 0.5 * opacity);
  for (final fx in [x0 + 1, bottom.dx - 1.5, x0 + width - 4]) {
    c.drawRect(Rect.fromLTWH(fx, y - 1.5, 3, 1.5), _fill);
  }
  final bw = (width - 1) / 6;
  const bh = 3.0;
  for (var k = 0; k < palletSize; k++) {
    final n = i * palletSize + k;
    if (n >= raster.bricks.length) break;
    final col = k % 6, layer = k ~/ 6;
    _fill.color = brickColor(raster.bricks[n].cover).withValues(alpha: opacity);
    c.drawRect(Rect.fromLTWH(x0 + 0.5 + col * bw, y - 4 - (layer + 1) * bh, bw - 0.6, bh - 0.6), _fill);
  }
}
