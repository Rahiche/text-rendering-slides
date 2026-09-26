import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'journey.dart';

/// Stop 2: the word as a Dart String — a strip of UTF-16 code units in
/// memory, wired to where each grapheme really lands on screen.
class JStringSlide extends StatelessWidget {
  const JStringSlide({super.key});

  @override
  Widget build(BuildContext context) => JourneyFrame(
    stop: 2,
    title: (_) => 'A Dart String',
    builder: (context, d) => _StringStage(data: d),
  );
}

const _stripL = 170.0;
const _stripR = 1250.0;
const _stripC = (_stripL + _stripR) / 2;
const _baseline = 120.0;
const _cellTop = 252.0;
const _cellH = 92.0;
const _cellGap = 8.0;
const _cpTop = 400.0;
const _cpH = 44.0;
const _bitsTop = 492.0;
const _bit = 28.0;
const _bitGap = 4.0;
const _nibbleGap = 12.0;
const _bitsW = 16 * _bit + 12 * _bitGap + 3 * _nibbleGap;
const _countX = 1290.0;

String _hex4(int v) => v.toRadixString(16).toUpperCase().padLeft(4, '0');

bool _isHigh(int u) => u >= 0xD800 && u <= 0xDBFF;
bool _isLow(int u) => u >= 0xDC00 && u <= 0xDFFF;

bool _isCombining(int c) =>
    (c >= 0x0300 && c <= 0x036F) ||
    (c >= 0x064B && c <= 0x065F) ||
    (c >= 0x0900 && c <= 0x0903) ||
    (c >= 0x093A && c <= 0x094F);

class _StringStage extends StatefulWidget {
  const _StringStage({required this.data});

  final JourneyData data;

  @override
  State<_StringStage> createState() => _StringStageState();
}

class _StringStageState extends State<_StringStage> {
  late final String _s = widget.data.text;
  late final List<int> _units = _s.codeUnits;
  late final double _size;
  late final TextProbe _probe;
  late final TextPainter _quote;
  late final List<(int, int)> _clusters;

  /// Code points: (value, UTF-16 start, UTF-16 length).
  late final List<(int, int, int)> _cps = [
    for (final g in widget.data.glyphs) (g.codePoint, g.start, g.end - g.start),
  ];
  int? _hover;

