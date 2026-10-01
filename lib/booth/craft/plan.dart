import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../deck/theme.dart';
import 'geometry.dart';
import 'method.dart';
import 'methods.dart';
import 'stage.dart';
import '../web_fonts.dart';
import 'workshop_layout.dart';

/// Font size characters are rasterized at for vectorizing.
const craftRasterSize = 150.0;

/// The style characters are made in: bold Space Grotesk, Japanese from the
/// platform (Hiragino on macOS) with Japanese glyph forms.
TextStyle craftStyle(double size, {Color color = BP.ink}) => TextStyle(
  fontFamily: BP.display,
  fontFamilyFallback: const [BP.arabic],
  fontSize: size,
  color: color,
  height: 1.2,
  locale: const ui.Locale('ja'),
  fontWeight: FontWeight.w700,
  fontVariations: const [ui.FontVariation('wght', 700)],
);

/// One character of the name, ready for the workshop.
class CraftChar {
  CraftChar({
    required this.char,
    required this.index,
    required this.geo,
    required this.method,
    required this.stage,
    required this.signInk,
    required this.seed,
  });

  /// The grapheme ('A', 'が', '田'…).
  final String char;

  /// Position in the name (spaces included).
  final int index;

  final GlyphGeometry geo;
  final CraftMethod method;

  /// The character on the dais (canvas paths, helpers).
  final GlyphStage stage;

  /// Where its ink sits on the name sign (canvas).
  final Rect signInk;

  final int seed;

  /// Build-time window, as fractions of the whole build: [start, end).
  double start = 0;
  double end = 1;

  int get codePoint => char.runes.first;
  String get hex => 'U+${codePoint.toRadixString(16).toUpperCase().padLeft(4, '0')}';
}

/// The workshop's plan for one name: every non-space character with its
/// geometry, its craft (no craft repeats within a name, up to 16) and its
/// slot on the sign.
class CraftPlan {
  CraftPlan._(this.name, this.chars, this.nominal);

  final String name;
  final List<CraftChar> chars;

  /// Seconds the whole build takes at the normal pace.
  final double nominal;

  /// Parts of one character's window (fractions of the window).
  static const setup = 0.10; // material arrives
  static const finish = 0.08; // inspection ✓
  static const transfer = 0.14; // gantry carries it to the sign

  /// The character being worked on at build fraction [f] (null after the
  /// last one).
  int? current(double f) {
    for (var k = 0; k < chars.length; k++) {
      if (f < chars[k].end) return k;
    }
    return null;
  }

  static Future<CraftPlan> of(String name) async {
    await awaitFallbackFonts(name, style: craftStyle(40)); // web: no tofu glyphs
    final graphemes = name.characters.toList();
    // Rasterize each non-space character with the real text stack.
    final rasters = <(int, String, VectorizeInput)>[];
    for (var i = 0; i < graphemes.length; i++) {
      final g = graphemes[i];
      if (g.trim().isEmpty) continue;
      rasters.add((i, g, await _rasterize(g)));
    }
    final geos = await compute(_vectorizeAll, [for (final r in rasters) r.$3]);

    // Sign layout: the whole name in one line, as large as fits.
    final probe = TextPainter(
      text: TextSpan(text: name, style: craftStyle(100)),
      textDirection: TextDirection.ltr,
    )..layout();
    final perPx = math.max(probe.width / 100, 0.2);
    final lineH = probe.height / 100;
    probe.dispose();
    final signSize = math
        .min((BW.sign.width - 40) / perPx, (BW.sign.height - 6) / lineH)
        .clamp(20.0, 104.0);
    final full = TextPainter(
      text: TextSpan(text: name, style: craftStyle(signSize)),
      textDirection: TextDirection.ltr,
    )..layout();
    final signOrigin = Offset(
      BW.sign.center.dx - full.width / 2,
      BW.sign.center.dy - full.height / 2,
    );
    final offsets = <int>[];
    var at = 0;
    for (final g in graphemes) {
      offsets.add(at);
      at += g.length;
    }

    final seed = name.hashCode & 0x7fffffff;
    final methods = assignMethods(rasters.length, seed);
    final chars = <CraftChar>[];
    for (var k = 0; k < rasters.length; k++) {
      final (i, g, input) = rasters[k];
      final geo = geos[k];
      final pad = _pad;
      // Raster px → sign canvas: same font at signSize, origin at the box.
      final boxes = full.getBoxesForSelection(
        TextSelection(baseOffset: offsets[i], extentOffset: offsets[i] + g.length),
      );
      final boxLeft = boxes.isEmpty ? 0.0 : boxes.first.left;
      final s = signSize / craftRasterSize;
      Offset toSign(double x, double y) =>
          signOrigin + Offset(boxLeft + (x - pad) * s, (y - pad) * s);
      final signInk = Rect.fromPoints(
        toSign(geo.inkLeft, geo.inkTop),
        toSign(geo.inkRight, geo.inkBottom),
      );
      chars.add(
        CraftChar(
          char: g,
          index: i,
          geo: geo,
          method: methods[k],
          stage: GlyphStage.fit(geo, BW.make),
          signInk: signInk,
          seed: seed + k * 7919,
        ),
      );
    }
    full.dispose();

    // Timing: each character's window by its craft's weight; long names are
    // compressed so the whole build stays within a few minutes.
    final raw = [for (final c in chars) 20.0 * c.method.weight + 6.0];
    var total = raw.fold<double>(0, (a, b) => a + b);
    const cap = 260.0;
    final squeeze = total > cap ? cap / total : 1.0;
    total *= squeeze;
    var t = 0.0;
    for (var k = 0; k < chars.length; k++) {
      chars[k].start = total == 0 ? 0 : t / total;
      t += raw[k] * squeeze;
      chars[k].end = total == 0 ? 1 : t / total;
    }
    return CraftPlan._(name, chars, math.max(total, 1));
  }
}

