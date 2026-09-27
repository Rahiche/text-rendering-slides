import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/deck.dart';
import '../../deck/scripts.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'crew.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The pipeline as seven specialised crews in a line, each with its tool:
// unicode stamps, the ICU sorter, the font crates, the HarfBuzz wrench, the
// UAX #14 cutter, the layout surveyor and the GPU painter. Each build step
// brings the next crew in; a tray with the text is handed from crew to crew.
// Click a crew to visit its slide.
// ─────────────────────────────────────────────────────────────────────────────

class _Stage {
  const _Stage(this.name, this.tool, this.slideId, this.tray, this.readout);

  final String name;
  final String tool;
  final String slideId;
  final String tray;
  final String readout;
}

const _stages = [
  _Stage('text', 'unicode', 'string', 'Hi كتاب', 'U+0048 U+0069 U+0020 U+0643 U+062A U+0627 U+0628'),
  _Stage('itemize', 'ICU', 'itemize', '2 runs', '[latin →  0..3)   [arabic ←  3..7)'),
  _Stage('fonts', 'font crates', 'fallback', '2 fonts', 'latin → Space Grotesk   arabic → Noto Kufi Arabic'),
  _Stage('shape', 'HarfBuzz', 'shaping', '#43 #76 …', 'code points → glyph ids + advances + offsets'),
  _Stage('wrap', 'UAX #14', 'linebreak', '1 line', 'break opportunities → lines that fit'),
  _Stage('position', 'layout', 'bidi', 'x, y', 'visual order · baselines → x, y per glyph'),
  _Stage('raster', 'GPU', 'raster', '▦', 'outlines → coverage → pixels'),
];

const _colW = 1472 / 7;
const _floor = 400.0;
const _s = 1.55; // crew scale
const _work = 1.1; // seconds a crew works on the tray
const _carry = 0.75; // seconds to hand it to the next crew

double _cx(int i) => _colW * (i + 0.5);

class WorkersPipeline extends StatelessWidget {
  const WorkersPipeline({super.key});

  @override
  Widget build(BuildContext context) => const SlideFrame(title: 'The pipeline', child: _Body());
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  int? _hover;
  final _arrive = List<double?>.filled(7, null);

  @override
  Widget build(BuildContext context) {
    final step = SlideScope.of(context).step;
    final visible = (step + 1).clamp(1, 7);
    return SceneHost(
      painter: (clock, labels) => _PipelinePainter(clock, labels, visible, _hover, _arrive),
      children: [
        for (var i = 0; i < 7; i++)
          Positioned(
            left: i * _colW,
            top: 0,
            width: _colW,
            height: _floor + 40,
            child: i < visible
                ? MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) => setState(() => _hover = i),
                    onExit: (_) => setState(() => _hover = null),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => DeckScope.read(context).goToId(_stages[i].slideId),
                    ),
                  )
                : const SizedBox(),
          ),
      ],
    );
  }
}

class _PipelinePainter extends CustomPainter {
  _PipelinePainter(this.clock, this.labels, this.visible, this.hover, this.arrive) : super(repaint: clock);

  final SceneClock clock;
  final LabelCache labels;
  final int visible;
  final int? hover;
  final List<double?> arrive;

  late Canvas _c;
  late CrewPainter _k;
  double _t = 0;

  @override
  bool shouldRepaint(_PipelinePainter old) => old.visible != visible || old.hover != hover || old.labels != labels;

