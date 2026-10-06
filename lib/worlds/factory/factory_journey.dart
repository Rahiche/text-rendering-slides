import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../deck/deck.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import '../../slides/journey/journey.dart';
import 'factory_kit.dart';

/// Section 05's overview as the factory's floor plan: a cross-section of six
/// floors (framework · Dart down to the GPU). The word's crate is packed at
/// the top, rides the layout() line down the lifts to SkParagraph's floor,
/// and a "size" slip shoots back up the pneumatic tube. Then the paint() line
/// runs: record (a tape deck), the atlas oven (tiles of the word's unique
/// glyphs), and the GPU print head, which prints the word on a screen.
///
/// Every stop shows the real sample data for the current word (same logic as
/// j00_map), hover enlarges it, click jumps to the stop. Type a new word in
/// the field (or pick one top-right) and the next crate carries it.
class FactoryJourneyMap extends StatefulWidget {
  const FactoryJourneyMap({super.key});

  @override
  State<FactoryJourneyMap> createState() => _FactoryJourneyMapState();
}

class _FactoryJourneyMapState extends State<FactoryJourneyMap> {
  late final _ctrl = TextEditingController(text: journeyWord.value);

  /// Word-dependent text and rasters, dropped whenever the word changes.
  final _wordText = TextCache();
  String? _for;
  List<String> _samples = const [];

