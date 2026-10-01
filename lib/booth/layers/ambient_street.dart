import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../deck/theme.dart';
import '../../worlds/factory/factory_kit.dart';
import '../layout.dart';
import '../model.dart';
import 'ambient_kit.dart';
import 'ambient_street_sim.dart';

/// Draws the street: the road (background), and in front of everything the
/// site's cones and 安全第一 banner, the traffic guard, cars, scooters and
/// buses, the near sidewalk's props (bus stop, vending machine, street lamps,
/// a 工事中 sign) and the people walking by.
class StreetArt {
  ui.Picture? _road;
  ui.Picture? _apron;
  ui.Picture? _sidewalk;

  void dispose() {
    for (final p in [_road, _apron, _sidewalk]) {
      p?.dispose();
    }
  }

  static const _lamps = [236.0, 868.0, 1318.0];
  static const _cones = [672.0, 770.0, 868.0, 966.0, 1064.0, 1376.0, 1464.0];
  static const _banner = Rect.fromLTRB(1112, 703, 1340, 719);
  static const _vending = Rect.fromLTRB(556, 762, 580, 800);
  static const _sign = Rect.fromLTRB(1500, 746, 1594, 790);

  // ── Background ────────────────────────────────────────────────────────────

  void paintBack(AmbientFrame f) {
    f.c.drawPicture(_road ??= _recordRoad());
  }

  static ui.Picture _recordRoad() {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    const pave = Color(0xFF0B1E33);
    // Apron in front of factory and site.
    c.drawRect(const Rect.fromLTRB(0, BL.groundY, 1600, Street.apronBottom), fillOf(pave));
    final joints = Path();
    for (var x = 16.0; x < 1600; x += 34) {
      joints
        ..moveTo(x, BL.groundY + 4)
        ..lineTo(x - 5, Street.apronBottom - 2);
    }
    c.drawPath(joints, strokeOf(BP.lineFaint.withValues(alpha: 0.5), 0.8));
    c.drawLine(const Offset(0, BL.groundY), const Offset(1600, BL.groundY), strokeOf(BP.lineDim, 1.2));
    // Far curb.
    c.drawRect(const Rect.fromLTRB(0, Street.apronBottom, 1600, Street.roadTop), fillOf(BP.panel));
    c.drawLine(const Offset(0, Street.apronBottom), const Offset(1600, Street.apronBottom), strokeOf(BP.lineDim, 1));
    // Asphalt.
    c.drawRect(const Rect.fromLTRB(0, Street.roadTop, 1600, Street.roadBottom), fillOf(const Color(0xFF08182A)));
    c.drawLine(const Offset(0, Street.roadTop + 3), const Offset(1600, Street.roadTop + 3), strokeOf(BP.inkFaint.withValues(alpha: 0.35), 1));
    c.drawLine(const Offset(0, Street.roadBottom - 3), const Offset(1600, Street.roadBottom - 3), strokeOf(BP.inkFaint.withValues(alpha: 0.35), 1));
    final dash = Path();
    for (var x = 8.0; x < 1600; x += 40) {
      dash
        ..moveTo(x, Street.centre)
        ..lineTo(x + 22, Street.centre);
    }
    c.drawPath(dash, strokeOf(BP.ink.withValues(alpha: 0.28), 1.6));
    // Manholes.
    for (final x in [300.0, 1190.0]) {
      final r = Rect.fromCenter(center: Offset(x, 770), width: 26, height: 6);
      c.drawOval(r, fillOf(const Color(0xFF0C2137)));
      c.drawOval(r, strokeOf(BP.lineFaint, 1));
      c.drawOval(r.deflate(2.5), strokeOf(BP.lineFaint.withValues(alpha: 0.6), 0.8));
    }
    // Near curb and sidewalk (with the yellow tactile paving strip).
    c.drawRect(const Rect.fromLTRB(0, Street.roadBottom, 1600, Street.roadBottom + 3), fillOf(BP.panel));
    c.drawLine(const Offset(0, Street.roadBottom), const Offset(1600, Street.roadBottom), strokeOf(BP.lineDim, 1));
    c.drawRect(const Rect.fromLTRB(0, Street.roadBottom + 3, 1600, Street.sidewalkBottom), fillOf(pave));
    final tiles = Path();
    for (var x = 12.0; x < 1600; x += 26) {
      tiles
        ..moveTo(x, Street.roadBottom + 4)
        ..lineTo(x - 4, Street.sidewalkBottom - 1);
    }
    c.drawPath(tiles, strokeOf(BP.lineFaint.withValues(alpha: 0.5), 0.8));
    final bumps = <Offset>[for (var x = 4.0; x < 1600; x += 6) Offset(x, Street.roadBottom + 6)];
    c.drawPoints(ui.PointMode.points, bumps, strokeOf(BP.amber.withValues(alpha: 0.16), 1.6));
    c.drawLine(const Offset(0, Street.sidewalkBottom), const Offset(1600, Street.sidewalkBottom), strokeOf(BP.lineFaint, 1));
    // The input band below stays plain and dark.
    c.drawRect(const Rect.fromLTRB(0, Street.sidewalkBottom + 0.5, 1600, 900), fillOf(BP.bg));
    return rec.endRecording();
  }

  // ── Foreground ────────────────────────────────────────────────────────────

  void paintFront(AmbientFrame f, StreetSim sim) {
    final c = f.c;
    c.drawPicture(_apron ??= _recordApron());
    _apronLive(f, sim);
    for (final car in sim.lanes[0]) {
      _car(f, car, 0);
    }
    for (final car in sim.lanes[1]) {
      _car(f, car, 1);
    }
    c.drawPicture(_sidewalk ??= _recordSidewalk());
    _sidewalkLive(f);
    for (final w in sim.walkers) {
      _walker(f, w);
    }
  }

