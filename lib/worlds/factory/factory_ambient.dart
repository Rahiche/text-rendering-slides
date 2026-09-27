import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import 'factory_kit.dart';

/// Scenery behind every content slide, kept to the margins: pipes along the
/// ceiling and down both edges, two gauges, a valve that sometimes vents
/// steam, and two workers on the floor band (a sweeper on the left, a
/// valve-man with a coffee on the right). Faint and slow; it runs on the
/// deck-wide clock so it carries on seamlessly from slide to slide.
class FactoryAmbient extends StatelessWidget {
  const FactoryAmbient({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: SceneTicker(
        builder: (context, clock) => CustomPaint(size: Size.infinite, painter: _AmbientPainter(clock)),
      ),
    ),
  );
}

const _floor = 876.0; // the ruler's floor line
const _lx = 47.0; // left pipe centre
const _rx = 1553.0; // right pipe centre
const _topY = 9.0; // ceiling pipe centre
const _gaugeL = Offset(_lx, 372);
const _gaugeR = Offset(_rx, 300);
const _valveR = Offset(_rx, 836);
const _valveL = Offset(_lx, 640);
const _vent = Offset(1506, _topY - 3);

ui.Picture? _static;

ui.Picture _scenery() => _static ??= () {
  final rec = ui.PictureRecorder();
  final k = FactoryInk(Canvas(rec));
  final c = k.c;
  final pipe = k.st(BP.lineFaint, 1.2);
  // Ceiling pipe with elbows down both edges.
  const r = 3.0;
  final outer = Path()
    ..moveTo(_lx - r, _floor)
    ..lineTo(_lx - r, _topY + 14)
    ..arcToPoint(const Offset(_lx + 14, _topY - r), radius: const Radius.circular(17))
    ..lineTo(_rx - 14, _topY - r)
    ..arcToPoint(const Offset(_rx + r, _topY + 14), radius: const Radius.circular(17))
    ..lineTo(_rx + r, _floor);
  final inner = Path()
    ..moveTo(_lx + r, _floor)
    ..lineTo(_lx + r, _topY + 14)
    ..arcToPoint(const Offset(_lx + 14, _topY + r), radius: const Radius.circular(11))
    ..lineTo(_rx - 14, _topY + r)
    ..arcToPoint(const Offset(_rx - r, _topY + 14), radius: const Radius.circular(11))
    ..lineTo(_rx - r, _floor);
  c.drawPath(outer, pipe);
  c.drawPath(inner, pipe);
  // Flanges and ceiling hangers.
  final fl = k.st(BP.lineFaint, 1.4);
  for (var x = 200.0; x < 1450; x += 250) {
    c.drawRect(Rect.fromCenter(center: Offset(x, _topY), width: 5, height: 11), fl);
  }
  for (var x = 325.0; x < 1450; x += 500) {
    c.drawLine(Offset(x, 0), Offset(x, _topY - r), k.st(BP.lineFaint, 1));
    c.drawArc(Rect.fromCircle(center: Offset(x, _topY), radius: r + 2), math.pi, math.pi, false, k.st(BP.lineFaint, 1));
  }
  for (final x in [_lx, _rx]) {
    for (var y = 200.0; y < 800; y += 220) {
      c.drawRect(Rect.fromCenter(center: Offset(x, y), width: 11, height: 5), fl);
    }
    // Wall brackets.
    for (var y = 110.0; y < 800; y += 220) {
      c.drawLine(Offset(x + (x < 800 ? -r : r), y), Offset(x < 800 ? 24 : 1576, y), k.st(BP.lineFaint, 1));
    }
  }
  // A thin conduit along the ceiling on the right, with a junction box.
  c.drawLine(const Offset(1150, 24), const Offset(_rx - 12, 24), k.st(BP.lineFaint, 1));
  c.drawLine(const Offset(_rx - 12, 24), const Offset(_rx - 12, 60), k.st(BP.lineFaint, 1));
  c.drawRect(const Rect.fromLTRB(1143, 19, 1153, 29), k.st(BP.lineFaint, 1));
  // Vent stub on the ceiling pipe.
  c.drawRect(Rect.fromCenter(center: _vent + const Offset(0, -2), width: 8, height: 6), k.st(BP.lineFaint, 1.2));
  // Gauge dials (needles are drawn live).
  for (final g in [_gaugeL, _gaugeR]) {
    c.drawCircle(g, 12, k.fl(BP.paper));
    c.drawCircle(g, 12, k.st(BP.lineDim, 1.1));
    for (var i = 0; i <= 6; i++) {
      final a = math.pi * (0.8 + i * 0.233);
      final d = Offset(math.cos(a), math.sin(a));
      c.drawLine(g + d * 8.5, g + d * 10.5, k.st(BP.lineFaint, 1));
    }
  }
  // The right worker's coffee crate.
  k.box(const Rect.fromLTRB(1456, _floor - 13, 1476, _floor), col: BP.lineFaint, w: 1);
  return rec.endRecording();
}();

