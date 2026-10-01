import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../../../worlds/factory/factory_kit.dart';
import '../method.dart';
import '../stage.dart';
import '../workshop_layout.dart';

/// ステンシル · Spray stencil: two workers on lifts unroll a big stencil
/// card over a clear acrylic panel — the glyph cut out of it, with bridges
/// holding the islands (the counters of A, 8, 田…) like a real stencil.
/// A sprayer shakes the can and sprays it in passes (mist, overspray on the
/// card), then the card is rolled off from the top, revealing the violet
/// letter with its sprayed edge and the little gaps where the bridges were.
class StencilCraft extends CraftMethod {
  const StencilCraft();

  @override
  String get id => 'stencil';

  @override
  String get en => 'Spray stencil';

  @override
  String get ja => 'ステンシル';

  @override
  Color get color => BP.violet;

  @override
  double get weight => 0.85;

  static final _plans = Expando<_Stencil>();

  _Stencil _plan(GlyphStage s) => _plans[s] ??= _Stencil(s);

  // Timeline (fractions of p).
  static const _up1 = 0.04; // the rolled card goes up on two lifts
  static const _lay1 = 0.16; // ...and is unrolled down over the panel
  static const _fold1 = 0.20; // lifts fold down
  static const _spray0 = 0.25, _spray1 = 0.72; // spraying in passes
  static const _peel0 = 0.78, _peel1 = 0.96; // card rolled off from the top

  @override
  void paintMaking(CraftContext x, double p) {
    final s = x.s, c = x.c;
    final st = _plan(s);
    st.panelDraw(c, x);

    // Paint on the panel: where the passes have been (all of it after).
    final u = seg(p, _spray0, _spray1);
    final nozzle = st.nozzle(u);
    if (u > 0) {
      c.save();
      if (u < 1) c.clipPath(st.sprayed(u, nozzle));
      st.paint(c);
      c.restore();
    }

    // The card: laid from the top down, later rolled off from the top.
    final lay = eio(seg(p, _up1, _lay1));
    final peel = eio(seg(p, _peel0, _peel1));
    double? rollY;
    if (p < _peel0) {
      if (lay > 0) {
        final y = lerp(st.sheet.top, st.sheet.bottom, lay);
        st.card(c, x, Rect.fromLTRB(-1e4, -1e4, 1e4, y), u, nozzle);
        if (lay < 1) rollY = y;
      }
    } else if (peel < 1) {
      final y = lerp(st.sheet.top, st.sheet.bottom, peel);
      st.card(c, x, Rect.fromLTRB(-1e4, y, 1e4, 1e4), 1, nozzle);
      rollY = y;
    }
    // Still rolled up: going up with the lifts at the start.
    if (p < _up1) rollY = lerp(x.floorY - 60, st.sheet.top, eio(seg(p, 0, _up1)));
    if (rollY != null) {
      final rolled = p < _peel0 ? 1 - lay : peel;
      st.roll(c, x, rollY, rolled, p >= _peel0);
    }

    _crew(x, st, p, rollY, u, nozzle);
  }

