import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import '../world/shot.dart';

/// What the talk's card says at a stop: its name (Japanese, as the city's
/// signs have it, and English), what happens there, and the facts, with the
/// talk's own numbers. [opener]: a section's first card (its number and
/// title, large).
class TalkCard {
  const TalkCard(this.title, this.lede, [this.facts = const [], this.opener = false, this.kicker = '']);

  final String title, lede;

  /// A line over the title (the thanks: ありがとうございました).
  final String kicker;
  final List<CardFact> facts;
  final bool opener;
}

sealed class CardFact {
  const CardFact();
}

/// A value with its label ([accent]: the one to look at), and an
/// [example] under it (a | in it is a place a line may break).
class FactRow extends CardFact {
  const FactRow(this.label, this.value, {this.accent = false, this.example});
  final String label, value;
  final bool accent;
  final String? example;
}

/// A few samples measured several ways: the columns' names (the first is
/// the samples'), a row a sample, the column to look at ([lit]).
class FactTable extends CardFact {
  const FactTable(this.columns, this.rows, {this.lit});
  final List<String> columns;
  final List<List<String>> rows;
  final int? lit;
}

/// A few lines of code.
class FactCode extends CardFact {
  const FactCode(this.code);
  final String code;
}

/// Points on a line between two ends ([left], [right]): each a name at a
/// value from −1 (the left end) to 1 (the right) ([accent]: the one to
/// look at).
class FactScale extends CardFact {
  const FactScale(this.left, this.right, this.points);
  final String left, right;
  final List<(String, double, bool)> points;
}

/// A word letter by letter (or any short items), a value under each
/// ([lit]: the one being looked at).
class FactLetters extends CardFact {
  const FactLetters(this.label, this.cells);
  final String label;
  final List<(String, String, bool)> cells;
}

/// Something in the city named where it is (a callout following the
/// camera): where, its name; a step's number ([order]: they come up one
/// after another) and a word after the name ([sub], dimmer).
class TalkPin {
  const TalkPin(this.at, this.name, {this.order, this.sub});
  final vm.Vector3 at;
  final String name;
  final int? order;
  final String? sub;
}

/// One beat of the talk: the stop it belongs to (a stop has one or more),
/// where the camera goes, how long it takes to get there, and how far right
/// of the middle what it looks at sits (of the half width: the card's on the
/// left).
class TalkBeat {
  const TalkBeat(this.stop, this.shot, {this.fly = 2.2, this.shift = 0.3, this.pull = 1, this.pins = const [], this.live, this.cardAt = 0, this.chapter = false});

  final int stop;
  final Shot shot;
  final double fly, shift;

  /// How far back from what it looks at the camera stands (of the shot's
  /// own distance): room for a wide subject beside the card.
  final double pull;

  /// Where the camera is this frame, when it follows something (a scene's
  /// own camera): instead of [shot].
  final Shot Function()? live;

  /// Named in the city while the beat's on (once the camera's there).
  final List<TalkPin> pins;

  /// Seconds into the beat (flown to) before its card comes up.
  final double cardAt;

  /// Opens a chapter: the section's number, title and glyphs large in the
  /// middle until the card comes up.
  final bool chapter;
}

/// One section of the talk, told in the city: its number and title (as the
/// deck's), its stops, the camera's beats through them, a card a stop; and
/// what it does to the world while it's on (the journey runs the Glyph
/// Works on its own clock, the others call on a scene to play).
abstract class TalkSection {
  /// '05' (empty: the title and the end).
  String get number;
  String get title;

  /// The stops' short names, for the way along the bottom.
  List<String> get stops;

  /// Its glyphs, as the deck's divider shows them.
  List<String> get glyphs => const [];
  List<TalkBeat> get beats;
  TalkCard card(int stop);

  /// The talk's come to this section, or left it.
  void enter() {}
  void leave() {}

  /// Beat [beat] is on: [cut] when it was cut to (back, a jump), not flown
  /// to (set the world as the beat left it).
  void arrive(int beat, {required bool cut}) {}

  /// Every frame while on, before the site's update: [age] seconds into
  /// [beat], which the camera takes [TalkBeat.fly] to get to.
  void update(int beat, double age, double t, double dt) {}

  /// Every frame while on, after the site's update (captions).
  void caption(int beat, double age) {}

  /// Got ready (the capture waits for it).
  Future<void>? get pending => null;
}

/// A framing from its eye and target (and fov), drifting a little.
/// The shot that a beat's framing (Talk: pulled back [pull] times from
/// what it looks at, then slid left by [shift] of the half width) turns
/// into [s]: a camera that ends up exactly where [s] is.
Shot unframed(Shot s, double shift, double pull) {
  final f = s.target - s.eye;
  final d = f.length;
  final right = vm.Vector3(0, 1, 0).cross(f)..normalize();
  final by = right * (shift * d * math.tan(s.fov * math.pi / 360) * 16 / 9);
  final eye = s.eye + by, target = s.target + by;
  return Shot(target + (eye - target) / pull, target, fov: s.fov, settle: s.settle, drift: s.drift);
}

Shot talkShot(double ex, double ey, double ez, double tx, double ty, double tz, double fov, {double drift = 0.35}) =>
    Shot(vm.Vector3(ex, ey, ez), vm.Vector3(tx, ty, tz), fov: fov, drift: drift);
