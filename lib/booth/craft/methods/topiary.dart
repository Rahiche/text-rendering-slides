import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../../../worlds/factory/factory_kit.dart';
import '../geometry.dart';
import '../method.dart';
import '../stage.dart';

/// 植木 · Topiary: a hedge grows into a full block on the dais; the niwashi
/// (gardener, straw hat) climbs a stepladder and follows the letter's
/// outlines with big shears: every clump of leaves beyond the edge he
/// passes is snipped off and flutters to the floor, so the bush shrinks to
/// the letter. A helper sweeps the clippings; the gardener waters it.
class TopiaryCraft extends CraftMethod {
  const TopiaryCraft();

  @override
  String get id => 'topiary';

  @override
  String get en => 'Topiary';

  @override
  String get ja => '植木';

  @override
  Color get color => Mat.leaf;

  @override
  double get weight => 1.0;

  static final _hedges = Expando<_Hedge>();
  static final _leaves = Expando<_Leaves>();

  static _Hedge _hedge(CraftContext x) => _hedges[x.s] ??= _Hedge(x.s, x.seed, x.daisY);
  static _Leaves _leafy(GlyphStage s, int seed) => _leaves[s] ??= _Leaves(s, seed);

  // Timeline (fractions of p).
  static const _growEnd = 0.07;
  static const _trimStart = 0.09, _trimEnd = 0.88;
  static const _waterStart = 0.9;

  /// How long a snipped clump's leaves flutter down.
  static const _fall = 0.06;

  @override
  void paintMaking(CraftContext x, double p) {
    final s = x.s;
    if (s.contours.isEmpty) return;
    final h = _hedge(x);
    final c = x.c;
    p = p.clamp(0.0, 1.0);
    // Trimming progress: the shears' place along the schedule (0..1); every
    // clump whose nearest outline point they've passed is gone.
    final trim = seg(p, _trimStart, _trimEnd);

    // The bush grows up from the dais first.
    final grow = eo(seg(p, 0, _growEnd));
    if (grow < 1) {
      c.save();
      c.clipRect(Rect.fromLTRB(h.r.left - 30, lerp(x.daisY, h.r.top - 24, grow), h.r.right + 30, x.daisY + 2));
    }
    // Shadow layer, then leaves, of the clumps not yet snipped.
    final shade = Path(), body = Path();
    final dark = <Offset>[], mid = <Offset>[], light = <Offset>[];
    for (final k in h.clumps) {
      if (k.u <= trim) continue;
      shade.addOval(Rect.fromCircle(center: k.c + const Offset(1.5, 2.5), radius: k.r));
      body.addOval(Rect.fromCircle(center: k.c, radius: k.r - 0.5));
      for (var i = 0; i < k.dots.length; i++) {
        (i < 2 ? dark : (i < 4 ? mid : light)).add(k.c + k.dots[i]);
      }
    }
    // The letter's own shade first, so it only shows where it's trimmed.
    c.save();
    c.translate(1.5, 2.5);
    c.drawPath(s.outline, x.fl(_leafDark));
    c.restore();
    c.drawPath(shade, x.fl(_leafDark));
    c.drawPath(body, x.fl(_leafMid));
    c.drawPath(s.outline, x.fl(_leafMid));
    _foliage(x);
    c.drawPoints(ui.PointMode.points, dark, x.st(_leafDark, 4.2));
    c.drawPoints(ui.PointMode.points, mid, x.st(Mat.leaf, 3.6));
    c.drawPoints(ui.PointMode.points, light, x.st(_leafLight, 2.6));
    // The edge the shears have cut so far is crisp.
    c.drawPath(s.outlineUpTo(h.outlineFrac(trim)), x.st(_leafEdge, 1.6));
    if (grow < 1) c.restore();

    // Clippings fluttering to the floor (and lying there until swept).
    _clippings(x, h, p);

    if (p < _trimEnd + 0.01) {
      _gardener(x, h, trim, p);
    } else {
      _watering(x, h, p);
    }
    _sweeper(x, h, p);
  }

