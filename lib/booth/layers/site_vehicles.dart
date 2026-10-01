import 'dart:math' as math;
import 'dart:ui';

import '../../deck/theme.dart';
import '../../worlds/factory/factory_kit.dart' show FactoryInk, TextCache;
import '../layout.dart';
import 'site_plan.dart';
import 'site_rubble.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Cleanup machines: a tracked loader (bulldozer with a lifting bucket) that
// pushes the rubble into a pile and lifts it into the dump truck, and the
// truck that backs up to the factory and pours the bricks into its hopper.
// Both are keyframed when their phase starts, so they also drive on into the
// next name's intake.
// ─────────────────────────────────────────────────────────────────────────────

/// Eased keyframes of one value.
class Track {
  final _t = <double>[];
  final _v = <double>[];

  void key(double t, double v) {
    if (_t.isNotEmpty && t < _t.last) t = _t.last;
    _t.add(t);
    _v.add(v);
  }

  bool get isEmpty => _t.isEmpty;
  double get first => _t.isEmpty ? 0 : _t.first;
  double get last => _t.isEmpty ? 0 : _t.last;

  double at(double t) {
    if (_t.isEmpty) return 0;
    if (t <= _t.first) return _v.first;
    if (t >= _t.last) return _v.last;
    var i = 0;
    while (i < _t.length - 2 && _t[i + 1] <= t) {
      i++;
    }
    final a = _t[i], b = _t[i + 1];
    return mix(_v[i], _v[i + 1], eio(b <= a ? 1 : (t - a) / (b - a)));
  }

  void clear() {
    _t.clear();
    _v.clear();
  }
}

/// Where the truck's wheels touch the road.
const truckLane = 778.0;

/// Pile point: the loader's blade stops here; the truck loads beside it.
const pileX = 776.0;
const truckLoadX = pileX + 43;

/// The truck backs up until its rear lip is over the factory's hopper.
const truckDumpX = 240.0;

class Loader {
  final x = Track(); // blade front
  final lift = Track(); // 0 bucket on the ground … 1 raised
  final tip = Track(); // 0 level … 1 dumped
  double from = double.infinity, to = double.negativeInfinity;
  double pushFrom = 0, pushTo = 0, scoopAt = 0, dumpAt = 0;
  bool scooped = false, dumped = false;

  bool visible(double t) => t >= from && t <= to;

  static const _pivot = Offset(52, -32);

  /// The bucket's hinge, relative to the blade front on the ground.
  static Offset hinge(double lift) {
    final a = mix(2.66, 3.84, lift);
    return _pivot + Offset(math.cos(a), math.sin(a)) * 40;
  }

  static double tipAngle(double tip) => -1.7 * tip;

  /// Floor centre of the bucket in world space.
  Offset bucketFloor(double t) {
    final bx = x.at(t);
    final h = hinge(lift.at(t));
    final a = tipAngle(tip.at(t));
    final local = const Offset(-9, 11);
    final r = Offset(local.dx * math.cos(a) - local.dy * math.sin(a), local.dx * math.sin(a) + local.dy * math.cos(a));
    return Offset(bx, BL.groundY) + h + r;
  }

