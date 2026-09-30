import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../deck/deck.dart';
import '../../deck/scripts.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';

/// Itemize: one string → runs of one script, one direction, one font.
///
/// Brackets sit under each run's REAL visual boxes (from the laid-out
/// paragraph), so a run that bidi splits or reorders gets split brackets.
/// Steps: 0 text · 1 runs + script · 2 direction · 3 font.
class ItemizeSlide extends StatefulWidget {
  const ItemizeSlide({super.key});

  @override
  State<ItemizeSlide> createState() => _ItemizeSlideState();
}

const _presets = [
  'Hello مرحبا 世界 👋 123',
  'Hi كتاب 2026',
  'नमस्ते Привет שלום',
  'ไทย 한국어 かな 漢字',
];

const _textTop = 190.0;

Color _colorOf(Script s) => s == Script.common ? BP.inkDim : s.color;

class _ItemizeSlideState extends State<ItemizeSlide> with TickerProviderStateMixin {
  late final TextEditingController _ctrl = TextEditingController(text: _presets.first);
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );
  late final AnimationController _arrows = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  late final AnimationController _fonts = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  late final AnimationController _scan = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );
  late final AnimationController _march = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  late _Layout _layout;
  int _step = -1;

  @override
  void initState() {
    super.initState();
    _layout = _Layout.of(_ctrl.text);
    _restartScan();
  }

  void _restartScan() {
    final n = _layout.clusters.length;
    _scan.repeat(period: Duration(milliseconds: 320 * (n + 5)));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final step = SlideScope.of(context).step;
    if (step == _step) return;
    _step = step;
    step >= 1 ? _enter.forward() : _enter.reverse();
    step >= 2 ? _arrows.forward() : _arrows.reverse();
    step >= 3 ? _fonts.forward() : _fonts.reverse();
  }

  void _setText(String s) {
    if (_ctrl.text != s) _ctrl.text = s;
    final old = _layout;
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    setState(() => _layout = _Layout.of(s));
    _restartScan();
    if (_step >= 1) _enter.forward(from: 0);
  }

  @override
  void dispose() {
    for (final c in [_enter, _arrows, _fonts, _scan, _march]) {
      c.dispose();
    }
    _ctrl.dispose();
    _layout.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = SlideScope.of(context).step;
    return SlideFrame(
      title: 'Itemize',
      trailing: Reveal(
        visible: step >= 1,
        child: BpTag('${_layout.runs.length} runs', color: BP.amber, size: 15),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _ItemizePainter(
                  layout: _layout,
                  enter: _enter,
                  arrows: _arrows,
                  fonts: _fonts,
                  scan: _scan,
                  march: _march,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                BpTextField(
                  controller: _ctrl,
                  width: 500,
                  style: BT.sample(28),
                  onChanged: _setText,
                ),
                const SizedBox(width: 36),
                Expanded(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final p in _presets)
                        _Chip(text: p, selected: p == _ctrl.text, onTap: () => _setText(p)),
                    ],
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

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.selected, required this.onTap});

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? BP.line.withValues(alpha: 0.16) : Colors.transparent,
          border: Border.all(color: selected ? BP.amber : BP.lineDim, width: selected ? 2 : 1),
        ),
        child: Text(text, style: BT.sample(19, color: selected ? BP.ink : BP.inkDim)),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Layout data (all from the real paragraph)
// ─────────────────────────────────────────────────────────────────────────────

/// One visually contiguous piece of a run.
class _Seg {
  _Seg(this.run, this.rect);

  final int run;
  final Rect rect;
}

class _Cluster {
  _Cluster(this.script, this.rect, this.cp, this.seg);

  final Script script;
  final Rect rect;
  final String cp;
  final int seg;
}

class _Layout {
  _Layout._({
    required this.plain,
    required this.colored,
    required this.runs,
    required this.segs,
    required this.mainSeg,
    required this.clusters,
    required this.baseline,
  });

