import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:text_slides/booth/craft/extrude.dart';
import 'package:text_slides/booth/craft/geometry.dart';

GlyphGeometry ring() {
  const w = 60, h = 60;
  final a = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final outer = x >= 8 && x < 52 && y >= 8 && y < 52;
      final inner = x >= 20 && x < 40 && y >= 20 && y < 40;
      if (outer && !inner) a[y * w + x] = 255;
    }
  }
  return vectorize(VectorizeInput(w, h, a));
}

void main() {
  test('a square ring extrudes to a closed solid with outward normals', () {
    final g = ring();
    final m = extrudeGlyph(g, unitsPerPx: 0.1, depth: 1);
    expect(m.width, closeTo(4.4, 0.05));
    expect(m.height, closeTo(4.4, 0.05));
    // Front face area = ring area (44² − 20²) × 0.01 = 15.36.
    var front = 0.0;
    for (var t = 0; t < m.indices.length; t += 3) {
      final a = m.indices[t], b = m.indices[t + 1], c = m.indices[t + 2];
      if (m.normals[a * 3 + 2] < 0.9) continue;
      final ax = m.positions[a * 3], ay = m.positions[a * 3 + 1];
      final bx = m.positions[b * 3], by = m.positions[b * 3 + 1];
      final cx = m.positions[c * 3], cy = m.positions[c * 3 + 1];
      final cross = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
      expect(cross, greaterThan(0), reason: 'front faces are counter-clockwise');
      front += cross / 2;
    }
    expect(front, closeTo(15.36, 0.3));
    // Every side wall normal points away from the solid: stepping along it
    // from the wall lands outside the ring (or in the hole).
    for (var v = 0; v < m.vertexCount; v++) {
      final nz = m.normals[v * 3 + 2];
      if (nz.abs() > 0.1) continue;
      final x = m.positions[v * 3] + m.normals[v * 3] * 0.3;
      final y = m.positions[v * 3 + 1] + m.normals[v * 3 + 1] * 0.3;
      // Ring in world units: outer |x| < 2.2, y in [0, 4.4]; hole |x| < 1, y in [1.2, 3.2].
      final inOuter = x.abs() < 2.2 && y > 0 && y < 4.4;
      final inHole = x.abs() < 1.0 && y > 1.2 && y < 3.2;
      expect(inOuter && !inHole, isFalse, reason: 'normal at ($x, $y) points into the solid');
    }
  });
}