  @override
  void paintFinished(CraftContext x) {
    final s = x.s, c = x.c;
    if (s.contours.isEmpty) return;
    c.save();
    c.translate(1.5, 2.5);
    c.drawPath(s.outline, x.fl(_leafDark));
    c.restore();
    c.drawPath(s.outline, x.fl(_leafMid));
    _foliage(x);
    c.drawPath(s.outline, x.st(_leafEdge, 1.6));
  }

  /// Leaf texture inside the letter.
  void _foliage(CraftContext x) {
    final f = _leafy(x.s, x.seed);
    x.c.drawPoints(ui.PointMode.points, f.dark, x.st(_leafDark, 4.2));
    x.c.drawPoints(ui.PointMode.points, f.mid, x.st(Mat.leaf, 3.6));
    x.c.drawPoints(ui.PointMode.points, f.light, x.st(_leafLight, 2.6));
  }

  /// Where the helper's broom is (it sweeps left to right late in the job).
  static double _broomX(_Hedge h, double p) {
    final swept = seg(p, 0.6, 0.97);
    return swept <= 0 ? math.max(800.0, h.r.left - 24) : lerp(h.r.left - 4, h.r.right + 46, swept);
  }

  void _clippings(CraftContext x, _Hedge h, double p) {
    final c = x.c;
    final broom = _broomX(h, p);
    final floor = x.daisY;
    var pile = 0;
    final light = Path(), dark = Path();
    for (final k in h.clumps) {
      final t0 = h.cutTime(k);
      if (t0 > p) continue;
      final age = (p - t0) / _fall;
      for (var i = 0; i < 2; i++) {
        final seedI = k.seed * 2 + i;
        final vx = (rnd(seedI, 1) - 0.5) * 60 + k.out.dx * 50;
        final vy = -20 - 50 * rnd(seedI, 2);
        final fallTo = floor - 2 - 4 * rnd(seedI, 3);
        final tau = math.min(age, 1.0);
        var at = k.c + Offset(vx * tau + 6 * math.sin(tau * 9 + i), vy * tau + 420 * tau * tau);
        if (at.dy > fallTo) at = Offset(at.dx, fallTo);
        if (age >= 1 && at.dx < broom + 4) {
          pile++; // pushed along in front of the broom
          continue;
        }
        _leaf(i == 0 ? light : dark, at, tau * 8 + i);
      }
    }
    if (pile > 0) {
      // The heap of clippings in front of the broom.
      final w = math.min(40.0, 8 + math.sqrt(pile) * 2.2);
      final hgt = math.min(16.0, 3 + math.sqrt(pile) * 0.9);
      final heap = Rect.fromLTWH(broom + 4, floor - hgt, w, hgt * 2);
      c.drawArc(heap, math.pi, math.pi, true, x.fl(_leafDark));
      for (var i = 0; i < math.min(pile, 14); i++) {
        _leaf(light, Offset(heap.left + w * rnd(i, 5), floor - hgt * 0.8 * rnd(i, 6)), i * 1.3);
      }
    }
    c.drawPath(dark, x.fl(_leafDark));
    c.drawPath(light, x.fl(Mat.leaf));
  }

  /// Adds a small leaf at [at], turned [a], to [into].
  void _leaf(Path into, Offset at, double a) {
    final d = Offset(math.cos(a), math.sin(a)) * 4.5;
    final n = Offset(-d.dy, d.dx) * 0.45;
    into
      ..moveTo(at.dx - d.dx, at.dy - d.dy)
      ..quadraticBezierTo(at.dx + n.dx, at.dy + n.dy, at.dx + d.dx, at.dy + d.dy)
      ..quadraticBezierTo(at.dx - n.dx, at.dy - n.dy, at.dx - d.dx, at.dy - d.dy)
      ..close();
  }