  @override
  void paint(Canvas canvas, Size size) {
    _c = canvas;
    _t = clock.t;
    _k = CrewPainter(canvas, _t);
    for (var i = 0; i < 7; i++) {
      if (i < visible) {
        arrive[i] ??= _t;
      } else {
        arrive[i] = null;
      }
    }
    // Where is the tray? Stage (with fraction) along the line.
    final period = visible * _work + (visible - 1) * _carry + 0.8;
    final lt = _t % period;
    var at = 0;
    var carrying = false;
    var u = 0.0;
    var acc = 0.0;
    for (var i = 0; i < visible; i++) {
      if (lt < acc + _work) {
        at = i;
        u = (lt - acc) / _work;
        break;
      }
      acc += _work;
      if (i == visible - 1) {
        at = i;
        u = 1;
        break;
      }
      if (lt < acc + _carry) {
        at = i;
        carrying = true;
        u = (lt - acc) / _carry;
        break;
      }
      acc += _carry;
    }
    final focus = hover ?? at;
    final crew = <Worker>[];
    for (var i = 0; i < 7; i++) {
      _station(i, crew, hot: i == focus && i < visible, working: i == at && !carrying && i < visible, u: u);
    }
    // The runner carrying the tray to the next crew.
    Offset tray;
    if (carrying) {
      final x = mix(_cx(at) + 40, _cx(at + 1) - 40, easeInOut3(u));
      final g = Worker(x, 1, Pose.carry, y: _floor, ph: x / 4, move: true, id: 70)
        ..scale = _s
        ..sweat = at > 0;
      crew.add(g);
      tray = Offset(x, _floor - 36 * _s - 10);
    } else {
      tray = Offset(_cx(at) + 70, _floor + 34);
    }
    _k.drawCrew(crew);
    _tray(tray, carrying ? at : at, carrying ? u : 1);
    // Readout for the stage in focus.
    final st = _stages[focus];
    final name = labels.mono(st.name, 18, BP.amber);
    name.paint(_c, const Offset(0, 500));
    _c.drawLine(Offset(name.width + 18, 512), Offset(name.width + 48, 512), inkStroke(BP.lineDim, 1));
    final r = labels.sample(st.readout, 24, BP.ink);
    r.paint(_c, Offset(name.width + 66, 512 - r.height / 2));
  }

  void _tray(Offset c, int stage, double u) {
    final label = _stages[stage].tray;
    final p = stage == 0 ? labels.sample(label, 15, BP.ink) : labels.mono(label, 13, BP.ink);
    final r = Rect.fromCenter(center: c, width: math.max(46, p.width + 16), height: 22);
    _c
      ..drawRect(r, inkFill(BP.paper))
      ..drawRect(r, inkStroke(BP.amber, 1.5));
    if (label == '▦') {
      for (var y = 0; y < 3; y++) {
        for (var x = 0; x < 3; x++) {
          if ((x + y).isEven) _c.drawRect(Rect.fromLTWH(r.center.dx - 7 + x * 5, r.center.dy - 7 + y * 5, 4, 4), inkFill(BP.ink));
        }
      }
    } else {
      p.paint(_c, r.center - Offset(p.width / 2, p.height / 2));
    }
  }

