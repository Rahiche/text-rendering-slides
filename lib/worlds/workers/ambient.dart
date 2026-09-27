import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import 'crew.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Ambient: tiny crews in the bottom corners of every content slide, on the
// floor of the ruler band. Left: the lazy Latin trio (coffee, a nap, a lean
// on their one crate). Right: the busy crew, hauling and welding glyphs of
// other scripts. Dim, slow, and on a world-wide clock, so they carry on
// from slide to slide instead of restarting.
// ─────────────────────────────────────────────────────────────────────────────

const _floor = 858.0;
const _busy = ['字', 'ب', 'क', 'ก', '한', 'ע'];

class WorkersAmbient extends StatelessWidget {
  const WorkersAmbient({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: SceneHost(shared: true, interactive: false, painter: (clock, labels) => _AmbientPainter(clock, labels)),
  );
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.clock, this.labels) : super(repaint: clock);

  final SceneClock clock;
  final LabelCache labels;

  @override
  bool shouldRepaint(_AmbientPainter old) => old.labels != labels;

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.t;
    final k = CrewPainter(canvas, t);
    canvas.saveLayer(const Rect.fromLTRB(0, 740, 1600, 900), Paint()..color = const Color.fromRGBO(0, 0, 0, 0.62));
    final crew = <Worker>[];
    Worker dim(Worker g) => g
      ..scale = 0.8
      ..ink = BP.inkDim;

    // ── left: the trio ──
    canvas.drawLine(const Offset(18, _floor), const Offset(146, _floor), inkStroke(BP.lineDim, 1));
    const crate = Rect.fromLTWH(84, _floor - 20, 26, 20);
    canvas
      ..drawRect(crate, inkFill(BP.paper))
      ..drawRect(crate, inkStroke(BP.lineDim, 1.1));
    labels.display('Aa', 11, BP.inkDim).paint(canvas, crate.topLeft + const Offset(6, 3));
    crew
      ..add(dim(Worker(40, 1, Pose.coffee, y: _floor, id: 1, item: Tool.cup)))
      ..add(dim(Worker(76, -1, Pose.lean, y: _floor, id: 2, k: (t * 0.15 % 1) < 0.25 ? 1 : 0)))
      ..add(dim(Worker(132, -1, Pose.lie, y: _floor, id: 3)));

    // ── right: the busy crew ──
    canvas.drawLine(const Offset(1466, _floor), const Offset(1584, _floor), inkStroke(BP.lineDim, 1));
    // A glyph under construction; a new one every 12 s.
    const period = 12.0;
    final n = (t / period).floor();
    final u = (t % period) / period;
    final g = _busy[n % _busy.length];
    final fill = labels.sample(g, 30, BP.inkDim);
    final line = labels.outline(g, 30, BP.lineDim, width: 1.2);
    final base = fill.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final o = Offset(1560 - fill.width / 2, _floor - 5 - base);
    final p = span(u, 0.15, 0.75);
    final reveal = _floor - 32 * p;
    canvas
      ..save()
      ..clipRect(Rect.fromLTRB(1500, reveal, 1600, _floor + 4));
    (u > 0.8 ? fill : line).paint(canvas, o);
    canvas.restore();
    if (p > 0 && p < 1) {
      canvas.drawLine(const Offset(1540, _floor), Offset(1540, reveal - 6), inkStroke(BP.lineDim, 1));
      canvas.drawLine(const Offset(1580, _floor), Offset(1580, reveal - 6), inkStroke(BP.lineDim, 1));
      k.stream(Offset(1550 + 8 * math.sin(t * 2), reveal), t, 5);
    }
    final work = p > 0 && p < 1;
    crew
      ..add(dim(Worker(1534, 1, work ? Pose.weld : Pose.wipe, y: _floor, id: 11, item: work ? Tool.torch : Tool.none)
        ..aim = Offset(1548, reveal)
        ..visor = work
        ..sweat = true))
      ..add(dim(Worker(1590, -1, work ? Pose.hammer : Pose.stand, y: _floor, id: 12, item: Tool.hammer, ph: t * 8)..sweat = work));
    // Two haulers carry the next glyph in, back and forth, forever.
    final c = (t * 0.07) % 1;
    final back = c > 0.5;
    final x = back ? mix(1478, 1512, (c - 0.5) * 2) : mix(1512, 1478, c * 2);
    for (var j = 0; j < 2; j++) {
      crew.add(dim(Worker(x + j * 14, back ? 1 : -1, Pose.carry, y: _floor, move: true, ph: x / 3 + j, id: 13 + j, k: 0.5)
        ..sweat = true));
    }
    final next = labels.sample(_busy[(n + 1) % _busy.length], 14, BP.inkDim);
    final box = Rect.fromCenter(center: Offset(x + 7, _floor - 38), width: 26, height: 14);
    canvas
      ..drawRect(box, inkFill(BP.paper))
      ..drawRect(box, inkStroke(BP.lineDim, 1));
    next.paint(canvas, box.center - Offset(next.width / 2, next.height / 2));
    k.drawCrew(crew);
    k.zzz(crew[2].head, t);
    canvas.restore();
  }
}
