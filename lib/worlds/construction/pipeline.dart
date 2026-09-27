import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../deck/deck.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'site_kit.dart';

// The pipeline as a building cross-section: text/unicode is the foundation,
// raster is the top floor. Each build step, the crane sets the next floor
// and the construction hoist climbs to it; then the hoist keeps carrying
// "Hi كتاب" up through every floor built so far. Click a floor → its slide.

const _stages = [
  ('text', 'unicode', 'string', ['"Hi كتاب"', 'U+0048 U+0069 U+0020', 'U+0643 U+062A U+0627 U+0628']),
  ('itemize', 'ICU', 'itemize', ['[latin  → 0..3)', '[arabic ← 3..7)']),
  ('fonts', 'font manager', 'fallback', ['latin  → Space Grotesk', 'arabic → Noto Kufi Arabic']),
  ('shape', 'HarfBuzz', 'shaping', ['code points →', 'glyph ids + advances', '+ offsets']),
  ('wrap', 'ICU · UAX #14', 'linebreak', ['break opportunities', '→ lines that fit']),
  ('position', 'layout', 'bidi', ['visual order · baselines', '→ x, y per glyph']),
  ('raster', 'Skia · GPU', 'raster', ['outlines → coverage', '→ pixels']),
];

const _g = 500.0; // ground (local to the content area)
const _fh = 66.0;
const _bl = 440.0;
const _br = 1040.0;
const _split = 650.0; // labels | illustration
const _mastL = 1090.0;
const _mastR = 1112.0;
const _jibY = 20.0;
const _hoistX0 = 382.0;
const _hoistX1 = 400.0;

double _top(int k) => k == 0 ? _g : _g - k * _fh;
double _bottom(int k) => k == 0 ? _g + 66 : _g - (k - 1) * _fh;

class ConstructionPipeline extends StatelessWidget {
  const ConstructionPipeline({super.key});

  @override
  Widget build(BuildContext context) => const SlideFrame(title: 'The pipeline', child: _Body());
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0);
  final _labels = SiteLabels();
  final _rev = List<double?>.filled(7, null);
  bool _first = true;
  int? _hover;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => _clock.value = d.inMicroseconds / 1e6)..start();
    PaintingBinding.instance.systemFonts.addListener(_labels.clear);
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_labels.clear);
    _ticker.dispose();
    _clock.dispose();
    _labels.clear();
    super.dispose();
  }

  void _sync(int step) {
    final now = _clock.value;
    for (var k = 0; k < 7; k++) {
      if (k <= step) {
        // Coming back to a later step: everything below is already built.
        // First visit at step 0: pour the foundation. Coming back to a later
        // step: everything up to it is already built.
        _rev[k] ??= _first ? (step == 0 ? now + 0.5 : -10) : now;
      } else {
        _rev[k] = null;
      }
    }
    _first = false;
    _step = step;
  }

  @override
  Widget build(BuildContext context) {
    _sync(SlideScope.of(context).step);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _PipelinePainter(clock: _clock, labels: _labels, rev: List.of(_rev), step: _step, hover: _hover),
            ),
          ),
        ),
        for (var k = 0; k <= _step; k++)
          Positioned(
            left: _bl,
            top: _top(k),
            width: _br - _bl,
            height: _bottom(k) - _top(k),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hover = k),
              onExit: (_) => setState(() => _hover = null),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => DeckScope.read(context).goToId(_stages[k].$3),
              ),
            ),
          ),
      ],
    );
  }
}

class _PipelinePainter extends CustomPainter {
  _PipelinePainter({
    required this.clock,
    required this.labels,
    required this.rev,
    required this.step,
    required this.hover,
  }) : super(repaint: clock);

  final ValueNotifier<double> clock;
  final SiteLabels labels;
  final List<double?> rev;
  final int step;
  final int? hover;

  @override
  void paint(Canvas canvas, Size size) {
    _Frame(canvas, clock.value, labels, rev, step, hover).paint();
  }

  @override
  bool shouldRepaint(_PipelinePainter old) => old.step != step || old.hover != hover;
}

