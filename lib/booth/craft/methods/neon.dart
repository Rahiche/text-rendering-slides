import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../../../worlds/factory/factory_kit.dart';
import '../geometry.dart';
import '../method.dart';
import '../stage.dart';
import '../workshop_layout.dart';

/// ネオン管 · Neon: a glass bender on a lift heats straight glass tubes with
/// a hand torch and bends them, tube by tube, along the glyph's centre-line
/// strokes (along its outlines when the skeleton is only a dot, like '.').
/// Then electrodes and the cable to the transformer go on, the switch is
/// thrown, and the tubes flicker on one after another into a buzzing pink
/// glow.
class NeonCraft extends CraftMethod {
  const NeonCraft();

  @override
  String get id => 'neon';

  @override
  String get en => 'Neon';

  @override
  String get ja => 'ネオン管';

  @override
  Color get color => Mat.neon;

  @override
  double get weight => 0.95;

  static final _plans = Expando<_Neon>();

  _Neon _neon(GlyphStage s) => _plans[s] ??= _Neon(s);

  // Timeline (fractions of p).
  static const _bend0 = 0.03, _bend1 = 0.74; // tubes bent one by one
  static const _wire0 = 0.75, _wire1 = 0.85; // electrodes, cable
  static const _on0 = 0.87, _on1 = 0.93; // switch thrown, tubes ignite

  /// Transformer on the floor right of the dais.
  static const _box = Rect.fromLTWH(1358, 658, 58, 42);

  @override
  void paintMaking(CraftContext x, double p) {
    final s = x.s, c = x.c;
    final n = _neon(s);
    if (n.tubes.isEmpty) return;

    // The pattern: chalk outline and dashed centre lines to bend to.
    final pattern = 1 - seg(p, _wire0, _wire1);
    if (pattern > 0) {
      c.drawPath(s.outline, x.st(BP.lineFaint.withValues(alpha: pattern), 1));
      c.drawPath(n.pattern, x.st(Mat.neon.withValues(alpha: 0.4 * pattern), 1.5));
    }

    _props(x, n, p);

    final q = seg(p, _bend0, _bend1);
    final st = n.at(q);
    if (p < _on0) {
      // Bent tubes so far, unlit glass.
      final done = Path();
      final upto = q >= 1 ? n.tubes.length : st.i;
      for (var j = 0; j < upto; j++) {
        done.addPath(n.tubes[j].path, Offset.zero);
      }
      n.glass(c, done);
    } else {
      _ignite(x, n, p);
    }
    // Electrodes: blacked-out tube ends, one after another.
    final caps = seg(p, _wire0, _wire0 + 0.6 * (_wire1 - _wire0));
    if (caps > 0) n.paintCaps(c, (caps * n.caps.length).ceil());

    // The tube being bent: glass up to the torch, hot at the bend, the
    // straight rest sticking out along the tangent.
    if (q > 0 && q < 1 && !st.moving) {
      final tube = n.tubes[st.i];
      final d = st.d;
      n.glass(c, tube.part(0, d));
      final (pos, dir) = tube.at(d);
      final rest = math.min(tube.length - d, 96.0);
      if (rest > 1) {
        final straight = Path()
          ..moveTo(pos.dx, pos.dy)
          ..lineTo(pos.dx + dir.dx * rest, pos.dy + dir.dy * rest);
        n.glass(c, straight);
      }
      final hot = math.min(d, n.w * 3.4);
      for (var k = 0; k < 3; k++) {
        n.line(
          c,
          tube.part(d - hot * (1 - k / 3), d - hot * (1 - (k + 1) / 3)),
          n.w * (1.05 + 0.08 * k),
          Color.lerp(
            Mat.molten,
            const Color(0xFFFFF4D6),
            k * 0.3,
          )!.withValues(alpha: 0.45 + 0.25 * k),
        );
      }
      x.glow(pos, n.w * 2.4, Mat.molten, alpha: 0.6);
    }

    _bender(x, n, p, q, st);
  }

  // ── Switching on ──────────────────────────────────────────────────────────

