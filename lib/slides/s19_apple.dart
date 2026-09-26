import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../deck/scripts.dart';
import '../deck/theme.dart';
import '../deck/widgets.dart';

/// macOS / iOS: Core Text's object model drawn over a real paragraph,
/// plus SF Pro's automatic size-specific tracking.
class AppleSlide extends StatelessWidget {
  const AppleSlide({super.key});

  @override
  Widget build(BuildContext context) => const SlideFrame(
    title: 'macOS · Core Text',
    child: _EngineLayout(
      hero: _AppleHero(),
      layers: [
        _Layer('SwiftUI / TextKit 2', 'NSTextLayoutManager'),
        _Layer('Core Text', 'CTFramesetter → CTLine → CTRun'),
        _Layer('Core Graphics', 'glyph rasterization'),
        _Layer('Core Animation', 'layers · compositing'),
      ],
      caps: [
        _Cap('own shaper (AAT + OpenType)'),
        _Cap('vertical', _K.yes),
        _Cap('ruby', _K.yes),
        _Cap('hyphenation', _K.yes),
        _Cap('subpixel AA off since 10.14'),
      ],
    ),
  );
}

class _AppleHero extends StatelessWidget {
  const _AppleHero();

  @override
  Widget build(BuildContext context) => const Stack(
    children: [
      Positioned(left: 0, top: 0, right: 0, height: 376, child: _CoreTextPanel()),
      Positioned(left: 0, top: 402, right: 0, bottom: 0, child: _TrackingPanel()),
    ],
  );
}

TextPainter _tp(String s, TextStyle style) =>
    TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();

Path _rectPath(Rect r) => Path()..addRect(r);

// ─────────────────────────────────────────────────────────────────────────────
// CTFrame › CTLine › CTRun › CGGlyph over real layout data
// ─────────────────────────────────────────────────────────────────────────────

const _levelNames = ['CTFrame', 'CTLine', 'CTRun', 'CGGlyph'];
const _levelColors = [BP.inkDim, BP.violet, BP.line, BP.coral];
const _dash = [(10.0, 5.0), (7.0, 4.0), (5.0, 3.0), (3.0, 2.5)];

class _RunBox {
  const _RunBox(this.rect, this.script, this.line);

  final Rect rect;
  final Script script;
  final int line;
}

class _GlyphBox {
  const _GlyphBox(this.rect, this.text);

  final Rect rect;
  final String text;
}

/// Nested rectangles for the four levels, measured from the real paragraph.
class _Geo {
  _Geo(this.frame, this.lines, this.runs, this.glyphs)
    : framePath = _dashed(frame, 0),
      linePaths = [for (final r in lines) _dashed(r, 1)],
      runPaths = [for (final r in runs) _dashed(r.rect, 2)],
      glyphPath = glyphs.fold(Path(), (p, g) => p..addPath(_dashed(g.rect, 3), Offset.zero));

  final Rect frame;
  final List<Rect> lines;
  final List<_RunBox> runs;
  final List<_GlyphBox> glyphs;
  final Path framePath;
  final List<Path> linePaths;
  final List<Path> runPaths;
  final Path glyphPath;

  static Path _dashed(Rect r, int level) =>
      dashPath(_rectPath(r), dash: _dash[level].$1, gap: _dash[level].$2);

