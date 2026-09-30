import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../deck/deck.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';

/// "Only in Flutter": five live playgrounds for things you get because
/// Flutter owns the whole text stack. Tabs top-right; if the registry gives
/// this slide steps, each step selects the matching tab. Each playground is
/// one big demo with at most a couple of large controls.
class CanSlide extends StatefulWidget {
  const CanSlide({super.key});

  @override
  State<CanSlide> createState() => _CanSlideState();
}

enum _Tab {
  same('same everywhere'),
  paint('paint'),
  widgets('widgets in text'),
  glyph('every glyph'),
  threeD('3D');

  const _Tab(this.label);

  final String label;
}

class _CanSlideState extends State<CanSlide> {
  _Tab _tab = _Tab.same;
  int? _step;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final step = SlideScope.of(context).step;
    if (step != _step) {
      _step = step;
      _tab = _Tab.values[step.clamp(0, _Tab.values.length - 1)];
    }
  }

  @override
  Widget build(BuildContext context) {
    return SlideFrame(
      title: 'Only in Flutter',
      contentBottom: 114,
      trailing: BpSegmented<_Tab>(
        values: _Tab.values,
        selected: _tab,
        size: 18,
        labelOf: (t) => t.label,
        onChanged: (t) => setState(() => _tab = t),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (cur, prev) => Stack(fit: StackFit.expand, children: [...prev, ?cur]),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.025), end: Offset.zero).animate(anim),
            child: child,
          ),
        ),
        child: KeyedSubtree(
          key: ValueKey(_tab),
          child: switch (_tab) {
            _Tab.same => const _SameTab(),
            _Tab.paint => const _PaintTab(),
            _Tab.widgets => const _WidgetsTab(),
            _Tab.glyph => const _GlyphTab(),
            _Tab.threeD => const _ThreeDTab(),
          },
        ),
      ),
    );
  }
}

Paint _stroke(Color c, [double w = 1]) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w;

double _lerp(double a, double b, double t) => a + (b - a) * t;

// ─────────────────────────────────────────────────────────────────────────────
// a) same everywhere
// ─────────────────────────────────────────────────────────────────────────────

/// Paragraph parameters: font size, letter spacing, wrap width, line height.
class _P {
  const _P(this.size, this.spacing, this.width, this.height);

  final double size;
  final double spacing;
  final double width;
  final double height;

  _P lerp(_P o, double t) => _P(
    _lerp(size, o.size, t),
    _lerp(spacing, o.spacing, t),
    _lerp(width, o.width, t),
    _lerp(height, o.height, t),
  );
}

const _sameText =
    'The five boxing wizards jump quickly. Sphinx of black quartz, judge my vow. '
    'How vexingly quick daft zebras jump!';

const _flutterP = _P(28, 0, 282, 1.4);

/// Mimics of each native engine: slightly different size, tracking, width.
const _devices = [
  ('iOS', _P(29.8, -0.3, 276, 1.28)),
  ('Android', _P(27, 0.25, 290, 1.5)),
  ('web', _P(28, 0.5, 272, 1.45)),
  ('macOS', _P(26.6, -0.1, 292, 1.34)),
];

const _devW = 344.0;
const _devH = 474.0;
const _devGap = (1472 - 4 * _devW) / 3;
const _paraOrigin = Offset(28, 112);

TextStyle _sameStyle(_P p) => BT.display(p.size, letterSpacing: p.spacing, weight: 400);

/// Where every word lands in a real paragraph layout with parameters [p].
class _ParaLayout {
  _ParaLayout(_P p, List<(int, int)> words) {
    final probe = TextProbe(
      TextSpan(text: _sameText, style: _sameStyle(p).copyWith(height: p.height)),
      maxWidth: p.width,
    );
    lines = probe.lines;
    for (final (s, e) in words) {
      final r = probe.rectFor(s, e) ?? Rect.zero;
      var li = lines.length - 1;
      for (var l = 0; l < lines.length; l++) {
        if (r.center.dy <= lines[l].baseline + lines[l].descent) {
          li = l;
          break;
        }
      }
      pos.add(Offset(r.left, lines[li].baseline));
      lineOf.add(li);
    }
    probe.dispose();
    final one = TextProbe(TextSpan(text: 'Hx', style: _sameStyle(p)));
    ascent = one.lines.first.ascent;
    one.dispose();
  }

  late final List<ui.LineMetrics> lines;
  final pos = <Offset>[];
  final lineOf = <int>[];
  late final double ascent;
}

class _SameTab extends StatefulWidget {
  const _SameTab();

  @override
  State<_SameTab> createState() => _SameTabState();
}

class _SameTabState extends State<_SameTab> {
  bool _native = false;
  late final List<(int, int)> _words = [
    for (final m in RegExp(r'\S+').allMatches(_sameText)) (m.start, m.end),
  ];
  late _ParaLayout _flutter;
  late List<_ParaLayout> _natives;

  @override
  void initState() {
    super.initState();
    _compute();
    PaintingBinding.instance.systemFonts.addListener(_onFonts);
  }

