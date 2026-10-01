import 'dart:convert' show utf8;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:characters/characters.dart';
import 'package:flutter/painting.dart';
import 'package:text_slides/booth/craft/geometry.dart' show simplifyClosed;
import 'package:text_slides/booth/craft/plan.dart' show vectorizeText, craftRasterSize, rasterPad;
import 'package:text_slides/booth/raster.dart';
import 'package:text_slides/deck/font_data.dart';

import 'site_letters.dart';

/// The fonts a code point is looked up in, in the order the name's style
/// asks for them (its fontFamily, its fontFamilyFallback), then the
/// platform's own fallback.
const worksFonts = ['Space Grotesk', 'Noto Kufi Arabic', 'system font'];

/// One letter of the name on its way through the text pipeline, with the
/// values the real text stack gives for it: its UTF-8 bytes, the code points
/// they decode to, the font whose cmap has them, its advance and kerning,
/// its outline and its pixels at the Glyph Works' size.
class WorksLetter {
  WorksLetter._(this.k, this.text, this.start, this.end);

  /// Its place among the plan's letters (left to right), the grapheme, and
  /// its code units in the name.
  final int k;
  final String text;
  final int start, end;

  /// Its UTF-8 bytes (`utf8.encode`), and the code points they decode to.
  late final List<int> bytes = utf8.encode(text);
  late final List<int> codePoints = text.runes.toList();

  /// For each code point, the first of [worksFonts] whose cmap has it (2:
  /// neither of the name's own fonts, so the platform's fallback).
  List<int> fonts = const [];

  /// The font the letter's glyph comes from (its first code point's).
  int get font => fonts.isEmpty ? 2 : fonts.first;

  /// Shaping, in em: its advance on its own, where the pen starts it in the
  /// laid-out line, and where the pen would have started it unkerned (the
  /// letter before's pen and advance, and any spaces between). [spaced]: a
  /// space (or an inkless grapheme) comes between it and the letter before.
  double advance = 0, pen = 0, unkerned = 0;
  bool spaced = false;
  double get kern => pen - unkerned;

  /// At the works' size: its pen in the line (px), and its pixels — a
  /// [w]×[h] crop of the line's raster at ([x], [y]), coverage 0..1 row by
  /// row — [full] of them fully covered, [edge] anti-aliased.
  double penPx = 0;
  int x = 0, y = 0, w = 0, h = 0;
  Float32List cover = Float32List(0);
  int full = 0, edge = 0;

  /// Its outline, traced from the glyph as the text stack draws it: closed
  /// polylines in px of its crop (y down), and how many of them are holes.
  List<Float32List> outline = const [];
  int holes = 0;

  bool get rendered => w > 0;

  /// "U+3088" (upper-case hex, at least four digits).
  static String hex(int cp) => 'U+${cp.toRadixString(16).toUpperCase().padLeft(4, '0')}';

  /// "E3".
  static String byte(int b) => b.toRadixString(16).toUpperCase().padLeft(2, '0');
}

/// The name as the Glyph Works sees it: every letter's data at each step of
/// the pipeline, measured with the real text stack in the style the name is
/// built in ([NameRaster.nameStyle]).
///
/// [measure] does what's quick (the encoding, the cmap lookups, the
/// shaping); [render] what needs the rasterizer: the line drawn at the
/// works' [size], each letter painted alone at its place in it (the others
/// transparent, so the shaping is the whole line's) for its own coverage —
/// the way a glyph cache keeps each glyph's mask — and its outline.
class WorksName {
  WorksName._(this.name, this.letters, this.string, this.size, this.lineEm);

  final String name;
  final List<WorksLetter> letters;

  /// Every grapheme of the string with its bytes, and the letter it is
  /// (null: a space).
  final List<({String text, List<int> bytes, int? letter})> string;

  /// The size the works draws the name at (px), and the line's advance (em).
  final double size, lineEm;

  /// The framebuffer the letters land in: [cols]×[rows] px of the line's
  /// raster from ([x0], [y0]) (the ink, a pixel round it). Zero before
  /// [render].
  int x0 = 0, y0 = 0, cols = 0, rows = 0;
  bool get rendered => cols > 0;

  /// The line drawn whole vs. its letters painted one by one and laid over
  /// each other: the largest difference in any pixel's coverage (a check
  /// that each letter's own raster is the line's).
  double check = double.nan;

