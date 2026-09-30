import 'package:flutter/material.dart';

import '../../deck/deck.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';

class _Engine {
  const _Engine(this.name, this.id, this.cells);

  final String name;
  final String id;
  final List<String> cells;
}

/// Pipeline order: find fonts → shape → lay out lines → rasterize.
const _rows = ['fonts', 'shaping', 'layout', 'raster'];

const _engines = [
  _Engine('Chrome', 'chrome', ['system + web', 'HarfBuzz', 'LayoutNG', 'Skia']),
  _Engine('Figma', 'figma', ['Noto fallback', 'HarfBuzz', 'own C++', 'WebGL / WebGPU']),
  _Engine('macOS', 'apple', ['system cascade', 'Core Text', 'TextKit 2', 'Core Graphics']),
  _Engine('Android', 'android', ['system fallback', 'HarfBuzz', 'Minikin', 'Skia']),
  _Engine('Flutter', 'j-map', ['FontCollection', 'HarfBuzz', 'SkParagraph', 'Impeller']),
];

const _labelW = 170.0;
const _colW = (1472 - _labelW) / 5;
const _headH = 88.0;
const _rowH = 106.0;
const _inset = 8.0;
const _shapingRow = 1;
const _gridBottom = _headH + 4 * _rowH;
const _busY = _headH + (_shapingRow + 1) * _rowH;
const _apple = 2;

bool _isHarfBuzz(int c, int r) => r == _shapingRow && _engines[c].cells[r] == 'HarfBuzz';

/// Five text stacks side by side. Step 1 fills the matrix column by column,
/// step 2 lights up the shaper four of them share.
class EnginesSlide extends StatefulWidget {
  const EnginesSlide({super.key});

  @override
  State<EnginesSlide> createState() => _EnginesSlideState();
}

class _EnginesSlideState extends State<EnginesSlide> {
  int? _hr;
  int? _hc;
  int _lastR = 0;
  int _lastC = 0;

  void _hover(int? r, int? c) => setState(() {
    _hr = r;
    _hc = c;
    if (r != null) _lastR = r;
    if (c != null) _lastC = c;
  });

  @override
  Widget build(BuildContext context) {
    final step = SlideScope.of(context).step;
    return SlideFrame(
      title: 'Five engines',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Hover bands (row / column)
          _Band(
            visible: _hr != null,
            vertical: false,
            rect: Rect.fromLTWH(0, _headH + _lastR * _rowH, 1472, _rowH),
          ),
          _Band(
            visible: _hc != null,
            vertical: true,
            rect: Rect.fromLTWH(_labelW + _lastC * _colW, 0, _colW, _gridBottom),
          ),

          // Construction grid
          Positioned.fill(
            child: IgnorePointer(
              child: DrawOn(
                duration: const Duration(milliseconds: 1400),
                color: BP.lineFaint,
                dashed: true,
                path: (_) => _gridPath(),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DrawOn(
                duration: const Duration(milliseconds: 900),
                color: BP.lineDim,
                path: (_) => Path()
                  ..moveTo(0, _headH)
                  ..lineTo(1472, _headH),
              ),
            ),
          ),

          // Pipeline rail with a packet running down the stages
          Positioned(
            left: 0,
            top: _headH,
            width: 18,
            height: 4 * _rowH,
            child: IgnorePointer(
              child: LoopBuilder(
                period: const Duration(milliseconds: 3600),
                builder: (context, t, _) => CustomPaint(painter: _RailPainter(t)),
              ),
            ),
          ),

          // Row labels
          for (var r = 0; r < _rows.length; r++)
            Positioned(
              left: 30,
              top: _headH + r * _rowH,
              width: _labelW - 36,
              height: _rowH,
              child: MouseRegion(
                onEnter: (_) => _hover(r, null),
                onExit: (_) => _hover(null, null),
                child: Reveal(
                  visible: true,
                  delay: Duration(milliseconds: 200 + r * 80),
                  offset: const Offset(-16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 160),
                      style: BT.mono(
                        24,
                        color: _hr == r || (r == _shapingRow && step >= 2) ? BP.amber : BP.inkDim,
                      ),
                      child: Text(_rows[r]),
                    ),
                  ),
                ),
              ),
            ),

          // Column headers (click → deep-dive slide, where there is one)
          for (var c = 0; c < _engines.length; c++)
            Positioned(
              left: _labelW + c * _colW,
              top: 0,
              width: _colW,
              height: _headH,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => _hover(null, c),
                onExit: (_) => _hover(null, null),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => DeckScope.read(context).goToId(_engines[c].id),
                  child: Reveal(
                    visible: true,
                    delay: Duration(milliseconds: 120 + c * 90),
                    child: _Header(name: _engines[c].name, hot: _hc == c),
                  ),
                ),
              ),
            ),

          // Cells
          for (var c = 0; c < _engines.length; c++)
            for (var r = 0; r < _rows.length; r++)
              Positioned(
                left: _labelW + c * _colW + _inset,
                top: _headH + r * _rowH + _inset,
                width: _colW - 2 * _inset,
                height: _rowH - 2 * _inset,
                child: MouseRegion(
                  onEnter: (_) => _hover(r, c),
                  onExit: (_) => _hover(null, null),
                  child: _Cell(
                    text: _engines[c].cells[r],
                    visible: step >= 1,
                    delay: Duration(milliseconds: c * 220 + r * 60),
                    glow: step >= 2 && _isHarfBuzz(c, r),
                    own: step >= 2 && c == _apple && r == _shapingRow,
                    hot: _hr == r || _hc == c,
                  ),
                ),
              ),

          // The shared-shaper bus
          Positioned.fill(
            child: IgnorePointer(child: _Bus(visible: step >= 2)),
          ),

          // The one takeaway.
          Positioned(
            left: _labelW,
            right: 0,
            top: _gridBottom + 28,
            child: StepReveal(
              at: 2,
              delay: const Duration(milliseconds: 500),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'HarfBuzz', style: BT.display(36, color: BP.amber, weight: 600)),
                    TextSpan(text: ' shapes text in 4 of 5', style: BT.display(36, color: BP.ink)),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Path _gridPath() {
    final p = Path();
    for (var r = 1; r <= _rows.length; r++) {
      final y = _headH + r * _rowH;
      p
        ..moveTo(0, y)
        ..lineTo(1472, y);
    }
    for (var c = 0; c <= _engines.length; c++) {
      final x = _labelW + c * _colW;
      p
        ..moveTo(x, 14)
        ..lineTo(x, _gridBottom);
    }
    return p;
  }
}

