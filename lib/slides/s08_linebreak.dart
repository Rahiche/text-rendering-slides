import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../deck/theme.dart';
import '../deck/widgets.dart';

/// Line breaking: drag the right edge; the real paragraph re-breaks, and every
/// grapheme glides to its new line. Bands and ticks come from computeLineMetrics.
class LineBreakSlide extends StatefulWidget {
  const LineBreakSlide({super.key});

  @override
  State<LineBreakSlide> createState() => _LineBreakSlideState();
}

class _Lang {
  const _Lang(this.name, this.text, {this.rtl = false, this.spaces = true, this.height = 1.6});

  final String name;
  final String text;
  final bool rtl;

  /// Line height multiplier (Noto Kufi Arabic is ~1.9 em tall).
  final double height;

  /// Whether the script separates words with spaces (so a break between two
  /// letters is a forced, emergency break).
  final bool spaces;
}

const _langs = [
  _Lang('English', 'Greedy line breaking puts as many words on each line as will fit, then moves on to the next.'),
  _Lang('German', 'Der Donaudampfschifffahrtsgesellschaftskapitän sucht vergeblich nach einer Silbentrennung.'),
  _Lang('Thai', 'ภาษาไทยไม่มีช่องว่างระหว่างคำแต่ก็ยังตัดบรรทัดได้ ตัวตัดคำใช้พจนานุกรม', spaces: false),
  _Lang('Japanese', '日本語の文章は単語の間にスペースがありません。改行はどこでもできます。', spaces: false),
  _Lang('Arabic', 'النص العربي يكتب من اليمين إلى اليسار ويقسم إلى أسطر عند المسافات بين الكلمات', rtl: true, height: 2.0),
];

const _boxX = 56.0;
const _boxY = 92.0;
const _minW = 200.0;
const _maxW = 1100.0;

class _Break {
  const _Break(this.line, this.x, this.forced);

  final int line;
  final double x;
  final bool forced;
}

/// Everything the painter needs; notifies once per frame.
class _Flow extends ChangeNotifier {
  TextProbe? probe;
  double width = 640;
  double fade = 1;
  bool rtl = false;

  final ranges = <(int, int)>[];
  final ink = <bool>[];
  final target = <Rect>[];
  final shown = <Offset>[];

  final bandTarget = <Rect>[];
  final bandShown = <Rect>[];
  final bandAlpha = <double>[];
  final lineSpan = <(double, double)>[];
  final breaks = <_Break>[];
  int lineCount = 0;

  void notify() => notifyListeners();
}

class _LineBreakSlideState extends State<LineBreakSlide> with SingleTickerProviderStateMixin {
  final _flow = _Flow();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _phase = 0;
  double _fadeT = 1;
  bool _auto = true;
  int _lang = 0;

  @override
  void initState() {
    super.initState();
    _load(0, animate: false);
    _ticker = createTicker(_tick)..start();
  }

  void _load(int i, {bool animate = true}) {
    final old = _flow.probe;
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    final lang = _langs[i];
    _flow.rtl = lang.rtl;
    _flow.probe = TextProbe(
      TextSpan(text: lang.text, style: BT.sample(34, color: BP.ink, height: lang.height)),
      textDirection: lang.rtl ? TextDirection.rtl : TextDirection.ltr,
    );
    _flow.ranges
      ..clear()
      ..addAll(_flow.probe!.graphemes());
    _flow.ink
      ..clear()
      ..addAll([for (final (s, e) in _flow.ranges) lang.text.substring(s, e).trim().isNotEmpty]);
    _flow.target.clear();
    _flow.shown.clear();
    _flow.bandShown.clear();
    _flow.bandAlpha.clear();
    _relayout();
    // Start settled; fade the new text in.
    for (var k = 0; k < _flow.target.length; k++) {
      _flow.shown[k] = _flow.target[k].topLeft;
    }
    _fadeT = animate ? 0 : 1;
  }

