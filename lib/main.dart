import 'package:flutter/material.dart';

import 'deck/deck.dart';
import 'deck/theme.dart';
import 'slides/registry.dart';
import 'worlds/worlds.dart';

void main() => runApp(const SlidesApp());

class SlidesApp extends StatelessWidget {
  const SlidesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Text rendering in Flutter',
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
          child: Deck(worlds: worlds, initial: worldFromEnvironment(), slidesFor: buildSlides),
        ),
      ),
    );
  }
}
