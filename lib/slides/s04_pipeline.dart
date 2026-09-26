import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../deck/deck.dart';
import '../deck/theme.dart';
import '../deck/widgets.dart';

class _Stage {
  const _Stage(this.name, this.lib, this.slideId, this.readout);

  final String name;
  final String lib;
  final String slideId;
  final String readout;
}

const _stages = [
  _Stage('text', 'unicode', 'string', '"Hi كتاب"  →  U+0048 U+0069 U+0020 U+0643 U+062A U+0627 U+0628'),
  _Stage('itemize', 'ICU', 'itemize', '[latin →  0..3)   [arabic ←  3..7)'),
  _Stage('fonts', 'font manager', 'fallback', 'latin → Space Grotesk    arabic → Noto Kufi Arabic'),
  _Stage('shape', 'HarfBuzz', 'shaping', 'code points  →  glyph ids + advances + offsets'),
  _Stage('wrap', 'ICU · UAX #14', 'linebreak', 'break opportunities  →  lines that fit the width'),
  _Stage('position', 'layout', 'bidi', 'visual order · alignment · baselines  →  x, y per glyph'),
  _Stage('raster', 'Skia · GPU', 'raster', 'outlines  →  coverage  →  pixels'),
];

const _boxW = 176.0;
const _boxH = 250.0;
const _gapW = (1472 - 7 * _boxW) / 6;
const _top = 110.0;

/// The whole text pipeline, one stage per build step, with a packet running
/// through it. Clicking a stage jumps to its deep-dive slide.
class PipelineSlide extends StatefulWidget {
  const PipelineSlide({super.key});

  @override
  State<PipelineSlide> createState() => _PipelineSlideState();
}

class _PipelineSlideState extends State<PipelineSlide> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final step = SlideScope.of(context).step;
    final visible = step + 1;
    return SlideFrame(
      title: 'The pipeline',
      child: LoopBuilder(
        period: Duration(milliseconds: 900 * visible + 600),
        builder: (context, t, _) {
          // Packet position along the rail, in stage units.
          final pos = (t * (visible - 1 + 0.6)).clamp(0.0, visible - 1.0);
          final active = _hover ?? pos.round();
          final focus = _hover ?? step;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Arrows between boxes
              for (var i = 0; i < 6; i++)
                Positioned(
                  left: (i + 1) * _boxW + i * _gapW + 4,
                  top: _top + _boxH / 2 - 14,
                  width: _gapW - 8,
                  height: 20,
                  child: DrawOn(
                    visible: i + 1 < visible,
                    duration: const Duration(milliseconds: 400),
                    arrow: true,
                    color: BP.line,
                    path: (s) => Path()
                      ..moveTo(0, s.height / 2)
                      ..lineTo(s.width, s.height / 2),
                  ),
                ),
              for (var i = 0; i < _stages.length; i++)
                Positioned(
                  left: i * (_boxW + _gapW),
                  top: _top - 40,
                  width: _boxW,
                  child: Reveal(
                    visible: i < visible,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      onEnter: (_) => setState(() => _hover = i),
                      onExit: (_) => setState(() => _hover = null),
                      child: GestureDetector(
                        onTap: () => DeckScope.read(context).goToId(_stages[i].slideId),
                        child: _StageBox(
                          index: i,
                          stage: _stages[i],
                          hot: i == active && i < visible,
                        ),
                      ),
                    ),
                  ),
                ),
              // Rail + packet
              Positioned(
                left: _boxW / 2,
                top: _top + _boxH + 80,
                width: 6 * (_boxW + _gapW),
                height: 30,
                child: CustomPaint(
                  painter: _RailPainter(visible: visible, pos: pos),
                ),
              ),
              // Readout
              Positioned(
                left: 0,
                right: 0,
                top: _top + _boxH + 150,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Row(
                    key: ValueKey(focus),
                    children: [
                      Text(_stages[focus].name, style: BT.mono(18, color: BP.amber)),
                      const SizedBox(width: 18),
                      Container(width: 30, height: 1, color: BP.lineDim),
                      const SizedBox(width: 18),
                      Text(_stages[focus].readout, style: BT.sample(22, color: BP.ink)),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StageBox extends StatelessWidget {
  const _StageBox({required this.index, required this.stage, required this.hot});

  final int index;
  final _Stage stage;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          (index + 1).toString().padLeft(2, '0'),
          style: BT.mono(14, color: hot ? BP.amber : BP.inkFaint),
        ),
        const SizedBox(height: 16),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: _boxW,
          height: _boxH,
          decoration: BoxDecoration(
            color: hot ? BP.line.withValues(alpha: 0.10) : BP.panel,
            border: Border.all(color: hot ? BP.amber : BP.lineDim, width: hot ? 2 : 1),
          ),
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: _Illustration(index: index, hot: hot),
                ),
              ),
              Container(height: 1, color: hot ? BP.amber : BP.lineDim),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(stage.name, style: BT.display(24, color: hot ? BP.amber : BP.ink)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(stage.lib, style: BT.mono(14, color: BP.inkDim)),
      ],
    );
  }
}

