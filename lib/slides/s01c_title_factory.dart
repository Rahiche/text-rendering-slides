import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../deck/font_data.dart';
import '../deck/scripts.dart';
import '../deck/theme.dart';
import '../deck/widgets.dart';
import '../worlds/factory/factory_kit.dart';

/// Title, option C: "The glyph factory".
///
/// An indexing assembly line (move, stop, work, move…) runs through the real
/// pipeline: code points drop out of a `unicode` chute in crates; a mixed
/// line such as "Flutterで文字をレンダリング" arrives chained and itemize splits
/// it into runs, routing each onto its lane (latin · hiragana · katakana ·
/// kanji · other). Fonts drops each glyph in (real TrueType outlines from
/// [FontData], or the engine's own rendering, with `Locale('ja')` for
/// Japanese); shape stamps glyph ids / joins Arabic / forms Devanagari
/// conjuncts; wrap cuts the ribbon into lines greedily; raster bakes pixel
/// tiles (real coverage from `Picture.toImageSync`). A bucket elevator lifts
/// the tiles; a gantry drops them into the huge title, where they develop
/// from coarse pixels into crisp text. Afterwards the factory keeps printing a
/// multilingual marquee (Japanese first) forever.
///
/// Everything is a pure function of time (one ticker, seeded randomness), so
/// nothing accumulates however long it stays on screen.
class TitleFactorySlide extends StatefulWidget {
  const TitleFactorySlide({super.key});

  @override
  State<TitleFactorySlide> createState() => _TitleFactorySlideState();
}

// ─────────────────────────────────────────────────────────────────────────────
// Layout & timing
// ─────────────────────────────────────────────────────────────────────────────

const _title = 'Text rendering';
const _titleSize = 168.0;
const _titleLeft = 66.0;
const _baseline = 262.0;
const _shelfY = 264.0;

/// Belt index cycle: move for [_mv] of it, then every machine works.
const _tc = 1.2;
const _mv = 0.42;
const _slots = 18; // belt slots 0..17; slot 18 = elevator bucket
const _x0 = 130.0;
const _pitch = (1452.0 - 130.0) / 18;
const _sSort = 3;
const _sFont = 6;
const _sPress = 9;
/// Itemize sorts onto five lanes, back to front:
/// latin · hiragana · katakana · kanji · everything else.
const _laneY = [663.0, 672.0, 681.0, 690.0, 699.0]; // crate bottoms
const _laneColor = [BP.line, Color(0xFF9FF0D6), BP.coral, BP.green, BP.violet];
const _mid = 2; // unsorted crates ride the middle lane
const _crateH = 38.0;
const _floor = 790.0;

// Bucket elevator (runs clockwise; tiles ride the left run up).
const _exX = 1452.0;
const _chainL = 1478.0;
const _chainR = 1526.0;
const _sprX = 1502.0;
const _sprR = 24.0;
const _sprTop = 128.0;
const _sprBot = 700.0;
const _loadY = 681.0;
const _rackY = 150.0; // tray level where title tiles leave
const _tickY = 344.0; // tray level where marquee tiles leave
const _buckets = 5;

// Gantry
const _pickX = 1262.0;
const _carryTop = 78.0;

const _board = 1312.0; // glyph counter

// Marquee
const _mLeft = 64.0;
const _mRight = 1382.0;
const _mTop = 352.0;
const _mBot = 402.0;
const _kM = 17; // first marquee item on the belt
const _ja = Locale('ja');
const _zh = Locale('zh');

/// The marquee, Japanese first. The locale picks the right glyph variants
/// for unified Han characters (and the right fallback font).
const _mEntries = <(String, Locale?)>[
  ('こんにちは', _ja),
  ('日本語', _ja),
  ('縦書き', _ja),
  ('Flutterで文字をレンダリング', _ja),
  ('Hello', null),
  ('مرحبا', null),
  ('नमस्ते', null),
  ('你好', _zh),
  ('שלום', null),
  ('สวัสดี', null),
  ('Привет', null),
  ('안녕', null),
  ('👋', null),
];

// Machines (hit areas for clicks) — order: unicode, itemize, fonts, shape, wrap, raster.
const _machineRects = <Rect>[
  Rect.fromLTRB(28, 436, 204, 604),
  Rect.fromLTRB(288, 452, 412, 616),
  Rect.fromLTRB(508, 440, 636, 616),
  Rect.fromLTRB(736, 440, 846, 616),
  Rect.fromLTRB(1000, 452, 1112, 616),
  Rect.fromLTRB(1182, 436, 1354, 710),
];

double _sx(double p) => _x0 + p * _pitch;
double _c01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
double _seg(double t, double a, double b) => _c01((t - a) / (b - a));
double _lerp(double a, double b, double t) => a + (b - a) * t;
double _eio(double t) => Curves.easeInOutCubic.transform(_c01(t));
double _eo(double t) => Curves.easeOutCubic.transform(_c01(t));
double _ei(double t) => Curves.easeInCubic.transform(_c01(t));
double _bump(double t) => t <= 0 || t >= 1 ? 0 : math.sin(t * math.pi);

/// Deterministic pseudo-random in [0, 1) (same sequence every run).
double _rnd(int a, [int b = 0, int c = 0]) {
  final v = math.sin(a * 12.9898 + b * 78.233 + c * 37.719 + 0.5) * 43758.5453;
  return v - v.floorToDouble();
}

/// Itemize's lane for a code point: Japanese gets one lane per script.
int _laneOf(int cp) {
  if (cp >= 0x3040 && cp <= 0x309F) return 1; // hiragana
  if ((cp >= 0x30A0 && cp <= 0x30FF) || (cp >= 0x31F0 && cp <= 0x31FF)) return 2; // katakana
  final s = scriptOf(cp);
  if (s == Script.han) return 3; // kanji
  if (s == Script.latin || s == Script.cyrillic || s == Script.greek || s == Script.common) return 0;
  return 4;
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────────────────────

class _Interaction {
  Offset? mouse;
  int letter = -1;
  double letterAt = -1e9;
  int machine = -1;
  double machineAt = -1e9;
}

class _TitleFactorySlideState extends State<TitleFactorySlide>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0);
  final _io = _Interaction();
  late _Model _model;
  FontData? _sg;
  FontData? _kufi;

  @override
  void initState() {
    super.initState();
    _model = _Model(null, null);
    _ticker = createTicker((d) => _clock.value = d.inMicroseconds / 1e6)..start();
    PaintingBinding.instance.systemFonts.addListener(_rebuild);
    _loadFonts();
  }

  Future<void> _loadFonts() async {
    try {
      final sg = await FontData.spaceGrotesk();
      final kufi = await FontData.notoKufiArabic();
      _sg = sg;
      _kufi = kufi;
      _rebuild();
    } catch (_) {
      // Outlines are a nicety; the painted fallback still works.
    }
  }

  /// Fonts arrived (bundled outlines, or a web fallback font): re-measure.
  void _rebuild() {
    if (!mounted) return;
    final old = _model;
    setState(() => _model = _Model(_sg, _kufi));
    SchedulerBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_rebuild);
    _ticker.dispose();
    _clock.dispose();
    _model.dispose();
    super.dispose();
  }

  void _tap(Offset p) {
    final t = _clock.value;
    for (final l in _model.letters) {
      if (!l.space && l.hit.contains(p)) {
        _io
          ..letter = l.index
          ..letterAt = t;
        return;
      }
    }
    for (var i = 0; i < _machineRects.length; i++) {
      if (_machineRects[i].contains(p)) {
        _io
          ..machine = i
          ..machineAt = t;
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: MouseRegion(
            onHover: (e) => _io.mouse = e.localPosition,
            onExit: (_) => _io.mouse = null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _tap(d.localPosition),
              child: CustomPaint(painter: _FactoryPainter(_clock, _model, _io)),
            ),
          ),
        ),
        Positioned(
          left: _titleLeft,
          top: 287,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 36, height: 1.5, color: BP.amber),
                  const SizedBox(width: 12),
                  Text(
                    'from code points to pixels · and how Flutter does it',
                    style: BT.mono(20, color: BP.inkDim),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 38, top: 2),
                child: Text(
                  '「テキストレンダリング」',
                  style: BT.sample(17, color: BP.inkDim, height: 1.2).copyWith(locale: _ja, letterSpacing: 1),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: 64,
          top: 11,
          child: Text('flutter / text', style: BT.mono(16, color: BP.inkDim)),
        ),
      ],
    );
  }
}

class _FactoryPainter extends CustomPainter {
  _FactoryPainter(this.clock, this.model, this.io) : super(repaint: clock);

  final ValueNotifier<double> clock;
  final _Model model;
  final _Interaction io;

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    _Frame(canvas, model, t + model.s0, t, io).draw();
  }

  @override
  bool shouldRepaint(_FactoryPainter old) => old.model != model;
}

// ─────────────────────────────────────────────────────────────────────────────
// Model: text layouts, rasters, outlines and the precomputed schedule
// ─────────────────────────────────────────────────────────────────────────────

/// One glyph as drawn in a crate: a real outline, or (for scripts our bundled
/// fonts don't cover) the engine's own stroked rendering.
class _Glyph {
  _Glyph.path(Path this.path, this.points, this.adv) : painter = null, base = 0;
  _Glyph.text(TextPainter this.painter, this.base, this.adv) : path = null, points = const [];

  final Path? path;
  final List<Offset> points;
  final TextPainter? painter;
  final double base;
  final double adv;

  void draw(Canvas c, Offset pen, {required bool filled, required Paint stroke, required Paint fill, Paint? dots}) {
    final p = path;
    if (p != null) {
      c.save();
      c.translate(pen.dx, pen.dy);
      c.drawPath(p, filled ? fill : stroke);
      if (dots != null && !filled && points.isNotEmpty) c.drawPoints(ui.PointMode.points, points, dots);
      c.restore();
    } else {
      painter!.paint(c, Offset(pen.dx, pen.dy - base));
    }
  }
}

/// What rides the belt: one title letter, one marquee word, or one " · ".
class _Unit {
  _Unit(
    this.text,
    this.cps,
    this.script, {
    this.titleIndex = -1,
    this.sep = false,
    this.group = -1,
    this.locale,
  }) : lane = _laneOf(cps.first) {
    color = switch (lane) {
      1 || 2 || 3 => _laneColor[lane],
      _ => script.color,
    };
    label = switch (lane) {
      1 => 'hiragana',
      2 => 'katakana',
      3 => locale == _ja ? 'kanji' : 'han',
      _ => script.label,
    };
  }

  final String text;
  final List<int> cps;
  final Script script;
  final int titleIndex;
  final bool sep;
  final int group; // which marquee entry (a run train before itemize)
  final Locale? locale;
  final int lane;
  late final Color color;
  late final String label;

  bool get isTitle => titleIndex >= 0;
  bool get space => text.trim().isEmpty;

  double w = 46;
  int glyphs = 1;
  bool lineEnd = false;
  double mx = 0; // left edge in the marquee layout
  int slot = -1;

  late TextPainter stamp;
  TextPainter? gid;
  _Glyph? glyph; // title letters
  final minis = <_Glyph>[];
  TextPainter? plate;
  ui.Image? tile;
  Rect tileDst = Rect.zero;
  Path tileGrid = Path();
}

class _Letter {
  _Letter({
    required this.ch,
    required this.index,
    required this.box,
    required this.fill,
    required this.fillAt,
    required this.big,
    required this.bigDst,
    required this.space,
  });

  final String ch;
  final int index;
  final Rect box; // advance box on the shelf
  final TextPainter fill;
  final Offset fillAt;
  final ui.Image? big; // 14 px raster, blown up ×12 while it develops
  final Rect bigDst;
  final bool space;
  double inkTop = _baseline - 0.72 * _titleSize;

  double get cx => box.center.dx;
  Rect get hit => Rect.fromLTRB(box.left, box.top + 30, box.right, _baseline + 12);
}

class _Job {
  _Job(this.i, this.arrive, this.start, this.x) {
    final d = (x - _pickX).abs();
    t1 = start + 0.2; // hook down + grab
    t2 = t1 + 0.14; // lift
    t3 = t2 + 0.16 + d / 4200; // travel out
    t4 = t3 + 0.36; // unfold into the slot
    t5 = t4 + 0.08; // release
    end = t5 + 0.12 + d / 4800; // travel back
  }

  final int i;
  final double arrive;
  final double start;
  final double x;
  late final double t1, t2, t3, t4, t5, end;
}

class _Model {
  _Model(this.sg, this.kufi) {
    _buildTitle();
    _buildMarquee();
    _buildTitleUnits();
    for (final u in mUnits) {
      _prepUnit(u);
    }
    _schedule();
    _buildMisc();
    back = _recordBack();
    front = _recordFront();
  }

  final FontData? sg;
  final FontData? kufi;
  final _painters = <TextPainter>[];
  final _images = <ui.Image>[];
  late final ui.Picture back;
  late final ui.Picture front;