  @override
  void dispose() {
    _ctrl.dispose();
    _wordText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return JourneyFrame(
      stop: 0,
      rekey: false,
      title: (_) => "One word's journey",
      builder: (context, d) {
        if (_ctrl.text != d.text) _ctrl.text = d.text;
        if (_for != d.text) {
          _wordText.clear();
          _samples = _samplesOf(d);
          _for = d.text;
        }
        final samples = _samples;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: FactoryScene(
                painter: (clock, text, io) => _MapPainter(clock, text, io, d, samples, _wordText),
                onTarget: (context, i) => DeckScope.read(context).goToId(journeyStops[i + 1].$1),
              ),
            ),
            Positioned(
              left: 0,
              bottom: 0,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('word', style: BT.mono(16, color: BP.inkDim)),
                  const SizedBox(width: 16),
                  BpTextField(
                    controller: _ctrl,
                    width: 300,
                    style: journeyStyle(30),
                    onChanged: (v) {
                      if (v.isNotEmpty) journeyWord.value = v;
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// What the data looks like at each stop, for this word (as in j00_map).
List<String> _samplesOf(JourneyData d) {
  final w = d.text;
  String short(String w) => w.length > 8 ? '${w.substring(0, 7)}…' : w;
  final units = w.codeUnits.take(3).map((u) => u.toRadixString(16).toUpperCase().padLeft(4, '0')).join(' ');
  final bytes = utf8.encode(w).take(4).map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0')).join(' ');
  final ids = d.glyphs.where((g) => !g.isJoinControl).take(3).map((g) => g.font == null ? '?' : '#${g.glyphId}').join(' ');
  final adv = d.glyphs.take(3).map((g) => g.advance).join(' ');
  final probe = TextProbe(TextSpan(text: w, style: journeyStyle(48)));
  final size = probe.size;
  probe.dispose();
  return [
    "Text('${short(w)}')",
    '$units${w.length > 3 ? ' …' : ''}',
    'utf8 $bytes …',
    '${w.characters.length} graphemes · ${d.rtl ? 'RTL' : 'LTR'}',
    '$ids …',
    'adv $adv …',
    '${size.width.toStringAsFixed(0)} × ${size.height.toStringAsFixed(0)}',
    'DrawTextFrame',
    'atlas ← ${d.atlasGlyphs}',
    '${d.quads * 2} triangles',
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// The building (content-area coordinates, 1472 × 628)
// ─────────────────────────────────────────────────────────────────────────────

const _bands = ['framework · Dart', 'dart:ui', 'engine · C++', 'SkParagraph', 'Impeller', 'GPU'];
const _top = 4.0;
const _bandH = 90.0;
const _wall = 168.0; // the building's left wall; floor labels sit outside it

double _floorY(int b) => _top + _bandH * (b + 1);

/// Crate centre height on floor [b] (it rides a low belt on the floor).
double _trackY(int b) => _floorY(b) - 23;

/// The ten stops: (stop, floor, x).
const _stations = [
  (1, 0, 238.0),
  (2, 0, 364.0),
  (3, 2, 508.0),
  (4, 3, 652.0),
  (5, 3, 772.0),
  (6, 3, 892.0),
  (7, 3, 1012.0),
  (8, 2, 1226.0),
  (9, 4, 1368.0),
  (10, 5, 1296.0),
];

Offset _st(int i) => Offset(_stations[i].$3, _trackY(_stations[i].$2));

// Lifts between floors: (x, from floor, to floor).
const _liftA = (434.0, 0, 2);
const _liftB = (580.0, 2, 3);
const _tubeX = 1082.0; // the pneumatic tube, SkParagraph → framework
const _liftC = (1150.0, 0, 2);
const _liftD = (1300.0, 2, 4);
const _liftE = (1440.0, 4, 5);
const _lifts = [_liftA, _liftB, _liftC, _liftD, _liftE];

/// A booth's rect (plate, readout, body down to the floor).
Rect _booth(int i) {
  final (_, b, x) = _stations[i];
  final w = i == 8 ? 118.0 : 104.0;
  return Rect.fromLTRB(x - w / 2, _floorY(b) - 86, x + w / 2, _floorY(b));
}

// ─────────────────────────────────────────────────────────────────────────────
// Timeline: one crate down the layout() line, the size slip up, then the
// paint() line. A pure function of time; loops every [_Route.period] s.
// ─────────────────────────────────────────────────────────────────────────────

class _Leg {
  _Leg(this.pts, this.t0, this.dur, this.to);

  final List<Offset> pts;
  final double t0;
  final double dur;
  final int to; // station index reached at the end (-1: none)
  late final double length = () {
    var l = 0.0;
    for (var i = 1; i < pts.length; i++) {
      l += (pts[i] - pts[i - 1]).distance;
    }
    return l;
  }();

  Offset at(double p) {
    var d = length * eio(p);
    for (var i = 1; i < pts.length; i++) {
      final s = (pts[i] - pts[i - 1]).distance;
      if (d <= s || i == pts.length - 1) {
        return Offset.lerp(pts[i - 1], pts[i], s == 0 ? 1 : c01(d / s))!;
      }
      d -= s;
    }
    return pts.last;
  }
}

class _Route {
  _Route._() {
    Offset lift((double, int, int) l, int floor) => Offset(l.$1, _trackY(floor));
    var t = 0.9;
    // layout(): 1 → 7.
    appear = t;
    dwell[0] = (t, t + 1.3);
    t += 1.3;
    final hops = <List<Offset>>[
      [_st(0), _st(1)],
      [_st(1), lift(_liftA, 0), lift(_liftA, 2), _st(2)],
      [_st(2), lift(_liftB, 2), lift(_liftB, 3), _st(3)],
      [_st(3), _st(4)],
      [_st(4), _st(5)],
      [_st(5), _st(6)],
    ];
    for (var i = 0; i < hops.length; i++) {
      t = _add(hops[i], t, i + 1, 1.15);
    }
    // The size slip: into the tube, up to the framework.
    slip = _Leg([_st(6), Offset(_tubeX, _trackY(3)), Offset(_tubeX, _trackY(0) - 6)], t, 1.9, -1);
    t += 1.9;
    // The framework reads the size, then calls paint().
    dispatch = (t, t + 1.0);
    t += 1.0;
    paintFrom = Offset(_tubeX + 30, _trackY(0));
    final paint = <List<Offset>>[
      [paintFrom, lift(_liftC, 0), lift(_liftC, 2), _st(7)],
      [_st(7), lift(_liftD, 2), lift(_liftD, 4), _st(8)],
      [_st(8), lift(_liftE, 4), lift(_liftE, 5), _st(9)],
    ];
    paintStart = t;
    t = _add(paint[0], t, 7, 1.2);
    t = _add(paint[1], t, 8, 1.5);
    t = _add(paint[2], t, 9, 2.6);
    period = t + 2.4;
  }

  static final instance = _Route._();

  final legs = <_Leg>[];
  final dwell = List<(double, double)>.filled(10, (0, 0));
  late final double appear;
  late final _Leg slip;
  late final (double, double) dispatch;
  late final Offset paintFrom;
  late final double paintStart;
  late final double period;

  double _add(List<Offset> pts, double t, int to, double stay) {
    final leg = _Leg(pts, t, 0, to);
    final dur = 0.5 + leg.length / 230;
    legs.add(_Leg(pts, t, dur, to));
    dwell[to] = (t + dur, t + dur + stay);
    return t + dur + stay;
  }

  /// Where the crate is at [u] (seconds into the loop), and which station it
  /// is dwelling at (-1 = moving / not there).
  ({Offset? layout, Offset? paint, int at, int reached}) crate(double u) {
    Offset? layout, paint;
    var at = -1, reached = -1;
    for (var i = 0; i < 10; i++) {
      if (u >= dwell[i].$1) reached = i;
      if (u >= dwell[i].$1 && u < dwell[i].$2) at = i;
    }
    if (u >= appear) layout = _st(0);
    for (final l in legs) {
      if (u < l.t0) continue;
      final p = u >= l.t0 + l.dur ? 1.0 : (u - l.t0) / l.dur;
      if (l.to <= 6) {
        layout = l.at(p);
      } else {
        paint = l.at(p);
      }
    }
    if (u >= paintStart && paint == null) paint = paintFrom;
    return (layout: layout, paint: paint, at: at, reached: reached);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painting
// ─────────────────────────────────────────────────────────────────────────────

class _MapPainter extends CustomPainter {
  _MapPainter(this.clock, this.text, this.io, this.d, this.samples, this.wt) : super(repaint: clock);

  final SceneClock clock;
  final TextCache text;
  final SceneInput io;
  final JourneyData d;
  final List<String> samples;
  final TextCache wt;

  @override
  void paint(Canvas canvas, Size size) {
    io.targets
      ..clear()
      ..addAll([for (var i = 0; i < 10; i++) _booth(i)]);
    _Map(canvas, clock.local, text, io, d, samples, wt).draw();
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.d.text != d.text || old.samples != samples;
}

class _Map extends FactoryInk {
  _Map(super.c, this.t, this.txt, this.io, this.d, this.samples, this.wt)
    : u = t % _Route.instance.period,
      r = _Route.instance;

  final double t;
  final TextCache txt;
  final SceneInput io;
  final JourneyData d;
  final List<String> samples;
  final TextCache wt;
  final double u;
  final _Route r;

  late final crateNow = r.crate(u);

  TextPainter mono(String s, double size, [Color col = BP.inkDim, double weight = 400]) =>
      txt.get(s, BT.mono(size, color: col, weight: weight));

  int? get hover {
    final m = io.mouse;
    if (m == null) return null;
    for (var i = 0; i < 10; i++) {
      if (_booth(i).contains(m)) return i;
    }
    return null;
  }

  /// The layout() phase runs until the slip is up; paint() after.
  bool get painting => u >= r.dispatch.$1;

  void draw() {
    // Blueprint draw-on: the building sweeps in from the left.
    final reveal = eo(seg(t, 0, 1.1));
    c.save();
    c.clipRect(Rect.fromLTWH(-40, -60, 1560 * reveal, 760));
    building();
    lifts();
    belts();
    booths();
    atlasRack();
    screen();
    crates();
    ovenFront();
    people();
    readouts();
    brackets();
    c.restore();
  }

  // ── Building ──────────────────────────────────────────────────────────────

  void building() {
    for (var b = 0; b < _bands.length; b++) {
      final top = _floorY(b) - _bandH;
      if (b.isEven) c.drawRect(Rect.fromLTRB(_wall, top, 1472, _floorY(b)), fl(BP.line.withValues(alpha: 0.03)));
      final l = mono(_bands[b], 13, BP.inkDim);
      l.paint(c, Offset(0, top + 10));
      c.drawLine(Offset(0, top + 30), Offset(_wall - 14, top + 30), st(BP.lineFaint, 1));
      // The slab, with openings where lifts and the tube pass through.
      final holes = <double>[
        for (final l in _lifts)
          if (b >= l.$2 && b < l.$3) l.$1,
        if (b < 3) _tubeX,
      ]..sort();
      var x0 = _wall;
      for (final hx in holes) {
        floor(x0, hx - 18, _floorY(b), col: BP.lineDim);
        x0 = hx + 18;
      }
      floor(x0, 1472, _floorY(b), col: BP.lineDim);
    }
    // Outer wall and roof.
    c.drawLine(Offset(_wall, 0), Offset(_wall, _floorY(5)), st(BP.line, 1.4));
    c.drawLine(Offset(_wall - 6, 0), Offset(_wall - 6, _floorY(5)), st(BP.lineDim, 1));
    c.drawLine(const Offset(_wall - 6, 0), const Offset(1472, 0), st(BP.line, 1.4));
  }

  void lifts() {
    for (final (x, b0, b1) in _lifts) {
      final y0 = _floorY(b0) - _bandH + 8, y1 = _floorY(b1);
      for (final dx in [-16.0, 16.0]) {
        c.drawLine(Offset(x + dx, y0), Offset(x + dx, y1), st(BP.lineDim, 1.2));
      }
      final rungs = Path();
      for (var y = y0 + 10; y < y1; y += 18) {
        rungs
          ..moveTo(x - 16, y)
          ..lineTo(x - 12, y)
          ..moveTo(x + 12, y)
          ..lineTo(x + 16, y);
      }
      c.drawPath(rungs, st(BP.lineFaint, 1));
      // Winch at the top.
      c.drawCircle(Offset(x, y0 - 2), 5, st(BP.lineDim, 1.1));
    }
    // The pneumatic tube: from SkParagraph's floor up to the framework.
    final y0 = _trackY(0) - 20, y1 = _trackY(3) + 8;
    for (final dx in [-7.0, 7.0]) {
      c.drawLine(Offset(_tubeX + dx, y0), Offset(_tubeX + dx, y1), st(BP.line, 1.2));
    }
    c.drawRect(Rect.fromCenter(center: Offset(_tubeX, y0 - 4), width: 26, height: 10), st(BP.line, 1.2));
    c.drawRect(Rect.fromCenter(center: Offset(_tubeX, y1 + 4), width: 26, height: 10), st(BP.line, 1.2));
    final up = mono('size ↑', 12, painting || r.slip.t0 <= u ? BP.amber : BP.inkFaint);
    up.paint(c, Offset(_tubeX - 16 - up.width, _floorY(2) - 52));
  }

  void belts() {
    void belt(double x0, double x1, int b) {
      final y = _floorY(b) - 8;
      c.drawRect(Rect.fromLTRB(x0, y, x1, y + 6), fl(BP.panel));
      c.drawLine(Offset(x0, y), Offset(x1, y), st(BP.line, 1.1));
      c.drawLine(Offset(x0, y + 6), Offset(x1, y + 6), st(BP.lineDim, 1));
      final sl = Path();
      for (var x = x0 + 4 + (t * 30) % 12; x < x1 - 2; x += 12) {
        sl
          ..moveTo(x, y + 1)
          ..lineTo(x - 3, y + 5);
      }
      c.drawPath(sl, st(BP.lineFaint, 1));
    }

    belt(186, _liftA.$1 - 18, 0);
    belt(_liftA.$1 + 18, _liftB.$1 - 18, 2);
    belt(_liftB.$1 + 18, _tubeX - 18, 3);
    belt(_tubeX + 18, _liftC.$1 - 18, 0);
    belt(_liftC.$1 + 18, _liftD.$1 - 18, 2);
    belt(_liftD.$1 + 18, _liftE.$1 - 18, 4);
    belt(1236, _liftE.$1 - 18, 5);
  }

  // ── Stations ──────────────────────────────────────────────────────────────

  void booths() {
    final hv = hover;
    for (var i = 0; i < 10; i++) {
      if (i == 8) continue; // the oven is drawn around the crate
      final b = _booth(i);
      final here = crateNow.at == i;
      box(b, col: here || hv == i ? BP.amber : BP.line, w: here ? 1.5 : 1.2);
      c.drawRect(Rect.fromLTRB(b.left + 6, b.top + 22, b.right - 6, b.top + 44), st(BP.lineDim, 1));
      // A doorway the belt runs through.
      c.drawRect(Rect.fromLTRB(b.left + 8, b.bottom - 38, b.right - 8, b.bottom - 8), st(BP.lineFaint, 1));
      accent(i, b, here);
    }
    // The oven's back wall.
    box(_booth(8));
  }

  /// A little mechanism per station, on the booth's shoulder.
  void accent(int i, Rect b, bool here) {
    final o = Offset(b.right - 10, b.top + 10);
    final spin = here ? t * 5 : t * 0.4;
    switch (i) {
      case 2: // engine: a gear
      case 5: // shape: the press flywheel
        final p = Path();
        for (var k = 0; k < 6; k++) {
          final a = spin + k * math.pi / 3;
          p
            ..moveTo(o.dx, o.dy)
            ..lineTo(o.dx + math.cos(a) * 5, o.dy + math.sin(a) * 5);
        }
        c.drawPath(p, st(here ? BP.amber : BP.lineDim, 1));
        c.drawCircle(o, 5.5, st(here ? BP.amber : BP.lineDim, 1));
      case 7: // record: two tape reels
        for (final dx in [-16.0, 0.0]) {
          final q = o.translate(dx, 0);
          c.drawCircle(q, 5, st(here ? BP.amber : BP.lineDim, 1));
          c.drawLine(q, q + Offset(math.cos(spin * 2), math.sin(spin * 2)) * 5, st(here ? BP.amber : BP.lineDim, 1));
        }
      default:
        lamp(o, BP.amber, here && (t * 4).floor().isEven, 3.5);
    }
  }

  void readouts() {
    final hv = hover;
    for (var i = 0; i < 10; i++) {
      final b = _booth(i);
      final (stop, _, x) = _stations[i];
      final here = crateNow.at == i;
      final hot = here || hv == i;
      final name = mono('${stop.toString().padLeft(2, '0')} ${journeyStops[stop].$2}', 12, hot ? BP.amber : BP.ink, 500);
      paintFit(name, Rect.fromLTRB(b.left + 6, b.top + 3, b.right - 6, b.top + 19));
      final s = i < samples.length ? samples[i] : '';
      final done = crateNow.reached >= i;
      final tp = txt.get(s, journeyStyle(12, color: hot ? BP.amber : (done ? BP.ink : BP.inkDim)).copyWith(fontFamily: BP.mono));
      paintFit(tp, Rect.fromLTRB(b.left + 9, b.top + 24, b.right - 9, b.top + 42), fitHeight: true);
      if (hv == i) {
        // Enlarged readout above the booth.
        final big = txt.get(s, journeyStyle(18, color: BP.amber).copyWith(fontFamily: BP.mono));
        final w = math.max(b.width, big.width + 24);
        final pr = Rect.fromLTWH(x - w / 2, b.top - 36, w, 30);
        box(pr, col: BP.amber, w: 1.2);
        big.paint(c, Offset(pr.center.dx - big.width / 2, pr.center.dy - big.height / 2));
        c.drawPath(dashPath(Path()..addRect(b.inflate(3)), dash: 5, gap: 4), st(BP.amber.withValues(alpha: 0.7), 1));
      }
    }
  }

  // ── The atlas rack and the screen ────────────────────────────────────────

  /// The word's different glyphs as shaped (one atlas tile each: t t is
  /// one, the font's ligature), at most ten.
  List<String> get uniques => {for (final r in d.run) d.text.substring(r.start, r.end)}.take(10).toList();

  void atlasRack() {
    final y1 = _floorY(4) - 6;
    final rack = Rect.fromLTRB(1150, y1 - 74, 1276, y1);
    box(rack, col: BP.lineDim, w: 1.1);
    mono('atlas', 11, BP.inkDim).paint(c, Offset(rack.left + 6, rack.top + 3));
    final since = u - r.dwell[8].$1;
    final g = uniques;
    for (var j = 0; j < 10; j++) {
      final cell = Rect.fromLTWH(rack.left + 8 + (j % 5) * 22.0, rack.top + 20 + (j ~/ 5) * 26.0, 20, 24);
      c.drawRect(cell, st(BP.lineFaint, 1));
      if (j >= g.length || since < 0.2 + 0.14 * j) continue;
      final fresh = since < 0.5 + 0.14 * j;
      c.drawRect(cell, st(fresh ? BP.amber : BP.line, 1.1));
      pixels(wt.raster(g[j], journeyStyle(11)), cell.deflate(2), grid: false);
    }
  }

  void screen() {
    final fy = _floorY(5);
    final scr = Rect.fromLTRB(1044, fy - 80, 1224, fy - 14);
    for (final x in [scr.left + 20, scr.right - 20]) {
      c.drawLine(Offset(x, scr.bottom), Offset(x, fy), st(BP.line, 1.2));
    }
    box(scr, w: 1.5);
    final inner = scr.deflate(7);
    final railY = scr.top - 6;
    c.drawLine(Offset(scr.left - 4, railY), Offset(scr.right + 4, railY), st(BP.lineDim, 1.2));
    final start = r.dwell[9].$1 + 0.3;
    final pr = seg(u, start, start + 1.8);
    final fade = 1 - seg(u, r.period - 0.6, r.period);
    final img = wt.raster(d.text, journeyStyle(13));
    if (pr > 0 && fade > 0) {
      c.save();
      c.clipRect(Rect.fromLTRB(inner.left, inner.top, inner.right, inner.top + inner.height * pr));
      pixels(img, inner.deflate(3), opacity: fade);
      c.restore();
    } else {
      for (var y = inner.top + 4; y < inner.bottom; y += 6) {
        c.drawLine(Offset(inner.left + 2, y), Offset(inner.right - 2, y), st(BP.lineFaint.withValues(alpha: 0.6), 1));
      }
    }
    // The print head sweeps while it prints.
    final printing = pr > 0 && pr < 1;
    final hx = printing ? lerp(inner.left + 8, inner.right - 8, 0.5 - 0.5 * math.cos(pr * math.pi * 7)) : scr.right - 10;
    box(Rect.fromCenter(center: Offset(hx, railY), width: 22, height: 10), col: printing ? BP.amber : BP.line, w: 1.2);
    if (printing) {
      final y = inner.top + inner.height * pr;
      final dots = <Offset>[
        for (var k = 0; k < 5; k++) Offset(hx + (rnd(k, (t * 20).floor()) - 0.5) * 10, lerp(railY + 5, y, (k + 1) / 5)),
      ];
      c.drawPoints(ui.PointMode.points, dots, st(BP.amber, 2));
    }
  }

  // ── Crates ────────────────────────────────────────────────────────────────

  double get crateW => (wt.get(d.text, journeyStyle(17)).width + 20).clamp(60.0, 100.0);

  void crates() {
    final cn = crateNow;
    final fade = 1 - seg(u, r.period - 0.5, r.period);
    if (cn.layout != null) {
      final pop = eo(seg(u, r.appear, r.appear + 0.3));
      dim = (u >= r.slip.t0 ? 0.55 : 1) * fade;
      crateAt(cn.layout!, math.min(cn.reached, 6), false, pop);
      dim = 1;
    }
    // The size slip: out of the crate, up the tube, into the framework's hand.
    final s = r.slip;
    if (u >= s.t0 && u < r.dispatch.$2) {
      final p = u >= s.t0 + s.dur ? s.pts.last : s.at((u - s.t0) / s.dur);
      final slip = Rect.fromCenter(center: p, width: 64, height: 18);
      c.drawRRect(RRect.fromRectAndRadius(slip, const Radius.circular(5)), fl(BP.paper));
      c.drawRRect(RRect.fromRectAndRadius(slip, const Radius.circular(5)), st(BP.amber, 1.3));
      paintFit(mono(samples.length > 6 ? samples[6] : '', 10, BP.amber, 600), slip.deflate(3));
    }
    if (cn.paint != null && u < r.dwell[9].$1 + 0.35) {
      final pop = eo(seg(u, r.paintStart, r.paintStart + 0.3));
      final into = seg(u, r.dwell[9].$1, r.dwell[9].$1 + 0.35);
      dim = 1 - into;
      crateAt(cn.paint!, math.max(cn.reached, 6), true, pop);
      dim = 1;
    }
  }

  /// A crate at [center]; [stage] = the last stop it passed (0-based).
  void crateAt(Offset center, int stage, bool paintLine, double pop) {
    if (pop <= 0) return;
    final w = crateW;
    final rect = Rect.fromCenter(center: center, width: w * pop, height: 30 * pop);
    // On a lift: a platform and its cables.
    for (final (lx, b0, _) in _lifts) {
      if ((center.dx - lx).abs() < 0.5 && (center.dy - _trackY(b0)).abs() > 0.5) {
        final top = _floorY(b0) - _bandH + 6;
        c.drawLine(Offset(lx - 12, top), Offset(rect.left + 4, rect.bottom), st(BP.inkDim, 1));
        c.drawLine(Offset(lx + 12, top), Offset(rect.right - 4, rect.bottom), st(BP.inkDim, 1));
        c.drawLine(Offset(rect.left - 4, rect.bottom + 2), Offset(rect.right + 4, rect.bottom + 2), st(BP.amber, 2.4));
      }
    }
    final col = paintLine ? BP.violet : (stage >= 3 ? BP.line : BP.inkDim);
    c.drawRect(rect, fl(BP.panel));
    c.drawRect(rect, st(col, 1.4));
    if (pop < 1) return;
    c.drawLine(Offset(rect.left, rect.top + 6), Offset(rect.right, rect.top + 6), st(col.withValues(alpha: 0.5), 0.8));
    final body = Rect.fromLTRB(rect.left + 5, rect.top + 7, rect.right - 5, rect.bottom - 3);
    if (paintLine && stage >= 8) {
      pixels(wt.raster(d.text, journeyStyle(12)), body);
    } else if (paintLine || stage >= 4) {
      paintFit(wt.get(d.text, journeyStyle(17)), body, fitHeight: true);
    } else {
      paintFit(wt.get(d.text, BT.mono(14, color: BP.inkDim)), body, fitHeight: true);
    }
    if (!paintLine && stage >= 5) {
      // Shaped: a glyph id tick per glyph (a ligature one).
      final n = math.max(1, d.run.length);
      final ticks = Path();
      for (var k = 0; k < n; k++) {
        final x = lerp(body.left + 4, body.right - 4, n == 1 ? 0.5 : k / (n - 1));
        ticks
          ..moveTo(x, rect.bottom - 1)
          ..lineTo(x, rect.bottom + 3);
      }
      c.drawPath(ticks, st(BP.amber, 1.2));
    }
    if (!paintLine && stage >= 6) {
      // Laid out: its size, as a dimension line.
      final y = rect.top - 6;
      c.drawLine(Offset(rect.left, y), Offset(rect.right, y), st(BP.amber, 1));
      c.drawLine(Offset(rect.left, y - 4), Offset(rect.left, y + 4), st(BP.amber, 1));
      c.drawLine(Offset(rect.right, y - 4), Offset(rect.right, y + 4), st(BP.amber, 1));
    }
    if (paintLine && stage >= 7) {
      // Recorded: a strip of film.
      final holes = <Offset>[
        for (var x = rect.left + 5; x < rect.right - 3; x += 7) ...[Offset(x, rect.top + 3), Offset(x, rect.bottom - 2)],
      ];
      c.drawPoints(ui.PointMode.points, holes, st(BP.violet.withValues(alpha: 0.8), 2));
    }
  }

  void ovenFront() {
    final b = _booth(8);
    final win = Rect.fromLTRB(b.left + 8, b.bottom - 40, b.right - 8, b.bottom - 6);
    final shell = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(b)
      ..addRect(win);
    c.drawPath(shell, fl(BP.panel));
    final here = crateNow.at == 8;
    c.drawRect(b, st(here || hover == 8 ? BP.amber : BP.line, here ? 1.5 : 1.2));
    c.drawRect(win, st(BP.line, 1.1));
    c.drawRect(Rect.fromLTRB(b.left + 6, b.top + 22, b.right - 6, b.top + 44), st(BP.lineDim, 1));
    final heat = here ? bump(seg(u, r.dwell[8].$1, r.dwell[8].$2)) : 0.0;
    final flick = 0.5 + 0.5 * math.sin(t * 7.3) * math.sin(t * 2.9 + 1);
    final coil = Path()..moveTo(win.left + 4, win.top + 4);
    for (var i = 1; i <= 12; i++) {
      coil.lineTo(win.left + 4 + i * (win.width - 8) / 12, win.top + (i.isEven ? 4 : 8));
    }
    c.drawPath(coil, st(BP.coral.withValues(alpha: 0.4 + 0.2 * flick + 0.4 * heat), 1.2));
    steam(Offset(b.right - 14, b.top), t, per: 0.7, life: 2.0, rise: 22, r: 5 + 4 * heat, seed: 9);
  }

  // ── People ────────────────────────────────────────────────────────────────

  double groupX(double v) {
    final back = seg(v, r.period - 2.4, r.period);
    final out = eio(seg(v, 2.0, r.paintStart));
    return lerp(560, 1020, out * (1 - eio(back)));
  }

  void people() {
    final gx = groupX(u);
    final moving = (gx - groupX(u - 0.05)).abs() > 0.3;
    final back = u > r.period - 2.4;
    tourGroup(
      gx,
      _floorY(0),
      t,
      h: 24,
      dir: back ? -1 : 1,
      walk: moving ? gx / 4 : -1,
      pointing: moving ? 0 : bump(seg(t % 6, 0.5, 3.5)),
      look: true,
      mouse: io.mouse,
    );
    // The framework's dispatcher reads the size, then sends paint() down.
    {
      final f = Pose();
      final reading = u >= r.slip.t0 + r.slip.dur && u < r.dispatch.$2;
      final sending = u >= r.paintStart && u < r.paintStart + 1.2;
      if (reading) {
        f
          ..upA = 1.6
          ..foA = 2.3
          ..head = 0.15;
      } else if (sending) {
        f.point(lerp(0.9, 1.5, bump(seg(u, r.paintStart, r.paintStart + 1.2))));
      }
      final g = worker(Offset(1206, _floorY(0)), 24, -1, f);
      if (!reading && !sending) clipboard(g.handB);
    }
    // The GPU floor's technician cheers each print.
    {
      final f = Pose();
      final printed = u > r.dwell[9].$1 + 2.1;
      if (printed) {
        f.cheer(t, 3);
      } else {
        f
          ..upA = 1.1
          ..foA = 1.8
          ..head = -0.1;
      }
      final g = worker(Offset(1008, _floorY(5)), 26, 1, f);
      if (!printed) clipboard(g.handA);
    }
  }

  void brackets() {
    void bracket(double x0, double x1, String label, bool on) {
      final y = _floorY(5) + 12;
      final col = on ? BP.amber : BP.amber.withValues(alpha: 0.35);
      c.drawPath(
        Path()
          ..moveTo(x0, y - 8)
          ..lineTo(x0, y)
          ..lineTo(x1, y)
          ..lineTo(x1, y - 8),
        st(col, 1.2),
      );
      final l = txt.get(label, BT.mono(15, color: col));
      l.paint(c, Offset((x0 + x1) / 2 - l.width / 2, y + 4));
    }

    bracket(_stations[2].$3 - 60, _stations[6].$3 + 60, 'layout()', !painting);
    bracket(_stations[7].$3 - 60, 1452, 'paint()', painting);
  }
}
