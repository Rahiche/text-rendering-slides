import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/scripts.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'journey.dart';

/// Stop 6: HarfBuzz turns code points + font into positioned glyphs.
/// Top: hb_buffer in → hb_shape() → glyph infos/positions out (real numbers).
/// Bottom: nominal glyphs (cmap + hmtx) fall into their shaped positions.
class JShapeSlide extends StatelessWidget {
  const JShapeSlide({super.key});

  @override
  Widget build(BuildContext context) => JourneyFrame(
    stop: 6,
    title: (_) => 'Shape',
    builder: (context, d) => _Shape(data: d),
  );
}

class _Shape extends StatefulWidget {
  const _Shape({required this.data});

  final JourneyData data;

  @override
  State<_Shape> createState() => _ShapeState();
}

/// One row of shaping output: a glyph (a ligature or an emoji cluster: one
/// for several code points), its cluster and its measured advance.
class _Out {
  _Out(this.glyph, this.glyphs, this.start, this.end, this.advancePx, this.box);

  final JRunGlyph glyph;
  final List<JGlyph> glyphs;
  final int start;
  final int end;
  final double advancePx;
  final Rect? box;
}

class _ShapeState extends State<_Shape> {
  static const _size = 96.0;
  bool _kern = true;
  bool _liga = true;

  List<FontFeature> get _features => [
    if (!_kern) const FontFeature.disable('kern'),
    if (!_liga) const FontFeature.disable('liga'),
  ];

  /// A row a glyph as shaped: the fonts' ligatures (t t, with liga on) and
  /// emoji clusters one glyph each.
  List<_Out> _outputs(TextProbe probe) {
    final d = widget.data;
    return [
      for (final g in d.shaped(liga: _liga))
        () {
          final r = probe.rectFor(g.start, g.end);
          return _Out(g, [for (final i in g.parts) d.glyphs[i]], g.start, g.end, r?.width ?? 0, r);
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final probe = TextProbe(TextSpan(text: d.text, style: journeyStyle(_size, features: _features)));
    final outs = _outputs(probe);
    probe.dispose();
    final upem = d.latin.unitsPerEm;
    final script = d.rtl ? 'Arab' : (d.glyphs.any((g) => g.script == Script.latin) ? 'Latn' : 'Zyyy');
    final fonts = {for (final g in d.glyphs) g.fontName}.join(' + ');
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── hb_buffer
        Positioned(
          left: 0,
          top: 8,
          width: 430,
          child: BpPanel(
            label: 'hb_buffer',
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final g in d.glyphs)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(border: Border.all(color: BP.lineDim)),
                        child: Text(g.hex.substring(2), style: BT.mono(12, color: BP.line)),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                JField('font', fonts, size: 14),
                const SizedBox(height: 6),
                JField('size', '${_size.round()} px · wght 300', size: 14),
                const SizedBox(height: 6),
                JField('script', script, size: 14),
                const SizedBox(height: 6),
                JField('dir', d.rtl ? 'RTL' : 'LTR', size: 14, color: d.rtl ? BP.amber : BP.ink),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('features', style: BT.mono(12, color: BP.inkFaint)),
                    const SizedBox(width: 12),
                    BpButton(label: 'kern', size: 13, selected: _kern, onTap: () => setState(() => _kern = !_kern)),
                    const SizedBox(width: 8),
                    BpButton(label: 'liga', size: 13, selected: _liga, onTap: () => setState(() => _liga = !_liga)),
                  ],
                ),
              ],
            ),
          ),
        ),
        // ── hb_shape()
        Positioned(
          left: 470,
          top: 60,
          width: 190,
          height: 190,
          child: const _Engine(),
        ),
        // ── output
        Positioned(
          left: 700,
          top: 8,
          right: 0,
          child: BpPanel(
            label: 'hb_glyph_info + hb_glyph_position',
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
            child: _OutTable(outs: outs, upem: upem, size: _size),
          ),
        ),
        if (d.rtl)
          Positioned(
            right: 0,
            top: 290,
            child: BpTag('GSUB: ccmp · init · medi · fina → new glyph ids', color: BP.coral, size: 13),
          ),
        // ── nominal → shaped
        Positioned(
          left: 0,
          right: 0,
          top: 330,
          bottom: 0,
          child: _Fall(data: d, outs: outs, size: _size, features: _features),
        ),
      ],
    );
  }
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
    final r = size.shortestSide / 2 - 16;
    final ring = Paint()
      ..color = BP.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(t * 2 * math.pi);
    canvas.drawPath(dashPath(Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r)), dash: 10, gap: 8), ring);
    canvas.rotate(-t * 4 * math.pi);
    canvas.drawPath(
      dashPath(Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r - 18)), dash: 4, gap: 6),
      ring..color = BP.lineDim,
    );
    canvas.restore();
    final tp = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(text: 'HarfBuzz\n', style: BT.display(20)),
          TextSpan(text: 'hb_shape()', style: BT.mono(13, color: BP.amber)),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
    // In / out arrows with packets
    final a = Paint()
      ..color = BP.line
      ..strokeWidth = 1.5;
    drawArrow(canvas, Offset(-30, c.dy), Offset(c.dx - r - 6, c.dy), a);
    drawArrow(canvas, Offset(c.dx + r + 6, c.dy), Offset(size.width + 30, c.dy), a);
    final px = -30 + (c.dx - r + 24) * t;
    canvas.drawCircle(Offset(px, c.dy), 4, Paint()..color = BP.amber);
    final qx = c.dx + r + 6 + (size.width + 24 - c.dx - r) * t;
    canvas.drawRect(Rect.fromCenter(center: Offset(qx, c.dy), width: 8, height: 8), Paint()..color = BP.green);
  }

  @override
  bool shouldRepaint(_EnginePainter old) => old.t != t;
}

