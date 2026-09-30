import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../deck/font_data.dart';
import '../../../deck/theme.dart';
import '../../../deck/widgets.dart';
import '../../../slides/journey/journey.dart';
import 'frame.dart';

/// Stop 2: every code point asks the font collection "who has a glyph?".
/// fontFamily, then fontFamilyFallback, then the platform. Real cmap lookups,
/// real glyph ids, real glyf outlines.
class JFontSlide extends StatelessWidget {
  const JFontSlide({super.key});

  @override
  Widget build(BuildContext context) => SJourneyFrame(
    stop: 1,
    title: (_) => 'Find the glyphs',
    builder: (context, d) => _FontLookup(data: d),
  );
}

// Geometry (content-area coordinates).
const _tile = 70.0;
const _tileGap = 12.0;

const _flowY = 370.0; // the letter → font → id line
const _bigSize = 190.0;
const _bigTop = _flowY - _bigSize / 2;

const _cardX = 280.0;
const _cardW = 400.0;
const _cardH = 120.0;
const _cardGap = 20.0;
double _cardTop(int k) => 160 + k * (_cardH + _cardGap);
double _cardCy(int k) => _cardTop(k) + _cardH / 2;

const _idX = 780.0;
const _outlineX = 1000.0;
const _outlineTop = 120.0;

// Timing: each probe of one font takes [_segMs]; a found letter rests [_dwellMs].
const _segMs = 200;
const _dwellMs = 120;
const _sweepDelay = Duration(milliseconds: 500);

enum _Probe { idle, miss, hit }

class _FontLookup extends StatefulWidget {
  const _FontLookup({required this.data});

  final JourneyData data;

  @override
  State<_FontLookup> createState() => _FontLookupState();
}

class _FontLookupState extends State<_FontLookup> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  /// Letters probed by the current run, in order.
  List<int> _order = const [];

  /// Letters whose glyph id has been found.
  final Set<int> _found = {};

  /// The letter shown in detail once the run is over.
  int _sel = 0;
  bool _settled = false;
  Timer? _start;

  List<JGlyph> get _glyphs => widget.data.glyphs;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        setState(() {
          _found.addAll(_order);
          _settled = true;
        });
      }
    });
    _start = Timer(_sweepDelay, _sweep);
  }

  @override
  void dispose() {
    _start?.cancel();
    _c.dispose();
    super.dispose();
  }

  /// 0 = fontFamily, 1 = fontFamilyFallback, 2 = platform.
  int _hit(int i) {
    final f = _glyphs[i].font;
    return f == widget.data.latin ? 0 : (f == widget.data.arabic ? 1 : 2);
  }

  int _letterMs(int i) => (_hit(i) + 1) * _segMs + _dwellMs;

  void _run(List<int> order, int sel) {
    _start?.cancel();
    setState(() {
      _order = order;
      _sel = sel;
      _settled = false;
    });
    _c.duration = Duration(milliseconds: order.fold(0, (a, i) => a + _letterMs(i)));
    _c.forward(from: 0);
  }

  /// Every code point in turn, then settle on the first.
  void _sweep() {
    _found.clear();
    _run([for (var i = 0; i < _glyphs.length; i++) i], 0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // Where the run is: the active letter and how far its probe got
        // (0 … hit + 1, in fonts).
        var active = _sel;
        var probe = _settled ? _hit(_sel) + 1.0 : 0.0;
        final running = <int>{};
        if (!_settled && _order.isNotEmpty) {
          var e = _c.value * (_c.duration?.inMilliseconds ?? 0);
          for (final i in _order) {
            final ms = _letterMs(i);
            active = i;
            if (e < ms) {
              probe = (e / _segMs).clamp(0.0, _hit(i) + 1.0);
              if (probe >= _hit(i) + 1) running.add(i);
              break;
            }
            running.add(i);
            e -= ms;
            probe = _hit(i) + 1.0;
          }
        }
        final hit = _hit(active);
        final g = _glyphs[active];

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // ── The word, one tile per code point (tap one to look it up)
            Positioned(
              left: 0,
              top: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                textDirection: widget.data.rtl ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  for (var i = 0; i < _glyphs.length; i++) ...[
                    if (i > 0) const SizedBox(width: _tileGap),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => _run([i], i),
                        child: _Tile(
                          glyph: _glyphs[i],
                          active: i == active,
                          showId: _found.contains(i) || running.contains(i),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Probe lines: letter → fonts, hit font → glyph id
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _ProbePainter(probe: probe, hit: hit)),
              ),
            ),

            // ── The letter being looked up (tap: run the whole word again)
            Positioned(
              left: 0,
              top: _bigTop,
              width: _bigSize,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(onTap: _sweep, child: _BigLetter(glyph: g)),
              ),
            ),

            // ── The font collection
            for (var k = 0; k < 3; k++)
              Positioned(
                left: _cardX,
                top: _cardTop(k),
                width: _cardW,
                height: _cardH,
                child: _FontCard(
                  role: const ['fontFamily', 'fontFamilyFallback', 'platform'][k],
                  name: k == 0
                      ? widget.data.latin.name
                      : (k == 1 ? widget.data.arabic.name : 'system fonts'),
                  state: probe < k + 0.8 ? _Probe.idle : (k == hit ? _Probe.hit : _Probe.miss),
                ),
              ),

            // ── Glyph id + outline of the settled letter
            Positioned(
              left: _idX,
              top: _outlineTop,
              right: 0,
              bottom: 0,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _settled
                    ? KeyedSubtree(key: ValueKey(_sel), child: _GlyphDetail(glyph: _glyphs[_sel]))
                    : const SizedBox.expand(),
              ),
            ),
          ],
        );
      },
    );
  }
}