  @override
  void initState() {
    super.initState();
    var size = 110.0;
    var p = TextProbe(TextSpan(text: _s, style: journeyStyle(size)));
    if (p.size.width > 900) {
      size = size * 900 / p.size.width;
      p.dispose();
      p = TextProbe(TextSpan(text: _s, style: journeyStyle(size)));
    }
    _size = size;
    _probe = p;
    _clusters = p.graphemes();
    _quote = TextPainter(
      text: TextSpan(text: "'", style: BT.mono(size * 0.8, color: BP.inkFaint)),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  void dispose() {
    _probe.dispose();
    _quote.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = _units.length;
    if (n == 0) return const SizedBox();
    final cellW = math.min(120.0, (_stripR - _stripL - (n - 1) * _cellGap) / n);
    final total = n * cellW + (n - 1) * _cellGap;
    final x0 = _stripC - total / 2;
    double cellX(int i) => x0 + i * (cellW + _cellGap);
    final lines = _probe.lines;
    final origin = Offset(
      _stripC - _probe.size.width / 2,
      _baseline - (lines.isEmpty ? _size : lines.first.baseline),
    );
    final rtl = widget.data.rtl;

    return LoopBuilder(
      period: Duration(milliseconds: 820 * n),
      builder: (context, t, _) {
        final pos = t * n;
        final head = pos.floor().clamp(0, n - 1);
        final target = _hover ?? head;
        final cluster = _clusters.indexWhere((c) => target >= c.$1 && target < c.$2);

        // Read head glides to the next cell at the end of each slot.
        final f = Curves.easeInOutCubic.transform(((pos - head - 0.78) / 0.22).clamp(0.0, 1.0));
        final next = head + 1;
        final hx = next >= n
            ? cellX(head) + cellW / 2
            : lerpDouble(cellX(head), cellX(next), f)! + cellW / 2;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Row labels
            Positioned(
              left: 0,
              top: _baseline - 24,
              child: _RowLabel('String s', rtl ? 'visual ←' : null),
            ),
            Positioned(left: 0, top: _cellTop + 24, child: _RowLabel('UTF-16', rtl ? 'logical →' : 'code units')),
            Positioned(left: 0, top: _cpTop + 10, child: const _RowLabel('code points', null)),
            Positioned(left: 0, top: _bitsTop + 2, child: const _RowLabel('bits', null)),

            // Callout lines (behind everything below the cells)
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: target.toDouble()),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => CustomPaint(
                  painter: _CalloutPainter(
                    left: x0 + v * (cellW + _cellGap),
                    width: cellW,
                  ),
                ),
              ),
            ),

            // The word + connectors to memory
            Positioned.fill(
              child: CustomPaint(
                painter: _WordPainter(
                  probe: _probe,
                  quote: _quote,
                  origin: origin,
                  size: _size,
                  clusters: _clusters,
                  cellCenter: (i) => cellX(i) + cellW / 2,
                  active: cluster,
                ),
              ),
            ),

            // Read head
            Positioned(
              left: hx - 9,
              top: _cellTop - 18,
              width: 18,
              height: 12,
              child: const CustomPaint(painter: _HeadPainter()),
            ),

            // Memory: one cell per UTF-16 code unit
            for (var i = 0; i < n; i++)
              Positioned(
                left: cellX(i),
                top: _cellTop,
                width: cellW,
                height: _cellH,
                child: MouseRegion(
                  onEnter: (_) => setState(() => _hover = i),
                  onExit: (_) => setState(() => _hover = null),
                  child: Reveal(
                    visible: true,
                    delay: Duration(milliseconds: 60 * math.min(i, 12)),
                    child: _UnitCell(index: i, unit: _units[i], active: i == target),
                  ),
                ),
              ),

            // Surrogate pairs
            for (final (_, o, len) in _cps)
              if (len == 2) ...[
                Positioned(
                  left: cellX(o),
                  top: _cellTop + _cellH + 4,
                  width: 2 * cellW + _cellGap,
                  height: 18,
                  child: const CustomPaint(painter: _BracketPainter(BP.coral)),
                ),
                Positioned(
                  left: cellX(o),
                  top: _cellTop + _cellH + 25,
                  width: 2 * cellW + _cellGap,
                  child: Text(
                    'surrogate pair',
                    textAlign: TextAlign.center,
                    style: BT.mono(12, color: BP.coral),
                  ),
                ),
              ],

            // Code points
            for (final (cp, o, len) in _cps)
              Positioned(
                left: cellX(o),
                top: _cpTop,
                width: len * cellW + (len - 1) * _cellGap,
                height: _cpH,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: BP.panel,
                    border: Border.all(
                      color: target >= o && target < o + len ? BP.amber : BP.lineDim,
                      width: target >= o && target < o + len ? 1.5 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'U+${_hex4(cp)}',
                      style: BT.mono(15, color: len == 2 ? BP.coral : BP.line),
                    ),
                  ),
                ),
              ),