  void _onFonts() {
    if (mounted) setState(_compute);
  }

  void _compute() {
    _flutter = _ParaLayout(_flutterP, _words);
    _natives = [for (final d in _devices) _ParaLayout(d.$2, _words)];
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_onFonts);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final distinct = {for (final n in _natives) n.lineOf.join(',')}.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            BpSegmented<bool>(
              values: const [false, true],
              selected: _native,
              size: 20,
              labelOf: (v) => v ? 'native' : 'flutter',
              onChanged: (v) => setState(() => _native = v),
            ),
            const SizedBox(width: 28),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _native
                  ? BpTag('$distinct layouts', key: const ValueKey('n'), color: BP.red, size: 20)
                  : const BpTag('1 layout', key: ValueKey('f'), color: BP.green, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Expanded(
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: _native ? 1.0 : 0.0),
            duration: const Duration(milliseconds: 1100),
            curve: Curves.easeInOutCubic,
            builder: (context, k, _) => _devicesAt(k),
          ),
        ),
      ],
    );
  }

  Widget _devicesAt(double k) {
    final words = <Widget>[];
    for (var i = 0; i < _devices.length; i++) {
      final a = _flutter;
      final b = _natives[i];
      final p = _flutterP.lerp(_devices[i].$2, k);
      final style = _sameStyle(p);
      final asc = _lerp(a.ascent, b.ascent, k);
      final ox = i * (_devW + _devGap) + _paraOrigin.dx;
      for (var w = 0; w < _words.length; w++) {
        final pos = Offset.lerp(a.pos[w], b.pos[w], k)!;
        words.add(Positioned(
          left: ox + pos.dx,
          top: _paraOrigin.dy + pos.dy - asc,
          child: Text(
            _sameText.substring(_words[w].$1, _words[w].$2),
            style: style,
            softWrap: false,
          ),
        ));
      }
    }
    final layouts = [for (var i = 0; i < _devices.length; i++) k < 0.5 ? _flutter : _natives[i]];
    return LoopBuilder(
      period: const Duration(milliseconds: 9000),
      child: Stack(clipBehavior: Clip.none, children: words),
      builder: (context, t, child) => Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < _devices.length; i++)
            Positioned(
              left: i * (_devW + _devGap),
              top: 0,
              width: _devW,
              height: _devH,
              child: CustomPaint(painter: _ChromePainter(i)),
            ),
          Positioned.fill(
            child: CustomPaint(
              painter: _SameOverlay(
                k: k,
                t: t,
                layouts: layouts,
                flutter: _flutter,
                widths: [for (final d in _devices) _lerp(_flutterP.width, d.$2.width, k)],
              ),
            ),
          ),
          Positioned.fill(child: child!),
          for (var i = 0; i < _devices.length; i++)
            Positioned(
              left: i * (_devW + _devGap),
              width: _devW,
              top: _devH + 12,
              child: Center(child: Text(_devices[i].$1, style: BT.display(28))),
            ),
        ],
      ),
    );
  }
}

class _SameOverlay extends CustomPainter {
  _SameOverlay({
    required this.k,
    required this.t,
    required this.layouts,
    required this.flutter,
    required this.widths,
  });

  final double k;
  final double t;
  final List<_ParaLayout> layouts;
  final _ParaLayout flutter;
  final List<double> widths;

  @override
  void paint(Canvas canvas, Size size) {
    final fade = 1 - math.sin(k * math.pi);
    // Shared baselines across all four frames while they agree.
    if (k < 1) {
      final g = _stroke(BP.lineDim.withValues(alpha: 0.55 * (1 - k)));
      for (final l in flutter.lines) {
        final y = _paraOrigin.dy + l.baseline;
        canvas.drawPath(
          dashPath(Path()
            ..moveTo(0, y)
            ..lineTo(size.width, y), dash: 3, gap: 7),
          g,
        );
      }
    }
    final step = (t * 9).floor();
    for (var i = 0; i < layouts.length; i++) {
      final L = layouts[i];
      final o = Offset(i * (_devW + _devGap), 0) + _paraOrigin;
      final w = widths[i];
      // wrap width
      final wp = _stroke(BP.lineFaint);
      for (final x in [o.dx, o.dx + w]) {
        canvas.drawPath(
          dashPath(Path()
            ..moveTo(x, o.dy - 18)
            ..lineTo(x, _devH - 40), dash: 4, gap: 4),
          wp,
        );
      }
      if (fade <= 0.02) continue;
      // scanning line highlight
      final li = step % 12;
      if (li < L.lines.length) {
        final l = L.lines[li];
        final r = Rect.fromLTRB(
          o.dx - 8,
          o.dy + l.baseline - l.ascent,
          o.dx + w + 8,
          o.dy + l.baseline + l.descent,
        );
        canvas.drawRect(r, Paint()..color = BP.amber.withValues(alpha: 0.10 * fade));
        canvas.drawRect(
          Rect.fromLTWH(r.left, r.top, 2.5, r.height),
          Paint()..color = BP.amber.withValues(alpha: fade),
        );
      }
      // line ends
      final tick = Paint()
        ..color = BP.amber.withValues(alpha: 0.9 * fade)
        ..strokeWidth = 2;
      for (final l in L.lines) {
        final x = o.dx + l.left + l.width + 4;
        final y = o.dy + l.baseline;
        canvas.drawLine(Offset(x, y - l.ascent * 0.7), Offset(x, y + 2), tick);
      }
    }
  }

