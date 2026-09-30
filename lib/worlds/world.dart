import 'package:flutter/widgets.dart';

import '../deck/deck.dart';

/// A section divider's content, handed to [World.section].
class SectionInfo {
  const SectionInfo({
    required this.index,
    required this.number,
    required this.id,
    required this.title,
    required this.glyphs,
  });

  /// 0..4
  final int index;

  /// '01'..'05'
  final String number;

  /// Section id used in the ruler / kicker: basics, scripts, others, flutter, journey.
  final String id;
  final String title;
  final List<String> glyphs;
}

/// Builds a slide transition. [animation] runs 0→1 for the incoming slide and
/// 1→0 for the outgoing one. Keep the returned widget structure constant for
/// the whole animation so slide state survives.
typedef WorldTransition =
    Widget Function(
      BuildContext context,
      Widget child,
      Animation<double> animation, {
      required bool incoming,
      required bool forward,
    });

/// A version of the deck: the same interactive content slides, told inside
/// one visual story (a factory, a construction site, a crew of workers…).
///
/// Everything except [id], [name], [title] and [section] is optional; `null`
/// means "use the default blueprint version".
abstract class World {
  const World();

  /// URL path segment and `?deck=` value: e.g. 'factory'.
  String get id;
  String get name;

  /// The intro slide.
  Widget title();

  /// A section divider.
  Widget section(SectionInfo s);

  /// Replaces the pipeline overview slide ('pipeline', 7 build steps).
  Widget? pipeline() => null;

  /// Replaces the journey overview ('j-map').
  Widget? journeyMap() => null;

  /// An extra closing slide appended after 'The trade-off'.
  Widget? outro() => null;

  /// Story slides this world inserts right after the shared slide [slideId]
  /// (e.g. a clue after 'string'). Their ids must be unique across the deck.
  List<SlideDef> after(String slideId) => const [];

  /// Painted behind every standard content slide (anything using
  /// SlideFrame), across the full 1600×900 canvas. Keep it in the margins:
  /// the content area is x 64–1536, y 176–804; the title sits top-left.
  Widget? ambient(BuildContext context) => null;

  /// Replaces the bottom progress ruler. Gets the full-width bottom band
  /// (y 790–900 on the canvas). Must let the presenter click to jump.
  Widget? ruler(DeckController controller) => null;

  /// Replaces the blueprint wipe between slides.
  WorldTransition? get transition => null;

  /// Quieter chrome for the simplified deck (e.g. no "03 / basics" kicker).
  bool get minimal => false;
}

/// Makes the current [World] available to slides.
class WorldScope extends InheritedWidget {
  const WorldScope({super.key, required this.world, required super.child});

  final World world;

  static World? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorldScope>()?.world;

  @override
  bool updateShouldNotify(WorldScope old) => old.world.id != world.id;
}
