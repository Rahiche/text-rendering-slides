import 'dart:math' as math;
import 'dart:ui';

import 'geometry.dart';

/// A character placed on the canvas (on the dais), with its vectorized
/// geometry turned into paths and the helpers crafts use to draw it being
/// made: a tool tip travelling along the outline or the strokes, partial
/// paths, brush masks, and "reveal the glyph where I painted" layers.
class GlyphStage {
  GlyphStage._(this.geo, this.k, this.origin) {
    for (final c in geo.contours) {
      final p = Path()..fillType = PathFillType.evenOdd;
      for (var i = 0; i < c.count; i++) {
        final o = map(c.pts[2 * i], c.pts[2 * i + 1]);
        i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
      }
      p.close();
      contours.add(p);
      outline.addPath(p, Offset.zero);
      final m = p.computeMetrics().first;
      contourMetrics.add(m);
      _contourStart.add(outlineLength);
      outlineLength += m.length;
      contourHole.add(c.hole);
    }
    for (final s in geo.strokes) {
      var pts = [for (var i = 0; i < s.count; i++) map(s.pts[2 * i], s.pts[2 * i + 1])];
      var rad = [for (var i = 0; i < s.count; i++) s.radius[i] * k];
      if (pts.length == 1) {
        // A dot (the dakuten's tick, the i's dot): give it a little length.
        final r = rad.first;
        pts = [pts.first - Offset(r * 0.4, 0), pts.first + Offset(r * 0.4, 0)];
        rad = [r, r];
      }
      final arc = <double>[0];
      for (var i = 1; i < pts.length; i++) {
        arc.add(arc.last + (pts[i] - pts[i - 1]).distance);
      }
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      strokes.add(StagedStroke(pts, rad, arc, path, strokeLength));
      strokeLength += arc.last;
    }
    ink = Rect.fromLTRB(
      origin.dx + geo.inkLeft * k,
      origin.dy + geo.inkTop * k,
      origin.dx + geo.inkRight * k,
      origin.dy + geo.inkBottom * k,
    );
  }

  /// Fits the glyph's ink into [box]: as large as fits, centred
  /// horizontally, standing on the box's bottom edge.
  factory GlyphStage.fit(GlyphGeometry geo, Rect box) {
    if (geo.isEmpty) return GlyphStage._(geo, 1, box.bottomCenter);
    final k = math.min(box.width / geo.inkWidth, box.height / geo.inkHeight);
    final origin = Offset(
      box.center.dx - (geo.inkLeft + geo.inkWidth / 2) * k,
      box.bottom - geo.inkBottom * k,
    );
    return GlyphStage._(geo, k, origin);
  }

  final GlyphGeometry geo;

  /// Raster px → canvas px.
  final double k;
  final Offset origin;

  Offset map(double x, double y) => origin + Offset(x * k, y * k);

  /// The glyph's ink bounds on the canvas.
  late final Rect ink;

  /// The whole glyph (outer outlines and holes, even-odd).
  final outline = Path()..fillType = PathFillType.evenOdd;

  /// Each closed outline, outer ones first (largest first), then holes.
  final contours = <Path>[];
  final contourHole = <bool>[];
  final contourMetrics = <PathMetric>[];
  final _contourStart = <double>[];
  double outlineLength = 0;

  /// Centre-line strokes in writing order.
  final strokes = <StagedStroke>[];
  double strokeLength = 0;

  /// Stroke widths are this × the typical half-width.
  double get typicalRadius {
    if (strokes.isEmpty) return 4;
    final r = [for (final s in strokes) ...s.radius]..sort();
    return r[r.length ~/ 2];
  }

  // ── Along the outline ─────────────────────────────────────────────────────

  /// Where a tool tracing every outline in turn is at fraction [p], and
  /// which way it's heading.
  Tangent outlineAt(double p) {
    if (contourMetrics.isEmpty) return Tangent(ink.center, const Offset(1, 0));
    final d = (p.clamp(0.0, 1.0)) * outlineLength;
    var i = contourMetrics.length - 1;
    while (i > 0 && _contourStart[i] > d) {
      i--;
    }
    final m = contourMetrics[i];
    return m.getTangentForOffset((d - _contourStart[i]).clamp(0.0, m.length)) ??
        Tangent(ink.center, const Offset(1, 0));
  }

