import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../deck/scripts.dart';
import '../../../deck/theme.dart';
import '../../../deck/widgets.dart';
import '../../../slides/journey/journey.dart';
import 'frame.dart';

/// Stop 3: HarfBuzz turns code points + font into glyph ids + positions.
/// Code points go in; the nominal glyphs (cmap + hmtx) drop into their real
/// shaped positions, measured from the real paragraph. Kerning shows up as
/// glyphs sliding left; Arabic gets new (joined) glyphs; an emoji sequence
/// collapses into one glyph.
class JShapeSlide extends StatelessWidget {
  const JShapeSlide({super.key});

  @override
  Widget build(BuildContext context) => SJourneyFrame(
    stop: 2,
    title: (_) => 'Shape',
    builder: (context, d) => _Shape(data: d),
  );
}

// Geometry (content-area coordinates).
const _chipW = 160.0;
const _chipH = 46.0;
const _chipGap = 10.0;
const _engineX = 200.0;
const _engineD = 190.0;
const _outX = 480.0;
const _rowsTop = 16.0;
const _rowGap = 100.0;
const _labelsW = 250.0; // room right of the word for the width readouts
const _maxSize = 160.0;

/// One shaped cluster: its code points, its box in the paragraph and its
/// advance in font units (vs the sum of their nominal hmtx advances).
class _Cluster {
  _Cluster(this.glyphs, this.box, this.units, this.nominalUnits);

  final List<JGlyph> glyphs;
  final Rect box;
  final int units;
  final int nominalUnits;

  bool get changed => units != nominalUnits;
}

/// Everything measured for one word + feature set.
class _Layout {
  _Layout(this.size, this.probe, this.nominalPx, this.clusters);

  final double size;

  /// The real shaped paragraph at [size].
  final TextProbe probe;

  /// Per code point: the advance without shaping, in px.
  final List<double> nominalPx;
  final List<_Cluster> clusters;
}

class _Shape extends StatefulWidget {
  const _Shape({required this.data});

  final JourneyData data;

  @override
  State<_Shape> createState() => _ShapeState();
}

class _ShapeState extends State<_Shape> with SingleTickerProviderStateMixin {
  late final AnimationController _fall = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  Timer? _start;
  bool _kern = true;
  late _Layout _layout = _measure();

  @override
  void initState() {
    super.initState();
    _start = Timer(const Duration(milliseconds: 700), _replay);
  }

  @override
  void dispose() {
    _start?.cancel();
    _fall.dispose();
    _layout.probe.dispose();
    super.dispose();
  }

  void _replay() {
    _start?.cancel();
    _fall.forward(from: 0);
  }

  void _toggleKern() {
    setState(() {
      _kern = !_kern;
      _layout.probe.dispose();
      _layout = _measure();
    });
    _replay();
  }

  List<FontFeature> get _features => [if (!_kern) const FontFeature.disable('kern')];

  TextStyle _style(double size) => journeyStyle(size, features: _features);