  /// Tubes ignite one after another, each stuttering for a moment.
  void _ignite(CraftContext x, _Neon n, double p) {
    final lit = Path(), dim = Path(), off = Path();
    var all = true;
    final frame = (x.t * 30).floor();
    final count = n.tubes.length;
    for (var j = 0; j < count; j++) {
      final at = _on0 + 0.004 + (_on1 - _on0 - 0.02) * (count == 1 ? 0 : j / (count - 1));
      final k = (p - at) / 0.016;
      final path = n.tubes[j].path;
      if (k < 0) {
        off.addPath(path, Offset.zero);
        all = false;
      } else if (k >= 1 || rnd(frame, j, x.seed) > 0.42) {
        lit.addPath(path, Offset.zero);
        if (k < 1) all = false;
      } else {
        dim.addPath(path, Offset.zero);
        all = false;
      }
    }
    final col = _Neon.tint(x.seed);
    if (all) {
      n.paintLit(x.c, n.all, _hum(x.t, x.seed), col);
      return;
    }
    n.glass(x.c, off);
    n.glass(x.c, dim);
    n.paintLit(x.c, dim, 0.25, col);
    n.paintLit(x.c, lit, 1, col);
  }

  /// Brightness of the lit sign: a faint mains shimmer and, every few
  /// seconds, a short stutter.
  static double _hum(double t, int seed) {
    final cycle = (t + (seed % 997) * 0.37) % 11.0;
    if (cycle < 0.22) return rnd((t * 30).floor(), seed, 5) > 0.5 ? 1 : 0.55;
    return 0.95 + 0.05 * math.sin(t * 43);
  }

  // ── The crew ──────────────────────────────────────────────────────────────

  /// The bender on a lift: torch at the bend while bending, moving to the
  /// next tube in between. Once all tubes are in, the lift comes down and the
  /// bender steps off to the side to watch the switch-on.
  void _bender(CraftContext x, _Neon n, double p, double q, _At st) {
    final s = x.s;
    Offset target;
    double standX;
    var torch = false;
    if (q >= 1) {
      final last = n.tubes.last;
      (target, standX) = n.stand(last, last.length);
    } else if (st.moving) {
      final tube = n.tubes[st.i];
      final prev = st.i == 0 ? null : n.tubes[st.i - 1];
      final to = n.stand(tube, 0);
      final from = prev == null ? to : n.stand(prev, prev.length);
      final f = eio(st.f);
      target = Offset.lerp(from.$1, to.$1, f)!;
      standX = lerp(from.$2, to.$2, f);
    } else {
      (target, standX) = n.stand(n.tubes[st.i], st.d);
      torch = q > 0;
    }
    final low = x.floorY - 16; // a lift folded right down
    final down = eio(seg(p, _bend1, _bend1 + 0.04));
    final platform = lerp(math.min(x.liftFor(target.dy), low), low, q >= 1 ? down : 0);
    x.lift(standX, platform, w: 54, col: Mat.neon);
    if (q < 1 || down < 1) {
      final feet = Offset(standX, platform - 4);
      final dir = target.dx >= standX ? 1 : -1;
      final aim = q >= 1 ? Offset.lerp(target, feet + Offset(dir * 26.0, -22), down)! : target;
      final limbs = x.reach(feet, aim, dir: dir, hat: Mat.neon);
      _goggles(x, limbs.head, dir);
      _torch(x, limbs.handA, q >= 1 ? limbs.handA + Offset(dir * 14.0, 9) : target, torch);
      return;
    }
    // Off the lift: to the nearer side of the letter, then watch and cheer.
    final walk = seg(p, _bend1 + 0.04, _bend1 + 0.1);
    final toLeft = standX < s.ink.center.dx;
    final restX = toLeft ? math.max(790.0, s.ink.left - 40) : math.min(1320.0, s.ink.right + 40);
    final fx = lerp(standX, restX, eio(walk));
    final dir = walk < 1 ? (restX >= standX ? 1 : -1) : (toLeft ? 1 : -1);
    final pose = Pose();
    if (p >= _on1) {
      pose.cheer(x.t, 1);
    } else if (walk > 0 && walk < 1) {
      pose.walk(x.t * 9);
    } else {
      pose
        ..upA = 0.3
        ..head = -0.15;
    }
    final limbs = x.worker(Offset(fx, x.floorY), dir: dir, pose: pose, hat: Mat.neon);
    _goggles(x, limbs.head, dir);
  }

