import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';
import 'site_geo.dart';
import 'site_plan.dart';

/// One concrete block under the wall: from [x0] to [x1], its top at [top]
/// (it stands on the ground, [depth] deep, centred on the wall's plane).
typedef PlinthRun = ({double x0, double x1, double top});

/// The letters' plinths. The wall's bottom row is its lowest ink — a
/// descender, if the name has one — so the name's other letters stand on
/// their baseline, up in the air: each needs something under it. Under
/// every column of the wall the support comes up to just under the skid of
/// the letter above it; a gap between letters takes the lower of its
/// neighbours (a descender always reaches the ground); runs of the same
/// height are one block. A letter built loose to the right, waiting to be
/// kerned, may overhang its block until it's pushed home.
///
/// They rise out of the ground as a name's plan is made, carry the wall
/// (and the wreck's rubble: [runs] for the physics), and go with the
/// rubble at the cleanup's cut.
class Plinths {
  Plinths(this.scene);
  final Scene scene;

  static const _max = 40;
  late final InstancedMesh _mesh;
  final _node = Node(name: 'plinths');

  /// The blocks of the current plan (empty: none needed).
  final runs = <PlinthRun>[];

  /// How deep the blocks are (z), centred on the wall.
  double depth = 0.35;

  void init() {
    _mesh = InstancedMesh(geometry: (MeshBatch()..chamferedCube(0.02)).build(), material: pbr(lin(const Color(0xFFB9B4AB)), roughness: 0.92));
    for (var i = 0; i < _max; i++) {
      _mesh.addInstance(hidden);
    }
    scene.add(_node..addComponent(InstancedMeshComponent(_mesh)));
    _node.visible = false;
  }

  /// Works out [plan]'s blocks.
  void plan(BuildPlan plan) {
    runs.clear();
    final b = plan.b, cols = plan.r.cols;
    depth = b * 1.5;
    const none = double.infinity;
    final top = List<double>.filled(cols, none);
    final ls = plan.letters.letters;
    for (final l in ls) {
      if (l.col1 < l.col0) continue;
      final t = l.row0 * b - 0.06;
      for (var c = math.max(0, l.col0); c <= math.min(cols - 1, l.col1); c++) {
        top[c] = math.min(top[c], t);
      }
    }
    // Gaps between letters: the lower neighbour.
    final first = top.indexWhere((t) => t != none), last = top.lastIndexWhere((t) => t != none);
    if (first < 0) return;
    for (var c = first; c <= last; c++) {
      if (top[c] != none) continue;
      var r = c;
      while (r <= last && top[r] == none) {
        r++;
      }
      final fill = math.min(top[c - 1], r <= last ? top[r] : top[c - 1]);
      for (var k = c; k < r; k++) {
        top[k] = fill;
      }
      c = r - 1;
    }
    // Runs of one height; none where the ground is close enough.
    double x(int c) => (c - cols / 2) * b;
    var c = first;
    while (c <= last) {
      var e = c;
      while (e + 1 <= last && (top[e + 1] - top[c]).abs() < 1e-6) {
        e++;
      }
      if (top[c] >= 0.1 && runs.length < _max) {
        runs.add((x0: x(c) - (c == first ? 0.08 : 0), x1: x(e + 1) + (e == last ? 0.08 : 0), top: top[c]));
      }
      c = e + 1;
    }
  }

  final _m = vm.Matrix4.identity();
  final _q = vm.Quaternion.identity();

  /// Draws the blocks, [rise] (0..1) of the way up out of the ground;
  /// hidden at 0.
  void update(double rise) {
    _node.visible = rise > 0.001 && runs.isNotEmpty;
    if (!_node.visible) return;
    for (var i = 0; i < _max; i++) {
      if (i >= runs.length) {
        _mesh.setInstanceTransform(i, hidden);
        continue;
      }
      final r = runs[i], h = r.top;
      _mesh.setInstanceTransform(i, setTqs(_m, (r.x0 + r.x1) / 2, h / 2 - h * (1 - rise), 0, _q, r.x1 - r.x0, h, depth));
    }
  }
}