  @override
  bool shouldRepaint(_SameOverlay old) => true;
}

/// Device chrome: iOS phone, Android phone, browser window, macOS window.
class _ChromePainter extends CustomPainter {
  const _ChromePainter(this.kind);

  final int kind;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final line = _stroke(BP.line, 1.5);
    final dim = _stroke(BP.lineDim);
    final fill = Paint()..color = BP.panel;
    final faint = Paint()..color = BP.lineFaint;
    final w = size.width;
    switch (kind) {
      case 0: // iOS
        final outer = RRect.fromRectAndRadius(r, const Radius.circular(50));
        canvas.drawRRect(outer, fill);
        canvas.drawRRect(outer, line);
        canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(10), const Radius.circular(40)), dim);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(w / 2, 36), width: 100, height: 30),
            const Radius.circular(15),
          ),
          faint,
        );
        canvas.drawLine(const Offset(46, 36), const Offset(80, 36), _stroke(BP.lineDim, 4));
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(w - 72, 30, 26, 12), const Radius.circular(3)),
          dim,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(w / 2, size.height - 22), width: 124, height: 5),
            const Radius.circular(3),
          ),
          Paint()..color = BP.lineDim,
        );
      case 1: // Android
        final outer = RRect.fromRectAndRadius(r, const Radius.circular(30));
        canvas.drawRRect(outer, fill);
        canvas.drawRRect(outer, line);
        canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(10), const Radius.circular(22)), dim);
        canvas.drawCircle(Offset(w / 2, 34), 8, dim);
        canvas.drawLine(const Offset(30, 35), const Offset(66, 35), _stroke(BP.lineDim, 4));
        final sig = Path()
          ..moveTo(w - 80, 42)
          ..lineTo(w - 64, 42)
          ..lineTo(w - 64, 28)
          ..close();
        canvas.drawPath(sig, Paint()..color = BP.lineDim);
        canvas.drawRect(Rect.fromLTWH(w - 54, 28, 10, 14), dim);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(w / 2, size.height - 22), width: 90, height: 4),
            const Radius.circular(2),
          ),
          Paint()..color = BP.lineDim,
        );
      case 2: // browser
        final outer = RRect.fromRectAndRadius(r, const Radius.circular(10));
        canvas.drawRRect(outer, fill);
        canvas.drawRRect(outer, line);
        final tab = Path()
          ..moveTo(14, 38)
          ..lineTo(24, 10)
          ..lineTo(140, 10)
          ..lineTo(150, 38);
        canvas.drawPath(tab, dim);
        canvas.drawLine(const Offset(0, 38), Offset(w, 38), dim);
        for (var i = 0; i < 2; i++) {
          final cx = 22.0 + i * 22;
          drawArrowHead(canvas, Offset(i == 0 ? cx - 5 : cx + 5, 58), Offset(cx, 58), dim, 7);
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(70, 46, w - 86, 24), const Radius.circular(12)),
          dim,
        );
        canvas.drawCircle(const Offset(86, 58), 4, dim);
        canvas.drawLine(const Offset(98, 58), Offset(w - 60, 58), _stroke(BP.lineFaint, 3));
        canvas.drawLine(const Offset(0, 80), Offset(w, 80), dim);
      default: // macOS
        final outer = RRect.fromRectAndRadius(r, const Radius.circular(12));
        canvas.drawRRect(outer, fill);
        canvas.drawRRect(outer, line);
        canvas.drawLine(const Offset(0, 46), Offset(w, 46), dim);
        final colors = [BP.red, BP.amber, BP.green];
        for (var i = 0; i < 3; i++) {
          canvas.drawCircle(Offset(24.0 + i * 20, 23), 6.5, Paint()..color = colors[i].withValues(alpha: 0.7));
        }
        canvas.drawLine(Offset(w / 2 - 50, 23), Offset(w / 2 + 50, 23), _stroke(BP.lineFaint, 3));
    }
  }

  @override
  bool shouldRepaint(_ChromePainter old) => old.kind != kind;
}

// ─────────────────────────────────────────────────────────────────────────────
// b) paint: shader foreground, stroke width, animated variable weight
// ─────────────────────────────────────────────────────────────────────────────

class _PaintTab extends StatefulWidget {
  const _PaintTab();

  @override
  State<_PaintTab> createState() => _PaintTabState();
}

class _PaintTabState extends State<_PaintTab> {
  double _stroke = 0;
  double _weight = 400;
  bool _breathe = true;

