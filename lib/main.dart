import 'package:flutter/material.dart';

import 'booth/booth_app.dart';
import 'deck/deck.dart';
import 'deck/theme.dart';
import 'probe/slug_probe.dart';
import 'simple/simple_deck.dart';
import 'simple/simple_world.dart';
import 'slides/registry.dart';
import 'worlds/chooser.dart';
import 'worlds/world.dart';
import 'worlds/worlds.dart';

void main() {
  // compare/index.html embeds `?probe=slug` to show Text vs SlugText alone.
  if (Uri.base.queryParameters['probe'] == 'slug') {
    runApp(const SlugProbeApp());
    return;
  }
  // The conference-stall loop: /booth/ or ?booth.
  if (Uri.base.pathSegments.contains('booth') || Uri.base.queryParameters.containsKey('booth')) {
    runApp(const BoothApp());
    return;
  }
  runApp(const SlidesApp());
}

class SlidesApp extends StatelessWidget {
  const SlidesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Inside Flutter's Text Pipeline",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: BP.paper,
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: BP.amber,
          selectionColor: BP.line.withValues(alpha: 0.35),
        ),
      ),
      home: Material(
        type: MaterialType.transparency,
        // A neutral default (no Material letterSpacing / height), so Text
        // widgets measure exactly like the raw paragraphs the slides probe.
        child: DefaultTextStyle(
          style: const TextStyle(fontFamily: BP.display, fontSize: 16, color: BP.ink),
          child: const _Home(),
        ),
      ),
    );
  }
}

/// Opens the deck in the requested world, or shows the version picker first
/// (native runs have no URL to pick one).
class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  World? _world = requestedWorld();

  @override
  Widget build(BuildContext context) {
    final w = _world;
    if (w == null) {
      return WorldChooser(worlds: worlds, onPick: (w) => setState(() => _world = w));
    }
    if (w is SimpleFactoryWorld) {
      return Deck(worlds: [w], initial: w, slidesFor: buildSimpleSlides);
    }
    return Deck(worlds: worlds, initial: w, slidesFor: buildSlides);
  }
}
