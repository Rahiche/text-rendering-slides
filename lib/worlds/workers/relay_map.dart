import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/deck.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import '../../slides/journey/journey.dart';
import 'crew.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Section 05's map as a relay race. One runner per stop, stationed in its
// layer; the word is the baton. layout() passes it down to SkParagraph, a
// runner carries the size note back up to the framework, then paint() passes
// the word down again to the GPU crew, who paint it. Hover a runner for what
// the data looks like there, click to go there; type a word to race it.
// ─────────────────────────────────────────────────────────────────────────────

const _bands = ['framework · Dart', 'dart:ui', 'engine · C++', 'SkParagraph', 'Impeller', 'GPU'];
const _bandH = 84.0;
const _bandTop = 20.0;
const _s = 1.2;

double _bandY(int b) => _bandTop + b * _bandH + _bandH / 2;

/// A runner's footing inside band [b].
double _footY(int b) => _bandY(b) + 26;

/// (stop index, band, x) — the same map as the classic deck's.
const _stations = [
  (1, 0, 300.0),
  (2, 0, 430.0),
  (3, 2, 560.0),
  (4, 3, 690.0),
  (5, 3, 820.0),
  (6, 3, 950.0),
  (7, 3, 1080.0),
  (8, 2, 1230.0),
  (9, 4, 1330.0),
  (10, 5, 1430.0),
];

Offset _pt(int i) => Offset(_stations[i].$3, _footY(_stations[i].$2));

/// The framework, where the size note is delivered and paint() starts.
Offset get _home => Offset(_stations[6].$3 + 70, _footY(0));

/// Legs of the race: (from, to, carries the size note?). -1 = [_home].
const _legs = [(0, 1, false), (1, 2, false), (2, 3, false), (3, 4, false), (4, 5, false), (5, 6, false), (6, -1, true), (-1, 7, false), (7, 8, false), (8, 9, false)];
const _legT = 0.95;
const _hand = 0.25;
const _period = 10 * (_legT + _hand) + 2.6; // 10 legs

Offset _at(int i) => i < 0 ? _home : _pt(i);

class WorkersJourneyMap extends StatefulWidget {
  const WorkersJourneyMap({super.key});

  @override
  State<WorkersJourneyMap> createState() => _WorkersJourneyMapState();
}

class _WorkersJourneyMapState extends State<WorkersJourneyMap> {
  late final _ctrl = TextEditingController(text: journeyWord.value);
  int? _hover;