  void _relayout() {
    final f = _flow;
    final p = f.probe!;
    p.painter.layout(minWidth: f.width, maxWidth: f.width);
    final lines = p.lines;
    f.lineCount = lines.length;

    f.target
      ..clear()
      ..addAll([for (final (s, e) in f.ranges) p.rectFor(s, e) ?? Rect.zero]);
    while (f.shown.length < f.target.length) {
      f.shown.add(f.target[f.shown.length].topLeft);
    }

    f.bandTarget.clear();
    f.lineSpan.clear();
    for (final l in lines) {
      final top = l.baseline - l.ascent;
      f.bandTarget.add(Rect.fromLTWH(0, top, f.width, l.ascent + l.descent));
      f.lineSpan.add((l.left, l.left + l.width));
    }
    while (f.bandShown.length < f.bandTarget.length) {
      final r = f.bandTarget[f.bandShown.length];
      f.bandShown.add(Rect.fromLTWH(r.left, r.top, r.width, 0));
      f.bandAlpha.add(0);
    }

    // Which grapheme ends each line → where (and how) it broke.
    final lastOnLine = List<int>.filled(lines.length, -1);
    for (var k = 0; k < f.target.length; k++) {
      final r = f.target[k];
      if (r == Rect.zero) continue;
      final cy = r.center.dy;
      for (var li = 0; li < lines.length; li++) {
        final b = f.bandTarget[li];
        if (cy >= b.top && cy <= b.bottom) {
          if (k > lastOnLine[li]) lastOnLine[li] = k;
          break;
        }
      }
    }
    f.breaks.clear();
    final lang = _langs[_lang];
    for (var li = 0; li < lines.length - 1; li++) {
      final k = lastOnLine[li];
      if (k < 0 || k + 1 >= f.ranges.length) continue;
      final a = lang.text.substring(f.ranges[k].$1, f.ranges[k].$2);
      final b = lang.text.substring(f.ranges[k + 1].$1, f.ranges[k + 1].$2);
      final forced = lang.spaces && a.trim().isNotEmpty && b.trim().isNotEmpty && a != '-';
      final (l, r) = f.lineSpan[li];
      f.breaks.add(_Break(li, f.rtl ? l : r, forced));
    }
  }

  void _tick(Duration elapsed) {
    final dt = math.min(0.05, (elapsed - _last).inMicroseconds / 1e6);
    _last = elapsed;
    final f = _flow;
    if (_auto) {
      _phase += dt;
      final w = 640 + 400 * math.sin(_phase * 2 * math.pi / 11);
      if ((w - f.width).abs() > 0.25) {
        f.width = w;
        _relayout();
      }
    }
    final k = 1 - math.exp(-dt / 0.075);
    for (var i = 0; i < f.target.length; i++) {
      final t = f.target[i].topLeft;
      final s = f.shown[i];
      f.shown[i] = (t - s).distance < 0.3 ? t : Offset.lerp(s, t, k)!;
    }
    for (var i = 0; i < f.bandShown.length; i++) {
      final live = i < f.bandTarget.length;
      final tr = live ? f.bandTarget[i] : Rect.fromLTWH(0, f.bandShown[i].top, f.width, f.bandShown[i].height);
      f.bandShown[i] = Rect.lerp(f.bandShown[i], tr, k)!;
      f.bandAlpha[i] += ((live ? 1.0 : 0.0) - f.bandAlpha[i]) * k;
    }
    // Drop bands that have faded out.
    while (f.bandShown.length > f.bandTarget.length && f.bandAlpha.last < 0.02) {
      f.bandShown.removeLast();
      f.bandAlpha.removeLast();
    }
    _fadeT = math.min(1, _fadeT + dt / 0.45);
    f.fade = Curves.easeOutCubic.transform(_fadeT);
    f.notify();
  }

