import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

// Shapes made the way things are made: no edge razor sharp (a real edge is
// rounded off, and catches the light along it), smooth normals round the
// curves. Centred on the origin; the front faces −z (the side a camera in
// front sees), its texture upright across it.

/// A rounded rectangle's outline round the origin, counter-clockwise from
/// the bottom of its right side: half extents [a]×[b], corners of radius
/// [r] (0: square), [n] steps a corner; each point with its outward
/// normal (x, y, nx, ny).
List<(double, double, double, double)> roundedOutline(double a, double b, double r, int n) {
  final out = <(double, double, double, double)>[];
  for (final (cx, cy, a0) in [(a - r, -(b - r), -math.pi / 2), (a - r, b - r, 0.0), (-(a - r), b - r, math.pi / 2), (-(a - r), -(b - r), math.pi)]) {
    for (var k = 0; k <= n; k++) {
      final t = a0 + k / n * math.pi / 2;
      final c = math.cos(t), s = math.sin(t);
      out.add((cx + r * c, cy + r * s, c, s));
    }
  }
  return out;
}

/// A slab [w]×[h]×[d] (x, y, z) with rounded corners ([corner], seen from
/// the front) and every edge rounded off ([edge]): a phone, a board, a
/// button. Texture coordinates run across the front and back, upright.
MeshData roundedSlab(double w, double h, double d, {required double corner, required double edge, int cornerSteps = 8, int edgeSteps = 4}) {
  final e = math.min(edge, math.min(d / 2, math.min(w, h) / 2) * 0.999);
  final rc = math.max(0.0, math.min(corner, math.min(w, h) / 2) - e);
  final ring = roundedOutline(w / 2 - e, h / 2 - e, rc, cornerSteps);
  final s = d / 2 - e;
  // The profile round an edge: from the front's rim (facing −z) over to
  // the side, along it, and on round to the back's rim.
  final prof = <(double, double, double, double)>[
    for (var k = 0; k <= edgeSteps; k++) _arc(-math.pi / 2 + k / edgeSteps * math.pi / 2, e, -s),
    for (var k = 0; k <= edgeSteps; k++) _arc(k / edgeSteps * math.pi / 2, e, s),
  ];
  final b = _Builder();
  final n = ring.length;
  for (final (off, z, nr, nz) in prof) {
    for (final (x, y, nx, ny) in ring) {
      final px = x + nx * off, py = y + ny * off;
      b.vertex(px, py, z, nx * nr, ny * nr, nz, px / w + 0.5, 0.5 - py / h);
    }
  }
  for (var r = 0; r + 1 < prof.length; r++) {
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      b.quad(r * n + i, r * n + j, (r + 1) * n + j, (r + 1) * n + i);
    }
  }
  // The front and the back: fans from the middle to the rims.
  for (final (z, nz) in [(-d / 2, -1.0), (d / 2, 1.0)]) {
    final c = b.vertex(0, 0, z, 0, 0, nz, 0.5, 0.5);
    for (final (x, y, _, _) in ring) {
      b.vertex(x, y, z, 0, 0, nz, x / w + 0.5, 0.5 - y / h);
    }
    for (var i = 0; i < n; i++) {
      b.tri(c, c + 1 + i, c + 1 + (i + 1) % n);
    }
  }
  return b.build();
}

(double, double, double, double) _arc(double phi, double e, double zc) => (e * math.cos(phi), zc + e * math.sin(phi), math.cos(phi), math.sin(phi));

/// A flat rounded rectangle [w]×[h] (corners of radius [corner]) facing −z
/// (or +z, [back]), its texture upright across it (as seen from its side).
MeshData roundedPlate(double w, double h, double corner, {bool back = false, int cornerSteps = 10}) {
  final rc = math.min(corner, math.min(w, h) / 2);
  final ring = roundedOutline(w / 2, h / 2, rc, cornerSteps);
  final b = _Builder();
  final nz = back ? 1.0 : -1.0;
  // (Seen from behind, x runs the other way.)
  double u(double x) => back ? 0.5 - x / w : x / w + 0.5;
  final c = b.vertex(0, 0, 0, 0, 0, nz, 0.5, 0.5);
  for (final (x, y, _, _) in ring) {
    b.vertex(x, y, 0, 0, 0, nz, u(x), 0.5 - y / h);
  }
  for (var i = 0; i < ring.length; i++) {
    b.tri(c, c + 1 + i, c + 1 + (i + 1) % ring.length);
  }
  return b.build();
}

/// A disc of radius [r] facing −z (or +z, [back]).
MeshData disc(double r, {bool back = false, int steps = 28}) => roundedPlate(2 * r, 2 * r, r, back: back, cornerSteps: steps ~/ 4);

final _bevelled = <(double, double, double), MeshData>{};

/// A box [w]×[h]×[d] with its edges rounded off a little (as a made
/// thing's are: the bevel catches the light along an edge); a plain box
/// when it's too thin to show one. The same size, the same mesh.
MeshData bevelBox(double w, double h, double d) {
  final m = math.min(w, math.min(h, d));
  if (m < 0.05) return CuboidGeometry(vm.Vector3(w, h, d)).extractMeshData();
  return _bevelled.putIfAbsent((w, h, d), () {
    final e = math.min(0.03, 0.18 * m);
    return roundedSlab(w, h, d, corner: e, edge: e, cornerSteps: 1, edgeSteps: 2);
  });
}

/// [d] as geometry.
MeshGeometry geometryOf(MeshData d) => MeshGeometry.fromMeshData(d);

/// Gathers vertices and triangles; each triangle wound so it faces the way
/// its vertices' normals do (counter-clockwise seen from outside).
class _Builder {
  final _p = <double>[], _n = <double>[], _uv = <double>[];
  final _idx = <int>[];

  int vertex(double x, double y, double z, double nx, double ny, double nz, double u, double v) {
    _p.addAll([x, y, z]);
    _n.addAll([nx, ny, nz]);
    _uv.addAll([u, v]);
    return _p.length ~/ 3 - 1;
  }

  void quad(int a, int b, int c, int d) {
    tri(a, b, c);
    tri(a, c, d);
  }

  void tri(int a, int b, int c) {
    vm.Vector3 p(int i) => vm.Vector3(_p[i * 3], _p[i * 3 + 1], _p[i * 3 + 2]);
    final pa = p(a), pb = p(b), pc = p(c);
    final f = (pb - pa).cross(pc - pa);
    if (f.length2 < 1e-14) return; // (degenerate: a seam's sliver)
    final nx = _n[a * 3] + _n[b * 3] + _n[c * 3], ny = _n[a * 3 + 1] + _n[b * 3 + 1] + _n[c * 3 + 1], nz = _n[a * 3 + 2] + _n[b * 3 + 2] + _n[c * 3 + 2];
    if (f.x * nx + f.y * ny + f.z * nz >= 0) {
      _idx.addAll([a, b, c]);
    } else {
      _idx.addAll([a, c, b]);
    }
  }

  MeshData build() => MeshData(
    positions: Float32List.fromList(_p),
    vertexCount: _p.length ~/ 3,
    normals: Float32List.fromList(_n),
    texCoords: Float32List.fromList(_uv),
    indices: _idx,
  );
}