class _OutTable extends StatelessWidget {
  const _OutTable({required this.outs, required this.upem, required this.size});

  final List<_Out> outs;
  final int upem;
  final double size;

  @override
  Widget build(BuildContext context) {
    Widget row(List<String> cells, {Color color = BP.ink, bool header = false, Color? deltaColor}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            SizedBox(
              width: const <double>[70, 110, 90, 130, 150][i],
              child: Text(
                cells[i],
                style: BT.mono(header ? 12 : 15, color: header ? BP.inkFaint : (i == 4 ? (deltaColor ?? color) : color)),
              ),
            ),
        ],
      ),
    );

    final rows = outs.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row(['', 'glyph', 'cluster', 'x_advance', 'Δ vs hmtx'], header: true),
        for (final o in rows) _buildRow(o, row),
        if (outs.length > rows.length) Text('…', style: BT.mono(14, color: BP.inkFaint)),
      ],
    );
  }

  Widget _buildRow(_Out o, Widget Function(List<String>, {Color color, bool header, Color? deltaColor}) row) {
    final g = o.glyphs.isEmpty ? null : o.glyphs.first;
    final units = (o.advancePx * upem / size).round();
    final f = o.glyph.font;
    final sys = f == null;
    // Against the glyph's own hmtx (a ligature's: the new glyph's).
    final nominal = sys ? 0 : f.advance(o.glyph.glyphId);
    final delta = units - nominal;
    final text = o.glyphs.map((x) => x.char).join();
    final liga = o.glyph.ligature;
    return row(
      [
        text,
        sys ? 'sys' : '#${o.glyph.glyphId}${g!.script.rtl ? '→' : ''}',
        '${o.start}',
        sys ? '${o.advancePx.toStringAsFixed(1)}px' : '$units',
        sys ? '—' : '${delta == 0 ? '0' : (delta > 0 ? '+$delta' : '$delta')}${liga ? ' · liga' : ''}',
      ],
      deltaColor: sys || (delta == 0 && !liga) ? BP.inkFaint : BP.amber,
    );
  }
}

/// Nominal glyphs (each drawn alone at hmtx positions) fall into the real
/// shaped positions. Differences = kerning (GPOS) or new glyphs (GSUB).
class _Fall extends StatelessWidget {
  const _Fall({
    required this.data,
    required this.outs,
    required this.size,
    required this.features,
  });

