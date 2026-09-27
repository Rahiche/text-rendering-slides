/// kumihan (組版): Japanese typesetting for Flutter Text.
///
/// * [KumihanText]: a drop-in [Text] that breaks lines between BudouX
///   phrases, applies strict kinsoku, can balance headings and tighten
///   adjacent punctuation (yakumono).
/// * [Kumihan]: the same as plain functions on strings.
/// * [KumihanLayout]: the reusable analysis behind both.
/// * [KumihanSelectionArea]: a [SelectionArea] that strips the word joiners
///   on copy.
library;

import 'package:flutter/painting.dart';

import 'src/budoux/parser.dart';
import 'src/chars.dart' as chars;
import 'src/layout.dart';

export 'src/budoux/parser.dart' show BudouxParser, KumihanLang;
export 'src/chars.dart'
    show
        isConditionalStarter,
        isLineEndProhibited,
        isLineStartProhibited,
        isYakumonoClosing,
        isYakumonoOpening,
        lineEndProhibited,
        lineStartProhibited,
        stripWordJoiners,
        wordJoiner;
export 'src/kumihan_text.dart' show KumihanText;
export 'src/layout.dart' show KumihanLayout, KumihanPrepared;
export 'src/selection.dart' show KumihanSelectionArea;

/// String-level entry points.
abstract final class Kumihan {
  /// U+2060 WORD JOINER.
  static const String wordJoiner = chars.wordJoiner;

  /// Splits [text] into BudouX phrases (文節). `phrases(t).join() == t`.
  static List<String> phrases(String text, {KumihanLang lang = KumihanLang.ja}) =>
      BudouxParser.forLang(lang).parse(text);

  /// Returns [text] with U+2060 WORD JOINERs inserted so Flutter breaks lines
  /// only between phrases ([phrases]) and never against strict kinsoku
  /// ([strictKinsoku]).
  ///
  /// When both [maxWidth] and [style] are given, a phrase wider than
  /// [maxWidth] is not glued (it would otherwise be split at an arbitrary
  /// character, ignoring kinsoku). Pass the fully resolved style the text
  /// will be painted with. For repeated layouts, keep a [KumihanLayout].
  static String prepare(
    String text, {
    double? maxWidth,
    TextStyle? style,
    bool strictKinsoku = true,
    bool phrases = true,
    KumihanLang lang = KumihanLang.ja,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final layout = KumihanLayout(
      text,
      style: maxWidth == null ? null : style,
      lang: lang,
      phrases: phrases,
      strictKinsoku: strictKinsoku,
      textScaler: textScaler,
      locale: style?.locale,
    );
    try {
      return layout.prepare(maxWidth).text;
    } finally {
      layout.dispose();
    }
  }

  /// Removes the word joiners inserted by [prepare].
  static String strip(String text) => chars.stripWordJoiners(text);

  /// UTF-16 offsets of the punctuation that yakumono spacing sets half-width:
  /// a closing bracket, comma or full stop followed by another one or by an
  /// opening bracket (」「 。」 、「), and an opening bracket preceded by
  /// another opening bracket (（「).
  static List<int> yakumonoHalts(String text) => KumihanLayout(text, phrases: false, strictKinsoku: false).haltOffsets;

  /// [text] as spans, with `halt` on the punctuation from [yakumonoHalts].
  static TextSpan yakumono(String text, {TextStyle? style}) {
    final layout = KumihanLayout(text, style: style, phrases: false, strictKinsoku: false, yakumono: true);
    return TextSpan(style: style, children: [layout.prepare().span]);
  }
}
