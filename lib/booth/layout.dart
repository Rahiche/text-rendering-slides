import 'dart:ui';

/// Scene geometry for the booth loop, on the deck's 1600×900 canvas.
///
/// This is the contract between the layers: each layer draws in its own
/// regions so they never fight over the same pixels.
abstract final class BL {
  static const size = Size(1600, 900);

  /// The ground line everything stands on (factory floor, slab, crane base).
  static const groundY = 700.0;

  // ── Sky & city (ambient layer, behind everything) ─────────────────────────
  /// Sky: the whole canvas above the ground. Sun 日 / moon 月 travel here.
  static const sky = Rect.fromLTRB(0, 0, 1600, groundY);

  /// Distant skyline band (buildings with glyph windows, neon signs).
  static const skyline = Rect.fromLTRB(0, 360, 1600, groundY);

  /// Elevated train line crossing the whole width, high in the background.
  static const trainY = 272.0;

  // ── Factory (left) ────────────────────────────────────────────────────────
  /// The factory hall: machines stand on [groundY].
  static const factory = Rect.fromLTRB(24, 380, 560, groundY);

  /// The belt from the factory's last machine to the crane pickup.
  static const beltY = 684.0;
  static const beltStart = 470.0;
  static const beltEnd = 640.0;

  /// Where the crane hooks pallets of bricks.
  static const pickup = Offset(612, 676);

  // ── Construction site (right) ─────────────────────────────────────────────
  /// The name is built in this box, bottom-centred on the slab at [groundY].
  static const plot = Rect.fromLTRB(660, 392, 1470, groundY);

  /// Scaffolding may extend this far around the plot.
  static const site = Rect.fromLTRB(640, 330, 1500, groundY);

  /// Tower crane: mast foot, mast top, jib height, jib reach (left end).
  static const craneMastX = 1538.0;
  static const craneJibY = 112.0;
  static const craneJibLeft = 580.0;

  // ── Street (foreground) ───────────────────────────────────────────────────
  /// Road for trucks, the bulldozer and passing traffic.
  static const road = Rect.fromLTRB(0, 724, 1600, 800);

  // ── UI overlay ────────────────────────────────────────────────────────────
  /// Name sign + "now building" board + queue (top-left, over the sky).
  static const board = Rect.fromLTRB(36, 26, 640, 250);

  /// Bottom band: the name input (left) and the built-today counter (right).
  static const bottom = Rect.fromLTRB(0, 806, 1600, 900);
  static const input = Rect.fromLTRB(36, 816, 760, 886);
}