  @override
  Widget build(BuildContext context) {
    return LoopBuilder(
      period: const Duration(milliseconds: 6000),
      builder: (context, t, _) {
        final target = _breathe ? 500 + 200 * math.sin(2 * math.pi * t * 2) : _weight;
        return TweenAnimationBuilder<double>(
          tween: Tween(end: target),
          duration: Duration(milliseconds: _breathe ? 120 : 450),
          curve: Curves.easeOutCubic,
          builder: (context, w, _) => Column(
            children: [
              Expanded(
                child: CustomPaint(
                  painter: _ShaderTextPainter(t: t, weight: w, stroke: _stroke),
                  child: const SizedBox.expand(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Slider(
                    label: 'stroke',
                    value: _stroke,
                    min: 0,
                    max: 10,
                    width: 300,
                    format: (v) => v < 0.05 ? 'fill' : v.toStringAsFixed(1),
                    onChanged: (v) => setState(() => _stroke = v),
                  ),
                  const SizedBox(width: 72),
                  _Slider(
                    label: 'weight',
                    value: _breathe ? w : _weight,
                    min: 300,
                    max: 700,
                    width: 360,
                    format: (v) => v.round().toString(),
                    onChanged: (v) => setState(() {
                      _breathe = false;
                      _weight = v;
                    }),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ShaderTextPainter extends CustomPainter {
  _ShaderTextPainter({required this.t, required this.weight, required this.stroke});

  final double t;
  final double weight;
  final double stroke;

  static const _text = 'Text نص';
  static const _colors = [BP.line, BP.violet, BP.pink, BP.coral, BP.amber, BP.green, BP.line];

  TextPainter _tp(Paint? fg) => TextPainter(
    text: TextSpan(
      text: _text,
      style: TextStyle(
        fontFamily: BP.display,
        fontFamilyFallback: const [BP.arabic],
        fontSize: 230,
        foreground: fg,
        fontVariations: [FontVariation.weight(weight)],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final measure = _tp(null);
    final o = Offset((size.width - measure.width) / 2, (size.height - measure.height) / 2);
    final rect = o & measure.size;
    final lm = measure.computeLineMetrics().first;
    final base = o.dy + lm.baseline;

    // Guides: baseline, ascent, descent.
    canvas.drawLine(Offset(0, base), Offset(size.width, base), _stroke(BP.lineDim));
    final g = _stroke(BP.lineFaint);
    for (final y in [base - lm.ascent, base + lm.descent]) {
      canvas.drawPath(
        dashPath(Path()
          ..moveTo(0, y)
          ..lineTo(size.width, y), dash: 8, gap: 6),
        g,
      );
    }

    Shader sweep(double a) => SweepGradient(
      colors: _colors,
      transform: GradientRotation(a),
    ).createShader(rect);

    final fillAlpha = 1 - (stroke / 10) * 0.9;
    final fill = _tp(Paint()
      ..shader = sweep(2 * math.pi * t)
      ..color = Color.fromRGBO(255, 255, 255, fillAlpha));
    fill.paint(canvas, o);
    fill.dispose();
    if (stroke > 0.05) {
      final s = _tp(Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round
        ..shader = sweep(math.pi - 2 * math.pi * t));
      s.paint(canvas, o);
      s.dispose();
    }
    measure.dispose();
  }

  @override
  bool shouldRepaint(_ShaderTextPainter old) =>
      old.t != t || old.weight != weight || old.stroke != stroke;
}

/// [BpSlider] with presentation-sized label and readout.
class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
    required this.width,
    required this.format,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final double width;
  final String Function(double v) format;

  @override
  Widget build(BuildContext context) {
    void update(Offset p) => onChanged(min + (p.dx / width).clamp(0.0, 1.0) * (max - min));
    final t = ((value - min) / (max - min)).clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: BT.mono(20, color: BP.inkDim)),
        const SizedBox(width: 18),
        SizedBox(
          width: width,
          height: 44,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (d) => update(d.localPosition),
              onPanUpdate: (d) => update(d.localPosition),
              child: CustomPaint(painter: _SliderPainter(t)),
            ),
          ),
        ),
        const SizedBox(width: 18),
        SizedBox(width: 64, child: Text(format(value), style: BT.mono(20, color: BP.amber))),
      ],
    );
  }
}

class _SliderPainter extends CustomPainter {
  _SliderPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final dim = _stroke(BP.lineDim, 1.2);
    canvas.drawLine(Offset(0, y), Offset(size.width, y), dim);
    for (var i = 0; i <= 10; i++) {
      final x = size.width * i / 10;
      final h = i % 5 == 0 ? 10.0 : 5.0;
      canvas.drawLine(Offset(x, y - h), Offset(x, y + h), dim);
    }
    final x = size.width * t;
    canvas.drawLine(Offset(0, y), Offset(x, y), _stroke(BP.line, 2.5));
    final d = Path()
      ..moveTo(x, y - 12)
      ..lineTo(x + 12, y)
      ..lineTo(x, y + 12)
      ..lineTo(x - 12, y)
      ..close();
    canvas.drawPath(d, Paint()..color = BP.paper);
    canvas.drawPath(d, _stroke(BP.amber, 2.5));
  }

  @override
  bool shouldRepaint(_SliderPainter old) => old.t != t;
}

// ─────────────────────────────────────────────────────────────────────────────
// c) widgets in text
// ─────────────────────────────────────────────────────────────────────────────

class _WidgetsTab extends StatefulWidget {
  const _WidgetsTab();

  @override
  State<_WidgetsTab> createState() => _WidgetsTabState();
}

class _WidgetsTabState extends State<_WidgetsTab> with SingleTickerProviderStateMixin {
  static const _pool = ['中文', 'ไทย', 'عربي', 'हिन्दी', '😀'];

  bool _bold = false;
  double _size = 54;
  double _width = 1260;
  bool _fast = false;
  final _chips = <String>['中文'];

  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  void _toggleSpeed() {
    setState(() => _fast = !_fast);
    _spin.duration = Duration(milliseconds: _fast ? 500 : 2400);
    _spin.repeat();
  }

  void _addChip() {
    final next = _pool.firstWhere((c) => !_chips.contains(c), orElse: () => '');
    if (next.isNotEmpty) setState(() => _chips.add(next));
  }

  WidgetSpan _ws(Widget child) => WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: DashedBox(
        color: BP.amber.withValues(alpha: 0.5),
        dash: 3,
        gap: 3,
        padding: const EdgeInsets.all(3),
        child: child,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final em = _size;
    final style = BT.display(em, weight: _bold ? 680 : 360, height: 1.55);
    final canAdd = _chips.length < _pool.length;
    final para = Text.rich(
      TextSpan(
        style: style,
        children: [
          const TextSpan(text: 'The quick '),
          _ws(_Toggle(on: _bold, em: em, onTap: () => setState(() => _bold = !_bold))),
          const TextSpan(text: ' brown fox jumps over '),
          _ws(_MiniSlider(
            value: (_size - 32) / 32,
            em: em,
            onChanged: (v) => setState(() => _size = 32 + 32 * v),
          )),
          const TextSpan(text: ' the lazy dog. Five '),
          _ws(_Spinner(turns: _spin, em: em, fast: _fast, onTap: _toggleSpeed)),
          const TextSpan(text: ' boxing wizards '),
          for (var i = 0; i < _chips.length; i++)
            _ws(_Chip(
              label: _chips[i],
              em: em,
              onTap: () => setState(() => _chips.removeAt(i)),
            )),
          if (canAdd) _ws(_Chip(label: '+', em: em, add: true, onTap: _addChip)),
          const TextSpan(text: ' jump quickly.'),
        ],
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: _width,
          child: Align(alignment: Alignment.centerLeft, child: para),
        ),
        Positioned(
          left: _width - 14,
          top: 0,
          bottom: 0,
          width: 28,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) =>
                  setState(() => _width = (_width + d.delta.dx).clamp(600.0, 1460.0)),
              child: const CustomPaint(painter: _MarginPainter()),
            ),
          ),
        ),
      ],
    );
  }
}

class _MarginPainter extends CustomPainter {
  const _MarginPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    canvas.drawPath(
      dashPath(Path()
        ..moveTo(x, 0)
        ..lineTo(x, size.height)),
      _stroke(BP.amber, 1.4),
    );
    final y = size.height / 2;
    final d = Path()
      ..moveTo(x, y - 13)
      ..lineTo(x + 13, y)
      ..lineTo(x, y + 13)
      ..lineTo(x - 13, y)
      ..close();
    canvas.drawPath(d, Paint()..color = BP.paper);
    canvas.drawPath(d, _stroke(BP.amber, 2.5));
  }

  @override
  bool shouldRepaint(_MarginPainter old) => false;
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.on, required this.em, required this.onTap});

  final bool on;
  final double em;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: em * 1.5,
          height: em * 0.82,
          padding: EdgeInsets.all(em * 0.1),
          decoration: BoxDecoration(
            color: on ? BP.amber : BP.panel,
            border: Border.all(color: on ? BP.amber : BP.line, width: 1.5),
            borderRadius: BorderRadius.circular(em),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: em * 0.58,
              height: em * 0.58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? BP.paper : BP.line,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniSlider extends StatefulWidget {
  const _MiniSlider({required this.value, required this.em, required this.onChanged});

  final double value;
  final double em;
  final ValueChanged<double> onChanged;

  @override
  State<_MiniSlider> createState() => _MiniSliderState();
}

class _MiniSliderState extends State<_MiniSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final w = widget.em * 3.2;
    final h = widget.em * 0.8;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => _drag = widget.value,
        onHorizontalDragUpdate: (d) {
          _drag = ((_drag ?? widget.value) + d.delta.dx / w).clamp(0.0, 1.0);
          widget.onChanged(_drag!);
        },
        onHorizontalDragEnd: (_) => _drag = null,
        onTapUp: (d) => widget.onChanged((d.localPosition.dx / w).clamp(0.0, 1.0)),
        child: CustomPaint(size: Size(w, h), painter: _MiniSliderPainter(widget.value)),
      ),
    );
  }
}

