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

// Tree geometry (content-area coordinates).
const _nodeX = 430.0;
const _nodeW = 300.0;
const _nodeH = 72.0;
const _nodeGap = 56.0;
const _nodeCx = _nodeX + _nodeW / 2;
double _nodeTop(int i) => 14 + i * (_nodeH + _nodeGap);

// Right column: parent → rails → RenderParagraph.
const _rightX = 1060.0;
const _parentW = 210.0;
const _parentH = 40.0;
const _boxTop = 176.0;
const _downX = _rightX + 24;
const _upX = _rightX + 50;
const _railTop = _parentH + 6;
const _railBottom = _boxTop - 8;

const _stagger = 520;
const _sideDelay = 300 + 5 * _stagger;

const _nodes = [
  ('Text', 'StatelessWidget', 'widgets'),
  ('RichText', 'MultiChildRenderObjectWidget', 'widgets'),
  ('RenderParagraph', 'RenderBox', 'rendering'),
  ('TextPainter', 'layout · paint', 'painting'),
  ('ui.Paragraph', '→ SkParagraph', 'dart:ui'),
];
const _edges = ['build()', 'createRenderObject()', 'owns', 'builds'];

String _num(double v) => double.parse(v.toStringAsFixed(2)).toString();

class _WidgetStage extends StatefulWidget {
  const _WidgetStage({required this.data});

  final JourneyData data;

  @override
  State<_WidgetStage> createState() => _WidgetStageState();
}

class _WidgetStageState extends State<_WidgetStage> {
  double _maxW = 360;
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
    _timer = Timer(const Duration(milliseconds: _sideDelay + 700), () {
      if (mounted) setState(() => _built = true);
    });
  }

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
    final scaler = MediaQuery.textScalerOf(context);

    // Exactly what Text does: DefaultTextStyle ⊕ style, MediaQuery's scaler,
    // then RenderParagraph lays its TextPainter out with (0, maxWidth).
    final tp = TextPainter(
      text: TextSpan(text: word, style: def.merge(journeyStyle(48))),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout(maxWidth: _maxW);
    final size = tp.size;
    tp.dispose();

    final fromDefault = [
      if (def.height != null) 'height ${_num(def.height!)}',
      if (def.letterSpacing != null) 'spacing ${_num(def.letterSpacing!)}',
    ].join(' · ');
    final scale = scaler.scale(1);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── Code ─────────────────────────────────────────────────────────
        Positioned(
          left: 0,
          top: 20,
          width: 380,
          child: Reveal(visible: true, child: _CodePanel(word: word)),
        ),

        // ── The tree, drawn on in order ──────────────────────────────────
        Positioned.fill(
          child: IgnorePointer(
            child: KeyedSubtree(
              key: ValueKey(_nonce),
              child: _Tree(fromDefault: fromDefault, scale: scale),
            ),
          ),
        ),

        // ── Right: the real Text under real constraints ──────────────────
        Positioned(
          left: _rightX,
          top: 0,
          width: _parentW,
          height: _parentH,
          child: Reveal(
            visible: true,
            delay: const Duration(milliseconds: 500),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: BP.panel,
                border: Border.all(color: BP.lineDim),
              ),
              child: Text('RenderConstrainedBox', style: BT.mono(14, color: BP.inkDim)),
            ),
          ),
        ),
        const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _RailsPainter()))),
        Positioned(
          left: _rightX - 170,
          top: 124,
          width: 156,
          child: Text(
            'constraints ↓',
            textAlign: TextAlign.right,
            style: BT.mono(12, color: BP.amber.withValues(alpha: 0.8)),
          ),
        ),
        Positioned(
          left: _rightX - 170,
          top: 144,
          width: 156,
          child: Text(
            'size ↑',
            textAlign: TextAlign.right,
            style: BT.mono(12, color: BP.green.withValues(alpha: 0.8)),
          ),
        ),
        Positioned(
          left: _rightX - 200,
          top: _boxTop + 4,
          width: 186,
          child: Text('RenderParagraph', textAlign: TextAlign.right, style: BT.mono(14, color: BP.line)),
        ),
        // Dashed outline = RenderParagraph.size.
        Positioned(
          left: _rightX,
          top: _boxTop,
          width: size.width,
          height: size.height,
          child: CustomPaint(painter: DashedRectPainter(color: BP.line)),
        ),
        // The real widget: Stack → ConstrainedBox → Text → RichText → RenderParagraph.
        Positioned(
          left: _rightX,
          top: _boxTop,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _maxW),
            child: Text(word, style: journeyStyle(48)),
          ),
        ),
        // maxWidth limit
        Positioned(
          left: _rightX + _maxW - 1,
          top: _boxTop - 14,
          width: 2,
          height: 380,
          child: const CustomPaint(painter: _VDashPainter(BP.amber)),
        ),
        Positioned(
          left: _rightX + _maxW - 106,
          top: _boxTop + 370,
          width: 100,
          child: Text('maxWidth', textAlign: TextAlign.right, style: BT.mono(12, color: BP.amber)),
        ),

        // ── Layout protocol, looping once the tree is built ──────────────
        if (_built)
          Positioned.fill(
            child: IgnorePointer(
              child: LoopBuilder(
                period: const Duration(milliseconds: 3800),
                builder: (context, t, _) => _Protocol(t: t, maxW: _maxW, size: size),
              ),
            ),
          ),

        // ── Controls (last, so they sit on top) ──────────────────────────
        Positioned(
          left: 0,
          top: 300,
          child: Reveal(
            visible: true,
            delay: const Duration(milliseconds: 400),
            child: BpButton(label: 'rebuild', icon: Icons.replay, size: 14, onTap: _rebuild),
          ),
        ),
        Positioned(
          left: _rightX,
          top: 584,
          child: BpSlider(
            value: _maxW,
            min: 60,
            max: 400,
            width: 210,
            label: 'maxWidth',
            format: (v) => '${v.round()} px',
            onChanged: (v) => setState(() => _maxW = v),
          ),
        ),
      ],
    );
  }
}