  void _goggles(CraftContext x, Offset head, int dir) => x.c.drawRect(
    Rect.fromCenter(center: head + Offset(dir * 3.5, -0.5), width: 7, height: 4),
    x.fl(Mat.sumi),
  );

  void _torch(CraftContext x, Offset hand, Offset tip, bool on) {
    final c = x.c;
    final v = tip - hand;
    final dist = math.max(1.0, v.distance);
    final u = v / dist;
    final nozzle = hand + u * math.min(12.0, dist * 0.4);
    c.drawLine(hand - u * 5, nozzle, x.st(BP.inkDim, 3.6));
    c.drawLine(nozzle - u * 4, nozzle, x.st(Mat.bronze, 3));
    if (!on) return;
    final frame = (x.t * 30).floor();
    final len = math.max(16.0, (tip - nozzle).distance) * (0.95 + 0.15 * rnd(frame, 11, x.seed));
    final nn = Offset(-u.dy, u.dx);
    Path cone(double l, double r) {
      final end = nozzle + u * l;
      final mid = nozzle + u * (l * 0.4);
      return Path()
        ..moveTo(nozzle.dx + nn.dx * r, nozzle.dy + nn.dy * r)
        ..quadraticBezierTo(mid.dx + nn.dx * r * 1.4, mid.dy + nn.dy * r * 1.4, end.dx, end.dy)
        ..quadraticBezierTo(
          mid.dx - nn.dx * r * 1.4,
          mid.dy - nn.dy * r * 1.4,
          nozzle.dx - nn.dx * r,
          nozzle.dy - nn.dy * r,
        )
        ..close();
    }

    x.glow(nozzle + u * (len * 0.5), 12, const Color(0xFF6FA8FF), alpha: 0.35);
    c.drawPath(cone(len * 1.05, 6), x.fl(const Color(0xFF5B8FFF).withValues(alpha: 0.55)));
    c.drawPath(cone(len * 0.6, 3.4), x.fl(const Color(0xFF9CC4FF).withValues(alpha: 0.9)));
    c.drawPath(cone(len * 0.3, 1.8), x.fl(const Color(0xFFF2F8FF)));
  }

