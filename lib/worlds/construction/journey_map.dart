import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../deck/deck.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import '../../slides/journey/journey.dart';
import 'site_kit.dart';

// The journey map as a building cross-section. The word walks into the lobby
// (framework), rides the building's lift DOWN for layout() — dart:ui → engine
// → SkParagraph in the basement — then takes the construction hoist on the
// outside back UP: it drops the size off at the lobby, and paint() carries it
// to the engine's recorder, Impeller's atlas and the GPU billboard on the roof.

const _wl = 170.0; // outer walls
const _wr = 1310.0;
const _shaft = 505.0; // internal lift (x centre)
const _hoist = 1335.0; // external construction hoist (x centre)
const _ground = 340.0;

/// Levels: (label, top, bottom).
const _levels = [
  ('Impeller', 110.0, 180.0),
  ('engine · C++', 180.0, 250.0),
  ('framework · Dart', 250.0, 340.0),
  ('dart:ui → engine', 340.0, 410.0),
  ('SkParagraph', 410.0, 500.0),
];

double _walk(int level) => _levels[level].$3 - 10;

/// Rooms of stops 1..10 (index 0 unused).
final _rooms = <Rect>[
  Rect.zero,
  const Rect.fromLTRB(182, 270, 320, 334), // widget
  const Rect.fromLTRB(326, 270, 464, 334), // string
  const Rect.fromLTRB(546, 346, 726, 404), // engine
  const Rect.fromLTRB(546, 416, 726, 494), // unicode
  const Rect.fromLTRB(732, 416, 912, 494), // fonts
  const Rect.fromLTRB(918, 416, 1098, 494), // shape
  const Rect.fromLTRB(1104, 416, 1302, 494), // layout
  const Rect.fromLTRB(1104, 186, 1302, 244), // record
  const Rect.fromLTRB(1104, 116, 1302, 174), // raster
  const Rect.fromLTRB(700, 6, 1250, 88), // draw: the billboard
];

const _desk = Rect.fromLTRB(1104, 270, 1302, 334); // where the size arrives

class _Wp {
  const _Wp(this.x, this.y, {this.stop, this.dwell = 0, this.size = false});

  final double x;
  final double y;
  final int? stop;
  final double dwell;
  final bool size;

  Offset get p => Offset(x, y);
}

final _route = <_Wp>[
  _Wp(118, _walk(2), dwell: 0.5),
  _Wp(251, _walk(2), stop: 1, dwell: 0.9),
  _Wp(395, _walk(2), stop: 2, dwell: 0.9),
  _Wp(_shaft, _walk(2), dwell: 0.2),
  _Wp(_shaft, _walk(3), dwell: 0.2),
  _Wp(636, _walk(3), stop: 3, dwell: 0.9),
  _Wp(_shaft, _walk(3), dwell: 0.2),
  _Wp(_shaft, _walk(4), dwell: 0.2),
  _Wp(636, _walk(4), stop: 4, dwell: 0.9),
  _Wp(822, _walk(4), stop: 5, dwell: 0.9),
  _Wp(1008, _walk(4), stop: 6, dwell: 0.9),
  _Wp(1203, _walk(4), stop: 7, dwell: 1.0),
  _Wp(_hoist, _walk(4), dwell: 0.2),
  _Wp(_hoist, _walk(2), dwell: 1.1, size: true),
  _Wp(_hoist, _walk(1), dwell: 0.2),
  _Wp(1203, _walk(1), stop: 8, dwell: 0.9),
  _Wp(_hoist, _walk(1), dwell: 0.2),
  _Wp(_hoist, _walk(0), dwell: 0.2),
  _Wp(1203, _walk(0), stop: 9, dwell: 0.9),
  _Wp(_hoist, _walk(0), dwell: 0.2),
  _Wp(_hoist, 92, dwell: 0.1),
  _Wp(975, 47, stop: 10, dwell: 2.6),
];