  void _station(int i, List<Worker> crew, {required bool hot, required bool working, required double u}) {
    final cx = _cx(i);
    final shown = i < visible;
    final ink = hot ? BP.amber : (shown ? BP.ink : BP.inkFaint);
    // Header: number, name, tool.
    labels.mono((i + 1).toString().padLeft(2, '0'), 14, hot ? BP.amber : BP.inkFaint).paint(_c, Offset(cx - 88, 0));
    final name = labels.display(_stages[i].name, 28, ink);
    name.paint(_c, Offset(cx - 88, 22));
    final tool = labels.mono(_stages[i].tool, 14, shown ? BP.line : BP.inkFaint);
    tool.paint(_c, Offset(cx - 88, 62));
    // Platform.
    final plat = Rect.fromLTRB(cx - 92, _floor, cx + 92, _floor + 10);
    if (!shown) {
      _c.drawPath(dashPath(Path()..addRect(Rect.fromLTRB(cx - 92, 110, cx + 92, _floor + 10)), dash: 5, gap: 5), inkStroke(BP.lineFaint, 1));
      final q = labels.mono('?', 28, BP.inkFaint);
      q.paint(_c, Offset(cx - q.width / 2, 240));
      return;
    }
    _c
      ..drawRect(plat, inkFill(BP.panel))
      ..drawRect(plat, inkStroke(hot ? BP.amber : BP.lineDim, hot ? 1.8 : 1.2));
    if (i < visible - 1) {
      // Hand-over lane to the next crew.
      _c.drawPath(dashPath(Path()..moveTo(cx + 96, _floor + 5)..lineTo(_cx(i + 1) - 96, _floor + 5), dash: 4, gap: 4),
          inkStroke(BP.lineDim, 1));
    }
    // The crew walks in when its build step arrives.
    final since = _t - (arrive[i] ?? _t);
    final (wx, wd) = walkTo(since, 0, 1500, cx, 900);
    final entering = wd != 0;
    final dx = entering ? wx - cx : 0.0;
    final t = _t + i * 0.37;
    final busy = working || hot;
    Worker w(double x, double f, Pose p, {int id = 0}) => Worker(cx + x + dx, entering ? -1 : f, entering ? Pose.walk : p,
        y: _floor, id: i * 10 + id, ph: entering ? (cx + x + dx) / 4 : t * 8 + id, move: entering)
      ..scale = _s
      ..sweat = busy && i > 0;
    final a = entering ? 0.0 : 1.0;
    switch (i) {
      case 0: // unicode: stamping code points onto blocks
        const cps = ['U+48', 'U+69', 'U+20', 'U+643', 'U+62A', 'U+627', 'U+628', '…'];
        for (var b = 0; b < cps.length; b++) {
          final r = Rect.fromLTWH(cx - 14 + (b % 3) * 34, _floor - 34 - (b ~/ 3) * 34, 32, 32);
          _c
            ..drawRect(r, inkFill(BP.paper))
            ..drawRect(r, inkStroke(b == ((t * 2).floor() % 7) && busy ? BP.amber : BP.line, 1.3, a));
          final l = labels.mono(cps[b], 9, BP.inkDim);
          l.paint(_c, r.center - Offset(l.width / 2, l.height / 2));
        }
        crew
          ..add(w(-44, 1, busy ? Pose.hammer : Pose.stand)..item = Tool.hammer)
          ..add(w(-76, 1, Pose.clipboard, id: 1)..item = Tool.clipboard);
        if (busy) _k.burst(Offset(cx - 22 + dx, _floor - 20), (t * 8 / (2 * math.pi) % 1) * 0.78, (t * 1.27).floor(), n: 4);
      case 1: // ICU sorter: a hopper splitting into two bins
        final p = inkStroke(BP.line, 1.6, a);
        final hop = Path()
          ..moveTo(cx - 44, 150)
          ..lineTo(cx + 44, 150)
          ..lineTo(cx + 10, 200)
          ..lineTo(cx - 10, 200)
          ..close();
        _c
          ..drawPath(hop, inkFill(BP.panel))
          ..drawPath(hop, p)
          ..drawLine(Offset(cx - 10, 200), Offset(cx - 10, 232), p)
          ..drawLine(Offset(cx + 10, 200), Offset(cx + 10, 232), p);
        labels.mono('ICU', 11, BP.line).paint(_c, Offset(cx - 11, 160));
        for (final (k, col, lab) in [(-1, Script.latin.color, 'latin →'), (1, Script.arabic.color, '← arabic')]) {
          final bin = Rect.fromLTWH(cx + (k < 0 ? -88 : 14), _floor - 76, 74, 76);
          _c
            ..drawRect(bin, inkFill(col, 0.08))
            ..drawRect(bin, inkStroke(col, 1.6, a))
            ..drawLine(Offset(cx + k * 10, 232), Offset(bin.center.dx, bin.top - 2), inkStroke(col, 1.4, a * 0.7));
          final l = labels.mono(lab, 11, col);
          l.paint(_c, Offset(bin.center.dx - l.width / 2, bin.bottom - 20));
        }
        if (busy) {
          final ph = (t * 1.3) % 1;
          final k = ((t * 1.3).floor()).isEven ? -1 : 1;
          final bx = cx + k * 51 * easeInOut3(span(ph, 0.4, 1));
          final by = mix(160, _floor - 60, ph);
          _c.drawRect(Rect.fromCenter(center: Offset(bx, by), width: 12, height: 12), inkFill(k < 0 ? Script.latin.color : Script.arabic.color));
        }
        crew.add(w(-60, 1, busy ? Pose.climb : Pose.stand)..y = 206);
        _k.ladder(Offset(cx - 70 + dx, _floor), Offset(cx - 52 + dx, 196), a: a);
        crew.add(w(82, -1, Pose.clipboard, id: 1)..item = Tool.clipboard);
      case 2: // font crates
        for (final (k, g, name, y) in [(-1, 'Aa', 'Grotesk', _floor - 84.0), (1, 'ب', 'Kufi', _floor - 84.0), (0, '字', 'fallback', _floor - 176.0)]) {
          final r = Rect.fromLTWH(cx - 42 + k * 44, y, 84, 84);
          _c
            ..drawRect(r, inkFill(BP.paper))
            ..drawRect(r, inkStroke(k == 0 ? BP.lineDim : BP.line, 1.6, a))
            ..drawLine(r.topLeft + const Offset(0, 12), r.topRight + const Offset(0, 12), inkStroke(BP.lineDim, 1, a));
          final gp = labels.sample(g, 34, k == 0 ? BP.inkDim : BP.ink, ja: k == 0);
          gp.paint(_c, Offset(r.center.dx - gp.width / 2, r.top + 18));
          final l = labels.mono(name, 10, BP.inkDim);
          l.paint(_c, Offset(r.center.dx - l.width / 2, r.bottom - 16));
        }
        crew.add(w(-78, 1, busy ? Pose.reach : Pose.stand)..aim = Offset(cx - 60 + dx, _floor - 84));
        crew.add(w(84, -1, busy ? Pose.shoulder : Pose.stand, id: 1));
      case 3: // HarfBuzz: a big wrench on the joined word
        final word = labels.sample('كتاب', 64, BP.ink);
        final o = Offset(cx - word.width / 2 + 14, _floor - 150);
        final box = Rect.fromLTWH(o.dx - 6, o.dy + 6, word.width + 12, word.height - 8);
        _c
          ..drawLine(Offset(box.left + 8, box.bottom), Offset(box.left + 8, _floor), inkStroke(BP.lineDim, 1.4, a))
          ..drawLine(Offset(box.right - 8, box.bottom), Offset(box.right - 8, _floor), inkStroke(BP.lineDim, 1.4, a));
        word.paint(_c, o);
        _c.drawPath(dashPath(Path()..addRect(box), dash: 4, gap: 3), inkStroke(BP.amber, 1.2, a));
        // The wrench itself, turning.
        final pivot = Offset(box.left - 4 + dx, box.center.dy + 6);
        final ang = busy ? -0.5 + 0.35 * math.sin(t * 5) : -0.4;
        final end = pivot + Offset(-math.cos(ang) * 56, math.sin(ang) * 56 + 40);
        _c
          ..drawLine(pivot, end, inkStroke(BP.amber, 5, a))
          ..drawArc(Rect.fromCircle(center: pivot, radius: 9), 0.8, 4.7, false, inkStroke(BP.amber, 4, a));
        crew.add(w(-84, 1, busy ? Pose.push : Pose.stand)..sweat = busy);
        crew.add(w(86, -1, busy ? Pose.wrench : Pose.stand, id: 1)
          ..item = Tool.wrench
          ..aim = Offset(box.right - 4 + dx, box.bottom - 10));
        if (busy) _k.burst(pivot, (t * 1.1) % 0.5, (t * 2.2).floor(), n: 4);
      case 4: // UAX #14: sawing the line at a break opportunity
        final bar = Rect.fromLTWH(cx - 86, _floor - 70, 172, 22);
        final cut = cx + 16;
        for (final x in [bar.left + 14, bar.right - 14]) {
          _c
            ..drawLine(Offset(x, bar.bottom), Offset(x - 12, _floor), inkStroke(BP.lineDim, 1.4, a))
            ..drawLine(Offset(x, bar.bottom), Offset(x + 12, _floor), inkStroke(BP.lineDim, 1.4, a));
        }
        final open = busy ? 0.0 : 8.0;
        for (var b = 0; b < 6; b++) {
          final r = Rect.fromLTWH(bar.left + b * 28.6 + (b >= 3 ? open : 0), bar.top, 26, bar.height);
          _c.drawRect(r, inkStroke(b < 3 ? BP.line : BP.inkDim, 1.4, a));
        }
        _c.drawPath(dashPath(Path()..moveTo(cut, bar.top - 60)..lineTo(cut, bar.bottom + 8), dash: 4, gap: 3), inkStroke(BP.amber, 1.6, a));
        labels.mono('break', 10, BP.amber).paint(_c, Offset(cut - 14, bar.top - 74));
        if (busy) {
          final sx = cut + 10 * math.sin(t * 16);
          _c
            ..drawLine(Offset(sx - 22, bar.top - 4), Offset(sx + 22, bar.top - 4), inkStroke(BP.ink, 2.6))
            ..drawLine(Offset(sx + 22, bar.top - 4), Offset(sx + 30, bar.top - 14), inkStroke(BP.ink, 3));
          _k.stream(Offset(cut, bar.top + 2), t, 44);
        }
        crew.add(w(56, -1, busy ? Pose.push : Pose.stand)..y = _floor);
        crew.add(w(-92, 1, busy ? Pose.pull : Pose.stand, id: 1)..rope = busy ? bar.centerLeft + Offset(dx, 0) : null);
      case 5: // layout: the surveyor, the staff and the baseline
        final tx = cx - 34 + dx;
        _c
          ..drawLine(Offset(tx, _floor - 52), Offset(tx - 16, _floor), inkStroke(BP.inkDim, 1.5, a))
          ..drawLine(Offset(tx, _floor - 52), Offset(tx + 14, _floor), inkStroke(BP.inkDim, 1.5, a))
          ..drawLine(Offset(tx, _floor - 52), Offset(tx + 2, _floor), inkStroke(BP.inkDim, 1.5, a))
          ..drawRect(Rect.fromLTWH(tx - 9, _floor - 68, 18, 16), inkFill(BP.paper))
          ..drawRect(Rect.fromLTWH(tx - 9, _floor - 68, 18, 16), inkStroke(BP.line, 1.5, a));
        crew.add(w(-70, 1, Pose.survey)..aim = Offset(tx - 9, _floor - 60));
        crew.add(w(80, -1, Pose.pole, id: 1)..item = Tool.staff);
        final base = _floor - 30.0;
        _c.drawLine(Offset(cx - 92, base), Offset(cx + 92, base), inkStroke(BP.amber, 1.2, 0.5 * a));
        if (busy) {
          final la = (t * 0.9) % 1;
          _c.drawPath(dashPath(Path()..moveTo(tx + 9, _floor - 60)..lineTo(mix(tx + 9, cx + 74, easeOut3(la * 2)), _floor - 60), dash: 5, gap: 3),
              inkStroke(BP.amber, 1.4));
        }
        labels.mono('baseline', 10, BP.amber).paint(_c, Offset(cx - 10, base + 4));
        for (var g = 0; g < 4; g++) {
          _c.drawRect(Rect.fromLTWH(cx - 6 + g * 16, base - 28 + (g.isOdd ? 8 : 0), 12, 28 - (g.isOdd ? 8 : 0)), inkStroke(BP.line, 1.1, a));
        }
      default: // GPU: painting coverage into pixels
        const n = 7;
        const cell = 17.0;
        final g0 = Offset(cx - 34, _floor - 34 - n * cell);
        const cov = [
          [0, 0, 3, 7, 8, 5, 0],
          [0, 0, 0, 0, 2, 8, 2],
          [0, 0, 4, 8, 8, 9, 3],
          [0, 5, 8, 2, 0, 9, 3],
          [0, 8, 3, 0, 3, 9, 3],
          [0, 6, 8, 7, 8, 7, 6],
          [0, 0, 1, 2, 0, 0, 0],
        ];
        final filled = busy ? ((t * 16) % (n * n + 10)).floor() : n * n;
        _c
          ..drawLine(Offset(g0.dx + 10, g0.dy + n * cell), Offset(g0.dx - 4, _floor), inkStroke(BP.inkDim, 1.5, a))
          ..drawLine(Offset(g0.dx + n * cell - 10, g0.dy + n * cell), Offset(g0.dx + n * cell + 4, _floor), inkStroke(BP.inkDim, 1.5, a));
        for (var r = 0; r < n; r++) {
          for (var q = 0; q < n; q++) {
            final rect = Rect.fromLTWH(g0.dx + q * cell, g0.dy + r * cell, cell - 1, cell - 1);
            final k = r * n + q;
            if (k < filled && cov[r][q] > 0) _c.drawRect(rect, inkFill(BP.ink, cov[r][q] / 9));
            _c.drawRect(rect, inkStroke(BP.lineFaint, 0.8, a));
          }
        }
        final k = math.min(filled, n * n - 1);
        final brush = g0 + Offset((k % n + 0.5) * cell, (k ~/ n + 0.5) * cell);
        final py = math.min(_floor, brush.dy + 44);
        if (py < _floor - 4) _k.ladder(Offset(cx - 58 + dx, _floor), Offset(cx - 52 + dx, py + 6), a: a);
        crew.add(w(-54, 1, busy ? Pose.weld : Pose.stand)
          ..y = busy ? py : _floor
          ..item = Tool.torch
          ..aim = busy ? brush + Offset(dx, 0) : null);
        crew.add(w(-84, 1, Pose.bucket, id: 1)
          ..item = Tool.bucket
          ..move = false);
    }
  }
}