  /// The niwashi on a stepladder, shears at the point being trimmed.
  void _gardener(CraftContext x, _Hedge h, double trim, double p) {
    final (tip, side) = h.shears(trim);
    // Stand beside the cut, on the contour's own side (smoothly between).
    final standX = (tip.dx + side * 44).clamp(700.0, 1470.0);
    final top = math.min(x.floorY, tip.dy + 0.72 * 50 + 4);
    _ladder(x, standX, top);
    // While the hedge grows, the gardener climbs up to the first cut.
    final climb = eio(seg(p, 0.02, _trimStart));
    final feetY = lerp(x.floorY, top, climb);
    final dir = tip.dx >= standX ? 1 : -1;
    final shoulder = Offset(standX, feetY - 39);
    final mid = shoulder + (tip - shoulder) * 0.45;
    final pose = Pose();
    if (climb < 1) {
      pose
        ..walk(climb * 14, amp: 0.5)
        ..upA = 2.5
        ..foA = 2.7
        ..upB = 2.3
        ..foB = 2.6;
    } else {
      // Both hands out towards the cut.
      final v = mid - shoulder;
      final a = math.atan2(v.dx * dir, v.dy).clamp(-0.3, 3.0);
      pose
        ..point(a)
        ..upB = a - 0.15
        ..foB = a - 0.05;
    }
    final limbs = _niwashi(x, Offset(standX, feetY), dir, pose);
    if (climb < 1) {
      // Shears carried on the back.
      x.c.drawLine(limbs.hip + const Offset(-8, -4), limbs.head + const Offset(10, 4), x.st(Mat.steel, 2.4));
      return;
    }
    _shears(x, limbs.handA, tip, p < _trimEnd && p > _trimStart);
  }

  void _ladder(CraftContext x, double lx, double feetY) {
    final floor = x.floorY;
    if (feetY > floor - 8) return;
    final c = x.c;
    final top = feetY;
    final spread = 10 + (floor - top) * 0.12;
    final col = x.st(Mat.wood, 2.6);
    c.drawLine(Offset(lx - 6, top), Offset(lx - spread, floor), col);
    c.drawLine(Offset(lx + 6, top), Offset(lx + spread, floor), col);
    final rungs = Path();
    for (var y = top + 14.0; y < floor - 4; y += 16) {
      final f = (y - top) / (floor - top);
      final w = lerp(6, spread, f);
      rungs
        ..moveTo(lx - w, y)
        ..lineTo(lx + w, y);
    }
    c.drawPath(rungs, x.st(Mat.woodDark, 1.8));
    c.drawLine(Offset(lx - 9, top), Offset(lx + 9, top), x.st(Mat.woodDark, 3));
  }

  /// The gardener: no hard hat, a conical straw hat (kasa) instead.
  Limbs _niwashi(CraftContext x, Offset feet, int dir, Pose pose) {
    final l = x.ink.worker(feet, 50, dir, pose, helmet: false);
    final head = l.head;
    final hat = Path()
      ..moveTo(head.dx - 13, head.dy - 3)
      ..lineTo(head.dx, head.dy - 13)
      ..lineTo(head.dx + 13, head.dy - 3)
      ..close();
    x.c.drawPath(hat, x.fl(_straw));
    x.c.drawPath(hat, x.st(_strawDark, 1.1));
    x.c.drawLine(Offset(head.dx - 6, head.dy - 8), Offset(head.dx + 6, head.dy - 8), x.st(_strawDark, 0.8));
    return l;
  }

  /// Hedge shears: two long blades from a pivot near the hands to [tip],
  /// snipping open and shut.
  void _shears(CraftContext x, Offset hand, Offset tip, bool snipping) {
    final c = x.c;
    final d = tip - hand;
    final len = d.distance;
    if (len < 1) return;
    final u = d / len;
    final pivot = hand + u * math.min(14, len * 0.35);
    final open = snipping ? 0.12 + 0.2 * (0.5 + 0.5 * math.sin(x.t * 26)) : 0.05;
    final bl = math.max(18.0, (tip - pivot).distance + 6);
    for (final sgn in [-1.0, 1.0]) {
      final a = math.atan2(u.dy, u.dx) + sgn * open;
      final end = pivot + Offset(math.cos(a), math.sin(a)) * bl;
      c.drawLine(pivot, end, x.st(Mat.steel, 2.6));
      c.drawLine(hand + Offset(-u.dy, u.dx) * sgn * 3, pivot, x.st(Mat.wood, 2.8));
    }
    c.drawCircle(pivot, 2.2, x.fl(Mat.steelDark));
  }