class _CodePanel extends StatelessWidget {
  const _CodePanel({required this.word});

  final String word;

  @override
  Widget build(BuildContext context) {
    TextSpan s(String t, Color c) => TextSpan(text: t, style: BT.mono(22, color: c));
    return BpPanel(
      label: 'your code',
      padding: const EdgeInsets.fromLTRB(24, 26, 20, 22),
      child: Text.rich(
        TextSpan(
          style: BT.mono(22, height: 1.55),
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
            s('48', BP.coral),
            s(',\n', BP.inkDim),
            s('  ),\n', BP.inkDim),
            s(')', BP.inkDim),
          ],
        ),
      ),
    );
  }
}

/// The five objects, revealed one by one with the calls that create them.
class _Tree extends StatelessWidget {
  const _Tree({required this.fromDefault, required this.scale});

  final String fromDefault;
  final double scale;

  @override
  Widget build(BuildContext context) {
    Duration ms(int v) => Duration(milliseconds: v);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // code → Text
        Positioned.fill(
          child: DrawOn(
            delay: ms(150),
            duration: ms(450),
            arrow: true,
            path: (_) => Path()
              ..moveTo(386, 50)
              ..lineTo(_nodeX - 8, 50),
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
              delay: ms(300 + i * _stagger),
              offset: const Offset(0, 16),
              child: _Node(name: _nodes[i].$1, kind: _nodes[i].$2, lib: _nodes[i].$3),
            ),
          ),
        for (var i = 0; i < _edges.length; i++) ...[
          Positioned.fill(
            child: DrawOn(
              delay: ms(300 + i * _stagger + 260),
              duration: ms(380),
              arrow: true,
              path: (_) => Path()
                ..moveTo(_nodeCx, _nodeTop(i) + _nodeH + 4)
                ..lineTo(_nodeCx, _nodeTop(i + 1) - 6),
            ),
          ),
          Positioned(
            left: _nodeCx + 14,
            top: _nodeTop(i) + _nodeH + 17,
            child: Reveal(
              visible: true,
              delay: ms(300 + i * _stagger + 420),
              offset: const Offset(-10, 0),
              child: Text(_edges[i], style: BT.mono(14, color: BP.line)),
            ),
          ),
        ],
        // Side inputs into Text
        Positioned(
          left: 780,
          top: 2,
          width: 250,
          child: Reveal(
            visible: true,
            delay: ms(_sideDelay),
            offset: const Offset(16, 0),
            child: _SideInput(title: 'DefaultTextStyle', merge: 'style', detail: fromDefault),
          ),
        ),
        Positioned(
          left: 780,
          top: 64,
          width: 250,
          child: Reveal(
            visible: true,
            delay: ms(_sideDelay + 200),
            offset: const Offset(16, 0),
            child: _SideInput(title: 'TextScaler', detail: 'MediaQuery · ×${scale.toStringAsFixed(1)}'),
          ),
        ),
        Positioned.fill(
          child: DrawOn(
            delay: ms(_sideDelay + 150),
            duration: ms(400),
            arrow: true,
            color: BP.lineDim,
            path: (_) => Path()
              ..moveTo(776, 26)
              ..lineTo(_nodeX + _nodeW + 6, 38),
          ),
        ),
        Positioned.fill(
          child: DrawOn(
            delay: ms(_sideDelay + 350),
            duration: ms(400),
            arrow: true,
            color: BP.lineDim,
            path: (_) => Path()
              ..moveTo(776, 86)
              ..lineTo(_nodeX + _nodeW + 6, 64),
          ),
        ),
        // RenderParagraph node ↔ the real box on the right
        Positioned.fill(
          child: DrawOn(
            delay: ms(_sideDelay + 500),
            duration: ms(600),
            dashed: true,
            color: BP.lineDim,
            path: (_) => Path()
              ..moveTo(_nodeX + _nodeW + 6, _nodeTop(2) + _nodeH / 2)
              ..lineTo(_rightX - 158, _boxTop + 13),
          ),
        ),
      ],
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.name, required this.kind, required this.lib});

  final String name;
  final String kind;
  final String lib;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: BP.panel,
      border: Border.all(color: BP.line, width: 1.2),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(name, style: BT.display(22)),
            const Spacer(),
            Text(lib, style: BT.mono(11, color: BP.inkFaint)),
          ],
        ),
        const SizedBox(height: 4),
        Text(kind, style: BT.mono(13, color: BP.inkDim)),
      ],
    ),
  );
}