  /// Transformer, cable, the spare tubes and the helper who throws the switch.
  void _props(CraftContext x, _Neon n, double p) {
    final c = x.c;
    const box = _box;
    // Spare tubes leaning on the hall's column, used up as the bending goes.
    final spare = 4 - (seg(p, _bend0, _bend1) * 3.2).floor();
    for (var i = 0; i < spare; i++) {
      final bx = 1454.0 + i * 5;
      n.glass(
        c,
        Path()
          ..moveTo(bx, x.floorY - 2)
          ..lineTo(bx + 16, x.floorY - 180 + i * 8),
        w: 6,
      );
    }
    // Cable from the transformer to the first electrode.
    final wire = seg(p, _wire0 + 0.3 * (_wire1 - _wire0), _wire1);
    if (wire > 0) {
      final e = n.plug;
      final cable = Path()
        ..moveTo(box.left + 6, box.top + 8)
        ..cubicTo(box.left - 18, x.floorY + 4, e.dx + 40, x.floorY + 4, e.dx, e.dy);
      final m = cable.computeMetrics().first;
      final part = m.extractPath(0, m.length * wire);
      c.drawPath(part, x.st(const Color(0xFF151A22), 5));
      c.drawPath(part, x.st(BP.inkDim, 1.2));
    }
    // The transformer: vents, a lamp, its rating and a knife switch.
    x.ink.box(box, col: BP.inkDim, fill: const Color(0xFF1E2633));
    final kv = x.text.get('15kV', BT.mono(12, color: BP.amber, weight: 700));
    kv.paint(c, Offset(box.left + 5, box.top + 3));
    for (var i = 0; i < 3; i++) {
      final y = box.top + 22 + i * 5.0;
      c.drawLine(Offset(box.left + 6, y), Offset(box.left + 24, y), x.st(BP.lineDim, 1.2));
    }
    final bolt = Path()
      ..moveTo(box.right - 13, box.top + 18)
      ..lineTo(box.right - 20, box.top + 29)
      ..lineTo(box.right - 14, box.top + 28)
      ..lineTo(box.right - 17, box.top + 37)
      ..lineTo(box.right - 7, box.top + 24)
      ..lineTo(box.right - 13, box.top + 25)
      ..close();
    c.drawPath(bolt, x.fl(BP.amber));
    final lit = p >= _on0;
    x.ink.lamp(Offset(box.right - 8, box.top + 8), BP.green, lit, 3.5);
    // Knife switch on the side: up = off, down = on.
    final thrown = eio(seg(p, _on0 - 0.02, _on0));
    final pivot = Offset(box.right + 2, box.top + 24);
    final a = lerp(-2.0, -0.35, thrown);
    final handle = pivot + Offset(math.cos(a) * 16, math.sin(a) * 16);
    c.drawLine(pivot, handle, x.st(BP.ink, 2.4));
    c.drawCircle(handle, 3, x.fl(BP.red));
    c.drawCircle(pivot, 2.2, x.fl(BP.inkDim));
    // The helper: waits with a spare tube, wires up, throws the switch.
    const feet = Offset(1440, BW.floorY);
    if (p >= _on1) {
      x.worker(feet, dir: -1, pose: Pose()..cheer(x.t, 3), h: 48, hat: BP.coral);
    } else if (p >= _on0 - 0.04) {
      x.reach(feet, handle, dir: -1, h: 48, hat: BP.coral);
    } else if (p >= _wire0) {
      final pose = Pose()
        ..point(0.75 + 0.15 * math.sin(x.t * 7))
        ..lean = 0.3
        ..head = 0.25;
      x.worker(feet, dir: -1, pose: pose, h: 48, hat: BP.coral);
    } else {
      final pose = Pose()..carry();
      final l = x.worker(feet, dir: -1, pose: pose, h: 48, hat: BP.coral);
      n.glass(
        c,
        Path()
          ..moveTo(l.handA.dx - 30, l.handA.dy)
          ..lineTo(l.handA.dx + 22, l.handA.dy),
        w: 5,
      );
    }
    // A buzz once it's on.
    if (lit) {
      final col = _Neon.tint(x.seed);
      final hum = x.text.get(
        'ジー',
        BT.sample(16, color: col, weight: 600).copyWith(locale: jaLocale),
      );
      final j = math.sin(x.t * 60) * 0.8;
      hum.paint(c, Offset(box.left + 2 + j, box.top - 30));
      final z = Path();
      for (var k = 0; k < 2; k++) {
        final y0 = box.top - 8.0 - k * 5;
        z.moveTo(box.left + 30, y0);
        for (var m = 1; m <= 4; m++) {
          z.lineTo(box.left + 30 + m * 4, y0 + (m.isOdd ? -3 : 0) + (k == 0 ? j : -j));
        }
      }
      c.drawPath(z, x.st(col.withValues(alpha: 0.7), 1));
    }
  }

  @override
  void paintFinished(CraftContext x) {
    final n = _neon(x.s);
    if (n.tubes.isEmpty) return;
    n.paintLit(x.c, n.all, _hum(x.t, x.seed), _Neon.tint(x.seed));
    n.paintCaps(x.c, n.caps.length);
  }
}

typedef _At = ({int i, bool moving, double f, double d});

/// The tubes for one character and when each one is bent.
class _Neon {
  _Neon(GlyphStage s) {
    final r = s.typicalRadius;
    final dotty = s.strokes.isEmpty || s.strokeLength < 2.4 * r;
    if (!dotty) {
      for (final st in s.strokes) {
        final pts = _dedupe(st.pts);
        if (pts.length >= 2) tubes.add(_Poly(pts));
      }
      for (final (a, b) in missingBranches(s.geo)) {
        tubes.add(_Poly([s.map(a.dx, a.dy), s.map(b.dx, b.dy)]));
      }
    }
    if (tubes.isEmpty) {
      // Outline tubes (a dot is a ring of neon).
      for (final c in s.geo.contours) {
        final q = simplifyClosed(Float64List.fromList(c.pts), 0.3);
        final pts = _dedupe([
          for (var i = 0; i < q.length ~/ 2; i++) s.map(q[2 * i], q[2 * i + 1]),
        ]);
        if (pts.length < 3) continue;
        final smooth = _chaikin(_chaikin(pts));
        tubes.add(_Poly([...smooth, smooth.first], closed: true));
      }
    }
    w = dotty ? 13 : (r * 0.5).clamp(6.0, 15.0);
    _trimTees();
    for (final t in tubes) {
      all.addPath(t.path, Offset.zero);
    }
    _schedule();
    _caps();
    // Dashed centre lines: the pattern the tubes are bent to.
    for (final t in tubes) {
      for (var d = 0.0; d < t.length; d += 15) {
        pattern.addPath(t.part(d, d + 8), Offset.zero);
      }
    }
    _ink = s.ink;
  }

