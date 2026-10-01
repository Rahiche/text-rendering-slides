import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../deck/theme.dart';
import '../raster.dart';
import 'site_plan.dart';
import 'site_rubble.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The wall: one brick per raster pixel. Full-coverage bricks are solid white
// with a little bevel; anti-aliased edge pixels are "half bricks" of blue
// glass, as strong as their coverage — the anti-aliasing lesson made
// physical. Mortar joints run between neighbours.
//
// All bricks of a name are precomputed into one vertex mesh (mortar quad +
// brick quad per brick); a frame draws a prefix of it (the build order) or,
// during the demolition, the standing subset. One drawVertices call.
// ─────────────────────────────────────────────────────────────────────────────

const mortar = Color(0xFF1A3350);
const _glassLo = Color(0xFF20405F);
const _glassHi = Color(0xFFA7D3F7);

/// Coverage at or above this is a "full" brick.
const fullCover = 0.97;

int _argb(double a, double r, double g, double b) =>
    ((a * 255).round().clamp(0, 255) << 24) |
    ((r * 255).round().clamp(0, 255) << 16) |
    ((g * 255).round().clamp(0, 255) << 8) |
    (b * 255).round().clamp(0, 255);

int _scale(Color c, double k, [double toward = 0]) {
  double ch(double v) => (v * k + toward).clamp(0.0, 1.0);
  return _argb(c.a, ch(c.r), ch(c.g), ch(c.b));
}

/// Face colour of a brick (top and bottom of its bevel).
(int, int) brickColors(Brick b) {
  final v = 0.95 + 0.07 * hash(b.col, b.row, 11);
  if (b.cover >= fullCover) {
    return (_scale(BP.ink, v, 0.04), _scale(BP.ink, v * 0.86));
  }
  final c = Color.lerp(_glassLo, _glassHi, math.pow(b.cover, 0.85).toDouble())!;
  return (_scale(c, v, 0.05), _scale(c, v * 0.82));
}

/// A single colour per brick (for loose pieces).
int pieceColor(Brick b) => brickColors(b).$1;

class WallMesh {
  WallMesh(this.site) {
    final n = site.total;
    pos = Float32List(n * 16);
    col = Int32List(n * 8);
    idx = Uint16List(n * 12);
    final b = site.b;
    final m = math.max(0.75, b * 0.085);
    final mortarArgb = mortar.toARGB32();
    for (var i = 0; i < n; i++) {
      final k = site.r.bricks[i];
      final l = site.wall.left + k.col * b;
      final t = site.wall.top + k.row * b;
      final p = i * 16;
      // Mortar quad (the whole cell).
      _quad(p, l, t, l + b, t + b);
      // Brick quad, inset.
      _quad(p + 8, l + m, t + m, l + b - m, t + b - m);
      final (top, bottom) = brickColors(k);
      final c = i * 8;
      for (var j = 0; j < 4; j++) {
        col[c + j] = mortarArgb;
      }
      col[c + 4] = top;
      col[c + 5] = top;
      col[c + 6] = bottom;
      col[c + 7] = bottom;
      final v = i * 8, q = i * 12;
      for (final (o, base) in [(0, v), (6, v + 4)]) {
        idx[q + o] = base;
        idx[q + o + 1] = base + 1;
        idx[q + o + 2] = base + 2;
        idx[q + o + 3] = base;
        idx[q + o + 4] = base + 2;
        idx[q + o + 5] = base + 3;
      }
    }
  }

  void _quad(int p, double l, double t, double r, double b) {
    pos[p] = l;
    pos[p + 1] = t;
    pos[p + 2] = r;
    pos[p + 3] = t;
    pos[p + 4] = r;
    pos[p + 5] = b;
    pos[p + 6] = l;
    pos[p + 7] = b;
  }

  final SitePlan site;
  late final Float32List pos;
  late final Int32List col;
  late final Uint16List idx;

  ui.Vertices? _prefix;
  int _prefixK = -1;
  ui.Vertices? _subset;
  int _subsetVersion = -1;
  Rubble? _subsetOf;

  static final _paint = Paint();

  /// Draws bricks [0, k) (the standing wall during the build).
  void drawPrefix(Canvas c, int k, {Paint? tint}) {
    if (k <= 0) return;
    if (k != _prefixK) {
      _prefix?.dispose();
      _prefix = ui.Vertices.raw(
        ui.VertexMode.triangles,
        Float32List.sublistView(pos, 0, k * 16),
        colors: Int32List.sublistView(col, 0, k * 8),
        indices: Uint16List.sublistView(idx, 0, k * 12),
      );
      _prefixK = k;
    }
    c.drawVertices(_prefix!, tint == null ? BlendMode.dst : BlendMode.src, tint ?? _paint);
  }

  ui.Vertices? _flat;
  int _flatK = -1;