  // Elevator geometry.
  static final double chainLen = (_loadY - _sprTop) + math.pi * _sprR + (_sprBot - _sprTop) + math.pi * _sprR + (_sprBot - _loadY);
  static final double spacing = chainLen / _buckets;
  static final double ve = spacing / _tc;

  TextPainter _tp(InlineSpan span) {
    final p = TextPainter(text: span, textDirection: TextDirection.ltr)..layout();
    _painters.add(p);
    return p;
  }

  ui.Image _raster(TextPainter p) {
    final w = (p.width + 2).ceil();
    final h = p.height.ceil();
    final rec = ui.PictureRecorder();
    p.paint(Canvas(rec), const Offset(1, 0));
    final pic = rec.endRecording();
    final img = pic.toImageSync(math.max(1, w), math.max(1, h));
    pic.dispose();
    _images.add(img);
    return img;
  }

  static double _boxLeft(TextPainter p, int start, int end) {
    final b = p.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end));
    if (b.isEmpty) return 0;
    return b.map((e) => e.left).reduce(math.min);
  }

  // ── Title ──────────────────────────────────────────────────────────────────
  final letters = <_Letter>[];
  late final TextPainter plan;
  late final Offset planAt;
  late final double lineTop;
  late final List<int> solid; // non-space letter indices

  static TextStyle _titleStyle(double size, {Paint? fg}) => TextStyle(
    fontFamily: BP.display,
    fontSize: size,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation.weight(500)],
    letterSpacing: -3 * size / _titleSize,
    color: fg == null ? BP.ink : null,
    foreground: fg,
  );

  void _buildTitle() {
    final full = TextPainter(
      text: TextSpan(text: _title, style: _titleStyle(_titleSize)),
      textDirection: TextDirection.ltr,
    )..layout();
    final base = full.computeLineMetrics().first.baseline;
    lineTop = _baseline - base;
    planAt = Offset(_titleLeft, lineTop);
    plan = _tp(TextSpan(
      text: _title,
      style: _titleStyle(
        _titleSize,
        fg: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = BP.line.withValues(alpha: 0.5),
      ),
    ));
    var i = 0;
    var n = 0;
    for (final g in _title.characters) {
      final r = full.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + g.length)).first.toRect();
      final space = g.trim().isEmpty;
      final fill = _tp(TextSpan(text: g, style: _titleStyle(_titleSize)));
      final ownL = _boxLeft(fill, 0, g.length);
      final fillBase = fill.computeLineMetrics().first.baseline;
      final xl = _titleLeft + r.left;
      ui.Image? big;
      var dst = Rect.zero;
      if (!space) {
        final small = TextPainter(
          text: TextSpan(text: g, style: _titleStyle(_titleSize / 12)),
          textDirection: TextDirection.ltr,
        )..layout();
        final sl = _boxLeft(small, 0, g.length);
        final sb = small.computeLineMetrics().first.baseline;
        big = _raster(small);
        small.dispose();
        dst = Rect.fromLTWH(xl - (1 + sl) * 12, _baseline - sb * 12, big.width * 12.0, big.height * 12.0);
      }
      letters.add(_Letter(
        ch: g,
        index: n++,
        box: Rect.fromLTRB(xl, lineTop, xl + r.width, lineTop + full.height),
        fill: fill,
        fillAt: Offset(xl - ownL, _baseline - fillBase),
        big: big,
        bigDst: dst,
        space: space,
      ));
      i += g.length;
    }
    full.dispose();
    solid = [for (final l in letters) if (!l.space) l.index];
  }

  // ── Units ─────────────────────────────────────────────────────────────────
  final tUnits = <_Unit>[];
  final mUnits = <_Unit>[];
  late final TextPainter marquee;
  late final double mW;
  late final double vM;
  late final int nC; // belt slots per marquee repetition
  late final List<int> mSlots;
  late final List<int> mPrefix;

  void _buildTitleUnits() {
    for (final l in letters) {
      final cp = l.ch.runes.first;
      final u = _Unit(l.ch, [cp], l.space ? Script.common : Script.latin, titleIndex: l.index)
        ..w = 46
        ..lineEnd = l.index == letters.length - 1;
      final f = sg;
      if (f != null && f.has(cp)) {
        final gid = f.glyphId(cp);
        u.gid = _tp(TextSpan(text: '#$gid', style: BT.mono(8, color: BP.amber)));
        final o = f.outline(gid);
        if (!l.space && o.contours.isNotEmpty) l.inkTop = _baseline - o.bounds.bottom * _titleSize / f.unitsPerEm;
      }
      _prepUnit(u);
      tUnits.add(u);
    }
  }

  void _buildMarquee() {
    final style = BT.sample(30, height: 1.25);
    final spans = <InlineSpan>[];
    final ranges = <(int, int)>[];
    var at = 0;
    for (final (text, loc) in _mEntries) {
      spans
        ..add(TextSpan(text: text, style: loc == null ? null : TextStyle(locale: loc)))
        ..add(const TextSpan(text: ' · '));
      ranges.add((at, at + text.length));
      at += text.length + 3;
    }
    marquee = _tp(TextSpan(style: style, children: spans));
    final two = TextPainter(
      text: TextSpan(style: style, children: [...spans, ...spans]),
      textDirection: TextDirection.ltr,
    )..layout();
    final hb = two.getBoxesForSelection(TextSelection(baseOffset: at, extentOffset: at + 1));
    mW = hb.isEmpty ? marquee.width + 20 : hb.first.left;
    two.dispose();
    // Itemize each entry into runs of one script (Japanese: kana and kanji
    // split, the way ICU/SkParagraph split a paragraph before shaping).
    for (var e = 0; e < _mEntries.length; e++) {
      final (text, loc) = _mEntries[e];
      final (a, b) = ranges[e];
      var i = 0;
      var start = 0;
      (int, Script)? key;
      void flush(int end) {
        if (end <= start) return;
        final run = text.substring(start, end);
        mUnits.add(
          _Unit(run, run.runes.toList(), scriptOfCluster(run.characters.first), group: e, locale: loc)
            ..mx = _boxLeft(marquee, a + start, a + end)
            ..glyphs = run.characters.length,
        );
        start = end;
      }

      for (final g in text.characters) {
        final lane = _laneOf(g.runes.first);
        final k = (lane, lane == 0 || lane == 4 ? scriptOfCluster(g) : Script.common);
        if (key != null && k != key) flush(i);
        key = k;
        i += g.length;
      }
      flush(i);
      mUnits.add(
        _Unit(' · ', const [0xB7], Script.common, sep: true, group: e)
          ..mx = _boxLeft(marquee, b, b + 3)
          ..glyphs = 3,
      );
    }
    nC = math.max(16, (mW / (46 * _tc)).round());
    vM = mW / (nC * _tc);
    mSlots = List<int>.filled(nC, -1);
    mPrefix = List<int>.filled(nC + 1, 0);
    // Each run rides the slot that reaches the print head just before its
    // text has to come out; separators only where there's room.
    var last = -1;
    for (var j = 0; j < mUnits.length; j++) {
      final u = mUnits[j];
      if (u.sep) continue;
      final q = math.max((u.mx * nC / mW).floor(), last + 1);
      if (q >= nC) continue;
      mSlots[q] = j;
      u.slot = last = q;
    }
    for (var j = 0; j < mUnits.length; j++) {
      final u = mUnits[j];
      if (!u.sep) continue;
      final q = (u.mx * nC / mW).floor();
      final prev = j > 0 ? mUnits[j - 1].slot : -1;
      final next = j + 1 < mUnits.length ? mUnits[j + 1].slot : nC;
      if (q > prev && (next < 0 || q < next) && q < nC && mSlots[q] == -1) {
        mSlots[q] = j;
        u.slot = q;
      }
    }
    // Greedy (first-fit) line breaking, like SkParagraph: break opportunities
    // after the spaces of each " · ".
    const maxLine = 330.0;
    var lineW = 0.0;
    for (var j = 0; j < mUnits.length; j++) {
      final next = j + 1 < mUnits.length ? mUnits[j + 1].mx : mW;
      lineW += next - mUnits[j].mx;
      if (!mUnits[j].sep) continue;
      var k = j + 1;
      while (k < mUnits.length && !mUnits[k].sep) {
        k++;
      }
      final segEnd = k + 1 < mUnits.length ? mUnits[k + 1].mx : mW;
      if (j == mUnits.length - 1 || lineW + (segEnd - next) > maxLine) {
        mUnits[j].lineEnd = true;
        lineW = 0;
      }
    }
    for (var j = mUnits.length - 1; j > 0; j--) {
      if (mUnits[j].lineEnd && mUnits[j].slot < 0) {
        mUnits[j].lineEnd = false;
        mUnits[j - 1].lineEnd = true;
      }
    }
    for (var q = 0; q < nC; q++) {
      final j = mSlots[q];
      mPrefix[q + 1] = mPrefix[q] + (j < 0 ? 0 : mUnits[j].glyphs);
    }
  }

  _Glyph _glyph(int cp, double em, {double stroke = 0.8, Locale? locale}) {
    final sc = scriptOf(cp);
    FontData? f;
    if (sc == Script.arabic) {
      if (kufi?.has(cp) ?? false) f = kufi;
    } else if (sg?.has(cp) ?? false) {
      f = sg;
    }
    if (f != null) {
      final k = em / f.unitsPerEm;
      final gid = f.glyphId(cp);
      final o = f.outline(gid);
      return _Glyph.path(
        o.toPath(scale: k),
        [for (final c in o.contours) for (final p in c) if (p.onCurve) Offset(p.x * k, -p.y * k)],
        f.advance(gid) * k,
      );
    }
    final p = _tp(TextSpan(
      text: String.fromCharCode(cp),
      style: TextStyle(
        fontFamily: BP.display,
        fontFamilyFallback: const [BP.arabic],
        fontSize: em,
        locale: locale,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = BP.ink,
      ),
    ));
    return _Glyph.text(p, p.computeLineMetrics().first.baseline, p.width);
  }

  String _hex(int cp) => 'U+${cp.toRadixString(16).toUpperCase().padLeft(4, '0')}';

  void _prepUnit(_Unit u) {
    final n = u.cps.length;
    if (!u.isTitle) u.w = u.sep ? 26 : (10.0 * n + 12).clamp(32.0, 64.0);
    u.stamp = _tp(TextSpan(
      text: n == 1 ? _hex(u.cps.first) : '${_hex(u.cps.first)} +${n - 1}',
      style: BT.mono(8, color: BP.inkDim),
    ));
    ui.Image? img;
    if (u.isTitle) {
      u.glyph = _glyph(u.cps.first, 28, stroke: 0.9);
      if (!u.space) {
        final tp = TextPainter(text: TextSpan(text: u.text, style: _titleStyle(8)), textDirection: TextDirection.ltr)..layout();
        img = _raster(tp);
        tp.dispose();
      }
    } else {
      for (final cp in u.cps) {
        u.minis.add(_glyph(cp, 13, locale: u.locale));
      }
      final shown = u.sep ? '·' : u.text;
      u.plate = _tp(TextSpan(text: shown, style: BT.sample(15).copyWith(locale: u.locale)));
      final tp = TextPainter(
        text: TextSpan(text: shown, style: BT.sample(11, height: 1.45).copyWith(locale: u.locale)),
        textDirection: TextDirection.ltr,
      )..layout();
      img = _raster(tp);
      tp.dispose();
    }
    labels.putIfAbsent(u.label, () => _tp(TextSpan(text: u.label, style: BT.mono(11, color: u.color))));
    u.tile = img;
    if (img != null) {
      final iw = img.width.toDouble(), ih = img.height.toDouble();
      var k = math.min((u.w - 6) / iw, (_crateH - 6) / ih);
      if (k > 2) k = k.floorToDouble();
      final dw = iw * k, dh = ih * k;
      u.tileDst = Rect.fromLTWH((u.w - dw) / 2, (_crateH - dh) / 2, dw, dh);
      final grid = Path();
      for (var x = 0; x <= img.width; x++) {
        grid
          ..moveTo(x * k, 0)
          ..lineTo(x * k, dh);
      }
      for (var y = 0; y <= img.height; y++) {
        grid
          ..moveTo(0, y * k)
          ..lineTo(dw, y * k);
      }
      u.tileGrid = grid;
    }
  }

  _Unit? unitAt(int k) {
    if (k < 0) return null;
    if (k < tUnits.length) return tUnits[k];
    if (k < _kM) return null;
    final j = mSlots[(k - _kM) % nC];
    return j < 0 ? null : mUnits[j];
  }

  int glyphsUpTo(int n) {
    if (n < 0) return 0;
    var g = math.min(n + 1, tUnits.length);
    if (n >= _kM) {
      final nn = n - _kM + 1;
      g += (nn ~/ nC) * mPrefix[nC] + mPrefix[nn % nC];
    }
    return g;
  }

  // ── Schedule ─────────────────────────────────────────────────────────────
  final jobs = <_Job>[];
  late final double s0;
  late final double sDone;
  late final double sM0;

  static double sLoad(int k) => (k + _slots + _mv) * _tc;
  static double sTopOf(int k) => sLoad(k) + (_loadY - _rackY) / ve;
  static double sTickOf(int k) => sLoad(k) + (_loadY - _tickY) / ve;

  /// When unit [k]'s text starts coming out of the print head.
  double tauOf(int k) => sM0 + (unitAt(k)!.mx + ((k - _kM) ~/ nC) * mW) / vM;

  void _schedule() {
    var free = -1e9;
    for (var i = 0; i < letters.length; i++) {
      final arrive = sTopOf(i) + 0.35;
      final j = _Job(i, arrive, math.max(arrive, free), letters[i].cx);
      jobs.add(j);
      free = j.end;
    }
    // Start the clock with the factory already running: the first tile is
    // just reaching the rack.
    s0 = jobs.first.arrive - 0.6;
    sDone = jobs.last.t4 + 0.7;
    sM0 = sTickOf(_kM) + 0.45;
  }

  // Gantry inspections once the title is done.
  static const qcPeriod = 37.0;
  double get qcStart => sDone + 12;
  int qcLetter(int q) => solid[(_rnd(q, 31) * solid.length).floor().clamp(0, solid.length - 1)];

  /// Returns the chain point and the direction of travel [d] px along the loop
  /// from the loading point.
  (Offset, Offset) chainAt(double d) {
    d %= chainLen;
    const up1 = _loadY - _sprTop;
    const arc = math.pi * _sprR;
    const run = _sprBot - _sprTop;
    if (d < up1) return (Offset(_chainL, _loadY - d), const Offset(0, -1));
    d -= up1;
    if (d < arc) {
      final a = math.pi + d / _sprR;
      return (Offset(_sprX + math.cos(a) * _sprR, _sprTop + math.sin(a) * _sprR), Offset(-math.sin(a), math.cos(a)));
    }
    d -= arc;
    if (d < run) return (Offset(_chainR, _sprTop + d), const Offset(0, 1));
    d -= run;
    if (d < arc) {
      final a = d / _sprR;
      return (Offset(_sprX + math.cos(a) * _sprR, _sprBot + math.sin(a) * _sprR), Offset(-math.sin(a), math.cos(a)));
    }
    d -= arc;
    return (Offset(_chainL, _sprBot - d), const Offset(0, -1));
  }

  // ── Labels ───────────────────────────────────────────────────────────────
  final labels = <String, TextPainter>{};
  late final TextPainter hexRoll;
  late final TextPainter glyphsLabel;
  final fontCells = <TextPainter>[];
  final plates = <TextPainter>[];

  void _buildMisc() {
    final cps = <String>{};
    for (final r in (_title + _mEntries.map((e) => e.$1).join()).runes) {
      if (r != 0x20) cps.add(_hex(r));
    }
    hexRoll = _tp(TextSpan(text: '${cps.join('  ')}  ', style: BT.mono(10, color: BP.lineDim)));
    glyphsLabel = _tp(TextSpan(text: 'glyphs', style: BT.mono(12, color: BP.inkDim)));
    for (final (g, loc) in _cells) {
      fontCells.add(_tp(TextSpan(text: g, style: BT.sample(15, color: BP.inkDim).copyWith(locale: loc))));
    }
    const names = ['itemize', 'fonts', 'shape', 'wrap', 'raster'];
    for (var i = 0; i < names.length; i++) {
      plates.add(_tp(TextSpan(children: [
        TextSpan(text: '0${i + 1} ', style: BT.mono(13, color: BP.inkFaint)),
        TextSpan(text: names[i], style: BT.mono(14, color: BP.line)),
      ])));
    }
    plates.add(_tp(TextSpan(text: 'unicode', style: BT.mono(14, color: BP.line))));
  }

  /// The fonts machine's glass: one sample per font it can hand out.
  static const _cells = <(String, Locale?)>[
    ('Aa', null), ('あ', _ja), ('ア', _ja), ('字', _ja),
    ('Я', null), ('ب', null), ('ש', null), ('क', null),
    ('ก', null), ('한', null), ('你', _zh), ('👋', null),
  ];

  static Rect cellRect(int i) => Rect.fromLTWH(518 + (i % 4) * 25.0, 460 + (i ~/ 4) * 25.0, 25, 25);

  static int fontCell(_Unit u) => switch (u.lane) {
    1 => 1,
    2 => 2,
    3 => u.locale == _zh ? 10 : 3,
    _ => switch (u.script) {
      Script.cyrillic => 4,
      Script.arabic => 5,
      Script.hebrew => 6,
      Script.devanagari => 7,
      Script.thai => 8,
      Script.hangul => 9,
      Script.emoji => 11,
      _ => 0,
    },
  };

  int _count = -1;
  TextPainter? _countTp;
  double countChangedAt = -1e9;

  TextPainter countPainter(int v, double t) {
    if (v != _count || _countTp == null) {
      if (_count >= 0) countChangedAt = t;
      _countTp?.dispose();
      _count = v;
      _countTp = TextPainter(
        text: TextSpan(text: AnimatedCount.format(v), style: BT.mono(18, color: BP.amber, weight: 500)),
        textDirection: TextDirection.ltr,
      )..layout();
    }
    return _countTp!;
  }

  void dispose() {
    for (final p in _painters) {
      p.dispose();
    }
    for (final i in _images) {
      i.dispose();
    }
    _countTp?.dispose();
    back.dispose();
    front.dispose();
  }

  // ── Static drawing (recorded once) ─────────────────────────────────────────

  ui.Picture _recordBack() {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final f = Paint();
    Paint s(Color col, [double w = 1.2]) => p
      ..color = col
      ..strokeWidth = w;
    Paint fl(Color col) => f..color = col;
    void box(Rect r, {Color col = BP.line, double w = 1.3}) {
      c.drawRect(r, fl(BP.panel));
      c.drawRect(r, s(col, w));
    }

    void plate(int i, double cx, double y) {
      final t = plates[i];
      final r = Rect.fromCenter(center: Offset(cx, y), width: t.width + 18, height: 22);
      box(r, col: BP.lineDim, w: 1);
      t.paint(c, Offset(r.left + 9, r.top + (22 - t.height) / 2));
    }

    // Gantry rail (an I-beam hung from the ceiling).
    for (final x in [180.0, 580.0, 980.0, 1380.0]) {
      c.drawLine(Offset(x, 0), Offset(x, 36), s(BP.lineDim, 1));
      c.drawRect(Rect.fromLTWH(x - 8, 33, 16, 5), s(BP.lineDim, 1));
    }
    box(const Rect.fromLTRB(52, 38, 1548, 54), w: 1.2);
    c.drawLine(const Offset(52, 42), const Offset(1548, 42), s(BP.lineDim, 1));
    c.drawLine(const Offset(52, 50), const Offset(1548, 50), s(BP.lineDim, 1));
    final rivets = <Offset>[for (var x = 68.0; x < 1540; x += 48) Offset(x, 46)];
    c.drawPoints(ui.PointMode.points, rivets, s(BP.lineDim, 2.4));
    box(const Rect.fromLTRB(46, 36, 52, 58), w: 1);
    box(const Rect.fromLTRB(1548, 36, 1554, 58), w: 1);

    // The output shelf under the title (its top edge is the baseline).
    for (final x in [44.0, 1226.0]) {
      c.drawLine(Offset(x, 54), Offset(x, _shelfY), s(BP.lineDim, 1));
    }
    box(const Rect.fromLTRB(36, _shelfY, 1234, _shelfY + 7), w: 1.2);
    c.drawPoints(ui.PointMode.points, [for (var x = 52.0; x < 1230; x += 40) Offset(x, _shelfY + 3.5)], s(BP.lineDim, 2));
    for (final l in letters) {
      c.drawLine(Offset(l.box.left, _shelfY + 7), Offset(l.box.left, _shelfY + 13), s(BP.lineDim, 1));
    }
    c.drawLine(Offset(letters.last.box.right, _shelfY + 7), Offset(letters.last.box.right, _shelfY + 13), s(BP.lineDim, 1));

    // Marquee track + print head.
    c.drawLine(const Offset(_mLeft, _mTop), const Offset(_mRight, _mTop), s(BP.lineDim, 1.2));
    c.drawLine(const Offset(_mLeft, _mBot), const Offset(_mRight, _mBot), s(BP.lineDim, 1.2));
    for (final y in [_mTop, _mBot]) {
      c.drawCircle(Offset(_mLeft, y), 3.5, s(BP.lineDim, 1));
    }
    box(const Rect.fromLTRB(_mRight, _tickY, 1430, 410), w: 1.3);
    final nozzle = Path()
      ..moveTo(_mRight, 366)
      ..lineTo(_mRight - 8, 371)
      ..lineTo(_mRight - 8, 383)
      ..lineTo(_mRight, 388);
    c.drawPath(nozzle, s(BP.line, 1.2));
    c.drawCircle(const Offset(1420, 354), 4, s(BP.lineDim, 1));
    for (var y = 372.0; y < 404; y += 7) {
      c.drawLine(Offset(1392, y), Offset(1420, y), s(BP.lineFaint, 1));
    }

    // Rack for finished title tiles.
    for (final x in [1240.0, 1404.0]) {
      c.drawLine(Offset(x, 54), Offset(x, _rackY), s(BP.lineDim, 1));
    }
    c.drawLine(const Offset(1236, _rackY), const Offset(1428, _rackY), s(BP.line, 2));
    c.drawLine(const Offset(1236, _rackY - 6), const Offset(1236, _rackY), s(BP.line, 2));

    // Elevator tower.
    for (final x in [1490.0, 1514.0]) {
      c.drawLine(Offset(x, 96), Offset(x, _floor), s(BP.lineDim, 1));
    }
    final brace = Path()..moveTo(1490, 160);
    for (var y = 160.0, l = true; y < 770; y += 30, l = !l) {
      brace.lineTo(l ? 1514 : 1490, y + 30);
    }
    c.drawPath(brace, s(BP.lineFaint, 1));
    c.drawLine(const Offset(_chainL, _sprTop), const Offset(_chainL, _sprBot), s(BP.lineDim, 1));
    c.drawLine(const Offset(_chainR, _sprTop), const Offset(_chainR, _sprBot), s(BP.lineDim, 1));
    for (final y in [_sprTop, _sprBot]) {
      c.drawCircle(Offset(_sprX, y), _sprR, fl(BP.panel));
      c.drawCircle(Offset(_sprX, y), _sprR, s(BP.line, 1.3));
      c.drawCircle(Offset(_sprX, y), 4, s(BP.line, 1.2));
    }

    // Belt: surface (seen slightly from above), three lanes, frame, legs.
    const bl = 96.0, br = 1424.0;
    c.drawRect(const Rect.fromLTRB(bl, 654, br, 703), fl(BP.panel));
    c.drawLine(const Offset(bl, 654), const Offset(br, 654), s(BP.line, 1.3));
    c.drawLine(const Offset(bl, 703), const Offset(br, 703), s(BP.line, 1.3));
    for (var i = 0; i < 4; i++) {
      c.drawLine(Offset(bl, _laneY[i]), Offset(br, _laneY[i]), s(BP.lineFaint, 1));
    }
    for (var i = 0; i < 5; i++) {
      final lane = Path()
        ..moveTo(_sx(_sSort + 0.5), _laneY[i] - 4.5)
        ..lineTo(_sx(11.3), _laneY[i] - 4.5);
      c.drawPath(dashPath(lane, dash: 10, gap: 8), s(_laneColor[i].withValues(alpha: 0.6), 1.4));
    }
    box(const Rect.fromLTRB(bl, 703, br, 711), w: 1.2);
    c.drawLine(const Offset(bl, 729), const Offset(br, 729), s(BP.lineDim, 1));
    for (final x in [112.0, 330.0, 560.0, 790.0, 1010.0, 1170.0, 1416.0]) {
      c.drawLine(Offset(x - 3, 711), Offset(x - 3, _floor), s(BP.lineDim, 1.2));
      c.drawLine(Offset(x + 3, 711), Offset(x + 3, _floor), s(BP.lineDim, 1.2));
      c.drawLine(Offset(x - 8, _floor - 1), Offset(x + 8, _floor - 1), s(BP.lineDim, 1.6));
    }

    // Floor.
    c.drawLine(const Offset(24, _floor), const Offset(1576, _floor), s(BP.line, 1.4));
    final hatch = Path();
    for (var x = 30.0; x < 1576; x += 12) {
      hatch
        ..moveTo(x, _floor)
        ..lineTo(x - 7, _floor + 8);
    }
    c.drawPath(hatch, s(BP.lineFaint, 1));

    // Unicode hopper + chute, ladder, sack of code points.
    final funnel = Path()
      ..moveTo(60, 440)
      ..lineTo(200, 440)
      ..lineTo(158, 524)
      ..lineTo(102, 524)
      ..close();
    c.drawPath(funnel, fl(BP.panel));
    c.drawPath(funnel, s(BP.line, 1.4));
    box(const Rect.fromLTRB(102, 524, 158, 600), w: 1.3);
    c.drawLine(const Offset(98, 600), const Offset(162, 600), s(BP.line, 2));
    c.drawRect(const Rect.fromLTRB(78, 447, 182, 469), s(BP.lineDim, 1));
    final uni = plates[5];
    uni.paint(c, Offset(130 - uni.width / 2, 477));
    c.drawCircle(const Offset(146, 540), 4, s(BP.lineDim, 1));
    for (final x in [28.0, 50.0]) {
      c.drawLine(Offset(x, 452), Offset(x, _floor), s(BP.lineDim, 1.3));
    }
    for (var y = 502.0; y <= _floor; y += 16) {
      c.drawLine(Offset(28, y), Offset(50, y), s(BP.lineDim, 1.1));
    }
    final sack = Path()
      ..moveTo(62, 544)
      ..quadraticBezierTo(54, 572, 62, 584)
      ..lineTo(84, 584)
      ..quadraticBezierTo(92, 572, 84, 544)
      ..close();
    c.drawPath(sack, fl(BP.panel));
    c.drawPath(sack, s(BP.lineDim, 1.1));
    c.drawLine(const Offset(58, 544), const Offset(88, 544), s(BP.lineDim, 1.1));

    // 01 itemize: sorter with a screen, lane lamps, a pick-and-place arm.
    final sortRoof = Path()
      ..moveTo(292, 504)
      ..lineTo(310, 488)
      ..lineTo(390, 488)
      ..lineTo(408, 504)
      ..close();
    c.drawPath(sortRoof, fl(BP.panel));
    c.drawPath(sortRoof, s(BP.line, 1.3));
    box(const Rect.fromLTRB(292, 504, 408, 612));
    c.drawRect(const Rect.fromLTRB(304, 516, 396, 542), s(BP.lineDim, 1));
    for (var i = 0; i < 5; i++) {
      c.drawCircle(Offset(314.0 + i * 15, 590), 4, s(_laneColor[i].withValues(alpha: 0.7), 1));
    }
    c.drawRect(const Rect.fromLTRB(340, 606, 360, 612), s(BP.line, 1));
    plate(0, 350, 468);

    // 02 fonts: a vending machine of glyphs.
    box(const Rect.fromLTRB(512, 452, 630, 612));
    c.drawRect(const Rect.fromLTRB(516, 458, 620, 537), s(BP.lineDim, 1));
    for (var i = 0; i < _cells.length; i++) {
      final r = cellRect(i);
      c.drawRect(r.deflate(1.5), s(BP.lineFaint, 1));
      final t = fontCells[i];
      final k = math.min(1.0, 19 / math.max(t.width, t.height));
      c.save();
      c.translate(r.center.dx, r.center.dy);
      c.scale(k);
      t.paint(c, Offset(-t.width / 2, -t.height / 2));
      c.restore();
    }
    for (var i = 0; i < 3; i++) {
      c.drawCircle(Offset(532.0 + i * 14, 550), 3.5, s(BP.lineDim, 1));
    }
    c.drawRect(const Rect.fromLTRB(590, 544, 612, 556), s(BP.lineDim, 1));
    c.drawRect(const Rect.fromLTRB(534, 564, 600, 576), s(BP.lineDim, 1));
    final chute = Path()
      ..moveTo(556, 596)
      ..lineTo(586, 596)
      ..lineTo(580, 612)
      ..lineTo(562, 612)
      ..close();
    c.drawPath(chute, s(BP.line, 1.2));
    plate(1, 571, 432);

    // 03 shape: stamping press.
    box(const Rect.fromLTRB(742, 478, 840, 510));
    box(const Rect.fromLTRB(746, 510, 756, 612), w: 1.1);
    box(const Rect.fromLTRB(826, 510, 836, 612), w: 1.1);
    c.drawCircle(const Offset(822, 464), 14, fl(BP.panel));
    c.drawCircle(const Offset(822, 464), 14, s(BP.line, 1.3));
    c.drawLine(const Offset(822, 464), const Offset(800, 478), s(BP.lineDim, 1));
    c.drawCircle(const Offset(760, 494), 9, s(BP.lineDim, 1));
    plate(2, 791, 432);
    final anvil = Path()
      ..moveTo(844, 772)
      ..lineTo(872, 772)
      ..lineTo(866, 778)
      ..lineTo(862, 778)
      ..lineTo(864, 790)
      ..lineTo(852, 790)
      ..lineTo(854, 778)
      ..lineTo(848, 778)
      ..close();
    c.drawPath(anvil, fl(BP.panel));
    c.drawPath(anvil, s(BP.line, 1.2));

    // 04 wrap: guillotine with a width ruler.
    box(const Rect.fromLTRB(1004, 488, 1092, 514));
    for (final x in [1008.0, 1088.0]) {
      c.drawLine(Offset(x - 2, 514), Offset(x - 2, 612), s(BP.line, 1.2));
      c.drawLine(Offset(x + 2, 514), Offset(x + 2, 612), s(BP.line, 1.2));
    }
    c.drawLine(const Offset(1034, 514), const Offset(1034, 600), s(BP.lineFaint, 1));
    c.drawLine(const Offset(1062, 514), const Offset(1062, 600), s(BP.lineFaint, 1));
    for (var x = 1010.0; x < 1090; x += 8) {
      c.drawLine(Offset(x, 514), Offset(x, (x - 1010) % 32 == 0 ? 520 : 517), s(BP.lineDim, 1));
    }
    c.drawLine(const Offset(1092, 500), const Offset(1104, 500), s(BP.lineDim, 1.2));
    c.drawCircle(const Offset(1106, 500), 5, s(BP.line, 1.2));
    plate(3, 1048, 468);

    // Consoles on the floor.
    box(const Rect.fromLTRB(380, 752, 406, _floor), w: 1.1);
    box(const Rect.fromLTRB(604, 748, 632, _floor), w: 1.1);
    for (var i = 0; i < 3; i++) {
      c.drawCircle(Offset(612.0 + i * 8, 758), 2.5, s(BP.lineDim, 1));
    }
    c.drawLine(const Offset(1096, 790), const Offset(1104, 782), s(BP.lineDim, 1.2));
    // Coffee crate.
    box(const Rect.fromLTRB(918, 776, 946, _floor), w: 1.1);
    c.drawLine(const Offset(918, 776), const Offset(946, 790), s(BP.lineFaint, 1));
    // Coal pile for the oven.
    final coal = Path()
      ..moveTo(1128, _floor)
      ..quadraticBezierTo(1140, 772, 1152, _floor);
    c.drawPath(coal, s(BP.lineDim, 1.2));
    // Firebox under the oven.
    box(const Rect.fromLTRB(1196, 742, 1246, _floor), w: 1.2);
    c.drawRect(const Rect.fromLTRB(1206, 754, 1236, 772), s(BP.line, 1));
    c.drawLine(const Offset(1221, 742), const Offset(1221, 706), s(BP.lineDim, 1.2));

    // Glyph counter board.
    box(const Rect.fromLTRB(_board, 722, _board + 86, 772), w: 1.2);
    c.drawLine(const Offset(_board + 8, 772), const Offset(_board + 8, _floor), s(BP.lineDim, 1.2));
    c.drawLine(const Offset(_board + 78, 772), const Offset(_board + 78, _floor), s(BP.lineDim, 1.2));
    glyphsLabel.paint(c, const Offset(_board + 8, 726));

    return rec.endRecording();
  }

  /// Parts that sit in front of the belt: the oven body (with a window).
  ui.Picture _recordFront() {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Paint s(Color col, [double w = 1.2]) => p
      ..color = col
      ..strokeWidth = w;
    const body = Rect.fromLTRB(1186, 486, 1350, 706);
    const win = Rect.fromLTRB(1212, 598, 1324, 668);
    final shell = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(body)
      ..addRect(win);
    c.drawPath(shell, Paint()..color = BP.panel);
    c.drawRect(body, s(BP.line, 1.4));
    c.drawRect(win, s(BP.line, 1.3));
    c.drawRect(win.inflate(5), s(BP.lineDim, 1));
    // Chimney.
    c.drawRect(const Rect.fromLTRB(1314, 446, 1332, 486), Paint()..color = BP.panel);
    c.drawRect(const Rect.fromLTRB(1314, 446, 1332, 486), s(BP.line, 1.3));
    c.drawLine(const Offset(1310, 446), const Offset(1336, 446), s(BP.line, 2));
    // Gauge & lamps.
    c.drawCircle(const Offset(1224, 526), 15, s(BP.line, 1.2));
    for (var i = 0; i <= 6; i++) {
      final a = math.pi * (0.8 + i * 0.233);
      c.drawLine(
        Offset(1224 + math.cos(a) * 11, 526 + math.sin(a) * 11),
        Offset(1224 + math.cos(a) * 14, 526 + math.sin(a) * 14),
        s(BP.lineDim, 1),
      );
    }
    for (var i = 0; i < 3; i++) {
      c.drawCircle(Offset(1290.0 + i * 16, 520), 4.5, s(BP.lineDim, 1));
    }
    // Vents.
    for (var y = 680.0; y < 700; y += 6) {
      c.drawLine(Offset(1262, y), Offset(1330, y), s(BP.lineFaint, 1));
    }
    // Belt openings.
    c.drawRect(const Rect.fromLTRB(1186, 620, 1192, 703), s(BP.lineDim, 1));
    c.drawRect(const Rect.fromLTRB(1344, 620, 1350, 703), s(BP.lineDim, 1));
    final t = plates[4];
    final r = Rect.fromCenter(center: const Offset(1250, 468), width: t.width + 18, height: 22);
    c.drawRect(r, Paint()..color = BP.panel);
    c.drawRect(r, s(BP.lineDim, 1));
    t.paint(c, Offset(r.left + 9, r.top + (22 - t.height) / 2));
    return rec.endRecording();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// One painted frame
// ─────────────────────────────────────────────────────────────────────────────

class _Frame extends FactoryInk {
  _Frame(super.c, this.m, this.s, this.t, this.io) : cyc = (s / _tc).floor() {
    ph = s / _tc - cyc;
    e = ph < _mv ? _eio(ph / _mv) : 1.0;
    belt = (cyc - 1 + e) * _pitch;
  }

  final _Model m;
  final double s; // simulation time
  final double t; // wall time since the slide appeared
  final _Interaction io;
  final int cyc;
  late final double ph;
  late final double e;
  late final double belt;

  static final _pix = Paint()..filterQuality = FilterQuality.none;
  static final _sheen = Paint()..blendMode = BlendMode.srcATop;

  bool get dwell => ph >= _mv;

  /// Progress through [a, b] of the dwell (0..1 fractions of it).
  double dw(double a, double b) => _seg(ph, _mv + a * (1 - _mv), _mv + b * (1 - _mv));

  /// How far the item at [pos] is through the job at station [st].
  double prog(double pos, int st, double a, double b) {
    if (pos < st - 1e-6) return 0;
    if (pos > st + 1e-6) return 1;
    return dwell ? dw(a, b) : 1;
  }

  double boost(int machine) => io.machine == machine ? _bump(_seg(t, io.machineAt, io.machineAt + 1.2)) : 0;

  void draw() {
    c.drawPicture(m.back);
    hopper();
    beltMotion();
    elevatorChain();
    items();
    sorter();
    fontsMachine();
    press();
    cutter();
    c.drawPicture(m.front);
    oven();
    elevatorTrays();
    printHead();
    marquee();
    title();
    rack();
    gantry();
    workers();
    counter();
  }

  // ── Belt & items ───────────────────────────────────────────────────────────

  void beltMotion() {
    final slats = Path();
    const gap = 22.0;
    for (var x = 100 + belt % gap; x < 1422; x += gap) {
      slats
        ..moveTo(x, 656)
        ..lineTo(x - 6, 701);
    }
    c.drawPath(slats, st(BP.lineFaint, 1));
    final rollers = Path();
    final a = belt / 6;
    final d = Offset(math.cos(a) * 6, math.sin(a) * 6);
    for (var x = 112.0; x < 1418; x += 38) {
      rollers
        ..addOval(Rect.fromCircle(center: Offset(x, 719), radius: 6))
        ..moveTo(x - d.dx, 719 - d.dy)
        ..lineTo(x + d.dx, 719 + d.dy)
        ..moveTo(x - d.dy, 719 + d.dx)
        ..lineTo(x + d.dy, 719 - d.dx);
    }
    c.drawPath(rollers, st(BP.lineDim, 1.1));
  }

  void items() {
    final list = <(int, _Unit, Rect, double, bool)>[];
    for (var k = cyc - _slots; k <= cyc; k++) {
      final u = m.unitAt(k);
      if (u == null) continue;
      final pos = (cyc - k - 1) + e;
      if (pos < -1e-6 || pos > _slots - 1e-6) continue;
      final x = _sx(pos);
      final sortP = prog(pos, _sSort, 0.2, 0.6);
      var yb = _lerp(_laneY[_mid], _laneY[u.lane], _eio(sortP));
      yb = _lerp(yb, _laneY[_mid], _eio(pos - 11));
      if (k == cyc) {
        yb = _lerp(600, _laneY[_mid], _ei(dw(0, 0.28))) - 4 * _bump(dw(0.28, 0.42));
      }
      final r = Rect.fromLTWH(x - u.w / 2, yb - _crateH, u.w, _crateH);
      list.add((k, u, r, pos, prog(pos, _sPress, 0.14, 0.15) >= 1));
    }
    // Before itemize, the runs of one mixed line arrive chained together;
    // the sorter unhooks them and routes each run to its script's lane.
    for (var i = 0; i + 1 < list.length; i++) {
      final (_, ua, ra, pa, _) = list[i];
      final (_, ub, rb, _, _) = list[i + 1];
      if (ua.group < 0 || ua.group != ub.group) continue;
      if (prog(pa, _sSort, 0.15, 0.2) >= 1) continue;
      final y = (ra.center.dy + rb.center.dy) / 2 + 4;
      c.drawLine(Offset(rb.right, y), Offset(ra.left, y), st(BP.inkDim, 1.2));
      final mx = (rb.right + ra.left) / 2;
      c.drawOval(Rect.fromCenter(center: Offset(mx - 3, y), width: 7, height: 5), st(BP.inkDim, 1.1));
      c.drawOval(Rect.fromCenter(center: Offset(mx + 3, y), width: 7, height: 5), st(BP.inkDim, 1.1));
    }
    // The ribbon: shaped units are taped together until the cutter splits
    // lines apart.
    for (var i = 0; i + 1 < list.length; i++) {
      final (ka, ua, ra, pa, prA) = list[i]; // further along
      final (kb, _, rb, pb, prB) = list[i + 1];
      if (kb != ka + 1 && m.unitAt(ka + 1) != null) continue;
      if (!prA || !prB || pa > 15.4) continue;
      final cut = ua.lineEnd && prog(pa, 13, 0.18, 0.2) >= 1;
      final ya = ra.bottom - 6, yb = rb.bottom - 6;
      if (!cut) {
        c.drawLine(Offset(rb.right, yb), Offset(ra.left, ya), st(BP.line.withValues(alpha: 0.7), 2.4));
      } else {
        c.drawLine(Offset(ra.left, ya), Offset(ra.left - 7, ya + 3), st(BP.line.withValues(alpha: 0.7), 2.4));
        if (pb < 12.6) c.drawLine(Offset(rb.right, yb), Offset(rb.right + 7, yb + 3), st(BP.line.withValues(alpha: 0.7), 2.4));
      }
    }
    for (final (k, u, r, pos, pressed) in list) {
      final sortP = prog(pos, _sSort, 0.2, 0.6);
      final fontP = prog(pos, _sFont, 0.05, 0.4);
      final rastP = _c01((pos - 15.2) / 0.6);
      if (k == cyc) {
        c.save();
        c.clipRect(const Rect.fromLTRB(0, 601, 1600, 900));
        unit(u, r, sortP: sortP, fontP: fontP, pressed: pressed, rastP: rastP);
        c.restore();
      } else {
        unit(u, r, sortP: sortP, fontP: fontP, pressed: pressed, rastP: rastP);
      }
    }
  }

  void unit(_Unit u, Rect r, {double sortP = 1, double fontP = 1, bool pressed = true, double rastP = 1}) {
    if (rastP >= 1) {
      tile(u, r);
      return;
    }
    unitCrate(u, r, sortP, fontP, pressed);
    if (rastP > 0) {
      final y = r.top + r.height * rastP;
      c.save();
      c.clipRect(Rect.fromLTRB(r.left - 2, r.top - 2, r.right + 2, y));
      tile(u, r);
      c.restore();
      c.drawLine(Offset(r.left - 4, y), Offset(r.right + 4, y), st(BP.amber, 1.4));
    }
  }

  void unitCrate(_Unit u, Rect r, double sortP, double fontP, bool pressed) {
    final col = sortP >= 0.5 ? u.color : BP.inkDim;
    c.drawRect(r, fl(BP.panel));
    c.drawRect(r, st(col, 1.2));
    final strip = r.top + 10;
    c.drawLine(Offset(r.left, strip), Offset(r.right, strip), st(col.withValues(alpha: 0.5), 0.8));
    paintFit(pressed && u.gid != null ? u.gid! : u.stamp, Rect.fromLTRB(r.left + 3, r.top + 1, r.right - 3, strip));
    final body = Rect.fromLTRB(r.left, strip, r.right, r.bottom);
    if (fontP <= 0) {
      final b = body.deflate(4);
      c.drawLine(b.topLeft, b.bottomRight, st(BP.lineFaint, 1));
      c.drawLine(b.bottomLeft, b.topRight, st(BP.lineFaint, 1));
      return;
    }
    // Glyphs drop out of the fonts machine's chute (bottom at y 612).
    final dy = fontP >= 1 ? 0.0 : -(1 - _ei(fontP)) * (body.top - 604);
    c.save();
    c.translate(0, dy);
    if (u.isTitle) {
      final g = u.glyph!;
      final pen = Offset(body.center.dx - g.adv / 2, body.bottom - 6);
      if (u.space) {
        c.drawPath(
          dashPath(Path()..addRect(Rect.fromLTWH(pen.dx, body.top + 4, g.adv, body.height - 9)), dash: 2, gap: 2),
          st(BP.lineDim, 1),
        );
      } else {
        g.draw(
          c,
          pen,
          filled: pressed,
          stroke: st(BP.ink, 0.9),
          fill: fl(BP.ink),
          dots: _dots..color = BP.amber,
        );
      }
    } else if (pressed) {
      // Shaped: one plate, glyphs joined / reordered by the engine.
      c.drawRect(body.deflate(2.5), st(col.withValues(alpha: 0.45), 1));
      paintFit(u.plate!, body.deflate(3));
    } else {
      final n = u.minis.length;
      final cw = (r.width - 4) / n;
      for (var i = 0; i < n; i++) {
        final cell = Rect.fromLTWH(r.left + 2 + i * cw, body.top + 2, cw, body.height - 4);
        if (i > 0) c.drawLine(cell.topLeft, cell.bottomLeft, st(BP.lineFaint, 1));
        final g = u.minis[i];
        final k = math.min(1.0, (cw - 1.5) / math.max(1, g.adv));
        c.save();
        c.translate(cell.center.dx, cell.bottom - 6);
        c.scale(k);
        g.draw(c, Offset(-g.adv / 2, 0), filled: false, stroke: st(BP.ink, 0.8 / k), fill: fl(BP.ink));
        c.restore();
      }
    }
    c.restore();
  }

  static final _dots = Paint()
    ..strokeWidth = 2.2
    ..strokeCap = StrokeCap.round;

  void tile(_Unit u, Rect r) {
    c.drawRect(r, fl(BP.panel));
    final img = u.tile;
    if (img != null) {
      final dst = u.tileDst.shift(r.topLeft);
      c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, _pix);
      c.save();
      c.translate(dst.left, dst.top);
      c.drawPath(u.tileGrid, st(BP.lineFaint.withValues(alpha: 0.8), 0.6));
      c.restore();
    } else {
      c.drawPath(dashPath(Path()..addRect(r.deflate(8)), dash: 3, gap: 3), st(BP.lineDim, 1));
    }
    c.drawRect(r, st(BP.line, 1.2));
  }

  // ── Machines ──────────────────────────────────────────────────────────────

  @override
  void lamp(Offset p, Color col, bool on, [double r = 4.5]) {
    if (on) c.drawCircle(p, r - 1, fl(col));
  }

  void hopper() {
    final roll = m.hexRoll;
    final off = (s * 16) % roll.width;
    c.save();
    c.clipRect(const Rect.fromLTRB(79, 448, 181, 468));
    for (var x = 80 - off; x < 181; x += roll.width) {
      roll.paint(c, Offset(x, 458 - roll.height / 2));
    }
    c.restore();
    final dropping = m.unitAt(cyc) != null && dwell && dw(0, 0.45) < 1;
    lamp(const Offset(146, 540), BP.amber, dropping || boost(0) > 0);
    if (boost(0) > 0) puff(const Offset(130, 432), _seg(t, io.machineAt, io.machineAt + 1.2), 6, 30, BP.amber);
  }

  void sorter() {
    const cx = 350.3;
    final k = cyc - _sSort;
    final u = m.unitAt(k);
    var gy = 614.0;
    if (u != null && dwell) {
      final down = _eio(dw(0.0, 0.18));
      final up = _eio(dw(0.66, 0.92));
      final top = _lerp(_laneY[_mid], _laneY[u.lane], _eio(dw(0.2, 0.6))) - _crateH;
      gy = _lerp(614, top, down * (1 - up));
    }
    c.drawLine(const Offset(cx, 606), Offset(cx, gy - 3), st(BP.line, 2.2));
    c.drawLine(Offset(cx - 16, gy - 3), Offset(cx + 16, gy - 3), st(BP.line, 1.8));
    c.drawLine(Offset(cx - 16, gy - 3), Offset(cx - 18, gy + 4), st(BP.line, 1.5));
    c.drawLine(Offset(cx + 16, gy - 3), Offset(cx + 18, gy + 4), st(BP.line, 1.5));
    final shown = dwell ? u : m.unitAt(k - 1);
    if (shown != null) {
      final lab = m.labels[shown.label]!;
      lab.paint(c, Offset(310, 529 - lab.height / 2));
      if ((s * 2.5).floor().isEven) {
        c.drawRect(Rect.fromLTWH(313 + lab.width, 524, 5, 10), fl(shown.color));
      }
    }
    for (var i = 0; i < 5; i++) {
      lamp(Offset(314.0 + i * 15, 590), _laneColor[i], (shown != null && shown.lane == i) || boost(1) > 0, 4);
    }
  }

  void fontsMachine() {
    final u = m.unitAt(cyc - _sFont);
    if (u != null) {
      final i = _Model.fontCell(u);
      final r = _Model.cellRect(i).deflate(0.5);
      final a = dwell ? 1.0 : _seg(ph, 0, _mv);
      c.drawRect(r, st(BP.amber.withValues(alpha: 0.25 + 0.75 * a), 1.6));
      if (dwell) lamp(Offset(532.0 + 14 * (i % 3), 550), BP.amber, dw(0, 0.45) < 1, 3.5);
    }
    if (boost(2) > 0) {
      for (var i = 0; i < 3; i++) {
        lamp(Offset(532.0 + 14 * i, 550), BP.amber, true, 3.5);
      }
    }
  }

  void press() {
    const cx = 791.0;
    final u = m.unitAt(cyc - _sPress);
    var ram = 580.0;
    var impact = -1.0;
    if (u != null && dwell) {
      final down = _ei(dw(0.0, 0.14));
      final up = _eio(dw(0.35, 0.8));
      ram = _lerp(580, _laneY[u.lane] - _crateH, down * (1 - up));
      impact = dw(0.14, 0.7);
    }
    c.drawLine(const Offset(cx, 510), Offset(cx, ram - 26), st(BP.line, 4));
    final r = Rect.fromLTRB(cx - 22, ram - 26, cx + 22, ram);
    c.drawRect(r, fl(BP.panel));
    c.drawRect(r, st(BP.line, 1.4));
    c.drawLine(Offset(r.left + 4, ram - 7), Offset(r.right - 4, ram - 7), st(BP.lineDim, 1));
    // Flywheel.
    final a = s * 3.2 + boost(3) * 6;
    final sp = Path();
    for (var i = 0; i < 3; i++) {
      final d = Offset(math.cos(a + i * 2.094), math.sin(a + i * 2.094)) * 12;
      sp
        ..moveTo(822, 464)
        ..lineTo(822 + d.dx, 464 + d.dy);
    }
    c.drawPath(sp, st(BP.line, 1.2));
    // Pressure gauge: builds while the next crate approaches, drops on impact.
    final pr = u == null ? 0.15 : (dwell ? 1 - _seg(ph, _mv + 0.1 * (1 - _mv), 1) : _seg(ph, 0, _mv));
    final ga = math.pi * (0.8 + 1.4 * pr);
    c.drawLine(const Offset(760, 494), Offset(760 + math.cos(ga) * 7, 494 + math.sin(ga) * 7), st(BP.amber, 1.4));
    if (impact > 0 && impact < 1 && u != null) {
      final y = _laneY[u.lane];
      for (final sg in [-1.0, 1.0]) {
        for (var i = 0; i < 3; i++) {
          puff(Offset(cx + sg * (28 + impact * (10 + i * 9)), y - 3 - i * 6 - impact * 8), _c01(impact * 1.1 + i * 0.07), 2, 6 + i * 2.5);
        }
        final f = 1 - impact;
        c.drawLine(
          Offset(cx + sg * 26, ram - 14),
          Offset(cx + sg * (30 + 10 * impact), ram - 20 - 8 * impact),
          st(BP.amber.withValues(alpha: f), 1.3),
        );
      }
    }
  }

  void cutter() {
    const bx = 1048.0;
    final a = m.unitAt(cyc - 13);
    var bottom = 606.0;
    var cut = -1.0;
    if (a != null && a.lineEnd && dwell) {
      bottom = _lerp(606, 700, _ei(dw(0.08, 0.2)) * (1 - _eio(dw(0.4, 0.8))));
      cut = dw(0.2, 0.55);
    }
    c.drawLine(const Offset(bx, 514), Offset(bx, bottom - 46), st(BP.line, 3));
    final blade = Path()
      ..moveTo(bx - 8, bottom - 46)
      ..lineTo(bx + 8, bottom - 46)
      ..lineTo(bx + 8, bottom)
      ..lineTo(bx - 8, bottom - 8)
      ..close();
    c.drawPath(blade, fl(BP.panel));
    c.drawPath(blade, st(BP.line, 1.4));
    c.drawLine(Offset(bx - 8, bottom - 8), Offset(bx + 8, bottom), st(BP.ink, 2));
    if (cut > 0 && cut < 1) sparks(const Offset(bx, 686), cut, cyc);
    lamp(const Offset(1016, 501), BP.green, (a != null && dwell && !a.lineEnd) || boost(4) > 0, 4);
    lamp(const Offset(1030, 501), BP.amber, cut > 0 || boost(4) > 0, 4);
  }

  void oven() {
    const win = Rect.fromLTRB(1212, 598, 1324, 668);
    var heat = 0.0;
    for (var k = cyc - 17; k <= cyc - 13; k++) {
      if (m.unitAt(k) == null) continue;
      heat = math.max(heat, _bump(_seg((cyc - k - 1) + e, 14.6, 16.4)));
    }
    final flick = 0.5 + 0.5 * math.sin(s * 7.3) * math.sin(s * 2.9 + 1);
    c.drawRect(
      Rect.fromLTRB(win.left, win.top, win.right, win.top + 16),
      fl(BP.coral.withValues(alpha: 0.06 + 0.05 * flick + 0.08 * heat)),
    );
    final coil = Path()..moveTo(win.left + 6, win.top + 6);
    for (var i = 1; i <= 12; i++) {
      coil.lineTo(win.left + 6 + i * 8.3, win.top + (i.isEven ? 6 : 11));
    }
    c.drawPath(coil, st(BP.coral.withValues(alpha: 0.45 + 0.3 * flick + 0.25 * heat), 1.3));
    // Heat shimmer rising inside the window.
    final shimmer = Path();
    for (var i = 0; i < 4; i++) {
      final x0 = win.left + 16 + i * 26.0;
      final q = (s * 0.8 + i * 0.37) % 1;
      final y0 = win.bottom - 6 - q * 38;
      shimmer.moveTo(x0, y0);
      for (var k = 1; k <= 5; k++) {
        shimmer.lineTo(x0 + math.sin(s * 6 + k + i) * 2, y0 - k * 3);
      }
    }
    c.drawPath(shimmer, st(BP.coral.withValues(alpha: 0.25 + 0.25 * heat), 1));
    final g = 0.5 + 0.18 * math.sin(s * 0.7) + 0.18 * heat + 0.03 * math.sin(s * 23) + 0.2 * boost(5);
    final a = math.pi * (0.8 + 1.4 * g);
    c.drawLine(const Offset(1224, 526), Offset(1224 + math.cos(a) * 11, 526 + math.sin(a) * 11), st(BP.amber, 1.5));
    const lamps = [BP.green, BP.amber, BP.red];
    for (var i = 0; i < 3; i++) {
      lamp(Offset(1290.0 + i * 16, 520), lamps[i], _rnd((s * 2.2).floor(), i, 5) > 0.45 || boost(5) > 0);
    }
    // Curtain flaps at the mouths swing as crates pass.
    for (final (x, at) in [(1189.0, 14.5), (1347.0, 16.5)]) {
      var sw = 0.0;
      for (var k = cyc - 18; k <= cyc - 13; k++) {
        if (m.unitAt(k) == null) continue;
        sw = math.max(sw, _bump(_seg((cyc - k - 1) + e, at - 0.5, at + 0.5)));
      }
      final ang = sw * 1.05;
      final hinge = Offset(x, 624);
      c.drawLine(hinge, hinge + Offset(math.sin(ang) * 30, math.cos(ang) * 30), st(BP.line, 1.8));
    }
    // Steam from the chimney.
    const per = 0.55;
    final extra = boost(5);
    for (var n = ((s - 2.6) / per).floor(); n <= (s / per).floor(); n++) {
      final age = (s - n * per) / 2.6;
      if (age <= 0 || age >= 1) continue;
      final o = Offset(1323 + (4 + 12 * _rnd(n, 41)) * age + 3 * math.sin(age * 6 + n), 442 - 38 * age);
      puff(o, age, 3, 10 + 4 * _rnd(n, 42) + 10 * extra);
    }
    // Firebox glow, flaring after each shovel of coal.
    const shovel = 2.4;
    final last = ((s / shovel - 0.87).floor() + 0.87) * shovel;
    final flare = math.exp(-(s - last) * 1.8);
    c.drawRect(const Rect.fromLTRB(1207, 755, 1235, 771), fl(BP.amber.withValues(alpha: 0.12 + 0.4 * flare + 0.08 * flick)));
  }

  // ── Elevator, print head, marquee ─────────────────────────────────────────

  void elevatorChain() {
    final ang = _Model.ve * s / _sprR;
    final spokes = Path();
    for (final cy in [_sprTop, _sprBot]) {
      for (var i = 0; i < 3; i++) {
        final a = ang + i * math.pi / 3;
        final d = Offset(math.cos(a), math.sin(a)) * (_sprR - 5);
        spokes
          ..moveTo(_sprX - d.dx, cy - d.dy)
          ..lineTo(_sprX + d.dx, cy + d.dy);
      }
    }
    c.drawPath(spokes, st(BP.lineDim, 1.2));
    final links = <Offset>[];
    for (var d = (_Model.ve * s) % 16; d < _Model.chainLen; d += 16) {
      links.add(m.chainAt(d).$1);
    }
    c.drawPoints(ui.PointMode.points, links, st(BP.line, 2.6));
  }

  void elevatorTrays() {
    final since = s / _tc - _mv;
    final b0 = since.floor();
    final base = _Model.ve * (since - b0) * _tc;
    for (var i = 0; i < _buckets; i++) {
      final d = base + i * _Model.spacing;
      final (p, f) = m.chainAt(d);
      final o = Offset(f.dy, -f.dx);
      final a = p + o * 52;
      final k = b0 - i - _slots;
      final u = m.unitAt(k);
      if (u != null && d < (k < _kM ? _loadY - _rackY : _loadY - _tickY)) {
        tile(u, Rect.fromLTWH(p.dx - 26 - u.w / 2, p.dy - _crateH, u.w, _crateH));
      }
      final tray = Path()
        ..moveTo(p.dx + f.dx * 18, p.dy + f.dy * 18)
        ..lineTo(p.dx, p.dy)
        ..lineTo(a.dx, a.dy)
        ..lineTo(a.dx + f.dx * 7, a.dy + f.dy * 7);
      c.drawPath(tray, st(BP.line, 1.7));
    }
  }

  void printHead() {
    var sinking = false;
    for (var k = math.max(_kM, cyc - 24); k <= cyc - _slots; k++) {
      final u = m.unitAt(k);
      if (u == null) continue;
      final s0 = _Model.sTickOf(k);
      if (s < s0) continue;
      final tau = m.tauOf(k);
      if (s > tau + 0.4) continue;
      final x = _lerp(_exX, 1400, _eio((s - s0) / 0.32));
      final sink = _eio((s - tau) / 0.4);
      if (sink > 0) sinking = true;
      c.save();
      c.clipRect(const Rect.fromLTRB(1300, 250, 1600, _tickY));
      tile(u, Rect.fromLTWH(x - u.w / 2, _tickY - _crateH + sink * _crateH, u.w, _crateH));
      c.restore();
    }
    final printing = s > m.sM0;
    lamp(const Offset(1420, 354), BP.green, sinking || (printing && (s * 3).floor().isEven), 4);
    if (printing) {
      final dots = <Offset>[];
      for (var i = 0; i < 7; i++) {
        final q = s * 2.4 + i / 7;
        final a = q - q.floorToDouble();
        dots.add(Offset(_mRight - 9 - a * 16, 377 + (_rnd(i, q.floor()) - 0.5) * 18));
      }
      c.drawPoints(ui.PointMode.points, dots, st(BP.line.withValues(alpha: 0.7), 1.8));
    }
  }

  void marquee() {
    if (s <= m.sM0) return;
    final u = m.vM * (s - m.sM0);
    final left = math.max(_mLeft, _mRight - u);
    final p = m.marquee;
    final y = (_mTop + _mBot) / 2 - p.height / 2;
    c.save();
    c.clipRect(Rect.fromLTRB(left, _mTop + 1, _mRight, _mBot - 1));
    final r0 = math.max(0, ((u - (_mRight - _mLeft)) / m.mW).floor());
    final r1 = (u / m.mW).floor();
    for (var r = r0; r <= r1; r++) {
      p.paint(c, Offset(_mRight - u + r * m.mW, y));
    }
    c.restore();
  }

  // ── Title, rack, gantry ───────────────────────────────────────────────────

  Rect slotRect(_Letter l) => l.space ? Rect.fromLTRB(l.box.left, _baseline - 112, l.box.right, _baseline) : l.bigDst;

  ({int letter, double trolley, double hook, double open, double dy})? qcJob() {
    if (s < m.qcStart) return null;
    final q = ((s - m.qcStart) / _Model.qcPeriod).floor();
    final t0 = m.qcStart + q * _Model.qcPeriod;
    final li = m.qcLetter(q);
    final l = m.letters[li];
    final tr = 0.3 + (l.cx - _pickX).abs() / 2400;
    final a1 = t0 + tr, a2 = a1 + 0.35, a3 = a2 + 0.15, a4 = a3 + 0.6, a5 = a4 + 2.8;
    final a6 = a5 + 0.6, a7 = a6 + 0.15, a8 = a7 + 0.35, a9 = a8 + tr;
    if (s >= a9) return null;
    final grab = l.inkTop - 2;
    var x = l.cx, hook = _carryTop, open = 1.0, dy = 0.0;
    if (s < a1) {
      x = _lerp(_pickX, l.cx, _eio(_seg(s, t0, a1)));
    } else if (s < a2) {
      hook = _lerp(_carryTop, grab, _eio(_seg(s, a1, a2)));
    } else if (s < a3) {
      hook = grab;
      open = 1 - _seg(s, a2, a3);
    } else if (s < a6) {
      open = 0;
      dy = -30 * (_eio(_seg(s, a3, a4)) - _eio(_seg(s, a5, a6)));
      hook = grab + dy;
    } else if (s < a7) {
      hook = grab;
      open = _seg(s, a6, a7);
    } else if (s < a8) {
      hook = _lerp(grab, _carryTop, _eio(_seg(s, a7, a8)));
    } else {
      x = _lerp(l.cx, _pickX, _eio(_seg(s, a8, a9)));
    }
    return (letter: li, trolley: x, hook: hook, open: open, dy: dy);
  }

  // The shelf crew: every [_ep] seconds they pick a finished letter, walk
  // over, polish it, and high-five.
  static const _ep = 8.0;

  int? crewTarget(int ep) {
    final t0 = ep * _ep;
    // A slow wander along the shelf (never more than ~300 px per episode).
    final v = 0.5 + 0.3 * math.sin(ep * 0.55) + 0.18 * math.sin(ep * 0.23 + 2);
    final want = _lerp(m.letters.first.cx, m.letters.last.cx, v);
    int? best;
    for (final i in m.solid) {
      if (m.jobs[i].t4 + 0.8 > t0) continue;
      if (best == null || (m.letters[i].cx - want).abs() < (m.letters[best].cx - want).abs()) best = i;
    }
    return best;
  }

  double crewX(int? target) => target == null ? 58 : m.letters[target].cx - 12;

  ({double x, int dir, double walk, int? target, double polish, double five}) crew(double time) {
    final ep = (time / _ep).floor();
    final u = time - ep * _ep;
    final tg = crewTarget(ep);
    final x0 = crewX(crewTarget(ep - 1)), x1 = crewX(tg);
    final dist = (x1 - x0).abs();
    final wd = dist < 1 ? 0.0 : math.min(3.4, math.max(0.9, dist / 70));
    if (u < wd) {
      final x = _lerp(x0, x1, _eio(u / wd));
      return (x: x, dir: x1 >= x0 ? 1 : -1, walk: (x - x0).abs() / 4.5, target: null, polish: 0, five: 0);
    }
    if (tg == null) return (x: x1, dir: 1, walk: -1, target: null, polish: 0, five: 0);
    return (
      x: x1,
      dir: 1,
      walk: -1,
      target: tg,
      polish: _seg(u, wd + 0.2, _ep - 1.1),
      five: _seg(u, _ep - 1.0, _ep - 0.2),
    );
  }

  void title() {
    m.plan.paint(c, m.planAt);
    final qc = qcJob();
    final cr = crew(s);
    final clickP = _seg(t, io.letterAt, io.letterAt + 1.3);
    for (final l in m.letters) {
      final j = m.jobs[l.index];
      if (s < j.t3) continue;
      final slot = slotRect(l);
      if (l.space) {
        final from = Rect.fromLTWH(j.x - 23, _carryTop, 46, _crateH);
        final r = Rect.lerp(from, slot, _eio(_seg(s, j.t3, j.t4)))!;
        final a = 1 - _seg(s, j.t4, j.t4 + 1.4);
        if (a > 0) c.drawPath(dashPath(Path()..addRect(r), dash: 4, gap: 4), st(BP.amber.withValues(alpha: a), 1.2));
        continue;
      }
      final src = Rect.fromLTWH(0, 0, l.big!.width.toDouble(), l.big!.height.toDouble());
      if (s < j.t4) {
        // Unfolding: the coarse tile grows into its slot.
        final p = _eio(_seg(s, j.t3, j.t4));
        final r = Rect.lerp(Rect.fromLTWH(j.x - 23, _carryTop, 46, _crateH), slot, p)!;
        c.drawImageRect(l.big!, src, r, _pix);
        c.drawRect(r, st(BP.amber.withValues(alpha: 1 - p * 0.6), 1.2));
        continue;
      }
      final dev = _seg(s, j.t4, j.t4 + 0.7);
      if (dev < 1) {
        // Develop: crisp text above the scan line, raw pixels below it.
        final y = _lerp(slot.top, slot.bottom, _eio(dev));
        c.save();
        c.clipRect(Rect.fromLTRB(0, 0, 1600, y));
        l.fill.paint(c, l.fillAt);
        c.restore();
        c.save();
        c.clipRect(Rect.fromLTRB(0, y, 1600, 900));
        c.drawImageRect(l.big!, src, slot, _pix);
        bigGrid(slot);
        c.restore();
        c.drawLine(Offset(slot.left + 4, y), Offset(slot.right - 4, y), st(BP.amber, 1.5));
        final age = _seg(s, j.t4, j.t4 + 0.7);
        for (final (x, sg) in [(l.box.left + 6, -1.0), (l.box.right - 6, 1.0)]) {
          for (var i = 0; i < 2; i++) {
            puff(Offset(x + sg * (4 + age * (10 + 8 * i)), _shelfY - 4 - i * 5 - age * 6), _c01(age + i * 0.1), 2, 6 + 2.0 * i);
          }
        }
        continue;
      }
      var dy = 0.0, dx = 0.0;
      if (qc != null && qc.letter == l.index) {
        dy = qc.dy;
        dx = dy < -1 ? 1.2 * math.sin(s * 5) : 0;
      }
      var sheen = -1.0;
      if (cr.target == l.index && cr.polish > 0 && cr.polish < 1) sheen = (cr.polish * 2) % 1;
      if (io.letter == l.index && clickP > 0 && clickP < 1) sheen = clickP;
      final at = l.fillAt + Offset(dx, dy);
      if (sheen > 0) {
        final b = l.box.shift(Offset(dx, dy)).inflate(6);
        c.saveLayer(b, Paint());
        l.fill.paint(c, at);
        final x = _lerp(b.left - 60, b.right + 60, sheen);
        Path band(double x0, double w) => Path()
          ..moveTo(x0, b.top)
          ..lineTo(x0 + w, b.top)
          ..lineTo(x0 + w - 50, b.bottom)
          ..lineTo(x0 - 50, b.bottom)
          ..close();
        c.drawPath(band(x, 14), _sheen..color = BP.line.withValues(alpha: 0.75));
        c.drawPath(band(x + 22, 5), _sheen..color = BP.line.withValues(alpha: 0.6));
        c.restore();
        for (var i = 0; i < 3; i++) {
          final q = (s * 3).floor() + i * 7;
          final p = Offset(
            _lerp(l.box.left + 8, l.box.right - 8, _rnd(q, l.index)),
            _lerp(l.inkTop + dy, _baseline - 10 + dy, _rnd(q, l.index, 3)),
          );
          star(p, 3 + 3 * _bump((s * 3) % 1), BP.ink);
        }
      } else {
        l.fill.paint(c, at);
      }
    }
  }

  void bigGrid(Rect r) {
    final g = Path();
    for (var x = r.left; x <= r.right + 0.1; x += 12) {
      g
        ..moveTo(x, r.top)
        ..lineTo(x, r.bottom);
    }
    for (var y = r.top; y <= r.bottom + 0.1; y += 12) {
      g
        ..moveTo(r.left, y)
        ..lineTo(r.right, y);
    }
    c.drawPath(g, st(BP.lineFaint, 0.8));
  }

  void rack() {
    for (var i = 0; i < m.jobs.length; i++) {
      final j = m.jobs[i];
      final top = j.arrive - 0.35;
      if (s < top || s >= j.t1) continue;
      var q = 0.0;
      for (var h = 0; h < i; h++) {
        final o = m.jobs[h];
        if (s >= o.arrive - 0.35) q += 1 - _eio((s - o.t1) / 0.35);
      }
      final u = m.tUnits[i];
      final x = _lerp(_exX, _pickX + 48 * q, _eio((s - top) / 0.35));
      tile(u, Rect.fromLTWH(x - u.w / 2, _rackY - _crateH, u.w, _crateH));
    }
  }

  void gantry() {
    var x = _pickX, hook = _carryTop, open = 1.0;
    _Unit? carried;
    for (final j in m.jobs) {
      if (s < j.start || s >= j.end) continue;
      const rackTop = _rackY - _crateH;
      final slot = slotRect(m.letters[j.i]);
      if (s < j.t1) {
        final p = _seg(s, j.start, j.t1);
        hook = _lerp(_carryTop, rackTop, _eio(p / 0.7));
        open = 1 - _seg(p, 0.75, 1);
      } else if (s < j.t2) {
        hook = _lerp(rackTop, _carryTop, _eio(_seg(s, j.t1, j.t2)));
        open = 0;
        carried = m.tUnits[j.i];
      } else if (s < j.t3) {
        x = _lerp(_pickX, j.x, _eio(_seg(s, j.t2, j.t3)));
        open = 0;
        carried = m.tUnits[j.i];
      } else if (s < j.t4) {
        x = j.x;
        open = 0;
        hook = _lerp(_carryTop, slot.top, _eio(_seg(s, j.t3, j.t4)));
      } else if (s < j.t5) {
        x = j.x;
        open = _seg(s, j.t4, j.t4 + 0.06);
        hook = _lerp(slot.top, _carryTop, _eio(_seg(s, j.t4, j.t5)));
      } else {
        x = _lerp(j.x, _pickX, _eio(_seg(s, j.t5, j.end)));
      }
      break;
    }
    final qc = qcJob();
    if (qc != null) {
      x = qc.trolley;
      hook = qc.hook;
      open = qc.open;
    }
    if (carried != null) tile(carried, Rect.fromLTWH(x - carried.w / 2, hook, carried.w, _crateH));
    // Cable + gripper.
    c.drawLine(Offset(x, 70), Offset(x, hook - 6), st(BP.inkDim, 1));
    c.drawLine(Offset(x - 26, hook - 6), Offset(x + 26, hook - 6), st(BP.line, 2));
    c.drawRect(Rect.fromCenter(center: Offset(x, hook - 8), width: 10, height: 5), fl(BP.line));
    final spread = 2 + 7 * open;
    for (final sg in [-1.0, 1.0]) {
      final top = Offset(x + sg * 26, hook - 6);
      c.drawPath(
        Path()
          ..moveTo(top.dx, top.dy)
          ..lineTo(top.dx + sg * spread, top.dy + 7)
          ..lineTo(top.dx + sg * (spread - 4), top.dy + 12),
        st(BP.line, 1.6),
      );
    }
    // Trolley on the lower flange, with a cab for its operator.
    final wa = x / 4.5;
    for (final wx in [x - 14, x + 14]) {
      c.drawLine(Offset(wx, 50), Offset(wx, 58), st(BP.line, 1.4));
      c.drawCircle(Offset(wx, 50), 4.5, fl(BP.panel));
      c.drawCircle(Offset(wx, 50), 4.5, st(BP.line, 1.2));
      c.drawLine(Offset(wx, 50), Offset(wx + math.cos(wa) * 4.5, 50 + math.sin(wa) * 4.5), st(BP.line, 1));
    }
    final body = Rect.fromLTRB(x - 24, 57, x + 24, 70);
    c.drawRect(body, fl(BP.panel));
    c.drawRect(body, st(BP.line, 1.3));
    final cab = Rect.fromLTRB(x + 24, 54, x + 46, 78);
    c.drawRect(cab, fl(BP.panel));
    c.drawRect(cab, st(BP.line, 1.3));
    c.drawRect(Rect.fromLTRB(cab.left + 4, cab.top + 4, cab.right - 4, cab.top + 15), st(BP.lineDim, 1));
    final head = Offset(cab.center.dx, cab.top + 11);
    c.drawCircle(head, 3.2, st(BP.ink, 1.2));
    c.drawArc(Rect.fromCircle(center: head, radius: 4), math.pi, math.pi, true, fl(BP.amber));
    final moving = (x - _pickX).abs() > 1 && carried == null ? true : carried != null;
    lamp(Offset(x - 16, 63.5), BP.amber, moving && (s * 4).floor().isEven, 3.5);
  }

  // ── Workers ──────────────────────────────────────────────────────────────

  bool get cheering => s > m.sDone && s < m.sDone + 2.6;

  bool hovered(Offset feet, double h) {
    final p = io.mouse;
    return p != null && (p - feet.translate(0, -h * 0.55)).distance < h * 0.7;
  }

  /// Set by [guy]: the last worker dropped his task to cheer or wave.
  bool busy = false;

  Limbs guy(Offset feet, double h, int dir, Pose f, {int seed = 0, bool canCheer = true, int machine = -1}) {
    busy = false;
    if (canCheer && (cheering || (machine >= 0 && boost(machine) > 0))) {
      f.cheer(t, seed);
      busy = true;
    }
    if (hovered(feet, h)) {
      f.wave(t);
      busy = true;
    }
    return worker(feet, h, dir, f);
  }

  void workers() {
    // 0 · Up the ladder, shovelling code points into the unicode hopper.
    {
      const per = 1.9;
      final n = (s / per).floor();
      final p = s / per - n;
      final rest = _rnd(n, 3) < 0.2;
      final f = Pose()
        ..thA = 0.08
        ..thB = -0.06
        ..shB = -0.06;
      if (rest) {
        f.wipe(t);
      } else {
        final sw = p < 0.45 ? 0.0 : (p < 0.62 ? _eo((p - 0.45) / 0.17) : 1 - _eio((p - 0.62) / 0.38));
        f
          ..lean = _lerp(0.45, -0.05, sw)
          ..upA = _lerp(0.55, 2.0, sw)
          ..foA = _lerp(1.0, 2.45, sw)
          ..upB = _lerp(0.25, 1.6, sw)
          ..foB = _lerp(1.05, 2.4, sw);
      }
      final g = guy(const Offset(39, 502), 30, 1, f, seed: 1, machine: 0);
      if (rest) {
        sweat(g.head, p * per, 1);
      } else {
        shovel(g.handB, g.handA, 10);
      }
      for (var j = n - 1; j <= n; j++) {
        if (_rnd(j, 3) < 0.2) continue;
        final age = (s - (j + 0.58) * per) / 0.75;
        if (age < 0 || age > 1) continue;
        for (var i = 0; i < 3; i++) {
          final pt = Offset.lerp(const Offset(66, 468), Offset(112 + i * 16.0, 442), age)! +
              Offset(0, -44 * math.sin(age * math.pi) + i * 2);
          c.drawRect(Rect.fromCenter(center: pt, width: 6, height: 4.5), st(BP.amber, 1));
        }
      }
    }
    // 1 · Sorter operator pulls the lever for every crate.
    {
      final u = m.unitAt(cyc - _sSort);
      final pull = u != null && dwell ? _eo(dw(0, 0.2)) * (1 - _eio(dw(0.55, 0.85))) : 0.0;
      final f = Pose()
        ..upA = _lerp(2.4, 1.25, pull)
        ..foA = _lerp(2.75, 1.6, pull)
        ..lean = 0.12 * pull;
      final ep = (s / 7).floor();
      if (pull == 0 && _rnd(ep, 5) < 0.35 && s - ep * 7 > 3.5) {
        f
          ..upB = 0.9
          ..foB = 2.2
          ..head = 0.3;
      }
      final g = guy(const Offset(428, _floor), 34, -1, f, seed: 2, machine: 1);
      final knob = busy ? const Offset(410, 740) : g.handA;
      c.drawLine(const Offset(400, 758), knob, st(BP.line, 1.6));
      c.drawCircle(knob, 2.6, fl(BP.amber));
      lamp(const Offset(393, 772), _laneColor[u?.lane ?? _mid], pull > 0.3, 4);
    }
    // 2 · Cart of font files, back and forth to the fonts machine.
    {
      const xa = 176.0, xb = 470.0, speed = 44.0, pause = 2.6;
      const leg = (xb - xa) / speed;
      const per = 2 * leg + 2 * pause;
      final n = (s / per).floor();
      final u = s - n * per;
      double x;
      int dir;
      var moving = true;
      var boxes = 0;
      var work = 0.0;
      if (u < leg) {
        x = xa + speed * u;
        dir = 1;
        boxes = 3;
      } else if (u < leg + pause) {
        x = xb;
        dir = 1;
        moving = false;
        work = (u - leg) / pause;
        boxes = (3 * (1 - work * 1.6)).ceil().clamp(0, 3);
      } else if (u < 2 * leg + pause) {
        x = xb - speed * (u - leg - pause);
        dir = -1;
      } else {
        x = xa;
        dir = -1;
        moving = false;
        work = (u - 2 * leg - pause) / pause;
        boxes = (3 * (work * 1.6 - 0.6)).ceil().clamp(0, 3);
      }
      final f = Pose();
      if (moving) f.walk(s * speed / 4.5, arms: false);
      final bend = _bump(work);
      f
        ..lean = moving ? 0.28 : 0.1 + 0.45 * bend
        ..upA = moving ? 1.25 : _lerp(1.25, 0.6, bend)
        ..foA = moving ? 1.5 : _lerp(1.5, 0.9, bend)
        ..upB = 1.15
        ..foB = 1.45;
      final g = guy(Offset(x, _floor), 34, dir, f, seed: 3);
      cart(Offset(x + dir * 26, _floor), dir, boxes, moving ? x / 3.5 : 0, busy ? null : g.handB);
    }
    // 3 · Fonts machine: presses the button for each glyph, yawns between.
    {
      final u = m.unitAt(cyc - _sFont);
      final poke = u != null && dwell ? _bump(dw(0, 0.3)) : 0.0;
      final f = Pose()
        ..upA = 1.05 + 0.2 * poke
        ..foA = 1.3 + 0.35 * poke;
      final ep = (s / 9).floor();
      final yawn = poke == 0 && _rnd(ep, 21) < 0.35 && s - ep * 9 < 3;
      if (yawn) {
        f
          ..upA = 2.9
          ..foA = 3.1
          ..upB = 2.8
          ..foB = 3.0
          ..head = -0.25;
      }
      final g = guy(const Offset(652, _floor), 34, -1, f, seed: 4, machine: 2);
      if (yawn) zees(g.head, s - ep * 9, -1);
      if (u != null) lamp(Offset(612.0 + 8 * (_Model.fontCell(u) % 3), 758), BP.amber, poke > 0.2, 3);
    }
    // 4 · Hammering on the anvil next to the press (two strikes per cycle).
    {
      final ep = (s / 7).floor();
      final r = _rnd(ep, 11);
      final f = Pose();
      var age = -1.0;
      if (r < 0.72) {
        const hp = _tc / 2;
        final q = (s / hp) % 1;
        final a = q < 0.35 ? _eio(q / 0.35) : (q < 0.5 ? 1 - _ei((q - 0.35) / 0.15) : 0.0);
        f
          ..upA = _lerp(1.0, 2.7, a)
          ..foA = _lerp(0.8, 3.1, a)
          ..lean = 0.28 - 0.18 * a
          ..upB = 0.7
          ..foB = 0.95;
        final last = ((s / hp - 0.5).floor() + 0.5) * hp;
        age = (s - last) / 0.35;
      } else if (r < 0.88) {
        f.wipe(t);
      } else {
        f
          ..upB = 0.9
          ..foB = 2.2
          ..head = 0.3;
      }
      final g = guy(const Offset(888, _floor), 34, -1, f, seed: 5, machine: 3);
      if (r < 0.72) {
        hammer(g.elbowA, g.handA);
        sparks(const Offset(860, 771), age, (s / 0.6).floor());
      } else if (r < 0.88) {
        sweat(g.head, s - ep * 7, -1);
      }
    }
    // 5 · Pulls the cutter's rope when a line is full.
    {
      final a = m.unitAt(cyc - 13);
      final pull = a != null && a.lineEnd && dwell ? _eo(dw(0, 0.18)) * (1 - _eio(dw(0.45, 0.85))) : 0.0;
      final f = Pose()
        ..upA = _lerp(2.55, 1.5, pull)
        ..foA = _lerp(2.75, 1.65, pull)
        ..upB = _lerp(2.35, 1.35, pull)
        ..foB = _lerp(2.55, 1.5, pull)
        ..lean = -0.22 * pull
        ..thA = -0.12 * pull;
      final g = guy(const Offset(1124, _floor), 34, -1, f, seed: 6, machine: 4);
      final rope = busy ? const Offset(1108, 760) : g.handA;
      c.drawLine(const Offset(1106, 505), rope, st(BP.inkDim, 1));
      c.drawLine(busy ? rope : g.handB, Offset(rope.dx + 4, _floor - 4), st(BP.inkDim, 1));
    }
    // 6 · Coffee break on a crate: sips, yawns "z z", checks the time.
    {
      final ep = (s / 9).floor();
      final r = _rnd(ep, 13);
      final u = s - ep * 9;
      final f = Pose()
        ..thA = 1.35
        ..shA = 0.15
        ..thB = 1.25
        ..shB = 0.05
        ..drop = (0.48 * 34 - 14) / 34
        ..upA = 0.4
        ..foA = 1.6;
      var yawn = false;
      if (r < 0.55) {
        final sip = _bump(_seg((u % 3) / 3, 0.15, 0.6));
        f
          ..upA = _lerp(0.4, 0.8, sip)
          ..foA = _lerp(1.6, 2.95, sip)
          ..head = -0.15 * sip;
      } else if (r < 0.8) {
        yawn = u < 3.2;
        if (u < 1.6) {
          f
            ..upA = 2.8
            ..foA = 3.0
            ..upB = 2.9
            ..foB = 3.1
            ..head = -0.3;
        }
      } else {
        f
          ..upB = 0.9
          ..foB = 2.2
          ..head = 0.32;
      }
      final g = guy(const Offset(932, _floor), 34, 1, f, seed: 7);
      coffee(g.handA, s);
      if (yawn) zees(g.head, u, 1);
    }
    // 7 · Stokes the oven: scoop from the pile, turn, throw into the firebox.
    {
      const per = 2.4;
      final n = (s / per).floor();
      final p = s / per - n;
      final toss = p >= 0.45;
      final f = Pose();
      if (!toss) {
        final sc = _bump(_seg(p, 0.05, 0.42));
        f
          ..lean = 0.2 + 0.45 * sc
          ..upA = 0.6
          ..foA = 0.9 + 0.3 * sc
          ..upB = 0.3
          ..foB = 0.95;
      } else {
        final sw = _eo(_seg(p, 0.45, 0.65)) * (1 - _eio(_seg(p, 0.75, 1)));
        f
          ..lean = 0.3 - 0.2 * sw
          ..upA = _lerp(0.7, 1.5, sw)
          ..foA = _lerp(0.9, 1.75, sw)
          ..upB = _lerp(0.4, 1.2, sw)
          ..foB = _lerp(1.0, 1.8, sw);
      }
      final g = guy(const Offset(1166, _floor), 34, toss ? 1 : -1, f, seed: 8, machine: 5);
      shovel(g.handB, g.handA, 11);
      final age = (p - 0.62) / 0.25;
      if (age >= 0 && age <= 1) {
        for (var i = 0; i < 3; i++) {
          final pt = Offset.lerp(const Offset(1190, 768), Offset(1214 + i * 6.0, 763), age)! +
              Offset(0, -12 * math.sin(age * math.pi) + i);
          c.drawCircle(pt, 1.8, fl(BP.inkDim));
        }
      }
    }
    // 8 · Next to the hot oven: wipes sweat, fans himself, reads the gauge.
    {
      final ep = (s / 6).floor();
      final r = _rnd(ep, 19);
      final u = s - ep * 6;
      final f = Pose();
      var wiping = false;
      if (r < 0.5) {
        wiping = u < 2.4;
        if (wiping) f.wipe(t);
      } else if (r < 0.8) {
        f
          ..upA = 1.95
          ..foA = 2.6 + 0.55 * math.sin(t * 16);
      } else {
        f
          ..head = -0.45
          ..upB = 0.55
          ..foB = -0.4;
      }
      final g = guy(const Offset(1276, _floor), 34, -1, f, seed: 9, machine: 5);
      if (wiping) sweat(g.head, u, 1);
    }
    // 9 · Foreman with a clipboard, nodding at every glyph.
    {
      final nod = _bump(_seg(t, m.countChangedAt, m.countChangedAt + 0.45));
      final f = Pose()
        ..upB = 0.55
        ..foB = 1.55
        ..upA = 0.65
        ..foA = 1.75 + 0.2 * math.sin(t * 11)
        ..head = 0.25 * nod;
      final ep = (s / 11).floor();
      if (_rnd(ep, 23) < 0.3 && s - ep * 11 > 8) {
        f
          ..upA = 0.9
          ..foA = 2.2
          ..head = 0.3;
      }
      final g = guy(const Offset(1424, _floor), 35, -1, f, seed: 10);
      clipboard(g.handB, done: s > m.sDone);
    }
    // 10, 11 · The shelf crew: polisher and inspector.
    {
      final a = crew(s);
      final b = crew(s - 0.35);
      const h = 28.0;
      final fb = Pose();
      var dirB = b.dir;
      final atWork = b.walk < 0 && b.target != null;
      if (b.walk >= 0) {
        fb.walk(b.walk);
      } else if (atWork) {
        dirB = 1;
        if (a.five > 0) {
          fb
            ..upA = 2.35
            ..foA = 2.6;
        } else {
          fb
            ..upA = 1.25 + 0.1 * math.sin(t * 2)
            ..foA = 2.05
            ..head = -0.3;
        }
      }
      final gb = guy(Offset(b.x - 22, _shelfY), h, dirB, fb, seed: 11);
      if (atWork && a.five <= 0) magnifier(gb.handA, gb.elbowA);
      final fa = Pose();
      var dirA = a.dir;
      final polishing = a.walk < 0 && a.target != null && a.polish > 0 && a.polish < 1;
      if (a.walk >= 0) {
        fa.walk(a.walk);
      } else if (a.target != null && a.five > 0) {
        dirA = -1;
        fa
          ..upA = 2.35
          ..foA = 2.6;
      } else if (polishing) {
        fa
          ..upA = 1.9 + 0.35 * math.sin(t * 9)
          ..foA = 2.4 + 0.45 * math.cos(t * 9);
      }
      final ga = guy(Offset(a.x, _shelfY), h, dirA, fa, seed: 12);
      if (polishing) c.drawRect(Rect.fromCenter(center: ga.handA, width: 5, height: 5), fl(BP.line));
      if (a.five > 0.3 && a.five < 0.9) {
        star(Offset.lerp(ga.handA, gb.handA, 0.5)! + const Offset(0, -3), 3 + 5 * _bump((a.five - 0.3) / 0.6), BP.amber);
      }
    }
  }

  void counter() {
    final n = ph > 0.25 ? cyc - 17 : cyc - 18;
    final p = m.countPainter(1284 + m.glyphsUpTo(n), t);
    const x = _board + 8.0;
    p.paint(c, Offset(x, 755 - p.height / 2));
    final flash = 1 - _seg(t, m.countChangedAt, m.countChangedAt + 0.6);
    if (flash > 0 && flash < 1) {
      c.drawLine(Offset(x, 767), Offset(x + p.width, 767), st(BP.amber.withValues(alpha: flash), 1.5));
    }
  }
}