class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.clock) : super(repaint: clock);

  final SceneClock clock;

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.global;
    final k = FactoryInk(canvas, dim: 0.75);
    canvas.drawPicture(_scenery());

    // Gauge needles: a slow drift and a little flutter.
    for (final (g, ph) in [(_gaugeL, 0.0), (_gaugeR, 2.1)]) {
      final v = 0.55 + 0.16 * math.sin(t * 0.37 + ph) + 0.03 * math.sin(t * 7.3 + ph);
      final a = math.pi * (0.8 + 1.4 * v);
      canvas.drawLine(g, g + Offset(math.cos(a), math.sin(a)) * 8, k.st(BP.amber.withValues(alpha: 0.55), 1.2));
    }

    // A pressure pulse runs along the ceiling pipe now and then.
    const pulseEvery = 13.0;
    final pp = (t % pulseEvery) / 3.2;
    if (pp < 1) {
      final x = lerp(_lx + 20, _rx - 20, eio(pp));
      canvas.drawCircle(Offset(x, _topY), 2.2, k.fl(BP.line.withValues(alpha: 0.35 * bump(pp))));
    }

    // The ceiling vent puffs a little steam every so often.
    const ventEvery = 17.0;
    final vn = (t / ventEvery).floor();
    final vt = t - vn * ventEvery;
    if (vt < 5) {
      k.steam(_vent + const Offset(0, -5), vt, per: 0.4, life: 2.2, rise: 26, r: 7, col: BP.inkFaint.withValues(alpha: 0.6), seed: vn, drift: -14);
    }

    _sweeper(k, t);
    _valveMan(k, t);
  }

  /// Left: sweeps the floor between x 76 and 186, rests on the broom.
  void _sweeper(FactoryInk k, double t) {
    const per = 22.0;
    final n = (t / per).floor();
    final u = t - n * per;
    const a = 80.0, b = 186.0;
    final f = Pose();
    var x = a;
    var dir = 1;
    var sweeping = false;
    var rest = false;
    if (u < 8) {
      x = lerp(a, b, u / 8);
      sweeping = true;
    } else if (u < 11.5) {
      x = b;
      rest = true;
    } else if (u < 19.5) {
      x = lerp(b, a, (u - 11.5) / 8);
      dir = -1;
      sweeping = true;
    } else {
      x = a;
      dir = -1;
      f.watch();
    }
    final sw = math.sin(t * 5.5);
    if (sweeping) {
      f.walk(u * 2.6, amp: 0.22, arms: false);
      f
        ..lean = 0.25
        ..upA = 0.75 + 0.18 * sw
        ..foA = 0.95 + 0.2 * sw
        ..upB = 0.55 + 0.15 * sw
        ..foB = 0.8 + 0.15 * sw;
    } else if (rest) {
      f
        ..upA = 0.55
        ..foA = 1.9
        ..upB = 0.3
        ..foB = 1.2;
      if (rnd(n, 7) < 0.5 && u > 9.5) f.wipe(t);
    }
    final g = k.worker(Offset(x, _floor), 24, dir, f);
    if (sweeping) {
      k.broom(g.handB, g.elbowB, _floor, dir * (8 + 5 * sw));
      // Dust.
      final q = (t * 1.3) % 1;
      k.puff(Offset(x + dir * (16 + 4 * sw), _floor - 3 - 6 * q), q, 1.5, 4, BP.inkFaint);
    } else if (rest) {
      k.broom(g.handA, g.elbowA, _floor, dir * 5.0);
      if (rnd(n, 7) < 0.5 && u > 9.5) k.sweat(g.head, u, dir);
    } else {
      k.broom(g.handA, g.elbowA, _floor, dir * 4.0);
    }
  }

  /// Right: coffee on a crate, then off to turn the valve (steam), and back.
  void _valveMan(FactoryInk k, double t) {
    const per = 28.0;
    final n = (t / per).floor();
    final u = t - n * per;
    const seat = 1466.0, valve = 1532.0;
    final f = Pose();
    double x;
    var dir = 1;
    var turning = 0.0;
    var sitting = false;
    if (u < 12) {
      x = seat;
      sitting = true;
    } else if (u < 14.5) {
      x = lerp(seat, valve, eio((u - 12) / 2.5));
      f.walk((x - seat) / 3.5, amp: 0.36);
    } else if (u < 18) {
      x = valve;
      turning = (u - 14.5) / 3.5;
    } else if (u < 20.5) {
      x = lerp(valve, seat, eio((u - 18) / 2.5));
      dir = -1;
      f.walk((valve - x) / 3.5, amp: 0.36);
    } else {
      x = seat;
      sitting = true;
    }
    Limbs g;
    if (sitting) {
      f.sit(24, 13);
      final sip = bump(seg((u % 4) / 4, 0.2, 0.6));
      final ep = u > 20.5 ? u - 20.5 : u;
      if (rnd(n, 3) < 0.5 && ep > 5 && ep < 7.5) {
        f
          ..upA = 0.4
          ..foA = 1.6
          ..watch();
      } else {
        f
          ..upA = lerp(0.4, 0.8, sip)
          ..foA = lerp(1.6, 2.95, sip)
          ..head = -0.15 * sip;
      }
      g = k.worker(Offset(x, _floor), 24, -1, f);
      k.coffee(g.handA, t);
    } else {
      if (turning > 0) {
        final w = math.sin(turning * math.pi * 6);
        f
          ..upA = 1.55 + 0.25 * w
          ..foA = 1.65 + 0.35 * w
          ..lean = 0.1;
      }
      g = k.worker(Offset(x, _floor), 24, dir, f);
    }
    // The valve and its steam.
    k.valve(_valveR, 6, turning * math.pi * 3, col: BP.lineDim);
    final st = u - 15.2;
    if (st > 0 && st < 5) {
      k.steam(const Offset(_rx + 4, 812), st, per: 0.28, life: 1.9, rise: 44, r: 9, col: BP.inkFaint, seed: n + 3, drift: 10, until: 2.6);
    }
    k.valve(_valveL, 6, 0.4, col: BP.lineFaint);
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => false;
}
