import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import 'factory_kit.dart';

/// Slides are panels riding the line: the old panel is lifted a little and
/// rolls out, the next one rolls in behind it, drops into place with a clunk,
/// and gets a quick "QC ✓" stamp. Going forward the line runs right-to-left
/// (the tour walks downstream); going back it runs the other way.
///
/// The widget tree is identical for the whole animation; only transform,
/// opacity and painter parameters change, so slide state survives.
Widget factoryTransition(
  BuildContext context,
  Widget child,
  Animation<double> animation, {
  required bool incoming,
  required bool forward,
}) => _ConveyorTransition(animation: animation, incoming: incoming, forward: forward, child: child);

const _w = 1600.0;
const _h = 900.0;
const _ride = 0.88; // panel scale while riding
const _rise = -40.0; // riding panels clear the ruler's floor band
const _gap = 70.0;

class _ConveyorTransition extends StatelessWidget {
  const _ConveyorTransition({
    required this.animation,
    required this.incoming,
    required this.forward,
    required this.child,
  });

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
        // Both panels share one progress value u: 0 → 1 as the line moves.
        final u = c01(incoming ? animation.value : 1 - animation.value);
        final dir = forward ? -1.0 : 1.0; // direction the panels travel
        final r = eio(seg(u, 0.0, 0.62)); // the ride
        const travel = _w * _ride + _gap;
        double scale, dx, dy, frame;
        if (incoming) {
          final land = seg(u, 0.58, 0.72);
          scale = lerp(_ride, 1, eo(land));
          dx = -dir * (1 - r) * travel;
          dy = _rise * (1 - eo(land)) + 5 * bump(seg(u, 0.72, 0.82));
          frame = 1 - seg(u, 0.6, 0.8);
        } else {
          final lift = eo(seg(u, 0.0, 0.12));
          scale = lerp(1, _ride, lift);
          dx = dir * r * travel;
          dy = _rise * lift;
          frame = lift;
        }
        final done = incoming && u >= 1;
        final m = done
            ? Matrix4.identity()
            : Matrix4(scale, 0, 0, 0, 0, scale, 0, 0, 0, 0, 1, 0, dx, dy, 0, 1);
        return Stack(
          fit: StackFit.expand,
          children: [
            Transform(
              alignment: Alignment.center,
              transform: m,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  IgnorePointer(child: CustomPaint(painter: _PanelBack(frame))),
                  IgnorePointer(ignoring: !incoming, child: child),
                  IgnorePointer(child: CustomPaint(painter: _PanelFrame(frame, incoming ? u : 0))),
                ],
              ),
            ),
            IgnorePointer(
              child: CustomPaint(painter: _Stamp(incoming ? u : 0, dir: dir, dust: incoming)),
            ),
          ],
        );
      },
    );
  }
}

/// The panel's backing plate (only while it rides).
class _PanelBack extends CustomPainter {
  _PanelBack(this.a);

  final double a;

  @override
  void paint(Canvas canvas, Size size) {
    if (a <= 0.01) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = BP.paper.withValues(alpha: 0.92 * a));
  }

  @override
  bool shouldRepaint(_PanelBack old) => old.a != a;
}

/// Outline, corner brackets, lifting lugs and hazard stripes on the panel.
class _PanelFrame extends CustomPainter {
  _PanelFrame(this.a, this.u);

  final double a;
  final double u;

  @override
  void paint(Canvas canvas, Size size) {
    if (a <= 0.01) return;
    final k = FactoryInk(canvas, dim: a);
    final r = (Offset.zero & size).deflate(2);
    canvas.drawRect(r, k.st(BP.line, 3));
    canvas.drawRect(r.deflate(10), k.st(BP.lineDim, 1));
    // Corner brackets.
    const l = 42.0;
    for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      final sx = c.dx < size.width / 2 ? 1.0 : -1.0;
      final sy = c.dy < size.height / 2 ? 1.0 : -1.0;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx + sx * l, c.dy + sy * 4)
          ..lineTo(c.dx + sx * 4, c.dy + sy * 4)
          ..lineTo(c.dx + sx * 4, c.dy + sy * l),
        k.st(BP.amber, 3),
      );
    }
    // Lifting lugs on top.
    for (final x in [size.width * 0.25, size.width * 0.75]) {
      canvas.drawArc(Rect.fromCenter(center: Offset(x, r.top), width: 36, height: 36), math.pi, math.pi, false, k.st(BP.line, 3));
    }
  }

  @override
  bool shouldRepaint(_PanelFrame old) => old.a != a || old.u != u;
}

/// Screen-space effects on arrival: dust from the clunk, the QC stamp.
class _Stamp extends CustomPainter {
  _Stamp(this.u, {required this.dir, required this.dust});

  final double u;
  final double dir;
  final bool dust;

  @override
  void paint(Canvas canvas, Size size) {
    if (u <= 0 || u >= 1) return;
    final k = FactoryInk(canvas);
    // Dust at the panel's feet as it lands.
    final d = seg(u, 0.72, 0.98);
    if (dust && d > 0 && d < 1) {
      for (final (x, s) in [(40.0, -1.0), (_w - 40, 1.0)]) {
        for (var i = 0; i < 3; i++) {
          k.puff(Offset(x + s * (8 + d * (16 + 10 * i)), _h - 96 - i * 7 - d * 10), c01(d + i * 0.08), 3, 12 + 4.0 * i, BP.inkDim);
        }
      }
    }
    // The stamp slams down, holds, fades.
    final slam = seg(u, 0.66, 0.76);
    final fade = 1 - seg(u, 0.93, 1.0);
    if (slam <= 0 || fade <= 0) return;
    final scale = lerp(1.8, 1, eo(slam));
    final a = math.min(eo(slam * 1.5), fade);
    const center = Offset(_w - 150, 94);
    canvas.saveLayer(
      Rect.fromCenter(center: center, width: 420, height: 220),
      Paint()..color = Color.fromRGBO(0, 0, 0, a),
    );
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.14);
    canvas.scale(scale);
    final box = Rect.fromCenter(center: Offset.zero, width: 132, height: 52);
    final ring = RRect.fromRectAndRadius(box, const Radius.circular(8));
    canvas.drawRRect(ring, Paint()..color = BP.paper.withValues(alpha: 0.85));
    canvas.drawRRect(ring, k.st(BP.green, 3));
    canvas.drawRRect(ring.deflate(5), k.st(BP.green.withValues(alpha: 0.6), 1.2));
    final tp = _qc;
    tp.paint(canvas, Offset(-tp.width / 2 - 14, -tp.height / 2));
    // The check.
    final p = Path()
      ..moveTo(26, 0)
      ..lineTo(34, 9)
      ..lineTo(50, -11);
    canvas.drawPath(p, k.st(BP.green, 4));
    canvas.restore();
  }

  /// Laid out once (an 800 ms flash doesn't need a font-change refresh).
  static final TextPainter _qc = TextPainter(
    text: TextSpan(text: 'QC', style: BT.mono(24, color: BP.green, weight: 700)),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  bool shouldRepaint(_Stamp old) => old.u != u;
}