  // Apron: cones with bars, the safety banner, the guard.

  static ui.Picture _recordApron() {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final k = FactoryInk(c);
    // Bars between neighbouring cones (striped).
    for (var i = 0; i + 1 < _cones.length; i++) {
      final a = _cones[i], b = _cones[i + 1];
      if (b - a > 120) continue;
      final bar = Rect.fromLTRB(a + 4, 709, b - 4, 712.5);
      c.drawRect(bar, fillOf(BP.panel));
      c.save();
      c.clipRect(bar);
      final stripes = Path();
      for (var x = bar.left - 6; x < bar.right; x += 9) {
        stripes
          ..moveTo(x, bar.bottom)
          ..lineTo(x + 4, bar.top);
      }
      c.drawPath(stripes, strokeOf(BP.amber.withValues(alpha: 0.75), 2.4));
      c.restore();
      c.drawRect(bar, strokeOf(BP.amber.withValues(alpha: 0.5), 0.8));
    }
    // Cones (red with white bands).
    for (final x in _cones) {
      final cone = Path()
        ..moveTo(x - 7, 720)
        ..lineTo(x - 2, 704)
        ..lineTo(x + 2, 704)
        ..lineTo(x + 7, 720)
        ..close();
      c.drawPath(cone, fillOf(const Color(0xFF2A1A26)));
      c.drawPath(cone, strokeOf(BP.red.withValues(alpha: 0.9), 1.1));
      c.drawLine(Offset(x - 4.6, 713), Offset(x + 4.6, 713), strokeOf(BP.ink.withValues(alpha: 0.8), 1.6));
      c.drawRect(Rect.fromLTRB(x - 9, 720, x + 9, 722), fillOf(BP.red.withValues(alpha: 0.7)));
    }
    // Banner posts and cloth.
    for (final x in [_banner.left - 2, _banner.right + 2]) {
      c.drawLine(Offset(x, _banner.top - 2), Offset(x, 722), strokeOf(BP.lineDim, 1.4));
    }
    k.box(_banner, col: BP.green.withValues(alpha: 0.85), w: 1.1, fill: const Color(0xFF0B2236));
    return rec.endRecording();
  }

  void _apronLive(AmbientFrame f, StreetSim sim) {
    final c = f.c;
    final banner = f.text.span(
      'safety',
      () => TextSpan(
        children: [
          TextSpan(text: '✚ ', style: BT.sample(11, color: BP.green, weight: 700)),
          TextSpan(text: '安全第一', style: BT.sample(11, color: BP.ink, weight: 700).copyWith(locale: jaLocale)),
          TextSpan(text: '  ·  Safety first', style: BT.display(9.5, color: BP.inkDim, weight: 500)),
          TextSpan(text: '  ✚', style: BT.sample(11, color: BP.green, weight: 700)),
        ],
      ),
    );
    f.centered(banner, _banner.center + const Offset(0, 0.5));
    // Warning lamps on the cones chase along at night.
    final night = f.d.night;
    if (night > 0.25) {
      for (var i = 0; i < _cones.length; i++) {
        final on = fract(f.t * 0.9 - i * 0.12) < 0.28;
        final p = Offset(_cones[i], 706);
        if (on) c.drawCircle(p, 5.5, fillOf(BP.amber.withValues(alpha: 0.22 * night)));
        c.drawCircle(p, 1.8, fillOf((on ? BP.amber : BP.lineDim).withValues(alpha: on ? night : 0.6)));
      }
    }
    _guard(f, sim);
  }

  /// 交通誘導員: the traffic guard at the site gate, with a light baton.
  void _guard(AmbientFrame f, StreetSim sim) {
    final k = f.ink;
    final t = f.t;
    final busy = sim.closed;
    final p = Pose();
    final cycle = fract(t / 9);
    if (busy) {
      // Holding the traffic: baton up, swinging.
      p
        ..upA = 2.5 + 0.45 * math.sin(t * 5)
        ..foA = 2.7 + 0.5 * math.sin(t * 5);
    } else if (cycle < 0.22) {
      final s = math.sin(cycle / 0.22 * math.pi * 4);
      p
        ..upA = 1.5 + 0.5 * s
        ..foA = 1.7 + 0.6 * s;
    } else {
      p
        ..upA = 0.35
        ..foA = 0.55
        ..head = 0.15 * math.sin(t * 0.4);
    }
    final g = k.worker(const Offset(Street.guardX, Street.apronBottom - 1), 22, -1, p, hat: BP.ink);
    final d = g.handA - g.elbowA;
    final u = d / math.max(d.distance, 0.1);
    final tip = g.handA + u * 9;
    final night = f.d.night;
    if (night > 0.3) {
      f.c.drawLine(g.handA, tip, strokeOf(BP.red.withValues(alpha: 0.35 * night), 5));
    }
    f.c.drawLine(g.handA, tip, strokeOf(night > 0.3 ? BP.red : BP.red.withValues(alpha: 0.8), 1.8));
    // Reflective vest.
    final vest = Path()
      ..moveTo(g.hip.dx - 1.5, g.hip.dy - 1)
      ..lineTo(g.hip.dx + 1.5, g.hip.dy - 6)
      ..moveTo(g.hip.dx + 1.5, g.hip.dy - 1)
      ..lineTo(g.hip.dx - 1.5, g.hip.dy - 6);
    f.c.drawPath(vest, strokeOf(BP.amber, 1));
  }

  // Sidewalk: lamps, bus stop and bench, vending machine, 工事中 sign.

