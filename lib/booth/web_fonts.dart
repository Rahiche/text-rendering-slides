import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// On the web, characters outside the bundled fonts (Japanese, Arabic,
/// Devanagari…) come from Noto fallback fonts that Flutter downloads on first
/// use; text rasterized before they arrive shows tofu (□), and the booth
/// rasterizes names into bricks and meshes only once.
///
/// Lays [text] out in [style] (which starts any downloads), then waits until
/// the platform's fonts stop changing: up to [firstWait] for the first font
/// to arrive, then [quiet] with no further changes, never longer than [max].
/// A no-op off the web.
Future<void> awaitFallbackFonts(
  String text, {
  TextStyle style = const TextStyle(fontSize: 32, locale: Locale('ja')),
  Duration firstWait = const Duration(milliseconds: 2000),
  Duration quiet = const Duration(milliseconds: 350),
  Duration max = const Duration(seconds: 8),
}) async {
  if (!kIsWeb || text.trim().isEmpty) return;
  final done = Completer<void>();
  Timer? timer;
  void finish() {
    if (!done.isCompleted) done.complete();
  }

  void changed() {
    timer?.cancel();
    timer = Timer(quiet, finish);
  }

  final fonts = PaintingBinding.instance.systemFonts;
  fonts.addListener(changed);
  timer = Timer(firstWait, finish);
  TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)
    ..layout()
    ..dispose();
  await done.future.timeout(max, onTimeout: () {});
  timer?.cancel();
  fonts.removeListener(changed);
}