  /// Card handlers at both ends of the roll, the sprayer on its lift.
  void _crew(CraftContext x, _Stencil st, double p, double? rollY, double u, Offset nozzle) {
    final c = x.c;
    final sheet = st.sheet;
    // The two card handlers.
    for (final side in [-1, 1]) {
      final end = Offset(side < 0 ? sheet.left - 8 : sheet.right + 8, rollY ?? 0);
      final standX = (end.dx + side * 30).clamp(772.0, 1400.0);
      final hat = side < 0 ? BP.amber : BP.coral;
      if (rollY != null) {
        final platform = math.min(x.liftFor(rollY + 6), x.floorY - 16);
        x.lift(standX, platform, w: 46, col: BP.violet);
        x.reach(Offset(standX, platform - 4), end, dir: -side, both: true, hat: hat);
        continue;
      }
      // On the floor beside the panel, out of the sprayer's way.
      final fx = side < 0
          ? math.max(776.0, st.panel.left - 52)
          : math.min(1400.0, st.panel.right + 50);
      final pose = Pose();
      if (p >= _peel1) {
        pose.cheer(x.t, side < 0 ? 0 : 3);
      } else if (p > _lay1 && p < _fold1 + 0.02) {
        // Lifts folding down.
        final platform = lerp(
          x.liftFor(sheet.bottom + 6),
          x.floorY - 16,
          eio(seg(p, _lay1, _fold1)),
        );
        x.lift(standX, math.min(platform, x.floorY - 16), w: 46, col: BP.violet);
        x.worker(Offset(standX, math.min(platform, x.floorY - 16) - 4), dir: -side, hat: hat);
        continue;
      } else {
        pose
          ..upA = 0.35
          ..head = -0.25;
      }
      x.worker(Offset(fx, x.floorY), dir: -side, pose: pose, hat: hat);
    }
    // The sprayer: shakes the can, then sprays pass after pass.
    if (p < _fold1 || p >= _spray1 + 0.05) return;
    final standX = (nozzle.dx - 54).clamp(772.0, 1400.0);
    final lift = eio(seg(p, _fold1, _spray0 - 0.01)) * (1 - eio(seg(p, _spray1, _spray1 + 0.05)));
    final platform = lerp(x.floorY - 16, math.min(x.liftFor(nozzle.dy), x.floorY - 16), lift);
    x.lift(standX, platform, w: 54, col: BP.violet);
    final feet = Offset(standX, platform - 4);
    final spraying = u > 0 && u < 1;
    Limbs l;
    if (p < _spray0) {
      // Shaking the can (シャカシャカ).
      final pose = Pose()
        ..upA = 2.2 + 0.35 * math.sin(x.t * 30)
        ..foA = 2.6 + 0.35 * math.sin(x.t * 30);
      l = x.worker(feet, dir: 1, pose: pose, hat: BP.violet);
      final shake = x.text.get(
        'シャカシャカ',
        BT.sample(15, color: BP.violet, weight: 600).copyWith(locale: jaLocale),
      );
      shake.paint(c, l.head + const Offset(12, -26));
    } else {
      l = x.reach(feet, nozzle, dir: 1, hat: BP.violet);
    }
    // Mask over the mouth.
    c.drawRect(
      Rect.fromCenter(center: l.head + const Offset(3, 3), width: 7, height: 4),
      x.fl(BP.inkDim),
    );
    final can = _can(x, l.handA);
    if (spraying) st.mist(c, x, can, nozzle);
  }

  /// A spray can held at [hand]; returns its nozzle.
  Offset _can(CraftContext x, Offset hand) {
    final c = x.c;
    final body = Rect.fromLTWH(hand.dx - 4, hand.dy - 14, 9, 18);
    c.drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(2.5)), x.fl(_Stencil.paintCol));
    c.drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(2.5)), x.st(BP.ink, 1));
    c.drawRect(Rect.fromLTWH(body.left + 2, body.top - 4, 5, 4), x.fl(BP.ink));
    return Offset(body.right, body.top - 2);
  }

  @override
  void paintFinished(CraftContext x) {
    final st = _plan(x.s);
    st.panelDraw(x.c, x);
    st.paint(x.c);
  }
}

/// The panel, the stencil card with its bridges, and the paint for one
/// character.
class _Stencil {
  _Stencil(this.s) {
    final ink = s.ink;
    final m = math.max(14.0, ink.height * 0.06);
    sheet = Rect.fromLTRB(ink.left - m, ink.top - m, ink.right + m, ink.bottom + 6);
    panel = Rect.fromLTRB(sheet.left - 6, sheet.top - 6, sheet.right + 6, BW.floorY - 2);
    _index();
    _bridgesFor();
    final b = Path();
    for (final r in bridges) {
      b.addRect(r);
    }
    final hollow = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(sheet)
      ..addPath(s.outline, Offset.zero);
    if (bridges.isEmpty) {
      cut = s.outline;
      stencil = hollow;
    } else {
      try {
        cut = Path.combine(PathOperation.difference, s.outline, b);
        stencil = Path.combine(PathOperation.union, hollow, b);
      } catch (_) {
        cut = s.outline;
        stencil = hollow;
      }
    }
    _grain();
    final bandH = (sheet.height / 8).clamp(30.0, 54.0);
    passes = (sheet.height / bandH).ceil();
    band = sheet.height / passes;
  }

  final GlyphStage s;
  late final Rect sheet;
  late final Rect panel;
  late final Path cut;
  late final Path stencil;
  final bridges = <Rect>[];
  late final int passes;
  late final double band;

  static const paintCol = Color(0xFF9B6BFF);
  static const _paintDark = Color(0xFF6A3BD9);
  static const _paintLight = Color(0xFFC9AEFF);
  static const _card = Color(0xFFD7B676);
  static const _cardDark = Color(0xFF9A7739);
  static const _overspray = Color(0x7A6E3CF0);

  // ── Raster cells: material, holes, outside (fast point tests) ──────────────

