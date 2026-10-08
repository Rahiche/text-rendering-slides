import 'dart:convert' show utf8;

import 'package:characters/characters.dart';
import 'package:text_slides/deck/font_data.dart';

import '../world/works_name.dart';
import 'talk_section.dart';

/// The talk's stops: the deck's eleven (lib/slides/journey), the close ones
/// told together.
const journeyStops = ['map', 'widget', 'engine', 'fonts', 'shape', 'raster', 'draw'];

/// The cards for [word], with what the works measured of it ([name]: null
/// before it has) and its font ([font]: its cmap).
List<TalkCard> journeyCards(String word, WorksName? name, FontData? font) {
  final letters = word.characters.toList();
  // The letter the works takes down the line: the first.
  List<(String, String, bool)> each(String Function(int i, String g) value) => [
    for (final (i, g) in letters.indexed) (g, value(i, g), i == 0),
  ];
  String hex(int v, int digits) => v.toRadixString(16).toUpperCase().padLeft(digits, '0');
  final n = letters.length, units = word.codeUnits.length, bytes = utf8.encode(word).length;
  final first = word.runes.first;
  final measured = name != null && name.letters.length == n ? name.letters : null;
  final rendered = measured != null && name!.rendered;
  final width = measured == null ? null : measured.last.pen + measured.last.advance;
  String ems(double v) => v.toStringAsFixed(2);
  // As positioned: from each pen to the next (the run's x_advance per
  // cluster; a ligature's split between its letters).
  String advance(int i) {
    final m = measured;
    if (m == null) return '…';
    return ems(i + 1 < m.length ? m[i + 1].pen - m[i].pen : m[i].advance);
  }

  String gid(String g) => font == null ? '…' : '#${font.glyphId(g.runes.first)}';
  // The glyphs as shaped: the cmap's, the font's ligatures made one glyph
  // (Space Grotesk: t t → #906).
  final shaped = <(int, int)>[];
  if (font != null) {
    final ids = [for (final g in letters) font.glyphId(g.runes.first)];
    for (var i = 0; i < ids.length;) {
      final lig = font.ligatureAt(ids, i);
      shaped.add((lig?.$1 ?? ids[i], lig?.$2 ?? 1));
      i += lig?.$2 ?? 1;
    }
  }
  final glyphs = font == null ? null : shaped.length;
  // A cell a glyph as shaped (t t one), its advance as positioned.
  List<(String, String, bool)> run() {
    final m = measured;
    if (font == null || m == null) return each((i, g) => advance(i));
    var a = 0;
    return [
      for (final (_, k) in shaped)
        () {
          final end = a + k < m.length ? m[a + k].pen : m.last.pen + m.last.advance;
          final cell = (letters.sublist(a, a + k).join(), ems(end - m[a].pen), a == 0);
          a += k;
          return cell;
        }(),
    ];
  }

  final ligature = [for (final (id, n) in shaped) if (n > 1) id];
  final found = font == null ? null : letters.where((g) => font.has(g.runes.first)).length;
  // How the cmap gets the first letter's glyph (format 4: a delta).
  final segment = font?.segmentIndexOf(first);
  final cmap = font == null || segment == null || segment < 0 || font.segments[segment].usesRange
      ? null
      : '0x${hex(first, 4)} ${font.segments[segment].delta < 0 ? '−' : '+'} ${font.segments[segment].delta.abs()} = #${font.glyphId(first)}';
  return [
    TalkCard(
      "One word's journey",
      "Text('$word') on its way to pixels. layout() takes it down through the framework and dart:ui "
          'into the engine; paint() records it, and the GPU draws it. Every stop is a place in this city.',
      const [
        FactRow('framework', 'widget'),
        FactRow('SkParagraph', 'engine · fonts · shape'),
        FactRow('Impeller · gpu', 'raster · draw', accent: true),
      ],
    ),
    TalkCard(
      "Text('$word')",
      'A widget only describes: a string and a style. Its RenderParagraph owns a TextPainter, which '
          'builds the paragraph. Dart keeps the string as UTF-16 code units.',
      [
        FactCode("Text(\n  '$word',\n  style: TextStyle(fontSize: 48),\n)"),
        const FactRow('tree', 'Text → RichText → RenderParagraph'),
        FactLetters('UTF-16 code units · s.length $units', each((i, g) => g.codeUnits.map((u) => hex(u, 4)).join(' '))),
        const FactRow('builds', 'TextPainter → ui.Paragraph', accent: true),
      ],
    ),
    TalkCard(
      'Into the engine',
      "Across dart:ui, the engine's ParagraphBuilder hands the text to SkParagraph, which keeps it as "
          'UTF-8. ICU marks its graphemes, breaks, direction and script, and it is itemized into runs.',
      [
        FactCode("ParagraphBuilder(style)\n  ..addText('$word')\n  ..build();"),
        FactLetters('UTF-8 bytes · $bytes', each((i, g) => utf8.encode(g).map((b) => hex(b, 2)).join(' '))),
        const FactRow('bidi · script', 'level 0 (LTR) · Latn'),
        const FactRow('runs', '1', accent: true),
      ],
    ),
    TalkCard(
      'Find the glyphs',
      "Each code point is looked up in the style's fonts in order: fontFamily, fontFamilyFallback, "
          "then the platform's. The font's cmap maps it to a glyph id.",
      [
        FactLetters('glyph ids · Space Grotesk', each((i, g) => gid(g))),
        FactRow('cmap', cmap ?? '…'),
        FactRow('fallback', found == null ? '…' : (found == n ? 'not needed: $n of $n found' : '${n - found} of $n'), accent: true),
      ],
    ),
    TalkCard(
      'Shape, then lay out',
      'HarfBuzz shapes the whole run at once: glyphs and advances, t t joined into one by the '
          "font's liga. layout() then wraps it to the width (shaped once, wrapped many) and measures each line.",
      [
        FactLetters('x_advance · em', run()),
        FactRow(
          'glyphs',
          glyphs == null ? '…' : '$n code points → $glyphs${ligature.isEmpty ? '' : '  (liga: ${ligature.map((id) => '#$id').join(' ')})'}',
        ),
        const FactCode('p.layout(ParagraphConstraints(width: 360));'),
        FactRow('lines', width == null ? '1' : '1 · ${ems(width)} em', accent: true),
      ],
    ),
    TalkCard(
      'Record, then rasterize',
      "paint() doesn't draw: drawParagraph is recorded into a display list, glyph ids and positions, "
          'for the raster thread. There each glyph not yet in the atlas is rasterized once, as coverage.',
      [
        const FactCode('DrawTextFrame(frame, x, baseline)'),
        FactLetters('pixels at ${name == null ? 16 : name.size.toStringAsFixed(0)} px', each((i, g) => rendered ? '${measured[i].w}×${measured[i].h}' : '…')),
        const FactRow('atlas', 'A8 · alpha coverage'),
        FactRow(
          'coverage',
          rendered ? '${measured.fold(0, (a, l) => a + l.full)} full · ${measured.fold(0, (a, l) => a + l.edge)} edge px' : '…',
          accent: true,
        ),
      ],
    ),
    TalkCard(
      'Draw',
      'Each glyph is a quad, two triangles whose corners point into the atlas (t t is one glyph). '
          'The shader multiplies the text color by the coverage, all in one draw call.',
      [
        const FactCode('color = text_color * atlas.r;  // A8 glyphs'),
        FactRow('quads', glyphs == null ? '…' : '$glyphs · ${glyphs * 2} triangles'),
        const FactRow('draw calls', '1', accent: true),
        FactRow('framebuffer', rendered ? '${name.cols} × ${name.rows} px (the board)' : '…'),
      ],
    ),
  ];
}
