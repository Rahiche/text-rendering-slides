import 'package:characters/characters.dart';

/// What the factory builds while nobody is waiting: words from the talk
/// (text, Flutter, Japan), alternating Japanese and English, short to long.
const sampleNames = [
  'Flutter',
  'ようこそ',
  'Glyph',
  '文字',
  'Hello',
  'テキスト',
  'Dart',
  '東京',
  'Impeller',
  'ひらがな',
  'Widget',
  '日本語',
  'Pixels',
  'カタカナ',
  'Unicode',
  '漢字',
  'Kerning',
  'ありがとう',
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
  const NameRejected(this.en);
  final String en;
}

/// Tidies a typed name: full-width ASCII (a Japanese keyboard in full-width
/// mode types "Ａｎａ") becomes plain ASCII, and runs of spaces (including the
/// ideographic space "　") become one space.
String cleanName(String raw) {
  final b = StringBuffer();
  for (final r in raw.runes) {
    if (r >= 0xFF01 && r <= 0xFF5E) {
      b.writeCharCode(r - 0xFEE0);
    } else if (r == 0xFF65) {
      b.write('・'); // half-width katakana middle dot
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

// Letters (any script), combining marks, digits, spaces and a few name
// punctuation marks. No emoji or symbols.
final _allowed = RegExp(r"^[\p{L}\p{M}\p{N} .'’\-・ー々〆]+$", unicode: true);
final _letter = RegExp(r'\p{L}', unicode: true);

/// Cleans up and checks a name typed at the booth.
NameCheck checkName(String raw) {
  final name = cleanName(raw);
  if (name.isEmpty) return const NameRejected('Type your name first');
  if (name.characters.length > maxNameLength) {
    return const NameRejected('A little shorter, please: $maxNameLength letters max');
  }
  if (!_allowed.hasMatch(name) || !_letter.hasMatch(name)) {
    return const NameRejected('Letters only, please: no emoji or symbols');
  }
  if (isBlocked(name)) return const NameRejected("Let's build a different name");
  return NameOk(name);
}

// ── Blocklist ───────────────────────────────────────────────────────────────
// Deliberately short and conservative: the operator can always skip a name
// (Ctrl+Shift+S). False positives matter more here than misses: a visitor
// called Yamashita, Hancock or ジャクソン must never be turned away.
//
// Matching is on a folded form: lower case, katakana → hiragana, a few digit
// look-alikes (sh1t) → letters.

/// Blocked only as a whole word (a name part between spaces, dots, hyphens):
/// these also hide inside real names (Yamashita, Matsushita, Hancock, Essex,
/// Sexton, Draper, Nazir, Analia, Pornthip (Thai), Dickson, Kasumi かすみ,
/// Jackson ジャクソン, Nixon ニクソン, Errol エロール, Bakar バカル…).
const _blockedWords = {
  // en
  'shit', 'shits', 'shitty', 'cock', 'cocks', 'dick', 'dicks', 'anal', 'anus',
  'sex', 'sexy', 'rape', 'rapist', 'nazi', 'nazis', 'fag', 'fags', 'slut',
  'sluts', 'porno', 'cunt', 'cunts', 'penis', 'tits', 'boobs', 'piss', 'ass',
  'arse', 'twat', 'wank', 'jap', 'japs', 'chink', 'chinks', 'gook', 'kike',
  'spic',
  // ja (hiragana; katakana is folded to it)
  'ばか', 'あほ', 'くそ', 'えろ', 'えろい', 'しね', 'ぶす', 'でぶ', 'はげ', 'かす',
  'ごみ', 'きもい', 'うざい',
};

/// Blocked anywhere in a word: these don't occur inside real names.
const _blockedParts = [
  // en
  'fuck', 'nigger', 'nigga', 'faggot', 'bitch', 'pussy', 'whore', 'hitler',
  'vagina', 'retard', 'asshole', 'bullshit', 'shithead', 'motherf', 'cocksuck',
  'dickhead', 'blowjob', 'dildo', 'cumshot', 'jizz', 'wanker',
  // ja
  'ちんこ', 'ちんぽ', 'ちんちん', 'まんこ', 'うんこ', 'うんち', 'せっくす', 'おっぱい',
  'れいぷ', 'ころす', 'ひとらー', 'なちす', 'きちがい', 'くそやろう', 'ばかやろう',
  '死ね', '殺す', '殺し', '馬鹿', '阿呆', '糞', '変態', '痴漢', '強姦', '売春', '淫',
];

const _leet = {'0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '8': 'b'};

String _fold(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    if (r >= 0x30A1 && r <= 0x30F6) {
      b.writeCharCode(r - 0x60); // katakana → hiragana
    } else {
      final c = String.fromCharCode(r);
      b.write(_leet[c] ?? c);
    }
  }
  return b.toString();
}

/// Whether [name] (already cleaned) is on the blocklist.
bool isBlocked(String name) {
  final words = _fold(name).split(RegExp(r"[\s.\-_'’・]+")).where((w) => w.isNotEmpty).toList();
  // "f u c k" / "f.u.c.k": runs of one-letter words are joined back up.
  final checks = <String>[];
  var run = '';
  for (final w in words) {
    if (w.characters.length == 1) {
      run += w;
      continue;
    }
    if (run.isNotEmpty) checks.add(run);
    run = '';
    checks.add(w);
  }
  if (run.isNotEmpty) checks.add(run);
  for (final w in checks) {
    if (_blockedWords.contains(w)) return true;
    for (final p in _blockedParts) {
      if (w.contains(p)) return true;
    }
  }
  return false;
}
