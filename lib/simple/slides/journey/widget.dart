import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../deck/theme.dart';
import '../../../deck/widgets.dart';
import '../../../slides/journey/journey.dart';
import 'frame.dart';

/// Stop 1: `Text('Flutter')`. The widget → render → painting → dart:ui chain
/// builds itself; on the right the REAL Text widget runs the layout protocol
/// (constraints down, size up) under a maxWidth the presenter drags.
class JWidgetSlide extends StatelessWidget {
  const JWidgetSlide({super.key});

  @override
  Widget build(BuildContext context) => SJourneyFrame(
    stop: 0,
    title: (w) => "Text('$w')",
    builder: (context, d) => _WidgetStage(data: d),
  );
}

const _fontSize = 72.0;

// Code panel (content-area coordinates).
const _codeW = 400.0;

// The chain.
const _nodeX = 480.0;
const _nodeW = 420.0;
const _nodeH = 78.0;
const _nodeGap = 44.0;
const _nodeCx = _nodeX + _nodeW / 2;
double _nodeTop(int i) => i * (_nodeH + _nodeGap);

// Right: rails → the real Text → a ruler that sets maxWidth.
const _demoX = 1000.0;
const _railTop = 112.0;
const _boxTop = 250.0;
const _railBottom = _boxTop - 8;
const _downX = _demoX + 12;
const _upX = _demoX + 36;
const _rulerY = 572.0;
const _minW = 120.0;
const _maxRange = 460.0;

const _stagger = 360;
const _loopStart = 200 + 5 * _stagger + 400;

const _nodes = [
  ('Text', 'widgets'),
  ('RichText', 'widgets'),
  ('RenderParagraph', 'rendering'),
  ('TextPainter', 'painting'),
  ('ui.Paragraph', 'dart:ui'),
];
const _edges = ['build()', 'createRenderObject()', 'owns', 'builds'];

class _WidgetStage extends StatefulWidget {
  const _WidgetStage({required this.data});

  final JourneyData data;

  @override
  State<_WidgetStage> createState() => _WidgetStageState();
}

class _WidgetStageState extends State<_WidgetStage> {
  double _maxW = 400;
  int _nonce = 0;
  bool _built = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    _built = false;
    _timer = Timer(const Duration(milliseconds: _loopStart), () {
      if (mounted) setState(() => _built = true);
    });
  }

  /// Tap the code: build the chain again.
  void _rebuild() => setState(() {
    _nonce++;
    _arm();
  });

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final word = widget.data.text;
    final def = DefaultTextStyle.of(context).style;

    // Exactly what Text does: DefaultTextStyle ⊕ style, MediaQuery's scaler,
    // then RenderParagraph lays its TextPainter out with (0, maxWidth).
    final tp = TextPainter(
      text: TextSpan(text: word, style: def.merge(journeyStyle(_fontSize))),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: _maxW);
    final size = tp.size;
    tp.dispose();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── Your code (tap: rebuild the chain) ───────────────────────────
        Positioned(
          left: 0,
          top: 0,
          width: _codeW,
          child: Reveal(
            visible: true,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(onTap: _rebuild, child: _CodePanel(word: word)),
            ),
          ),
        ),

        // ── The chain, drawn on in order ─────────────────────────────────
        Positioned.fill(
          child: IgnorePointer(
            child: KeyedSubtree(key: ValueKey(_nonce), child: const _Tree()),
          ),
        ),

        // ── Right: the real Text under real constraints ──────────────────
        Positioned.fill(
          child: IgnorePointer(
            child: Reveal(
              visible: true,
              delay: const Duration(milliseconds: 500),
              offset: const Offset(16, 0),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Positioned.fill(child: CustomPaint(painter: _RailsPainter())),
                  Positioned(
                    left: _upX + 28,
                    top: _railTop - 6,
                    child: _Readout(arrow: 'constraints ↓', value: 'w ≤ ${_maxW.round()}', color: BP.amber),
                  ),
                  Positioned(
                    left: _upX + 28,
                    top: _railTop + 40,
                    child: _Readout(
                      arrow: 'size ↑',
                      value: '${size.width.round()} × ${size.height.round()}',
                      color: BP.green,
                    ),
                  ),
                  // Dashed outline = RenderParagraph.size.
                  Positioned(
                    left: _demoX,
                    top: _boxTop,
                    width: size.width,
                    height: size.height,
                    child: CustomPaint(painter: DashedRectPainter(color: BP.line, strokeWidth: 1.5)),
                  ),
                  // The real widget: ConstrainedBox → Text → RichText → RenderParagraph.
                  Positioned(
                    left: _demoX,
                    top: _boxTop,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: _maxW),
                      child: Text(word, style: journeyStyle(_fontSize)),
                    ),
                  ),
                  // maxWidth, down to the ruler's thumb.
                  Positioned(
                    left: _demoX + _maxW - 1,
                    top: _boxTop - 26,
                    width: 2,
                    height: _rulerY - _boxTop + 14,
                    child: const CustomPaint(painter: _VDashPainter(BP.amber)),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Layout protocol, looping once the chain is built ─────────────
        if (_built)
          Positioned.fill(
            child: IgnorePointer(
              child: LoopBuilder(
                period: const Duration(milliseconds: 4000),
                builder: (context, t, _) => CustomPaint(painter: _ProtocolPainter(t: t, size: size)),
              ),
            ),
          ),

        // ── maxWidth ruler (last, so it sits on top) ─────────────────────
        Positioned(
          left: _demoX - _WidthRuler.pad,
          top: _rulerY - 24,
          child: Reveal(
            visible: true,
            delay: const Duration(milliseconds: 700),
            child: _WidthRuler(
              value: _maxW,
              onChanged: (v) => setState(() => _maxW = v),
            ),
          ),
        ),
      ],
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.arrow, required this.value, required this.color});

  final String arrow;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: '$arrow  ', style: BT.mono(20, color: color.withValues(alpha: 0.7))),
        TextSpan(text: value, style: BT.mono(22, color: color, weight: 500)),
      ],
    ),
  );
}