  void _drag(double dx) {
    final f = _flow;
    f.width = (f.width + dx).clamp(_minW, _maxW);
    _relayout();
    if (_auto) setState(() => _auto = false);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _flow.probe?.dispose();
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideFrame(
      title: 'Line breaking',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: RepaintBoundary(child: CustomPaint(painter: _FlowPainter(_flow))),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: BpSegmented<int>(
              values: const [0, 1, 2, 3, 4],
              selected: _lang,
              labelOf: (i) => _langs[i].name,
              onChanged: (i) => setState(() {
                _lang = i;
                _load(i);
              }),
            ),
          ),
          // Drag handle on the width limit.
          AnimatedBuilder(
            animation: _flow,
            builder: (context, _) => Positioned(
              left: _boxX + _flow.width - 22,
              top: _boxY - 8,
              width: 44,
              height: 540,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (d) => _drag(d.delta.dx),
                  child: CustomPaint(painter: _HandlePainter(active: !_auto)),
                ),
              ),
            ),
          ),
          // Readout
          Positioned(
            left: _boxX + _maxW + 44,
            top: _boxY,
            right: 0,
            child: AnimatedBuilder(
              animation: _flow,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('maxWidth', style: BT.mono(14, color: BP.inkDim)),
                  const SizedBox(height: 4),
                  Text('${_flow.width.round()} px', style: BT.mono(36, color: BP.amber, weight: 500)),
                  const SizedBox(height: 28),
                  Text('lines', style: BT.mono(14, color: BP.inkDim)),
                  const SizedBox(height: 4),
                  AnimatedCount(
                    value: _flow.lineCount,
                    duration: const Duration(milliseconds: 300),
                    style: BT.display(48, color: BP.ink),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Container(width: 12, height: 3, color: BP.amber),
                      const SizedBox(width: 8),
                      Text('break', style: BT.mono(13, color: BP.inkDim)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(width: 12, height: 3, color: BP.red),
                      const SizedBox(width: 8),
                      Text('forced', style: BT.mono(13, color: BP.inkDim)),
                    ],
                  ),
                  const SizedBox(height: 28),
                  BpButton(
                    label: 'auto',
                    selected: _auto,
                    size: 14,
                    onTap: () => setState(() => _auto = !_auto),
                  ),
                ],
              ),
            ),
          ),
          const Positioned(
            right: 0,
            bottom: 0,
            child: BpTag('greedy · UAX #14 · ICU dictionaries', color: BP.inkDim),
          ),
        ],
      ),
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter(this.f) : super(repaint: f);

  final _Flow f;

  @override
  void paint(Canvas canvas, Size size) {
    final probe = f.probe;
    if (probe == null) return;
    const o = Offset(_boxX, _boxY);
    final w = f.width;
    final bottom = f.bandShown.isEmpty ? 60.0 : f.bandShown.fold<double>(0, (a, r) => math.max(a, r.bottom));
    final box = Rect.fromLTWH(o.dx, o.dy, w, math.max(60.0, bottom));

    // Paper box
    canvas.drawRect(box.inflate(12), Paint()..color = BP.panel.withValues(alpha: 0.7));
    canvas.drawRect(
      box.inflate(12),
      Paint()
        ..color = BP.lineFaint
        ..style = PaintingStyle.stroke,
    );

    // Line bands, alternating, with the real used width darker.
    for (var i = 0; i < f.bandShown.length; i++) {
      final a = f.bandAlpha[i];
      final r = f.bandShown[i].shift(o);
      canvas.drawRect(
        Rect.fromLTWH(o.dx, r.top, w, r.height),
        Paint()..color = (i.isEven ? BP.line : BP.violet).withValues(alpha: 0.05 * a),
      );
      if (i < f.lineSpan.length) {
        final (l, rr) = f.lineSpan[i];
        canvas.drawRect(
          Rect.fromLTRB(o.dx + l, r.top + 2, o.dx + rr, r.bottom - 2),
          Paint()..color = (i.isEven ? BP.line : BP.violet).withValues(alpha: 0.09 * a),
        );
      }
      _label(canvas, (i + 1).toString().padLeft(2, '0'), BT.mono(13, color: BP.inkFaint.withValues(alpha: a)),
          Offset(o.dx - 36, r.center.dy));
    }

    // Text: settled graphemes in one pass, moving ones one by one.
    final moving = <int>[];
    for (var k = 0; k < f.target.length; k++) {
      if (!f.ink[k]) continue;
      if ((f.shown[k] - f.target[k].topLeft).distance > 0.3) moving.add(k);
    }
    if (f.fade < 1) {
      canvas.saveLayer(box.inflate(80), Paint()..color = Color.fromRGBO(0, 0, 0, f.fade));
    }
    if (moving.isEmpty) {
      probe.paint(canvas, o);
    } else {
      final holes = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(box.inflate(200));
      for (final k in moving) {
        holes.addRect(_clipFor(k).shift(o));
      }
      canvas.save();
      canvas.clipPath(holes);
      probe.paint(canvas, o);
      canvas.restore();
      for (final k in moving) {
        final d = f.shown[k] - f.target[k].topLeft;
        canvas.save();
        canvas.translate(d.dx, d.dy);
        canvas.clipRect(_clipFor(k).shift(o));
        probe.paint(canvas, o);
        canvas.restore();
      }
    }
    if (f.fade < 1) canvas.restore();

    // Break ticks.
    for (final b in f.breaks) {
      if (b.line >= f.bandShown.length) continue;
      final r = f.bandShown[b.line].shift(o);
      final x = o.dx + b.x;
      final c = b.forced ? BP.red : BP.amber;
      final p = Paint()
        ..color = c
        ..strokeWidth = 2.5;
      canvas.drawLine(Offset(x, r.top + 8), Offset(x, r.bottom - 8), p);
      final dir = f.rtl ? -1.0 : 1.0;
      final tri = Path()
        ..moveTo(x + dir * 3, r.bottom - 8)
        ..lineTo(x + dir * 11, r.bottom - 8)
        ..lineTo(x + dir * 3, r.bottom - 16)
        ..close();
      canvas.drawPath(tri, Paint()..color = c);
    }

    // Width limit.
    final lx = o.dx + w;
    canvas.drawPath(
      dashPath(Path()
        ..moveTo(lx, o.dy - 40)
        ..lineTo(lx, size.height - 30), dash: 7, gap: 5),
      Paint()
        ..color = BP.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawPath(
      dashPath(Path()
        ..moveTo(o.dx, o.dy - 40)
        ..lineTo(o.dx, size.height - 30), dash: 7, gap: 5),
      Paint()
        ..color = BP.lineDim
        ..style = PaintingStyle.stroke,
    );
    // Dimension across the top.
    final dy = o.dy - 28;
    final dp = Paint()
      ..color = BP.amber
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(o.dx, dy), Offset(lx, dy), dp);
    drawArrowHead(canvas, Offset(o.dx, dy), Offset(o.dx + 10, dy), dp, 5);
    drawArrowHead(canvas, Offset(lx, dy), Offset(lx - 10, dy), dp, 5);
    final label = '${w.round()} px';
    final tp = TextPainter(
      text: TextSpan(text: label, style: BT.mono(14, color: BP.amber)),
      textDirection: TextDirection.ltr,
    )..layout();
    final tr = Rect.fromCenter(center: Offset((o.dx + lx) / 2, dy), width: tp.width + 16, height: tp.height);
    canvas.drawRect(tr, Paint()..color = BP.paper);
    tp.paint(canvas, tr.topLeft + const Offset(8, 0));
    tp.dispose();
  }

  /// Clip rect for grapheme [k]: its box, stretched to its whole line band so
  /// marks above and below are kept. Neighbouring clips never overlap, so they
  /// can be punched out of one even-odd path.
  Rect _clipFor(int k) {
    final r = f.target[k];
    final bands = f.bandTarget;
    for (var i = 0; i < bands.length; i++) {
      final b = bands[i];
      if (r.center.dy >= b.top && r.center.dy <= b.bottom) {
        return Rect.fromLTRB(
          r.left,
          i == 0 ? b.top - 40 : b.top,
          r.right,
          i == bands.length - 1 ? b.bottom + 40 : b.bottom,
        );
      }
    }
    return r;
  }

  static void _label(Canvas canvas, String text, TextStyle style, Offset center) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }

  @override
  bool shouldRepaint(_FlowPainter old) => old.f != f;
}

class _HandlePainter extends CustomPainter {
  _HandlePainter({required this.active});

  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final r = Rect.fromCenter(center: Offset(cx, 150), width: 16, height: 64);
    canvas.drawRect(r, Paint()..color = BP.paper);
    canvas.drawRect(
      r,
      Paint()
        ..color = BP.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 2.5 : 1.5,
    );
    final g = Paint()
      ..color = BP.amber
      ..strokeWidth = 1.5;
    for (final dy in [-8.0, 0.0, 8.0]) {
      canvas.drawLine(Offset(cx - 4, 150 + dy), Offset(cx + 4, 150 + dy), g);
    }
    final a = Paint()
      ..color = BP.amber.withValues(alpha: 0.8)
      ..strokeWidth = 1.5;
    drawArrowHead(canvas, Offset(cx - 18, 150), Offset(cx - 10, 150), a, 5);
    drawArrowHead(canvas, Offset(cx + 18, 150), Offset(cx + 10, 150), a, 5);
  }

  @override
  bool shouldRepaint(_HandlePainter old) => old.active != active;
}