  static ui.Picture _recordSidewalk() {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final k = FactoryInk(c);
    // Street lamps.
    for (final x in _lamps) {
      final pole = Path()
        ..moveTo(x, Street.walkY + 1)
        ..lineTo(x, 744)
        ..quadraticBezierTo(x, 737, x - 10, 737);
      c.drawPath(pole, strokeOf(BP.lineDim, 1.6));
      final head = Path()
        ..moveTo(x - 9, 735)
        ..lineTo(x - 21, 735)
        ..lineTo(x - 23, 739)
        ..lineTo(x - 7, 739)
        ..close();
      c.drawPath(head, fillOf(BP.panel));
      c.drawPath(head, strokeOf(BP.line.withValues(alpha: 0.7), 1));
      c.drawLine(Offset(x - 4, Street.walkY + 1), Offset(x + 4, Street.walkY + 1), strokeOf(BP.lineDim, 1.6));
    }
    // Bus stop: pole with a round plate, timetable, bench.
    const bx = Street.busPoleX;
    c.drawLine(const Offset(bx, Street.walkY + 1), const Offset(bx, 768), strokeOf(BP.lineDim, 1.6));
    c.drawCircle(const Offset(bx, 761), 9, fillOf(BP.panel));
    c.drawCircle(const Offset(bx, 761), 9, strokeOf(BP.green, 1.3));
    k.box(const Rect.fromLTWH(bx - 6, 774, 12, 14), col: BP.lineDim, w: 0.9);
    for (var i = 0; i < 4; i++) {
      c.drawLine(Offset(bx - 4, 777.0 + i * 3), Offset(bx + 4, 777.0 + i * 3), strokeOf(BP.lineFaint, 0.8));
    }
    c.drawLine(const Offset(Street.benchL, 792), const Offset(Street.benchR, 792), strokeOf(BP.line.withValues(alpha: 0.7), 2));
    c.drawLine(const Offset(Street.benchL, 785), const Offset(Street.benchR, 785), strokeOf(BP.lineDim, 1.2));
    for (final x in [Street.benchL + 3, Street.benchR - 3]) {
      c.drawLine(Offset(x, 785), Offset(x, Street.walkY + 1), strokeOf(BP.lineDim, 1.2));
    }
    // Vending machine.
    k.box(_vending, col: BP.line.withValues(alpha: 0.8), w: 1.1);
    c.drawRect(Rect.fromLTRB(_vending.left + 3, _vending.top + 3, _vending.right - 3, _vending.top + 8), strokeOf(BP.lineDim, 0.8));
    const drinks = [BP.coral, BP.green, BP.amber, BP.line, BP.pink, BP.violet];
    for (var r = 0; r < 3; r++) {
      for (var i = 0; i < 4; i++) {
        final d = Rect.fromLTWH(_vending.left + 3.5 + i * 4.6, _vending.top + 11 + r * 6.5, 2.6, 4.5);
        c.drawRect(d, fillOf(drinks[(r * 4 + i) % drinks.length].withValues(alpha: 0.6)));
      }
    }
    c.drawRect(Rect.fromLTRB(_vending.left + 4, _vending.bottom - 7, _vending.right - 4, _vending.bottom - 3), strokeOf(BP.lineDim, 0.8));
    // 工事中 sign on an A-frame.
    c.drawLine(Offset(_sign.left + 8, _sign.bottom), Offset(_sign.left + 4, Street.walkY + 1), strokeOf(BP.lineDim, 1.4));
    c.drawLine(Offset(_sign.right - 8, _sign.bottom), Offset(_sign.right - 4, Street.walkY + 1), strokeOf(BP.lineDim, 1.4));
    k.box(_sign, col: BP.amber.withValues(alpha: 0.85), w: 1.2, fill: const Color(0xFF0B2236));
    c.drawLine(Offset(_sign.left, _sign.top + 16), Offset(_sign.right, _sign.top + 16), strokeOf(BP.amber.withValues(alpha: 0.4), 0.8));
    // The bowing worker of every Japanese construction sign.
    final bow = Pose()
      ..lean = 0.95
      ..head = 0.2
      ..upA = 0.25
      ..foA = 0.35
      ..upB = 0.15
      ..foB = 0.3;
    k.worker(Offset(_sign.left + 13, _sign.bottom - 3), 18, 1, bow);
    return rec.endRecording();
  }

  void _sidewalkLive(AmbientFrame f) {
    final c = f.c;
    final night = f.d.night;
    final ja = f.text.get('工事中', BT.sample(12.5, color: BP.amber, weight: 700).copyWith(locale: jaLocale));
    f.centered(ja, Offset(_sign.center.dx, _sign.top + 8.5));
    final en1 = f.text.get('Under', BT.display(8, color: BP.ink, weight: 500));
    final en2 = f.text.get('construction', BT.display(8, color: BP.ink, weight: 500));
    en1.paint(c, Offset(_sign.left + 31, _sign.top + 18.5));
    en2.paint(c, Offset(_sign.left + 31, _sign.top + 28));
    final stop = f.text.get('バス', BT.sample(6.5, color: BP.ink, weight: 700).copyWith(locale: jaLocale));
    f.centered(stop, const Offset(Street.busPoleX, 761));
    if (night > 0.2) {
      // Lamps, the vending machine, the sign's little light.
      for (final x in _lamps) {
        final cone = Path()
          ..moveTo(x - 20, 739)
          ..lineTo(x - 10, 739)
          ..lineTo(x + 26, Street.walkY + 2)
          ..lineTo(x - 56, Street.walkY + 2)
          ..close();
        c.drawPath(
          cone,
          Paint()
            ..shader = ui.Gradient.linear(const Offset(0, 739), const Offset(0, Street.walkY), [
              BP.amber.withValues(alpha: 0.16 * night),
              BP.amber.withValues(alpha: 0.04 * night),
            ]),
        );
        c.drawCircle(Offset(x - 15, 738.5), 3, fillOf(const Color(0xFFFFE6B8).withValues(alpha: night)));
        glow(c, Rect.fromCenter(center: Offset(x - 15, 739), width: 18, height: 6), BP.amber.withValues(alpha: 0.35 * night), 4, radius: 3);
      }
      glow(c, _vending.inflate(3), BP.ink.withValues(alpha: 0.13 * night), 6);
      c.drawRect(
        Rect.fromLTRB(_vending.left + 3, _vending.top + 3, _vending.right - 3, _vending.top + 8),
        fillOf(BP.ink.withValues(alpha: 0.55 * night)),
      );
      final blink = fract(f.t * 0.8) < 0.5;
      c.drawCircle(Offset(_sign.right - 2, _sign.top - 2), 2.2, fillOf((blink ? BP.red : BP.lineDim).withValues(alpha: night)));
    }
  }

