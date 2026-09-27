import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kumihan/kumihan.dart';

/// Shows word joiners as `|` so expectations are readable.
String show(String s) => s.replaceAll(Kumihan.wordJoiner, '|');

void main() {
  group('prepare (no width)', () {
    test('glues the characters inside each phrase', () {
      // Phrases: 今日は / 天気です。
      expect(show(Kumihan.prepare('今日は天気です。')), '今|日|は天|気|で|す|。');
    });

    test('no joiner between two Latin letters (no break there anyway)', () {
      expect(show(Kumihan.prepare('Flutterで')), 'Flutter|で');
    });

    test('spaces stay break opportunities, even inside a phrase', () {
      expect(Kumihan.phrases('Google の使命'), ['Google の', '使命']);
      expect(show(Kumihan.prepare('Google の使命')), 'Google の使|命');
    });

    test('hard line breaks are untouched', () {
      final s = Kumihan.prepare('今日は\n天気です');
      expect(s.split('\n').length, 2);
      expect(s.contains('${Kumihan.wordJoiner}\n'), isFalse);
      expect(s.contains('\n${Kumihan.wordJoiner}'), isFalse);
    });

    test('strip() gives the source back', () {
      for (final t in ['今日は天気です。', 'Flutterで日本語の改行をきれいにする方法', '「こんにちは」「世界」。', '']) {
        expect(Kumihan.strip(Kumihan.prepare(t)), t);
      }
    });

    test('never splits a grapheme cluster', () {
      // U+E0100 is an ideographic variation selector; 👋🏽 is a modified emoji.
      const t = '葛\u{E0100}城市の👋🏽です';
      final s = Kumihan.prepare(t);
      expect(s.contains('${Kumihan.wordJoiner}\u{E0100}'), isFalse);
      expect(s.contains('👋${Kumihan.wordJoiner}🏽'), isFalse);
      expect(Kumihan.strip(s), t);
    });
  });

  group('strict kinsoku', () {
    test('small kana and ー are glued to the previous character', () {
      expect(show(Kumihan.prepare('ちょっと待って', phrases: false)), 'ち|ょ|っと待|って');
      expect(show(Kumihan.prepare('コーヒー', phrases: false)), 'コ|ーヒ|ー');
    });

    test('closing punctuation and opening brackets', () {
      expect(show(Kumihan.prepare('はい。「えっ」', phrases: false)), 'はい|。「|え|っ|」');
    });

    test('off: nothing is inserted', () {
      expect(Kumihan.prepare('ちょっと待って', phrases: false, strictKinsoku: false), 'ちょっと待って');
    });

    test('character classes', () {
      for (final c in 'ぁっゃァッャヵヶー'.runes) {
        expect(isConditionalStarter(c), isTrue, reason: String.fromCharCode(c));
        expect(isLineStartProhibited(c), isTrue, reason: String.fromCharCode(c));
      }
      for (final c in 'あアかカ漢'.runes) {
        expect(isConditionalStarter(c), isFalse, reason: String.fromCharCode(c));
        expect(isLineStartProhibited(c), isFalse, reason: String.fromCharCode(c));
      }
      expect(isLineEndProhibited('「'.runes.first), isTrue);
      expect(isLineEndProhibited('」'.runes.first), isFalse);
    });
  });

  group('offset mapping', () {
    test('toSource / toDisplay round-trip', () {
      const t = '今日は天気です。';
      final layout = KumihanLayout(t);
      final p = layout.prepare();
      for (var s = 0; s <= t.length; s++) {
        expect(p.toSource(p.toDisplay(s)), s);
      }
      // Every display offset maps into the source.
      for (var d = 0; d <= p.text.length; d++) {
        final s = p.toSource(d);
        expect(s, inInclusiveRange(0, t.length));
      }
      expect(p.joinerCount, p.text.length - t.length);
      expect(layout.phraseBoundaries, [3]);
      expect(layout.phraseList, ['今日は', '天気です。']);
    });
  });

  group('yakumono', () {
    test('adjacent punctuation only', () {
      // 」 before 「 and 」 before 。 are set half-width; lone ones are not.
      expect(Kumihan.yakumonoHalts('「こんにちは」「世界」。'), [6, 10]);
      expect(Kumihan.yakumonoHalts('（注）「例」、…'), [2, 5]);
      expect(Kumihan.yakumonoHalts('（「'), [1]);
      expect(Kumihan.yakumonoHalts('今日は、晴れ。'), isEmpty);
    });

    test('span splits out the halt characters', () {
      final span = Kumihan.yakumono('「東京」「大阪」');
      final leaves = <String>[];
      final halted = <String>[];
      span.visitChildren((s) {
        if (s is TextSpan && s.text != null) {
          leaves.add(s.text!);
          if (s.style?.fontFeatures?.any((f) => f.feature == 'halt') ?? false) halted.add(s.text!);
        }
        return true;
      });
      expect(leaves.join(), '「東京」「大阪」');
      expect(halted, ['」']);
    });
  });
}
