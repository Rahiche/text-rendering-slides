import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'journey.dart';

/// Stop 7: the shaped word is wrapped and formatted at a width. A real
/// ui.Paragraph is re-laid out on every drag of the box's right edge: real
/// line breaks, real LineMetrics, and the size travels back up.
class JLayoutSlide extends StatelessWidget {
  const JLayoutSlide({super.key});

  @override
  Widget build(BuildContext context) => JourneyFrame(
    stop: 7,
    title: (_) => 'Lay out',
    builder: (context, d) => _Layout(data: d),
  );
}

// Stage geometry (content-area coordinates).
const _stageW = 960.0;
const _stageH = 628.0;
const _origin = Offset(118, 118);
const _maxW = 800.0;
const _maxH = 460.0;
const _colX = 1000.0;
const _colW = 472.0;

/// Narrowest box, as a fraction of the word's one-line width.
const _minFraction = 0.45;

String _f1(double v) => v.toStringAsFixed(1);

class _Layout extends StatefulWidget {
  const _Layout({required this.data});

  final JourneyData data;

  @override
  State<_Layout> createState() => _LayoutState();
}

class _LayoutState extends State<_Layout> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  )..addListener(_onSweep);

  late double _fs;
  late double _minW;
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

  /// One-line width and the height at the narrowest box, on a throwaway paragraph.
  (double, double) _measure(double fs) {
    final p = _build(fs, TextAlign.left)..layout(const ui.ParagraphConstraints(width: double.infinity));
    final wordW = p.maxIntrinsicWidth;
    p.layout(ui.ParagraphConstraints(width: math.max(16, wordW * _minFraction)));
    final h = p.height;
    p.dispose();
    return (wordW, h);
  }

  @override
  void initState() {
    super.initState();
    const base = 120.0;
    final (w0, h0) = _measure(base);
    final fit = math.min(1.0, math.min(_maxH / math.max(h0, 1), _maxW * 0.6 / math.max(w0, 1)));
    var fs = (base * fit).floorToDouble();
    // Scaling can change where the greedy breaker splits; make sure it fits.
    while (fs > 24 && _measure(fs).$2 > _maxH) {
      fs -= 4;
    }
    _fs = fs;
    final wordW = _measure(_fs).$1;
    _minW = math.max(16.0, (wordW * _minFraction).roundToDouble());
    _w = math.min(_maxW, math.max(wordW + 180, wordW * 1.5)).roundToDouble();
    // The real paragraph: built (and shaped) once, laid out many times.
    _p = _build(_fs, _align)..layout(ui.ParagraphConstraints(width: _w));
    _wraps = 1;
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
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

  void _onSweep() {
    final t = _sweep.value;
    final k = Curves.easeInOutCubic.transform(t < 0.5 ? t * 2 : 2 - t * 2);
    _setWidth(ui.lerpDouble(_sweepFrom, _minW, k)!);
  }

  void _startSweep() {
    _sweepFrom = _w;
    _sweep.forward(from: 0);
  }

  void _onHover(Offset pos, List<ui.LineMetrics> lines) {
    final hx = _origin.dx + _w;
    final bottom = _origin.dy + math.max(_p.height, 80) + 40;
    final near = (pos.dx - hx).abs() < 22 && pos.dy > _origin.dy - 56 && pos.dy < bottom;
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
        // The paragraph box: drag anywhere to move its right edge.
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
        // Controls
        Positioned(
          left: _origin.dx,
          top: 0,
          child: Row(
            children: [
              BpSegmented<TextAlign>(
                values: const [TextAlign.left, TextAlign.center, TextAlign.right],
                selected: _align,
                onChanged: _setAlign,
                labelOf: (a) => a.name,
                size: 14,
              ),
              const SizedBox(width: 24),
              BpButton(label: 'sweep', icon: Icons.swap_horiz, size: 14, onTap: _startSweep),
            ],
          ),
        ),
        // Size travels back up; shaping stays cached.
        Positioned(
          left: _colX,
          top: 0,
          width: _colW,
          height: _stageH,
          child: _Chain(
            width: _w,
            height: _p.height,
            longest: _p.longestLine,
            lines: lines,
            focus: f,
            wraps: _wraps,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stage: paragraph box, line boxes, metrics, handle
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
    canvas.drawPath(dashPath(Path()..addRect(box), dash: 5, gap: 4), _stroke(BP.lineDim));

    var overflow = false;
    for (final l in lines) {
      final isF = l.lineNumber == focus;
      final top = o.dy + l.baseline - l.ascent;
      final base = o.dy + l.baseline;
      final bottom = o.dy + l.baseline + l.descent;
      final lx = o.dx + l.left;
      final lb = Rect.fromLTRB(lx, top, lx + l.width, bottom);

      canvas.drawRect(lb, Paint()..color = BP.line.withValues(alpha: isF ? 0.08 : 0.03));

      // Overflow: glyphs that don't fit (a single cluster can't be split).
      final outL = l.left < -0.5;
      final outR = l.left + l.width > width + 0.5;
      if (outL || outR) {
        overflow = true;
        final red = Paint()..color = BP.red.withValues(alpha: 0.16);
        if (outL) canvas.drawRect(Rect.fromLTRB(lx, top, o.dx, bottom), red);
        if (outR) canvas.drawRect(Rect.fromLTRB(o.dx + width, top, lx + l.width, bottom), red);
      }

      // Ascent / descent (dashed), across the box.
      final dash = _stroke(isF ? BP.line : BP.lineDim);
      canvas.drawPath(dashPath(_h(o.dx, o.dx + width, top), dash: 6, gap: 5), dash);
      canvas.drawPath(dashPath(_h(o.dx, o.dx + width, bottom), dash: 6, gap: 5), dash);

      // Line box
      canvas.drawRect(lb, _stroke(isF ? BP.line : BP.lineDim, isF ? 1.5 : 1));

      // Baseline (solid amber)
      canvas.drawLine(
        Offset(o.dx - 10, base),
        Offset(o.dx + width + 10, base),
        Paint()
          ..color = BP.amber.withValues(alpha: isF ? 1 : 0.5)
          ..strokeWidth = isF ? 1.6 : 1.1,
      );

      // line.left: from the box edge to where the line starts.
      if (l.left.abs() > 0.5) {
        final y = top + (base - top) * 0.45;
        final p = _stroke(BP.violet.withValues(alpha: isF ? 1 : 0.5), 1.2);
        canvas.drawPath(dashPath(_h(o.dx, lx, y), dash: 4, gap: 3), p);
        drawArrowHead(canvas, Offset(lx, y), Offset(o.dx, y), p, 7);
        canvas.drawLine(Offset(lx, y - 7), Offset(lx, y + 7), p);
        if (isF) {
          _label(canvas, 'left ${_f1(l.left)}', Offset((o.dx + lx) / 2, y - 12), color: BP.violet, ax: 0.5, bg: true);
        }
      }
    }

    // The real paragraph.
    canvas.drawParagraph(paragraph, o);

    // Focused line: its width, and the metric names in the gutter.
    if (lines.isNotEmpty) {
      final l = lines[focus.clamp(0, lines.length - 1)];
      final top = o.dy + l.baseline - l.ascent;
      final base = o.dy + l.baseline;
      final bottom = o.dy + l.baseline + l.descent;
      final lx = o.dx + l.left;
      final y = top + 11;
      final p = _stroke(BP.line, 1.1);
      canvas.drawLine(Offset(lx, y), Offset(lx + l.width, y), p);
      canvas.drawLine(Offset(lx, y - 6), Offset(lx, y + 6), p);
      canvas.drawLine(Offset(lx + l.width, y - 6), Offset(lx + l.width, y + 6), p);
      drawArrowHead(canvas, Offset(lx, y), Offset(lx + 10, y), p, 5);
      drawArrowHead(canvas, Offset(lx + l.width, y), Offset(lx + l.width - 10, y), p, 5);
      _label(canvas, 'width ${_f1(l.width)}', Offset(lx + l.width / 2, y), color: BP.line, ax: 0.5, bg: true);

      final gx = o.dx - 16;
      _label(canvas, 'ascent', Offset(gx, top), color: BP.line, ax: 1);
      _label(canvas, 'baseline', Offset(gx, base), color: BP.amber, ax: 1);
      _label(canvas, 'descent', Offset(gx, bottom), color: BP.line, ax: 1);
    }

    if (overflow) {
      _label(canvas, 'overflow', Offset(o.dx + width + 14, o.dy + h + 18), color: BP.red);
    }

    // maxWidth: dimension line + draggable edge.
    final hx = o.dx + width;
    final dy = o.dy - 34;
    final amber = _stroke(BP.amber, 1.2);
    canvas.drawLine(Offset(o.dx, dy), Offset(hx, dy), amber);
    canvas.drawLine(Offset(o.dx, dy - 7), Offset(o.dx, dy + 7), amber);
    drawArrowHead(canvas, Offset(o.dx, dy), Offset(o.dx + 10, dy), amber, 6);
    drawArrowHead(canvas, Offset(hx, dy), Offset(hx - 10, dy), amber, 6);
    _label(canvas, 'maxWidth ${_f1(width)}', Offset(o.dx + width / 2, dy - 13), color: BP.amber, ax: 0.5, size: 13, bg: true);

    final edgeBottom = o.dy + math.max(h, 60) + 26;
    canvas.drawPath(
      dashPath(Path()
        ..moveTo(hx, dy)
        ..lineTo(hx, edgeBottom), dash: 6, gap: 4),
      _stroke(BP.amber.withValues(alpha: hot ? 1 : 0.8), hot ? 2 : 1.4),
    );
    // Grip
    final gy = o.dy + math.max(h, 60) / 2;
    final grip = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(hx, gy), width: 12, height: 44), const Radius.circular(3));
    if (hot) {
      canvas.drawRRect(grip.inflate(6), Paint()..color = BP.amber.withValues(alpha: 0.18));
    }
    canvas.drawRRect(grip, Paint()..color = BP.paper);
    canvas.drawRRect(grip, _stroke(BP.amber, 2));
    for (final k in [-6.0, 0.0, 6.0]) {
      canvas.drawLine(Offset(hx - 3, gy + k), Offset(hx + 3, gy + k), _stroke(BP.amber, 1.2));
    }
  }

  void _label(
    Canvas c,
    String s,
    Offset at, {
    Color color = BP.inkDim,
    double size = 12,
    double ax = 0,
    bool bg = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: BT.mono(size, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    final p = at - Offset(tp.width * ax, tp.height / 2);
    if (bg) c.drawRect((p & tp.size).inflate(3), Paint()..color = BP.paper);
    tp.paint(c, p);
    tp.dispose();
  }

  @override
  bool shouldRepaint(_StagePainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Right column: constraints down, size up, shape vs wrap counters
// ─────────────────────────────────────────────────────────────────────────────

const _aTop = 0.0;
const _aH = 56.0;
const _bTop = 110.0;
const _bH = 44.0;
const _cTop = 208.0;
const _cH = 196.0;
const _dTop = 436.0;
const _downX = 250.0;
const _upX = 392.0;

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

class _Chain extends StatelessWidget {
  const _Chain({
    required this.width,
    required this.height,
    required this.longest,
    required this.lines,
    required this.focus,
    required this.wraps,
  });

  final double width;
  final double height;
  final double longest;
  final List<ui.LineMetrics> lines;
  final int focus;
  final int wraps;

  @override
  Widget build(BuildContext context) {
    final size = 'Size(${_f1(width)}, ${_f1(height)})';
    final line = lines.isEmpty ? null : lines[focus];
    final chain = LoopBuilder(
      period: const Duration(milliseconds: 3600),
      builder: (context, t, _) {
        final down = Curves.easeInOutCubic.transform(_seg(t, 0.02, 0.36));
        final up = Curves.easeInOutCubic.transform(_seg(t, 0.48, 0.86));
        final showDown = t > 0.02 && t < 0.38;
        final showUp = t > 0.48 && t < 0.88;
        final hitB = (t > 0.17 && t < 0.24) || (t > 0.64 && t < 0.72);
        final hitC = t >= 0.36 && t < 0.5;
        final hitA = t >= 0.86;
        final downY = ui.lerpDouble(_aTop + _aH, _cTop, down)!;
        final upY = ui.lerpDouble(_cTop, _aTop + _aH, up)!;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: CustomPaint(painter: _TrackPainter())),
            Positioned(
              left: 0,
              top: _aTop,
              width: _colW,
              height: _aH,
              child: _Chip(name: 'RenderParagraph', sub: '.size', value: size, hot: hitA),
            ),
            Positioned(
              left: 0,
              top: _bTop,
              width: _colW,
              height: _bH,
              child: _Chip(name: 'TextPainter', sub: '.layout()', hot: hitB),
            ),
            Positioned(
              left: 0,
              top: _cTop,
              width: _colW,
              height: _cH,
              child: BpPanel(
                label: 'ui.Paragraph',
                color: hitC ? BP.amber : BP.lineDim,
                padding: const EdgeInsets.fromLTRB(20, 24, 16, 12),
                child: _Readouts(width: width, height: height, longest: longest, lines: lines.length, line: line, index: focus),
              ),
            ),
            // Track labels
            Positioned(
              left: _downX - 12,
              top: _aTop + _aH + 12,
              child: FractionalTranslation(
                translation: const Offset(-1, 0),
                child: Text('constraints', style: BT.mono(12, color: BP.line)),
              ),
            ),
            Positioned(
              left: _upX + 12,
              top: _bTop + _bH + 16,
              child: Text('size', style: BT.mono(12, color: BP.amber)),
            ),
            if (showDown)
              Positioned(
                left: _downX,
                top: downY,
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: _Packet(text: 'maxWidth ${_f1(width)}', color: BP.line),
                ),
              ),
            if (showUp)
              Positioned(
                left: _upX,
                top: upY,
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: _Packet(text: size, color: BP.amber),
                ),
              ),
          ],
        );
      },
    );
    // The counters live outside the per-frame loop so their state is stable.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: chain),
        Positioned(
          left: 0,
          top: _dTop,
          width: _colW,
          height: _stageH - _dTop,
          child: BpPanel(
            label: 'shaped once · wrapped many',
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
            child: Row(
              children: [
                const _Counter(label: 'shape', value: 1, color: BP.green, sub: 'HarfBuzz'),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('glyph runs', style: BT.mono(12, color: BP.inkDim)),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 16,
                        child: DrawOn(
                          arrow: true,
                          dashed: true,
                          color: BP.inkDim,
                          path: (s) => Path()
                            ..moveTo(6, s.height / 2)
                            ..lineTo(s.width - 6, s.height / 2),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('cached', style: BT.mono(12, color: BP.green)),
                    ],
                  ),
                ),
                _Counter(label: 'wrap', value: wraps, color: BP.amber, sub: 'greedy'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TrackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final down = Paint()
      ..color = BP.line.withValues(alpha: 0.8)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final up = Paint()
      ..color = BP.amber.withValues(alpha: 0.8)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    // Constraints go down…
    drawArrow(canvas, const Offset(_downX, _aTop + _aH + 2), const Offset(_downX, _bTop - 3), down, dashed: true, head: 7);
    drawArrow(canvas, const Offset(_downX, _bTop + _bH + 2), const Offset(_downX, _cTop - 3), down, dashed: true, head: 7);
    // …size goes up.
    drawArrow(canvas, const Offset(_upX, _cTop - 2), const Offset(_upX, _bTop + _bH + 3), up, dashed: true, head: 7);
    drawArrow(canvas, const Offset(_upX, _bTop - 2), const Offset(_upX, _aTop + _aH + 3), up, dashed: true, head: 7);
  }

  @override
  bool shouldRepaint(_TrackPainter old) => false;
}

class _Chip extends StatelessWidget {
  const _Chip({required this.name, required this.sub, required this.hot, this.value});

  final String name;
  final String sub;
  final String? value;
  final bool hot;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: hot ? BP.amber.withValues(alpha: 0.12) : BP.panel,
      border: Border.all(color: hot ? BP.amber : BP.lineDim, width: hot ? 1.6 : 1),
    ),
    child: Row(
      children: [
        Text(name, style: BT.mono(16, color: BP.ink)),
        Text(sub, style: BT.mono(14, color: BP.inkDim)),
        const Spacer(),
        if (value != null) Text(value!, style: BT.mono(15, color: BP.amber)),
      ],
    ),
  );
}

