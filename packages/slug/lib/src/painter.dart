import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'encoder.dart';
import 'font.dart';

/// Glyphs of one or more fonts, encoded and uploaded as one data texture.
class SlugAtlas {
  SlugAtlas._(this.data, this.image, this._glyphs);

  /// The packed texels (CPU copy, used by overlays and tests).
  final SlugAtlasData data;

  /// The same texels as a GPU image (sampled with nearest filtering).
  final ui.Image image;
  final Map<(int, int), SlugGlyphData?> _glyphs;

  /// Encoded glyph for ([font], [gid]); null if it has no outline or is missing.
  SlugGlyphData? glyph(SlugFont font, int gid) => _glyphs[(font.id, gid)];

  bool contains(SlugFont font, int gid) => _glyphs.containsKey((font.id, gid));

  Iterable<SlugGlyphData> get glyphs => _glyphs.values.whereType<SlugGlyphData>();

  int get curveCount => glyphs.fold(0, (a, g) => a + g.curves.length);
  int get bandCount => glyphs.fold(0, (a, g) => a + g.hBandCount + g.vBandCount);

  /// Encodes [data] only (no GPU upload); useful for tests.
  static (SlugAtlasData, Map<(int, int), SlugGlyphData?>) encode(Iterable<(SlugFont, int)> glyphs) {
    final enc = SlugEncoder();
    final map = <(int, int), SlugGlyphData?>{};
    for (final (font, gid) in glyphs) {
      final key = (font.id, gid);
      if (map.containsKey(key)) continue;
      map[key] = enc.add(slugCurvesFromContours(font.contours(gid)), unitsPerEm: font.unitsPerEm);
    }
    return (enc.finish(), map);
  }

  /// Encodes the glyphs and uploads them as an RGBA8 image.
  static Future<SlugAtlas> build(Iterable<(SlugFont, int)> glyphs) async {
    final (data, map) = encode(glyphs);
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(data.pixels, data.width, data.height, ui.PixelFormat.rgba8888, c.complete);
    return SlugAtlas._(data, await c.future, map);
  }

  /// All glyphs needed to draw [runs] (cmap lookup per code point).
  static Future<SlugAtlas> forText(Iterable<(SlugFont, String)> runs) => build([
    for (final (font, text) in runs)
      for (final cp in text.runes) (font, font.glyphId(cp)),
  ]);

  void dispose() => image.dispose();
}

/// Loads the Slug fragment program (once).
abstract final class SlugShader {
  static ui.FragmentProgram? _loaded;
  static Future<ui.FragmentProgram>? _loading;

  /// The program, if already loaded (lets widgets draw on their first frame).
  static ui.FragmentProgram? get loaded => _loaded;

  static Future<ui.FragmentProgram> load() async {
    final done = _loaded;
    if (done != null) return done;
    final p = await (_loading ??= _fromAsset());
    return _loaded = p;
  }

  static Future<ui.FragmentProgram> _fromAsset() async {
    try {
      return await ui.FragmentProgram.fromAsset('packages/slug/shaders/slug.frag');
    } catch (_) {
      // When the package itself is the root (its own tests).
      return ui.FragmentProgram.fromAsset('shaders/slug.frag');
    }
  }
}

/// Draws encoded glyphs with the Slug shader: one quad per glyph.
///
/// Reuses one [ui.FragmentShader]; uniforms are copied into each draw call.
class SlugPainter {
  SlugPainter(ui.FragmentProgram program, this.atlas)
    : _shader = program.fragmentShader() {
    _shader.setImageSampler(0, atlas.image);
    _paint = Paint()
      ..shader = _shader
      ..isAntiAlias = false;
  }

  final SlugAtlas atlas;
  final ui.FragmentShader _shader;
  late final Paint _paint;

