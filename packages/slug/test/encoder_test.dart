import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:slug/slug.dart';

import 'util.dart';

const _latin = 'aegT&@%sQ8';
const _cjk = '直骨角海誤ほんものにせ';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sg = spaceGrotesk();
  final jp = notoJp();
  final glyphs = [
    for (final cp in _latin.runes) (sg, sg.glyphId(cp)),
    for (final cp in _cjk.runes) (jp, jp.glyphId(cp)),
  ];

  test('fonts parse and contain the demo glyphs', () {
    for (final (f, g) in glyphs) {
      expect(g, isNot(0));
      expect(f.contours(g), isNotEmpty);
    }
    expect(sg.glyphId(0x20), isNot(0));
    expect(sg.contours(sg.glyphId(0x20)), isEmpty);
  });

  test('contours become closed chains of quadratics', () {
    for (final (f, g) in glyphs) {
      final curves = slugCurvesFromContours(f.contours(g));
      expect(curves, isNotEmpty);
      // Every endpoint is the start point of exactly one curve (closed chains).
      final starts = <(double, double), int>{};
      final ends = <(double, double), int>{};
      for (final c in curves) {
        starts.update((c.x1, c.y1), (v) => v + 1, ifAbsent: () => 1);
        ends.update((c.x3, c.y3), (v) => v + 1, ifAbsent: () => 1);
      }
      expect(starts, ends, reason: 'open contour in glyph $g');
      // Lines are {p1, p3, p3}.
      for (final c in curves.where((c) => c.x2 == c.x3 && c.y2 == c.y3)) {
        expect(c.x1 != c.x3 || c.y1 != c.y3, isTrue);
      }
    }
  });

  test('packed texels decode to the quantized curves, bands are complete and sorted', () {
    final (data, map) = SlugAtlas.encode(glyphs);
    expect(data.width, SlugEncoder.textureWidth);
    expect(data.pixels.length, data.width * data.height * 4);
    for (var i = 3; i < data.pixels.length; i += 4) {
      expect(data.pixels[i], 255);
    }
    for (final (f, gid) in glyphs) {
      final g = map[(f.id, gid)]!;
      expect(g.quantum, 0.5, reason: 'upem ${f.unitsPerEm} glyphs fit the 12-bit half-unit grid');
      expect(g.maxCurvesPerBand, lessThanOrEqualTo(SlugEncoder.maxCurvesPerBand));
      for (final (horizontal, bands) in [(true, g.hBands), (false, g.vBands)]) {
        final extent = horizontal ? g.extentY : g.extentX;
        for (var b = 0; b < bands.length; b++) {
          final (count, offset) = data.header(g.base + (horizontal ? b : g.hBandCount + b));
          expect(count, bands[b].length);
          // Round trip through the texels.
          for (var k = 0; k < count; k++) {
            final t = g.base + offset + 3 * k;
            final c = g.curves[bands[b][k]];
            expect(data.point(t), (c.x1.toInt(), c.y1.toInt()));
            expect(data.point(t + 1), (c.x2.toInt(), c.y2.toInt()));
            expect(data.point(t + 2), (c.x3.toInt(), c.y3.toInt()));
          }
          // Sorted by max coordinate, descending (early exit in the shader).
          final keys = [
            for (final i in bands[b]) horizontal ? g.curves[i].maxX : g.curves[i].maxY,
          ];
          for (var k = 1; k < keys.length; k++) {
            expect(keys[k], lessThanOrEqualTo(keys[k - 1]));
          }
          // Complete: every curve crossing the band (except parallel lines).
          final lo = extent * b / bands.length, hi = extent * (b + 1) / bands.length;
          for (var i = 0; i < g.curves.length; i++) {
            final c = g.curves[i];
            final parallel = horizontal ? c.isHorizontalLine : c.isVerticalLine;
            final cLo = horizontal ? c.minY : c.minX, cHi = horizontal ? c.maxY : c.maxX;
            final crosses = cHi >= lo && cLo <= hi;
            final has = bands[b].contains(i);
            if (crosses && !parallel) expect(has, isTrue, reason: 'missing curve $i');
            if (has) expect(parallel, isFalse, reason: 'parallel line $i in band');
          }
        }
      }
    }
  });

  test('sign-based root eligibility equals the reference 0x2E74 lookup', () {
    for (var shift = 0; shift < 8; shift++) {
      final code = (0x2E74 >> shift) & 0x0101;
      final n1 = shift & 1 != 0, n2 = shift & 2 != 0, n3 = shift & 4 != 0;
      expect(slugRootEligible(1, n1, n2, n3), code & 1 != 0, reason: 'root 1, shift $shift');
      expect(slugRootEligible(2, n1, n2, n3), code & 0x100 != 0, reason: 'root 2, shift $shift');
    }
  });

  test('CPU port of the shader matches a path raster', () async {
    for (final px in [12.0, 24.0, 48.0, 96.0]) {
      for (final (f, gid) in glyphs) {
        final (data, map) = SlugAtlas.encode([(f, gid)]);
        final g = map[(f.id, gid)]!;
        final scale = px / f.unitsPerEm;
        final w = (px * 1.4).ceil() + 4, h = (px * 1.5).ceil() + 4;
        final pen = ui.Offset(2 - g.bounds.left * scale + 0.3, px * 1.15 + 0.4);
        final ref = await renderAlpha(w, h, (c) {
          c.drawPath(glyphFillPath(f, gid, pen, scale), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
        });
        final got = Float64List(w * h);
        final q = g.quantum;
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final gx = ((x + 0.5 - pen.dx) / scale - g.originX) / q;
            final gy = ((pen.dy - y - 0.5) / scale - g.originY) / q;
            got[y * w + x] = slugCoverageCpu(data, g, gx, gy, scale * q, scale * q).coverage;
          }
        }
        final d = compare(ref, got, w, h);
        expect(d.isCloseAt(px), isTrue, reason: 'glyph $gid @ $px px: $d');
      }
    }
  });
}
