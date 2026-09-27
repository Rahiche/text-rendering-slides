import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../deck/scripts.dart';
import '../deck/theme.dart';
import '../deck/widgets.dart';
import '../worlds/workers/crew.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Title prototype: "easy vs hard".
//
// Left: three relaxed workers drop "Text" into its slots in ~2 s, then idle.
// Right: a crowd shapes the same word in a complex script (Japanese →
// Arabic → Devanagari → Thai). Every job is a real shaping step, and every letter,
// form, dot and mark is real rendered text: contextual forms come from ZWJ
// context, marks are "word minus word-without-mark", the headline is a clip
// of the real word. One ticker drives one painter; nothing accumulates.
// ─────────────────────────────────────────────────────────────────────────────

const _gy = 470.0; // the ground = the baseline both crews build on
const _fy = 502.0; // front row (workers standing in front of the word)
const _divX = 800.0;
const _lCx = 462.0;
const _rCx = 1180.0;
const _mastX = 1552.0;
const _jibY = 150.0;
const _jibTip = 860.0;
const _homeX = 1440.0; // crane trolley parking spot
const _hookHome = _jibY + 46.0;
const _enterX = 1606.0; // carried letters enter here (their left edge)
const _offX = 1660.0; // off stage, right
const _hold = 3.2; // celebrate
const _tear = 1.8; // tear down
const _carryLift = 32.0; // letter baseline above the ground while carried

typedef _Cyc = ({int n, int s, double tau, double work});

double _seg(double t, double a, double b) =>
    b <= a ? (t >= b ? 1.0 : 0.0) : ((t - a) / (b - a)).clamp(0.0, 1.0);
double _eo(double x) => 1 - math.pow(1 - x, 3).toDouble();
double _eio(double x) =>
    x < 0.5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;
