import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/scripts.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import '../world.dart';
import 'crew.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Section dividers: "it takes a crew".
//
// Every divider: the lazy Latin trio tosses the section title into place in
// under two seconds and knocks off, while the big crew builds the section's
// glyphs (other scripts) with scaffolds, torches and sweat. The crew counter
// grows from divider to divider: 3 → 12 → 27 → 58 → 104.
//   01 first training · 02 new recruits · 03 rival crews · 04 inventory ·
//   05 the relay.
// Tap: the crew hurries (and, once done, runs a drill).
// ─────────────────────────────────────────────────────────────────────────────

/// Crew size at each divider: counts up from [_crewFrom] to [_crewTo].
const _crewFrom = [3, 12, 27, 58, 104];
const _crewTo = [12, 27, 58, 104, 104];
const _themes = ['first training', 'new recruits', 'rival crews', 'inventory', 'the relay'];
const _subtitles = [
  'コードポイントからピクセルへ',
  '文字体系ごとに増えるルール',
  '他のエンジンはどうしている？',
  'Flutterのトレードオフ',
  'ひとつの単語の旅',
];

const _ground = 742.0;
const _titleSize = 62.0;
const _titleTop = 292.0;
const _toss0 = 0.45; // first toss
const _tossGap = 0.05;
const _flight = 0.42;
const _crewScale = 1.3;
const _glyph = 148.0; // em of the glyphs the crew builds
const _glyph6 = 132.0; // … when there are six of them

class WorkersSection extends StatelessWidget {
  const WorkersSection({super.key, required this.info});

  final SectionInfo info;

  @override
  Widget build(BuildContext context) => SceneHost(
    painter: (clock, labels) => _SectionPainter(info, clock, labels),
    onTap: (clock, p) => clock.rush(),
  );
}

class _SectionPainter extends CustomPainter {
  _SectionPainter(this.s, this.clock, this.labels) : super(repaint: clock);

  final SectionInfo s;
  final SceneClock clock;
  final LabelCache labels;

  late Canvas _c;
  late CrewPainter _k;
  double _t = 0;
  final List<Worker> _crew = [];

  @override
  bool shouldRepaint(_SectionPainter old) => old.s.index != s.index || old.labels != labels;

  @override
  void paint(Canvas canvas, Size size) {
    _c = canvas;
    _t = clock.t;
    _k = CrewPainter(canvas, _t, flagSplit: 1600);
    _crew.clear();
    _groundLine();
    _number();
    final done = _title();
    switch (s.index) {
      case 0:
        _training();
      case 1:
        _recruits();
      case 2:
        _rivals();
      case 3:
        _inventory();
      default:
        _relay();
    }
    waveNearest(_crew, clock.pointer);
    _k.drawCrew(_crew);
    for (final g in _crew) {
      if (g.p == Pose.lie && !g.wave && g.id >= 0 && g.id < 3) _k.zzz(g.head, _t);
    }
    _counter(done);
  }

  // ── shared pieces ──────────────────────────────────────────────────────────

  void _groundLine() {
    _c.drawLine(const Offset(60, _ground), const Offset(1540, _ground), inkStroke(BP.line, 1.5));
    final tick = inkStroke(BP.lineDim, 1);
    for (var x = 70.0; x < 1540; x += 20) {
      _c.drawLine(Offset(x, _ground), Offset(x, _ground + ((x - 70) % 100 == 0 ? 7 : 4)), tick);
    }
  }

