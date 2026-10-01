import 'package:characters/characters.dart';

/// What the factory builds while nobody is waiting.
const sampleNames = [
  'Flutter',
  'こんにちは',
  'Hello',
  '文字',
  'テキスト',
  'Dart',
  '東京',
  'Text',
  '日本語',
  'Pixels',
  'ようこそ',
  'Glyph',
];

const maxNameLength = 16; // graphemes

/// Outcome of checking a submitted name.
sealed class NameCheck {
  const NameCheck();
}

class NameOk extends NameCheck {
  const NameOk(this.name);
  final String name;
}

class NameRejected extends NameCheck {
  const NameRejected(this.en, this.ja);
  final String en;
  final String ja;
}

/// Cleans up and checks a name typed at the booth.
NameCheck checkName(String raw) {
  final name = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (name.isEmpty) return const NameRejected('Type a name first', '名前を入力してください');
  if (name.characters.length > maxNameLength) {
    return const NameRejected('A little shorter, please', 'もう少し短くお願いします');
  }
  // Letters (any script), combining marks, digits, spaces and a few name
  // punctuation marks. No emoji or symbols.
  final ok = RegExp(r"^[\p{L}\p{M}\p{N} .'\-・ー々〆]+$", unicode: true);
  if (!ok.hasMatch(name) || !RegExp(r'\p{L}', unicode: true).hasMatch(name)) {
    return const NameRejected('Letters only, please', '文字だけでお願いします');
  }
  if (_blocked(name)) return const NameRejected("Let's build a different name", '別の名前にしましょう');
  return NameOk(name);
}

// A short, deliberately conservative list; the operator can always skip.
const _blocklist = [
  'fuck',
  'shit',
  'bitch',
  'cunt',
  'dick',
  'cock',
  'pussy',
  'nigg',
  'fag',
  'rape',
  'nazi',
  'hitler',
  'porn',
  'sex',
  'anal',
  'penis',
  'vagina',
  'whore',
  'slut',
  'retard',
  'ちんこ',
  'ちんぽ',
  'まんこ',
  'うんこ',
  'セックス',
  'エロ',
  '死ね',
  'しね',
  'ころす',
  '殺す',
  'ばか',
  'バカ',
  '馬鹿',
  'あほ',
  'アホ',
  'クソ',
  'くそ',
  'きもい',
  'キモい',
];

bool _blocked(String name) {
  final n = name.toLowerCase().replaceAll(RegExp(r'[\s.\-_]'), '');
  return _blocklist.any(n.contains);
}
