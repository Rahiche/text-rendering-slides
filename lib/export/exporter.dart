import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../deck/deck.dart';

/// Walks the deck like a presenter (every build step, in order), lets each
/// slide settle at its last step, and saves the 1600×900 canvas as PNG to
/// `<dir>/NN_<slide id>.png`. The app quits when done.
///
/// `--dart-define=EXPORT_ONLY=id1,id2` exports just those slides.
Future<void> exportDeck(
  DeckController c,
  GlobalKey canvasKey, {
  required String dir,
  double pixelRatio = 2,
  Duration step = const Duration(milliseconds: 1400),
  Duration settle = const Duration(milliseconds: 4200),
}) async {
  const only = String.fromEnvironment('EXPORT_ONLY');
  final ids = only.isEmpty ? null : only.split(',').map((s) => s.trim()).toSet();
  final out = Directory(dir)..createSync(recursive: true);
  for (final f in out.listSync()) {
    if (f.path.endsWith('.png')) f.deleteSync();
  }
  await Future<void>.delayed(const Duration(seconds: 2)); // fonts, shaders
  for (var i = 0; i < c.slides.length; i++) {
    final def = c.slides[i];
    if (ids != null && !ids.contains(def.id)) continue;
    c.goTo(i);
    await _frame(i);
    for (var s = 1; s < def.steps; s++) {
      await Future<void>.delayed(step);
      c.next();
    }
    await Future<void>.delayed(settle);
    await _frame(i);
    if (c.index != i || c.step != def.steps - 1) {
      stderr.writeln(
        'export: expected slide ${i + 1} step ${def.steps - 1}, at ${c.index + 1}/${c.step}',
      );
      exit(1);
    }
    final boundary = canvasKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final name = '${(i + 1).toString().padLeft(2, '0')}_${def.id}.png';
    File('${out.path}/$name').writeAsBytesSync(png!.buffer.asUint8List());
    stdout.writeln('exported $name');
  }
  stdout.writeln('EXPORT_DONE ${out.path}');
  exit(0);
}

/// Waits for a rendered frame. macOS stops drawing occluded windows and a
/// sleeping display, so fail loudly instead of saving a stale picture.
Future<void> _frame(int i) => WidgetsBinding.instance.endOfFrame.timeout(
  const Duration(seconds: 20),
  onTimeout: () {
    stderr.writeln('export: no frame for 20 s at slide ${i + 1} (window covered? display asleep?)');
    exit(2);
  },
);
