import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'devices.dart';
import 'kit.dart';
import 'shot.dart';
import 'v_phones.dart' show TalkPhones;
import 'vignette.dart';

/// How others do it: four screens hung in a row over the east side street,
/// one engine each, showing what its way of setting text gives it — only
/// while the talk calls on them. The camera glides along the row:
///
/// * Chrome (0–9 s): a web page, its text in the DOM: a headline balanced
///   over two lines, a paragraph hyphenated, a column of vertical Japanese
///   with ruby — all CSS; then find (Ctrl+F) lights up every "text", and a
///   sentence is selected, to copy or to translate;
/// * Figma (10–19 s): a design tool's canvas, its own text engine: a text
///   layer, mixed English and Arabic, zoomed from 100% to 400% to 1600%,
///   sharp all the way (drawn from the outlines each time);
/// * macOS (20–29 s): a document in Core Text: an English paragraph
///   justified and hyphenated, beside vertical Japanese with ruby, all
///   built into the platform;
/// * Android (30–39 s): a phone with one paragraph three times, as
///   Minikin's three break strategies lay it out: simple (first fit, what
///   Flutter does), balanced, and high quality (hyphenated); each lit in
///   turn;
/// * and Flutter (40–49 s, for the trade-off): the web page again, as
///   Flutter's Text() sets it: the headline not balanced, no hyphens, the
///   Japanese across with its readings in brackets — each a red tag.
class TalkEngines extends Vignette {
  TalkEngines(super.kit);

  @override
  String get name => 'engines';
  @override
  String get kick => 'HOW OTHERS DO IT';
  @override
  String get line => 'four engines, four screens';
  @override
  String get note => 'each one shows what its way of setting text gives it';

  @override
  bool get talkOnly => true;

  /// A navy wall behind the row: the screens read against it, not against
  /// the street's buildings.
  @override
  ({vm.Vector3 at, double w, double h})? get backdrop => (at: vm.Vector3(4.5, 6.6, 1.6), w: 49, h: 9.2);

  @override
  double get loop => 52;
  @override
  double get visit => 50;

  /// Over the east side street, facing the plaza (its −z: west); the row
  /// runs south (its +x), Chrome first.
  @override
  final frame = trs(vm.Vector3(21.5, 0, 15.0), rotY: math.pi / 2);

  /// The screens' places along the row, their height; a window's size (m)
  /// and pixels; the phone's.
  static const _xs = [-13.5, -4.5, 4.5, 13.5, 22.5];
  static const _y = 11.0;
  static const _ww = 5.6, _wh = 3.5, _wpx = 1600, _wpy = 1000;
  static const _pw = 1.81, _ph = 3.81, _ppx = 540, _ppy = 1174;

  /// Each act's start (its screen in front), and when its steps come.
  static const _acts = [0.0, 10.0, 20.0, 30.0, 40.0];
  static const _findAt = 3.0, _selectAt = 5.6;
  static const _zoom1 = 13.0, _zoom2 = 15.6;
  static const _lit = [31.0, 33.4, 35.8];

  late final Window3D _chrome, _figma, _mac, _flutter;
  late final Phone3D _android;
  late final List<Texture2D> _chromePages, _figmaPages, _androidScreens;
  late final Texture2D _macPage, _flutterPage;
  bool _ready = false;

  static const _ui = TextStyle(fontFamily: BP.display);
  static const _ja = TextStyle(fontFamily: BP.display, locale: Locale('ja'));

  @override
  List<(String, TextStyle)> get fontRuns => [
    ('$_headline $_webText $_macText $_androidText Hello مرحبا Layers Frame Text Inter 1600% typography.example', _ui.copyWith(fontSize: 40)),
    ([for (final (b, r) in _vertical) '$b${r ?? ''}'].join(), _ja.copyWith(fontSize: 40)),
  ];