            // Bits of the target unit
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: target.toDouble()),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) {
                  final center = x0 + v * (cellW + _cellGap) + cellW / 2;
                  final bx = (center - _bitsW / 2).clamp(_stripL, _stripR - _bitsW);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: bx,
                        top: _bitsTop,
                        child: _Bits(unit: _units[target], index: target),
                      ),
                    ],
                  );
                },
              ),
            ),

            // Counters
            Positioned(
              left: _countX,
              top: _cellTop,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('s.length', style: BT.mono(15, color: BP.inkDim)),
                  _CountUp(value: n, style: BT.display(72, color: BP.amber, height: 1.1)),
                ],
              ),
            ),
            Positioned(
              left: _countX,
              top: _cpTop - 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('s.runes.length', style: BT.mono(12, color: BP.inkFaint)),
                  _CountUp(value: _cps.length, style: BT.display(38, color: BP.inkDim, height: 1.1)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RowLabel extends StatelessWidget {
  const _RowLabel(this.label, this.sub);

  final String label;
  final String? sub;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: BT.mono(16, color: BP.inkDim)),
      if (sub != null) ...[
        const SizedBox(height: 4),
        Text(sub!, style: BT.mono(12, color: sub!.contains('←') || sub!.contains('→') ? BP.amber : BP.inkFaint)),
      ],
    ],
  );
}

class _UnitCell extends StatelessWidget {
  const _UnitCell({required this.index, required this.unit, required this.active});