  factory _Layout.of(String text) {
    var fs = 72.0;
    var plain = TextProbe(TextSpan(text: text, style: BT.sample(fs)));
    if (plain.size.width > 1400) {
      fs = math.max(24.0, fs * 1400 / plain.size.width);
      plain.dispose();
      plain = TextProbe(TextSpan(text: text, style: BT.sample(fs)));
    }
    final runs = itemize(text);
    final colored = TextProbe(
      TextSpan(
        children: [
          for (final r in runs)
            TextSpan(
              text: r.text,
              style: BT.sample(fs, color: Color.lerp(BP.ink, _colorOf(r.script), 0.7)!),
            ),
        ],
      ),
    );

    // Visual segments: a run's boxes, merged where they touch.
    final segs = <_Seg>[];
    for (var i = 0; i < runs.length; i++) {
      final rects = plain
          .boxes(runs[i].start, runs[i].end)
          .map((b) => b.toRect())
          .where((r) => r.width > 0.01)
          .toList()
        ..sort((a, b) => a.left.compareTo(b.left));
      final merged = <Rect>[];
      for (final r in rects) {
        if (merged.isNotEmpty && r.left - merged.last.right < 1.0) {
          merged[merged.length - 1] = merged.last.expandToInclude(r);
        } else {
          merged.add(r);
        }
      }
      segs.addAll(merged.map((r) => _Seg(i, r)));
    }
    segs.sort((a, b) => a.rect.left.compareTo(b.rect.left));

    final mainSeg = List<int>.filled(runs.length, 0);
    final best = List<double>.filled(runs.length, -1);
    for (var k = 0; k < segs.length; k++) {
      final s = segs[k];
      if (s.rect.width > best[s.run]) {
        best[s.run] = s.rect.width;
        mainSeg[s.run] = k;
      }
    }

    final clusters = <_Cluster>[];
    var i = 0;
    for (final g in text.characters) {
      final r = plain.rectFor(i, i + g.length);
      if (r != null) {
        var seg = 0;
        for (var k = 0; k < segs.length; k++) {
          if (r.center.dx >= segs[k].rect.left - 0.5 && r.center.dx <= segs[k].rect.right + 0.5) {
            seg = k;
            break;
          }
        }
        final cp = g.runes.first.toRadixString(16).toUpperCase().padLeft(4, '0');
        clusters.add(_Cluster(scriptOfCluster(g), r, 'U+$cp', seg));
      }
      i += g.length;
    }

    final lines = plain.lines;
    return _Layout._(
      plain: plain,
      colored: colored,
      runs: runs,
      segs: segs,
      mainSeg: mainSeg,
      clusters: clusters,
      baseline: lines.isEmpty ? fs : lines.first.baseline,
    );
  }

  final TextProbe plain;
  final TextProbe colored;
  final List<ScriptRun> runs;
  final List<_Seg> segs;
  final List<int> mainSeg;
  final List<_Cluster> clusters;
  final double baseline;

