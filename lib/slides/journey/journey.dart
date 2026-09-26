import 'package:flutter/material.dart';

import '../../deck/deck.dart';
import '../../deck/font_data.dart';
import '../../deck/scripts.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';

/// The word that travels through section 05. Shared by all journey slides.
final journeyWord = ValueNotifier<String>('Flutter');

const journeyPresets = ['Flutter', 'Type', 'café', 'مرحبا', '👋🏽'];

/// The stops, in order. Index 0 is the overview map.
const journeyStops = [
  ('j-map', 'map'),
  ('j-widget', 'widget'),
  ('j-string', 'string'),
  ('j-builder', 'engine'),
  ('j-unicode', 'unicode'),
  ('j-font', 'fonts'),
  ('j-shape', 'shape'),
  ('j-layout', 'layout'),
  ('j-record', 'record'),
  ('j-atlas', 'raster'),
  ('j-gpu', 'draw'),
];

/// Style for the journey word: Space Grotesk at its default instance
/// (wght 300) so parsed hmtx advances match the real layout exactly.
TextStyle journeyStyle(double size, {Color color = BP.ink, List<FontFeature>? features}) => TextStyle(
  fontFamily: BP.display,
  fontFamilyFallback: const [BP.arabic],
  fontSize: size,
  color: color,
  fontFeatures: features,
  fontVariations: const [FontVariation('wght', 300)],
);

/// One code point of the word, resolved to a font and a glyph id the same way
/// the paragraph's font collection does it: first family, then fallbacks.
class JGlyph {
  const JGlyph({
    required this.codePoint,
    required this.start,
    required this.end,
    required this.font,
    required this.glyphId,
    required this.advance,
    required this.script,
  });

  final int codePoint;

  /// UTF-16 range in the word.
  final int start;
  final int end;

  /// null = not in any bundled font → platform fallback (e.g. emoji).
  final FontData? font;
  final int glyphId;

  /// Nominal advance from hmtx, in font units.
  final int advance;
  final Script script;

  String get fontName => font?.name ?? 'system fallback';
  String get hex => 'U+${codePoint.toRadixString(16).toUpperCase().padLeft(4, '0')}';
  String get char => String.fromCharCode(codePoint);
  bool get isJoinControl => codePoint == 0x200D || codePoint == 0xFE0F;
}

class JourneyData {
  JourneyData(this.text, this.latin, this.arabic) {
    var i = 0;
    for (final cp in text.runes) {
      final len = cp > 0xFFFF ? 2 : 1;
      FontData? f;
      if (latin.has(cp)) {
        f = latin;
      } else if (arabic.has(cp)) {
        f = arabic;
      }
      final gid = f?.glyphId(cp) ?? 0;
      glyphs.add(JGlyph(
        codePoint: cp,
        start: i,
        end: i + len,
        font: f,
        glyphId: gid,
        advance: f?.advance(gid) ?? 0,
        script: scriptOf(cp),
      ));
      i += len;
    }
  }

  final String text;
  final FontData latin;
  final FontData arabic;
  final List<JGlyph> glyphs = [];

  bool get rtl => glyphs.any((g) => g.script.rtl);
  List<FontData?> get fonts => {for (final g in glyphs) g.font}.toList();

  static Future<(FontData, FontData)>? _fonts;

  static Future<(FontData, FontData)> loadFonts() => _fonts ??= () async {
    final l = await FontData.spaceGrotesk();
    final a = await FontData.notoKufiArabic();
    return (l, a);
  }();
}

/// A journey slide: SlideFrame + the "you are here" map + the word picker.
/// [builder] gets the resolved [JourneyData] for the current word.
class JourneyFrame extends StatelessWidget {
  const JourneyFrame({
    super.key,
    required this.stop,
    required this.title,
    required this.builder,
    this.showPicker = true,
    this.rekey = true,
  });

  /// Rebuild the content from scratch (fresh state) when the word changes.
  final bool rekey;

  /// Index into [journeyStops].
  final int stop;
  final String Function(String word) title;
  final Widget Function(BuildContext context, JourneyData data) builder;
  final bool showPicker;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: journeyWord,
      builder: (context, word, _) => FutureBuilder<(FontData, FontData)>(
        future: JourneyData.loadFonts(),
        builder: (context, snap) {
          final fonts = snap.data;
          return SlideFrame(
            title: title(word),
            trailing: _JourneyNav(stop: stop, word: word, showPicker: showPicker),
            child: fonts == null
                ? const SizedBox()
                : KeyedSubtree(
                    key: rekey ? ValueKey(word) : null,
                    child: builder(context, JourneyData(word, fonts.$1, fonts.$2)),
                  ),
          );
        },
      ),
    );
  }
}