  /// A code point's advance without shaping: hmtx for our fonts; measured
  /// alone for platform glyphs.
  double _nominalPx(JGlyph g, double size) {
    if (g.font != null) return g.advance * size / g.font!.unitsPerEm;
    final tp = TextPainter(
      text: TextSpan(text: g.char, style: _style(size)),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }

  _Layout _measure() {
    final d = widget.data;

    // Size the word so both rows and the readouts fit the content area.
    final p100 = TextProbe(TextSpan(text: d.text, style: _style(100)));
    final lineH100 = p100.size.height;
    final wide100 = math.max(
      p100.size.width,
      d.glyphs.fold<double>(0, (a, g) => a + _nominalPx(g, 100)),
    );
    p100.dispose();
    final size = [
      _maxSize,
      100 * (560 - _rowsTop - _rowGap - 56) / (2 * lineH100),
      100 * (1472 - _outX - _labelsW) / wide100,
    ].reduce(math.min).floorToDouble();

    final probe = TextProbe(TextSpan(text: d.text, style: _style(size)));
    int units(double px, JGlyph g) => (px * (g.font?.unitsPerEm ?? 1000) / size).round();
    final nominalPx = [for (final g in d.glyphs) _nominalPx(g, size)];

    // Clusters: one per code point, except emoji sequences (one per grapheme).
    final clusters = <_Cluster>[];
    final ranges = d.glyphs.any((g) => g.script == Script.emoji)
        ? probe.graphemes()
        : [for (final g in d.glyphs) (g.start, g.end)];
    for (final (s, e) in ranges) {
      final idx = [
        for (var i = 0; i < d.glyphs.length; i++)
          if (d.glyphs[i].start >= s && d.glyphs[i].end <= e) i,
      ];
      if (idx.isEmpty) continue;
      final box = probe.rectFor(s, e) ?? Rect.zero;
      clusters.add(
        _Cluster(
          [for (final i in idx) d.glyphs[i]],
          box,
          units(box.width, d.glyphs[idx.first]),
          idx.fold(0, (a, i) => a + units(nominalPx[i], d.glyphs[i])),
        ),
      );
    }
    return _Layout(size, probe, nominalPx, clusters);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final l = _layout;
    final blockMid = _rowsTop + l.probe.size.height + _rowGap / 2;
    final chipsH = d.glyphs.length * (_chipH + _chipGap) - _chipGap;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── in: code points
        Positioned(
          left: 0,
          top: blockMid - chipsH / 2,
          width: _chipW,
          child: Column(
            children: [
              for (var i = 0; i < d.glyphs.length; i++) ...[
                if (i > 0) const SizedBox(height: _chipGap),
                _Chip(glyph: d.glyphs[i]),
              ],
            ],
          ),
        ),
        // ── HarfBuzz
        Positioned(
          left: _engineX,
          top: blockMid - _engineD / 2,
          width: _engineD,
          height: _engineD,
          child: const _Engine(),
        ),
        // ── out: nominal glyphs fall into their shaped positions (tap: again)
        Positioned.fill(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _replay,
              child: AnimatedBuilder(
                animation: _fall,
                builder: (context, _) => CustomPaint(
                  painter: _FallPainter(data: d, layout: l, style: _style(l.size), t: _fall.value),
                ),
              ),
            ),
          ),
        ),
        // ── the one feature switch that matters here
        Positioned(
          left: 0,
          top: 540,
          child: BpButton(label: 'kern', size: 20, selected: _kern, onTap: _toggleKern),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.glyph});

  final JGlyph glyph;

  @override
  Widget build(BuildContext context) => Container(
    height: _chipH,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: BP.panel,
      border: Border.all(color: BP.lineDim, width: 1.5),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 36,
          child: glyph.isJoinControl
              ? const SizedBox()
              : Text(glyph.char, textAlign: TextAlign.center, style: journeyStyle(26)),
        ),
        const SizedBox(width: 10),
        Text(glyph.hex, style: BT.mono(18, color: BP.line)),
      ],
    ),
  );
}

class _Engine extends StatelessWidget {
  const _Engine();

  @override
  Widget build(BuildContext context) => LoopBuilder(
    period: const Duration(seconds: 3),
    builder: (context, t, _) => CustomPaint(painter: _EnginePainter(t)),
  );
}

class _EnginePainter extends CustomPainter {
  _EnginePainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 6;
    final ring = Paint()
      ..color = BP.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(t * 2 * math.pi);
    canvas.drawPath(
      dashPath(Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r)), dash: 12, gap: 9),
      ring,
    );
    canvas.rotate(-t * 4 * math.pi);
    canvas.drawPath(
      dashPath(Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r - 20)), dash: 5, gap: 7),
      ring..color = BP.lineDim,
    );
    canvas.restore();
    final tp = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(text: 'HarfBuzz\n', style: BT.display(28)),
          TextSpan(text: 'hb_shape()', style: BT.mono(18, color: BP.amber)),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
    // In / out arrows with packets.
    final a = Paint()
      ..color = BP.line
      ..strokeWidth = 2;
    const reach = 44.0;
    drawArrow(canvas, Offset(-reach + 10, c.dy), Offset(c.dx - r - 6, c.dy), a, head: 11);
    drawArrow(canvas, Offset(c.dx + r + 6, c.dy), Offset(size.width + reach + 20, c.dy), a, head: 11);
    final px = -reach + 10 + (c.dx - r - 16 + reach) * t;
    canvas.drawCircle(Offset(px, c.dy), 6, Paint()..color = BP.amber);
    final qx = c.dx + r + 6 + (size.width + reach + 10 - c.dx - r) * t;
    canvas.drawRect(
      Rect.fromCenter(center: Offset(qx, c.dy), width: 11, height: 11),
      Paint()..color = BP.green,
    );
  }

  @override
  bool shouldRepaint(_EnginePainter old) => old.t != t;
}