/// Padding (px) around each character's raster.
const rasterPad = 12;
const _pad = rasterPad;

Future<VectorizeInput> _rasterize(String g, {TextStyle Function(double size, Color color)? style}) async {
  final tp = TextPainter(
    text: TextSpan(
      text: g,
      style: (style ?? (size, color) => craftStyle(size, color: color))(craftRasterSize, const ui.Color(0xFFFFFFFF)),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final w = tp.width.ceil() + 2 * _pad;
  final h = tp.height.ceil() + 2 * _pad;
  final rec = ui.PictureRecorder();
  tp.paint(Canvas(rec), Offset(_pad.toDouble(), _pad.toDouble()));
  tp.dispose();
  final image = await rec.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  final rgba = data!.buffer.asUint8List();
  final alpha = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    alpha[i] = rgba[i * 4 + 3];
  }
  return VectorizeInput(w, h, alpha);
}

List<GlyphGeometry> _vectorizeAll(List<VectorizeInput> inputs) => [
  for (final i in inputs) vectorize(i),
];

/// Each non-space grapheme of [text], rasterized at [craftRasterSize] with
/// the real text stack (in [craftStyle]) and vectorized on a background
/// isolate. For the 3D booth, which extrudes them.
///
/// [style] (default [craftStyle]) gets the size and colour to render in;
/// geometry is in raster px of a [craftRasterSize] render with [rasterPad]
/// px of padding.
Future<List<(String, GlyphGeometry)>> vectorizeText(
  String text, {
  TextStyle Function(double size, Color color)? style,
}) async {
  final chars = [
    for (final g in text.characters)
      if (g.trim().isNotEmpty) g,
  ];
  await awaitFallbackFonts(
    chars.join(),
    style: (style ?? (size, color) => craftStyle(size, color: color))(40, const ui.Color(0xFFFFFFFF)),
  );
  final inputs = [for (final g in chars) await _rasterize(g, style: style)];
  final geos = await compute(_vectorizeAll, inputs);
  return [for (var i = 0; i < chars.length; i++) (chars[i], geos[i])];
}

/// Crafts for [n] characters: a shuffled tour of every craft (no repeats
/// within 16 characters), different for every name.
///
/// `--dart-define=BOOTH_CRAFTS=neon,laser` forces crafts in that order
/// (for testing a craft).
List<CraftMethod> assignMethods(int n, int seed) {
  const forced = String.fromEnvironment('BOOTH_CRAFTS');
  if (forced.isNotEmpty) {
    final ids = forced.split(',').map((s) => s.trim()).toList();
    final list = [
      for (final id in ids) ...craftMethods.where((m) => m.id == id),
    ];
    if (list.isNotEmpty) return [for (var k = 0; k < n; k++) list[k % list.length]];
  }
  final order = [...craftMethods];
  final rnd = math.Random(seed);
  for (var i = order.length - 1; i > 0; i--) {
    final j = rnd.nextInt(i + 1);
    final t = order[i];
    order[i] = order[j];
    order[j] = t;
  }
  return [for (var k = 0; k < n; k++) order[k % order.length]];
}
