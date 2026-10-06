import 'dart:convert' show utf8;

import 'package:characters/characters.dart';
import 'package:text_slides/deck/font_data.dart';

import '../world/works_name.dart';

/// The talk's stops, as the deck names them (lib/slides/journey).
const journeyStops = ['map', 'widget', 'string', 'engine', 'unicode', 'fonts', 'shape', 'layout', 'record', 'raster', 'draw'];

/// What the talk's card says at a stop: its name (Japanese, as the city's
/// signs have it, and English), what happens there, and the word's values.
/// The same story and numbers as the deck's journey slides.
class JourneyCard {
  const JourneyCard(this.ja, this.title, this.lede, [this.facts = const []]);

  final String ja, title, lede;
  final List<CardFact> facts;
}

sealed class CardFact {
  const CardFact();
}

/// A value with its label ([accent]: the one to look at).
class FactRow extends CardFact {
  const FactRow(this.label, this.value, {this.accent = false});
  final String label, value;
  final bool accent;
}

/// A few lines of code.
class FactCode extends CardFact {
  const FactCode(this.code);
  final String code;
}

/// The word letter by letter, a value under each ([lit]: the letter the
/// works is taking down the line).
class FactLetters extends CardFact {
  const FactLetters(this.label, this.cells);
  final String label;
  final List<(String, String, bool)> cells;
}

