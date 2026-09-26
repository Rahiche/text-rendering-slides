import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../deck/font_data.dart';
import '../deck/scripts.dart';
import '../deck/theme.dart';
import '../deck/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// "The title is a construction site."
//
// Each letter of "Text rendering" is built from its REAL Space Grotesk outline
// (FontData, wght 300 default instance), positioned with the REAL shaped
// advances (TextProbe → SkParagraph, kerning included):
//   crate "U+0054" (code point) → opened: glyph id + advance box (font lookup,
//   layout) → tower crane scales it 1000 upm → 170 px and sets it on the
//   surveyed baseline → welders trace the outline → painters fill a coarse
//   coverage grid (real 4×4 supersampled coverage = anti-aliasing) that then
//   resolves to the smooth fill.
// After the first build (~25 s) the site keeps living forever: maintenance
// crews, kerning adjustments with crowbars, traffic, and a small lot that
// builds and demolishes other scripts with real shaped text.
//
// One ticker → one ValueNotifier → one CustomPainter. Everything time-based is
// a pure function of the clock (seeded per cycle), so nothing accumulates.
// ─────────────────────────────────────────────────────────────────────────────

const _title = 'Text rendering';
const _subtitle = 'from code points to pixels · and how Flutter does it';
const _size = 170.0;
const _k = _size / 1000; // px per font unit (unitsPerEm = 1000)
const _left = 110.0;
const _base = 470.0;
const _ground = 700.0;
const _laneFar = 718.0;
const _laneNear = 740.0;
const _jibY = 152.0;
const _jibTop = 132.0;
const _jibL = 118.0;
const _mastL = 1418.0;
const _mastR = 1446.0;
const _hookRest = 236.0;
const _cell = 8.0;
const _door = 58.0;
const _lotCx = 1105.0;
const _lotBase = 684.0;
const _lotSize = 60.0;
const _lotPeriod = 18.0;
const _eventPeriod = 6.5;
const _rodL = 70.0;
const _rodR = 1352.0;
const _ws = 1.2; // worker scale (≈31 px tall)

/// Title slide prototype: the title is a construction site.
class TitleSiteSlide extends StatefulWidget {
  const TitleSiteSlide({super.key});

  @override
  State<TitleSiteSlide> createState() => _TitleSiteSlideState();
}