class _Packet extends StatelessWidget {
  const _Packet({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: BP.paper,
      border: Border.all(color: color, width: 1.4),
    ),
    child: Text(text, style: BT.mono(13, color: color)),
  );
}

class _Readouts extends StatelessWidget {
  const _Readouts({
    required this.width,
    required this.height,
    required this.longest,
    required this.lines,
    required this.line,
    required this.index,
  });

  final double width;
  final double height;
  final double longest;
  final int lines;
  final ui.LineMetrics? line;
  final int index;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 9);
    final l = line;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 22),
              JField('width      ', _f1(width), color: BP.amber),
              gap,
              JField('height     ', _f1(height)),
              gap,
              JField('longestLine', _f1(longest), color: longest > width + 0.5 ? BP.red : BP.ink),
              gap,
              JField('lines      ', '$lines'),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('line[$index]', style: BT.mono(13, color: BP.inkFaint)),
              const SizedBox(height: 7),
              if (l != null) ...[
                JField('ascent  ', _f1(l.ascent), color: BP.line),
                gap,
                JField('descent ', _f1(l.descent), color: BP.line),
                gap,
                JField('baseline', _f1(l.baseline), color: BP.amber),
                gap,
                JField('left    ', _f1(l.left), color: BP.violet),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A counter that flashes when its value changes.
class _Counter extends StatefulWidget {
  const _Counter({required this.label, required this.value, required this.color, required this.sub});

  final String label;
  final int value;
  final Color color;
  final String sub;

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
        width: 150,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.05 + 0.2 * k),
          border: Border.all(color: Color.lerp(c.withValues(alpha: 0.6), c, k)!, width: 1 + k),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.label, style: BT.mono(14, color: c)),
            Text('${widget.value}', style: BT.display(50, color: c, weight: 400, height: 1.15)),
            Text(widget.sub, style: BT.mono(12, color: BP.inkFaint)),
          ],
        ),
      );
    },
  );
}