String _label(JGlyph g) => switch (g.codePoint) {
  0x200D => 'ZWJ',
  0xFE0F => 'VS16',
  _ => g.char,
};

class _Tile extends StatelessWidget {
  const _Tile({required this.glyph, required this.active, required this.showId});

  final JGlyph glyph;
  final bool active;
  final bool showId;

  @override
  Widget build(BuildContext context) {
    final label = _label(glyph);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: _tile,
          height: _tile,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? BP.amber.withValues(alpha: 0.12) : BP.panel,
            border: Border.all(color: active ? BP.amber : BP.lineDim, width: active ? 2.5 : 1.5),
          ),
          child: glyph.isJoinControl
              ? Text(label, style: BT.mono(16, color: BP.inkDim))
              : Text(label, style: journeyStyle(40)),
        ),
        const SizedBox(height: 8),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: showId ? 1 : 0,
          child: Text(
            glyph.font == null ? 'sys' : '#${glyph.glyphId}',
            style: BT.mono(20, color: glyph.font == null ? BP.violet : BP.green),
          ),
        ),
      ],
    );
  }
}

class _BigLetter extends StatelessWidget {
  const _BigLetter({required this.glyph});

  final JGlyph glyph;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: _bigSize,
        height: _bigSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: BP.amber.withValues(alpha: 0.08),
          border: Border.all(color: BP.amber, width: 2.5),
        ),
        child: glyph.isJoinControl
            ? Text(_label(glyph), style: BT.mono(40, color: BP.inkDim))
            : Text(_label(glyph), style: journeyStyle(120)),
      ),
      const SizedBox(height: 14),
      Text(glyph.hex, style: BT.mono(24, color: BP.line)),
    ],
  );
}

class _FontCard extends StatelessWidget {
  const _FontCard({required this.role, required this.name, required this.state});