  @override
  Future<void> init() async {
    final pages = await Future.wait([
      _chromePage(),
      _chromePage(find: true),
      _chromePage(find: true, select: true),
      _figmaPage(1),
      _figmaPage(4),
      _figmaPage(16),
      _macWindow(),
      _androidScreen(-1),
      for (var k = 0; k < 3; k++) _androidScreen(k),
      _flutterText(),
    ]);
    _chromePages = pages.sublist(0, 3);
    _figmaPages = pages.sublist(3, 6);
    _macPage = pages[6];
    _androidScreens = pages.sublist(7, 11);
    _flutterPage = pages[11];
    _chrome = Window3D(detail, w: _ww, h: _wh, page: _chromePages[0], name: 'engines chrome');
    _figma = Window3D(detail, w: _ww, h: _wh, page: _figmaPages[0], name: 'engines figma');
    _mac = Window3D(detail, w: _ww, h: _wh, page: _macPage, name: 'engines macos');
    _android = Phone3D(detail, make: PhoneMake.pixel, w: _pw, h: _ph, screen: _androidScreens[0], name: 'engines android');
    _flutter = Window3D(detail, w: _ww, h: _wh, page: _flutterPage, name: 'engines flutter');
    if (const String.fromEnvironment('BOOTH3D_TIMES') != '') {
      const body = TextStyle(fontFamily: 'Roboto', fontSize: 30, height: 1.3);
      String show(List<String> l) => l.map((x) => '[$x]').join(' ');
      debugPrint('ENGINES simple ${show(_lines(_androidText, body, 452, hyphens: false))}');
      debugPrint('ENGINES balanced ${show(_balanced(_androidText, body, 452))}');
      debugPrint('ENGINES best ${show(_lines(_androidText, body, 452, best: true))}');
      const h1 = TextStyle(fontFamily: BP.display, fontSize: 68, fontWeight: FontWeight.w700, height: 1.15);
      debugPrint('ENGINES headline first fit ${show(_lines(_headline, h1, 960, hyphens: false))} balanced ${show(_balanced(_headline, h1, 960))}');
      debugPrint('ENGINES web ${show(_lines(_webText, _ui.copyWith(fontSize: 40, height: 1.25), 600))}');
      debugPrint('ENGINES mac ${show(_lines(_macText, _ui.copyWith(fontSize: 46, height: 1.25), 820, best: true, hyphenCost: 0.002))}');
    }
    _ready = true;
  }

  // ── Setting the text ──────────────────────────────────────────────────────

  static const _headline = 'Every page gets the platform’s typography for free';
  static const _webText =
      'Text in the DOM is text the browser understands: it can find text, select it, translate it and read it '
      'aloud, and it hyphe·nates long words like ty·pog·ra·phy for you, with the same text engine as the page.';
  static const _macText =
      'Core Text sets type the way a book does: it hyphe·nates and jus·ti·fies, sets Jap·a·nese ver·ti·cal·ly and '
      'puts ruby over it, all built into the plat·form.';
  static const _androidText =
      'Minikin weighs a whole para·graph before it breaks a line, and hyphe·nates long words like ty·pog·ra·phy '
      'when it helps.';

  /// Vertical Japanese with ruby: each run and its reading (null: none).
  static const _vertical = [
    ('縦書', 'たてが'),
    ('き', null),
    ('の', null),
    ('文字', 'もじ'),
    ('は', null),
    ('右', 'みぎ'),
    ('から', null),
    ('左', 'ひだり'),
    ('へ', null),
    ('読', 'よ'),
    ('む', null),
  ];

  /// [text]'s words, each in its pieces (where '·' allows a hyphen).
  static List<List<String>> _words(String text) => [for (final w in text.split(' ')) w.split('·')];

  /// A line of [words]' pieces from piece (i, j) up to (k, l): its text,
  /// hyphenated if it ends mid-word.
  static String _lineText(List<List<String>> words, int fromWord, int fromPiece, int toWord, int toPiece) {
    final b = StringBuffer();
    for (var w = fromWord; w <= toWord && w < words.length; w++) {
      final p0 = w == fromWord ? fromPiece : 0, p1 = w == toWord ? toPiece : words[w].length;
      if (w > fromWord) b.write(' ');
      b.write(words[w].sublist(p0, math.min(p1, words[w].length)).join());
    }
    if (toWord < words.length && toPiece > 0 && toPiece < words[toWord].length) b.write('-');
    return b.toString();
  }

