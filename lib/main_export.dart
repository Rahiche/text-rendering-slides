import 'dart:io';

import 'package:flutter/material.dart';

import 'deck/deck.dart';
import 'deck/theme.dart';
import 'export/exporter.dart';
import 'simple/simple_deck.dart';
import 'simple/simple_world.dart';
import 'slides/registry.dart';
import 'worlds/worlds.dart';

/// Saves every slide of one world, at its final step, as PNG (for the PDF):
///
///     flutter build macos --release -t lib/main_export.dart --dart-define=WORLD=factory-simple
///     SLIDES_EXPORT=1 build/macos/Build/Products/Release/text_slides.app/Contents/MacOS/text_slides
///
/// (tool/export_pdf.sh does both and assembles the PDF.)
///
/// Output: `<app temp dir>/slides_export/` (printed at the end).
void main() {
  final world = worldFromEnvironment();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: BP.paper),
      home: Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle(
          style: const TextStyle(fontFamily: BP.display, fontSize: 16, color: BP.ink),
          child: IgnorePointer(
            child: Deck(
              worlds: [world],
              initial: world,
              slidesFor: (w) => w is SimpleFactoryWorld ? buildSimpleSlides(w) : buildSlides(w),
              interactive: false,
              onReady: (c, key) => exportDeck(
                c,
                key,
                dir:
                    '${Directory.systemTemp.path}/slides_export/'
                    '${const String.fromEnvironment('EXPORT_TAG', defaultValue: 'deck')}',
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