  final tubes = <_Poly>[];
  late final double w;
  final all = Path();
  final pattern = Path();
  late final Rect _ink;

  /// Blacked-out ends (electrodes): (end, a little way into the tube).
  final caps = <(Offset, Offset)>[];

  /// Where the transformer's cable plugs in.
  Offset plug = Offset.zero;

  final _start = <double>[], _bend = <double>[], _end = <double>[];
  double _span = 1;

  static List<Offset> _dedupe(List<Offset> pts) {
    final out = <Offset>[];
    for (final p in pts) {
      if (out.isEmpty || (p - out.last).distance > 0.5) out.add(p);
    }
    return out;
  }

  /// One pass of corner cutting on a closed polygon (rounds an outline).
  static List<Offset> _chaikin(List<Offset> pts) => [
    for (var i = 0; i < pts.length; i++) ...[
      Offset.lerp(pts[i], pts[(i + 1) % pts.length], 0.25)!,
      Offset.lerp(pts[i], pts[(i + 1) % pts.length], 0.75)!,
    ],
  ];

  /// A tube ending on another one's side (the bar of an 'A') stops short of
  /// it, like real neon.
  void _trimTees() {
    final gap = w * 1.25;
    for (var i = 0; i < tubes.length; i++) {
      final t = tubes[i];
      if (t.closed || t.length < 5 * gap) continue;
      var a = 0.0, b = t.length;
      for (final atStart in [true, false]) {
        final e = atStart ? t.first : t.last;
        // Joined end to end with a tube (or itself: a ring) it runs on;
        // ending on a tube's side (or its own, like the bowl of a 'g') it
        // stops short.
        var joined = ((atStart ? t.last : t.first) - e).distance < w * 1.6;
        final own = atStart
            ? t.distanceTo(e, from: 3 * gap)
            : t.distanceTo(e, to: t.length - 3 * gap);
        var touches = own < w * 0.9;
        for (var j = 0; j < tubes.length; j++) {
          if (j == i) continue;
          final o = tubes[j];
          if ((o.first - e).distance < w * 1.6 || (o.last - e).distance < w * 1.6) joined = true;
          if (o.distanceTo(e) < w * 0.9) touches = true;
        }
        if (touches && !joined) {
          if (atStart) {
            a = gap;
          } else {
            b = t.length - gap;
          }
        }
      }
      if (a > 0 || b < t.length) tubes[i] = t.trimmed(a, b);
    }
  }

  void _schedule() {
    final n = tubes.length;
    final total = tubes.fold<double>(0, (a, t) => a + t.length);
    final avg = n == 0 ? 1.0 : total / n;
    var t = 0.0;
    Offset? prev;
    for (final tube in tubes) {
      _start.add(t);
      t += 0.3 * avg + (prev == null ? 0 : 0.25 * (tube.first - prev).distance);
      _bend.add(t);
      t += math.max(tube.length, 0.3 * avg);
      _end.add(t);
      prev = tube.last;
    }
    _span = math.max(t, 1);
  }

  void _caps() {
    var best = double.negativeInfinity;
    for (var i = 0; i < tubes.length; i++) {
      final t = tubes[i];
      if (t.closed || t.length < 5 * w) continue;
      for (final atStart in [true, false]) {
        final e = atStart ? t.first : t.last;
        var shared = ((atStart ? t.last : t.first) - e).distance < w * 1.6;
        for (var j = 0; j < tubes.length && !shared; j++) {
          if (j == i || tubes[j].closed) continue;
          if ((tubes[j].first - e).distance < w * 1.6 || (tubes[j].last - e).distance < w * 1.6) {
            shared = true;
          }
        }
        if (shared) continue;
        final len = math.min(w * 0.9, t.length * 0.3);
        final (inner, _) = t.at(atStart ? len : t.length - len);
        caps.add((e, inner));
        final score = e.dy + 0.4 * e.dx;
        if (score > best) {
          best = score;
          plug = e;
        }
      }
    }
    if (best == double.negativeInfinity && tubes.isNotEmpty) {
      // No free end (rings, an '8'): plug in at the lowest point.
      plug = [for (final t in tubes) ...t.pts].reduce((a, b) => b.dy > a.dy ? b : a);
    }
  }

