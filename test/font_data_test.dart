import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_slides/deck/font_data.dart';

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
}