  /// Of the fully covered pixels, how many lie inside the traced outline;
  /// of the empty ones, how many outside (a check that the outline is where
  /// the pixels are).
  double inside = double.nan, outside = double.nan;

  static const _probe = 400.0;

  /// Measures [name], split into the plan's letters [nl], looking the code
  /// points up in [latin] and [arabic] (the name style's two fonts; null:
  /// not loaded yet, see [lookUp]).
  static WorksName measure(String name, NameLetters nl, {FontData? latin, FontData? arabic}) {
    final graphemes = <(String, int, int)>[];
    var off = 0;
    for (final g in name.characters) {
      graphemes.add((g, off, off + g.length));
      off += g.length;
    }
    // The plan's letters are the graphemes with ink, by their order among
    // the non-space ones.
    final inked = [
      for (var i = 0; i < graphemes.length; i++)
        if (graphemes[i].$1.trim().isNotEmpty) i,
    ];
    final letters = <WorksLetter>[];
    final which = <int, int>{};
    for (final l in nl.letters) {
      if (l.glyph >= inked.length) continue;
      final gi = inked[l.glyph];
      which[gi] = letters.length;
      final (text, a, e) = graphemes[gi];
      letters.add(WorksLetter._(letters.length, text, a, e));
    }
    final string = [for (var i = 0; i < graphemes.length; i++) (text: graphemes[i].$1, bytes: utf8.encode(graphemes[i].$1), letter: which[i])];

    // Shaping: the whole name laid out once, each grapheme on its own for
    // its advance (measured large, so rounding doesn't show).
    final tp = TextPainter(
      text: TextSpan(text: name, style: NameRaster.nameStyle(_probe)),
      textDirection: TextDirection.ltr,
    )..layout();
    final widths = <String, double>{};
    double advance(String g) => widths[g] ??= () {
      final p = TextPainter(
        text: TextSpan(text: g, style: NameRaster.nameStyle(_probe)),
        textDirection: TextDirection.ltr,
      )..layout();
      final w = p.width / _probe;
      p.dispose();
      return w;
    }();
    for (final l in letters) {
      l
        ..advance = advance(l.text)
        ..pen = _left(tp, l.start, l.end) / _probe;
    }
    for (var k = 0; k < letters.length; k++) {
      final l = letters[k];
      l.unkerned = l.pen;
      if (k == 0) continue;
      final p = letters[k - 1];
      // (Right to left, the pen goes the other way: no kerning shown.)
      if (p.end > l.start) continue;
      var gap = 0.0;
      for (final (g, a, e) in graphemes) {
        if (a >= p.end && e <= l.start) gap += advance(g);
      }
      l
        ..spaced = gap > 0 || graphemes.any((g) => g.$2 >= p.end && g.$3 <= l.start)
        ..unkerned = p.pen + p.advance + gap;
      // Bigger than any kern: a script whose letters change shape side by
      // side (joining), not kerning.
      if (l.kern.abs() > 0.25) l.unkerned = l.pen;
    }
    final lineEm = tp.width / _probe;
    tp.dispose();
    // Small, as UI text is: 16 px, smaller for a long name (a line of about
    // 128 px at most), never under 10.
    final size = (128 / math.max(lineEm, 0.5)).floorToDouble().clamp(10.0, 16.0);
    return WorksName._(name, letters, string, size, lineEm)..lookUp(latin, arabic);
  }

  /// Looks every code point up in the cmaps of [latin] (Space Grotesk) and
  /// [arabic] (Noto Kufi Arabic), in that order.
  void lookUp(FontData? latin, FontData? arabic) {
    if (latin == null || arabic == null) return;
    for (final l in letters) {
      l.fonts = [for (final cp in l.codePoints) latin.has(cp) ? 0 : (arabic.has(cp) ? 1 : 2)];
    }
  }

  /// The left edge of code units [a, e) in [tp]'s layout.
  static double _left(TextPainter tp, int a, int e) {
    final boxes = tp.getBoxesForSelection(TextSelection(baseOffset: a, extentOffset: e));
    if (boxes.isEmpty) return 0;
    return boxes.map((b) => b.left).reduce(math.min);
  }

