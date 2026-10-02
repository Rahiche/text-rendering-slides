/// The city's street plan, shared by the city, its props and its life.
///
/// Metres; x east, y up, z north. The camera is on the −Z side looking
/// north at the plaza, so the avenue runs in front of the plaza and the city
/// rises behind and to the sides of it.
abstract final class Plan {
  /// The front avenue runs along x between these z.
  static const aveZ0 = -19.0, aveZ1 = -11.0;
  static double get aveZ => (aveZ0 + aveZ1) / 2;

  /// Lanes (Japan keeps left): eastbound on the north half, westbound south.
  static const laneEast = -13.0, laneWest = -17.0;

  /// Side streets run along z, centred on x = ±[streetX].
  static const streetX = 22.5, streetHalf = 3.5;

  /// Road surface height (a curb below the sidewalks).
  static const road = -0.06;

  /// The plaza block (with its 2 m sidewalk ring) spans x ∈ ±[blockX],
  /// z ∈ [aveZ1, …); its open build area is x ∈ ±[plazaX], z ∈ [plazaZ0, plazaZ1].
  static const blockX = 19.0;
  static const plazaX = 17.0, plazaZ0 = -9.0, plazaZ1 = 8.0;

  /// The park behind the plaza.
  static const parkZ0 = 8.0, parkZ1 = 64.0;

  /// Crosswalks over the avenue, at the plaza's corners (x centres).
  static const crossX = [-16.5, 16.5];
  static const crossHalf = 1.6;

  /// Sidewalk centre lines.
  static const walkFront = -10.0; // between the avenue and the plaza
  static const walkFar = -20.0; // the camera side of the avenue
  static const walkFlank = 18.0; // x = ±walkFlank, the plaza block's sides
  static const walkBlock = 27.0; // x = ±walkBlock, the outer blocks' fronts

  /// Where people walk (keeping left of these lines, up to 0.35 m) and
  /// where the furniture stands, clear of them.
  static const peopleFront = -10.3, peopleFlank = 18.0;
  static const peopleFar = [-20.6, -20.0];
  static const peopleBlock = [27.1, 27.6];
  static const lampFlank = 18.75, lampFar = aveZ0 - 2.3, bollardZ = aveZ1 + 0.2;

  /// Lots the mini world's scenes (vignette.dart) have instead of the
  /// city's own blocks, trees, lamps and benches (x0, z0, x1, z1).
  static const lots = [
    (-41.0, 4.6, -24.0, 17.8), (24.0, 5.6, 41.0, 20.0), // bidi, atlas
    (28.0, 84.0, 40.0, 100.0), (-15.8, 73.6, -2.2, 84.4), // tower, farm
    (1.5, 69.5, 18.5, 87.0), (24.0, 21.5, 41.0, 37.0), // relay, itemize
    (-41.0, 19.5, -24.0, 31.0), (-11.0, 55.0, -2.5, 65.0), (2.5, 50.5, 11.5, 64.0), // locale, ruby, hyphenation
  ];

  /// Whether (x, z) is on one of the [lots] ([margin] metres round it).
  static bool inLot(double x, double z, [double margin = 0]) =>
      lots.any((l) => x > l.$1 - margin && x < l.$3 + margin && z > l.$2 - margin && z < l.$4 + margin);
}