class _JourneyNav extends StatelessWidget {
  const _JourneyNav({required this.stop, required this.word, required this.showPicker});

  final int stop;
  final String word;
  final bool showPicker;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 1; i < journeyStops.length; i++) ...[
              if (i > 1)
                Container(width: 14, height: 1.5, color: i <= stop ? BP.line : BP.lineFaint),
              _Stop(index: i, current: i == stop, passed: i < stop),
            ],
          ],
        ),
        if (showPicker) ...[
          const SizedBox(height: 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final p in journeyPresets) ...[
                const SizedBox(width: 8),
                _WordChip(text: p, selected: p == word),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _Stop extends StatefulWidget {
  const _Stop({required this.index, required this.current, required this.passed});

  final int index;
  final bool current;
  final bool passed;

  @override
  State<_Stop> createState() => _StopState();
}

class _StopState extends State<_Stop> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final (id, name) = journeyStops[widget.index];
    final c = widget.current ? BP.amber : (widget.passed ? BP.line : BP.lineDim);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => DeckScope.read(context).goToId(id),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: widget.current ? 16 : 11,
              height: widget.current ? 16 : 11,
              decoration: BoxDecoration(
                color: widget.current || widget.passed ? c : BP.paper,
                border: Border.all(color: c, width: 1.5),
              ),
            ),
            if (_hover || widget.current)
              Positioned(
                top: -24,
                child: Text(name, softWrap: false, style: BT.mono(12, color: c)),
              ),
          ],
        ),
      ),
    );
  }
}

class _WordChip extends StatelessWidget {
  const _WordChip({required this.text, required this.selected});

  final String text;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => journeyWord.value = text,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? BP.amber.withValues(alpha: 0.15) : Colors.transparent,
            border: Border.all(color: selected ? BP.amber : BP.lineFaint),
          ),
          child: Text(text, style: journeyStyle(18, color: selected ? BP.ink : BP.inkDim)),
        ),
      ),
    );
  }
}

/// Small reusable "data readout" row: a mono label and a value.
class JField extends StatelessWidget {
  const JField(this.label, this.value, {super.key, this.color = BP.ink, this.size = 15});

  final String label;
  final String value;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(label, style: BT.mono(size - 2, color: BP.inkFaint)),
      const SizedBox(width: 10),
      Text(value, style: BT.mono(size, color: color)),
    ],
  );
}

// ── Arabic joining (simplified Unicode joining types) ───────────────────────

const _rightJoining = {
  0x0622, 0x0623, 0x0624, 0x0625, 0x0627, 0x0629, 0x062F, 0x0630, 0x0631,
  0x0632, 0x0648, 0x0671, 0x0672, 0x0673, 0x0675, 0x0676, 0x0677, 0x0688,
  0x0689, 0x068A, 0x068B, 0x068C, 0x068D, 0x068E, 0x068F, 0x0690, 0x0691,
  0x0692, 0x0693, 0x0694, 0x0695, 0x0696, 0x0697, 0x0698, 0x0699, 0x06C0,
  0x06C3, 0x06C4, 0x06C5, 0x06C6, 0x06C7, 0x06C8, 0x06C9, 0x06CA, 0x06CB,
  0x06CD, 0x06CF, 0x06D2, 0x06D3, 0x06D5,
};

bool _isArabicLetter(int c) => (c >= 0x0620 && c <= 0x064A) || (c >= 0x066E && c <= 0x06D5);
bool _joinsForward(int c) => _isArabicLetter(c) && c != 0x0621 && !_rightJoining.contains(c);
bool _joinsBack(int c) => _isArabicLetter(c) && c != 0x0621;

/// The positional form HarfBuzz will pick (via GSUB init/medi/fina) for the
/// code point at [index] of [runes], and a string that renders that form on
/// its own (ZWJ forces the joining context).
(String name, String display) arabicForm(List<int> runes, int index) {
  final c = runes[index];
  final ch = String.fromCharCode(c);
  if (!_isArabicLetter(c)) return ('', ch);
  final prev = index > 0 && _joinsForward(runes[index - 1]) && _joinsBack(c);
  final next = index < runes.length - 1 && _joinsForward(c) && _joinsBack(runes[index + 1]);
  const zwj = '‍';
  if (prev && next) return ('medi', '$zwj$ch$zwj');
  if (prev) return ('fina', '$zwj$ch');
  if (next) return ('init', '$ch$zwj');
  return ('isol', ch);
}