  static _Geo measure(TextProbe p, double fs, double maxWidth) {
    final lm = p.lines;
    final text = p.text;
    final runs = itemize(text);
    final glyphs = <_GlyphBox>[];
    final perRun = <(int, int), Rect>{};
    for (final (s, e) in p.graphemes()) {
      final ch = text.substring(s, e);
      if (ch.trim().isEmpty) continue;
      final bs = p.boxes(s, e);
      if (bs.isEmpty) continue;
      final r = bs.map((b) => b.toRect()).reduce((a, b) => a.expandToInclude(b));
      if (r.width < 0.5) continue;
      var li = 0;
      var best = double.infinity;
      for (var k = 0; k < lm.length; k++) {
        final d = (r.center.dy - (lm[k].baseline - fs * 0.3)).abs();
        if (d < best) {
          best = d;
          li = k;
        }
      }
      final b = lm[li].baseline;
      final g = Rect.fromLTRB(r.left + 0.5, b - fs * 0.78, r.right - 0.5, b + fs * 0.24);
      glyphs.add(_GlyphBox(g, ch));
      final ri = runs.indexWhere((x) => s >= x.start && s < x.end);
      if (ri < 0) continue;
      final key = (li, ri);
      perRun[key] = perRun[key]?.expandToInclude(g) ?? g;
    }
    final runBoxes = [
      for (final e in perRun.entries)
        _RunBox(e.value.inflate(5), runs[e.key.$2].script, e.key.$1),
    ];
    final lines = <Rect>[];
    for (var k = 0; k < lm.length; k++) {
      final b = lm[k].baseline;
      var r = Rect.fromLTRB(lm[k].left, b - fs * 0.78 - 5, lm[k].left + lm[k].width, b + fs * 0.24 + 5);
      for (final rb in runBoxes) {
        if (rb.line == k) r = r.expandToInclude(rb.rect);
      }
      lines.add(Rect.fromLTRB(r.left - 7, r.top - 4, r.right + 7, r.bottom + 4));
    }
    var frame = Rect.fromLTWH(0, 0, maxWidth, p.size.height);
    for (final l in lines) {
      frame = frame.expandToInclude(l);
    }
    return _Geo(frame.inflate(12), lines, runBoxes, glyphs);
  }
}

class _CoreTextPanel extends StatefulWidget {
  const _CoreTextPanel();

  @override
  State<_CoreTextPanel> createState() => _CoreTextPanelState();
}

class _CoreTextPanelState extends State<_CoreTextPanel> with TickerProviderStateMixin {
  static const _text =
      'Core Text splits a paragraph into lines, lines into runs: Latin, then '
      'العربية من اليمين إلى اليسار then Latin again, and runs into glyphs.';
  static const _fs = 30.0;
  static const _maxW = 800.0;