  // ── Vehicles ──────────────────────────────────────────────────────────────

  static const _bodyColors = [BP.line, BP.ink, BP.violet, BP.coral, BP.green, BP.pink, BP.inkDim, BP.amber];

  void _car(AmbientFrame f, Car car, int lane) {
    final c = f.c;
    final y = Street.laneY[lane];
    final dir = Street.laneDir[lane];
    final d = dir.toDouble();
    final cx = car.x - d * car.len / 2;
    if (cx + car.len < -20 || cx - car.len > 1620) return;
    Offset p(double u, double v) => Offset(cx + d * u, y - v);
    Path poly(List<(double, double)> pts) {
      final path = Path()..moveTo(p(pts[0].$1, pts[0].$2).dx, p(pts[0].$1, pts[0].$2).dy);
      for (final (u, v) in pts.skip(1)) {
        final q = p(u, v);
        path.lineTo(q.dx, q.dy);
      }
      return path..close();
    }

    final night = f.d.night;
    final col = switch (car.kind) {
      CarKind.bus => BP.green,
      CarKind.taxi => rnd(car.seed, 61) < 0.5 ? BP.amber : BP.green,
      CarKind.scooter => rnd(car.seed, 61) < 0.5 ? BP.red : BP.coral,
      _ => _bodyColors[(rnd(car.seed, 61) * _bodyColors.length).floor() % _bodyColors.length],
    };
    final edge = col.withValues(alpha: 0.85);
    final glass = night > 0.4
        ? const Color(0xFFFFE6B8).withValues(alpha: (car.kind == CarKind.bus ? 0.5 : 0.28) * night)
        : BP.lineFaint;
    final half = car.len / 2;

    // Shadow.
    c.drawOval(Rect.fromCenter(center: Offset(cx, y + 0.5), width: car.len * 0.95, height: 4), fillOf(const Color(0x66040C16)));
    // Headlight beam at night.
    if (night > 0.2) {
      final h0 = p(half - 1, car.kind == CarKind.bus ? 10 : 9);
      final beam = Path()
        ..moveTo(h0.dx, h0.dy - 2)
        ..lineTo(h0.dx + d * 120, h0.dy - 10)
        ..lineTo(h0.dx + d * 120, y + 2)
        ..lineTo(h0.dx, h0.dy + 2)
        ..close();
      c.drawPath(
        beam,
        Paint()
          ..shader = ui.Gradient.linear(h0, h0 + Offset(d * 120, 0), [
            BP.amber.withValues(alpha: 0.17 * night),
            BP.amber.withValues(alpha: 0),
          ]),
      );
    }

    void wheel(double u, double r) {
      final w = p(u, r);
      c.drawCircle(w, r, fillOf(const Color(0xFF071322)));
      c.drawCircle(w, r, strokeOf(BP.lineDim, 1.2));
      c.drawCircle(w, r * 0.35, strokeOf(BP.lineDim, 0.8));
      final a = -d * car.roll;
      c.drawLine(w, w + Offset(math.cos(a), math.sin(a)) * (r - 0.8), strokeOf(BP.lineDim, 0.8));
    }

    void lights(double vHead, double vTail) {
      c.drawCircle(p(half - 1.2, vHead), 1.7, fillOf(night > 0.2 ? const Color(0xFFFFE6B8) : BP.inkFaint));
      c.drawCircle(p(-half + 1, vTail), 1.6, fillOf(BP.red.withValues(alpha: night > 0.2 ? 1 : 0.55)));
      if (night > 0.2) c.drawCircle(p(-half + 1, vTail), 4.5, fillOf(BP.red.withValues(alpha: 0.2 * night)));
    }

    switch (car.kind) {
      case CarKind.kei:
        final body = poly([(-22, 3), (-22, 15), (-20, 17), (-18.5, 25.5), (11, 25.5), (17, 16.5), (21, 14.5), (22, 7), (21, 3)]);
        c.drawPath(body, fillOf(BP.panel));
        c.drawPath(body, strokeOf(edge, 1.2));
        c.drawPath(poly([(-16, 17.5), (-15, 23.5), (-3, 23.5), (-3, 17.5)]), fillOf(glass));
        c.drawPath(poly([(-0.5, 17.5), (-0.5, 23.5), (10, 23.5), (14.5, 17.5)]), fillOf(glass));
        c.drawLine(p(-1.5, 15), p(-1.5, 5), strokeOf(edge.withValues(alpha: 0.5), 0.8));
        wheel(-13, 4.5);
        wheel(13, 4.5);
        lights(11, 12);
      case CarKind.sedan || CarKind.taxi:
        final body = poly([(-29, 3), (-29.5, 12), (-27, 14.5), (-15, 15.5), (-10, 22.5), (7, 22.5), (14, 15.5), (27, 13.5), (29.5, 8), (28.5, 3)]);
        c.drawPath(body, fillOf(BP.panel));
        c.drawPath(body, strokeOf(edge, 1.2));
        c.drawPath(poly([(-13, 16), (-9, 21), (-1, 21), (-1, 16)]), fillOf(glass));
        c.drawPath(poly([(1, 16), (1, 21), (6, 21), (11, 16)]), fillOf(glass));
        if (car.kind == CarKind.taxi) {
          final andon = Rect.fromPoints(p(-4, 22.5), p(4, 26.5));
          c.drawRect(andon, fillOf(BP.amber.withValues(alpha: night > 0.3 ? 0.95 : 0.6)));
          if (night > 0.3) glow(c, andon.inflate(3), BP.amber.withValues(alpha: 0.3 * night), 3, radius: 2);
          // 空車 (vacant) in the windscreen: a red glow.
          c.drawRect(Rect.fromPoints(p(6.5, 16.5), p(9.5, 18.5)), fillOf(BP.red.withValues(alpha: 0.85)));
        }
        wheel(-18, 5);
        wheel(18, 5);
        lights(9, 11);
      case CarKind.van:
        final body = poly([(-30, 3), (-30, 26), (15, 26), (26, 16), (30, 13), (30, 3)]);
        c.drawPath(body, fillOf(BP.panel));
        c.drawPath(body, strokeOf(edge, 1.2));
        c.drawPath(poly([(9, 16.5), (9, 23.5), (15.5, 23.5), (22.5, 16.5)]), fillOf(glass));
        c.drawPath(poly([(-4, 16.5), (-4, 23.5), (6, 23.5), (6, 16.5)]), fillOf(glass));
        const labels = ['文字便', 'GLYPH EXPRESS', 'フォント運送'];
        final label = labels[(rnd(car.seed, 62) * labels.length).floor() % labels.length];
        final lp = f.text.get(label, BT.sample(7, color: edge, weight: 700).copyWith(locale: jaLocale));
        f.ink.paintFit(lp, Rect.fromPoints(p(-27, 5.5), p(6, 14.5)), fitHeight: true);
        wheel(-19, 5);
        wheel(19, 5);
        lights(9, 12);
      case CarKind.truck:
        final cab = poly([(8, 3), (8, 22.5), (22, 22.5), (26.5, 13), (27, 3)]);
        c.drawPath(cab, fillOf(BP.panel));
        c.drawPath(cab, strokeOf(edge, 1.2));
        c.drawPath(poly([(11, 13.5), (11, 20.5), (20.5, 20.5), (24, 13.5)]), fillOf(glass));
        // Open bed with letter crates.
        const glyphs = ['あ', 'A', '字', 'Ж', 'ก', '한', 'ア', 'Ω', 'क', 'ש'];
        for (var i = 0; i < 2; i++) {
          final u0 = -25.0 + i * 15;
          final crate = Rect.fromPoints(p(u0, 10), p(u0 + 13, 22));
          c.drawRect(crate, fillOf(BP.panel));
          c.drawRect(crate, strokeOf(BP.amber.withValues(alpha: 0.85), 1));
          final g = f.text.get(glyphs[(rnd(car.seed, 63, i) * glyphs.length).floor() % glyphs.length], BT.sample(8.5, color: BP.ink, weight: 600).copyWith(locale: jaLocale));
          f.centered(g, crate.center + const Offset(0, 0.5));
        }
        final bed = poly([(-27, 3), (-27, 10.5), (7, 10.5), (7, 3)]);
        c.drawPath(bed, fillOf(BP.panel));
        c.drawPath(bed, strokeOf(edge, 1.2));
        wheel(-17, 4.5);
        wheel(17, 4.5);
        lights(10, 8);
      case CarKind.yakiimo:
        // 焼き芋: a kei truck with a stone oven, crawling along and singing.
        final cab = poly([(8, 3), (8, 22.5), (22, 22.5), (26.5, 13), (27, 3)]);
        c.drawPath(cab, fillOf(BP.panel));
        c.drawPath(cab, strokeOf(BP.ink.withValues(alpha: 0.8), 1.2));
        c.drawPath(poly([(11, 13.5), (11, 20.5), (20.5, 20.5), (24, 13.5)]), fillOf(glass));
        final chimney = Rect.fromPoints(p(-19.5, 21), p(-16, 29));
        c.drawRect(chimney, fillOf(BP.panel));
        c.drawRect(chimney, strokeOf(BP.inkDim, 1));
        f.ink.steam(p(-17.75, 30), f.t + car.seed, per: 0.45, life: 1.8, rise: 9, r: 3, col: BP.inkDim, seed: car.seed, drift: -d * 8);
        final oven = Rect.fromPoints(p(-25, 10), p(4, 22));
        c.drawRect(oven, fillOf(BP.panel));
        c.drawRect(oven, strokeOf(BP.inkDim, 1));
        final fire = Rect.fromPoints(p(-23, 12.5), p(-17, 17));
        c.drawRect(fire, fillOf(BP.coral.withValues(alpha: 0.45 + 0.45 * night)));
        if (night > 0.3) glow(c, fire.inflate(3), BP.amber.withValues(alpha: 0.35 * night), 3, radius: 2);
        final sign = f.text.get('やきいも', BT.sample(7, color: BP.red, weight: 700).copyWith(locale: jaLocale));
        f.ink.paintFit(sign, Rect.fromPoints(p(-15.5, 12), p(3.5, 20.5)), fitHeight: true);
        final bed = poly([(-27, 3), (-27, 10), (7, 10), (7, 3)]);
        c.drawPath(bed, fillOf(BP.panel));
        c.drawPath(bed, strokeOf(BP.ink.withValues(alpha: 0.8), 1.2));
        // ♪ いしや〜きいも〜: little notes drift up from the loudspeaker.
        for (var i = 0; i < 2; i++) {
          final q = fract(f.t * 0.55 + i * 0.5 + car.seed * 0.1);
          final n = p(12 - 6 * q, 24 + 10 * q) + Offset(2 * math.sin(q * 9), 0);
          final col2 = BP.amber.withValues(alpha: 0.9 * bump(q));
          c.drawCircle(n, 1.5, fillOf(col2));
          c.drawLine(n + const Offset(1.3, 0), n + const Offset(1.3, -5.5), strokeOf(col2, 0.8));
          c.drawLine(n + const Offset(1.3, -5.5), n + const Offset(3.8, -3.8), strokeOf(col2, 0.8));
        }
        wheel(-17, 4.5);
        wheel(17, 4.5);
        lights(10, 8);
      case CarKind.scooter:
        final k = f.ink;
        final rider = Pose()
          ..sit(19, 13)
          ..upA = 1.25
          ..foA = 1.45
          ..upB = 1.2
          ..foB = 1.4
          ..lean = 0.18;
        final seat = p(-3, 0);
        k.worker(Offset(seat.dx, y), 19, dir, rider, hat: col);
        final body = Path()
          ..moveTo(p(-12, 5).dx, p(-12, 5).dy)
          ..lineTo(p(-9, 12.5).dx, p(-9, 12.5).dy)
          ..lineTo(p(3, 12.5).dx, p(3, 12.5).dy)
          ..lineTo(p(6, 6).dx, p(6, 6).dy)
          ..lineTo(p(10, 6).dx, p(10, 6).dy);
        c.drawPath(body, strokeOf(edge, 1.6));
        c.drawLine(p(11, 4.5), p(8, 21), strokeOf(edge, 1.4));
        c.drawLine(p(6.5, 21), p(10, 21.5), strokeOf(edge, 1.4));
        final box = Rect.fromPoints(p(-18, 12.5), p(-7, 23));
        c.drawRect(box, fillOf(BP.panel));
        c.drawRect(box, strokeOf(edge, 1.1));
        final mark = f.text.get(col == BP.red ? '〒' : '麺', BT.sample(7.5, color: edge, weight: 700).copyWith(locale: jaLocale));
        f.centered(mark, box.center + const Offset(0, 0.5));
        wheel(-11, 4.5);
        wheel(11, 4.5);
        lights(12, 9);
      case CarKind.bus:
        final shell = RRect.fromRectAndCorners(
          Rect.fromPoints(p(-62, 4), p(62, 45)),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
          bottomLeft: const Radius.circular(2),
          bottomRight: const Radius.circular(2),
        );
        c.drawRRect(shell, fillOf(BP.panel));
        c.drawRRect(shell, strokeOf(edge, 1.3));
        for (var i = 0; i < 7; i++) {
          final u0 = -56.0 + i * 13;
          c.drawRect(Rect.fromPoints(p(u0, 25), p(u0 + 11, 36)), fillOf(glass));
        }
        c.drawRect(Rect.fromPoints(p(45, 22), p(60.5, 41)), fillOf(glass));
        c.drawRect(Rect.fromPoints(p(34, 5), p(43, 37)), strokeOf(edge.withValues(alpha: 0.7), 0.9));
        c.drawLine(p(38.5, 5), p(38.5, 37), strokeOf(edge.withValues(alpha: 0.5), 0.8));
        // Destination board and route number.
        final board = Rect.fromPoints(p(-30, 38), p(40, 43.5));
        c.drawRect(board, fillOf(const Color(0xFF06111F)));
        final dest = f.text.span(
          'busdest',
          () => TextSpan(
            children: [
              TextSpan(text: '渋谷駅 ', style: BT.sample(5.5, color: BP.amber, weight: 700).copyWith(locale: jaLocale)),
              TextSpan(text: 'Shibuya Sta.', style: BT.display(5, color: BP.amber, weight: 600)),
            ],
          ),
        );
        f.centered(dest, board.center);
        final route = f.text.get('都01', BT.sample(5.5, color: BP.ink, weight: 700).copyWith(locale: jaLocale));
        f.centered(route, p(-48, 40.5));
        // Side advert in many scripts.
        final ad = Rect.fromPoints(p(-54, 9), p(28, 20));
        c.drawRect(ad, strokeOf(edge.withValues(alpha: 0.5), 0.8));
        final adText = f.text.get(
          'Hello · こんにちは · مرحبا · 안녕',
          BT.sample(7, color: BP.ink.withValues(alpha: 0.85), weight: 600).copyWith(locale: jaLocale),
        );
        f.ink.paintFit(adText, ad.deflate(2), fitHeight: true);
        wheel(-40, 6);
        wheel(40, 6);
        lights(11, 13);
    }
  }

