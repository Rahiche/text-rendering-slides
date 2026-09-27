import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'font.dart';

/// A quadratic Bézier curve (p1 → p3, control p2). Straight lines are stored
/// as degenerate quadratics {p1, p3, p3}, as recommended by the reference.
class SlugCurve {
  const SlugCurve(this.x1, this.y1, this.x2, this.y2, this.x3, this.y3);

  final double x1, y1, x2, y2, x3, y3;

  double get minX => math.min(x1, math.min(x2, x3));
  double get maxX => math.max(x1, math.max(x2, x3));
  double get minY => math.min(y1, math.min(y2, y3));
  double get maxY => math.max(y1, math.max(y2, y3));

  /// Rays parallel to these can never cross them, so bands skip them.
  bool get isHorizontalLine => y1 == y2 && y2 == y3;
  bool get isVerticalLine => x1 == x2 && x2 == x3;
  bool get isPoint => isHorizontalLine && isVerticalLine;

  SlugCurve map(double Function(double) fx, double Function(double) fy) =>
      SlugCurve(fx(x1), fy(y1), fx(x2), fy(y2), fx(x3), fy(y3));

  @override
  bool operator ==(Object other) =>
      other is SlugCurve &&
      other.x1 == x1 &&
      other.y1 == y1 &&
      other.x2 == x2 &&
      other.y2 == y2 &&
      other.x3 == x3 &&
      other.y3 == y3;

  @override
  int get hashCode => Object.hash(x1, y1, x2, y2, x3, y3);

  @override
  String toString() => 'SlugCurve(($x1,$y1) ($x2,$y2) ($x3,$y3))';
}

/// Converts TrueType contours (on/off-curve points, implied midpoints) into
/// closed chains of quadratic curves, in font units.
List<SlugCurve> slugCurvesFromContours(List<List<SlugPoint>> contours) {
  final out = <SlugCurve>[];
  for (final c in contours) {
    if (c.length < 2) continue;
    final n = c.length;
    // Start on an on-curve point, or on the midpoint of two off-curve points.
    final first = c.indexWhere((p) => p.onCurve);
    double sx, sy;
    List<SlugPoint> seq;
    if (first < 0) {
      sx = (c.last.x + c.first.x) / 2;
      sy = (c.last.y + c.first.y) / 2;
      seq = c;
    } else {
      sx = c[first].x;
      sy = c[first].y;
      seq = [for (var i = 1; i <= n; i++) c[(first + i) % n]];
      // seq ends with the start point again (closing segment).
    }
    var px = sx, py = sy; // current pen
    SlugPoint? ctrl;
    void line(double x, double y) {
      if (x != px || y != py) out.add(SlugCurve(px, py, x, y, x, y));
      px = x;
      py = y;
    }

    void quad(double cx, double cy, double x, double y) {
      out.add(SlugCurve(px, py, cx, cy, x, y));
      px = x;
      py = y;
    }

    for (final p in seq) {
      if (p.onCurve) {
        if (ctrl != null) {
          quad(ctrl.x, ctrl.y, p.x, p.y);
          ctrl = null;
        } else {
          line(p.x, p.y);
        }
      } else {
        if (ctrl != null) quad(ctrl.x, ctrl.y, (ctrl.x + p.x) / 2, (ctrl.y + p.y) / 2);
        ctrl = p;
      }
    }
    if (ctrl != null) {
      quad(ctrl.x, ctrl.y, sx, sy);
    } else {
      line(sx, sy);
    }
  }
  return out;
}

/// One glyph packed into a [SlugAtlasData].
///
/// Curve coordinates live on a 12-bit grid: `font units = origin + quantum ·
/// grid`. With `quantum = 0.5` (any glyph narrower than 2048 units) TrueType
/// points and their implied midpoints are represented exactly.
class SlugGlyphData {
  SlugGlyphData._({
    required this.base,
    required this.originX,
    required this.originY,
    required this.quantum,
    required this.extentX,
    required this.extentY,
    required this.curves,
    required this.hBands,
    required this.vBands,
  });

  /// Index of the first texel (band headers) in the atlas.
  final int base;
  final double originX, originY, quantum;

  /// Largest grid coordinate in x / y (the grid starts at 0).
  final int extentX, extentY;