  /// Draws the name at [size] and each letter alone at its place in the
  /// line, reads their coverage back, and traces their outlines.
  Future<void> render() async {
    const white = Color(0xFFFFFFFF), clear = Color(0x00FFFFFF);
    const pad = 3;
    final n = letters.length;
    final line = TextPainter(
      text: TextSpan(
        text: name,
        style: NameRaster.nameStyle(size, color: white),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = line.width.ceil() + 2 * pad, h = line.height.ceil() + 2 * pad;
    final base = line.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    for (final l in letters) {
      l.penPx = _left(line, l.start, l.end);
    }
    // One image: the line, then each letter on its own band.
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    line.paint(c, const Offset(pad + 0.0, pad + 0.0));
    line.dispose();
    for (var k = 0; k < n; k++) {
      final l = letters[k];
      final tp = TextPainter(
        text: TextSpan(
          style: NameRaster.nameStyle(size, color: clear),
          children: [
            if (l.start > 0) TextSpan(text: name.substring(0, l.start)),
            TextSpan(
              text: l.text,
              style: const TextStyle(color: white),
            ),
            if (l.end < name.length) TextSpan(text: name.substring(l.end)),
          ],
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, Offset(pad + 0.0, pad + (k + 1) * h + 0.0));
      tp.dispose();
    }
    final image = await rec.endRecording().toImage(w, h * (n + 1));
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    final px = data!.buffer.asUint8List();
    double cov(int band, int x, int y) => px[((band * h + y) * w + x) * 4 + 3] / 255;

    // Each letter's crop: its ink and a pixel round it.
    var l0 = w, t0 = h, r0 = -1, b0 = -1;
    for (var k = 0; k < n; k++) {
      final l = letters[k];
      var left = w, top = h, right = -1, bottom = -1;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (px[(((k + 1) * h + y) * w + x) * 4 + 3] == 0) continue;
          left = math.min(left, x);
          right = math.max(right, x);
          top = math.min(top, y);
          bottom = math.max(bottom, y);
        }
      }
      if (right < 0) continue;
      final int a = math.max(0, left - 1), b = math.max(0, top - 1);
      final int e = math.min(w - 1, right + 1), f = math.min(h - 1, bottom + 1);
      l
        ..x = a
        ..y = b
        ..w = e - a + 1
        ..h = f - b + 1;
      l.cover = Float32List(l.w * l.h);
      var full = 0, edge = 0;
      for (var j = 0; j < l.h; j++) {
        for (var i = 0; i < l.w; i++) {
          final v = cov(k + 1, l.x + i, l.y + j);
          l.cover[j * l.w + i] = v;
          if (v >= 254 / 255) {
            full++;
          } else if (v > 0) {
            edge++;
          }
        }
      }
      l
        ..full = full
        ..edge = edge;
      l0 = math.min(l0, l.x);
      t0 = math.min(t0, l.y);
      r0 = math.max(r0, l.x + l.w - 1);
      b0 = math.max(b0, l.y + l.h - 1);
    }
    // The check: the letters laid over each other against the whole line.
    var worst = 0.0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var keep = 1.0;
        for (var k = 0; k < n; k++) {
          keep *= 1 - cov(k + 1, x, y);
        }
        worst = math.max(worst, ((1 - keep) - cov(0, x, y)).abs());
      }
    }
    check = worst;

