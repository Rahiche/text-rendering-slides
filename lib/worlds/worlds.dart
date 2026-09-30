import '../simple/simple_world.dart';
import 'classic.dart';
import 'construction/construction_world.dart';
import 'detective/detective_world.dart';
import 'factory/factory_world.dart';
import 'workers/workers_world.dart';
import 'world.dart';

/// Every version of the deck. Order = the `w` key's cycle order. (The
/// simplified deck, [SimpleFactoryWorld], has its own slide list and is only
/// reached by its URL: `/factory-simple/`.)
const worlds = <World>[
  FactoryWorld(),
  ConstructionWorld(),
  WorkersWorld(),
  DetectiveWorld(),
  ClassicWorld(),
];

/// The world asked for by the URL (web): a path segment such as
/// `/text-rendering-slides/factory/`, or `?deck=factory`; otherwise
/// `--dart-define=WORLD=factory`. Null when nothing was asked for.
World? requestedWorld() {
  World? inList(String? id) {
    for (final w in worlds) {
      if (w.id == id) return w;
    }
    return null;
  }

  World? byId(String? id) =>
      id == const SimpleFactoryWorld().id ? const SimpleFactoryWorld() : inList(id);

  final uri = Uri.base;
  return byId(uri.queryParameters['deck']) ??
      uri.pathSegments.map(byId).whereType<World>().firstOrNull ??
      byId(const String.fromEnvironment('WORLD'));
}

/// [requestedWorld], else the classic blueprint deck.
World worldFromEnvironment() => requestedWorld() ?? const ClassicWorld();