/// The cards for [word], with what the works measured of it ([name]: null
/// before it has) and its font ([font]: its cmap).
List<JourneyCard> journeyCards(String word, WorksName? name, FontData? font) {
  final letters = word.characters.toList();
  // The letter the works takes down the line: the first.
  List<(String, String, bool)> each(String Function(int i, String g) value) => [
    for (final (i, g) in letters.indexed) (g, value(i, g), i == 0),
  ];
  String hex(int v, int digits) => v.toRadixString(16).toUpperCase().padLeft(digits, '0');
  final n = letters.length, units = word.codeUnits.length, runes = word.runes.length, bytes = utf8.encode(word).length;
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
    JourneyCard(
      '地図',
      "One word's journey",
      "Text('$word') on its way to pixels. layout() takes it down through the framework and dart:ui "
          'into the engine; paint() records it, and the GPU draws it. Every stop is a place in this city.',
      const [
        FactRow('framework', 'widget · string'),
        FactRow('engine · c++', 'engine · record'),
        FactRow('SkParagraph', 'unicode · fonts · shape · layout'),
        FactRow('Impeller · gpu', 'raster · draw', accent: true),
      ],
    ),
    JourneyCard(
      'ウィジェット',
      "Text('$word')",
      'A widget only describes: a string and a style. Its RenderParagraph owns a TextPainter, '
          'which builds the paragraph. Constraints go down, a size comes back up.',
      [
        FactCode("Text(\n  '$word',\n  style: TextStyle(\n    fontSize: 48,\n  ),\n)"),
        const FactRow('tree', 'Text → RichText → RenderParagraph'),
        const FactRow('builds', 'TextPainter → ui.Paragraph', accent: true),
      ],
    ),
    JourneyCard(
      '文字列',
      'A Dart String',
      "A Dart String is UTF-16: 16-bit code units. Every letter of '$word' is one unit, one code "
          'point, one grapheme.',
      [
        FactLetters('UTF-16 code units', each((i, g) => g.codeUnits.map((u) => hex(u, 4)).join(' '))),
        FactRow('s.length', '$units'),
        FactRow('s.runes.length', '$runes'),
        FactRow('s.codeUnitAt(0)', '0x${hex(word.codeUnitAt(0), 4)} = ${word.codeUnitAt(0)}', accent: true),
      ],
    ),
    JourneyCard(
      'エンジンへ',
      'Into the engine',
      'TextPainter.layout() builds a ui.Paragraph. Across dart:ui, the engine\'s ParagraphBuilder '
          'hands the text to SkParagraph, which keeps it as UTF-8.',
      [
        FactCode(
          'final b = ParagraphBuilder(\n    ParagraphStyle(textDirection: TextDirection.ltr))\n'
          "  ..pushStyle(style.getTextStyle())\n  ..addText('$word')\n  ..pop();\nfinal p = b.build();",
        ),
        FactLetters('UTF-8 bytes', each((i, g) => utf8.encode(g).map((b) => hex(b, 2)).join(' '))),
        FactRow('text', '$units units → $bytes bytes', accent: true),
      ],
    ),
    JourneyCard(
      'Unicode 解析',
      'Unicode analysis',
      'SkUnicode (ICU) marks the boundaries — graphemes, words, line breaks — and each code '
          "point's bidi level and script. itemize() turns them into runs.",
      [
        FactLetters('code points', each((i, g) => 'U+${hex(g.runes.first, 4)}')),
        FactRow('graphemes', '$n · word breaks at 0 and $units'),
        const FactRow('line break', 'only at the end'),
        const FactRow('bidi · script', 'level 0 (LTR) · Latn'),
        const FactRow('runs', '1', accent: true),
      ],
    ),
    JourneyCard(
      'フォント',
      'Find the glyphs',
      "Each code point is looked up in the style's fonts in order: fontFamily, fontFamilyFallback, "
          "then the platform's. The font's cmap maps it to a glyph id.",
      [
        FactLetters('glyph ids · Space Grotesk', each((i, g) => gid(g))),
        FactRow('cmap', cmap ?? '…'),
        FactRow('fallback', found == null ? '…' : (found == n ? 'not needed: $n of $n found' : '${n - found} of $n'), accent: true),
      ],
    ),
    JourneyCard(
      'シェーピング',
      'Shape',
      'HarfBuzz shapes the whole run at once: glyphs, advances, positions. Space Grotesk\'s liga '
          'joins t t into one glyph, its advance split between them.',
      [
        FactLetters('x_advance · em', run()),
        FactRow(
          'glyphs',
          glyphs == null ? '…' : '$n code points → $glyphs${ligature.isEmpty ? '' : '  (liga: ${ligature.map((id) => '#$id').join(' ')})'}',
        ),
        FactRow('run width', width == null ? '…' : '${ems(width)} em', accent: true),
      ],
    ),
    JourneyCard(
      'レイアウト',
      'Lay out',
      'The paragraph wraps the shaped run into lines for the width it\'s given — shaped once, '
          'wrapped many — and measures each: width, ascent, descent, baseline.',
      [
        const FactCode('p.layout(ParagraphConstraints(width: 360));\np.computeLineMetrics();'),
        const FactRow('lines', '1'),
        FactRow('longest line', width == null ? '…' : '${ems(width)} em', accent: true),
        const FactRow('size ↑', 'to the RenderParagraph'),
      ],
    ),
    JourneyCard(
      '記録',
      'Record',
      "paint() doesn't draw yet. canvas.drawParagraph is recorded into a display list — glyph ids "
          'and positions — and the frame goes from the UI thread to the raster thread.',
      [
        const FactCode('Save\nTranslate(x, y)\nDrawTextFrame(frame, x, baseline)\nRestore'),
        FactRow('TextFrame', font == null ? '…' : 'glyphs ${shaped.take(4).map((s) => '#${s.$1}').join(' ')} …'),
        const FactRow('thread', 'UI → raster', accent: true),
      ],
    ),
    JourneyCard(
      'ラスタライズ',
      'Rasterize',
      'On the raster thread each glyph key — font · glyph · size · subpixel x — not yet in the '
          'atlas is rasterized once: its outline filled as coverage, grey on the edges.',
      [
        FactLetters('pixels at ${name == null ? 16 : name.size.toStringAsFixed(0)} px', each((i, g) => rendered ? '${measured[i].w}×${measured[i].h}' : '…')),
        const FactRow('atlas', 'A8 · alpha coverage'),
        FactRow(
          'coverage',
          rendered ? '${measured.fold(0, (a, l) => a + l.full)} full · ${measured.fold(0, (a, l) => a + l.edge)} edge px' : '…',
          accent: true,
        ),
      ],
    ),
    JourneyCard(
      '描画',
      'Draw',
      'Each glyph is a quad — two triangles — its corners pointing into the atlas (t t is one '
          'glyph). The shader multiplies the text color by the coverage: one draw call.',
      [
        const FactCode('color = text_color * atlas.r;  // A8 glyphs'),
        FactRow('quads', glyphs == null ? '…' : '$glyphs · ${glyphs * 2} triangles'),
        const FactRow('draw calls', '1', accent: true),
        FactRow('framebuffer', rendered ? '${name.cols} × ${name.rows} px (the board)' : '…'),
      ],
    ),
  ];
}
