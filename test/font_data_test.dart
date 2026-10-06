import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_slides/deck/font_data.dart';
import 'package:text_slides/slides/journey/journey.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('parses Space Grotesk', () async {
    final f = await FontData.spaceGrotesk();
    debugPrint('upem ${f.unitsPerEm} glyphs ${f.numGlyphs} cmap fmt ${f.cmapFormat} segs ${f.segments.length} axes ${f.axes}');
    for (final ch in 'Flutter Typecafé'.runes) {
      final g = f.glyphId(ch);
      final o = f.outline(g);
      debugPrint('${String.fromCharCode(ch)} gid $g adv ${f.advance(g)} lsb ${f.leftSideBearing(g)} contours ${o.contours.length} pts ${o.pointCount} bounds ${o.bounds}');
    }
    expect(f.glyphId('F'.codeUnitAt(0)), isNot(0));
    final a = await FontData.notoKufiArabic();
    for (final ch in 'مرحبا'.runes) {
      final g = a.glyphId(ch);
      debugPrint('ar ${ch.toRadixString(16)} gid $g adv ${a.advance(g)} contours ${a.outline(g).contours.length}');
    }
    debugPrint('space grotesk has arabic: ${f.has(0x0645)}; tables ${f.tables.keys.toList()}');
  });
  test('shapes with the fonts\' default ligatures', () async {
    final f = await FontData.spaceGrotesk();
    final a = await FontData.notoKufiArabic();
    final t = f.glyphId('t'.codeUnitAt(0));
    expect(f.ligatureAt([t, t]), (906, 2));
    expect(f.ligatureAt([t]), isNull);
    // f i, f l, f f i: longest first.
    final ff = f.glyphId('f'.codeUnitAt(0)), i = f.glyphId('i'.codeUnitAt(0));
    expect(f.ligatureAt([ff, ff, i])?.$2, 3);
    // The journey's words: the glyphs the paragraph draws.
    final counts = {for (final w in journeyPresets) w: JourneyData(w, f, a).run.length};
    expect(counts, {'Flutter': 6, 'Type': 4, 'café': 4, 'مرحبا': 5, '👋🏽': 1});
    final flutter = JourneyData('Flutter', f, a);
    expect(flutter.run.map((r) => r.glyphId), [9, 41, 50, 906, 34, 47]);
    expect(flutter.run[3].parts, [3, 4]);
    expect(flutter.shaped(liga: false).length, 7);
    expect(flutter.quads, 6);
    expect(flutter.atlasGlyphs, 6);
  });
}
