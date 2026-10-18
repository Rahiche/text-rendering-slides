import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'figure.dart';
import 'kit.dart';
import 'motion.dart';
import 'shot.dart';
import 'devices.dart';
import 'vignette.dart';

/// デモ · The Demos store: a glass pavilion on the west side street, as a
/// phone maker's flagship store is, where the talk's demos wait on long
/// oak tables, each on a device about its real size, its screen laid out
/// by the real text stack. Only a talk plays them. A table a turn:
///
/// * line breaking (0–8 s, front left): a phone, a paragraph filled up to
///   its maxWidth (an amber line at the right margin); turned on its side,
///   the width more than doubles and the same words break into fewer,
///   longer lines;
/// * the same everywhere (20–32 s, front right): an iPhone in SF Pro and an
///   Android phone in Roboto, each laying the paragraph out its own way
///   (the lines break in different places); both turn round once on their
///   turntables and come back as Flutter draws them, in the app's own font
///   with its own line breaker: line for line the same;
/// * phrase breaking (40–47.5 s, back left): a Japanese sentence as Text()
///   breaks it, anywhere (the words it splits in red), and as
///   KumihanText() does, a word joiner (U+2060) inside each phrase so the
///   line breaker can only break between them (whole, in green);
/// * punctuation (48–56 s): the first of those phones turned on its side
///   for 「こんにちは」「世界」。 twice, as Text() spaces it and with the
///   font's 'halt' where 」 meets 「: the gap between the marks, 1 em, then ½;
/// * the web (60–68 s, back right): two laptops, an HTML page and a
///   Flutter web page (its text pixels on a canvas). The Flutter page's
///   Japanese is tofu until its font arrives from fonts.gstatic.com; then
///   find (Ctrl+F) for "text": the HTML page finds it, the canvas doesn't.
///
/// Each turn the camera comes from the street: the store whole through its
/// glass front, DEMOS over the door; in at the door and on to the table,
/// close on its devices.
class TalkPhones extends Vignette {
  TalkPhones(super.kit);

  @override
  String get name => 'phones';
  @override
  String get kick => 'DEMOS';
  @override
  String get line => 'the same words, the same lines';
  @override
  String get note => 'native fonts break lines their own way; Flutter brings its own';

  @override
  bool get talkOnly => true;

  /// (The talk holds its camera within a visit: every turn.)
  @override
  double get loop => 72;
  @override
  double get visit => 70;

  /// On the west side street, north of the locale office, its glass front
  /// (z = 0) to the street.
  @override
  final frame = trs(vm.Vector3(-28.6, 0, 41.0), rotY: -math.pi / 2);

  /// The pavilion: [_sw] wide, [_sd] deep, [_sh] tall; its door's half
  /// width and height.
  static const _sw = 14.0, _sd = 10.0, _sh = 5.6, _door = 1.4, _doorH = 3.3;

  /// The tables (their middles, in turn's order), their length, width and
  /// top; how far in from a table's front edge its devices stand.
  static const _tables = [(-3.6, 3.0), (3.6, 3.0), (-3.6, 6.6), (3.6, 6.6)];
  static const _tl = 3.4, _tw = 1.1, _top = 0.9, _in = 0.3;

  /// A phone's size (m: a little over life size), its screen's pixels;
  /// how far apart two stand, how far back they lean on their stands.
  static const _w = 0.09, _h = 0.19, _d = 0.0095, _px = 540, _py = 1174, _apart = 0.15, _lean = 0.2;

  /// The turns: the first's quarter turn, its hold; the second's from, its
  /// spin, its hold.
  static const _turn0 = 5.0, _turn1 = 6.1;
  static const _from2 = 20.0, _spin0 = 25.6, _spin1 = 26.5;

  /// The Japanese turns: the phrases' (from [_from3]; the punctuation
  /// carries on from [_from4], the same phones).
  static const _from3 = 40.0, _from4 = 48.0;

  /// The web's turn: from [_from5]; the font arrives at [_fontAt]; find at
  /// [_findAt].
  static const _from5 = 60.0, _fontAt = 65.0, _findAt = 66.4;

  /// A laptop's screen (m), its page's pixels; how far apart two stand.
  static const _bw = 0.3, _bh = 0.185, _bpx = 1300, _bpy = 800, _bx = 0.25;

  static const _lineText = 'Each line is filled up to maxWidth; the next word that won\'t fit starts a new one.';
  static const _sameText = 'These words wrap at different places on each phone\'s own text engine.';

  /// The devices, a table's each: the phone that turns on its side; the
  /// iPhone and the Pixel; the phones for Text() and KumihanText(); the
  /// laptops (the HTML page, found; the canvas page in tofu, with its
  /// font, found nothing).
  late final Phone3D _line, _ios, _android, _plain, _glued;
  late final Laptop3D _html, _canvas;
  late final Texture2D _htmlPage, _htmlFound, _canvasTofu, _canvasFont, _canvasFound;
  late final Texture2D _tall, _wideLines, _iosNative, _androidNative, _flutter, _jaPlain, _jaGlued, _punct;

