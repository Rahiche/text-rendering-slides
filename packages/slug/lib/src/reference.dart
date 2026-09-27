import 'dart:math' as math;

import 'encoder.dart';

/// Result of [slugCoverageCpu].
class SlugSample {
  const SlugSample(this.coverage, this.tested);

  final double coverage;

  /// Curves examined by both rays (what the heat map shows).
  final int tested;
}

/// A CPU port of `shaders/slug.frag`, reading the same packed texels.
///
/// [gx], [gy] are glyph-grid coordinates of the pixel centre; [ppuX], [ppuY]
/// pixels per grid unit. Used by tests to check the data format and the
/// algorithm independently of the GPU.
SlugSample slugCoverageCpu(
  SlugAtlasData data,
  SlugGlyphData g,
  double gx,
  double gy,
  double ppuX,
  double ppuY,
) {
  double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
  final base = g.base;
  final by = (gy * g.hBandScale).floor().clamp(0, g.hBandCount - 1);
  final bx = (gx * g.vBandScale).floor().clamp(0, g.vBandCount - 1);
  final (hCount, hOff) = data.header(base + by);
  final (vCount, vOff) = data.header(base + g.hBandCount + bx);
  var tested = 0;

  var xcov = 0.0, xwgt = 0.0;
  for (var i = 0; i < hCount; i++) {
    final t = base + hOff + 3 * i;
    final (x1, y1) = data.point(t);
    final (x2, y2) = data.point(t + 1);
    final (x3, y3) = data.point(t + 2);
    if (math.max(math.max(x1 - gx, x2 - gx), x3 - gx) * ppuX < -0.5) break;
    tested++;
    final n1 = y1 - gy < 0, n2 = y2 - gy < 0, n3 = y3 - gy < 0;
    final e1 = _eligible1(n1, n2, n3), e2 = _eligible2(n1, n2, n3);
    if (!e1 && !e2) continue;
    final r = _solve(
      (y1 - 2 * y2 + y3).toDouble(),
      (y1 - y2).toDouble(),
      y1 - gy,
      (x1 - 2 * x2 + x3).toDouble(),
      (x1 - x2).toDouble(),
      x1 - gx,
    );
    final r1 = r.$1 * ppuX, r2 = r.$2 * ppuX;
    if (e1) {
      xcov += clamp01(r1 + 0.5);
      xwgt = math.max(xwgt, clamp01(1 - r1.abs() * 2));
    }
    if (e2) {
      xcov -= clamp01(r2 + 0.5);
      xwgt = math.max(xwgt, clamp01(1 - r2.abs() * 2));
    }
  }

  var ycov = 0.0, ywgt = 0.0;
  for (var i = 0; i < vCount; i++) {
    final t = base + vOff + 3 * i;
    final (x1, y1) = data.point(t);
    final (x2, y2) = data.point(t + 1);
    final (x3, y3) = data.point(t + 2);
    if (math.max(math.max(y1 - gy, y2 - gy), y3 - gy) * ppuY < -0.5) break;
    tested++;
    final n1 = x1 - gx < 0, n2 = x2 - gx < 0, n3 = x3 - gx < 0;
    final e1 = _eligible1(n1, n2, n3), e2 = _eligible2(n1, n2, n3);
    if (!e1 && !e2) continue;
    final r = _solve(
      (x1 - 2 * x2 + x3).toDouble(),
      (x1 - x2).toDouble(),
      x1 - gx,
      (y1 - 2 * y2 + y3).toDouble(),
      (y1 - y2).toDouble(),
      y1 - gy,
    );
    final r1 = r.$1 * ppuY, r2 = r.$2 * ppuY;
    if (e1) {
      ycov -= clamp01(r1 + 0.5);
      ywgt = math.max(ywgt, clamp01(1 - r1.abs() * 2));
    }
    if (e2) {
      ycov += clamp01(r2 + 0.5);
      ywgt = math.max(ywgt, clamp01(1 - r2.abs() * 2));
    }
  }

  final cov = math.max(
    (xcov * xwgt + ycov * ywgt).abs() / math.max(xwgt + ywgt, 1 / 65536),
    math.min(xcov.abs(), ycov.abs()),
  );
  return SlugSample(clamp01(cov), tested);
}

/// Root eligibility by control-point signs: the reference's `0x2E74` table.
///
/// | y3<0 y2<0 y1<0 | root 1 | root 2 |
/// |  0    0    0   |   -    |   -    |
/// |  0    0    1   |   -    |   ✓    |
/// |  0    1    0   |   ✓    |   ✓    |
/// |  0    1    1   |   -    |   ✓    |
/// |  1    0    0   |   ✓    |   -    |
/// |  1    0    1   |   ✓    |   ✓    |
/// |  1    1    0   |   ✓    |   -    |
/// |  1    1    1   |   -    |   -    |
bool slugRootEligible(int which, bool n1, bool n2, bool n3) =>
    which == 1 ? _eligible1(n1, n2, n3) : _eligible2(n1, n2, n3);

bool _eligible1(bool n1, bool n2, bool n3) => (!n1 && (n2 || n3)) || (n1 && !n2 && n3);

bool _eligible2(bool n1, bool n2, bool n3) => (n1 && !(n2 && n3)) || (!n1 && n2 && !n3);

(double, double) _solve(double a, double b, double c, double oa, double ob, double oc) {
  double t1, t2;
  final disc = b * b - a * c;
  if (a.abs() < 0.25) {
    t1 = t2 = c * 0.5 / b;
  } else if (disc <= 0) {
    t1 = t2 = b / a;
  } else {
    final d = math.sqrt(disc);
    if (b >= 0) {
      t1 = c / (b + d);
      t2 = (b + d) / a;
    } else {
      t1 = (b - d) / a;
      t2 = c / (b - d);
    }
  }
  return ((oa * t1 - ob * 2) * t1 + oc, (oa * t2 - ob * 2) * t2 + oc);
}
