import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/craft/extrude.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Geometry helpers for the build site: beams and boxes merged into one mesh
/// (lattice masts, trusses), a hard-hat dome, glyph meshes sliced into
/// horizontal bands and strips (for the finish), and allocation-free
/// transforms for the per-frame loops.

/// Collects flat-shaded quads into one mesh (one draw for a whole truss).
class MeshBatch {
  final _p = <double>[], _n = <double>[], _uv = <double>[];
  final _i = <int>[];

  bool get isEmpty => _i.isEmpty;

  /// One quad (p0 p1 p2 p3 around its edge) facing [n]; the winding is
  /// fixed up so the front face points along [n] (CCW, glTF convention).
  void quad(vm.Vector3 p0, vm.Vector3 p1, vm.Vector3 p2, vm.Vector3 p3, vm.Vector3 n) {
    final base = _p.length ~/ 3;
    for (final (p, u, v) in [(p0, 0.0, 0.0), (p1, 1.0, 0.0), (p2, 1.0, 1.0), (p3, 0.0, 1.0)]) {
      _p.addAll([p.x, p.y, p.z]);
      _n.addAll([n.x, n.y, n.z]);
      _uv.addAll([u, v]);
    }
    final c = (p1 - p0).cross(p2 - p0);
    if (c.dot(n) >= 0) {
      _i.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
    } else {
      _i.addAll([base, base + 2, base + 1, base, base + 3, base + 2]);
    }
  }

  /// A box from its centre, three half-axes (any orientation).
  void orientedBox(vm.Vector3 c, vm.Vector3 ax, vm.Vector3 ay, vm.Vector3 az) {
    for (final (axis, s1, s2) in [(ax, ay, az), (ay, az, ax), (az, ax, ay)]) {
      for (final sign in const [1.0, -1.0]) {
        final f = c + axis * sign;
        final n = axis.normalized() * sign;
        quad(f - s1 - s2, f + s1 - s2, f + s1 + s2, f - s1 + s2, n);
      }
    }
  }

  /// An axis-aligned box.
  void box(vm.Vector3 center, vm.Vector3 size) => orientedBox(
    center,
    vm.Vector3(size.x / 2, 0, 0),
    vm.Vector3(0, size.y / 2, 0),
    vm.Vector3(0, 0, size.z / 2),
  );

  /// A square beam of thickness [t] from [a] to [b].
  void beam(vm.Vector3 a, vm.Vector3 b, double t) {
    final d = b - a;
    final len = d.length;
    if (len < 1e-6) return;
    final axis = d / len;
    final ref = axis.y.abs() < 0.9 ? vm.Vector3(0, 1, 0) : vm.Vector3(1, 0, 0);
    final u = axis.cross(ref)..normalize();
    final v = axis.cross(u)..normalize();
    orientedBox((a + b) * 0.5, axis * (len / 2), u * (t / 2), v * (t / 2));
  }

  MeshGeometry build() => MeshGeometry.fromArrays(
    positions: Float32List.fromList(_p),
    normals: Float32List.fromList(_n),
    texCoords: Float32List.fromList(_uv),
    indices: _i,
  );
}

/// A square lattice mast (four corner posts, ties and zig-zag braces on
/// every face) from [y0] to [y1], [w] wide, centred on x = z = 0.
void latticeMast(MeshBatch m, {required double w, required double y0, required double y1, double section = 1.2, double post = 0.1, double brace = 0.05}) {
  final h = w / 2;
  final corners = [vm.Vector3(-h, 0, -h), vm.Vector3(h, 0, -h), vm.Vector3(h, 0, h), vm.Vector3(-h, 0, h)];
  for (final c in corners) {
    m.beam(c + vm.Vector3(0, y0, 0), c + vm.Vector3(0, y1, 0), post);
  }
  final n = math.max(1, ((y1 - y0) / section).round());
  final step = (y1 - y0) / n;
  for (var k = 0; k <= n; k++) {
    final y = y0 + k * step;
    for (var i = 0; i < 4; i++) {
      m.beam(corners[i] + vm.Vector3(0, y, 0), corners[(i + 1) % 4] + vm.Vector3(0, y, 0), brace);
    }
    if (k == n) break;
    for (var i = 0; i < 4; i++) {
      final a = corners[i], b = corners[(i + 1) % 4];
      // Zig-zag: alternate the diagonal's direction each section.
      final (p, q) = k.isEven ? (a, b) : (b, a);
      m.beam(p + vm.Vector3(0, y, 0), q + vm.Vector3(0, y + step, 0), brace);
    }
  }
}

