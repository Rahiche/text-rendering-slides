import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../deck/theme.dart';
import 'building.dart';
import 'site_kit.dart';

// The building is complete: the roof goes on, two workers cut the ribbon with
// giant scissors, the whole crew cheers and fireworks go up — forever, with a
// new seeded burst every ~0.75 s. Click the sky to launch one; click the
// ribbon to tie it again and cut it once more.

const _g = Bld.ground;
const _ribbonY = 716.0;
const _postL = 944.0;
const _postR = 1456.0;
const _cutX = 1214.0;

const _colors = [BP.amber, BP.green, BP.pink, BP.violet, BP.coral, BP.line];

class ConstructionOutro extends StatefulWidget {
  const ConstructionOutro({super.key});

  @override
  State<ConstructionOutro> createState() => _ConstructionOutroState();
}

class _OutroModel {
  final labels = SiteLabels();
  double cutAt = 3.0;
  double tiedAt = 0;
  final launches = <(double, Offset)>[];
}

class _ConstructionOutroState extends State<ConstructionOutro> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0);
  final _m = _OutroModel();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => _clock.value = d.inMicroseconds / 1e6)..start();
    PaintingBinding.instance.systemFonts.addListener(_m.labels.clear);
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_m.labels.clear);
    _ticker.dispose();
    _clock.dispose();
    _m.labels.clear();
    super.dispose();
  }

  void _tap(Offset p) {
    final t = _clock.value;
    if (const Rect.fromLTRB(_postL - 20, _ribbonY - 50, _postR + 20, _g + 6).contains(p)) {
      if (t > _m.cutAt + 1) {
        _m.tiedAt = t;
        _m.cutAt = t + 2.2;
      }
      return;
    }
    if (p.dy < _g - 60) {
      _m.launches.add((t, p));
      if (_m.launches.length > 10) _m.launches.removeAt(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (d) => _tap(d.localPosition),
        child: SizedBox.expand(child: CustomPaint(painter: _OutroPainter(_clock, _m))),
      ),
    );
  }
}

class _OutroPainter extends CustomPainter {
  _OutroPainter(this.clock, this.m) : super(repaint: clock);

  final ValueNotifier<double> clock;
  final _OutroModel m;

  @override
  void paint(Canvas canvas, Size size) => _Outro(canvas, clock.value, m).paint();

  @override
  bool shouldRepaint(_OutroPainter old) => old.m != m;
}

class _Outro {
  _Outro(this.c, this.t, this.m) {
    k = SiteKit(c, t, m.labels, crew);
  }

  final Canvas c;
  final double t;
  final _OutroModel m;
  final crew = SiteCrew();
  late final SiteKit k;

  SiteLabels get labels => m.labels;
  bool get cut => t >= m.cutAt;
  double get sinceCut => t - m.cutAt;

  void paint() {
    _fireworks();
    paintGround(k);
    paintBuilding(k, done: Bld.floors, roof: seg01(t, 0.6, 1.4), lit: 0.25 + 0.35 * seg01(sinceCut, 0, 1.5));
    _crane();
    _ribbon();
    _crowd();
    crew.flush(c);
    _scissors();
    _confetti();
    _text();
  }

  void _crane() {
    k.towerCrane(mastL: Bld.mastL, mastR: Bld.mastR, ground: _g, jibY: Bld.jibY, jibL: Bld.jibL, jibR: Bld.jibR);
    // The crane sets the roof, then rests with a pennant on the hook.
    final roofY = Bld.top(Bld.floors) - 30;
    final down = seg01(t, 0.0, 0.8);
    final up = seg01(t, 1.5, 2.4);
    final x = Bld.cx + math.sin(t * 0.5) * 30 * up;
    final y = lerpD(lerpD(Bld.jibY + 60, roofY, eio(down)), 400, eio(up)) + math.sin(t * 1.2) * 4 * up;
    k.trolley(x, Bld.jibY, y);
    if (up > 0.5) {
      final pen = Path()..moveTo(x, y + 6);
      for (var i = 0; i <= 6; i++) {
        pen.lineTo(x + 30 * i / 6, y + 6 + math.sin(t * 5 - i) * 2 * i / 6);
      }
      pen.lineTo(x, y + 20);
      c.drawPath(pen..close(), fillP(BP.amber.withValues(alpha: 0.7)));
    }
  }