class _RailPainter extends CustomPainter {
  _RailPainter({required this.visible, required this.pos});

  final int visible;
  final double pos;

  @override
  void paint(Canvas canvas, Size size) {
    final seg = size.width / 6;
    final y = size.height / 2;
    final dim = Paint()
      ..color = BP.lineFaint
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), dim);
    final lit = Paint()
      ..color = BP.lineDim
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, y), Offset(seg * (visible - 1), y), lit);
    for (var i = 0; i < 7; i++) {
      final x = seg * i;
      canvas.drawLine(Offset(x, y - 8), Offset(x, y + 8), i < visible ? lit : dim);
    }
    // Packet: a diamond with a short comet trail.
    final x = seg * pos;
    for (var k = 1; k <= 6; k++) {
      final tx = x - k * 10;
      if (tx < 0) break;
      canvas.drawCircle(
        Offset(tx, y),
        3.5 - k * 0.4,
        Paint()..color = BP.amber.withValues(alpha: 0.5 - k * 0.07),
      );
    }
    final d = Path()
      ..moveTo(x, y - 9)
      ..lineTo(x + 9, y)
      ..lineTo(x, y + 9)
      ..lineTo(x - 9, y)
      ..close();
    canvas.drawPath(d, Paint()..color = BP.amber);
  }

  @override
  bool shouldRepaint(_RailPainter old) => old.pos != pos || old.visible != visible;
}

/// A tiny drawing for each stage.
class _Illustration extends StatelessWidget {
  const _Illustration({required this.index, required this.hot});

  final int index;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    final ink = hot ? BP.ink : BP.inkDim;
    switch (index) {
      case 0:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Hi كتاب', style: BT.sample(30, color: ink)),
            const SizedBox(height: 10),
            for (final s in ['U+0048', 'U+0069', 'U+0643 …'])
              Text(s, style: BT.mono(13, color: BP.line)),
          ],
        );
      case 1:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _run('Hi', BP.line, '→'),
                const SizedBox(width: 10),
                _run('كتاب', BP.amber, '←'),
              ],
            ),
          ],
        );
      case 2:
        return Center(
          child: SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              children: [
                for (final (k, g, c) in [(0, '😀', BP.inkFaint), (1, 'ب', BP.amber), (2, 'Aa', BP.line)])
                  Positioned(
                    left: k * 18.0,
                    top: k * 18.0,
                    child: Container(
                      width: 80,
                      height: 80,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: BP.panel,
                        border: Border.all(color: c),
                      ),
                      child: Text(g, style: BT.sample(30, color: ink)),
                    ),
                  ),
              ],
            ),
          ),
        );
      case 3:
        return Center(child: CustomPaint(size: const Size(140, 110), painter: _ShapePainter(ink)));
      case 4:
        return CustomPaint(painter: _WrapPainter(hot), child: const SizedBox.expand());
      case 5:
        return CustomPaint(painter: _PositionPainter(hot), child: const SizedBox.expand());
      default:
        return CustomPaint(painter: _PixelPainter(hot), child: const SizedBox.expand());
    }
  }

  Widget _run(String t, Color c, String arrow) => Column(
    children: [
      Text(t, style: BT.sample(30, color: c)),
      Container(width: t.length * 14.0 + 10, height: 2, color: c),
      const SizedBox(height: 6),
      Text(arrow, style: BT.mono(20, color: c)),
    ],
  );
}

