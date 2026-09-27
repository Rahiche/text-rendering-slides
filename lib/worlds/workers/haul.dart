import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import 'crew.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Transition: one crew hauls the new slide in on ropes while another pushes
// the old one out; the crews ride the seam between the two sheets. The
// widget tree is the same for the whole animation (only offsets change), so
// slides keep their state; the outgoing slide ignores pointers.
// ─────────────────────────────────────────────────────────────────────────────

Widget workersHaul(
  BuildContext context,
  Widget child,
  Animation<double> animation, {
  required bool incoming,
  required bool forward,
}) => _Haul(animation: animation, incoming: incoming, forward: forward, child: child);

class _Haul extends StatelessWidget {
  const _Haul({required this.animation, required this.incoming, required this.forward, required this.child});

  final Animation<double> animation;
  final bool incoming;
  final bool forward;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        // Incoming runs 0→1, outgoing 1→0: both map to the same seam.
        final u = (incoming ? animation.value : 1 - animation.value).clamp(0.0, 1.0);
        final e = easeInOut3(u);
        final w = BP.canvas.width;
        final dx = incoming ? (forward ? 1 : -1) * (1 - e) * w : (forward ? -1 : 1) * e * w;
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(
              child: Transform.translate(
                offset: Offset(dx, 0),
                child: IgnorePointer(ignoring: !incoming, child: child),
              ),
            ),
            IgnorePointer(
              child: CustomPaint(painter: _SeamPainter(u: u, forward: forward, show: incoming && u > 0 && u < 1)),
            ),
          ],
        );
      },
    );
  }
}

class _SeamPainter extends CustomPainter {
  _SeamPainter({required this.u, required this.forward, required this.show});

  final double u;
  final bool forward;
  final bool show;

  static const _floor = 786.0;
  static const _s = 1.7;

  @override
  bool shouldRepaint(_SeamPainter old) => old.u != u || old.show != show || old.forward != forward;

  @override
  void paint(Canvas canvas, Size size) {
    if (!show) return;
    final e = easeInOut3(u);
    final w = size.width;
    final seam = forward ? w * (1 - e) : w * e;
    // Old sheet goes away from the new one: +1 = the old one lies right.
    final away = forward ? -1.0 : 1.0; // direction everything moves
    // The seam: the new sheet's edge, with rope eyes.
    canvas.drawLine(Offset(seam, 0), Offset(seam, size.height), inkStroke(BP.line, 2));
    for (var y = 12.0; y < size.height; y += 24) {
      canvas.drawLine(Offset(seam - 5, y), Offset(seam + 5, y), inkStroke(BP.lineDim, 1));
    }
    final t = u * 0.8;
    final crew = <Worker>[];
    // Pushers: on the new sheet's side, leaning into the old sheet's edge.
    for (var j = 0; j < 2; j++) {
      final x = seam - away * (19 * _s + j * 22 * _s);
      crew.add(Worker(x, away, Pose.push, y: _floor, ph: t * 40 + j, id: 900 + j)
        ..scale = _s
        ..sweat = true);
    }
    // Haulers: out front, ropes tied to the new sheet's edge.
    final eyes = [const Offset(0, 640), const Offset(0, 700)];
    for (var j = 0; j < 3; j++) {
      final x = seam + away * (120 + j * 44) * 1.0;
      final eye = Offset(seam, eyes[j % 2].dy);
      crew.add(Worker(x, -away, Pose.pull, y: _floor, ph: t * 40 + j * 1.3, id: 910 + j, move: true)
        ..scale = _s
        ..rope = eye
        ..sweat = true);
    }
    CrewPainter(canvas, t, flagSplit: 0).drawCrew(crew);
    for (final eye in eyes) {
      canvas.drawCircle(Offset(seam, eye.dy), 4, inkStroke(BP.amber, 1.6));
    }
    // Dust where the sheets scrape the floor.
    for (var i = 0; i < 5; i++) {
      final a = (u * 9 + i / 5) % 1;
      final p = Offset(seam - away * (8 + a * 60), _floor + 2 - a * 10 - i * 2);
      canvas.drawCircle(p, 2 + 6 * a, inkStroke(BP.inkDim, 1, 0.7 * (1 - a)));
    }
  }
}
