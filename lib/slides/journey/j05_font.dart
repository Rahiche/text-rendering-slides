import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/font_data.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'journey.dart';

/// Stop 5: every code point asks the font collection "who has a glyph?".
/// Real cmap segments, real glyph ids, real glyf outlines.
class JFontSlide extends StatelessWidget {
  const JFontSlide({super.key});

  @override
  Widget build(BuildContext context) => JourneyFrame(
    stop: 5,
    title: (_) => 'Find the glyphs',
    builder: (context, d) => _FontLookup(data: d),
  );
}

class _FontLookup extends StatefulWidget {
  const _FontLookup({required this.data});

  final JourneyData data;

  @override
  State<_FontLookup> createState() => _FontLookupState();
}

class _FontLookupState extends State<_FontLookup> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3400),
  );
  int _i = 0;
  int? _prev;
  int _resolved = 0;
  bool _pinned = false;

  List<JGlyph> get _glyphs => widget.data.glyphs;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        setState(() {
          _resolved = math.max(_resolved, _i + 1);
          _prev = _i;
          if (!_pinned) _i = (_i + 1) % _glyphs.length;
        });
        _c.forward(from: 0);
      }
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 0 = first family, 1 = fallback family, 2 = platform fallback.
  int _hitIndex(JGlyph g) => g.font == widget.data.latin ? 0 : (g.font == widget.data.arabic ? 1 : 2);

  void _pick(int i) {
    setState(() {
      _i = i;
      _pinned = true;
    });
    _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final g = _glyphs[_i];
    final hit = _hitIndex(g);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        // Probing phase: 0..0.4 of the cycle walks down the font list.
        final probe = (t / 0.4 * (hit + 1)).clamp(0.0, hit + 1.0);
        final found = t > 0.4;
        // The detail keeps showing the last resolved glyph until this one lands.
        final shownIdx = found ? _i : _prev;
        final shown = shownIdx == null ? null : _glyphs[shownIdx];
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Code points → glyph ids
            Positioned(
              left: 0,
              top: 0,
              width: 300,
              bottom: 0,
              child: _CodePointList(
                glyphs: _glyphs,
                current: _i,
                resolved: _resolved,
                foundCurrent: found,
                onPick: _pick,
              ),
            ),
            // Probe lines
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ProbePainter(
                    from: Offset(300, _i * _rowH(_glyphs.length) + (_rowH(_glyphs.length) - 8) / 2),
                    cards: [for (var k = 0; k < 3; k++) Offset(360, _cardTop(k) + _cardH / 2)],
                    probe: probe,
                    hit: hit,
                  ),
                ),
              ),
            ),
            // Font collection
            for (var k = 0; k < 3; k++)
              Positioned(
                left: 360,
                top: _cardTop(k),
                width: 440,
                height: _cardH,
                child: _FontCard(
                  index: k,
                  font: k == 0 ? widget.data.latin : (k == 1 ? widget.data.arabic : null),
                  state: probe < k + 0.8
                      ? _Probe.idle
                      : (k == hit ? _Probe.hit : _Probe.miss),
                ),
              ),
            // Lookup detail
            Positioned(
              left: 860,
              top: 0,
              right: 0,
              bottom: 0,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: shown == null
                    ? const SizedBox.expand()
                    : KeyedSubtree(
                        key: ValueKey(shownIdx),
                        child: shown.font == null
                            ? _SystemFallback(glyph: shown, text: widget.data.text)
                            : _CmapDetail(glyph: shown, font: shown.font!),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

const _cardH = 172.0;
double _cardTop(int k) => 10 + k * (_cardH + 36);
double _rowH(int n) => math.min(66, 600 / math.max(1, n));

enum _Probe { idle, miss, hit }

class _CodePointList extends StatelessWidget {
  const _CodePointList({
    required this.glyphs,
    required this.current,
    required this.resolved,
    required this.foundCurrent,
    required this.onPick,
  });

  final List<JGlyph> glyphs;
  final int current;
  final int resolved;
  final bool foundCurrent;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final h = _rowH(glyphs.length);
    return Stack(
      children: [
        for (var i = 0; i < glyphs.length; i++)
          Positioned(
            left: 0,
            right: 0,
            top: i * h,
            height: h - 8,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => onPick(i),
                child: _CpRow(
                  glyph: glyphs[i],
                  active: i == current,
                  showId: i < resolved || (i == current && foundCurrent),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CpRow extends StatelessWidget {
  const _CpRow({required this.glyph, required this.active, required this.showId});

  final JGlyph glyph;
  final bool active;
  final bool showId;

  @override
  Widget build(BuildContext context) {
    final c = active ? BP.amber : BP.lineDim;
    final label = glyph.codePoint == 0x200D
        ? 'ZWJ'
        : (glyph.codePoint >= 0x1F3FB && glyph.codePoint <= 0x1F3FF ? '🏽' : glyph.char);
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 150,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active ? BP.amber.withValues(alpha: 0.1) : BP.panel,
            border: Border.all(color: c, width: active ? 2 : 1),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(label, textAlign: TextAlign.center, style: journeyStyle(24)),
              ),
              const SizedBox(width: 6),
              Text(glyph.hex, style: BT.mono(13, color: active ? BP.amber : BP.line)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: showId ? 1 : 0,
          child: Row(
            children: [
              Text('→', style: BT.mono(16, color: BP.inkFaint)),
              const SizedBox(width: 8),
              Text(
                glyph.font == null ? 'sys' : '#${glyph.glyphId}',
                style: BT.mono(20, color: glyph.font == null ? BP.violet : BP.green),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProbePainter extends CustomPainter {
  _ProbePainter({required this.from, required this.cards, required this.probe, required this.hit});

  final Offset from;
  final List<Offset> cards;
  final double probe;
  final int hit;

  @override
  void paint(Canvas canvas, Size size) {
    for (var k = 0; k <= hit; k++) {
      final local = (probe - k).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final miss = k < hit;
      final color = miss ? BP.red : BP.green;
      final a = from;
      final b = cards[k];
      final mid = Offset((a.dx + b.dx) / 2, a.dy);
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo(mid.dx, a.dy, mid.dx, b.dy, b.dx, b.dy);
      final p = Paint()
        ..color = color.withValues(alpha: miss ? 0.5 : 0.9)
        ..strokeWidth = miss ? 1.2 : 2
        ..style = PaintingStyle.stroke;
      canvas.drawPath(miss ? dashPath(partialPath(path, local)) : partialPath(path, local), p);
      final m = path.computeMetrics().first;
      final tan = m.getTangentForOffset(m.length * local);
      if (tan != null && local < 1) {
        canvas.drawCircle(tan.position, 5, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(_ProbePainter old) =>
      old.probe != probe || old.from != from || old.hit != hit;
}

class _FontCard extends StatelessWidget {
  const _FontCard({required this.index, required this.font, required this.state});

  final int index;
  final FontData? font;
  final _Probe state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _Probe.hit => BP.green,
      _Probe.miss => BP.red,
      _Probe.idle => BP.lineDim,
    };
    final role = ['fontFamily', 'fontFamilyFallback', 'platform font manager'][index];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: state == _Probe.hit ? BP.green.withValues(alpha: 0.07) : BP.panel,
        border: Border.all(color: color, width: state == _Probe.idle ? 1 : 2),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(role, style: BT.mono(12, color: BP.inkFaint)),
              const Spacer(),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  switch (state) {
                    _Probe.hit => '✓ has glyph',
                    _Probe.miss => '✕ no glyph',
                    _Probe.idle => '',
                  },
                  key: ValueKey(state),
                  style: BT.mono(13, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            font?.name ?? 'system fallback',
            style: BT.display(26, color: BP.ink),
          ),
          const SizedBox(height: 10),
          if (font != null) ...[
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final tag in font!.tables.keys)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: tag == 'cmap' && state == _Probe.hit ? BP.amber : Colors.transparent,
                      border: Border.all(color: tag == 'cmap' ? BP.amber : BP.lineFaint),
                    ),
                    child: Text(
                      tag,
                      style: BT.mono(11, color: tag == 'cmap' && state == _Probe.hit ? BP.paper : BP.inkDim),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              '${font!.numGlyphs} glyphs · ${(font!.fileSize / 1024).round()} KB · cmap format ${font!.cmapFormat}',
              style: BT.mono(12, color: BP.inkFaint),
            ),
          ] else ...[
            Text('Core Text · Android fonts · Noto (web)', style: BT.mono(13, color: BP.inkDim)),
            const Spacer(),
            Text('SkFontMgr::matchFamilyStyleCharacter', style: BT.mono(12, color: BP.inkFaint)),
          ],
        ],
      ),
    );
  }
}

class _CmapDetail extends StatelessWidget {
  const _CmapDetail({required this.glyph, required this.font});

  final JGlyph glyph;
  final FontData font;

  @override
  Widget build(BuildContext context) {
    final segs = font.segments;
    final hit = font.segmentIndexOf(glyph.codePoint);
    final from = (hit - 3).clamp(0, math.max(0, segs.length - 7)).toInt();
    final rows = segs.sublist(from, math.min(segs.length, from + 7));
    final seg = hit >= 0 ? segs[hit] : null;
    String h(int v) => v.toRadixString(16).toUpperCase().padLeft(4, '0');

    final String formula;
    if (seg == null) {
      formula = 'not mapped';
    } else if (seg.firstGlyph != null) {
      formula = '${seg.firstGlyph} + (${h(glyph.codePoint)} − ${h(seg.start)}) = #${glyph.glyphId}';
    } else if (seg.usesRange) {
      formula = 'glyphIdArray[…] = #${glyph.glyphId}';
    } else {
      formula = '0x${h(glyph.codePoint)} ${seg.delta >= 0 ? '+' : '−'} ${seg.delta.abs()} = #${glyph.glyphId}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('cmap', style: BT.mono(18, color: BP.amber)),
            const SizedBox(width: 10),
            Text('format ${font.cmapFormat} · ${segs.length} ${font.cmapFormat == 12 ? 'groups' : 'segments'}',
                style: BT.mono(13, color: BP.inkFaint)),
          ],
        ),
        const SizedBox(height: 10),
        // Segment table
        Container(
          decoration: BoxDecoration(border: Border.all(color: BP.lineDim)),
          child: Column(
            children: [
              _SegRow(cells: ['start', 'end', font.cmapFormat == 12 ? 'first' : 'Δ'], header: true),
              for (var r = 0; r < rows.length; r++)
                _SegRow(
                  hot: from + r == hit,
                  cells: [
                    h(rows[r].start),
                    h(rows[r].end),
                    rows[r].firstGlyph != null
                        ? '#${rows[r].firstGlyph}'
                        : (rows[r].usesRange ? 'array' : '${rows[r].delta}'),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(formula, style: BT.mono(17, color: BP.green)),
        const SizedBox(height: 16),
        Expanded(child: _GlyphCard(glyph: glyph, font: font)),
      ],
    );
  }
}

class _SegRow extends StatelessWidget {
  const _SegRow({required this.cells, this.header = false, this.hot = false});

  final List<String> cells;
  final bool header;
  final bool hot;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    color: hot ? BP.amber.withValues(alpha: 0.18) : (header ? BP.lineFaint.withValues(alpha: 0.4) : Colors.transparent),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
    child: Row(
      children: [
        for (final c in cells)
          Expanded(
            child: Text(
              c,
              style: BT.mono(14, color: hot ? BP.amber : (header ? BP.inkFaint : BP.inkDim)),
            ),
          ),
      ],
    ),
  );
}

/// The actual outline from the glyf table, with on/off-curve points.
class _GlyphCard extends StatelessWidget {
  const _GlyphCard({required this.glyph, required this.font});

  final JGlyph glyph;
  final FontData font;

  @override
  Widget build(BuildContext context) {
    final o = font.outline(glyph.glyphId);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 250,
          child: TweenAnimationBuilder<double>(
            key: ValueKey('${font.name}${glyph.glyphId}'),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            builder: (context, t, _) => CustomPaint(
              painter: _OutlinePainter(outline: o, advance: glyph.advance, font: font, t: t),
              size: const Size(250, 220),
            ),
          ),
        ),
        const SizedBox(width: 20),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('#${glyph.glyphId}', style: BT.display(44, color: BP.green)),
            const SizedBox(height: 8),
            JField('hmtx', 'advance ${glyph.advance}'),
            const SizedBox(height: 4),
            JField('    ', 'lsb ${font.leftSideBearing(glyph.glyphId)}'),
            const SizedBox(height: 4),
            JField('glyf', '${o.contours.length} contours · ${o.pointCount} pts'),
            const SizedBox(height: 4),
            JField('    ', 'units/em ${font.unitsPerEm}'),
          ],
        ),
      ],
    );
  }
}

class _OutlinePainter extends CustomPainter {
  _OutlinePainter({required this.outline, required this.advance, required this.font, required this.t});

  final GlyphOutline outline;
  final int advance;
  final FontData font;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final emH = (font.ascender - font.descender).toDouble();
    final scale = math.min((size.height - 20) / emH, (size.width - 20) / math.max(advance, 1));
    final baseline = 10 + font.ascender * scale;
    final left = (size.width - advance * scale) / 2;
    final origin = Offset(left, baseline);
    final guide = Paint()
      ..color = BP.lineFaint
      ..strokeWidth = 1;
    // Em box, baseline, advance
    canvas.drawRect(Rect.fromLTWH(left, 10, advance * scale, emH * scale), guide..style = PaintingStyle.stroke);
    canvas.drawLine(Offset(0, baseline), Offset(size.width, baseline), Paint()..color = BP.amber.withValues(alpha: 0.6));
    final path = outline.toPath(scale: scale, origin: origin);
    canvas.drawPath(path, Paint()..color = BP.ink.withValues(alpha: 0.12 * t));
    canvas.drawPath(
      partialPath(path, t),
      Paint()
        ..color = BP.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    if (t < 0.6) return;
    final a = ((t - 0.6) / 0.4).clamp(0.0, 1.0);
    final ctrl = Paint()
      ..color = BP.inkFaint.withValues(alpha: a)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (final c in outline.contours) {
      final pts = [for (final p in c) Offset(origin.dx + p.x * scale, origin.dy - p.y * scale)];
      if (pts.length > 1) canvas.drawPath(dashPath(Path()..addPolygon(pts, true), dash: 3, gap: 3), ctrl);
      for (var i = 0; i < c.length; i++) {
        if (c[i].onCurve) {
          canvas.drawRect(Rect.fromCenter(center: pts[i], width: 6, height: 6), Paint()..color = BP.amber.withValues(alpha: a));
        } else {
          canvas.drawCircle(pts[i], 3.2, Paint()..color = BP.paper);
          canvas.drawCircle(
            pts[i],
            3.2,
            Paint()
              ..color = BP.line.withValues(alpha: a)
              ..style = PaintingStyle.stroke,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_OutlinePainter old) => old.t != t || old.outline != outline;
}

class _SystemFallback extends StatelessWidget {
  const _SystemFallback({required this.glyph, required this.text});

  final JGlyph glyph;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('not in the bundled fonts', style: BT.mono(18, color: BP.violet)),
        const SizedBox(height: 16),
        BpPanel(
          label: 'platform emoji font',
          color: BP.violet,
          child: Row(
            children: [
              Text(text, style: journeyStyle(110)),
              const SizedBox(width: 28),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  JField('glyph', 'color, not an outline'),
                  const SizedBox(height: 6),
                  JField('apple', 'sbix bitmaps'),
                  const SizedBox(height: 6),
                  JField('noto', 'CBDT / COLRv1'),
                  const SizedBox(height: 6),
                  JField('web', 'Noto Color Emoji ↓'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('ZWJ + modifiers → one glyph via GSUB', style: BT.mono(14, color: BP.inkDim)),
      ],
    );
  }
}
