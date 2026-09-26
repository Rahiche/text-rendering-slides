import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_slides/deck/font_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('JP and SC subsets draw the same code point differently', () async {
    final jp = await FontData.load('assets/fonts/NotoSansJP-case.ttf', 'Noto Sans JP');
    final sc = await FontData.load('assets/fonts/NotoSansSC-case.ttf', 'Noto Sans SC');
    for (final ch in '直骨角今令海写次化起画誤'.runes) {
      final a = jp.outline(jp.glyphId(ch));
      final b = sc.outline(sc.glyphId(ch));
      debugPrint('${String.fromCharCode(ch)} U+${ch.toRadixString(16).toUpperCase()}  '
          'JP #${jp.glyphId(ch)} ${a.contours.length}c/${a.pointCount}p  '
          'SC #${sc.glyphId(ch)} ${b.contours.length}c/${b.pointCount}p');
      expect(jp.has(ch) && sc.has(ch), isTrue);
    }
  });
}