  final int index;
  final int unit;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final surrogate = _isHigh(unit) || _isLow(unit);
    Widget glyph;
    if (surrogate) {
      glyph = Text(_isHigh(unit) ? 'high' : 'low', style: BT.mono(15, color: BP.coral));
    } else if (unit == 0x200D || unit == 0xFE0F || unit == 0x20) {
      glyph = Text(unit == 0x20 ? 'SP' : (unit == 0x200D ? 'ZWJ' : 'VS16'), style: BT.mono(15, color: BP.inkDim));
    } else {
      final ch = String.fromCharCode(unit);
      glyph = Text(_isCombining(unit) ? '◌$ch' : ch, style: journeyStyle(28).copyWith(height: 1));
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: active ? BP.amber.withValues(alpha: 0.13) : BP.panel,
        border: Border.all(color: active ? BP.amber : BP.line, width: active ? 2 : 1),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 6,
            top: 3,
            child: Text('$index', style: BT.mono(11, color: active ? BP.amber : BP.inkFaint)),
          ),
          Positioned.fill(
            top: 14,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: 38, child: Center(child: glyph)),
                    const SizedBox(height: 4),
                    Text(
                      '0x${_hex4(unit)}',
                      style: BT.mono(15, color: active ? BP.amber : (surrogate ? BP.coral : BP.line)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A code unit exploded into its 16 bits, grouped in nibbles.
class _Bits extends StatelessWidget {
  const _Bits({required this.unit, required this.index});

  final int unit;
  final int index;

  @override
  Widget build(BuildContext context) {
    final hex = _hex4(unit);
    return SizedBox(
      width: _bitsW,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var b = 15; b >= 0; b--) ...[
                _Bit(on: (unit >> b) & 1 == 1),
                if (b > 0) SizedBox(width: b % 4 == 0 ? _nibbleGap : _bitGap),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var k = 0; k < 4; k++) ...[
                SizedBox(
                  width: 4 * _bit + 3 * _bitGap,
                  child: Text(hex[k], textAlign: TextAlign.center, style: BT.mono(14, color: BP.inkDim)),
                ),
                if (k < 3) const SizedBox(width: _nibbleGap),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Center(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 's.codeUnitAt($index)', style: BT.mono(17, color: BP.amber)),
                  TextSpan(text: '  =  0x$hex  =  $unit', style: BT.mono(17, color: BP.ink)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bit extends StatelessWidget {
  const _Bit({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 220),
    width: _bit,
    height: _bit,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: on ? BP.amber : BP.panel,
      border: Border.all(color: on ? BP.amber : BP.lineDim),
    ),
    child: Text(on ? '1' : '0', style: BT.mono(13, color: on ? BP.paper : BP.inkFaint)),
  );
}

class _CountUp extends StatelessWidget {
  const _CountUp({required this.value, required this.style});

  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value.toDouble()),
    duration: const Duration(milliseconds: 900),
    curve: Curves.easeOutCubic,
    builder: (context, v, _) => Text('${v.round()}', style: style),
  );
}

/// Quotes, the real laid-out word, glyph boxes and the wires down to memory.
class _WordPainter extends CustomPainter {
  _WordPainter({
    required this.probe,
    required this.quote,
    required this.origin,
    required this.size,
    required this.clusters,
    required this.cellCenter,
    required this.active,
  });

  final TextProbe probe;
  final TextPainter quote;
  final Offset origin;
  final double size;
  final List<(int, int)> clusters;
  final double Function(int unit) cellCenter;
  final int active;

  @override
  void paint(Canvas canvas, Size _) {
    final qBase = quote.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final w = probe.size.width;
    quote.paint(canvas, Offset(origin.dx - quote.width - 14, _baseline - qBase));
    quote.paint(canvas, Offset(origin.dx + w + 14, _baseline - qBase));

    final top = _baseline - size * 0.9;
    final bottom = _baseline + size * 0.34;
    final wireTop = bottom + 8;
    const wireBottom = _cellTop - 22;

    final dim = Paint()
      ..color = BP.lineDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final hot = Paint()
      ..color = BP.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Draw inactive wires first so the hot one sits on top.
    for (final pass in [false, true]) {
      for (var k = 0; k < clusters.length; k++) {
        final isHot = k == active;
        if (isHot != pass) continue;
        final (s, e) = clusters[k];
        final r = probe.rectFor(s, e);
        if (r == null) continue;
        final box = Rect.fromLTRB(origin.dx + r.left, top, origin.dx + r.right, bottom);
        if (isHot) {
          canvas.drawRect(box, Paint()..color = BP.amber.withValues(alpha: 0.10));
          canvas.drawRect(box, hot);
        } else {
          canvas.drawPath(dashPath(Path()..addRect(box), dash: 4, gap: 4), dim);
        }
        final from = Offset(box.center.dx, wireTop);
        for (var u = s; u < e; u++) {
          final to = Offset(cellCenter(u), wireBottom);
          canvas.drawLine(from, to, isHot ? hot : dim);
          canvas.drawCircle(to, isHot ? 3 : 2, Paint()..color = isHot ? BP.amber : BP.lineDim);
        }
        canvas.drawCircle(from, isHot ? 3 : 2, Paint()..color = isHot ? BP.amber : BP.lineDim);
      }
    }
    probe.paint(canvas, origin);
  }

  @override
  bool shouldRepaint(_WordPainter old) => old.active != active || old.origin != origin;
}

class _CalloutPainter extends CustomPainter {
  _CalloutPainter({required this.left, required this.width});

  final double left;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = left + width / 2;
    final bx = (cx - _bitsW / 2).clamp(_stripL, _stripR - _bitsW);
    const y0 = _cellTop + _cellH;
    const y1 = _bitsTop - 6;
    final p = Paint()
      ..color = BP.amber.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..moveTo(left, y0)
      ..lineTo(bx, y1)
      ..moveTo(left + width, y0)
      ..lineTo(bx + _bitsW, y1);
    canvas.drawPath(dashPath(path, dash: 5, gap: 5), p);
  }

  @override
  bool shouldRepaint(_CalloutPainter old) => old.left != left || old.width != width;
}

class _BracketPainter extends CustomPainter {
  const _BracketPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final m = size.height * 0.5;
    canvas.drawPath(
      Path()
        ..moveTo(3, 2)
        ..lineTo(3, m)
        ..lineTo(size.width - 3, m)
        ..lineTo(size.width - 3, 2)
        ..moveTo(size.width / 2, m)
        ..lineTo(size.width / 2, size.height),
      p,
    );
  }

  @override
  bool shouldRepaint(_BracketPainter old) => old.color != color;
}

class _HeadPainter extends CustomPainter {
  const _HeadPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close(),
      Paint()..color = BP.amber,
    );
  }

  @override
  bool shouldRepaint(_HeadPainter old) => false;
}
