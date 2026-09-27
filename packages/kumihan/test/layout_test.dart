// Layout tests with a real Japanese font. They load Hiragino Sans from macOS
// (/System/Library/Fonts) and are skipped where it is not installed.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumihan/kumihan.dart';

const _w3 = '/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc';
const _w6 = '/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc';
final bool hasFont = File(_w3).existsSync() && File(_w6).existsSync();
final Object skip = hasFont ? false : 'Hiragino Sans not installed';

Future<void> loadFont() async {
  final l = FontLoader('Hiragino Sans');
  for (final p in [_w3, _w6]) {
    l.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
  }
  await l.load();
}

const style = TextStyle(fontFamily: 'Hiragino Sans', fontSize: 32, locale: Locale('ja'));

/// (source start, source end) of each line of [display] laid out at [w].
List<(int, int)> lineRanges(KumihanPrepared? p, String display, double w, {TextStyle st = style}) {
  final tp = TextPainter(
    text: TextSpan(text: display, style: st),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: w);
  final out = <(int, int)>[];
  var s = 0;
  while (s < display.length) {
    final r = tp.getLineBoundary(TextPosition(offset: s));
    final a = p?.toSource(r.start) ?? r.start;
    final b = p?.toSource(r.end) ?? r.end;
    out.add((a, b));
    if (r.end <= s) break;
    s = r.end;
  }
  tp.dispose();
  return out;
}

/// Kinsoku violations: a line starting with a start-prohibited character or
/// ending with an opening bracket.
List<String> violations(String src, List<(int, int)> lines) {
  final out = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final (a, b) = lines[i];
    if (a >= b) continue;
    if (i > 0 && isLineStartProhibited(src.codeUnitAt(a))) out.add('start:${src[a]}');
    if (i < lines.length - 1 && isLineEndProhibited(src.codeUnitAt(b - 1))) out.add('end:${src[b - 1]}');
  }
  return out;
}

void main() {
  setUpAll(() async {
    if (hasFont) await loadFont();
  });

  const texts = [
    '東京都渋谷区で開催される技術カンファレンスに参加しました',
    'Flutterで日本語の改行をきれいにする方法',
    '今日は天気です。明日も晴れるでしょう。',
    'テキストレンダリングの仕組みを理解しよう',
    'ジャーナリストのキャッシュフローはチェックしてください。「ちょっと」待って、ヴァイオリンのコンサートへ行きましょう！',
  ];

  test('word joiners are zero-width', () {
    for (final t in texts) {
      final a = TextPainter(text: TextSpan(text: t, style: style), textDirection: TextDirection.ltr)..layout();
      final b = TextPainter(text: TextSpan(text: Kumihan.prepare(t), style: style), textDirection: TextDirection.ltr)
        ..layout();
      expect(b.width, closeTo(a.width, 0.01), reason: t);
      expect(b.height, a.height, reason: t);
      a.dispose();
      b.dispose();
    }
  }, skip: skip);

  test('Flutter splits words and breaks kinsoku; kumihan never does', () {
    var plainSplits = 0;
    final plainViolations = <String>{};
    for (final t in texts) {
      final layout = KumihanLayout(t, style: style);
      final bounds = layout.phraseBoundaries.toSet();
      // From 5 characters per line: the longest kinsoku chain here, 「ちょっ,
      // is 4 characters (narrower lines cannot avoid a violation).
      for (var w = 160.0; w <= 900; w += 5) {
        // Today: breaks inside words, small kana / ー at line starts.
        final plain = lineRanges(null, t, w);
        for (final (_, b) in plain.take(plain.length - 1)) {
          if (!bounds.contains(b)) plainSplits++;
        }
        plainViolations.addAll(violations(t, plain));

        // kumihan: only phrase boundaries, unless the phrase is wider than w.
        final p = layout.prepare(w);
        final lines = lineRanges(p, p.text, w);
        expect(violations(t, lines), isEmpty, reason: '$t @ $w');
        for (final (_, b) in lines.take(lines.length - 1)) {
          if (bounds.contains(b)) continue;
          // A break inside a phrase: that phrase must be wider than the line.
          final start = [0, ...bounds].where((x) => x < b).last;
          final end = [...bounds, t.length].firstWhere((x) => x > b);
          final tp = TextPainter(text: TextSpan(text: t.substring(start, end), style: style), textDirection: TextDirection.ltr)
            ..layout();
          expect(tp.width, greaterThan(w - 1), reason: 'split "${t.substring(start, end)}" in $t @ $w');
          tp.dispose();
        }
      }
    }
    expect(plainSplits, greaterThan(0));
    // Flutter follows CSS line-break: normal (small kana and ー may start a line).
    expect(plainViolations.intersection({'start:ー', 'start:ッ', 'start:ャ', 'start:ョ', 'start:ァ'}), isNotEmpty);
  }, skip: skip);

  test('gluing an over-wide phrase would force an emergency break', () {
    // Glue everything regardless of width (what a naive implementation does).
    const t = '技術カンファレンスに参加しました。';
    final naive = Kumihan.prepare(t);
    final bad = <String>{};
    for (var w = 96.0; w <= 300; w += 4) {
      final p = KumihanLayout(t).prepare();
      bad.addAll(violations(t, lineRanges(p, naive, w)));
      // Width-aware: never.
      final q = KumihanLayout(t, style: style).prepare(w);
      expect(violations(t, lineRanges(q, q.text, w)), isEmpty, reason: '@ $w');
    }
    expect(bad, isNotEmpty);
  }, skip: skip);

  test('balance: narrowest width with the same line count', () {
    const t = 'Flutterで日本語の改行をきれいにする方法';
    const st = TextStyle(fontFamily: 'Hiragino Sans', fontSize: 40, locale: Locale('ja'));
    final layout = KumihanLayout(t, style: st);
    for (final w in [420.0, 500.0, 640.0]) {
      final p = layout.prepare(w);
      final n = lineRanges(p, p.text, w, st: st).length;
      final bw = layout.balancedWidth(w, prepared: p);
      expect(bw, lessThanOrEqualTo(w));
      final lines = lineRanges(p, p.text, bw, st: st);
      expect(lines.length, n);
      expect(lineRanges(p, p.text, bw - 2, st: st).length, greaterThan(n));
      // No orphan: the last line holds more than one character.
      expect(lines.last.$2 - lines.last.$1, greaterThan(1));
    }
  }, skip: skip);

  test('yakumono halt narrows adjacent punctuation only', () {
    const t = '「こんにちは」「世界」。';
    final plain = TextPainter(text: const TextSpan(text: t, style: style), textDirection: TextDirection.ltr)..layout();
    final yaku = TextPainter(text: Kumihan.yakumono(t, style: style), textDirection: TextDirection.ltr)..layout();
    // Two characters lose half an em each.
    expect(plain.width - yaku.width, closeTo(32.0, 0.5));
    plain.dispose();
    yaku.dispose();
  }, skip: skip);
}
