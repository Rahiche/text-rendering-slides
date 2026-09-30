import 'package:flutter/material.dart';

import '../../../deck/deck.dart';
import '../../../deck/font_data.dart';
import '../../../deck/theme.dart';
import '../../../deck/widgets.dart';
import '../../../slides/journey/journey.dart';

/// The simplified journey: six stops, in order.
const simpleJourneyStops = [
  ('j-widget', 'widget'),
  ('j-font', 'glyphs'),
  ('j-shape', 'shape'),
  ('j-layout', 'layout'),
  ('j-atlas', 'raster'),
  ('j-gpu', 'draw'),
];

const simpleJourneyPresets = ['Flutter', 'Type', 'مرحبا', '👋🏽'];

/// A journey slide in the simplified deck: SlideFrame + a slim "you are
/// here" strip + the word picker. [builder] gets the resolved [JourneyData].
class SJourneyFrame extends StatelessWidget {
  const SJourneyFrame({
    super.key,
    required this.stop,
    required this.title,
    required this.builder,
    this.showPicker = true,
    this.rekey = true,
  });

  /// Index into [simpleJourneyStops].
  final int stop;
  final String Function(String word) title;
  final Widget Function(BuildContext context, JourneyData data) builder;
  final bool showPicker;

  /// Rebuild the content from scratch (fresh state) when the word changes.
  final bool rekey;

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
            trailing: _Nav(stop: stop, word: word, showPicker: showPicker),
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

class _Nav extends StatelessWidget {
  const _Nav({required this.stop, required this.word, required this.showPicker});

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
            for (var i = 0; i < simpleJourneyStops.length; i++) ...[
              if (i > 0) Container(width: 22, height: 2, color: i <= stop ? BP.line : BP.lineFaint),
              _Stop(index: i, current: i == stop, passed: i < stop),
            ],
          ],
        ),
        if (showPicker) ...[
          const SizedBox(height: 18),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final p in simpleJourneyPresets) ...[
                const SizedBox(width: 10),
                _WordChip(text: p, selected: p == word),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _Stop extends StatelessWidget {
  const _Stop({required this.index, required this.current, required this.passed});

  final int index;
  final bool current;
  final bool passed;

  @override
  Widget build(BuildContext context) {
    final (id, name) = simpleJourneyStops[index];
    final c = current ? BP.amber : (passed ? BP.line : BP.lineDim);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => DeckScope.read(context).goToId(id),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: current ? 18 : 12,
              height: current ? 18 : 12,
              decoration: BoxDecoration(
                color: current || passed ? c : BP.paper,
                border: Border.all(color: c, width: 2),
              ),
            ),
            if (current)
              Positioned(
                top: -30,
                child: Text(name, softWrap: false, style: BT.mono(16, color: c)),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? BP.amber.withValues(alpha: 0.15) : Colors.transparent,
            border: Border.all(color: selected ? BP.amber : BP.lineFaint, width: 1.5),
          ),
          child: Text(text, style: journeyStyle(24, color: selected ? BP.ink : BP.inkDim)),
        ),
      ),
    );
  }
}
