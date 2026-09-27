import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/deck.dart';
import '../../deck/theme.dart';
import 'site_kit.dart';

// The crane swaps the slides: it lifts the old sheet off the site (it shrinks
// as it rises, swinging a little) and carries it away; the new sheet arrives
// hanging from the hook, is lowered into place, bounces once and kicks up dust
// on the ground line (the ruler).
//
// The widget tree is identical for the whole animation, only parameters
// change, so the slide's state survives the transition.

Widget constructionTransition(
  BuildContext context,
  Widget child,
  Animation<double> animation, {
  required bool incoming,
  required bool forward,
}) => _CraneSwap(animation: animation, incoming: incoming, forward: forward, child: child);

const _hang = 0.74; // scale while hanging
const _lift = -40.0; // raise while hanging
const _sling = 64.0; // hook height above the sheet

class _Pose {
  const _Pose(this.dx, this.dy, this.scale, this.rot, this.rig, this.hookUp);

  final double dx;
  final double dy;
  final double scale;
  final double rot;

  /// 0..1: how visible the slings / hook / panel frame are.
  final double rig;

  /// Extra hook rise (it comes down to pick up, goes up after release).
  final double hookUp;

  bool get moving => scale < 0.999 || dx.abs() > 0.5 || dy.abs() > 0.5;
}

_Pose _outgoing(double u, double dir) {
  final l = eio(seg01(u, 0.0, 0.24));
  final tr = ei(seg01(u, 0.12, 0.56));
  final s = lerpD(1, _hang, l);
  final dy = _lift * l;
  final dx = -dir * 1560 * tr;
  final rot = dir * 0.035 * math.sin(tr * math.pi) + 0.012 * math.sin(l * math.pi);
  final rig = seg01(u, 0.0, 0.08);
  return _Pose(dx, dy, s, rot, rig, -90 * (1 - eo(seg01(u, 0, 0.1))));
}

_Pose _incoming(double u, double dir) {
  final tr = eo(seg01(u, 0.40, 0.80));
  final lo = seg01(u, 0.78, 0.95);
  final s = lerpD(_hang, 1, eio(lo));
  // Lowered, with a small bounce as it lands.
  final dy = lo < 1 ? _lift * (1 - eio(lo)) : 5 * math.sin(seg01(u, 0.95, 1) * math.pi);
  final dx = dir * 1560 * (1 - tr);
  final rot = -dir * 0.03 * math.sin(tr * math.pi) * (1 - tr);
  final rig = 1 - seg01(u, 0.93, 1.0);
  return _Pose(dx, dy, s, rot, rig, -120 * ei(seg01(u, 0.93, 1.0)));
}

class _CraneSwap extends StatelessWidget {
  const _CraneSwap({required this.animation, required this.incoming, required this.forward, required this.child});

  final Animation<double> animation;
  final bool incoming;
  final bool forward;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: RepaintBoundary(child: child),
      builder: (context, child) {
        final u = (incoming ? animation.value : 1 - animation.value).clamp(0.0, 1.0);
        final dir = forward ? 1.0 : -1.0;
        final pose = incoming ? _incoming(u, dir) : _outgoing(u, dir);
        final settled = incoming && u >= 1;
        final m = _matrix(pose);
        return Stack(
          fit: StackFit.expand,
          children: [
            Transform(
              transform: m,
              child: CustomPaint(
                painter: _SheetPainter(active: !settled && pose.moving, frame: pose.rig),
                child: IgnorePointer(ignoring: !incoming, child: child),
              ),
            ),
            IgnorePointer(
              child: CustomPaint(painter: _RigPainter(pose: settled ? null : pose)),
            ),
            IgnorePointer(child: _Dust(fire: incoming && u >= 0.95)),
          ],
        );
      },
    );
  }
}

Offset _hookOf(_Pose p) {
  const w = 1600.0;
  const h = 900.0;
  final cx = w / 2 + p.dx;
  final top = h / 2 + p.dy - h / 2 * p.scale;
  return Offset(cx, top - _sling);
}

Matrix4 _matrix(_Pose p) {
  if (!p.moving && p.rot == 0) return Matrix4.identity();
  final hook = _hookOf(p);
  return Matrix4.identity()
    ..translateByDouble(hook.dx, hook.dy, 0, 1)
    ..rotateZ(p.rot)
    ..translateByDouble(-hook.dx, -hook.dy, 0, 1)
    ..translateByDouble(800 + p.dx, 450 + p.dy, 0, 1)
    ..scaleByDouble(p.scale, p.scale, 1, 1)
    ..translateByDouble(-800, -450, 0, 1);
}

/// Behind a moving sheet: the blueprint paper, so it reads as a panel.
class _SheetPainter extends CustomPainter {
  _SheetPainter({required this.active, required this.frame});