  @override
  void dispose() {
    _ctrl.dispose();
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
        final samples = _samples(d);
        return SceneHost(
          painter: (clock, labels) => _RelayPainter(clock, labels, d.text, samples, _hover),
          children: [
            for (var i = 0; i < _stations.length; i++)
              Positioned(
                left: _stations[i].$3 - 56,
                top: _bandTop + _stations[i].$2 * _bandH,
                width: 112,
                height: _bandH,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _hover = i),
                  onExit: (_) => setState(() => _hover = null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => DeckScope.read(context).goToId(journeyStops[_stations[i].$1].$1),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              bottom: 0,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('baton', style: BT.mono(16, color: BP.inkDim)),
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

  /// What the data looks like at each stop, for this word (as on the
  /// classic map).
  List<String> _samples(JourneyData d) {
    final w = d.text;
    final units = w.codeUnits.take(3).map((u) => u.toRadixString(16).toUpperCase().padLeft(4, '0')).join(' ');
    final bytes = utf8.encode(w).take(4).map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0')).join(' ');
    final ids = d.glyphs.where((g) => !g.isJoinControl).take(3).map((g) => g.font == null ? '?' : '#${g.glyphId}').join(' ');
    final adv = d.glyphs.take(3).map((g) => g.advance).join(' ');
    final probe = TextProbe(TextSpan(text: w, style: journeyStyle(48)));
    final size = probe.size;
    probe.dispose();
    final unique = {for (final g in d.glyphs) '${g.font?.name}:${g.glyphId}:${g.codePoint}'}.length;
    final short = w.length > 8 ? '${w.substring(0, 7)}…' : w;
    return [
      "Text('$short')",
      '$units${w.length > 3 ? ' …' : ''}',
      'utf8 $bytes …',
      '${w.characters.length} graphemes · ${d.rtl ? 'RTL' : 'LTR'}',
      '$ids …',
      'adv $adv …',
      '${size.width.toStringAsFixed(0)} × ${size.height.toStringAsFixed(0)}',
      'DrawTextFrame',
      'atlas ← $unique',
      '${w.characters.length * 2} triangles',
    ];
  }
}

class _RelayPainter extends CustomPainter {
  _RelayPainter(this.clock, this.labels, this.word, this.samples, this.hover) : super(repaint: clock);

  final SceneClock clock;
  final LabelCache labels;
  final String word;
  final List<String> samples;
  final int? hover;

  late Canvas _c;

  @override
  bool shouldRepaint(_RelayPainter old) =>
      old.word != word || old.hover != hover || old.labels != labels || old.samples.join() != samples.join();

  @override
  void paint(Canvas canvas, Size size) {
    _c = canvas;
    final t = clock.t;
    final k = CrewPainter(canvas, t);
    final intro = easeOut3(span(t, 0, 0.8));
    // Lanes (the layers).
    for (var b = 0; b < _bands.length; b++) {
      final top = _bandTop + b * _bandH;
      if (b.isEven) canvas.drawRect(Rect.fromLTWH(0, top, 1472 * intro, _bandH), inkFill(BP.line, 0.035));
      canvas.drawLine(Offset(0, top), Offset(1472 * intro, top), inkStroke(BP.lineFaint, 1));
      labels.mono(_bands[b], 14, BP.inkDim).paint(canvas, Offset(4, top + _bandH / 2 - 9));
    }
    // The track: ramps between the stops, and the return lane.
    final track = Path()..moveTo(_pt(0).dx, _pt(0).dy);
    for (var i = 1; i <= 6; i++) {
      track.lineTo(_pt(i).dx, _pt(i).dy);
    }
    track
      ..lineTo(_home.dx, _home.dy)
      ..lineTo(_pt(7).dx, _pt(7).dy)
      ..lineTo(_pt(8).dx, _pt(8).dy)
      ..lineTo(_pt(9).dx, _pt(9).dy);
    canvas.drawPath(dashPath(partialPath(track, easeInOut3(span(t, 0.2, 1.6))), dash: 8, gap: 5), inkStroke(BP.lineDim, 2));
    // Phases.
    _phase(_pt(2).dx - 20, _pt(6).dx + 20, 'layout() ↓', BP.amber);
    _phase(_pt(7).dx - 20, _pt(9).dx + 20, 'paint() ↓', BP.amber);
    final up = labels.mono('size ↑', 13, BP.line);
    up.paint(canvas, Offset(_home.dx + 10, _bandY(1) - 8));
    canvas.drawLine(Offset(_home.dx, _footY(3) - 10), Offset(_home.dx, _footY(0) + 6), inkStroke(BP.lineFaint, 1));
    // The race.
    final lt = t < 1.8 ? -1.0 : (t - 1.8) % _period;
    var leg = -1;
    var u = 0.0;
    for (var j = 0; j < _legs.length; j++) {
      final a = j * (_legT + _hand);
      if (lt >= a && lt < a + _legT + _hand) {
        leg = j;
        u = ((lt - a) / _legT).clamp(0.0, 1.0);
      }
    }
    final crew = <Worker>[];
    Offset? baton;
    var note = false;
    // Station runners (+ the framework runner at home, index -1).
    for (var i = -1; i < _stations.length; i++) {
      final home = _at(i);
      var x = home.dx, y = home.dy;
      var pose = Pose.stand;
      var f = 1.0;
      var move = false;
      // Is this runner on its leg, or walking back from it?
      for (var j = 0; j < _legs.length; j++) {
        final (from, to, isNote) = _legs[j];
        if (from != i) continue;
        final a = j * (_legT + _hand);
        final b = _at(to);
        if (lt >= a && lt < a + _legT) {
          final e = easeInOut3((lt - a) / _legT);
          x = mix(home.dx, b.dx, e);
          y = mix(home.dy, b.dy, e);
          pose = Pose.run;
          f = b.dx >= home.dx ? 1 : -1;
          move = true;
          baton = Offset(x, y - 46 * _s);
          note = isNote;
        } else if (lt >= a + _legT && lt < a + _legT + _hand) {
          x = b.dx - (b.dx >= home.dx ? 16 : -16);
          y = b.dy;
          pose = Pose.reach;
          f = b.dx >= home.dx ? 1 : -1;
          baton = Offset(b.dx, b.dy - 40 * _s);
          note = isNote;
        } else if (lt >= a + _legT + _hand && lt < a + _legT + _hand + 1.6) {
          final e = easeInOut3((lt - a - _legT - _hand) / 1.6);
          x = mix(b.dx, home.dx, e);
          y = mix(b.dy, home.dy, e);
          pose = Pose.walk;
          f = home.dx >= b.dx ? 1 : -1;
          move = true;
        }
      }
      // Next runner reaches out as the baton comes in.
      if (leg >= 0 && _legs[leg].$2 == i && u > 0.6 && pose == Pose.stand) {
        pose = Pose.reach;
        f = _at(_legs[leg].$1).dx <= home.dx ? -1 : 1;
      }
      final hot = hover != null && hover == i;
      final g = Worker(x, f, pose, y: y, ph: move ? x / 5 : t * 6 + i, move: move, id: 20 + i)
        ..scale = _s
        ..aim = Offset(x + f * 16, y - 34 * _s)
        ..sweat = pose == Pose.run && i >= 3;
      if (hot) g.wave = true;
      crew.add(g);
    }
    // The GPU crew paints the word once the baton arrives.
    final gpu = _pt(9);
    final lastA = (_legs.length - 1) * (_legT + _hand) + _legT;
    final paintU = lt < 0 ? 0.0 : span(lt, lastA, lastA + 1.8);
    final fade = lt < 0 ? 0.0 : 1 - span(lt, _period - 0.5, _period);
    const cell = 10.0;
    final grid = Offset(gpu.dx - 150, gpu.dy - 5 * cell - 4);
    const f = ['11110', '10000', '11100', '10000', '10000'];
    for (var r = 0; r < 5; r++) {
      for (var q = 0; q < 5; q++) {
        final rect = Rect.fromLTWH(grid.dx + q * cell, grid.dy + r * cell, cell - 1, cell - 1);
        final on = f[r][q] == '1' && (r * 5 + q) / 25 < paintU;
        canvas.drawRect(rect, on ? inkFill(BP.amber, fade) : inkStroke(BP.lineFaint, 0.8));
      }
    }
    for (var j = 0; j < 2; j++) {
      final painting = paintU > 0 && paintU < 1;
      crew.add(Worker(grid.dx - 18 - j * 18, 1, painting ? Pose.weld : Pose.stand, y: gpu.dy, id: 40 + j, item: painting ? Tool.torch : Tool.none)
        ..scale = 1.1
        ..aim = grid + Offset(10 + 8 * math.sin(t * 5 + j), 12 + 10.0 * j)
        ..sweat = painting);
    }
    waveNearest(crew, clock.pointer);
    k.drawCrew(crew);
    // Station labels + samples, on top of the runners' lanes.
    for (var i = 0; i < _stations.length; i++) {
      final (stop, band, x) = _stations[i];
      final hot = hover == i;
      final name = labels.mono('${stop.toString().padLeft(2, '0')} ${journeyStops[stop].$2}', 13, hot ? BP.amber : BP.ink);
      final top = _bandTop + band * _bandH + 4;
      name.paint(canvas, Offset(x - name.width / 2, top));
      canvas.drawLine(Offset(x - 22, _footY(band)), Offset(x + 22, _footY(band)), inkStroke(hot ? BP.amber : BP.line, 2));
      final sm = labels.mono(samples[i], hot ? 14 : 11, hot ? BP.amber : BP.inkDim);
      final sx = (x - sm.width / 2).clamp(0.0, 1472 - sm.width);
      if (hot) {
        final r = Rect.fromLTWH(sx - 6, _footY(band) + 2, sm.width + 12, sm.height + 2);
        canvas
          ..drawRect(r, inkFill(BP.panel))
          ..drawRect(r, inkStroke(BP.amber, 1));
      }
      sm.paint(canvas, Offset(sx, _footY(band) + 3));
    }
    // The baton: the word (or, on the way up, the size note).
    final bp = baton;
    if (bp != null) {
      final p = note ? labels.mono(samples[6], 13, BP.line) : labels.get('baton|$word', () => TextSpan(text: word, style: journeyStyle(18)));
      final r = Rect.fromCenter(center: bp, width: p.width + 16, height: p.height + 4);
      canvas
        ..drawRect(r, inkFill(BP.paper))
        ..drawRect(r, inkStroke(note ? BP.line : BP.amber, 1.6));
      p.paint(canvas, r.center - Offset(p.width / 2, p.height / 2));
    }
  }

  void _phase(double l, double r, String label, Color color) {
    const y = _bandTop + 6 * _bandH + 8;
    final p = inkStroke(color, 1.2);
    _c
      ..drawLine(Offset(l, y), Offset(l, y + 10), p)
      ..drawLine(Offset(l, y + 10), Offset(r, y + 10), p)
      ..drawLine(Offset(r, y), Offset(r, y + 10), p);
    final t = labels.mono(label, 15, color);
    t.paint(_c, Offset((l + r) / 2 - t.width / 2, y + 16));
  }
}
