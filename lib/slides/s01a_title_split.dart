import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../deck/scripts.dart';
import '../deck/theme.dart';
import '../deck/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Title prototype: "easy vs hard".
//
// Left: three relaxed workers drop "Text" into its slots in ~2 s, then idle.
// Right: a crowd shapes the same word in a complex script (Arabic →
// Devanagari → Thai). Every job is a real shaping step, and every letter,
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
const _jibTip = 900.0;
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

/// One complex-script build.
class _Sc {
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

  final String name;
  final Color color;
  final List<String> steps;
  final List<(double, double)> at;
  final double work;
  final double size;
  final _Word word;
  final List<_Form> pre;
  final List<_Form> post;
  final List<double> preX;
  final List<double> finX;
  final bool rtl;
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

  void dispose() {
    word.dispose();
    for (final f in {...pre, ...post}) {
      f.dispose();
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

  factory _Kit.build() => _Kit(_Latin.build(), [_Sc.arabic(), _Sc.deva(), _Sc.thai()]);

  final _Latin latin;
  final List<_Sc> scripts;
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

// ─────────────────────────────────────────────────────────────────────────────
// Workers
// ─────────────────────────────────────────────────────────────────────────────

enum _P {
  stand,
  walk,
  run,
  carry,
  shoulder,
  reach,
  toss,
  push,
  pull,
  hammer,
  wrench,
  weld,
  climb,
  climbCarry,
  sit,
  coffee,
  lie,
  lean,
  cheer,
  highFive,
  wipe,
  signal,
  clipboard,
  pole,
  point,
  survey,
  bucket,
  ladder,
  wave2,
}

enum _I { none, cup, wrench, torch, clipboard, hammer, bucket, sign, flag, staff }

class _Fig {
  _Fig(
    this.x,
    this.f,
    this.p, {
    this.y = _gy,
    this.ph = 0,
    this.k = 0,
    this.move = false,
    this.id = 0,
    this.item = _I.none,
    this.aim,
    this.rope,
    this.sweat = false,
    this.itemT = 0,
  });

  double x;
  double f;
  _P p;
  double y;
  double ph;
  double k;
  bool move;
  int id;
  _I item;
  Offset? aim;
  Offset? rope;
  bool sweat;
  double itemT;
  Offset? plant; // planted pole base (sign / flag)
  bool wave = false;
  bool visor = false;
  bool alarm = false;
  bool free = true; // may celebrate / wave
  bool fixed = false; // never moves (crane operator)

  Offset hip = Offset.zero, neck = Offset.zero, head = Offset.zero;
  Offset hl = Offset.zero, hr = Offset.zero, fl = Offset.zero, fr = Offset.zero;
  Offset el = Offset.zero, er = Offset.zero, kl = Offset.zero, kr = Offset.zero;
}

Offset _ik(Offset a, Offset b, double l1, double l2, Offset hint) {
  final d = b - a;
  final dist = d.distance;
  if (dist < 1e-4) return a + Offset(0, l1);
  final u = d / dist;
  if (dist >= l1 + l2) return a + u * l1;
  final p = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist);
  final h = math.sqrt(math.max(0, l1 * l1 - p * p));
  var n = Offset(-u.dy, u.dx);
  if (n.dx * hint.dx + n.dy * hint.dy < 0) n = -n;
  return a + u * p + n * h;
}

/// Poses a stick figure: feet on (x, y), ~33 px tall with its hard hat.
void _solve(_Fig g, double time) {
  final f = g.f;
  final x = g.x;
  var y = g.y;
  final s = math.sin(g.ph), c = math.cos(g.ph);
  var hipH = 13.0;
  var lean = 0.0;
  var fl = Offset(x - 2.6, y), fr = Offset(x + 2.6, y);
  var kneeHint = Offset(f, -0.15);

  void legs(double stride, double lift) {
    fl = Offset(x + f * stride * s, y - lift * math.max(0, c));
    fr = Offset(x - f * stride * s, y - lift * math.max(0, -c));
    hipH += 0.6 * c.abs() - 0.3;
  }

  switch (g.p) {
    case _P.walk || _P.bucket || _P.ladder:
      legs(4.8, 2.4);
      lean = g.p == _P.bucket ? -0.06 : 0.05;
    case _P.run:
      legs(7.0, 3.6);
      lean = 0.3;
    case _P.carry || _P.shoulder || _P.toss:
      if (g.move) legs(4.2, 2.0);
      hipH -= 4.5 * g.k;
    case _P.push:
      lean = 0.55;
      fl = Offset(x - f * (7.5 - 1.5 * s), y);
      fr = Offset(x + f * 1.5, y - 1.4 * math.max(0, s));
    case _P.pull:
      lean = -0.38;
      fl = Offset(x + f * 5.5, y);
      fr = Offset(x - f * (2.5 + 1.0 * s), y);
    case _P.hammer || _P.weld:
      hipH = 7.5;
      lean = 0.18;
      fl = Offset(x - f * 7, y);
      fr = Offset(x + f * 5, y);
    case _P.climb || _P.climbCarry:
      lean = 0.1;
      fl = Offset(x + f * 1.5, y - 3 * math.max(0, s));
      fr = Offset(x + f * 1.5, y - 3 * math.max(0, -s));
    case _P.sit || _P.coffee:
      hipH = 4.2;
      lean = -0.08;
      fl = Offset(x + f * 10.5, y);
      fr = Offset(x + f * 12.5, y - 0.4);
      kneeHint = const Offset(0, -1);
    case _P.lie:
      hipH = 3.3 + 0.3 * math.sin(time * 1.8 + g.id);
      lean = math.pi / 2;
      fl = Offset(x - f * 12.5, y - 1.2);
      fr = Offset(x - f * 13.2, y - 3.2);
      kneeHint = const Offset(0, -1);
    case _P.lean:
      lean = -0.26;
      fl = Offset(x + f * 5.5, y);
      fr = Offset(x + f * 8.2, y);
    case _P.cheer:
      y -= math.max(0, math.sin(time * 9 + g.id)) * 5;
      fl = Offset(x - 2.8, y + 0.5);
      fr = Offset(x + 2.8, y + 0.5);
    case _P.highFive:
      y -= math.max(0, math.sin(time * 6 + g.k)) * 2.5;
      fl = Offset(x - 2.6, y);
      fr = Offset(x + 2.6, y);
      lean = 0.08;
    case _P.wipe:
      lean = 0.12;
    case _P.survey:
      lean = 0.42;
    case _P.stand ||
        _P.wave2 ||
        _P.reach ||
        _P.wrench ||
        _P.signal ||
        _P.clipboard ||
        _P.pole ||
        _P.point:
      if (g.p == _P.wrench) lean = 0.3;
      if (g.move) legs(4.8, 2.4);
  }

  final hip = Offset(x, y - hipH);
  final dir = Offset(math.sin(lean) * f, -math.cos(lean));
  final neck = hip + dir * 9.5;
  final head = neck + dir * 4.7;

  var hl = neck + const Offset(-2.8, 10.2);
  var hr = neck + const Offset(2.8, 10.2);
  var hintL = Offset(-f * 0.5, 1);
  var hintR = Offset(-f * 0.5, 1);

  switch (g.p) {
    case _P.walk:
      hl = neck + Offset(-f * 3.8 * s, 10.2);
      hr = neck + Offset(f * 3.8 * s, 10.2);
    case _P.run:
      hl = neck + Offset(f * (2 - 4.5 * s), 6.5);
      hr = neck + Offset(f * (2 + 4.5 * s), 6.5);
      hintL = hintR = Offset(-f, 0.6);
    case _P.carry || _P.climbCarry:
      hl = neck + const Offset(-2.6, -9.4);
      hr = neck + const Offset(2.6, -9.4);
      hintL = const Offset(-1, 0.2);
      hintR = const Offset(1, 0.2);
    case _P.shoulder:
      hr = neck + Offset(f * 1.2, -7.5);
      hl = neck + Offset(-f * 3.8 * s * (g.move ? 1 : 0), 10.2);
      hintR = Offset(f, 0.3);
    case _P.reach:
      final a = g.aim ?? neck + Offset(f * 6, -9);
      final d = a - neck;
      hr = neck + d / math.max(1, d.distance) * 11;
      hintR = Offset(f, 0.4);
    case _P.toss:
      final k = g.itemT;
      hr = neck + Offset(f * (1.2 + 8 * k), -7.5 + 2 * k);
      hintR = Offset(f * -0.3, 1);
    case _P.push:
      hl = neck + Offset(f * 9.5, 1.5);
      hr = neck + Offset(f * 9.5, 3.5);
      hintL = hintR = const Offset(0, 1);
    case _P.pull:
      hl = neck + Offset(f * 9.2, 3.5 + 1.2 * s);
      hr = neck + Offset(f * 8.2, 4.5 + 1.2 * s);
      hintL = hintR = const Offset(0, 1);
    case _P.hammer:
      final sw = 0.5 + 0.5 * s;
      final th = _lerp(-2.1, 0.45, sw * sw);
      hr = neck + Offset(f * math.cos(th) * 10.5, math.sin(th) * 10.5);
      hl = neck + Offset(f * 4, 8.5);
      hintR = Offset(-f * 0.3, 1);
    case _P.wrench:
      final a = g.aim ?? neck + Offset(f * 16, 6);
      final ang = -0.5 + 0.55 * s;
      final end = a + Offset(-f * 15 * math.cos(ang), 15 * math.sin(ang));
      hr = end;
      hl = end + Offset(f * 2.8, 0.6);
      hintL = hintR = const Offset(0, 1);
    case _P.weld:
      final a = g.aim ?? neck + Offset(f * 12, 8);
      hr = a - Offset(f * 7, 1);
      hl = hr + Offset(-f * 2, 2);
      hintL = hintR = const Offset(0, 1);
    case _P.climb:
      hl = neck + Offset(f * 3, -6.5 + 3 * s);
      hr = neck + Offset(f * 3, -6.5 - 3 * s);
      hintL = hintR = Offset(-f, 0.5);
    case _P.sit:
      hl = neck + Offset(f * 6.5, 6);
      hr = neck + Offset(f * 7.5, 7);
    case _P.coffee:
      final sip = _seg(math.sin(time * 1.1 + g.id), 0.55, 0.9);
      hr = Offset.lerp(neck + Offset(f * 6.5, 5.5), head + Offset(f * 3.2, 1.8), sip)!;
      hl = neck + Offset(f * 6, 7.5);
      g.k = sip;
    case _P.lie:
      hl = neck + Offset(-f * 6, 1.8);
      hr = neck + Offset(-f * 3.5, -1.6);
      hintL = hintR = const Offset(0, -1);
    case _P.lean:
      if (g.k > 0.5) {
        hr = neck + Offset(f * 6.5, 0.2);
        hl = hr + Offset(-f * 1.2, 1.6);
        hintR = hintL = const Offset(0, 1);
      } else {
        hl = neck + Offset(f * 3.2, 5.5);
        hr = neck + Offset(f * 2.4, 4.4);
      }
    case _P.cheer:
      hl = neck + const Offset(-4, -9.8);
      hr = neck + const Offset(4, -9.8);
      hintL = const Offset(-1, 0);
      hintR = const Offset(1, 0);
    case _P.highFive:
      hr = g.aim ?? neck + Offset(f * 6, -9.2);
      hintR = Offset(-f, 0.2);
    case _P.wipe:
      hr = head + Offset(f * (0.8 + 2.4 * math.sin(time * 7 + g.id)), -1.8);
      hintR = Offset(f, 0.5);
    case _P.signal:
      hl = neck + Offset(-5, -2 + 6 * s);
      hr = neck + Offset(5, -2 - 6 * s);
      hintL = const Offset(-1, 0.2);
      hintR = const Offset(1, 0.2);
    case _P.clipboard:
      hl = neck + Offset(f * 5.5, 5);
      hr = neck + Offset(f * (6.2 + 1.3 * math.sin(time * 11)), 3.6 + 0.8 * math.cos(time * 8));
    case _P.wave2:
      hl = Offset(g.plant?.dx ?? neck.dx + f * 4.5, neck.dy + 2);
      hr = neck + Offset(-f * 3 + 3.2 * math.sin(time * 14), -10.4);
      hintR = Offset(-f, 0);
    case _P.pole:
      hl = neck + Offset(f * 4.5, -1.5);
      hr = neck + Offset(f * 4.5, 5.5);
      if (g.plant != null) {
        hl = Offset(g.plant!.dx, neck.dy - 1.5);
        hr = Offset(g.plant!.dx, neck.dy + 5.5);
      }
    case _P.point:
      final a = g.aim;
      if (a != null) {
        final d = a - neck;
        hr = neck + d / math.max(1, d.distance) * 11;
      }
      hintR = const Offset(0, 1);
    case _P.survey:
      final a = g.aim ?? neck + Offset(f * 8, 2);
      hl = a + const Offset(0, 1.5);
      hr = a + const Offset(0, -1);
      hintL = hintR = const Offset(0, 1);
    case _P.bucket:
      hr = neck + Offset(f * 2, 10.8);
      hl = neck + Offset(-f * 5.5, 5.5);
    case _P.ladder:
      hr = neck + Offset(f * 2, -3.5);
      hl = neck + Offset(-f * 2.5, -3.5);
      hintL = hintR = const Offset(0, 1);
    case _P.stand:
      if (g.move) {
        hl = neck + Offset(-f * 3.8 * s, 10.2);
        hr = neck + Offset(f * 3.8 * s, 10.2);
      }
  }

  if (g.wave) {
    hr = neck + Offset(f * 3 + 3.2 * math.sin(time * 14), -10.4);
    hintR = Offset(f, 0);
  }

  g
    ..hip = hip
    ..neck = neck
    ..head = head
    ..hl = hl
    ..hr = hr
    ..fl = fl
    ..fr = fr
    ..el = _ik(neck, hl, 5.6, 5.6, hintL)
    ..er = _ik(neck, hr, 5.6, 5.6, hintR)
    ..kl = _ik(hip, fl, 7, 7, kneeHint)
    ..kr = _ik(hip, fr, 7, 7, kneeHint);
}

final _halo = Paint()
  ..color = BP.paper
  ..strokeWidth = 4.6
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;
final _body = Paint()
  ..color = BP.ink
  ..strokeWidth = 1.9
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;
final _headFill = Paint()..color = BP.paper;
final _headLine = Paint()
  ..color = BP.ink
  ..strokeWidth = 1.6
  ..style = PaintingStyle.stroke;
final _hatFill = Paint()..color = BP.amber;

Path _hatPath(double f) => Path()
  ..addArc(Rect.fromCircle(center: const Offset(0, -1.2), radius: 4.4), math.pi, math.pi)
  ..close()
  ..addRect(Rect.fromLTRB(f > 0 ? -4.9 : -6.9, -1.7, f > 0 ? 6.9 : 4.9, -0.4));
final _hatR = _hatPath(1);
final _hatL = _hatPath(-1);

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
  double _time = 0;

  @override
  void paint(Canvas canvas, Size size) {
    if (kit.disposed) return;
    _c = canvas;
    _time = clock.t;
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

  /// Sparks flying from [o]: a burst [age] seconds old.
  void _burst(Offset o, double age, int seed, {int n = 7, Color color = BP.amber, double up = 1, double speed = 1}) {
    if (age < 0 || age > 0.55) return;
    for (var i = 0; i < n; i++) {
      final life = 0.3 + 0.25 * _h(seed, i, 1);
      if (age > life) continue;
      final ang = -math.pi / 2 * up + (_h(seed, i, 2) - 0.5) * 2.6;
      final sp = (60 + 110 * _h(seed, i, 3)) * speed;
      final v = Offset(math.cos(ang) * sp, math.sin(ang) * sp + 420 * age);
      final p = o + Offset(math.cos(ang) * sp * age, math.sin(ang) * sp * age + 210 * age * age);
      final tail = p - v / math.max(1, v.distance) * 4;
      _c.drawLine(tail, p, _stroke(color, 1.4, 1 - age / life));
    }
  }

  /// A continuous spark stream (welding).
  void _stream(Offset o, double t, int seed, {Color color = BP.amber}) {
    const period = 0.42;
    for (var i = 0; i < 9; i++) {
      final off = _h(seed, i, 9) * period;
      final k = ((t + off) / period).floor();
      final age = (t + off) - k * period;
      _burst(o, age, seed * 31 + i * 7 + k, n: 1, color: color, speed: 1.1);
    }
  }

  void _dust(Offset o, double age, {double spread = 1}) {
    if (age < 0 || age > 0.8) return;
    final a = age / 0.8;
    for (var i = 0; i < 7; i++) {
      final side = i.isEven ? 1 : -1;
      final dx = side * (4 + (18 + 16 * _h(i, 3)) * spread * _eo(a));
      final dy = -2 - 9 * a * _h(i, 4);
      _c.drawCircle(o + Offset(dx, dy), 2 + 6 * a * (0.6 + 0.4 * _h(i, 5)), _stroke(BP.inkDim, 1, 0.7 * (1 - a)));
    }
  }

  void _rope(Offset a, Offset b, {double sag = 4, Color color = BP.amber, double w = 1.4}) {
    final m = Offset.lerp(a, b, 0.5)! + Offset(0, sag);
    _c.drawPath(
      Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(m.dx, m.dy, b.dx, b.dy),
      _stroke(color, w),
    );
  }

  void _ladder(Offset foot, Offset top, {double a = 1}) {
    final d = top - foot;
    final len = d.distance;
    if (len < 2) return;
    final u = d / len;
    final n = Offset(-u.dy, u.dx) * 4.6;
    final p = _stroke(BP.inkDim, 1.4, a);
    _c
      ..drawLine(foot + n, top + n, p)
      ..drawLine(foot - n, top - n, p);
    for (var s = 7.0; s < len - 3; s += 9) {
      final q = foot + u * s;
      _c.drawLine(q + n, q - n, p);
    }
  }

  void _zzz(Offset o, double t) {
    for (var j = 0; j < 3; j++) {
      final p = (t * 0.35 + j / 3) % 1;
      final s = 2.4 + p * 2.6;
      final c = o + Offset(4 + p * 12, -6 - p * 22);
      final path = Path()
        ..moveTo(c.dx - s, c.dy - s)
        ..lineTo(c.dx + s, c.dy - s)
        ..lineTo(c.dx - s, c.dy + s)
        ..lineTo(c.dx + s, c.dy + s);
      _c.drawPath(path, _stroke(BP.inkDim, 1.3, math.sin(p * math.pi)));
    }
  }

  void _steam(Offset o, double t) {
    for (var j = 0; j < 3; j++) {
      final p = (t * 0.55 + j / 3) % 1;
      final path = Path();
      for (var k = 0; k <= 6; k++) {
        final yy = o.dy - 2 - p * 14 - k * 1.6;
        final xx = o.dx + (j - 1) * 2 + math.sin(p * 6 + k * 0.9) * 1.6;
        k == 0 ? path.moveTo(xx, yy) : path.lineTo(xx, yy);
      }
      _c.drawPath(path, _stroke(BP.inkDim, 1, math.sin(p * math.pi) * 0.8));
    }
  }

  void _check(Offset o, double s, Paint p) {
    _c.drawPath(
      Path()
        ..moveTo(o.dx, o.dy)
        ..lineTo(o.dx + s * 0.35, o.dy + s * 0.35)
        ..lineTo(o.dx + s, o.dy - s * 0.45),
      p,
    );
  }

  // ── figures ────────────────────────────────────────────────────────────────

  void _hover(List<_Fig> figs) {
    final p = clock.pointer;
    if (p == null) return;
    _Fig? best;
    var bd = 22.0;
    for (final g in figs) {
      if (!g.free || g.p == _P.carry || g.p == _P.climbCarry || g.p == _P.shoulder || g.p == _P.ladder) continue;
      final d = (Offset(g.x, g.y - 16) - p).distance;
      if (d < bd) {
        bd = d;
        best = g;
      }
    }
    best?.wave = true;
  }

  void _drawFigs(List<_Fig> figs, {double minX = -99, double maxX = 1630}) {
    for (final g in figs) {
      _solve(g, _time);
    }
    // ropes behind bodies
    for (final g in figs) {
      final r = g.rope;
      if (r == null || g.x < minX || g.x > maxX) continue;
      _rope(Offset.lerp(g.hl, g.hr, 0.5)!, r, sag: 3);
    }
    for (final g in figs) {
      if (g.x < minX || g.x > maxX) continue;
      _fig(g);
    }
  }

  void _fig(_Fig g) {
    final c = _c;
    final f = g.f;
    final path = Path()
      ..moveTo(g.fl.dx, g.fl.dy)
      ..lineTo(g.kl.dx, g.kl.dy)
      ..lineTo(g.hip.dx, g.hip.dy)
      ..lineTo(g.kr.dx, g.kr.dy)
      ..lineTo(g.fr.dx, g.fr.dy)
      ..moveTo(g.hip.dx, g.hip.dy)
      ..lineTo(g.neck.dx, g.neck.dy)
      ..moveTo(g.hl.dx, g.hl.dy)
      ..lineTo(g.el.dx, g.el.dy)
      ..lineTo(g.neck.dx, g.neck.dy)
      ..lineTo(g.er.dx, g.er.dy)
      ..lineTo(g.hr.dx, g.hr.dy);
    c
      ..drawPath(path, _halo)
      ..drawPath(path, _body)
      ..drawCircle(g.head, 3.8, _headFill)
      ..drawCircle(g.head, 3.8, _headLine);
    final up = g.neck - g.hip;
    final ang = math.atan2(up.dx, -up.dy);
    c
      ..save()
      ..translate(g.head.dx, g.head.dy)
      ..rotate(ang);
    if (g.p == _P.lie) {
      c.rotate(f * 1.1);
      c.translate(0, 1.6);
    }
    c.drawPath(f > 0 ? _hatR : _hatL, _hatFill);
    if (g.visor) {
      c.drawRect(Rect.fromLTWH(f > 0 ? 1.4 : -4.4, -0.8, 3, 4.6), _fill(BP.amber, 0.85));
    }
    c.restore();
    _item(g);
    if (g.sweat) _sweat(g);
    if (g.alarm) {
      final o = g.head + const Offset(0, -9);
      c
        ..drawLine(o + const Offset(0, -9), o + const Offset(0, -2.5), _stroke(BP.amber, 2))
        ..drawCircle(o + const Offset(0, 0.6), 1.1, _fill(BP.amber));
    }
  }

  void _sweat(_Fig g) {
    const period = 0.95;
    for (var j = 0; j < 2; j++) {
      final t = _time + g.id * 0.37 + j * period / 2;
      final age = t % period;
      if (age > 0.6) continue;
      final side = (((t / period).floor() + j) % 2 == 0) ? 1.0 : -1.0;
      final p = g.head + Offset(side * (3 + 16 * age), -4 - 22 * age + 70 * age * age);
      final a = 1 - age / 0.6;
      _c
        ..drawCircle(p, 1.3, _fill(BP.line, a))
        ..drawLine(p + const Offset(0, -1.1), p + const Offset(0, -3), _stroke(BP.line, 1, a));
    }
  }

  void _item(_Fig g) {
    final c = _c;
    final f = g.f;
    switch (g.item) {
      case _I.none:
        break;
      case _I.cup:
        final o = g.hr + Offset(f * 1.4, -1.6);
        c
          ..drawRect(Rect.fromCenter(center: o, width: 3.6, height: 4.2), _fill(BP.paper))
          ..drawRect(Rect.fromCenter(center: o, width: 3.6, height: 4.2), _stroke(BP.ink, 1.1));
        if (g.k < 0.2) _steam(o + const Offset(0, -2), _time + g.id);
      case _I.wrench:
        final a = g.p == _P.wrench ? g.aim : null;
        final end = a ?? g.hr + Offset(f * 7, -5);
        c
          ..drawLine(g.hr, end, _stroke(BP.inkDim, 2.4))
          ..drawCircle(end, 2.4, _stroke(BP.amber, 1.4));
      case _I.torch:
        final a = g.p == _P.weld ? g.aim : null;
        final end = a ?? g.hr + Offset(f * 6, -2);
        c.drawLine(g.hr, end, _stroke(BP.ink, 1.8));
        if (a != null) c.drawCircle(end, 2, _fill(BP.amber));
      case _I.clipboard:
        final r = Rect.fromCenter(center: g.hl + Offset(f * 1.2, -2.5), width: 6, height: 8);
        c
          ..drawRect(r, _fill(BP.paper))
          ..drawRect(r, _stroke(BP.inkDim, 1.1))
          ..drawLine(r.topLeft + const Offset(1.5, 3), r.topRight + const Offset(-1.5, 3), _stroke(BP.inkDim, 0.8))
          ..drawLine(r.topLeft + const Offset(1.5, 5), r.topRight + const Offset(-1.5, 5), _stroke(BP.inkDim, 0.8));
      case _I.hammer:
        final d = g.hr - g.er;
        final u = d / math.max(0.01, d.distance);
        final end = g.hr + u * 6.5;
        final n = Offset(-u.dy, u.dx) * 2.8;
        c
          ..drawLine(g.hr, end, _stroke(BP.inkDim, 1.4))
          ..drawLine(end - n, end + n, _stroke(BP.ink, 2.8));
      case _I.bucket:
        final top = g.hr + const Offset(0, 2.5);
        final path = Path()
          ..moveTo(top.dx - 3.6, top.dy)
          ..lineTo(top.dx - 2.7, top.dy + 6)
          ..lineTo(top.dx + 2.7, top.dy + 6)
          ..lineTo(top.dx + 3.6, top.dy);
        c
          ..drawPath(path, _stroke(BP.line, 1.3))
          ..drawLine(top + const Offset(-3.2, 1.6), top + const Offset(3.2, 1.6), _stroke(BP.line, 1, 0.6))
          ..drawArc(Rect.fromCircle(center: top, radius: 3.6), math.pi, math.pi, false, _stroke(BP.inkDim, 0.9));
      case _I.sign:
        final base = g.plant ?? Offset(g.hr.dx, g.hr.dy + 16);
        final top = base + const Offset(0, -128);
        c.drawLine(base, top, _stroke(BP.inkDim, 2));
        final board = Rect.fromCenter(center: top + const Offset(0, 17), width: 70, height: 34);
        c
          ..drawRect(board, _fill(BP.paper))
          ..drawRect(board, _stroke(BP.amber, 1.6));
        final a = board.center + const Offset(21, 0), b = board.center + const Offset(-21, 0);
        c.drawLine(a, b, _stroke(BP.amber, 2.6));
        drawArrowHead(c, b, a, _stroke(BP.amber, 2.6), 9);
      case _I.flag:
        final base = g.plant ?? Offset(g.hr.dx, g.hr.dy + 14);
        const h = 100.0;
        final top = base + const Offset(0, -h);
        c.drawLine(base, top, _stroke(BP.inkDim, 2));
        final fy = top.dy + (1 - g.itemT) * (h - 30);
        final wv = math.sin(_time * 5) * 2;
        final fd = base.dx > _divX ? -1.0 : 1.0; // fly away from the word
        final path = Path()
          ..moveTo(top.dx, fy)
          ..quadraticBezierTo(top.dx + fd * 20, fy - wv, top.dx + fd * 40, fy + wv)
          ..lineTo(top.dx + fd * 40, fy + 26 + wv)
          ..quadraticBezierTo(top.dx + fd * 20, fy + 26 - wv, top.dx, fy + 26)
          ..close();
        c
          ..drawPath(path, _fill(BP.green, 0.18))
          ..drawPath(path, _stroke(BP.green, 1.6));
        _check(Offset(top.dx + (fd > 0 ? 11 : -29), fy + 13), 18, _stroke(BP.green, 2.6));
      case _I.staff:
        final x = g.hr.dx + f * 2.5;
        for (var i = 0; i < 7; i++) {
          c.drawLine(
            Offset(x, _gy - i * 10.0),
            Offset(x, _gy - i * 10.0 - 10),
            _stroke(i.isEven ? BP.amber : BP.inkDim, 2.2),
          );
        }
    }
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
    if (done) _check(Offset(x + 12, y + 14), 15, _stroke(BP.green, 2.6));
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
    _Fig plan(int w, double t) {
      final sx = _Latin.startX[w];
      switch (w) {
        case 0: // A: T, then leans on the T checking his watch
          if (t < _Latin.leave[0]) {
            return _Fig(sx, -1, _P.reach, id: 100, aim: L.stackPos(0) + const Offset(4, 14));
          }
          final a = L.arrive[0];
          if (t < a) {
            final (x, _) = _go(t, _Latin.leave[0], sx, L.dropX(0), _Latin.v);
            return _Fig(x, 1, _P.shoulder, ph: x / 5, move: true, id: 100);
          }
          if (t < a + 0.2) {
            return _Fig(L.dropX(0), 1, _P.toss, id: 100, itemT: _eo(_seg(t, a, a + 0.12)));
          }
          final watchEnd = math.max(L.done, a + 1.2);
          if (t < watchEnd) return _Fig(L.dropX(0), 1, _P.stand, id: 100);
          if (hasEvent && t >= ts + 0.5) {
            if (t < tArrive) {
              final (x, d) = _go(t, ts + 0.5, leanX, pushX, 140);
              return _Fig(x, d, _P.walk, ph: x / 4.5, move: true, id: 100);
            }
            if (t < tArrive + 0.75) {
              return _Fig(pushX, amp > 0 ? -1 : 1, _P.push, ph: t * 9, id: 100, sweat: false);
            }
            final back = _arr(tArrive + 0.75, pushX, leanX, 140);
            if (t < back) {
              final (x, d) = _go(t, tArrive + 0.75, pushX, leanX, 140);
              return _Fig(x, d, _P.walk, ph: x / 4.5, move: true, id: 100);
            }
          }
          final arrLean = _arr(watchEnd, L.dropX(0), leanX, 120);
          if (t < arrLean) {
            final (x, d) = _go(t, watchEnd, L.dropX(0), leanX, 120);
            return _Fig(x, d == 0 ? 1 : d, _P.walk, ph: x / 4.5, move: true, id: 100);
          }
          final watch = (t * 0.23 + 0.1) % 1 < 0.35 ? 1.0 : 0.0;
          return _Fig(leanX, 1, _P.lean, k: watch, id: 100);
        case 1: // B: e, then coffee at the far end
          if (t < _Latin.pick[1]) return _Fig(sx, -1, _P.stand, id: 101);
          if (t < _Latin.leave[1]) {
            return _Fig(sx, -1, _P.reach, id: 101, aim: L.stackPos(1) + const Offset(-4, 14));
          }
          final a = L.arrive[1];
          if (t < a) {
            final (x, _) = _go(t, _Latin.leave[1], sx, L.dropX(1), _Latin.v);
            return _Fig(x, 1, _P.shoulder, ph: x / 5 + 1, move: true, id: 101);
          }
          if (t < a + 0.2) {
            return _Fig(L.dropX(1), 1, _P.toss, id: 101, itemT: _eo(_seg(t, a, a + 0.12)));
          }
          final arrSit = _arr(a + 0.45, L.dropX(1), sitX, 170);
          if (t < arrSit) {
            final (x, _) = _go(t, a + 0.45, L.dropX(1), sitX, 170);
            return _Fig(x, 1, t < a + 0.45 ? _P.stand : _P.walk, ph: x / 4.5, move: t >= a + 0.45, id: 101);
          }
          return _Fig(sitX, -1, _P.coffee, id: 101, item: _I.cup);
        default: // C: x and t at once, then a nap by the empty pallet
          if (t < _Latin.pick[2]) return _Fig(sx, -1, _P.stand, id: 102);
          if (t < _Latin.leave[2]) {
            return _Fig(sx, -1, _P.reach, id: 102, aim: L.stackPos(2) + const Offset(10, 4));
          }
          final a2 = L.arrive[2], a3 = L.arrive[3];
          if (t < a2) {
            final (x, _) = _go(t, _Latin.leave[2], sx, L.dropX(2), _Latin.v);
            return _Fig(x, 1, _P.carry, ph: x / 5 + 2, move: true, id: 102);
          }
          if (t < a2 + 0.14) return _Fig(L.dropX(2), 1, _P.carry, id: 102);
          if (t < a3) {
            final (x, _) = _go(t, a2 + 0.14, L.dropX(2), L.dropX(3), _Latin.v);
            return _Fig(x, 1, _P.carry, ph: x / 5 + 2, move: true, id: 102);
          }
          if (t < a3 + 0.2) return _Fig(L.dropX(3), 1, _P.carry, id: 102);
          final arrNap = _arr(a3 + 0.6, L.dropX(3), napX, 190);
          if (t < a3 + 0.6) return _Fig(L.dropX(3), 1, _P.stand, id: 102);
          if (t < arrNap) {
            final (x, _) = _go(t, a3 + 0.6, L.dropX(3), napX, 190);
            return _Fig(x, -1, _P.walk, ph: x / 4.5, move: true, id: 102);
          }
          return _Fig(napX, -1, _P.lie, id: 102);
      }
    }

    final figs = <_Fig>[];
    for (var w = 0; w < 3; w++) {
      if (tau < tearAt) {
        final g = plan(w, tau);
        if (clock.awake && tau > L.done + 1 && (g.p == _P.lie || g.p == _P.coffee || g.p == _P.lean)) {
          g
            ..p = _P.stand
            ..alarm = true
            ..item = _I.none
            ..f = (clock.pointer?.dx ?? 900) > g.x ? 1 : -1;
        }
        figs.add(g);
      } else {
        final g0 = plan(w, tearAt - 1e-3);
        final tt = tau - tearAt;
        final sx = _Latin.startX[w];
        final (x, d) = _go(tt, 0.25, g0.x, sx, 330);
        figs.add(_Fig(x, d == 0 ? (tt < 0.25 ? g0.f : 1) : d, d == 0 ? _P.stand : _P.run, ph: x / 6, move: d != 0, id: 100 + w));
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
          _dust(Offset(L.slotC(i), _gy), tau - land, spread: 1.2);
        } else {
          _letter(i, Offset(L.slotC(i), _gy), 1, i == si ? tilt(tau) : 0);
          _dust(Offset(L.slotC(i), _gy), tau - land, spread: 1.2);
        }
      }
    }

    _hover(figs);
    _drawFigs(figs);

    // Idle details
    for (final g in figs) {
      if (g.p == _P.lie && !g.wave) _zzz(g.head, _time);
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
    final figs = <_Fig>[];
    switch (cy.s) {
      case 0:
        _arabic(sc, cy, figs);
      case 1:
        _deva(sc, cy, figs);
      default:
        _thai(sc, cy, figs);
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
    List<_Fig> out,
    _Sc sc,
    _Cyc cy,
    double t, {
    required double left,
    required double right,
    double? laserTo,
    Offset? job,
  }) {
    // Foreman, front row, clipboard; points at whatever is being built.
    {
      final x1 = left - 8;
      final (x, d) = _go(t, 0.1, _offX, x1, 260);
      final g = _Fig(x, d != 0 ? d : 1, d != 0 ? _P.walk : _P.clipboard,
          y: _fy, ph: x / 4.5, move: d != 0, id: 900, item: _I.clipboard);
      if (d == 0 && job != null && (t % 3.6) < 1.1) {
        g
          ..p = _P.point
          ..aim = job
          ..f = job.dx >= x ? 1 : -1;
      }
      out.add(g);
    }
    // Surveyor + theodolite on the baseline, left end.
    final sx = left - 44;
    final tx = sx + 11;
    final (svx, svd) = _go(t, 0.25, _offX, sx, 270);
    final svArr = _arr(0.25, _offX, sx, 270);
    final surveyor = _Fig(svx, svd != 0 ? svd : 1, svd != 0 ? _P.walk : _P.survey,
        ph: svx / 4.5, move: svd != 0, id: 903, aim: Offset(tx - 2, _gy - 28));
    out.add(surveyor);
    // Staff man, right end (unless a sign pole is the target).
    var target = laserTo;
    if (target == null) {
      final stx = right + 20;
      final (x, d) = _go(t, 0.45, _offX, stx, 240);
      out.add(_Fig(x, d != 0 ? d : -1, d != 0 ? _P.walk : _P.pole,
          ph: x / 4.5, move: d != 0, id: 902, item: _I.staff));
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
      out.add(_Fig(x, f, _P.bucket, y: _fy, ph: x / 4.5, move: true, id: 904, item: _I.bucket));
    }
    // Hammerers: tapping letters into true.
    for (var j = 0; j < 2; j++) {
      final hx = _lerp(left, right, j == 0 ? 0.3 : 0.74) + 10;
      final (x, d) = _go(t, 1.6 + j * 0.6, _offX, hx, 230);
      final active = t > 5.3 && t < sc.work - 0.6 && ((t * 0.45 + j * 0.5) % 1) < 0.62;
      final g = _Fig(x, d != 0 ? d : -1, d != 0 ? _P.walk : (active ? _P.hammer : _P.stand),
          ph: d != 0 ? x / 4.5 : t * 9 + j, move: d != 0, id: 905 + j, item: _I.hammer, sweat: active);
      out.add(g);
      if (active && d == 0) {
        final period = 2 * math.pi / 9;
        final age = ((t * 9 + j - math.pi / 2) / (2 * math.pi) % 1) * period;
        _burst(Offset(hx - 11, _gy - 3), age, cy.n * 13 + j * 5 + ((t * 9 + j) / (2 * math.pi)).floor(), n: 5);
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
  void _crane(double tx, double hy, {void Function(Offset hook)? load, List<Offset> slings = const []}) {
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
      ..drawCircle(head, 3.4, _headFill)
      ..drawCircle(head, 3.4, _headLine)
      ..save()
      ..translate(head.dx, head.dy)
      ..scale(0.9)
      ..drawPath(_hatL, _hatFill)
      ..restore();
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
  void _finishCrew(List<_Fig> figs, _Cyc cy) {
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
            ..p = _P.highFive
            ..f = 1
            ..aim = mid
            ..item = a.item == _I.hammer ? _I.none : a.item
            ..k = a.id.toDouble();
          b
            ..p = _P.highFive
            ..f = -1
            ..aim = mid
            ..item = b.item == _I.hammer ? _I.none : b.item
            ..k = a.id.toDouble();
          paired
            ..add(order[j])
            ..add(order[j + 1]);
          final clap = (math.sin(_time * 6 + a.id) + 1) / 2;
          if (clap > 0.9) _burst(mid, (clap - 0.9) * 2, a.id + cy.n, n: 5, color: BP.green);
        }
      }
      for (final g in figs) {
        if (g.id == 900) {
          // Foreman plants the green flag.
          g
            ..p = _P.pole
            ..item = _I.flag
            ..plant = Offset(g.x + g.f * 4.5, g.y)
            ..itemT = _eo(_seg(dd, 0.15, 1.0))
            ..move = false;
        } else if (g.id == 901) {
          g.p = (dd * 0.8) % 1 < 0.5 ? _P.pole : _P.wave2;
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
          g.p = _P.cheer;
        } else {
          g.p = [_P.cheer, _P.lie, _P.sit, _P.wipe][m];
          if (g.p == _P.lie || g.p == _P.sit) g.item = _I.none;
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
          ..p = _P.run
          ..ph = g.x / 6
          ..move = true
          ..sweat = false
          ..plant = null
          ..rope = null
          ..visor = false;
        if (g.item == _I.cup) g.item = _I.none;
        if (g.id == 900) {
          g
            ..item = _I.flag
            ..itemT = 1;
        }
      }
    }
  }

  // ── Arabic: bidi, joining, gsub, marks ────────────────────────────────────

  void _arabic(_Sc sc, _Cyc cy, List<_Fig> figs) {
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
          final g = _Fig(x, -1, _P.carry,
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
          figs.add(_Fig(atX, d != 0 ? d : (i == 0 ? 1 : -1),
              d != 0 ? _P.walk : (pushing ? _P.push : (t >= pushB ? _P.wipe : _P.stand)),
              ph: d != 0 ? x / 4.5 : t * 8 + j, move: d != 0, id: myId, sweat: pushing || t >= pushB));
        } else {
          final rx = under + (i == 0 ? -12 : 14) + 8 * _h(cy.n, myId);
          final e = _eio(_seg(t, lowEnd, lowEnd + 0.8));
          final x = _lerp(under, rx, e);
          final y = _lerp(_gy, _fy, e);
          final rest = [_P.wipe, _P.stand, _P.signal][(myId + cy.n) % 3];
          figs.add(_Fig(x, i == 0 ? 1 : -1, e < 1 ? _P.walk : rest,
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
        figs.add(_Fig(x, d, _P.walk, y: _fy, ph: x / 4.5, move: true, id: myId));
        continue;
      }
      if (j == 1) {
        figs.add(_Fig(x, 1, ropeOn ? _P.signal : _P.stand, y: _fy, ph: t * 7, id: myId, sweat: ropeOn));
      } else {
        final f = j == 0 ? -1.0 : 1.0;
        final anchor = j == 0 ? Offset(left[0] + w[0] - 6, joinY) : Offset(left[1] + 6, joinY);
        figs.add(_Fig(x, f, ropeOn ? _P.pull : _P.stand, y: _fy, ph: t * 6 + j,
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
      figs.add(_Fig(x, d != 0 ? d : f, d != 0 ? _P.walk : (on ? _P.wrench : (t > swap[i] ? _P.wipe : _P.stand)),
          ph: d != 0 ? x / 4.5 : t * 6, move: d != 0, id: 40 + i, item: _I.wrench,
          aim: on ? aims[i] : null, sweat: on));
    }
    // Rigger under the crane.
    final dot = sc.diffC;
    {
      final st = dot.center.dx + 34;
      final (x, d) = _go(t, 6.6, _offX, st, 230);
      final on = t > lowA - 0.4 && t < lowB;
      figs.add(_Fig(x, d != 0 ? d : -1, d != 0 ? _P.walk : (on ? _P.signal : _P.stand),
          ph: d != 0 ? x / 4.5 : t * 5, move: d != 0, id: 45));
    }
    // Flag-bearer: plants the direction sign first (bidi: this run is RTL).
    {
      final (x, d) = _go(t, 0.0, _offX, signX + 7, 230);
      final a0 = _arr(0.0, _offX, signX + 7, 230);
      final g = _Fig(x, d != 0 ? d : -1, d != 0 ? _P.walk : _P.pole,
          ph: x / 4.5, move: d != 0, id: 901, item: _I.sign);
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
        _dust(Offset(left[i] + w[i] / 2, _gy), t - arr[i] - 0.6, spread: 2);
        _burst(aims[i], t - swap[i], cy.n * 7 + i, n: 9);
      }
      if (landed) {
        _diff(sc, Offset.zero);
        _burst(dot.center, t - lowB, cy.n + 77, n: 8, color: BP.green);
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
    _drawFigs(figs, minX: 812);
  }

  // ── Devanagari: clusters, half forms, shirorekha, marks ───────────────────

  void _deva(_Sc sc, _Cyc cy, List<_Fig> figs) {
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
          final g = _Fig(x, -1, _P.carry, ph: x / 4.2 + j * 1.7, move: t < arr[i] && t >= t0s[i],
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
          figs.add(_Fig(atX, d != 0 ? d : moveDir, d != 0 ? _P.walk : (pushing ? _P.push : (t > slideB ? _P.wipe : _P.stand)),
              ph: d != 0 ? x / 4.5 : t * 8 + j, move: d != 0, id: myId, sweat: pushing || t > slideB));
        } else {
          final rx = under + 10 * (_h(cy.n, myId) - 0.5);
          final e = _eio(_seg(t, lowEnd, lowEnd + 0.8));
          final rest = [_P.wipe, _P.signal, _P.stand][(myId + cy.n) % 3];
          figs.add(_Fig(_lerp(under, rx, e), myId.isEven ? 1 : -1, e < 1 ? _P.walk : rest,
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
      final g = _Fig(x, d != 0 ? d : -1, d != 0 ? _P.walk : (on ? _P.weld : (t > weld[k].$2 ? _P.wipe : _P.stand)),
          ph: d != 0 ? x / 4.5 : t * 5, move: d != 0, id: 40 + k, item: _I.torch, aim: aim, sweat: on);
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
      figs.add(_Fig(x, d != 0 ? d : f, d != 0 ? _P.walk : (tagOn ? _P.pull : _P.stand),
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
      final g = _Fig(x, d != 0 ? d : -1, d != 0 ? _P.ladder : (raise > 0 ? _P.push : _P.ladder),
          ph: x / 4.5, move: d != 0, id: 60, sweat: raise > 0);
      figs.add(g);
      final la = 1 - _seg(tau, sc.work + _hold, sc.work + _hold + 0.6);
      if (raise <= 0) {
        if (x < 1640) {
          _ladder(Offset(x - 32, _gy - 27), Offset(x + 30, _gy - 27), a: la);
        }
      } else {
        final e = _eio(raise);
        final foot = Offset(fx, _gy);
        final flat = Offset(fx - 62, _gy - 4);
        _ladder(foot, Offset.lerp(flat, topC, e)!, a: la);
      }
    }
    Offset? matraAt;
    {
      final (x, d) = _go(t, 8.0, _offX, fx + 3, 170);
      final climb = _eio(_seg(t, climbA, climbB));
      final placed = _seg(t, placeA, placeB);
      _Fig g;
      if (d != 0 || t < climbA) {
        g = _Fig(x, d != 0 ? d : -1, _P.carry, ph: x / 4.2, move: d != 0, id: 61, sweat: true);
      } else {
        final p = Offset.lerp(Offset(fx + 3, _gy), feetTop, climb)!;
        g = _Fig(p.dx, -1, placed > 0.4 ? _P.climb : _P.climbCarry, y: p.dy,
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
        _dust(Offset(left[i] + wPre[i] / 2, _gy), t - arr[i] - 0.6, spread: 1.4);
      }
      if (headlineOn) {
        _c
          ..save()
          ..clipRect(band);
        sc.word.mForm.paint(_c, sc.wl, _gy);
        _c.restore();
        for (var k = 0; k < 6; k++) {
          _burst(Offset(sc.wl + sc.ww * (k + 0.5) / 6, bandB), t - lowB - k * 0.05, cy.n * 5 + k, n: 5);
        }
      }
      for (var k = 0; k < 2; k++) {
        if (t > weld[k].$1 && t < weld[k].$2) _stream(weldAim[k], _time, cy.n * 3 + k);
      }
      final m = matraAt;
      if (m != null) {
        _diff(sc, m);
      } else {
        _diff(sc, Offset.zero);
        _burst(mk.center, t - placeB, cy.n + 91, n: 8, color: BP.green);
      }
    } else {
      _finalWord(sc, dd);
    }
    _drawFigs(figs, minX: 812);
  }

  // ── Thai: clusters, marks, word breaks ────────────────────────────────────

  void _thai(_Sc sc, _Cyc cy, List<_Fig> figs) {
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
          final g = _Fig(x, -1, _P.carry, ph: x / 4.2 + j * 1.7, move: t < arr[i] && t >= t0s[i],
              id: myId, sweat: t > t0s[i] + 1, k: math.sin(math.pi * _seg(t, arr[i], lowEnd)) * 0.9);
          g.free = false;
          figs.add(g);
          continue;
        }
        final under = sc.finX[i] + w[i] * frac;
        final rx = under + 12 * (_h(cy.n, myId) - 0.5);
        final e = _eio(_seg(t, lowEnd, lowEnd + 0.8));
        final rest = [_P.wipe, _P.stand, _P.signal, _P.sit][(myId + cy.n) % 4];
        figs.add(_Fig(_lerp(under, rx, e), myId.isEven ? 1 : -1, e < 1 ? _P.walk : rest,
            y: _lerp(_gy, _fy, e), ph: t * 7 + j, move: e < 1, id: myId, sweat: rest != _P.stand));
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
      figs.add(_Fig(x, d != 0 ? d : -1, d != 0 ? _P.walk : (on ? _P.signal : _P.stand),
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
      figs.add(_Fig(x - 22, d != 0 ? d : -1, raise > 0 ? _P.push : _P.ladder,
          ph: x / 4.5, move: d != 0, id: 60, sweat: true));
      figs.add(_Fig(x + 22, d != 0 ? d : -1, raise > 0 ? _P.stand : _P.ladder,
          ph: x / 4.5 + 2, move: d != 0, id: 62));
      if (raise <= 0) {
        if (x - 40 < 1640) _ladder(Offset(x - 40, _gy - 27), Offset(x + 40, _gy - 27), a: la);
      } else {
        _ladder(foot1, Offset.lerp(foot1 + const Offset(-80, -4), top1, raise)!, a: la);
      }
    }
    Offset? markAt;
    {
      final (x, d) = _go(t, 3.4, _offX, foot1.dx + 3, 230);
      final up = _eio(_seg(t, climb1.$1, climb1.$2));
      final dn = _eio(_seg(t, down1.$1, down1.$2));
      final placed = _seg(t, place1.$1, place1.$2);
      _Fig g;
      if (d != 0 || t < climb1.$1) {
        g = _Fig(x, d != 0 ? d : -1, _P.carry, ph: x / 4.2, move: d != 0, id: 61, sweat: true);
      } else if (dn < 1) {
        final p = Offset.lerp(Offset(foot1.dx + 3, _gy), feet1, up * (1 - dn))!;
        g = _Fig(p.dx, -1, placed > 0.4 ? _P.climb : _P.climbCarry, y: p.dy, ph: (up + dn) * 18, id: 61, sweat: true);
      } else {
        final (x2, d2) = _go(t, down1.$2, foot1.dx + 3, foot1.dx + 40, 120);
        final e = _seg(t, down1.$2, down1.$2 + 0.6);
        g = _Fig(x2, d2 != 0 ? d2 : -1, d2 != 0 ? _P.walk : _P.wipe, y: _lerp(_gy, _fy, e), ph: x2 / 4.5, move: d2 != 0, id: 61, sweat: true);
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
      _Fig g;
      if (d != 0 || t < climb2.$1) {
        g = _Fig(x, d != 0 ? d : 1, d != 0 ? _P.ladder : _P.push, ph: x / 4.5, move: d != 0, id: 63);
      } else {
        final p = Offset.lerp(Offset(foot2.dx - 4, _gy), feet2, up * (1 - dn))!;
        g = _Fig(p.dx, 1, ham ? _P.hammer : _P.climb, y: p.dy, ph: ham ? t * 10 : (up + dn) * 18,
            id: 63, item: _I.hammer, sweat: ham);
        if (ham) {
          final period = 2 * math.pi / 10;
          final age = ((t * 10 - math.pi / 2) / (2 * math.pi) % 1) * period;
          _burst(Offset(p.dx + 11, p.dy - 3), age, cy.n * 17 + ((t * 10) / (2 * math.pi)).floor(), n: 5);
        }
      }
      g.free = t > down2.$2;
      figs.add(g);
      if (raise <= 0) {
        if (x < 1640) _ladder(Offset(x - 30, _gy - 27), Offset(x + 30, _gy - 27), a: la);
      } else {
        _ladder(foot2, Offset.lerp(foot2 + const Offset(70, -4), top2, raise)!, a: la);
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
      _P sp = _P.walk;
      var moving = false;
      for (var k = 0; k < bounds.length; k++) {
        final bx = bounds[k] - 8;
        final a = _arr(tt, x0, bx, k == 0 ? 250 : 240);
        if (sx == null && t < a) {
          final (x, d) = _go(t, tt, x0, bx, k == 0 ? 250 : 240);
          sx = x;
          sf = d != 0 ? d : 1;
          moving = d != 0;
          sp = moving ? _P.walk : _P.stand;
        } else if (sx == null && t < a + 0.6) {
          sx = bx;
          sf = 1;
          sp = _P.hammer;
        }
        stakeT.add(a + 0.6);
        tt = a + 0.6;
        x0 = bx;
      }
      final g = _Fig(sx ?? x0, sf, sx == null ? _P.stand : sp,
          ph: sp == _P.hammer ? t * 11 : (sx ?? x0) / 4.5, move: moving, id: 70, item: _I.hammer, sweat: sp == _P.hammer);
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
        _dust(Offset(left[i] + w[i] / 2, _gy), t - arr[i] - 0.6, spread: 1.2);
      }
      if (aLanded) {
        aForm.paint(_c, aLeft, _gy);
        _dust(Offset(aCx, _gy), t - lowB, spread: 1.2);
      }
      final m = markAt;
      if (m != null) {
        _diff(sc, m);
      } else {
        _diff(sc, Offset.zero);
        _burst(mk.center, t - place1.$2, cy.n + 93, n: 8, color: BP.green);
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
      _dust(Offset(bx, _gy), t - stakeT[k], spread: 0.7);
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
    _drawFigs(figs, minX: 812);
  }
}