class _TitleSiteSlideState extends State<TitleSiteSlide>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0);
  final _labels = _Labels();
  _Site? _site;
  Duration? _start;
  bool _pointer = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
    FontData.spaceGrotesk().then((f) {
      if (!mounted) return;
      setState(() => _site = _Site(f));
    });
  }

  void _tick(Duration d) {
    if (_site == null) return;
    _start ??= d;
    _clock.value = (d - _start!).inMicroseconds / 1e6;
  }

  /// Web: a Noto fallback font arrived — re-measure the lot's words.
  void _fontsChanged() {
    _site?.rebuildLot();
    _labels.clear();
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    _ticker.dispose();
    _clock.dispose();
    _labels.clear();
    _site?.dispose();
    super.dispose();
  }

  void _hover(Offset p) {
    final s = _site;
    if (s == null) return;
    final i = s.letterAt(p, _clock.value);
    s.hover = i;
    final pointer = i != null || s.lotHit(p, _clock.value);
    if (pointer != _pointer) setState(() => _pointer = pointer);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _pointer ? SystemMouseCursors.click : MouseCursor.defer,
      onHover: (e) => _hover(e.localPosition),
      onExit: (_) {
        _site?.hover = null;
        if (_pointer) setState(() => _pointer = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (d) => _site?.tap(d.localPosition, _clock.value),
        child: SizedBox.expand(
          child: CustomPaint(
            painter: _SitePainter(site: _site, clock: _clock, labels: _labels),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Model: glyphs, schedule, lot words. Built once.
// ─────────────────────────────────────────────────────────────────────────────

class _Cell {
  const _Cell(this.rect, this.cov, this.row);

  final Rect rect;
  final double cov; // 0..1 coverage from 4×4 supersampling
  final int row;
}

class _Glyph {
  _Glyph({
    required this.k,
    required this.cp,
    required this.gid,
    required this.adv,
    required this.origin,
    required this.box,
    required this.ink,
    required this.path,
  }) {
    metrics = path.computeMetrics().toList();
    length = metrics.fold(0.0, (a, m) => a + m.length);
    longest = metrics.reduce((a, b) => a.length >= b.length ? a : b);
  }

  final int k; // build order
  final int cp;
  final int gid;
  final int adv;
  final Offset origin; // pen position on the baseline
  final Rect box; // advance × line box from the real paragraph layout
  final Rect ink; // outline bounds on screen
  final Path path;
  late final List<ui.PathMetric> metrics;
  late final double length;
  late final ui.PathMetric longest;

  late final String cpLabel = 'U+${cp.toRadixString(16).toUpperCase().padLeft(4, '0')}';
  late final String gidLabel = 'gid $gid';
  late final String info = '$cpLabel → gid $gid · adv $adv';

  List<_Cell>? _cells;

  /// Coverage grid, computed lazily (the first time a painter needs it).
  List<_Cell> get cells => _cells ??= _raster();

  double get cx => ink.center.dx;

  // Schedule (seconds).
  double s = 0, a = 0, h0 = 0, w0 = 0, w1 = 0, p0 = 0, p1 = 0, r1 = 0;

  List<_Cell> _raster() {
    final out = <_Cell>[];
    final c0 = (ink.left / _cell).floor();
    final c1 = (ink.right / _cell).ceil();
    final r0 = (ink.top / _cell).floor();
    final r1 = (ink.bottom / _cell).ceil();
    var flip = false;
    for (var r = r1 - 1; r >= r0; r--) {
      final row = <_Cell>[];
      for (var c = c0; c < c1; c++) {
        var hits = 0;
        for (var sy = 0; sy < 4; sy++) {
          for (var sx = 0; sx < 4; sx++) {
            if (path.contains(Offset((c + (sx + .5) / 4) * _cell, (r + (sy + .5) / 4) * _cell))) {
              hits++;
            }
          }
        }
        if (hits > 0) {
          row.add(_Cell(Rect.fromLTWH(c * _cell, r * _cell, _cell, _cell), hits / 16, r));
        }
      }
      out.addAll(flip ? row.reversed : row);
      flip = !flip;
    }
    return out;
  }

  /// Point along the whole outline at fraction [f], plus the contour index.
  (Offset, int) tipAt(double f) {
    var left = length * f.clamp(0.0, 0.9999);
    for (var i = 0; i < metrics.length; i++) {
      final m = metrics[i];
      if (left <= m.length) {
        return (m.getTangentForOffset(left)?.position ?? ink.center, i);
      }
      left -= m.length;
    }
    return (ink.center, 0);
  }

  /// The first [f] of the outline, with the last [hot] px returned separately.
  (Path, Path) weldPaths(double f, {double hot = 46}) {
    final done = Path();
    final tail = Path();
    var left = length * f.clamp(0.0, 1.0);
    for (final m in metrics) {
      if (left <= 0) break;
      final l = math.min(left, m.length);
      done.addPath(m.extractPath(0, l), Offset.zero);
      if (left <= m.length) {
        tail.addPath(m.extractPath(math.max(0, l - hot), l), Offset.zero);
      }
      left -= m.length;
    }
    return (done, tail);
  }
}

/// One crane load in the side lot: a piece of real laid-out text.
class _Piece {
  const _Piece(this.painter, this.origin, this.clip);

  final TextPainter painter;
  final Offset origin; // where the painter paints when the piece is in place
  final Rect clip; // the piece's box (grapheme cluster, em cell or ruby)
}

const _ja = Locale('ja');

/// A word for the side lot. Horizontal words are ONE shaped paragraph cut
/// into its real grapheme-cluster boxes (so Arabic stays joined); Japanese
/// can carry ruby (furigana) and can be set vertically by hand, character by
/// character — Flutter has no vertical writing mode.
class _LotWord {
  _LotWord.horizontal(String text, this.script, this.tag, this.font,
      {List<String?> ruby = const [], Locale? locale, double size = _lotSize}) {
    final p = _painter(text, size, script.color, locale);
    final line = p.computeLineMetrics().first;
    final origin = Offset(_lotCx - p.width / 2, _lotBase - line.baseline);
    wholes.add((p, origin));
    final rubies = <_Piece>[];
    var i = 0;
    var gi = 0;
    for (final g in text.characters) {
      final boxes = p.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + g.length));
      i += g.length;
      if (boxes.isNotEmpty) {
        final r = boxes.map((b) => b.toRect()).reduce((a, b) => a.expandToInclude(b));
        final clip = Rect.fromLTRB(
            origin.dx + r.left, _lotBase - line.ascent, origin.dx + r.right, _lotBase + line.descent);
        if (clip.width >= 1) {
          pieces.add(_Piece(p, origin, clip));
          final rt = gi < ruby.length ? ruby[gi] : null;
          if (rt != null) {
            // Furigana: small kana centred over its base character.
            final rp = _painter(rt, _rubySize, Script.kana.color, locale);
            final rl = rp.computeLineMetrics().first;
            final rb = _lotBase - size * 0.98;
            final ro = Offset(clip.center.dx - rp.width / 2, rb - rl.baseline);
            rubies.add(_Piece(rp, ro, Rect.fromLTRB(ro.dx - 1, rb - rl.ascent, ro.dx + rp.width + 1, rb + rl.descent)));
            wholes.add((rp, ro));
          }
        }
      }
      gi++;
    }
    if (pieces.isEmpty) pieces.add(_Piece(p, origin, origin & p.size));
    pieces.addAll(rubies);
    bounds = pieces.map((e) => e.clip).reduce((a, b) => a.expandToInclude(b));
  }

  /// 縦書き: one column, top to bottom, ruby to the right.
  _LotWord.vertical(List<(String, Script)> chars, List<String?> ruby, this.script, this.tag, this.font) {
    const size = 54.0;
    const step = size * 1.06;
    final top = _ground - 8 - chars.length * step;
    const colX = _lotCx - 14;
    final rubies = <_Piece>[];
    for (var i = 0; i < chars.length; i++) {
      final (ch, sc) = chars[i];
      final p = _painter(ch, size, sc.color, _ja);
      final cell = Rect.fromLTWH(colX - step / 2, top + i * step, step, step);
      final o = Offset(cell.center.dx - p.width / 2, cell.center.dy - p.height / 2);
      pieces.add(_Piece(p, o, cell));
      wholes.add((p, o));
      final rt = i < ruby.length ? ruby[i] : null;
      if (rt != null) {
        final rp = _painter(rt.split('').join('\n'), _rubySize * 0.85, Script.kana.color, _ja, height: 1.0);
        final ro = Offset(cell.right + 3, cell.center.dy - rp.height / 2);
        rubies.add(_Piece(rp, ro, (ro & rp.size).inflate(1)));
        wholes.add((rp, ro));
      }
    }
    pieces.addAll(rubies);
    bounds = pieces.map((e) => e.clip).reduce((a, b) => a.expandToInclude(b));
  }

  static const _rubySize = 26.0;

  final Script script;
  final String tag;
  final String font;
  final List<_Piece> pieces = [];
  final List<(TextPainter, Offset)> wholes = [];
  final List<TextPainter> _owned = [];
  late final Rect bounds;

  bool get vertical => tag.contains('vertical');

  TextPainter _painter(String text, double size, Color color, Locale? locale, {double? height}) {
    final p = TextPainter(
      text: TextSpan(text: text, style: BT.sample(size, color: color, height: height).copyWith(locale: locale)),
      textDirection: TextDirection.ltr,
    )..layout();
    _owned.add(p);
    return p;
  }

  void dispose() {
    for (final p in _owned) {
      p.dispose();
    }
  }
}

class _Site {
  _Site(this.font) {
    final probe = TextProbe(TextSpan(text: _title, style: BT.display(_size, weight: 300)));
    final line = probe.lines.first;
    width = probe.size.width;
    var i = 0;
    var k = 0;
    var pen = 0.0;
    for (final r in _title.runes) {
      final gid = font.glyphId(r);
      final adv = font.advance(gid);
      final rect = probe.rectFor(i, i + 1);
      final x0 = _left + (rect?.left ?? pen);
      final x1 = _left + (rect?.right ?? pen + adv * _k);
      pen += adv * _k;
      i++;
      final o = font.outline(gid);
      if (o.contours.isEmpty) continue;
      final b = o.bounds;
      glyphs.add(_Glyph(
        k: k++,
        cp: r,
        gid: gid,
        adv: adv,
        origin: Offset(x0, _base),
        box: Rect.fromLTRB(x0, _base - line.ascent, x1, _base + line.descent),
        ink: Rect.fromLTRB(x0 + b.left * _k, _base - b.bottom * _k, x0 + b.right * _k, _base - b.top * _k),
        path: o.toPath(scale: _k, origin: Offset(x0, _base)),
      ));
    }
    probe.dispose();
    capY = _base - 700 * _k;
    xY = _base - 486 * _k;

    // The whole title as a dashed plan, drawn before anything is built.
    final all = Path();
    for (final g in glyphs) {
      all.addPath(g.path, Offset.zero);
    }
    plan = dashPath(all, dash: 5, gap: 5);

    // Build schedule: forklifts leave the warehouse every 1.35 s; the crane
    // takes one letter at a time.
    var craneFree = 0.0;
    for (final g in glyphs) {
      g.s = 0.9 + g.k * 1.35;
      g.a = g.s + math.max(0.5, (g.cx - 34 - _door) / 650);
      g.h0 = math.max(g.a + 0.55, craneFree);
      craneFree = g.h0 + 1.45;
      g.w0 = g.h0 + 1.25;
      g.w1 = g.w0 + (0.9 + g.length / 700).clamp(1.3, 2.3);
      g.p0 = g.w1 + 0.1;
      g.p1 = g.p0 + 1.4;
      g.r1 = g.p1 + 0.45;
    }
    craneEnd = craneFree;
    done = glyphs.map((g) => g.r1).reduce(math.max) + 0.2;
    lot0 = done + 1.5;
    events0 = done + 3.5;
    rebuildLot();
  }

  final FontData font;
  final List<_Glyph> glyphs = [];
  late final double width;
  late final double capY;
  late final double xY;
  late final Path plan;
  late final double craneEnd;
  late final double done;
  late final double lot0;
  late final double events0;

  /// The side lot's rotation: Japanese first, and every other word.
  static List<_LotWord> _makeLot() => [
    _LotWord.horizontal('文字', Script.han, 'ja · ruby', 'fallback: CJK · ja', ruby: ['も', 'じ'], locale: _ja, size: 76),
    _LotWord.horizontal('نص', Script.arabic, 'arabic · rtl', Script.arabic.font),
    _LotWord.vertical(
      [('縦', Script.han), ('書', Script.han), ('き', Script.kana)],
      ['たて', 'が'],
      Script.han,
      'ja · vertical',
      'fallback: CJK · ja',
    ),
    _LotWord.horizontal('टेक्स्ट', Script.devanagari, 'devanagari', Script.devanagari.font),
    _LotWord.horizontal('テキスト', Script.kana, 'ja · katakana', 'fallback: CJK · ja', locale: _ja, size: 64),
    _LotWord.horizontal('ข้อความ', Script.thai, 'thai', Script.thai.font),
  ];

  List<_LotWord> lot = [];
  TextPainter? jaSub;

  // Interaction.
  int? hover;
  int? manual;
  double manualAt = -100;
  double lotShift = 0;

  void rebuildLot() {
    for (final w in lot) {
      w.dispose();
    }
    lot = _makeLot();
    jaSub?.dispose();
    jaSub = TextPainter(
      text: TextSpan(text: 'テキストレンダリング', style: BT.sample(20, color: BP.inkDim).copyWith(locale: _ja)),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  void dispose() {
    for (final w in lot) {
      w.dispose();
    }
    jaSub?.dispose();
  }

  /// Lot cycle index and local time.
  (int, double) lotTime(double t) {
    final lt = t - lot0 + lotShift;
    if (lt < 0) return (-1, lt);
    final c = (lt / _lotPeriod).floor();
    return (c, lt - c * _lotPeriod);
  }

  _LotWord lotWord(int cycle) => lot[cycle % lot.length];

  int? letterAt(Offset p, double t) {
    for (var i = 0; i < glyphs.length; i++) {
      final g = glyphs[i];
      if (t > g.r1 && g.box.contains(p)) return i;
    }
    return null;
  }

  bool lotHit(Offset p, double t) {
    final (c, _) = lotTime(t);
    if (c < 0) return false;
    return lotWord(c).bounds.inflate(24).contains(p);
  }

  void tap(Offset p, double t) {
    final i = letterAt(p, t);
    if (i != null) {
      if (t - manualAt > 5.6 || manual != i) {
        manual = i;
        manualAt = t;
      }
      return;
    }
    if (lotHit(p, t)) {
      final (_, u) = lotTime(t);
      lotShift += _lotPeriod - u;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cached label painters (a small, bounded set of strings).
// ─────────────────────────────────────────────────────────────────────────────

class _Labels {
  final _cache = <String, TextPainter>{};

  TextPainter get(String text, double size, Color color, {bool display = false}) {
    final key = '$size|${color.toARGB32()}|$display|$text';
    var p = _cache[key];
    if (p == null) {
      if (_cache.length > 400) clear();
      p = TextPainter(
        text: TextSpan(
          text: text,
          style: display ? BT.display(size, color: color, weight: 400) : BT.mono(size, color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      _cache[key] = p;
    }
    return p;
  }

  /// Draws [text] anchored at [at] ([ax], [ay] = 0 left/top … 1 right/bottom).
  Size draw(
    Canvas c,
    String text,
    Offset at, {
    double size = 11,
    Color color = BP.inkDim,
    double alpha = 1,
    double ax = 0,
    double ay = 0,
    bool display = false,
  }) {
    final q = (alpha.clamp(0.0, 1.0) * 8).round();
    if (q == 0) return Size.zero;
    final p = get(text, size, color.withValues(alpha: color.a * q / 8), display: display);
    p.paint(c, at - Offset(p.width * ax, p.height * ay));
    return p.size;
  }

  void clear() {
    for (final p in _cache.values) {
      p.dispose();
    }
    _cache.clear();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small math helpers (all stateless; hashes are float-based so they behave
// identically on native and on the web).
// ─────────────────────────────────────────────────────────────────────────────

double _c01(double v) => v.clamp(0.0, 1.0);
double _seg(double t, double a, double b) => _c01((t - a) / (b - a));
double _eio(double v) => Curves.easeInOutCubic.transform(_c01(v));
double _eo(double v) => Curves.easeOutCubic.transform(_c01(v));
double _ei(double v) => Curves.easeInCubic.transform(_c01(v));
double _back(double v) => Curves.easeOutBack.transform(_c01(v));
double _lerp(double a, double b, double t) => a + (b - a) * t;
double _h(double x) {
  final s = math.sin(x * 12.9898 + 78.233) * 43758.5453;
  return s - s.floorToDouble();
}

double _h2(double a, double b) => _h(a * 1.618 + b * 57.31);

/// 1 inside [a+fade, b-fade], ramps at both ends, 0 outside [a, b].
double _window(double t, double a, double b, [double fade = 0.3]) =>
    _seg(t, a, a + fade) * (1 - _seg(t, b - fade, b));

Paint _stroke(Color c, [double w = 1]) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

Paint _fill(Color c) => Paint()..color = c;

Path _line(Offset a, Offset b) => Path()
  ..moveTo(a.dx, a.dy)
  ..lineTo(b.dx, b.dy);

/// Two-bone limb from [a] to [b] with total length [len], bending to [bend].
void _limb(Path p, Offset a, Offset b, double len, double bend) {
  var d = (b - a).distance;
  if (d < 0.01) return;
  final dir = (b - a) / d;
  if (d > len) {
    b = a + dir * len;
    d = len;
  }
  final h = math.sqrt(math.max(0, len * len / 4 - d * d / 4));
  final knee = (a + b) / 2 + Offset(-dir.dy, dir.dx) * (h * bend);
  p
    ..moveTo(a.dx, a.dy)
    ..lineTo(knee.dx, knee.dy)
    ..lineTo(b.dx, b.dy);
}

/// Batches every stick figure into two paths (bodies, hard hats).
class _Crew {
  final body = Path();
  final hats = Path();

  void flush(Canvas c) {
    c.drawPath(body, _stroke(BP.ink, 1.6));
    c.drawPath(hats, _fill(BP.amber));
    body.reset();
    hats.reset();
  }

  /// A worker. Returns (front hand, back hand, head).
  (Offset, Offset, Offset) figure(
    Offset hip, {
    required Offset footA,
    required Offset footB,
    double face = 1,
    double lean = 0,
    double armF = 0.25,
    double armB = -0.2,
    Offset? handF,
    Offset? handB,
    double s = _ws,
    bool hat = true,
  }) {
    _limb(body, hip, footA, 11 * s, -face);
    _limb(body, hip, footB, 11 * s, -face);
    final up = Offset(math.sin(lean) * face, -math.cos(lean));
    final sh = hip + up * (9 * s);
    body
      ..moveTo(hip.dx, hip.dy)
      ..lineTo(sh.dx, sh.dy);
    final head = sh + up * (4.6 * s);
    body.addOval(Rect.fromCircle(center: head, radius: 3.1 * s));
    Offset arm(double a) => sh + Offset(math.sin(a + lean) * face, math.cos(a + lean)) * (8.5 * s);
    final hf = handF ?? arm(armF);
    final hb = handB ?? arm(armB);
    _limb(body, sh, hf, 8.5 * s, face);
    _limb(body, sh, hb, 8.5 * s, face);
    if (hat) {
      final hc = head + up * (0.9 * s);
      hats
        ..addArc(Rect.fromCircle(center: hc, radius: 3.8 * s), math.pi + lean * face, math.pi)
        ..close();
      final bx = Offset(-up.dy, up.dx);
      final b0 = hc - bx * (4.2 * s) + up * 0.2;
      final b1 = hc + bx * (5.4 * s * face);
      hats
        ..moveTo(b0.dx, b0.dy)
        ..lineTo(b1.dx, b1.dy)
        ..lineTo(b1.dx - up.dx * 1.4 * s, b1.dy - up.dy * 1.4 * s + 1.2 * s)
        ..lineTo(b0.dx, b0.dy + 1.2 * s)
        ..close();
    }
    return (hf, hb, head);
  }

  /// Just a head and hard hat (drivers, the crane operator).
  void head(Offset head, double face) {
    const k = _ws;
    body.addOval(Rect.fromCircle(center: head, radius: 3.1 * k));
    final hc = head + const Offset(0, -0.9 * k);
    hats
      ..addArc(Rect.fromCircle(center: hc, radius: 3.8 * k), math.pi, math.pi)
      ..close()
      ..addRect(Rect.fromLTRB(
          hc.dx - (face > 0 ? 4.2 : 5.4) * k, hc.dy - 0.2, hc.dx + (face > 0 ? 5.4 : 4.2) * k, hc.dy + 1.3 * k));
  }

  /// Standing / walking worker with feet at [feet]. [walk] is the gait phase.
  (Offset, Offset, Offset) walker(
    Offset feet, {
    double face = 1,
    double walk = 0,
    double stride = 1,
    double lean = 0,
    double? armF,
    double? armB,
    Offset? handF,
    Offset? handB,
    double s = _ws,
  }) {
    final sw = math.sin(walk) * stride;
    final fa = feet + Offset(sw * 4 * s * face, -math.max(0, math.cos(walk)) * 2 * s * stride);
    final fb = feet + Offset(-sw * 4 * s * face, -math.max(0, -math.cos(walk)) * 2 * s * stride);
    final hip = feet + Offset(0, (-10.4 + 0.5 * math.cos(2 * walk) * stride) * s);
    return figure(
      hip,
      footA: fa,
      footB: fb,
      face: face,
      lean: lean,
      armF: armF ?? -sw * 0.55,
      armB: armB ?? sw * 0.55,
      handF: handF,
      handB: handB,
      s: s,
    );
  }

  /// Seated worker; [seat] is the point the hips rest on.
  (Offset, Offset, Offset) sitter(
    Offset seat, {
    double face = 1,
    double armF = 0.3,
    double armB = -0.1,
    Offset? handF,
    double lean = 0,
    double s = _ws,
  }) {
    final fa = seat + Offset(7 * s * face, 9 * s);
    final fb = seat + Offset(5 * s * face, 9 * s);
    return figure(seat, footA: fa, footB: fb, face: face, armF: armF, armB: armB, handF: handF, lean: lean, s: s);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────────────────

class _SitePainter extends CustomPainter {
  _SitePainter({required this.site, required this.clock, required this.labels}) : super(repaint: clock);

  final _Site? site;
  final ValueNotifier<double> clock;
  final _Labels labels;

  @override
  void paint(Canvas canvas, Size size) {
    labels.draw(canvas, 'flutter / text', const Offset(1600 - 64, 40), size: 16, ax: 1);
    final s = site;
    if (s == null) return;
    _Scene(canvas, s, clock.value, labels).paint();
  }

  @override
  bool shouldRepaint(_SitePainter old) => old.site != site;
}

/// A maintenance job on one letter (after the first build).
enum _Job { weld, paint, kern }

class _Event {
  const _Event(this.job, this.g, this.u, this.sign);

  final _Job job;
  final int g;
  final double u; // local time
  final double sign;
}

/// Everything drawn in one frame at time [t].
class _Scene {
  _Scene(this.c, this.s, this.t, this.labels);

  final Canvas c;
  final _Site s;
  final double t;
  final _Labels labels;
  final crew = _Crew();
  final List<_Event> events = [];

  bool get built => t >= s.done;

  void paint() {
    _collectEvents();
    _guides();
    _terrain();
    _craneStatic();
    _warehouse();
    _props();
    _plan();
    _scaffolds();
    _letters();
    _lot();
    _crates();
    _groundCrew();
    crew.flush(c);
    _vehicles();
    _craneDynamic();
    _ropeCrew();
    crew.flush(c);
    _texts();
  }

  // ── Living-phase events ────────────────────────────────────────────────────

  void _collectEvents() {
    if (t >= s.events0) {
      final e = ((t - s.events0) / _eventPeriod).floor();
      final u = t - s.events0 - e * _eventPeriod;
      final r = math.Random(9173 * e + 17);
      final job = _Job.values[r.nextInt(3)];
      var g = r.nextInt(s.glyphs.length);
      if (job == _Job.kern && g == 0) g = 1; // kern needs a left neighbour
      events.add(_Event(job, g, u, r.nextBool() ? 1 : -1));
    }
    final m = s.manual;
    if (m != null) {
      final u = t - s.manualAt;
      if (u < 5.4) {
        events.add(_Event(_Job.weld, m, u * 1.35, 1));
      } else if (u < 10.8) {
        events.add(_Event(_Job.paint, m, (u - 5.4) * 1.35, 1));
      }
    }
  }

  double _kernDx(int i) {
    for (final e in events) {
      if (e.job == _Job.kern && e.g == i) {
        final push = _eio(_seg(e.u, 0.9, 1.8)) - _eio(_seg(e.u, 3.4, 4.3));
        return push * 12 * e.sign;
      }
    }
    return 0;
  }

  // ── Static scenery ─────────────────────────────────────────────────────────

  void _guides() {
    // Survey rods: graduated staffs at both ends of the baseline.
    final rise = _eo(_seg(t, 0.1, 0.8));
    for (final x in [_rodL, _rodR]) {
      final top = _lerp(_ground, 430, rise);
      c.drawLine(Offset(x, _ground), Offset(x, top), _stroke(BP.lineDim, 1.2));
      for (var y = _ground - 12; y > top; y -= 12) {
        final major = ((_ground - y) / 12).round() % 5 == 0;
        c.drawLine(Offset(x - (major ? 5 : 3), y), Offset(x, y), _stroke(BP.lineDim, 1));
      }
    }
    if (rise > 0.99) {
      c.drawCircle(const Offset(_rodR, _base), 5, _stroke(BP.amber, 1.2));
      c.drawLine(const Offset(_rodR - 5, _base), const Offset(_rodR + 5, _base), _stroke(BP.amber, 1));
      // Surveyor's bracket on the left staff.
      final b = Path()
        ..moveTo(28, 492)
        ..lineTo(_rodL, 492)
        ..moveTo(40, 492)
        ..lineTo(_rodL, 520);
      c.drawPath(b, _stroke(BP.lineDim, 1.4));
      // Theodolite on its tripod.
      final tri = Path()
        ..moveTo(52, 492)
        ..lineTo(57, 476)
        ..lineTo(62, 492)
        ..moveTo(57, 476)
        ..lineTo(57, 492);
      c.drawPath(tri, _stroke(BP.line, 1));
      c.drawRect(const Rect.fromLTWH(52, 466, 11, 8), _stroke(BP.line, 1.2));
      c.drawLine(const Offset(63, 470), const Offset(67, 470), _stroke(BP.line, 2));
    }

    // Cap-height and x-height levels: faint dashed survey lines.
    final lv = _seg(t, 1.0, 2.0);
    if (lv > 0) {
      final w = _lerp(_rodL, _rodR, _eio(lv));
      for (final y in [s.capY, s.xY]) {
        c.drawPath(dashPath(_line(Offset(_rodL, y), Offset(w, y)), dash: 3, gap: 7), _stroke(BP.lineFaint, 1));
      }
    }

    // The baseline: sighted through the theodolite, then a string line snaps
    // tight and twangs.
    final sight = _seg(t, 0.8, 2.0);
    if (sight > 0 && t < 2.3) {
      final x = _lerp(_rodL, _rodR, _eio(sight));
      c.drawPath(dashPath(_line(const Offset(_rodL, _base), Offset(x, _base)), dash: 6, gap: 5),
          _stroke(BP.amber.withValues(alpha: 0.8), 1));
    }
    if (t >= 2.0) {
      final u = t - 2.0;
      final amp = 7 * math.exp(-u * 3.5) * math.sin(u * 28);
      final col = BP.amber.withValues(alpha: _lerp(0.9, 0.55, _seg(t, s.done, s.done + 2)));
      if (amp.abs() > 0.05) {
        final p = Path()..moveTo(_rodL, _base);
        for (var i = 1; i <= 32; i++) {
          final f = i / 32;
          p.lineTo(_lerp(_rodL, _rodR, f), _base + amp * math.sin(f * math.pi));
        }
        c.drawPath(p, _stroke(col, 1.3));
      } else {
        c.drawLine(const Offset(_rodL, _base), const Offset(_rodR, _base), _stroke(col, 1.3));
      }
      labels.draw(c, 'baseline', const Offset(_rodR + 9, _base), size: 11, color: BP.amber,
          ay: 0.5, alpha: 0.9 * _seg(t, 2.0, 2.6));
    }
  }

  void _terrain() {
    c.drawLine(const Offset(16, _ground), const Offset(1584, _ground), _stroke(BP.line, 1.4));
    c.drawLine(const Offset(16, 750), const Offset(1584, 750), _stroke(BP.lineDim, 1));
    c.drawPath(dashPath(_line(const Offset(16, 728), const Offset(1584, 728)), dash: 16, gap: 12),
        _stroke(BP.lineFaint, 1.2));
    final hatch = Path();
    for (var x = 20.0; x < 1580; x += 14) {
      hatch
        ..moveTo(x, 752)
        ..lineTo(x - 8, 762);
    }
    c.drawPath(hatch, _stroke(BP.lineFaint, 1));

    // Dimension line of the title's real advance width, once it is built.
    final d = _eo(_seg(t, s.done + 0.4, s.done + 1.4));
    if (d > 0) {
      const y = 784.0;
      final x0 = _left;
      final x1 = _left + s.width;
      final cx = (x0 + x1) / 2;
      final half = (x1 - x0) / 2 * d;
      final p = _stroke(BP.inkDim, 1);
      c.drawLine(Offset(cx - half, y), Offset(cx - 44, y), p);
      c.drawLine(Offset(cx + 44, y), Offset(cx + half, y), p);
      c.drawLine(Offset(cx - half, y - 6), Offset(cx - half, y + 6), p);
      c.drawLine(Offset(cx + half, y - 6), Offset(cx + half, y + 6), p);
      drawArrowHead(c, Offset(cx - half, y), Offset(cx - half + 10, y), p, 5);
      drawArrowHead(c, Offset(cx + half, y), Offset(cx + half - 10, y), p, 5);
      labels.draw(c, '${s.width.toStringAsFixed(1)} px', Offset(cx, y), size: 12, ax: 0.5, ay: 0.5, alpha: d);
    }
  }

  static Path? _craneCache;

  static Path _cranePath() {
    final p = Path();
    // Mast.
    p
      ..moveTo(_mastL, 184)
      ..lineTo(_mastL, _ground)
      ..moveTo(_mastR, 184)
      ..lineTo(_mastR, _ground);
    var left = true;
    for (var y = 184.0; y < _ground - 1; y += 13) {
      p
        ..moveTo(left ? _mastL : _mastR, y)
        ..lineTo(left ? _mastR : _mastL, math.min(_ground, y + 13));
      left = !left;
    }
    // Slewing unit + cat-head.
    p
      ..addRect(const Rect.fromLTRB(_mastL - 6, 170, _mastR + 6, 184))
      ..moveTo(_mastL, _jibTop)
      ..lineTo(1432, 96)
      ..lineTo(_mastR, _jibTop)
      ..moveTo(1432, 96)
      ..lineTo(1432, 170);
    // Jib: top chord tapers towards the tip.
    p
      ..moveTo(_jibL, _jibY)
      ..lineTo(1560, _jibY)
      ..moveTo(_jibL, _jibY - 8)
      ..lineTo(_mastL, _jibTop)
      ..moveTo(_mastR, _jibTop + 6)
      ..lineTo(1560, _jibTop + 6)
      ..moveTo(_jibL, _jibY - 8)
      ..lineTo(_jibL, _jibY)
      ..moveTo(1560, _jibTop + 6)
      ..lineTo(1560, _jibY);
    double topAt(double x) => _lerp(_jibY - 8, _jibTop, (x - _jibL) / (_mastL - _jibL));
    var up = true;
    for (var x = _jibL; x < _mastL - 1; x += 16) {
      final x2 = math.min(_mastL, x + 16);
      if (up) {
        p
          ..moveTo(x, _jibY)
          ..lineTo(x2, topAt(x2));
      } else {
        p
          ..moveTo(x, topAt(x))
          ..lineTo(x2, _jibY);
      }
      up = !up;
    }
    for (var x = _mastR; x < 1560; x += 19) {
      p
        ..moveTo(x, _jibY)
        ..lineTo(x + 9.5, _jibTop + 6)
        ..lineTo(math.min(1560, x + 19), _jibY);
    }
    // Pendants (tie bars) from the cat-head.
    p
      ..moveTo(1432, 96)
      ..lineTo(700, topAt(700))
      ..moveTo(1432, 96)
      ..lineTo(1556, _jibTop + 6);
    // Counterweights, cab, concrete base.
    for (var i = 0; i < 3; i++) {
      p.addRect(Rect.fromLTWH(1516, _jibY + i * 10, 40, 10));
    }
    p
      ..addRect(const Rect.fromLTRB(1386, 156, _mastL - 2, 186))
      ..moveTo(1386, 166)
      ..lineTo(_mastL - 2, 166)
      ..addRect(const Rect.fromLTRB(_mastL - 18, _ground - 8, _mastR + 18, _ground));
    return p;
  }

  void _craneStatic() {
    c.drawPath(_craneCache ??= _cranePath(), _stroke(BP.lineDim, 1.1));
    c.drawLine(const Offset(_jibL, _jibY), const Offset(1560, _jibY), _stroke(BP.line, 1.3));
    // Name plate hanging from the jib.
    c.drawLine(const Offset(1330, _jibY), const Offset(1330, 160), _stroke(BP.lineDim, 1));
    c.drawLine(const Offset(1372, _jibY), const Offset(1372, 160), _stroke(BP.lineDim, 1));
    c.drawRect(const Rect.fromLTRB(1322, 160, 1380, 176), _fill(BP.paper));
    c.drawRect(const Rect.fromLTRB(1322, 160, 1380, 176), _stroke(BP.line, 1));
    labels.draw(c, 'layout', const Offset(1351, 168), size: 11, color: BP.line, ax: 0.5, ay: 0.5);
  }

  void _warehouse() {
    final p = Path()
      ..moveTo(14, _ground)
      ..lineTo(14, 632)
      ..lineTo(46, 612)
      ..lineTo(46, 632)
      ..lineTo(78, 612)
      ..lineTo(78, 632)
      ..lineTo(110, 612)
      ..lineTo(110, _ground)
      ..addRect(const Rect.fromLTRB(34, 656, 88, _ground));
    c.drawPath(p, _stroke(BP.line, 1.3));
    final slats = Path();
    for (var y = 659.0; y < 670; y += 3.5) {
      slats
        ..moveTo(35, y)
        ..lineTo(87, y);
    }
    c.drawPath(slats, _stroke(BP.lineDim, 1));
    labels.draw(c, 'unicode', const Offset(61, 643), size: 12, color: BP.line, ax: 0.5, ay: 0.5);
    // A stack of spare crates outside.
    for (final r in const [
      Rect.fromLTWH(118, 682, 22, 18),
      Rect.fromLTWH(142, 682, 22, 18),
      Rect.fromLTWH(129, 664, 22, 18),
    ]) {
      c.drawRect(r, _fill(BP.paper));
      c.drawRect(r, _stroke(BP.lineDim, 1));
      c.drawLine(r.topLeft, r.bottomRight, _stroke(BP.lineFaint, 1));
    }
  }

  void _props() {
    // Coffee corner by the crane: bench, thermos.
    final p = Path()
      ..moveTo(1482, 686)
      ..lineTo(1566, 686)
      ..moveTo(1488, 686)
      ..lineTo(1488, _ground)
      ..moveTo(1560, 686)
      ..lineTo(1560, _ground)
      ..addRect(const Rect.fromLTWH(1570, 680, 8, 20));
    c.drawPath(p, _stroke(BP.lineDim, 1.3));
    c.drawLine(const Offset(1570, 684), const Offset(1578, 684), _stroke(BP.amber, 1.2));
    // Traffic cones.
    for (final x in const [888.0, 1382.0]) {
      final cone = Path()
        ..moveTo(x - 5, _ground)
        ..lineTo(x, _ground - 13)
        ..lineTo(x + 5, _ground)
        ..close();
      c.drawPath(cone, _stroke(BP.coral, 1.2));
      c.drawLine(Offset(x - 2.8, _ground - 6), Offset(x + 2.8, _ground - 6), _stroke(BP.ink, 1));
    }
  }

  // ── The plan, advance boxes, scaffolds ─────────────────────────────────────

  void _plan() {
    final a = 0.6 * _seg(t, 0.2, 0.9) * (1 - _seg(t, s.done, s.done + 1.5));
    if (a > 0) {
      c.save();
      c.clipRect(Rect.fromLTRB(0, 0, _lerp(_left - 10, _left + s.width + 30, _eio(_seg(t, 0.2, 1.8))), 900));
      c.drawPath(s.plan, _stroke(BP.lineDim.withValues(alpha: a), 1));
      c.restore();
    }
    for (final g in s.glyphs) {
      final vis = _seg(t, g.a + 0.45, g.a + 0.85) * (1 - _seg(t, g.r1, g.r1 + 0.6));
      if (vis <= 0) continue;
      _advanceBox(g, BP.line.withValues(alpha: 0.6 * vis), _eio(_seg(t, g.a + 0.45, g.a + 1.0)));
      labels.draw(c, g.gidLabel, Offset(g.box.left + 4, g.box.top + 4), size: 10, color: BP.line, alpha: vis);
    }
  }

  void _advanceBox(_Glyph g, Color color, [double f = 1, double dx = 0]) {
    final r = g.box.shift(Offset(dx, 0));
    var p = Path()..addRect(r);
    if (f < 1) p = partialPath(p, f);
    c.drawPath(dashPath(p, dash: 5, gap: 4), _stroke(color, 1));
    // Pen position on the baseline.
    final o = g.origin + Offset(dx, 0);
    final tri = Path()
      ..moveTo(o.dx, o.dy)
      ..lineTo(o.dx - 4, o.dy + 7)
      ..lineTo(o.dx + 4, o.dy + 7)
      ..close();
    c.drawPath(tri, _fill(color));
  }

  void _scaffolds() {
    final pole = _stroke(BP.lineDim, 1.2);
    final faint = _stroke(BP.lineFaint, 1);
    final plank = _stroke(BP.lineDim, 2.6);
    final topLevel = s.capY - 22;
    for (final g in s.glyphs) {
      final h = _eo(_seg(t, g.a - 0.6, g.a + 0.3)) * (1 - _ei(_seg(t, g.r1 + 0.1, g.r1 + 0.9)));
      if (h <= 0) continue;
      final top = _lerp(_ground, topLevel, h);
      final x0 = g.box.left + 3;
      final x1 = g.box.right - 3;
      final p = Path()
        ..moveTo(x0, _ground)
        ..lineTo(x0, top)
        ..moveTo(x1, _ground)
        ..lineTo(x1, top);
      final braces = Path();
      var prev = _ground;
      for (final y in const [610.0, 522.0]) {
        if (top > y) break;
        p
          ..moveTo(x0, y)
          ..lineTo(x1, y);
        braces
          ..moveTo(g.k.isEven ? x0 : x1, prev)
          ..lineTo(g.k.isEven ? x1 : x0, y);
        prev = y;
      }
      c.drawPath(p, pole);
      c.drawPath(braces, faint);
      if (top <= 522) {
        c.drawLine(Offset(x0 - 2, 520), Offset(x1 + 2, 520), plank);
        // Ladder.
        final l = Path()
          ..moveTo(x0 + 6, _ground)
          ..lineTo(x0 + 6, 520)
          ..moveTo(x0 + 13, _ground)
          ..lineTo(x0 + 13, 520);
        for (var y = _ground - 8; y > 522; y -= 9) {
          l
            ..moveTo(x0 + 6, y)
            ..lineTo(x0 + 13, y);
        }
        c.drawPath(l, faint);
      }
      if (h > 0.985) {
        c.drawLine(Offset(x0, topLevel), Offset(x1, topLevel), pole);
        c.drawLine(Offset(x0 - 2, topLevel - 2), Offset(x1 + 2, topLevel - 2), plank);
      }
    }
  }

  // ── Letters ────────────────────────────────────────────────────────────────

  /// Hanging pose while the crane lifts a glyph: (scale, dy) about its top.
  (double, double) _hang(_Glyph g, double u) {
    final crateDy = _ground - 34 - g.ink.top;
    if (u < 0.3) return (0.2, crateDy);
    if (u < 0.85) {
      final e = _eio((u - 0.3) / 0.55);
      return (_lerp(0.2, 1, e), _lerp(crateDy, -30, e));
    }
    return (1, -30 * (1 - _back((u - 0.85) / 0.3)));
  }

  void _letters() {
    for (var i = 0; i < s.glyphs.length; i++) {
      final g = s.glyphs[i];
      if (t < g.a + 0.5) continue;
      final u = t - g.h0;
      if (u < 1.15) {
        final (sc, dy) = _hang(g, u);
        final pv = Offset(g.cx, g.ink.top);
        c.save();
        c.translate(pv.dx, pv.dy + dy);
        c.scale(sc);
        c.translate(-pv.dx, -pv.dy);
        c.drawPath(g.path, _fill(BP.line.withValues(alpha: 0.10)));
        c.drawPath(g.path, _stroke(BP.line, 1.5 / sc));
        c.restore();
        continue;
      }
      final dx = _kernDx(i);
      if (dx != 0) {
        c.save();
        c.translate(dx, 0);
      }
      if (t < g.p0) {
        c.drawPath(g.path, _stroke(BP.lineDim, 1));
        if (t >= g.w0) {
          final f = _seg(t, g.w0, g.w1);
          final (done, tail) = g.weldPaths(f);
          c.drawPath(done, _stroke(BP.line, 2));
          if (f < 1) {
            c.drawPath(tail, _stroke(BP.amber.withValues(alpha: 0.3), 6));
            c.drawPath(tail, _stroke(BP.amber, 2.2));
          }
        }
      } else if (t < g.r1) {
        final e = _seg(t, g.p1, g.r1);
        final n = t < g.p1 ? (g.cells.length * _seg(t, g.p0, g.p1)).floor() : g.cells.length;
        _grid(g.ink, 1 - e);
        c.drawPath(g.path, _stroke(BP.line.withValues(alpha: 1 - e), 1.2));
        _cells(g.cells, n, 1 - e, t < g.p1 ? 8 : 0);
        if (e > 0) c.drawPath(g.path, _fill(BP.ink.withValues(alpha: e)));
      } else {
        final band = _bandFor(i);
        if (band == null) {
          c.drawPath(g.path, _fill(BP.ink));
        } else {
          _bandFill(g, band);
        }
      }
      if (dx != 0) c.restore();
    }
  }

  void _grid(Rect ink, double alpha) {
    if (alpha <= 0) return;
    final l = (ink.left / _cell).floor() * _cell;
    final r = (ink.right / _cell).ceil() * _cell;
    final tp = (ink.top / _cell).floor() * _cell;
    final b = (ink.bottom / _cell).ceil() * _cell;
    _gridRect(Rect.fromLTRB(l, tp, r, b), alpha);
  }

  void _gridRect(Rect r, double alpha) {
    final p = Path();
    for (var x = r.left; x <= r.right + 0.1; x += _cell) {
      p
        ..moveTo(x, r.top)
        ..lineTo(x, r.bottom);
    }
    for (var y = r.top; y <= r.bottom + 0.1; y += _cell) {
      p
        ..moveTo(r.left, y)
        ..lineTo(r.right, y);
    }
    c.drawPath(p, _stroke(BP.lineDim.withValues(alpha: 0.7 * alpha), 0.8));
  }

  /// Coverage cells [0, n): alpha = coverage (that IS anti-aliasing); the last
  /// [wet] cells are still wet amber paint.
  void _cells(List<_Cell> cells, int n, double alpha, int wet, [bool Function(_Cell)? keep]) {
    if (alpha <= 0) return;
    final buckets = List.generate(8, (_) => Path());
    final wetPath = Path();
    for (var i = 0; i < n && i < cells.length; i++) {
      final cell = cells[i];
      if (keep != null && !keep(cell)) continue;
      final r = cell.rect.deflate(0.7);
      if (n - i <= wet) {
        wetPath.addRect(r);
      } else {
        buckets[(cell.cov * 8).ceil().clamp(1, 8) - 1].addRect(r);
      }
    }
    for (var b = 0; b < 8; b++) {
      c.drawPath(buckets[b], _fill(BP.ink.withValues(alpha: alpha * (b + 1) / 8)));
    }
    c.drawPath(wetPath, _fill(BP.amber.withValues(alpha: alpha * 0.95)));
  }

  /// Band y of a running re-paint job on letter [i], if any.
  double? _bandFor(int i) {
    for (final e in events) {
      if (e.job == _Job.paint && e.g == i && e.u > 0.7 && e.u < 3.7) {
        final g = s.glyphs[i];
        return _lerp(g.ink.top - 12, g.ink.bottom + 12, _seg(e.u, 0.7, 3.7));
      }
    }
    return null;
  }

  void _bandFill(_Glyph g, double by) {
    final top = ((by - 14) / _cell).floor() * _cell;
    final bot = ((by + 14) / _cell).ceil() * _cell;
    final fill = _fill(BP.ink);
    c.save();
    c.clipRect(Rect.fromLTRB(0, 0, 1600, top));
    c.drawPath(g.path, fill);
    c.restore();
    c.save();
    c.clipRect(Rect.fromLTRB(0, bot, 1600, 900));
    c.drawPath(g.path, fill);
    c.restore();
    _gridRect(
      Rect.fromLTRB((g.ink.left / _cell).floor() * _cell, top, (g.ink.right / _cell).ceil() * _cell, bot),
      0.8,
    );
    _cells(g.cells, g.cells.length, 1, 0, (cell) => cell.rect.top >= top - 0.1 && cell.rect.bottom <= bot + 0.1);
    // Fresh paint on the band's leading row.
    final lead = Path();
    for (final cell in g.cells) {
      if ((cell.rect.bottom - bot).abs() < 0.1) lead.addRect(cell.rect.deflate(0.7));
    }
    c.drawPath(lead, _fill(BP.amber.withValues(alpha: 0.85)));
  }

  // ── Crates and forklifts ───────────────────────────────────────────────────

  double? _forkAnchor(_Glyph g) {
    if (t < g.s) return null;
    if (t < g.a) return _lerp(_door, g.cx, _eio(_seg(t, g.s, g.a)));
    if (t < g.a + 0.45) return g.cx;
    final d = (1720 - g.cx) / 600;
    if (t < g.a + 0.45 + d) return _lerp(g.cx, 1720, _ei(_seg(t, g.a + 0.45, g.a + 0.45 + d)));
    return null;
  }

  void _crates() {
    for (final g in s.glyphs) {
      if (t < g.s || t > g.h0 + 1.0) continue;
      Offset at;
      if (t < g.a) {
        at = Offset(_forkAnchor(g)!, _laneFar - 6);
      } else {
        at = Offset(g.cx, _lerp(_laneFar - 6, _ground, _eio(_seg(t, g.a, g.a + 0.4))));
      }
      _crate(at, g.cpLabel, _seg(t, g.a + 0.45, g.a + 0.85), _seg(t, g.h0 + 0.4, g.h0 + 1.0));
    }
  }

  /// A crate stamped with a code point; [open] pops the lid, [gone] folds it.
  void _crate(Offset bottom, String label, double open, double gone, {Color stamp = BP.amber}) {
    if (gone >= 1) return;
    final a = 1 - gone;
    final h = 26 * (1 - 0.8 * _ei(gone));
    final r = Rect.fromLTRB(bottom.dx - 22, bottom.dy - h, bottom.dx + 22, bottom.dy);
    c.drawRect(r, _fill(BP.paper));
    c.drawRect(r, _stroke(BP.line.withValues(alpha: a), 1.2));
    c.drawLine(r.topLeft + const Offset(0, 5), r.topRight + const Offset(0, 5), _stroke(BP.lineDim.withValues(alpha: a), 1));
    if (gone < 0.3) {
      labels.draw(c, label, r.center + const Offset(0, 3), size: 9.5, color: stamp, ax: 0.5, ay: 0.5, alpha: a);
    }
    // Lid.
    if (open < 1) {
      final e = _eo(open);
      c.save();
      c.translate(r.center.dx + 16 * e, r.top - 2 - 18 * math.sin(e * math.pi * 0.8));
      c.rotate(-0.7 * e);
      c.drawLine(const Offset(-23, 0), const Offset(23, 0), _stroke(BP.line.withValues(alpha: 1 - e), 2.4));
      c.restore();
    }
  }

  // ── Tower crane (moving parts) ─────────────────────────────────────────────

  /// (trolley x, hook y, sling half-width, sling y).
  (double, double, double, double) _craneState() {
    final gl = s.glyphs;
    if (t < s.craneEnd) {
      var j = 0;
      for (var i = 0; i < gl.length; i++) {
        if (t >= gl[i].h0 - 0.3) j = i;
      }
      final g = gl[j];
      final u = t - g.h0;
      final px = j > 0 ? gl[j - 1].cx : g.cx;
      final x = u < 0 ? _lerp(px, g.cx, _eio((u + 0.3) / 0.3)) : g.cx;
      if (u < 0) {
        if (j == 0) return (x, _hookRest, 0, 0);
        final pg = gl[j - 1];
        return (x, _lerp(pg.ink.top - 12, _hookRest, _eio((t - pg.h0 - 1.15) / 0.3)), 0, 0);
      }
      final (sc, dy) = _hang(g, u);
      final attach = g.ink.top + dy - 12;
      if (u < 0.3) return (x, _lerp(_hookRest, attach, _eio(u / 0.3)), 0, 0);
      if (u < 1.15) return (x, attach, g.ink.width * sc * 0.36, g.ink.top + dy);
      return (x, _lerp(g.ink.top - 12, _hookRest, _eio((u - 1.15) / 0.3)), 0, 0);
    }
    final (cyc, u) = s.lotTime(t);
    final sway = math.sin(t * 1.7) * 2.5;
    if (cyc < 0) {
      return (_lerp(gl.last.cx, _lotCx, _eio(_seg(t, s.craneEnd, s.craneEnd + 1.2))) + sway, _hookRest, 0, 0);
    }
    final w = s.lotWord(cyc);
    final n = w.pieces.length;
    for (var i = 0; i < n; i++) {
      final v = u - _lotJob(i);
      if (v < -0.3 || v >= 1.15) continue;
      final r = w.pieces[i].clip;
      final prevX = i == 0 ? _lotCx : w.pieces[i - 1].clip.center.dx;
      final x = v < 0 ? _lerp(prevX, r.center.dx, _eio((v + 0.3) / 0.3)) : r.center.dx;
      final dy = _lotDy(r, v);
      if (v < 0.85) return (x, r.top + dy - 12, r.width * 0.4, r.top + dy);
      return (x, _lerp(r.top - 12, _hookRest, _eio((v - 0.85) / 0.3)), 0, 0);
    }
    final lastEnd = _lotJob(n - 1) + 1.15;
    final lastX = w.pieces.last.clip.center.dx;
    final back = _eio(_seg(u, lastEnd, lastEnd + 1.2));
    final x = u < 1 ? _lotCx : _lerp(lastX, _lotCx, back);
    return (x + sway * _seg(u, lastEnd, lastEnd + 2), _hookRest, 0, 0);
  }

  double _lotJob(int i) => 2.0 + i * 1.45;

  /// Vertical offset of a lot cluster being lowered by the crane.
  double _lotDy(Rect r, double v) {
    final hang = _hookRest + 12 - r.top;
    if (v < 0) return hang;
    if (v < 0.6) return _lerp(hang, -18, _eio(v / 0.6));
    if (v < 0.85) return -18 * (1 - _back((v - 0.6) / 0.25));
    return 0;
  }

  void _craneDynamic() {
    final (x, y, sling, slingY) = _craneState();
    final line = _stroke(BP.line, 1.2);
    final trolley = Rect.fromLTRB(x - 10, _jibY + 1, x + 10, _jibY + 8);
    c.drawRect(trolley, _fill(BP.paper));
    c.drawRect(trolley, line);
    final cable = _stroke(BP.inkDim, 1);
    c.drawLine(Offset(x - 3, _jibY + 8), Offset(x - 3, y - 10), cable);
    c.drawLine(Offset(x + 3, _jibY + 8), Offset(x + 3, y - 10), cable);
    final block = Rect.fromLTRB(x - 6, y - 11, x + 6, y - 2);
    c.drawRect(block, _fill(BP.paper));
    c.drawRect(block, _stroke(BP.amber, 1.3));
    final hook = Path()
      ..moveTo(x, y - 2)
      ..lineTo(x, y + 3)
      ..arcTo(Rect.fromCircle(center: Offset(x - 3, y + 3), radius: 3), 0, math.pi * 0.9, false);
    c.drawPath(hook, _stroke(BP.amber, 1.5));
    if (sling > 0) {
      final sp = _stroke(BP.inkDim, 1);
      c.drawLine(Offset(x, y + 4), Offset(x - sling, slingY), sp);
      c.drawLine(Offset(x, y + 4), Offset(x + sling, slingY), sp);
    }
    // Operator in the cab.
    crew.head(const Offset(1402, 175), -1);
  }

  // ── Workers on ropes: welders, painters, maintenance crews ─────────────────

  /// A worker on a hanging cradle, feet at [feet], ropes up to the jib.
  void _cradle(Offset feet) {
    final p = Path()
      ..moveTo(feet.dx - 11, feet.dy + 1)
      ..lineTo(feet.dx + 11, feet.dy + 1);
    c.drawPath(p, _stroke(BP.lineDim, 2.4));
    final rope = _stroke(BP.lineFaint, 1);
    c.drawLine(Offset(feet.dx - 10, feet.dy), Offset(feet.dx - 10, _jibY + 2), rope);
    c.drawLine(Offset(feet.dx + 10, feet.dy), Offset(feet.dx + 10, _jibY + 2), rope);
  }

  /// Rope descent/ascent: blends [at] with a point just under the jib.
  Offset _abseil(Offset at, double down, double up) {
    final top = Offset(at.dx, _jibY + 34);
    return Offset.lerp(top, at, _eio(down) * (1 - _eio(up)))!;
  }

  void _welder(Offset tip, Offset pos, {required bool active, double seed = 0, Offset? Function(double)? src}) {
    final feet = pos + const Offset(-14, 18);
    _cradle(feet);
    final (hand, _, _) = crew.walker(feet, stride: 0, lean: 0.25, handF: pos + const Offset(-3, -2), armB: 0.5);
    c.drawLine(hand, pos, _stroke(BP.inkDim, 1.6));
    if (active) {
      c.drawCircle(tip, 3.2, _fill(BP.amber.withValues(alpha: 0.35 + 0.3 * _h(t * 20 + seed))));
      _sparks((back) => src?.call(back) ?? tip, n: 10, life: 0.45, seed: seed);
    }
  }

  void _painter(Offset roller, double dir, Offset pos, {required bool active, double seed = 0}) {
    final feet = pos + Offset(-15 * dir, 19);
    _cradle(feet);
    final (hand, _, head) = crew.walker(feet, face: dir, stride: 0, handF: pos + Offset(-5 * dir, 2), armB: 0.3);
    c.drawLine(hand, pos, _stroke(BP.inkDim, 1.4));
    final r = Rect.fromCenter(center: pos, width: 5, height: 13);
    c.drawRect(r, _fill(active ? BP.amber : BP.paper));
    c.drawRect(r, _stroke(BP.amber, 1));
    if (active) _sweat(head, dir, seed);
  }

  void _ropeCrew() {
    // First build.
    for (final g in s.glyphs) {
      if (t > g.w0 - 0.6 && t < g.w1 + 0.6) {
        final f = _seg(t, g.w0, g.w1);
        final (tip, _) = g.tipAt(f);
        final pos = _abseil(tip, _seg(t, g.w0 - 0.6, g.w0), _seg(t, g.w1 + 0.05, g.w1 + 0.6));
        _welder(tip, pos,
            active: t >= g.w0 && t < g.w1, seed: g.k.toDouble(), src: (b) => g.tipAt(_seg(t - b, g.w0, g.w1)).$1);
      }
      if (t > g.p0 - 0.6 && t < g.p1 + 0.6) {
        final cells = g.cells;
        final n = (cells.length * _seg(t, g.p0, g.p1)).floor().clamp(1, cells.length);
        final cell = cells[n - 1];
        final nextRow = n < cells.length ? cells[n].row == cell.row : true;
        final dir = nextRow && n > 1 && cells[n - 2].row == cell.row
            ? (cell.rect.left > cells[n - 2].rect.left ? 1.0 : -1.0)
            : 1.0;
        final pos = _abseil(cell.rect.center, _seg(t, g.p0 - 0.6, g.p0), _seg(t, g.p1 + 0.05, g.p1 + 0.6));
        _painter(cell.rect.center, dir, pos, active: t >= g.p0 && t < g.p1, seed: g.k.toDouble());
      }
    }
    // Maintenance.
    for (final e in events) {
      final g = s.glyphs[e.g];
      final dx = Offset(_kernDx(e.g), 0);
      switch (e.job) {
        case _Job.weld:
          final m = g.longest;
          final f = _seg(e.u, 0.7, 3.7);
          final l = m.length * f;
          final tip = (m.getTangentForOffset(l)?.position ?? g.ink.center) + dx;
          final fade = 1 - _seg(e.u, 3.8, 4.6);
          if (f > 0 && fade > 0) {
            c.save();
            c.translate(dx.dx, 0);
            c.drawPath(m.extractPath(0, l), _stroke(BP.line.withValues(alpha: fade), 2.2));
            if (f < 1) {
              final tail = m.extractPath(math.max(0, l - 46), l);
              c.drawPath(tail, _stroke(BP.amber.withValues(alpha: 0.3), 6));
              c.drawPath(tail, _stroke(BP.amber, 2.4));
            }
            c.restore();
          }
          if (e.u < 4.6) {
            final pos = _abseil(tip, _seg(e.u, 0, 0.7), _seg(e.u, 3.8, 4.6));
            _welder(tip, pos, active: f > 0 && f < 1, seed: 40 + e.g.toDouble(), src: (b) {
              final fb = _seg(e.u - b, 0.7, 3.7);
              return (m.getTangentForOffset(m.length * fb)?.position ?? g.ink.center) + dx;
            });
          }
        case _Job.paint:
          if (e.u < 4.6) {
            final f = _seg(e.u, 0.7, 3.7);
            final by = _lerp(g.ink.top - 12, g.ink.bottom + 12, f);
            final bot = ((by + 14) / _cell).ceil() * _cell;
            final sweep = math.sin(e.u * 6.5);
            final x = _lerp(g.ink.left + 6, g.ink.right - 6, 0.5 + 0.5 * sweep);
            final roller = Offset(x, bot - 4) + dx;
            final pos = _abseil(roller, _seg(e.u, 0, 0.7), _seg(e.u, 3.8, 4.6));
            _painter(roller, math.cos(e.u * 6.5) >= 0 ? 1 : -1, pos, active: f > 0 && f < 1, seed: 70 + e.g.toDouble());
          }
        case _Job.kern:
          _kernCrew(e, g, dx.dx);
      }
    }
  }

  void _kernCrew(_Event e, _Glyph g, double dx) {
    if (e.u > 5.2) return;
    final down = _seg(e.u, 0, 0.8);
    final up = _seg(e.u, 4.4, 5.2);
    // Who pushes first depends on the direction of the adjustment.
    for (final side in [-1.0, 1.0]) {
      final first = side == -e.sign;
      final pushing = first ? _window(e.u, 0.8, 1.9, 0.2) : _window(e.u, 3.3, 4.4, 0.2);
      final edge = side < 0 ? g.ink.left + dx : g.ink.right + dx;
      final base = Offset(edge + side * 22, _base + 14);
      final feet = _abseil(base, down, up);
      _cradle(feet);
      final face = -side;
      final bar = Offset(edge + side * 2, _base - 4);
      final (hand, _, head) = crew.walker(feet, face: face, stride: 0, lean: 0.35 * pushing, handF: Offset.lerp(feet + Offset(face * 8, -16), bar, 0.55), armB: 0.8);
      if (down >= 1 && up <= 0) {
        c.drawLine(hand - Offset(face * 6, 4), bar, _stroke(BP.coral, 2));
        if (pushing > 0.5) _sweat(head, face, side);
      }
    }
    // The kerning gap to the left neighbour, measured.
    final vis = _window(e.u, 1.0, 4.2, 0.3);
    if (vis > 0 && e.g > 0) {
      final prev = s.glyphs[e.g - 1];
      _advanceBox(g, BP.amber.withValues(alpha: 0.7 * vis), 1, dx);
      final y = _base + 34;
      final x0 = prev.box.right;
      final x1 = g.box.left + dx;
      final p = _stroke(BP.amber.withValues(alpha: vis), 1.2);
      c.drawLine(Offset(x0, y - 6), Offset(x0, y + 6), p);
      c.drawLine(Offset(x1, y - 6), Offset(x1, y + 6), p);
      c.drawLine(Offset(x0 - 14, y), Offset(x0, y), p);
      c.drawLine(Offset(x1, y), Offset(x1 + 14, y), p);
      drawArrowHead(c, Offset(x0, y), Offset(x0 - 10, y), p, 5);
      drawArrowHead(c, Offset(x1, y), Offset(x1 + 10, y), p, 5);
      labels.draw(c, 'kern', Offset((x0 + x1) / 2, y + 9), size: 11, color: BP.amber, ax: 0.5, alpha: vis);
    }
  }

  // ── Particles (stateless) ──────────────────────────────────────────────────

  void _sparks(Offset Function(double back) src,
      {int n = 10, double life = 0.45, double seed = 0, double power = 1, bool Function(double born)? gate}) {
    final hot = Path();
    final cool = Path();
    for (var i = 0; i < n; i++) {
      final ph = t / life + i / n + seed * 0.37;
      final cyc = ph.floorToDouble();
      final age = (ph - cyc) * life;
      if (gate != null && !gate(t - age)) continue;
      final r1 = _h2(cyc + seed * 13, i.toDouble());
      final r2 = _h2(i + 0.5, cyc - seed);
      final ang = -math.pi / 2 + (r1 - 0.5) * 2.8;
      final v = Offset(math.cos(ang), math.sin(ang)) * ((50 + 150 * r2) * power);
      final pos = src(age) + v * age + Offset(0, 300 * age * age);
      final vel = v + Offset(0, 600 * age);
      final tail = pos - vel * 0.016;
      (age < life * 0.45 ? hot : cool)
        ..moveTo(tail.dx, tail.dy)
        ..lineTo(pos.dx, pos.dy);
    }
    c.drawPath(hot, _stroke(BP.amber, 1.4));
    c.drawPath(cool, _stroke(BP.coral.withValues(alpha: 0.75), 1));
  }

  void _sweat(Offset head, double face, double seed) {
    for (var i = 0; i < 2; i++) {
      final ph = (t / 0.8 + i * 0.5 + seed * 0.29) % 1.0;
      final p = head + Offset(-face * (4 + ph * 9), -3 - 8 * ph + 26 * ph * ph);
      c.drawCircle(p, 1.3, _fill(BP.line.withValues(alpha: 1 - ph)));
    }
  }

  void _steam(Offset cup, double seed) {
    final p = Path();
    for (var i = 0; i < 2; i++) {
      final ph = (t * 0.6 + i * 0.5 + seed) % 1.0;
      final y = cup.dy - 3 - ph * 16;
      final x = cup.dx + math.sin(ph * 7 + i * 2) * 2.5;
      p
        ..moveTo(x, y)
        ..quadraticBezierTo(x + 2.5, y - 3, x, y - 6);
    }
    c.drawPath(p, _stroke(BP.inkDim.withValues(alpha: 0.7), 1));
  }

  // ── Ground crew ────────────────────────────────────────────────────────────

  double _survey() {
    if (t < s.done + 6) return 0;
    final u = (t - s.done - 6) % 19.0;
    return u < 2.4 ? u / 2.4 : 0;
  }

  void _groundCrew() {
    final cheer = _window(t, s.done, s.done + 2.8, 0.25);
    final hop = -(math.sin(t * 9).abs()) * 4 * cheer;

    // Surveyor at the theodolite, and the periodic re-check of the baseline.
    final sv = _survey();
    final sighting = t < 2.4 || sv > 0;
    crew.walker(const Offset(40, 492),
        stride: 0, lean: sighting ? 0.45 : 0, handF: sighting ? const Offset(52, 471) : null, armF: 0.15, armB: -0.1);
    if (sv > 0) {
      final x = _lerp(_rodL, _rodR, _eio(sv));
      c.drawPath(dashPath(_line(const Offset(_rodL, _base - 3), Offset(x, _base - 3)), dash: 6, gap: 5),
          _stroke(BP.amber.withValues(alpha: 0.7), 1));
      c.drawCircle(Offset(x, _base - 3), 2.5, _fill(BP.amber));
    }

    // Foreman with a clipboard, checking his watch.
    final watch = ((t + 3) % 11.0) < 1.4;
    final (fh, _, _) = crew.walker(Offset(182, _ground + hop),
        stride: 0,
        armF: cheer > 0.5 ? 2.8 : 1.15,
        armB: cheer > 0.5 ? 2.9 : (watch ? 2.0 : -0.1),
        lean: watch ? 0.12 : 0);
    if (cheer <= 0.5) {
      c.drawRect(Rect.fromCenter(center: fh + const Offset(2, -3), width: 7, height: 9), _stroke(BP.amber, 1.1));
    }

    // Plank carriers pacing the yard; they high-five when they cross.
    final walkers = <(double, double)>[];
    for (final (x0, x1, period, off) in const [(210.0, 860.0, 16.0, 0.0), (250.0, 900.0, 21.0, 7.0)]) {
      final ph = ((t + off) / period) % 1.0;
      final right = ph < 0.5;
      final f = right ? ph * 2 : 2 - ph * 2;
      walkers.add((_lerp(x0, x1, f), right ? 1.0 : -1.0));
    }
    final five = (walkers[0].$1 - walkers[1].$1).abs() < 16 && walkers[0].$2 != walkers[1].$2;
    for (var i = 0; i < walkers.length; i++) {
      final (x, face) = walkers[i];
      final carrying = face > 0;
      final walk = (t + i * 7) * 9.5;
      final feet = Offset(x, _ground + hop);
      if (cheer > 0.5) {
        crew.walker(feet, face: face, stride: 0, armF: 2.8, armB: 2.9);
        continue;
      }
      final (_, _, head) = crew.walker(feet,
          face: face,
          walk: walk,
          armF: carrying ? 2.5 : null,
          armB: five ? 2.8 : null,
          handF: carrying ? null : null);
      if (carrying) {
        c.drawLine(head + Offset(-18 * face, 6), head + Offset(22 * face, 4), _stroke(BP.lineDim, 2.6));
      }
    }
    if (five) {
      final m = Offset((walkers[0].$1 + walkers[1].$1) / 2, _ground - 36);
      final p = _stroke(BP.amber, 1.3);
      for (var k = 0; k < 6; k++) {
        final a = k * math.pi / 3 + t * 2;
        c.drawLine(m + Offset(math.cos(a), math.sin(a)) * 4, m + Offset(math.cos(a), math.sin(a)) * 8, p);
      }
    }

    // Coffee corner.
    final sip = (t % 7.0) < 1.6;
    final seatA = const Offset(1502, 686);
    final (ha, _, headA) = crew.sitter(seatA,
        face: 1, handF: cheer > 0.5 ? null : (sip ? null : seatA + const Offset(8, -5)), armF: cheer > 0.5 ? 2.8 : 2.2);
    final cupA = sip && cheer <= 0.5 ? headA + const Offset(4, 3) : ha;
    c.drawRect(Rect.fromCenter(center: cupA, width: 4, height: 5), _stroke(BP.ink, 1.2));
    if (!sip) _steam(cupA, 0.1);
    final yb = (t + 4) % 13.0;
    final stretch = yb < 2.0 && cheer <= 0.5;
    final doze = yb > 5 && yb < 9.5;
    final seatB = const Offset(1548, 686);
    final (hb, _, headB) = crew.sitter(seatB,
        face: -1,
        lean: doze ? 0.35 : 0,
        armF: stretch || cheer > 0.5 ? 2.9 : 0.9,
        armB: stretch ? 2.7 : 0.2);
    if (!stretch) {
      c.drawRect(Rect.fromCenter(center: hb, width: 4, height: 5), _stroke(BP.ink, 1.2));
      if (!doze) _steam(hb, 0.6);
    }
    if (doze) {
      for (var i = 0; i < 2; i++) {
        final ph = ((yb - 5) / 1.5 + i * 0.5) % 1.0;
        labels.draw(c, 'z', headB + Offset(-4 - 10 * ph, -10 - 16 * ph),
            size: 12, color: BP.inkDim, alpha: 1 - ph, ax: 0.5, ay: 0.5);
      }
    }

    // Scaffold crews during the first build.
    for (final g in s.glyphs) {
      if (t < g.a + 0.35 || t > g.r1) continue;
      final x0 = g.box.left + 3;
      final x1 = g.box.right - 3;
      if (g.k.isEven) {
        final off = g.k * 0.13;
        final ph = ((t + off) / 0.5) % 1.0;
        final arm = ph < 0.75 ? _lerp(1.3, 2.8, _eo(ph / 0.75)) : _lerp(2.8, 1.25, (ph - 0.75) / 0.25);
        final (hand, _, head) = crew.walker(Offset(x1 - 13, 518), stride: 0, armF: arm, armB: 0.3);
        final dir = (hand - (head + const Offset(0, 5)));
        final n = dir / math.max(0.01, dir.distance);
        final hd = hand + n * 4;
        c.drawLine(hd - Offset(-n.dy, n.dx) * 3, hd + Offset(-n.dy, n.dx) * 3, _stroke(BP.ink, 2.4));
        _sparks((_) => Offset(x1, 506),
            n: 6, life: 0.3, seed: g.k.toDouble(), power: 0.7, gate: (born) => ((born + off) / 0.5) % 1.0 < 0.06);
      } else {
        final cyc = ((t + g.k) / 3.4) % 1.0;
        final f = cyc < 0.5 ? cyc * 2 : 2 - cyc * 2;
        final y = _lerp(_ground, 522, _eio(f));
        final lx = x0 + 9.5;
        final st = math.sin(y / 4.5);
        crew.figure(Offset(lx - 5, y - 11),
            footA: Offset(lx - 1, y - 3 - 3 * st),
            footB: Offset(lx - 1, y - 3 + 3 * st),
            handF: Offset(lx + 1, y - 27 + 3 * st),
            handB: Offset(lx + 1, y - 24 - 3 * st),
            lean: 0.1);
      }
    }
  }

  // ── Vehicles ───────────────────────────────────────────────────────────────

  void _vehicles() {
    for (final g in s.glyphs) {
      final ax = _forkAnchor(g);
      if (ax == null) continue;
      final lift = t < g.a
          ? 0.0
          : t < g.a + 0.45
          ? _eio(_seg(t, g.a, g.a + 0.4))
          : 1 - _seg(t, g.a + 0.45, g.a + 0.9);
      _forklift(ax, lift);
    }
    // The font arrives first.
    if (t < 6.2) {
      final x = t < 2.2
          ? _lerp(-220, 640, _eo(t / 2.2))
          : t < 3.6
          ? 640.0
          : _lerp(640, 1780, _ei(_seg(t, 3.6, 6.2)));
      _truck(x, 1, 0, 'SpaceGrotesk.ttf');
    }
    final (cyc, u) = s.lotTime(t);
    if (cyc < 0) return;
    final w = s.lotWord(cyc);
    final r = math.Random(cyc * 97 + 3);
    final kind = const [0, 1, 3][r.nextInt(3)];
    final dir = r.nextBool() ? 1.0 : -1.0;
    final spare = s.glyphs[r.nextInt(s.glyphs.length)];
    // Spare crate on a forklift, far lane.
    if (u > 8.5 && u < 13.5) {
      final ax = _lerp(_door, 1720, _seg(u, 8.5, 13.5));
      _crate(Offset(ax, _laneFar - 6), spare.cpLabel, 0, 0);
      _forklift(ax, 0);
    }
    // The lot's font (fallback!) is delivered.
    if (u < 5.5) {
      final x = u < 1.8
          ? _lerp(1780, _lotCx + 30, _eo(u / 1.8))
          : u < 3.2
          ? _lotCx + 30
          : _lerp(_lotCx + 30, -220, _ei(_seg(u, 3.2, 5.5)));
      _truck(x, -1, 0, w.font);
    }
    // Passing traffic.
    if (u > 6 && u < 12) {
      final f = _seg(u, 6, 12);
      _truck(dir > 0 ? _lerp(-220, 1780, f) : _lerp(1780, -220, f), dir, kind, 'SpaceGrotesk.ttf');
    }
    // Dump truck hauls the rubble away.
    if (u > 12.4) {
      final x = u < 14.4
          ? _lerp(-220, _lotCx - 20, _eo(_seg(u, 12.4, 14.4)))
          : u < 16.2
          ? _lotCx - 20
          : _lerp(_lotCx - 20, 1780, _ei(_seg(u, 16.2, 18)));
      _truck(x, 1, 2, null, load: _seg(u, 14.0, 15.8), loadColor: w.script.color);
    }
  }

  void _forklift(double ax, double lift) {
    const y = _laneFar;
    final forkY = _lerp(y - 6, _ground, lift);
    final body = Path()
      ..moveTo(ax - 62, y - 6)
      ..lineTo(ax - 62, y - 17)
      ..lineTo(ax - 55, y - 21)
      ..lineTo(ax - 27, y - 21)
      ..lineTo(ax - 27, y - 6)
      ..close();
    c.drawPath(body, _fill(BP.paper));
    c.drawPath(body, _stroke(BP.line, 1.2));
    final guard = Path()
      ..moveTo(ax - 53, y - 21)
      ..lineTo(ax - 53, y - 44)
      ..lineTo(ax - 30, y - 44)
      ..lineTo(ax - 30, y - 21);
    c.drawPath(guard, _stroke(BP.lineDim, 1.2));
    c.drawLine(Offset(ax - 25, y - 4), Offset(ax - 25, y - 48), _stroke(BP.line, 1.6));
    c.drawLine(Offset(ax - 25, forkY), Offset(ax + 20, forkY), _stroke(BP.line, 1.8));
    for (final wx in [ax - 52.0, ax - 34.0]) {
      _wheel(Offset(wx, y - 5), 5, ax);
    }
    crew.sitter(Offset(ax - 43, y - 21), face: 1, handF: Offset(ax - 32, y - 27));
  }

  void _wheel(Offset at, double r, double travel) {
    c.drawCircle(at, r, _fill(BP.paper));
    c.drawCircle(at, r, _stroke(BP.line, 1.2));
    final a = travel / r;
    c.drawLine(at, at + Offset(math.cos(a), math.sin(a)) * (r - 1), _stroke(BP.lineDim, 1));
  }

  /// kind: 0 box truck, 1 mixer, 2 dump truck, 3 flatbed with crates.
  void _truck(double x, double face, int kind, String? label, {double load = 0, Color loadColor = BP.ink}) {
    Offset p(double lx, double ly) => Offset(x + lx * face, _laneNear + ly);
    Path poly(List<(double, double)> pts) {
      final path = Path();
      for (var i = 0; i < pts.length; i++) {
        final o = p(pts[i].$1, pts[i].$2);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      return path..close();
    }

    final ink = _stroke(BP.line, 1.3);
    final paper = _fill(BP.paper);
    final cab = poly(const [(30, -12), (30, -42), (48, -42), (63, -27), (63, -12)]);
    c.drawPath(cab, paper);
    c.drawPath(cab, ink);
    c.drawPath(poly(const [(34, -38), (47, -38), (58, -28), (34, -28)]), _stroke(BP.lineDim, 1));
    crew.head(p(41, -31), face);
    c.drawLine(p(-90, -12), p(63, -12), ink);
    switch (kind) {
      case 0:
        final box = poly(const [(-92, -54), (26, -54), (26, -14), (-92, -14)]);
        c.drawPath(box, paper);
        c.drawPath(box, ink);
        if (label != null) {
          labels.draw(c, label, p(-33, -34), size: 10, color: BP.amber, ax: 0.5, ay: 0.5);
        }
      case 1:
        final ctr = p(-30, -34);
        c.save();
        c.translate(ctr.dx, ctr.dy);
        c.rotate(-0.14 * face);
        final drum = Rect.fromCenter(center: Offset.zero, width: 100, height: 38);
        c.drawOval(drum, paper);
        c.drawOval(drum, ink);
        c.clipPath(Path()..addOval(drum));
        final stripes = Path();
        for (var i = 0; i < 5; i++) {
          final sx = ((i / 5 + t * 0.35 * face) % 1.0) * 120 - 60;
          stripes
            ..moveTo(sx - 8, -19)
            ..lineTo(sx + 8, 19);
        }
        c.drawPath(stripes, _stroke(BP.lineDim, 1.2));
        c.restore();
      case 2:
        final bed = poly(const [(-92, -46), (24, -46), (24, -14), (-84, -14)]);
        c.drawPath(bed, paper);
        c.drawPath(bed, ink);
        if (load > 0) {
          final rubble = Path();
          final n = (14 * load).round();
          for (var i = 0; i < n; i++) {
            final o = p(-84 + 102 * _h(i + 0.3), -50 - 6 * _h(i + 7.7));
            rubble.addRect(Rect.fromCenter(center: o, width: 5, height: 5));
          }
          c.drawPath(rubble, _fill(loadColor.withValues(alpha: 0.8)));
        }
      default:
        c.drawLine(p(-92, -16), p(26, -16), ink);
        for (var i = 0; i < 3; i++) {
          final r = Rect.fromPoints(p(-88 + i * 34.0, -16), p(-62 + i * 34.0, -34));
          c.drawRect(r, paper);
          c.drawRect(r, _stroke(BP.line, 1.1));
          c.drawLine(r.topLeft, r.bottomRight, _stroke(BP.lineDim, 1));
        }
    }
    for (final wx in const [-70.0, -52.0, 44.0]) {
      _wheel(p(wx, -7), 7, x);
    }
  }

  // ── The side lot: other scripts, built and demolished forever ──────────────

  void _lot() {
    final (cyc, u) = s.lotTime(t);
    if (cyc < 0) return;
    final w = s.lotWord(cyc);
    final col = w.script.color;
    final b = w.bounds;
    final n = w.pieces.length;
    final built = _lotJob(n - 1) + 1.15;

    // Scaffold.
    final h = _eo(_seg(u, 0.5, 1.3)) * (1 - _ei(_seg(u, built + 0.3, built + 1.1)));
    final plankY = b.top - 12;
    if (h > 0) {
      final top = _lerp(_ground, plankY, h);
      final p = Path();
      for (final x in [b.left - 10, b.center.dx, b.right + 10]) {
        p
          ..moveTo(x, _ground)
          ..lineTo(x, top);
      }
      c.drawPath(p, _stroke(BP.lineDim, 1.1));
      if (h > 0.98) {
        c.drawLine(Offset(b.left - 14, plankY), Offset(b.right + 14, plankY), _stroke(BP.lineDim, 2.6));
        if (u > 1.6 && u < built) {
          final ph = ((u + cyc * 0.3) / 0.55) % 1.0;
          final arm = ph < 0.75 ? _lerp(1.3, 2.8, _eo(ph / 0.75)) : _lerp(2.8, 1.2, (ph - 0.75) / 0.25);
          crew.walker(Offset(b.right + 6, plankY - 1), face: -1, stride: 0, armF: arm, armB: 0.2);
          _sparks((_) => Offset(b.right - 6, plankY - 4),
              n: 5, life: 0.3, seed: 90, power: 0.6, gate: (born) => ((born - t + u + cyc * 0.3) / 0.55) % 1.0 < 0.06);
        }
      }
    }

    // Cluster boxes from the real paragraph (one per grapheme cluster).
    final bv = _seg(u, 1.2, 1.8) * (1 - _seg(u, built + 0.2, built + 1.0));
    if (bv > 0) {
      final p = Path();
      for (final pc in w.pieces) {
        p.addRect(pc.clip);
      }
      c.drawPath(dashPath(p, dash: 4, gap: 4), _stroke(col.withValues(alpha: 0.6 * bv), 1));
    }

    // Script tag (left of the column for vertical text).
    final tv = _window(u, 1.2, 15.8, 0.4);
    if (tv > 0) {
      final tw = labels.get(w.tag, 11, col).width;
      final at = w.vertical ? Offset(b.left - 30 - tw, b.top) : Offset(b.left - 10, b.top - 44);
      final sz = labels.draw(c, w.tag, at + const Offset(6, 3), size: 11, color: col, alpha: tv);
      c.drawRect(Rect.fromLTWH(at.dx, at.dy, sz.width + 12, sz.height + 6), _stroke(col.withValues(alpha: tv * 0.8), 1));
    }

    // The text: pieces lowered one by one in logical order (so Arabic is
    // built right-to-left, vertical Japanese top-to-bottom, ruby last), then
    // the whole shaped word.
    if (u < built) {
      for (var i = 0; i < n; i++) {
        final v = u - _lotJob(i);
        if (v < -0.3) continue;
        final pc = w.pieces[i];
        final dy = _lotDy(pc.clip, v);
        c.save();
        c.clipRect(pc.clip.shift(Offset(0, dy)));
        pc.painter.paint(c, pc.origin + Offset(0, dy));
        c.restore();
      }
      return;
    }
    final demo = _seg(u, 13.2, 15.6);
    if (demo >= 1) return;
    final front = _lerp(b.top - 2, b.bottom + 2, _eio(demo));
    c.save();
    c.clipRect(Rect.fromLTRB(b.left - 40, front, b.right + 40, b.bottom + 40));
    for (final (p, o) in w.wholes) {
      p.paint(c, o);
    }
    c.restore();
    if (u < 12.6) return;

    // Demolition crew on ropes with jackhammers; rubble falls.
    final down = _seg(u, 12.6, 13.2);
    final up = _seg(u, 15.7, 16.4);
    for (final fx in const [0.3, 0.72]) {
      final base = Offset(_lerp(b.left, b.right, fx), math.min(_ground, front) - 1);
      final feet = _abseil(base, down, up);
      if (up <= 0 && down >= 1) {
        final jig = Offset(0, math.sin(t * 70 + fx * 9) * 1.2);
        final (hand, _, _) = crew.walker(feet + jig, face: fx < 0.5 ? 1 : -1, stride: 0.2, walk: t * 30, armF: 0.9, armB: 0.7);
        final bit = feet + Offset(fx < 0.5 ? 8 : -8, 0);
        c.drawLine(hand, bit, _stroke(BP.ink, 2));
        c.drawRect(Rect.fromCenter(center: hand + const Offset(0, 3), width: 5, height: 8), _stroke(BP.amber, 1.2));
        for (var k = 0; k < 3; k++) {
          final ph = (t * 2.2 + k / 3 + fx) % 1.0;
          c.drawCircle(bit + Offset((k - 1) * 6 * ph, -3 * ph), 2 + 5 * ph, _stroke(BP.inkDim.withValues(alpha: 0.6 * (1 - ph)), 1));
        }
      } else {
        _cradle(feet);
        crew.walker(feet, stride: 0);
      }
    }
    final rubble = Path();
    for (var i = 0; i < 18; i++) {
      final ph = (u * 1.6 + i / 18) % 1.0;
      final age = ph / 1.6;
      final born = u - age;
      if (born < 13.2 || born > 15.6) continue;
      final fy = _lerp(b.top - 2, b.bottom + 2, _eio(_seg(born, 13.2, 15.6)));
      final id = (u * 1.6 + i / 18).floorToDouble();
      final x = _lerp(b.left, b.right, _h2(i.toDouble(), id)) + (_h2(id, i + 0.7) - 0.5) * 50 * age;
      final y = math.min(_ground - 3, fy + 40 * age + 420 * age * age);
      rubble.addRect(Rect.fromCenter(center: Offset(x, y), width: 4.5, height: 4.5));
    }
    c.drawPath(rubble, _fill(col.withValues(alpha: 0.85)));
  }

  // ── Words ──────────────────────────────────────────────────────────────────

  void _texts() {
    final st = _seg(t, s.done, s.done + 1.8);
    if (st > 0) {
      const y = 540.0;
      c.drawLine(const Offset(_left, y + 14), Offset(_left + 36 * _eo(st * 4), y + 14), _stroke(BP.amber, 1.5));
      final p = labels.get(_subtitle, 22, BP.inkDim);
      final w = p.width * st;
      c.save();
      c.clipRect(Rect.fromLTWH(_left + 48, y - 6, w, 44));
      p.paint(c, const Offset(_left + 48, y));
      c.restore();
      if (st < 1) {
        c.drawRect(Rect.fromLTWH(_left + 50 + w, y + 3, 11, 24), _fill(BP.amber));
      }
    }
    final ja = s.jaSub;
    final jt = _seg(t, s.done + 1.6, s.done + 2.6);
    if (ja != null && jt > 0) {
      const y = 580.0;
      c.save();
      c.clipRect(Rect.fromLTWH(_left + 48, y - 6, ja.width * jt, ja.height + 12));
      ja.paint(c, const Offset(_left + 48, y));
      c.restore();
    }
    final hv = s.hover;
    if (hv != null && t > s.glyphs[hv].r1) {
      final g = s.glyphs[hv];
      final dx = _kernDx(hv);
      _advanceBox(g, BP.amber, 1, dx);
      labels.draw(c, g.info, Offset(g.box.left + dx, g.box.top - 6), size: 12, color: BP.amber, ay: 1);
    }
  }
}