final class _Timeline {
  _Timeline() {
    var time = 0.0;
    for (var i = 0; i < _route.length; i++) {
      if (i > 0) {
        final a = _route[i - 1].p;
        final b = _route[i].p;
        final vertical = (a.dx - b.dx).abs() < 1;
        time += (b - a).distance / (vertical ? 230 : 430) + 0.15;
      }
      arr.add(time);
      time += _route[i].dwell;
      dep.add(time);
    }
    period = time;
  }

  final arr = <double>[];
  final dep = <double>[];
  late final double period;

  /// Word position, the waypoint it is dwelling at (if any), and the leg.
  (Offset, int?, int) at(double u) {
    for (var i = 0; i < _route.length; i++) {
      if (u < arr[i]) {
        final f = (u - dep[i - 1]) / (arr[i] - dep[i - 1]);
        return (Offset.lerp(_route[i - 1].p, _route[i].p, Curves.easeInOut.transform(c01(f)))!, null, i - 1);
      }
      if (u < dep[i]) return (_route[i].p, i, i);
    }
    return (_route.last.p, _route.length - 1, _route.length - 1);
  }
}

final _tl = _Timeline();

final _shaftPath = dashPath(
  Path()
    ..moveTo(_shaft - 34, 250)
    ..lineTo(_shaft - 34, 500)
    ..moveTo(_shaft + 34, 250)
    ..lineTo(_shaft + 34, 500),
  dash: 6,
  gap: 4,
);

class ConstructionJourneyMap extends StatefulWidget {
  const ConstructionJourneyMap({super.key});

  @override
  State<ConstructionJourneyMap> createState() => _ConstructionJourneyMapState();
}