  // ── People ────────────────────────────────────────────────────────────────

  static const _clothes = [BP.ink, BP.inkDim, BP.violet, BP.pink, BP.green, BP.coral, BP.line, BP.amber];

  void _walker(AmbientFrame f, Walker w) {
    final c = f.c;
    final k = FactoryInk(c, dim: c01(w.fade));
    final t = f.t;
    final col = _clothes[(rnd(w.seed, 71) * _clothes.length).floor() % _clothes.length];
    final back = Color.lerp(col, BP.bg, 0.45)!;
    final phase = f.phase;
    final feet = Offset(w.x, Street.walkY);
    final ph = w.dist / (w.h * 0.11);
    final moving = w.still == 0;
    final pose = Pose();

    c.drawOval(Rect.fromCenter(center: feet + const Offset(0, 1), width: w.h * 0.55, height: 2.5), k.fl(const Color(0x55040C16)));
    if (w.kind == WalkerKind.bike) {
      _bike(f, k, w, col, back, ph);
      return;
    }
    if (moving) pose.walk(ph, amp: 0.38);

    final looking = w.state == WalkerState.look;
    final sitting = w.state == WalkerState.wait && !moving && w.target < Street.benchR - 10;
    if (sitting) pose.sit(w.h, 8);
    final cheering = phase == Phase.celebrate;

    switch (w.kind) {
      case WalkerKind.letter:
        pose.carry();
        if (cheering) {
          pose
            ..upA = 2.75
            ..foA = 2.95
            ..upB = 2.85
            ..foB = 3.05;
        }
      case WalkerKind.balloon:
        pose
          ..upA = 2.2
          ..foA = 2.5;
      case WalkerKind.parasol:
        pose
          ..upA = 2.35
          ..foA = 2.75;
      case WalkerKind.camera when looking:
        pose
          ..upA = 2.0
          ..foA = 2.9
          ..upB = 1.9
          ..foB = 2.8
          ..head = -0.12;
      case WalkerKind.dog || WalkerKind.briefcase:
        pose
          ..upA = 0.35 + (moving ? 0.25 * math.sin(ph) : 0)
          ..foA = 0.6;
      default:
        break;
    }
    if (looking && w.kind != WalkerKind.camera) {
      if (phase == Phase.demolish) {
        pose.overwhelmed(t);
      } else if (cheering) {
        pose.cheer(t, w.seed);
      } else {
        pose
          ..point(2.25)
          ..head = -0.3;
      }
    } else if (cheering && (w.kind == WalkerKind.plain || w.kind == WalkerKind.briefcase || w.kind == WalkerKind.camera)) {
      pose.cheer(t, w.seed);
    } else if (w.state == WalkerState.wait && !moving && fract(w.still / 7) > 0.7) {
      pose.watch();
    }

    final g = k.worker(feet, w.h, w.dir, pose, helmet: false, ink: col, back: back);
    _hair(k, g.head, w);

    final d = w.dir.toDouble();
    switch (w.kind) {
      case WalkerKind.letter:
        final mid = Offset.lerp(g.handA, g.handB, 0.5)! + Offset(d * 2, -5);
        final crate = Rect.fromCenter(center: mid, width: 14, height: 12);
        c.drawRect(crate, k.fl(BP.panel));
        c.drawRect(crate, k.st(BP.amber, 1));
        const glyphs = ['あ', 'A', '字', 'Ж', 'ก', '한', 'ア', 'Ω', 'क', 'ע', 'é', 'ß'];
        final gp = f.text.get(glyphs[(rnd(w.seed, 72) * glyphs.length).floor() % glyphs.length], BT.sample(8.5, color: BP.ink, weight: 600).copyWith(locale: jaLocale));
        if (w.fade >= 1) f.centered(gp, crate.center + const Offset(0, 0.5));
      case WalkerKind.balloon:
        final sway = 3 * math.sin(t * 1.3 + w.seed);
        final b = g.handA + Offset(d * 4 + sway, -27 + 1.5 * math.sin(t * 2.1 + w.seed));
        final string = Path()
          ..moveTo(g.handA.dx, g.handA.dy)
          ..quadraticBezierTo(g.handA.dx - d * 3, (g.handA.dy + b.dy) / 2, b.dx, b.dy + 7.5);
        c.drawPath(string, k.st(BP.inkDim, 0.8));
        const bc = [BP.pink, BP.amber, BP.green, BP.violet, BP.coral];
        final bcol = bc[(rnd(w.seed, 73) * bc.length).floor() % bc.length];
        c.drawCircle(b, 7.5, k.fl(Color.lerp(BP.panel, bcol, 0.25)!));
        c.drawCircle(b, 7.5, k.st(bcol, 1.2));
        const glyphs = ['あ', 'A', '字', 'ア', 'Ω', '♪'];
        final gp = f.text.get(glyphs[(rnd(w.seed, 74) * glyphs.length).floor() % glyphs.length], BT.sample(8, color: bcol, weight: 700).copyWith(locale: jaLocale));
        if (w.fade >= 1) f.centered(gp, b + const Offset(0, 0.5));
      case WalkerKind.parasol:
        if (f.d.day > 0.4) {
          final top = g.handA + const Offset(0, -6);
          final canopy = Path()
            ..moveTo(top.dx - 13, top.dy + 4)
            ..quadraticBezierTo(top.dx, top.dy - 13, top.dx + 13, top.dy + 4)
            ..close();
          c.drawPath(canopy, k.fl(BP.pink.withValues(alpha: 0.25)));
          c.drawPath(canopy, k.st(BP.pink, 1.1));
          c.drawLine(g.handA, top - const Offset(0, 4), k.st(BP.inkDim, 1));
        }
      case WalkerKind.briefcase:
        final bag = Rect.fromLTWH(g.handA.dx - 4, g.handA.dy, 8, 6);
        c.drawRect(bag, k.fl(BP.panel));
        c.drawRect(bag, k.st(BP.inkDim, 1));
      case WalkerKind.camera:
        final at = looking ? Offset.lerp(g.handA, g.handB, 0.5)! + Offset(d * 2, -2) : g.hip + Offset(d * 2, -w.h * 0.22);
        final cam = Rect.fromCenter(center: at, width: 7, height: 5);
        c.drawRect(cam, k.fl(BP.panel));
        c.drawRect(cam, k.st(BP.ink, 1));
        if (looking && fract(t * 0.6 + w.seed * 0.13) < 0.08) k.star(cam.center + Offset(d * 3, -1), 7, BP.ink);
      case WalkerKind.dog:
        _dog(f, k, w, g.handA, ph);
      default:
        break;
    }
  }