  /// After trimming: down on the floor with a watering can.
  void _watering(CraftContext x, _Hedge h, double p) {
    final c = x.c;
    final s = x.s;
    final feet = Offset(math.min(1440.0, s.ink.right + 46), x.floorY);
    final tilt = eio(seg(p, _waterStart, _waterStart + 0.03)) * (1 - seg(p, 0.985, 1));
    final pose = Pose()
      ..upA = 1.1 + 0.35 * tilt
      ..foA = 1.5 + 0.3 * tilt;
    final l = _niwashi(x, feet, -1, pose);
    // The can (a jouro), its spout rose tipping down to the roots.
    final can = Rect.fromCenter(center: l.handA + const Offset(-9, 6), width: 18, height: 13);
    c.drawRect(can, x.fl(Mat.steelDark));
    c.drawRect(can, x.st(Mat.steel, 1.2));
    c.drawArc(Rect.fromLTWH(can.left + 3, can.top - 7, 12, 12), math.pi, math.pi, false, x.st(Mat.steel, 1.4));
    final spout = can.centerLeft + Offset(-14, -6 - 6 * tilt);
    c.drawLine(can.centerLeft, spout, x.st(Mat.steel, 2.2));
    c.drawCircle(spout, 2.4, x.fl(Mat.steel));
    if (tilt > 0.5) {
      final frame = x.t * 2.5;
      final fall = x.daisY - 2 - spout.dy;
      final drops = <Offset>[];
      for (var i = 0; i < 18; i++) {
        final u = (frame + i / 18) % 1;
        drops.add(spout + Offset(-34 * u + 6 * (rnd(i, 2) - 0.5), -4 * u + (fall + 4) * u * u));
      }
      c.drawPoints(ui.PointMode.points, drops, x.st(_water, 3.2));
      // Splashes at the roots.
      final base = spout + Offset(-34, fall);
      for (var i = 0; i < 3; i++) {
        final k = (x.t * 3 + i / 3) % 1;
        c.drawArc(
          Rect.fromCenter(center: base + Offset((i - 1) * 7.0, 0), width: 6 + 10 * k, height: 3 + 4 * k),
          math.pi,
          math.pi,
          false,
          x.st(_water.withValues(alpha: 1 - k), 1.2),
        );
      }
    }
  }

  /// A helper with a broom: sweeps the clippings off the dais.
  void _sweeper(CraftContext x, _Hedge h, double p) {
    if (p < 0.12) return;
    final broom = _broomX(h, p);
    final pose = Pose()
      ..upA = 1.0
      ..foA = 1.25 + 0.2 * math.sin(x.t * 9)
      ..upB = 0.8
      ..foB = 1.1
      ..lean = 0.2;
    final l = x.worker(Offset(broom - 26, x.floorY), dir: 1, pose: pose, h: 46, hat: BP.green);
    final foot = Offset(broom + 2 * math.sin(x.t * 9), x.daisY - 1);
    x.c.drawLine(l.elbowA, foot, x.st(BP.inkDim, 1.4));
    final bristles = Path();
    for (var i = -3; i <= 3; i++) {
      bristles
        ..moveTo(foot.dx + i * 1.4, foot.dy - 5)
        ..lineTo(foot.dx + i * 2.4, foot.dy);
    }
    x.c.drawPath(bristles, x.st(_straw, 1.2));
  }
}

// Leaf colours.
const _leafDark = Color(0xFF2F7A4C);
const _leafMid = Color(0xFF4FA86C);
const _leafLight = Color(0xFF8ED39B);
const _leafEdge = Color(0xFF256140);
const _straw = Color(0xFFE2C27A);
const _water = Color(0xFF8FD3FF);
const _strawDark = Color(0xFFA4843E);

class _Clump {
  _Clump(this.c, this.r, this.u, this.out, this.seed, this.dots);

  final Offset c;
  final double r;

