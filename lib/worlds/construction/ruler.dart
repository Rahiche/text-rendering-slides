import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../deck/deck.dart';
import '../../deck/theme.dart';
import 'site_kit.dart';

// The site's ground level: a surveyor's measuring tape pulled out along the
// bottom of the deck, one graduation per slide. Section starts are site-board
// signs, a crane hook hangs over the current slide (and swings when it moves),
// clicking the tape jumps. The band is 1600 × 110 (canvas y 790–900).

const _x0 = 150.0; // tape start (leaves the case)
const _x1 = 1452.0; // tape end hook
const _ground = 46.0; // tape top = ground line
const _tapeH = 12.0;

class ConstructionRuler extends StatefulWidget {
  const ConstructionRuler({super.key, required this.controller});

  final DeckController controller;

  @override
  State<ConstructionRuler> createState() => _ConstructionRulerState();
}

class _Hook {
  double x = double.nan;
  double v = 0;
  double theta = 0;
  double omega = 0;
}

class _ConstructionRulerState extends State<ConstructionRuler> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _hook = _Hook();
  final _labels = SiteLabels();
  final _repaint = ValueNotifier<int>(0);
  double _target = 0;
  Duration? _last;
  int? _hover;

  double _xOf(int i, int n) => _x0 + 14 + (n <= 1 ? 0 : i * (_x1 - _x0 - 28) / (n - 1));

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.systemFonts.addListener(_labels.clear);
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_labels.clear);
    _ticker.dispose();
    _repaint.dispose();
    _labels.clear();
    super.dispose();
  }

  void _tick(Duration d) {
    final dt = _last == null ? 1 / 60 : math.min(0.05, (d - _last!).inMicroseconds / 1e6);
    _last = d;
    final h = _hook;
    // Critically damped trolley, pendulum hook that lags behind it.
    const k = 70.0;
    final a = k * (_target - h.x) - 2 * math.sqrt(k) * h.v;
    h.v += a * dt;
    h.x += h.v * dt;
    final alpha = -40 * h.theta - 3.2 * h.omega - a * 0.0022;
    h.omega += alpha * dt;
    h.theta = (h.theta + h.omega * dt).clamp(-0.6, 0.6);
    _repaint.value++;
    if ((h.x - _target).abs() < 0.2 && h.v.abs() < 1 && h.theta.abs() < 0.002 && h.omega.abs() < 0.01) {
      h
        ..x = _target
        ..v = 0
        ..theta = 0
        ..omega = 0;
      _ticker.stop();
      _last = null;
    }
  }

  void _retarget() {
    final c = widget.controller;
    final t = _xOf(c.index, c.slides.length);
    if (_hook.x.isNaN) {
      _hook.x = t;
      _target = t;
      return;
    }
    if (t != _target) {
      _target = t;
      if (!_ticker.isActive) _ticker.start();
    }
  }

  int? _indexAt(Offset p) {
    final n = widget.controller.slides.length;
    if (p.dx < _x0 - 6 || p.dx > _x1 + 6) return null;
    final f = (p.dx - _x0 - 14) / (_x1 - _x0 - 28);
    return (f * (n - 1)).round().clamp(0, n - 1);
  }

  void _setHover(int? i) {
    if (i == _hover) return;
    setState(() => _hover = i);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    _retarget();
    return RepaintBoundary(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _RulerPainter(
                  controller: c,
                  hook: _hook,
                  hover: _hover,
                  labels: _labels,
                  repaint: _repaint,
                  xOf: _xOf,
                ),
              ),
            ),
          ),
          // The tape: hover shows the slide's title, click jumps.
          Positioned(
            left: _x0 - 10,
            width: _x1 - _x0 + 20,
            top: 14,
            height: 64,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onHover: (e) => _setHover(_indexAt(e.localPosition + const Offset(_x0 - 10, 14))),
              onExit: (_) => _setHover(null),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final i = _indexAt(d.localPosition + const Offset(_x0 - 10, 14));
                  if (i != null) c.goTo(i);
                },
              ),
            ),
          ),
          // Counter: opens the overview.
          Positioned(
            right: 36,
            top: 50,
            child: GestureDetector(
              onTap: c.toggleOverview,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Text(
                  '${(c.index + 1).toString().padLeft(2, '0')} / ${c.slides.length.toString().padLeft(2, '0')}',
                  style: BT.mono(14, color: BP.line),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.controller,
    required this.hook,
    required this.hover,
    required this.labels,
    required this.xOf,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final DeckController controller;
  final _Hook hook;
  final int? hover;
  final SiteLabels labels;
  final double Function(int i, int n) xOf;

  static bool _real(String s) => s != 'intro' && s != 'outro';

  @override
  void paint(Canvas c, Size size) {
    final slides = controller.slides;
    final n = slides.length;
    final idx = controller.index;
    final cur = xOf(idx, n);

    // Ground line either side of the tape.
    c.drawLine(const Offset(40, _ground), const Offset(_x0 - 50, _ground), strokeP(BP.lineDim, 1.2));
    c.drawLine(const Offset(_x1 + 10, _ground), const Offset(1560, _ground), strokeP(BP.lineDim, 1.2));

    // Tape body: the part we have measured so far is brighter.
    const tape = Rect.fromLTRB(_x0, _ground, _x1, _ground + _tapeH);
    c.drawRect(tape, fillP(BP.panel));
    c.drawRect(Rect.fromLTRB(_x0, _ground, cur, _ground + _tapeH), fillP(BP.line.withValues(alpha: 0.08)));
    c.drawRect(tape, strokeP(BP.lineDim, 1));
    c.drawLine(const Offset(_x0, _ground + _tapeH), Offset(cur, _ground + _tapeH), strokeP(BP.amber, 2.2));

    // Graduations: one per slide, three fine marks between.
    final fine = Path();
    final done = Path();
    final todo = Path();
    final majors = Path();
    for (var i = 0; i < n; i++) {
      final x = xOf(i, n);
      final major = i == 0 || slides[i].section != slides[i - 1].section;
      (major ? majors : (i <= idx ? done : todo))
        ..moveTo(x, _ground)
        ..lineTo(x, _ground + (major ? 11 : 7));
      if (i < n - 1) {
        final nx = xOf(i + 1, n);
        for (var q = 1; q < 4; q++) {
          final fx = x + (nx - x) * q / 4;
          fine
            ..moveTo(fx, _ground)
            ..lineTo(fx, _ground + (q == 2 ? 4.5 : 3));
        }
      }
      if ((i + 1) % 5 == 0) {
        labels.draw(c, '${i + 1}', Offset(x, _ground + _tapeH + 2), size: 9, color: BP.inkFaint, ax: 0.5);
      }
    }
    c.drawPath(fine, strokeP(BP.lineFaint, 1));
    c.drawPath(todo, strokeP(BP.lineDim, 1.2));
    c.drawPath(done, strokeP(BP.line, 1.2));
    c.drawPath(majors, strokeP(BP.ink, 1.4));

    // Tape case at the start, the end hook at the far end.
    final box = RRect.fromRectAndRadius(const Rect.fromLTRB(98, 30, 146, 64), const Radius.circular(9));
    c.drawRRect(box, fillP(BP.paper));
    c.drawRRect(box, strokeP(BP.line, 1.3));
    c.drawCircle(const Offset(122, 47), 9, strokeP(BP.lineDim, 1.2));
    c.drawCircle(const Offset(122, 47), 2, fillP(BP.line));
    c.drawLine(const Offset(146, _ground + 1), const Offset(_x0, _ground + 1), strokeP(BP.lineDim, 1));
    c.drawLine(const Offset(_x1, _ground - 5), const Offset(_x1, _ground + _tapeH + 3), strokeP(BP.line, 2));
    c.drawLine(
      const Offset(_x1, _ground + _tapeH + 3),
      const Offset(_x1 - 5, _ground + _tapeH + 3),
      strokeP(BP.line, 2),
    );

    // Current section name, by the case.
    labels.draw(c, controller.current.section, const Offset(98, 26), size: 12, color: BP.inkDim, ay: 1);

    // Site-board signs at section starts: "01" … "05", a flag at the end.
    var k = 0;
    for (var i = 1; i < n; i++) {
      if (slides[i].section == slides[i - 1].section) continue;
      final x = xOf(i, n) - 1.5;
      final sec = slides[i].section;
      final here = controller.current.section == sec;
      final passed = idx >= i;
      final col = here ? BP.amber : (passed ? BP.line : BP.lineDim);
      c.drawLine(Offset(x, _ground), Offset(x, 14), strokeP(col, 1.2));
      if (_real(sec)) {
        k++;
        final r = Rect.fromLTRB(x - 25, 14, x, 28);
        c.drawRect(r, fillP(BP.paper));
        c.drawRect(r, strokeP(col, 1.1));
        labels.draw(
          c,
          '0$k',
          r.center,
          size: 10,
          color: here ? BP.amber : (passed ? BP.ink : BP.inkFaint),
          ax: 0.5,
          ay: 0.5,
        );
      } else {
        // Finish flag.
        final f = Path()
          ..moveTo(x, 14)
          ..lineTo(x - 18, 18)
          ..lineTo(x, 23)
          ..close();
        c.drawPath(f, fillP(col.withValues(alpha: 0.8)));
      }
    }

    // Steps of the current slide, under the tape.
    final steps = controller.current.steps;
    if (steps > 1) {
      final w = steps * 8.0;
      for (var s = 0; s < steps; s++) {
        c.drawRect(
          Rect.fromLTWH(cur - w / 2 + s * 8 + 1.5, _ground + _tapeH + 16, 5, 5),
          fillP(s <= controller.step ? BP.amber : BP.lineFaint),
        );
      }
    }

    // The crane hook over the current slide.
    final hx = hook.x.isNaN ? cur : hook.x;
    const top = -18.0;
    const len = 44.0;
    final tip = Offset(hx + math.sin(hook.theta) * len, top + math.cos(hook.theta) * len);
    final cable = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [BP.inkDim.withValues(alpha: 0), BP.inkDim],
      ).createShader(Rect.fromLTRB(hx - 20, top, hx + 20, tip.dy))
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    c.drawLine(Offset(hx - 2, top), tip + const Offset(-2, -9), cable);
    c.drawLine(Offset(hx + 2, top), tip + const Offset(2, -9), cable);
    c.save();
    c.translate(tip.dx, tip.dy);
    c.rotate(-hook.theta);
    final block = Rect.fromLTRB(-5, -10, 5, -2);
    c.drawRect(block, fillP(BP.paper));
    c.drawRect(block, strokeP(BP.amber, 1.3));
    final h = Path()
      ..moveTo(0, -2)
      ..lineTo(0, 3)
      ..arcTo(Rect.fromCircle(center: const Offset(-3, 3), radius: 3), 0, math.pi * 0.9, false);
    c.drawPath(h, strokeP(BP.amber, 1.5));
    c.restore();
    // Plumb line from the hook to the graduation.
    c.drawLine(Offset(tip.dx, tip.dy + 7), Offset(cur, _ground - 1), strokeP(BP.amber.withValues(alpha: 0.35), 1));
    c.drawLine(Offset(cur, _ground - 1), Offset(cur, _ground + _tapeH + 1), strokeP(BP.amber, 2));

    // Hovered graduation: its title in a tag above.
    final hv = hover;
    if (hv != null && hv < n) {
      final x = xOf(hv, n);
      c.drawLine(Offset(x, _ground - 6), Offset(x, _ground + _tapeH), strokeP(BP.amber, 2.5));
      final p = labels.get(slides[hv].title, 13, BP.ink);
      final w = p.width + 20;
      final left = (x - w / 2).clamp(20.0, 1580 - w);
      final r = Rect.fromLTWH(left, -22, w, p.height + 8);
      c.drawRect(r, fillP(BP.panel));
      c.drawRect(r, strokeP(BP.line, 1));
      p.paint(c, r.topLeft + const Offset(10, 4));
      c.drawLine(Offset(x, r.bottom), Offset(x, _ground - 6), strokeP(BP.line, 1));
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) => true;
}