  static double _width(String s, TextStyle style) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }

  /// [text] broken into lines of at most [maxWidth]: first fit (each line
  /// as full as it goes, as Flutter does; [hyphens]: a word hyphenated
  /// where '·' allows if that fills the line, as browsers do), or ([best])
  /// the breaks that make the lines most even over the whole paragraph,
  /// hyphenating where '·' allows (Knuth and Plass's idea, as Minikin's
  /// high quality does).
  static List<String> _lines(String text, TextStyle style, double maxWidth, {bool best = false, bool hyphens = true, double hyphenCost = 0.02}) {
    final words = _words(text);
    // The places a line may end: after a word, or (hyphens) inside one.
    final stops = <(int, int)>[];
    for (var w = 0; w < words.length; w++) {
      if (hyphens) {
        for (var p = 1; p < words[w].length; p++) {
          stops.add((w, p));
        }
      }
      stops.add((w + 1, 0));
    }
    String line(int a, int b) {
      final (fw, fp) = a < 0 ? (0, 0) : stops[a];
      final (tw, tp) = stops[b];
      return tp == 0 ? _lineText(words, fw, fp, tw - 1, words[tw - 1].length) : _lineText(words, fw, fp, tw, tp);
    }

    if (!best) {
      final out = <String>[];
      var from = -1;
      while (from < stops.length - 1) {
        var to = from + 1;
        // The furthest break that fits (inside a word too, where hyphens
        // are allowed: as a browser's hyphens: auto does).
        int? fit;
        for (var b = from + 1; b < stops.length; b++) {
          if (_width(line(from, b), style) <= maxWidth) {
            fit = b;
          } else {
            break;
          }
        }
        to = fit ?? to;
        out.add(line(from, to));
        from = to;
      }
      return out;
    }
    // The fewest badness to each stop: (W − width)² a line, a hyphen a
    // little extra; the last line free.
    final n = stops.length;
    final cost = List<double>.filled(n + 1, double.infinity), prev = List<int>.filled(n + 1, -1);
    cost[0] = 0; // (index i + 1 ↔ stop i; 0: the start)
    for (var b = 0; b < n; b++) {
      for (var a = b - 1; a >= -1; a--) {
        final s = line(a, b), w = _width(s, style);
        if (w > maxWidth) break;
        final last = b == n - 1;
        final slack = maxWidth - w, short = math.max(0.0, 0.4 * maxWidth - w);
        // (The last line free, unless it's a word or two on its own.)
        final c = cost[a + 1] + (last ? 4 * short * short : slack * slack) + (s.endsWith('-') ? maxWidth * maxWidth * hyphenCost : 0);
        if (c < cost[b + 1]) {
          cost[b + 1] = c;
          prev[b + 1] = a;
        }
      }
    }
    final out = <String>[];
    for (var b = n - 1; b >= 0;) {
      final a = prev[b + 1];
      out.insert(0, line(a, b));
      b = a;
    }
    return out;
  }

  /// [text] (no hyphens) in as few lines as first fit takes at [maxWidth],
  /// the words shared out so the lines are as even as they go: the longest
  /// as short as it can be (CSS's text-wrap: balance, Minikin's balanced).
  static List<String> _balanced(String text, TextStyle style, double maxWidth) {
    final words = text.replaceAll('·', '').split(' ');
    final n = _lines(text, style, maxWidth, hyphens: false).length;
    // best[k][i]: the longest line, words 0..i−1 in k lines (and where the
    // last of them starts).
    double width(int a, int b) => _width(words.sublist(a, b).join(' '), style);
    final best = List.generate(n + 1, (_) => List<double>.filled(words.length + 1, double.infinity));
    final from = List.generate(n + 1, (_) => List<int>.filled(words.length + 1, 0));
    best[0][0] = 0;
    for (var k = 1; k <= n; k++) {
      for (var i = 1; i <= words.length; i++) {
        for (var a = i - 1; a >= 0; a--) {
          if (best[k - 1][a] == double.infinity) continue;
          final lw = width(a, i);
          if (lw > maxWidth) break;
          final m = math.max(best[k - 1][a], lw);
          if (m < best[k][i]) {
            best[k][i] = m;
            from[k][i] = a;
          }
        }
      }
    }
    final out = <String>[];
    for (var k = n, i = words.length; k > 0; k--) {
      final a = from[k][i];
      out.insert(0, words.sublist(a, i).join(' '));
      i = a;
    }
    return out;
  }

  /// Paints [lines] from (x, y), [lead] apart; ([justify]) every line but
  /// the last spread to [width]. Returns each line's top-left and painter
  /// metrics (for marking words), and the bottom.
  static double _paintLines(Canvas c, List<String> lines, TextStyle style, double x, double y, double lead, {double? width, bool justify = false, List<(String, Rect)>? words}) {
    for (final (i, l) in lines.indexed) {
      final last = i == lines.length - 1;
      if (justify && !last && width != null) {
        final parts = l.split(' ');
        final ws = [for (final p in parts) _width(p, style)];
        final gap = parts.length > 1 ? (width - ws.reduce((a, b) => a + b)) / (parts.length - 1) : 0.0;
        var px = x;
        for (final (k, p) in parts.indexed) {
          _text(c, p, style, Offset(px, y));
          words?.add((p, Rect.fromLTWH(px, y, ws[k], lead)));
          px += ws[k] + gap;
        }
      } else {
        _text(c, l, style, Offset(x, y));
        if (words != null) {
          var px = x;
          final space = _width(' ', style);
          for (final p in l.split(' ')) {
            final w = _width(p, style);
            words.add((p, Rect.fromLTWH(px, y, w, lead)));
            px += w + space;
          }
        }
      }
      y += lead;
    }
    return y;
  }

  /// Where each word of [lines] (unjustified) lands, from (x, y), [lead]
  /// apart.
  static List<(String, Rect)> _wordRects(List<String> lines, TextStyle style, double x, double y, double lead) {
    final out = <(String, Rect)>[];
    final space = _width(' ', style);
    for (final l in lines) {
      var px = x;
      for (final p in l.split(' ')) {
        final w = _width(p, style);
        out.add((p, Rect.fromLTWH(px, y, w, lead)));
        px += w + space;
      }
      y += lead;
    }
    return out;
  }

  static void _text(Canvas c, String s, TextStyle style, Offset at) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, at);
    tp.dispose();
  }

  /// A small mono tag (a CSS property, a setting) in a pill.
  static void _tag(Canvas c, String s, Offset at, {Color ink = const Color(0xFF5F6368), Color fill = const Color(0xFFF1F3F4), double size = 22}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontFamily: BP.mono, fontSize: size, color: ink, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(at.dx, at.dy, tp.width + 24, tp.height + 10), Radius.circular((tp.height + 10) / 2)), Paint()..color = fill);
    tp.paint(c, at + const Offset(12, 5));
    tp.dispose();
  }

  /// Vertical Japanese with ruby in columns from [right] leftwards, [size]
  /// a character, [perColumn] to a column; each ruby run's reading small,
  /// down its right side.
  static void _verticalText(Canvas c, double right, double top, double size, int perColumn, Color ink, Color rubyInk) {
    final cells = <(String, String?, int)>[]; // (character, its run's reading, the run's length) at the run's first
    for (final (base, ruby) in _vertical) {
      for (var i = 0; i < base.length; i++) {
        cells.add((base[i], i == 0 ? ruby : null, i == 0 ? base.length : 0));
      }
    }
    final col = size * 1.9, step = size * 1.08;
    for (final (k, (ch, ruby, run)) in cells.indexed) {
      final x = right - col * (k ~/ perColumn) - size, y = top + step * (k % perColumn);
      _text(c, ch, _ja.copyWith(fontSize: size, color: ink, height: 1.0), Offset(x, y));
      if (ruby != null) {
        // Its reading beside the run (as tall as the run, or a little more).
        final rs = size * 0.44, span = step * math.min(run, perColumn - k % perColumn);
        final gap = math.max(0.0, (span - rs * 1.04 * ruby.length) / 2);
        for (var i = 0; i < ruby.length; i++) {
          _text(c, ruby[i], _ja.copyWith(fontSize: rs, color: rubyInk, height: 1.0), Offset(x + size * 1.04, y + gap + rs * 1.04 * i));
        }
      }
    }
  }

  // ── The pages ─────────────────────────────────────────────────────────────

  /// The web page: a browser's tab and address bar; the headline balanced,
  /// the paragraph hyphenated, vertical Japanese with ruby; ([find]) the
  /// find bar and every "text" lit, ([select]) a sentence selected and its
  /// menu.
  Future<Texture2D> _chromePage({bool find = false, bool select = false}) => paintedTexture(_wpx, _wpy, (c, s) {
    c
      ..clipRRect(RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(22)))
      ..drawRect(Offset.zero & s, Paint()..color = const Color(0xFFFFFFFF))
      ..drawRect(Rect.fromLTWH(0, 0, s.width, 132), Paint()..color = const Color(0xFFDEE1E6));
    final tab = RRect.fromRectAndCorners(Rect.fromLTWH(36, 12, 520, 56), topLeft: const Radius.circular(14), topRight: const Radius.circular(14));
    c
      ..drawRRect(tab, Paint()..color = const Color(0xFFFFFFFF))
      ..drawRect(Rect.fromLTWH(0, 68, s.width, 64), Paint()..color = const Color(0xFFFFFFFF))
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(36, 76, s.width - 72, 48), const Radius.circular(24)), Paint()..color = const Color(0xFFF1F3F4));
    _text(c, 'Typography · Chrome', _ui.copyWith(fontSize: 30, color: const Color(0xFF202124), fontWeight: FontWeight.w700), const Offset(62, 22));
    _text(c, 'typography.example', _ui.copyWith(fontSize: 26, color: const Color(0xFF5F6368)), const Offset(72, 85));
    // The headline, balanced.
    final h1 = _ui.copyWith(fontSize: 68, color: const Color(0xFF202124), fontWeight: FontWeight.w700, height: 1.15);
    _tag(c, 'text-wrap: balance', const Offset(70, 156), size: 24);
    final y1 = _paintLines(c, _balanced(_headline, h1, 960), h1, 70, 204, 80);
    // The paragraph, hyphenated (and every "text" in it, for find).
    final body = _ui.copyWith(fontSize: 40, color: const Color(0xFF3C4043), height: 1.25);
    _tag(c, 'hyphens: auto', Offset(70, y1 + 22), size: 24);
    final words = <(String, Rect)>[];
    final lines = _lines(_webText, body, 600);
    void Function()? menu;
    if (select) {
      // "it can find text, select it, translate it and read it aloud",
      // selected: the words from "can" to "aloud".
      final probe = _wordRects(lines, body, 70, y1 + 76, 50);
      final from = probe.indexWhere((w) => w.$1 == 'can'), to = probe.indexWhere((w) => w.$1.startsWith('aloud'));
      for (var k = from; k >= 0 && k <= to; k++) {
        c.drawRect(probe[k].$2.inflate(3), Paint()..color = const Color(0x553D7EFF));
      }
      if (to >= 0) {
        // The menu by the selection (over the text).
        final r = probe[to].$2;
        menu = () {
          final box = RRect.fromRectAndRadius(Rect.fromLTWH(r.left + 30, r.bottom + 16, 420, 176), const Radius.circular(12));
          c
            ..drawRRect(box.shift(const Offset(0, 8)), Paint()..color = const Color(0x33000000))
            ..drawRRect(box, Paint()..color = const Color(0xFFFFFFFF))
            ..drawRRect(
              box,
              Paint()
                ..color = const Color(0xFFDADCE0)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2,
            );
          for (final (i, item) in ['Copy', 'Translate to Japanese', 'Read aloud'].indexed) {
            _text(c, item, _ui.copyWith(fontSize: 30, color: const Color(0xFF202124), fontWeight: i == 1 ? FontWeight.w700 : FontWeight.w500), Offset(r.left + 56, r.bottom + 32 + i * 52));
          }
        };
      }
    }
    _paintLines(c, lines, body, 70, y1 + 76, 50, words: words);
    if (find) {
      for (final (w, r) in words) {
        if (!w.startsWith('text')) continue;
        final cut = Rect.fromLTWH(r.left - 2, r.top + 2, _width('text', body) + 4, r.height - 2);
        c.drawRect(cut, Paint()..color = const Color(0x99FFD54F));
      }
      final bar = RRect.fromRectAndRadius(Rect.fromLTWH(s.width - 560, 146, 520, 84), const Radius.circular(14));
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
      _text(c, 'text', _ui.copyWith(fontSize: 44, color: const Color(0xFF202124), fontWeight: FontWeight.w600), Offset(s.width - 530, 160));
      final hits = words.where((w) => w.$1.startsWith('text')).length;
      _text(c, '$hits of $hits', TextStyle(fontFamily: BP.mono, fontSize: 40, color: const Color(0xFF1E8E3E), fontWeight: FontWeight.w800), Offset(s.width - 260, 166));
    }
    menu?.call();
    // Vertical Japanese with ruby (writing-mode and ruby, CSS).
    _tag(c, 'writing-mode: vertical-rl · ruby', Offset(s.width - 470, find ? 248 : 156), size: 22);
    _verticalText(c, s.width - 96, find ? 306 : 214, 70, 8, const Color(0xFF202124), const Color(0xFF1A73E8));
  });

  /// The design tool: its bars and panels, the canvas; a text layer in a
  /// frame, selected, at [zoom] (1, 4, 16 times).
  Future<Texture2D> _figmaPage(int zoom) => paintedTexture(_wpx, _wpy, (c, s) {
    const panel = Color(0xFF2C2C2C), line = Color(0xFF444444), dim = Color(0xFFB3B3B3), blue = Color(0xFF0D99FF);
    c
      ..clipRRect(RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(22)))
      ..drawRect(Offset.zero & s, Paint()..color = const Color(0xFFE5E5E5))
      ..drawRect(Rect.fromLTWH(0, 0, s.width, 64), Paint()..color = panel)
      ..drawRect(Rect.fromLTWH(0, 64, 300, s.height), Paint()..color = panel)
      ..drawRect(Rect.fromLTWH(s.width - 300, 64, 300, s.height), Paint()..color = panel)
      ..drawLine(const Offset(0, 64), Offset(s.width, 64), Paint()..color = line);
    for (final (i, col) in [const Color(0xFFF24E1E), const Color(0xFFA259FF), const Color(0xFF1ABCFE)].indexed) {
      c.drawCircle(Offset(34 + i * 30, 32), 11, Paint()..color = col);
    }
    _text(c, 'Text rendering', _ui.copyWith(fontSize: 26, color: const Color(0xFFFFFFFF), fontWeight: FontWeight.w600), Offset(s.width / 2 - 90, 16));
    _text(c, '${zoom * 100}%', const TextStyle(fontFamily: BP.mono, fontSize: 28, color: Color(0xFFFFFFFF), fontWeight: FontWeight.w700), Offset(s.width - 130, 16));
    // Layers.
    _text(c, 'Layers', _ui.copyWith(fontSize: 24, color: const Color(0xFFFFFFFF), fontWeight: FontWeight.w700), const Offset(24, 86));
    _text(c, '#  Frame 1', _ui.copyWith(fontSize: 24, color: dim), const Offset(24, 136));
    c.drawRect(const Rect.fromLTWH(8, 176, 284, 44), Paint()..color = const Color(0xFF0C4E7A));
    _text(c, 'T   Hello مرحبا', _ui.copyWith(fontSize: 24, color: const Color(0xFFFFFFFF), fontFamilyFallback: const [BP.arabic]), const Offset(48, 184));
    // The text's properties.
    final px = s.width - 276.0;
    _text(c, 'Text', _ui.copyWith(fontSize: 24, color: const Color(0xFFFFFFFF), fontWeight: FontWeight.w700), Offset(px, 86));
    for (final (i, row) in ['Inter · Regular', '64 · auto width', 'mixed LTR · RTL ✓', 'vertical ✕'].indexed) {
      _text(c, row, _ui.copyWith(fontSize: 22, color: i == 3 ? const Color(0xFFFF7262) : dim, fontFamilyFallback: const [BP.arabic]), Offset(px, 136 + i * 46.0));
    }
    _tag(c, 'its own text engine', Offset(px, 340), ink: const Color(0xFF0D99FF), fill: const Color(0xFF1E3A50));
    // The canvas: the frame, the text layer at this zoom (the canvas
    // re-renders it from the outlines: sharp at any size).
    final canvas = Rect.fromLTWH(300, 64, s.width - 600, s.height - 64);
    c
      ..save()
      ..clipRect(canvas);
    final size = 64.0 * zoom;
    final style = TextStyle(fontFamily: BP.display, fontFamilyFallback: const [BP.arabic], fontSize: size, color: const Color(0xFF1E1E1E), fontWeight: FontWeight.w600);
    final tp = TextPainter(text: TextSpan(text: 'Hello مرحبا', style: style), textDirection: TextDirection.ltr)..layout();
    // Zoomed in about the first letters.
    final focus = zoom == 1 ? Offset(tp.width / 2, tp.height / 2) : Offset(size * (zoom == 4 ? 1.1 : 0.42), tp.height * 0.52);
    final at = canvas.center - focus;
    final frameRect = Rect.fromLTWH(at.dx - 60.0 * zoom, at.dy - 70.0 * zoom, tp.width + 120.0 * zoom, tp.height + 140.0 * zoom);
    c.drawRect(frameRect, Paint()..color = const Color(0xFFFFFFFF));
    if (zoom == 1) _text(c, 'Frame 1', _ui.copyWith(fontSize: 22, color: const Color(0xFF7A7A7A)), frameRect.topLeft - const Offset(0, 32));
    tp.paint(c, at);
    final box = Rect.fromLTWH(at.dx, at.dy, tp.width, tp.height);
    c.drawRect(
      box,
      Paint()
        ..color = blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    for (final p in [box.topLeft, box.topRight, box.bottomLeft, box.bottomRight]) {
      final h = Rect.fromCenter(center: p, width: 16, height: 16);
      c
        ..drawRect(h, Paint()..color = const Color(0xFFFFFFFF))
        ..drawRect(
          h,
          Paint()
            ..color = blue
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
    }
    tp.dispose();
    c.restore();
    if (zoom > 1) _tag(c, '${zoom * 100}% · still sharp', Offset(canvas.left + 24, canvas.bottom - 64), ink: const Color(0xFF1E1E1E), fill: const Color(0xFFFFFFFF), size: 26);
  });

  /// The Mac document: its title bar; the paragraph justified and
  /// hyphenated; vertical Japanese with ruby.
  Future<Texture2D> _macWindow() => paintedTexture(_wpx, _wpy, (c, s) {
    c
      ..clipRRect(RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(22)))
      ..drawRect(Offset.zero & s, Paint()..color = const Color(0xFFFFFFFF))
      ..drawRect(Rect.fromLTWH(0, 0, s.width, 70), Paint()..color = const Color(0xFFECECEC))
      ..drawLine(const Offset(0, 70), Offset(s.width, 70), Paint()..color = const Color(0xFFD0D0D0));
    for (final (i, col) in [const Color(0xFFFF5F57), const Color(0xFFFEBC2E), const Color(0xFF28C840)].indexed) {
      c.drawCircle(Offset(34 + i * 34, 35), 12, Paint()..color = col);
    }
    _text(c, 'Typesetting — Core Text', _ui.copyWith(fontSize: 26, color: const Color(0xFF3C3C3C), fontWeight: FontWeight.w600), Offset(s.width / 2 - 150, 19));
    final body = _ui.copyWith(fontSize: 46, color: const Color(0xFF1D1D1F), height: 1.25);
    _tag(c, 'hyphenation · justification', const Offset(70, 100), ink: const Color(0xFF6E6E73), fill: const Color(0xFFF2F2F7), size: 24);
    final lines = _lines(_macText, body, 820, best: true, hyphenCost: 0.002);
    _paintLines(c, lines, body, 70, 166, 62, width: 820, justify: true);
    // The margins, faint: both edges straight.
    for (final x in [64.0, 896.0]) {
      c.drawLine(Offset(x, 156), Offset(x, 170 + 62.0 * lines.length), Paint()
        ..color = const Color(0x44007AFF)
        ..strokeWidth = 3);
    }
    _tag(c, 'vertical · ruby', Offset(s.width - 420, 100), ink: const Color(0xFF6E6E73), fill: const Color(0xFFF2F2F7), size: 24);
    _verticalText(c, s.width - 120, 170, 84, 8, const Color(0xFF1D1D1F), const Color(0xFFD70015));
  });

  /// The phone: the paragraph three times, as each break strategy lays it
  /// out (the margin a dashed line); [lit] the one being looked at (−1:
  /// none).
  Future<Texture2D> _androidScreen(int lit) => paintedTexture(_ppx, _ppy, (c, s) {
    TalkPhones.chrome(c, s, 'Minikin', 'breakStrategy');
    final body = const TextStyle(fontFamily: 'Roboto', fontSize: 30, color: Color(0xFF16181D), height: 1.3);
    const left = 40.0, width = 452.0;
    final kinds = [
      ('SIMPLE  · = Flutter', _lines(_androidText, body, width, hyphens: false), const Color(0xFFB06000)),
      ('BALANCED', _balanced(_androidText, body, width), const Color(0xFF1565C0)),
      ('HIGH_QUALITY', _lines(_androidText, body, width, best: true), const Color(0xFF2E7D32)),
    ];
    var y = 222.0;
    for (final (k, (label, lines, col)) in kinds.indexed) {
      final h = 46 + lines.length * 39.0 + 16;
      if (k == lit) {
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(16, y - 10, s.width - 32, h + 6), const Radius.circular(18));
        c
          ..drawRRect(r, Paint()..color = col.withValues(alpha: 0.16))
          ..drawRRect(
            r,
            Paint()
              ..color = col.withValues(alpha: 0.7)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4,
          );
      }
      _text(c, label, TextStyle(fontFamily: BP.mono, fontSize: 24, color: col, fontWeight: FontWeight.w800), Offset(left, y));
      _paintLines(c, lines, body, left, y + 42, 39);
      // The margin.
      for (var yy = y + 40; yy < y + 42 + lines.length * 39; yy += 16) {
        c.drawLine(Offset(left + width + 6, yy), Offset(left + width + 6, yy + 8), Paint()
          ..color = col.withValues(alpha: 0.6)
          ..strokeWidth = 3);
      }
      y += h + 14;
    }
    TalkPhones.home(c, s);
  });

  /// The web page as Flutter's Text() sets it: an app bar; the headline
  /// first fit (no balance), the paragraph first fit (no hyphens), the
  /// Japanese across (no vertical) with its readings in brackets (no ruby);
  /// what's missing tagged in red.
  Future<Texture2D> _flutterText() => paintedTexture(_wpx, _wpy, (c, s) {
    const red = Color(0xFFD93025), redFill = Color(0xFFFCE8E6);
    c
      ..clipRRect(RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(22)))
      ..drawRect(Offset.zero & s, Paint()..color = const Color(0xFFFFFFFF))
      ..drawRect(Rect.fromLTWH(0, 0, s.width, 132), Paint()..color = const Color(0xFF0175C2));
    _text(c, 'Flutter · Text()', _ui.copyWith(fontSize: 40, color: const Color(0xFFFFFFFF), fontWeight: FontWeight.w700), const Offset(70, 40));
    _text(c, 'the same page, set by the app', _ui.copyWith(fontSize: 26, color: const Color(0xCCFFFFFF)), Offset(s.width - 470, 52));
    final h1 = _ui.copyWith(fontSize: 68, color: const Color(0xFF202124), fontWeight: FontWeight.w700, height: 1.15);
    _tag(c, 'text-wrap: balance  ✕', const Offset(70, 156), ink: red, fill: redFill, size: 24);
    final y1 = _paintLines(c, _lines(_headline, h1, 960, hyphens: false), h1, 70, 204, 80);
    final body = _ui.copyWith(fontSize: 40, color: const Color(0xFF3C4043), height: 1.25);
    _tag(c, 'hyphens  ✕', Offset(70, y1 + 22), ink: red, fill: redFill, size: 24);
    final lines = _lines(_webText, body, 600, hyphens: false);
    _paintLines(c, lines, body, 70, y1 + 76, 50);
    // The ragged edge, for comparison: where the column ends.
    for (var y = y1 + 70; y < y1 + 76 + 50.0 * lines.length; y += 20) {
      c.drawLine(Offset(674, y), Offset(674, y + 10), Paint()
        ..color = red.withValues(alpha: 0.5)
        ..strokeWidth = 3);
    }
    _tag(c, 'vertical  ✕   ruby  ✕', Offset(s.width - 470, 156), ink: red, fill: redFill, size: 24);
    final ja = [for (final (b, r) in _vertical) r == null ? b : '$b（$r）'].join();
    final tp = TextPainter(
      text: TextSpan(text: ja, style: _ja.copyWith(fontSize: 46, color: const Color(0xFF202124), height: 1.5)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 420);
    tp
      ..paint(c, Offset(s.width - 470, 222))
      ..dispose();
  });

  // ── Posing ────────────────────────────────────────────────────────────────

  final _m = vm.Matrix4.identity();

  @override
  void pose(double u, double t, double night) {
    if (!_ready) return;
    final on = visited && u < visit;
    if (!on) {
      for (final w in [_chrome, _figma, _mac, _flutter]) {
        w.hide();
      }
      _android.hide();
      return;
    }
    // In together as the camera comes; each at its place, bobbing a little.
    final s = eio(seg(u, 0.0, 0.9));
    _chrome.page = _chromePages[u < _findAt ? 0 : (u < _selectAt ? 1 : 2)];
    _figma.page = _figmaPages[u < _zoom1 ? 0 : (u < _zoom2 ? 1 : 2)];
    final lit = u < _lit[0] ? -1 : (u < _lit[1] ? 0 : (u < _lit[2] ? 1 : 2));
    _android.screen = _androidScreens[lit + 1];
    for (final (i, x) in _xs.indexed) {
      final bob = 0.05 * math.sin(t * 1.2 + i * 1.3);
      // (Flutter's comes in only when the talk gets to it.)
      final k = i == 4 ? eio(seg(u, _acts[4] - 0.4, _acts[4] + 0.6)) : s;
      vm.Matrix4? m;
      if (k > 0.001) {
        _m.setFromTranslationRotationScale(vm.Vector3(x, _y + bob, 0), vm.Quaternion.identity(), vm.Vector3.all(k));
        m = frame * _m;
      }
      switch (i) {
        case 0:
          m == null ? _chrome.hide() : _chrome.place(m);
        case 1:
          m == null ? _figma.hide() : _figma.place(m);
        case 2:
          m == null ? _mac.hide() : _mac.place(m);
        case 3:
          m == null ? _android.hide() : _android.place(m);
        default:
          m == null ? _flutter.hide() : _flutter.place(m);
      }
    }
  }

  // ── The camera ────────────────────────────────────────────────────────────

  @override
  Shot shot(double u) {
    final i = _acts.lastIndexWhere((a) => u >= a - 0.01).clamp(0, 4);
    final x = _xs[i], phone = i == 3;
    // Head on, close enough to read (the phone, a little closer).
    return Shot(vm.Vector3(x - 0.3, _y + 0.15, phone ? -6.0 : -7.8), vm.Vector3(x, _y, 0), fov: 40, settle: 1.0, drift: 0.3);
  }
}