  /// Where along the trimming schedule (0..1) the shears pass it.
  final double u;

  /// Away from the letter (unit).
  final Offset out;
  final int seed;

  /// Leaf dots (dark, dark, mid, mid, light), relative to [c].
  final List<Offset> dots;
}

/// The bush: leaf clumps outside the letter, each snipped when the shears
/// pass the nearest point of the outline; and the trimming schedule (each
/// outline in turn, a short move between outlines).
class _Hedge {
  _Hedge(GlyphStage s, int seed, double daisY) : _s = s {
    final ink = s.ink;
    final rng = math.Random(seed);
    final m = (ink.height * 0.07).clamp(12.0, 22.0);
    r = Rect.fromLTRB(ink.left - m, ink.top - m, ink.right + m, daisY);

    // Schedule: trace each contour; moving between them takes a little.
    final n = s.contourMetrics.length;
    final avg = n == 0 ? 1.0 : s.outlineLength / n;
    final move = math.min(0.35 * avg, 60.0);
    var t = 0.0;
    for (var i = 0; i < n; i++) {
      if (i > 0) t += move;
      _starts.add(t);
      t += s.contourMetrics[i].length;
    }
    _total = math.max(t, 1);
    _move = move;
    // Which side the gardener stands on for each contour.
    for (var i = 0; i < n; i++) {
      final b = s.contours[i].getBounds();
      _sides.add(b.center.dx < ink.center.dx ? -1 : 1);
    }

    // Outline samples (position, schedule time), bucketed on a coarse grid
    // so each clump finds its nearest one quickly.
    const cell = 24.0;
    final buckets = <int, List<(Offset, double)>>{};
    int key(int i, int j) => i * 4096 + j;
    for (var i = 0; i < n; i++) {
      final mtr = s.contourMetrics[i];
      final steps = math.max(4, (mtr.length / 5).ceil());
      for (var k = 0; k < steps; k++) {
        final d = mtr.length * k / steps;
        final tan = mtr.getTangentForOffset(d);
        if (tan == null) continue;
        final q = tan.position;
        (buckets[key((q.dx / cell).floor(), (q.dy / cell).floor())] ??= []).add((q, (_starts[i] + d) / _total));
      }
    }

    // Clumps on a jittered grid over the bush, outside the letter.
    final inside = _Inside(s);
    const sp = 15.0;
    for (var y = r.top + sp / 2; y < r.bottom - 2; y += sp) {
      for (var xx = r.left + sp / 2; xx < r.right; xx += sp) {
        final o = Offset(
          xx + (rng.nextDouble() - 0.5) * sp * 0.6,
          math.min(daisY - 7, y + (rng.nextDouble() - 0.5) * sp * 0.6),
        );
        if (!_inBush(o) || inside(o)) continue;
        var best = double.infinity;
        var bu = 0.0;
        var bp = o;
        final ci = (o.dx / cell).floor(), cj = (o.dy / cell).floor();
        // Search rings of buckets until the nearest sample can't be beaten.
        for (var ring = 0; ring < 40; ring++) {
          for (var i = ci - ring; i <= ci + ring; i++) {
            for (var j = cj - ring; j <= cj + ring; j++) {
              if ((i - ci).abs() != ring && (j - cj).abs() != ring) continue;
              for (final (q, u) in buckets[key(i, j)] ?? const <(Offset, double)>[]) {
                final d = (q - o).distanceSquared;
                if (d < best) {
                  best = d;
                  bu = u;
                  bp = q;
                }
              }
            }
          }
          if (best <= (ring * cell) * (ring * cell)) break;
        }
        final away = o - bp;
        final out = away.distance < 0.5 ? const Offset(0, -1) : away / away.distance;
        clumps.add(
          _Clump(o, sp * 0.92 + rng.nextDouble() * 3, bu, out, clumps.length, [
            for (var i = 0; i < 5; i++)
              Offset((rng.nextDouble() - 0.5) * sp * 0.95, (rng.nextDouble() - 0.5) * sp * 0.95),
          ]),
        );
      }
    }
  }