  void _hair(FactoryInk k, Offset head, Walker w) {
    final r = 0.125 * w.h;
    final d = w.dir.toDouble();
    final style = rnd(w.seed, 75);
    if (style < 0.3) {
      // Cap.
      k.c.drawArc(Rect.fromCircle(center: head, radius: r + 0.5), math.pi, math.pi, true, k.fl(_clothes[(rnd(w.seed, 76) * 8).floor() % 8]));
      k.c.drawLine(head + Offset(-d * r * 0.2, -r * 0.1), head + Offset(d * (r + 3), -r * 0.1), k.st(_clothes[(rnd(w.seed, 76) * 8).floor() % 8], 1.2));
    } else if (style < 0.55) {
      // Hair tied back.
      final p = Path()
        ..moveTo(head.dx - d * r * 0.6, head.dy - r * 0.7)
        ..quadraticBezierTo(head.dx - d * (r + 4), head.dy - r * 0.2, head.dx - d * (r + 2), head.dy + r * 0.9);
      k.c.drawPath(p, k.st(BP.inkDim, 1.4));
    }
  }

  void _dog(AmbientFrame f, FactoryInk k, Walker w, Offset hand, double ph) {
    final c = f.c;
    final d = w.dir.toDouble();
    final moving = w.still == 0;
    final bx = w.x + d * 17;
    const y = Street.walkY;
    final body = Rect.fromCenter(center: Offset(bx, y - 7), width: 13, height: 5.5);
    final legs = Path();
    for (final (o, phase) in [(-4.5, 0.0), (-2.5, math.pi), (3.0, math.pi), (5.0, 0.0)]) {
      final sw = moving ? 2.2 * math.sin(ph * 1.6 + phase) : 0.0;
      legs
        ..moveTo(bx + d * o, y - 6)
        ..lineTo(bx + d * (o + sw), y);
    }
    c.drawPath(legs, k.st(BP.inkDim, 1.2));
    c.drawOval(body, k.fl(BP.panel));
    c.drawOval(body, k.st(BP.inkDim, 1.2));
    final head = Offset(bx + d * 8, y - 11);
    c.drawCircle(head, 3, k.fl(BP.panel));
    c.drawCircle(head, 3, k.st(BP.inkDim, 1.1));
    c.drawLine(head + Offset(-d * 1, -2.4), head + Offset(-d * 2.8, -5), k.st(BP.inkDim, 1.1));
    final wag = math.sin(f.t * (moving ? 9 : 5) + w.seed) * 0.6;
    final tail0 = Offset(bx - d * 6.5, y - 8);
    c.drawLine(tail0, tail0 + Offset(-d * 3 * math.cos(wag), -4 - 2 * math.sin(wag)), k.st(BP.inkDim, 1.1));
    c.drawLine(hand, head + Offset(-d * 2, 2), k.st(BP.amber.withValues(alpha: 0.7), 0.8));
  }

