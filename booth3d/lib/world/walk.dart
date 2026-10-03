import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import 'crew.dart';
import 'crew_breaks.dart' show OffDuty;
import 'kit.dart';
import 'motion.dart';

/// Someone's walk along [pts], from [start] to [end] at an even pace
/// (picked up over the first steps, slowed to a stop over the last, the
/// body turning through the corners), then standing at the end facing
/// [face] (yaw, 0 towards −z). For the scenes that move people about on a
/// schedule (the team photo, the manager's visit): [pose] puts a figure
/// where the walk has them at a moment.
class Walk {
  Walk(this.pts, this.start, double speed, {this.face = 0}) : end = start + lengthOf(pts) / speed;

  final List<vm.Vector3> pts;
  final double start, end, face;

  /// How long setting off and stopping take (at most a third of the walk
  /// each).
  static const _ease = 0.35;

  /// How far through (0..1) a walk [len] seconds long is [t] seconds in.
  static double _frac(double t, double len) {
    final e = math.min(_ease, len / 3), v = 1 / (len - e);
    if (t <= 0) return 0;
    if (t >= len) return 1;
    if (t < e) return 0.5 * v / e * t * t;
    if (t > len - e) return 1 - 0.5 * v / e * (len - t) * (len - t);
    return 0.5 * v * e + v * (t - e);
  }

  /// When (seconds in) it's [f] (0..1) of the way.
  static double _timeOf(double f, double len) {
    final e = math.min(_ease, len / 3), v = 1 / (len - e), f1 = 0.5 * v * e;
    if (f <= 0) return 0;
    if (f >= 1) return len;
    if (f < f1) return math.sqrt(2 * f * e / v);
    if (f > 1 - f1) return len - math.sqrt(2 * (1 - f) * e / v);
    return e + (f - f1) / v;
  }

  /// The pace at [t] seconds in (0..1 of its top speed).
  static double _pace(double t, double len) {
    final e = math.min(_ease, len / 3);
    if (t <= 0 || t >= len) return 0;
    return math.min(1.0, math.min(t, len - t) / e);
  }

  vm.Vector3 get last => pts.last;

  static double lengthOf(List<vm.Vector3> pts) {
    var l = 0.0;
    for (var i = 0; i + 1 < pts.length; i++) {
      l += pts[i].distanceTo(pts[i + 1]);
    }
    return l;
  }

  /// When the walk gets to point [i].
  double at(int i) {
    var l = 0.0;
    for (var k = 0; k < i; k++) {
      l += pts[k].distanceTo(pts[k + 1]);
    }
    return start + _timeOf(l / math.max(lengthOf(pts), 1e-6), math.max(end - start, 1e-3));
  }

  /// How far along the walk they are at [t].
  double _along(double t) => lengthOf(pts) * _frac(t - start, math.max(end - start, 1e-3));

  /// The way leg [i] goes (yaw); a leg too short to tell, the next's (or
  /// the last's).
  double _legYaw(int i) {
    for (var k = i; k + 1 < pts.length; k++) {
      final a = pts[k], b = pts[k + 1];
      if (a.distanceTo(b) > 0.01) return math.atan2(-(b.x - a.x), -(b.z - a.z));
    }
    for (var k = i - 1; k >= 0; k--) {
      final a = pts[k], b = pts[k + 1];
      if (a.distanceTo(b) > 0.01) return math.atan2(-(b.x - a.x), -(b.z - a.z));
    }
    return face;
  }

  static double _wrap(double a) {
    var d = a % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    return d;
  }

  /// The way they face [d] metres along leg [i] (which starts [acc] metres
  /// in, [l] long): the leg's way, turning into the next from a little
  /// before the corner to a little after.
  double _yawAt(int i, double d, double acc, double l) {
    final h = _legYaw(i);
    if (i + 2 < pts.length) {
      final r = math.min(0.35, math.min(l, pts[i + 1].distanceTo(pts[i + 2])) / 2);
      final into = r > 0.01 ? smooth(acc + l - r, acc + l + r, d) : 0.0;
      if (into > 0) return h + _wrap(_legYaw(i + 1) - h) * into;
    }
    if (i > 0) {
      final r = math.min(0.35, math.min(l, pts[i - 1].distanceTo(pts[i])) / 2);
      final out = r > 0.01 ? smooth(acc - r, acc + r, d) : 1.0;
      if (out < 1) {
        final hp = _legYaw(i - 1);
        return hp + _wrap(h - hp) * out;
      }
    }
    return h;
  }

  /// Where the walk has them at [t] (into [out]).
  vm.Vector3 posAt(double t, vm.Vector3 out) {
    var d = _along(t);
    for (var i = 0; i + 1 < pts.length; i++) {
      final a = pts[i], b = pts[i + 1];
      final l = a.distanceTo(b);
      if (d <= l || i + 2 == pts.length) {
        final k = l > 0 ? c01(d / l) : 1.0;
        return out..setValues(lerp(a.x, b.x, k), 0, lerp(a.z, b.z, k));
      }
      d -= l;
    }
    return out..setFrom(pts.last);
  }

  /// The way back to the start from where the walk has them at [t]: from
  /// there through the points already passed, latest first.
  List<vm.Vector3> backFrom(double t) {
    final out = [posAt(t, vm.Vector3.zero())];
    final d = _along(t);
    final passed = [pts.first];
    var l = 0.0;
    for (var i = 0; i + 1 < pts.length; i++) {
      l += pts[i].distanceTo(pts[i + 1]);
      if (l < d - 1e-6) passed.add(pts[i + 1]);
    }
    for (final p in passed.reversed) {
      if (p.distanceTo(out.last) > 1e-3) out.add(p);
    }
    return out;
  }

  /// Poses [f] walking (or, done, standing) at [t]; before it starts,
  /// standing at the start facing the way.
  void pose(FigurePose f, double t, int seed) {
    if (t <= start) {
      final a = pts.first;
      f.pos.setValues(a.x, 0, a.z);
      OffDuty.stand(f, t, seed);
      final b = pts.length > 1 ? pts[1] : a;
      f.yaw = a.distanceTo(b) > 0.01 ? math.atan2(-(b.x - a.x), -(b.z - a.z)) : face;
      return;
    }
    final total = lengthOf(pts), len = math.max(end - start, 1e-3), along = _along(t);
    var d = along, acc = 0.0;
    for (var i = 0; i + 1 < pts.length; i++) {
      final a = pts[i], b = pts[i + 1];
      final l = a.distanceTo(b);
      if (d <= l || i + 2 == pts.length) {
        final k = l > 0 ? c01(d / l) : 1.0;
        f.pos.setValues(lerp(a.x, b.x, k), 0, lerp(a.z, b.z, k));
        if (t < end && total > 0.01) {
          // The steps fitted to the way (none taken half), the stride
          // opening up as they get going and closing as they stop.
          final top = total / math.max(len - math.min(_ease, len / 3), 1e-3), m = Manner.of(seed);
          Gait.walk(f, Gait.phaseOver(along, total, top, 1, m), top, m, amount: c01(0.15 + 1.6 * _pace(t - start, len)));
          f.yaw = _yawAt(i, along, acc, l);
        } else {
          OffDuty.stand(f, t, seed);
          f.yaw = face;
        }
        return;
      }
      d -= l;
      acc += l;
    }
  }
}