  /// The store's people: two of its staff, a visitor.
  final _people = <int>[];
  final _poses = List.generate(3, (_) => FigurePose());
  bool _ready = false;
  int _act = 0;

  @override
  List<(String, TextStyle)> get fontRuns => [
    (_sameText, const TextStyle(fontFamily: 'Roboto', fontSize: 40)),
    ('$_plainJa$_punctText', _ja.copyWith(fontSize: 40)),
    ('Hello text □ ⟳ ✓ Noto Sans JP · fonts.gstatic.com… <canvas> <p> example.com', const TextStyle(fontFamily: BP.display, fontSize: 40)),
  ];

  @override
  Future<void> init() async {
    // The paragraph for the same-everywhere turn, at a size where the two
    // platforms' own fonts break it in different places.
    final size = _differingSize();
    // The Japanese sentence at a size where Text() splits two of its words.
    final jaSize = _phraseSize(), split = _split(jaSize);
    final textures = await Future.wait([
      _screen(_lineText, 'Notes', 'maxWidth', const TextStyle(fontFamily: BP.display), 62, guide: true),
      _screen(_lineText, 'Notes', 'maxWidth', const TextStyle(fontFamily: BP.display), 62, guide: true, wide: true),
      _screen(_sameText, 'iOS', 'SF Pro · its own layout', const TextStyle(), size),
      _screen(_sameText, 'Android', 'Roboto · its own layout', const TextStyle(fontFamily: 'Roboto'), size),
      _screen(_sameText, 'Flutter', 'Space Grotesk · one layout', const TextStyle(fontFamily: BP.display), size, flutter: true),
      _phraseScreen(glued: false, split: split, size: jaSize),
      _phraseScreen(glued: true, split: split, size: jaSize),
      _punctScreen(84),
      _browser(canvas: false),
      _browser(canvas: false, find: true),
      _browser(canvas: true, tofu: true),
      _browser(canvas: true),
      _browser(canvas: true, find: true),
    ]);
    _tall = textures[0];
    _wideLines = textures[1];
    _iosNative = textures[2];
    _androidNative = textures[3];
    _flutter = textures[4];
    _jaPlain = textures[5];
    _jaGlued = textures[6];
    _punct = textures[7];
    _htmlPage = textures[8];
    _htmlFound = textures[9];
    _canvasTofu = textures[10];
    _canvasFont = textures[11];
    _canvasFound = textures[12];
    Phone3D phone(PhoneMake make, Texture2D screen, String name, {Texture2D? wide}) =>
        Phone3D(detail, make: make, w: _w, h: _h, d: _d, screen: screen, wide: wide, name: 'demo $name');
    _line = phone(PhoneMake.iphone, _tall, 'line iphone', wide: _wideLines);
    _ios = phone(PhoneMake.iphone, _iosNative, 'ios');
    _android = phone(PhoneMake.pixel, _androidNative, 'android');
    _plain = phone(PhoneMake.iphone, _jaPlain, 'text iphone', wide: _punct);
    _glued = phone(PhoneMake.pixel, _jaGlued, 'kumihan pixel');
    _html = Laptop3D(detail, w: _bw, h: _bh, page: _htmlPage, name: 'demo html laptop');
    _canvas = Laptop3D(detail, w: _bw, h: _bh, page: _canvasFont, name: 'demo canvas laptop');
    await _store();
    _people
      ..add(person(_look(0x2B63C9, 0x2A2F3A, wear: 'casual_m4', staff: true)))
      ..add(person(_look(0x2B63C9, 0x2D3340, wear: 'worker_c', staff: true, slim: true)))
      ..add(person(_look(0xB5543C, 0x3F5F80)));
    if (const String.fromEnvironment('BOOTH3D_TIMES') != '') {
      debugPrint('PHONES ja size ${jaSize.toStringAsFixed(0)}, Text() splits ${[for (final k in split) _phrases[k]].join(' ')}; halt ${_haltWorks(84) ? 'from the font' : 'by letter spacing'}');
    }
    _ready = true;
  }

  /// A size (px) at which SF Pro and Roboto break [_sameText] differently
  /// across the screen's width.
  static double _differingSize() {
    for (final s in [62.0, 60.0, 64.0, 58.0, 66.0, 56.0]) {
      if (!_sameBreaks(_breaks(const TextStyle(), s), _breaks(const TextStyle(fontFamily: 'Roboto'), s))) return s;
    }
    return 62;
  }

