import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../deck/theme.dart';
import '../../../deck/widgets.dart';
import '../../../slides/journey/journey.dart';
import 'frame.dart';

/// Stop 4: the shaped word is wrapped at a width. A real ui.Paragraph is
/// re-laid out on every drag of the box's right edge: real line breaks, real
/// LineMetrics. It is shaped once and wrapped many times.
class JLayoutSlide extends StatelessWidget {
  const JLayoutSlide({super.key});

  @override
  Widget build(BuildContext context) => SJourneyFrame(
    stop: 3,
    title: (_) => 'Lay out',
    builder: (context, d) => _Layout(data: d),
  );
}

// Stage geometry (content-area coordinates, 1472 × 628).
const _stageW = 1010.0;
const _stageH = 628.0;
const _origin = Offset(270, 118);
const _maxW = 720.0;
const _maxH = 452.0;
const _colX = 1072.0;
const _colW = 400.0;

/// Narrowest box, as a fraction of the word's one-line width.
const _minFraction = 0.45;

/// The sweep on arrival: full width → narrowest two-line box → rest wrapped.
const _sweepDelay = Duration(milliseconds: 500);
const _sweepTime = Duration(milliseconds: 2900);

class _Layout extends StatefulWidget {
  const _Layout({required this.data});

  final JourneyData data;

  @override
  State<_Layout> createState() => _LayoutState();
}

