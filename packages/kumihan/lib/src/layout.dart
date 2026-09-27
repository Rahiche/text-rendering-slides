import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:characters/characters.dart';
import 'package:flutter/painting.dart';

import 'budoux/parser.dart';
import 'chars.dart';

// Why the gap before grapheme k must not break (bit flags).
const int _kPhrase = 1; // inside a BudouX phrase
const int _kKinsoku = 2; // strict kinsoku (禁則)
const int _kWord = 4; // two letters/digits: the line breaker never breaks here
const int _kNatural = 8; // kinsoku the line breaker already enforces by itself

/// SkParagraph moves a word to the next line when it fits (`width <=
/// maxWidth`) and splits it at any grapheme when it does not. A glued run may
/// exceed the line by this much (float rounding) and still be kept glued.
const double _epsilon = 0.001;

/// Japanese line-breaking analysis of one text, reusable across widths.
///
/// Width-independent work (graphemes, BudouX phrases, kinsoku pairs, yakumono)
/// is done once in the constructor; glyph advances are measured once, lazily,
/// the first time a width-aware [prepare] needs them. [prepare] itself is then
/// cheap, so it can run on every layout (e.g. while a window is resized).
///
/// Call [dispose] when done (nothing native is retained today, but the API
/// leaves room for caching a painter).
class KumihanLayout {
  KumihanLayout(
    this.text, {
    this.style,
    this.lang = KumihanLang.ja,
    this.phrases = true,
    this.strictKinsoku = true,
    this.yakumono = false,
    this.textScaler = TextScaler.noScaling,
    this.textDirection = TextDirection.ltr,
    this.locale,
    this.strutStyle,
  }) {
    _analyze();
  }

  /// The source text (never modified).
  final String text;

  /// The fully resolved style the text will be painted with. Needed for
  /// width-aware gluing and [balancedWidth]; without it, every phrase is glued.
  final TextStyle? style;

  /// Which BudouX model splits the text into phrases.
  final KumihanLang lang;

  /// Keep BudouX phrases (文節) together: break only between them.
  final bool phrases;

  /// Strict kinsoku: no small kana, ー, closing punctuation… at a line start,
  /// no opening bracket at a line end (CSS `line-break: strict`).
  final bool strictKinsoku;

  /// Collapse the blank halves of adjacent full-width punctuation with the
  /// OpenType `halt` feature (JLREQ "yakumono" spacing).
  final bool yakumono;

  final TextScaler textScaler;
  final TextDirection textDirection;
  final Locale? locale;
  final StrutStyle? strutStyle;

  late final List<int> _starts; // grapheme start offsets, plus text.length
  late final List<int> _first; // first code point of each grapheme
  late final Uint8List _gap; // flags for the gap before grapheme k
  late final List<int> _phraseStarts; // grapheme indices starting a phrase
  late final Uint8List _halt; // 1 = this grapheme gets `halt`
  List<double>? _advances;

  /// Number of grapheme clusters in [text].
  int get graphemeCount => _first.length;

  /// UTF-16 offset where grapheme [k] starts (`k == graphemeCount` → end).
  int graphemeStart(int k) => _starts[k];

  /// BudouX phrase boundaries as UTF-16 offsets into [text] (never 0 or
  /// `text.length`; hard line breaks are not listed).
  late final List<int> phraseBoundaries = [for (final k in _phraseStarts) _starts[k]];

  /// The phrases themselves.
  List<String> get phraseList {
    final out = <String>[];
    var s = 0;
    for (final b in phraseBoundaries) {
      out.add(text.substring(s, b));
      s = b;
    }
    if (s < text.length) out.add(text.substring(s));
    return out;
  }

  /// UTF-16 offsets of the characters set half-width by [yakumono] spacing
  /// (computed even when [yakumono] is false).
  late final List<int> haltOffsets = [
    for (var k = 0; k < graphemeCount; k++)
      if (_halt[k] == 1) _starts[k],
  ];