  /// Quantized curves, in grid units.
  final List<SlugCurve> curves;

  /// Curve indices per horizontal band (bottom → top), sorted by max x desc.
  final List<List<int>> hBands;

  /// Curve indices per vertical band (left → right), sorted by max y desc.
  final List<List<int>> vBands;

  int get hBandCount => hBands.length;
  int get vBandCount => vBands.length;

  /// Glyph bounds in font units (y up).
  Rect get bounds => Rect.fromLTRB(
    originX,
    originY,
    originX + extentX * quantum,
    originY + extentY * quantum,
  );

  /// Bands split the grid evenly: band index = floor(grid · scale).
  double get hBandScale => hBands.length / math.max(extentY, 1);
  double get vBandScale => vBands.length / math.max(extentX, 1);

  int get maxCurvesPerBand => [
    for (final b in hBands) b.length,
    for (final b in vBands) b.length,
  ].fold(0, math.max);

  /// Band edges in font units (for debug overlays).
  List<double> get hBandEdges => [
    for (var i = 0; i <= hBands.length; i++) originY + extentY * quantum * i / hBands.length,
  ];
  List<double> get vBandEdges => [
    for (var i = 0; i <= vBands.length; i++) originX + extentX * quantum * i / vBands.length,
  ];
}

/// The packed data texture for a set of glyphs: RGBA8, [width] a power of
/// two, alpha always 255 (so premultiplication and colour management are
/// no-ops). Every texel holds 24 bits:
///
/// * band header: `r` = curve count, `g·256 + b` = offset from glyph base;
/// * curve point: 12-bit x, 12-bit y: `r = x>>4`, `g = (x&15)<<4 | y>>8`,
///   `b = y&255`. A curve is 3 consecutive texels (p1, p2, p3).
///
/// Per glyph: `hBands` headers, then `vBands` headers, then the curve lists
/// (identical bands share one list).
class SlugAtlasData {
  SlugAtlasData(this.pixels, this.width, this.height, this.texelCount);

  final Uint8List pixels;
  final int width;
  final int height;
  final int texelCount;

  int get byteSize => pixels.length;

  /// Decodes texel [i] into its three bytes.
  (int, int, int) texel(int i) {
    final o = 4 * i;
    return (pixels[o], pixels[o + 1], pixels[o + 2]);
  }

  (int count, int offset) header(int i) {
    final (r, g, b) = texel(i);
    return (r, g * 256 + b);
  }

  (int x, int y) point(int i) {
    final (r, g, b) = texel(i);
    return (r * 16 + (g >> 4), (g & 15) * 256 + b);
  }
}

/// Builds a [SlugAtlasData] from glyph outlines.
class SlugEncoder {
  SlugEncoder();

  /// Texture width in texels (a power of two keeps the shader's index math exact).
  static const int textureWidth = 1024;

  /// Loop bound in the shader; bands never hold more curves than this.
  static const int maxCurvesPerBand = 64;
  static const int _gridMax = 4095;

  final List<int> _texels = [];

  int get texelCount => _texels.length;

  /// Encodes one glyph. Returns null for glyphs without area (e.g. space).
  SlugGlyphData? add(List<SlugCurve> fontCurves, {required int unitsPerEm, int maxBands = 16}) {
    final src = [for (final c in fontCurves) if (!c.isPoint) c];
    if (src.isEmpty) return null;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final c in src) {
      minX = math.min(minX, c.minX);
      minY = math.min(minY, c.minY);
      maxX = math.max(maxX, c.maxX);
      maxY = math.max(maxY, c.maxY);
    }
    final span = math.max(maxX - minX, maxY - minY);
    final q = span <= _gridMax / 2 ? 0.5 : span / _gridMax;
    double gx(double x) => ((x - minX) / q).roundToDouble().clamp(0, _gridMax.toDouble());
    double gy(double y) => ((y - minY) / q).roundToDouble().clamp(0, _gridMax.toDouble());
    final curves = [
      for (final c in src)
        if (c.map(gx, gy) case final g when !g.isPoint) g,
    ];
    if (curves.isEmpty) return null;
    final extentX = curves.fold<double>(0, (a, c) => math.max(a, c.maxX)).toInt();
    final extentY = curves.fold<double>(0, (a, c) => math.max(a, c.maxY)).toInt();
    if (extentX == 0 || extentY == 0) return null;

