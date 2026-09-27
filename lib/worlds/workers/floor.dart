import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../deck/deck.dart';
import '../../deck/theme.dart';
import 'crew.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The ruler: the crew roster marching along the floor. One tick per slide;
// every slide we have passed has its workers standing on it, more of them
// the deeper the section (the crew grows as the talk goes on). The foreman
// carries the flag to the current slide. Click a tick to jump; hover shows
// its title; click the counter for the overview.
// ─────────────────────────────────────────────────────────────────────────────

const _floorY = 68.0; // local to the 110 px band
const _x0 = 184.0;
const _x1 = 1432.0;

double _xOf(int i, int n) => _x0 + (n <= 1 ? 0 : i * (_x1 - _x0) / (n - 1));

/// Workers per tick, by section: the crew grows as the talk goes deeper.
int _perTick(String section) => switch (section) {
  'intro' || 'basics' => 1,
  'scripts' || 'others' => 2,
  _ => 3,
};

class WorkersFloor extends StatefulWidget {
  const WorkersFloor({super.key, required this.controller});

  final DeckController controller;

  @override
  State<WorkersFloor> createState() => _WorkersFloorState();
}

class _WorkersFloorState extends State<WorkersFloor> with SingleTickerProviderStateMixin {
  final _hover = ValueNotifier<int?>(null);
  final _anim = _ForemanState();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  final _labels = LabelCache();

  @override
  void initState() {
    super.initState();
    _anim.x = _xOf(widget.controller.index, widget.controller.slides.length);
    _ticker = createTicker(_tick)..start();
    PaintingBinding.instance.systemFonts.addListener(_labels.clear);
  }

  void _tick(Duration e) {
    var dt = (e - _last).inMicroseconds / 1e6;
    _last = e;
    if (dt < 0 || dt > 0.1) dt = 1 / 60;
    final c = widget.controller;
    _anim.step(dt, _xOf(c.index, c.slides.length));
  }

  @override
  void dispose() {
    _ticker.dispose();
    PaintingBinding.instance.systemFonts.removeListener(_labels.clear);
    _hover.dispose();
    _anim.dispose();
    _labels.clear();
    super.dispose();
  }