  late final List<AnimationController> _lv = [
    for (var i = 0; i < 4; i++)
      AnimationController(vsync: this, duration: const Duration(milliseconds: 750)),
  ];
  late final AnimationController _walk = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  )..repeat();
  final _on = [true, true, true, true];
  final _timers = <Timer>[];
  late TextProbe _probe;
  late _Geo _geo;
  (int, int)? _hover;

  @override
  void initState() {
    super.initState();
    _measure();
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
    for (var k = 0; k < 4; k++) {
      _timers.add(Timer(Duration(milliseconds: 400 + 800 * k), () {
        if (mounted && _on[k]) _lv[k].forward();
      }));
    }
  }

  void _measure() {
    _probe = TextProbe(
      TextSpan(text: _text, style: BT.sample(_fs, height: 1.7)),
      maxWidth: _maxW,
    );
    _geo = _Geo.measure(_probe, _fs, _maxW);
  }

  void _fontsChanged() {
    if (!mounted) return;
    setState(() {
      _probe.dispose();
      _measure();
      _hover = null;
    });
  }

  void _toggle(int k) {
    setState(() => _on[k] = !_on[k]);
    _on[k] ? _lv[k].forward() : _lv[k].reverse();
  }

  void _onHover(Offset p) {
    (int, int)? hit;
    final g = _geo;
    if (_lv[3].value > 0.5) {
      for (var i = 0; i < g.glyphs.length && hit == null; i++) {
        if (g.glyphs[i].rect.contains(p)) hit = (3, i);
      }
    }
    if (hit == null && _lv[2].value > 0.5) {
      for (var i = 0; i < g.runs.length && hit == null; i++) {
        if (g.runs[i].rect.contains(p)) hit = (2, i);
      }
    }
    if (hit == null && _lv[1].value > 0.5) {
      for (var i = 0; i < g.lines.length && hit == null; i++) {
        if (g.lines[i].contains(p)) hit = (1, i);
      }
    }
    if (hit == null && _lv[0].value > 0.5 && g.frame.contains(p)) hit = (0, 0);
    if (hit != _hover) setState(() => _hover = hit);
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    for (final t in _timers) {
      t.cancel();
    }
    for (final c in _lv) {
      c.dispose();
    }
    _walk.dispose();
    _probe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BpPanel(
      label: 'CTFramesetter',
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var k = 0; k < 4; k++) ...[
                BpButton(
                  label: _levelNames[k],
                  color: _levelColors[k],
                  selected: _on[k],
                  size: 14,
                  onTap: () => _toggle(k),
                ),
                if (k < 3)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('›', style: BT.mono(18, color: BP.inkFaint)),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final origin = Offset(
                  (box.maxWidth - _maxW) / 2,
                  (box.maxHeight - _probe.size.height) / 2,
                );
                return MouseRegion(
                  onHover: (e) => _onHover(e.localPosition - origin),
                  onExit: (_) => setState(() => _hover = null),
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _CTPainter(
                      probe: _probe,
                      geo: _geo,
                      levels: _lv,
                      walk: _walk,
                      hover: _hover,
                      origin: origin,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CTPainter extends CustomPainter {
  _CTPainter({
    required this.probe,
    required this.geo,
    required this.levels,
    required this.walk,
    required this.hover,
    required this.origin,
  }) : super(repaint: Listenable.merge([...levels, walk]));

  final TextProbe probe;
  final _Geo geo;
  final List<Animation<double>> levels;
  final Animation<double> walk;
  final (int, int)? hover;
  final Offset origin;

  static double _stagger(double t, int j, int n, double spread) {
    if (n <= 1) return t;
    return (t * (1 + spread) - spread * j / (n - 1)).clamp(0.0, 1.0);
  }

  static void _stroke(Canvas canvas, Rect r, Path full, double t, Paint p, int level) {
    if (t <= 0) return;
    if (t >= 1) {
      canvas.drawPath(full, p);
    } else {
      canvas.drawPath(
        dashPath(partialPath(_rectPath(r), t), dash: _dash[level].$1, gap: _dash[level].$2),
        p,
      );
    }
  }

  Rect _rectOf((int, int) h) => switch (h.$1) {
    0 => geo.frame,
    1 => geo.lines[h.$2],
    2 => geo.runs[h.$2].rect,
    _ => geo.glyphs[h.$2].rect,
  };

  String _labelOf((int, int) h) => switch (h.$1) {
    0 => 'CTFrame',
    1 => 'CTLine ${h.$2 + 1}',
    2 => 'CTRun · ${geo.runs[h.$2].script.label} ${geo.runs[h.$2].script.rtl ? '←' : '→'}',
    _ => 'CGGlyph · ${geo.glyphs[h.$2].text}',
  };

  Paint _pen(Color c, double a, double w) => Paint()
    ..color = c.withValues(alpha: a)
    ..style = PaintingStyle.stroke
    ..strokeWidth = w;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    final lv = [for (final c in levels) Curves.easeInOutCubic.transform(c.value)];

    // Run tint (fills go under the text).
    for (final r in geo.runs) {
      canvas.drawRect(r.rect, Paint()..color = r.script.color.withValues(alpha: 0.06 * lv[2]));
    }

    // Walk: glyphs in logical (memory) order; watch it jump inside the Arabic run.
    final gl = geo.glyphs;
    if (lv[3] > 0.01 && gl.isNotEmpty) {
      final pos = walk.value * gl.length;
      final idx = pos.floor() % gl.length;
      for (var k = 4; k >= 0; k--) {
        final i = idx - k;
        if (i < 0) continue;
        final a = (k == 0 ? 0.22 : 0.12 * (1 - k / 5)) * lv[3];
        canvas.drawRect(gl[i].rect, Paint()..color = BP.ink.withValues(alpha: a));
      }
    }

    if (hover != null) {
      canvas.drawRect(_rectOf(hover!), Paint()..color = BP.amber.withValues(alpha: 0.12));
    }

    // Outlines, level by level, drawing on.
    _stroke(canvas, geo.frame, geo.framePath, lv[0], _pen(_levelColors[0], 1, 1.4), 0);
    for (var i = 0; i < geo.lines.length; i++) {
      _stroke(
        canvas,
        geo.lines[i],
        geo.linePaths[i],
        _stagger(lv[1], i, geo.lines.length, 0.6),
        _pen(_levelColors[1], 0.95, 1.3),
        1,
      );
    }
    for (var i = 0; i < geo.runs.length; i++) {
      final r = geo.runs[i];
      final t = _stagger(lv[2], i, geo.runs.length, 0.6);
      _stroke(canvas, r.rect, geo.runPaths[i], t, _pen(r.script.color, 0.95, 1.2), 2);
      // Direction of the run.
      if (t > 0.5) {
        final a = ((t - 0.5) * 2).clamp(0.0, 1.0);
        final y = r.rect.bottom;
        final x0 = r.script.rtl ? r.rect.right - 6 : r.rect.left + 6;
        final x1 = r.script.rtl ? x0 - 22 : x0 + 22;
        final p = Paint()
          ..color = r.script.color.withValues(alpha: a)
          ..strokeWidth = 2;
        canvas.drawLine(Offset(x0, y), Offset(x1, y), p);
        drawArrowHead(canvas, Offset(x1, y), Offset(x0, y), p, 6);
      }
    }
    final gp = _pen(_levelColors[3], 0.85, 1);
    if (lv[3] >= 1) {
      canvas.drawPath(geo.glyphPath, gp);
    } else if (lv[3] > 0) {
      for (var i = 0; i < gl.length; i++) {
        final t = _stagger(lv[3], i, gl.length, 0.8);
        if (t <= 0) continue;
        canvas.drawPath(dashPath(partialPath(_rectPath(gl[i].rect), t), dash: 3, gap: 2.5), gp);
      }
    }

    // The real text.
    probe.paint(canvas, Offset.zero);

    // Frame name tag, always on when the frame is.
    if (lv[0] > 0.3) {
      final tag = _tp('CTFrame', BT.mono(12, color: _levelColors[0].withValues(alpha: lv[0])));
      tag.paint(canvas, Offset(geo.frame.left + 8, geo.frame.top - tag.height - 2));
      tag.dispose();
    }

    // Hover: outline + name chip.
    final h = hover;
    if (h != null) {
      final r = _rectOf(h);
      canvas.drawRect(r, _pen(BP.amber, 1, 2));
      final tp = _tp(_labelOf(h), BT.mono(13, color: BP.paper, weight: 600));
      var o = Offset(r.left, r.top - tp.height - 8);
      if (o.dy < -origin.dy + 2) o = Offset(r.left, r.bottom + 8);
      final chip = Rect.fromLTWH(o.dx - 6, o.dy - 3, tp.width + 12, tp.height + 6);
      canvas.drawRect(chip, Paint()..color = BP.amber);
      tp.paint(canvas, o);
      tp.dispose();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CTPainter old) =>
      old.geo != geo || old.hover != hover || old.origin != origin || old.probe != probe;
}

// ─────────────────────────────────────────────────────────────────────────────
// Optical size & tracking
// ─────────────────────────────────────────────────────────────────────────────

/// Qualitative only: looser at small sizes, tighter at large ones (em units).
double _tracking(double size) => -0.026 + 0.076 * math.exp(-(size - 8) / 9.5);

class _TrackingPanel extends StatefulWidget {
  const _TrackingPanel();

  @override
  State<_TrackingPanel> createState() => _TrackingPanelState();
}

class _TrackingPanelState extends State<_TrackingPanel> with SingleTickerProviderStateMixin {
  static const _min = 8.0;
  static const _max = 96.0;

  double _size = _min;
  bool _sweep = true;
  bool _auto = true;
  double _phase = 0;
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration e) {
    final dt = ((e - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = e;
    if (!_sweep) return;
    _phase = (_phase + dt / 10) % 1.0;
    setState(() => _size = _min + (_max - _min) * (0.5 - 0.5 * math.cos(2 * math.pi * _phase)));
  }

  void _toggleSweep() => setState(() {
    _sweep = !_sweep;
    if (_sweep) {
      final u = ((_size - _min) / (_max - _min)).clamp(0.0, 1.0);
      _phase = math.acos(1 - 2 * u) / (2 * math.pi);
    }
  });

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BpPanel(
      label: 'optical size · tracking',
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 14),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: _auto ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
        builder: (context, blend, _) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 250,
              child: CustomPaint(painter: _CurvePainter(size: _size, blend: blend)),
            ),
            const SizedBox(width: 26),
            SizedBox(
              width: 250,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BpSlider(
                    value: _size,
                    min: _min,
                    max: _max,
                    width: 140,
                    ticks: 11,
                    format: (v) => '${v.round()} pt',
                    onChanged: (v) => setState(() {
                      _sweep = false;
                      _size = v;
                    }),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      BpButton(
                        label: 'auto tracking',
                        size: 13,
                        selected: _auto,
                        onTap: () => setState(() => _auto = !_auto),
                      ),
                      const SizedBox(width: 8),
                      BpButton(label: 'sweep', size: 13, selected: _sweep, onTap: _toggleSweep),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const BpTag('SF Pro · opsz · automatic', color: BP.amber, size: 12),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(width: 118, child: CustomPaint(painter: _AaPainter(_size))),
            const SizedBox(width: 16),
            Expanded(child: CustomPaint(painter: _SamplePainter(size: _size, blend: blend))),
          ],
        ),
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({required this.size, required this.blend});

  final double size;
  final double blend;

  static const _hi = 0.065;
  static const _lo = -0.035;

  @override
  void paint(Canvas canvas, Size box) {
    final plot = Rect.fromLTRB(46, 10, box.width - 6, box.height - 24);
    double xOf(double s) => plot.left + (s - 8) / 88 * plot.width;
    double yOf(double em) => plot.top + (_hi - em) / (_hi - _lo) * plot.height;

    final axis = Paint()
      ..color = BP.lineDim
      ..strokeWidth = 1;
    canvas.drawLine(plot.bottomLeft, plot.topLeft, axis);
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axis);
    drawArrowHead(canvas, plot.bottomRight + const Offset(4, 0), plot.bottomLeft, axis, 6);
    canvas.drawPath(
      dashPath(Path()
        ..moveTo(plot.left, yOf(0))
        ..lineTo(plot.right, yOf(0)), dash: 4, gap: 4),
      Paint()
        ..color = BP.lineFaint
        ..style = PaintingStyle.stroke,
    );

    void label(String s, Offset o, {bool right = false}) {
      final tp = _tp(s, BT.mono(11, color: BP.inkFaint));
      tp.paint(canvas, right ? o - Offset(tp.width, 0) : o);
      tp.dispose();
    }

    label('loose', Offset(0, plot.top));
    label('tight', Offset(0, plot.bottom - 16));
    label('small', Offset(plot.left, plot.bottom + 6));
    label('large', Offset(plot.right, plot.bottom + 6), right: true);

    // Ghost of the real curve when auto tracking is off.
    Path curve(double k) {
      final p = Path()..moveTo(xOf(8), yOf(_tracking(8) * k));
      for (var s = 9.0; s <= 96; s += 1) {
        p.lineTo(xOf(s), yOf(_tracking(s) * k));
      }
      return p;
    }

    if (blend < 0.99) {
      canvas.drawPath(
        dashPath(curve(1), dash: 3, gap: 4),
        Paint()
          ..color = BP.line.withValues(alpha: 0.35 * (1 - blend))
          ..style = PaintingStyle.stroke,
      );
    }
    canvas.drawPath(
      curve(blend),
      Paint()
        ..color = Color.lerp(BP.inkDim, BP.line, blend)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final dot = Offset(xOf(size), yOf(_tracking(size) * blend));
    canvas.drawPath(
      dashPath(Path()
        ..moveTo(dot.dx, dot.dy)
        ..lineTo(dot.dx, plot.bottom), dash: 3, gap: 3),
      Paint()
        ..color = BP.amber.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke,
    );
    canvas.drawCircle(dot, 9, Paint()..color = BP.amber.withValues(alpha: 0.18));
    canvas.drawCircle(dot, 5, Paint()..color = BP.amber);
  }

  @override
  bool shouldRepaint(_CurvePainter old) => old.size != size || old.blend != blend;
}

/// "Aa" at the actual size, in its em square.
class _AaPainter extends CustomPainter {
  _AaPainter(this.size);

  final double size;

  @override
  void paint(Canvas canvas, Size box) {
    final c = box.center(Offset.zero);
    final em = Rect.fromCenter(center: c, width: size, height: size);
    canvas.drawPath(
      dashPath(_rectPath(em), dash: 4, gap: 3),
      Paint()
        ..color = BP.lineDim
        ..style = PaintingStyle.stroke,
    );
    final tp = _tp('Aa', BT.display(size, weight: 500));
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }

  @override
  bool shouldRepaint(_AaPainter old) => old.size != size;
}

/// The same word at a fixed display size, tracked as the chosen size would
/// be; the dashed ghost boxes are the untracked layout.
class _SamplePainter extends CustomPainter {
  _SamplePainter({required this.size, required this.blend});

  final double size;
  final double blend;

  @override
  void paint(Canvas canvas, Size box) {
    const fs = 42.0;
    const word = 'Tracking';
    final ls = blend * _tracking(size) * fs;
    final auto = TextProbe(TextSpan(text: word, style: BT.display(fs, letterSpacing: ls)));
    final flat = TextProbe(TextSpan(text: word, style: BT.display(fs)));
    final o = Offset(4, (box.height - auto.size.height) / 2 - 18);

    final ghost = Paint()
      ..color = BP.lineFaint
      ..style = PaintingStyle.stroke;
    for (final (s, e) in flat.graphemes()) {
      for (final b in flat.boxes(s, e)) {
        canvas.drawPath(dashPath(_rectPath(b.toRect().shift(o).deflate(1)), dash: 3, gap: 3), ghost);
      }
    }
    final live = Paint()
      ..color = BP.lineDim
      ..style = PaintingStyle.stroke;
    for (final (s, e) in auto.graphemes()) {
      for (final b in auto.boxes(s, e)) {
        canvas.drawPath(dashPath(_rectPath(b.toRect().shift(o).deflate(1)), dash: 5, gap: 3), live);
      }
    }
    auto.paint(canvas, o);

    // Width comparison.
    final y = o.dy + auto.size.height + 14;
    final fw = flat.size.width;
    final aw = auto.size.width;
    void bar(double w, double yy, Color c, String name) {
      final p = Paint()
        ..color = c
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(o.dx, yy), Offset(o.dx + w, yy), p);
      canvas.drawLine(Offset(o.dx, yy - 4), Offset(o.dx, yy + 4), p);
      canvas.drawLine(Offset(o.dx + w, yy - 4), Offset(o.dx + w, yy + 4), p);
      final tp = _tp(name, BT.mono(11, color: c));
      tp.paint(canvas, Offset(o.dx + math.max(fw, aw) + 10, yy - tp.height / 2));
      tp.dispose();
    }

    canvas.drawRect(
      Rect.fromLTRB(o.dx + math.min(fw, aw), y - 5, o.dx + math.max(fw, aw), y + 17),
      Paint()..color = BP.amber.withValues(alpha: 0.18),
    );
    bar(fw, y, BP.inkFaint, 'flat');
    bar(aw, y + 12, BP.amber, 'auto');
    auto.dispose();
    flat.dispose();
  }

  @override
  bool shouldRepaint(_SamplePainter old) => old.size != size || old.blend != blend;
}

// ─────────────────────────────────────────────────────────────────────────────
// Engine layout: hero (≈ 2/3) · stack strip · capability tags
// ─────────────────────────────────────────────────────────────────────────────

const _heroW = 980.0;
const _sideX = 1016.0;
const _stripH = 440.0;

class _Layer {
  const _Layer(this.name, this.sub);

  final String name;
  final String sub;
}

enum _K { yes, no, info, flutter }

class _Cap {
  const _Cap(this.text, [this.kind = _K.info]);

  final String text;
  final _K kind;
}

class _EngineLayout extends StatelessWidget {
  const _EngineLayout({required this.hero, required this.layers, required this.caps});

  final Widget hero;
  final List<_Layer> layers;
  final List<_Cap> caps;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned(left: 0, top: 0, width: _heroW, bottom: 0, child: hero),
      Positioned(
        left: _sideX,
        top: 0,
        right: 0,
        height: _stripH,
        child: Reveal(
          visible: true,
          delay: const Duration(milliseconds: 250),
          offset: const Offset(24, 0),
          child: _StackStrip(layers: layers),
        ),
      ),
      Positioned(
        left: _sideX,
        top: _stripH + 30,
        right: 0,
        bottom: 0,
        child: _CapTags(caps: caps),
      ),
    ],
  );
}

class _CapTags extends StatelessWidget {
  const _CapTags({required this.caps});

  final List<_Cap> caps;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      for (var i = 0; i < caps.length; i++)
        Reveal(
          visible: true,
          delay: Duration(milliseconds: 900 + 110 * i),
          offset: const Offset(0, 12),
          child: _tag(caps[i]),
        ),
    ],
  );

  static Widget _tag(_Cap c) {
    final color = switch (c.kind) {
      _K.yes => BP.green,
      _K.no => BP.red,
      _K.flutter => BP.amber,
      _K.info => BP.line,
    };
    final mark = c.kind == _K.yes || c.kind == _K.no;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mark) ...[
            _Mark(yes: c.kind == _K.yes, color: color, size: 12),
            const SizedBox(width: 7),
          ],
          Text(c.text, style: BT.mono(14, color: color)),
        ],
      ),
    );
  }
}

