import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import 'crew.dart';
import 'crew_breaks.dart' show OffDuty;
import 'kit.dart';

/// Someone's walk along [pts], from [start] to [end] at an even pace, then
/// standing at the end facing [face] (yaw, 0 towards −z). For the scenes
/// that move people about on a schedule (the team photo, the manager's
/// visit): [pose] puts a figure where the walk has them at a moment.
class Walk {
  Walk(this.pts, this.start, double speed, {this.face = 0}) : end = start + lengthOf(pts) / speed;

  final List<vm.Vector3> pts;
  final double start, end, face;

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
    return start + (end - start) * l / math.max(lengthOf(pts), 1e-6);
  }

  /// How far along the walk they are at [t].
  double _along(double t) => lengthOf(pts) * c01((t - start) / math.max(end - start, 1e-3));

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
    final total = lengthOf(pts);
    var d = _along(t);
    for (var i = 0; i + 1 < pts.length; i++) {
      final a = pts[i], b = pts[i + 1];
      final l = a.distanceTo(b);
      if (d <= l || i + 2 == pts.length) {
        final k = l > 0 ? c01(d / l) : 1.0;
        f.pos.setValues(lerp(a.x, b.x, k), 0, lerp(a.z, b.z, k));
        if (t < end && l > 0.01) {
          OffDuty.walk(f, t, total / math.max(end - start, 1e-3), seed, dist: _along(t), total: total);
          f.yaw = math.atan2(-(b.x - a.x), -(b.z - a.z));
        } else {
          OffDuty.stand(f, t, seed);
          f.yaw = face;
        }
        return;
      }
      d -= l;
    }
  }
}