  int? _hit(Offset p) {
    final n = widget.controller.slides.length;
    if (p.dx < _x0 - 20 || p.dx > _x1 + 20 || p.dy < 20) return null;
    final i = ((p.dx - _x0) / ((_x1 - _x0) / math.max(1, n - 1))).round().clamp(0, n - 1);
    return (p.dx - _xOf(i, n)).abs() < 20 ? i : null;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            onHover: (e) => _hover.value = _hit(e.localPosition),
            onExit: (_) => _hover.value = null,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (d) {
                final i = _hit(d.localPosition);
                if (i != null) c.goTo(i);
              },
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _RosterPainter(
                    slides: c.slides,
                    index: c.index,
                    step: c.step,
                    hover: _hover,
                    labels: _labels,
                  ),
                  foregroundPainter: _ForemanPainter(_anim, c.slides.length, c.index),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
        // Counter: "07 / 38", with the section; click for the overview.
        Positioned(
          right: 64,
          top: 76,
          child: GestureDetector(
            onTap: c.toggleOverview,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Row(
                children: [
                  Text(c.current.section, style: BT.mono(14, color: BP.inkDim)),
                  const SizedBox(width: 12),
                  Text(
                    '${(c.index + 1).toString().padLeft(2, '0')} / ${c.slides.length.toString().padLeft(2, '0')}',
                    style: BT.mono(14, color: BP.line),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The foreman's walk: eases toward the current tick.
class _ForemanState extends ChangeNotifier {
  double x = 0;
  double v = 0;
  double t = 0;
  double target = 0;

  void step(double dt, double to) {
    t += dt;
    target = to;
    final d = to - x;
    if (d.abs() < 0.5 && v.abs() < 5) {
      x = to;
      v = 0;
    } else {
      // Walk (or run, if far) toward the target.
      final speed = math.min(900.0, 140 + d.abs() * 3);
      v = d.sign * speed;
      final nx = x + v * dt;
      x = (d > 0 ? nx > to : nx < to) ? to : nx;
    }
    notifyListeners();
  }
}

class _RosterPainter extends CustomPainter {
  _RosterPainter({
    required this.slides,
    required this.index,
    required this.step,
    required this.hover,
    required this.labels,
  }) : super(repaint: hover);

  final List<SlideDef> slides;
  final int index;
  final int step;
  final ValueNotifier<int?> hover;
  final LabelCache labels;

  @override
  bool shouldRepaint(_RosterPainter old) =>
      old.index != index || old.step != step || old.slides.length != slides.length;

  @override
  void paint(Canvas canvas, Size size) {
    final n = slides.length;
    final k = CrewPainter(canvas, 0);
    // The floor.
    canvas.drawLine(const Offset(_x0 - 30, _floorY), const Offset(_x1 + 30, _floorY), inkStroke(BP.lineDim, 1.2));
    final crew = <Worker>[];
    var sec = 0;
    for (var i = 0; i < n; i++) {
      final x = _xOf(i, n);
      final major = i == 0 || slides[i].section != slides[i - 1].section;
      final passed = i <= index;
      final h = hover.value == i;
      canvas.drawLine(
        Offset(x, _floorY),
        Offset(x, _floorY + (major ? 12 : 6)),
        inkStroke(h ? BP.amber : (passed ? BP.line : BP.lineFaint), h ? 2.4 : 1.2),
      );
      if (major && slides[i].section != 'intro' && slides[i].section != 'outro') {
        sec++;
        final l = labels.mono(sec.toString().padLeft(2, '0'), 11, i <= index ? BP.inkDim : BP.inkFaint);
        l.paint(canvas, Offset(x - l.width / 2, _floorY + 15));
      }
      if (i < index) {
        // The roster: this slide's crew, standing under its tick.
        final m = _perTick(slides[i].section);
        for (var j = 0; j < m; j++) {
          final wx = x + (j - (m - 1) / 2) * 8.5;
          final pose = (i * 7 + j * 3) % 11 == 0 ? Pose.sit : Pose.stand;
          crew.add(Worker(wx, (i + j).isEven ? 1 : -1, pose, y: _floorY, id: i * 4 + j)
            ..scale = 0.56
            ..ink = h ? BP.ink : BP.inkDim
            ..hat = BP.amber.withValues(alpha: h ? 1 : 0.65));
        }
      } else if (i > index) {
        canvas.drawCircle(Offset(x, _floorY - 3), 1.6, inkFill(BP.lineFaint));
      }
    }
    k.drawCrew(crew);
    // Steps of the current slide: little blocks next to the flag.
    final cur = slides[index];
    if (cur.steps > 1) {
      final x = _xOf(index, n);
      for (var s = 0; s < cur.steps; s++) {
        final r = Rect.fromLTWH(x - cur.steps * 4 + s * 8, _floorY + 30, 5, 5);
        canvas.drawRect(r, inkFill(s <= step ? BP.amber : BP.lineFaint));
      }
    }
    // Hover: the slide's title.
    final hv = hover.value;
    if (hv != null && hv < n) {
      final t = labels.mono(slides[hv].title, 13, BP.ink);
      final x = _xOf(hv, n);
      final r = Rect.fromCenter(center: Offset(x, 8), width: t.width + 20, height: t.height + 8);
      canvas
        ..drawRect(r, inkFill(BP.panel))
        ..drawRect(r, inkStroke(BP.amber, 1));
      t.paint(canvas, Offset(r.left + 10, r.top + 4));
    }
  }
}

class _ForemanPainter extends CustomPainter {
  _ForemanPainter(this.a, this.n, this.index) : super(repaint: a);

  final _ForemanState a;
  final int n;
  final int index;

  @override
  bool shouldRepaint(_ForemanPainter old) => old.a != a || old.n != n || old.index != index;

  @override
  void paint(Canvas canvas, Size size) {
    final moving = a.v.abs() > 1;
    final f = moving ? a.v.sign : 1.0;
    final g = Worker(a.x + (moving ? 0 : -6), f, moving ? (a.v.abs() > 400 ? Pose.run : Pose.walk) : Pose.pole,
        y: _floorY, ph: a.x / 4, move: moving, id: 999)
      ..scale = 0.9
      ..plant = Offset(a.x, _floorY);
    CrewPainter(canvas, a.t).drawCrew([g]);
    // The flag: on his shoulder while walking, planted at the tick when there.
    const s = 0.9;
    final hand = Offset(g.x + (g.hr.dx - g.x) * s, g.y + (g.hr.dy - g.y) * s);
    final base = moving ? hand + Offset(-f * 2, 4) : Offset(a.x, _floorY);
    final top = moving ? base + Offset(-f * 12, -40) : Offset(a.x, _floorY - 52);
    canvas.drawLine(base, top, inkStroke(BP.inkDim, 1.6));
    final wv = math.sin(a.t * 4) * 2;
    final dir = moving ? -f : 1.0;
    final flag = Path()
      ..moveTo(top.dx, top.dy)
      ..quadraticBezierTo(top.dx + dir * 9, top.dy + 2 + wv, top.dx + dir * 18, top.dy + 5 + wv)
      ..lineTo(top.dx, top.dy + 12)
      ..close();
    canvas
      ..drawPath(flag, inkFill(BP.amber))
      ..drawPath(flag, inkStroke(BP.amber, 1));
  }
}