  void _bike(AmbientFrame f, FactoryInk k, Walker w, Color col, Color back, double ph) {
    final c = f.c;
    final d = w.dir.toDouble();
    final x = w.x;
    const y = Street.walkY;
    final rot = w.dist / 6;
    for (final o in [-11.0, 11.0]) {
      final hub = Offset(x + d * o, y - 6);
      c.drawCircle(hub, 6, k.st(BP.inkDim, 1.1));
      c.drawLine(hub, hub + Offset(math.cos(rot), math.sin(rot)) * 5.5, k.st(BP.lineDim, 0.8));
    }
    final crank = Offset(x, y - 6);
    final seat = Offset(x - d * 3, y - 17);
    final bar = Offset(x + d * 8, y - 19);
    final frame = Path()
      ..moveTo(x - d * 11, y - 6)
      ..lineTo(crank.dx, crank.dy)
      ..lineTo(seat.dx, seat.dy)
      ..moveTo(crank.dx, crank.dy)
      ..lineTo(bar.dx - d * 2, bar.dy + 5)
      ..lineTo(x + d * 11, y - 6)
      ..moveTo(bar.dx - d * 2, bar.dy + 5)
      ..lineTo(bar.dx, bar.dy);
    c.drawPath(frame, k.st(col, 1.3));
    // Front basket with a letter.
    final basket = Rect.fromLTWH(x + d * 10 - 4, y - 21, 8, 6);
    c.drawRect(basket, k.st(BP.lineDim, 1));
    final pose = Pose()
      ..sit(w.h, 17)
      ..lean = 0.25
      ..upA = 1.25
      ..foA = 1.5
      ..upB = 1.2
      ..foB = 1.45;
    final s = math.sin(ph * 0.6);
    pose
      ..thA = 1.05 + 0.35 * s
      ..shA = 0.15 - 0.45 * s
      ..thB = 1.05 - 0.35 * s
      ..shB = 0.15 + 0.45 * s;
    final g = k.worker(Offset(seat.dx, y), w.h, w.dir, pose, helmet: false, ink: col, back: back);
    _hair(k, g.head, w);
    final gp = f.text.get('文', BT.sample(6.5, color: BP.amber, weight: 700).copyWith(locale: jaLocale));
    f.centered(gp, basket.center + const Offset(0, -2));
  }
}