  // ── Ribbon and giant scissors ──────────────────────────────────────────────

  void _ribbon() {
    final col = BP.coral;
    // Stands.
    for (final x in [_postL, _postR]) {
      c.drawLine(Offset(x, _ribbonY - 4), Offset(x, _g), strokeP(BP.line, 1.6));
      c.drawLine(Offset(x - 8, _g), Offset(x + 8, _g), strokeP(BP.line, 1.6));
      c.drawCircle(Offset(x, _ribbonY - 6), 3, fillP(BP.amber));
    }
    final rib = strokeP(col, 3.2);
    if (!cut) {
      c.drawLine(const Offset(_postL, _ribbonY), const Offset(_postR, _ribbonY), rib);
      _bow(const Offset(1196, _ribbonY), 0);
      return;
    }
    // Both halves drop from the cut and droop to the ground.
    final f = backOut(seg01(sinceCut, 0, 0.7));
    for (final side in [-1.0, 1.0]) {
      final post = Offset(side < 0 ? _postL : _postR, _ribbonY);
      final end = Offset(lerpD(_cutX, _cutX - side * -40 + side * 20, c01(f)), lerpD(_ribbonY, _g - 2, c01(f)));
      final ctrl = Offset((post.dx + end.dx) / 2, lerpD(_ribbonY, _g + 14, c01(f)));
      final p = Path()
        ..moveTo(post.dx, post.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);
      c.drawPath(p, rib);
      if (side < 0) _bow(Offset.lerp(post, end, 0.93)! + Offset(0, 10 * c01(f)), 0.5 * c01(f));
    }
  }

  void _bow(Offset at, double tilt) {
    c.save();
    c.translate(at.dx, at.dy);
    c.rotate(tilt);
    final p = strokeP(BP.coral, 2.4);
    c.drawOval(Rect.fromCenter(center: const Offset(-13, -6), width: 24, height: 14), p);
    c.drawOval(Rect.fromCenter(center: const Offset(13, -6), width: 24, height: 14), p);
    c.drawLine(Offset.zero, const Offset(-10, 18), p);
    c.drawLine(Offset.zero, const Offset(10, 18), p);
    c.drawCircle(Offset.zero, 4, fillP(BP.coral));
    c.restore();
  }