  /// Per raster pixel: 1 material, 2 outside (reaches the border), 0 a hole.
  late final Uint8List _cell;

  void _index() {
    final g = s.geo, w = g.w, h = g.h;
    _cell = Uint8List(w * h);
    for (final sp in g.spans) {
      _cell.fillRange(sp.y * w + sp.x0, sp.y * w + sp.x1, 1);
    }
    final stack = <int>[];
    void push(int i) {
      if (_cell[i] != 0) return;
      _cell[i] = 2;
      stack.add(i);
    }

    for (var x = 0; x < w; x++) {
      push(x);
      push((h - 1) * w + x);
    }
    for (var y = 0; y < h; y++) {
      push(y * w);
      push(y * w + w - 1);
    }
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      final x = i % w, y = i ~/ w;
      if (x > 0) push(i - 1);
      if (x < w - 1) push(i + 1);
      if (y > 0) push(i - w);
      if (y < h - 1) push(i + w);
    }
  }

  int _cellAt(Offset p) {
    final g = s.geo;
    final rx = ((p.dx - s.origin.dx) / s.k).floor(), ry = ((p.dy - s.origin.dy) / s.k).floor();
    if (rx < 0 || ry < 0 || rx >= g.w || ry >= g.h) return 2;
    return _cell[ry * g.w + rx];
  }

  bool inside(Offset p) => _cellAt(p) == 1;

  // ── Bridges: each island (a counter) is tied to the card across a stroke ─

  void _bridgesFor() {
    const dirs = [Offset(0, -1), Offset(0, 1), Offset(-1, 0), Offset(1, 0)];
    final holes = [
      for (var i = 0; i < s.contours.length; i++)
        if (s.contourHole[i]) i,
    ];
    if (holes.isEmpty) return;
    final w = (s.typicalRadius * 0.5).clamp(3.5, 12.0);
    final maxCross = s.typicalRadius * 5 + 12;
    final probe = s.k * 2 + 1;
    // One or two counters (A, O, 8) get a bridge on each side.
    final few = holes.length <= 2;
    for (final h in holes) {
      final m = s.contourMetrics[h];
      final hb = s.contours[h].getBounds();
      final best = <int, (double, Offset, Offset)>{};
      final n = math.max(16, (m.length / 3).floor());
      for (var i = 0; i < n; i++) {
        final pt = m.getTangentForOffset(m.length * i / n)?.position;
        if (pt == null) continue;
        for (var d = 0; d < 4; d++) {
          final v = dirs[d];
          // Out of the counter into the stroke. (Probing a little further
          // than a raster pixel: the traced outline and the raster cells
          // may disagree by about that much.)
          if (!inside(pt + v * probe) || inside(pt - v * probe)) continue;
          var l = probe;
          while (l < maxCross && inside(pt + v * l)) {
            l += 1;
          }
          final end = pt + v * l;
          if (l >= maxCross || !sheet.deflate(2).contains(end)) continue;
          // Short, reaching the card outside rather than another island,
          // near the middle of the counter's side (like a stencil font).
          final off = d < 2
              ? (pt.dx - hb.center.dx) / math.max(1, hb.width / 2)
              : (pt.dy - hb.center.dy) / math.max(1, hb.height / 2);
          final score =
              l * (_cellAt(end) == 0 ? 1.35 : 1) * (d < 2 ? 0.95 : 1) * (1 + 0.4 * off * off);
          final cur = best[d];
          if (cur == null || score < cur.$1) best[d] = (score, pt, end);
        }
      }
      if (best.isEmpty) continue;
      final order = best.keys.toList()..sort((a, b) => best[a]!.$1.compareTo(best[b]!.$1));
      final first = order.first;
      _bridge(best[first]!, dirs[first], w);
      final opp = first ^ 1;
      if (few &&
          best.containsKey(opp) &&
          best[opp]!.$1 < best[first]!.$1 * 2.2 &&
          hb.shortestSide > 5 * w) {
        _bridge(best[opp]!, dirs[opp], w);
      }
    }
  }

  void _bridge((double, Offset, Offset) b, Offset v, double w) {
    final r = Rect.fromPoints(b.$2 - v * (3 + s.k * 2), b.$3 + v * 3);
    bridges.add(
      v.dx == 0
          ? Rect.fromLTRB(r.center.dx - w / 2, r.top, r.center.dx + w / 2, r.bottom)
          : Rect.fromLTRB(r.left, r.center.dy - w / 2, r.right, r.center.dy + w / 2),
    );
  }

  // ── Paint texture ─────────────────────────────────────────────────────────

  final _speckS = <Offset>[], _speckL = <Offset>[];
  final _grainD = <Offset>[], _grainL = <Offset>[];

  bool _inCut(Offset p) => inside(p) && !bridges.any((r) => r.contains(p));

  /// Inside the cut whether or not the traced outline sits a raster pixel
  /// off the raster cells (see [_bridgesFor]).
  bool _surelyInCut(Offset p) => _inCut(p) && _inCut(p + Offset(s.k, s.k));

  void _grain() {
    // Overspray speckles just outside the cut edges.
    var i = 0;
    final probe = s.k * 2 + 1;
    for (final m in cut.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 2.2, i++) {
        final tan = m.getTangentForOffset(d);
        if (tan == null || rnd(i, 3, 11) > 0.55) continue;
        final nrm = Offset(-tan.vector.dy, tan.vector.dx);
        final out = _inCut(tan.position + nrm * probe) ? -nrm : nrm;
        final r = rnd(i, 5, 11);
        final at = tan.position + out * (1 + 6 * r * r) + tan.vector * (rnd(i, 7, 11) - 0.5) * 2;
        (rnd(i, 9, 11) < 0.25 ? _speckL : _speckS).add(at);
      }
    }
    // Spray grain inside the letter.
    final ink = s.ink;
    final n = (ink.width * ink.height / 90).clamp(200, 1600).toInt();
    for (var k = 0; k < n; k++) {
      final p = Offset(ink.left + rnd(k, 1, 23) * ink.width, ink.top + rnd(k, 2, 23) * ink.height);
      if (!_surelyInCut(p)) continue;
      (k.isEven ? _grainD : _grainL).add(p);
    }
  }

  // ── Drawing ───────────────────────────────────────────────────────────────

  static final _fill = Paint();
  static final _edge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;
  static final _dots = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  /// The clear acrylic panel on two feet.
  void panelDraw(Canvas c, CraftContext x) {
    _fill.color = const Color(0x12FFFFFF);
    c.drawRect(panel, _fill);
    c.save();
    c.clipRect(panel);
    final g = x.st(const Color(0x0EFFFFFF), panel.width * 0.12);
    c.drawLine(
      panel.bottomLeft + Offset(panel.width * 0.15, 0),
      panel.topLeft + Offset(panel.width * 0.45, 0),
      g,
    );
    c.drawLine(
      panel.bottomLeft + Offset(panel.width * 0.42, 0),
      panel.topLeft + Offset(panel.width * 0.62, 0),
      g,
    );
    c.restore();
    c.drawRect(panel, x.st(const Color(0x66E3F2FF), 1.6));
    c.drawRect(panel.deflate(4), x.st(const Color(0x1FE3F2FF), 1));
    for (final o in [panel.topLeft, panel.topRight, panel.bottomLeft, panel.bottomRight]) {
      final at = o + Offset(o.dx < panel.center.dx ? 9 : -9, o.dy < panel.center.dy ? 9 : -9);
      c.drawCircle(at, 3, x.fl(BP.inkDim));
    }
  }

  /// The sprayed letter: a soft, slightly bled edge, grain and speckles.
  void paint(Canvas c) {
    _edge
      ..strokeWidth = 2.6
      ..color = paintCol.withValues(alpha: 0.45);
    c.drawPath(cut, _edge);
    _fill.color = paintCol;
    c.drawPath(cut, _fill);
    _dots
      ..strokeWidth = 1.8
      ..color = _paintDark.withValues(alpha: 0.45);
    c.drawPoints(PointMode.points, _grainD, _dots);
    _dots.color = _paintLight.withValues(alpha: 0.35);
    c.drawPoints(PointMode.points, _grainL, _dots);
    _dots
      ..strokeWidth = 1.4
      ..color = paintCol.withValues(alpha: 0.8);
    c.drawPoints(PointMode.points, _speckS, _dots);
    _dots.strokeWidth = 2.4;
    c.drawPoints(PointMode.points, _speckL, _dots);
  }

  /// Spray nozzle target for spray progress [u]: back and forth in passes
  /// from the top down.
  Offset nozzle(double u) {
    final f = u.clamp(0.0, 1.0) * passes;
    final k = math.min(passes - 1, f.floor());
    final g = u >= 1 ? 1.0 : f - k;
    final x0 = sheet.left - 6, x1 = sheet.right + 6;
    final x = k.isEven ? lerp(x0, x1, g) : lerp(x1, x0, g);
    return Offset(x, sheet.top + (k + 0.5) * band);
  }

  /// Where paint has landed by spray progress [u].
  Path sprayed(double u, Offset at) {
    final f = u.clamp(0.0, 1.0) * passes;
    final k = math.min(passes - 1, f.floor());
    final top = sheet.top + k * band;
    final x0 = sheet.left - 20, x1 = sheet.right + 20;
    final out = Path()..addRect(Rect.fromLTRB(x0, sheet.top - 20, x1, top + 0.5));
    out.addRect(
      k.isEven
          ? Rect.fromLTRB(x0, top, at.dx, top + band)
          : Rect.fromLTRB(at.dx, top, x1, top + band),
    );
    out.addOval(Rect.fromCircle(center: at, radius: band * 0.62));
    return out;
  }

  /// The stencil card where [show] allows, with overspray up to spray
  /// progress [u], and masking tape at the corners.
  void card(Canvas c, CraftContext x, Rect show, double u, Offset at) {
    c.save();
    c.clipRect(show);
    _fill.color = _card;
    c.drawPath(stencil, _fill);
    if (u > 0) {
      // Overspray on the card.
      c.save();
      if (u < 1) c.clipPath(sprayed(u, at));
      _fill.color = _overspray;
      c.drawPath(stencil, _fill);
      c.restore();
    }
    c.drawPath(stencil, x.st(_cardDark, 1.3));
    for (final o in [sheet.topLeft, sheet.topRight, sheet.bottomLeft, sheet.bottomRight]) {
      c.save();
      c.translate(o.dx, o.dy);
      c.rotate((o.dx < sheet.center.dx) == (o.dy < sheet.center.dy) ? -math.pi / 4 : math.pi / 4);
      c.drawRect(const Rect.fromLTWH(-17, -6, 34, 12), x.fl(const Color(0xE6EFE6C8)));
      c.restore();
    }
    c.restore();
  }

  /// The card rolled up at [y] ([rolled] 0..1 of it on the roll).
  void roll(Canvas c, CraftContext x, double y, double rolled, bool sprayedCard) {
    final th = 12 + 10 * rolled;
    final r = Rect.fromLTRB(sheet.left - 10, y - th / 2, sheet.right + 10, y + th / 2);
    final rr = RRect.fromRectAndRadius(r, Radius.circular(th / 2));
    c.drawRRect(rr, x.fl(_card));
    if (sprayedCard) c.drawRRect(rr, x.fl(_overspray));
    c.drawRRect(rr, x.st(_cardDark, 1.4));
    c.drawLine(
      Offset(r.left + th / 2, r.top + 2),
      Offset(r.right - th / 2, r.top + 2),
      x.st(const Color(0x66FFFFFF), 1.2),
    );
    for (final ex in [r.left + th / 2, r.right - th / 2]) {
      c.drawOval(
        Rect.fromCenter(center: Offset(ex, y), width: th * 0.55, height: th),
        x.st(_cardDark, 1),
      );
      c.drawOval(
        Rect.fromCenter(center: Offset(ex, y), width: th * 0.25, height: th * 0.5),
        x.st(_cardDark, 1),
      );
    }
  }

  /// Spray from the can's nozzle to the card: a fan of droplets and a mist.
  void mist(Canvas c, CraftContext x, Offset from, Offset to) {
    final frame = (x.t * 30).floor();
    final v = to - from;
    final len = v.distance;
    if (len < 1) return;
    final u = v / len, n = Offset(-u.dy, u.dx);
    final fan = Path()
      ..moveTo(from.dx, from.dy)
      ..lineTo(to.dx + n.dx * band * 0.5, to.dy + n.dy * band * 0.5)
      ..lineTo(to.dx - n.dx * band * 0.5, to.dy - n.dy * band * 0.5)
      ..close();
    c.drawPath(fan, x.fl(paintCol.withValues(alpha: 0.22)));
    x.glow(to, band * 0.7, paintCol, alpha: 0.5);
    final drops = <Offset>[], fine = <Offset>[];
    for (var i = 0; i < 44; i++) {
      final a = rnd(frame, i, x.seed);
      final spread = (rnd(i, frame, 3) - 0.5) * (4 + band * 1.1 * a);
      (i.isEven ? drops : fine).add(from + u * (len * a * 1.08) + n * spread);
    }
    _dots
      ..strokeWidth = 2.6
      ..color = paintCol;
    c.drawPoints(PointMode.points, drops, _dots);
    _dots
      ..strokeWidth = 1.6
      ..color = _paintLight;
    c.drawPoints(PointMode.points, fine, _dots);
  }
}
