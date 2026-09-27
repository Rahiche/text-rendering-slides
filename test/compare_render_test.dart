// Renders compare/cases.json with Flutter's Text and with KumihanText, using
// the same font file, size, width and line height as compare/index.html, and
// writes compare/out/flutter/<id>_<mode>.png plus the actual line breaks.
//
// Run through compare/capture.sh (it fetches the font first).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumihan/kumihan.dart';

const _fontFile = 'compare/fonts/NotoSansJP.ttf';
const _out = 'compare/out/flutter';
const _pad = 16.0;

void main() {
  final font = File(_fontFile);
  final missing = !font.existsSync();

  setUpAll(() async {
    if (missing) return;
    final bytes = ByteData.sublistView(font.readAsBytesSync());
    await (FontLoader('NotoSansJP')..addFont(Future.value(bytes))).load();
  });

  testWidgets('render compare cases', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Directory(_out).createSync(recursive: true);

    final cases = (jsonDecode(File('compare/cases.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    final report = <String, Map<String, dynamic>>{};

    for (final c in cases) {
      final id = c['id'] as String;
      final text = c['text'] as String;
      final width = (c['width'] as num).toDouble();
      final style = TextStyle(
        fontFamily: 'NotoSansJP',
        fontSize: (c['fontSize'] as num).toDouble(),
        height: 1.5,
        leadingDistribution: TextLeadingDistribution.even,
        color: const Color(0xFF111111),
        // The variable font's default instance is Thin (100): ask for 400
        // explicitly, as the CSS side does with font-weight: 400.
        fontVariations: const [FontVariation('wght', 400)],
        locale: const Locale('ja'),
      );
      report[id] = {};

      for (final mode in ['text', 'kumihan']) {
        final key = GlobalKey();
        final Widget label = mode == 'text'
            ? Text(text, style: style)
            : KumihanText(text, style: style, balance: c['balance'] == true, yakumono: true);
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: DefaultTextStyle(
                style: const TextStyle(),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: RepaintBoundary(
                    key: key,
                    child: ColoredBox(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(_pad),
                        child: SizedBox(width: width, child: label),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Where did the lines actually break? Re-lay out the RichText's own
        // span at the width it received (KumihanText may balance narrower).
        final rp = tester.renderObject<RenderParagraph>(
          find.descendant(of: find.byKey(key), matching: find.byType(RichText)),
        );
        final tp = TextPainter(text: rp.text, textDirection: TextDirection.ltr)
          ..layout(maxWidth: rp.constraints.maxWidth);
        final plain = rp.text.toPlainText();
        final lines = <String>[];
        var start = 0;
        while (start < plain.length) {
          final end = tp.getLineBoundary(TextPosition(offset: start)).end;
          if (end <= start) break;
          lines.add(Kumihan.strip(plain.substring(start, end)).trimRight());
          start = end;
        }
        report[id]![mode] = {
          'lines': lines,
          'longestLine': tp.computeLineMetrics().fold<double>(0, (a, m) => a > m.width ? a : m.width),
        };
        tp.dispose();

        await tester.runAsync(() async {
          final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$_out/${id}_$mode.png').writeAsBytesSync(png!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    File('$_out/lines.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  }, skip: missing);
}
