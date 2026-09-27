// Test vectors from google/budoux v0.9.2 (Apache License 2.0):
// tests/test_parser.py, javascript/src/tests/parser_test.ts and
// tests/quality/ja.tsv; plus outputs of the upstream Python parser.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kumihan/kumihan.dart';

void main() {
  group('BudouxParser (upstream unit tests)', () {
    const sentence = 'abcdeabcd';

    test('should separate if a strong feature item supports', () {
      final p = BudouxParser({
        'UW4': {'a': 10000},
      });
      expect(p.parse(sentence), ['abcde', 'abcd']);
    });

    test('should separate even if it makes a phrase of one character', () {
      final p = BudouxParser({
        'UW4': {'b': 10000},
      });
      expect(p.parse(sentence), ['a', 'bcdea', 'bcd']);
    });

    test('should return an empty list when the input is a blank string', () {
      expect(BudouxParser({}).parse(''), isEmpty);
    });

    test('separate_right_before_a model', () {
      final p = BudouxParser({
        'UW4': {'a': 1001},
      });
      expect(p.parse('xyzabcd'), ['xyz', 'abcd']);
      expect(p.parseBoundaries('xyzabcd'), [3]);
    });

    test('base score is -0.5 × total weight', () {
      final p = BudouxParser({
        'UW1': {'a': 3},
        'BW2': {'ab': -7},
      });
      expect(p.baseScore, 2.0);
    });

    test('works on code points (no split surrogate pairs)', () {
      final p = BudouxParser({
        'UW4': {'𠮷': 10000},
      });
      expect(p.parse('あ𠮷野家'), ['あ', '𠮷野家']);
      expect(p.parseBoundaries('あ𠮷野家'), [1]);
    });
  });

  group('default models (upstream test_parser.py)', () {
    test('ja', () {
      expect(
        Kumihan.phrases('Google の使命は、世界中の情報を整理し、世界中の人がアクセスできて使えるようにすることです。'),
        [
          'Google の',
          '使命は、',
          '世界中の',
          '情報を',
          '整理し、',
          '世界中の',
          '人が',
          'アクセスできて',
          '使えるように',
          'する',
          'ことです。',
        ],
      );
    });

    test('zh-hans', () {
      expect(
        Kumihan.phrases('我们的使命是整合全球信息，供大众使用，让人人受益。', lang: KumihanLang.zhHans),
        ['我们', '的', '使命', '是', '整合', '全球', '信息，', '供', '大众', '使用，', '让', '人', '人', '受益。'],
      );
    });

    test('zh-hant', () {
      expect(
        Kumihan.phrases('我們的使命是匯整全球資訊，供大眾使用，使人人受惠。', lang: KumihanLang.zhHant),
        ['我們', '的', '使命', '是', '匯整', '全球', '資訊，', '供', '大眾', '使用，', '使', '人', '人', '受惠。'],
      );
    });
  });

  test('ja quality regression set (upstream tests/quality/ja.tsv)', () {
    final lines = File('test/data/budoux_quality_ja.tsv').readAsLinesSync();
    var checked = 0;
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final expected = line.split('\t').last.trim().split('▁');
      expect(Kumihan.phrases(expected.join()), expected, reason: line);
      checked++;
    }
    expect(checked, 39);
  });

  test('matches the upstream Python parser on the demo headlines', () {
    const vectors = {
      'Flutterで日本語の改行をきれいにする方法': ['Flutterで', '日本語の', '改行を', 'きれいに', 'する', '方法'],
      '今日は天気です。明日も晴れるでしょう。': ['今日は', '天気です。', '明日も', '晴れるでしょう。'],
      'テキストレンダリングの仕組みを理解しよう': ['テキストレンダリングの', '仕組みを', '理解しよう'],
      '東京都渋谷区で開催される技術カンファレンスに参加しました': ['東京都渋谷区で', '開催される', '技術カンファレンスに', '参加しました'],
      '「こんにちは」「世界」。': ['「こんにちは」', '「世界」。'],
      'ジャーナリストのキャッシュフローはチェックしてください。': ['ジャーナリストの', 'キャッシュフローは', 'チェックしてください。'],
      '私はその人を常に先生と呼んでいた。だからここでもただ先生と書くだけで本名は打ち明けない。': [
        '私は', 'その', '人を', '常に', '先生と', '呼んでいた。', //
        'だから', 'ここでもただ', '先生と', '書くだけで', '本名は', '打ち明けない。',
      ],
    };
    vectors.forEach((s, phrases) => expect(Kumihan.phrases(s), phrases, reason: s));
  });
}
