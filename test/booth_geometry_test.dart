import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:text_slides/booth/craft/geometry.dart';

/// A w×h raster with [inside] pixels at full coverage.
VectorizeInput raster(int w, int h, bool Function(int x, int y) inside) {
  final a = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (inside(x, y)) a[y * w + x] = 255;
    }
  }
  return VectorizeInput(w, h, a);
}

bool horizontal(Stroke s) {
  final n = s.count;
  return (s.pts[2 * n - 2] - s.pts[0]).abs() > (s.pts[2 * n - 1] - s.pts[1]).abs();
}

void main() {
  test('empty raster → empty geometry', () {
    final g = vectorize(raster(20, 20, (x, y) => false));
    expect(g.isEmpty, isTrue);
    expect(g.strokes, isEmpty);
  });

  test('bar: one outline, one left→right stroke, half-width ≈ 3', () {
    final g = vectorize(raster(60, 20, (x, y) => x >= 5 && x < 55 && y >= 7 && y < 13));
    expect(g.contours.length, 1);
    expect(g.contours.single.hole, isFalse);
    expect(g.contours.single.area, closeTo(300, 30));
    expect(g.strokes.length, 1);
    final s = g.strokes.single;
    expect(horizontal(s), isTrue);
    expect(s.pts[0], lessThan(s.pts[2 * s.count - 2]), reason: 'left to right');
    expect(s.maxRadius, closeTo(3, 1));
    expect(g.inkLeft, 5);
    expect(g.inkRight, 55);
    expect(g.spans.length, 6);
  });

  test('ring: outer outline + hole, one closed stroke', () {
    final g = vectorize(raster(60, 60, (x, y) {
      final d = math.sqrt(math.pow(x + 0.5 - 30, 2) + math.pow(y + 0.5 - 30, 2));
      return d < 22 && d > 14;
    }));
    expect(g.contours.where((c) => !c.hole).length, 1);
    expect(g.contours.where((c) => c.hole).length, 1);
    expect(g.strokes.length, 1);
    expect(g.strokes.single.pathLength, closeTo(2 * math.pi * 18, 15));
  });

  test('十: two strokes, horizontal first', () {
    final g = vectorize(raster(60, 60, (x, y) => (y >= 26 && y < 33 && x >= 6 && x < 54) || (x >= 27 && x < 34 && y >= 4 && y < 56)));
    expect(g.strokes.length, 2);
    expect(horizontal(g.strokes[0]), isTrue);
    expect(horizontal(g.strokes[1]), isFalse);
    expect(g.strokes[1].pts[1], lessThan(g.strokes[1].pts[2 * g.strokes[1].count - 1]), reason: 'top to bottom');
  });

  test('L: split at the corner, vertical first', () {
    final g = vectorize(raster(50, 60, (x, y) => (x >= 8 && x < 15 && y >= 5 && y < 52) || (y >= 45 && y < 52 && x >= 8 && x < 44)));
    expect(g.strokes.length, 2);
    expect(horizontal(g.strokes[0]), isFalse);
    expect(horizontal(g.strokes[1]), isTrue);
  });

  test('口: outline + hole; four sides, the left side first', () {
    final g = vectorize(raster(60, 60, (x, y) {
      final outer = x >= 8 && x < 52 && y >= 8 && y < 52;
      final inner = x >= 16 && x < 44 && y >= 16 && y < 44;
      return outer && !inner;
    }));
    expect(g.contours.where((c) => c.hole).length, 1);
    expect(g.strokes.length, 4);
    expect(horizontal(g.strokes.first), isFalse);
    expect(g.strokes.first.pts[0], lessThan(20), reason: 'left side');
  });
}