/// Top row: each code point drawn alone at its nominal (hmtx) advance.
/// Bottom row: the real shaped paragraph, one box per cluster with its glyph
/// id above and its x-advance (font units) below. The nominal glyphs drop
/// into place; amber = moved or resized by shaping.
class _FallPainter extends CustomPainter {
  _FallPainter({required this.data, required this.layout, required this.style, required this.t});

  final JourneyData data;
  final _Layout layout;
  final TextStyle style;
  final double t;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final probe = layout.probe;
    final line = probe.lines.first;
    final lineH = probe.size.height;
    final rtl = data.rtl;
    final shapedW = probe.size.width;
    final nominalW = layout.nominalPx.fold<double>(0, (a, w) => a + w);
    final wide = math.max(shapedW, nominalW);

    const topY = _rowsTop;
    final botY = _rowsTop + lineH + _rowGap;
    final topBase = topY + line.baseline;
    final botBase = botY + line.baseline;
    // RTL words line up on the right, LTR on the left.
    final shapedX = rtl ? _outX + wide - shapedW : _outX;

    final fall = Curves.easeInOutCubic.transform(((t - 0.15) / 0.55).clamp(0.0, 1.0));
    final land = ((t - 0.7) / 0.2).clamp(0.0, 1.0);

    // Baselines
    final end = _outX + wide + 24;
    canvas.drawLine(
      Offset(_outX - 16, topBase),
      Offset(end, topBase),
      Paint()
        ..color = BP.lineDim
        ..strokeWidth = 1.5,
    );
    canvas.drawLine(
      Offset(_outX - 16, botBase),
      Offset(end, botBase),
      Paint()
        ..color = BP.amber.withValues(alpha: 0.7)
        ..strokeWidth = 1.5,
    );

    // Nominal boxes: the pen advances by hmtx, code point by code point.
    final nominal = <Rect>[];
    var pen = rtl ? _outX + wide : _outX;
    for (final w in layout.nominalPx) {
      if (rtl) pen -= w;
      nominal.add(Rect.fromLTWH(pen, topY, w, lineH));
      if (!rtl) pen += w;
    }

    // Output labels: glyph id (or the positional form Arabic shaping picks)
    // above each shaped box, x-advance below; staggered where boxes are
    // narrower than their labels.
    final runes = data.text.runes.toList();
    final boxes = [for (final c in layout.clusters) c.box.shift(Offset(shapedX, botY))];
    final ids = <TextPainter>[];
    final advances = <TextPainter>[];
    for (final c in layout.clusters) {
      final g0 = c.glyphs.first;
      final (id, idColor) = g0.font == null
          ? ('sys', BP.violet)
          : (g0.script.rtl
                ? (arabicForm(runes, data.glyphs.indexOf(g0)).$1, BP.coral)
                : ('#${g0.glyphId}', BP.green));
      ids.add(_painter(id, BT.mono(20, color: idColor.withValues(alpha: land))));
      advances.add(
        _painter('${c.units}', BT.mono(18, color: (c.changed ? BP.amber : BP.inkDim).withValues(alpha: land))),
      );
    }
    final centers = [for (final b in boxes) b.center.dx];
    final idLevel = _levels(centers, [for (final p in ids) p.width]);
    final advLevel = _levels(centers, [for (final p in advances) p.width]);
    const idStep = 26.0;
    final idTop = botY - 34;
    final connectorEnd = idTop - 6 - idLevel.fold(0, math.max) * idStep;

