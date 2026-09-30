import 'package:flutter/material.dart';

import 'deck/deck.dart';
import 'deck/theme.dart';
import 'simple/simple_deck.dart';
import 'simple/simple_world.dart';

/// The macOS build of just the simplified talk, "Inside Flutter's Text
/// Pipeline" (no version picker, no other worlds, no side-quest labs):
///
///     flutter build macos --release -t lib/main_simple.dart
void main() => runApp(const SimpleSlidesApp());

class SimpleSlidesApp extends StatelessWidget {
  const SimpleSlidesApp({super.key});

  @override
  Widget build(BuildContext context) {
    const world = SimpleFactoryWorld();
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
      home: const Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle(
          style: TextStyle(fontFamily: BP.display, fontSize: 16, color: BP.ink),
          child: Deck(worlds: [world], initial: world, slidesFor: buildSimpleSlides),
        ),
      ),
    );
  }
}
