import 'package:flutter/widgets.dart';

import 'budoux/parser.dart';
import 'layout.dart';

/// A drop-in replacement for [Text] that typesets Japanese properly:
///
/// * breaks lines between BudouX phrases (文節), never inside a word;
/// * strict kinsoku (禁則): no small kana, ー or closing punctuation at a
///   line start, no opening bracket at a line end;
/// * optional [balance] (like CSS `text-wrap: balance`) for headings;
/// * optional [yakumono] spacing: adjacent full-width punctuation such as
///   」「 or 。」 is set half-width with the font's `halt` feature.
///
/// It works by inserting U+2060 WORD JOINER (zero width) where a break must
/// not happen, then letting Flutter lay out the text as usual. The joiners
/// are width-aware: a phrase wider than the available width is left unglued,
/// so it wraps normally instead of being split at an arbitrary character.
///
/// Uses a [LayoutBuilder], so it cannot report intrinsic dimensions (e.g.
/// inside [IntrinsicWidth]). Copied text contains the word joiners: wrap
/// selectable content in `KumihanSelectionArea` to strip them on copy.
class KumihanText extends StatefulWidget {
  const KumihanText(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
    this.lang = KumihanLang.ja,
    this.phrases = true,
    this.strictKinsoku = true,
    this.balance = false,
    this.yakumono = false,
    this.balanceMaxLines = 6,
  });

  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;

  /// Defaults to the language of [lang] (`ja`), so CJK code points get their
  /// Japanese glyph forms.
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;

  /// Defaults to [data] (without word joiners).
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  /// The BudouX model used to find phrases.
  final KumihanLang lang;

  /// Break only between phrases.
  final bool phrases;

  /// Strict kinsoku (CSS `line-break: strict`).
  final bool strictKinsoku;

  /// Use the narrowest width that keeps the same number of lines
  /// (CSS `text-wrap: balance`), for 2…[balanceMaxLines] lines.
  final bool balance;

  /// Half-width adjacent punctuation (`halt`), JLREQ yakumono spacing.
  final bool yakumono;

  /// Balance only paragraphs of at most this many lines (Chrome uses 6).
  final int balanceMaxLines;

  @override
  State<KumihanText> createState() => _KumihanTextState();
}

class _KumihanTextState extends State<KumihanText> {
  KumihanLayout? _layout;
  _Key? _key;
  double? _lastWidth;
  _Result? _last;

  @override
  void dispose() {
    _layout?.dispose();
    super.dispose();
  }

  Locale get _locale =>
      widget.locale ??
      switch (widget.lang) {
        KumihanLang.ja => const Locale('ja'),
        KumihanLang.zhHans => const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        KumihanLang.zhHant => const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      };

  KumihanLayout _layoutFor(TextStyle style, TextScaler scaler, TextDirection dir) {
    final key = _Key(widget, style, scaler, dir, _locale);
    if (_layout == null || key != _key) {
      _layout?.dispose();
      _key = key;
      _lastWidth = null;
      _last = null;
      _layout = KumihanLayout(
        widget.data,
        style: style,
        lang: widget.lang,
        phrases: widget.phrases,
        strictKinsoku: widget.strictKinsoku,
        yakumono: widget.yakumono,
        textScaler: scaler,
        textDirection: dir,
        locale: _locale,
        strutStyle: widget.strutStyle,
      );
    }
    return _layout!;
  }

  _Result _resultFor(KumihanLayout layout, double maxWidth) {
    if (_last != null && _lastWidth == maxWidth) return _last!;
    final w = maxWidth.isFinite ? maxWidth : null;
    final prepared = layout.prepare(w);
    var width = maxWidth;
    if (widget.balance && w != null && (widget.softWrap ?? true)) {
      width = layout.balancedWidth(w, maxLines: widget.balanceMaxLines, prepared: prepared);
    }
    _lastWidth = maxWidth;
    return _last = _Result(prepared, width);
  }

  @override
  Widget build(BuildContext context) {
    // Resolve the style exactly like Text does, so measuring matches painting.
    final defaults = DefaultTextStyle.of(context);
    var style = widget.style;
    style = (style == null || style.inherit) ? defaults.style.merge(style) : style;
    if (MediaQuery.boldTextOf(context)) {
      style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final scaler = widget.textScaler ?? MediaQuery.textScalerOf(context);
    final dir = widget.textDirection ?? Directionality.of(context);
    final layout = _layoutFor(style, scaler, dir);

    return LayoutBuilder(
      builder: (context, constraints) {
        final r = _resultFor(layout, constraints.maxWidth);
        Widget text = Text.rich(
          r.prepared.span,
          style: widget.style,
          strutStyle: widget.strutStyle,
          textAlign: widget.textAlign,
          textDirection: widget.textDirection,
          locale: _locale,
          softWrap: widget.softWrap,
          overflow: widget.overflow,
          textScaler: widget.textScaler,
          maxLines: widget.maxLines,
          semanticsLabel: widget.semanticsLabel ?? widget.data,
          textWidthBasis: widget.textWidthBasis,
          textHeightBehavior: widget.textHeightBehavior,
          selectionColor: widget.selectionColor,
        );
        if (r.width < constraints.maxWidth) {
          // Balanced: a narrower box, placed where the lines would align.
          final align = widget.textAlign ?? defaults.textAlign ?? TextAlign.start;
          final x = switch (align) {
            TextAlign.left => -1.0,
            TextAlign.right => 1.0,
            TextAlign.center => 0.0,
            TextAlign.end => dir == TextDirection.ltr ? 1.0 : -1.0,
            TextAlign.start || TextAlign.justify => dir == TextDirection.ltr ? -1.0 : 1.0,
          };
          text = Align(
            alignment: Alignment(x, -1),
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: r.width),
              child: text,
            ),
          );
        }
        return text;
      },
    );
  }
}

class _Result {
  const _Result(this.prepared, this.width);

  final KumihanPrepared prepared;
  final double width;
}

class _Key {
  _Key(KumihanText w, this.style, this.scaler, this.dir, this.locale)
    : data = w.data,
      lang = w.lang,
      phrases = w.phrases,
      strict = w.strictKinsoku,
      yakumono = w.yakumono,
      balance = w.balance,
      balanceMaxLines = w.balanceMaxLines,
      softWrap = w.softWrap,
      strut = w.strutStyle;

  final String data;
  final TextStyle style;
  final TextScaler scaler;
  final TextDirection dir;
  final Locale locale;
  final KumihanLang lang;
  final bool phrases;
  final bool strict;
  final bool yakumono;
  final bool balance;
  final int balanceMaxLines;
  final bool? softWrap;
  final StrutStyle? strut;

  @override
  bool operator ==(Object other) =>
      other is _Key &&
      other.data == data &&
      other.style == style &&
      other.scaler == scaler &&
      other.dir == dir &&
      other.locale == locale &&
      other.lang == lang &&
      other.phrases == phrases &&
      other.strict == strict &&
      other.yakumono == yakumono &&
      other.balance == balance &&
      other.balanceMaxLines == balanceMaxLines &&
      other.softWrap == softWrap &&
      other.strut == strut;

  @override
  int get hashCode => Object.hash(
    data,
    style,
    scaler,
    dir,
    locale,
    lang,
    phrases,
    strict,
    yakumono,
    balance,
    balanceMaxLines,
    softWrap,
    strut,
  );
}
