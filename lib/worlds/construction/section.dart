import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../deck/deck.dart';
import '../../deck/scripts.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import '../../slides/journey/journey.dart';
import '../world.dart';
import 'building.dart';
import 'site_kit.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Section dividers: the building gains a floor at every section.
//   01 foundations       the pipeline poured as 7 footings
//   02 materials         trucks deliver every script; each needs its own tool
//   03 other architects  Chrome · Figma · Apple · Android across the street
//   04 building code     the inspector stamps Flutter's permits ✕ / ✓
//   05 follow one beam   one beam, stamped with the journey word, goes up
// One ticker → one painter per divider; everything is a function of time.
// ─────────────────────────────────────────────────────────────────────────────

const _ja = ['コードポイントからピクセルへ', '文字体系ごとに増えるルール', '他のエンジンはどうしている？', 'Flutterのトレードオフ', 'ひとつの単語の旅'];

const _kickers = ['foundations', 'materials from everywhere', 'other architects', 'building code', 'follow one beam'];

/// Pipeline stages poured as footings: (name, library, slide).
const footings = [
  ('text', 'unicode', 'string'),
  ('itemize', 'ICU', 'itemize'),
  ('fonts', 'font manager', 'fallback'),
  ('shape', 'HarfBuzz', 'shaping'),
  ('wrap', 'ICU · UAX #14', 'linebreak'),
  ('position', 'layout', 'bidi'),
  ('raster', 'Skia · GPU', 'raster'),
];

/// Delivered materials: (glyph, script, tool).
const _stock = [
  ('ع', Script.arabic, 'join'),
  ('कि', Script.devanagari, 'reorder'),
  ('ปั่น', Script.thai, 'stack'),
  ('한', Script.hangul, 'compose'),
  ('縦', Script.han, 'vertical'),
  ('👋🏽', Script.emoji, 'ZWJ'),
];

/// The other architects: (name, what it's built from, slide).
const _architects = [
  ('Chrome', 'LayoutNG → HarfBuzz → Skia', 'chrome'),
  ('Figma', 'C++ → WASM → WebGPU', 'figma'),
  ('Apple', 'TextKit 2 → Core Text', 'apple'),
  ('Android', 'StaticLayout → Minikin', 'android'),
];

/// Permits: (line 1, line 2, granted).
const _permits = [
  ('vertical', 'text', false),
  ('ruby', 'furigana', false),
  ('hyphens', 'auto', false),
  ('LCD', 'subpixel', false),
  ('same', 'everywhere', true),
  ('shaders', 'on text', true),
  ('widgets', 'in text', true),
];

const _g = Bld.ground;
const _lane = 782.0;

class ConstructionSection extends StatefulWidget {
  const ConstructionSection({super.key, required this.info});

  final SectionInfo info;

  @override
  State<ConstructionSection> createState() => _ConstructionSectionState();
}

class _Model {
  _Model(this.info);

  final SectionInfo info;
  final labels = SiteLabels();
  final hits = <(Rect, int)>[];
  int? hover;
  double hoverAt = 0;
  final pokes = <int, double>{};
  double replayAt = 0;
  TextPainter? number;
  TextPainter? title;
  TextPainter? shaded;