class _MiniSliderPainter extends CustomPainter {
  _MiniSliderPainter(this.v);

  final double v;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final pad = size.height * 0.4;
    final x0 = pad;
    final x1 = size.width - pad;
    canvas.drawLine(Offset(x0, y), Offset(x1, y), _stroke(BP.lineDim, 1.5));
    for (var i = 0; i <= 8; i++) {
      final x = _lerp(x0, x1, i / 8);
      final h = i % 4 == 0 ? size.height * 0.22 : size.height * 0.1;
      canvas.drawLine(Offset(x, y - h), Offset(x, y + h), _stroke(BP.lineDim));
    }
    final x = _lerp(x0, x1, v);
    canvas.drawLine(Offset(x0, y), Offset(x, y), _stroke(BP.line, 2.5));
    final s = size.height * 0.34;
    final d = Path()
      ..moveTo(x, y - s)
      ..lineTo(x + s, y)
      ..lineTo(x, y + s)
      ..lineTo(x - s, y)
      ..close();
    canvas.drawPath(d, Paint()..color = BP.paper);
    canvas.drawPath(d, _stroke(BP.amber, 2));
  }

  @override
  bool shouldRepaint(_MiniSliderPainter old) => old.v != v;
}

class _Spinner extends StatelessWidget {
  const _Spinner({required this.turns, required this.em, required this.fast, required this.onTap});