  void _analyze() {
    final starts = <int>[];
    final first = <int>[];
    var o = 0;
    for (final g in text.characters) {
      starts.add(o);
      first.add(g.runes.first);
      o += g.length;
    }
    starts.add(o);
    _starts = starts;
    _first = first;
    final n = first.length;

    // Phrases, paragraph by paragraph (hard breaks are never glued anyway).
    final boundaries = <int>{};
    if (n > 1) {
      final parser = BudouxParser.forLang(lang);
      var ps = 0;
      for (var i = 0; i <= text.length; i++) {
        final end = i == text.length;
        final c = end ? 0 : text.codeUnitAt(i);
        if (end || c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029) {
          if (i > ps) {
            for (final b in parser.parseBoundaries(text.substring(ps, i))) {
              boundaries.add(ps + b);
            }
          }
          ps = i + 1;
        }
      }
    }

    final gap = Uint8List(n);
    final phraseStarts = <int>[];
    for (var k = 1; k < n; k++) {
      final a = first[k - 1];
      final b = first[k];
      final phraseStart = boundaries.contains(starts[k]);
      if (phraseStart) phraseStarts.add(k);
      if (_noGlue(a) || _noGlue(b)) continue;
      var f = 0;
      final word = isWordChar(a) && isWordChar(b);
      if (word) f |= _kWord;
      if (!phraseStart && !word) f |= _kPhrase;
      if (_kinsoku(a, b)) {
        f |= _kKinsoku;
        if (!isConditionalStarter(b)) f |= _kNatural;
      }
      gap[k] = f;
    }
    _gap = gap;
    _phraseStarts = phraseStarts;

    final halt = Uint8List(n);
    bool single(int k) => _starts[k + 1] - _starts[k] == 1;
    for (var k = 0; k < n; k++) {
      if (!single(k)) continue;
      final c = first[k];
      final next = k + 1 < n && single(k + 1) ? first[k + 1] : -1;
      final prev = k > 0 && single(k - 1) ? first[k - 1] : -1;
      // 」「 」。 。」 、「 ）」 … → the first one loses its blank half.
      // 「『 （「 … → the second one loses its blank half.
      if ((isYakumonoClosing(c) && (isYakumonoClosing(next) || isYakumonoOpening(next))) ||
          (isYakumonoOpening(c) && isYakumonoOpening(prev))) {
        halt[k] = 1;
      }
    }
    _halt = halt;
  }

  static bool _noGlue(int cp) => isSpace(cp) || cp == 0x00AD || isWordJoiner(cp);

  static bool _kinsoku(int a, int b) {
    if (a == b && isInseparable(a)) return true;
    final cjk = isCjk(a) || isCjk(b);
    return cjk && (isLineStartProhibited(b) || isLineEndProhibited(a));
  }

  /// Advance of every grapheme, measured once with [style] on a single line
  /// (with `halt` applied when [yakumono] is on). Requires [style].
  List<double> get graphemeAdvances => _advances ??= _measure();

  List<double> _measure() {
    final tp = _painter(_buildSpan(null, withJoiners: false).span);
    try {
      tp.layout();
      return [
        for (var k = 0; k < graphemeCount; k++)
          _starts[k + 1] == _starts[k]
              ? 0.0
              : tp
                    .getBoxesForSelection(TextSelection(baseOffset: _starts[k], extentOffset: _starts[k + 1]))
                    .fold<double>(0, (a, b) => a + (b.right - b.left)),
      ];
    } finally {
      tp.dispose();
    }
  }

  TextPainter _painter(InlineSpan span) => TextPainter(
    text: TextSpan(style: style, children: [span]),
    textDirection: textDirection,
    textScaler: textScaler,
    locale: locale,
    strutStyle: strutStyle,
  );

  /// The display text for a paragraph [maxWidth] wide (null: glue every
  /// phrase). Word joiners go inside phrases and around kinsoku pairs; a
  /// phrase wider than [maxWidth] is left unglued (only its kinsoku pairs are
  /// kept), because the line breaker would otherwise split it anywhere,
  /// ignoring kinsoku.
  KumihanPrepared prepare([double? maxWidth]) {
    final n = graphemeCount;
    final glue = Uint8List(n);
    for (var k = 1; k < n; k++) {
      final f = _gap[k];
      if ((phrases && f & _kPhrase != 0) || (strictKinsoku && f & _kKinsoku != 0)) glue[k] = 1;
    }
    var maxRun = 0.0;
    if (maxWidth != null && maxWidth.isFinite && style != null && n > 1) {
      maxRun = _fit(glue, maxWidth + _epsilon);
    }
    return _buildSpan(glue, withJoiners: true, maxRun: maxRun);
  }

  /// Unglues runs wider than [limit]; returns the widest remaining run.
  double _fit(Uint8List glue, double limit) {
    final adv = graphemeAdvances;
    final n = graphemeCount;
    bool held(int k) => glue[k] == 1 || _gap[k] & (_kWord | _kNatural) != 0;
    bool keepKinsoku(int k) => strictKinsoku && _gap[k] & _kKinsoku != 0;
    var widest = 0.0;
    for (var pass = 0; pass < 3; pass++) {
      var changed = false;
      widest = 0;
      var a = 0;
      while (a < n) {
        var b = a;
        var w = adv[a];
        while (b + 1 < n && held(b + 1)) {
          b++;
          w += adv[b];
        }
        if (w > limit) {
          var dropped = false;
          for (var k = a + 1; k <= b; k++) {
            if (glue[k] == 1 && !keepKinsoku(k)) {
              glue[k] = 0;
              dropped = true;
            }
          }
          if (!dropped) {
            // Only kinsoku pairs left and still too wide: allow breaks before
            // small kana and ー again. (Pairs the line breaker enforces by
            // itself stay; our joiner changes nothing there.)
            for (var k = a + 1; k <= b; k++) {
              if (glue[k] == 1 && _gap[k] & _kNatural == 0) {
                glue[k] = 0;
                dropped = true;
              }
            }
          }
          changed |= dropped;
        } else {
          widest = math.max(widest, w);
        }
        a = b + 1;
      }
      if (!changed) break;
    }
    return widest;
  }