  void _scissors() {
    // Approach the ribbon, snip, then held up in triumph.
    final u = t - m.tiedAt;
    final approach = eio(seg01(u, 0.3, m.cutAt - m.tiedAt - 0.4));
    final open = cut ? 0.0 : (0.35 + 0.25 * math.sin(u * 5).abs()) * (1 - seg01(t, m.cutAt - 0.25, m.cutAt));
    final raise = cut ? eo(seg01(sinceCut, 0.4, 1.2)) : 0.0;
    final pivot = Offset(lerpD(1080, 1170, approach), lerpD(_ribbonY, _ribbonY - 36, raise));
    final rot = -0.3 * raise;
    c.save();
    c.translate(pivot.dx, pivot.dy);
    c.rotate(rot);
    for (final s in [-1.0, 1.0]) {
      c.save();
      c.rotate(s * open * 0.5);
      final blade = Path()
        ..moveTo(0, -4 * s)
        ..lineTo(96, -1 * s)
        ..lineTo(96, 0)
        ..lineTo(0, 5 * s)
        ..close();
      c.drawPath(blade, fillP(BP.paper));
      c.drawPath(blade, strokeP(BP.ink, 1.6));
      // Handle and ring.
      c.drawLine(Offset.zero, Offset(-40, 10 * s), strokeP(BP.ink, 2.4));
      c.drawCircle(Offset(-52, 12 * s), 12, strokeP(BP.amber, 3));
      c.restore();
    }
    c.drawCircle(Offset.zero, 3.4, fillP(BP.amber));
    c.restore();
    // Snip!
    if (cut && sinceCut < 0.5) {
      final f = sinceCut / 0.5;
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        final o = const Offset(_cutX, _ribbonY) + Offset(math.cos(a), math.sin(a)) * (10 + 26 * eo(f));
        c.drawLine(o, o + Offset(math.cos(a), math.sin(a)) * 8, strokeP(BP.amber.withValues(alpha: 1 - f), 2));
      }
    }
    // The two scissor hands: workers holding the rings.
    final hands = [const Offset(0, -12), const Offset(0, 12)];
    for (var i = 0; i < 2; i++) {
      final ring = pivot + _rot(Offset(-52, hands[i].dy), rot);
      final feet = Offset(ring.dx - 22 - i * 16, _g);
      crew.walker(feet, face: 1, stride: 0, lean: 0.12, handF: ring, armB: cut ? 2.8 : 0.4);
    }
    crew.flush(c);
  }

  Offset _rot(Offset p, double a) =>
      Offset(p.dx * math.cos(a) - p.dy * math.sin(a), p.dx * math.sin(a) + p.dy * math.cos(a));

  // ── The crowd ──────────────────────────────────────────────────────────────

  void _crowd() {
    final cheer = cut;
    // Everyone who built it: the mixer from the foundations, the flatbed that
    // brought the materials, and the whole crew.
    k.truck(250, 782, 1, 1, null);
    k.truck(470, 782, 1, 3, null);
    for (final (x, y) in const [(208.0, 728.0), (420.0, 750.0), (452.0, 750.0)]) {
      if (cheer) {
        crew.cheer(Offset(x, y), t, seed: x);
      } else {
        crew.walker(Offset(x, y), stride: 0, armF: 0.2, armB: -0.2);
      }
    }
    for (var i = 0; i < 9; i++) {
      final x = 640.0 + i * 34 + (i.isEven ? 0 : 6);
      final feet = Offset(x, _g);
      if (cheer && hash1(i + 0.5) < 0.85) {
        crew.cheer(feet, t, seed: i.toDouble(), face: i < 4 ? 1 : -1);
      } else {
        crew.walker(feet, face: 1, stride: 0, armF: 0.2, armB: -0.2, lean: -0.05);
      }
    }
    // The inspector (white hat) and the tour guide with her flag.
    final insp = SiteCrew(hat: BP.ink, scale: 1.3);
    final (_, hb, _) = cheer
        ? insp.cheer(const Offset(560, _g), t, seed: 9)
        : insp.walker(const Offset(560, _g), stride: 0, armB: 1.2);
    insp.flush(c);
    if (!cheer) {
      c.drawRect(Rect.fromCenter(center: hb + const Offset(-3, -4), width: 10, height: 13), strokeP(BP.amber, 1.2));
    }
    final (hand, _, _) = crew.walker(const Offset(600, _g), stride: 0, armF: 2.6 + 0.2 * math.sin(t * 3), armB: 0.2);
    final top = hand + const Offset(2, -34);
    c.drawLine(hand + const Offset(0, 4), top, strokeP(BP.ink, 1.3));
    final flag = Path()..moveTo(top.dx, top.dy);
    for (var s = 0; s <= 6; s++) {
      flag.lineTo(top.dx + 20 * s / 6, top.dy + math.sin(t * 6 - s) * 2 * s / 6);
    }
    for (var s = 6; s >= 0; s--) {
      flag.lineTo(top.dx + 20 * s / 6, top.dy + 12 + math.sin(t * 6 - s) * 2 * s / 6);
    }
    c.drawPath(flag..close(), fillP(BP.amber.withValues(alpha: 0.8)));
    // Coffee corner, as always.
    final bench = Path()
      ..moveTo(1492, _g - 14)
      ..lineTo(1572, _g - 14)
      ..moveTo(1498, _g - 14)
      ..lineTo(1498, _g)
      ..moveTo(1566, _g - 14)
      ..lineTo(1566, _g);
    c.drawPath(bench, strokeP(BP.lineDim, 1.3));
    for (final (x, face) in [(1510.0, 1.0), (1556.0, -1.0)]) {
      if (cheer) {
        crew.sitter(Offset(x, _g - 14), face: face, armF: 2.8 + 0.2 * math.sin(t * 7 + x), armB: 2.6);
      } else {
        final (h, _, _) = crew.sitter(Offset(x, _g - 14), face: face, armF: 2.2);
        c.drawRect(Rect.fromCenter(center: h, width: 4, height: 5), strokeP(BP.ink, 1.2));
        k.steam(h, x);
      }
    }
  }

  // ── Fireworks and confetti ─────────────────────────────────────────────────

  void _fireworks() {
    if (cut) {
      const every = 0.75;
      const life = 2.4;
      final t0 = m.cutAt + 0.3;
      final hi = ((t - t0) / every).floor();
      for (var n = math.max(0, hi - 4); n <= hi; n++) {
        final age = t - t0 - n * every;
        if (age < 0 || age > life) continue;
        final r1 = hash2(n.toDouble(), 3.3);
        final r2 = hash2(n + 0.7, 9.1);
        final burst = Offset(lerpD(1060, 1520, r1), lerpD(100, 290, r2));
        final launch = Offset(burst.dx + (hash1(n + 2.2) - 0.5) * 120, _g - 40);
        k.firework(launch, burst, age, n.toDouble(), _colors[n % _colors.length], radius: 60 + 40 * hash1(n + 5.5));
      }
    }
    for (final (at, p) in m.launches) {
      final age = t - at;
      if (age > 2.6) continue;
      final seed = at * 7;
      k.firework(
        Offset(p.dx + 30, _g - 40),
        p,
        age,
        seed,
        _colors[(seed * 3).floor() % _colors.length],
        climb: 0.55,
        radius: 90,
      );
    }
  }

  void _confetti() {
    if (!cut || sinceCut > 5) return;
    final u = sinceCut;
    for (var i = 0; i < 44; i++) {
      final r1 = hash2(i.toDouble(), m.cutAt);
      final r2 = hash2(i + 0.3, m.cutAt + 1);
      final vx = (r1 - 0.5) * 520;
      final vy = -260 - 320 * r2;
      final x = _cutX + vx * u * math.exp(-u * 0.8);
      final y = math.min(_g - 2, _ribbonY + vy * u + 170 * u * u);
      final spin = u * (6 + 8 * r1) + i;
      final col = _colors[i % _colors.length].withValues(alpha: 1 - seg01(u, 3.5, 5));
      c.save();
      c.translate(x + math.sin(spin) * 4, y);
      c.rotate(spin);
      c.drawRect(Rect.fromCenter(center: Offset.zero, width: 6, height: 3 * math.cos(spin).abs() + 1), fillP(col));
      c.restore();
    }
  }

  // ── Words ──────────────────────────────────────────────────────────────────

  void _text() {
    labels.draw(c, 'flutter / text', const Offset(1600 - 64, 40), size: 16, color: BP.line, ax: 1);
    const x = 104.0;
    final kv = seg01(t, 0.1, 0.6);
    c.drawLine(const Offset(x, 150), Offset(x + 28 * eo(kv), 150), strokeP(BP.amber, 1.5));
    labels.draw(
      c,
      'topping out · 竣工',
      const Offset(x + 40, 150),
      size: 16,
      color: BP.amber,
      ay: 0.5,
      alpha: kv,
      font: LabelFont.ja,
    );
    final ja = labels.get('ありがとうございました', 76, BP.ink, font: LabelFont.ja, weight: 500);
    final jv = eo(seg01(t, 0.3, 1.3));
    c.save();
    c.clipRect(Rect.fromLTWH(x - 4, 170, (ja.width + 8) * jv, ja.height + 20));
    ja.paint(c, const Offset(x, 176));
    c.restore();
    final ty = labels.get('thank you', 64, BP.ink, display: true, weight: 500);
    final tv = eo(seg01(t, 0.8, 1.6));
    c.save();
    c.clipRect(Rect.fromLTWH(x - 4, 296, (ty.width + 8) * tv, ty.height + 10));
    ty.paint(c, const Offset(x, 300));
    c.restore();
    final rv = eio(seg01(t, 1.0, 1.8));
    c.drawLine(const Offset(x, 408), Offset(x + 760 * rv, 408), strokeP(BP.lineDim, 1));
    final qv = seg01(t, 1.6, 2.2);
    final q = labels.draw(c, 'questions?', const Offset(x, 430), size: 28, color: BP.amber, alpha: qv);
    labels.draw(c, '·', Offset(x + q.width + 18, 430), size: 28, color: BP.inkDim, alpha: qv);
    labels.draw(c, 'ご質問は？', Offset(x + q.width + 52, 428), size: 28, color: BP.amber, font: LabelFont.ja, alpha: qv);
  }
}
