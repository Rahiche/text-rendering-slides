import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../deck/scripts.dart';
import '../deck/theme.dart';
import '../deck/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Content
// ─────────────────────────────────────────────────────────────────────────────

class _Frag {
  const _Frag(this.name, this.text, this.script);

  final String name;
  final String text;
  final Script script;
}

const _frags = [
  _Frag('arabic', 'مرحبا', Script.arabic),
  _Frag('hebrew', 'שלום', Script.hebrew),
  _Frag('devanagari', 'नमस्ते', Script.devanagari),
  _Frag('thai', 'สวัสดี', Script.thai),
  _Frag('japanese', 'こんにちは世界', Script.kana),
  _Frag('emoji', '👋🏽🌍', Script.emoji),
];

const _fontSize = 52.0;
const _paraOrigin = Offset(36, 70);
const _panelW = 944.0;
const _panelH = 556.0;
const _minWrap = 480.0;
const _maxWrap = _panelW - 2 * 36;

TextStyle get _paraStyle => BT.sample(_fontSize, height: 2.0);

String _sample(Script s) => switch (s) {
  Script.latin => 'Aa',
  Script.arabic => 'ع',
  Script.hebrew => 'ש',
  Script.devanagari => 'क',
  Script.thai => 'ก',
  Script.han => '字',
  Script.kana => 'あ',
  Script.hangul => '한',
  Script.cyrillic => 'Ж',
  Script.greek => 'Ω',
  Script.emoji => '😀',
  Script.common => '·',
};

/// Which HarfBuzz shaper a script goes through.
String _shaper(Script s) => switch (s) {
  Script.arabic => 'arabic',
  Script.hebrew => 'hebrew',
  Script.devanagari => 'indic',
  Script.thai => 'thai',
  Script.hangul => 'hangul',
  _ => 'default',
};

/// Which line-break machinery a script needs on top of plain UAX #14.
String _breaker(Script s) => switch (s) {
  Script.thai => 'dictionary',
  Script.han || Script.kana => 'CJK',
  _ => 'UAX #14',
};

// ─────────────────────────────────────────────────────────────────────────────
// Gauges, all derived from itemize()
// ─────────────────────────────────────────────────────────────────────────────

class _GCell {
  const _GCell(this.glyph, this.color, this.desc);

  final String glyph;
  final Color color;
  final String desc;
}

class _Gauge {
  const _Gauge(this.label, this.cells);

  final String label;
  final List<_GCell> cells;

  int get value => cells.length;
}