class _Band extends StatelessWidget {
  const _Band({required this.visible, required this.vertical, required this.rect});

  final bool visible;
  final bool vertical;
  final Rect rect;

  @override
  Widget build(BuildContext context) {
    const side = BorderSide(color: BP.amber, width: 2);
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: BP.line.withValues(alpha: 0.06),
              border: vertical ? const Border(top: side) : const Border(left: side),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.hot});

  final String name;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    final flutter = name == 'Flutter';
    return Padding(
      padding: const EdgeInsets.only(left: 14, bottom: 18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (flutter) ...[
                  Transform.rotate(
                    angle: 0.785398,
                    child: Container(width: 12, height: 12, color: BP.amber),
                  ),
                  const SizedBox(width: 14),
                ],
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 160),
                  style: BT.display(38, color: hot ? BP.amber : BP.ink, letterSpacing: -0.5),
                  child: Text(name),
                ),
                const SizedBox(width: 10),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: hot ? 1 : 0,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 200),
                    offset: hot ? Offset.zero : const Offset(-0.4, 0),
                    child: Text('→', style: BT.mono(28, color: BP.amber)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.text,
    required this.visible,
    required this.delay,
    required this.glow,
    required this.own,
    required this.hot,
  });

  final String text;
  final bool visible;
  final Duration delay;
  final bool glow;
  final bool own;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    final edge = glow
        ? BP.amber
        : own
        ? BP.violet
        : hot
        ? BP.line
        : BP.lineDim;
    return Stack(
      fit: StackFit.expand,
      children: [
        Reveal(
          visible: visible,
          delay: delay,
          offset: Offset.zero,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 450),
            decoration: BoxDecoration(
              // Opaque fills so the glow only shows around the cell, not through it.
              color: glow
                  ? Color.alphaBlend(BP.amber.withValues(alpha: 0.14), BP.panel)
                  : (hot ? Color.alphaBlend(BP.line.withValues(alpha: 0.06), BP.panel) : BP.panel),
              boxShadow: glow
                  ? [BoxShadow(color: BP.amber.withValues(alpha: 0.3), blurRadius: 24)]
                  : const [],
            ),
          ),
        ),
        IgnorePointer(
          child: DrawOn(
            visible: visible,
            delay: delay,
            duration: const Duration(milliseconds: 520),
            color: edge,
            strokeWidth: glow ? 2.5 : (own ? 2 : 1),
            dashed: own,
            path: (s) => Path()..addRect(Offset.zero & s),
          ),
        ),
        Reveal(
          visible: visible,
          delay: delay + const Duration(milliseconds: 220),
          offset: const Offset(0, 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  style: BT.mono(
                    24,
                    color: glow ? BP.amber : (own ? BP.violet : BP.ink),
                    weight: glow ? 700 : 400,
                  ),
                  child: Text(text, softWrap: false),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A bus line joining every HarfBuzz cell; the Apple column has no tap.
class _Bus extends StatelessWidget {
  const _Bus({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: visible ? 1 : 0),
    duration: const Duration(milliseconds: 1200),
    curve: Curves.easeInOutCubic,
    builder: (context, p, _) => p <= 0
        ? const SizedBox.shrink()
        : LoopBuilder(
            period: const Duration(milliseconds: 2400),
            builder: (context, t, _) => CustomPaint(painter: _BusPainter(p, t)),
          ),
  );
}

class _BusPainter extends CustomPainter {
  _BusPainter(this.p, this.t);

  final double p;
  final double t;

  static const _x0 = _labelW - 24;
  static const _x1 = _labelW + 4.5 * _colW;

  @override
  void paint(Canvas canvas, Size size) {
    final x = _x0 + (_x1 - _x0) * p;
    final line = Paint()
      ..color = BP.amber
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(_x0, _busY), Offset(x, _busY), line);
    for (var c = 0; c < _engines.length; c++) {
      final cx = _labelW + (c + 0.5) * _colW;
      if (cx > x) break;
      if (_isHarfBuzz(c, _shapingRow)) {
        canvas.drawLine(Offset(cx, _busY - _inset), Offset(cx, _busY), line);
        canvas.drawCircle(Offset(cx, _busY), 7, Paint()..color = BP.amber);
        canvas.drawCircle(
          Offset(cx, _busY),
          7,
          Paint()
            ..color = BP.paper
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      } else {
        // A jumper: crosses under Apple's own shaper without connecting.
        final hop = Path()
          ..moveTo(cx - 9, _busY)
          ..arcToPoint(Offset(cx + 9, _busY), radius: const Radius.circular(9), clockwise: false);
        canvas.drawLine(
          Offset(cx - 9, _busY),
          Offset(cx + 9, _busY),
          Paint()
            ..color = BP.paper
            ..strokeWidth = 6,
        );
        canvas.drawPath(
          hop,
          Paint()
            ..color = BP.amber
            ..strokeWidth = 3
            ..style = PaintingStyle.stroke,
        );
      }
    }
    // A pulse riding the bus once it's drawn.
    if (p >= 1) {
      final px = _x0 + (_x1 - _x0) * Curves.easeInOutSine.transform(t);
      canvas.drawCircle(
        Offset(px, _busY),
        12,
        Paint()
          ..color = BP.amber.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
      canvas.drawCircle(Offset(px, _busY), 4.5, Paint()..color = BP.ink);
    }
  }

  @override
  bool shouldRepaint(_BusPainter old) => old.p != p || old.t != t;
}

class _RailPainter extends CustomPainter {
  _RailPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    const x = 6.0;
    final dim = Paint()
      ..color = BP.lineDim
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(x, 0), Offset(x, size.height), dim);
    for (var r = 0; r < _rows.length; r++) {
      final y = (r + 0.5) * _rowH;
      canvas.drawLine(Offset(x - 4, y), Offset(x + 6, y), dim);
    }
    drawArrowHead(canvas, Offset(x, size.height), Offset(x, size.height - 10), dim, 6);
    final y = Curves.easeInOutSine.transform(t) * size.height;
    for (var k = 1; k <= 5; k++) {
      final ty = y - k * 9;
      if (ty < 0) break;
      canvas.drawCircle(
        Offset(x, ty),
        3.2 - k * 0.45,
        Paint()..color = BP.amber.withValues(alpha: 0.5 - k * 0.08),
      );
    }
    final d = Path()
      ..moveTo(x, y - 7)
      ..lineTo(x + 7, y)
      ..lineTo(x, y + 7)
      ..lineTo(x - 7, y)
      ..close();
    canvas.drawPath(d, Paint()..color = BP.amber);
  }

  @override
  bool shouldRepaint(_RailPainter old) => old.t != t;
}