class _Frame {
  _Frame(this.c, this.t, this.labels, this.rev, this.step, this.hover) {
    k = SiteKit(c, t, labels, crew);
  }

  final Canvas c;
  final double t;
  final SiteLabels labels;
  final List<double?> rev;
  final int step;
  final int? hover;
  final crew = SiteCrew(scale: 1.0);
  late final SiteKit k;

  double _v(int f) => t - (rev[f] ?? 1e9);

  // ── Hoist: climbs to each new floor, then loops through all of them ───────

  /// (position in floors, floor it is stopped at).
  (double, int?) _cab() {
    final s = step;
    final u = _v(s);
    if (s == 0) return (0, 0);
    if (u < 1.4) {
      final f = seg01(u, 0.6, 1.4);
      return (s - 1 + eio(f), f <= 0 ? s - 1 : (f >= 1 ? s : null));
    }
    // Cycle: dwell at the top, go down, climb floor by floor.
    final down = 0.4 + 0.18 * s;
    final len = 1.6 + down + (s + 1) * 0.7 + s * 0.4;
    var w = (u - 1.4) % len;
    if (w < 1.6) return (s.toDouble(), s);
    w -= 1.6;
    if (w < down) return (s * (1 - eio(w / down)), null);
    w -= down;
    for (var f = 0; f <= s; f++) {
      if (w < 0.7) return (f.toDouble(), f);
      w -= 0.7;
      if (f < s) {
        if (w < 0.4) return (f + eio(w / 0.4), null);
        w -= 0.4;
      }
    }
    return (s.toDouble(), s);
  }

  void paint() {
    final (cab, stop) = _cab();
    final focus = hover ?? stop;

    _ground();
    // The crane serves the newest floor.
    _crane();
    for (var f = 0; f <= step; f++) {
      _floor(f, focus == f, stop == f);
    }
    if (step == 6) _roof(_v(6));
    _hoist(cab, stop);
    _yard();
    crew.flush(c);
    _board(hover ?? stop ?? step);
  }

  void _ground() {
    c.drawLine(const Offset(-20, _g), const Offset(1492, _g), strokeP(BP.line, 1.4));
    // Earth around the basement.
    final hatch = Path();
    for (var x = 320.0; x < 1120; x += 12) {
      if (x > _bl - 14 && x < _br + 8) continue;
      hatch
        ..moveTo(x, _g + 10)
        ..lineTo(x - 8, _g + 20);
    }
    c.drawPath(hatch, strokeP(BP.lineFaint, 1));
    labels.draw(c, '±0', const Offset(1480, _g - 4), size: 10, color: BP.inkFaint, ax: 1, ay: 1);
  }

  void _crane() {
    k.towerCrane(mastL: _mastL, mastR: _mastR, ground: _g, jibY: _jibY, jibL: 360, jibR: 1200);
    // Hook: lowering the newest slab, else parked and swaying.
    final f = step;
    final v = _v(f);
    final top = _top(f);
    const x = (_bl + _br) / 2;
    if (f > 0 && v >= 0 && v < 1.4) {
      final hang = _slabY(f, v);
      if (hang != null) {
        final r = Rect.fromLTRB(_bl - 6, hang - 5, _br + 6, hang + 5);
        k.slings(Offset(x, hang - 22), r.topLeft + const Offset(80, 0), r.topRight - const Offset(80, 0));
        k.trolley(x, _jibY, hang - 26);
        return;
      }
      final up = seg01(v, 0.95, 1.4);
      k.trolley(x, _jibY, lerpD(top - 26, 72, eio(up)));
      return;
    }
    k.trolley(x + math.sin(t * 0.5) * 50, _jibY, 72 + math.sin(t * 1.2) * 4);
  }

  /// While hanging, the y of floor [f]'s slab; null once it has landed.
  double? _slabY(int f, double v) {
    if (v < 0.2 || v >= 0.95) return null;
    final e = seg01(v, 0.2, 0.95);
    final top = _top(f);
    return e < 0.8 ? lerpD(_jibY + 60, top - 12, eio(e / 0.8)) : lerpD(top - 12, top, backOut((e - 0.8) / 0.2));
  }