  final Animation<double> turns;
  final double em;
  final bool fast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: RotationTransition(
          turns: turns,
          child: Icon(Icons.settings, size: em * 0.9, color: fast ? BP.amber : BP.line),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.em, required this.onTap, this.add = false});

  final String label;
  final double em;
  final VoidCallback onTap;
  final bool add;

  @override
  Widget build(BuildContext context) {
    final c = add ? BP.green : BP.violet;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: em * 0.28, vertical: em * 0.06),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.14),
            border: Border.all(color: c),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: BT.sample(em * 0.55, color: add ? BP.green : BP.ink)),
              if (!add) ...[
                SizedBox(width: em * 0.18),
                Text('×', style: BT.mono(em * 0.45, color: BP.inkDim)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// d) every glyph: per-grapheme springs, sliced from the real paragraph
// ─────────────────────────────────────────────────────────────────────────────

class _Particle {
  Offset p = Offset.zero;
  Offset v = Offset.zero;
  double a = 0;
  double w = 0;
}

class _GlyphTab extends StatefulWidget {
  const _GlyphTab();

  @override
  State<_GlyphTab> createState() => _GlyphTabState();
}

class _GlyphTabState extends State<_GlyphTab> with SingleTickerProviderStateMixin {
  static const _maxW = 1472.0 - 140;

  late final _ctrl = TextEditingController(text: 'Glyphs نص');
  TextProbe? _probe;
  var _homes = <Rect>[];
  var _blank = <bool>[];
  final _parts = <_Particle>[];
  final _rng = math.Random(11);
  Offset? _mouse;
  Size _area = const Size(1472, 520);

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _time = 0;
  double _boom = -10;

  @override
  void initState() {
    super.initState();
    _relayout();
    _ticker = createTicker(_tick)..start();
    PaintingBinding.instance.systemFonts.addListener(_onFonts);
  }

  void _onFonts() {
    if (mounted) setState(_relayout);
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_onFonts);
    _ticker.dispose();
    _ctrl.dispose();
    _probe?.dispose();
    super.dispose();
  }

  void _relayout() {
    _probe?.dispose();
    final text = _ctrl.text.isEmpty ? ' ' : _ctrl.text;
    TextProbe make(double size) =>
        TextProbe(TextSpan(text: text, style: BT.sample(size, weight: 500)));
    var p = make(190);
    if (p.size.width > _maxW) {
      final size = 190 * _maxW / p.size.width;
      p.dispose();
      p = make(size);
    }
    _probe = p;
    final g = p.graphemes();
    _homes = [for (final (s, e) in g) p.rectFor(s, e) ?? Rect.zero];
    _blank = [for (final (s, e) in g) text.substring(s, e).trim().isEmpty];
    while (_parts.length < _homes.length) {
      _parts.add(_Particle());
    }
    if (_parts.length > _homes.length) _parts.removeRange(_homes.length, _parts.length);
  }

  Offset get _origin => Offset(
    (_area.width - _probe!.size.width) / 2,
    (_area.height - _probe!.size.height) / 2,
  );

  void _tick(Duration d) {
    final dt = ((d - _last).inMicroseconds / 1e6).clamp(0.0, 1 / 30);
    _last = d;
    _time += dt;
    final o = _origin;
    final since = _time - _boom;
    final k = 110.0 * (since < 1 ? math.max(0.03, since * since) : 1.0);
    const c = 8.0;
    final m = _mouse;
    for (var i = 0; i < _parts.length; i++) {
      final q = _parts[i];
      final target = Offset(0, 6 * math.sin(_time * 2.4 - i * 0.55));
      var acc = (target - q.p) * k - q.v * c;
      var torque = -q.a * k * 0.7 - q.w * c * 0.7;
      if (m != null) {
        final d = o + _homes[i].center + q.p - m;
        final dist = d.distance;
        const r = 190.0;
        if (dist < r && dist > 0.001) {
          final f = 1 - dist / r;
          acc += d / dist * (f * f * 14000);
          torque += d.dx / dist * f * 30;
        }
      }
      q.v += acc * dt;
      q.p += q.v * dt;
      q.w += torque * dt;
      q.a += q.w * dt;
    }
    setState(() {});
  }

  void _explode(Offset at) {
    _boom = _time;
    final o = _origin;
    for (var i = 0; i < _parts.length; i++) {
      final q = _parts[i];
      var d = o + _homes[i].center + q.p - at;
      if (d.distance < 1) d = Offset(_rng.nextDouble() - 0.5, _rng.nextDouble() - 0.5);
      final dir = d / d.distance;
      final jitter = Offset(_rng.nextDouble() * 2 - 1, _rng.nextDouble() * 2 - 1) * 0.6;
      q.v += (dir + jitter) * (900 + _rng.nextDouble() * 900);
      q.w += (_rng.nextDouble() * 2 - 1) * 18;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BpTextField(
          controller: _ctrl,
          width: 520,
          style: BT.sample(34),
          onChanged: (_) => setState(_relayout),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              _area = box.biggest;
              return MouseRegion(
                cursor: SystemMouseCursors.precise,
                onHover: (e) => _mouse = e.localPosition,
                onExit: (_) => _mouse = null,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _explode(d.localPosition),
                  child: CustomPaint(
                    size: box.biggest,
                    painter: _GlyphPainter(
                      probe: _probe!,
                      homes: _homes,
                      blank: _blank,
                      parts: _parts,
                      origin: _origin,
                      mouse: _mouse,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter({
    required this.probe,
    required this.homes,
    required this.blank,
    required this.parts,
    required this.origin,
    required this.mouse,
  });

  final TextProbe probe;
  final List<Rect> homes;
  final List<bool> blank;
  final List<_Particle> parts;
  final Offset origin;
  final Offset? mouse;

  @override
  void paint(Canvas canvas, Size size) {
    final lines = probe.lines;
    if (lines.isEmpty) return;
    final l0 = lines.first;
    final baseY = origin.dy + l0.baseline;
    canvas.drawPath(
      dashPath(Path()
        ..moveTo(40, baseY)
        ..lineTo(size.width - 40, baseY), dash: 8, gap: 6),
      _stroke(BP.lineDim),
    );
    final top = origin.dy;
    final bottom = origin.dy + probe.size.height;

    // Home slots and rubber bands.
    final slot = _stroke(BP.lineFaint);
    final band = _stroke(BP.lineDim.withValues(alpha: 0.7));
    for (var i = 0; i < homes.length; i++) {
      if (blank[i]) continue;
      final r = homes[i].shift(origin);
      canvas.drawPath(dashPath(Path()..addRect(r), dash: 4, gap: 4), slot);
      final q = parts[i];
      if (q.p.distance > 3) {
        canvas.drawLine(r.center, r.center + q.p, band);
        canvas.drawCircle(r.center, 2.5, Paint()..color = BP.lineDim);
      }
    }

    // Each grapheme: a slice of the real paragraph, moved and rotated.
    for (var i = 0; i < homes.length; i++) {
      if (blank[i]) continue;
      final r = homes[i].shift(origin);
      final q = parts[i];
      final clip = Rect.fromLTRB(r.left, top - 30, r.right, bottom + 30);
      final heat = (q.p.distance / 140).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(r.center.dx + q.p.dx, r.center.dy + q.p.dy);
      canvas.rotate(q.a);
      canvas.translate(-r.center.dx, -r.center.dy);
      canvas.clipRect(clip);
      if (heat > 0.02) {
        canvas.saveLayer(
          clip,
          Paint()
            ..colorFilter = ColorFilter.mode(Color.lerp(BP.ink, BP.amber, heat)!, BlendMode.srcIn),
        );
        probe.paint(canvas, origin);
        canvas.restore();
      } else {
        probe.paint(canvas, origin);
      }
      canvas.restore();
    }

    final m = mouse;
    if (m != null) {
      canvas.drawPath(
        dashPath(Path()..addOval(Rect.fromCircle(center: m, radius: 190)), dash: 5, gap: 7),
        _stroke(BP.lineFaint),
      );
      final c = _stroke(BP.amber, 1.2);
      canvas.drawLine(m - const Offset(10, 0), m + const Offset(10, 0), c);
      canvas.drawLine(m - const Offset(0, 10), m + const Offset(0, 10), c);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// e) 3D: a live Text under a perspective transform (no relayout)
// ─────────────────────────────────────────────────────────────────────────────

const _card3DWidth = 980.0;
const _perspective = 0.001;

class _ThreeDTab extends StatefulWidget {
  const _ThreeDTab();

  @override
  State<_ThreeDTab> createState() => _ThreeDTabState();
}

class _ThreeDTabState extends State<_ThreeDTab> with SingleTickerProviderStateMixin {
  final _angles = ValueNotifier<Offset>(const Offset(-0.12, 0.45));
  final _alt = ValueNotifier<bool>(false);

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _time = 0;
  double _rx = -0.12;
  double _ry = 0.45;
  double _vx = 0;
  double _vy = 0;
  bool _drag = false;

  /// Built once, so rotating never rebuilds (or relays out) the text.
  late final Widget _card = _Card3D(alt: _alt);

  static double _wrap(double a) => math.atan2(math.sin(a), math.cos(a));

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _angles.dispose();
    _alt.dispose();
    super.dispose();
  }

  void _tick(Duration d) {
    final dt = ((d - _last).inMicroseconds / 1e6).clamp(0.0, 1 / 30);
    _last = d;
    _time += dt;
    if (!_drag) {
      final ox = -0.12 + 0.1 * math.sin(_time * 0.43);
      final oy = 0.5 * math.sin(_time * 0.55);
      const k = 2.2;
      const c = 1.3;
      _vx += (k * _wrap(ox - _rx) - c * _vx) * dt;
      _vy += (k * _wrap(oy - _ry) - c * _vy) * dt;
      _rx = _wrap(_rx + _vx * dt);
      _ry = _wrap(_ry + _vy * dt);
    }
    _angles.value = Offset(_rx, _ry);
  }

  static String _deg(double r) => '${(r * 180 / math.pi).round()}°'.padLeft(4);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: MouseRegion(
            cursor: _drag ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => setState(() {
                _drag = true;
                _vx = 0;
                _vy = 0;
              }),
              onPanUpdate: (d) {
                _ry = _wrap(_ry + d.delta.dx * 0.009);
                _rx = (_rx - d.delta.dy * 0.009).clamp(-1.3, 1.3);
                _angles.value = Offset(_rx, _ry);
              },
              onPanEnd: (d) => setState(() {
                _drag = false;
                _vy = (d.velocity.pixelsPerSecond.dx * 0.009).clamp(-14.0, 14.0);
                _vx = (-d.velocity.pixelsPerSecond.dy * 0.009).clamp(-6.0, 6.0);
              }),
              child: ClipRect(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _angles,
                    child: _card,
                    builder: (context, child) {
                      final a = _angles.value;
                      // Perspective grows the near side; shift back so the
                      // projected card stays centred.
                      const half = _card3DWidth / 2;
                      final c = half * math.cos(a.dy);
                      final z = _perspective * half * math.sin(a.dy);
                      final shift = (c / (1 - z) - c / (1 + z)) / 2;
                      return Transform.translate(
                        offset: Offset(-shift, 0),
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, _perspective)
                            ..rotateX(a.dx)
                            ..rotateY(a.dy),
                          child: child,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            AnimatedBuilder(
              animation: _angles,
              builder: (context, _) => Text(
                'rotateX ${_deg(_angles.value.dx)}    rotateY ${_deg(_angles.value.dy)}',
                style: BT.mono(20, color: BP.amber),
              ),
            ),
            const Spacer(),
            BpButton(label: 'edit text', size: 20, onTap: () => _alt.value = !_alt.value),
          ],
        ),
      ],
    );
  }
}

class _Card3D extends StatelessWidget {
  const _Card3D({required this.alt});

  final ValueNotifier<bool> alt;

  @override
  Widget build(BuildContext context) {
    final big = BT.display(210, weight: 600, height: 1.0);
    final probe = TextProbe(TextSpan(text: 'Text', style: big));
    final lm = probe.lines.first;
    final metrics = (lm.baseline, lm.ascent, lm.descent);
    probe.dispose();
    return BpPanel(
      width: _card3DWidth,
      height: 400,
      color: BP.line,
      padding: const EdgeInsets.fromLTRB(56, 40, 56, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomPaint(
            painter: _GuidesPainter(metrics),
            child: Text('Text', style: big),
          ),
          const SizedBox(height: 18),
          ValueListenableBuilder<bool>(
            valueListenable: alt,
            builder: (context, a, _) => Text(
              a ? 'نص · 文字 · ข้อความ · 🙂' : 'نص · 文字 · ข้อความ',
              style: BT.sample(56, color: BP.inkDim),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuidesPainter extends CustomPainter {
  _GuidesPainter(this.m);

  /// (baseline, ascent, descent)
  final (double, double, double) m;

  @override
  void paint(Canvas canvas, Size size) {
    final (base, asc, desc) = m;
    const x0 = -32.0;
    const x1 = _card3DWidth - 56 - 24;
    canvas.drawLine(Offset(x0, base), Offset(x1, base), _stroke(BP.amber, 1.6));
    final g = _stroke(BP.lineDim, 1.2);
    for (final y in [base - asc, base + desc]) {
      canvas.drawPath(
        dashPath(Path()
          ..moveTo(x0, y)
          ..lineTo(x1, y), dash: 8, gap: 6),
        g,
      );
    }
  }

  @override
  bool shouldRepaint(_GuidesPainter old) => old.m != m;
}