class _ShapePainter extends CustomPainter {
  _ShapePainter(this.ink);

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final probe = TextProbe(TextSpan(text: 'كتاب', style: BT.sample(52, color: ink)));
    final o = Offset((size.width - probe.size.width) / 2, (size.height - probe.size.height) / 2);
    final p = Paint()
      ..color = BP.line
      ..style = PaintingStyle.stroke;
    for (final (s, e) in probe.graphemes()) {
      for (final b in probe.boxes(s, e)) {
        canvas.drawPath(dashPath(Path()..addRect(b.toRect().shift(o)), dash: 3, gap: 3), p);
      }
    }
    probe.paint(canvas, o);
    probe.dispose();
  }

  @override
  bool shouldRepaint(_ShapePainter old) => old.ink != ink;
}

class _WrapPainter extends CustomPainter {
  _WrapPainter(this.hot);

  final bool hot;

  @override
  void paint(Canvas canvas, Size size) {
    final bar = Paint()..color = hot ? BP.line : BP.lineDim;
    final widths = [0.95, 0.8, 0.9, 0.45];
    for (var i = 0; i < widths.length; i++) {
      final y = 22.0 + i * 30;
      canvas.drawRect(Rect.fromLTWH(0, y, (size.width - 26) * widths[i], 12), bar);
    }
    // Width limit
    final lim = Paint()
      ..color = BP.amber
      ..strokeWidth = 1.5;
    final x = size.width - 16;
    canvas.drawPath(
      dashPath(Path()
        ..moveTo(x, 8)
        ..lineTo(x, size.height - 4)),
      lim..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_WrapPainter old) => old.hot != hot;
}

class _PositionPainter extends CustomPainter {
  _PositionPainter(this.hot);

  final bool hot;

  @override
  void paint(Canvas canvas, Size size) {
    final base = size.height * 0.72;
    canvas.drawLine(
      Offset(0, base),
      Offset(size.width, base),
      Paint()
        ..color = BP.amber
        ..strokeWidth = 1.5,
    );
    final box = Paint()
      ..color = hot ? BP.line : BP.lineDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final heights = <double>[60, 44, 70, 30, 52];
    var x = 6.0;
    for (final h in heights) {
      canvas.drawRect(Rect.fromLTWH(x, base - h, 22, h), box);
      canvas.drawCircle(Offset(x, base), 2.5, Paint()..color = BP.amber);
      x += 28;
    }
  }

  @override
  bool shouldRepaint(_PositionPainter old) => old.hot != hot;
}

class _PixelPainter extends CustomPainter {
  _PixelPainter(this.hot);

  final bool hot;

  // Coverage of a tiny "a", 8×9.
  static const _a = [
    [0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 3, 8, 9, 6, 0, 0],
    [0, 0, 0, 0, 0, 9, 3, 0],
    [0, 0, 4, 8, 9, 9, 4, 0],
    [0, 5, 8, 1, 0, 9, 4, 0],
    [0, 8, 4, 0, 1, 9, 4, 0],
    [0, 5, 9, 7, 8, 7, 6, 0],
    [0, 0, 1, 2, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cell = math.min(size.width / 8, size.height / 9);
    final o = Offset((size.width - cell * 8) / 2, (size.height - cell * 9) / 2);
    final grid = Paint()
      ..color = BP.lineFaint
      ..style = PaintingStyle.stroke;
    for (var r = 0; r < 9; r++) {
      for (var c = 0; c < 8; c++) {
        final rect = Rect.fromLTWH(o.dx + c * cell, o.dy + r * cell, cell, cell);
        final v = _a[r][c] / 9;
        if (v > 0) {
          canvas.drawRect(rect, Paint()..color = (hot ? BP.ink : BP.inkDim).withValues(alpha: v));
        }
        canvas.drawRect(rect, grid);
      }
    }
  }

  @override
  bool shouldRepaint(_PixelPainter old) => old.hot != hot;
}