  static bool _sameBreaks(List<int> a, List<int> b) => a.length == b.length && [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

  /// Where each line of [_sameText] starts, laid out in [style] at [size]
  /// across the screen's text width.
  static List<int> _breaks(TextStyle style, double size) => _lineStarts(_sameText, style.copyWith(fontSize: size, height: 1.38));

  /// Where each line of [text] in [style] starts, across the screen's text
  /// width.
  static List<int> _lineStarts(String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _px - 2 * _margin);
    final starts = [
      for (final m in tp.computeLineMetrics()) tp.getPositionForOffset(Offset(1, m.baseline - m.ascent + 1)).offset,
    ];
    tp.dispose();
    return starts;
  }

  // ── Japanese: phrases and punctuation ─────────────────────────────────────

  static const _ja = TextStyle(fontFamily: BP.display, locale: Locale('ja'));

  /// A sentence, in its phrases (文節, as BudouX finds them).
  static const _phrases = ['今日は', '天気が', 'いいので、', '公園で', '友達と', '一緒に', 'お弁当を', '食べました。'];
  static final _plainJa = _phrases.join();

  /// The phrases Text() breaks inside, laid out at [size].
  static Set<int> _split(double size) {
    final starts = _lineStarts(_plainJa, _ja.copyWith(fontSize: size, height: 1.5));
    final out = <int>{};
    var at = 0;
    for (final (k, p) in _phrases.indexed) {
      if (starts.any((b) => b > at && b < at + p.length)) out.add(k);
      at += p.length;
    }
    return out;
  }

  /// A size at which Text() splits two of the sentence's words at least.
  static double _phraseSize() {
    for (final s in [64.0, 60.0, 68.0, 56.0, 72.0]) {
      if (_split(s).length >= 2) return s;
    }
    return 64;
  }