  /// The outlines traced up to fraction [p] (open paths).
  Path outlineUpTo(double p) {
    final out = Path();
    final d = p.clamp(0.0, 1.0) * outlineLength;
    for (var i = 0; i < contourMetrics.length; i++) {
      final s = _contourStart[i];
      if (d <= s) break;
      final m = contourMetrics[i];
      out.addPath(m.extractPath(0, math.min(m.length, d - s)), Offset.zero);
    }
    return out;
  }

  // ── Along the strokes ─────────────────────────────────────────────────────

  /// Where a pen writing every stroke in order is at fraction [p]: the
  /// stroke index, position, half-width and direction.
  ({int stroke, Offset pos, double radius, Offset dir}) strokeAt(double p) {
    if (strokes.isEmpty) return (stroke: 0, pos: ink.center, radius: 4, dir: const Offset(1, 0));
    final d = p.clamp(0.0, 1.0) * strokeLength;
    var i = strokes.length - 1;
    while (i > 0 && strokes[i].start > d) {
      i--;
    }
    final s = strokes[i];
    final (pos, r, dir) = s.at(d - s.start);
    return (stroke: i, pos: pos, radius: r, dir: dir);
  }

  /// Paints the strokes written up to fraction [p] as round-capped segments
  /// of the stroke's own width × [grow] — a brush mask that, intersected
  /// with the glyph ([reveal]), uncovers exactly the written part.
  void paintStrokesUpTo(Canvas c, double p, Paint paint, {double grow = 1.2}) {
    final d = p.clamp(0.0, 1.0) * strokeLength;
    paint
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final s in strokes) {
      if (d <= s.start) break;
      final upto = d - s.start;
      for (var i = 1; i < s.pts.length; i++) {
        if (s.arc[i - 1] >= upto) break;
        final f = s.arc[i] <= upto ? 1.0 : (upto - s.arc[i - 1]) / (s.arc[i] - s.arc[i - 1]);
        final a = s.pts[i - 1], b = Offset.lerp(s.pts[i - 1], s.pts[i], f)!;
        paint.strokeWidth = 2 * grow * math.max(s.radius[i - 1], s.radius[i]) + 1;
        c.drawLine(a, b, paint);
      }
    }
  }

  // ── Rows ──────────────────────────────────────────────────────────────────

  /// The inside of every raster row as canvas rects, top row first.
  late final List<Rect> rows = [
    for (final s in geo.spans)
      Rect.fromLTRB(
        origin.dx + s.x0 * k,
        origin.dy + s.y * k,
        origin.dx + s.x1 * k,
        origin.dy + (s.y + 1) * k,
      ),
  ];

  // ── Layers ────────────────────────────────────────────────────────────────

  /// Draws [material] only where [mask] painted (and only inside the glyph
  /// if the material fills [outline]): e.g. a brush revealing the letter.
  void reveal(
    Canvas c,
    void Function(Canvas c) mask,
    void Function(Canvas c) material, {
    double margin = 40,
  }) {
    final r = ink.inflate(margin);
    c.saveLayer(r, Paint());
    mask(c);
    c.saveLayer(r, Paint()..blendMode = BlendMode.srcIn);
    material(c);
    c.restore();
    c.restore();
  }

  /// Runs [paint] clipped to the glyph.
  void clipped(Canvas c, void Function() paint) {
    c.save();
    c.clipPath(outline);
    paint();
    c.restore();
  }
}

/// One stroke on the canvas: points, half-widths, arc length per point.
class StagedStroke {
  StagedStroke(this.pts, this.radius, this.arc, this.path, this.start);

  final List<Offset> pts;
  final List<double> radius;
  final List<double> arc;
  final Path path;

  /// Where this stroke starts along all strokes (canvas px).
  final double start;

  double get length => arc.last;

  (Offset, double, Offset) at(double d) {
    if (pts.length == 1) return (pts.first, radius.first, const Offset(1, 0));
    d = d.clamp(0.0, length);
    var i = 1;
    while (i < pts.length - 1 && arc[i] < d) {
      i++;
    }
    final seg = arc[i] - arc[i - 1];
    final f = seg <= 0 ? 0.0 : (d - arc[i - 1]) / seg;
    final pos = Offset.lerp(pts[i - 1], pts[i], f)!;
    final r = radius[i - 1] + (radius[i] - radius[i - 1]) * f;
    final v = pts[i] - pts[i - 1];
    final l = v.distance;
    return (pos, r, l == 0 ? const Offset(1, 0) : v / l);
  }
}