List<_Gauge> _gauges(List<ScriptRun> runs) {
  final real = runs.where((r) => r.script != Script.common).toList();
  final rtl = real.any((r) => r.rtl);
  final fonts = <String, _GCell>{};
  final shapers = <String, _GCell>{};
  final breakers = <String, _GCell>{};
  for (final r in real) {
    final s = r.script;
    fonts.putIfAbsent(s.font, () => _GCell(_sample(s), s.color, s.font));
    final sh = _shaper(s);
    shapers.putIfAbsent(
      sh,
      () => sh == 'default'
          ? const _GCell('Aa', BP.line, 'HarfBuzz · default shaper')
          : _GCell(_sample(s), s.color, 'HarfBuzz · $sh shaper'),
    );
    final br = _breaker(s);
    breakers.putIfAbsent(
      br,
      () => switch (br) {
        'dictionary' => _GCell('ก', Script.thai.color, 'ICU · Thai dictionary'),
        'CJK' => _GCell('字', Script.han.color, 'ICU · CJK line rules'),
        _ => const _GCell('␣', BP.line, 'ICU · UAX #14 rules'),
      },
    );
  }
  return [
    _Gauge('runs', [
      for (final r in runs)
        _GCell(
          r.text.trim().isEmpty ? '·' : r.text.trim().characters.first,
          r.script.color,
          '${r.script.label} run ${r.rtl ? '←' : '→'}',
        ),
    ]),
    _Gauge('bidi', [
      const _GCell('→', BP.line, 'level 0 · LTR'),
      if (rtl) const _GCell('←', BP.amber, 'level 1 · RTL'),
    ]),
    _Gauge('fonts', fonts.values.toList()),
    _Gauge('shaping', shapers.values.toList()),
    _Gauge('breaks', breakers.values.toList()),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Paragraph layout: real boxes from the engine, grouped per run per line
// ─────────────────────────────────────────────────────────────────────────────

/// One run's stretch on one line, in reading order (x0 → x1).
class _Seg {
  const _Seg({
    required this.run,
    required this.line,
    required this.x0,
    required this.x1,
    required this.y,
    required this.left,
    required this.right,
  });

  final int run;
  final int line;
  final double x0;
  final double x1;
  final double y;
  final double left;
  final double right;
}

class _ParaLayout {
  _ParaLayout._(
    this.probe,
    this.runs,
    this.lines,
    this.segs,
    this.hops,
    this.metric,
    this.segStart,
  );

  final TextProbe probe;
  final List<ScriptRun> runs;
  final List<ui.LineMetrics> lines;
  final List<_Seg> segs;
  final Path hops;
  final ui.PathMetric? metric;
  final List<double> segStart;

  double get walkLen => metric?.length ?? 0;

  static _ParaLayout build(String text, double width) {
    final probe = TextProbe(TextSpan(text: text, style: _paraStyle), maxWidth: width);
    final runs = itemize(text);
    final lines = probe.lines;

    int lineOf(double cy) {
      for (final l in lines) {
        if (cy <= l.baseline + l.descent + 0.5) return l.lineNumber;
      }
      return lines.isEmpty ? 0 : lines.last.lineNumber;
    }

    final segs = <_Seg>[];
    for (var ri = 0; ri < runs.length; ri++) {
      final r = runs[ri];
      final trimmed = r.text.trimRight().length;
      final end = r.start + (trimmed == 0 ? r.text.length : trimmed);
      final byLine = <int, Rect>{};
      for (final b in probe.boxes(r.start, end)) {
        final rect = b.toRect();
        if (rect.width < 0.5) continue;
        byLine.update(lineOf(rect.center.dy), (v) => v.expandToInclude(rect), ifAbsent: () => rect);
      }
      final keys = byLine.keys.toList()..sort();
      for (final k in keys) {
        if (k >= lines.length) continue;
        final rect = byLine[k]!;
        segs.add(
          _Seg(
            run: ri,
            line: k,
            x0: r.rtl ? rect.right : rect.left,
            x1: r.rtl ? rect.left : rect.right,
            y: lines[k].baseline + _fontSize * 0.36,
            left: rect.left,
            right: rect.right,
          ),
        );
      }
    }

    // The reading path: along each segment, hopping between them in logical order.
    double lenOf(Path p) => p.computeMetrics().fold(0.0, (a, m) => a + m.length);
    final walk = Path();
    final hops = Path();
    final segStart = <double>[];
    Offset? prev;
    for (final s in segs) {
      final a = Offset(s.x0, s.y);
      final b = Offset(s.x1, s.y);
      if (prev == null) {
        walk.moveTo(a.dx, a.dy);
      } else {
        final mid = Offset.lerp(prev, a, 0.5)!;
        final sameLine = (a.dy - prev.dy).abs() < 1;
        final c = sameLine
            ? mid + Offset(0, math.min(46, 14 + (a.dx - prev.dx).abs() * 0.1))
            : Offset(mid.dx, prev.dy + 34);
        walk.quadraticBezierTo(c.dx, c.dy, a.dx, a.dy);
        hops
          ..moveTo(prev.dx, prev.dy)
          ..quadraticBezierTo(c.dx, c.dy, a.dx, a.dy);
      }
      segStart.add(lenOf(walk));
      walk.lineTo(b.dx, b.dy);
      prev = b;
    }
    final ms = walk.computeMetrics().toList();
    return _ParaLayout._(probe, runs, lines, segs, hops, ms.isEmpty ? null : ms.first, segStart);
  }

  int segAt(double d) {
    var k = 0;
    for (var i = 0; i < segStart.length; i++) {
      if (segStart[i] <= d) k = i;
    }
    return k;
  }

  void dispose() => probe.dispose();
}

// ─────────────────────────────────────────────────────────────────────────────
// Slide
// ─────────────────────────────────────────────────────────────────────────────

/// One live paragraph; every script you add multiplies the work per stage.
class MixingSlide extends StatefulWidget {
  const MixingSlide({super.key});

  @override
  State<MixingSlide> createState() => _MixingSlideState();
}

class _MixingSlideState extends State<MixingSlide> with SingleTickerProviderStateMixin {
  final _on = <String>{};
  double _wrap = 820;
  String? _desc;
  late _ParaLayout _layout;
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  String get _text => ['Hello', for (final f in _frags) if (_on.contains(f.name)) f.text, 'world'].join(' ');

  @override
  void initState() {
    super.initState();
    _layout = _ParaLayout.build(_text, _wrap);
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
    _intro.forward();
  }

  void _fontsChanged() {
    if (mounted) setState(_relayout);
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    _layout.dispose();
    _intro.dispose();
    super.dispose();
  }

  void _relayout() {
    _layout.dispose();
    _layout = _ParaLayout.build(_text, _wrap);
  }

  void _toggle(String name) {
    setState(() {
      if (!_on.remove(name)) _on.add(name);
      _relayout();
    });
    _intro.forward(from: 0);
  }

  void _all() {
    setState(() {
      if (_on.length == _frags.length) {
        _on.clear();
      } else {
        _on.addAll(_frags.map((f) => f.name));
      }
      _relayout();
    });
    _intro.forward(from: 0);
  }

  void _setWrap(double w) {
    final v = w.clamp(_minWrap, _maxWrap);
    if (v == _wrap) return;
    setState(() {
      _wrap = v;
      _relayout();
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    final gauges = _gauges(_layout.runs);
    final product = gauges.fold<int>(1, (a, g) => a * g.value);
    final periodMs = (_layout.walkLen / 0.24).clamp(2600.0, 11000.0).round();
    return SlideFrame(
      title: 'Mixing multiplies',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Script toggles
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                BpButton(label: 'latin', selected: true, color: Script.latin.color, onTap: null),
                for (final f in _frags)
                  BpButton(
                    label: '+ ${f.name}',
                    selected: _on.contains(f.name),
                    color: f.script.color,
                    onTap: () => _toggle(f.name),
                  ),
                const SizedBox(width: 18),
                BpButton(
                  label: _on.length == _frags.length ? 'reset' : 'all',
                  color: BP.inkDim,
                  onTap: _all,
                ),
              ],
            ),
          ),

          LoopBuilder(
            key: ValueKey(text),
            period: Duration(milliseconds: periodMs),
            builder: (context, t, _) {
              final L = _layout;
              final d = L.walkLen * t;
              final curRun = L.segs.isEmpty ? -1 : L.segs[L.segAt(d)].run;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Paragraph
                  Positioned(
                    left: 0,
                    top: 72,
                    width: _panelW,
                    height: _panelH,
                    child: BpPanel(
                      label: 'one paragraph',
                      padding: EdgeInsets.zero,
                      child: SizedBox.expand(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: _paraOrigin.dx,
                              top: _paraOrigin.dy,
                              right: 0,
                              bottom: 0,
                              child: CustomPaint(
                                painter: _ParaPainter(
                                  layout: L,
                                  t: t,
                                  intro: _intro.value,
                                  curRun: curRun,
                                  wrap: _wrap,
                                ),
                              ),
                            ),
                            Positioned(
                              left: _paraOrigin.dx + _wrap - 16,
                              top: 0,
                              bottom: 0,
                              width: 32,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.resizeLeftRight,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onHorizontalDragUpdate: (e) => _setWrap(_wrap + e.delta.dx),
                                  child: CustomPaint(painter: _HandlePainter(_wrap)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Gauges
                  Positioned(
                    left: _panelW + 40,
                    top: 72,
                    right: 0,
                    height: _panelH,
                    child: BpPanel(
                      label: 'pipeline',
                      padding: const EdgeInsets.fromLTRB(24, 30, 24, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final g in gauges)
                            _GaugeRow(
                              gauge: g,
                              hot: g.label == 'runs' ? curRun : null,
                              onHover: (s) => setState(() => _desc = s),
                            ),
                          const SizedBox(height: 12),
                          Container(height: 1, color: BP.lineDim),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 96,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.bottomLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text('×', style: BT.display(54, color: BP.amber)),
                                  const SizedBox(width: 6),
                                  AnimatedCount(
                                    value: product,
                                    duration: const Duration(milliseconds: 700),
                                    style: BT.display(80, color: BP.amber, weight: 600, letterSpacing: -2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 250),
                                  layoutBuilder: (cur, prev) => Stack(
                                    alignment: Alignment.centerLeft,
                                    children: [...prev, ?cur],
                                  ),
                                  child: Text(
                                    gauges.map((g) => g.value).join(' × '),
                                    key: ValueKey(product),
                                    maxLines: 1,
                                    overflow: TextOverflow.fade,
                                    softWrap: false,
                                    style: BT.mono(15, color: BP.inkFaint),
                                  ),
                                ),
                              ),
                              Text('combinations', style: BT.mono(14, color: BP.inkDim)),
                            ],
                          ),
                          const Spacer(),
                          SizedBox(
                            height: 20,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: Text(
                                _desc ?? '',
                                key: ValueKey(_desc),
                                style: BT.mono(14, color: BP.amber),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gauge row
// ─────────────────────────────────────────────────────────────────────────────

class _GaugeRow extends StatelessWidget {
  const _GaugeRow({required this.gauge, required this.hot, required this.onHover});

  final _Gauge gauge;
  final int? hot;
  final ValueChanged<String?> onHover;

  @override
  Widget build(BuildContext context) {
    final cells = gauge.cells;
    return SizedBox(
      height: 60,
      child: Row(
        children: [
          SizedBox(width: 92, child: Text(gauge.label, style: BT.mono(15, color: BP.inkDim))),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                const gap = 5.0;
                final n = math.max(cells.length, 1);
                final size = math.min(40.0, (box.maxWidth - n * gap) / n);
                return Row(
                  children: [
                    for (var i = 0; i < cells.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: gap),
                        child: MouseRegion(
                          onEnter: (_) => onHover(cells[i].desc),
                          onExit: (_) => onHover(null),
                          child: _PopCell(
                            key: ValueKey('${cells[i].glyph}|${cells[i].desc}|$i'),
                            cell: cells[i],
                            size: size,
                            hot: hot == i,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          SizedBox(
            width: 48,
            child: Align(
              alignment: Alignment.centerRight,
              child: AnimatedCount(
                value: gauge.value,
                duration: const Duration(milliseconds: 400),
                style: BT.display(32, color: BP.ink, weight: 500),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A gauge cell that pops in when it first appears.
class _PopCell extends StatefulWidget {
  const _PopCell({super.key, required this.cell, required this.size, required this.hot});

  final _GCell cell;
  final double size;
  final bool hot;

  @override
  State<_PopCell> createState() => _PopCellState();
}

class _PopCellState extends State<_PopCell> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cell.color;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.scale(
        scale: Curves.easeOutBack.transform(_c.value),
        child: child,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: widget.size,
        height: widget.size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: (widget.hot ? BP.amber : c).withValues(alpha: widget.hot ? 0.22 : 0.13),
          border: Border.all(color: widget.hot ? BP.amber : c, width: widget.hot ? 2 : 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(widget.cell.glyph, style: BT.sample(widget.size * 0.5, color: BP.ink, height: 1.1)),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painters
// ─────────────────────────────────────────────────────────────────────────────

class _ParaPainter extends CustomPainter {
  _ParaPainter({
    required this.layout,
    required this.t,
    required this.intro,
    required this.curRun,
    required this.wrap,
  });

  final _ParaLayout layout;
  final double t;
  final double intro;
  final int curRun;
  final double wrap;

  @override
  void paint(Canvas canvas, Size size) {
    final L = layout;

    // Baselines (real line metrics)
    final base = Paint()
      ..color = BP.lineFaint
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (final l in L.lines) {
      canvas.drawPath(
        dashPath(Path()
          ..moveTo(0, l.baseline)
          ..lineTo(wrap, l.baseline), dash: 6, gap: 5),
        base,
      );
    }

    // Run tints (real boxes, one band per run per line)
    for (final s in L.segs) {
      final color = L.runs[s.run].script.color;
      final l = L.lines[s.line];
      final band = Rect.fromLTRB(s.left, l.baseline - _fontSize * 0.98, s.right, l.baseline + _fontSize * 0.3);
      final hot = s.run == curRun;
      canvas.drawRect(band, Paint()..color = color.withValues(alpha: (hot ? 0.18 : 0.07) * intro));
      if (hot) {
        canvas.drawRect(
          band,
          Paint()
            ..color = BP.amber.withValues(alpha: 0.9 * intro)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    L.probe.paint(canvas, Offset.zero);

    // Hops between runs (logical order), faint.
    canvas.drawPath(
      dashPath(L.hops, dash: 4, gap: 4),
      Paint()
        ..color = BP.amber.withValues(alpha: 0.35 * intro)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );

    // Underlines as arrows in reading direction, drawn on with a stagger.
    final seen = <int>{};
    for (final s in L.segs) {
      final color = L.runs[s.run].script.color;
      final p = (intro * 1.8 - s.run * 0.08).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final e = Curves.easeOutCubic.transform(p);
      final end = ui.lerpDouble(s.x0, s.x1, e)!;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(s.x0, s.y), Offset(end, s.y), paint);
      if (p > 0.9 && (s.x1 - s.x0).abs() > 14) {
        final dir = s.x1 >= s.x0 ? 1.0 : -1.0;
        drawArrowHead(canvas, Offset(s.x1 + dir * 4, s.y), Offset(s.x1 - dir * 6, s.y), paint..strokeWidth = 2.5, 8);
      }
      if (seen.add(s.run)) {
        // Numbered at the run's logical start, nudged inside so neighbours don't collide.
        final o = Offset(s.x0 + (s.x1 >= s.x0 ? 10 : -10), s.y);
        canvas.drawCircle(o, 11 * e, Paint()..color = BP.paper);
        canvas.drawCircle(
          o,
          11 * e,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
        final tp = TextPainter(
          text: TextSpan(text: '${s.run + 1}', style: BT.mono(11, color: color.withValues(alpha: e), weight: 600)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, o - Offset(tp.width / 2, tp.height / 2));
        tp.dispose();
      }
    }

    // The walker: reads the runs in logical order, jumping around visually.
    final m = L.metric;
    if (m != null && m.length > 0) {
      final d = m.length * t;
      for (var k = 1; k <= 7; k++) {
        final tan = m.getTangentForOffset(math.max(0, d - k * 9));
        if (tan == null) break;
        canvas.drawCircle(
          tan.position,
          4.2 - k * 0.5,
          Paint()..color = BP.amber.withValues(alpha: 0.55 - k * 0.07),
        );
      }
      final tan = m.getTangentForOffset(d);
      if (tan != null) {
        final c = tan.position;
        canvas.drawCircle(
          c,
          14,
          Paint()
            ..color = BP.amber.withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
        );
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - 8)
            ..lineTo(c.dx + 8, c.dy)
            ..lineTo(c.dx, c.dy + 8)
            ..lineTo(c.dx - 8, c.dy)
            ..close(),
          Paint()..color = BP.amber,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ParaPainter old) =>
      old.t != t || old.intro != intro || old.layout != layout || old.curRun != curRun || old.wrap != wrap;
}

/// The paragraph's max width: a dashed limit line with a draggable diamond.
class _HandlePainter extends CustomPainter {
  _HandlePainter(this.wrap);

  final double wrap;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    canvas.drawPath(
      dashPath(Path()
        ..moveTo(x, 40)
        ..lineTo(x, size.height - 24), dash: 6, gap: 5),
      Paint()
        ..color = BP.amber.withValues(alpha: 0.8)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
    const y = 30.0;
    final d = Path()
      ..moveTo(x, y - 9)
      ..lineTo(x + 9, y)
      ..lineTo(x, y + 9)
      ..lineTo(x - 9, y)
      ..close();
    canvas.drawPath(d, Paint()..color = BP.paper);
    canvas.drawPath(
      d,
      Paint()
        ..color = BP.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final tp = TextPainter(
      text: TextSpan(text: 'width ${wrap.round()}', style: BT.mono(12, color: BP.amber)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x - tp.width - 14, y - tp.height / 2));
    tp.dispose();
  }

  @override
  bool shouldRepaint(_HandlePainter old) => old.wrap != wrap;
}