  final GlyphStage _s;
  late final Rect r;
  final clumps = <_Clump>[];
  final _starts = <double>[];
  final _sides = <int>[];
  late final double _total;
  late final double _move;

  /// A rounded bush shape over [r].
  bool _inBush(Offset o) {
    final rr = RRect.fromRectAndRadius(r, Radius.circular(math.min(r.width, r.height) * 0.22));
    return rr.contains(o);
  }

  /// When clump [k] is snipped (p).
  double cutTime(_Clump k) =>
      TopiaryCraft._trimStart + (TopiaryCraft._trimEnd - TopiaryCraft._trimStart) * k.u;

  /// The outline fraction (as [GlyphStage.outlineUpTo] counts it) traced at
  /// trimming progress [q].
  double outlineFrac(double q) {
    final s = _s;
    if (s.outlineLength <= 0) return q;
    final time = q * _total;
    var done = 0.0;
    for (var i = 0; i < _starts.length; i++) {
      final len = s.contourMetrics[i].length;
      if (time < _starts[i]) break;
      done += math.min(len, time - _starts[i]);
    }
    return done / s.outlineLength;
  }

  /// The shears' tip at trimming progress [q] and the side the gardener
  /// stands on (−1 left, 1 right), blended while moving between outlines.
  (Offset, double) shears(double q) {
    final s = _s;
    final n = _starts.length;
    if (n == 0) return (s.ink.center, 1);
    final time = q * _total;
    var i = n - 1;
    while (i > 0 && _starts[i] > time) {
      i--;
    }
    final m = s.contourMetrics[i];
    final d = time - _starts[i];
    if (d <= m.length || i == n - 1) {
      final tan = m.getTangentForOffset(d.clamp(0.0, m.length));
      return (tan?.position ?? s.ink.center, _sides[i].toDouble());
    }
    // Moving to the next outline.
    final f = eio((d - m.length) / math.max(1, _move));
    final a = m.getTangentForOffset(m.length)?.position ?? s.ink.center;
    final b = s.contourMetrics[i + 1].getTangentForOffset(0)?.position ?? s.ink.center;
    return (Offset.lerp(a, b, f)!, lerp(_sides[i].toDouble(), _sides[i + 1].toDouble(), f));
  }
}

/// Leaf texture inside the letter (cached; drawn as round dots).
class _Leaves {
  _Leaves(GlyphStage s, int seed) {
    final rng = math.Random(seed ^ 0x1eaf);
    final inside = _Inside(s);
    for (final r in s.rows) {
      final expected = r.width * r.height / 46;
      var n = expected.floor();
      if (rng.nextDouble() < expected - n) n++;
      for (var i = 0; i < n; i++) {
        final pt = Offset(r.left + rng.nextDouble() * r.width, r.top + rng.nextDouble() * r.height);
        if (!inside(pt, 3.2)) continue;
        final pick = rng.nextDouble();
        (pick < 0.4 ? dark : (pick < 0.75 ? mid : light)).add(pt);
      }
    }
  }

  final dark = <Offset>[];
  final mid = <Offset>[];
  final light = <Offset>[];
}

/// Raster-row lookup: is a canvas point inside the glyph (by [inset] px)?
class _Inside {
  _Inside(GlyphStage s) : _k = s.k, _o = s.origin {
    for (final sp in s.geo.spans) {
      (_rows[sp.y] ??= <Span>[]).add(sp);
    }
  }

  final double _k;
  final Offset _o;
  final _rows = <int, List<Span>>{};

  bool call(Offset p, [double inset = 0]) {
    if (inset > 0) {
      return call(p) &&
          call(p + Offset(inset, 0)) &&
          call(p - Offset(inset, 0)) &&
          call(p + Offset(0, inset)) &&
          call(p - Offset(0, inset));
    }
    final row = _rows[((p.dy - _o.dy) / _k).floor()];
    if (row == null) return false;
    final rx = (p.dx - _o.dx) / _k;
    for (final sp in row) {
      if (rx >= sp.x0 && rx < sp.x1) return true;
    }
    return false;
  }
}
