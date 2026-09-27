// A Dart port of the BudouX parser (google/budoux v0.9.2).
//
// Copyright 2021 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// Modifications: ported to Dart; the score is kept as an integer
// (2 × sum − total, as in the upstream Java parser) instead of the
// floating-point `baseScore = −0.5 × total`; the sign test is identical.

import 'model_ja.dart';
import 'model_zh_hans.dart';
import 'model_zh_hant.dart';

/// Languages with a bundled BudouX model.
enum KumihanLang {
  /// Japanese (`budoux/models/ja.json`).
  ja,

  /// Simplified Chinese (`budoux/models/zh-hans.json`).
  zhHans,

  /// Traditional Chinese (`budoux/models/zh-hant.json`).
  zhHant,
}

/// BudouX: splits a sentence into phrases with a tiny AdaBoost model.
///
/// For every boundary `i` (between code points `i - 1` and `i`) the score is
/// the model's base score plus the weights of the unigram (UW1–UW6), bigram
/// (BW1–BW3) and trigram (TW1–TW4) features around `i`; a positive score
/// means "break here". This is the exact algorithm of the upstream Python,
/// JavaScript and Java parsers.
///
/// Like the reference Python parser, it works on Unicode code points, so a
/// surrogate pair is never split.
class BudouxParser {
  BudouxParser(Map<String, Map<String, int>> model)
    : _uw1 = model['UW1'] ?? const {},
      _uw2 = model['UW2'] ?? const {},
      _uw3 = model['UW3'] ?? const {},
      _uw4 = model['UW4'] ?? const {},
      _uw5 = model['UW5'] ?? const {},
      _uw6 = model['UW6'] ?? const {},
      _bw1 = model['BW1'] ?? const {},
      _bw2 = model['BW2'] ?? const {},
      _bw3 = model['BW3'] ?? const {},
      _tw1 = model['TW1'] ?? const {},
      _tw2 = model['TW2'] ?? const {},
      _tw3 = model['TW3'] ?? const {},
      _tw4 = model['TW4'] ?? const {},
      _total = model.values.fold<int>(0, (a, g) => g.values.fold<int>(a, (b, v) => b + v));

  /// The bundled model for [lang] (created once, then cached).
  factory BudouxParser.forLang(KumihanLang lang) => switch (lang) {
    KumihanLang.ja => ja,
    KumihanLang.zhHans => zhHans,
    KumihanLang.zhHant => zhHant,
  };

  /// Parser with the default Japanese model.
  static final BudouxParser ja = BudouxParser(budouxJa);

  /// Parser with the default Simplified Chinese model.
  static final BudouxParser zhHans = BudouxParser(budouxZhHans);

  /// Parser with the default Traditional Chinese model.
  static final BudouxParser zhHant = BudouxParser(budouxZhHant);

  final Map<String, int> _uw1, _uw2, _uw3, _uw4, _uw5, _uw6;
  final Map<String, int> _bw1, _bw2, _bw3;
  final Map<String, int> _tw1, _tw2, _tw3, _tw4;

  /// Sum of every weight in the model. The base score is `-total / 2`.
  final int _total;

  /// The model's base score (`-0.5 × sum of all weights`).
  double get baseScore => -0.5 * _total;

  /// Splits [sentence] into phrases. Joining them gives back [sentence].
  List<String> parse(String sentence) {
    if (sentence.isEmpty) return const [];
    final out = <String>[];
    var start = 0;
    for (final b in parseBoundaries(sentence)) {
      out.add(sentence.substring(start, b));
      start = b;
    }
    out.add(sentence.substring(start));
    return out;
  }

  /// Phrase boundaries as UTF-16 offsets into [sentence] (never 0 or
  /// `sentence.length`), in increasing order.
  List<int> parseBoundaries(String sentence) {
    if (sentence.isEmpty) return const [];
    final chars = <String>[];
    final offsets = <int>[];
    var o = 0;
    for (final r in sentence.runes) {
      final c = String.fromCharCode(r);
      chars.add(c);
      offsets.add(o);
      o += c.length;
    }
    final n = chars.length;
    final out = <int>[];
    for (var i = 1; i < n; i++) {
      // 2 × (baseScore + Σ weights) = 2 × Σ weights − total.
      var s = 0;
      if (i > 2) s += _uw1[chars[i - 3]] ?? 0;
      if (i > 1) s += _uw2[chars[i - 2]] ?? 0;
      s += _uw3[chars[i - 1]] ?? 0;
      s += _uw4[chars[i]] ?? 0;
      if (i + 1 < n) s += _uw5[chars[i + 1]] ?? 0;
      if (i + 2 < n) s += _uw6[chars[i + 2]] ?? 0;
      if (i > 1) s += _bw1[chars[i - 2] + chars[i - 1]] ?? 0;
      s += _bw2[chars[i - 1] + chars[i]] ?? 0;
      if (i + 1 < n) s += _bw3[chars[i] + chars[i + 1]] ?? 0;
      if (i > 2) s += _tw1[chars[i - 3] + chars[i - 2] + chars[i - 1]] ?? 0;
      if (i > 1) s += _tw2[chars[i - 2] + chars[i - 1] + chars[i]] ?? 0;
      if (i + 1 < n) s += _tw3[chars[i - 1] + chars[i] + chars[i + 1]] ?? 0;
      if (i + 2 < n) s += _tw4[chars[i] + chars[i + 1] + chars[i + 2]] ?? 0;
      if (2 * s - _total > 0) out.add(offsets[i]);
    }
    return out;
  }
}