    // Outlines: traced from each glyph drawn large on its own (as the
    // site's smooth letters are), scaled to [size] and put where the line
    // has it (its pen; its baseline on the line's).
    final geos = await vectorizeText(name, style: (s, color) => NameRaster.nameStyle(s, color: color));
    final k150 = size / craftRasterSize;
    final inked = [
      for (final g in name.characters)
        if (g.trim().isNotEmpty) g,
    ];
    var inFull = 0, nFull = 0, outEmpty = 0, nEmpty = 0;
    for (final l in letters) {
      if (!l.rendered) continue;
      // Its glyph among the vectorized ones (non-space graphemes, in order).
      var gi = 0;
      for (final g in name.substring(0, l.start).characters) {
        if (g.trim().isNotEmpty) gi++;
      }
      if (gi >= geos.length || gi >= inked.length) continue;
      final geo = geos[gi].$2;
      if (geo.isEmpty) continue;
      final alone = TextPainter(
        text: TextSpan(text: l.text, style: NameRaster.nameStyle(craftRasterSize)),
        textDirection: TextDirection.ltr,
      )..layout();
      final base150 = alone.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      alone.dispose();
      final loops = <Float32List>[];
      var holes = 0;
      for (final ct in geo.contours) {
        final s = simplifyClosed(ct.pts, 0.8);
        final out = Float32List(s.length);
        for (var i = 0; i < s.length; i += 2) {
          out[i] = pad + l.penPx + (s[i] - rasterPad) * k150 - l.x;
          out[i + 1] = pad + base + (s[i + 1] - rasterPad - base150) * k150 - l.y;
        }
        loops.add(out);
        if (ct.hole) holes++;
      }
      l
        ..outline = loops
        ..holes = holes;
      // The check: pixel centres inside the outline (even-odd) vs coverage.
      for (var j = 0; j < l.h; j++) {
        for (var i = 0; i < l.w; i++) {
          final v = l.cover[j * l.w + i];
          if (v > 0 && v < 254 / 255) continue;
          final inside = _inside(loops, i + 0.5, j + 0.5);
          if (v > 0) {
            nFull++;
            if (inside) inFull++;
          } else {
            nEmpty++;
            if (!inside) outEmpty++;
          }
        }
      }
    }
    inside = nFull == 0 ? double.nan : inFull / nFull;
    outside = nEmpty == 0 ? double.nan : outEmpty / nEmpty;
    // Last: it's rendered once the framebuffer has a size.
    if (r0 >= 0) {
      x0 = l0;
      y0 = t0;
      cols = r0 - l0 + 1;
      rows = b0 - t0 + 1;
    }
  }

  /// Whether (x, y) is inside [loops] (even-odd).
  static bool _inside(List<Float32List> loops, double x, double y) {
    var inside = false;
    for (final p in loops) {
      final n = p.length ~/ 2;
      for (var i = 0, j = n - 1; i < n; j = i++) {
        final xi = p[2 * i], yi = p[2 * i + 1], xj = p[2 * j], yj = p[2 * j + 1];
        if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
      }
    }
    return inside;
  }

  /// The whole raster's coverage at line pixel (x, y) with the first
  /// [landed] letters in (laid over each other as a renderer composites
  /// them: each covers what's left).
  double coverAt(int x, int y, int landed) {
    var keep = 1.0;
    for (var k = 0; k < math.min(landed, letters.length); k++) {
      final l = letters[k];
      final i = x - l.x, j = y - l.y;
      if (i < 0 || j < 0 || i >= l.w || j >= l.h) continue;
      keep *= 1 - l.cover[j * l.w + i];
    }
    return 1 - keep;
  }

  /// The plan's values in words, for the capture log.
  String describe() {
    String f(double v, [int d = 2]) => v.toStringAsFixed(d);
    String em(double v) => '${v < -0.0005 ? '−' : (v > 0.0005 ? '+' : '±')}${f(v.abs(), 3)}';
    final out = StringBuffer(
      'works ${name.characters.length} graphemes, ${utf8.encode(name).length} bytes, ${f(lineEm)} em; at ${size.toStringAsFixed(0)} px a $cols×$rows px framebuffer'
      ' (letters laid over each other vs the whole line: ${f(check, 3)} at most; outline vs pixels: ${f(inside * 100, 1)}% of full inside, ${f(outside * 100, 1)}% of empty outside)',
    );
    for (final l in letters) {
      out
        ..writeln()
        ..write('  ${l.text}  UTF-8 ${l.bytes.map(WorksLetter.byte).join(' ')} → ${l.codePoints.map(WorksLetter.hex).join(' ')}')
        ..write(' → ${[for (var i = 0; i < l.codePoints.length; i++) worksFonts[i < l.fonts.length ? l.fonts[i] : 2]].join(', ')}')
        ..write('  advance ${f(l.advance, 3)} em, pen ${f(l.pen, 3)} em, kern ${em(l.kern)} em${l.spaced ? ' (after a space)' : ''}')
        ..write(
          '  outline ${l.outline.length - l.holes}+${l.holes} holes  ${l.w}×${l.h} px at (${l.x - x0}, ${l.y - y0}), pen ${f(l.penPx, 2)} px: ${l.full} full, ${l.edge} edge',
        );
    }
    return out.toString();
  }
}