  void draw(FactoryInk ink, double t, {List<Offset>? bucketPieces}) {
    if (!visible(t)) return;
    final c = ink.c;
    final x0 = x.at(t);
    const g = BL.groundY;
    final travel = x0;
    // Tracks with road wheels.
    final tracks = RRect.fromLTRBR(x0 + 34, g - 16, x0 + 98, g, const Radius.circular(8));
    c.drawRRect(tracks, ink.fl(BP.paper));
    c.drawRRect(tracks, ink.st(BP.line, 1.3));
    for (final wx in [42.0, 56.0, 70.0, 84.0, 91.0]) {
      final w = Offset(x0 + wx, g - 8);
      c.drawCircle(w, wx == 91 ? 4 : 5, ink.st(BP.lineDim, 1));
      final a = -travel / 5;
      c.drawLine(w, w + Offset(math.cos(a), math.sin(a)) * 4, ink.st(BP.lineDim, 1));
    }
    // Body, grille, cab with driver.
    final body = Rect.fromLTRB(x0 + 40, g - 40, x0 + 96, g - 16);
    c.drawRect(body, ink.fl(BP.panel));
    c.drawRect(body, ink.st(BP.amber, 1.3));
    for (var i = 0; i < 3; i++) {
      c.drawLine(Offset(x0 + 84, g - 35 + i * 6.0), Offset(x0 + 93, g - 35 + i * 6.0), ink.st(BP.lineDim, 1));
    }
    final cab = Path()
      ..moveTo(x0 + 60, g - 40)
      ..lineTo(x0 + 64, g - 66)
      ..lineTo(x0 + 88, g - 66)
      ..lineTo(x0 + 90, g - 40);
    c.drawPath(cab, ink.fl(BP.panel));
    c.drawPath(cab, ink.st(BP.amber, 1.3));
    c.drawRect(Rect.fromLTRB(x0 + 66, g - 62, x0 + 86, g - 46), ink.st(BP.lineDim, 1));
    final head = Offset(x0 + 74, g - 52);
    c.drawCircle(head, 3.4, ink.fl(BP.paper));
    c.drawCircle(head, 3.4, ink.st(BP.ink, 1.2));
    c.drawArc(Rect.fromCircle(center: head + const Offset(0, -0.8), radius: 4.2), math.pi, math.pi, true, ink.fl(BP.amber));
    // Exhaust.
    c.drawLine(Offset(x0 + 50, g - 40), Offset(x0 + 50, g - 54), ink.st(BP.lineDim, 2));
    ink.steam(Offset(x0 + 50, g - 56), t, per: 0.35, life: 1.4, rise: 26, r: 5, drift: 14, seed: 3);
    // Arms and bucket.
    final lf = lift.at(t);
    final pivot = Offset(x0, g) + _pivot;
    final h = Offset(x0, g) + hinge(lf);
    c.drawLine(pivot, h, ink.st(BP.line, 3.2));
    c.drawLine(pivot, h, ink.st(BP.paper, 1.2));
    c.drawCircle(pivot, 2.6, ink.st(BP.line, 1.2));
    // Hydraulic ram.
    c.drawLine(Offset(x0 + 62, g - 22), Offset.lerp(pivot, h, 0.55)!, ink.st(BP.lineDim, 1.6));
    c.save();
    c.translate(h.dx, h.dy);
    c.rotate(tipAngle(tip.at(t)));
    final bucket = Path()
      ..moveTo(3, -9)
      ..lineTo(1, 13)
      ..lineTo(-17, 13)
      ..lineTo(-21, 3)
      ..lineTo(-17, 4)
      ..lineTo(-14, 9)
      ..lineTo(-2, 9)
      ..lineTo(-1, -9)
      ..close();
    c.drawPath(bucket, ink.fl(BP.panel));
    c.drawPath(bucket, ink.st(BP.amber, 1.4));
    c.restore();
  }
}

class Truck implements BedFrame {
  final x = Track();
  final tilt = Track();
  double from = double.infinity, to = double.negativeInfinity;
  double reverseFrom = 0, reverseTo = 0, pourFrom = 0, pourTo = 0;

  bool visible(double t) => t >= from && t <= to;

  double angle(double t) => 0.72 * tilt.at(t);

  Offset pivot(double t) => Offset(x.at(t) - 90, truckLane - 14);

  @override
  Offset world(double t, double bx, double by) {
    final a = angle(t);
    final p = pivot(t);
    final ca = math.cos(a), sa = math.sin(a);
    return p + Offset(bx * ca - by * sa, -bx * sa - by * ca);
  }

  @override
  Offset lip(double t) => world(t, 2, 3);