class _CodePanel extends StatelessWidget {
  const _CodePanel({required this.word});

  final String word;

  @override
  Widget build(BuildContext context) {
    TextSpan s(String t, Color c) => TextSpan(text: t, style: BT.mono(28, color: c));
    return BpPanel(
      padding: const EdgeInsets.fromLTRB(28, 26, 20, 26),
      child: Text.rich(
        TextSpan(
          style: BT.mono(28, height: 1.5),
          children: [
            s('Text', BP.line),
            s('(\n', BP.inkDim),
            s("  '", BP.inkDim),
            s(word, BP.amber),
            s("',\n", BP.inkDim),
            s('  style: ', BP.inkDim),
            s('TextStyle', BP.line),
            s('(\n', BP.inkDim),
            s('    fontSize: ', BP.inkDim),
            s('${_fontSize.round()}', BP.coral),
            s(',\n', BP.inkDim),
            s('  ),\n', BP.inkDim),
            s(')', BP.inkDim),
          ],
        ),
      ),
    );
  }
}

/// The five objects, revealed one by one with the calls that link them.
class _Tree extends StatelessWidget {
  const _Tree();

  @override
  Widget build(BuildContext context) {
    Duration ms(int v) => Duration(milliseconds: v);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // code → Text
        Positioned.fill(
          child: DrawOn(
            delay: ms(120),
            duration: ms(400),
            arrow: true,
            strokeWidth: 2,
            path: (_) => Path()
              ..moveTo(_codeW + 10, _nodeH / 2)
              ..lineTo(_nodeX - 10, _nodeH / 2),
          ),
        ),
        for (var i = 0; i < _nodes.length; i++)
          Positioned(
            left: _nodeX,
            top: _nodeTop(i),
            width: _nodeW,
            height: _nodeH,
            child: Reveal(
              visible: true,
              delay: ms(200 + i * _stagger),
              offset: const Offset(0, 16),
              child: _Node(name: _nodes[i].$1, lib: _nodes[i].$2),
            ),
          ),
        for (var i = 0; i < _edges.length; i++) ...[
          Positioned.fill(
            child: DrawOn(
              delay: ms(200 + i * _stagger + 220),
              duration: ms(320),
              arrow: true,
              strokeWidth: 2,
              path: (_) => Path()
                ..moveTo(_nodeCx, _nodeTop(i) + _nodeH + 4)
                ..lineTo(_nodeCx, _nodeTop(i + 1) - 6),
            ),
          ),
          Positioned(
            left: _nodeCx + 16,
            top: _nodeTop(i) + _nodeH + (_nodeGap - 24) / 2,
            child: Reveal(
              visible: true,
              delay: ms(200 + i * _stagger + 360),
              offset: const Offset(-10, 0),
              child: Text(_edges[i], style: BT.mono(18, color: BP.line)),
            ),
          ),
        ],
        // RenderParagraph node ↔ the real box on the right
        Positioned.fill(
          child: DrawOn(
            delay: ms(200 + 5 * _stagger),
            duration: ms(500),
            dashed: true,
            strokeWidth: 1.5,
            color: BP.lineDim,
            path: (_) => Path()
              ..moveTo(_nodeX + _nodeW + 8, _nodeTop(2) + _nodeH / 2)
              ..lineTo(_demoX - 14, _nodeTop(2) + _nodeH / 2),
          ),
        ),
      ],
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.name, required this.lib});

  final String name;
  final String lib;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 22),
    decoration: BoxDecoration(
      color: BP.panel,
      border: Border.all(color: BP.line, width: 1.5),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(name, style: BT.display(32)),
        const Spacer(),
        Text(lib, style: BT.mono(16, color: BP.inkFaint)),
      ],
    ),
  );
}

/// One layout pass, looping: constraints run down the rail, the chain lays
/// out (RenderParagraph → TextPainter → ui.Paragraph), the size runs back up.
class _ProtocolPainter extends CustomPainter {
  _ProtocolPainter({required this.t, required this.size});

  final double t;
  final Size size;

