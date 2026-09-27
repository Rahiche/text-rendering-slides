import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:slug/slug.dart';

import 'util.dart';

/// SlugText next to Flutter's own Text, inside identical transforms.
void main() {
  final sg = spaceGrotesk();
  final jp = notoJp();
  const sgFamily = 'SlugTestGrotesk';
  const jpFamily = 'SlugTestJP';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final dir = Directory.current.path.endsWith('test') ? 'fonts' : 'test/fonts';
    Future<ByteData> bytes(String f) async =>
        ByteData.sublistView(File('$dir/$f').readAsBytesSync());
    await (FontLoader(sgFamily)..addFont(bytes('SpaceGrotesk.ttf'))).load();
    await (FontLoader(jpFamily)..addFont(bytes('NotoSansJP-case.ttf'))).load();
    await SlugShader.load();
  });

  List<SlugSpan> spans(double size) => [
    SlugSpan(
      'Tag ',
      font: sg,
      style: TextStyle(
        fontFamily: sgFamily,
        fontSize: size,
        color: Colors.white,
        fontVariations: [for (final e in sg.defaultAxes.entries) ui.FontVariation(e.key, e.value)],
      ),
    ),
    SlugSpan('直海', font: jp, style: TextStyle(fontFamily: jpFamily, fontSize: size, color: Colors.white)),
  ];

  Widget trio(Matrix4 transform, double size, GlobalKey a, GlobalKey b, GlobalKey c) {
    Widget cell(GlobalKey key, Widget child) => RepaintBoundary(
      key: key,
      child: SizedBox(
        width: 400,
        height: 200,
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: Transform(transform: transform, alignment: Alignment.center, child: child),
          ),
        ),
      ),
    );
    final s = spans(size);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cell(a, Text.rich(TextSpan(children: [for (final x in s) TextSpan(text: x.text, style: x.style)]))),
          cell(b, SlugText(s)),
          cell(c, CustomPaint(size: _OutlinePainter.sizeOf(s), painter: _OutlinePainter(s))),
        ],
      ),
    );
  }

  Future<Float64List> capture(WidgetTester tester, GlobalKey key) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
    final dpr = tester.view.devicePixelRatio;
    final img = (await tester.runAsync(() => boundary.toImage(pixelRatio: dpr)))!;
    final bytes = (await tester.runAsync(() => img.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
    final out = Float64List(img.width * img.height);
    for (var i = 0; i < out.length; i++) {
      out[i] = bytes.getUint8(4 * i) / 255; // white on black: red = coverage
    }
    img.dispose();
    return out;
  }

  final cases = <String, Matrix4>{
    'identity': Matrix4.identity(),
    'zoom 3x': Matrix4.diagonal3Values(3, 3, 1),
    'rotate': Matrix4.rotationZ(-0.35),
    'perspective': (Matrix4.identity()..setEntry(3, 2, 0.002))
      ..multiply(Matrix4.rotationX(0.7))
      ..multiply(Matrix4.rotationY(-0.6)),
  };

  for (final MapEntry(key: name, value: m) in cases.entries) {
    testWidgets('SlugText matches Text: $name', (tester) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final a = GlobalKey(), b = GlobalKey(), c = GlobalKey();
      await tester.pumpWidget(trio(m, 48, a, b, c));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      final text = await capture(tester, a);
      final slug = await capture(tester, b);
      final outline = await capture(tester, c);
      // Same outlines, same layout: Slug vs Skia's path fill.
      final d = compare(outline, slug, 800, 400);
      expect(d.speckles, 0, reason: 'vs outline, $name: $d');
      expect(d.mean, lessThan(0.06), reason: 'vs outline, $name: $d');
      expect(d.ink, lessThan(0.04), reason: 'vs outline, $name: $d');
      // Vs Flutter's Text: same placement. flutter_tester's glyph scaler
      // emboldens a little, so measure Text against the plain outline fill
      // too and require Slug to add no shift of its own.
      final t = maskStats(text, slug, 800, 400);
      final o = maskStats(text, outline, 800, 400);
      expect(t.iou, greaterThan(0.8), reason: 'vs Text, $name: $t');
      expect(t.centroidShift, lessThan(o.centroidShift + 0.25), reason: 'vs Text, $name: $t / outline $o');
    });
  }
}

/// Draws the spans' outlines as paths at the positions a TextPainter gives.
class _OutlinePainter extends CustomPainter {
  _OutlinePainter(this.spans);

  final List<SlugSpan> spans;

  static Size sizeOf(List<SlugSpan> spans) {
    final tp = TextPainter(
      text: TextSpan(children: [for (final s in spans) TextSpan(text: s.text, style: s.style)]),
      textDirection: TextDirection.ltr,
    )..layout();
    final size = tp.size;
    tp.dispose();
    return size;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: TextSpan(children: [for (final s in spans) TextSpan(text: s.text, style: s.style)]),
      textDirection: TextDirection.ltr,
    )..layout();
    final baseline = tp.computeLineMetrics().first.baseline;
    var i = 0;
    for (final s in spans) {
      for (final cp in s.text.runes) {
        final box = tp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1)).first;
        i++;
        final gid = s.font.glyphId(cp);
        canvas.drawPath(
          glyphFillPath(s.font, gid, Offset(box.left, baseline), s.style.fontSize! / s.font.unitsPerEm),
          Paint()..color = Colors.white,
        );
      }
    }
    tp.dispose();
  }

  @override
  bool shouldRepaint(_OutlinePainter old) => false;
}