  /// The big outlined number, welded on by a worker in a bosun's chair.
  void _number() {
    final p = labels.get(
      'num|${s.number}',
      () => TextSpan(
        text: s.number,
        style: BT.display(200, weight: 700, height: 1).copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = BP.line,
        ),
      ),
    );
    const o = Offset(92, 64);
    final u = easeInOut3(span(_t, 0.1, 1.3));
    final x = o.dx + p.width * u;
    _c
      ..save()
      ..clipRect(Rect.fromLTRB(0, 0, x, 290));
    p.paint(_c, o);
    _c.restore();
    // The welder rides a rope from the top edge along the reveal.
    final rx = u < 1 ? x : o.dx + p.width + 26 + 3 * math.sin(_t * 0.9);
    final ry = o.dy + 118 + (u < 1 ? 6 * math.sin(_t * 5) : 4 * math.sin(_t * 1.3));
    _c.drawLine(Offset(rx, 18), Offset(rx, ry - 30), inkStroke(BP.inkDim, 1.1));
    _c.drawLine(Offset(rx - 9, ry), Offset(rx + 9, ry), inkStroke(BP.inkDim, 2));
    final g = Worker(rx - 2, -1, u < 1 ? Pose.weld : Pose.sit, y: ry, id: 40, item: u < 1 ? Tool.torch : Tool.none)
      ..visor = u < 1
      ..aim = Offset(rx - 16, ry - 12);
    if (u >= 1) g.f = 1;
    _crew.add(g);
    if (u > 0 && u < 1) _k.stream(Offset(rx - 16, ry - 12), _t, 7 + s.index);
  }

  /// The title, tossed into place by the lazy trio. Returns when it was done.
  double _title() {
    final full = labels.display(s.title, _titleSize, BP.ink, letterSpacing: -1.2);
    final base = full.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    const left = 100.0;
    final plankY = _titleTop + base;
    final right = left + full.width;
    final pallet = right + 46;
    // Letter slots from the real layout.
    final slots = <(int, int, Rect)>[];
    var i = 0;
    for (final g in s.title.characters) {
      final r = full.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + g.length));
      if (g.trim().isNotEmpty && r.isNotEmpty) slots.add((i, i + g.length, r.first.toRect().shift(const Offset(left, _titleTop))));
      i += g.length;
    }
    final n = slots.length;
    final doneAt = _toss0 + (n - 1) * _tossGap + _flight;
    // Plank + struts + pallet.
    _c.drawLine(Offset(left - 12, plankY), Offset(pallet + 118, plankY), inkStroke(BP.line, 1.4));
    for (final x in [left + 20, pallet + 90]) {
      _c.drawLine(Offset(x, plankY), Offset(x - 16, plankY + 16), inkStroke(BP.lineDim, 1.1));
    }
    final left3 = (3 * (1 - span(_t, _toss0, doneAt))).ceil();
    for (var b = 0; b < left3; b++) {
      final r = Rect.fromLTWH(pallet - 12, plankY - 12 - b * 12, 24, 12);
      _c
        ..drawRect(r, inkFill(BP.paper))
        ..drawRect(r, inkStroke(BP.line, 1.1));
    }
    _c.drawLine(Offset(pallet - 16, plankY - 1), Offset(pallet + 16, plankY - 1), inkStroke(BP.inkDim, 2));
    // Landed letters: the real paragraph, clipped to what has arrived.
    var landedRight = left - 1;
    for (var k = 0; k < n; k++) {
      if (_t >= _toss0 + k * _tossGap + _flight) landedRight = slots[k].$3.right + 1;
    }
    if (landedRight > left) {
      _c
        ..save()
        ..clipRect(Rect.fromLTRB(0, _titleTop - 30, landedRight, plankY + 30));
      full.paint(_c, const Offset(left, _titleTop));
      _c.restore();
    }
    // Letters in flight, and a puff where each lands.
    for (var k = 0; k < n; k++) {
      final ts = _toss0 + k * _tossGap;
      final (a, b, r) = slots[k];
      final u = span(_t, ts, ts + _flight);
      if (u > 0 && u < 1) {
        final ch = labels.display(s.title.substring(a, b), _titleSize, BP.ink);
        final from = Offset(pallet - 14, plankY - 40);
        final to = r.topLeft;
        final e = easeInOut3(u);
        final p = Offset.lerp(from, to, e)! + Offset(0, -math.sin(u * math.pi) * (50 + (from.dx - to.dx).abs() * 0.12));
        final sc = mix(0.35, 1, easeOut3(u));
        _c
          ..save()
          ..translate(p.dx, p.dy)
          ..scale(sc);
        ch.paint(_c, Offset.zero);
        _c.restore();
      }
      _k.dust(Offset(r.center.dx, plankY), _t - ts - _flight, spread: 0.5);
    }
    // The trio.
    final tossing = _t < doneAt;
    for (var w = 0; w < 3; w++) {
      Worker g;
      if (tossing && _t > 0.2) {
        if (w < 2) {
          final phase = ((_t - _toss0) / 0.1 + w * 0.5) % 1;
          g = Worker(pallet - 14 - w * 22, -1, Pose.toss, y: plankY, id: w, itemT: phase < 0.5 ? easeOut3(phase * 2) : 0);
        } else {
          g = Worker(pallet + 26, -1, Pose.clipboard, y: plankY, id: w, item: Tool.clipboard);
        }
      } else if (_t <= 0.2) {
        g = Worker(pallet - 14 - (w == 2 ? -40 : w * 22), -1, Pose.stand, y: plankY, id: w);
      } else {
        // Done: coffee on the pallet, a nap, leaning on the last letter.
        final after = _t - doneAt;
        switch (w) {
          case 0:
            g = Worker(pallet - 4, 1, Pose.coffee, y: plankY - 8, id: w, item: Tool.cup);
          case 1:
            final (x, d) = walkTo(after, 0.4, pallet - 36, pallet + 70, 120);
            g = d != 0
                ? Worker(x, d, Pose.walk, y: plankY, ph: x / 4.5, move: true, id: w)
                : Worker(pallet + 70, 1, Pose.lie, y: plankY, id: w);
          default:
            final (x, d) = walkTo(after, 0.2, pallet + 26, right + 16, 110);
            g = d != 0
                ? Worker(x, d, Pose.walk, y: plankY, ph: x / 4.5, move: true, id: w)
                : Worker(right + 16, -1, Pose.lean, y: plankY, id: w, k: (_t * 0.2 % 1) < 0.3 ? 1 : 0);
        }
        // A tap wakes them up for a moment.
        if (clock.sinceTap < 1.6 && (g.p == Pose.lie || g.p == Pose.coffee || g.p == Pose.lean)) {
          g
            ..p = Pose.stand
            ..alarm = true
            ..item = Tool.none;
        }
      }
      _crew.add(g);
    }
    // Label: "3 workers · 1.9 s ✓"
    final secs = math.min(_t, doneAt);
    final done = _t >= doneAt;
    final a = labels.mono('3 workers', 15, BP.inkDim);
    final b = labels.mono('${secs.toStringAsFixed(1)} s', 15, done ? BP.green : BP.line);
    final lx = pallet + 118 - a.width - b.width - 40;
    a.paint(_c, Offset(lx, plankY + 10));
    b.paint(_c, Offset(lx + a.width + 12, plankY + 10));
    if (done) _k.check(Offset(lx + a.width + b.width + 20, plankY + 20), 12, inkStroke(BP.green, 2.2));
    // Japanese subtitle.
    final sub = labels.sample(_subtitles[s.index], 26, BP.inkDim, weight: 400, ja: true);
    final sa = span(_t, 0.8, 1.4);
    if (sa > 0) {
      _c.saveLayer(Rect.fromLTWH(96, plankY + 36, sub.width + 10, sub.height + 8), Paint()..color = Color.fromRGBO(0, 0, 0, sa));
      sub.paint(_c, Offset(100, plankY + 40));
      _c.restore();
    }
    return doneAt;
  }

  /// "12 workers", counting up as the crew arrives; the theme underneath.
  double _crewCount = 0;

  void _counter(double latinDone) {
    final from = _crewFrom[s.index], to = _crewTo[s.index];
    final n = (from + (to - from) * _crewCount).round();
    final growing = n < to;
    // The joke of the talk, big: how many it takes this time.
    final big = labels.display('$n', 150, growing ? BP.coral : BP.ink, weight: 600, letterSpacing: -4);
    big.paint(_c, Offset(1540 - big.width, 30));
    final w = labels.mono('workers', 24, BP.inkDim);
    w.paint(_c, Offset(1540 - w.width, 196));
    final th = labels.mono(_themes[s.index], 16, BP.amber);
    th.paint(_c, Offset(1540 - th.width, 232));
    if (from != to) {
      final was = labels.mono('$from →', 20, BP.inkFaint);
      was.paint(_c, Offset(1540 - big.width - was.width - 18, 142));
    }
    if (growing) {
      for (var i = 0; i < 2; i++) {
        final o = Offset(1540 - w.width - 30 + i * 10, 211);
        _c.drawPath(
          Path()
            ..moveTo(o.dx, o.dy - 7)
            ..lineTo(o.dx + 8, o.dy)
            ..lineTo(o.dx, o.dy + 7)
            ..close(),
          inkFill(BP.coral, 0.5 + 0.5 * math.sin(_t * 8 + i)),
        );
      }
    }
  }

  // ── a glyph under construction ─────────────────────────────────────────────

  /// Draws glyph [g] being built on the ground at [cx] ([size] = em). [p]:
  /// outline rising from the ground; [solid]: ink sweeping down after.
  /// Returns the em box and the height the work has reached.
  (Rect, double) _site(String g, double cx, double size, double p, double solid, {bool ja = false, int seed = 0, Color line = BP.line}) {
    final fillP = labels.sample(g, size, BP.ink, ja: ja);
    final lineP = labels.outline(g, size, line, ja: ja);
    final base = fillP.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final w = math.max(fillP.width, size * 0.7);
    final em = Rect.fromLTRB(cx - w / 2, _ground - size, cx + w / 2, _ground);
    final o = Offset(cx - fillP.width / 2, _ground - size * 0.12 - base);
    final reveal = _ground - size * p;
    final scaffoldA = 1 - span(solid, 0.6, 1);
    // Scaffold grows with the work.
    if (scaffoldA > 0 && p > 0) {
      final st = inkStroke(BP.lineDim, 1.2, scaffoldA);
      final top = math.max(em.top - 10, reveal - 14);
      for (final x in [em.left - 12, em.right + 12]) {
        _c.drawLine(Offset(x, _ground), Offset(x, top), st);
      }
      for (var y = _ground - 34; y > top; y -= 34) {
        _c.drawLine(Offset(em.left - 16, y), Offset(em.right + 16, y), st);
      }
      _c.drawLine(Offset(em.left - 12, _ground), Offset(em.right + 12, math.max(top, _ground - 68)), inkStroke(BP.lineFaint, 1, scaffoldA));
    }
    if (p < 1) {
      _c.drawPath(dashPath(Path()..addRect(em), dash: 5, gap: 5), inkStroke(BP.lineFaint, 1));
    }
    if (p > 0) {
      final cut = solid > 0 ? em.top - 20 + (size + 40) * easeInOut3(solid) : em.top - 30;
      if (solid < 1) {
        _c
          ..save()
          ..clipRect(Rect.fromLTRB(em.left - 60, math.max(reveal, cut), em.right + 60, _ground + 30));
        lineP.paint(_c, o);
        _c.restore();
      }
      if (solid > 0) {
        _c
          ..save()
          ..clipRect(Rect.fromLTRB(em.left - 60, em.top - 40, em.right + 60, cut));
        fillP.paint(_c, o);
        _c.restore();
        if (solid < 1) _c.drawLine(Offset(em.left - 16, cut), Offset(em.right + 16, cut), inkStroke(BP.amber, 2));
      }
      if (p < 1) {
        final sx = em.left + em.width * (0.5 + 0.42 * math.sin(_t * 1.9 + seed));
        _k.stream(Offset(sx, reveal), _t, 31 + seed);
        _c.drawLine(Offset(em.left - 6, reveal), Offset(em.right + 6, reveal), inkStroke(BP.amber, 1, 0.5));
      }
    }
    return (em, reveal);
  }

  /// The site's crew: a welder on the scaffold, a hauler on a rope, a
  /// hammerer at the base. Cheers once done.
  void _siteCrew(Rect em, double reveal, double p, double solid, double doneT, int seed,
      {Color hat = BP.amber, Color? vest, int n = 3, double scale = _crewScale}) {
    final working = p > 0 && p < 1;
    final after = _t - doneT;
    final cheer = p >= 1 && after < 1.6;
    final drill = clock.sinceTap < 2.2 && p >= 1;
    Worker w(double x, double f, Pose pose, {double y = _ground, int id = 0}) => Worker(x, f, pose, y: y, id: seed * 10 + id, ph: _t * 8 + id)
      ..hat = hat
      ..vest = vest
      ..scale = scale;
    // Welder.
    if (n >= 1) {
      Worker g;
      if (working) {
        final y = math.min(_ground, math.max(em.top + 24, reveal + 36));
        g = w(em.left - 10, 1, Pose.weld, y: y)
          ..item = Tool.torch
          ..aim = Offset(em.left + 10, reveal - 2)
          ..visor = true
          ..sweat = true;
      } else {
        g = w(em.left - 20, 1, cheer || drill ? Pose.cheer : (p >= 1 ? Pose.wipe : Pose.stand))..sweat = p >= 1 && after < 4;
      }
      _crew.add(g);
    }
    // Hauler on a rope over the scaffold's pulley.
    if (n >= 2) {
      final pulley = Offset(em.right + 12, math.max(em.top - 10, reveal - 14));
      final g = w(em.right + 40, -1, working ? Pose.pull : (cheer || drill ? Pose.cheer : Pose.stand), id: 1)
        ..sweat = working
        ..rope = working ? pulley : null;
      if (!working && p >= 1 && !cheer && !drill) g.p = (seed + (_t * 0.1).floor()) % 3 == 0 ? Pose.sit : Pose.wipe;
      _crew.add(g);
      if (working) {
        _c.drawCircle(pulley, 3, inkStroke(BP.line, 1.2));
        final by = mix(_ground - 8, pulley.dy + 14, 0.5 + 0.5 * math.sin(_t * 2.2 + seed));
        _c.drawLine(pulley, Offset(pulley.dx + 3, by - 4), inkStroke(BP.amber, 1));
        _c.drawRect(Rect.fromCenter(center: Offset(pulley.dx + 3, by), width: 7, height: 8), inkStroke(BP.line, 1.1));
      }
    }
    // Hammerer at the base.
    if (n >= 3) {
      final hx = em.center.dx + (seed.isEven ? -18 : 18);
      final g = w(hx, seed.isEven ? 1 : -1, working ? Pose.hammer : (cheer || drill ? Pose.cheer : Pose.stand), id: 2)
        ..item = working ? Tool.hammer : Tool.none
        ..sweat = working
        ..y = _ground + 24;
      _crew.add(g);
      if (working) {
        final period = 2 * math.pi / 8;
        final ph = _t * 8 + 2;
        final age = ((ph - math.pi / 2) / (2 * math.pi) % 1) * period;
        _k.burst(Offset(hx + (seed.isEven ? 14 : -14), _ground + 20), age, seed * 13 + (ph / (2 * math.pi)).floor(), n: 4);
      }
    }
  }

  /// Centres for [gs] packed between [x0] and [x1] by their real widths.
  List<double> _pack(List<String> gs, double size, double x0, double x1) {
    final ws = [
      for (final g in gs) math.max(labels.sample(g, size, BP.ink, ja: scriptOfCluster(g) == Script.han).width, size * 0.7) + 28,
    ];
    final sum = ws.fold(0.0, (a, b) => a + b);
    final gap = gs.length < 2 ? 0.0 : math.max(8.0, (x1 - x0 - sum) / (gs.length - 1));
    final out = <double>[];
    var x = x0;
    for (final w in ws) {
      out.add(x + w / 2);
      x += w + gap;
    }
    return out;
  }

  /// Wobbly, effortful progress: stalls and surges but never goes back.
  double _effort(double a, double b) {
    final u = span(_t, a, b);
    return (u - 0.035 * math.sin(u * math.pi * 6)).clamp(0.0, 1.0);
  }

  // ── 01: first training ─────────────────────────────────────────────────────

  void _training() {
    final gs = s.glyphs;
    final xs = _pack(gs, _glyph6, 470, 1540);
    final n = math.min(gs.length, xs.length);
    // Trainees arrive (9 of them): the crew grows 3 → 12.
    var arrived = 0;
    final starts = <double>[];
    for (var i = 0; i < n; i++) {
      starts.add(2.0 + i * 0.85);
    }
    // Chalkboard lesson: the code point of whatever is being trained now.
    var active = 0;
    for (var i = 0; i < n; i++) {
      if (_t >= starts[i]) active = i;
    }
    const board = Rect.fromLTWH(150, 520, 250, 150);
    _c
      ..drawLine(board.bottomLeft + const Offset(24, 0), const Offset(160, _ground), inkStroke(BP.inkDim, 1.6))
      ..drawLine(board.bottomRight + const Offset(-24, 0), const Offset(390, _ground), inkStroke(BP.inkDim, 1.6))
      ..drawRect(board, inkFill(BP.panel))
      ..drawRect(board, inkStroke(BP.line, 1.6));
    final g0 = gs[active];
    final cp = g0.runes.first.toRadixString(16).toUpperCase().padLeft(4, '0');
    labels.mono('U+$cp', 18, BP.amber).paint(_c, board.topLeft + const Offset(18, 16));
    labels.mono('→', 18, BP.inkDim).paint(_c, board.topLeft + const Offset(106, 16));
    final big = labels.sample(g0, 62, BP.ink);
    big.paint(_c, Offset(board.left + 170 - big.width / 2, board.top + 60 - big.height / 2 + 30));
    labels.mono('lesson ${active + 1}', 13, BP.inkFaint).paint(_c, board.bottomLeft + const Offset(18, -26));
    // Instructor with a whistle, pointing at the active stand.
    final whistle = (_t > 0.3 && _t < 0.9) || starts.any((a) => _t > a - 0.1 && _t < a + 0.3) || clock.sinceTap < 0.5;
    final ins = Worker(450, 1, whistle ? Pose.stand : Pose.point, y: _ground, id: 50, item: Tool.clipboard)
      ..scale = 1.25
      ..aim = Offset(xs[active], _ground - 90);
    _crew.add(ins);
    if (whistle) {
      final m = Offset(450 + 5 * 1.25, _ground - 29 * 1.25);
      for (var j = 0; j < 3; j++) {
        final r = 6.0 + j * 5 + (_t * 30 % 5);
        _c.drawArc(Rect.fromCircle(center: m, radius: r), -0.6, 1.2, false, inkStroke(BP.amber, 1.2, 1 - j / 3));
      }
    }
    // Stands.
    var allDone = 0.0;
    for (var i = 0; i < n; i++) {
      final a = starts[i], b = a + 2.4;
      final p = _effort(a, b);
      final solid = span(_t, b + 0.1, b + 0.7);
      allDone = math.max(allDone, b + 0.7);
      final (em, rv) = _site(gs[i], xs[i], _glyph6, p, solid, seed: i);
      // Trainees walk in from the right to their stand.
      final ta = 0.25 + i * 0.22;
      final (x, d) = walkTo(_t, ta, 1680, em.left - 20, 300);
      if (d != 0) {
        _crew.add(Worker(x, d, Pose.walk, y: _ground, ph: x / 4.5, move: true, id: 60 + i)..scale = _crewScale);
        if (i < 3) {
          _crew.add(Worker(x + 38, d, Pose.walk, y: _ground, ph: x / 4.5 + 1, move: true, id: 70 + i)..scale = _crewScale);
        }
      } else {
        arrived += i < 3 ? 2 : 1;
        _siteCrew(em, rv, p, solid, b, i, n: i < 3 ? 3 : 1);
      }
      // "Trained": a green tick over each finished stand.
      final tick = span(_t, b + 0.7, b + 1.0);
      if (tick > 0) {
        final o = Offset(em.center.dx - 10, em.top - 30 - 6 * backOut(tick));
        _k.check(o, 20 * tick, inkStroke(BP.green, 3));
      }
    }
    _crewCount = arrived / 9;
    // Drill on tap once trained: everybody jumps.
    if (_t > allDone && clock.sinceTap < 2.2) {
      for (final g in _crew) {
        if (g.id >= 60 && g.id < 80) g.p = Pose.cheer;
      }
    }
  }

  // ── 02: new recruits ───────────────────────────────────────────────────────

  void _recruits() {
    const sizes = [3, 3, 3, 2, 2, 2];
    final gs = s.glyphs;
    final xs = _pack(gs, _glyph6, 480, 1540);
    final n = math.min(gs.length, xs.length);
    // The crew so far (9 + the trio up top) waves the recruits in.
    for (var j = 0; j < 9; j++) {
      final x = 150.0 + j * 36;
      final waving = _t < 7 && ((_t * 0.8 + j * 0.3) % 1) < 0.6;
      _crew.add(Worker(x, 1, Pose.stand, y: _ground, id: 80 + j)
        ..wave = waving && j.isEven
        ..scale = 1.15);
    }
    labels.mono('crew', 13, BP.inkFaint).paint(_c, const Offset(150, _ground + 12));
    var arrived = 0;
    for (var i = 0; i < n; i++) {
      final sc = scriptOfCluster(gs[i]);
      final color = sc.color;
      final leave = 0.3 + i * 0.5;
      const v = 290.0;
      final arriveT = arrival(leave, 1700, xs[i] + 40, v);
      final a = arriveT + 0.4, b = a + 2.6;
      final p = _effort(a, b);
      final solid = span(_t, b + 0.1, b + 0.7);
      final (em, rv) = _site(gs[i], xs[i], _glyph6, p, solid, ja: sc == Script.han, seed: i + 10, line: BP.line);
      final m = sizes[i];
      // Pennant with the script's name: carried in, then planted by the
      // scaffold, flying over the glyph.
      Offset pole, top;
      if (_t < arriveT) {
        final (x, _) = walkTo(_t, leave, 1700, xs[i] + 40, v);
        for (var r = 0; r < m; r++) {
          final rx = x + r * 34;
          _crew.add(Worker(rx, -1, Pose.walk, y: _ground, ph: rx / 4.5, move: true, id: 100 + i * 4 + r)
            ..vest = color
            ..scale = _crewScale);
        }
        pole = Offset(x - 10, _ground - 26);
        top = pole + const Offset(0, -60);
      } else {
        arrived += m;
        _siteCrew(em, rv, p, solid, b, i + 10, hat: BP.amber, vest: color, n: m);
        pole = Offset(em.left - 18, _ground);
        top = Offset(pole.dx, em.top - 36);
      }
      _c.drawLine(pole, top, inkStroke(BP.inkDim, 1.4));
      final lab = labels.mono(sc.label, 12, color);
      final flag = Rect.fromLTWH(top.dx, top.dy, lab.width + 12, 18);
      _c
        ..drawRect(flag, inkFill(BP.paper))
        ..drawRect(flag, inkStroke(color, 1.2));
      lab.paint(_c, Offset(flag.left + 6, flag.top + 2));
    }
    _crewCount = arrived / 15;
  }

  // ── 03: rival crews ────────────────────────────────────────────────────────

  void _rivals() {
    // Three crews share one tool (HarfBuzz); Apple brings its own shaper.
    const names = ['Chrome', 'Figma', 'Android', 'Apple'];
    const colors = [BP.coral, BP.violet, BP.green, BP.ink];
    const xs = [640.0, 890.0, 1140.0, 1400.0];
    final gs = s.glyphs;
    final n = math.min(gs.length, 4);
    // Our crew watches from the left, taking notes.
    for (var j = 0; j < 6; j++) {
      final x = 170.0 + j * 44;
      final g = Worker(x, 1, j.isEven ? Pose.clipboard : Pose.point, y: _ground, id: 90 + j,
          item: j.isEven ? Tool.clipboard : Tool.none)
        ..aim = Offset(xs[(j + (_t / 3).floor()) % 4], _ground - 120)
        ..scale = 1.15;
      _crew.add(g);
    }
    labels.mono('flutter', 13, BP.amber).paint(_c, const Offset(170, _ground + 12));
    var arrived = 0.0;
    for (var i = 0; i < n; i++) {
      final leave = 0.3 + i * 0.35;
      final arriveT = arrival(leave, 1700, xs[i], 320);
      final a = arriveT + 0.5, b = a + 3.2 + i * 0.2;
      final p = _effort(a, b);
      final solid = span(_t, b + 0.1, b + 0.7);
      final (em, rv) = _site(gs[i], xs[i], _glyph, p, solid, seed: i + 20, ja: gs[i] == '字');
      if (_t < arriveT) {
        final (x, _) = walkTo(_t, leave, 1700, xs[i], 320);
        for (var r = 0; r < 3; r++) {
          _crew.add(Worker(x + r * 32, -1, Pose.walk, y: _ground, ph: (x + r * 32) / 4.5, move: true, id: 200 + i * 5 + r)
            ..hat = colors[i]
            ..scale = _crewScale);
        }
      } else {
        arrived += 1;
        _siteCrew(em, rv, p, solid, b, i + 20, hat: colors[i]);
      }
      // Banner.
      final lab = labels.mono(names[i], 16, colors[i]);
      final bx = xs[i] - lab.width / 2;
      const by = 446.0;
      final ba = span(_t, arriveT - 0.2, arriveT + 0.3);
      if (ba > 0) {
        final r = Rect.fromLTWH(bx - 12, by - 8 * (1 - ba), lab.width + 24, 28);
        _alpha(ba, () {
          _c
            ..drawRect(r, inkFill(BP.paper))
            ..drawRect(r, inkStroke(colors[i], 1.6))
            ..drawRect(Rect.fromLTWH(r.left, r.top, 5, r.height), inkFill(colors[i]));
          lab.paint(_c, Offset(bx + 2, r.top + 4));
        });
      }
    }
    // The tools: the same HarfBuzz wrench in three crews' hands, Core Text in
    // Apple's.
    final hb = span(_t, 2.0, 2.6);
    if (hb > 0) {
      const y = 546.0;
      final p = inkStroke(BP.amber, 1.3, hb);
      _c
        ..drawLine(Offset(xs[0] - 60, y), Offset(xs[2] + 60, y), p)
        ..drawLine(Offset(xs[0] - 60, y), Offset(xs[0] - 60, y + 8), p)
        ..drawLine(Offset(xs[2] + 60, y), Offset(xs[2] + 60, y + 8), p);
      for (var i = 0; i < 3; i++) {
        _wrench(Offset(xs[i], y + 4), hb, BP.amber);
      }
      final l = labels.mono('HarfBuzz', 15, BP.amber);
      _alpha(hb, () => l.paint(_c, Offset((xs[0] + xs[2]) / 2 - l.width / 2, y - 24)));
      final q = inkStroke(BP.ink, 1.3, hb);
      _c
        ..drawLine(Offset(xs[3] - 60, y), Offset(xs[3] + 60, y), q)
        ..drawLine(Offset(xs[3] - 60, y), Offset(xs[3] - 60, y + 8), q)
        ..drawLine(Offset(xs[3] + 60, y), Offset(xs[3] + 60, y + 8), q);
      _gear(Offset(xs[3], y + 4), hb);
      final l2 = labels.mono('Core Text', 15, BP.ink);
      _alpha(hb, () => l2.paint(_c, Offset(xs[3] - l2.width / 2, y - 24)));
    }
    _crewCount = arrived / 4;
  }

  void _wrench(Offset o, double a, Color color) {
    final p = inkStroke(color, 2.4, a);
    _c
      ..drawLine(o + const Offset(-14, 6), o + const Offset(10, -2), p)
      ..drawArc(Rect.fromCircle(center: o + const Offset(14, -3), radius: 5), 0.9, 4.6, false, p);
  }

  void _gear(Offset o, double a) {
    final p = inkStroke(BP.ink, 1.6, a);
    _c.drawCircle(o, 6, p);
    for (var k = 0; k < 8; k++) {
      final an = k * math.pi / 4 + _t * 0.8;
      _c.drawLine(o + Offset(math.cos(an), math.sin(an)) * 6, o + Offset(math.cos(an), math.sin(an)) * 9.5, p);
    }
  }

  void _alpha(double a, void Function() draw) {
    if (a <= 0.01) return;
    if (a >= 0.99) {
      draw();
      return;
    }
    _c.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, a));
    draw();
    _c.restore();
  }

  // ── 04: the toolbox inventory ──────────────────────────────────────────────

  static const _tools = [
    ('vertical', false),
    ('ruby', false),
    ('hyphens', false),
    ('LCD AA', false),
    ('same layout', true),
    ('WidgetSpan', true),
    ('shaders', true),
    ('var fonts', true),
  ];

  void _inventory() {
    const box = Rect.fromLTRB(130, 606, 1010, _ground);
    final cw = box.width / _tools.length;
    // Open lid, leaning back.
    final lid = Path()
      ..moveTo(box.left, box.top)
      ..lineTo(box.left + 26, box.top - 70)
      ..lineTo(box.right - 26, box.top - 70)
      ..lineTo(box.right, box.top);
    _c
      ..drawPath(lid, inkFill(BP.panel))
      ..drawPath(lid, inkStroke(BP.lineDim, 1.4))
      ..drawRect(box, inkFill(BP.panel))
      ..drawRect(box, inkStroke(BP.line, 1.8));
    final flutter = labels.mono('flutter toolbox', 14, BP.inkDim);
    flutter.paint(_c, Offset(box.center.dx - flutter.width / 2, box.top - 58));
    for (var j = 1; j < _tools.length; j++) {
      _c.drawLine(Offset(box.left + j * cw, box.top + 8), Offset(box.left + j * cw, box.bottom), inkStroke(BP.lineDim, 1));
    }
    // The inspector walks along, stamping each compartment.
    const t0 = 1.2, gap = 0.62;
    final idx = ((_t - t0) / gap).floor().clamp(-1, _tools.length);
    for (var j = 0; j < _tools.length; j++) {
      final (name, has) = _tools[j];
      final c = Offset(box.left + (j + 0.5) * cw, box.top + 54);
      _toolIcon(j, c, has);
      final lab = labels.mono(name, 13, has ? BP.ink : BP.inkFaint);
      lab.paint(_c, Offset(c.dx - lab.width / 2, box.bottom - 26));
      final st = span(_t, t0 + j * gap + 0.3, t0 + j * gap + 0.45);
      if (st > 0) {
        final k = 1 + 0.6 * (1 - backOut(st));
        final o = Offset(c.dx, box.top - 20);
        if (has) {
          _k.check(o + Offset(-12 * k, 0), 26 * k, inkStroke(BP.green, 3.4));
        } else {
          final d = 11 * k;
          final p = inkStroke(BP.red, 3.4);
          _c
            ..drawLine(o + Offset(-d, -d), o + Offset(d, d), p)
            ..drawLine(o + Offset(d, -d), o + Offset(-d, d), p);
        }
      }
    }
    final ix = idx < 0 ? box.left - 40 : box.left + (math.min(idx, _tools.length - 1) + 0.5) * cw + 20;
    final walking = idx >= 0 && idx < _tools.length && ((_t - t0) % gap) < 0.25;
    final inspector = Worker(ix + (walking ? -cw * (1 - ((_t - t0) % gap) / 0.25) : 0), 1,
        walking ? Pose.walk : Pose.clipboard, y: _ground + 30, id: 300, item: Tool.clipboard, ph: _t * 9, move: walking);
    if (_t < t0) {
      final (x, d) = walkTo(_t, 0.2, 60, box.left - 40, 200);
      inspector
        ..x = x
        ..p = d != 0 ? Pose.walk : Pose.clipboard
        ..move = d != 0;
    }
    _crew.add(inspector);
    // The big ✕ and ✓, built by the crew with effort.
    final gs = s.glyphs;
    const xs = [1190.0, 1420.0];
    for (var i = 0; i < math.min(2, gs.length); i++) {
      final a = 1.0 + i * 1.2, b = a + 3.0;
      final p = _effort(a, b);
      final solid = span(_t, b + 0.1, b + 0.7);
      final (em, rv) = _site(gs[i], xs[i], 150, p, solid, seed: 40 + i, line: i == 0 ? BP.red : BP.green);
      _siteCrew(em, rv, p, solid, b, 40 + i);
    }
    // The crowd fills the bleachers: 58 → 104.
    const rows = 4;
    final grow = span(_t, 0.4, 6.5);
    _crewCount = grow;
    final total = (46 * grow).round();
    for (var r = 0; r < rows; r++) {
      final y = 300.0 + r * 44;
      _c.drawLine(Offset(1080 - r * 16, y), Offset(1540, y), inkStroke(BP.lineFaint, 1.2));
    }
    var k = 0;
    for (var r = 0; r < rows && k < total; r++) {
      for (var j = 0; j < 12 && k < total; j++, k++) {
        final x = 1100.0 - r * 16 + j * 36 + (r.isOdd ? 18 : 0);
        final y = 300.0 + r * 44;
        final cheer = ((_t * 0.7 + hash01(k, 3)) % 3) < 0.5;
        _crew.add(Worker(x, hash01(k, 1) < 0.5 ? -1 : 1, cheer ? Pose.cheer : Pose.stand, y: y, id: 400 + k)
          ..scale = 0.7
          ..ink = BP.inkDim);
      }
    }
  }

  void _toolIcon(int j, Offset c, bool has) {
    final col = has ? BP.line : BP.inkFaint;
    final p = inkStroke(col, 1.6);
    Path d(Path path) => has ? path : dashPath(path, dash: 4, gap: 3);
    switch (j) {
      case 0: // vertical: glyph boxes stacked in a column
        for (var i = 0; i < 3; i++) {
          _c.drawPath(d(Path()..addRect(Rect.fromCenter(center: c + Offset(0, -26 + i * 18.0), width: 16, height: 16))), p);
        }
      case 1: // ruby: small boxes over a big one
        _c.drawPath(d(Path()..addRect(Rect.fromCenter(center: c + const Offset(0, 6), width: 34, height: 34))), p);
        for (var i = 0; i < 2; i++) {
          _c.drawPath(d(Path()..addRect(Rect.fromCenter(center: c + Offset(-8 + i * 16.0, -22), width: 12, height: 12))), p);
        }
      case 2: // hyphenation: a word cut with a hyphen
        _c.drawPath(d(Path()..addRect(Rect.fromLTWH(c.dx - 30, c.dy - 20, 34, 14))), p);
        _c.drawPath(d(Path()..addRect(Rect.fromLTWH(c.dx - 30, c.dy + 4, 24, 14))), p);
        _c.drawLine(c + const Offset(8, -13), c + const Offset(18, -13), inkStroke(col, 2.4));
      case 3: // LCD subpixels
        for (var i = 0; i < 3; i++) {
          _c.drawPath(d(Path()..addRect(Rect.fromLTWH(c.dx - 18 + i * 13.0, c.dy - 24, 9, 44))), inkStroke(has ? [BP.red, BP.green, BP.line][i] : col, 1.6));
        }
      case 4: // same layout: two screens, same line
        for (var i = 0; i < 2; i++) {
          final r = Rect.fromLTWH(c.dx - 36 + i * 38.0, c.dy - 20, 32, 26);
          _c
            ..drawRect(r, p)
            ..drawLine(r.centerLeft + const Offset(5, 0), r.centerRight + const Offset(-8, 0), inkStroke(BP.amber, 2));
        }
      case 5: // WidgetSpan: a widget inside a line of text
        _c
          ..drawLine(c + const Offset(-34, 0), c + const Offset(-12, 0), inkStroke(col, 3))
          ..drawRect(Rect.fromCenter(center: c + const Offset(0, -4), width: 20, height: 20), inkStroke(BP.amber, 1.8))
          ..drawLine(c + const Offset(12, 0), c + const Offset(34, 0), inkStroke(col, 3));
      case 6: // shaders: a paint roller
        _c
          ..drawRect(Rect.fromLTWH(c.dx - 22, c.dy - 26, 40, 14), p)
          ..drawLine(c + const Offset(18, -19), c + const Offset(26, -19), p)
          ..drawLine(c + const Offset(26, -19), c + const Offset(26, -2), p)
          ..drawLine(c + const Offset(26, -2), c + const Offset(0, -2), p)
          ..drawLine(c + const Offset(0, -2), c + const Offset(0, 20), inkStroke(col, 2.6));
        for (var i = 0; i < 4; i++) {
          _c.drawLine(Offset(c.dx - 20 + i * 10.0, c.dy - 12), Offset(c.dx - 20 + i * 10.0, c.dy - 6), inkStroke([BP.pink, BP.violet, BP.line, BP.green][i], 2));
        }
      default: // variable fonts: a weight slider that keeps moving
        final u = 0.5 + 0.45 * math.sin(_t * 1.4);
        _c
          ..drawLine(c + const Offset(-32, 8), c + const Offset(32, 8), p)
          ..drawCircle(c + Offset(-32 + 64 * u, 8), 5, inkFill(BP.amber));
        final a = labels.sample('a', 30, BP.ink, weight: 300);
        final b = labels.sample('a', 30, BP.ink, weight: 800);
        _alpha(1 - u, () => a.paint(_c, Offset(c.dx - a.width / 2, c.dy - 36)));
        _alpha(u, () => b.paint(_c, Offset(c.dx - b.width / 2, c.dy - 36)));
    }
  }

  // ── 05: the relay ──────────────────────────────────────────────────────────

  void _relay() {
    // Checkpoints: the glyphs F, #9, ▦ (arrows between them), hoisted on
    // gantries by their crews; then runners carry the word through.
    const cx = [360.0, 830.0, 1300.0];
    const top = 470.0;
    final gs = s.glyphs.where((g) => g != '→').toList();
    for (var i = 0; i < math.min(3, gs.length); i++) {
      final up = easeOut3(span(_t, 0.5 + i * 0.6, 2.0 + i * 0.6));
      final x = cx[i];
      // Gantry.
      final gp = inkStroke(BP.lineDim, 1.4);
      _c
        ..drawLine(Offset(x - 90, _ground), Offset(x - 90, top - 10), gp)
        ..drawLine(Offset(x + 90, _ground), Offset(x + 90, top - 10), gp)
        ..drawLine(Offset(x - 96, top - 10), Offset(x + 96, top - 10), gp);
      final by = mix(_ground - 60, top + 8, up);
      final board = Rect.fromCenter(center: Offset(x, by + 56), width: 150, height: 112);
      _c
        ..drawLine(Offset(x - 50, top - 10), board.topLeft + const Offset(20, 0), inkStroke(BP.inkDim, 1))
        ..drawLine(Offset(x + 50, top - 10), board.topRight + const Offset(-20, 0), inkStroke(BP.inkDim, 1))
        ..drawRect(board, inkFill(BP.paper))
        ..drawRect(board, inkStroke(i == 2 ? BP.amber : BP.line, 1.6));
      if (gs[i] == '▦') {
        _pixelF(board.center, 9);
      } else {
        final p = i == 0 ? labels.display(gs[i], 84, BP.ink) : labels.mono(gs[i], 60, BP.line);
        p.paint(_c, board.center - Offset(p.width / 2, p.height / 2));
      }
      // Hoist crew on the rope.
      final hoisting = up > 0 && up < 1;
      for (var r = 0; r < 2; r++) {
        final hx = x + 110 + r * 26;
        _crew.add(Worker(hx, -1, hoisting ? Pose.pull : Pose.stand, y: _ground, id: 500 + i * 3 + r, ph: _t * 7 + r)
          ..rope = hoisting ? Offset(x + 90, top - 10) : null
          ..sweat = hoisting);
      }
      if (i < 2) {
        final a = Offset(x + 120, top + 30), b = Offset(cx[i + 1] - 120, top + 30);
        drawArrow(_c, a, b, inkStroke(BP.lineDim, 1.4), dashed: true, progress: span(_t, 2.4 + i * 0.4, 3.0 + i * 0.4));
      }
    }
    // Track.
    const lane = _ground - 4;
    _c.drawPath(dashPath(Path()..moveTo(80, lane - 20)..lineTo(1540, lane - 20), dash: 10, gap: 8), inkStroke(BP.lineFaint, 1));
    // Runners: F → #9 → ▦, a lap every 7 s.
    const period = 7.0;
    final lt = (_t - 2.6) % period;
    if (_t > 2.6) {
      const legs = [(120.0, 780.0), (780.0, 1250.0), (1250.0, 1500.0)];
      const legT = [(0.0, 2.3), (2.3, 4.3), (4.3, 5.6)];
      for (var r = 0; r < 3; r++) {
        final (x0, x1) = legs[r];
        final (a, b) = legT[r];
        double x;
        Pose pose;
        var f = 1.0;
        if (lt < a) {
          x = x0;
          pose = lt > a - 0.5 ? Pose.reach : Pose.stand;
        } else if (lt < b) {
          x = mix(x0, x1, easeInOut3((lt - a) / (b - a)));
          pose = Pose.run;
        } else {
          final back = span(lt, b + 0.3, period - 0.2);
          x = mix(x1, x0, easeInOut3(back));
          pose = back > 0 && back < 1 ? Pose.walk : Pose.stand;
          if (pose == Pose.walk) f = -1;
        }
        final g = Worker(x, f, pose, y: lane, id: 600 + r, ph: x / (pose == Pose.run ? 6 : 4.5), move: pose != Pose.stand && pose != Pose.reach)
          ..aim = Offset(x - 20, lane - 36)
          ..scale = 1.75;
        _crew.add(g);
        if (lt >= a && lt < b) {
          final baton = ['Flutter', '#9', '▦'][r];
          final bp = g.x + 8;
          final rect = Rect.fromCenter(center: Offset(bp + 6, lane - 78), width: r == 0 ? 76 : 40, height: 24);
          _c
            ..drawRect(rect, inkFill(BP.paper))
            ..drawRect(rect, inkStroke(BP.amber, 1.4));
          if (r == 2) {
            _pixelF(rect.center, 2);
          } else {
            final l = labels.mono(baton, 15, BP.ink);
            l.paint(_c, rect.center - Offset(l.width / 2, l.height / 2));
          }
        }
      }
    }
    // The whole crew lines the track (104 of them, a few dozen in view).
    for (var k = 0; k < 44; k++) {
      final x = 110.0 + k * 32.5 + (k.isOdd ? 8 : 0);
      const y = _ground - 40;
      final near = _crew.any((g) => g.id >= 600 && g.id < 603 && g.p == Pose.run && (g.x - x).abs() < 70);
      _crew.add(Worker(x, hash01(k, 7) < 0.5 ? 1 : -1, near ? Pose.cheer : Pose.stand, y: y, id: 700 + k)
        ..scale = 0.8
        ..ink = BP.inkDim);
    }
    _crewCount = 1;
  }

  /// A tiny pixel "F": what the glyph becomes at the end of the relay.
  void _pixelF(Offset c, double cell) {
    const rows = ['1111', '1000', '1110', '1000', '1000'];
    final o = c - Offset(cell * 2, cell * 2.5);
    for (var r = 0; r < rows.length; r++) {
      for (var q = 0; q < 4; q++) {
        final rect = Rect.fromLTWH(o.dx + q * cell, o.dy + r * cell, cell - 1, cell - 1);
        if (rows[r][q] == '1') {
          _c.drawRect(rect, inkFill(BP.ink));
        } else if (cell > 4) {
          _c.drawRect(rect, inkStroke(BP.lineFaint, 1));
        }
      }
    }
  }
}