  /// Draws [g] with its pen (origin on the baseline) at [pen], [scale] local
  /// px per font unit. [toDevice] maps the canvas' current local coordinates
  /// to device pixels (column-major 4×4, as [Canvas.getTransform]).
  ///
  /// Returns the (dilated) quad that was drawn.
  Rect drawGlyph(
    Canvas canvas,
    SlugGlyphData g, {
    required Offset pen,
    required double scale,
    required Float64List toDevice,
    required Color color,
    bool heat = false,
    bool dilate = true,
  }) {
    final m = toDevice;
    final h = _Homography(m);
    final q = g.quantum;
    final a = 1 / (scale * q);
    final b = Rect.fromLTRB(
      pen.dx + g.bounds.left * scale,
      pen.dy - g.bounds.bottom * scale,
      pen.dx + g.bounds.right * scale,
      pen.dy - g.bounds.top * scale,
    );
    final quad = dilate ? h.dilate(b) : b;
    final s = _shader;
    var i = 0;
    void f(double v) => s.setFloat(i++, v);
    f(atlas.data.width.toDouble());
    f(atlas.data.height.toDouble());
    f(g.base.toDouble());
    f(heat ? 1 : 0);
    f(h.h00);
    f(h.h01);
    f(h.h02);
    f(0);
    f(h.h10);
    f(h.h11);
    f(h.h12);
    f(0);
    f(h.h20);
    f(h.h21);
    f(h.h22);
    f(0);
    f(a);
    f(-(pen.dx / scale + g.originX) / q);
    f((pen.dy / scale - g.originY) / q);
    f(0);
    f(g.hBandCount.toDouble());
    f(g.vBandCount.toDouble());
    f(g.hBandScale);
    f(g.vBandScale);
    f(color.r * color.a);
    f(color.g * color.a);
    f(color.b * color.a);
    f(color.a);
    canvas.drawRect(quad, _paint);
    return quad;
  }

  void dispose() => _shader.dispose();
}

/// The local → device map of a 4×4 transform restricted to the z = 0 plane.
class _Homography {
  _Homography(Float64List m)
    : h00 = m[0],
      h01 = m[4],
      h02 = m[12],
      h10 = m[1],
      h11 = m[5],
      h12 = m[13],
      h20 = m[3],
      h21 = m[7],
      h22 = m[15];

  final double h00, h01, h02, h10, h11, h12, h20, h21, h22;

  /// Local units per device pixel along local x and y (L1 footprint of one
  /// device pixel, like fwidth), or null behind the camera / degenerate.
  (double, double)? localPerPixel(double x, double y) {
    final w = h20 * x + h21 * y + h22;
    if (w <= 1e-9) return null;
    final u = (h00 * x + h01 * y + h02) / w;
    final v = (h10 * x + h11 * y + h12) / w;
    final j00 = (h00 - u * h20) / w, j01 = (h01 - u * h21) / w;
    final j10 = (h10 - v * h20) / w, j11 = (h11 - v * h21) / w;
    final det = (j00 * j11 - j01 * j10).abs();
    if (det < 1e-20) return null;
    return ((j11.abs() + j01.abs()) / det, (j10.abs() + j00.abs()) / det);
  }

  /// Dynamic dilation: grow the quad so every pixel whose centre is within
  /// half a pixel of the glyph box is rasterized (computed per corner).
  Rect dilate(Rect r) {
    var ex = 0.0, ey = 0.0;
    for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      final l = localPerPixel(c.dx, c.dy);
      if (l == null) continue;
      ex = math.max(ex, l.$1);
      ey = math.max(ey, l.$2);
    }
    final dx = 0.5 * ex + 1e-4, dy = 0.5 * ey + 1e-4;
    return Rect.fromLTRB(r.left - dx, r.top - dy, r.right + dx, r.bottom + dy);
  }
}

/// Local units per device pixel at ([x], [y]) for the column-major transform
/// [m]: useful for constant-size debug marks under zoom and perspective.
double slugLocalPerPixel(Float64List m, double x, double y) {
  final h = _Homography(m);
  final w = h.h20 * x + h.h21 * y + h.h22;
  if (w <= 1e-9) return 1;
  final u = (h.h00 * x + h.h01 * y + h.h02) / w;
  final v = (h.h10 * x + h.h11 * y + h.h12) / w;
  final det = ((h.h00 - u * h.h20) * (h.h11 - v * h.h21) - (h.h01 - u * h.h21) * (h.h10 - v * h.h20)) / (w * w);
  return det.abs() < 1e-20 ? 1 : 1 / math.sqrt(det.abs());
}

@visibleForTesting
Rect slugDilate(Float64List m, Rect r) => _Homography(m).dilate(r);