class _LayoutState extends State<_Layout> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(vsync: this, duration: _sweepTime)
    ..addListener(_onSweep);

  late double _fs;
  late double _minW;
  late double _restW;
  late double _w;
  late ui.Paragraph _p;
  double _sweepFrom = 0;
  TextAlign _align = TextAlign.left;
  int _wraps = 0;
  int _focus = 0;
  bool _nearHandle = false;
  bool _dragging = false;

  TextDirection get _dir => widget.data.rtl ? TextDirection.rtl : TextDirection.ltr;

  ui.Paragraph _build(double fs, TextAlign align) {
    final style = journeyStyle(fs);
    final b = ui.ParagraphBuilder(style.getParagraphStyle(textAlign: align, textDirection: _dir))
      ..pushStyle(style.getTextStyle())
      ..addText(widget.data.text);
    return b.build();
  }

  /// On a throwaway paragraph at [fs]: the one-line width, the narrowest box
  /// that still wraps into at most two lines, and the height there.
  (double, double, double) _measure(double fs) {
    final p = _build(fs, TextAlign.left)..layout(const ui.ParagraphConstraints(width: double.infinity));
    final wordW = p.maxIntrinsicWidth;
    int lines(double w) {
      p.layout(ui.ParagraphConstraints(width: w));
      return p.computeLineMetrics().length;
    }

    var lo = math.max(16.0, wordW * _minFraction);
    var hi = wordW.ceilToDouble();
    if (lines(lo) <= 2) {
      hi = lo;
    } else {
      while (hi - lo > 1) {
        final mid = (lo + hi) / 2;
        if (lines(mid) <= 2) {
          hi = mid;
        } else {
          lo = mid;
        }
      }
    }
    final minW = hi.ceilToDouble();
    p.layout(ui.ParagraphConstraints(width: minW));
    final h = p.height;
    p.dispose();
    return (wordW, minW, h);
  }

  @override
  void initState() {
    super.initState();
    const base = 240.0;
    final (w0, _, h0) = _measure(base);
    final fit = math.min(1.0, math.min(_maxH / math.max(h0, 1), (_maxW - 120) / math.max(w0, 1)));
    var fs = (base * fit).floorToDouble();
    var (wordW, minW, h) = _measure(fs);
    // Scaling can change where the greedy breaker splits; make sure it fits.
    while (fs > 24 && (h > _maxH || wordW > _maxW - 120)) {
      fs -= 4;
      (wordW, minW, h) = _measure(fs);
    }
    _fs = fs;
    _minW = minW;
    // Where the sweep comes to rest: still wrapped, with some air in the box.
    _restW = wordW - 1 <= _minW
        ? _minW
        : math.min(wordW - 1, _minW + (wordW - _minW) * 0.4).roundToDouble();
    _w = math.min(_maxW, wordW + 140).roundToDouble();
    // The real paragraph: built (and shaped) once, laid out many times.
    _p = _build(_fs, _align)..layout(ui.ParagraphConstraints(width: _w));
    _wraps = 1;
    Future<void>.delayed(_sweepDelay, () {
      if (mounted && !_dragging) _startSweep();
    });
  }

  @override
  void dispose() {
    _sweep.dispose();
    _p.dispose();
    super.dispose();
  }

  void _setWidth(double w) {
    final nw = w.clamp(_minW, _maxW).roundToDouble();
    if (nw == _w) return;
    setState(() {
      _w = nw;
      _p.layout(ui.ParagraphConstraints(width: _w));
      _wraps++;
    });
  }

  void _setAlign(TextAlign a) {
    if (a == _align) return;
    // A new ParagraphStyle means a new ui.Paragraph: its own shape + wrap.
    setState(() {
      _align = a;
      _p.dispose();
      _p = _build(_fs, _align)..layout(ui.ParagraphConstraints(width: _w));
      _wraps = 1;
    });
  }

  /// Down to the narrowest box, then back out to the resting width.
  void _onSweep() {
    final t = _sweep.value;
    const split = 0.58;
    final w = t < split
        ? ui.lerpDouble(_sweepFrom, _minW, Curves.easeInOutCubic.transform(t / split))!
        : ui.lerpDouble(_minW, _restW, Curves.easeInOutCubic.transform((t - split) / (1 - split)))!;
    _setWidth(w);
  }

  void _startSweep() {
    _sweepFrom = _w <= _restW + 40 ? _maxW : _w;
    _sweep.forward(from: 0);
  }

  void _onHover(Offset pos, List<ui.LineMetrics> lines) {
    final hx = _origin.dx + _w;
    final bottom = _origin.dy + math.max(_p.height, 80) + 40;
    final near = (pos.dx - hx).abs() < 28 && pos.dy > _origin.dy - 56 && pos.dy < bottom;
    var focus = _focus;
    for (final l in lines) {
      final top = _origin.dy + l.baseline - l.ascent;
      final bot = _origin.dy + l.baseline + l.descent;
      if (pos.dy >= top && pos.dy < bot) focus = l.lineNumber;
    }
    if (near != _nearHandle || focus != _focus) {
      setState(() {
        _nearHandle = near;
        _focus = focus;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = _p.computeLineMetrics();
    final f = lines.isEmpty ? 0 : _focus.clamp(0, lines.length - 1);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The paragraph box: drag anywhere to move its right edge;
        // double-tap to replay the sweep.
        Positioned(
          left: 0,
          top: 0,
          width: _stageW,
          height: _stageH,
          child: MouseRegion(
            cursor: _nearHandle || _dragging ? SystemMouseCursors.resizeLeftRight : MouseCursor.defer,
            onHover: (e) => _onHover(e.localPosition, lines),
            onExit: (_) => setState(() => _nearHandle = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: _startSweep,
              onPanStart: (e) {
                _sweep.stop();
                setState(() => _dragging = true);
                _setWidth(e.localPosition.dx - _origin.dx);
              },
              onPanUpdate: (e) => _setWidth(e.localPosition.dx - _origin.dx),
              onPanEnd: (_) => setState(() => _dragging = false),
              onPanCancel: () => setState(() => _dragging = false),
              child: CustomPaint(
                size: const Size(_stageW, _stageH),
                painter: _StagePainter(
                  paragraph: _p,
                  lines: lines,
                  width: _w,
                  focus: f,
                  hot: _nearHandle || _dragging,
                ),
              ),
            ),
          ),
        ),
        // Align
        Positioned(
          left: _origin.dx,
          top: 0,
          child: BpSegmented<TextAlign>(
            values: const [TextAlign.left, TextAlign.center, TextAlign.right],
            selected: _align,
            onChanged: _setAlign,
            labelOf: (a) => a.name,
            size: 20,
            spacing: 10,
          ),
        ),
        // The size that travels back up, and shape-once / wrap-many.
        Positioned(
          left: _colX,
          top: _origin.dy - 10,
          width: _colW,
          child: _Readout(width: _w, height: _p.height, lines: lines.length, wraps: _wraps),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stage: paragraph box, line guides, width handle
// ─────────────────────────────────────────────────────────────────────────────

class _StagePainter extends CustomPainter {
  _StagePainter({
    required this.paragraph,
    required this.lines,
    required this.width,
    required this.focus,
    required this.hot,
  });

  final ui.Paragraph paragraph;
  final List<ui.LineMetrics> lines;
  final double width;
  final int focus;
  final bool hot;

  static Paint _stroke(Color c, [double w = 1]) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w;

  static Path _h(double x0, double x1, double y) => Path()
    ..moveTo(x0, y)
    ..lineTo(x1, y);

  @override
  void paint(Canvas canvas, Size size) {
    const o = _origin;
    final h = math.max(paragraph.height, 1.0);
    final box = Rect.fromLTWH(o.dx, o.dy, width, h);

    // Paragraph box (the constraint).
    canvas.drawRect(box, Paint()..color = BP.panel.withValues(alpha: 0.7));
    canvas.drawPath(dashPath(Path()..addRect(box), dash: 6, gap: 5), _stroke(BP.lineDim, 1.4));

    var overflow = false;
    for (final l in lines) {
      final isF = l.lineNumber == focus;
      final top = o.dy + l.baseline - l.ascent;
      final base = o.dy + l.baseline;
      final bottom = o.dy + l.baseline + l.descent;
      final lx = o.dx + l.left;
      final lb = Rect.fromLTRB(lx, top, lx + l.width, bottom);

      canvas.drawRect(lb, Paint()..color = BP.line.withValues(alpha: isF ? 0.09 : 0.04));

      // Overflow: glyphs that don't fit (a single cluster can't be split).
      final outL = l.left < -0.5;
      final outR = l.left + l.width > width + 0.5;
      if (outL || outR) {
        overflow = true;
        final red = Paint()..color = BP.red.withValues(alpha: 0.18);
        if (outL) canvas.drawRect(Rect.fromLTRB(lx, top, o.dx, bottom), red);
        if (outR) canvas.drawRect(Rect.fromLTRB(o.dx + width, top, lx + l.width, bottom), red);
      }

      // Ascent / descent (dashed), across the box.
      final dash = _stroke(isF ? BP.line : BP.lineDim, 1.4);
      canvas.drawPath(dashPath(_h(o.dx - 12, o.dx + width, top), dash: 8, gap: 6), dash);
      canvas.drawPath(dashPath(_h(o.dx - 12, o.dx + width, bottom), dash: 8, gap: 6), dash);

      // Line box
      canvas.drawRect(lb, _stroke(isF ? BP.line : BP.lineDim, isF ? 2 : 1.4));

      // Baseline (solid amber)
      canvas.drawLine(
        Offset(o.dx - 14, base),
        Offset(o.dx + width + 14, base),
        Paint()
          ..color = BP.amber.withValues(alpha: isF ? 1 : 0.6)
          ..strokeWidth = isF ? 2.4 : 1.6,
      );
    }

    // The real paragraph.
    canvas.drawParagraph(paragraph, o);

    // The focused line's metric names in the gutter.
    if (lines.isNotEmpty) {
      final l = lines[focus.clamp(0, lines.length - 1)];
      final top = o.dy + l.baseline - l.ascent;
      final base = o.dy + l.baseline;
      final bottom = o.dy + l.baseline + l.descent;
      final gx = o.dx - 26;
      _label(canvas, 'ascent', Offset(gx, top), color: BP.line, ax: 1);
      _label(canvas, 'baseline', Offset(gx, base), color: BP.amber, ax: 1);
      _label(canvas, 'descent', Offset(gx, bottom), color: BP.line, ax: 1);
    }

    if (overflow) {
      _label(canvas, 'overflow', Offset(o.dx + width + 40, o.dy + h + 30), color: BP.red);
    }

    // maxWidth: a dimension line over the box…
    final hx = o.dx + width;
    final dy = o.dy - 34;
    final amber = _stroke(BP.amber, 2);
    canvas.drawLine(Offset(o.dx, dy), Offset(hx, dy), amber);
    canvas.drawLine(Offset(o.dx, dy - 10), Offset(o.dx, dy + 10), amber);
    drawArrowHead(canvas, Offset(o.dx, dy), Offset(o.dx + 10, dy), amber, 9);
    drawArrowHead(canvas, Offset(hx, dy), Offset(hx - 10, dy), amber, 9);
    _label(canvas, 'maxWidth', Offset(o.dx + width / 2, dy), color: BP.amber, ax: 0.5, size: 20, bg: true);

    // …and its right edge, the handle you drag.
    final edgeBottom = o.dy + math.max(h, 60) + 30;
    canvas.drawLine(
      Offset(hx, dy),
      Offset(hx, edgeBottom),
      _stroke(BP.amber.withValues(alpha: hot ? 1 : 0.85), hot ? 3 : 2.2),
    );
    final gy = o.dy + math.max(h, 60) / 2;
    final grip = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(hx, gy), width: 22, height: 84),
      const Radius.circular(5),
    );
    canvas.drawRRect(grip.inflate(hot ? 10 : 6), Paint()..color = BP.amber.withValues(alpha: hot ? 0.28 : 0.14));
    canvas.drawRRect(grip, Paint()..color = BP.paper);
    canvas.drawRRect(grip, _stroke(BP.amber, 2.6));
    for (final k in [-12.0, 0.0, 12.0]) {
      canvas.drawLine(Offset(hx - 5, gy + k), Offset(hx + 5, gy + k), _stroke(BP.amber, 2));
    }
    // ◀ ▶ : it moves sideways.
    final fill = Paint()..color = BP.amber.withValues(alpha: hot ? 1 : 0.85);
    for (final s in [-1.0, 1.0]) {
      final tip = Offset(hx + s * 34, gy);
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(tip.dx - s * 12, tip.dy - 10)
          ..lineTo(tip.dx - s * 12, tip.dy + 10)
          ..close(),
        fill,
      );
    }
  }

  void _label(
    Canvas c,
    String s,
    Offset at, {
    Color color = BP.inkDim,
    double size = 18,
    double ax = 0,
    bool bg = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: BT.mono(size, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    final p = at - Offset(tp.width * ax, tp.height / 2);
    if (bg) c.drawRect((p & tp.size).inflate(6), Paint()..color = BP.paper);
    tp.paint(c, p);
    tp.dispose();
  }

  @override
  bool shouldRepaint(_StagePainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Right column: the size that comes back up, and shape once → wrap many
// ─────────────────────────────────────────────────────────────────────────────

class _Readout extends StatelessWidget {
  const _Readout({required this.width, required this.height, required this.lines, required this.wraps});

  final double width;
  final double height;
  final int lines;
  final int wraps;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value, Color color) => Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: BP.lineFaint)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(label, style: BT.mono(22, color: BP.inkDim)),
          const Spacer(),
          Text(value, style: BT.display(64, color: color, weight: 400, height: 1.1)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        stat('width', width.round().toString(), BP.amber),
        stat('height', height.round().toString(), BP.ink),
        stat('lines', '$lines', BP.ink),
        const SizedBox(height: 48),
        Row(
          children: [
            const _Counter(label: 'shape', value: 1, color: BP.green),
            Expanded(
              child: SizedBox(
                height: 24,
                child: DrawOn(
                  arrow: true,
                  strokeWidth: 2,
                  color: BP.inkDim,
                  delay: const Duration(milliseconds: 300),
                  path: (s) => Path()
                    ..moveTo(12, s.height / 2)
                    ..lineTo(s.width - 12, s.height / 2),
                ),
              ),
            ),
            _Counter(label: 'wrap', value: wraps, color: BP.amber),
          ],
        ),
      ],
    );
  }
}

/// A counter that flashes when its value changes.
class _Counter extends StatefulWidget {
  const _Counter({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(_Counter old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _flash.forward(from: 0);
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _flash,
    builder: (context, _) {
      final k = _flash.isAnimating ? 1 - _flash.value : 0.0;
      final c = widget.color;
      return Container(
        width: 156,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.06 + 0.2 * k),
          border: Border.all(color: Color.lerp(c.withValues(alpha: 0.7), c, k)!, width: 1.5 + k),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.label, style: BT.mono(22, color: c)),
            Text('×${widget.value}', style: BT.display(56, color: c, weight: 400, height: 1.15)),
          ],
        ),
      );
    },
  );
}
