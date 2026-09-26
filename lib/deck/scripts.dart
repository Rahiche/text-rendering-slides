import 'dart:ui';

import 'package:characters/characters.dart';

import 'theme.dart';

/// A simplified Unicode script classifier + itemizer, good enough to
/// visualise what ICU / SkParagraph do when they split text into runs.
enum Script {
  latin('latin', BP.line, false, 'Space Grotesk'),
  arabic('arabic', BP.amber, true, 'Noto Kufi Arabic'),
  hebrew('hebrew', BP.coral, true, 'fallback: Hebrew'),
  devanagari('devanagari', BP.violet, false, 'fallback: Devanagari'),
  thai('thai', BP.pink, false, 'fallback: Thai'),
  han('han', BP.green, false, 'fallback: CJK'),
  kana('kana', Color(0xFF9FF0D6), false, 'fallback: CJK'),
  hangul('hangul', Color(0xFF7FE0FF), false, 'fallback: Korean'),
  cyrillic('cyrillic', Color(0xFFA9C7FF), false, 'Space Grotesk*'),
  greek('greek', Color(0xFFB8D4FF), false, 'fallback: Greek'),
  emoji('emoji', Color(0xFFFFE36D), false, 'fallback: Emoji'),
  common('common', BP.inkDim, false, '—');

  const Script(this.label, this.color, this.rtl, this.font);

  final String label;
  final Color color;
  final bool rtl;
  final String font;
}

bool _in(int c, int a, int b) => c >= a && c <= b;

bool isEmojiCodePoint(int c) =>
    _in(c, 0x1F300, 0x1FAFF) ||
    _in(c, 0x1F1E6, 0x1F1FF) ||
    _in(c, 0x2600, 0x27BF) ||
    c == 0x200D ||
    c == 0xFE0F;

Script scriptOf(int c) {
  if (isEmojiCodePoint(c)) return Script.emoji;
  if (_in(c, 0x41, 0x5A) || _in(c, 0x61, 0x7A) || _in(c, 0xC0, 0x24F) || _in(c, 0x1E00, 0x1EFF)) {
    return Script.latin;
  }
  if (_in(c, 0x0600, 0x06FF) || _in(c, 0x0750, 0x077F) || _in(c, 0x08A0, 0x08FF) ||
      _in(c, 0xFB50, 0xFDFF) || _in(c, 0xFE70, 0xFEFF)) {
    return Script.arabic;
  }
  if (_in(c, 0x0590, 0x05FF) || _in(c, 0xFB1D, 0xFB4F)) return Script.hebrew;
  if (_in(c, 0x0900, 0x097F) || _in(c, 0xA8E0, 0xA8FF)) return Script.devanagari;
  if (_in(c, 0x0E00, 0x0E7F)) return Script.thai;
  if (_in(c, 0x4E00, 0x9FFF) || _in(c, 0x3400, 0x4DBF) || _in(c, 0x20000, 0x2A6DF) ||
      _in(c, 0x3000, 0x303F) || _in(c, 0xFF00, 0xFFEF)) {
    return Script.han;
  }
  if (_in(c, 0x3040, 0x30FF) || _in(c, 0x31F0, 0x31FF)) return Script.kana;
  if (_in(c, 0xAC00, 0xD7AF) || _in(c, 0x1100, 0x11FF) || _in(c, 0x3130, 0x318F)) {
    return Script.hangul;
  }
  if (_in(c, 0x0400, 0x04FF)) return Script.cyrillic;
  if (_in(c, 0x0370, 0x03FF)) return Script.greek;
  return Script.common;
}

Script scriptOfCluster(String g) {
  final runes = g.runes.toList();
  if (runes.any(isEmojiCodePoint) || runes.any((r) => _in(r, 0x1F3FB, 0x1F3FF))) {
    return Script.emoji;
  }
  for (final r in runes) {
    final s = scriptOf(r);
    if (s != Script.common) return s;
  }
  return Script.common;
}

/// A run of text sharing one script (and so one direction and one font).
class ScriptRun {
  const ScriptRun(this.start, this.end, this.script, this.text);

  /// UTF-16 offsets.
  final int start;
  final int end;
  final Script script;
  final String text;

  bool get rtl => script.rtl;

  @override
  String toString() => 'ScriptRun(${script.label} $start..$end "$text")';
}

/// Splits [text] into script runs. "Common" characters (spaces, digits,
/// punctuation) join the run before them, like ICU's script resolution.
List<ScriptRun> itemize(String text) {
  final clusters = <(int, int, Script)>[];
  var i = 0;
  for (final g in text.characters) {
    clusters.add((i, i + g.length, scriptOfCluster(g)));
    i += g.length;
  }
  // Resolve commons: take the previous real script, or the next one at start.
  final resolved = <Script>[];
  Script? last;
  for (final c in clusters) {
    if (c.$3 != Script.common) last = c.$3;
    resolved.add(c.$3 == Script.common ? (last ?? Script.common) : c.$3);
  }
  Script? next;
  for (var k = resolved.length - 1; k >= 0; k--) {
    if (clusters[k].$3 != Script.common) next = clusters[k].$3;
    if (resolved[k] == Script.common && next != null) resolved[k] = next;
  }
  final runs = <ScriptRun>[];
  for (var k = 0; k < clusters.length; k++) {
    final (s, e, _) = clusters[k];
    final sc = resolved[k];
    if (runs.isNotEmpty && runs.last.script == sc) {
      final r = runs.removeLast();
      runs.add(ScriptRun(r.start, e, sc, text.substring(r.start, e)));
    } else {
      runs.add(ScriptRun(s, e, sc, text.substring(s, e)));
    }
  }
  return runs;
}