  /// The sentence on a phone: as Text() breaks it, or ([glued]) as
  /// KumihanText() does; the [split] phrases marked (red where they're
  /// split, green where they're kept whole).
  Future<Texture2D> _phraseScreen({required bool glued, required Set<int> split, required double size}) => paintedTexture(_px, _py, (c, s) {
    chrome(c, s, glued ? 'KumihanText()' : 'Text()', glued ? 'breaks between phrases' : 'breaks anywhere', flutter: glued);
    final mark = TextStyle(
      background: Paint()..color = glued ? const Color(0x5534C77B) : const Color(0x55E8505F),
      color: glued ? const Color(0xFF0E5A2E) : const Color(0xFF8A1C2A),
    );
    final tp = TextPainter(
      text: TextSpan(
        style: _ja.copyWith(fontSize: size, height: 1.5, color: const Color(0xFF16181D)),
        children: [
          for (final (k, p) in _phrases.indexed) TextSpan(text: glued ? p.split('').join('\u2060') : p, style: split.contains(k) ? mark : null),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: s.width - 2 * _margin);
    tp.paint(c, const Offset(_margin, 236));
    tp.dispose();
    home(c, s);
  });

  static const _punctText = '「こんにちは」「世界」。';

  /// Where 」 meets 「 in [_punctText] (the 」's index).
  static const _meet = 6;

  /// Whether the font's 'halt' (half-width alternates) narrows 」 at
  /// [size]; if not, kumihan's half em is taken off by letter spacing.
  static bool _haltWorks(double size) {
    double width(TextStyle st) {
      final tp = TextPainter(text: TextSpan(text: '」', style: st), textDirection: TextDirection.ltr)..layout();
      final w = tp.width;
      tp.dispose();
      return w;
    }

    final base = _ja.copyWith(fontSize: size);
    return width(base.copyWith(fontFeatures: const [FontFeature('halt')])) < width(base) * 0.75;
  }

  /// The marks on a phone on its side: Text()'s 「こんにちは」「世界」。, and
  /// kumihan's, half an em taken off where 」 meets 「; the gap between
  /// the two marks shown under each (amber, 1 em; green, ½ em).
  Future<Texture2D> _punctScreen(double size) {
    final base = _ja.copyWith(fontSize: size, height: 1.2, color: const Color(0xFF16181D));
    final halt = _haltWorks(size) ? base.copyWith(fontFeatures: const [FontFeature('halt')]) : base.copyWith(letterSpacing: -size / 2);
    return paintedTexture(_py, _px, (c, s) {
      chrome(c, s, '', '', bar: false);
      void row(String name, Color accent, InlineSpan text, double y, String gap, Color gapColor) {
        label(c, name, Offset(_safe, y), 26, accent, weight: FontWeight.w700, family: BP.mono);
        final tp = TextPainter(text: text, textDirection: TextDirection.ltr)..layout();
        const x0 = _safe;
        final ty = y + 34;
        final a = tp.getBoxesForSelection(const TextSelection(baseOffset: _meet, extentOffset: _meet + 1)).first;
        final b = tp.getBoxesForSelection(const TextSelection(baseOffset: _meet + 1, extentOffset: _meet + 2)).first;
        // (Each mark is half an em of ink and half of blank: the gap runs
        // from the middle of 」's box to the middle of 「's.)
        final g0 = x0 + a.left + size / 2, g1 = x0 + b.left + size / 2;
        c.drawRect(Rect.fromLTRB(g0, ty + 6, g1, ty + size * 1.12), Paint()..color = gapColor.withValues(alpha: 0.32));
        tp.paint(c, Offset(x0, ty));
        tp.dispose();
        final my = ty + size * 1.2 + 6;
        final line = Paint()
          ..color = gapColor
          ..strokeWidth = 6;
        c
          ..drawLine(Offset(g0, my), Offset(g1, my), line)
          ..drawLine(Offset(g0, my - 11), Offset(g0, my + 11), line)
          ..drawLine(Offset(g1, my - 11), Offset(g1, my + 11), line);
        label(c, gap, Offset(g1 + 18, my - 22), 38, gapColor, weight: FontWeight.w800, family: BP.mono);
      }

      row('Text()', const Color(0xFF4A505C), TextSpan(text: _punctText, style: base), 92, '1 em', const Color(0xFFE0901A));
      row(
        'KumihanText()',
        const Color(0xFF1565C0),
        TextSpan(
          style: base,
          children: [
            TextSpan(text: _punctText.substring(0, _meet)),
            TextSpan(text: _punctText.substring(_meet, _meet + 1), style: halt),
            TextSpan(text: _punctText.substring(_meet + 1)),
          ],
        ),
        300,
        '½ em',
        const Color(0xFF1E9E55),
      );
      home(c, s);
    });
  }

  static const _margin = 44.0;

  /// On its side, the island's at the left: the content starts clear of it
  /// (the safe area iOS keeps in landscape).
  static const _safe = 96.0;

  /// A screen: the status bar, an app bar ([title], [sub]), [text] laid out
  /// in [style] at [size] across the screen's width (on its side if
  /// [wide]); [guide]: the maxWidth line at the right margin. Corners round
  /// (see-through), as a phone's screen is.
  Future<Texture2D> _screen(String text, String title, String sub, TextStyle style, double size, {bool guide = false, bool wide = false, bool flutter = false}) async {
    final w = wide ? _py : _px, h = wide ? _px : _py;
    return paintedTexture(w, h, (c, s) {
      chrome(c, s, title, sub, flutter: flutter);
      // The paragraph, as this text stack lays it out; each line's last
      // word marked (where it broke).
      final left = wide ? _safe : _margin, maxWidth = s.width - left - _margin;
      final tp = TextPainter(
        text: _marked(text, style.copyWith(fontSize: size, height: 1.38, color: const Color(0xFF16181D)), maxWidth),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth);
      tp.paint(c, Offset(left, 236));
      if (guide) {
        // maxWidth: the line the words fill up to.
        final x = left + maxWidth;
        for (var y = 226.0; y < 236 + tp.height + 10; y += 22) {
          c.drawLine(Offset(x, y), Offset(x, y + 12), Paint()
            ..color = const Color(0xFFF5A524)
            ..strokeWidth = 4);
        }
        label(c, 'maxWidth', Offset(x - 150, 236 + tp.height + 24), 24, const Color(0xFFE0901A), weight: FontWeight.w700, family: BP.mono);
      }
      tp.dispose();
      home(c, s);
    });
  }

  /// A screen's ground (its corners round, see-through), its status bar,
  /// and ([bar]) an app bar: [title], and [sub] saying what's drawing it.
  static void chrome(Canvas c, Size s, String title, String sub, {bool flutter = false, bool bar = true, bool dark = false}) {
    final r = RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(54));
    final ink = dark ? const Color(0xFFF2F4F8) : const Color(0xFF16181D);
    c
      ..clipRRect(r)
      ..drawRect(Offset.zero & s, Paint()..color = dark ? const Color(0xFF14171D) : const Color(0xFFF7F8FA));
    label(c, '9:41', const Offset(_margin, 26), 26, ink, weight: FontWeight.w600);
    final bx = s.width - _margin - 46;
    c
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(bx, 30, 42, 20), const Radius.circular(5)), Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4)
      ..drawRect(Rect.fromLTWH(bx + 4, 34, 30, 12), Paint()..color = ink);
    if (!bar) return;
    final accent = flutter ? const Color(0xFF1565C0) : const Color(0xFF4A505C);
    c.drawRect(Rect.fromLTWH(0, 84, s.width, 116), Paint()..color = flutter ? const Color(0xFFE6F1FD) : const Color(0xFFEDEEF1));
    label(c, title, const Offset(_margin, 100), 44, const Color(0xFF16181D), weight: FontWeight.w700);
    label(c, sub, const Offset(_margin, 154), 24, accent, weight: FontWeight.w600, family: BP.mono);
  }

  /// The home indicator.
  static void home(Canvas c, Size s, {bool dark = false}) => c.drawRRect(
    RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(s.width / 2, s.height - 22), width: 170, height: 9), const Radius.circular(5)),
    Paint()..color = dark ? const Color(0xFFF2F4F8) : const Color(0xFF16181D),
  );

  /// [text] in [style], each line's last word (as laid out across
  /// [maxWidth]) on an amber highlight: only colours change, so the lines
  /// break where they did.
  static TextSpan _marked(String text, TextStyle style, double maxWidth) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout(maxWidth: maxWidth);
    final ends = [
      for (final m in tp.computeLineMetrics()) tp.getPositionForOffset(Offset(maxWidth + 20, m.baseline - m.ascent / 2)).offset,
    ];
    tp.dispose();
    final mark = TextStyle(background: Paint()..color = const Color(0x66F5A524), color: const Color(0xFF7A4A00));
    final spans = <TextSpan>[];
    var at = 0;
    for (final e in ends) {
      if (e <= at) continue;
      final line = text.substring(at, e).trimRight();
      final cut = at + line.lastIndexOf(' ') + 1;
      spans
        ..add(TextSpan(text: text.substring(at, cut)))
        ..add(TextSpan(text: text.substring(cut, at + line.length), style: mark))
        ..add(TextSpan(text: text.substring(at + line.length, e)));
      at = e;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: style, children: spans);
  }

  static void label(Canvas c, String s, Offset at, double size, Color color, {FontWeight weight = FontWeight.w500, String? family}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontFamily: family ?? BP.display, fontSize: size, color: color, fontWeight: weight)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, at);
    tp.dispose();
  }

  /// A browser window: a tab ([canvas]: the Flutter web page, its text
  /// pixels on a canvas; else an HTML page), the address bar, two lines
  /// of text — the Japanese in [tofu] until its font's arrived — and
  /// ([find]) the find bar, searching for "text".
  Future<Texture2D> _browser({required bool canvas, bool tofu = false, bool find = false}) => paintedTexture(_bpx, _bpy, (c, s) {
    final r = RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(22));
    c
      ..clipRRect(r)
      ..drawRect(Offset.zero & s, Paint()..color = const Color(0xFFFFFFFF))
      ..drawRect(Rect.fromLTWH(0, 0, s.width, 150), Paint()..color = const Color(0xFFDEE1E6));
    // The tab, the address bar.
    final tab = RRect.fromRectAndCorners(Rect.fromLTWH(40, 14, 560, 62), topLeft: const Radius.circular(16), topRight: const Radius.circular(16));
    c
      ..drawRRect(tab, Paint()..color = const Color(0xFFFFFFFF))
      ..drawRect(Rect.fromLTWH(0, 76, s.width, 74), Paint()..color = const Color(0xFFFFFFFF))
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(40, 86, s.width - 80, 54), const Radius.circular(27)), Paint()..color = const Color(0xFFF1F3F4));
    label(c, canvas ? 'Flutter web · <canvas>' : 'HTML page · <p>', const Offset(66, 22), 40, const Color(0xFF202124), weight: FontWeight.w700);
    label(c, 'example.com', const Offset(80, 96), 30, const Color(0xFF5F6368), weight: FontWeight.w500);
    // The text.
    const big = TextStyle(fontFamily: BP.display, fontSize: 118, color: Color(0xFF202124), fontWeight: FontWeight.w600);
    final mark = TextStyle(background: Paint()..color = const Color(0xFFFFE066));
    final line1 = TextPainter(
      text: TextSpan(
        style: big,
        children: [const TextSpan(text: 'Hello '), TextSpan(text: 'text', style: find && !canvas ? mark : null)],
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    line1.paint(c, const Offset(80, 210));
    line1.dispose();
    final line2 = TextPainter(
      text: TextSpan(text: tofu ? '□□□□□' : 'こんにちは', style: big.copyWith(locale: const Locale('ja'), color: tofu ? const Color(0xFF9AA0A6) : null)),
      textDirection: TextDirection.ltr,
    )..layout();
    line2.paint(c, const Offset(80, 380));
    line2.dispose();
    if (canvas) {
      // The font: on its way, then here.
      final pill = RRect.fromRectAndRadius(Rect.fromLTWH(60, 610, 1060, 96), const Radius.circular(48));
      c.drawRRect(pill, Paint()..color = tofu ? const Color(0xFFFFF4E0) : const Color(0xFFE6F4EA));
      label(c, tofu ? '⟳ Noto Sans JP · fonts.gstatic.com…' : '✓ Noto Sans JP arrived', const Offset(100, 628), 48, tofu ? const Color(0xFFB06000) : const Color(0xFF1E8E3E), weight: FontWeight.w700);
    }
    if (find) {
      // The find bar, top right.
      final bar = RRect.fromRectAndRadius(Rect.fromLTWH(s.width - 620, 166, 580, 104), const Radius.circular(16));
      c
        ..drawRRect(bar.shift(const Offset(0, 6)), Paint()..color = const Color(0x22000000))
        ..drawRRect(bar, Paint()..color = const Color(0xFFFFFFFF))
        ..drawRRect(
          bar,
          Paint()
            ..color = const Color(0xFFDADCE0)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      label(c, 'text', Offset(s.width - 590, 182), 54, const Color(0xFF202124), weight: FontWeight.w600);
      label(c, canvas ? '0 of 0' : '1 of 1', Offset(s.width - 290, 186), 50, canvas ? const Color(0xFFD93025) : const Color(0xFF1E8E3E), weight: FontWeight.w800, family: BP.mono);
    }
  });

  // ── The store ─────────────────────────────────────────────────────────────

  /// The pavilion: a pale stone floor; stone side and back walls; the
  /// glass front between steel fins, the door open in its middle; a white
  /// roof round a skylight, DEMOS on its front; inside, four oak tables (a
  /// round white stand for each device), a screen on the back wall.
  /// (Nothing of it casts a shadow: inside is as bright as a store's.)
  Future<void> _store() async {
    final b = Batch(), clear = Batch();
    final stone = pbr(rgb(1, 1, 1), roughness: 0.62), oak = pbr(rgb(1, 1, 1), roughness: 0.5);
    final steel = pbr(rgb(1, 1, 1), metallic: 0.85, roughness: 0.3);
    final glass = pbr(rgb(0.86, 0.93, 0.97, 0.14), roughness: 0.05)..alphaMode = AlphaMode.blend;
    final wall = Vignette.c(0xE7E2D9), floor = Vignette.c(0xD9D4CC), white = Vignette.c(0xF4F3F0), grey = Vignette.c(0x5E646C);
    const hw = _sw / 2;
    // The floor, the side walls, the back.
    box(b, stone, _sw, 0.08, _sd, 0, 0.04, _sd / 2, floor);
    for (final x in [-hw + 0.15, hw - 0.15]) {
      box(b, stone, 0.3, _sh, _sd, x, _sh / 2, _sd / 2, wall);
    }
    box(b, stone, _sw, _sh, 0.3, 0, _sh / 2, _sd - 0.15, wall);
    // The roof round its skylight (glass over the tables).
    const t = 0.32, y = _sh + t / 2, sx = 4.6, sz0 = 1.8, sz1 = 8.2;
    box(b, stone, _sw + 0.4, t, sz0 + 0.5, 0, y, (sz0 - 0.5) / 2, white);
    box(b, stone, _sw + 0.4, t, _sd + 0.2 - sz1, 0, y, (sz1 + _sd + 0.2) / 2, white);
    for (final s in [-1.0, 1.0]) {
      box(b, stone, hw + 0.2 - sx, t, sz1 - sz0, s * (sx + hw + 0.2) / 2, y, (sz0 + sz1) / 2, white);
    }
    box(clear, glass, 2 * sx, 0.03, sz1 - sz0, 0, _sh + t - 0.03, (sz0 + sz1) / 2, Vignette.c(0xFFFFFF));
    for (var x = -sx + 1.15; x < sx; x += 2.3) {
      box(b, steel, 0.06, 0.08, sz1 - sz0, x, _sh + t - 0.06, (sz0 + sz1) / 2, grey);
    }
    // The front: steel fins between full-height panes; the door open in the
    // middle, glass over it; a band under the roof for the sign.
    const top = _sh - 0.75, bay = 2.8;
    for (var k = -2; k <= 2; k++) {
      final x = k * bay;
      if (k == 0) {
        box(clear, glass, 2 * _door - 0.08, top - _doorH, 0.03, x, (top + _doorH) / 2, 0, Vignette.c(0xFFFFFF));
        box(b, steel, 2 * _door, 0.1, 0.12, x, _doorH, 0, grey);
      } else {
        box(clear, glass, bay - 0.08, top - 0.08, 0.03, x, (top + 0.08) / 2, 0, Vignette.c(0xFFFFFF));
      }
    }
    for (var k = -2; k <= 3; k++) {
      box(b, steel, 0.08, top, 0.28, (k - 0.5) * bay, top / 2, 0, grey);
    }
    box(b, stone, _sw + 0.4, _sh - top, 0.3, 0, (_sh + top) / 2, 0, white);
    b.buildInto(shell, 'demo store', castsShadows: false);
    clear.buildInto(shell, 'demo store glass', castsShadows: false);
    // The tables (their shadows on the floor): an oak top on two slab legs;
    // a stand for each phone.
    final tables = Batch();
    for (final (tx, tz) in _tables) {
      box(tables, oak, _tl, 0.06, _tw, tx, _top - 0.03, tz, Vignette.c(0xC9A57C));
      for (final s in [-1.0, 1.0]) {
        box(tables, oak, 0.06, _top - 0.06, _tw - 0.2, tx + s * (_tl / 2 - 0.35), (_top - 0.06) / 2, tz, Vignette.c(0xB8946B));
      }
    }
    for (final (x, z) in [(_tables[0].$1, _tables[0].$2), for (final i in [1, 2]) for (final s in [-1.0, 1.0]) (_tables[i].$1 + s * _apart, _tables[i].$2)]) {
      cylinder(tables, stone, 0.055, 0.012, x, _top + 0.006, z - _tw / 2 + _in, white);
    }
    tables.buildInto(shell, 'demo tables');
    // The sign over the door, and the screen on the back wall.
    await Future.wait([
      sign(5.2, 0.62, trs(vm.Vector3(0, (_sh + top) / 2, -0.17)), (c, s) {
        c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFF4F3F0));
        label(c, 'DEMOS', Offset(s.width * 0.31, s.height * 0.08), s.height * 0.72, const Color(0xFF1C2230), weight: FontWeight.w700);
      }, px: 1040, glow: 0.35, thick: 0.03, shell: true),
      sign(7.4, 2.6, trs(vm.Vector3(0, 2.6, _sd - 0.31)), (c, s) {
        c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF0E1420));
        label(c, 'DEMOS', Offset(s.width * 0.07, s.height * 0.16), s.height * 0.3, const Color(0xFFF2F4F8), weight: FontWeight.w700);
        label(c, 'Flutter text, on every screen', Offset(s.width * 0.07, s.height * 0.56), s.height * 0.1, const Color(0xFF8FB8FF), weight: FontWeight.w600);
        label(c, 'line breaking · one layout · phrases · punctuation · the web', Offset(s.width * 0.07, s.height * 0.72), s.height * 0.065, const Color(0xFF9AA3B2));
      }, px: 1480, glow: 0.6, thick: 0.05, shell: true),
    ]);
  }

  static FigureLook _look(int top, int legs, {String? wear, bool staff = false, bool slim = false}) => FigureLook()
    ..top = rgbHex(top)
    ..legs = rgbHex(legs)
    ..shoes = rgbHex(0x1B1C20)
    ..skin = rgbHex(slim ? 0xE8C6AC : 0xD9AE8E)
    ..hairColor = rgbHex(0x1F1915)
    ..hair = slim ? Hair.bob : Hair.short
    ..slim = slim
    ..wear = wear
    ..atWork = staff;

  // ── Posing ────────────────────────────────────────────────────────────────

  @override
  void pose(double u, double t, double night) {
    if (!_ready) return;
    if (visited) _act = u < 15 ? 1 : (u < 35 ? 2 : (u < _from4 ? 3 : (u < 58 ? 4 : 5)));
    // Each table's devices: as their turn has them, else as they wait.
    _lines(_act == 1 ? u : null);
    _same(_act == 2 ? u : null);
    _japanese(_act == 3 || _act == 4 ? u : null);
    _browsing(_act == 5 ? u : null);
    // The staff: one by the back wall, one by the side; a visitor at the
    // first table's far end.
    for (final (i, (x, z, yaw)) in [(0.2, 8.7, 0.0), (6.1, 4.8, math.pi / 2), (-5.6, 1.95, math.pi)].indexed) {
      final p = _poses[i]..rest();
      p.pos.setValues(x, 0.08, z);
      Idle.stand(p, t, Manner.of(140 + i), look: 0.6);
      p.yaw += yaw;
      draw(_people[i], p);
    }
  }

  /// Where a device stands on table [k]: [dx] along it from its middle.
  static vm.Vector3 _spot(int k, double dx) {
    final (tx, tz) = _tables[k];
    return vm.Vector3(tx + dx, _top, tz - _tw / 2 + _in);
  }

  /// Phone [p] on its stand at [at] (the stand's middle, on the table):
  /// leaning back, [roll]ed about its face ([roll] a quarter turn: on its
  /// side), turned [yaw] with its stand.
  void _phoneOn(Phone3D p, vm.Vector3 at, {double yaw = 0, double roll = 0}) {
    final half = lerp(_h, _w, (roll / (math.pi / 2)).abs().clamp(0.0, 1.0)) / 2;
    final up = half * math.cos(_lean), back = half * math.sin(_lean);
    final c = vm.Vector3(at.x + back * math.sin(yaw), at.y + 0.014 + up, at.z + back * math.cos(yaw));
    p.place(place(trs(c, rotY: yaw, rotX: _lean, rotZ: roll)));
  }

  /// The first table: the phone turned on its side (from portrait).
  void _lines(double? u) {
    final turn = u == null ? 0.0 : eio(seg(u, _turn0, _turn1));
    _line
      ..screen = _tall
      ..wideScreen = _wideLines
      ..wide = turn >= 0.5;
    _phoneOn(_line, _spot(0, 0), roll: math.pi / 2 * turn);
  }

  /// The second: the iPhone and the Pixel, native; a turn on their
  /// turntables, and Flutter's.
  void _same(double? u) {
    final spin = u == null ? 0.0 : 2 * math.pi * eio(seg(u, _spin0, _spin1));
    final flutter = u != null && u >= (_spin0 + _spin1) / 2;
    _ios.screen = flutter ? _flutter : _iosNative;
    _android.screen = flutter ? _flutter : _androidNative;
    _phoneOn(_ios, _spot(1, -_apart), yaw: spin + 0.06);
    _phoneOn(_android, _spot(1, _apart), yaw: spin - 0.06);
  }

  /// The third: Text() and KumihanText(); then the first on its side, the
  /// marks' spacing.
  void _japanese(double? u) {
    final turn = u == null ? 0.0 : eio(seg(u, _from4 + 0.4, _from4 + 1.4));
    _plain
      ..screen = _jaPlain
      ..wideScreen = _punct
      ..wide = turn >= 0.5;
    _phoneOn(_plain, _spot(2, -_apart), yaw: 0.06, roll: math.pi / 2 * turn);
    _phoneOn(_glued, _spot(2, _apart), yaw: -0.06);
  }

  /// The last: the two laptops; the canvas page's font arriving; find.
  void _browsing(double? u) {
    _html.page = u == null || u < _findAt ? _htmlPage : _htmlFound;
    _canvas.page = u == null ? _canvasFont : (u < _fontAt ? _canvasTofu : (u < _findAt ? _canvasFont : _canvasFound));
    for (final (i, l) in [_html, _canvas].indexed) {
      final side = i == 0 ? -1.0 : 1.0;
      final at = _spot(3, side * _bx)..z -= 0.12;
      l.place(place(trs(at, rotY: -side * 0.1)));
    }
  }

  // ── The camera ────────────────────────────────────────────────────────────

  /// Each turn's table, when it starts; how far from its devices the camera
  /// stops, and how much of the table it takes in.
  static double _from(int k) => const [0.0, _from2, _from3, _from5][k];
  static const _near = [0.46, 0.56, 0.56, 0.9];

  /// From the street, in at the door, to the table: the store whole through
  /// its glass, then down the aisle, close on the devices (on the first of
  /// the Japanese phones for the marks).
  @override
  Shot shot(double u) {
    final k = u < 15 ? 0 : (u < 35 ? 1 : (u < 58 ? 2 : 3));
    final f = eio(seg(u, _from(k) + 0.4, _from(k) + 4.6));
    var at = _spot(k, 0)..y += k == 3 ? 0.15 : 0.1;
    var near = _near[k];
    if (k == 2) {
      // (The marks: in on the first phone, on its side.)
      final m = eio(seg(u, _from4 + 0.2, _from4 + 1.6));
      at = at..x -= _apart * m;
      near = lerp(near, 0.48, m);
    }
    final end = vm.Vector3(at.x, at.y + 0.42 * near, at.z - near);
    final pts = [vm.Vector3(0, 2.6, -11.5), vm.Vector3(0, 1.75, -0.7), end];
    final eye = _path(pts, f);
    final target = vm.Vector3(lerp(0, at.x, eio(seg(f, 0.25, 1))), lerp(2.0, at.y, eio(seg(f, 0.2, 1))), lerp(3.0, at.z, eio(seg(f, 0.2, 1))));
    return Shot(eye, target, fov: lerp(44, 40, f), settle: 1.0, drift: lerp(0.4, 0.15, f));
  }

  /// [f] (0..1) of the way along [pts]: a smooth curve through them, as far
  /// between each two as their distance.
  static vm.Vector3 _path(List<vm.Vector3> pts, double f) {
    final lens = [for (var i = 0; i + 1 < pts.length; i++) pts[i].distanceTo(pts[i + 1])];
    final total = lens.fold<double>(0, (a, b) => a + b);
    var d = f * total;
    for (var i = 0; i < lens.length; i++) {
      if (d <= lens[i] || i == lens.length - 1) {
        final u = (d / lens[i]).clamp(0.0, 1.0);
        final p0 = pts[math.max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[math.min(i + 2, pts.length - 1)];
        // (Catmull-Rom.)
        final u2 = u * u, u3 = u2 * u;
        return (p1 * 2 + (p2 - p0) * u + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * u2 + (-p0 + p1 * 3 - p2 * 3 + p3) * u3) * 0.5;
      }
      d -= lens[i];
    }
    return pts.last.clone();
  }
}
