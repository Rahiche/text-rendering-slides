import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_slides/deck/deck.dart';
import 'package:text_slides/slides/registry.dart';
import 'package:text_slides/worlds/worlds.dart';

Future<void> _loadFonts() async {
  const fonts = {
    'SpaceGrotesk': 'assets/fonts/SpaceGrotesk.ttf',
    'JetBrainsMono': 'assets/fonts/JetBrainsMono.ttf',
    'NotoKufiArabic': 'assets/fonts/NotoKufiArabic.ttf',
    'CaseJP': 'assets/fonts/NotoSansJP-case.ttf',
    'CaseSC': 'assets/fonts/NotoSansSC-case.ttf',
  };
  for (final e in fonts.entries) {
    await (FontLoader(e.key)..addFont(rootBundle.load(e.value))).load();
  }
}

/// Walks every build step of every slide in every world and fails on any
/// exception. Layout overflows are reported, not fatal: flutter_test has no
/// platform fallback fonts, so CJK/emoji metrics differ from real devices.
int _step = 0;

/// The slide id shown at a global build-step index.
String slidesAtStep(List<SlideDef> slides, int step) {
  var n = step;
  for (final s in slides) {
    if (n < s.steps) return s.id;
    n -= s.steps;
  }
  return slides.last.id;
}

void main() {
  setUpAll(_loadFonts);
  for (final world in worlds) {
    testWidgets('walk the ${world.id} deck', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final slides = buildSlides(world);
      final steps = slides.fold<int>(0, (a, s) => a + s.steps);
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            type: MaterialType.transparency,
            child: Deck(worlds: [world], initial: world, slidesFor: buildSlides),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final overflows = <String>{};
      final original = FlutterError.onError;
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) {
          overflows.add('${slidesAtStep(slides, _step)}: ${msg.split('\n').first}');
        } else {
          original?.call(details);
        }
      };
      for (var i = 0; i < steps - 1; i++) {
        _step = i + 1;
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pump(const Duration(milliseconds: 450));
        final e = tester.takeException();
        if (e != null) fail('${world.id}: step $i → $e');
      }
      FlutterError.onError = original;
      for (final o in overflows) {
        debugPrint('  overflow (${world.id}) $o');
      }
      // Tear down cleanly: replace the deck so tickers and timers stop.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      expect(slides.map((s) => s.id).toSet().length, slides.length, reason: 'unique slide ids');
      debugPrint('${world.id}: ${slides.length} slides, $steps steps OK');
    });
  }
}
