import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumihan/kumihan.dart';

const _w3 = '/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc';
final bool hasFont = File(_w3).existsSync();

const style = TextStyle(fontFamily: 'Hiragino Sans', fontSize: 40);

Widget app(Widget child) => MaterialApp(
  home: Material(
    child: Align(alignment: Alignment.topLeft, child: child),
  ),
);

RenderParagraph paragraph(WidgetTester tester) =>
    tester.renderObject<RenderParagraph>(find.descendant(of: find.byType(KumihanText), matching: find.byType(RichText)));

void main() {
  setUpAll(() async {
    if (!hasFont) return;
    final l = FontLoader('Hiragino Sans')..addFont(Future.value(ByteData.sublistView(File(_w3).readAsBytesSync())));
    await l.load();
  });

  testWidgets('renders the prepared text with word joiners, semantics without', (tester) async {
    const t = '今日は天気です。明日も晴れるでしょう。';
    await tester.pumpWidget(app(const SizedBox(width: 300, child: KumihanText(t, style: style))));
    final p = paragraph(tester);
    expect(p.text.toPlainText(), contains(Kumihan.wordJoiner));
    expect(Kumihan.strip(p.text.toPlainText()), t);
    expect(p.locale, const Locale('ja'));
    expect(find.bySemanticsLabel(t), findsOneWidget);
  });

  testWidgets('breaks between phrases only', (tester) async {
    const t = '今日は天気です。明日も晴れるでしょう。';
    // 340 px: every phrase fits (晴れるでしょう。 is 8 × 40 = 320 px).
    await tester.pumpWidget(app(const SizedBox(width: 340, child: KumihanText(t, style: style))));
    final p = painterOf(paragraph(tester));
    final plain = p.plainText;
    final bounds = KumihanLayout(t).phraseBoundaries.toSet();
    var s = 0;
    while (s < plain.length) {
      final r = p.getLineBoundary(TextPosition(offset: s));
      if (r.end < plain.length) {
        expect(bounds, contains(Kumihan.strip(plain.substring(0, r.end)).length));
      }
      if (r.end <= s) break;
      s = r.end;
    }
  }, skip: !hasFont);

  testWidgets('balance narrows the box but keeps the line count', (tester) async {
    const t = 'Flutterで日本語の改行をきれいにする方法';
    await tester.pumpWidget(app(const SizedBox(width: 560, child: KumihanText(t, style: style))));
    final plain = paragraph(tester);
    final n = _lineCount(plain);
    final plainWidth = plain.size.width;

    await tester.pumpWidget(app(const SizedBox(width: 560, child: KumihanText(t, style: style, balance: true))));
    final bal = paragraph(tester);
    expect(_lineCount(bal), n);
    expect(bal.size.width, lessThan(plainWidth));
    // The KumihanText itself still takes the full width.
    expect(tester.getSize(find.byType(KumihanText)).width, 560);
  }, skip: !hasFont);

  testWidgets('yakumono puts halt on adjacent punctuation', (tester) async {
    await tester.pumpWidget(app(const KumihanText('「東京」「大阪」', style: style, yakumono: true)));
    final halted = <String>[];
    paragraph(tester).text.visitChildren((s) {
      if (s is TextSpan && (s.style?.fontFeatures?.any((f) => f.feature == 'halt') ?? false)) halted.add(s.text!);
      return true;
    });
    expect(halted, ['」']);
  });

  testWidgets('KumihanSelectionArea strips word joiners on copy', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    const t = '今日は天気です。';
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(app(KumihanSelectionArea(focusNode: focus, child: const KumihanText(t, style: style))));
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(copied, t);
  });
}

/// A painter laid out exactly like [p] (RenderParagraph hides its own).
TextPainter painterOf(RenderParagraph p) => TextPainter(
  text: p.text,
  textDirection: p.textDirection,
  locale: p.locale,
  textScaler: p.textScaler,
)..layout(maxWidth: p.constraints.maxWidth);

int _lineCount(RenderParagraph rp) {
  final p = painterOf(rp);
  final text = p.plainText;
  var n = 0;
  var s = 0;
  while (s < text.length) {
    final r = p.getLineBoundary(TextPosition(offset: s));
    n++;
    if (r.end <= s) break;
    s = r.end;
  }
  return n;
}