  void _floor(int f, bool hot, bool served) {
    final v = _v(f);
    if (v < 0) return;
    final top = _top(f);
    final bot = _bottom(f);
    final rise = eo(seg01(v, 0, 0.45));
    final show = seg01(v, 0.8, 1.2);
    // Walls / columns rise.
    final walls = Path();
    for (final x in [_bl, _split, _br]) {
      walls
        ..moveTo(x, bot)
        ..lineTo(x, bot - (bot - top) * rise);
    }
    c.drawPath(walls, strokeP(BP.lineDim, 1.4));
    // Slab on top (the crane brings it), the basement just has walls.
    if (f == 0) {
      final base = partialPath(
        Path()
          ..moveTo(_bl - 8, _g)
          ..lineTo(_bl - 8, bot)
          ..lineTo(_br + 8, bot)
          ..lineTo(_br + 8, _g),
        rise,
      );
      c.drawPath(base, strokeP(BP.line, 2.2));
    } else if (_slabY(f, v) == null && v >= 0.95) {
      c.drawLine(Offset(_bl - 8, top), Offset(_br + 8, top), strokeP(BP.line, 2.4));
      k.dust(Offset(_bl + 40, top), v - 0.95, seed: f.toDouble(), n: 4, spread: 30, life: 0.7);
      k.dust(Offset(_br - 40, top), v - 0.95, seed: f + 0.5, n: 4, spread: 30, life: 0.7);
    } else {
      final y = _slabY(f, v);
      if (y != null) k.beam(Rect.fromLTRB(_bl - 6, y - 5, _br + 6, y + 5));
    }
    if (show <= 0) return;
    final room = Rect.fromLTRB(_bl + 1, top + 2, _br - 1, bot - 1);
    if (hot) {
      c.drawRect(room, fillP(BP.line.withValues(alpha: 0.07)));
      c.drawRect(room, strokeP(BP.amber, 1.6));
    }
    final (name, lib, _, _) = _stages[f];
    labels.draw(
      c,
      name,
      Offset(_bl + 18, top + 8),
      size: 24,
      color: hot ? BP.amber : BP.ink,
      display: true,
      alpha: show,
    );
    labels.draw(c, lib, Offset(_bl + 19, top + 40), size: 12, color: BP.inkDim, alpha: show);
    labels.draw(
      c,
      '0${f + 1}',
      Offset(_split - 12, top + 10),
      size: 12,
      color: hot ? BP.amber : BP.inkFaint,
      ax: 1,
      alpha: show,
    );
    c.save();
    final area = Rect.fromLTRB(_split + 16, top + 8, _br - 14, bot - 8);
    c.clipRect(area.inflate(6));
    _illustration(f, area, served || hot, show);
    c.restore();
  }

  void _roof(double v) {
    final f = seg01(v, 1.1, 1.6);
    if (f <= 0) return;
    final y = _top(6);
    final r = Rect.fromLTRB(_bl + 40, y - 16 * eo(f), _br - 40, y);
    c.drawRect(r, strokeP(BP.line, 1.2));
    if (f < 1) return;
    // Topping out: a flag on the roof.
    const px = _br - 70;
    c.drawLine(Offset(px, y - 16), Offset(px, y - 70), strokeP(BP.ink, 1.3));
    final flag = Path()..moveTo(px, y - 70);
    for (var i = 0; i <= 8; i++) {
      flag.lineTo(px + 34 * i / 8, y - 68 + math.sin(t * 5 - i * 0.7) * 2.4 * i / 8);
    }
    for (var i = 8; i >= 0; i--) {
      flag.lineTo(px + 34 * i / 8, y - 50 + math.sin(t * 5 - i * 0.7) * 2.4 * i / 8);
    }
    c.drawPath(flag..close(), fillP(BP.amber.withValues(alpha: 0.85)));
  }