  /// Body (cab, chassis, wheels). The load and the bed's side are drawn
  /// around it by [bed].
  void body(FactoryInk ink, double t, TextCache text) {
    final c = ink.c;
    final x0 = x.at(t);
    const y0 = truckLane;
    Offset p(double lx, double ly) => Offset(x0 + lx, y0 + ly);
    final ln = ink.st(BP.line, 1.3);
    final cab = Path()
      ..moveTo(x0 + 30, y0 - 12)
      ..lineTo(x0 + 30, y0 - 42)
      ..lineTo(x0 + 48, y0 - 42)
      ..lineTo(x0 + 63, y0 - 27)
      ..lineTo(x0 + 63, y0 - 12)
      ..close();
    c.drawPath(cab, ink.fl(BP.paper));
    c.drawPath(cab, ln);
    c.drawPath(
      Path()
        ..moveTo(x0 + 34, y0 - 38)
        ..lineTo(x0 + 47, y0 - 38)
        ..lineTo(x0 + 58, y0 - 28)
        ..lineTo(x0 + 34, y0 - 28)
        ..close(),
      ink.st(BP.lineDim, 1),
    );
    final head = p(42, -31);
    c.drawCircle(head, 3.4, ink.fl(BP.paper));
    c.drawCircle(head, 3.4, ink.st(BP.ink, 1.2));
    c.drawArc(Rect.fromCircle(center: head + const Offset(0, -0.8), radius: 4.2), math.pi, math.pi, true, ink.fl(BP.amber));
    c.drawLine(p(-90, -12), p(63, -12), ln);
    // Tipping ram.
    final a = angle(t);
    if (a > 0.01) {
      c.drawLine(p(-30, -12), world(t, 70, 0), ink.st(BP.lineDim, 2.2));
    }
  }

  /// Beeper while backing up: 「バックします」 ("backing up").
  void beeper(FactoryInk ink, double t, TextCache text) {
    if (t <= reverseFrom || t >= reverseTo) return;
    final on = ((t - reverseFrom) * 2.2) % 1.0 < 0.6;
    if (!on) return;
    final tp = text.get(
      'バックします ♪',
      BT.sample(12, color: BP.amber, weight: 500).copyWith(locale: const Locale('ja')),
    );
    tp.paint(ink.c, Offset(x.at(t) + 26, truckLane - 44 - tp.height));
  }

  /// The bed (rotating about its rear lip); [load] paints the pieces in it
  /// before the near side panel goes over them.
  void bed(FactoryInk ink, double t, TextCache text, void Function() load) {
    final c = ink.c;
    final pv = pivot(t);
    final a = angle(t);
    c.save();
    c.translate(pv.dx, pv.dy);
    c.rotate(-a);
    // Far side (inside of the bed).
    const inside = Rect.fromLTRB(-2, -32, 114, 0);
    c.drawRect(inside, ink.fl(BP.panel));
    c.restore();
    load();
    c.save();
    c.translate(pv.dx, pv.dy);
    c.rotate(-a);
    final side = Path()
      ..moveTo(-2, -32)
      ..lineTo(114, -32)
      ..lineTo(114, 0)
      ..lineTo(6, 0)
      ..close();
    c.drawPath(side, ink.fl(BP.paper));
    c.drawPath(side, ink.st(BP.line, 1.3));
    c.drawLine(const Offset(10, -24), const Offset(108, -24), ink.st(BP.lineDim, 1));
    final label = text.get(
      '再生 RECYCLE',
      BT.mono(10, color: BP.green, weight: 600).copyWith(fontFamilyFallback: const ['Hiragino Sans']),
    );
    label.paint(c, Offset(58 - label.width / 2, -18));
    c.restore();
    for (final wx in const [-70.0, -52.0, 44.0]) {
      final w = Offset(x.at(t) + wx, truckLane - 7);
      c.drawCircle(w, 7, ink.fl(BP.paper));
      c.drawCircle(w, 7, ink.st(BP.line, 1.2));
      final r = x.at(t) / 7;
      c.drawLine(w, w + Offset(math.cos(r), math.sin(r)) * 6, ink.st(BP.lineDim, 1));
    }
  }
}