/// A triangular truss along −x from [x0] to [x1] (x1 < x0): two bottom
/// chords [w] apart, one top chord [h] above, diagonals between.
void triangularTruss(MeshBatch m, {required double x0, required double x1, required double w, required double h, double chord = 0.1, double brace = 0.05, double panel = 1.1}) {
  final b1 = vm.Vector3(0, 0, -w / 2), b2 = vm.Vector3(0, 0, w / 2), top = vm.Vector3(0, h, 0);
  vm.Vector3 at(vm.Vector3 c, double x) => vm.Vector3(x, c.y, c.z);
  for (final c in [b1, b2, top]) {
    m.beam(at(c, x0), at(c, x1), chord);
  }
  final n = math.max(1, ((x0 - x1).abs() / panel).round());
  final step = (x1 - x0) / n;
  for (var k = 0; k <= n; k++) {
    final x = x0 + k * step;
    m.beam(at(b1, x), at(b2, x), brace);
    if (k == n) break;
    final xn = x + step;
    m.beam(at(b1, x), at(top, xn), brace);
    m.beam(at(b2, x), at(top, xn), brace);
    m.beam(at(top, x), at(b1, xn), brace);
    m.beam(at(top, x), at(b2, xn), brace);
    m.beam(at(b1, x), at(b2, xn), brace * 0.8);
  }
}

/// A dome (the top half of a sphere) with a flat base, base on y = 0.
MeshGeometry domeGeometry({double radius = 0.5, int segments = 18, int rings = 6}) {
  final p = <double>[], n = <double>[], uv = <double>[];
  final idx = <int>[];
  for (var r = 0; r <= rings; r++) {
    final phi = r / rings * math.pi / 2; // 0 = equator … π/2 = top
    for (var s = 0; s <= segments; s++) {
      final th = s / segments * math.pi * 2;
      final nx = math.cos(phi) * math.cos(th), ny = math.sin(phi), nz = math.cos(phi) * math.sin(th);
      p.addAll([nx * radius, ny * radius, nz * radius]);
      n.addAll([nx, ny, nz]);
      uv.addAll([s / segments, r / rings]);
    }
  }
  final row = segments + 1;
  for (var r = 0; r < rings; r++) {
    for (var s = 0; s < segments; s++) {
      final a = r * row + s, b = a + 1, c = a + row, d = c + 1;
      // Outward normals: (a, c, b) and (b, c, d) wind CCW seen from outside.
      idx.addAll([a, c, b, b, c, d]);
    }
  }
  // Base disc (facing down).
  final center = p.length ~/ 3;
  p.addAll([0, 0, 0]);
  n.addAll([0, -1, 0]);
  uv.addAll([0.5, 0.5]);
  final ring0 = p.length ~/ 3;
  for (var s = 0; s <= segments; s++) {
    final th = s / segments * math.pi * 2;
    p.addAll([math.cos(th) * radius, 0, math.sin(th) * radius]);
    n.addAll([0, -1, 0]);
    uv.addAll([0.5 + 0.5 * math.cos(th), 0.5 + 0.5 * math.sin(th)]);
  }
  for (var s = 0; s < segments; s++) {
    idx.addAll([center, ring0 + s, ring0 + s + 1]);
  }
  final g = _fixWinding(Float32List.fromList(p), Float32List.fromList(n), idx);
  return MeshGeometry.fromArrays(positions: g.$1, normals: g.$2, texCoords: Float32List.fromList(uv), indices: g.$3);
}

