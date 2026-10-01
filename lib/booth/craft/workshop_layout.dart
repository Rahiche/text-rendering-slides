import 'dart:ui';

/// Geometry of the Name Workshop (craft mode) on the 1600×900 canvas.
/// The city (ambient layer) and the UI keep their regions from `BL`.
abstract final class BW {
  /// Floor everything stands on (same as BL.groundY).
  static const floorY = 700.0;

  /// The workshop hall: two columns and a roof beam framing the stage.
  static const hall = Rect.fromLTRB(648, 118, 1496, floorY);

  /// The gantry crane's beam under the roof.
  static const beamY = 150.0;

  /// The name sign the finished characters are hung on, one by one.
  static const sign = Rect.fromLTRB(668, 180, 1476, 304);

  /// Low stage the character is made on.
  static const dais = Rect.fromLTRB(764, 684, 1356, floorY);

  /// Largest box the character being made may fill (bottom on the dais).
  static const make = Rect.fromLTRB(830, 366, 1290, 684);

  /// The drafting office (left): blueprint of the character, craft plan.
  static const office = Rect.fromLTRB(24, 372, 610, floorY);
}