class _ConstructionJourneyMapState extends State<ConstructionJourneyMap> with SingleTickerProviderStateMixin {
  late final _ctrl = TextEditingController(text: journeyWord.value);
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0);
  final _labels = SiteLabels();
  int? _hover;
  String? _samplesFor;
  List<String> _samples = const [];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => _clock.value = d.inMicroseconds / 1e6)..start();
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
  }

  void _fontsChanged() {
    _labels.clear();
    _samplesFor = null;
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    _ticker.dispose();
    _clock.dispose();
    _ctrl.dispose();
    _labels.clear();
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
        if (_samplesFor != d.text) {
          _samples = _computeSamples(d);
          _samplesFor = d.text;
        }
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _MapPainter(clock: _clock, labels: _labels, word: d.text, samples: _samples, hover: _hover),
                ),
              ),
            ),
            for (var i = 1; i <= 10; i++)
              Positioned.fromRect(
                rect: _rooms[i],
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _hover = i),
                  onExit: (_) => setState(() => _hover = null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => DeckScope.read(context).goToId(journeyStops[i].$1),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              top: 552,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('word', style: BT.mono(16, color: BP.inkDim)),
                  const SizedBox(width: 16),
                  BpTextField(
                    controller: _ctrl,
                    width: 360,
                    style: journeyStyle(34),
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

  /// What the data looks like at each stop, for this word (as in j00_map).
  List<String> _computeSamples(JourneyData d) {
    final w = d.text;
    String short(String s) => s.length > 8 ? '${s.substring(0, 7)}…' : s;
    final units = w.codeUnits.take(3).map((u) => u.toRadixString(16).toUpperCase().padLeft(4, '0')).join(' ');
    final bytes = utf8.encode(w).take(4).map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0')).join(' ');
    final ids = d.glyphs
        .where((g) => !g.isJoinControl)
        .take(3)
        .map((g) => g.font == null ? '?' : '#${g.glyphId}')
        .join(' ');
    final adv = d.glyphs.take(3).map((g) => g.advance).join(' ');
    final probe = TextProbe(TextSpan(text: w, style: journeyStyle(48)));
    final size = probe.size;
    probe.dispose();
    return [
      '',
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
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.clock,
    required this.labels,
    required this.word,
    required this.samples,
    required this.hover,
  }) : super(repaint: clock);

  final ValueNotifier<double> clock;
  final SiteLabels labels;
  final String word;
  final List<String> samples;
  final int? hover;

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final crew = SiteCrew(scale: 1.0);
    final k = SiteKit(canvas, t, labels, crew);
    _Map(canvas, t, k, word, samples, hover).paint();
    crew.flush(canvas);
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.word != word || old.hover != hover || old.samples != samples;
}

class _Map {
  _Map(this.c, this.t, this.k, this.word, this.samples, this.hover);

  final Canvas c;
  final double t;
  final SiteKit k;
  final String word;
  final List<String> samples;
  final int? hover;

  SiteLabels get labels => k.labels;

  void paint() {
    // Loop after the slide has settled in.
    final u = math.max(0.0, t - 1.0) % _tl.period;
    final (pos, at, leg) = _tl.at(u);
    final stop = at == null ? null : _route[at].stop;
    final sizeHere = at != null && _route[at].size;
    final reveal = eo(seg01(t, 0.1, 0.9));

    _shell(reveal);
    for (var i = 1; i <= 10; i++) {
      _room(i, stop == i, hover == i, reveal);
    }
    _deskRoom(u >= _tl.arr[13], sizeHere);
    _decor(u, sizeHere, stop);
    _phases();
    _lift(pos, at, leg, u);
    _hoistCab(pos, at, leg, u);
    _billboard(at == 21 ? u - _tl.arr[21] : null, u);
    _crew();
    _word(pos, at, leg, u);
  }

  // ── The building ───────────────────────────────────────────────────────────

  void _shell(double reveal) {
    // Ground and earth.
    c.drawLine(const Offset(-20, _ground), const Offset(1492, _ground), strokeP(BP.line, 1.4));
    final hatch = Path();
    for (var y = _ground + 12; y < 500; y += 14) {
      for (final x0 in [0.0, 1392.0]) {
        for (var x = x0; x < x0 + 80; x += 14) {
          hatch
            ..moveTo(x, y + 8)
            ..lineTo(x + 8, y);
        }
      }
    }
    c.drawPath(hatch, strokeP(BP.lineFaint, 1));
    labels.draw(c, '±0', const Offset(1470, _ground - 4), size: 10, color: BP.inkFaint, ax: 1, ay: 1);

    final a = reveal;
    final walls = Path()
      ..moveTo(_wl, 500)
      ..lineTo(_wl, 334)
      ..moveTo(_wl, 272)
      ..lineTo(_wl, 110)
      ..moveTo(_wr, 500)
      ..lineTo(_wr, 110);
    c.drawPath(partialPath(walls, a), strokeP(BP.line, 1.6));
    // Slabs.
    for (final y in const <double>[110, 180, 250, 410, 500]) {
      c.drawLine(
        Offset(_wl - 8, y),
        Offset(lerpD(_wl - 8, _wr + 8, a), y),
        strokeP(BP.line, y == 110 || y == 500 ? 2.6 : 2),
      );
    }
    c.drawLine(const Offset(_wl, _ground), Offset(lerpD(_wl, _wr, a), _ground), strokeP(BP.line, 2));
    // Lift shaft.
    c.drawPath(_shaftPath, strokeP(BP.lineDim, 1.2));
    // Floor names, top-left of each level.
    for (final (name, top, _) in _levels) {
      labels.draw(c, name, Offset(_wl + 12, top + 5), size: 12, color: BP.inkDim, alpha: a);
    }
    // Hoist mast outside the right wall.
    k.lattice(_hoist + 26, _hoist + 42, 84, 500, color: BP.lineDim);
    labels.draw(c, 'hoist', const Offset(_hoist + 34, 504), size: 10, color: BP.inkFaint, ax: 0.5, alpha: a);
    labels.draw(c, 'lift', const Offset(_shaft, 504), size: 10, color: BP.inkFaint, ax: 0.5, alpha: a);
  }

  void _room(int i, bool active, bool hot, double reveal) {
    if (i == 10) return;
    final r = _rooms[i];
    final lit = active || hot;
    if (active) c.drawRect(r, fillP(BP.amber.withValues(alpha: 0.08)));
    c.drawRect(r, strokeP(lit ? BP.amber : BP.lineDim, lit ? 1.6 : 1));
    final (_, name) = journeyStops[i];
    labels.draw(
      c,
      '${i.toString().padLeft(2, '0')} $name',
      r.topLeft + const Offset(8, 6),
      size: 13,
      color: lit ? BP.amber : BP.ink,
      alpha: reveal,
    );
    labels.draw(
      c,
      samples.length > i ? samples[i] : '',
      r.topLeft + const Offset(8, 24),
      size: hot ? 13 : 11,
      color: lit ? BP.amber : BP.inkDim,
      alpha: reveal,
    );
  }

  void _deskRoom(bool known, bool arriving) {
    final r = _desk;
    c.drawRect(r, strokeP(arriving ? BP.amber : BP.lineDim, arriving ? 1.6 : 1));
    labels.draw(c, 'size ↑', r.topLeft + const Offset(8, 6), size: 13, color: arriving ? BP.amber : BP.ink);
    if (known && samples.length > 7) {
      labels.draw(
        c,
        samples[7],
        r.topLeft + const Offset(8, 24),
        size: arriving ? 15 : 12,
        color: arriving ? BP.amber : BP.inkDim,
      );
    }
  }

  void _phases() {
    labels.draw(c, 'layout() ↓', const Offset(_shaft - 44, 380), size: 14, color: BP.amber, ax: 1, ay: 0.5);
    labels.draw(c, 'paint() ↑', const Offset(_hoist + 52, 212), size: 14, color: BP.amber, ay: 0.5);
    final down = Path()
      ..moveTo(_shaft - 44, 396)
      ..lineTo(_shaft - 44, 470);
    c.drawPath(dashPath(down, dash: 4, gap: 4), strokeP(BP.amber.withValues(alpha: 0.6), 1.2));
    drawArrowHead(c, const Offset(_shaft - 44, 472), const Offset(_shaft - 44, 460), strokeP(BP.amber, 1.2), 6);
    final up = Path()
      ..moveTo(_hoist + 52, 196)
      ..lineTo(_hoist + 52, 120);
    c.drawPath(dashPath(up, dash: 4, gap: 4), strokeP(BP.amber.withValues(alpha: 0.6), 1.2));
    drawArrowHead(c, const Offset(_hoist + 52, 118), const Offset(_hoist + 52, 130), strokeP(BP.amber, 1.2), 6);
  }

  // ── What happens on the floors between the stops ───────────────────────────

  void _decor(double u, bool sizeHere, int? stop) {
    // 1F: the framework's chain, where the size is delivered.
    const chain = ['Text', 'RichText', 'RenderParagraph'];
    var x = 600.0;
    for (var i = 0; i < chain.length; i++) {
      final p = labels.get(chain[i], 11, i == 2 && sizeHere ? BP.amber : BP.inkDim);
      final r = Rect.fromLTWH(x, 292, p.width + 16, 22);
      c.drawRect(r, strokeP(i == 2 && sizeHere ? BP.amber : BP.lineDim, 1));
      p.paint(c, r.topLeft + Offset(8, (22 - p.height) / 2));
      x = r.right + 26;
      final a = Offset(r.right + 4, r.center.dy);
      final b = Offset(i == 2 ? _desk.left - 4 : x - 4, r.center.dy);
      c.drawLine(a, b, strokeP(BP.lineDim, 1));
      drawArrowHead(c, b, a, strokeP(BP.lineDim, 1), 5);
    }
    // B1: dart:ui → engine, through the pipes.
    for (final y in const <double>[368, 386]) {
      c.drawLine(Offset(740, y), Offset(1296, y), strokeP(BP.lineDim, 3));
      c.drawLine(Offset(740, y), Offset(1296, y), strokeP(BP.paper, 1));
      for (var fx = 790.0; fx < 1290; fx += 96) {
        c.drawLine(Offset(fx, y - 4), Offset(fx, y + 4), strokeP(BP.lineDim, 1.4));
      }
    }
    final flow = (t * 60) % 96;
    for (var fx = 740.0 + flow; fx < 1290; fx += 96) {
      c.drawCircle(Offset(fx, 368), 1.6, fillP(BP.amber.withValues(alpha: 0.7)));
    }
    // 2F: the recorder's conveyor — the paint ops of the DisplayList.
    const ops = ['save', 'translate', 'drawTextFrame', 'restore'];
    const belt = 236.0;
    c.drawLine(const Offset(560, belt), const Offset(1090, belt), strokeP(BP.lineDim, 1.4));
    for (var rx = 566.0; rx < 1090; rx += 26) {
      c.drawCircle(Offset(rx, belt + 4), 2.5, strokeP(BP.lineFaint, 1));
    }
    labels.draw(c, 'DisplayList', const Offset(560, 196), size: 11, color: BP.inkFaint);
    // One strip of ops, repeated until it is longer than the belt, scrolling.
    final strip = <(TextPainter, double, bool)>[];
    var len = 0.0;
    while (len < 560) {
      for (final op in ops) {
        final hot = op == 'drawTextFrame';
        final p = labels.get(op, 10, hot ? BP.amber : BP.inkDim);
        strip.add((p, len, hot));
        len += p.width + 12 + 22;
      }
    }
    final shift = (t * 28) % len;
    for (final (p, at, hot) in strip) {
      final w = p.width + 12;
      final left = 560 + (at + shift) % len;
      if (left + w > 1090) continue;
      final r = Rect.fromLTWH(left, belt - 18, w, 16);
      c.drawRect(r, fillP(BP.paper));
      c.drawRect(r, strokeP(hot ? BP.amber : BP.lineDim, 1));
      p.paint(c, r.topLeft + Offset(6, (16 - p.height) / 2));
    }
    // 3F: Impeller's glyph atlas, with this word's glyphs in it.
    const cols = 20;
    const cell = 24.0;
    const gx = 600.0;
    const gy = 122.0;
    final mine = word.characters.where((g) => g.trim().isNotEmpty).toSet().take(10).toList();
    const others = 'aeonstrilhcumdgpbfwykv';
    final rasterized = u >= _tl.arr[18];
    labels.draw(c, 'atlas', const Offset(gx - 10, gy + cell), size: 11, color: BP.inkFaint, ax: 1, ay: 0.5);
    for (var i = 0; i < cols * 2; i++) {
      final r = Rect.fromLTWH(gx + (i % cols) * cell, gy + (i ~/ cols) * cell, cell, cell);
      c.drawRect(r, strokeP(BP.lineFaint, 1));
      final isMine = i < mine.length;
      final g = isMine ? mine[i] : others[(i * 7) % others.length];
      if (isMine && !rasterized) continue;
      final p = labels.get(g, 14, isMine ? (stop == 9 ? BP.amber : BP.ink) : BP.inkFaint, display: true, weight: 300);
      final sc = math.min(1.0, (cell - 4) / math.max(1, p.width));
      c.save();
      c.translate(r.center.dx - p.width * sc / 2, r.center.dy - p.height * sc / 2);
      c.scale(sc);
      p.paint(c, Offset.zero);
      c.restore();
    }
  }

  // ── Lift and hoist cabs ────────────────────────────────────────────────────

  /// Where a cab running on column [x] is: with the word while it rides,
  /// parked where it left it, then back to [rest].
  double _cabY(double x, Offset pos, int? at, int leg, double u, double rest, int lastIndex) {
    bool onShaft(int i) => (_route[i].x - x).abs() < 1;
    final idx = at ?? leg;
    // Riding: the word is on this column right now.
    if ((pos.dx - x).abs() < 1) return pos.dy;
    // Otherwise: the last waypoint on this column before now.
    for (var i = idx; i >= 0; i--) {
      if (onShaft(i)) {
        if (i == lastIndex) {
          final back = seg01(u, _tl.dep[i] + 0.3, _tl.dep[i] + 1.5);
          return lerpD(_route[i].y, rest, eio(back));
        }
        return _route[i].y;
      }
    }
    return rest;
  }

  void _lift(Offset pos, int? at, int leg, double u) {
    final y = _cabY(_shaft, pos, at, leg, u, _walk(2), 7);
    final cab = Rect.fromLTRB(_shaft - 30, y - 40, _shaft + 30, y + 8);
    c.drawRect(cab, fillP(BP.paper));
    c.drawRect(cab, strokeP(BP.line, 1.4));
    c.drawLine(Offset(_shaft, cab.top), Offset(_shaft, 250), strokeP(BP.inkDim, 1));
    k.crew.head(Offset(cab.left + 10, cab.top + 12), 1);
  }

  void _hoistCab(Offset pos, int? at, int leg, double u) {
    final y = _cabY(_hoist, pos, at, leg, u, _walk(4), 20);
    final cab = Rect.fromLTRB(_hoist - 24, y - 40, _hoist + 24, y + 8);
    c.drawRect(cab, fillP(BP.paper));
    c.drawRect(cab, strokeP(BP.amber, 1.4));
    c.drawLine(cab.topLeft, cab.bottomRight, strokeP(BP.lineFaint, 1));
    c.drawLine(Offset(_hoist + 34, cab.top + 6), Offset(_hoist + 24, cab.top + 6), strokeP(BP.lineDim, 1.4));
    k.crew.head(Offset(cab.right - 10, cab.top + 12), -1);
  }

  // ── The word itself ────────────────────────────────────────────────────────

  void _word(Offset pos, int? at, int leg, double u) {
    if (at == 21) return; // it is on the billboard
    // Fly into the billboard: shrink away on the last leg.
    final last = leg == 20 && at == null;
    final f = last ? seg01(u, _tl.dep[20], _tl.arr[21]) : 0.0;
    final p = labels.get(word, 15, BP.ink, display: true, weight: 300);
    const maxW = 92.0;
    final sc = math.min(1.0, maxW / p.width) * (1 + 0.8 * f);
    final w = p.width * sc + 12;
    final h = p.height * sc + 6;
    final box = Rect.fromCenter(center: pos + const Offset(0, -7), width: w, height: h);
    final alpha = 1 - f;
    c.drawRect(box, fillP(BP.paper.withValues(alpha: alpha)));
    c.drawRect(box, strokeP(BP.amber.withValues(alpha: alpha), 1.4));
    c.save();
    c.translate(box.left + 6, box.top + 3);
    c.scale(sc);
    if (alpha < 1) {
      c.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
      p.paint(c, Offset.zero);
      c.restore();
    } else {
      p.paint(c, Offset.zero);
    }
    c.restore();
    // The size note rides up with it and is handed to the framework at 1F.
    if (samples.length > 7 && (at == 12 || (at == null && leg == 12) || at == 13)) {
      final hand = at == 13 ? eio(seg01(u, _tl.arr[13] + 0.1, _tl.dep[13] - 0.2)) : 0.0;
      final from = Offset(pos.dx, pos.dy - 52);
      final to = Offset(_desk.left + 60, _desk.top + 44);
      final np = Offset.lerp(from, to, hand)!;
      final note = labels.get(samples[7], 10, BP.amber);
      final r = Rect.fromCenter(center: np, width: note.width + 10, height: note.height + 4);
      c.drawRect(r, fillP(BP.paper.withValues(alpha: 1 - hand * 0.6)));
      c.drawRect(r, strokeP(BP.amber.withValues(alpha: 1 - hand * 0.6), 1));
      note.paint(c, r.topLeft + const Offset(5, 2));
    }
    // A little trail when moving.
    if (at == null) {
      final (back, _, _) = _tl.at(math.max(0, u - 0.12));
      c.drawLine(back + const Offset(0, 5), pos + const Offset(0, 5), strokeP(BP.amber.withValues(alpha: 0.5), 2));
    }
  }

  // ── Roof: the GPU billboard ────────────────────────────────────────────────

  void _billboard(double? since, double u) {
    final r = _rooms[10];
    final hot = hover == 10;
    // Posts on the roof.
    for (final x in [r.left + 90, r.right - 90]) {
      c.drawLine(Offset(x, r.bottom), Offset(x, 110), strokeP(BP.lineDim, 1.6));
      c.drawLine(Offset(x - 20, 110), Offset(x, r.bottom + 6), strokeP(BP.lineFaint, 1));
    }
    c.drawRect(r, fillP(BP.panel));
    final lit = since != null;
    c.drawRect(r, strokeP(lit || hot ? BP.amber : BP.line, lit || hot ? 2 : 1.4));
    labels.draw(c, '10 draw', r.topLeft + const Offset(8, 6), size: 12, color: lit || hot ? BP.amber : BP.inkDim);
    labels.draw(c, 'GPU', Offset(r.left - 12, r.center.dy), size: 14, color: BP.inkDim, ax: 1, ay: 0.5);
    labels.draw(
      c,
      samples.length > 10 ? samples[10] : '',
      r.bottomRight + const Offset(-8, -6),
      size: 11,
      color: lit || hot ? BP.amber : BP.inkFaint,
      ax: 1,
      ay: 1,
    );
    // The word, big. It scans on when it arrives, then glows; dim otherwise.
    final p = labels.get(word, 50, lit ? BP.ink : BP.inkFaint, display: true, weight: 300);
    final sc = math.min(1.0, (r.width - 140) / p.width);
    final o = Offset(r.center.dx - p.width * sc / 2, r.center.dy - p.height * sc / 2 + 2);
    final scan = lit ? eo(seg01(since, 0, 0.6)) : 1.0;
    c.save();
    c.clipRect(Rect.fromLTRB(r.left, r.top, r.right, lerpD(r.top, r.bottom, scan)));
    c.translate(o.dx, o.dy);
    c.scale(sc);
    p.paint(c, Offset.zero);
    c.restore();
    if (lit && scan < 1) {
      final y = lerpD(r.top, r.bottom, scan);
      c.drawLine(Offset(r.left + 2, y), Offset(r.right - 2, y), strokeP(BP.amber, 2));
    }
    // Pixel grid over the display.
    final grid = Path();
    for (var x = r.left + 6; x < r.right; x += 6) {
      grid
        ..moveTo(x, r.top + 1)
        ..lineTo(x, r.bottom - 1);
    }
    for (var y = r.top + 6; y < r.bottom; y += 6) {
      grid
        ..moveTo(r.left + 1, y)
        ..lineTo(r.right - 1, y);
    }
    c.drawPath(grid, strokeP(BP.paper.withValues(alpha: 0.35), 1));
  }

  void _crew() {
    final crew = k.crew;
    // Receptionist in the lobby, a worker with a cart in the basement,
    // a technician on the roof.
    crew.walker(const Offset(_wl + 150, 334), face: 1, stride: 0, armF: 0.9 + 0.3 * math.sin(t * 2));
    final ph = (t / 9) % 1.0;
    final go = ph < 0.5;
    final f = go ? ph * 2 : 2 - ph * 2;
    final x = lerpD(_wl + 40, _wl + 250, eio(f));
    final (hand, _, _) = crew.walker(Offset(x, 494), face: go ? 1 : -1, walk: t * 7, armF: 1.2);
    final cart = Rect.fromLTWH(hand.dx + (go ? 4 : -22), 482, 18, 8);
    c.drawRect(cart, strokeP(BP.lineDim, 1.2));
    c.drawCircle(Offset(cart.left + 4, 492), 2, strokeP(BP.line, 1));
    c.drawCircle(Offset(cart.right - 4, 492), 2, strokeP(BP.line, 1));
    final wave = ((t % 7.0) < 1.5);
    crew.walker(
      const Offset(1275, 110),
      face: -1,
      stride: 0,
      armF: wave ? 2.7 + 0.3 * math.sin(t * 9) : 0.4,
      armB: -0.2,
    );
  }
}