/// A drawn ✓ / ✕ (the mono font has no check mark).
class _Mark extends StatelessWidget {
  const _Mark({required this.yes, required this.color, this.size = 13});

  final bool yes;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _MarkPainter(yes, color)),
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.yes, this.color);

  final bool yes;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = math.max(1.6, s.width * 0.15)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = s.width;
    final h = s.height;
    final path = yes
        ? (Path()
            ..moveTo(w * 0.1, h * 0.55)
            ..lineTo(w * 0.4, h * 0.84)
            ..lineTo(w * 0.92, h * 0.18))
        : (Path()
            ..moveTo(w * 0.18, h * 0.18)
            ..lineTo(w * 0.82, h * 0.82)
            ..moveTo(w * 0.82, h * 0.18)
            ..lineTo(w * 0.18, h * 0.82));
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.yes != yes || old.color != color;
}

/// The engine's layers, top to bottom, with a packet hopping through them.
class _StackStrip extends StatefulWidget {
  const _StackStrip({required this.layers});

  final List<_Layer> layers;

  @override
  State<_StackStrip> createState() => _StackStripState();
}

class _StackStripState extends State<_StackStrip> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final n = widget.layers.length;
    return BpPanel(
      label: 'stack',
      padding: const EdgeInsets.fromLTRB(14, 30, 18, 18),
      child: LayoutBuilder(
        builder: (context, box) {
          final slot = box.maxHeight / n;
          final h = math.min(54.0, slot - 14);
          return LoopBuilder(
            period: Duration(milliseconds: 1000 * n + 1600),
            builder: (context, t, _) {
              final travel = n - 1.0;
              final u = t * (travel + 1.6);
              var pos = travel;
              if (u < travel) {
                final seg = u.floor();
                final f = ((u - seg - 0.3) / 0.7).clamp(0.0, 1.0);
                pos = seg + Curves.easeInOutCubic.transform(f);
              }
              final fade = u < 0.15
                  ? u / 0.15
                  : (u > travel + 1.0 ? (1 - (u - travel - 1.0) / 0.6).clamp(0.0, 1.0) : 1.0);
              final active = (pos - pos.round()).abs() < 0.2 && fade > 0.3 ? pos.round() : -1;
              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RailPainter(n: n, slot: slot, pos: pos, alpha: fade, boxLeft: 34),
                    ),
                  ),
                  for (var i = 0; i < n; i++)
                    Positioned(
                      left: 34,
                      right: 0,
                      top: slot * i + (slot - h) / 2,
                      height: h,
                      child: Reveal(
                        visible: true,
                        delay: Duration(milliseconds: 400 + 90 * i),
                        offset: const Offset(16, 0),
                        child: MouseRegion(
                          onEnter: (_) => setState(() => _hover = i),
                          onExit: (_) => setState(() => _hover = null),
                          child: _LayerBox(
                            layer: widget.layers[i],
                            hot: i == active || i == _hover,
                            passed: pos >= i - 0.01 && fade > 0.3,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _LayerBox extends StatelessWidget {
  const _LayerBox({required this.layer, required this.hot, required this.passed});

  final _Layer layer;
  final bool hot;
  final bool passed;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 220),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: hot ? BP.amber.withValues(alpha: 0.10) : BP.panel,
      border: Border.all(
        color: hot ? BP.amber : (passed ? BP.line.withValues(alpha: 0.7) : BP.lineDim),
        width: hot ? 1.6 : 1,
      ),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          layer.name,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          style: BT.mono(16, color: hot ? BP.amber : BP.ink, weight: 500, height: 1.2),
        ),
        const SizedBox(height: 2),
        Text(
          layer.sub,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          style: BT.mono(11.5, color: BP.inkFaint, height: 1.2),
        ),
      ],
    ),
  );
}

class _RailPainter extends CustomPainter {
  _RailPainter({
    required this.n,
    required this.slot,
    required this.pos,
    required this.alpha,
    required this.boxLeft,
  });

  final int n;
  final double slot;
  final double pos;
  final double alpha;
  final double boxLeft;

  @override
  void paint(Canvas canvas, Size size) {
    const x = 10.0;
    double y(double i) => slot * i + slot / 2;
    canvas.drawLine(
      Offset(x, y(0)),
      Offset(x, y(n - 1.0)),
      Paint()
        ..color = BP.lineDim
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(x, y(0)),
      Offset(x, y(pos)),
      Paint()
        ..color = BP.line.withValues(alpha: 0.8 * alpha)
        ..strokeWidth = 2,
    );
    for (var i = 0; i < n; i++) {
      final yi = y(i.toDouble());
      final on = pos >= i - 0.01 && alpha > 0.3;
      canvas.drawLine(
        Offset(x, yi),
        Offset(boxLeft, yi),
        Paint()
          ..color = (on ? BP.line : BP.lineDim)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(Offset(x, yi), 4.5, Paint()..color = BP.paper);
      canvas.drawCircle(
        Offset(x, yi),
        4.5,
        Paint()
          ..color = (on ? BP.line : BP.lineDim)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      if (i < n - 1) {
        final ym = y(i + 0.5);
        drawArrowHead(
          canvas,
          Offset(x, ym + 3),
          Offset(x, ym - 5),
          Paint()
            ..color = BP.lineDim
            ..strokeWidth = 1.2,
          5,
        );
      }
    }
    if (alpha <= 0.01) return;
    final py = y(pos);
    for (var k = 1; k <= 6; k++) {
      final ty = py - k * 7;
      if (ty < y(0)) break;
      canvas.drawCircle(
        Offset(x, ty),
        3.5 - k * 0.45,
        Paint()..color = BP.amber.withValues(alpha: (0.5 - k * 0.07) * alpha),
      );
    }
    final d = Path()
      ..moveTo(x, py - 9)
      ..lineTo(x + 9, py)
      ..lineTo(x, py + 9)
      ..lineTo(x - 9, py)
      ..close();
    canvas.drawPath(d, Paint()..color = BP.amber.withValues(alpha: alpha));
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.pos != pos || old.alpha != alpha || old.n != n || old.slot != slot;
}