  final JourneyData data;
  final List<_Out> outs;
  final double size;
  final List<FontFeature> features;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 20,
          child: Text('cmap + hmtx', style: BT.mono(14, color: BP.inkDim)),
        ),
        Positioned(
          left: 0,
          top: 158,
          child: Text('shaped', style: BT.mono(14, color: BP.amber)),
        ),
        Positioned.fill(
          child: LoopBuilder(
            period: const Duration(milliseconds: 5200),
            builder: (context, t, _) => CustomPaint(
              painter: _FallPainter(
                data: data,
                outs: outs,
                size: size,
                features: features,
                t: t,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FallPainter extends CustomPainter {
  _FallPainter({
    required this.data,
    required this.outs,
    required this.size,
    required this.features,
    required this.t,
  });

  final JourneyData data;
  final List<_Out> outs;
  final double size;
  final List<FontFeature> features;
  final double t;

  static const _topBase = 110.0;
  static const _botBase = 250.0;
  static const _left = 200.0;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final shaped = TextProbe(TextSpan(text: data.text, style: journeyStyle(size, features: features)));
    final line = shaped.lines.first;
    final scale = size / data.latin.unitsPerEm;
    final rtl = data.rtl;
    final width = shaped.size.width;
    final origin = Offset(_left, _botBase - line.baseline);

    // Baselines
    final base = Paint()
      ..color = BP.lineDim
      ..strokeWidth = 1;
    canvas.drawLine(Offset(_left - 20, _topBase), Offset(_left + width + 260, _topBase), base);
    canvas.drawLine(
      Offset(_left - 20, _botBase),
      Offset(_left + width + 260, _botBase),
      Paint()
        ..color = BP.amber.withValues(alpha: 0.7)
        ..strokeWidth = 1.2,
    );

    // Nominal positions: pen advances by hmtx, per code point.
    final nominal = <Rect>[];
    var pen = rtl ? _left + width : _left;
    for (final o in outs) {
      var adv = 0.0;
      for (final g in o.glyphs) {
        adv += g.font == null ? o.advancePx / o.glyphs.length : g.advance * scale;
      }
      if (rtl) {
        nominal.add(Rect.fromLTWH(pen - adv, _topBase - size, adv, size));
        pen -= adv;
      } else {
        nominal.add(Rect.fromLTWH(pen, _topBase - size, adv, size));
        pen += adv;
      }
    }

    final fall = Curves.easeInOutCubic.transform(((t - 0.25) / 0.35).clamp(0.0, 1.0));
    final hold = t > 0.6;
    final ink = BP.ink;

    for (var i = 0; i < outs.length; i++) {
      final o = outs[i];
      final box = o.box?.shift(origin);
      final n = nominal[i];
      // Ghost nominal box
      canvas.drawPath(
        dashPath(Path()..addRect(n), dash: 4, gap: 4),
        Paint()
          ..color = BP.lineFaint
          ..style = PaintingStyle.stroke,
      );
      if (box != null) {
        // Shaped box + connector
        final shifted = (box.left - n.left).abs() > 0.5 || (box.width - n.width).abs() > 0.5;
        final c = shifted ? BP.amber : BP.lineDim;
        canvas.drawPath(
          dashPath(Path()..addRect(Rect.fromLTRB(box.left, _botBase - size, box.right, _botBase + size * 0.28)), dash: 4, gap: 4),
          Paint()
            ..color = c.withValues(alpha: hold ? 0.9 : 0.35)
            ..style = PaintingStyle.stroke,
        );
        canvas.drawLine(
          Offset(n.left, _topBase + 8),
          Offset(box.left, _botBase - size - 4),
          Paint()
            ..color = c.withValues(alpha: 0.5)
            ..strokeWidth = 1,
        );
      }
      // The falling glyph (drawn alone = nominal form; a ligature's letters
      // each alone, falling together into the one glyph).
      if (!hold) {
        final parts = o.glyph.ligature ? [for (final g in o.glyphs) g.char] : [o.glyphs.map((g) => g.char).join()];
        var from = n.left;
        for (final (k, text) in parts.indexed) {
          final tp = TextPainter(
            text: TextSpan(text: text, style: journeyStyle(size, color: ink, features: features)),
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          )..layout();
          final target = box == null ? from : box.left + box.width * k / parts.length;
          final x = from + (target - from) * fall;
          final y = (_topBase - line.baseline) + (_botBase - _topBase) * fall;
          tp.paint(canvas, Offset(x, y));
          from += o.glyph.ligature ? o.glyphs[k].advance * scale : 0;
          tp.dispose();
        }
      }
    }

    // The real shaped word appears once the glyphs land.
    if (hold) {
      shaped.paint(canvas, origin);
    }
    // Width readouts
    final nominalW = nominal.fold<double>(0, (a, r) => a + r.width);
    _label(canvas, Offset(_left + width + 40, _topBase - 30), 'Σ hmtx  ${nominalW.toStringAsFixed(1)} px', BP.inkDim);
    _label(canvas, Offset(_left + width + 40, _botBase - 30), 'shaped  ${width.toStringAsFixed(1)} px', BP.amber);
    shaped.dispose();
  }

  void _label(Canvas canvas, Offset at, String s, Color c) {
    final tp = TextPainter(text: TextSpan(text: s, style: BT.mono(15, color: c)), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, at);
    tp.dispose();
  }

  @override
  bool shouldRepaint(_FallPainter old) => old.t != t || old.data != data || old.features != features;
}
