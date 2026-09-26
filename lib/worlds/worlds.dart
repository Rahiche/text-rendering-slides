import 'classic.dart';
import 'construction/construction_world.dart';
import 'detective/detective_world.dart';
import 'factory/factory_world.dart';
import 'workers/workers_world.dart';
import 'world.dart';

/// Every version of the deck. Order = the `w` key's cycle order.
const worlds = <World>[
  FactoryWorld(),
  ConstructionWorld(),
  WorkersWorld(),
  DetectiveWorld(),
  ClassicWorld(),
];

/// Picks the world from the URL (web): a path segment such as
/// `/text-rendering-slides/factory/`, or `?deck=factory`. Otherwise
/// `--dart-define=WORLD=factory`, else the classic blueprint deck.
World worldFromEnvironment() {
  World? byId(String? id) {
    for (final w in worlds) {
      if (w.id == id) return w;
    }
    return null;
  }

  final uri = Uri.base;
  return byId(uri.queryParameters['deck']) ??
      uri.pathSegments.map(byId).whereType<World>().firstOrNull ??
      byId(const String.fromEnvironment('WORLD')) ??
      const ClassicWorld();
}
