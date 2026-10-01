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
/// Characters waited for before (in the same locale) don't wait again, nor
/// does ASCII (the bundled fonts have it). A no-op off the web.
Future<void> awaitFallbackFonts(
  String text, {
  TextStyle style = const TextStyle(fontSize: 32, locale: Locale('ja')),
  Duration firstWait = const Duration(milliseconds: 2000),
  Duration quiet = const Duration(milliseconds: 350),
  Duration max = const Duration(seconds: 8),
}) => awaitFallbackFontsAll([(text, style)], firstWait: firstWait, quiet: quiet, max: max);

/// [awaitFallbackFonts] for several runs at once: all their downloads start
/// together and one wait covers them, so it takes as long as the slowest
/// font, not the sum of them all.
Future<void> awaitFallbackFontsAll(
  List<(String, TextStyle)> runs, {
  Duration firstWait = const Duration(milliseconds: 2000),
  Duration quiet = const Duration(milliseconds: 350),
  Duration max = const Duration(seconds: 8),
}) async {
  if (!kIsWeb) return;
  final cold = [
    for (final (text, style) in runs)
      if (_cold(text, style)) (text, style),
  ];
  if (cold.isEmpty) return;
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
  for (final (text, style) in cold) {
    TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )
      ..layout()
      ..dispose();
  }
  await done.future.timeout(max, onTimeout: () {});
  timer?.cancel();
  fonts.removeListener(changed);
  for (final (text, style) in cold) {
    (_warm[_locale(style)] ??= {}).addAll(text.runes.where((r) => r >= 0x80));
  }
}

/// Characters already waited for, per locale (Han characters take their
/// glyphs from a different font in Japanese, Chinese and Korean).
final _warm = <String, Set<int>>{};

String _locale(TextStyle style) => style.locale?.toLanguageTag() ?? '';

bool _cold(String text, TextStyle style) {
  final warm = _warm[_locale(style)];
  return text.runes.any((r) => r >= 0x80 && !(warm?.contains(r) ?? false));
}