  // ── The construction hoist on the left ─────────────────────────────────────

  void _hoist(double pos, int? stop) {
    final topF = _top(step) - 30;
    k.lattice(_hoistX0, _hoistX1, math.min(topF, _g - 30), _bottom(0), color: BP.lineDim);
    // Landing gates at every built floor.
    for (var f = 0; f <= step; f++) {
      if (_v(f) < 0.9) continue;
      final y = _bottom(f);
      c.drawLine(Offset(_hoistX1 + 2, y), Offset(_bl, y), strokeP(BP.lineDim, 1.4));
    }
    final y = lerpD(_bottom(pos.floor()), _bottom(math.min(6, pos.floor() + 1)), pos - pos.floor());
    final cab = Rect.fromLTRB(_hoistX1 + 3, y - 46, _bl - 3, y - 2);
    c.drawRect(cab, fillP(BP.paper));
    c.drawRect(cab, strokeP(stop != null ? BP.amber : BP.line, 1.4));
    c.drawLine(cab.topLeft, cab.bottomRight, strokeP(BP.lineFaint, 1));
    c.drawLine(Offset(_hoistX0 + 9, cab.top), Offset(_hoistX0 + 9, math.min(topF, _g - 30)), strokeP(BP.inkDim, 1));
    // The load: a crate of text, and the operator.
    final crate = Rect.fromLTRB(cab.left + 4, cab.bottom - 16, cab.right - 4, cab.bottom - 2);
    c.drawRect(crate, fillP(BP.paper));
    c.drawRect(crate, strokeP(BP.amber, 1));
    labels.draw(c, 'Hi', crate.center, size: 9, color: BP.amber, ax: 0.5, ay: 0.5);
    crew.head(Offset(cab.center.dx, cab.top + 12), 1);
  }

  /// Left of the hoist: where the text is delivered.
  void _yard() {
    final p = labels.get('Hi كتاب', 30, BP.ink, font: LabelFont.ja);
    final pallet = Rect.fromLTRB(150, _g - 14, 330, _g);
    c.drawRect(pallet, strokeP(BP.lineDim, 1.2));
    c.drawLine(Offset(pallet.left + 10, pallet.bottom), Offset(pallet.left + 10, pallet.top), strokeP(BP.lineDim, 1));
    c.drawLine(Offset(pallet.right - 10, pallet.bottom), Offset(pallet.right - 10, pallet.top), strokeP(BP.lineDim, 1));
    p.paint(c, Offset(pallet.center.dx - p.width / 2, pallet.top - p.height - 2));
    labels.draw(c, 'input', Offset(pallet.center.dx, _g + 10), size: 11, color: BP.inkFaint, ax: 0.5);
    // A worker wheels a barrow between the pallet and the hoist.
    final ph = (t / 7) % 1.0;
    final go = ph < 0.5;
    final f = go ? ph * 2 : 2 - ph * 2;
    final x = lerpD(120, 350, eio(f));
    final (hand, _, _) = crew.walker(Offset(x, _g), face: go ? 1 : -1, walk: t * 8, armF: 1.1, s: 1.1);
    final wheel = hand + Offset((go ? 1 : -1) * 16, 12);
    c.drawLine(hand, wheel + const Offset(0, -6), strokeP(BP.ink, 1.3));
    c.drawCircle(wheel, 3.5, strokeP(BP.line, 1.2));
    k.cone(const Offset(60, _g), s: 0.9);
    k.cone(const Offset(84, _g), s: 0.9);
  }

  // ── Site board on the right: the focused stage's readout ───────────────────