  /// Bending progress [q]: the tube, and whether the bender is moving to it
  /// ([f] of the way) or bending it ([d] px along).
  _At at(double q) {
    if (tubes.isEmpty) return (i: 0, moving: true, f: 0, d: 0);
    final time = q * _span;
    var i = tubes.length - 1;
    while (i > 0 && _start[i] > time) {
      i--;
    }
    if (time < _bend[i]) {
      return (i: i, moving: true, f: c01((time - _start[i]) / (_bend[i] - _start[i])), d: 0);
    }
    final f = c01((time - _bend[i]) / (_end[i] - _bend[i]));
    return (i: i, moving: false, f: 1, d: f * tubes[i].length);
  }

  /// -1: the bender works this tube from the left, 1: from the right.
  int sideOf(_Poly t) => t.at(t.length / 2).$1.dx < _ink.center.dx ? -1 : 1;

  /// The torch target and the lift's x for arc [d] of tube [t].
  (Offset, double) stand(_Poly t, double d) {
    final (pos, _) = t.at(d);
    return (pos, (pos.dx + sideOf(t) * 46).clamp(706.0, 1440.0));
  }

  // ── Drawing ───────────────────────────────────────────────────────────────

  static final _pen = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  static final _blur = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  static const _glassEdge = Color(0xFFCFE7F2);
  static const _white = Color(0xFFFFFFFF);

  void line(Canvas c, Path p, double width, Color col) {
    _pen
      ..strokeWidth = width
      ..color = col;
    c.drawPath(p, _pen);
  }

  /// Unlit glass: bright walls, dark bore, a highlight.
  void glass(Canvas c, Path p, {double? w}) {
    final ww = w ?? this.w;
    line(c, p, ww, _glassEdge.withValues(alpha: 0.8));
    line(c, p, ww * 0.5, BP.paper.withValues(alpha: 0.7));
    line(c, p, math.max(1, ww * 0.16), _white.withValues(alpha: 0.75));
  }

  /// The gas colour for a character: mostly pink, sometimes amber.
  static Color tint(int seed) => seed % 3 == 2 ? const Color(0xFFFFB347) : Mat.neon;

  /// Lit neon: a soft blurred halo under a bright tube and a white-hot core.
  void paintLit(Canvas c, Path p, double a, Color col) {
    _blur
      ..strokeWidth = w * 3.2
      ..color = col.withValues(alpha: 0.55 * a)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 1.25);
    c.drawPath(p, _blur);
    line(c, p, w * 1.8, col.withValues(alpha: 0.35 * a));
    line(c, p, w, Color.lerp(col, _white, 0.3)!.withValues(alpha: a));
    line(c, p, w * 0.42, Color.lerp(col, _white, 0.85)!.withValues(alpha: a));
  }

  /// The first [n] blacked-out ends.
  void paintCaps(Canvas c, int n) {
    if (n <= 0) return;
    final p = Path();
    for (var k = 0; k < math.min(n, caps.length); k++) {
      final (e, inner) = caps[k];
      p
        ..moveTo(e.dx, e.dy)
        ..lineTo(inner.dx, inner.dy);
    }
    line(c, p, w * 1.12, const Color(0xFF262A33));
    line(c, p, math.max(1, w * 0.2), const Color(0xFF59606E));
  }
}

/// A polyline with arc lengths.
class _Poly {
  _Poly(this.pts, {this.closed = false}) {
    arc.add(0);
    for (var i = 1; i < pts.length; i++) {
      arc.add(arc.last + (pts[i] - pts[i - 1]).distance);
    }
    path.moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
  }

  final List<Offset> pts;
  final bool closed;
  final arc = <double>[];
  final path = Path();