  final bool active;
  final double frame;

  @override
  void paint(Canvas canvas, Size size) {
    if (!active) return;
    final r = Offset.zero & size;
    canvas.drawRect(r, fillP(BP.paper));
    GridPaperPainter(scale: 1, origin: Offset.zero).paint(canvas, size);
    final a = frame.clamp(0.0, 1.0);
    canvas.drawRect(r, strokeP(BP.line.withValues(alpha: a), 3));
    final t = strokeP(BP.amber.withValues(alpha: a), 4);
    const l = 40.0;
    for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      final dx = c.dx == 0 ? l : -l;
      final dy = c.dy == 0 ? l : -l;
      canvas.drawLine(c, c + Offset(dx, 0), t);
      canvas.drawLine(c, c + Offset(0, dy), t);
    }
    // Lifting lugs on the top edge.
    for (final x in [420.0, 1180.0]) {
      canvas.drawCircle(Offset(x, 10), 9, fillP(BP.paper));
      canvas.drawCircle(Offset(x, 10), 9, strokeP(BP.amber.withValues(alpha: a), 3));
    }
  }

  @override
  bool hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_SheetPainter old) => old.active != active || old.frame != frame;
}

/// Cable, hook and slings above the sheet.
class _RigPainter extends CustomPainter {
  _RigPainter({required this.pose});

  final _Pose? pose;

  @override
  void paint(Canvas canvas, Size size) {
    final p = pose;
    if (p == null || p.rig <= 0 || !p.moving) return;
    final a = p.rig;
    final hook = _hookOf(p);
    final h = hook + Offset(0, p.hookUp);
    // Slings go to the lugs on the (rotated) sheet.
    Offset lug(double x) {
      final local = Offset(800 + (x - 800) * p.scale + p.dx, 450 + (10 - 450) * p.scale + p.dy);
      final d = local - hook;
      final c = math.cos(p.rot);
      final s = math.sin(p.rot);
      return hook + Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
    }

    final cable = strokeP(BP.inkDim.withValues(alpha: a), 1.4);
    canvas.drawLine(Offset(h.dx - 3, -40), Offset(h.dx - 3, h.dy - 12), cable);
    canvas.drawLine(Offset(h.dx + 3, -40), Offset(h.dx + 3, h.dy - 12), cable);
    if (p.hookUp > -20) {
      final sl = strokeP(BP.inkDim.withValues(alpha: a), 1.2);
      canvas.drawLine(h + const Offset(0, 5), lug(420), sl);
      canvas.drawLine(h + const Offset(0, 5), lug(1180), sl);
    }
    final block = Rect.fromLTRB(h.dx - 9, h.dy - 15, h.dx + 9, h.dy - 2);
    canvas.drawRect(block, fillP(BP.paper));
    canvas.drawRect(block, strokeP(BP.amber.withValues(alpha: a), 1.6));
    final hk = Path()
      ..moveTo(h.dx, h.dy - 2)
      ..lineTo(h.dx, h.dy + 4)
      ..arcTo(Rect.fromCircle(center: Offset(h.dx - 4, h.dy + 4), radius: 4), 0, math.pi * 0.9, false);
    canvas.drawPath(hk, strokeP(BP.amber.withValues(alpha: a), 2));
  }

  @override
  bool shouldRepaint(_RigPainter old) => true;
}

/// Dust kicked up along the ground line when the sheet lands.
class _Dust extends StatefulWidget {
  const _Dust({required this.fire});

  final bool fire;

  @override
  State<_Dust> createState() => _DustState();
}

class _DustState extends State<_Dust> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));

  @override
  void initState() {
    super.initState();
    if (widget.fire) _c.forward();
  }

  @override
  void didUpdateWidget(_Dust old) {
    super.didUpdateWidget(old);
    if (widget.fire && !old.fire) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _DustPainter(_c));
}

class _DustPainter extends CustomPainter {
  _DustPainter(this.anim) : super(repaint: anim);

  final Animation<double> anim;

  @override
  void paint(Canvas canvas, Size size) {
    final f = anim.value;
    if (f <= 0 || f >= 1) return;
    const y = 834.0;
    final p = strokeP(BP.inkDim.withValues(alpha: 0.55 * (1 - f)), 1.1);
    for (var i = 0; i < 14; i++) {
      final x = 130 + i * 102.0 + (hash1(i + 0.3) - 0.5) * 40;
      final r = hash1(i + 7.1);
      final side = i.isEven ? -1.0 : 1.0;
      final o = Offset(x + side * 26 * eo(f) * (0.5 + r), y - 6 - 20 * eo(f) * (0.4 + r));
      canvas.drawCircle(o, 3 + 10 * eo(f) * (0.6 + 0.5 * r), p);
    }
  }

  @override
  bool shouldRepaint(_DustPainter old) => false;
}