  void dispose() {
    plain.dispose();
    colored.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────────────────

double _ease(double t) => Curves.easeInOutCubic.transform(t.clamp(0.0, 1.0));
double _win(double v, double a, double b) => _ease((v - a) / (b - a));

class _ItemizePainter extends CustomPainter {
  _ItemizePainter({
    required this.layout,
    required this.enter,
    required this.arrows,
    required this.fonts,
    required this.scan,
    required this.march,
  }) : super(repaint: Listenable.merge([enter, arrows, fonts, scan, march]));

  final _Layout layout;
  final Animation<double> enter;
  final Animation<double> arrows;
  final Animation<double> fonts;
  final Animation<double> scan;
  final Animation<double> march;

  @override
  void paint(Canvas canvas, Size size) {
    final l = layout;
    if (l.runs.isEmpty) return;
    final origin = Offset((size.width - l.plain.size.width) / 2, _textTop);
    final e = enter.value;
    // Runs pull apart, then settle back onto their real positions.
    final sep = Curves.easeOutCubic.transform((e / 0.3).clamp(0.0, 1.0)) * (1 - _win(e, 0.6, 1));
    final tint = _win(e, 0.12, 0.5);
    final n = l.segs.length;
    Offset shift(int k) => Offset((k - (n - 1) / 2) * 42 * sep, 0);
    final top = origin.dy;
    final bottom = origin.dy + l.plain.size.height;
    final st = math.min(0.06, 0.3 / math.max(1, n));

    // Baseline guide.
    final by = origin.dy + l.baseline;
    canvas.drawPath(
      dashPath(Path()
        ..moveTo(0, by)
        ..lineTo(size.width, by), dash: 8, gap: 6),
      Paint()
        ..color = BP.lineFaint
        ..style = PaintingStyle.stroke,
    );

    // Tinted run bands behind the text.
    for (var k = 0; k < n; k++) {
      final s = l.segs[k];
      final p = _win(e, 0.18 + k * st, 0.58 + k * st);
      if (p <= 0) continue;
      final r = Rect.fromLTRB(s.rect.left, top, s.rect.right, bottom).shift(Offset(origin.dx, 0) + shift(k));
      canvas.drawRect(
        r.deflate(2),
        Paint()..color = _colorOf(l.runs[s.run].script).withValues(alpha: 0.07 * p),
      );
    }

    // The text: whole when settled, clipped per segment while separated.
    void paintText(Offset o) {
      if (tint < 1) _paintAlpha(canvas, l.plain, o, 1 - tint);
      if (tint > 0) _paintAlpha(canvas, l.colored, o, tint);
    }

    if (sep < 0.002) {
      paintText(origin);
    } else {
      for (var k = 0; k < n; k++) {
        final r = l.segs[k].rect;
        canvas.save();
        canvas.translate(shift(k).dx, 0);
        canvas.clipRect(Rect.fromLTRB(origin.dx + r.left, top - 80, origin.dx + r.right, bottom + 80));
        paintText(origin);
        canvas.restore();
      }
    }

    // Scanner: the itemizer walking clusters in logical (memory) order.
    final nc = l.clusters.length;
    final pos = scan.value * (nc + 5);
    final i = pos.floor();
    if (i < nc) {
      final c = l.clusters[i];
      final col = _colorOf(c.script);
      final r = c.rect.shift(origin + shift(c.seg));
      canvas.drawRect(r, Paint()..color = col.withValues(alpha: 0.14));
      canvas.drawPath(
        dashPath(Path()..addRect(r), dash: 4, gap: 3),
        Paint()
          ..color = col
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      final prev = i > 0 ? l.clusters[i - 1].rect.shift(origin + shift(l.clusters[i - 1].seg)).center.dx : r.center.dx;
      final x = lerpDouble(prev, r.center.dx, Curves.easeOutCubic.transform(((pos - i) / 0.45).clamp(0.0, 1.0)))!;
      final head = Path()
        ..moveTo(x - 7, top - 14)
        ..lineTo(x + 7, top - 14)
        ..lineTo(x, top - 4)
        ..close();
      canvas.drawPath(head, Paint()..color = BP.amber);
      _label(canvas, c.cp, BT.mono(15, color: col), Offset(x, top - 32));
    }

    // Brackets under every visual segment.
    final y0 = bottom + 16;
    for (var k = 0; k < n; k++) {
      final s = l.segs[k];
      final p = _win(e, 0.18 + k * st, 0.58 + k * st);
      if (p <= 0) continue;
      final col = _colorOf(l.runs[s.run].script);
      final r = s.rect.shift(origin + shift(k));
      final left = r.left + 4;
      final right = math.max(left + 2, r.right - 4);
      final cx = (left + right) / 2;
      final yb = y0 + 14;
      final paint = Paint()
        ..color = col
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.square;
      for (final end in [left, right]) {
        final half = Path()
          ..moveTo(cx, yb)
          ..lineTo(end, yb)
          ..lineTo(end, y0);
        canvas.drawPath(partialPath(half, p), paint);
      }
      if (l.mainSeg[s.run] == k) {
        canvas.drawLine(Offset(cx, yb), Offset(cx, yb + 8 * p), paint..strokeWidth = 1.5);
      }
    }

    // Per-run labels, under the widest segment of each run.
    for (var ri = 0; ri < l.runs.length; ri++) {
      final run = l.runs[ri];
      final k = l.mainSeg[ri];
      if (k >= n) continue;
      final col = _colorOf(run.script);
      final r = l.segs[k].rect.shift(origin + shift(k));
      final la = _win(e, 0.38 + k * st, 0.78 + k * st);
      if (la <= 0) continue;
      final maxW = math.max(r.width + 16, 84.0);
      _label(canvas, run.script.label, BT.mono(19, color: col, weight: 500), Offset(r.center.dx, y0 + 44 + 8 * (1 - la)),
          alpha: la, maxWidth: maxW);

      final at = _ease(arrows.value) * la;
      if (at > 0) {
        _dirArrow(canvas, r, y0 + 78, run.rtl, col, at, march.value);
        _label(canvas, run.rtl ? 'rtl' : 'ltr', BT.mono(12, color: col), Offset(r.center.dx, y0 + 96), alpha: at * 0.8);
      }

      final ft = _ease(fonts.value) * la;
      if (ft > 0) {
        _label(canvas, run.script.font, BT.mono(15, color: BP.ink), Offset(r.center.dx, y0 + 132 - 22 * (1 - ft)),
            alpha: ft, maxWidth: maxW);
        final w = math.min(maxW, 150.0) * ft;
        canvas.drawLine(
          Offset(r.center.dx - w / 2, y0 + 146),
          Offset(r.center.dx + w / 2, y0 + 146),
          Paint()
            ..color = col.withValues(alpha: 0.6 * ft)
            ..strokeWidth = 1,
        );
      }
    }
  }

  static void _paintAlpha(Canvas canvas, TextProbe probe, Offset o, double alpha) {
    if (alpha >= 0.999) {
      probe.paint(canvas, o);
      return;
    }
    canvas.saveLayer(
      (o & probe.size).inflate(80),
      Paint()..color = Color.fromRGBO(0, 0, 0, alpha),
    );
    probe.paint(canvas, o);
    canvas.restore();
  }

  static void _label(
    Canvas canvas,
    String text,
    TextStyle style,
    Offset center, {
    double alpha = 1,
    double? maxWidth,
  }) {
    if (alpha <= 0) return;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style.copyWith(color: style.color!.withValues(alpha: style.color!.a * alpha))),
      textDirection: TextDirection.ltr,
    )..layout();
    final s = maxWidth == null ? 1.0 : math.min(1.0, maxWidth / tp.width);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(s);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
    tp.dispose();
  }

  static void _dirArrow(Canvas canvas, Rect r, double y, bool rtl, Color col, double t, double phase) {
    var a = r.left + 12;
    var b = r.right - 12;
    if (b - a < 40) {
      a = r.center.dx - 20;
      b = r.center.dx + 20;
    }
    final from = rtl ? b : a;
    final to = rtl ? a : b;
    final end = from + (to - from) * t;
    final line = Paint()
      ..color = col.withValues(alpha: 0.9 * t)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(from, y), Offset(end, y), line);
    drawArrowHead(canvas, Offset(end, y), Offset(from, y), line, 9);
    // Marching chevrons in the reading direction.
    final len = (to - from).abs() * t;
    const gap = 20.0;
    final dir = rtl ? -1.0 : 1.0;
    for (var d = phase * gap; d < len - 14; d += gap) {
      final x = from + dir * d;
      final fade = math.min(1.0, math.min(d, len - d) / 20);
      final p = Paint()
        ..color = col.withValues(alpha: 0.7 * t * fade)
        ..strokeWidth = 1.4;
      drawArrowHead(canvas, Offset(x, y - 7), Offset(x - dir, y - 7), p, 5);
    }
  }

  @override
  bool shouldRepaint(_ItemizePainter old) => old.layout != layout;
}
