import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show Matrix4;
import 'package:flutter_test/flutter_test.dart';
import 'package:slug/slug.dart';

import 'util.dart';

/// Renders glyphs with the real fragment shader (flutter_tester runs the
/// SkSL variant through Skia) and compares against Skia's path raster.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sg = spaceGrotesk();
  final jp = notoJp();
  final glyphs = [
    for (final cp in 'aegT&@Q'.runes) (sg, sg.glyphId(cp)),
    for (final cp in '直海誤ほ'.runes) (jp, jp.glyphId(cp)),
  ];
  const white = ui.Color(0xFFFFFFFF);

  late ui.FragmentProgram program;
  late SlugAtlas atlas;
  late SlugPainter painter;

  setUpAll(() async {
    program = await SlugShader.load();
    atlas = await SlugAtlas.build(glyphs);
    painter = SlugPainter(program, atlas);
  });

  tearDownAll(() {
    painter.dispose();
    atlas.dispose();
  });

  test('shader coverage matches a path raster at several sizes', () async {
    final identity = Matrix4.identity().storage;
    for (final px in [12.0, 24.0, 48.0, 96.0, 160.0]) {
      for (final (f, gid) in glyphs) {
        final g = atlas.glyph(f, gid)!;
        final scale = px / f.unitsPerEm;
        final w = (px * 1.4).ceil() + 4, h = (px * 1.5).ceil() + 4;
        final pen = ui.Offset(2 - g.bounds.left * scale + 0.3, px * 1.15 + 0.4);
        final ref = await renderAlpha(w, h, (c) {
          c.drawPath(glyphFillPath(f, gid, pen, scale), ui.Paint()..color = white);
        });
        final got = await renderAlpha(w, h, (c) {
          painter.drawGlyph(c, g, pen: pen, scale: scale, toDevice: identity, color: white);
        });
        final d = compare(ref, got, w, h);
        expect(d.isCloseAt(px), isTrue, reason: 'glyph $gid @ $px px: $d');

        // GPU vs the CPU port of the same shader: same algorithm, same data.
        final cpu = Float64List(w * h);
        final q = g.quantum;
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final gx = ((x + 0.5 - pen.dx) / scale - g.originX) / q;
            final gy = ((pen.dy - y - 0.5) / scale - g.originY) / q;
            cpu[y * w + x] = slugCoverageCpu(atlas.data, g, gx, gy, scale * q, scale * q).coverage;
          }
        }
        final e = compare(cpu, got, w, h);
        expect(e.max, lessThan(0.02), reason: 'GPU vs CPU, glyph $gid @ $px px: $e');
      }
    }
  });

  test('composes under rotation and perspective', () async {
    const w = 220, h = 220;
    Matrix4 about(Matrix4 m) => Matrix4.translationValues(110, 110, 0)
      ..multiply(m)
      ..multiply(Matrix4.translationValues(-110, -110, 0));
    final transforms = <String, Matrix4>{
      'rotate': about(Matrix4.rotationZ(0.5)),
      'scale': about(Matrix4.diagonal3Values(9, 9, 1)..translateByDouble(-20, 10, 0, 1)),
      'perspective': about(
        (Matrix4.identity()..setEntry(3, 2, 0.003))
          ..multiply(Matrix4.rotationX(0.8))
          ..multiply(Matrix4.rotationY(-0.5)),
      ),
      'steep': about(
        (Matrix4.identity()..setEntry(3, 2, 0.004))
          ..multiply(Matrix4.rotationX(1.15))
          ..multiply(Matrix4.rotationZ(0.3)),
      ),
    };
    for (final MapEntry(key: name, value: m) in transforms.entries) {
      for (final (f, gid) in [glyphs[0], glyphs[5], glyphs[7], glyphs[9]]) {
        final g = atlas.glyph(f, gid)!;
        const px = 150.0;
        final scale = px / f.unitsPerEm;
        final pen = ui.Offset(110 - (g.bounds.left + g.bounds.right) / 2 * scale, 165);
        final ref = await renderAlpha(w, h, (c) {
          c.transform(m.storage);
          c.drawPath(glyphFillPath(f, gid, pen, scale), ui.Paint()..color = white);
        });
        final got = await renderAlpha(w, h, (c) {
          c.transform(m.storage);
          painter.drawGlyph(c, g, pen: pen, scale: scale, toDevice: m.storage, color: white);
        });
        final d = compare(ref, got, w, h);
        expect(d.speckles, 0, reason: '$name glyph $gid: $d');
        expect(d.mean, lessThan(0.06), reason: '$name glyph $gid: $d');
        expect(d.ink, lessThan(0.04), reason: '$name glyph $gid: $d');
      }
    }
  });

  test('dilation grows the quad by about half a device pixel', () {
    final m = (Matrix4.identity()..scaleByDouble(4, 4, 1, 1)).storage;
    final r = slugDilate(m, const ui.Rect.fromLTWH(10, 10, 20, 20));
    expect(r.left, closeTo(10 - 0.5 / 4, 1e-3));
    expect(r.bottom, closeTo(30 + 0.5 / 4, 1e-3));
    final p = (Matrix4.identity()
          ..setEntry(3, 2, 0.002)
          ..rotateY(math.pi / 4))
        .storage;
    final q = slugDilate(p, const ui.Rect.fromLTWH(0, 0, 100, 100));
    expect(q.width, greaterThan(100));
  });
}