double _backOut(double x) {
  const c1 = 1.70158;
  const c3 = c1 + 1;
  return 1 + c3 * math.pow(x - 1, 3) + c1 * math.pow(x - 1, 2);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Deterministic hash → [0, 1). Float based so web and native agree.
double _h(num a, [num b = 0, num c = 0]) {
  final s = math.sin(a * 12.9898 + b * 78.233 + c * 37.719) * 43758.5453;
  return s - s.floorToDouble();
}

/// Walk from [x0] (starting at [t0]) to [x1] at speed [v].
/// Returns the position and the heading (0 when standing).
(double, double) _go(double t, double t0, double x0, double x1, double v) {
  if (t <= t0) return (x0, 0);
  final d = x1 - x0;
  final dur = d.abs() / v;
  if (t >= t0 + dur) return (x1, 0);
  return (x0 + d.sign * v * (t - t0), d.sign);
}

double _arr(double t0, double x0, double x1, double v) => t0 + (x1 - x0).abs() / v;

TextPainter _tp(String s, TextStyle st, TextDirection d) =>
    TextPainter(text: TextSpan(text: s, style: st), textDirection: d)..layout();

// ─────────────────────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────────────────────

class TitleSplitSlide extends StatefulWidget {
  const TitleSplitSlide({super.key});

  @override
  State<TitleSplitSlide> createState() => _TitleSplitSlideState();
}

class _TitleSplitSlideState extends State<TitleSplitSlide>
    with SingleTickerProviderStateMixin {
  final _clock = _Clock();
  late _Kit _kit;
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _kit = _Kit.build()..scan();
    PaintingBinding.instance.systemFonts.addListener(_onFonts);
    _ticker = createTicker(_tick)..start();
  }

  /// On the web a fallback font (Devanagari, Thai) may arrive later: rebuild
  /// every cached paragraph and re-measure the real ink.
  void _onFonts() {
    final old = _kit;
    setState(() => _kit = _Kit.build()..scan());
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  void _tick(Duration e) {
    var dt = (e - _last).inMicroseconds / 1e6;
    _last = e;
    if (dt < 0 || dt > 0.1) dt = 1 / 60;
    _clock.advance(dt);
  }

  @override
  void dispose() {
    _ticker.dispose();
    PaintingBinding.instance.systemFonts.removeListener(_onFonts);
    _kit.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: MouseRegion(
            onHover: (e) => _clock.pointer = e.localPosition,
            onExit: (_) => _clock.pointer = null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) =>
                  d.localPosition.dx < _divX ? _clock.wake() : _clock.hurry(),
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _ScenePainter(_clock, _kit),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 596,
          child: IgnorePointer(
            child: Column(
              children: [
                Reveal(
                  visible: true,
                  delay: const Duration(milliseconds: 300),
                  child: Text(
                    'Text rendering',
                    style: BT.display(124, letterSpacing: -3, height: 1),
                  ),
                ),
                const SizedBox(height: 22),
                Reveal(
                  visible: true,
                  delay: const Duration(milliseconds: 650),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 36, height: 1.5, color: BP.amber),
                      const SizedBox(width: 14),
                      Text(
                        'from code points to pixels · and how Flutter does it',
                        style: BT.mono(20, color: BP.inkDim),
                      ),
                      const SizedBox(width: 14),
                      Container(width: 36, height: 1.5, color: BP.amber),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Scene time. Runs faster for a moment after a click on the right half.
class _Clock extends ChangeNotifier {
  double t = 0;
  double real = 0;
  double hurryAt = -99;
  double wakeAt = -99;
  Offset? pointer;

  /// 0..1: how hurried the crew is right now.
  double get rush {
    final a = real - hurryAt;
    if (a < 0 || a > 3.4) return 0;
    return _seg(a, 0, 0.3) * (1 - _seg(a, 2.8, 3.4));
  }

  bool get awake => real - wakeAt >= 0 && real - wakeAt < 1.8;

  void advance(double dt) {
    real += dt;
    t += dt * (1 + 2.4 * rush);
    notifyListeners();
  }

  void hurry() => hurryAt = real - (rush > 0.99 ? 0.3 : 0);

  void wake() => wakeAt = real;
}

// ─────────────────────────────────────────────────────────────────────────────
// Cached text: forms, words, ink scans
// ─────────────────────────────────────────────────────────────────────────────

final _outlinePaint = Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = 1.6
  ..strokeJoin = StrokeJoin.round
  ..color = BP.line;

/// One glyph form drawn "under construction": faint fill + cyan outline.
class _Form {
  _Form(String text, TextStyle base, TextDirection dir)
      : fill = _tp(text, base.copyWith(color: BP.line.withValues(alpha: 0.13)), dir),
        line = _tp(text, base.copyWith(foreground: _outlinePaint), dir) {
    baseline = fill.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  }

  final TextPainter fill;
  final TextPainter line;
  late final double baseline;

  double get width => fill.width;
  double get height => fill.height;

  void paint(Canvas c, double left, double baseY) {
    final o = Offset(left, baseY - baseline);
    fill.paint(c, o);
    line.paint(c, o);
  }

  void dispose() {
    fill.dispose();
    line.dispose();
  }
}

/// The finished word W, and W' = the same word without its mark(s), so that
/// W − W' is exactly the mark as the real shaper positioned it.
class _Word {
  _Word(String text, String minus, TextStyle base, TextDirection dir)
      : solid = _tp(text, base.copyWith(color: BP.ink), dir),
        form = _Form(text, base, dir),
        mSolid = _tp(minus, base.copyWith(color: BP.ink), dir),
        mErase = _tp(
          minus,
          base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5
              ..strokeJoin = StrokeJoin.round
              ..color = BP.ink,
          ),
          dir,
        ),
        mForm = _Form(minus, base, dir) {
    baseline = solid.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  }

  final TextPainter solid;
  final _Form form;
  final TextPainter mSolid;
  final TextPainter mErase;
  final _Form mForm;
  late final double baseline;

  double get width => solid.width;
  double get height => solid.height;

  Rect? box(TextPainter p, int a, int b) {
    final bs = p.getBoxesForSelection(TextSelection(baseOffset: a, extentOffset: b));
    if (bs.isEmpty) return null;
    return bs.map((e) => e.toRect()).reduce((x, y) => x.expandToInclude(y));
  }

  void dispose() {
    solid.dispose();
    form.dispose();
    mSolid.dispose();
    mErase.dispose();
    mForm.dispose();
  }
}

/// What every right-side build shares.
abstract interface class _Stage {
  String get name;
  Color get color;
  List<String> get steps;
  List<(double, double)> get at;
  double get work;
  String get codes;
  Future<void> scan(bool Function() alive);
  void dispose();
}

/// One complex-script build.
class _Sc implements _Stage {
  _Sc({
    required this.name,
    required this.color,
    required this.steps,
    required this.at,
    required this.work,
    required this.size,
    required this.word,
    required this.pre,
    required this.post,
    required this.preX,
    required this.finX,
    required this.rtl,
    required this.codes,
    required this.diff,
    required this.bandTop,
    required this.bandBottom,
  });

  @override
  final String name;
  @override
  final Color color;
  @override
  final List<String> steps;
  @override
  final List<(double, double)> at;
  @override
  final double work;
  final double size;
  final _Word word;
  final List<_Form> pre;
  final List<_Form> post;
  final List<double> preX;
  final List<double> finX;
  final bool rtl;
  @override
  final String codes;

  // Ink measured from real rasterized text (painter coordinates). Estimates
  // until the async scan lands.
  Rect diff;
  double bandTop;
  double bandBottom;
  Float64List? tops;
  List<double> bounds = const [];

  double get wl => _rCx - word.width / 2;
  double get ww => word.width;
  double get y0 => _gy - word.baseline;
  Rect get diffC => diff.shift(Offset(wl, y0));
  double get bandTopC => y0 + bandTop;
  double get bandBottomC => y0 + bandBottom;

  /// Canvas y of the highest ink of W' between canvas x [a, b].
  double inkTop(double a, double b, double fallback) {
    final t = tops;
    if (t == null) return fallback;
    var best = double.infinity;
    for (var x = (a - wl).floor(); x <= (b - wl).ceil(); x++) {
      if (x >= 0 && x < t.length && t[x] < best) best = t[x];
    }
    return best.isFinite ? y0 + best : fallback;
  }

  static String _codes(String s) => s.runes
      .map((r) => 'U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}')
      .join(' ');

  static List<double> _measure(List<String> ss, TextStyle st, TextDirection d) {
    return [
      for (final s in ss)
        (() {
          final p = _tp(s, st, d);
          final w = p.width;
          p.dispose();
          return w;
        })(),
    ];
  }

  factory _Sc.arabic() {
    TextStyle st(double s) => TextStyle(
          fontFamily: BP.arabic,
          fontSize: s,
          color: BP.ink,
          fontVariations: const [FontVariation('wght', 500)],
        );
    const d = TextDirection.rtl;
    final m = _measure(['ں', 'ص'], st(100), d);
    final size = math.min(250.0, (520 - 70) / ((m[0] + m[1]) / 100));
    final base = st(size);
    final word = _Word('نص', 'ٮص', base, d);
    // Visual order, left to right: sad, then noon (RTL).
    final pre = [_Form('ص', base, d), _Form('ں', base, d)];
    final post = [_Form('‍ص', base, d), _Form('ٮ‍', base, d)];
    final wl = _rCx - word.width / 2;
    final bs = word.box(word.mSolid, 1, 2);
    final bn = word.box(word.mSolid, 0, 1);
    final finX = [
      wl + (bs?.left ?? 0),
      wl + (bn?.left ?? word.width - post[1].width),
    ];
    final pairL = _rCx - (pre[0].width + pre[1].width) / 2;
    final preX = [pairL - 35, pairL + pre[0].width + 35];
    final nx = (bn?.center.dx ?? word.width * 0.9);
    return _Sc(
      name: 'arabic',
      color: Script.arabic.color,
      steps: const ['bidi ←', 'joining', 'gsub', 'marks'],
      at: const [(0.2, 2.2), (5.9, 8.4), (9.0, 11.15), (11.2, 13.2)],
      work: 13.8,
      size: size,
      word: word,
      pre: pre,
      post: post,
      preX: preX,
      finX: finX,
      rtl: true,
      codes: _codes('نص'),
      diff: Rect.fromCenter(
        center: Offset(nx, word.baseline - size * 0.62),
        width: size * 0.12,
        height: size * 0.1,
      ),
      bandTop: word.baseline - size * 0.62,
      bandBottom: word.baseline - size * 0.55,
    );
  }

  factory _Sc.deva() {
    TextStyle st(double s) => BT.sample(s, weight: 500);
    const d = TextDirection.ltr;
    const preT = ['ट', 'क्', 'स्', 'ट'];
    const postT = ['ट', 'क्‍', 'स्‍', 'ट'];
    final m = _measure(preT, st(100), d);
    final sum = m.fold(0.0, (a, b) => a + b);
    final size = math.min(236.0, (600 - 36) / (sum / 100));
    final base = st(size);
    final word = _Word('टेक्स्ट', 'टक्स्ट', base, d);
    final pre = [for (final s in preT) _Form(s, base, d)];
    final post = [for (final s in postT) _Form(s, base, d)];
    final wl = _rCx - word.width / 2;
    final sumPost = post.fold(0.0, (a, f) => a + f.width);
    final k = sumPost > 0 ? word.width / sumPost : 1.0;
    final finX = <double>[];
    var acc = wl;
    for (final f in post) {
      finX.add(acc);
      acc += f.width * k;
    }
    final total = pre.fold(0.0, (a, f) => a + f.width) + 3 * 12;
    final preX = <double>[];
    var x = _rCx - total / 2;
    for (final f in pre) {
      preX.add(x);
      x += f.width + 12;
    }
    return _Sc(
      name: 'devanagari',
      color: Script.devanagari.color,
      steps: const ['clusters', 'half forms', 'shirorekha', 'marks'],
      at: const [(0.3, 4.9), (5.2, 9.4), (9.6, 11.8), (12.3, 14.3)],
      work: 14.8,
      size: size,
      word: word,
      pre: pre,
      post: post,
      preX: preX,
      finX: finX,
      rtl: false,
      codes: _codes('टेक्स्ट'),
      diff: Rect.fromLTWH(
        pre[0].width * 0.2,
        word.baseline - size * 0.95,
        pre[0].width * 0.6,
        size * 0.22,
      ),
      bandTop: word.baseline - size * 0.72,
      bandBottom: word.baseline - size * 0.64,
    );
  }

  factory _Sc.thai() {
    TextStyle st(double s) => BT.sample(s, weight: 500);
    const d = TextDirection.ltr;
    final m = _measure(['ขอความ'], st(100), d);
    final size = math.min(180.0, 590 / (m[0] / 100));
    final base = st(size);
    final word = _Word('ข้อความ', 'ขอความ', base, d);
    const letters = ['ข', 'อ', 'ค', 'ว', 'า', 'ม'];
    final forms = [for (final s in letters) _Form(s, base, d)];
    final wl = _rCx - word.width / 2;
    final finX = <double>[];
    var acc = wl;
    for (var i = 0; i < letters.length; i++) {
      final b = word.box(word.mSolid, i, i + 1);
      finX.add(b != null ? wl + b.left : acc);
      acc += forms[i].width;
    }
    final sc = _Sc(
      name: 'thai',
      color: Script.thai.color,
      steps: const ['clusters', 'marks', 'word breaks'],
      at: const [(0.3, 6.2), (6.9, 8.7), (8.4, 12.5)],
      work: 13.0,
      size: size,
      word: word,
      pre: forms,
      post: forms,
      preX: finX,
      finX: finX,
      rtl: false,
      codes: _codes('ข้อความ'),
      diff: Rect.fromLTWH(
        forms[0].width * 0.3,
        word.baseline - size * 0.95,
        forms[0].width * 0.5,
        size * 0.2,
      ),
      bandTop: 0,
      bandBottom: 0,
    );
    // Word boundaries from the real ICU word breaker (Thai has no spaces;
    // the dictionary decides where words start and end).
    final p = word.solid;
    final text = p.plainText;
    final offs = <int>{};
    for (var i = 0; i <= text.length; i++) {
      final r = p.getWordBoundary(TextPosition(offset: i));
      offs
        ..add(r.start)
        ..add(r.end);
    }
    final xs = [
      for (final o in offs.toList()..sort())
        wl + p.getOffsetForCaret(TextPosition(offset: o), Rect.zero).dx,
    ];
    final uniq = <double>[];
    for (final x in xs..sort()) {
      if (uniq.isEmpty || (x - uniq.last).abs() > 4) uniq.add(x);
    }
    sc.bounds = uniq.length >= 2 ? uniq : [wl, wl + word.width];
    return sc;
  }

  /// Rasterizes W' and W − W' once to find the real ink: the mark's box, the
  /// headline band (the row with the most ink) and each column's top.
  @override
  Future<void> scan(bool Function() alive) async {
    const pad = 6;
    final w = word.width.ceil() + 2 * pad;
    final h = word.height.ceil() + 2 * pad;
    const o = Offset(6, 6);
    final bounds = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    // Record both pictures before awaiting (painters may be disposed later).
    final r1 = ui.PictureRecorder();
    word.mSolid.paint(Canvas(r1), o);
    final p1 = r1.endRecording();
    final r2 = ui.PictureRecorder();
    final c2 = Canvas(r2)..saveLayer(bounds, Paint());
    word.solid.paint(c2, o);
    c2.saveLayer(bounds, Paint()..blendMode = BlendMode.dstOut);
    word.mSolid.paint(c2, o);
    word.mErase.paint(c2, o);
    c2
      ..restore()
      ..restore();
    final p2 = r2.endRecording();
    try {
      final a = await _pixels(p1, w, h);
      final b = await _pixels(p2, w, h);
      if (a == null || b == null || !alive()) return;
      // Column tops + row coverage of W'.
      final tops = Float64List(w - 2 * pad)..fillRange(0, w - 2 * pad, double.infinity);
      final rows = List<int>.filled(h, 0);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (a.getUint8((y * w + x) * 4 + 3) > 110) {
            rows[y]++;
            final cx = x - pad;
            if (cx >= 0 && cx < tops.length && tops[cx] == double.infinity) {
              tops[cx] = (y - pad).toDouble();
            }
          }
        }
      }
      this.tops = tops;
      var best = 0;
      for (var y = 1; y < h; y++) {
        if (rows[y] > rows[best]) best = y;
      }
      if (rows[best] > 0) {
        var t = best, bb = best;
        while (t > 0 && rows[t - 1] >= rows[best] * 0.6) {
          t--;
        }
        while (bb < h - 1 && rows[bb + 1] >= rows[best] * 0.6) {
          bb++;
        }
        bandTop = (t - pad - 1).toDouble();
        bandBottom = (bb - pad + 2).toDouble();
      }
      // Bounding box of W − W'.
      var x0 = w, y0 = h, x1 = -1, y1 = -1;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (b.getUint8((y * w + x) * 4 + 3) > 60) {
            if (x < x0) x0 = x;
            if (x > x1) x1 = x;
            if (y < y0) y0 = y;
            if (y > y1) y1 = y;
          }
        }
      }
      if (x1 >= x0) {
        diff = Rect.fromLTRB(
          (x0 - pad - 2).toDouble(),
          (y0 - pad - 2).toDouble(),
          (x1 - pad + 3).toDouble(),
          (y1 - pad + 3).toDouble(),
        );
      }
    } finally {
      p1.dispose();
      p2.dispose();
    }
  }

  static Future<ByteData?> _pixels(ui.Picture p, int w, int h) async {
    final img = await p.toImage(w, h);
    try {
      return await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    } finally {
      img.dispose();
    }
  }

  @override
  void dispose() {
    word.dispose();
    for (final f in {...pre, ...post}) {
      f.dispose();
    }
  }
}

/// Japanese: 「縦書き」 (tategaki, "vertical writing"). Built as a horizontal
/// line, broken where the real line breaker breaks it, then hung as
/// vertical-rl columns. locale 'ja' picks Japanese glyph variants (Hiragino on
/// macOS, Noto Sans JP on the web); the bracket swap is the font's own 'vert'.
class _Ja implements _Stage {
  _Ja._(this.s, this.base, this.solid, this.vert, this.vertSolid, this.ruby, this.rubySolid, this.peek, this.brk);

  factory _Ja.build() {
    const s = 96.0;
    const d = TextDirection.ltr;
    TextStyle st(double size, {bool vert = false, Color? color}) => BT.sample(size, weight: 500).copyWith(
          locale: const Locale('ja'),
          color: color,
          fontFeatures: vert ? const [FontFeature.enable('vert')] : null,
        );
    final base = [for (final c in chars) _Form(c, st(s), d)];
    final solid = [for (final c in chars) _tp(c, st(s), d)];
    final vert = [_Form('「', st(s, vert: true), d), _Form('」', st(s, vert: true), d)];
    final vertSolid = [_tp('「', st(s, vert: true), d), _tp('」', st(s, vert: true), d)];
    final ruby = [for (final c in rubyChars) _Form(c, st(s / 2), d)];
    final rubySolid = [for (final c in rubyChars) _tp(c, st(s / 2), d)];
    final peek = [for (final c in const ['字', 'あ', '漢']) _tp(c, st(24, color: BP.inkDim), d)];
    // Where does Flutter (SkParagraph + ICU line breaking) end line 1 at our
    // measure? No break is allowed before 」, so き goes down with it.
    final probe = TextPainter(text: TextSpan(text: chars.join(), style: st(s)), textDirection: d)
      ..layout(maxWidth: s * 4.4);
    final brk = probe.getLineBoundary(const TextPosition(offset: 0)).end.clamp(1, 4);
    probe.dispose();
    return _Ja._(s, base, solid, vert, vertSolid, ruby, rubySolid, peek, brk);
  }

  static const chars = ['「', '縦', '書', 'き', '」'];
  static const rubyChars = ['た', 'て', 'が'];
  static const rubyAt = [1.25, 1.75, 2.5]; // centres, in em from the line start
  static const rubyBase = [1, 1, 2]; // the kanji each ruby kana belongs to
  static const left = 900.0; // line start
  static const rail = 182.0; // top edge of the vertical text frame
  static const x1 = 1090.0; // first column (vertical-rl: the rightmost)
  static const crate = Rect.fromLTWH(1392, 350, 144, 120);

  @override
  final String name = 'japanese';
  @override
  final Color color = Script.kana.color;
  @override
  final List<String> steps = const ['fallback', 'ruby', 'kinsoku', 'vert'];
  @override
  final List<(double, double)> at = const [(0.2, 3.8), (4.2, 8.4), (5.8, 9.6), (9.6, 15.5)];
  @override
  final double work = 15.8;
  @override
  final String codes = 'U+300C U+7E26 U+66F8 U+304D U+300D';

  final double s;
  final List<_Form> base;
  final List<TextPainter> solid;
  final List<_Form> vert; // 「 」 with the 'vert' feature
  final List<TextPainter> vertSolid;
  final List<_Form> ruby;
  final List<TextPainter> rubySolid;
  final List<TextPainter> peek;
  final int brk; // glyphs on line 1, from the real line breaker

  /// Whether the font really swaps 「 / 」 under 'vert' (checked on pixels);
  /// if not, the brackets are turned 90° instead.
  final List<bool> vertWorks = [true, true];

  double get measure => s * 4.4;
  double get emMid => _gy - s / 2;
  double get rubyMid => _gy - s - 3 - s / 4;
  double get x2 => x1 - 1.4 * s;
  int chainOf(int k) => k < brk ? 0 : 1;
  Offset anchor0(int c) => Offset(left + (c == 0 ? 0 : brk) * s, emMid);
  Offset anchorF(int c) => Offset(c == 0 ? x1 : x2, rail);
  Offset slot(int k) => Offset(left + (k + 0.5) * s, emMid);
  Offset rubySlot(int i) => Offset(left + rubyAt[i] * s, rubyMid);

  @override
  Future<void> scan(bool Function() alive) async {
    final pics = <ui.Picture>[];
    for (var i = 0; i < 2; i++) {
      for (final p in [solid[i == 0 ? 0 : 4], vertSolid[i]]) {
        final r = ui.PictureRecorder();
        p.paint(Canvas(r), Offset.zero);
        pics.add(r.endRecording());
      }
    }
    try {
      final w = s.ceil() + 4, h = solid[0].height.ceil() + 4;
      final px = <ByteData?>[];
      for (final p in pics) {
        px.add(await _Sc._pixels(p, w, h));
      }
      if (!alive()) return;
      for (var i = 0; i < 2; i++) {
        final a = px[2 * i], b = px[2 * i + 1];
        if (a == null || b == null) continue;
        var diff = 0;
        for (var j = 3; j < a.lengthInBytes; j += 4) {
          diff += (a.getUint8(j) - b.getUint8(j)).abs();
        }
        vertWorks[i] = diff > 255 * 40;
      }
    } finally {
      for (final p in pics) {
        p.dispose();
      }
    }
  }

  @override
  void dispose() {
    for (final f in [...base, ...vert, ...ruby]) {
      f.dispose();
    }
    for (final p in [...solid, ...vertSolid, ...rubySolid, ...peek]) {
      p.dispose();
    }
  }
}

/// The easy side: "Text", four solid letters and four little blocks.
class _Latin {
  _Latin._(this.size, this.letters, this.blocks, this.slotL, this.slotR, this.baseline);

  factory _Latin.build() {
    const size = 230.0;
    const d = TextDirection.ltr;
    final st = BT.display(size, weight: 500);
    final word = _tp('Text', st, d);
    final left = _lCx - word.width / 2;
    final slotL = <double>[], slotR = <double>[];
    for (var i = 0; i < 4; i++) {
      final b = word.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
      final r = b.isEmpty ? Rect.fromLTWH(i * word.width / 4, 0, word.width / 4, 1) : b.first.toRect();
      slotL.add(left + r.left);
      slotR.add(left + r.right);
    }
    final baseline = word.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    word.dispose();
    return _Latin._(
      size,
      [for (final ch in 'Text'.split('')) _tp(ch, st, d)],
      [for (final ch in 'Text'.split('')) _tp(ch, BT.display(21, color: BP.line, weight: 500), d)],
      slotL,
      slotR,
      baseline,
    );
  }

  final double size;
  final List<TextPainter> letters;
  final List<TextPainter> blocks;
  final List<double> slotL;
  final List<double> slotR;
  final double baseline;

  double slotC(int i) => (slotL[i] + slotR[i]) / 2;

  /// Dashed advance boxes the letters drop into.
  late final Path guides = () {
    final p = Path();
    for (var i = 0; i < 4; i++) {
      p.addPath(
        dashPath(Path()..addRect(Rect.fromLTRB(slotL[i], _gy - size * 0.7, slotR[i], _gy)), dash: 5, gap: 5),
        Offset.zero,
      );
    }
    return p;
  }();

  // ── The (static) plan: who carries what, when. ──
  static const block = 34.0;
  static const stackL = 96.0;
  static const startX = [180.0, 194.0, 208.0];
  static const pick = [0.0, 0.12, 0.24];
  static const leave = [0.16, 0.28, 0.44];
  static const v = 330.0;

  /// Stack spot of block i: 2 × 2, top row T e, bottom row x t.
  Offset stackPos(int i) => Offset(
        stackL + block / 2 + (i % 2) * block,
        _gy - block / 2 - (i < 2 ? block : 0),
      );

  double dropX(int i) => slotC(i) - 14;

  late final List<double> arrive = () {
    final a0 = leave[0] + (dropX(0) - startX[0]) / v;
    final a1 = leave[1] + (dropX(1) - startX[1]) / v;
    final a2 = leave[2] + (dropX(2) - startX[2]) / v;
    final a3 = a2 + 0.14 + (dropX(3) - dropX(2)) / v;
    return [a0, a1, a2, a3];
  }();

  double land(int i) => arrive[i] + 0.24;
  double get done => land(3) + 0.3;

  void dispose() {
    for (final p in [...letters, ...blocks]) {
      p.dispose();
    }
  }
}

class _Kit {
  _Kit(this.latin, this.scripts) {
    var acc = 0.0;
    for (final s in scripts) {
      starts.add(acc);
      acc += s.work + _hold + _tear;
    }
    period = acc;
  }

  factory _Kit.build() => _Kit(_Latin.build(), [_Ja.build(), _Sc.arabic(), _Sc.deva(), _Sc.thai()]);

  final _Latin latin;
  final List<_Stage> scripts;
  final List<double> starts = [];
  late final double period;
  final Map<String, TextPainter> _labels = {};
  bool disposed = false;

  _Cyc cycleAt(double t) {
    final k = (t / period).floor();
    final r = t - k * period;
    var i = scripts.length - 1;
    while (i > 0 && r < starts[i]) {
      i--;
    }
    return (n: k * scripts.length + i, s: i, tau: r - starts[i], work: scripts[i].work);
  }

  TextPainter label(String text, double size, Color color) {
    final key = '$text|$size|${color.toARGB32()}';
    final hit = _labels[key];
    if (hit != null) return hit;
    return _labels[key] = _tp(text, BT.mono(size, color: color), TextDirection.ltr);
  }

  /// Called before painting: keeps the label cache bounded (the counters
  /// create a new string every 0.1 s).
  void beginFrame() {
    if (_labels.length < 400) return;
    for (final p in _labels.values) {
      p.dispose();
    }
    _labels.clear();
  }

  Future<void> scan() => Future.wait([for (final s in scripts) s.scan(() => !disposed)]);

  void dispose() {
    disposed = true;
    latin.dispose();
    for (final s in scripts) {
      s.dispose();
    }
    for (final p in _labels.values) {
      p.dispose();
    }
    _labels.clear();
  }
}

/// A worker standing on the title's ground unless told otherwise.
Worker _w(
  double x,
  double f,
  Pose p, {
  double y = _gy,
  double ph = 0,
  double k = 0,
  bool move = false,
  int id = 0,
  Tool item = Tool.none,
  Offset? aim,
  Offset? rope,
  bool sweat = false,
  double itemT = 0,
}) => Worker(x, f, p, y: y, ph: ph, k: k, move: move, id: id, item: item, aim: aim, rope: rope, sweat: sweat, itemT: itemT);

Paint _stroke(Color c, double w, [double a = 1]) => Paint()
  ..color = c.withValues(alpha: c.a * a)
  ..strokeWidth = w
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

Paint _fill(Color c, [double a = 1]) => Paint()..color = c.withValues(alpha: c.a * a);

// ─────────────────────────────────────────────────────────────────────────────
// The painter
// ─────────────────────────────────────────────────────────────────────────────

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.clock, this.kit) : super(repaint: clock);

  final _Clock clock;
  final _Kit kit;

  late Canvas _c;
  late CrewPainter _k;
  double _time = 0;

  @override
  void paint(Canvas canvas, Size size) {
    if (kit.disposed) return;
    _c = canvas;
    _time = clock.t;
    _k = CrewPainter(canvas, clock.t, flagSplit: _divX);
    kit.beginFrame();
    final cy = kit.cycleAt(clock.t);
    _frame();
    _left(cy);
    _right(cy);
  }

  @override
  bool shouldRepaint(_ScenePainter old) => old.kit != kit;

  // ── small drawing helpers ──────────────────────────────────────────────────

  void _alpha(double a, Rect? bounds, void Function() draw) {
    if (a <= 0.004) return;
    if (a >= 0.996) {
      draw();
      return;
    }
    _c.saveLayer(bounds, Paint()..color = Color.fromRGBO(0, 0, 0, a));
    draw();
    _c.restore();
  }

  void _text(TextPainter p, Offset o) => p.paint(_c, o);

  // ── figures ────────────────────────────────────────────────────────────────

  void _hover(List<Worker> figs) {
    final p = clock.pointer;
    if (p == null) return;
    Worker? best;
    var bd = 22.0;
    for (final g in figs) {
      if (!g.free || g.p == Pose.carry || g.p == Pose.climbCarry || g.p == Pose.shoulder || g.p == Pose.ladder) continue;
      final d = (Offset(g.x, g.y - 16) - p).distance;
      if (d < bd) {
        bd = d;
        best = g;
      }
    }
    best?.wave = true;
  }

  // ── frame: divider, labels ────────────────────────────────────────────────

  static final _dividerPath = dashPath(
    Path()
      ..moveTo(_divX, 44)
      ..lineTo(_divX, 578),
    dash: 7,
    gap: 6,
  );

  void _frame() {
    _c.drawPath(_dividerPath, _stroke(BP.lineDim, 1.2));
    for (final y in [44.0, 578.0]) {
      final d = Path()
        ..moveTo(_divX, y - 5)
        ..lineTo(_divX + 5, y)
        ..lineTo(_divX, y + 5)
        ..lineTo(_divX - 5, y)
        ..close();
      _c
        ..drawPath(d, _fill(BP.paper))
        ..drawPath(d, _stroke(BP.line, 1.2));
    }
  }

  void _tag(double x, String name, Color color, String codes, double cx, double a) {
    _alpha(a, null, () {
      _c.drawRect(Rect.fromLTWH(x, 66, 9, 9), _fill(color));
      _text(kit.label(name, 17, color), Offset(x + 18, 59));
      final cp = kit.label(codes, 13, BP.inkFaint);
      _text(cp, Offset(cx - cp.width / 2, 548));
    });
  }

  /// "27 workers · 14.2 s", right-aligned on [right].
  void _counter(double right, double y, int n, double secs, Color tc, {bool done = false, double fast = 0}) {
    final a = kit.label('$n workers', 22, BP.inkDim);
    final dot = kit.label('·', 22, BP.inkFaint);
    final b = kit.label('${secs.toStringAsFixed(1)} s', 22, tc);
    final w = a.width + dot.width + b.width + 24 + 28;
    var x = right - w;
    _text(a, Offset(x, y));
    x += a.width + 12;
    _text(dot, Offset(x, y));
    x += dot.width + 12;
    _text(b, Offset(x, y));
    x += b.width;
    if (done) _k.check(Offset(x + 12, y + 14), 15, _stroke(BP.green, 2.6));
    if (fast > 0.02 && !done) {
      for (var i = 0; i < 2; i++) {
        final o = Offset(x + 10 + i * 9, y + 14);
        _c.drawPath(
          Path()
            ..moveTo(o.dx, o.dy - 6)
            ..lineTo(o.dx + 7, o.dy)
            ..lineTo(o.dx, o.dy + 6)
            ..close(),
          _fill(BP.coral, fast),
        );
      }
    }
  }

  /// Pipeline steps: faint = pending, amber = happening, green = done.
  void _steps(List<String> steps, List<(double, double)> at, double t, double right, double y, {double a = 1}) {
    final ps = <TextPainter>[];
    for (var i = 0; i < steps.length; i++) {
      final (s, e) = at[i];
      final col = t >= e ? BP.green : (t >= s ? BP.amber : BP.inkFaint);
      ps.add(kit.label(steps[i], 15, col));
    }
    final w = ps.fold(0.0, (acc, p) => acc + p.width) + 26.0 * (ps.length - 1);
    var x = right - w;
    _alpha(a, null, () {
      for (var i = 0; i < ps.length; i++) {
        _text(ps[i], Offset(x, y));
        x += ps[i].width;
        if (i < ps.length - 1) {
          _c.drawCircle(Offset(x + 13, y + 10), 1.6, _fill(BP.inkFaint));
          x += 26;
        }
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LEFT: latin, easy
  // ─────────────────────────────────────────────────────────────────────────

  void _left(_Cyc cy) {
    final L = kit.latin;
    final tau = cy.tau;
    final tearAt = cy.work + _hold;
    final c = _c;

    // Ground + slot guides
    c.drawLine(const Offset(84, _gy), const Offset(770, _gy), _stroke(BP.line, 1.5));
    final tick = _stroke(BP.lineDim, 1);
    for (var x = 90.0; x < 770; x += 20) {
      c.drawLine(Offset(x, _gy), Offset(x, _gy + (x % 100 == 90 ? 7 : 4)), tick);
    }
    final cap = L.size * 0.7;
    c.drawPath(L.guides, _stroke(BP.lineFaint, 1));
    // pallet
    c
      ..drawLine(Offset(_Latin.stackL - 4, _gy - 2), Offset(_Latin.stackL + 2 * _Latin.block + 4, _gy - 2), _stroke(BP.inkDim, 1.4))
      ..drawLine(Offset(_Latin.stackL, _gy - 2), Offset(_Latin.stackL, _gy), _stroke(BP.inkDim, 1.4))
      ..drawLine(Offset(_Latin.stackL + 2 * _Latin.block, _gy - 2), Offset(_Latin.stackL + 2 * _Latin.block, _gy), _stroke(BP.inkDim, 1.4));

    // Straighten event (seeded per cycle)
    final si = (_h(cy.n, 1) * 4).floor().clamp(0, 3);
    final ts = 6.5 + _h(cy.n, 2) * 4.5;
    final amp = (_h(cy.n, 3) < 0.5 ? -1 : 1) * 0.075;
    final hasEvent = ts + 5 < tearAt;
    final leanX = L.slotC(0) + L.size * 0.05 + 6;
    final pushX = amp > 0 ? L.slotR[si] + 9 : L.slotL[si] - 9;
    final tArrive = _arr(ts + 0.5, leanX, pushX, 140);
    double tilt(double t) {
      if (!hasEvent) return 0;
      return amp * _eio(_seg(t, ts, ts + 0.8)) * (1 - _backOut(_seg(t, tArrive + 0.15, tArrive + 0.7)));
    }

    final sitX = L.slotR[3] + 34;
    const napX = 198.0;

    // Worker plans (before teardown)
    Worker plan(int w, double t) {
      final sx = _Latin.startX[w];
      switch (w) {
        case 0: // A: T, then leans on the T checking his watch
          if (t < _Latin.leave[0]) {
            return _w(sx, -1, Pose.reach, id: 100, aim: L.stackPos(0) + const Offset(4, 14));
          }
          final a = L.arrive[0];
          if (t < a) {
            final (x, _) = _go(t, _Latin.leave[0], sx, L.dropX(0), _Latin.v);
            return _w(x, 1, Pose.shoulder, ph: x / 5, move: true, id: 100);
          }
          if (t < a + 0.2) {
            return _w(L.dropX(0), 1, Pose.toss, id: 100, itemT: _eo(_seg(t, a, a + 0.12)));
          }
          final watchEnd = math.max(L.done, a + 1.2);
          if (t < watchEnd) return _w(L.dropX(0), 1, Pose.stand, id: 100);
          if (hasEvent && t >= ts + 0.5) {
            if (t < tArrive) {
              final (x, d) = _go(t, ts + 0.5, leanX, pushX, 140);
              return _w(x, d, Pose.walk, ph: x / 4.5, move: true, id: 100);
            }
            if (t < tArrive + 0.75) {
              return _w(pushX, amp > 0 ? -1 : 1, Pose.push, ph: t * 9, id: 100, sweat: false);
            }
            final back = _arr(tArrive + 0.75, pushX, leanX, 140);
            if (t < back) {
              final (x, d) = _go(t, tArrive + 0.75, pushX, leanX, 140);
              return _w(x, d, Pose.walk, ph: x / 4.5, move: true, id: 100);
            }
          }
          final arrLean = _arr(watchEnd, L.dropX(0), leanX, 120);
          if (t < arrLean) {
            final (x, d) = _go(t, watchEnd, L.dropX(0), leanX, 120);
            return _w(x, d == 0 ? 1 : d, Pose.walk, ph: x / 4.5, move: true, id: 100);
          }
          final watch = (t * 0.23 + 0.1) % 1 < 0.35 ? 1.0 : 0.0;
          return _w(leanX, 1, Pose.lean, k: watch, id: 100);
        case 1: // B: e, then coffee at the far end
          if (t < _Latin.pick[1]) return _w(sx, -1, Pose.stand, id: 101);
          if (t < _Latin.leave[1]) {
            return _w(sx, -1, Pose.reach, id: 101, aim: L.stackPos(1) + const Offset(-4, 14));
          }
          final a = L.arrive[1];
          if (t < a) {
            final (x, _) = _go(t, _Latin.leave[1], sx, L.dropX(1), _Latin.v);
            return _w(x, 1, Pose.shoulder, ph: x / 5 + 1, move: true, id: 101);
          }
          if (t < a + 0.2) {
            return _w(L.dropX(1), 1, Pose.toss, id: 101, itemT: _eo(_seg(t, a, a + 0.12)));
          }
          final arrSit = _arr(a + 0.45, L.dropX(1), sitX, 170);
          if (t < arrSit) {
            final (x, _) = _go(t, a + 0.45, L.dropX(1), sitX, 170);
            return _w(x, 1, t < a + 0.45 ? Pose.stand : Pose.walk, ph: x / 4.5, move: t >= a + 0.45, id: 101);
          }
          return _w(sitX, -1, Pose.coffee, id: 101, item: Tool.cup);
        default: // C: x and t at once, then a nap by the empty pallet
          if (t < _Latin.pick[2]) return _w(sx, -1, Pose.stand, id: 102);
          if (t < _Latin.leave[2]) {
            return _w(sx, -1, Pose.reach, id: 102, aim: L.stackPos(2) + const Offset(10, 4));
          }
          final a2 = L.arrive[2], a3 = L.arrive[3];
          if (t < a2) {
            final (x, _) = _go(t, _Latin.leave[2], sx, L.dropX(2), _Latin.v);
            return _w(x, 1, Pose.carry, ph: x / 5 + 2, move: true, id: 102);
          }
          if (t < a2 + 0.14) return _w(L.dropX(2), 1, Pose.carry, id: 102);
          if (t < a3) {
            final (x, _) = _go(t, a2 + 0.14, L.dropX(2), L.dropX(3), _Latin.v);
            return _w(x, 1, Pose.carry, ph: x / 5 + 2, move: true, id: 102);
          }
          if (t < a3 + 0.2) return _w(L.dropX(3), 1, Pose.carry, id: 102);
          final arrNap = _arr(a3 + 0.6, L.dropX(3), napX, 190);
          if (t < a3 + 0.6) return _w(L.dropX(3), 1, Pose.stand, id: 102);
          if (t < arrNap) {
            final (x, _) = _go(t, a3 + 0.6, L.dropX(3), napX, 190);
            return _w(x, -1, Pose.walk, ph: x / 4.5, move: true, id: 102);
          }
          return _w(napX, -1, Pose.lie, id: 102);
      }
    }

    final figs = <Worker>[];
    for (var w = 0; w < 3; w++) {
      if (tau < tearAt) {
        final g = plan(w, tau);
        if (clock.awake && tau > L.done + 1 && (g.p == Pose.lie || g.p == Pose.coffee || g.p == Pose.lean)) {
          g
            ..p = Pose.stand
            ..alarm = true
            ..item = Tool.none
            ..f = (clock.pointer?.dx ?? 900) > g.x ? 1 : -1;
        }
        figs.add(g);
      } else {
        final g0 = plan(w, tearAt - 1e-3);
        final tt = tau - tearAt;
        final sx = _Latin.startX[w];
        final (x, d) = _go(tt, 0.25, g0.x, sx, 330);
        figs.add(_w(x, d == 0 ? (tt < 0.25 ? g0.f : 1) : d, d == 0 ? Pose.stand : Pose.run, ph: x / 6, move: d != 0, id: 100 + w));
      }
    }

    // Letters & blocks
    final bs = _Latin.block;
    void blockAt(int i, Offset center, [double a = 1]) {
      final r = Rect.fromCenter(center: center, width: bs, height: bs);
      _alpha(a, r.inflate(4), () {
        c
          ..drawRect(r, _fill(BP.paper))
          ..drawPath(dashPath(Path()..addRect(r), dash: 4, gap: 3), _stroke(BP.line, 1.2));
        final p = L.blocks[i];
        _text(p, center - Offset(p.width / 2, p.height / 2));
      });
    }

    for (var i = 0; i < 4; i++) {
      final land = L.land(i);
      final toss = L.arrive[i];
      final w = i == 0 ? 0 : (i == 1 ? 1 : 2);
      final back0 = tearAt + 0.1 + 0.1 * i;
      final backT = _seg(tau, back0, back0 + 0.55);
      // Where the block rides while carried (analytic hand positions).
      Offset carried(double t) {
        final g = figs[w];
        if (tau >= tearAt) return L.stackPos(i);
        if (w == 2) {
          final top = i == 2;
          return Offset(g.x, _gy - 13 - 9.5 - 9.4 - bs / 2 - (top ? bs : 0));
        }
        return Offset(g.x + g.f * 1.2, _gy - 13 - 9.5 - 7.5 - bs / 2);
      }

      final slot = Offset(L.slotC(i), _gy - bs / 2);
      if (tau >= tearAt && backT > 0) {
        // Letter shrinks back into its block and hops home.
        final e = _eio(backT);
        final from = Offset(L.slotC(i), _gy);
        final to = L.stackPos(i) + Offset(0, bs / 2);
        final p = Offset.lerp(from, to, e)! + Offset(0, -math.sin(e * math.pi) * 90);
        if (e < 0.35) {
          final s = _lerp(1, bs * 0.62 / L.size, e / 0.35);
          _letter(i, p, s, 0);
        } else {
          blockAt(i, p - Offset(0, bs / 2));
        }
        continue;
      }
      if (tau < _Latin.pick[w] || (tau >= tearAt && backT >= 1)) {
        blockAt(i, L.stackPos(i));
      } else if (tau < _Latin.leave[w]) {
        final e = _eio(_seg(tau, _Latin.pick[w], _Latin.leave[w]));
        blockAt(i, Offset.lerp(L.stackPos(i), carried(tau), e)!);
      } else if (tau < toss) {
        blockAt(i, carried(tau));
      } else if (tau < land) {
        final e = _seg(tau, toss, land);
        final from = w == 2
            ? Offset(L.dropX(i), _gy - 13 - 9.5 - 9.4 - bs / 2 - (i == 2 ? bs : 0))
            : Offset(L.dropX(i) + 1.2, _gy - 13 - 9.5 - 7.5 - bs / 2);
        final p = Offset.lerp(from, slot, e)! + Offset(0, -math.sin(e * math.pi) * 40);
        blockAt(i, p);
      } else {
        final pop = _seg(tau, land, land + 0.3);
        if (pop < 1) {
          final s = _lerp(bs * 0.62 / L.size, 1, _backOut(pop));
          _letter(i, Offset(L.slotC(i), _gy), s, 0);
          _alpha(1 - pop, null, () {
            final r = Rect.fromCenter(center: slot, width: bs, height: bs);
            final big = Rect.fromLTRB(L.slotL[i], _gy - cap, L.slotR[i], _gy);
            c.drawRect(Rect.lerp(r, big, _eo(pop))!, _stroke(BP.amber, 1.4));
          });
          _k.dust(Offset(L.slotC(i), _gy), tau - land, spread: 1.2);
        } else {
          _letter(i, Offset(L.slotC(i), _gy), 1, i == si ? tilt(tau) : 0);
          _k.dust(Offset(L.slotC(i), _gy), tau - land, spread: 1.2);
        }
      }
    }

    _hover(figs);
    _k.drawCrew(figs);

    // Idle details
    for (final g in figs) {
      if (g.p == Pose.lie && !g.wave) _k.zzz(g.head, _time);
    }

    // Counter + steps + label
    final built = math.min(tau, L.done);
    final done = tau >= L.done;
    _counter(_divX - 32, 56, 3, built, done ? BP.green : BP.line, done: done);
    _steps(const ['cmap', 'advance'], [(0, L.land(0)), (L.land(0), L.done)], tau, _divX - 60, 92);
    _tag(96, 'latin', Script.latin.color, 'U+0054 U+0065 U+0078 U+0074', _lCx, 1);
  }

  /// Latin letter i, scaled [s] about its bottom-centre [anchor], tilted [rot].
  void _letter(int i, Offset anchor, double s, double rot) {
    final L = kit.latin;
    final p = L.letters[i];
    _c.save();
    if (rot != 0) {
      final pivot = Offset(rot > 0 ? L.slotR[i] - 4 : L.slotL[i] + 4, _gy);
      _c
        ..translate(pivot.dx, pivot.dy)
        ..rotate(rot)
        ..translate(-pivot.dx, -pivot.dy);
    }
    _c
      ..translate(anchor.dx, anchor.dy)
      ..scale(s);
    p.paint(_c, Offset(-p.width / 2, -L.baseline));
    _c.restore();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RIGHT: complex scripts, hard
  // ─────────────────────────────────────────────────────────────────────────

  void _right(_Cyc cy) {
    final sc = kit.scripts[cy.s];
    final c = _c;
    c.drawLine(const Offset(830, _gy), const Offset(1580, _gy), _stroke(BP.line, 1.5));
    final tick = _stroke(BP.lineDim, 1);
    for (var x = 840.0; x < 1580; x += 20) {
      c.drawLine(Offset(x, _gy), Offset(x, _gy + (x % 100 == 40 ? 7 : 4)), tick);
    }
    final figs = <Worker>[];
    switch (sc) {
      case _Ja ja:
        _japanese(ja, cy, figs);
      case _Sc st when st.name == 'arabic':
        _arabic(st, cy, figs);
      case _Sc st when st.name == 'devanagari':
        _deva(st, cy, figs);
      case _Sc st:
        _thai(st, cy, figs);
    }
    final t = math.min(cy.tau, sc.work);
    final done = cy.tau >= sc.work;
    final len = sc.work + _hold + _tear;
    final la = _seg(cy.tau, 0, 0.5) * (1 - _seg(cy.tau, len - 0.45, len));
    _counter(1540, 56, figs.length + 1, t, done ? BP.green : BP.coral, done: done, fast: clock.rush);
    _steps(sc.steps, sc.at, done ? sc.work + 1 : t, 1512, 92, a: la);
    _tag(832, sc.name, sc.color, sc.codes, _rCx, la);
  }

  // ── shared right-side pieces ──────────────────────────────────────────────

  /// Foreman, surveyor (+ staff), water carrier, two hammerers.
  void _common(
    List<Worker> out,
    _Stage sc,
    _Cyc cy,
    double t, {
    required double left,
    required double right,
    double? laserTo,
    Offset? job,
    double? surveyX,
    double? foremanX,
  }) {
    // Foreman, front row, clipboard; points at whatever is being built.
    {
      final x1 = foremanX ?? left - 8;
      final (x, d) = _go(t, 0.1, _offX, x1, 260);
      final g = _w(x, d != 0 ? d : 1, d != 0 ? Pose.walk : Pose.clipboard,
          y: _fy, ph: x / 4.5, move: d != 0, id: 900, item: Tool.clipboard);
      if (d == 0 && job != null && (t % 3.6) < 1.1) {
        g
          ..p = Pose.point
          ..aim = job
          ..f = job.dx >= x ? 1 : -1;
      }
      out.add(g);
    }
    // Surveyor + theodolite on the baseline, left end.
    final sx = surveyX ?? left - 44;
    final tx = sx + 11;
    final (svx, svd) = _go(t, 0.25, _offX, sx, 270);
    final svArr = _arr(0.25, _offX, sx, 270);
    final surveyor = _w(svx, svd != 0 ? svd : 1, svd != 0 ? Pose.walk : Pose.survey,
        ph: svx / 4.5, move: svd != 0, id: 903, aim: Offset(tx - 2, _gy - 28));
    out.add(surveyor);
    // Staff man, right end (unless a sign pole is the target).
    var target = laserTo;
    if (target == null) {
      final stx = right + 20;
      final (x, d) = _go(t, 0.45, _offX, stx, 240);
      out.add(_w(x, d != 0 ? d : -1, d != 0 ? Pose.walk : Pose.pole,
          ph: x / 4.5, move: d != 0, id: 902, item: Tool.staff));
      target = stx - 2.5;
    }
    // Water carrier (front row), back and forth.
    {
      final a0 = _arr(1.2, _offX, right - 40, 190);
      double x;
      double f;
      if (t < a0) {
        final (xx, _) = _go(t, 1.2, _offX, right - 40, 190);
        x = xx;
        f = -1;
      } else {
        final span = math.max(80.0, right - left - 60);
        final ph = ((t - a0) * 70 / span) % 2;
        x = right - 40 - span * (ph < 1 ? ph : 2 - ph);
        f = ph < 1 ? -1 : 1;
      }
      out.add(_w(x, f, Pose.bucket, y: _fy, ph: x / 4.5, move: true, id: 904, item: Tool.bucket));
    }
    // Hammerers: tapping letters into true.
    for (var j = 0; j < 2; j++) {
      final hx = _lerp(left, right, j == 0 ? 0.3 : 0.74) + 10;
      final (x, d) = _go(t, 1.6 + j * 0.6, _offX, hx, 230);
      final active = t > 5.3 && t < sc.work - 0.6 && ((t * 0.45 + j * 0.5) % 1) < 0.62;
      final g = _w(x, d != 0 ? d : -1, d != 0 ? Pose.walk : (active ? Pose.hammer : Pose.stand),
          ph: d != 0 ? x / 4.5 : t * 9 + j, move: d != 0, id: 905 + j, item: Tool.hammer, sweat: active);
      out.add(g);
      if (active && d == 0) {
        final period = 2 * math.pi / 9;
        final age = ((t * 9 + j - math.pi / 2) / (2 * math.pi) % 1) * period;
        _k.burst(Offset(hx - 11, _gy - 3), age, cy.n * 13 + j * 5 + ((t * 9 + j) / (2 * math.pi)).floor(), n: 5);
      }
    }
    // Theodolite + laser + surveyed baseline.
    final unfold = _seg(t, svArr, svArr + 0.4);
    final tripodA = 1 - _seg(cy.tau, sc.work + _hold, sc.work + _hold + 0.5);
    if (t >= svArr && tripodA > 0) {
      final p = _stroke(BP.inkDim, 1.3, tripodA);
      final apex = Offset(tx, _gy - 21);
      _c
        ..drawLine(apex, Offset(tx - 8 * unfold, _gy), p)
        ..drawLine(apex, Offset(tx + 7 * unfold, _gy), p)
        ..drawLine(apex, Offset(tx + 1, _gy), p)
        ..drawRect(Rect.fromLTWH(tx - 4.5, _gy - 30, 9, 8), _fill(BP.paper, tripodA))
        ..drawRect(Rect.fromLTWH(tx - 4.5, _gy - 30, 9, 8), _stroke(BP.line, 1.2, tripodA))
        ..drawLine(Offset(tx + 4.5, _gy - 27), Offset(tx + 9, _gy - 27), _stroke(BP.line, 1.6, tripodA));
    }
    final la = _seg(t, 3.0, 3.5);
    final lf = 1 - _seg(t, 5.0, 5.4);
    if (la > 0 && lf > 0) {
      final a = Offset(tx + 9, _gy - 27);
      final b = Offset(_lerp(a.dx, target, la), _gy - 27);
      final flick = 0.75 + 0.25 * math.sin(_time * 40);
      _c.drawPath(dashPath(Path()..moveTo(a.dx, a.dy)..lineTo(b.dx, b.dy), dash: 6, gap: 4),
          _stroke(BP.amber, 1.3, lf * flick));
      if (la >= 1) _c.drawCircle(Offset(target, _gy - 27), 2.5, _fill(BP.amber, lf));
    }
    final bl = _seg(t, 3.3, 4.2);
    final bf = 1 - _seg(cy.tau, sc.work, sc.work + 0.8);
    if (bl > 0 && bf > 0) {
      _c.drawLine(Offset(left - 10, _gy), Offset(_lerp(left - 10, right + 10, bl), _gy), _stroke(BP.amber, 2, bf));
    }
  }

  /// The tower crane. [load] draws whatever hangs from the hook.
  void _crane(double tx, double hy, {void Function(Offset hook)? load, List<Offset> slings = const [], bool strain = false}) {
    final c = _c;
    final p = _stroke(BP.lineDim, 1.1);
    const m = _mastX;
    const j = _jibY;
    // Mast
    c
      ..drawLine(const Offset(m - 7, _gy), const Offset(m - 7, j), p)
      ..drawLine(const Offset(m + 7, _gy), const Offset(m + 7, j), p);
    var up = true;
    for (var y = _gy; y > j + 14; y -= 16) {
      c.drawLine(Offset(up ? m - 7 : m + 7, y), Offset(up ? m + 7 : m - 7, y - 16), p);
      up = !up;
    }
    // Jib
    c
      ..drawLine(const Offset(_jibTip, j), const Offset(m + 7, j), p)
      ..drawLine(const Offset(_jibTip, j + 14), const Offset(m - 7, j + 14), p)
      ..drawLine(const Offset(_jibTip, j), const Offset(_jibTip, j + 14), p);
    up = true;
    for (var x = _jibTip; x < m - 7; x += 18) {
      c.drawLine(Offset(x, up ? j + 14 : j), Offset(math.min(x + 18, m - 7), up ? j : j + 14), p);
      up = !up;
    }
    // Apex, ties, counter-jib, counterweight
    const apex = Offset(m, j - 38);
    c
      ..drawLine(const Offset(m - 7, j), apex, p)
      ..drawLine(const Offset(m + 7, j), apex, p)
      ..drawLine(apex, const Offset(_jibTip + 140, j), p)
      ..drawLine(apex, const Offset(m + 44, j), p)
      ..drawLine(const Offset(m + 7, j + 10), const Offset(m + 44, j + 10), p)
      ..drawLine(const Offset(m + 44, j), const Offset(m + 44, j + 10), p)
      ..drawRect(const Rect.fromLTWH(m + 24, j + 10, 18, 22), _fill(BP.lineFaint))
      ..drawRect(const Rect.fromLTWH(m + 24, j + 10, 18, 22), p);
    // Cab with its operator
    const cab = Rect.fromLTWH(m - 27, j + 16, 19, 17);
    c
      ..drawRect(cab, _fill(BP.paper))
      ..drawRect(cab, _stroke(BP.line, 1.2));
    final head = Offset(m - 18 + math.sin(_time * 0.7) * 1.5, j + 26);
    c
      ..drawCircle(head, 3.4, CrewInk.headFill)
      ..drawCircle(head, 3.4, CrewInk.headLine)
      ..save()
      ..translate(head.dx, head.dy)
      ..scale(0.9)
      ..drawPath(CrewInk.hatLeft, CrewInk.hatFill)
      ..restore();
    if (strain) {
      for (var j = 0; j < 2; j++) {
        final age = (_time * 1.6 + j * 0.5) % 1;
        c.drawCircle(head + Offset(5 + 8 * age, -3 + 14 * age * age), 1.2, _fill(BP.line, 1 - age));
      }
    }
    // Trolley, cable, hook
    c
      ..drawRect(Rect.fromLTWH(tx - 8, j + 14, 16, 5), _fill(BP.amber))
      ..drawLine(Offset(tx - 1.5, j + 19), Offset(tx - 1.5, hy - 6), _stroke(BP.line, 1))
      ..drawLine(Offset(tx + 1.5, j + 19), Offset(tx + 1.5, hy - 6), _stroke(BP.line, 1))
      ..drawRect(Rect.fromLTWH(tx - 4.5, hy - 7, 9, 7), _fill(BP.paper))
      ..drawRect(Rect.fromLTWH(tx - 4.5, hy - 7, 9, 7), _stroke(BP.line, 1.2))
      ..drawArc(Rect.fromCircle(center: Offset(tx, hy + 3.5), radius: 3.5), -math.pi / 2, math.pi * 1.4, false, _stroke(BP.line, 1.4));
    for (final s in slings) {
      c.drawLine(Offset(tx, hy + 2), s, _stroke(BP.line, 1, 0.8));
    }
    load?.call(Offset(tx, hy));
  }

  /// Draws W − W' (the mark alone), shifted by [d].
  void _diff(_Sc sc, Offset d, {double a = 1}) {
    final r = sc.diffC.shift(d).inflate(8);
    final o = Offset(sc.wl, sc.y0) + d;
    _alpha(a, r, () {
      _c.saveLayer(r, Paint());
      sc.word.form.fill.paint(_c, o);
      sc.word.form.line.paint(_c, o);
      _c.saveLayer(r, Paint()..blendMode = BlendMode.dstOut);
      sc.word.mSolid.paint(_c, o);
      sc.word.mErase.paint(_c, o);
      _c
        ..restore()
        ..restore();
    });
  }

  /// The finished word: the outline is "rasterized" into solid ink by a scan
  /// line in writing direction, then fades out at teardown.
  void _finalWord(_Sc sc, double dd) {
    final u = _eio(_seg(dd, 0.05, 0.8));
    final fade = 1 - _seg(dd, _hold + 0.15, _hold + 0.95);
    final l = sc.wl - 30, r = sc.wl + sc.ww + 30;
    final area = Rect.fromLTRB(l, 60, r, _gy + 90);
    final xs = sc.rtl ? _lerp(r, l, u) : _lerp(l, r, u);
    _alpha(fade, area, () {
      _c
        ..save()
        ..clipRect(sc.rtl ? Rect.fromLTRB(l, 60, xs, _gy + 90) : Rect.fromLTRB(xs, 60, r, _gy + 90));
      sc.word.form.paint(_c, sc.wl, _gy);
      _c
        ..restore()
        ..save()
        ..clipRect(sc.rtl ? Rect.fromLTRB(xs, 60, r, _gy + 90) : Rect.fromLTRB(l, 60, xs, _gy + 90));
      sc.word.solid.paint(_c, Offset(sc.wl, sc.y0));
      _c.restore();
      if (u > 0 && u < 1) {
        _c.drawLine(Offset(xs, _gy - sc.size), Offset(xs, _gy + 12), _stroke(BP.amber, 2));
      }
    });
  }

  /// After the work: celebrate (collapse, cheer, high-five), then run off.
  void _finishCrew(List<Worker> figs, _Cyc cy) {
    final dd = cy.tau - cy.work;
    if (dd < 0) return;
    if (dd < _hold) {
      final order = [for (var i = 0; i < figs.length; i++) i]..sort((a, b) => figs[a].x.compareTo(figs[b].x));
      final paired = <int>{};
      for (var j = 0; j + 1 < order.length; j++) {
        final a = figs[order[j]], b = figs[order[j + 1]];
        if (!a.free || !b.free || paired.contains(order[j])) continue;
        if ((b.x - a.x).abs() < 34 && (b.x - a.x).abs() > 6 && a.y == b.y && _h(cy.n, a.id, 3) < 0.7) {
          final mid = Offset((a.x + b.x) / 2, a.y - 34);
          a
            ..p = Pose.highFive
            ..f = 1
            ..aim = mid
            ..item = a.item == Tool.hammer ? Tool.none : a.item
            ..k = a.id.toDouble();
          b
            ..p = Pose.highFive
            ..f = -1
            ..aim = mid
            ..item = b.item == Tool.hammer ? Tool.none : b.item
            ..k = a.id.toDouble();
          paired
            ..add(order[j])
            ..add(order[j + 1]);
          final clap = (math.sin(_time * 6 + a.id) + 1) / 2;
          if (clap > 0.9) _k.burst(mid, (clap - 0.9) * 2, a.id + cy.n, n: 5, color: BP.green);
        }
      }
      for (final g in figs) {
        if (g.id == 900) {
          // Foreman plants the green flag.
          g
            ..p = Pose.pole
            ..item = Tool.flag
            ..plant = Offset(g.x + g.f * 4.5, g.y)
            ..itemT = _eo(_seg(dd, 0.15, 1.0))
            ..move = false;
        } else if (g.id == 901) {
          g.p = (dd * 0.8) % 1 < 0.5 ? Pose.pole : Pose.wave2;
        }
      }
      for (var i = 0; i < figs.length; i++) {
        final g = figs[i];
        if (!g.free || paired.contains(i) || g.id == 900 || g.id == 901) continue;
        if (dd < 0.15 + 0.8 * _h(cy.n, g.id, 7)) continue;
        final lifted = g.y < _gy - 1 && g.y != _fy;
        final m = (_h(cy.n, g.id, 5) * 4).floor();
        g
          ..move = false
          ..sweat = true;
        if (lifted) {
          g.p = Pose.cheer;
        } else {
          g.p = [Pose.cheer, Pose.lie, Pose.sit, Pose.wipe][m];
          if (g.p == Pose.lie || g.p == Pose.sit) g.item = Tool.none;
        }
      }
    } else {
      final tt = dd - _hold;
      for (final g in figs) {
        if (g.fixed) continue;
        final v = 240 + 90 * _h(cy.n, g.id, 11);
        g
          ..x = g.x + v * tt + 80 * tt * tt
          ..y = g.y < _gy - 1 && g.y != _fy ? _lerp(g.y, _gy, _seg(tt, 0, 0.25)) : g.y
          ..f = 1
          ..p = Pose.run
          ..ph = g.x / 6
          ..move = true
          ..sweat = false
          ..plant = null
          ..rope = null
          ..visor = false;
        if (g.item == Tool.cup) g.item = Tool.none;
        if (g.id == 900) {
          g
            ..item = Tool.flag
            ..itemT = 1;
        }
      }
    }
  }

  // ── Japanese: fallback, ruby, kinsoku, vert ──────────────────────────────

  /// A glyph form centred on its em box at [c].
  void _jaForm(_Form f, Offset c, double size, {double a = 1, double rot = 0}) {
    _alpha(a, Rect.fromCenter(center: c, width: size * 1.7, height: size * 1.7), () {
      _c.save();
      if (rot != 0) {
        _c
          ..translate(c.dx, c.dy)
          ..rotate(rot)
          ..translate(-c.dx, -c.dy);
      }
      f.paint(_c, c.dx - f.width / 2, c.dy + size * 0.38);
      _c.restore();
    });
  }

  void _jaSolid(TextPainter p, Offset c, double size, {double rot = 0}) {
    _c.save();
    if (rot != 0) {
      _c
        ..translate(c.dx, c.dy)
        ..rotate(rot)
        ..translate(-c.dx, -c.dy);
    }
    final base = p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    p.paint(_c, Offset(c.dx - p.width / 2, c.dy + size * 0.38 - base));
    _c.restore();
  }

  /// The font crate: huge, because a CJK font carries tens of thousands of glyphs.
  void _crate(Rect r, {double lid = 0, double a = 1, List<TextPainter> peek = const []}) {
    _alpha(a, r.inflate(90), () {
      final c = _c;
      if (lid > 0.4) {
        for (var i = 0; i < peek.length; i++) {
          final p = peek[i];
          _text(p, Offset(r.left + 28 + i * 38, r.top - p.height * 0.55 + 3 * math.sin(i * 2 + _time * 2.5)));
        }
      }
      c
        ..drawRect(r, _fill(BP.paper))
        ..drawRect(r, _stroke(BP.line, 1.8));
      for (final f in [0.16, 0.84]) {
        c.drawLine(Offset(r.left, r.top + r.height * f), Offset(r.right, r.top + r.height * f), _stroke(BP.lineDim, 1));
      }
      for (final x in [r.left + 7, r.right - 7]) {
        c.drawLine(Offset(x, r.top), Offset(x, r.bottom), _stroke(BP.lineDim, 1));
      }
      final l1 = kit.label('CJK font', 18, BP.ink);
      final l2 = kit.label('U+4E00–9FFF', 11, BP.inkDim);
      _text(l1, Offset(r.center.dx - l1.width / 2, r.center.dy - l1.height + 2));
      _text(l2, Offset(r.center.dx - l2.width / 2, r.center.dy + 6));
      // Two flaps hinged on the outer edges swing UP and open (the left one
      // just past vertical, the right one stopping short of the mast); short
      // enough to stay clear of the ruby lifted out above them.
      final e = _eo(lid);
      final hw = r.width / 2;
      for (final left in [true, false]) {
        c
          ..save()
          ..translate(left ? r.left : r.right, r.top)
          ..rotate(left ? -1.75 * e : 1.45 * e);
        final flap = left ? Rect.fromLTWH(0, -7, hw, 7) : Rect.fromLTWH(-hw, -7, hw, 7);
        c
          ..drawRect(flap, _fill(BP.paper))
          ..drawRect(flap, _stroke(BP.line, 1.6))
          ..restore();
      }
    });
  }

  void _japanese(_Ja ja, _Cyc cy, List<Worker> figs) {
    final tau = cy.tau;
    final t = math.min(tau, ja.work);
    final s = ja.s;
    const crate = _Ja.crate;
    const lowerA = 0.4, landT = 3.0;
    // Each carrier leaves the crate 0.75 s after the previous one, so the
    // glyphs travel ~190 px apart (a glyph is 96 px): a readable train.
    const cs = [3.5, 4.25, 5.0, 5.75, 6.5];
    const cv = 250.0;
    final pickX = crate.left - 8;
    final arr = [for (var k = 0; k < 5; k++) cs[k] + (pickX - ja.slot(k).dx) / cv];
    const plantA = 5.9, breakA = 7.3, flagA = 7.8, kickA = 8.6, kickB = 9.2;
    // vertical-rl: line 2 (き」) becomes the LEFT column, so it is hoisted
    // first and carried over the top; line 1 slides right, then is raised
    // by its head (its tail slides along the ground). Nothing crosses.
    const hoist2 = (9.6, 10.3), trav2 = (10.3, 11.1), swing2 = (11.1, 11.8);
    const slide1 = (10.3, 11.1), raise1 = (12.3, 13.8);
    const liftStart = [10.3, 9.6], liftEnd = [13.8, 11.8];
    const topY = 230.0; // line 2's anchor height while carried over the top
    const raiseA = 13.9, raiseB = 14.3, climbA = 14.3, climbB = 14.9, turnA = 14.9;
    const swapT = [15.3, 15.4];
    final kinsoku = ja.brk < 4;
    final naiveX = _Ja.left + 4 * s;
    final breakX = _Ja.left + ja.brk * s;
    final rubyCx = _Ja.left + 1.875 * s;
    final rubyHook = ja.rubyMid - 46;
    final dd = tau - ja.work;
    final la = 1 - _seg(tau, ja.work + _hold, ja.work + _hold + 0.6);

    // Each line hangs from its start (the anchor) and turns into a column,
    // glyphs staying upright. (anchor, rotation) of chain c at time [at].
    (Offset, double) chain(int c, double at) {
      final a0 = ja.anchor0(c), af = ja.anchorF(c);
      if (c == 1) {
        // Hoisted flat, carried over the top, then let go at the tail: it
        // swings down (a little past vertical) into the left column.
        if (at <= hoist2.$1) return (a0, 0.0);
        final up = _eio(_seg(at, hoist2.$1, hoist2.$2));
        final tr = _seg(at, trav2.$1, trav2.$2);
        final sw = _seg(at, swing2.$1, swing2.$2);
        final x = _lerp(a0.dx, af.dx, _eio(tr));
        final y = _lerp(_lerp(a0.dy, topY, up), af.dy, _eio(sw));
        final sway = 0.035 * math.sin(_time * 3.1) * math.sin(math.pi * tr);
        return (Offset(x, y), math.pi / 2 * _backOut(sw) + sway);
      }
      // Line 1: slides right, then its head is raised; the tail stays on
      // the ground, like standing up a beam.
      final x = _lerp(a0.dx, af.dx, _eio(_seg(at, slide1.$1, slide1.$2)));
      final u = _seg(at, raise1.$1, raise1.$2);
      if (u <= 0) return (Offset(x, a0.dy), 0.0);
      final th = math.pi / 2 * _eio(u) + 0.03 * math.sin(_time * 4.2) * math.sin(math.pi * u);
      return (Offset(x, a0.dy - (a0.dy - af.dy) * math.sin(th)), th);
    }

    Offset rot(Offset a, double th, Offset off) =>
        a + Offset(off.dx * math.cos(th) - off.dy * math.sin(th), off.dx * math.sin(th) + off.dy * math.cos(th));
    Offset placed(int k, double at) {
      final c = ja.chainOf(k);
      final (a, th) = chain(c, at);
      return rot(a, th, ja.slot(k) - ja.anchor0(c));
    }

    Offset rubyPlaced(int i, double at) {
      final c = ja.chainOf(_Ja.rubyBase[i]);
      final (a, th) = chain(c, at);
      return rot(a, th, ja.rubySlot(i) - ja.anchor0(c));
    }

    final open0 = placed(0, 99), close0 = placed(4, 99);
    // Where each ladder worker's wrench meets its bracket (both climb from
    // the left: one in the gap between the columns, one left of column 2).
    final aims = [open0 + const Offset(-26, 8), close0 + const Offset(-34, -4)];

    // ── crew ──
    // Crate guides on tag lines, a signaller in the front row.
    final crateBottom = _lerp(330, _gy, _eio(_seg(t, lowerA, landT)));
    final crateR = Rect.fromLTRB(crate.left, crateBottom - crate.height, crate.right, crateBottom);
    for (var j = 0; j < 3; j++) {
      final st = [1366.0, 1380.0, 1548.0][j];
      final f = j < 2 ? 1.0 : -1.0;
      final (x, d) = _go(t, j * 0.2, _offX, st, 280);
      final on = d == 0 && t < landT;
      final g = _w(x, d != 0 ? d : f, d != 0 ? Pose.walk : (on ? Pose.pull : (t < landT + 0.9 && j == 0 ? Pose.reach : Pose.wipe)),
          ph: d != 0 ? x / 4.5 : t * 6 + j, move: d != 0, id: 70 + j, sweat: t < landT + 1.5,
          rope: on ? (j < 2 ? crateR.bottomLeft + const Offset(4, -6) : crateR.bottomRight + const Offset(-4, -6)) : null,
          aim: crate.topLeft + const Offset(20, -6));
      figs.add(g);
    }
    {
      final sx = t < 6.0 ? 1470.0 : _lerp(1470, rubyCx + 34, _eio(_seg(t, 6.0, 7.0)));
      final (x, d) = _go(t, 0.3, _offX, 1470, 280);
      final on = (t > 0.8 && t < landT) || (t > 7.1 && t < 8.3);
      final moving = t > 6.0 && t < 7.0;
      figs.add(_w(d != 0 ? x : sx, d != 0 ? d : -1, d != 0 || moving ? Pose.walk : (on ? Pose.signal : Pose.stand),
          y: _fy, ph: t * 6, move: d != 0 || moving, id: 73));
    }
    // Carriers: one glyph each, unpacked from the font crate.
    for (var k = 0; k < 5; k++) {
      final slot = ja.slot(k);
      final (xIn, dIn) = _go(t, cs[k] - 1.3, _offX, pickX, 260);
      Worker g;
      if (t < cs[k]) {
        g = _w(xIn, dIn != 0 ? dIn : -1, dIn != 0 ? Pose.walk : Pose.carry, ph: xIn / 4.5, move: dIn != 0, id: 74 + k);
      } else if (t < arr[k] + 0.5) {
        final x = t < arr[k] ? pickX - cv * (t - cs[k]) : slot.dx;
        g = _w(x, -1, Pose.carry, ph: x / 4.2 + k, move: t < arr[k], id: 74 + k, sweat: true,
            k: math.sin(math.pi * _seg(t, arr[k], arr[k] + 0.5)) * 0.9);
        g.free = false;
      } else {
        final e = _eio(_seg(t, arr[k] + 0.5, arr[k] + 1.3));
        final rx = slot.dx + (k.isEven ? -18 : 18);
        final rest = [Pose.wipe, Pose.sit, Pose.stand, Pose.wipe, Pose.signal][(k + cy.n) % 5];
        g = _w(_lerp(slot.dx, rx, e), k.isEven ? 1 : -1, e < 1 ? Pose.walk : rest,
            y: _lerp(_gy, _fy, e), ph: t * 7 + k, move: e < 1, id: 74 + k, sweat: true);
      }
      figs.add(g);
    }
    // Kinsoku crew: the measure post, a naive line break, the inspector.
    final postX = _Ja.left + ja.measure;
    {
      final (x, d) = _go(t, 4.3, _offX, postX + 12, 250);
      final e = _eio(_seg(t, plantA + 0.6, plantA + 1.4));
      final ham = t > plantA && t < plantA + 0.45;
      figs.add(_w(x + 10 * e, d != 0 ? d : -1, d != 0 ? Pose.walk : (ham ? Pose.hammer : (e > 0 && e < 1 ? Pose.walk : Pose.stand)),
          y: _lerp(_gy, _fy, e), ph: ham ? t * 12 : x / 4.5, move: d != 0 || (e > 0 && e < 1), id: 80,
          item: t < plantA ? Tool.staff : Tool.hammer));
      if (ham) {
        _k.burst(Offset(postX, _gy - 4), (t - plantA) % 0.22, cy.n * 3 + 1, n: 4);
      }
    }
    {
      final st = naiveX - 16;
      final (x, d) = _go(t, 5.7, _offX, st, 260);
      final ham = t > breakA && t < breakA + 0.45;
      final shamed = kinsoku && t > flagA;
      figs.add(_w(x, d != 0 ? d : 1, d != 0 ? Pose.walk : (ham ? Pose.hammer : (shamed ? Pose.wipe : Pose.stand)),
          ph: ham ? t * 12 : x / 4.5, move: d != 0, id: 81, item: Tool.hammer, sweat: shamed));
      if (ham) _k.burst(Offset(naiveX, _gy - 4), (t - breakA) % 0.22, cy.n * 3 + 2, n: 4);
    }
    {
      final st = naiveX + 38;
      final (x, d) = _go(t, 5.0, _offX, st, 250);
      Worker g;
      if (d != 0) {
        g = _w(x, d, Pose.walk, ph: x / 4.5, move: true, id: 82);
      } else if (kinsoku && t > flagA && t < kickA - 0.25) {
        g = _w(st, -1, Pose.point, id: 82, item: Tool.redFlag, aim: Offset(naiveX, _gy - 110));
        g.alarm = true;
      } else if (kinsoku && t >= kickA - 0.25 && t < kickA) {
        final (xx, _) = _go(t, kickA - 0.25, st, naiveX + 16, 120);
        g = _w(xx, -1, Pose.walk, ph: xx / 4.5, move: true, id: 82);
      } else if (kinsoku && t >= kickA && t < kickA + 0.4) {
        g = _w(naiveX + 16, -1, Pose.kick, id: 82, k: math.sin(math.pi * _seg(t, kickA, kickA + 0.4)));
      } else {
        g = _w(t > kickA ? naiveX + 16 : st, -1, Pose.clipboard, id: 82, item: Tool.clipboard);
      }
      figs.add(g);
    }
    // Rope team (front row, in front of the crate): a tag line on line 2's
    // tail while it is hoisted, then they haul line 1 to the right and hold
    // its tail while it is stood up.
    for (var j = 0; j < 3; j++) {
      final back = 26 * _eio(_seg(t, slide1.$1, slide1.$2));
      final st = 1398.0 + j * 24;
      final (x, d) = _go(t, 7.8 + j * 0.2, _offX, st, 240);
      Offset? rope;
      if (d == 0) {
        if (t > hoist2.$1 && t < hoist2.$2 - 0.05) {
          rope = placed(4, t) + Offset(s * 0.3, s * 0.2);
        } else if ((t > slide1.$1 - 0.1 && t < slide1.$2) || (t > raise1.$1 && t < raise1.$2)) {
          rope = placed(ja.brk - 1, t) + Offset(s * 0.3, s * 0.2);
        }
      }
      final hauling = rope != null && t > slide1.$1 - 0.1 && t < slide1.$2;
      figs.add(_w(x + (d == 0 ? back : 0), d != 0 ? d : -1, d != 0 ? Pose.walk : (rope != null ? Pose.pull : Pose.stand),
          y: _fy, ph: d != 0 ? x / 4.5 : t * (hauling ? 9 : 6) + j, move: d != 0, id: 84 + j, rope: rope, sweat: rope != null));
    }
    // Ladder crews: GSUB 'vert' swaps each bracket for its vertical form.
    for (var j = 0; j < 2; j++) {
      final aim = aims[j];
      final foot = j == 0 ? Offset(aim.dx - 72, _gy) : Offset(aim.dx - 50, _gy);
      final feetY = aim.dy + 24;
      final top = Offset(j == 0 ? aim.dx - 24 : aim.dx - 14, aim.dy - 24);
      final u = ((_gy - feetY) / (_gy - top.dy)).clamp(0.0, 1.0);
      final feet = Offset(_lerp(foot.dx, top.dx, u) + 2, feetY);
      final (x, d) = _go(t, j == 0 ? 11.4 : 11.1, _offX, foot.dx + 16, 280);
      final r = _eio(_seg(t, raiseA, raiseB));
      Worker g;
      if (t < climbA) {
        g = _w(x, d != 0 ? d : -1, d != 0 || r <= 0 ? Pose.ladder : Pose.push, ph: x / 4.5, move: d != 0, id: 87 + j, sweat: r > 0);
      } else {
        final up = _eio(_seg(t, climbA, climbB));
        final p = Offset.lerp(Offset(foot.dx + 3, _gy), feet, up)!;
        final on = t > turnA && t < swapT[j];
        g = _w(p.dx, 1, on ? Pose.wrench : (up < 1 ? Pose.climb : Pose.cheer), y: p.dy, ph: on ? t * 6 : up * 16,
            id: 87 + j, item: Tool.wrench, aim: on ? aim : null, sweat: on);
      }
      g.free = t > swapT[j];
      figs.add(g);
      if (r <= 0) {
        if (x < 1640) _k.ladder(Offset(x - 32, _gy - 27), Offset(x + 30, _gy - 27), a: la);
      } else {
        _k.ladder(foot, Offset.lerp(foot + Offset(j == 0 ? -70 : 70, -4), top, r)!, a: la);
      }
    }
    final job = t < landT
        ? crateR.center
        : t < arr[0] + 0.5
            ? ja.slot(0)
            : t < kickB
                ? Offset(naiveX, _gy - 60)
                : t < raise1.$2
                    ? placed(t < swing2.$2 ? 3 : 0, t)
                    : aims[0];
    _common(figs, ja, cy, t, left: _Ja.left, right: crate.left - 10, laserTo: crate.left, job: job, surveyX: 838, foremanX: 1252);

    _finishCrew(figs, cy);
    _hover(figs);

    // ── crane ──
    double tx;
    double hy;
    final a1 = ja.anchor0(1);
    if (t < landT) {
      tx = crate.center.dx + (t > lowerA ? 1.3 * math.sin(_time * 31) : 0);
      hy = crateR.top - 26;
    } else if (t < 9.0) {
      tx = _lerp(crate.center.dx, rubyCx, _eio(_seg(t, 6.0, 7.0)));
      hy = _lerp(crate.top - 26, _hookHome, _eio(_seg(t, landT + 0.05, landT + 0.8)));
      if (t > 4.2) hy = _lerp(_hookHome, crate.top + 4, _eio(_seg(t, 4.2, 4.9)));
      if (t > 5.0) hy = _lerp(crate.top + 4, _hookHome, _eio(_seg(t, 5.0, 5.9)));
      if (t > 7.1) hy = _lerp(_hookHome, rubyHook, _eio(_seg(t, 7.1, 8.3)));
      if (t > 8.4) hy = _lerp(rubyHook, _hookHome, _eio(_seg(t, 8.4, 8.9)));
    } else if (t < hoist2.$1) {
      // Over to line 2's start.
      tx = _lerp(rubyCx, a1.dx, _eio(_seg(t, 9.0, 9.35)));
      hy = _lerp(_hookHome, a1.dy - 8, _eio(_seg(t, 9.2, 9.6)));
    } else if (t < swing2.$2) {
      final (a, _) = chain(1, t);
      tx = a.dx;
      hy = a.dy - 8;
    } else if (t < raise1.$1) {
      // Line 2 is on the rail: over to line 1's head (it has slid right).
      final af = ja.anchorF(1);
      final (h, _) = chain(0, t);
      tx = _lerp(af.dx, h.dx, _eio(_seg(t, 11.85, 12.15)));
      hy = _lerp(_lerp(af.dy - 8, _hookHome, _eio(_seg(t, 11.8, 11.95))), h.dy - 8, _eio(_seg(t, 12.0, 12.3)));
    } else if (t < raise1.$2) {
      final (a, _) = chain(0, t);
      tx = a.dx;
      hy = a.dy - 8;
    } else {
      final af = ja.anchorF(0);
      tx = af.dx;
      hy = _lerp(af.dy - 8, _hookHome, _eio(_seg(t, 13.85, 14.3)));
    }
    if (dd > 0) {
      tx = _lerp(tx, _homeX, _eio(_seg(dd, _hold, _hold + 1.4)));
    }
    final crateA = _seg(tau, 0, 0.5) * la;
    final rubyHang = t > 4.9 && t < 8.3;
    final rubyHangAt = [for (var i = 0; i < 3; i++) Offset(tx + (_Ja.rubyAt[i] - 1.875) * s, hy + 46)];
    _crane(tx, hy,
        strain: t > lowerA && t < landT,
        slings: t < landT
            ? [crateR.topLeft + const Offset(12, 0), crateR.topRight + const Offset(-12, 0)]
            : rubyHang
                ? [Offset(tx - 1.2 * s, hy + 12), Offset(tx + 1.0 * s, hy + 12)]
                : const [],
        load: t < landT
            ? (hook) => _crate(crateR, a: crateA)
            : rubyHang
                ? (hook) {
                    _c.drawLine(Offset(tx - 1.2 * s, hy + 12), Offset(tx + 1.0 * s, hy + 12), _stroke(BP.inkDim, 2.4));
                    for (var i = 0; i < 3; i++) {
                      final o = rubyHangAt[i];
                      _c.drawLine(Offset(o.dx, hy + 12), Offset(o.dx, o.dy - s / 4), _stroke(BP.line, 0.8, 0.6));
                      _jaForm(ja.ruby[i], o, s / 2);
                    }
                  }
                : null);
    // A second cable keeps line 2 flat while it is carried; let go, and the
    // line swings down into its column.
    final tailA = _seg(t, hoist2.$1, hoist2.$1 + 0.15) * (1 - _seg(t, swing2.$1, swing2.$1 + 0.12));
    if (tailA > 0) {
      _c.drawLine(Offset(tx + 6, _jibY + 19), placed(4, t) + Offset(s / 2 - 10, -s / 2 + 4),
          _stroke(BP.line, 1.1, 0.85 * tailA));
    }

    // ── the crate, on the ground ──
    if (t >= landT) {
      for (var k = 0; k < 5; k++) {
        if (t > cs[k] - 0.35 && t < cs[k]) {
          final e = _eio(_seg(t, cs[k] - 0.35, cs[k]));
          final from = Offset(crate.center.dx - 30 + 15 * k, crate.top + 50);
          _jaForm(ja.base[k], Offset.lerp(from, Offset(pickX, _gy - _carryLift - s / 2), e)!, s);
        }
      }
      _crate(crate, lid: _seg(t, 3.25, 3.8), a: la, peek: ja.peek);
      _k.dust(Offset(crate.left + 20, _gy), t - landT, spread: 2.2);
      _k.dust(Offset(crate.right - 20, _gy), t - landT, spread: 2.2);
    }

    if (tau < ja.work) {
      // Tofu: the slots before a font that has these characters arrives.
      for (var k = 0; k < 5; k++) {
        final a = 1 - _seg(t, arr[k] + 0.2, arr[k] + 0.5);
        if (a <= 0) continue;
        final r = Rect.fromCenter(center: ja.slot(k), width: s * 0.6, height: s * 0.78);
        final p = _stroke(BP.inkFaint, 1.3, a);
        _c
          ..drawPath(dashPath(Path()..addRect(r), dash: 5, gap: 4), p)
          ..drawLine(r.topLeft, r.bottomRight, p)
          ..drawLine(r.topRight, r.bottomLeft, p);
      }
      // The measure: a post at the line end and a dimension line.
      final pa = 1 - _seg(t, 9.3, 9.8);
      final grow = _eo(_seg(t, plantA, plantA + 0.4));
      if (grow > 0 && pa > 0) {
        final topY = _gy - (_gy - 290) * grow;
        _c.drawPath(dashPath(Path()..moveTo(postX, _gy)..lineTo(postX, topY), dash: 6, gap: 4), _stroke(BP.amber, 1.6, pa));
        final dl = _eio(_seg(t, plantA + 0.4, plantA + 1.0));
        if (dl > 0) {
          const y = 296.0;
          final x0 = _Ja.left, xe = _lerp(_Ja.left, postX, dl);
          final p = _stroke(BP.amber, 1.3, pa);
          _c
            ..drawLine(Offset(x0, y), Offset(xe, y), p)
            ..drawLine(Offset(x0, y - 7), Offset(x0, y + 7), p);
          drawArrowHead(_c, Offset(x0, y), Offset(x0 + 10, y), p, 7);
          if (dl >= 1) drawArrowHead(_c, Offset(postX, y), Offset(postX - 10, y), p, 7);
        }
      }
      // The line break: planted before 」, flagged, kicked back before き.
      final sg = _eo(_seg(t, breakA, breakA + 0.4));
      final sa = 1 - _seg(t, hoist2.$1 - 0.1, hoist2.$1 + 0.3);
      if (sg > 0 && sa > 0) {
        final fly = kinsoku ? _seg(t, kickA + 0.1, kickB) : 0.0;
        final sx = _lerp(naiveX, breakX, _eio(fly));
        final lift2 = math.sin(math.pi * fly) * 70;
        final col = !kinsoku || fly >= 1 ? BP.green : (t > flagA ? BP.red : BP.coral);
        final top = _gy - 128 * sg - lift2;
        final base = _gy + 8 - lift2;
        _c
          ..drawPath(dashPath(Path()..moveTo(sx, base)..lineTo(sx, top), dash: 6, gap: 4), _stroke(col, 2, sa))
          ..drawPath(
            Path()
              ..moveTo(sx, top)
              ..lineTo(sx + 13, top + 5)
              ..lineTo(sx, top + 10)
              ..close(),
            _fill(col, sa),
          );
        if (kinsoku && t > flagA && fly < 0.2) {
          final o = Offset(naiveX, _gy - s * 0.5);
          final p = _stroke(BP.red, 3, sa * (1 - fly * 5));
          _c
            ..drawLine(o + const Offset(-16, -16), o + const Offset(16, 16), p)
            ..drawLine(o + const Offset(16, -16), o + const Offset(-16, 16), p);
        }
        _k.dust(Offset(breakX, _gy), t - kickB, spread: 1);
      }

      // Glyphs.
      for (var k = 0; k < 5; k++) {
        if (t < cs[k]) continue;
        Offset c;
        if (t < arr[k]) {
          c = Offset(pickX - cv * (t - cs[k]), _gy - _carryLift - s / 2);
        } else if (t < arr[k] + 0.5) {
          c = Offset(ja.slot(k).dx, _lerp(_gy - _carryLift - s / 2, ja.emMid, _eio(_seg(t, arr[k], arr[k] + 0.5))));
        } else {
          c = placed(k, t);
        }
        final b = k == 0 ? 0 : (k == 4 ? 1 : -1);
        if (b >= 0 && t > swapT[b] - 0.8) {
          final m = _eio(_seg(t, swapT[b], swapT[b] + 0.35));
          final shake = _seg(t, swapT[b] - 0.8, swapT[b]) * (1 - _seg(t, swapT[b], swapT[b] + 0.02));
          c += Offset(shake * 1.2 * math.sin(_time * 70), 0);
          if (ja.vertWorks[b]) {
            _jaForm(ja.base[k], c, s, a: 1 - m);
            _jaForm(ja.vert[b], c, s, a: m);
          } else {
            _jaForm(ja.base[k], c, s, rot: m * math.pi / 2);
          }
          _k.burst(c, t - swapT[b], cy.n * 11 + b, n: 9);
        } else {
          _jaForm(ja.base[k], c, s);
        }
        _k.dust(Offset(ja.slot(k).dx, _gy), t - arr[k] - 0.5, spread: 1.3);
      }
      if (t >= 8.3) {
        for (var i = 0; i < 3; i++) {
          _jaForm(ja.ruby[i], rubyPlaced(i, t), s / 2);
        }
      }
      // Links along each lifted line; the kinsoku lashing ties き to 」.
      for (var k = 0; k < 4; k++) {
        if (ja.chainOf(k) != ja.chainOf(k + 1)) continue;
        final c = ja.chainOf(k);
        final glue = kinsoku && k == ja.brk && k == 3;
        final shown = glue ? _seg(t, kickB, kickB + 0.4) : _seg(t, liftStart[c] - 0.4, liftStart[c]);
        if (shown <= 0) continue;
        final m = Offset.lerp(placed(k, t), placed(k + 1, t), 0.5)!;
        final col = glue ? BP.green : BP.amber;
        _c
          ..drawCircle(m + const Offset(0, -3), 3.2, _stroke(col, 1.5, shown))
          ..drawCircle(m + const Offset(0, 3), 3.2, _stroke(col, 1.5, shown));
      }
      for (var c = 0; c < 2; c++) {
        _k.burst(ja.anchorF(c), t - liftEnd[c], cy.n * 7 + c, n: 7);
      }
    } else {
      _jaFinal(ja, dd, placed, rubyPlaced);
    }

    // The rail: the top edge of the vertical text frame.
    final ra = _eo(_seg(t, 8.8, 9.4)) * la;
    if (ra > 0) {
      final l = ja.x2 - s / 2 - 22, r = _Ja.x1 + s / 2 + 80;
      final y = _Ja.rail - 3;
      final p = _stroke(BP.line, 2, ra);
      _c
        ..drawLine(Offset(l, y), Offset(_lerp(l, r, ra), y), p)
        ..drawLine(Offset(l + 14, y), Offset(l + 14, _jibY + 14), _stroke(BP.lineDim, 1.2, ra))
        ..drawLine(Offset(r - 14, y), Offset(r - 14, _jibY + 14), _stroke(BP.lineDim, 1.2, ra));
    }
    _k.drawCrew(figs, minX: 812);
  }

  /// Finished: the vertical text is swept into solid ink, top to bottom.
  void _jaFinal(_Ja ja, double dd, Offset Function(int, double) placed, Offset Function(int, double) rubyPlaced) {
    final s = ja.s;
    final u = _eio(_seg(dd, 0.05, 0.8));
    final fade = 1 - _seg(dd, _hold + 0.15, _hold + 0.95);
    final top = _Ja.rail - 10, bottom = _gy + 10;
    final ys = _lerp(top, bottom, u);
    final area = Rect.fromLTRB(830, top - 30, 1400, bottom);
    _alpha(fade, area, () {
      for (final solidPart in [false, true]) {
        _c
          ..save()
          ..clipRect(solidPart ? Rect.fromLTRB(830, top - 30, 1400, ys) : Rect.fromLTRB(830, ys, 1400, bottom));
        for (var k = 0; k < 5; k++) {
          final c = placed(k, 99);
          final b = k == 0 ? 0 : (k == 4 ? 1 : -1);
          if (solidPart) {
            if (b >= 0 && ja.vertWorks[b]) {
              _jaSolid(ja.vertSolid[b], c, s);
            } else {
              _jaSolid(ja.solid[k], c, s, rot: b >= 0 ? math.pi / 2 : 0);
            }
          } else {
            if (b >= 0 && ja.vertWorks[b]) {
              _jaForm(ja.vert[b], c, s);
            } else {
              _jaForm(ja.base[k], c, s, rot: b >= 0 ? math.pi / 2 : 0);
            }
          }
        }
        for (var i = 0; i < 3; i++) {
          final c = rubyPlaced(i, 99);
          solidPart ? _jaSolid(ja.rubySolid[i], c, s / 2) : _jaForm(ja.ruby[i], c, s / 2);
        }
        _c.restore();
      }
      if (u > 0 && u < 1) {
        _c.drawLine(Offset(ja.x2 - s / 2 - 10, ys), Offset(_Ja.x1 + s + 10, ys), _stroke(BP.amber, 2));
      }
    });
  }

  // ── Arabic: bidi, joining, gsub, marks ────────────────────────────────────

  void _arabic(_Sc sc, _Cyc cy, List<Worker> figs) {
    final tau = cy.tau;
    final t = math.min(tau, sc.work);
    final s = sc.size;
    final w = [sc.pre[0].width, sc.pre[1].width];
    final start = sc.preX;
    final touch = [start[0] + 35, start[1] - 35];
    final fin = sc.finX;
    const tin = [0.4, 1.3];
    const v = [190.0, 160.0];
    final arr = [for (var i = 0; i < 2; i++) tin[i] + (_enterX - start[i]) / v[i]];
    const pushA = 6.4, pushB = 8.4;
    const swap = [10.8, 10.0];
    const swapD = 0.35;
    const craneA = 7.4, craneB = 9.4, lowA = 11.2, lowB = 13.2;
    final signX = math.min(start[1] + w[1] + 56, _mastX - 30);
    final joinY = _gy - s * 0.16;

    // ── letters ──
    final left = [0.0, 0.0], lift = [0.0, 0.0], morph = [0.0, 0.0];
    for (var i = 0; i < 2; i++) {
      if (t < arr[i]) {
        left[i] = _enterX - v[i] * math.max(0, t - tin[i]);
        lift[i] = _carryLift;
      } else {
        lift[i] = _carryLift * (1 - _eio(_seg(t, arr[i], arr[i] + 0.6)));
        final pushed = _lerp(start[i], touch[i], _eio(_seg(t, pushA, pushB)));
        morph[i] = _eio(_seg(t, swap[i], swap[i] + swapD));
        left[i] = _lerp(pushed, fin[i], morph[i]);
        final shake = _seg(t, swap[i] - 0.9, swap[i]) * (1 - _seg(t, swap[i], swap[i] + 0.02));
        left[i] += shake * 1.3 * math.sin(tau * 70 + i);
      }
    }

    // ── crew ──
    var id = 0;
    const team = [6, 5];
    for (var i = 0; i < 2; i++) {
      final n = team[i];
      final lowEnd = arr[i] + 0.6;
      for (var j = 0; j < n; j++) {
        final frac = 0.14 + 0.72 * j / (n - 1);
        final pusher = i == 0 ? j < 3 : j >= n - 3;
        final rank = i == 0 ? 2 - j : j - (n - 3);
        final myId = id++;
        if (t < lowEnd) {
          final x = left[i] + w[i] * frac;
          final g = _w(x, -1, Pose.carry,
              ph: x / 4.2 + j * 1.3, move: t < arr[i] && t >= tin[i], id: myId, sweat: t > tin[i] + 1,
              k: math.sin(math.pi * _seg(t, arr[i], lowEnd)) * 0.9);
          g.free = false;
          figs.add(g);
          continue;
        }
        final under = start[i] + w[i] * frac;
        if (pusher) {
          final st = i == 0 ? left[i] - 6 - 10 * rank : left[i] + w[i] + 6 + 10 * rank;
          final stPre = i == 0 ? start[i] - 6 - 10 * rank : start[i] + w[i] + 6 + 10 * rank;
          final (x, d) = _go(t, lowEnd, under, stPre, 150);
          final pushing = t >= pushA - 0.3 && t < pushB;
          final atX = t >= pushA ? (t < swap[i] ? st : stPre + (touch[i] - start[i])) : x;
          figs.add(_w(atX, d != 0 ? d : (i == 0 ? 1 : -1),
              d != 0 ? Pose.walk : (pushing ? Pose.push : (t >= pushB ? Pose.wipe : Pose.stand)),
              ph: d != 0 ? x / 4.5 : t * 8 + j, move: d != 0, id: myId, sweat: pushing || t >= pushB));
        } else {
          final rx = under + (i == 0 ? -12 : 14) + 8 * _h(cy.n, myId);
          final e = _eio(_seg(t, lowEnd, lowEnd + 0.8));
          final x = _lerp(under, rx, e);
          final y = _lerp(_gy, _fy, e);
          final rest = [Pose.wipe, Pose.stand, Pose.signal][(myId + cy.n) % 3];
          figs.add(_w(x, i == 0 ? 1 : -1, e < 1 ? Pose.walk : rest,
              y: y, ph: t * 7 + j, move: e < 1, id: myId, sweat: true));
        }
      }
    }
    // Rope team (front row): ropes around the two letters, heave together.
    final gapC = (start[0] + w[0] + start[1]) / 2;
    final ropeOn = t > pushA - 0.7 && t < pushB + 0.4;
    for (var j = 0; j < 3; j++) {
      final st = gapC + (j - 1) * 22;
      final (x, d) = _go(t, 2.4 + j * 0.2, _offX, st, 210);
      final myId = 30 + j;
      if (d != 0) {
        figs.add(_w(x, d, Pose.walk, y: _fy, ph: x / 4.5, move: true, id: myId));
        continue;
      }
      if (j == 1) {
        figs.add(_w(x, 1, ropeOn ? Pose.signal : Pose.stand, y: _fy, ph: t * 7, id: myId, sweat: ropeOn));
      } else {
        final f = j == 0 ? -1.0 : 1.0;
        final anchor = j == 0 ? Offset(left[0] + w[0] - 6, joinY) : Offset(left[1] + 6, joinY);
        figs.add(_w(x, f, ropeOn ? Pose.pull : Pose.stand, y: _fy, ph: t * 6 + j,
            id: myId, sweat: ropeOn, rope: ropeOn ? anchor : null));
      }
    }
    // Wrench crew: GSUB swaps each isolated form for its contextual form.
    final aims = [
      Offset(left[0] + w[0] * 0.8, _gy - 9),
      Offset(left[1] + w[1] * 0.28, _gy - 9),
    ];
    for (var i = 0; i < 2; i++) {
      final f = i == 0 ? 1.0 : -1.0;
      final st = (i == 0 ? touch[0] + w[0] * 0.8 : touch[1] + w[1] * 0.28) - f * 17;
      final (x, d) = _go(t, 5.2 + i * 0.5, _offX, st, 230);
      final on = t > swap[i] - 1.1 && t < swap[i];
      figs.add(_w(x, d != 0 ? d : f, d != 0 ? Pose.walk : (on ? Pose.wrench : (t > swap[i] ? Pose.wipe : Pose.stand)),
          ph: d != 0 ? x / 4.5 : t * 6, move: d != 0, id: 40 + i, item: Tool.wrench,
          aim: on ? aims[i] : null, sweat: on));
    }
    // Rigger under the crane.
    final dot = sc.diffC;
    {
      final st = dot.center.dx + 34;
      final (x, d) = _go(t, 6.6, _offX, st, 230);
      final on = t > lowA - 0.4 && t < lowB;
      figs.add(_w(x, d != 0 ? d : -1, d != 0 ? Pose.walk : (on ? Pose.signal : Pose.stand),
          ph: d != 0 ? x / 4.5 : t * 5, move: d != 0, id: 45));
    }
    // Flag-bearer: plants the direction sign first (bidi: this run is RTL).
    {
      final (x, d) = _go(t, 0.0, _offX, signX + 7, 230);
      final a0 = _arr(0.0, _offX, signX + 7, 230);
      final g = _w(x, d != 0 ? d : -1, d != 0 ? Pose.walk : Pose.pole,
          ph: x / 4.5, move: d != 0, id: 901, item: Tool.sign);
      if (t >= a0 + 0.35) g.plant = Offset(signX, _gy);
      g.free = true;
      figs.add(g);
    }
    final job = t < 2.4
        ? Offset(signX, _gy - 110)
        : t < pushB
            ? Offset(gapC, joinY)
            : t < swap[0] + 0.3
                ? aims[t < swap[1] ? 1 : 0]
                : dot.center;
    _common(figs, sc, cy, t, left: start[0], right: start[1] + w[1], laserTo: signX, job: job);

    _finishCrew(figs, cy);
    _hover(figs);

    // ── crane: lowers the dot ──
    final dd = tau - sc.work;
    var tx = _lerp(_homeX, dot.center.dx, _eio(_seg(t, craneA, craneB)));
    final hookFinal = dot.top - 12;
    var hy = _lerp(_hookHome, hookFinal, _eio(_seg(t, lowA, lowB)));
    final landed = t >= lowB;
    if (landed) hy = _lerp(hookFinal, _hookHome, _eio(_seg(t, lowB + 0.2, lowB + 1.0)));
    if (dd > 0) tx = _lerp(tx, _homeX, _eio(_seg(dd, _hold, _hold + 1.4)));
    final sway = 3 * math.sin(_time * 1.7) * (1 - _seg(t, lowB - 0.9, lowB - 0.1));
    final dotA = _seg(tau, 0, 0.5);
    _crane(tx, hy,
        slings: landed ? const [] : [dot.topLeft + Offset(tx - dot.center.dx + sway + 3, hy + 12 - dot.top), dot.topRight + Offset(tx - dot.center.dx + sway - 3, hy + 12 - dot.top)],
        load: landed
            ? null
            : (hook) => _diff(sc, Offset(hook.dx - dot.center.dx + sway, hook.dy + 12 - dot.top), a: dotA));

    // ── letters ──
    if (tau < sc.work) {
      for (var i = 0; i < 2; i++) {
        if (left[i] > 1640) continue;
        final by = _gy - lift[i];
        final m = morph[i];
        final r = Rect.fromLTWH(left[i] - 20, 40, w[i] + 60, _gy + 60);
        _alpha(1 - m, r, () => sc.pre[i].paint(_c, left[i], by));
        _alpha(m, r, () => sc.post[i].paint(_c, left[i], by));
        _k.dust(Offset(left[i] + w[i] / 2, _gy), t - arr[i] - 0.6, spread: 2);
        _k.burst(aims[i], t - swap[i], cy.n * 7 + i, n: 9);
      }
      if (landed) {
        _diff(sc, Offset.zero);
        _k.burst(dot.center, t - lowB, cy.n + 77, n: 8, color: BP.green);
      }
      // The lashing where the letters meet.
      final knot = _seg(t, pushB, pushB + 0.3) * (1 - _seg(t, swap[1], swap[1] + 0.3));
      if (knot > 0) {
        final o = Offset(touch[1], joinY);
        _c
          ..drawCircle(o + const Offset(-4, 0), 5, _stroke(BP.amber, 1.5, knot))
          ..drawCircle(o + const Offset(4, 0), 5, _stroke(BP.amber, 1.5, knot));
      }
    } else {
      _finalWord(sc, dd);
    }
    _k.drawCrew(figs, minX: 812);
  }

  // ── Devanagari: clusters, half forms, shirorekha, marks ───────────────────

  void _deva(_Sc sc, _Cyc cy, List<Worker> figs) {
    final tau = cy.tau;
    final t = math.min(tau, sc.work);
    final s = sc.size;
    const n = 4;
    const t0s = [0.3, 1.0, 1.7, 2.4];
    const vs = [205.0, 195.0, 185.0, 175.0];
    const team = [3, 3, 3, 3];
    final wPre = [for (final f in sc.pre) f.width];
    final wPost = [for (final f in sc.post) f.width];
    final arr = [for (var i = 0; i < n; i++) t0s[i] + (_enterX - sc.preX[i]) / vs[i]];
    const weld = [(5.2, 7.0), (5.9, 7.7)]; // pieces 1, 2
    const slideA = 8.0, slideB = 9.4;
    const lowA = 9.6, lowB = 11.8;
    const raiseA = 12.0, raiseB = 12.5;
    const climbA = 12.5, climbB = 13.8, placeA = 13.8, placeB = 14.3;
    final bandT = sc.bandTopC - 2, bandB = sc.bandBottomC + 2;
    final headlineOn = t >= lowB;

    // ── pieces ──
    final left = List<double>.filled(n, 0), lift = List<double>.filled(n, 0), morph = List<double>.filled(n, 0);
    final slide = _eio(_seg(t, slideA, slideB));
    for (var i = 0; i < n; i++) {
      if (t < arr[i]) {
        left[i] = _enterX - vs[i] * math.max(0, t - t0s[i]);
        lift[i] = _carryLift;
      } else {
        lift[i] = _carryLift * (1 - _eio(_seg(t, arr[i], arr[i] + 0.6)));
        left[i] = _lerp(sc.preX[i], sc.finX[i], slide);
      }
      if (i == 1 || i == 2) {
        final sw = weld[i - 1].$2;
        morph[i] = _eio(_seg(t, sw, sw + 0.4));
        final shake = _seg(t, sw - 1.2, sw) * (1 - _seg(t, sw, sw + 0.02));
        left[i] += shake * 1.1 * math.sin(tau * 80 + i);
      }
    }

    // ── crew ──
    var id = 0;
    for (var i = 0; i < n; i++) {
      final lowEnd = arr[i] + 0.6;
      final moveDir = (sc.finX[i] - sc.preX[i]).sign;
      for (var j = 0; j < team[i]; j++) {
        final frac = 0.18 + 0.64 * j / (team[i] - 1);
        final myId = id++;
        if (t < lowEnd) {
          final x = left[i] + wPre[i] * frac;
          final g = _w(x, -1, Pose.carry, ph: x / 4.2 + j * 1.7, move: t < arr[i] && t >= t0s[i],
              id: myId, sweat: t > t0s[i] + 1, k: math.sin(math.pi * _seg(t, arr[i], lowEnd)) * 0.9);
          g.free = false;
          figs.add(g);
          continue;
        }
        final under = sc.preX[i] + wPre[i] * frac;
        if (j < 2 && moveDir != 0) {
          // Pushers on the trailing side: close the gaps once the half forms shrink.
          final behind = moveDir > 0;
          double st(double l, double wd) => behind ? l - 6 - 10 * j : l + wd + 6 + 10 * j;
          final stPre = st(sc.preX[i], wPre[i]);
          final (x, d) = _go(t, lowEnd, under, stPre, 150);
          final pushing = t >= slideA - 0.3 && t < slideB;
          final wd = _lerp(wPre[i], wPost[i], morph[i]);
          final atX = t >= slideA ? st(left[i], wd) : x;
          figs.add(_w(atX, d != 0 ? d : moveDir, d != 0 ? Pose.walk : (pushing ? Pose.push : (t > slideB ? Pose.wipe : Pose.stand)),
              ph: d != 0 ? x / 4.5 : t * 8 + j, move: d != 0, id: myId, sweat: pushing || t > slideB));
        } else {
          final rx = under + 10 * (_h(cy.n, myId) - 0.5);
          final e = _eio(_seg(t, lowEnd, lowEnd + 0.8));
          final rest = [Pose.wipe, Pose.signal, Pose.stand][(myId + cy.n) % 3];
          figs.add(_w(_lerp(under, rx, e), myId.isEven ? 1 : -1, e < 1 ? Pose.walk : rest,
              y: _lerp(_gy, _fy, e), ph: t * 7 + j, move: e < 1, id: myId, sweat: true));
        }
      }
    }
    // Welders: virama + consonant → half form.
    final weldAim = <Offset>[];
    for (var k = 0; k < 2; k++) {
      final i = k + 1;
      final aim = Offset(left[i] + wPre[i] * 0.74, _gy - s * 0.1);
      weldAim.add(aim);
      final st = sc.preX[i] + wPre[i] * 0.74 + 15;
      final (x, d) = _go(t, 1.6 + k * 0.6, _offX, st, 230);
      final on = t > weld[k].$1 && t < weld[k].$2;
      final g = _w(x, d != 0 ? d : -1, d != 0 ? Pose.walk : (on ? Pose.weld : (t > weld[k].$2 ? Pose.wipe : Pose.stand)),
          ph: d != 0 ? x / 4.5 : t * 5, move: d != 0, id: 40 + k, item: Tool.torch, aim: aim, sweat: on);
      g.visor = on;
      figs.add(g);
    }
    // Tag-line riggers (front row) steady the headline.
    final tagOn = t > lowA - 0.3 && t < lowB + 0.2;
    final hookFinal = bandT - 16;
    var hy = _lerp(_hookHome, hookFinal, _eio(_seg(t, lowA, lowB)));
    if (t >= lowB) hy = _lerp(hookFinal, _hookHome, _eio(_seg(t, lowB + 0.3, lowB + 1.1)));
    final dy = headlineOn ? 0.0 : (hy - hookFinal);
    final sway = 2.5 * math.sin(_time * 1.3) * (1 - _seg(t, lowB - 0.8, lowB));
    for (var k = 0; k < 2; k++) {
      final st = k == 0 ? sc.wl + 16 : sc.wl + sc.ww - 16;
      final (x, d) = _go(t, 5.6 + k * 0.4, _offX, st, 220);
      final f = k == 0 ? -1.0 : 1.0;
      final end = Offset(k == 0 ? sc.wl + 8 + sway : sc.wl + sc.ww - 8 + sway, bandB + dy);
      figs.add(_w(x, d != 0 ? d : f, d != 0 ? Pose.walk : (tagOn ? Pose.pull : Pose.stand),
          y: _fy, ph: d != 0 ? x / 4.5 : t * 5 + k, move: d != 0, id: 50 + k,
          rope: tagOn && d == 0 ? end : null, sweat: tagOn));
    }
    // Ladder crew: the vowel sign े goes on top.
    final fx = sc.finX[1] + wPost[1] * 0.55;
    final topC = Offset(sc.finX[0] + wPost[0] * 0.8, bandT + 4);
    final mk = sc.diffC;
    final feetTopY = mk.bottom + 30;
    final uTop = ((_gy - feetTopY) / (_gy - topC.dy)).clamp(0.0, 1.0);
    final feetTop = Offset(_lerp(fx, topC.dx, uTop) + 3, feetTopY);
    {
      // holder carries the ladder in, raises it, holds its foot
      final (x, d) = _go(t, 8.4, _offX, fx + 10, 230);
      final raise = _seg(t, raiseA, raiseB);
      final g = _w(x, d != 0 ? d : -1, d != 0 ? Pose.ladder : (raise > 0 ? Pose.push : Pose.ladder),
          ph: x / 4.5, move: d != 0, id: 60, sweat: raise > 0);
      figs.add(g);
      final la = 1 - _seg(tau, sc.work + _hold, sc.work + _hold + 0.6);
      if (raise <= 0) {
        if (x < 1640) {
          _k.ladder(Offset(x - 32, _gy - 27), Offset(x + 30, _gy - 27), a: la);
        }
      } else {
        final e = _eio(raise);
        final foot = Offset(fx, _gy);
        final flat = Offset(fx - 62, _gy - 4);
        _k.ladder(foot, Offset.lerp(flat, topC, e)!, a: la);
      }
    }
    Offset? matraAt;
    {
      final (x, d) = _go(t, 8.0, _offX, fx + 3, 170);
      final climb = _eio(_seg(t, climbA, climbB));
      final placed = _seg(t, placeA, placeB);
      Worker g;
      if (d != 0 || t < climbA) {
        g = _w(x, d != 0 ? d : -1, Pose.carry, ph: x / 4.2, move: d != 0, id: 61, sweat: true);
      } else {
        final p = Offset.lerp(Offset(fx + 3, _gy), feetTop, climb)!;
        g = _w(p.dx, -1, placed > 0.4 ? Pose.climb : Pose.climbCarry, y: p.dy,
            ph: climb * 18, id: 61, sweat: true);
      }
      g.free = placed >= 1;
      figs.add(g);
      if (placed < 1) {
        final hands = Offset(g.x, g.y - 13 - 9.5 - 9.4 + 4.5 * g.k);
        final carried = Offset(hands.dx - mk.center.dx, hands.dy - mk.bottom);
        matraAt = Offset.lerp(carried, Offset.zero, _eio(placed));
      }
    }
    final job = t < 5
        ? Offset(_rCx, _gy - 60)
        : t < 7.8
            ? weldAim[t < 7.0 ? 0 : 1]
            : t < lowB
                ? Offset(_rCx, bandT)
                : mk.center;
    _common(figs, sc, cy, t, left: sc.preX.first, right: sc.preX.last + wPre.last, job: job);

    _finishCrew(figs, cy);
    _hover(figs);

    // ── crane: the headline bar ──
    final dd = tau - sc.work;
    var tx = _lerp(_homeX, _rCx, _eio(_seg(t, 0.5, 3.0)));
    if (dd > 0) tx = _lerp(tx, _homeX, _eio(_seg(dd, _hold, _hold + 1.4)));
    final barA = _seg(tau, 0, 0.5);
    final band = Rect.fromLTRB(sc.wl - 12, bandT, sc.wl + sc.ww + 12, bandB);
    _crane(tx, hy,
        slings: headlineOn
            ? const []
            : [Offset(sc.wl + 30 + sway + (tx - _rCx), bandT + dy), Offset(sc.wl + sc.ww - 30 + sway + (tx - _rCx), bandT + dy)],
        load: headlineOn
            ? null
            : (hook) => _alpha(barA, null, () {
                  _c
                    ..save()
                    ..translate(sway + (tx - _rCx), dy)
                    ..clipRect(band);
                  sc.word.mForm.paint(_c, sc.wl, _gy);
                  _c.restore();
                }));

    // ── letters ──
    if (tau < sc.work) {
      for (var i = 0; i < n; i++) {
        if (left[i] > 1640) continue;
        final by = _gy - lift[i];
        final r = Rect.fromLTWH(left[i] - 20, 40, wPre[i] + 60, _gy + 60);
        // Letters arrive headless: the shirorekha comes later, by crane.
        _c.save();
        if (!headlineOn) {
          _c.clipPath(Path()
            ..addRect(Rect.fromLTRB(800, 0, 1600, bandT - lift[i]))
            ..addRect(Rect.fromLTRB(800, bandB - lift[i], 1600, 900)));
        }
        _alpha(1 - morph[i], r, () => sc.pre[i].paint(_c, left[i], by));
        if (morph[i] > 0) _alpha(morph[i], r, () => sc.post[i].paint(_c, left[i], by));
        _c.restore();
        _k.dust(Offset(left[i] + wPre[i] / 2, _gy), t - arr[i] - 0.6, spread: 1.4);
      }
      if (headlineOn) {
        _c
          ..save()
          ..clipRect(band);
        sc.word.mForm.paint(_c, sc.wl, _gy);
        _c.restore();
        for (var k = 0; k < 6; k++) {
          _k.burst(Offset(sc.wl + sc.ww * (k + 0.5) / 6, bandB), t - lowB - k * 0.05, cy.n * 5 + k, n: 5);
        }
      }
      for (var k = 0; k < 2; k++) {
        if (t > weld[k].$1 && t < weld[k].$2) _k.stream(weldAim[k], _time, cy.n * 3 + k);
      }
      final m = matraAt;
      if (m != null) {
        _diff(sc, m);
      } else {
        _diff(sc, Offset.zero);
        _k.burst(mk.center, t - placeB, cy.n + 91, n: 8, color: BP.green);
      }
    } else {
      _finalWord(sc, dd);
    }
    _k.drawCrew(figs, minX: 812);
  }

  // ── Thai: clusters, marks, word breaks ────────────────────────────────────

  void _thai(_Sc sc, _Cyc cy, List<Worker> figs) {
    final tau = cy.tau;
    final t = math.min(tau, sc.work);
    final n = sc.pre.length; // 6
    final w = [for (final f in sc.pre) f.width];
    const carried = [0, 1, 2, 3, 5];
    const t0s = [0.3, 0.9, 1.5, 2.1, 0, 2.7];
    const vs = [210.0, 200.0, 195.0, 185.0, 0.0, 175.0];
    const team = [3, 2, 3, 2, 0, 3];
    final arr = List<double>.filled(n, 0);
    for (final i in carried) {
      arr[i] = t0s[i] + (_enterX - sc.finX[i]) / vs[i];
    }
    const craneA = 0.8, craneB = 2.8, lowA = 4.4, lowB = 6.2;
    const raise1 = (6.0, 6.5), climb1 = (6.9, 8.2), place1 = (8.2, 8.7), down1 = (9.2, 10.2);
    const raise2 = (7.0, 7.4), climb2 = (7.4, 8.6), hammer2 = (8.6, 10.8), down2 = (10.8, 11.8);

    final left = List<double>.filled(n, 0), lift = List<double>.filled(n, 0);
    for (final i in carried) {
      if (t < arr[i]) {
        left[i] = _enterX - vs[i] * math.max(0, t - t0s[i]);
        lift[i] = _carryLift;
      } else {
        left[i] = sc.finX[i];
        lift[i] = _carryLift * (1 - _eio(_seg(t, arr[i], arr[i] + 0.6)));
      }
    }

    // ── crew: carriers ──
    var id = 0;
    for (final i in carried) {
      final lowEnd = arr[i] + 0.6;
      for (var j = 0; j < team[i]; j++) {
        final frac = team[i] == 2 ? (j == 0 ? 0.25 : 0.75) : 0.18 + 0.32 * j;
        final myId = id++;
        if (t < lowEnd) {
          final x = left[i] + w[i] * frac;
          final g = _w(x, -1, Pose.carry, ph: x / 4.2 + j * 1.7, move: t < arr[i] && t >= t0s[i],
              id: myId, sweat: t > t0s[i] + 1, k: math.sin(math.pi * _seg(t, arr[i], lowEnd)) * 0.9);
          g.free = false;
          figs.add(g);
          continue;
        }
        final under = sc.finX[i] + w[i] * frac;
        final rx = under + 12 * (_h(cy.n, myId) - 0.5);
        final e = _eio(_seg(t, lowEnd, lowEnd + 0.8));
        final rest = [Pose.wipe, Pose.stand, Pose.signal, Pose.sit][(myId + cy.n) % 4];
        figs.add(_w(_lerp(under, rx, e), myId.isEven ? 1 : -1, e < 1 ? Pose.walk : rest,
            y: _lerp(_gy, _fy, e), ph: t * 7 + j, move: e < 1, id: myId, sweat: rest != Pose.stand));
      }
    }
    // ── crane: า arrives from above ──
    final aLeft = sc.finX[4];
    final aForm = sc.pre[4];
    final aCx = aLeft + w[4] / 2;
    var tx = _lerp(_homeX, aCx, _eio(_seg(t, craneA, craneB)));
    final aTop = sc.inkTop(aLeft, aLeft + w[4], _gy - sc.size * 0.55);
    final hookFinal = aTop - 14;
    final hookStart = _hookHome;
    var hy = _lerp(hookStart, hookFinal, _eio(_seg(t, lowA, lowB)));
    final aLanded = t >= lowB;
    if (aLanded) hy = _lerp(hookFinal, _hookHome, _eio(_seg(t, lowB + 0.2, lowB + 1.0)));
    final dd = tau - sc.work;
    if (dd > 0) tx = _lerp(tx, _homeX, _eio(_seg(dd, _hold, _hold + 1.4)));
    final aDy = aLanded ? 0.0 : hy - hookFinal;
    final aSway = 2.6 * math.sin(_time * 1.5) * (1 - _seg(t, lowB - 0.8, lowB));
    {
      final st = aCx + 8;
      final (x, d) = _go(t, 2.2, _offX, st, 220);
      final on = t > lowA - 0.3 && t < lowB;
      figs.add(_w(x, d != 0 ? d : -1, d != 0 ? Pose.walk : (on ? Pose.signal : Pose.stand),
          y: _fy, ph: d != 0 ? x / 4.5 : t * 5, move: d != 0, id: 45));
    }
    // ── ladder 1: the tone mark ้ on ข ──
    final mk = sc.diffC;
    final khTop = sc.inkTop(sc.finX[0], sc.finX[0] + w[0], _gy - sc.size * 0.5);
    final foot1 = Offset(sc.finX[1] + w[1] * 0.55, _gy);
    final top1 = Offset(sc.finX[0] + w[0] * 0.82, khTop + 3);
    final feet1Y = mk.bottom + 30;
    final u1 = ((_gy - feet1Y) / (_gy - top1.dy)).clamp(0.0, 1.0);
    final feet1 = Offset(_lerp(foot1.dx, top1.dx, u1) + 3, feet1Y);
    final la = 1 - _seg(tau, sc.work + _hold, sc.work + _hold + 0.6);
    {
      // two-person ladder team
      final (x, d) = _go(t, 2.8, _offX, foot1.dx + 24, 200);
      final raise = _eio(_seg(t, raise1.$1, raise1.$2));
      figs.add(_w(x - 22, d != 0 ? d : -1, raise > 0 ? Pose.push : Pose.ladder,
          ph: x / 4.5, move: d != 0, id: 60, sweat: true));
      figs.add(_w(x + 22, d != 0 ? d : -1, raise > 0 ? Pose.stand : Pose.ladder,
          ph: x / 4.5 + 2, move: d != 0, id: 62));
      if (raise <= 0) {
        if (x - 40 < 1640) _k.ladder(Offset(x - 40, _gy - 27), Offset(x + 40, _gy - 27), a: la);
      } else {
        _k.ladder(foot1, Offset.lerp(foot1 + const Offset(-80, -4), top1, raise)!, a: la);
      }
    }
    Offset? markAt;
    {
      final (x, d) = _go(t, 3.4, _offX, foot1.dx + 3, 230);
      final up = _eio(_seg(t, climb1.$1, climb1.$2));
      final dn = _eio(_seg(t, down1.$1, down1.$2));
      final placed = _seg(t, place1.$1, place1.$2);
      Worker g;
      if (d != 0 || t < climb1.$1) {
        g = _w(x, d != 0 ? d : -1, Pose.carry, ph: x / 4.2, move: d != 0, id: 61, sweat: true);
      } else if (dn < 1) {
        final p = Offset.lerp(Offset(foot1.dx + 3, _gy), feet1, up * (1 - dn))!;
        g = _w(p.dx, -1, placed > 0.4 ? Pose.climb : Pose.climbCarry, y: p.dy, ph: (up + dn) * 18, id: 61, sweat: true);
      } else {
        final (x2, d2) = _go(t, down1.$2, foot1.dx + 3, foot1.dx + 40, 120);
        final e = _seg(t, down1.$2, down1.$2 + 0.6);
        g = _w(x2, d2 != 0 ? d2 : -1, d2 != 0 ? Pose.walk : Pose.wipe, y: _lerp(_gy, _fy, e), ph: x2 / 4.5, move: d2 != 0, id: 61, sweat: true);
      }
      g.free = t > down1.$2;
      figs.add(g);
      if (placed < 1) {
        final hands = Offset(g.x, g.y - 13 - 9.5 - 9.4);
        final c0 = Offset(hands.dx - mk.center.dx, hands.dy - mk.bottom);
        markAt = Offset.lerp(c0, Offset.zero, _eio(placed));
      }
    }
    // ── ladder 2: a worker trues up the top of ม ──
    final foot2 = Offset(sc.finX[5] - 12, _gy);
    final maTop = sc.inkTop(sc.finX[5], sc.finX[5] + w[5], _gy - sc.size * 0.5);
    final top2 = Offset(sc.finX[5] + w[5] * 0.3, maTop + 3);
    final feet2Y = maTop + 8;
    final u2 = ((_gy - feet2Y) / (_gy - top2.dy)).clamp(0.0, 0.92);
    final feet2 = Offset(_lerp(foot2.dx, top2.dx, u2) - 4, _gy - (_gy - top2.dy) * u2);
    {
      final (x, d) = _go(t, 4.0, _offX, foot2.dx - 4, 220);
      final raise = _eio(_seg(t, raise2.$1, raise2.$2));
      final up = _eio(_seg(t, climb2.$1, climb2.$2));
      final dn = _eio(_seg(t, down2.$1, down2.$2));
      final ham = t > hammer2.$1 && t < hammer2.$2;
      Worker g;
      if (d != 0 || t < climb2.$1) {
        g = _w(x, d != 0 ? d : 1, d != 0 ? Pose.ladder : Pose.push, ph: x / 4.5, move: d != 0, id: 63);
      } else {
        final p = Offset.lerp(Offset(foot2.dx - 4, _gy), feet2, up * (1 - dn))!;
        g = _w(p.dx, 1, ham ? Pose.hammer : Pose.climb, y: p.dy, ph: ham ? t * 10 : (up + dn) * 18,
            id: 63, item: Tool.hammer, sweat: ham);
        if (ham) {
          final period = 2 * math.pi / 10;
          final age = ((t * 10 - math.pi / 2) / (2 * math.pi) % 1) * period;
          _k.burst(Offset(p.dx + 11, p.dy - 3), age, cy.n * 17 + ((t * 10) / (2 * math.pi)).floor(), n: 5);
        }
      }
      g.free = t > down2.$2;
      figs.add(g);
      if (raise <= 0) {
        if (x < 1640) _k.ladder(Offset(x - 30, _gy - 27), Offset(x + 30, _gy - 27), a: la);
      } else {
        _k.ladder(foot2, Offset.lerp(foot2 + const Offset(70, -4), top2, raise)!, a: la);
      }
    }
    // ── word-boundary stakes (ICU dictionary: no spaces in Thai) ──
    final bounds = sc.bounds;
    final stakeT = <double>[];
    {
      var tt = 5.2;
      var x0 = _offX;
      double? sx;
      double sf = -1;
      Pose sp = Pose.walk;
      var moving = false;
      for (var k = 0; k < bounds.length; k++) {
        final bx = bounds[k] - 8;
        final a = _arr(tt, x0, bx, k == 0 ? 250 : 240);
        if (sx == null && t < a) {
          final (x, d) = _go(t, tt, x0, bx, k == 0 ? 250 : 240);
          sx = x;
          sf = d != 0 ? d : 1;
          moving = d != 0;
          sp = moving ? Pose.walk : Pose.stand;
        } else if (sx == null && t < a + 0.6) {
          sx = bx;
          sf = 1;
          sp = Pose.hammer;
        }
        stakeT.add(a + 0.6);
        tt = a + 0.6;
        x0 = bx;
      }
      final g = _w(sx ?? x0, sf, sx == null ? Pose.stand : sp,
          ph: sp == Pose.hammer ? t * 11 : (sx ?? x0) / 4.5, move: moving, id: 70, item: Tool.hammer, sweat: sp == Pose.hammer);
      figs.add(g);
    }
    final lastStake = stakeT.isEmpty ? 0.0 : stakeT.last;
    final job = t < lowB
        ? Offset(aCx, hy + 30)
        : t < place1.$2
            ? mk.center
            : Offset(bounds.last, _gy - 20);
    _common(figs, sc, cy, t, left: sc.wl, right: sc.wl + sc.ww, job: job);

    _finishCrew(figs, cy);
    _hover(figs);

    // ── crane ──
    final aA = _seg(tau, 0, 0.5);
    final aBase = _gy + aDy;
    _crane(tx, hy,
        slings: aLanded ? const [] : [Offset(aLeft + 4 + aSway + (tx - aCx), aTop + aDy), Offset(aLeft + w[4] - 4 + aSway + (tx - aCx), aTop + aDy)],
        load: aLanded ? null : (hook) => _alpha(aA, null, () => aForm.paint(_c, aLeft + aSway + (tx - aCx), aBase)));

    // ── letters, mark, stakes ──
    if (tau < sc.work) {
      for (final i in carried) {
        if (left[i] > 1640) continue;
        sc.pre[i].paint(_c, left[i], _gy - lift[i]);
        _k.dust(Offset(left[i] + w[i] / 2, _gy), t - arr[i] - 0.6, spread: 1.2);
      }
      if (aLanded) {
        aForm.paint(_c, aLeft, _gy);
        _k.dust(Offset(aCx, _gy), t - lowB, spread: 1.2);
      }
      final m = markAt;
      if (m != null) {
        _diff(sc, m);
      } else {
        _diff(sc, Offset.zero);
        _k.burst(mk.center, t - place1.$2, cy.n + 93, n: 8, color: BP.green);
      }
    } else {
      _finalWord(sc, dd);
    }
    final sa = 1 - _seg(tau, sc.work + _hold, sc.work + _hold + 0.6);
    for (var k = 0; k < bounds.length; k++) {
      final g = _eo(_seg(t, stakeT[k] - 0.5, stakeT[k]));
      if (g <= 0) continue;
      final bx = bounds[k];
      final top = _gy - 44 * g;
      _c
        ..drawLine(Offset(bx, _gy + 8), Offset(bx, top), _stroke(sc.color, 2, sa))
        ..drawPath(
          Path()
            ..moveTo(bx, top)
            ..lineTo(bx + 12, top + 5)
            ..lineTo(bx, top + 10)
            ..close(),
          _fill(sc.color, sa * 0.9),
        );
      _k.dust(Offset(bx, _gy), t - stakeT[k], spread: 0.7);
    }
    final br = _eio(_seg(t, lastStake, lastStake + 0.7));
    if (br > 0 && bounds.length >= 2) {
      final y = _gy + 16;
      final a = bounds.first, b = bounds.last;
      _c
        ..drawPath(dashPath(Path()..moveTo(a, y)..lineTo(_lerp(a, b, br), y), dash: 6, gap: 4), _stroke(sc.color, 1.6, sa))
        ..drawLine(Offset(a, y - 5), Offset(a, y + 5), _stroke(sc.color, 1.6, sa));
      if (br >= 1) _c.drawLine(Offset(b, y - 5), Offset(b, y + 5), _stroke(sc.color, 1.6, sa));
    }
    _k.drawCrew(figs, minX: 812);
  }
}
