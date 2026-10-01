import 'package:flutter_test/flutter_test.dart';
import 'package:text_slides/booth/names.dart';

String? ok(String raw) => switch (checkName(raw)) {
  NameOk(:final name) => name,
  NameRejected() => null,
};

void main() {
  test('accepts names in any script', () {
    for (final n in ['Ana', '田中太郎', 'さくら', 'Chen', "O'Brien", 'Jean-Pierre', 'José', 'Đặng', 'Ольга', 'محمد', 'ゆうき・タナカ', 'R2D2']) {
      expect(ok(n), n, reason: n);
    }
  });

  test('tidies spaces and full-width letters', () {
    expect(ok('  Ana   Lee '), 'Ana Lee');
    expect(ok('田中　太郎'), '田中 太郎'); // ideographic space
    expect(ok('Ａｎａ'), 'Ana'); // full-width keyboard mode
  });

  test('rejects empty, too long, emoji and symbols', () {
    expect(checkName('   '), isA<NameRejected>());
    expect(checkName('a' * (maxNameLength + 1)), isA<NameRejected>());
    expect(ok('a' * maxNameLength), isNotNull);
    expect(ok('あ' * maxNameLength), isNotNull);
    for (final n in ['😀 Bob', 'Ana!', '<b>', '123', '@@']) {
      expect(checkName(n), isA<NameRejected>(), reason: n);
    }
  });

  test('never blocks real names that contain a blocked word', () {
    for (final n in [
      'Yamashita', 'Matsushita', 'Kinoshita', 'Morishita', 'Takeshita', 'Shitara',
      'Hancock', 'Peacock', 'Dickson', 'Dickens', 'Essex', 'Sexton', 'Draper',
      'Nazir', 'Nazia', 'Analia', 'Pornthip', 'Fukuda', 'Scunthorpe', 'Cassandra',
      'Hassan', 'Assaf', 'Penistone', 'Shitake',
      'ジャクソン', 'ニクソン', 'エリクソン', 'エロール', 'バカル', 'かすみ', 'ごみやま',
      'しねん', '山下', '木下', '松下',
    ]) {
      expect(ok(n), n, reason: n);
    }
  });

  test('blocks a conservative list, however it is typed', () {
    for (final n in [
      'fuck', 'FUCK', 'ｆｕｃｋ', 'f u c k', 'f.u.c.k', 'motherfucker', 'shit', 'Bull Shit',
      'sh1t', 'Hitler', 'ass', 'nazi', 'ばか', 'バカ', '馬鹿', 'アホ', 'クソ', 'くそ',
      'うんこ', 'ウンコ', 'ちんこ', '死ね', 'しね', 'シネ', 'エロ', 'キモい',
    ]) {
      expect(checkName(n), isA<NameRejected>(), reason: n);
    }
  });

  test('samples are valid, varied names', () {
    expect(sampleNames.toSet().length, sampleNames.length);
    for (final n in sampleNames) {
      expect(ok(n), n, reason: n);
    }
  });
}