/// Makes every triangle wind CCW around its vertex normals.
(Float32List, Float32List, List<int>) _fixWinding(Float32List p, Float32List n, List<int> idx) {
  final out = <int>[];
  for (var t = 0; t + 2 < idx.length; t += 3) {
    final a = idx[t], b = idx[t + 1], c = idx[t + 2];
    final ux = p[3 * b] - p[3 * a], uy = p[3 * b + 1] - p[3 * a + 1], uz = p[3 * b + 2] - p[3 * a + 2];
    final vx = p[3 * c] - p[3 * a], vy = p[3 * c + 1] - p[3 * a + 1], vz = p[3 * c + 2] - p[3 * a + 2];
    final cx = uy * vz - uz * vy, cy = uz * vx - ux * vz, cz = ux * vy - uy * vx;
    final nx = n[3 * a] + n[3 * b] + n[3 * c], ny = n[3 * a + 1] + n[3 * b + 1] + n[3 * c + 1], nz = n[3 * a + 2] + n[3 * b + 2] + n[3 * c + 2];
    if (cx * nx + cy * ny + cz * nz >= 0) {
      out.addAll([a, b, c]);
    } else {
      out.addAll([a, c, b]);
    }
  }
  return (p, n, out);
}

/// [m] cut into horizontal bands at [cuts] (ascending y, in the mesh's
/// units): band k holds the part of every triangle with
/// cuts[k-1] ≤ y < cuts[k] (the first band is open below, the last above).
/// Bands with nothing in them are null. Normals and uvs are interpolated
/// along the cut edges, so the pieces put back together are the letter.
List<MeshGeometry?> sliceGlyph(GlyphMesh m, List<double> cuts) => sliceGlyphGrid(m, const [], cuts).first;

/// [m] cut into a grid: vertical strips at [xCuts] and, within each, the
/// horizontal bands of [sliceGlyph] at [yCuts] (both ascending, in the
/// mesh's units). Piece [s][k] is strip s's band k (null when empty).
List<List<MeshGeometry?>> sliceGlyphGrid(GlyphMesh m, List<double> xCuts, List<double> yCuts) {
  final strips = xCuts.length + 1, bands = yCuts.length + 1;
  final pos = List.generate(strips * bands, (_) => <double>[]);
  final nor = List.generate(strips * bands, (_) => <double>[]);
  final uvs = List.generate(strips * bands, (_) => <double>[]);
  final p = m.positions, n = m.normals, uv = m.uvs, idx = m.indices;
  int cellOf(List<double> cuts, double v) {
    var k = 0;
    while (k < cuts.length && v >= cuts[k]) {
      k++;
    }
    return k;
  }

  // A polygon vertex: x y z nx ny nz u v.
  List<double> vert(int i) => [p[3 * i], p[3 * i + 1], p[3 * i + 2], n[3 * i], n[3 * i + 1], n[3 * i + 2], uv[2 * i], uv[2 * i + 1]];
  List<double> mix(List<double> a, List<double> b, double f) => [for (var k = 0; k < 8; k++) a[k] + (b[k] - a[k]) * f];
  // Keeps the part of [poly] with coordinate [axis] (0 x, 1 y) ≥ c (above)
  // or ≤ c (below).
  List<List<double>> clip(List<List<double>> poly, double c, bool above, int axis) {
    final out = <List<double>>[];
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
      final ia = above ? a[axis] >= c : a[axis] <= c;
      final ib = above ? b[axis] >= c : b[axis] <= c;
      if (ia) out.add(a);
      if (ia != ib) {
        final f = (c - a[axis]) / (b[axis] - a[axis]);
        out.add(mix(a, b, f));
      }
    }
    return out;
  }

  void emit(int cell, List<List<double>> poly) {
    for (var i = 1; i + 1 < poly.length; i++) {
      for (final v in [poly[0], poly[i], poly[i + 1]]) {
        final l = math.sqrt(v[3] * v[3] + v[4] * v[4] + v[5] * v[5]);
        pos[cell].addAll([v[0], v[1], v[2]]);
        nor[cell].addAll(l == 0 ? [0.0, 0.0, 1.0] : [v[3] / l, v[4] / l, v[5] / l]);
        uvs[cell].addAll([v[6], v[7]]);
      }
    }
  }

  // The span of [poly] along [axis].
  (double, double) span(List<List<double>> poly, int axis) {
    var lo = poly[0][axis], hi = lo;
    for (final v in poly) {
      lo = math.min(lo, v[axis]);
      hi = math.max(hi, v[axis]);
    }
    return (lo, hi);
  }

  // [poly] (convex) into the bands of strip [s].
  void bandsOf(int s, List<List<double>> poly) {
    final (lo, hi) = span(poly, 1);
    final k0 = cellOf(yCuts, lo), k1 = cellOf(yCuts, hi);
    if (k0 == k1) {
      emit(s * bands + k0, poly);
      return;
    }
    for (var k = k0; k <= k1; k++) {
      var part = poly;
      if (k > 0) part = clip(part, yCuts[k - 1], true, 1);
      if (part.length >= 3 && k < yCuts.length) part = clip(part, yCuts[k], false, 1);
      if (part.length >= 3) emit(s * bands + k, part);
    }
  }

  for (var t = 0; t + 2 < idx.length; t += 3) {
    final tri = [vert(idx[t]), vert(idx[t + 1]), vert(idx[t + 2])];
    final (lo, hi) = span(tri, 0);
    final s0 = cellOf(xCuts, lo), s1 = cellOf(xCuts, hi);
    if (s0 == s1) {
      bandsOf(s0, tri);
      continue;
    }
    for (var s = s0; s <= s1; s++) {
      var part = tri;
      if (s > 0) part = clip(part, xCuts[s - 1], true, 0);
      if (part.length >= 3 && s < xCuts.length) part = clip(part, xCuts[s], false, 0);
      if (part.length >= 3) bandsOf(s, part);
    }
  }
  return [
    for (var s = 0; s < strips; s++)
      [
        for (var k = 0; k < bands; k++)
          pos[s * bands + k].isEmpty
              ? null
              : MeshGeometry.fromArrays(
                  positions: Float32List.fromList(pos[s * bands + k]),
                  normals: Float32List.fromList(nor[s * bands + k]),
                  texCoords: Float32List.fromList(uvs[s * bands + k]),
                ),
      ],
  ];
}