  /// Draws a prefix in one flat colour (tints the developed part of the
  /// wall during the reveal).
  void drawPrefixFlat(Canvas c, int k, Paint paint) {
    if (k <= 0) return;
    if (k != _flatK) {
      _flat?.dispose();
      _flat = ui.Vertices.raw(
        ui.VertexMode.triangles,
        Float32List.sublistView(pos, 0, k * 16),
        indices: Uint16List.sublistView(idx, 0, k * 12),
      );
      _flatK = k;
    }
    c.drawVertices(_flat!, BlendMode.src, paint);
  }

  /// Draws the bricks still standing in [r].
  void drawStanding(Canvas c, Rubble r) {
    if (r.standingCount <= 0) return;
    if (_subsetOf != r || _subsetVersion != r.standingVersion) {
      _subset?.dispose();
      final ids = Uint16List(r.standingCount * 12);
      var q = 0;
      final standing = Piece.standing.index;
      for (var i = 0; i < r.count && i < site.total; i++) {
        if (r.state[i] != standing) continue;
        if (q + 12 > ids.length) break;
        ids.setRange(q, q + 12, idx, i * 12);
        q += 12;
      }
      _subset = ui.Vertices.raw(
        ui.VertexMode.triangles,
        pos,
        colors: col,
        indices: Uint16List.sublistView(ids, 0, q),
      );
      _subsetOf = r;
      _subsetVersion = r.standingVersion;
    }
    c.drawVertices(_subset!, BlendMode.dst, _paint);
  }

  void dispose() {
    _prefix?.dispose();
    _subset?.dispose();
    _flat?.dispose();
    _prefix = null;
    _subset = null;
    _flat = null;
  }
}

/// Loose pieces as rotated quads (an outline-dark quad and the face), batched.
class PieceBatch {
  Float32List _pos = Float32List(0);
  Int32List _col = Int32List(0);
  Uint16List _idx = Uint16List(0);
  int _n = 0;

  void begin(int capacity) {
    if (_pos.length < capacity * 16) {
      _pos = Float32List(capacity * 16);
      _col = Int32List(capacity * 8);
      _idx = Uint16List(capacity * 12);
    }
    _n = 0;
  }

  int get length => _n;

  void add(double x, double y, double s, double a, int face, {double alpha = 1}) {
    if ((_n + 1) * 16 > _pos.length) return;
    final ca = math.cos(a), sa = math.sin(a);
    void quad(int p, double h) {
      final ux = ca * h, uy = sa * h, vx = -sa * h, vy = ca * h;
      _pos[p] = x - ux - vx;
      _pos[p + 1] = y - uy - vy;
      _pos[p + 2] = x + ux - vx;
      _pos[p + 3] = y + uy - vy;
      _pos[p + 4] = x + ux + vx;
      _pos[p + 5] = y + uy + vy;
      _pos[p + 6] = x - ux + vx;
      _pos[p + 7] = y - uy + vy;
    }

    final p = _n * 16;
    quad(p, s / 2);
    quad(p + 8, s / 2 - math.max(0.7, s * 0.1));
    final c = _n * 8;
    final edge = alpha >= 1 ? 0xFF0F2238 : _withAlpha(0xFF0F2238, alpha);
    final f = alpha >= 1 ? face : _withAlpha(face, alpha);
    for (var j = 0; j < 4; j++) {
      _col[c + j] = edge;
      _col[c + 4 + j] = f;
    }
    final v = _n * 8, q = _n * 12;
    for (final (o, base) in [(0, v), (6, v + 4)]) {
      _idx[q + o] = base;
      _idx[q + o + 1] = base + 1;
      _idx[q + o + 2] = base + 2;
      _idx[q + o + 3] = base;
      _idx[q + o + 4] = base + 2;
      _idx[q + o + 5] = base + 3;
    }
    _n++;
  }

  static int _withAlpha(int argb, double a) {
    final al = ((argb >>> 24) * a).round().clamp(0, 255);
    return (al << 24) | (argb & 0x00FFFFFF);
  }

  static final _paint = Paint();

  void draw(Canvas c) {
    if (_n == 0) return;
    final v = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(_pos, 0, _n * 16),
      colors: Int32List.sublistView(_col, 0, _n * 8),
      indices: Uint16List.sublistView(_idx, 0, _n * 12),
    );
    c.drawVertices(v, BlendMode.dst, _paint);
    v.dispose();
  }
}

/// The name drawn crisply over the bricks: fill and outline painters.
class CrispName {
  CrispName(NameRaster r) {
    final size = r.fontSize * r.brick;
    fill = TextPainter(
      text: TextSpan(text: r.name, style: NameRaster.nameStyle(size, color: BP.ink)),
      textDirection: TextDirection.ltr,
    )..layout();
    outline = TextPainter(
      text: TextSpan(
        text: r.name,
        style: NameRaster.nameStyle(size).copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.4, r.brick * 0.2)
            ..strokeJoin = StrokeJoin.round
            ..color = BP.amber,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    origin = r.textOrigin;
  }

  late final TextPainter fill;
  late final TextPainter outline;
  late final Offset origin;

  void dispose() {
    fill.dispose();
    outline.dispose();
  }
}
