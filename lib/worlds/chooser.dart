import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../deck/deck.dart';
import '../deck/theme.dart';
import 'world.dart';

/// Version picker shown when no world was requested (e.g. native runs).
/// Click a card or press 1–5.
class WorldChooser extends StatefulWidget {
  const WorldChooser({super.key, required this.worlds, required this.onPick});

  final List<World> worlds;
  final ValueChanged<World> onPick;

  @override
  State<WorldChooser> createState() => _WorldChooserState();
}

class _WorldChooserState extends State<WorldChooser> {
  static const _blurbs = {
    'factory': 'a tour of the glyph factory',
    'construction': 'one building, floor by floor',
    'workers': 'Latin: 3 workers. The rest: a crew.',
    'detective': 'why does 直 look Chinese?',
    'classic': 'plain blueprint deck',
  };

  int? _hover;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    final n = int.tryParse(e.character ?? '');
    if (n != null && n >= 1 && n <= widget.worlds.length) {
      widget.onPick(widget.worlds[n - 1]);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final scale = (box.maxWidth / BP.canvas.width).clamp(0.0, box.maxHeight / BP.canvas.height);
        final origin = Offset(
          (box.maxWidth - BP.canvas.width * scale) / 2,
          (box.maxHeight - BP.canvas.height * scale) / 2,
        );
        return ColoredBox(
          color: BP.paper,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: GridPaperPainter(scale: scale, origin: origin)),
              ),
              Positioned.fill(
                child: FittedBox(
                  child: SizedBox.fromSize(size: BP.canvas, child: _page()),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _page() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(96, 110, 96, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 28, height: 1.5, color: BP.line),
              const SizedBox(width: 12),
              Text('flutter / text', style: BT.mono(16)),
            ],
          ),
          const SizedBox(height: 14),
          Text('Text rendering', style: BT.display(104, letterSpacing: -2.5, height: 1)),
          const SizedBox(height: 16),
          Text('from code points to pixels · and how Flutter does it',
              style: BT.mono(20, color: BP.inkDim)),
          const SizedBox(height: 8),
          Text('テキストレンダリング',
              style: BT.sample(24, color: BP.inkDim).copyWith(locale: const Locale('ja'))),
          const Spacer(),
          Wrap(
            spacing: 22,
            runSpacing: 22,
            children: [
              for (var i = 0; i < widget.worlds.length; i++) _card(i),
            ],
          ),
          const SizedBox(height: 36),
          Text('click a version or press 1–${widget.worlds.length} · in the deck: w switches version',
              style: BT.mono(15, color: BP.inkFaint)),
        ],
      ),
    );
  }

  Widget _card(int i) {
    final w = widget.worlds[i];
    final hot = _hover == i;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = i),
      onExit: (_) => setState(() => _hover = null),
      child: GestureDetector(
        onTap: () => widget.onPick(w),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 266,
          height: 190,
          padding: const EdgeInsets.all(22),
          transform: Matrix4.translationValues(0, hot ? -4 : 0, 0),
          decoration: BoxDecoration(
            color: BP.panel,
            border: Border.all(color: hot ? BP.amber : BP.lineDim, width: hot ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${i + 1}', style: BT.mono(15, color: BP.amber)),
              const SizedBox(height: 10),
              Text(w.name, style: BT.display(28).copyWith(locale: const Locale('ja'))),
              const Spacer(),
              Text(_blurbs[w.id] ?? '', style: BT.sample(15, color: BP.inkDim)),
            ],
          ),
        ),
      ),
    );
  }
}