  KumihanPrepared _buildSpan(Uint8List? glue, {required bool withJoiners, double maxRun = 0}) {
    final n = graphemeCount;
    final useHalt = yakumono && haltOffsets.isNotEmpty;
    final sb = StringBuffer();
    final all = StringBuffer();
    final children = <InlineSpan>[];
    final joined = <int>[];
    final haltStyle = useHalt
        ? TextStyle(fontFeatures: [...?style?.fontFeatures, const ui.FontFeature.enable('halt')])
        : null;
    for (var k = 0; k < n; k++) {
      if (withJoiners && k > 0 && glue != null && glue[k] == 1) {
        sb.write(wordJoiner);
        all.write(wordJoiner);
        joined.add(_starts[k]);
      }
      final g = text.substring(_starts[k], _starts[k + 1]);
      all.write(g);
      if (useHalt && _halt[k] == 1) {
        if (sb.isNotEmpty) {
          children.add(TextSpan(text: sb.toString()));
          sb.clear();
        }
        children.add(TextSpan(text: g, style: haltStyle));
      } else {
        sb.write(g);
      }
    }
    final InlineSpan span;
    if (!useHalt) {
      span = TextSpan(text: sb.toString());
    } else {
      if (sb.isNotEmpty) children.add(TextSpan(text: sb.toString()));
      span = TextSpan(children: children);
    }
    return KumihanPrepared._(all.toString(), span, joined, maxRun);
  }

  /// The narrowest width, at most [maxWidth], that still lays the text out in
  /// the same number of lines, like CSS `text-wrap: balance` (applied only to
  /// 2…[maxLines] lines, as in Chrome). Returns [maxWidth] when balancing does
  /// not apply or [style] is null.
  double balancedWidth(double maxWidth, {int maxLines = 6, KumihanPrepared? prepared}) {
    if (!maxWidth.isFinite || style == null || graphemeCount < 2) return maxWidth;
    final p = prepared ?? prepare(maxWidth);
    final tp = _painter(p.span);
    try {
      tp.layout(maxWidth: maxWidth);
      final lines = tp.computeLineMetrics().length;
      if (lines < 2 || lines > maxLines) return maxWidth;
      // Never narrower than the widest glued run: that would force an
      // emergency break inside it.
      var lo = p.maxRunWidth;
      var hi = maxWidth;
      if (lo >= hi) return maxWidth;
      for (var i = 0; i < 20 && hi - lo > 0.5; i++) {
        final mid = (lo + hi) / 2;
        tp.layout(maxWidth: mid);
        if (tp.computeLineMetrics().length <= lines) {
          hi = mid;
        } else {
          lo = mid;
        }
      }
      return hi;
    } finally {
      tp.dispose();
    }
  }

  void dispose() {}
}

/// The result of [KumihanLayout.prepare]: the text to display.
class KumihanPrepared {
  KumihanPrepared._(this.text, this.span, this.joinedAt, this.maxRunWidth);

  /// The display text: the source with U+2060 WORD JOINERs inserted.
  final String text;

  /// [text] as a span tree (split into `halt` runs when yakumono is on). It
  /// carries no style of its own: wrap it in a styled parent span.
  final InlineSpan span;

  /// Source UTF-16 offsets before which a word joiner was inserted.
  final List<int> joinedAt;

  /// Width of the widest glued run (0 when no width was given).
  final double maxRunWidth;

  /// Number of word joiners inserted.
  int get joinerCount => joinedAt.length;

  /// Maps an offset in [text] back to the source text.
  int toSource(int displayOffset) {
    // The i-th joiner sits at display index joinedAt[i] + i.
    var lo = 0, hi = joinedAt.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (joinedAt[mid] + mid < displayOffset) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return displayOffset - lo;
  }

  /// Maps a source offset to [text] (after any joiner inserted there).
  int toDisplay(int sourceOffset) {
    var lo = 0, hi = joinedAt.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (joinedAt[mid] <= sourceOffset) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return sourceOffset + lo;
  }
}