class _SideInput extends StatelessWidget {
  const _SideInput({required this.title, required this.detail, this.merge});

  final String title;
  final String detail;

  /// Shown as "title ⊕ merge".
  final String? merge;

  @override
  Widget build(BuildContext context) => DashedBox(
    color: BP.lineDim,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            style: BT.mono(13, color: BP.ink),
            children: [
              TextSpan(text: title),
              if (merge != null) ...[
                const WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 7),
                    child: CustomPaint(size: Size(12, 12), painter: _OPlusPainter()),
                  ),
                ),
                TextSpan(text: merge, style: BT.mono(13, color: BP.amber)),
              ],
            ],
          ),
        ),
        if (detail.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(detail, style: BT.mono(11, color: BP.inkFaint)),
        ],
      ],
    ),
  );
}

/// Packets on the rails, node glows, and the two readouts.
class _Protocol extends StatelessWidget {
  const _Protocol({required this.t, required this.maxW, required this.size});

  final double t;
  final double maxW;
  final Size size;

  static double _ramp(double t, double a, double b) =>
      Curves.easeInOutCubic.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  static double _win(double t, double a, double b, [double f = 0.04]) =>
      ((t - a) / f).clamp(0.0, 1.0) * ((b - t) / f).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final down = _ramp(t, 0.04, 0.28);
    final up = _ramp(t, 0.60, 0.84);
    final yDown = lerpDouble(_railTop, _railBottom, down)!;
    final yUp = lerpDouble(_railBottom, _railTop, up)!;
    final layoutCall = _win(t, 0.36, 0.60);
    final paraCall = _win(t, 0.42, 0.54);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: CustomPaint(painter: _ProtocolPainter(t: t, size: size))),
        Positioned(
          left: _upX + 22,
          top: yDown - 13,
          child: Opacity(
            opacity: _win(t, 0.03, 0.50),
            child: BpTag('BoxConstraints(0 ≤ w ≤ ${maxW.round()})', color: BP.amber, size: 13),
          ),
        ),
        Positioned(
          left: _upX + 22,
          top: yUp - 13,
          child: Opacity(
            opacity: _win(t, 0.58, 0.97),
            child: BpTag(
              'Size(${size.width.toStringAsFixed(1)} × ${size.height.toStringAsFixed(1)})',
              color: BP.green,
              size: 13,
            ),
          ),
        ),
        Positioned(
          left: _nodeX + _nodeW + 18,
          top: _nodeTop(3) + 26,
          child: Opacity(
            opacity: layoutCall,
            child: Text('layout(minWidth: 0, maxWidth: ${maxW.round()})', style: BT.mono(13, color: BP.amber)),
          ),
        ),
        Positioned(
          left: _nodeX + _nodeW + 18,
          top: _nodeTop(4) + 26,
          child: Opacity(
            opacity: paraCall,
            child: Text(
              'layout(ParagraphConstraints(width: ${maxW.round()}))',
              style: BT.mono(12, color: BP.amber),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProtocolPainter extends CustomPainter {
  _ProtocolPainter({required this.t, required this.size});

  final double t;
  final Size size;

  @override
  void paint(Canvas canvas, Size _) {
    final win = _Protocol._win;
    final ramp = _Protocol._ramp;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    void glow(Rect r, Color c, double g) {
      if (g <= 0) return;
      canvas.drawRect(r, Paint()..color = c.withValues(alpha: 0.10 * g));
      canvas.drawRect(r, stroke..color = c.withValues(alpha: g));
    }

    // Layout delegates down the chain: RenderParagraph → TextPainter → Paragraph.
    for (final (i, a, b) in const [(2, 0.28, 0.68), (3, 0.36, 0.62), (4, 0.42, 0.56)]) {
      glow(Rect.fromLTWH(_nodeX, _nodeTop(i), _nodeW, _nodeH).inflate(4), BP.amber, win(t, a, b));
    }
    // The real box lights while it lays out; the parent when the size lands.
    glow(Rect.fromLTWH(_rightX, _boxTop, size.width, size.height).inflate(4), BP.amber, win(t, 0.28, 0.62));
    glow(Rect.fromLTWH(_rightX, 0, _parentW, _parentH).inflate(3), BP.amber, win(t, 0.02, 0.10));
    glow(Rect.fromLTWH(_rightX, 0, _parentW, _parentH).inflate(3), BP.green, win(t, 0.83, 0.98));

    // Call dot running down owns/builds, result dot running back up.
    final top = _nodeTop(2) + _nodeH;
    final bottom = _nodeTop(4);
    if (t > 0.32 && t < 0.46) {
      final y = lerpDouble(top, bottom, ramp(t, 0.32, 0.45))!;
      canvas.drawCircle(Offset(_nodeCx, y), 5, Paint()..color = BP.amber);
    }
    if (t > 0.52 && t < 0.64) {
      final y = lerpDouble(bottom, top, ramp(t, 0.52, 0.63))!;
      canvas.drawCircle(Offset(_nodeCx, y), 5, Paint()..color = BP.green);
    }

    // Packets on the rails.
    void diamond(Offset c, Color color) {
      final d = Path()
        ..moveTo(c.dx, c.dy - 8)
        ..lineTo(c.dx + 8, c.dy)
        ..lineTo(c.dx, c.dy + 8)
        ..lineTo(c.dx - 8, c.dy)
        ..close();
      canvas.drawPath(d, Paint()..color = color);
    }

    if (t > 0.03 && t < 0.34) {
      diamond(Offset(_downX, lerpDouble(_railTop, _railBottom, ramp(t, 0.04, 0.28))!), BP.amber);
    }
    if (t > 0.58 && t < 0.88) {
      diamond(Offset(_upX, lerpDouble(_railBottom, _railTop, ramp(t, 0.60, 0.84))!), BP.green);
    }
  }

  @override
  bool shouldRepaint(_ProtocolPainter old) => old.t != t || old.size != size;
}

/// ⊕ (not in the bundled fonts, so drawn).
class _OPlusPainter extends CustomPainter {
  const _OPlusPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = BP.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 0.5;
    canvas.drawCircle(c, r, p);
    canvas.drawLine(c - Offset(r, 0), c + Offset(r, 0), p);
    canvas.drawLine(c - Offset(0, r), c + Offset(0, r), p);
  }

  @override
  bool shouldRepaint(_OPlusPainter old) => false;
}

class _RailsPainter extends CustomPainter {
  const _RailsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final down = Paint()
      ..color = BP.amber.withValues(alpha: 0.45)
      ..strokeWidth = 1.5;
    final up = Paint()
      ..color = BP.green.withValues(alpha: 0.45)
      ..strokeWidth = 1.5;
    drawArrow(canvas, const Offset(_downX, _railTop), const Offset(_downX, _railBottom), down, head: 7);
    drawArrow(canvas, const Offset(_upX, _railBottom), const Offset(_upX, _railTop), up, head: 7);
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
        dash: 5,
        gap: 5,
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_VDashPainter old) => old.color != color;
}