  void _board(int f) {
    if (_v(f) < 0.8) f = math.max(0, f - 1);
    const r = Rect.fromLTRB(1150, 150, 1466, 330);
    c.drawLine(const Offset(1190, 330), const Offset(1190, _g), strokeP(BP.lineDim, 1.3));
    c.drawLine(const Offset(1426, 330), const Offset(1426, _g), strokeP(BP.lineDim, 1.3));
    c.drawRect(r, fillP(BP.panel));
    c.drawRect(r, strokeP(BP.line, 1.2));
    final (name, lib, _, lines) = _stages[f];
    labels.draw(c, '0${f + 1} · $name', const Offset(1168, 166), size: 14, color: BP.amber);
    c.drawLine(const Offset(1168, 190), const Offset(1448, 190), strokeP(BP.lineDim, 1));
    for (var i = 0; i < lines.length; i++) {
      labels.draw(c, lines[i], Offset(1168, 206 + i * 30.0), size: 17, color: BP.ink, font: LabelFont.ja);
    }
    labels.draw(c, lib, const Offset(1448, 318), size: 11, color: BP.inkFaint, ax: 1, ay: 1);
  }

  // ── Per-floor illustrations ────────────────────────────────────────────────

  void _illustration(int f, Rect a, bool live, double alpha) {
    final ink = (live ? BP.ink : BP.inkDim).withValues(alpha: alpha);
    switch (f) {
      case 0:
        final txt = labels.get('Hi كتاب', 22, ink, font: LabelFont.ja);
        txt.paint(c, Offset(a.left, a.center.dy - txt.height / 2));
        const cps = ['0048', '0069', '0020', '0643', '062A', '0627', '0628'];
        final hi = live ? ((t * 2.5) % 7).floor() : -1;
        var x = a.left + txt.width + 18;
        for (var i = 0; i < cps.length; i++) {
          final p = labels.get(cps[i], 11, i == hi ? BP.amber : BP.line.withValues(alpha: alpha));
          if (x + p.width > a.right) break;
          p.paint(c, Offset(x, a.center.dy - p.height / 2));
          x += p.width + 8;
        }
      case 1:
        final l = labels.get('Hi', 22, BP.line.withValues(alpha: alpha), font: LabelFont.ja);
        final r = labels.get('كتاب', 22, BP.amber.withValues(alpha: alpha), font: LabelFont.ja);
        final y = a.top + 2;
        l.paint(c, Offset(a.left + 10, y));
        r.paint(c, Offset(a.left + 90, y));
        final d = live ? eio((t * 0.8) % 1.0) : 1.0;
        final base = a.top + l.height + 6;
        c.drawLine(Offset(a.left + 4, base), Offset(a.left + 4 + (l.width + 12) * d, base), strokeP(BP.line, 2));
        c.drawLine(
          Offset(a.left + 84 + r.width + 12, base),
          Offset(a.left + 84 + r.width + 12 - (r.width + 12) * d, base),
          strokeP(BP.amber, 2),
        );
        labels.draw(c, 'latin →', Offset(a.left + 180, a.top + 6), size: 11, color: BP.line);
        labels.draw(c, 'arabic ←', Offset(a.left + 180, a.top + 22), size: 11, color: BP.amber);
      case 2:
        const fonts = [('Aa', 'Space Grotesk'), ('ب', 'Noto Kufi'), ('😀', 'fallback')];
        final pick = live ? ((t / 0.9) % 3).floor() : 1;
        for (var i = 0; i < 3; i++) {
          final lift = i == pick ? 6.0 : 0.0;
          final box = Rect.fromLTWH(a.left + i * 44, a.bottom - 34 - lift, 38, 32);
          c.drawRect(box, fillP(BP.paper));
          c.drawRect(box, strokeP(i == pick ? BP.amber : BP.lineDim, 1.2));
          final g = labels.get(fonts[i].$1, 17, ink, font: LabelFont.ja);
          g.paint(c, box.center - Offset(g.width / 2, g.height / 2));
        }
        labels.draw(
          c,
          fonts[pick].$2,
          Offset(a.left + 146, a.center.dy),
          size: 12,
          color: BP.amber,
          ay: 0.5,
          alpha: alpha,
        );
      case 3:
        // Isolated letters slide together and join.
        const letters = ['ب', 'ا', 'ت', 'ك']; // visual order, left to right
        final ph = live ? (t / 2.4) % 1.0 : 1.0;
        final gather = eio(seg01(ph, 0.1, 0.55));
        final join = seg01(ph, 0.55, 0.7);
        final word = labels.get('كتاب', 30, ink, font: LabelFont.ja);
        final x0 = a.left + 12;
        final y = a.center.dy - word.height / 2;
        if (join < 1) {
          var x = x0;
          for (final l in letters) {
            final p = labels.get(l, 30, ink.withValues(alpha: ink.a * (1 - join)), font: LabelFont.ja);
            p.paint(c, Offset(x, y));
            x += p.width * lerpD(1.0, 0.55, gather) + 14 * (1 - gather);
          }
        }
        if (join > 0) {
          final p = labels.get('كتاب', 30, ink.withValues(alpha: ink.a * join), font: LabelFont.ja);
          p.paint(c, Offset(x0, y));
        }
        labels.draw(
          c,
          'isol → init medi fina',
          Offset(a.left + 150, a.center.dy),
          size: 11,
          color: BP.inkDim,
          ay: 0.5,
          alpha: alpha,
        );
      case 4:
        const words = <double>[34, 22, 46, 28, 40, 18, 30, 44, 26];
        final limit = a.left + 150 + (live ? 50 * math.sin(t * 1.3) : 0);
        var x = a.left;
        var row = 0;
        final bar = fillP((live ? BP.line : BP.lineDim).withValues(alpha: alpha));
        for (final w in words) {
          if (x + w > limit && x > a.left) {
            row++;
            x = a.left;
          }
          if (row > 2) break;
          c.drawRect(Rect.fromLTWH(x, a.top + 4 + row * 15, w, 8), bar);
          x += w + 6;
        }
        k.dashed(Offset(limit + 3, a.top - 2), Offset(limit + 3, a.bottom + 2), BP.amber, dash: 3, gap: 3);
      case 5:
        final base = a.bottom - 8;
        c.drawLine(Offset(a.left, base), Offset(a.left + 200, base), strokeP(BP.amber, 1.2));
        const hs = <double>[30, 22, 36, 16, 28, 24];
        final pen = live ? (t * 0.9) % 1.0 : 1.0;
        var x = a.left + 6;
        for (var i = 0; i < hs.length; i++) {
          if (i / hs.length > pen) break;
          c.drawRect(Rect.fromLTWH(x, base - hs[i], 22, hs[i]), strokeP(live ? BP.line : BP.lineDim, 1.1));
          c.drawCircle(Offset(x, base), 2.2, fillP(BP.amber));
          x += 30;
        }
        final tri = Path()
          ..moveTo(x, base)
          ..lineTo(x - 4, base + 7)
          ..lineTo(x + 4, base + 7)
          ..close();
        c.drawPath(tri, fillP(BP.amber));
        labels.draw(c, 'x, y', Offset(a.left + 230, a.center.dy), size: 12, color: BP.inkDim, ay: 0.5, alpha: alpha);
      default:
        const cov = [
          [0, 3, 8, 9, 6, 0],
          [0, 0, 0, 0, 9, 3],
          [0, 4, 8, 9, 9, 4],
          [5, 8, 1, 0, 9, 4],
          [8, 4, 0, 1, 9, 4],
          [5, 9, 7, 8, 7, 6],
        ];
        const cell = 8.0;
        final scan = live ? ((t * 1.2) % 1.3) : 2.0;
        for (var r = 0; r < 6; r++) {
          for (var q = 0; q < 6; q++) {
            final rect = Rect.fromLTWH(a.left + q * cell, a.top + r * cell, cell, cell);
            final on = (r * 6 + q) / 36 <= scan;
            final v = cov[r][q] / 9;
            if (on && v > 0) c.drawRect(rect, fillP(BP.ink.withValues(alpha: v * alpha)));
            c.drawRect(rect, strokeP(BP.lineFaint, 1));
          }
        }
        labels.draw(
          c,
          'coverage → pixels',
          Offset(a.left + 64, a.center.dy),
          size: 11,
          color: BP.inkDim,
          ay: 0.5,
          alpha: alpha,
        );
    }
  }
}