  void layoutText() {
    number?.dispose();
    title?.dispose();
    shaded?.dispose();
    shaded = TextPainter(
      text: TextSpan(
        text: 'Aa',
        style: BT
            .display(34, weight: 700)
            .copyWith(
              foreground: Paint()
                ..shader = const LinearGradient(
                  colors: [BP.amber, BP.pink, BP.violet],
                ).createShader(const Rect.fromLTWH(0, 0, 50, 40)),
            ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    number = TextPainter(
      text: TextSpan(
        text: info.number,
        style: BT
            .display(210, weight: 700, height: 1)
            .copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..color = BP.line,
            ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    title = TextPainter(
      text: TextSpan(text: info.title, style: BT.display(66, letterSpacing: -1.5, height: 1.1)),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  int? hitAt(Offset p) {
    for (final (r, id) in hits.reversed) {
      if (r.contains(p)) return id;
    }
    return null;
  }

  void dispose() {
    labels.clear();
    number?.dispose();
    title?.dispose();
    shaded?.dispose();
  }
}

class _ConstructionSectionState extends State<ConstructionSection> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0);
  late final _Model _m = _Model(widget.info)..layoutText();
  bool _pointer = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => _clock.value = d.inMicroseconds / 1e6)..start();
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
  }

  void _fontsChanged() {
    _m.labels.clear();
    _m.layoutText();
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    _ticker.dispose();
    _clock.dispose();
    _m.dispose();
    super.dispose();
  }

  void _hover(Offset p) {
    final id = _m.hitAt(p);
    if (id != _m.hover) {
      _m.hover = id;
      _m.hoverAt = _clock.value;
    }
    final pointer = id != null;
    if (pointer != _pointer) setState(() => _pointer = pointer);
  }

  void _tap(Offset p) {
    final id = _m.hitAt(p);
    final t = _clock.value;
    switch (widget.info.index) {
      case 0:
        if (id != null) DeckScope.read(context).goToId(footings[id].$3);
      case 2:
        if (id != null) DeckScope.read(context).goToId(_architects[id].$3);
      case 4:
        _m.replayAt = t;
      default:
        if (id != null) _m.pokes[id] = t;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _pointer ? SystemMouseCursors.click : MouseCursor.defer,
      onHover: (e) => _hover(e.localPosition),
      onExit: (_) {
        _m.hover = null;
        if (_pointer) setState(() => _pointer = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (d) => _tap(d.localPosition),
        child: SizedBox.expand(
          child: CustomPaint(
            painter: _SectionPainter(
              model: _m,
              clock: _clock,
              repaint: Listenable.merge([_clock, if (widget.info.index == 4) journeyWord]),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionPainter extends CustomPainter {
  _SectionPainter({required this.model, required this.clock, required Listenable repaint}) : super(repaint: repaint);

  final _Model model;
  final ValueNotifier<double> clock;

  @override
  void paint(Canvas canvas, Size size) {
    model.hits.clear();
    _Scene(canvas, model, clock.value).paint();
  }

  @override
  bool shouldRepaint(_SectionPainter old) => old.model != model;
}

class _Scene {
  _Scene(this.c, this.m, this.t) : crew = SiteCrew(), labels = m.labels {
    k = SiteKit(c, t, labels, crew);
  }

  final Canvas c;
  final _Model m;
  final double t;
  final SiteCrew crew;
  final SiteLabels labels;
  late final SiteKit k;

  int get i => m.info.index;

  /// Local build time: starts once the crane has set the slide down.
  double get b => t - 0.7;

  void paint() {
    _text();
    switch (i) {
      case 0:
        _foundations();
      case 1:
        _materials();
      case 2:
        _architectsScene();
      case 3:
        _code();
      default:
        _beam();
    }
    crew.flush(c);
  }

  // ── Title block ────────────────────────────────────────────────────────────

  void _text() {
    final n = m.number!;
    final title = m.title!;
    const x0 = 104.0;
    final a = seg01(t, 0.15, 0.8);
    if (a > 0) {
      c.saveLayer(Rect.fromLTWH(x0 - 10, 20, n.width + 20, n.height + 20), Paint()..color = Color.fromRGBO(0, 0, 0, a));
      n.paint(c, Offset(x0, 36 + 20 * (1 - eo(a))));
      c.restore();
    }
    final tx = x0 + n.width + 44;
    final maxW = 1500 - tx;
    final sc = math.min(1.0, maxW / title.width);
    // Kicker.
    final kv = seg01(t, 0.2, 0.7);
    c.drawLine(Offset(tx, 86), Offset(tx + 28 * eo(kv), 86), strokeP(BP.amber, 1.5));
    labels.draw(c, _kickers[i], Offset(tx + 40, 86), size: 16, color: BP.amber, ay: 0.5, alpha: kv);
    // Title, wiped on.
    final tv = eo(seg01(t, 0.35, 1.2));
    if (tv > 0) {
      c.save();
      c.clipRect(Rect.fromLTWH(tx - 4, 96, (title.width * sc + 8) * tv, title.height * sc + 20));
      c.translate(tx, 104);
      c.scale(sc);
      title.paint(c, Offset.zero);
      c.restore();
    }
    // Japanese subtitle.
    final jv = seg01(t, 0.9, 1.5);
    labels.draw(
      c,
      _ja[i],
      Offset(tx + 2, 104 + title.height * sc + 16),
      size: 28,
      color: BP.inkDim,
      font: LabelFont.ja,
      alpha: jv,
    );
    // Rule.
    final rv = eio(seg01(t, 0.1, 1.1));
    c.drawLine(const Offset(x0, 272), Offset(x0 + (1380 - x0) * rv, 272), strokeP(BP.lineDim, 1));
    for (var s = 0; s < 5; s++) {
      final x = x0 + s * (1380 - x0) / 4;
      if (x > x0 + (1380 - x0) * rv) break;
      c.drawLine(Offset(x, 266), Offset(x, 278), strokeP(s == i ? BP.amber : BP.lineDim, s == i ? 2 : 1));
    }
  }

  // ── Shared scenery ─────────────────────────────────────────────────────────

  void _crane(double x, double hookY, {void Function(double x, double y)? load}) {
    k.towerCrane(mastL: Bld.mastL, mastR: Bld.mastR, ground: _g, jibY: Bld.jibY, jibL: Bld.jibL, jibR: Bld.jibR);
    load?.call(x, hookY);
    k.trolley(x, Bld.jibY, hookY);
  }

  /// Crane lowering the slab of floor [n] at progress [p]; idle otherwise.
  void _slabCrane(int n, double p) {
    final (r, hanging) = slabAt(n, p);
    if (hanging && r != null) {
      _crane(
        Bld.cx,
        r.top - 14,
        load: (x, y) => k.slings(Offset(x, y + 4), r.topLeft + const Offset(40, 0), r.topRight - const Offset(40, 0)),
      );
    } else if (p < 0.3) {
      final f = seg01(p, 0.05, 0.3);
      _crane(Bld.cx, lerpD(420, Bld.jibY + 70, eio(f)));
    } else {
      final f = seg01(p, 0.7, 0.85);
      _crane(Bld.cx + math.sin(t * 0.6) * 60 * f, lerpD(Bld.top(n) - 14, 420, eio(f)) + math.sin(t * 1.3) * 6 * f);
    }
  }

  void _coffeeCorner() {
    final p = Path()
      ..moveTo(1492, _g - 14)
      ..lineTo(1572, _g - 14)
      ..moveTo(1498, _g - 14)
      ..lineTo(1498, _g)
      ..moveTo(1566, _g - 14)
      ..lineTo(1566, _g);
    c.drawPath(p, strokeP(BP.lineDim, 1.3));
    final sip = ((t + i * 2.3) % 7.0) < 1.6;
    const seatA = Offset(1510, _g - 14);
    final (ha, _, headA) = crew.sitter(seatA, face: 1, handF: sip ? null : seatA + const Offset(8, -5), armF: 2.2);
    final cupA = sip ? headA + const Offset(4, 3) : ha;
    c.drawRect(Rect.fromCenter(center: cupA, width: 4, height: 5), strokeP(BP.ink, 1.2));
    if (!sip) k.steam(cupA, 0.1);
    final yb = (t + 4 + i) % 13.0;
    final doze = yb > 5 && yb < 9.5;
    const seatB = Offset(1556, _g - 14);
    final (hb, _, headB) = crew.sitter(seatB, face: -1, lean: doze ? 0.35 : 0, armF: 0.9, armB: 0.2);
    c.drawRect(Rect.fromCenter(center: hb, width: 4, height: 5), strokeP(BP.ink, 1.2));
    if (doze) {
      k.snore(headB, yb - 5);
    } else {
      k.steam(hb, 0.6);
    }
  }

  /// A worker hammering on the scaffold at [y] (standing on the plank).
  void _hammerer(Offset feet, double seed, {double face = 1}) {
    final ph = ((t + seed) / 0.5) % 1.0;
    final arm = ph < 0.75 ? lerpD(1.3, 2.8, eo(ph / 0.75)) : lerpD(2.8, 1.25, (ph - 0.75) / 0.25);
    final (hand, _, head) = crew.walker(feet, face: face, stride: 0, armF: arm, armB: 0.3);
    final dir = hand - (head + const Offset(0, 5));
    final nrm = dir / math.max(0.01, dir.distance);
    final hd = hand + nrm * 4;
    c.drawLine(hd - Offset(-nrm.dy, nrm.dx) * 3, hd + Offset(-nrm.dy, nrm.dx) * 3, strokeP(BP.ink, 2.4));
    k.sparks(
      (_) => feet + Offset(14 * face, -8),
      n: 6,
      life: 0.3,
      seed: seed,
      power: 0.7,
      gate: (born) => ((born + seed) / 0.5) % 1.0 < 0.06,
    );
  }

  /// Welder on the newest slab, sparks at the column joint.
  void _welders(int n, double p) {
    final w = winAt(p, 0.68, 1.0, 0.04);
    if (w <= 0) return;
    final y = Bld.top(n);
    for (final j in [1, 4]) {
      final x = Bld.left + j * Bld.bay;
      crew.walker(Offset(x - 12, y), stride: 0, lean: 0.4, handF: Offset(x - 2, y - 4), armB: 0.4);
      c.drawCircle(Offset(x, y - 3), 3, fillP(BP.amber.withValues(alpha: 0.4 + 0.3 * hash1(t * 20 + j))));
      k.sparks((_) => Offset(x, y - 3), n: 8, life: 0.4, seed: j.toDouble() + n);
    }
  }

  // ── 01 Foundations ─────────────────────────────────────────────────────────

  double _pour(int j) => 1.6 + j * 0.8;

  void _foundations() {
    paintGround(k, pit: true);
    _excavator();
    // Excavation pit.
    final pit = Path()
      ..moveTo(Bld.left - 24, _g)
      ..lineTo(Bld.left - 14, Bld.footBottom + 6)
      ..lineTo(Bld.right + 14, Bld.footBottom + 6)
      ..lineTo(Bld.right + 24, _g);
    c.drawPath(pit, strokeP(BP.lineDim, 1.2));
    // The building to come.
    paintBuilding(k, foundation: false, done: 0);
    final done = b > _pour(6) + 0.6;
    // Blinding slab once every footing is poured.
    final slab = seg01(b, _pour(6) + 0.6, _pour(6) + 1.3);
    if (slab > 0) {
      final r = Rect.fromLTRB(Bld.left - 10, _g, Bld.left - 10 + (Bld.width + 20) * eio(slab), Bld.footTop);
      c.drawRect(r, fillP(BP.lineFaint.withValues(alpha: 0.5)));
      c.drawRect(r, strokeP(BP.line, 1.2));
    }
    // Footings: formwork, then concrete, then the stage name stamped in.
    for (var j = 0; j < 7; j++) {
      final r = Bld.footing(j);
      final fill = seg01(b, _pour(j), _pour(j) + 0.45);
      final hot = m.hover == j;
      if (fill > 0) {
        final fr = Rect.fromLTRB(r.left, r.bottom - r.height * eo(fill), r.right, r.bottom);
        c.drawRect(fr, fillP(BP.inkFaint.withValues(alpha: 0.45)));
        final dots = Path();
        for (var q = 0; q < 10; q++) {
          final o = Offset(
            r.left + 4 + (r.width - 8) * hash2(j.toDouble(), q.toDouble()),
            r.bottom - 3 - (r.height - 6) * hash2(q + 0.5, j + 0.3),
          );
          if (fr.contains(o)) dots.addOval(Rect.fromCircle(center: o, radius: 0.9));
        }
        c.drawPath(dots, fillP(BP.inkDim));
      }
      c.drawPath(dashPath(Path()..addRect(r), dash: 4, gap: 3), strokeP(hot ? BP.amber : BP.lineDim, hot ? 1.6 : 1));
      final lv = seg01(b, _pour(j) + 0.4, _pour(j) + 0.7);
      final flash = 1 - seg01(b, _pour(j) + 0.45, _pour(j) + 1.0);
      if (lv > 0) {
        if (flash > 0 && flash < 1) c.drawRect(r.inflate(2), strokeP(BP.amber.withValues(alpha: flash), 1.5));
        labels.draw(
          c,
          footings[j].$1,
          r.center + const Offset(0, 2),
          size: 11,
          color: hot ? BP.amber : BP.ink,
          ax: 0.5,
          ay: 0.5,
          alpha: lv,
        );
      }
      m.hits.add((r.inflate(4), j));
      if (hot) {
        final tag = labels.get(footings[j].$2, 12, BP.amber);
        final at = Offset(r.center.dx, _g - 70);
        final box = Rect.fromCenter(center: at, width: tag.width + 16, height: tag.height + 8);
        c.drawRect(box, fillP(BP.paper));
        c.drawRect(box, strokeP(BP.amber, 1));
        tag.paint(c, box.topLeft + const Offset(8, 4));
        k.dashed(Offset(r.center.dx, box.bottom), Offset(r.center.dx, r.top - 2), BP.amber, dash: 3, gap: 3);
      }
    }

    // Mixer truck, parked, facing left; its drum keeps turning.
    k.truck(840, _lane, -1, 1, null);
    // Chute from the drum.
    c.drawLine(const Offset(934, _lane - 30), const Offset(962, _lane - 16), strokeP(BP.line, 1.6));

    // The concrete skip on the crane: mixer → footing j → pour → next.
    var x = 948.0;
    var y = 560.0;
    var pouring = -1;
    if (b < _pour(0) - 0.45) {
      x = 948;
      y = lerpD(460, _g - 40, eio(seg01(b, 0, 0.9)));
    } else if (!done) {
      var j = 0;
      for (var q = 0; q < 7; q++) {
        if (b >= _pour(q) - 0.45) j = q;
      }
      final u = b - _pour(j);
      final from = j == 0 ? 948.0 : Bld.footing(j - 1).center.dx;
      final to = Bld.footing(j).center.dx;
      x = lerpD(from, to, eio(seg01(u, -0.45, -0.1)));
      final dip = winAt(u, -0.3, 0.6, 0.2);
      y = lerpD(_g - 70, _g - 30, dip);
      if (u >= 0 && u < 0.45) pouring = j;
    } else {
      final f = seg01(b, _pour(6) + 0.6, _pour(6) + 1.8);
      x = lerpD(Bld.footing(6).center.dx, 948, eio(f)) + math.sin(t * 0.7) * 10 * f;
      y = lerpD(_g - 70, _g - 40, f) + math.sin(t * 1.3) * 3 * f;
    }
    _crane(
      x,
      y - 26,
      load: (hx, hy) {
        final skip = Path()
          ..moveTo(hx - 13, hy + 8)
          ..lineTo(hx + 13, hy + 8)
          ..lineTo(hx + 8, hy + 28)
          ..lineTo(hx - 8, hy + 28)
          ..close();
        c.drawLine(Offset(hx, hy + 3), Offset(hx - 12, hy + 8), strokeP(BP.inkDim, 1));
        c.drawLine(Offset(hx, hy + 3), Offset(hx + 12, hy + 8), strokeP(BP.inkDim, 1));
        c.drawPath(skip, fillP(BP.paper));
        c.drawPath(skip, strokeP(BP.line, 1.3));
        if (pouring >= 0) {
          final r = Bld.footing(pouring);
          final stream = Path();
          for (var s = 0; s < 3; s++) {
            final sx = hx - 4 + s * 4;
            final off = (t * 90 + s * 7) % 8;
            for (var yy = hy + 30 + off; yy < r.bottom - 2; yy += 8) {
              stream
                ..moveTo(sx, yy)
                ..lineTo(sx, math.min(r.bottom - 2, yy + 5));
            }
          }
          c.drawPath(stream, strokeP(BP.inkDim, 1.4));
        }
      },
    );

    // Crew: a digger by the pit, a trowel hand on the slab, the surveyor.
    final dig = (t * 1.1) % 1.0;
    final (hand, _, _) = crew.walker(
      const Offset(Bld.left - 64, _g),
      face: 1,
      stride: 0,
      lean: 0.35 * math.sin(dig * math.pi),
      armF: lerpD(0.6, 1.6, dig),
      armB: lerpD(0.9, 1.8, dig),
    );
    c.drawLine(hand + const Offset(-6, -8), hand + const Offset(10, 12), strokeP(BP.ink, 1.6));
    if (dig > 0.55 && dig < 0.95) {
      final f = (dig - 0.55) / 0.4;
      for (var q = 0; q < 3; q++) {
        c.drawCircle(hand + Offset(-8 - 22 * f - q * 3, 12 - 26 * f + 40 * f * f), 1.4, fillP(BP.inkDim));
      }
    }
    if (done) {
      final ph = ((b - _pour(6)) / 9) % 1.0;
      final f = ph < 0.5 ? ph * 2 : 2 - ph * 2;
      final wx = lerpD(Bld.left + 20, Bld.right - 20, eio(f));
      final (h2, _, _) = crew.walker(Offset(wx, _g), face: ph < 0.5 ? 1 : -1, walk: t * 8, stride: 0.6, armF: 1.3);
      c.drawLine(h2 + const Offset(-5, 6), h2 + const Offset(7, 6), strokeP(BP.ink, 2));
      // The surveyor re-checks the level, like on the title.
      final sv = ((b - _pour(6)) % 8.0) / 2.2;
      crew.walker(
        const Offset(Bld.right + 70, _g),
        face: -1,
        stride: 0,
        lean: 0.4,
        handF: const Offset(Bld.right + 58, _g - 22),
      );
      final tri = Path()
        ..moveTo(Bld.right + 52, _g)
        ..lineTo(Bld.right + 57, _g - 18)
        ..lineTo(Bld.right + 62, _g)
        ..moveTo(Bld.right + 57, _g - 18)
        ..lineTo(Bld.right + 57, _g);
      c.drawPath(tri, strokeP(BP.line, 1));
      c.drawRect(const Rect.fromLTWH(Bld.right + 51, _g - 27, 11, 8), strokeP(BP.line, 1.2));
      if (sv < 1) {
        final lx = lerpD(Bld.right + 50, Bld.left - 10, eio(sv));
        k.dashed(Offset(Bld.right + 50, _g - 2), Offset(lx, _g - 2), BP.amber.withValues(alpha: 0.8));
        labels.draw(
          c,
          'level ±0',
          Offset(Bld.left - 16, _g - 16),
          size: 10,
          color: BP.amber,
          ax: 1,
          alpha: winAt(sv, 0.6, 1.0, 0.1),
        );
      }
    }
    k.cone(const Offset(Bld.left - 110, _g));
    k.cone(const Offset(Bld.right + 30, _g));
    _coffeeCorner();
  }

  // ── 02 Materials from everywhere ───────────────────────────────────────────

  double _crateX(int j) => 880.0 - j * 140;
  double _truckStart(int j) => 0.3 + j * 1.05;

  void _materials() {
    paintGround(k);
    final p = seg01(b, 0.2, 3.4);
    paintScaffold(k, Bld.top(1) - 4);
    paintBuilding(k, done: 0, p: p);
    _welders(1, p);
    _hammerer(Offset(Bld.left - 20, Bld.top(1) - 4), 0.3, face: 1);

    for (var j = 0; j < _stock.length; j++) {
      final (glyph, script, tool) = _stock[j];
      final s0 = _truckStart(j);
      final arrive = s0 + 1.2;
      final land = arrive + 0.55;
      final xc = _crateX(j);
      final xt = xc + 33;
      final u = b;
      // Truck.
      if (u > s0 && u < land + 1.8) {
        double tx;
        if (u < arrive) {
          tx = lerpD(-200, xt, eo(seg01(u, s0, arrive)));
        } else if (u < land) {
          tx = xt;
        } else {
          tx = lerpD(xt, 1800, ei(seg01(u, land, land + 1.8)));
        }
        k.truck(tx, _lane, 1, 4, null);
        if (u < arrive) _crate(Offset(tx - 33, _lane - 16), glyph, script, j, 0);
      }
      // Crate hop onto the yard, then the material stands up in it.
      if (u >= arrive) {
        final f = seg01(u, arrive, land);
        final pos = Offset(xc, lerpD(_lane - 16, _g, eio(f)) - 30 * math.sin(f * math.pi));
        _crate(pos, glyph, script, j, seg01(u, land + 0.2, land + 0.8));
        k.dust(Offset(xc, _g), u - land, seed: j.toDouble(), spread: 36);
        if (u > land + 0.5) _crateLife(j, xc, u - land - 0.5, tool, script);
      }
    }
    _slabCrane(1, p);
    _coffeeCorner();
  }

  void _crate(Offset bottom, String glyph, Script script, int j, double rise) {
    const w = 96.0;
    const h = 44.0;
    final hot = m.hover == j;
    final poke = m.pokes[j];
    final pop = poke == null ? 0.0 : winAt(t - poke, 0, 0.8, 0.15);
    final grow = hot ? eo((t - m.hoverAt) / 0.3) : 0.0;
    // The material stands up out of its crate.
    if (rise > 0) {
      final gp = labels.get(glyph, 60, script.color, font: LabelFont.ja);
      final sc = 1 + 0.5 * grow + 0.25 * pop;
      final base = bottom + Offset(0, -h + 14 - 50 * eo(rise) - 10 * pop);
      c.save();
      c.clipRect(Rect.fromLTRB(bottom.dx - 200, 0, bottom.dx + 200, bottom.dy - h + 2));
      c.translate(base.dx, base.dy);
      c.scale(sc);
      gp.paint(c, Offset(-gp.width / 2, -gp.height * 0.72));
      c.restore();
    }
    final r = Rect.fromLTRB(bottom.dx - w / 2, bottom.dy - h, bottom.dx + w / 2, bottom.dy);
    c.drawRect(r, fillP(BP.paper));
    c.drawRect(r, strokeP(hot ? BP.amber : BP.line, 1.2));
    c.drawLine(r.topLeft + const Offset(0, 6), r.topRight + const Offset(0, 6), strokeP(BP.lineDim, 1));
    c.drawLine(r.topLeft + const Offset(0, 6), r.bottomRight, strokeP(BP.lineFaint, 1));
    labels.draw(c, script.label, r.center + const Offset(0, 5), size: 10, color: script.color, ax: 0.5, ay: 0.5);
    if (rise > 0) m.hits.add((Rect.fromLTRB(r.left - 6, r.top - 130, r.right + 6, r.bottom), j));
  }

  void _crateLife(int j, double xc, double u, String tool, Script script) {
    final hot = m.hover == j;
    // Tool tag above the material.
    final tv = seg01(u, 0.2, 0.6);
    final tag = labels.get(tool, 13, hot ? BP.amber : script.color);
    final box = Rect.fromCenter(center: Offset(xc, _g - 178), width: tag.width + 36, height: tag.height + 10);
    if (tv > 0) {
      c.save();
      c.translate(0, 8 * (1 - eo(tv)));
      final col = (hot ? BP.amber : script.color).withValues(alpha: tv);
      c.drawRect(box, fillP(BP.paper));
      c.drawRect(box, strokeP(col, 1));
      _toolIcon(j, Offset(box.left + 12, box.center.dy), col);
      labels.draw(
        c,
        tool,
        Offset(box.left + 26, box.center.dy),
        size: 13,
        color: hot ? BP.amber : script.color,
        ay: 0.5,
        alpha: tv,
      );
      c.restore();
    }
    // A worker per crate, each with a different job.
    final feet = Offset(xc + 62, _g);
    final poke = m.pokes[j];
    final jump = poke == null ? 0.0 : -math.sin(seg01(t - poke, 0, 0.5) * math.pi) * 10;
    final f = feet + Offset(0, jump);
    switch (j % 6) {
      case 0: // joining: welding the joint
        final (hand, _, _) = crew.walker(f, face: -1, stride: 0, lean: 0.3, handF: Offset(xc + 34, _g - 26), armB: 0.5);
        c.drawLine(hand, Offset(xc + 30, _g - 30), strokeP(BP.inkDim, 1.6));
        k.sparks((_) => Offset(xc + 30, _g - 30), n: 7, life: 0.4, seed: j.toDouble());
      case 1: // reorder: carries a piece from the right side to the left
        final ph = (u / 3.2) % 1.0;
        final go = ph < 0.5;
        final g2 = go ? ph * 2 : 2 - ph * 2;
        final x = lerpD(xc + 56, xc - 56, eio(g2));
        final (_, _, head) = crew.walker(Offset(x, _g + jump), face: go ? -1 : 1, walk: u * 9, armF: go ? 2.6 : null);
        if (go) {
          c.drawRect(
            Rect.fromCenter(center: head + const Offset(0, -9), width: 12, height: 7),
            strokeP(script.color, 1.2),
          );
        }
      case 2: // stack: marks stacked on top of each other
        final n = ((u / 0.7) % 4).floor();
        for (var q = 0; q < n; q++) {
          c.drawRect(Rect.fromLTWH(xc + 38, _g - 6 - q * 6, 14, 5), strokeP(script.color, 1));
        }
        crew.walker(f + const Offset(14, 0), face: -1, stride: 0, armF: 1.6 + 0.4 * math.sin(u * 5), armB: 0.4);
      case 3: // compose: scratching his head over jamo blocks
        final (_, _, head) = crew.walker(
          f,
          face: -1,
          stride: 0,
          handB: null,
          armF: 0.4,
          armB: 2.9 + 0.15 * math.sin(u * 12),
        );
        labels.draw(c, '?', head + Offset(8, -14 - 2 * math.sin(u * 3)), size: 13, color: BP.amber, ax: 0.5, ay: 0.5);
        k.sweat(head, -1, j.toDouble());
      case 4: // vertical: a staff held upright, measuring the column
        final (hand, _, _) = crew.walker(f, face: -1, stride: 0, armF: 2.2, armB: 0.3);
        c.drawLine(Offset(hand.dx, _g), Offset(hand.dx, _g - 64), strokeP(BP.line, 1.4));
        for (var y = _g - 8; y > _g - 64; y -= 8) {
          c.drawLine(Offset(hand.dx, y), Offset(hand.dx + 4, y), strokeP(BP.line, 1));
        }
      default: // ZWJ: glues pieces together with a paint roller
        final up = math.sin(u * 4);
        final roller = Offset(xc + 36, _g - 22 + up * 10);
        final (hand, _, _) = crew.walker(f, face: -1, stride: 0, handF: roller + const Offset(6, 4), armB: 0.3);
        c.drawLine(hand, roller, strokeP(BP.inkDim, 1.4));
        c.drawRect(Rect.fromCenter(center: roller, width: 5, height: 12), fillP(BP.amber));
    }
  }

  void _toolIcon(int j, Offset at, Color col) {
    final p = strokeP(col, 1.2);
    switch (j) {
      case 0:
        c.drawOval(Rect.fromCenter(center: at + const Offset(-3, 0), width: 9, height: 6), p);
        c.drawOval(Rect.fromCenter(center: at + const Offset(3, 0), width: 9, height: 6), p);
      case 1:
        c.drawArc(Rect.fromCircle(center: at, radius: 5), -math.pi * 0.9, math.pi * 1.5, false, p);
        c.drawLine(at + const Offset(-5, -2), at + const Offset(-6, 3), p);
      case 2:
        for (var q = 0; q < 3; q++) {
          c.drawLine(at + Offset(-5, 4 - q * 4.0), at + Offset(5, 4 - q * 4.0), p);
        }
      case 3:
        c.drawRect(Rect.fromCenter(center: at, width: 10, height: 10), p);
        c.drawLine(at + const Offset(0, -5), at + const Offset(0, 5), p);
        c.drawLine(at + const Offset(0, 0), at + const Offset(5, 0), p);
      case 4:
        c.drawLine(at + const Offset(0, -6), at + const Offset(0, 6), p);
        c.drawLine(at + const Offset(-3, 3), at + const Offset(0, 6), p);
        c.drawLine(at + const Offset(3, 3), at + const Offset(0, 6), p);
      default:
        c.drawCircle(at + const Offset(-4, 0), 2.2, p);
        c.drawCircle(at + const Offset(4, 0), 2.2, p);
        c.drawLine(at + const Offset(-1.5, 0), at + const Offset(1.5, 0), p);
    }
  }

  // ── 03 Other architects ────────────────────────────────────────────────────

  static const _far = 690.0;
  static const _lots = [
    Rect.fromLTRB(96, 330, 260, _far),
    Rect.fromLTRB(298, 540, 506, _far),
    Rect.fromLTRB(546, 404, 704, _far),
    Rect.fromLTRB(744, 436, 880, _far),
  ];

  void _architectsScene() {
    // The street and the far sidewalk.
    c.drawLine(const Offset(60, _far), const Offset(960, _far), strokeP(BP.lineDim, 1.2));
    k.dashed(const Offset(60, 716), const Offset(930, 716), BP.lineFaint, w: 1.2, dash: 16, gap: 12);
    paintGround(k);
    for (var q = 0; q < 4; q++) {
      final r = _lots[q];
      final hot = m.hover == q;
      final col = hot ? BP.amber : BP.lineDim;
      final rise = eo(seg01(t, 0.4 + q * 0.18, 1.2 + q * 0.18));
      if (rise <= 0) continue;
      c.save();
      c.clipRect(Rect.fromLTRB(r.left - 60, lerpD(_far, r.top - 80, rise), r.right + 60, _far + 1));
      switch (q) {
        case 0:
          _chrome(r, col, hot);
        case 1:
          _figma(r, col, hot);
        case 2:
          _apple(r, col, hot);
        default:
          _android(r, col, hot);
      }
      c.restore();
      // Street sign with the name.
      final (name, stack, _) = _architects[q];
      final sign = k.board(Offset(r.center.dx, _far + 10), 84, 18, _far + 30, color: hot ? BP.amber : BP.lineDim);
      labels.draw(c, name, sign.center, size: 12, color: hot ? BP.amber : BP.ink, ax: 0.5, ay: 0.5);
      m.hits.add((Rect.fromLTRB(r.left - 10, r.top - 50, r.right + 10, _far + 32), q));
      if (hot) {
        final tag = labels.get(stack, 12, BP.amber);
        final box = Rect.fromCenter(
          center: Offset(r.center.dx, r.top - 64),
          width: tag.width + 16,
          height: tag.height + 8,
        );
        final bx = box.shift(Offset(math.max(0, 70 - box.left), 0));
        c.drawRect(bx, fillP(BP.paper));
        c.drawRect(bx, strokeP(BP.amber, 1));
        tag.paint(c, bx.topLeft + const Offset(8, 4));
      }
    }

    // Our side: the building gets its 2nd floor.
    final p = seg01(b, 0.4, 3.6);
    paintScaffold(k, Bld.top(2) - 4);
    paintBuilding(k, done: 1, p: p);
    _welders(2, p);
    final sign = k.board(const Offset(Bld.left - 76, _g - 38), 76, 34, _g);
    labels.draw(
      c,
      'Flutter',
      sign.center + const Offset(0, -6),
      size: 15,
      color: BP.ink,
      display: true,
      ax: 0.5,
      ay: 0.5,
    );
    labels.draw(c, 'SkParagraph', sign.center + const Offset(0, 9), size: 9, color: BP.inkDim, ax: 0.5, ay: 0.5);
    // A worker with binoculars, looking across the street.
    final look = (t % 9.0) < 6;
    final (_, _, head) = crew.walker(
      Offset(Bld.left + 26, Bld.top(1)),
      face: -1,
      stride: 0,
      armF: look ? 2.0 : 0.3,
      armB: look ? 2.1 : -0.2,
      lean: look ? -0.08 : 0,
    );
    if (look) {
      c.drawRect(Rect.fromCenter(center: head + const Offset(-5, 1), width: 5, height: 4), strokeP(BP.ink, 1.3));
    }
    _slabCrane(2, p);
    _coffeeCorner();
  }

  void _chrome(Rect r, Color col, bool hot) {
    // A tower of DOM blocks; one row re-flows every few seconds.
    const rows = [
      ['<body>'],
      ['<main>', '<nav>'],
      ['<div>', '<p>', '<a>'],
      ['<section>'],
      ['<h1>', '<span>'],
      ['<ul>', '<li>', '<li>'],
      ['<article>'],
      ['<img>', '<p>'],
      ['<div>', '<em>'],
      ['<header>'],
    ];
    final rh = (r.height - 20) / rows.length;
    final reflow = ((t / 2.6).floor()) % rows.length;
    final rf = seg01(t % 2.6, 0.2, 0.8);
    final ink = strokeP(col, 1.1);
    for (var row = 0; row < rows.length; row++) {
      final items = rows[row];
      final y1 = r.bottom - row * rh;
      final y0 = y1 - rh + 3;
      var x = r.left;
      for (var q = 0; q < items.length; q++) {
        var wf = 1 / items.length;
        if (row == reflow && items.length > 1) {
          final wave = math.sin(rf * math.pi) * 0.18;
          wf += (q == 0 ? wave : -wave / (items.length - 1));
        }
        final w = r.width * wf;
        final box = Rect.fromLTRB(x + 1.5, y0, x + w - 1.5, y1);
        c.drawRect(box, fillP(BP.paper));
        c.drawRect(box, ink);
        labels.draw(c, items[q], box.center, size: 9, color: hot ? BP.amber : BP.inkDim, ax: 0.5, ay: 0.5);
        x += w;
      }
    }
    // Antenna.
    c.drawLine(Offset(r.center.dx, r.top + 20), Offset(r.center.dx, r.top - 10), ink);
    c.drawCircle(
      Offset(r.center.dx, r.top - 12),
      2.5,
      fillP(BP.coral.withValues(alpha: 0.4 + 0.6 * ((t * 1.3) % 1.0 < 0.5 ? 1 : 0))),
    );
  }

  void _figma(Rect r, Color col, bool hot) {
    // A pavilion of pure vector steel: bézier roof with its handles.
    final ink = strokeP(col, 1.2);
    final base = r.bottom;
    final roofY = r.top + 70;
    final a = Offset(r.left, roofY);
    final d = Offset(r.right, roofY);
    final s1 = math.sin(t * 0.8) * 18;
    final s2 = math.cos(t * 0.65) * 18;
    final b1 = Offset(r.left + 50 + s1, r.top - 10);
    final c1 = Offset(r.right - 50 + s2, r.top - 10 - s1 * 0.5);
    final roof = Path()
      ..moveTo(a.dx, a.dy)
      ..cubicTo(b1.dx, b1.dy, c1.dx, c1.dy, d.dx, d.dy);
    c.drawPath(roof, strokeP(col, 2));
    c.drawLine(a, d, ink);
    // Columns as vector strokes with anchor points.
    for (var q = 0; q <= 4; q++) {
      final x = lerpD(r.left + 10, r.right - 10, q / 4);
      c.drawLine(Offset(x, roofY), Offset(x, base), ink);
      c.drawRect(Rect.fromCenter(center: Offset(x, base), width: 5, height: 5), fillP(BP.paper));
      c.drawRect(Rect.fromCenter(center: Offset(x, base), width: 5, height: 5), strokeP(col, 1));
    }
    final handle = strokeP((hot ? BP.amber : BP.violet).withValues(alpha: 0.8), 1);
    c.drawLine(a, b1, handle);
    c.drawLine(d, c1, handle);
    for (final h in [b1, c1]) {
      c.drawCircle(h, 3.2, fillP(BP.paper));
      c.drawCircle(h, 3.2, handle);
    }
    for (final pnt in [a, d]) {
      final sq = Rect.fromCenter(center: pnt, width: 7, height: 7);
      c.drawRect(sq, fillP(BP.paper));
      c.drawRect(sq, strokeP(hot ? BP.amber : BP.violet, 1.2));
    }
  }

  void _apple(Rect r, Color col, bool hot) {
    // A rounded tower with its own shaper crane on the roof.
    final ink = strokeP(col, 1.2);
    final body = RRect.fromRectAndCorners(r, topLeft: const Radius.circular(22), topRight: const Radius.circular(22));
    c.drawRRect(body, fillP(BP.paper));
    c.drawRRect(body, ink);
    final win = Path();
    for (var y = r.top + 30; y < r.bottom - 10; y += 16) {
      win
        ..moveTo(r.left + 14, y)
        ..lineTo(r.right - 14, y);
    }
    c.drawPath(win, strokeP(BP.lineFaint, 1));
    // Roof crane, slewing.
    final mx = r.center.dx + 20;
    final top = r.top - 58;
    c.drawLine(Offset(mx, r.top), Offset(mx, top), strokeP(col, 1.4));
    c.drawLine(Offset(mx - 5, r.top), Offset(mx - 5, top + 6), strokeP(col, 1));
    final slew = math.cos(t * 0.5);
    final tip = Offset(mx - 70 * slew, top + 4);
    c.drawLine(Offset(mx, top), tip, strokeP(col, 1.3));
    c.drawLine(Offset(mx, top), Offset(mx + 22 * slew, top + 4), strokeP(col, 1.3));
    c.drawRect(Rect.fromCenter(center: Offset(mx + 22 * slew, top + 8), width: 10, height: 7), strokeP(col, 1));
    final hookY = top + 30 + math.sin(t * 1.4) * 4;
    c.drawLine(tip, Offset(tip.dx, hookY), strokeP(BP.inkDim, 1));
    c.drawRect(
      Rect.fromCenter(center: Offset(tip.dx, hookY + 6), width: 16, height: 11),
      strokeP(hot ? BP.amber : BP.line, 1),
    );
    labels.draw(
      c,
      'A',
      Offset(tip.dx, hookY + 6),
      size: 9,
      color: hot ? BP.amber : BP.ink,
      ax: 0.5,
      ay: 0.5,
      display: true,
    );
    final sign = Rect.fromCenter(center: Offset(r.center.dx, r.top + 14), width: 74, height: 14);
    c.drawRect(sign, fillP(BP.paper));
    c.drawRect(sign, strokeP(col, 1));
    labels.draw(c, 'Core Text', sign.center, size: 9, color: hot ? BP.amber : BP.inkDim, ax: 0.5, ay: 0.5);
  }

  void _android(Rect r, Color col, bool hot) {
    // Minikin's facade: a paragraph that re-breaks, greedy ↔ balanced.
    final ink = strokeP(col, 1.2);
    c.drawRect(r, fillP(BP.paper));
    c.drawRect(r, ink);
    final sign = Rect.fromLTWH(r.left + 16, r.top - 22, r.width - 32, 18);
    c.drawLine(Offset(sign.left + 10, sign.bottom), Offset(sign.left + 10, r.top), ink);
    c.drawLine(Offset(sign.right - 10, sign.bottom), Offset(sign.right - 10, r.top), ink);
    c.drawRect(sign, fillP(BP.paper));
    c.drawRect(sign, ink);
    labels.draw(c, 'Minikin', sign.center, size: 10, color: hot ? BP.amber : BP.ink, ax: 0.5, ay: 0.5);
    const greedy = [1.0, 0.96, 1.0, 0.22];
    const balanced = [0.8, 0.78, 0.82, 0.76];
    final ph = (t / 3.0) % 2.0;
    final f = ph < 1 ? eio(seg01(ph, 0.6, 1.0)) : 1 - eio(seg01(ph - 1, 0.6, 1.0));
    final bar = fillP((hot ? BP.amber : BP.line).withValues(alpha: 0.45));
    for (var blk = 0; blk < 3; blk++) {
      for (var q = 0; q < 4; q++) {
        final w = (r.width - 36) * lerpD(greedy[q], balanced[q], f);
        c.drawRect(Rect.fromLTWH(r.left + 18, r.top + 20 + blk * 72 + q * 14, w, 6), bar);
      }
    }
    labels.draw(
      c,
      f > 0.5 ? 'balanced' : 'greedy',
      Offset(r.center.dx, r.bottom - 22),
      size: 9,
      color: BP.inkFaint,
      ax: 0.5,
    );
  }

  // ── Excavator (01): digs a trench, swings, fills the dump truck ───────────

  void _excavator() {
    const cyc = 6.0;
    final n = (t / cyc).floor();
    final u = t - n * cyc;
    // Arm pose over the cycle: (boom angle, stick angle, swing).
    double boom;
    double stick;
    var swing = 0.0;
    var dump = 0.0;
    if (u < 1.0) {
      boom = lerpD(0.18, 0.08, eio(u));
      stick = lerpD(-1.2, -1.75, eio(u));
    } else if (u < 1.8) {
      final f = eio((u - 1.0) / 0.8);
      boom = lerpD(0.08, 0.8, f);
      stick = lerpD(-1.75, -1.05, f);
    } else if (u < 3.0) {
      boom = 0.8;
      stick = -1.05;
      swing = eio((u - 1.8) / 1.2);
    } else if (u < 3.8) {
      boom = 0.8;
      stick = -1.05;
      swing = 1;
      dump = winAt(u, 3.0, 3.8, 0.2);
    } else if (u < 5.0) {
      boom = 0.8;
      stick = -1.05;
      swing = 1 - eio((u - 3.8) / 1.2);
    } else {
      final f = eio((u - 5.0) / 1.0);
      boom = lerpD(0.8, 0.18, f);
      stick = lerpD(-1.05, -1.2, f);
    }
    final d = math.cos(swing * math.pi);
    const cx = 470.0;
    // Trench on the right, spoil falls into the truck on the left.
    final trench = Path()
      ..moveTo(600, _g)
      ..lineTo(612, _g + 22)
      ..lineTo(672, _g + 22)
      ..lineTo(684, _g);
    c.drawPath(dashPath(trench, dash: 4, gap: 3), strokeP(BP.lineDim, 1.2));
    final load = math.min(1.0, (n + (u > 3.4 ? 1 : 0)) / 4);
    k.truck(300, _lane, -1, 2, null, load: math.max(0.15, load), loadColor: BP.inkDim);
    // Tracks and body.
    final tracks = RRect.fromRectAndRadius(
      const Rect.fromLTRB(cx - 62, _g - 18, cx + 62, _g),
      const Radius.circular(9),
    );
    c.drawRRect(tracks, fillP(BP.paper));
    c.drawRRect(tracks, strokeP(BP.line, 1.3));
    for (var wx = cx - 50; wx <= cx + 50; wx += 20) {
      k.wheel(Offset(wx, _g - 9), 5, 0);
    }
    final body = Rect.fromLTRB(cx - 44, _g - 44, cx + 40, _g - 20);
    c.drawRect(body, fillP(BP.paper));
    c.drawRect(body, strokeP(BP.line, 1.3));
    final cab = Rect.fromLTRB(cx + 6 * d - 16, _g - 76, cx + 6 * d + 16, _g - 44);
    c.drawRect(cab, fillP(BP.paper));
    c.drawRect(cab, strokeP(BP.line, 1.3));
    c.drawRect(cab.deflate(5), strokeP(BP.lineDim, 1));
    crew.head(cab.center + const Offset(0, 2), d >= 0 ? 1 : -1);
    // Boom, stick, bucket (the swing foreshortens the arm).
    final pivot = Offset(cx + 30 * d, _g - 40);
    final elbow = pivot + Offset(math.cos(boom) * 100 * d, -math.sin(boom) * 100);
    final tip = elbow + Offset(math.cos(stick) * 74 * d, -math.sin(stick) * 74);
    c.drawLine(pivot, elbow, strokeP(BP.line, 4));
    c.drawLine(pivot, elbow, strokeP(BP.paper, 1.6));
    c.drawLine(elbow, tip, strokeP(BP.line, 3));
    final ang = stick - 0.9 + dump * 1.4;
    final bucket = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx + math.cos(ang) * 22 * d, tip.dy - math.sin(ang) * 22)
      ..lineTo(tip.dx + math.cos(ang - 1.2) * 16 * d, tip.dy - math.sin(ang - 1.2) * 16)
      ..close();
    c.drawPath(bucket, fillP(BP.paper));
    c.drawPath(bucket, strokeP(BP.amber, 1.5));
    // Dirt: scooped up while digging, poured into the truck.
    if (u > 0.4 && u < 1.0) {
      for (var q = 0; q < 4; q++) {
        final ph = (u * 3 + q / 4) % 1.0;
        c.drawCircle(tip + Offset(-8 + q * 5.0, 6 - 10 * ph), 1.6, fillP(BP.inkDim.withValues(alpha: 1 - ph)));
      }
    }
    if (dump > 0) {
      for (var q = 0; q < 8; q++) {
        final ph = (u * 2.4 + q / 8) % 1.0;
        final y = tip.dy + 8 + ph * (_lane - 50 - tip.dy);
        c.drawCircle(Offset(tip.dx - 4 + (q % 3) * 4.0, y), 2, fillP(BP.inkDim.withValues(alpha: dump)));
      }
    }
  }

  // ── Permit drawings (04) ──────────────────────────────────────────────────

  void _permitArt(int j, Offset at) {
    final p = strokeP(BP.inkDim, 1.2);
    switch (j) {
      case 0: // vertical text: a column of glyph boxes
        for (var q = 0; q < 3; q++) {
          c.drawRect(Rect.fromCenter(center: at + Offset(0, -16 + q * 16.0), width: 13, height: 13), p);
        }
        c.drawLine(at + const Offset(14, -18), at + const Offset(14, 18), strokeP(BP.inkFaint, 1));
        drawArrowHead(c, at + const Offset(14, 20), at + const Offset(14, 10), strokeP(BP.inkFaint, 1), 4);
      case 1: // ruby: kana over the base
        c.drawRect(Rect.fromCenter(center: at + const Offset(0, 6), width: 40, height: 20), p);
        c.drawRect(Rect.fromCenter(center: at + const Offset(-9, -14), width: 14, height: 8), p);
        c.drawRect(Rect.fromCenter(center: at + const Offset(9, -14), width: 14, height: 8), p);
      case 2: // hyphenation
        labels.draw(c, 'hyphen-', at + const Offset(0, -9), size: 12, color: BP.inkDim, ax: 0.5, ay: 0.5);
        labels.draw(c, 'ation', at + const Offset(-8, 9), size: 12, color: BP.inkDim, ax: 0.5, ay: 0.5);
      case 3: // LCD subpixels
        const cols = [BP.coral, BP.green, BP.line];
        for (var q = 0; q < 6; q++) {
          c.drawRect(Rect.fromLTWH(at.dx - 21 + q * 7.0, at.dy - 16, 5, 32), fillP(cols[q % 3].withValues(alpha: 0.6)));
        }
      case 4: // the same on every device
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: at + const Offset(-26, 0), width: 12, height: 22),
            const Radius.circular(2),
          ),
          p,
        );
        c.drawRect(Rect.fromCenter(center: at + const Offset(0, -2), width: 26, height: 16), p);
        c.drawLine(at + const Offset(-16, 8), at + const Offset(16, 8), p);
        c.drawRect(Rect.fromCenter(center: at + const Offset(28, -3), width: 18, height: 14), p);
        c.drawLine(at + const Offset(28, 4), at + const Offset(28, 10), p);
        for (final dx in [-26.0, 0.0, 28.0]) {
          labels.draw(
            c,
            'A',
            at + Offset(dx, dx == 0 ? -2 : -3),
            size: 9,
            color: BP.ink,
            display: true,
            ax: 0.5,
            ay: 0.5,
          );
        }
      case 5: // shaders on text
        final sh = m.shaded;
        if (sh != null) sh.paint(c, at - Offset(sh.width / 2, sh.height / 2));
      default: // a widget inside a line of text
        labels.draw(c, 'ab', at + const Offset(-24, 0), size: 14, color: BP.ink, ax: 0.5, ay: 0.5);
        c.drawRect(Rect.fromCenter(center: at, width: 14, height: 14), fillP(BP.amber.withValues(alpha: 0.3)));
        c.drawRect(Rect.fromCenter(center: at, width: 14, height: 14), strokeP(BP.amber, 1.2));
        labels.draw(c, 'cd', at + const Offset(24, 0), size: 14, color: BP.ink, ax: 0.5, ay: 0.5);
    }
  }

  // ── 04 Building code ───────────────────────────────────────────────────────

  static const _pw = 100.0;
  static const _ph = 160.0;
  static const _pTop = 500.0;

  Rect _permit(int j) => Rect.fromLTWH(112 + j * (_pw + 10), _pTop, _pw, _ph);

  /// Inspector schedule: walks to permit j, stamps it.
  (double arrive, double stamp) _visit(int j) {
    const speed = 150.0;
    var time = 1.0;
    var x = 40.0;
    for (var q = 0; q <= j; q++) {
      final tx = _permit(q).center.dx - 22;
      time += (tx - x).abs() / speed;
      x = tx;
      if (q == j) return (time, time + 0.45);
      time += 1.0;
    }
    return (time, time);
  }

  void _code() {
    paintGround(k);
    final p = seg01(b, 0.3, 3.5);
    paintScaffold(k, Bld.top(3) - 4);
    paintBuilding(k, done: 2, p: p);
    _welders(3, p);
    _hammerer(Offset(Bld.left - 20, Bld.top(2) - 4), 1.1);

    // The notice board.
    const board = Rect.fromLTRB(96, _pTop - 16, 884, _pTop + _ph + 14);
    c.drawLine(const Offset(160, _pTop + _ph + 14), const Offset(160, _g), strokeP(BP.lineDim, 1.4));
    c.drawLine(const Offset(820, _pTop + _ph + 14), const Offset(820, _g), strokeP(BP.lineDim, 1.4));
    c.drawRect(board, fillP(BP.paper));
    c.drawRect(board, strokeP(BP.lineDim, 1.2));
    labels.draw(c, 'permits', const Offset(96, _pTop - 22), size: 12, color: BP.inkDim, ay: 1);

    // Stamp times (clicks re-stamp).
    for (var j = 0; j < _permits.length; j++) {
      final (l1, l2, ok) = _permits[j];
      final r = _permit(j);
      final hot = m.hover == j;
      final (_, s) = _visit(j);
      final poke = m.pokes[j];
      final st = poke != null && t - poke < 5 ? poke + 0.1 : s;
      final shake = (t - st > 0 && t - st < 0.15) ? math.sin((t - st) * 120) * 1.5 : 0.0;
      final rr = r.shift(Offset(shake, 0));
      c.drawRect(rr, fillP(BP.panel));
      c.drawRect(rr, strokeP(hot ? BP.amber : BP.lineDim, hot ? 1.6 : 1));
      c.drawLine(rr.topLeft + const Offset(8, 14), rr.topRight + const Offset(-8, 14), strokeP(BP.lineFaint, 1));
      labels.draw(c, l1, Offset(rr.center.dx, rr.top + 26), size: 14, color: BP.ink, ax: 0.5, ay: 0.5);
      if (l2.isNotEmpty) {
        labels.draw(c, l2, Offset(rr.center.dx, rr.top + 43), size: 11, color: BP.inkDim, ax: 0.5, ay: 0.5);
      }
      _permitArt(j, Offset(rr.center.dx, rr.top + 78));
      final sv = seg01(t, st, st + 0.14);
      if (sv > 0) {
        final col = ok ? BP.green : BP.red;
        final ctr = Offset(rr.center.dx, rr.top + 128);
        final sc = lerpD(1.7, 1, eo(sv));
        c.save();
        c.translate(ctr.dx, ctr.dy);
        c.rotate(ok ? -0.12 : 0.14);
        c.scale(sc);
        final pc = strokeP(col.withValues(alpha: sv), 2.2);
        c.drawCircle(Offset.zero, 21, pc);
        c.drawCircle(Offset.zero, 17, strokeP(col.withValues(alpha: 0.5 * sv), 1));
        if (ok) {
          c.drawPath(
            Path()
              ..moveTo(-9, 0)
              ..lineTo(-3, 7)
              ..lineTo(10, -8),
            strokeP(col.withValues(alpha: sv), 3.2),
          );
        } else {
          c.drawLine(const Offset(-8, -8), const Offset(8, 8), strokeP(col.withValues(alpha: sv), 3.2));
          c.drawLine(const Offset(8, -8), const Offset(-8, 8), strokeP(col.withValues(alpha: sv), 3.2));
        }
        c.restore();
        if (t - st < 0.5) {
          final ring = (t - st) / 0.5;
          c.drawCircle(ctr, 22 + 18 * ring, strokeP(col.withValues(alpha: 0.5 * (1 - ring)), 1.2));
        }
      }
      m.hits.add((r.inflate(4), j));
    }

    // The inspector (white hat), with a clipboard and a long stamp.
    final inspector = SiteCrew(hat: BP.ink, scale: 2.2);
    var x = 40.0;
    var face = 1.0;
    var walking = false;
    var stampLift = 0.0;
    var prevX = 40.0;
    var time = 1.0;
    final last = _visit(_permits.length - 1).$2;
    for (var q = 0; q < _permits.length; q++) {
      final (arr, s) = _visit(q);
      final tx = _permit(q).center.dx - 22;
      if (t < arr) {
        final f = seg01(t, time, arr);
        x = lerpD(prevX, tx, f);
        walking = t > time;
        face = tx >= prevX ? 1 : -1;
        break;
      }
      x = tx;
      if (t < arr + 1.0) {
        stampLift = t < s ? eo(seg01(t, arr, s - 0.1)) : 1 - eo(seg01(t, s, s + 0.3));
        break;
      }
      prevX = tx;
      time = arr + 1.0;
    }
    if (t > last + 0.6) {
      // Done: stroll back to the middle, then read the clipboard.
      final f = seg01(t, last + 0.6, last + 3.2);
      x = lerpD(_permit(6).center.dx - 22, 470, eio(f));
      walking = f > 0 && f < 1;
      face = f < 1 ? -1 : ((t % 8.0) < 5 ? -1 : 1);
    }
    // A poke: he turns to the permit.
    for (final e in m.pokes.entries) {
      if (t - e.value < 1.2) face = _permit(e.key).center.dx > x ? 1 : -1;
    }
    final feet = Offset(x, _g);
    final stampAt = Offset(x + 22 * face, _pTop + 128);
    final (hf, hb, head) = inspector.walker(
      feet,
      face: face,
      walk: walking ? t * 8 : 0,
      stride: walking ? 1 : 0,
      handF: stampLift > 0
          ? Offset.lerp(feet + Offset(10 * face, -30), stampAt + const Offset(0, 40), stampLift)
          : null,
      armF: 0.5,
      armB: 1.2,
    );
    // Clipboard in the back hand.
    c.drawRect(Rect.fromCenter(center: hb + Offset(-3 * face, -4), width: 11, height: 14), fillP(BP.paper));
    c.drawRect(Rect.fromCenter(center: hb + Offset(-3 * face, -4), width: 11, height: 14), strokeP(BP.amber, 1.2));
    // Stamp on a handle.
    if (stampLift > 0) {
      final tip = Offset(hf.dx, math.min(hf.dy - 18, stampAt.dy + 8));
      c.drawLine(hf, tip, strokeP(BP.ink, 1.6));
      c.drawRect(Rect.fromCenter(center: tip + const Offset(0, -3), width: 12, height: 6), fillP(BP.ink));
    }
    inspector.flush(c);
    labels.draw(
      c,
      'inspector',
      Offset(head.dx, _g + 8),
      size: 10,
      color: BP.inkFaint,
      ax: 0.5,
      alpha: seg01(t, 1, 1.6),
    );
    _slabCrane(3, p);
    _coffeeCorner();
  }

  // ── 05 Follow one beam ─────────────────────────────────────────────────────

  /// The beam's centre and tilt at local time u.
  (Offset, double) _beamAt(double u) {
    const truckX = 700.0;
    const onBed = Offset(truckX - 33, _lane - 16 - 8);
    const up = 408.0;
    final land = Offset(Bld.cx, Bld.top(4) - 1);
    if (u < 1.6) return (onBed + Offset(lerpD(-1000, 0, eo(seg01(u, 0.2, 1.6))), 0), 0);
    if (u < 2.2) return (onBed, 0);
    if (u < 3.0) return (Offset(onBed.dx, lerpD(onBed.dy, up, eio(seg01(u, 2.2, 3.0)))), 0);
    if (u < 4.6) {
      final f = seg01(u, 3.0, 4.6);
      return (Offset(lerpD(onBed.dx, land.dx, eio(f)), up), math.sin(f * math.pi * 2) * 0.03);
    }
    if (u < 5.4) {
      final f = seg01(u, 4.6, 5.4);
      final y = f < 0.8
          ? lerpD(up, land.dy - 10, eio(f / 0.8))
          : lerpD(land.dy - 10, land.dy, backOut((f - 0.8) / 0.2));
      return (Offset(land.dx, y), 0);
    }
    return (land, 0);
  }

  void _beam() {
    paintGround(k);
    final u = t - m.replayAt - (m.replayAt > 0 ? 0 : 0.7);
    const landT = 5.4;
    final landed = u >= landT;
    final cols = seg01(b, 0.2, 1.6) * 0.3;
    final p = landed ? math.max(cols, 0.65 + 0.35 * seg01(u, landT, landT + 1.4)) : cols;
    paintScaffold(k, Bld.top(4) - 4);
    paintBuilding(k, done: 3, p: p, slab: false);

    // Truck: brings the beam, then leaves.
    const truckX = 700.0;
    if (u < 4.6) {
      final x = u < 1.6
          ? lerpD(-300, truckX, eo(seg01(u, 0.2, 1.6)))
          : u < 2.9
          ? truckX
          : lerpD(truckX, 1800, ei(seg01(u, 2.9, 4.6)));
      k.truck(x, _lane, 1, 4, null);
    }

    // The trail it has travelled.
    if (u > 2.2) {
      final trail = Path();
      final end = math.min(u, landT);
      for (var q = 0; q <= 40; q++) {
        final (pt, _) = _beamAt(lerpD(2.2, end, q / 40));
        q == 0 ? trail.moveTo(pt.dx, pt.dy) : trail.lineTo(pt.dx, pt.dy);
      }
      c.drawPath(dashPath(trail, dash: 5, gap: 5), strokeP(BP.amber.withValues(alpha: 0.55), 1.3));
    }

    // The beam itself, stamped with the journey word.
    final (ctr, tilt) = _beamAt(u);
    const bw = Bld.width + 16;
    final r = Rect.fromCenter(center: ctr, width: bw, height: 22);
    final glow = landed ? 0.5 + 0.5 * math.sin((u - landT) * 2.2) : 1.0;
    c.save();
    c.translate(ctr.dx, ctr.dy);
    c.rotate(tilt);
    c.translate(-ctr.dx, -ctr.dy);
    if (landed) c.drawRect(r.inflate(4), fillP(BP.amber.withValues(alpha: 0.08 + 0.08 * glow)));
    k.beam(r, color: BP.amber);
    final word = journeyWord.value;
    labels.draw(
      c,
      word.length > 14 ? '${word.substring(0, 13)}…' : word,
      r.center,
      size: 17,
      color: BP.amber,
      display: true,
      ax: 0.5,
      ay: 0.5,
    );
    c.restore();
    m.hits.add((r.inflate(20), 0));

    // Crane: hook comes down, lifts, carries, lowers, lets go.
    final hookUp = Bld.jibY + 60.0;
    double hx;
    double hy;
    var hooked = false;
    if (u < 1.6) {
      hx = lerpD(Bld.cx, truckX - 33, eio(seg01(u, 0, 1.4)));
      hy = hookUp;
    } else if (u < 2.2) {
      hx = truckX - 33;
      hy = lerpD(hookUp, ctr.dy - 36, eio(seg01(u, 1.6, 2.2)));
      hooked = u > 2.0;
    } else if (u < landT + 0.3) {
      hx = ctr.dx;
      hy = ctr.dy - 36;
      hooked = true;
    } else {
      final f = seg01(u, landT + 0.3, landT + 1.3);
      hx = ctr.dx + math.sin(t * 0.6) * 40 * f;
      hy = lerpD(ctr.dy - 36, 400, eio(f)) + math.sin(t * 1.3) * 5 * f;
    }
    _crane(
      hx,
      hy,
      load: hooked
          ? (x, y) => k.slings(Offset(x, y + 4), r.topLeft + const Offset(60, 0), r.topRight - const Offset(60, 0))
          : null,
    );

    // Bolting at both ends, dust on landing.
    if (landed) {
      k.dust(Offset(Bld.left, Bld.top(4)), u - landT, seed: 1, spread: 30);
      k.dust(Offset(Bld.right, Bld.top(4)), u - landT, seed: 2, spread: 30);
      final w = winAt(u, landT + 0.3, landT + 2.4, 0.1);
      if (w > 0) {
        for (final x in [Bld.left + 14.0, Bld.right - 14.0]) {
          crew.walker(
            Offset(x + (x < Bld.cx ? 12 : -12), Bld.top(4) - 8),
            face: x < Bld.cx ? -1 : 1,
            stride: 0,
            lean: 0.3,
            armF: 1.2,
          );
          k.sparks((_) => Offset(x, Bld.top(4) - 4), n: 8, life: 0.35, seed: x);
        }
      }
    }

    // The tour: a guide with a flag and three visitors follow the beam.
    final follow = u < 2.2 ? lerpD(60, truckX - 200, eo(seg01(u, 0.4, 2.4))) : math.min(ctr.dx - 190, 900);
    final cheer = landed && u < landT + 1.6;
    for (var q = 0; q < 4; q++) {
      final tx = follow - q * 30.0;
      final moving = u > 0.4 && (u < 2.4 || (u > 3.0 && u < 4.6));
      final feet = Offset(tx, _g);
      if (q == 0) {
        final (hand, _, _) = crew.walker(
          feet,
          walk: moving ? t * 8 : 0,
          stride: moving ? 1 : 0,
          armF: 2.6 + 0.2 * math.sin(t * 3),
          armB: 0.2,
        );
        final top = hand + const Offset(2, -34);
        c.drawLine(hand + const Offset(0, 4), top, strokeP(BP.ink, 1.3));
        final flag = Path()..moveTo(top.dx, top.dy);
        for (var s = 0; s <= 6; s++) {
          flag.lineTo(top.dx + 20 * s / 6, top.dy + math.sin(t * 6 - s) * 2 * s / 6);
        }
        for (var s = 6; s >= 0; s--) {
          flag.lineTo(top.dx + 20 * s / 6, top.dy + 12 + math.sin(t * 6 - s) * 2 * s / 6);
        }
        c.drawPath(flag..close(), fillP(BP.amber.withValues(alpha: 0.8)));
      } else if (cheer) {
        crew.cheer(feet, t, seed: q.toDouble());
      } else {
        crew.walker(feet, walk: moving ? t * 8 + q : 0, stride: moving ? 1 : 0, lean: -0.18, armF: 0.2, armB: -0.3);
      }
    }
    labels.draw(
      c,
      'tour',
      Offset(follow - 45, _g + 14),
      size: 10,
      color: BP.inkFaint,
      ax: 0.5,
      alpha: seg01(u, 0.8, 1.4),
    );
    _coffeeCorner();
  }
}