// ── Allocation-free transforms ──────────────────────────────────────────────

/// Node transforms written in place: a node keeps the matrix it is given,
/// so a shared scratch matrix must never be assigned to one.
extension NodePlace on Node {
  void place(void Function(vm.Matrix4 m) write) => mutateLocalTransform(write);
}

final _q = vm.Quaternion.identity();
final _t = vm.Vector3.zero();

/// Writes translation, yaw/pitch/roll (radians) and a uniform [s] into [out].
vm.Matrix4 setTrs(vm.Matrix4 out, double x, double y, double z, {double yaw = 0, double pitch = 0, double roll = 0, double s = 1}) {
  _q.setEuler(yaw, pitch, roll);
  _t.setValues(x, y, z);
  out.setFromTranslationRotation(_t, _q);
  if (s != 1) _scaleCols(out, s, s, s);
  return out;
}

/// Writes translation, rotation [q] and scale (per axis) into [out].
vm.Matrix4 setTqs(vm.Matrix4 out, double x, double y, double z, vm.Quaternion q, double sx, double sy, double sz) {
  _t.setValues(x, y, z);
  out.setFromTranslationRotation(_t, q);
  _scaleCols(out, sx, sy, sz);
  return out;
}

void _scaleCols(vm.Matrix4 m, double sx, double sy, double sz) {
  final s = m.storage;
  s[0] *= sx;
  s[1] *= sx;
  s[2] *= sx;
  s[4] *= sy;
  s[5] *= sy;
  s[6] *= sy;
  s[8] *= sz;
  s[9] *= sz;
  s[10] *= sz;
}

/// A unit cylinder/capsule along +y, oriented to point from [a] to [b]
/// (scaled along its axis to the distance when [stretch]).
vm.Matrix4 setSpan(vm.Matrix4 out, vm.Vector3 a, vm.Vector3 b, {double thickness = 1, bool stretch = true}) {
  final dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z;
  final len = math.sqrt(dx * dx + dy * dy + dz * dz);
  if (len < 1e-6) {
    return setTqs(out, a.x, a.y, a.z, _q..setValues(0, 0, 0, 1), 0, 0, 0);
  }
  // Rotation taking +y to the direction (shortest arc).
  final ux = dx / len, uy = dy / len, uz = dz / len;
  if (uy < -0.99999) {
    _q.setValues(1, 0, 0, 0);
  } else {
    // axis = y × u = (uz, 0, -ux); angle via half-vector.
    final w = 1 + uy;
    _q.setValues(uz, 0, -ux, w);
    _q.normalize();
  }
  return setTqs(out, (a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2, _q, thickness, stretch ? len : 1, thickness);
}