  static double _ramp(double t, double a, double b) =>
      Curves.easeInOutCubic.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  static double _win(double t, double a, double b, [double f = 0.04]) =>
      ((t - a) / f).clamp(0.0, 1.0) * ((b - t) / f).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size _) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    void glow(Rect r, Color c, double g) {
      if (g <= 0) return;
      canvas.drawRect(r, Paint()..color = c.withValues(alpha: 0.06 * g));
      canvas.drawRect(r, stroke..color = c.withValues(alpha: g));
    }

    // Layout delegates down the chain: RenderParagraph → TextPainter → Paragraph.
    for (final (i, a, b) in const [(2, 0.22, 0.70), (3, 0.30, 0.64), (4, 0.38, 0.56)]) {
      glow(Rect.fromLTWH(_nodeX, _nodeTop(i), _nodeW, _nodeH).inflate(5), BP.amber, _win(t, a, b));
    }
    // The real box lights while it lays out.
    glow(Rect.fromLTWH(_demoX, _boxTop, size.width, size.height).inflate(6), BP.amber, _win(t, 0.22, 0.66));

    // Call dot running down the chain, result dot running back up.
    final top = _nodeTop(2) + _nodeH;
    final bottom = _nodeTop(4);
    if (t > 0.26 && t < 0.42) {
      final y = lerpDouble(top, bottom, _ramp(t, 0.26, 0.41))!;
      canvas.drawCircle(Offset(_nodeCx, y), 7, Paint()..color = BP.amber);
    }
    if (t > 0.54 && t < 0.68) {
      final y = lerpDouble(bottom, top, _ramp(t, 0.54, 0.67))!;
      canvas.drawCircle(Offset(_nodeCx, y), 7, Paint()..color = BP.green);
    }

    // Packets on the rails.
    void diamond(Offset c, Color color) {
      const r = 11.0;
      final d = Path()
        ..moveTo(c.dx, c.dy - r)
        ..lineTo(c.dx + r, c.dy)
        ..lineTo(c.dx, c.dy + r)
        ..lineTo(c.dx - r, c.dy)
        ..close();
      canvas.drawPath(d, Paint()..color = color);
    }

    if (t > 0.01 && t < 0.26) {
      diamond(Offset(_downX, lerpDouble(_railTop, _railBottom, _ramp(t, 0.02, 0.22))!), BP.amber);
    }
    if (t > 0.66 && t < 0.92) {
      diamond(Offset(_upX, lerpDouble(_railBottom, _railTop, _ramp(t, 0.68, 0.88))!), BP.green);
    }
  }

  @override
  bool shouldRepaint(_ProtocolPainter old) => old.t != t || old.size != size;
}

class _RailsPainter extends CustomPainter {
  const _RailsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final down = Paint()
      ..color = BP.amber.withValues(alpha: 0.6)
      ..strokeWidth = 2;
    final up = Paint()
      ..color = BP.green.withValues(alpha: 0.6)
      ..strokeWidth = 2;
    drawArrow(canvas, const Offset(_downX, _railTop), const Offset(_downX, _railBottom), down, head: 10);
    drawArrow(canvas, const Offset(_upX, _railBottom), const Offset(_upX, _railTop), up, head: 10);
  }

  @override
  bool shouldRepaint(_RailsPainter old) => false;
}

class _VDashPainter extends CustomPainter {
  const _VDashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    canvas.drawPath(
      dashPath(
        Path()
          ..moveTo(x, 0)
          ..lineTo(x, size.height),
        dash: 6,
        gap: 5,
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(_VDashPainter old) => old.color != color;
}

/// A ruler under the word: the thumb sits exactly at x = maxWidth, so
/// dragging it drags the constraint line.
class _WidthRuler extends StatelessWidget {
  const _WidthRuler({required this.value, required this.onChanged});

  /// Room left of 0 so the thumb and the first tick aren't clipped.
  static const pad = 16.0;

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    void update(Offset p) => onChanged((p.dx - pad).clamp(_minW, _maxRange));
    return SizedBox(
      width: _maxRange + 2 * pad,
      height: 48,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => update(d.localPosition),
          onPanUpdate: (d) => update(d.localPosition),
          child: CustomPaint(painter: _RulerPainter(value)),
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter(this.value);

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    const x0 = _WidthRuler.pad;
    final y = size.height / 2;
    final dim = Paint()
      ..color = BP.lineDim
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(x0, y), Offset(x0 + _maxRange, y), dim);
    for (var v = 0.0; v <= _maxRange + 0.1; v += 20) {
      final h = v % 100 == 0 ? 10.0 : 5.0;
      canvas.drawLine(Offset(x0 + v, y - h), Offset(x0 + v, y + h), dim);
    }
    final x = x0 + value;
    canvas.drawLine(
      Offset(x0, y),
      Offset(x, y),
      Paint()
        ..color = BP.line
        ..strokeWidth = 3,
    );
    const r = 13.0;
    final d = Path()
      ..moveTo(x, y - r)
      ..lineTo(x + r, y)
      ..lineTo(x, y + r)
      ..lineTo(x - r, y)
      ..close();
    canvas.drawPath(d, Paint()..color = BP.paper);
    canvas.drawPath(
      d,
      Paint()
        ..color = BP.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_RulerPainter old) => old.value != value;
}