  final String role;
  final String name;
  final _Probe state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _Probe.hit => BP.green,
      _Probe.miss => BP.red,
      _Probe.idle => BP.lineDim,
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: state == _Probe.hit ? BP.green.withValues(alpha: 0.08) : BP.panel,
        border: Border.all(color: color, width: state == _Probe.idle ? 1.5 : 2.5),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 22, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(role, style: BT.mono(18, color: BP.inkDim)),
                const SizedBox(height: 6),
                Text(name, maxLines: 1, softWrap: false, style: BT.display(32)),
              ],
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: Text(
              switch (state) {
                _Probe.hit => '✓',
                _Probe.miss => '✕',
                _Probe.idle => '',
              },
              key: ValueKey(state),
              style: BT.mono(34, color: color, weight: 600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Letter → each font in turn (red dashed = no glyph, green = found), then
/// the found font → the glyph id.
class _ProbePainter extends CustomPainter {
  _ProbePainter({required this.probe, required this.hit});

  final double probe;
  final int hit;

  static const _from = Offset(_bigSize + 10, _flowY);

  @override
  void paint(Canvas canvas, Size size) {
    for (var k = 0; k <= hit; k++) {
      final local = (probe - k).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final miss = k < hit;
      final color = miss ? BP.red : BP.green;
      final b = Offset(_cardX - 10, _cardCy(k));
      final path = _curve(_from, b);
      final p = Paint()
        ..color = color.withValues(alpha: miss ? 0.6 : 0.95)
        ..strokeWidth = miss ? 2 : 3
        ..style = PaintingStyle.stroke;
      final part = partialPath(path, local);
      canvas.drawPath(miss ? dashPath(part, dash: 8, gap: 6) : part, p);
      final m = path.computeMetrics().first;
      final tan = m.getTangentForOffset(m.length * local);
      if (tan != null && local < 1) canvas.drawCircle(tan.position, 7, Paint()..color = color);
      if (local >= 1 && !miss) drawArrowHead(canvas, b, b - const Offset(10, 0), p, 12);
    }
    // Found: font → glyph id.
    if (probe >= hit + 1) {
      final a = Offset(_cardX + _cardW + 10, _cardCy(hit));
      const b = Offset(_idX - 16, _flowY);
      final p = Paint()
        ..color = BP.green
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      canvas.drawPath(_curve(a, b), p);
      drawArrowHead(canvas, b, b - const Offset(10, 0), p, 12);
    }
  }

  static Path _curve(Offset a, Offset b) {
    final mx = (a.dx + b.dx) / 2;
    return Path()
      ..moveTo(a.dx, a.dy)
      ..cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
  }

  @override
  bool shouldRepaint(_ProbePainter old) => old.probe != probe || old.hit != hit;
}

/// Glyph id + the real outline from the glyf table (or the platform's glyph).
class _GlyphDetail extends StatelessWidget {
  const _GlyphDetail({required this.glyph});

  final JGlyph glyph;

  @override
  Widget build(BuildContext context) {
    final font = glyph.font;
    const outline = Rect.fromLTWH(_outlineX - _idX, 0, 1472 - _outlineX, 480);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (font != null)
          Positioned(
            left: 4,
            top: _flowY - _outlineTop - 84,
            child: Text('cmap', style: BT.mono(20, color: BP.amber)),
          ),
        Positioned(
          left: 0,
          top: _flowY - _outlineTop - 56,
          child: Text(
            font == null ? 'sys' : '#${glyph.glyphId}',
            style: BT.display(88, color: font == null ? BP.violet : BP.green, height: 1.2),
          ),
        ),
        Positioned.fromRect(
          rect: outline,
          child: font == null
              ? Center(child: Text(glyph.char, style: journeyStyle(220)))
              : TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 1000),
                  builder: (context, t, _) => CustomPaint(
                    painter: _OutlinePainter(
                      outline: font.outline(glyph.glyphId),
                      advance: glyph.advance,
                      font: font,
                      t: t,
                    ),
                  ),
                ),
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
    // Fit the ink (at least baseline … 0.72 em, so letters of one font share
    // a scale) and the advance. Bounds are font units, y up: top = yMin.
    final b = outline.bounds;
    final hi = math.max(b.bottom, 0.72 * font.unitsPerEm);
    final lo = math.min(b.top, 0.0);
    final l = math.min(b.left, 0.0);
    final r = math.max(b.right, advance.toDouble());
    const pad = 24.0;
    final scale = math.min((size.height - 2 * pad) / (hi - lo), (size.width - 2 * pad) / math.max(r - l, 1));
    final left = (size.width - (r - l) * scale) / 2 - l * scale;
    final baseline = (size.height - (hi - lo) * scale) / 2 + hi * scale;
    final origin = Offset(left, baseline);
    // Advance box and the baseline.
    canvas.drawRect(
      Rect.fromLTRB(left, baseline - hi * scale - pad / 2, left + advance * scale, baseline - lo * scale + pad / 2),
      Paint()
        ..color = BP.lineFaint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawLine(
      Offset(0, baseline),
      Offset(size.width, baseline),
      Paint()
        ..color = BP.amber.withValues(alpha: 0.6)
        ..strokeWidth = 1.5,
    );
    final path = outline.toPath(scale: scale, origin: origin);
    canvas.drawPath(path, Paint()..color = BP.ink.withValues(alpha: 0.2 * t));
    canvas.drawPath(
      partialPath(path, t),
      Paint()
        ..color = BP.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    if (t < 0.6) return;
    final a = ((t - 0.6) / 0.4).clamp(0.0, 1.0);
    final ctrl = Paint()
      ..color = BP.inkFaint.withValues(alpha: a)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (final c in outline.contours) {
      final pts = [for (final p in c) Offset(origin.dx + p.x * scale, origin.dy - p.y * scale)];
      if (pts.length > 1) canvas.drawPath(dashPath(Path()..addPolygon(pts, true), dash: 4, gap: 4), ctrl);
      for (var i = 0; i < c.length; i++) {
        if (c[i].onCurve) {
          canvas.drawRect(
            Rect.fromCenter(center: pts[i], width: 9, height: 9),
            Paint()..color = BP.amber.withValues(alpha: a),
          );
        } else {
          canvas.drawCircle(pts[i], 5, Paint()..color = BP.paper);
          canvas.drawCircle(
            pts[i],
            5,
            Paint()
              ..color = BP.line.withValues(alpha: a)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_OutlinePainter old) => old.t != t || old.outline != outline;
}