  double get length => arc.last;
  Offset get first => pts.first;
  Offset get last => pts.last;

  /// Position and direction at arc length [d].
  (Offset, Offset) at(double d) {
    if (pts.length == 1) return (pts.first, const Offset(1, 0));
    d = d.clamp(0.0, length);
    var i = 1;
    while (i < pts.length - 1 && arc[i] < d) {
      i++;
    }
    final l = arc[i] - arc[i - 1];
    final f = l <= 0 ? 0.0 : (d - arc[i - 1]) / l;
    final v = pts[i] - pts[i - 1];
    final n = v.distance;
    return (Offset.lerp(pts[i - 1], pts[i], f)!, n == 0 ? const Offset(1, 0) : v / n);
  }

  /// The part between arc lengths [a] and [b].
  Path part(double a, double b) {
    a = a.clamp(0.0, length);
    b = b.clamp(a, length);
    final (pa, _) = at(a);
    final out = Path()..moveTo(pa.dx, pa.dy);
    for (var i = 1; i < pts.length; i++) {
      if (arc[i] <= a) continue;
      if (arc[i] >= b) break;
      out.lineTo(pts[i].dx, pts[i].dy);
    }
    final (pb, _) = at(b);
    return out..lineTo(pb.dx, pb.dy);
  }

  _Poly trimmed(double a, double b) {
    final (pa, _) = at(a);
    final (pb, _) = at(b);
    return _Poly([
      pa,
      for (var i = 1; i < pts.length - 1; i++)
        if (arc[i] > a && arc[i] < b) pts[i],
      pb,
    ]);
  }

  /// Distance from [p] to the polyline (only its part between arc lengths
  /// [from] and [to]).
  double distanceTo(Offset p, {double from = 0, double to = double.infinity}) {
    var best = double.infinity;
    for (var i = 1; i < pts.length; i++) {
      if (arc[i] < from || arc[i - 1] > to) continue;
      final a = pts[i - 1], b = pts[i];
      final ab = b - a;
      final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
      final f = l2 == 0 ? 0.0 : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / l2).clamp(0.0, 1.0);
      best = math.min(best, (p - (a + ab * f)).distance);
    }
    return best;
  }
}

