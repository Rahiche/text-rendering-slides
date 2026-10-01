import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../deck/theme.dart';
import 'layout.dart';
import 'web_fonts.dart';

/// One pixel of the name's raster, laid as one brick.
class Brick {
  const Brick(this.col, this.row, this.cover, this.zone);

  /// Column / row in the raster (row 0 = top).
  final int col;
  final int row;

  /// Coverage 0..1 from the real rasterizer: < 1 is an anti-aliased edge.
  final double cover;

  /// Which builder's stretch of the wall this brick is in (0..zones-1).
  final int zone;
}

/// A name rasterized by the engine (real coverage), as bricks on the plot.
class NameRaster {
  NameRaster._({
    required this.name,
    required this.cols,
    required this.rows,
    required this.bricks,
    required this.fontSize,
    required this.inkOffset,
    required this.brick,
    required this.origin,
  });

  static const zones = 6;

  final String name;
  final int cols;
  final int rows;

  /// In build order: bottom row first, round-robin across [zones].
  final List<Brick> bricks;

  /// Font size the name was rasterized at (1 raster px = 1 brick).
  final double fontSize;

  /// Where the TextPainter's origin sits relative to the raster's top-left,
  /// in raster px (so crisp text can be drawn exactly over the bricks).
  final Offset inkOffset;

  /// Brick size on the canvas.
  final double brick;

  /// Canvas position of the raster's top-left corner.
  final Offset origin;

  Rect get bounds => origin & Size(cols * brick, rows * brick);

  /// Canvas rect of [b].
  Rect rectOf(Brick b) =>
      Rect.fromLTWH(origin.dx + b.col * brick, origin.dy + b.row * brick, brick, brick);

  /// The name drawn crisply at the bricks' scale: paint it at [textOrigin].
  TextPainter crisp({Color color = BP.ink}) => TextPainter(
    text: TextSpan(
      text: name,
      style: nameStyle(fontSize * brick, color: color),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  Offset get textOrigin => origin - inkOffset * brick;

  /// The style names are built in: Space Grotesk, Japanese from the platform
  /// (Hiragino on macOS), with Japanese glyph forms for Han characters.
  static TextStyle nameStyle(double size, {Color color = BP.ink}) => TextStyle(
    fontFamily: BP.display,
    fontFamilyFallback: const [BP.arabic],
    fontSize: size,
    color: color,
    height: 1.2,
    locale: const Locale('ja'),
    fontWeight: FontWeight.w600,
    fontVariations: const [ui.FontVariation('wght', 600)],
  );

  /// Rasterizes [name] with the real text stack and turns its coverage into
  /// bricks, sized to fill [BL.plot] as well as the name allows.
  static Future<NameRaster> of(String name) async {
    await awaitFallbackFonts(name, style: nameStyle(40)); // web: no tofu bricks
    final plot = BL.plot;
    // Width per px of font size, to pick the largest size that still fits.
    final probe = TextPainter(
      text: TextSpan(text: name, style: nameStyle(100)),
      textDirection: TextDirection.ltr,
    )..layout();
    final widthPerPx = math.max(probe.width / 100, 0.3);
    probe.dispose();
    const minBrick = 9.0;
    final byWidth = (plot.width - 20) / (widthPerPx * minBrick);
    final byHeight = (plot.height - 20) / (0.98 * minBrick);
    final size = math.min(byWidth, byHeight).clamp(12.0, 34.0).floorToDouble();

    final tp = TextPainter(
      text: TextSpan(
        text: name,
        style: nameStyle(size, color: const Color(0xFFFFFFFF)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const pad = 2;
    final w = tp.width.ceil() + pad * 2;
    final h = tp.height.ceil() + pad * 2;
    final rec = ui.PictureRecorder();
    tp.paint(Canvas(rec), const Offset(pad + 0.0, pad + 0.0));
    tp.dispose();
    final image = await rec.endRecording().toImage(w, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    final px = data!.buffer.asUint8List();

    // Ink bounds.
    var top = h, bottom = -1, left = w, right = -1;
    double cov(int x, int y) => px[(y * w + x) * 4 + 3] / 255;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (cov(x, y) > 0.1) {
          top = math.min(top, y);
          bottom = math.max(bottom, y);
          left = math.min(left, x);
          right = math.max(right, x);
        }
      }
    }
    if (bottom < 0) {
      top = 0;
      bottom = 0;
      left = 0;
      right = 0;
    }
    final cols = right - left + 1;
    final rows = bottom - top + 1;
    final brick = math.min(16.0, math.min((plot.width - 20) / cols, (plot.height - 20) / rows));
    final origin = Offset(plot.center.dx - cols * brick / 2, plot.bottom - rows * brick);

    final byRow = <int, List<Brick>>{};
    for (var y = top; y <= bottom; y++) {
      for (var x = left; x <= right; x++) {
        final c = cov(x, y);
        if (c <= 0.12) continue;
        final col = x - left;
        final zone = (col * zones ~/ cols).clamp(0, zones - 1);
        byRow.putIfAbsent(y - top, () => []).add(Brick(col, y - top, c, zone));
      }
    }
    // Bottom row first; within a row, the six builders take turns along
    // their own stretch of wall.
    final order = <Brick>[];
    for (var r = rows - 1; r >= 0; r--) {
      final row = byRow[r];
      if (row == null) continue;
      final perZone = List.generate(zones, (z) => row.where((b) => b.zone == z).toList());
      for (var i = 0; perZone.any((z) => i < z.length); i++) {
        for (final z in perZone) {
          if (i < z.length) order.add(z[i]);
        }
      }
    }
    return NameRaster._(
      name: name,
      cols: cols,
      rows: rows,
      bricks: order,
      fontSize: size,
      inkOffset: Offset(left - pad + 0.0, top - pad + 0.0),
      brick: brick,
      origin: origin,
    );
  }
}