    final dashed = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    var gi = 0;
    for (var ci = 0; ci < layout.clusters.length; ci++) {
      final c = layout.clusters[ci];
      final box = boxes[ci];
      final first = nominal[gi];
      final moved = rtl ? (first.right - box.right).abs() > 0.5 : (first.left - box.left).abs() > 0.5;
      final col = c.changed || moved ? BP.amber : BP.lineDim;
      // Shaped box
      canvas.drawPath(
        dashPath(Path()..addRect(box), dash: 6, gap: 5),
        dashed..color = col.withValues(alpha: 0.3 + 0.6 * land),
      );
      for (final g in c.glyphs) {
        final n = nominal[gi++];
        // Ghost nominal glyph + box
        canvas.drawPath(dashPath(Path()..addRect(n), dash: 6, gap: 5), dashed..color = BP.lineFaint);
        _glyph(canvas, g, Offset(n.left, topBase), 0.3);
        // Connector: nominal pen position → shaped pen position.
        final nx = rtl ? n.right : n.left;
        final sx = rtl ? box.right : box.left;
        final shifted = (nx - sx).abs() > 0.5;
        canvas.drawLine(
          Offset(nx, topY + lineH + 6),
          Offset(sx, connectorEnd),
          Paint()
            ..color = (shifted ? BP.amber : BP.lineDim).withValues(alpha: shifted ? 0.8 : 0.5)
            ..strokeWidth = shifted ? 2 : 1.2,
        );
        // The falling glyph (drawn alone = its nominal form).
        if (land < 1) {
          final x = n.left + (box.left - n.left) * fall;
          final base = topBase + (botBase - topBase) * fall;
          _glyph(canvas, g, Offset(x, base), 1 - land);
        }
      }
      final id = ids[ci];
      id.paint(canvas, Offset(box.center.dx - id.width / 2, idTop - idLevel[ci] * idStep));
      final adv = advances[ci];
      adv.paint(canvas, Offset(box.center.dx - adv.width / 2, botY + lineH + 8 + advLevel[ci] * 24));
    }
    for (final p in [...ids, ...advances]) {
      p.dispose();
    }

    // The real shaped word lands.
    if (land > 0) {
      canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: land));
      probe.paint(canvas, Offset(shapedX, botY));
      canvas.restore();
    }

    // Width readouts, in font units.
    int sum(Iterable<int> v) => v.fold(0, (a, b) => a + b);
    final nominalUnits = sum(layout.clusters.map((c) => c.nominalUnits));
    final shapedUnits = sum(layout.clusters.map((c) => c.units));
    _text(
      canvas,
      '${data.glyphs.every((g) => g.font != null) ? 'hmtx' : 'alone'}  $nominalUnits',
      BT.mono(20, color: BP.inkDim),
      Offset(end + 20, topBase - 30),
      center: false,
    );
    _text(
      canvas,
      'shaped  $shapedUnits',
      BT.mono(20, color: BP.amber.withValues(alpha: 0.25 + 0.75 * land)),
      Offset(end + 20, botBase - 30),
      center: false,
    );
  }

  /// One code point on its own, its baseline at [base].dy.
  void _glyph(Canvas canvas, JGlyph g, Offset base, double opacity) {
    if (g.isJoinControl || opacity <= 0) return;
    final tp = TextPainter(
      text: TextSpan(text: g.char, style: style),
      textDirection: g.script.rtl ? TextDirection.rtl : TextDirection.ltr,
    )..layout();
    final ascent = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final at = Offset(base.dx, base.dy - ascent);
    // A layer, so colour (emoji) glyphs fade too.
    if (opacity < 1) {
      canvas.saveLayer(at & tp.size, Paint()..color = Colors.white.withValues(alpha: opacity));
    }
    tp.paint(canvas, at);
    if (opacity < 1) canvas.restore();
    tp.dispose();
  }

  static TextPainter _painter(String s, TextStyle style) =>
      TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();

  /// Stacking level per label so labels centred at [centers] with [widths]
  /// never overlap (0 = on the box, 1 = one step further out, …).
  static List<int> _levels(List<double> centers, List<double> widths, {double gap = 10}) {
    final order = List.generate(centers.length, (i) => i)..sort((a, b) => centers[a].compareTo(centers[b]));
    final lastRight = <double>[];
    final out = List.filled(centers.length, 0);
    for (final i in order) {
      final left = centers[i] - widths[i] / 2;
      var lv = 0;
      while (lv < lastRight.length && lastRight[lv] + gap > left) {
        lv++;
      }
      if (lv == lastRight.length) lastRight.add(double.negativeInfinity);
      lastRight[lv] = centers[i] + widths[i] / 2;
      out[i] = lv;
    }
    return out;
  }

  void _text(Canvas canvas, String s, TextStyle style, Offset at, {bool center = true}) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, center ? at - Offset(tp.width / 2, 0) : at);
    tp.dispose();
  }

  @override
  bool shouldRepaint(_FallPainter old) => old.t != t || old.layout != layout || old.data != data;
}