    // Bands overlap by 1/1024 em, as in the reference.
    final eps = unitsPerEm / 1024 / q;
    final hBands = _bands(
      curves,
      extentY.toDouble(),
      eps,
      maxBands,
      include: (c) => !c.isHorizontalLine,
      lo: (c) => c.minY,
      hi: (c) => c.maxY,
      sortKey: (c) => c.maxX,
    );
    final vBands = _bands(
      curves,
      extentX.toDouble(),
      eps,
      maxBands,
      include: (c) => !c.isVerticalLine,
      lo: (c) => c.minX,
      hi: (c) => c.maxX,
      sortKey: (c) => c.maxY,
    );

    final base = _texels.length;
    final headerCount = hBands.length + vBands.length;
    for (var i = 0; i < headerCount; i++) {
      _texels.add(0);
    }
    final shared = <String, int>{};
    var h = 0;
    for (final band in [...hBands, ...vBands]) {
      final key = band.join(',');
      final offset = shared.putIfAbsent(key, () {
        final o = _texels.length - base;
        for (final ci in band) {
          final c = curves[ci];
          _texels
            ..add(_pt(c.x1, c.y1))
            ..add(_pt(c.x2, c.y2))
            ..add(_pt(c.x3, c.y3));
        }
        return o;
      });
      if (offset > 0xFFFF) throw StateError('glyph too large for 16-bit band offsets');
      _texels[base + h] = band.length << 16 | offset;
      h++;
    }
    return SlugGlyphData._(
      base: base,
      originX: minX,
      originY: minY,
      quantum: q,
      extentX: extentX,
      extentY: extentY,
      curves: curves,
      hBands: hBands,
      vBands: vBands,
    );
  }

  static int _pt(double x, double y) => x.toInt() << 12 | y.toInt();

  static List<List<int>> _bands(
    List<SlugCurve> curves,
    double extent,
    double eps,
    int maxBands, {
    required bool Function(SlugCurve) include,
    required double Function(SlugCurve) lo,
    required double Function(SlugCurve) hi,
    required double Function(SlugCurve) sortKey,
  }) {
    final idx = [for (var i = 0; i < curves.length; i++) if (include(curves[i])) i];
    List<List<int>> split(int n) {
      final size = extent / n;
      return [
        for (var b = 0; b < n; b++)
          [
            for (final i in idx)
              if (hi(curves[i]) >= b * size - eps && lo(curves[i]) <= (b + 1) * size + eps) i,
          ]..sort((a, c) => sortKey(curves[c]).compareTo(sortKey(curves[a]))),
      ];
    }

    int worst(List<List<int>> bands) => bands.fold(0, (a, b) => math.max(a, b.length));
    // Minimise the busiest band (per-pixel cost) with a small price per band
    // (data size, header fetch); go past maxBands only to respect the loop bound.
    List<List<int>>? best;
    var bestCost = double.infinity;
    final limit = math.min(math.max(1, idx.length), 32);
    for (var n = 1; n <= limit; n++) {
      final bands = split(n);
      final w = worst(bands);
      if (n > maxBands && best != null && worst(best) <= maxCurvesPerBand) break;
      final cost = w + 0.35 * n + (w > maxCurvesPerBand ? 1000.0 * w : 0);
      if (cost < bestCost) {
        bestCost = cost;
        best = bands;
      }
    }
    final bands = best!;
    for (final b in bands) {
      if (b.length > maxCurvesPerBand) b.length = maxCurvesPerBand; // never in practice
    }
    return bands;
  }

  /// Packs everything added so far into RGBA8 pixels.
  SlugAtlasData finish() {
    const w = textureWidth;
    final h = math.max(1, (_texels.length + w - 1) ~/ w);
    final px = Uint8List(w * h * 4);
    for (var i = 0; i < _texels.length; i++) {
      final v = _texels[i];
      px[4 * i] = v >> 16 & 0xFF;
      px[4 * i + 1] = v >> 8 & 0xFF;
      px[4 * i + 2] = v & 0xFF;
    }
    for (var i = 3; i < px.length; i += 4) {
      px[i] = 255;
    }
    return SlugAtlasData(px, w, h, _texels.length);
  }
}
