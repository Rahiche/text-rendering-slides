import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_earcut/dart_earcut.dart';

import 'geometry.dart';

/// A glyph as a 3D triangle mesh: its outlines extruded to a solid letter,
/// front and back faces triangulated around the holes (earcut), side walls
/// with smooth normals along curves and hard edges at corners.
///
/// World units: x right, y up, z towards the viewer; the letter's ink sits
/// on y = 0, centred on x = 0, between z = ±depth/2. Counter-clockwise front
/// faces (glTF convention). Pure Dart: feed it to any engine.
class GlyphMesh {
  GlyphMesh(this.positions, this.normals, this.uvs, this.indices, this.width, this.height);

  /// x, y, z per vertex.
  final Float32List positions;

  /// Unit normal per vertex.
  final Float32List normals;

  /// u, v per vertex (faces: 0..1 over the ink box; sides: along the outline × depth).
  final Float32List uvs;

  final Uint32List indices;

  /// Ink size in world units.
  final double width;
  final double height;

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;
}

/// Extrudes [g] (raster px) into a [GlyphMesh]: [unitsPerPx] world units per
/// raster pixel, [depth] in world units. Outlines are simplified by
/// [simplify] px first.
GlyphMesh extrudeGlyph(GlyphGeometry g, {double unitsPerPx = 0.01, double depth = 0.3, double simplify = 0.5}) {
  final pos = <double>[], nor = <double>[], uv = <double>[];
  final idx = <int>[];
  if (g.isEmpty) {
    return GlyphMesh(Float32List(0), Float32List(0), Float32List(0), Uint32List(0), 0, 0);
  }
  final cx = g.inkLeft + g.inkWidth / 2, by = g.inkBottom;
  final w = g.inkWidth * unitsPerPx, h = g.inkHeight * unitsPerPx;
  // Rings in world xy (y up), simplified.
  final rings = <List<math.Point<double>>>[];
  final hole = <bool>[];
  for (final c in g.contours) {
    final p = simplifyClosed(c.pts, simplify);
    final n = p.length ~/ 2;
    if (n < 3) continue;
    rings.add([for (var i = 0; i < n; i++) math.Point((p[2 * i] - cx) * unitsPerPx, (by - p[2 * i + 1]) * unitsPerPx)]);
    hole.add(c.hole);
  }
  final minX = -w / 2, minY = 0.0;
  final zf = depth / 2, zb = -depth / 2;

  // ── Faces: each outer outline with the holes inside it ──────────────────
  final outers = [for (var i = 0; i < rings.length; i++) if (!hole[i]) i];
  final holesOf = {for (final o in outers) o: <int>[]};
  for (var i = 0; i < rings.length; i++) {
    if (!hole[i]) continue;
    int? best;
    var bestArea = double.infinity;
    for (final o in outers) {
      if (_inside(rings[i].first, rings[o])) {
        final a = _area(rings[o]).abs();
        if (a < bestArea) {
          bestArea = a;
          best = o;
        }
      }
    }
    if (best != null) holesOf[best]!.add(i);
  }
  for (final o in outers) {
    final pts = [rings[o], for (final hh in holesOf[o]!) rings[hh]];
    final flat = [for (final r in pts) ...r];
    final tris = Earcut.triangulateFromPointsAndHolePoints(
      outline: rings[o],
      holes: [for (final hh in holesOf[o]!) rings[hh]],
    );
    for (final (z, nz) in [(zf, 1.0), (zb, -1.0)]) {
      final base = pos.length ~/ 3;
      for (final p in flat) {
        pos.addAll([p.x, p.y, z]);
        nor.addAll([0, 0, nz]);
        uv.addAll([(p.x - minX) / w, 1 - (p.y - minY) / h]);
      }
      for (var t = 0; t + 2 < tris.length; t += 3) {
        var a = tris[t], b = tris[t + 1], c = tris[t + 2];
        final pa = flat[a], pb = flat[b], pc = flat[c];
        final cross = (pb.x - pa.x) * (pc.y - pa.y) - (pb.y - pa.y) * (pc.x - pa.x);
        // Front faces counter-clockwise seen from +z, back faces from -z.
        if ((cross < 0) == (nz > 0)) {
          final s = b;
          b = c;
          c = s;
        }
        idx.addAll([base + a, base + b, base + c]);
      }
    }
  }

  // ── Side walls ────────────────────────────────────────────────────────────
  bool solidAt(math.Point<double> p) {
    var inside = false;
    for (final r in rings) {
      if (_inside(p, r)) inside = !inside;
    }
    return inside;
  }

  const smoothCos = 0.77; // ~40°: smoother turns share a normal
  for (final r in rings) {
    final n = r.length;
    // Outward normal per edge: the right of travel, unless the solid is there.
    final en = <math.Point<double>>[];
    for (var i = 0; i < n; i++) {
      final a = r[i], b = r[(i + 1) % n];
      final dx = b.x - a.x, dy = b.y - a.y;
      final l = math.sqrt(dx * dx + dy * dy);
      en.add(l == 0 ? const math.Point(0.0, 0.0) : math.Point(dy / l, -dx / l));
    }
    var longest = 0;
    var best = -1.0;
    for (var i = 0; i < n; i++) {
      final a = r[i], b = r[(i + 1) % n];
      final l = a.distanceTo(b);
      if (l > best) {
        best = l;
        longest = i;
      }
    }
    final a0 = r[longest], b0 = r[(longest + 1) % n];
    final mid = math.Point((a0.x + b0.x) / 2, (a0.y + b0.y) / 2);
    final probe = math.Point(mid.x + en[longest].x * unitsPerPx * 0.35, mid.y + en[longest].y * unitsPerPx * 0.35);
    final flip = solidAt(probe) ? -1.0 : 1.0;
    math.Point<double> vn(int edge, int other) {
      final e = en[edge] * flip, o = en[other] * flip;
      if (e.x * o.x + e.y * o.y > smoothCos) {
        final s = math.Point(e.x + o.x, e.y + o.y);
        final l = math.sqrt(s.x * s.x + s.y * s.y);
        return l == 0 ? e : math.Point(s.x / l, s.y / l);
      }
      return e;
    }

    var along = 0.0;
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final a = r[i], b = r[j];
      final l = a.distanceTo(b);
      if (l == 0) continue;
      final na = vn(i, (i - 1 + n) % n), nb = vn(i, j);
      final base = pos.length ~/ 3;
      final u0 = along / math.max(w, h), u1 = (along + l) / math.max(w, h);
      along += l;
      // A: a front, B: b front, C: b back, D: a back.
      pos.addAll([a.x, a.y, zf, b.x, b.y, zf, b.x, b.y, zb, a.x, a.y, zb]);
      nor.addAll([na.x, na.y, 0, nb.x, nb.y, 0, nb.x, nb.y, 0, na.x, na.y, 0]);
      uv.addAll([u0, 0, u1, 0, u1, 1, u0, 1]);
      // (A, B, C) faces the left of travel; use it when that's outward.
      final e = en[i] * flip;
      final leftX = -(b.y - a.y), leftY = b.x - a.x;
      if (leftX * e.x + leftY * e.y > 0) {
        idx.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
      } else {
        idx.addAll([base, base + 2, base + 1, base, base + 3, base + 2]);
      }
    }
  }
  return GlyphMesh(
    Float32List.fromList(pos),
    Float32List.fromList(nor),
    Float32List.fromList(uv),
    Uint32List.fromList(idx),
    w,
    h,
  );
}

double _area(List<math.Point<double>> r) {
  var s = 0.0;
  for (var i = 0; i < r.length; i++) {
    final a = r[i], b = r[(i + 1) % r.length];
    s += a.x * b.y - b.x * a.y;
  }
  return s / 2;
}

bool _inside(math.Point<double> p, List<math.Point<double>> r) {
  var inside = false;
  for (var i = 0, j = r.length - 1; i < r.length; j = i++) {
    final a = r[i], b = r[j];
    if ((a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) {
      inside = !inside;
    }
  }
  return inside;
}