/// Parts of the glyph the skeleton lost (a short crossbar like the one of
/// an 'f' or 't', the foot of a '4', can be pruned as spurs): rebuild the
/// glyph from the strokes' disks; for each region left uncovered that
/// reaches out from a stroke (not just the corner of a stroke's end), a
/// straight arm (raster px) from the stroke into it, along the direction
/// it reaches furthest; repeat with the arms added (an L-shaped leftover
/// gives two arms). Two arms on either side of a stroke become one bar.
List<(Offset, Offset)> missingBranches(GlyphGeometry g) {
  final w = g.w, h = g.h;
  final inside = Uint8List(w * h);
  for (final sp in g.spans) {
    inside.fillRange(sp.y * w + sp.x0, sp.y * w + sp.x1, 1);
  }
  final covered = Uint8List(w * h);
  // Skeleton samples about a pixel apart: x, y, radius, stroke's median
  // radius.
  final samples = <(double, double, double, double)>[];
  void disk(double x, double y, double r) {
    final rr = r + 1;
    for (var py = math.max(0, (y - rr).floor()); py <= math.min(h - 1, (y + rr).ceil()); py++) {
      for (var px = math.max(0, (x - rr).floor()); px <= math.min(w - 1, (x + rr).ceil()); px++) {
        final dx = px + 0.5 - x, dy = py + 0.5 - y;
        if (dx * dx + dy * dy <= rr * rr) covered[py * w + px] = 1;
      }
    }
  }

  void line(double x0, double y0, double r0, double x1, double y1, double r1, double med) {
    final n = math.max(1, math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)).ceil());
    for (var k = 1; k <= n; k++) {
      final f = k / n;
      final s = (x0 + (x1 - x0) * f, y0 + (y1 - y0) * f, r0 + (r1 - r0) * f, med);
      samples.add(s);
      disk(s.$1, s.$2, s.$3);
    }
  }

  for (final st in g.strokes) {
    final med = ([...st.radius]..sort())[st.count ~/ 2];
    samples.add((st.pts[0], st.pts[1], st.radius[0], med));
    disk(st.pts[0], st.pts[1], st.radius[0]);
    for (var i = 1; i < st.count; i++) {
      line(
        st.pts[2 * i - 2],
        st.pts[2 * i - 1],
        st.radius[i - 1],
        st.pts[2 * i],
        st.pts[2 * i + 1],
        st.radius[i],
        med,
      );
    }
  }
  if (samples.isEmpty) return const [];
  final dirs = [
    for (var a = 0; a < 8; a++) Offset(math.cos(a * math.pi / 4), math.sin(a * math.pi / 4)),
  ];
  final arms = <(Offset, Offset, double)>[]; // root, tip, root's median radius
  final seen = Uint8List(w * h);
  final stack = <int>[];
  for (var round = 0; round < 4; round++) {
    seen.fillRange(0, w * h, 0);
    final found = <(Offset, Offset, double)>[];
    for (var start = 0; start < w * h; start++) {
      if (inside[start] == 0 || covered[start] == 1 || seen[start] == 1) continue;
      // One uncovered region.
      final region = <int>[];
      seen[start] = 1;
      stack.add(start);
      while (stack.isNotEmpty) {
        final i = stack.removeLast();
        region.add(i);
        final x = i % w;
        for (final j in [if (x > 0) i - 1, if (x < w - 1) i + 1, i - w, i + w]) {
          if (j >= 0 && j < w * h && inside[j] == 1 && covered[j] == 0 && seen[j] == 0) {
            seen[j] = 1;
            stack.add(j);
          }
        }
      }
      if (region.length < 8) continue;
      // Rooted at the skeleton point nearest its centroid...
      var cx = 0.0, cy = 0.0;
      for (final i in region) {
        cx += i % w + 0.5;
        cy += i ~/ w + 0.5;
      }
      final centroid = Offset(cx / region.length, cy / region.length);
      var root = samples.first;
      var bestD = double.infinity;
      for (final sm in samples) {
        final d = (centroid - Offset(sm.$1, sm.$2)).distanceSquared;
        if (d < bestD) {
          bestD = d;
          root = sm;
        }
      }
      final r = root.$4;
      if (region.length < 0.6 * r * r) continue;
      final rootPt = Offset(root.$1, root.$2);
      // ...reaching out furthest along one direction (one of eight, or
      // towards the centroid), within a stroke's width of it.
      final toC = centroid - rootPt;
      var bestU = Offset.zero;
      var reach = 0.0;
      for (final u in [...dirs, if (toC.distance > 1e-6) toC / toC.distance]) {
        var ext = 0.0;
        for (final i in region) {
          final p = Offset(i % w + 0.5, i ~/ w + 0.5) - rootPt;
          final along = p.dx * u.dx + p.dy * u.dy;
          if (along > ext && (p.dx * u.dy - p.dy * u.dx).abs() <= r) ext = along;
        }
        if (ext > reach) {
          reach = ext;
          bestU = u;
        }
      }
      // Leftovers at a stroke's end or corner don't reach this far.
      if (reach < 1.8 * r) continue;
      // End the arm about a stroke radius short of the tip, like strokes.
      found.add((rootPt, rootPt + bestU * math.max(r, reach - r * 0.9), r));
    }
    if (found.isEmpty) break;
    for (final (a, b, r) in found) {
      line(a.dx, a.dy, r, b.dx, b.dy, r, r);
    }
    arms.addAll(found);
  }
  final out = <(Offset, Offset)>[];
  final used = <int>{};
  for (var i = 0; i < arms.length; i++) {
    if (used.contains(i)) continue;
    final (a, b, r) = arms[i];
    var merged = false;
    for (var j = i + 1; j < arms.length && !merged; j++) {
      if (used.contains(j)) continue;
      final (a2, b2, _) = arms[j];
      final u1 = b - a, u2 = b2 - a2;
      final cos = (u1.dx * u2.dx + u1.dy * u2.dy) / (u1.distance * u2.distance);
      if ((a - a2).distance < 2.5 * r && cos < -0.85) {
        out.add(b.dx <= b2.dx ? (b, b2) : (b2, b));
        used.add(j);
        merged = true;
      }
    }
    if (!merged) out.add((a, b));
  }
  return out;
}
