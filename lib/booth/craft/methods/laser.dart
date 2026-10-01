import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../../../worlds/factory/factory_kit.dart';
import '../method.dart';
import '../stage.dart';
import '../workshop_layout.dart';

/// レーザー切断 · Laser cutting: a steel sheet stands in a CNC gantry; the
/// laser head traces every outline of the glyph (the holes first, like a
/// real nesting program), with a white-hot cut point, sparks and a glowing
/// kerf. Suction cups lift the cut letter out, the scrap sheet with its
/// letter-shaped hole tips over backwards, and the letter is set down: a
/// brushed-metal plate with a bevelled edge.
class LaserCraft extends CraftMethod {
  const LaserCraft();

  @override
  String get id => 'laser';

  @override
  String get en => 'Laser cutting';

  @override
  String get ja => 'レーザー切断';

  @override
  Color get color => Mat.steel;

  @override
  double get weight => 0.9;

  static final _plans = Expando<_Laser>();

  _Laser _plan(GlyphStage s) => _plans[s] ??= _Laser(s);

  // Timeline (fractions of p).
  static const _in0 = 0.0, _in1 = 0.05; // sheet slides into the frame
  static const _cut0 = 0.06, _cut1 = 0.68; // cutting
  static const _hook0 = 0.69, _hook1 = 0.73; // head parks, cups go on
  static const _up0 = 0.73, _up1 = 0.78; // letter lifted out
  static const _drop0 = 0.80, _drop1 = 0.87; // scrap tips over backwards
  static const _down0 = 0.88, _down1 = 0.93; // letter set down
  static const _off0 = 0.94, _off1 = 0.985; // cups off, machine away

  /// How high the cups lift the letter out of the sheet.
  static const _rise = 24.0;

  /// The CNC console on the floor right of the dais.
  static const _screen = Rect.fromLTWH(1366, 592, 62, 44);

  @override
  void paintMaking(CraftContext x, double p) {
    final s = x.s, c = x.c;
    final l = _plan(s);
    if (l.empty) return;
    final q = seg(p, _cut0, _cut1);
    final st = l.at(q);
    final lift = eio(seg(p, _up0, _up1)) - eio(seg(p, _down0, _down1));
    final fall = ei(seg(p, _drop0, _drop1));
    final machine = 1 - seg(p, _off0, _off1);

    // Machine frame behind the sheet.
    _layer(c, machine, () => _frame(x, l));

    // The sheet slides in from the right.
    final slide = (1 - eo(seg(p, _in0, _in1))) * 120;
    if (q < 1) {
      c.save();
      c.translate(slide, 0);
      l.metal(c, l.sheetPath);
      l.rim(c, x);
      // Layout marks, then the kerf cut so far.
      c.drawPath(s.outline, x.st(Mat.steelDark.withValues(alpha: 0.35), 1));
      final kerf = l.kerf(st);
      c.drawPath(kerf, x.st(const Color(0xFF161B22), 2.6));
      if (st.phase == _Phase.cut) l.trail(c, x, st);
      c.restore();
    } else {
      // The scrap sheet (with the letter-shaped hole) tips over backwards.
      if (fall < 1) {
        c.save();
        final k = math.cos(fall * math.pi / 2);
        c.translate(0, l.sheet.bottom * (1 - k));
        c.scale(1, k);
        l.metal(c, l.scrapPath);
        l.rim(c, x);
        c.drawPath(s.outline, x.st(const Color(0xFF161B22), 2.2));
        if (fall > 0) {
          c.drawRect(l.sheet, x.fl(const Color(0xFF000000).withValues(alpha: 0.45 * fall)));
        }
        c.restore();
        // The letter's shadow on the sheet behind it.
        if (lift > 0) {
          c.save();
          c.translate(7 * lift, 9 * lift - _rise * lift);
          c.drawPath(
            s.outline,
            x.fl(const Color(0xFF000000).withValues(alpha: 0.38 * lift * (1 - fall))),
          );
          c.restore();
        }
      }
      if (fall > 0.85) _dust(x, l, seg(p, _drop1 - 0.01, _drop1 + 0.06));
      // The letter, lifted towards the viewer.
      c.save();
      _liftTransform(c, s, lift);
      l.letter(c, x, seg(p, _up0, _up1));
      c.restore();
    }

    // Gantry beam, head, cups.
    _layer(c, machine, () => _gantry(x, l, p, q, st, lift));
    _console(x, l, p, st);
  }

  void _liftTransform(Canvas c, GlyphStage s, double lift) {
    if (lift <= 0) return;
    final k = 1 + 0.035 * lift;
    final o = s.ink.center;
    c.translate(o.dx, o.dy - _rise * lift);
    c.scale(k);
    c.translate(-o.dx, -o.dy);
  }

  /// Draws [paint] faded by [a] (one layer only while fading).
  void _layer(Canvas c, double a, void Function() paint) {
    if (a <= 0) return;
    if (a >= 1) {
      paint();
      return;
    }
    c.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, a));
    paint();
    c.restore();
  }

  /// Two rails standing on the floor and a cross bar at the top.
  void _frame(CraftContext x, _Laser l) {
    final c = x.c;
    final f = l.frame;
    for (final rx in [f.left, f.right]) {
      final r = Rect.fromLTRB(rx - 6, f.top, rx + 6, x.floorY);
      c.drawRect(r, x.fl(BP.panel));
      c.drawRect(r, x.st(BP.line, 1.4));
      final ticks = Path();
      for (var y = f.top + 14; y < x.floorY - 8; y += 14) {
        ticks
          ..moveTo(rx - 6, y)
          ..lineTo(rx - 2, y);
      }
      c.drawPath(ticks, x.st(BP.lineDim, 1));
      // Foot.
      c.drawRect(Rect.fromLTRB(rx - 14, x.floorY - 6, rx + 14, x.floorY), x.fl(BP.lineDim));
    }
    final top = Rect.fromLTRB(f.left - 8, f.top - 8, f.right + 8, f.top + 2);
    x.ink.box(top, col: BP.line);
    final label = x.text.get('CNC LASER 4kW', BT.mono(10, color: BP.inkDim, weight: 600));
    label.paint(c, Offset(top.center.dx - label.width / 2, top.center.dy - label.height / 2));
  }

  /// The gantry beam riding the rails, the laser head on it, and later the
  /// suction cups hanging from the beam.
  void _gantry(CraftContext x, _Laser l, double p, double q, _At st, double lift) {
    final c = x.c;
    final f = l.frame;
    final park = Offset(f.right - 22, l.sheet.top + 4);
    Offset head;
    if (q < 1) {
      head = st.pos - const Offset(0, 34);
    } else {
      final last = l.at(1).pos - const Offset(0, 34);
      head = Offset.lerp(last, park, eio(seg(p, _cut1, _hook0 + 0.02)))!;
    }
    final beamY = head.dy - (q >= 1 ? _rise * lift : 0);
    if (q >= 1) head = Offset(head.dx, beamY);
    // Beam.
    final beam = Rect.fromLTRB(f.left - 10, beamY - 6, f.right + 10, beamY + 6);
    c.drawRect(beam, x.fl(BP.panel));
    c.drawRect(beam, x.st(BP.amber.withValues(alpha: 0.9), 1.4));
    for (final ex in [f.left, f.right]) {
      c.drawRect(Rect.fromCenter(center: Offset(ex, beamY), width: 18, height: 20), x.fl(BP.amber));
    }
    // Cable chain from the left end to the head.
    final chain = Path();
    for (var cx = f.left + 12; cx < head.dx - 16; cx += 9) {
      chain.addRect(Rect.fromLTWH(cx, beamY - 12, 6, 5));
    }
    c.drawPath(chain, x.st(BP.lineDim, 1));

    // Suction cups on hoses (after the cut).
    final hook = seg(p, _hook0, _hook1);
    final off = seg(p, _off0, _off0 + 0.03);
    if (q >= 1 && hook > 0 && off < 1) {
      for (final cup in l.cups) {
        final at = cup - Offset(0, _rise * lift);
        final reach = (at.dy - beamY) * (hook < 1 ? eo(hook) : 1 - eio(off));
        final end = Offset(at.dx, beamY + reach);
        c.drawLine(Offset(at.dx, beamY + 6), end, x.st(BP.ink, 3.2));
        c.drawLine(Offset(at.dx, beamY + 6), end, x.st(BP.lineDim, 1.2));
        if (reach >= at.dy - beamY - 0.5) {
          final cupR = Rect.fromCenter(center: at, width: 26, height: 14);
          c.drawOval(cupR, x.fl(const Color(0xFF242A33)));
          c.drawOval(cupR, x.st(BP.ink, 1.6));
          c.drawRect(
            Rect.fromCenter(center: at - const Offset(0, 9), width: 8, height: 6),
            x.fl(BP.amber),
          );
        }
      }
    }

    // Head: carriage, nozzle, beam to the sheet.
    final cut = st.phase != _Phase.move && q > 0 && q < 1;
    final carriage = Rect.fromCenter(center: head, width: 30, height: 22);
    c.drawRect(carriage, x.fl(const Color(0xFF1E2633)));
    c.drawRect(carriage, x.st(BP.ink, 1.4));
    c.drawCircle(head + const Offset(-7, -4), 2.4, x.fl(cut ? BP.red : BP.lineDim));
    final nozzle = Path()
      ..moveTo(head.dx - 7, head.dy + 11)
      ..lineTo(head.dx + 7, head.dy + 11)
      ..lineTo(head.dx + 2.5, head.dy + 25)
      ..lineTo(head.dx - 2.5, head.dy + 25)
      ..close();
    c.drawPath(nozzle, x.fl(Mat.bronze));
    c.drawPath(nozzle, x.st(BP.ink, 1));
    if (!cut) return;
    final tip = st.pos;
    final pierce = st.phase == _Phase.pierce;
    final frame = (x.t * 30).floor();
    final flicker = 0.85 + 0.15 * rnd(frame, 3, x.seed);
    c.drawLine(Offset(tip.dx, head.dy + 25), tip, x.st(BP.red.withValues(alpha: 0.9), 3.2));
    c.drawLine(Offset(tip.dx, head.dy + 25), tip, x.st(const Color(0xFFFFE6EA), 1.2));
    // Fumes rising from the cut.
    x.ink.steam(
      tip - const Offset(0, 6),
      x.t,
      per: 0.1,
      life: 0.8,
      rise: 34,
      r: 5,
      seed: x.seed,
      drift: 6,
    );
    x.glow(tip, (pierce ? 26 : 18) * flicker, Mat.molten, alpha: 0.75);
    c.drawCircle(tip, pierce ? 5.5 : 4, x.fl(const Color(0xFFFFFBEA)));
    // Sparks (they don't fall through the floor).
    c.save();
    c.clipRect(Rect.fromLTRB(0, 0, BW.hall.right, x.floorY - 1));
    _sparks(x, tip, st, pierce);
    c.restore();
  }

  /// Molten sparks: they fly out and fall.
  void _sparks(CraftContext x, Offset at, _At st, bool pierce) {
    final c = x.c;
    final frame = (x.t * 30).floor();
    final n = pierce ? 22 : 14;
    final path = Path();
    final hot = Path();
    for (var i = 0; i < n; i++) {
      final a = pierce
          ? rnd(frame, i, x.seed) * math.pi * 2
          : math.pi / 2 + (rnd(frame, i, x.seed) - 0.5) * 2.2 - st.dir.dx * 0.5;
      final l = (8 + 34 * rnd(i, frame, 5)) * (pierce ? 1.1 : 1);
      final v = Offset(math.cos(a), math.sin(a));
      final g = Offset(0, 0.012 * l * l);
      final p0 = at + v * (l * 0.35) + g * 0.3, p1 = at + v * l + g;
      (i.isEven ? path : hot)
        ..moveTo(p0.dx, p0.dy)
        ..lineTo(p1.dx, p1.dy);
    }
    c.drawPath(path, x.st(Mat.molten, 1.5));
    c.drawPath(hot, x.st(const Color(0xFFFFF0B3), 1.2));
  }

  void _dust(CraftContext x, _Laser l, double age) {
    for (var i = 0; i < 6; i++) {
      final px = lerp(l.sheet.left + 20, l.sheet.right - 20, i / 5);
      x.ink.puff(Offset(px, x.floorY - 6), age, 4, 16 + 6 * rnd(i, x.seed), BP.inkDim);
    }
  }

  /// The operator at the console; its screen shows the toolpath and the
  /// head's position.
  void _console(CraftContext x, _Laser l, double p, _At st) {
    final c = x.c;
    const r = _screen;
    c.drawLine(Offset(r.center.dx, r.bottom), Offset(r.center.dx, x.floorY), x.st(BP.lineDim, 3));
    c.drawLine(
      Offset(r.center.dx - 14, x.floorY - 1),
      Offset(r.center.dx + 14, x.floorY - 1),
      x.st(BP.lineDim, 3),
    );
    x.ink.box(r.inflate(3), col: BP.inkDim, fill: const Color(0xFF0A1410));
    // The glyph's outline on the screen, the cut part bright.
    final s = x.s;
    final k = math.min((r.width - 10) / s.ink.width, (r.height - 10) / s.ink.height);
    c.save();
    c.translate(r.center.dx, r.center.dy);
    c.scale(k);
    c.translate(-s.ink.center.dx, -s.ink.center.dy);
    c.drawPath(s.outline, x.st(BP.green.withValues(alpha: 0.3), 1 / k));
    final q = seg(p, _cut0, _cut1);
    c.drawPath(l.kerf(st), x.st(BP.green, 1.6 / k));
    if (q > 0 && q < 1) c.drawCircle(st.pos, 2.8 / k, x.fl(BP.red));
    c.restore();
    final pct = x.text.get('${(q * 100).floor()}%', BT.mono(9, color: BP.green, weight: 600));
    pct.paint(c, Offset(r.right - pct.width - 2, r.bottom - pct.height));
    // Big green button (drops the scrap).
    final btn = Offset(r.left + 6, r.bottom + 10);
    final pressed = p >= _drop0 - 0.02 && p < _drop0 + 0.01;
    c.drawCircle(btn, 4, x.fl(pressed ? BP.amber : BP.green));
    // The operator.
    const feet = Offset(1452, BW.floorY);
    final pose = Pose();
    if (p >= _off1) {
      pose.cheer(x.t, 2);
    } else if (p >= _drop0 - 0.03 && p < _drop0 + 0.02) {
      x.reach(feet, btn, dir: -1, h: 48, hat: BP.line);
      return;
    } else {
      pose
        ..upA = 1.25 + 0.08 * math.sin(x.t * 9)
        ..foA = 1.7 + 0.12 * math.sin(x.t * 11)
        ..upB = 1.1
        ..foB = 1.5
        ..head = -0.1;
    }
    final limbs = x.worker(feet, dir: -1, pose: pose, h: 48, hat: BP.line);
    // Safety glasses.
    c.drawLine(
      limbs.head + const Offset(-6, -1),
      limbs.head + const Offset(-1, -1),
      x.st(BP.green, 2),
    );
  }

  @override
  void paintFinished(CraftContext x) {
    final l = _plan(x.s);
    if (l.empty) return;
    l.letter(x.c, x, 1);
  }
}

enum _Phase { move, pierce, cut }

typedef _At = ({int k, _Phase phase, Offset pos, Offset dir, double d});

/// The sheet, the materials and the toolpath for one character.
class _Laser {
  _Laser(this.s) {
    final m = math.max(16.0, s.ink.height * 0.05);
    sheet = Rect.fromLTRB(s.ink.left - m, s.ink.top - m, s.ink.right + m, BW.floorY - 6);
    frame = Rect.fromLTRB(sheet.left - 16, sheet.top - 18, sheet.right + 16, BW.floorY);
    sheetPath = Path()..addRect(sheet);
    scrapPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(sheet)
      ..addPath(s.outline, Offset.zero);
    _materials();
    _toolpath();
    _cupsAt();
  }

  final GlyphStage s;
  late final Rect sheet;
  late final Rect frame;
  late final Path sheetPath;
  late final Path scrapPath;

  bool get empty => order.isEmpty;

  // ── Material: brushed steel ───────────────────────────────────────────────

  late final Paint _base;
  final _light = Path(), _dark = Path();

  void _materials() {
    _base = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE6EAEF), Color(0xFFB9C1CB), Color(0xFFD9DEE4), Color(0xFF9EA7B2)],
        stops: [0, 0.38, 0.62, 1],
      ).createShader(sheet);
    // Fine diagonal brush streaks.
    final n = (sheet.width * sheet.height / 700).clamp(60, 400).toInt();
    const u = Offset(0.94, -0.34);
    for (var i = 0; i < n; i++) {
      final o = Offset(
        sheet.left + rnd(i, 1, 77) * sheet.width,
        sheet.top + rnd(i, 2, 77) * sheet.height,
      );
      final len = 20 + 110 * rnd(i, 3, 77);
      (i.isEven ? _light : _dark)
        ..moveTo(o.dx, o.dy)
        ..lineTo(o.dx + u.dx * len, o.dy + u.dy * len);
    }
  }

  static final _streak = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  static final _bevel = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;

  /// Brushed steel inside [clip].
  void metal(Canvas c, Path clip) {
    c.save();
    c.clipPath(clip);
    c.drawRect(sheet, _base);
    _streak.color = const Color(0x40FFFFFF);
    c.drawPath(_light, _streak);
    _streak.color = const Color(0x2A27303B);
    c.drawPath(_dark, _streak);
    c.restore();
  }

  void rim(Canvas c, CraftContext x) {
    c.drawRect(sheet, x.st(Mat.steelDark, 1.6));
    // Clamps on the rails.
    for (final y in [sheet.top + 24, sheet.bottom - 24]) {
      c.drawRect(Rect.fromLTWH(sheet.left - 10, y - 6, 16, 12), x.fl(BP.lineDim));
      c.drawRect(Rect.fromLTWH(sheet.right - 6, y - 6, 16, 12), x.fl(BP.lineDim));
    }
  }

  /// The cut letter: brushed steel with a bevelled edge ([bevel] 0..1).
  void letter(Canvas c, CraftContext x, double bevel) {
    metal(c, s.outline);
    if (bevel > 0) {
      final b = (s.typicalRadius * 0.11).clamp(1.6, 4.0);
      c.save();
      c.clipPath(s.outline);
      _bevel
        ..strokeWidth = 2 * b
        ..color = Color.fromRGBO(255, 255, 255, 0.7 * bevel);
      c.save();
      c.translate(b * 0.9, b * 0.9);
      c.drawPath(s.outline, _bevel);
      c.restore();
      _bevel.color = Color.fromRGBO(40, 48, 60, 0.55 * bevel);
      c.save();
      c.translate(-b * 0.9, -b * 0.9);
      c.drawPath(s.outline, _bevel);
      c.restore();
      c.restore();
    }
    c.drawPath(s.outline, x.st(const Color(0xFF4A5462), 1.3));
  }

  // ── Toolpath: holes first, then the outer outlines ───────────────────────

  final order = <int>[];
  final _move = <double>[], _pierce = <double>[], _cut = <double>[], _end = <double>[];
  double _span = 1;

  void _toolpath() {
    final n = s.contours.length;
    final holes = [
      for (var i = 0; i < n; i++)
        if (s.contourHole[i]) i,
    ];
    final outers = [
      for (var i = 0; i < n; i++)
        if (!s.contourHole[i]) i,
    ];
    int byPos(int a, int b) {
      final ra = s.contours[a].getBounds(), rb = s.contours[b].getBounds();
      final ya = (ra.top / 40).floor(), yb = (rb.top / 40).floor();
      return ya != yb ? ya.compareTo(yb) : ra.left.compareTo(rb.left);
    }

    holes.sort(byPos);
    outers.sort(byPos);
    order.addAll([...holes, ...outers]);
    final total = s.outlineLength;
    final pierce = math.max(30.0, total * 0.025);
    var t = 0.0;
    var at = Offset(sheet.right, sheet.top);
    for (final k in order) {
      final m = s.contourMetrics[k];
      final start = m.getTangentForOffset(0)?.position ?? at;
      _move.add(t);
      t += (start - at).distance / 5;
      _pierce.add(t);
      t += pierce;
      _cut.add(t);
      t += m.length;
      _end.add(t);
      at = start;
    }
    _span = math.max(t, 1);
  }

  /// Toolpath at progress [q]: contour (index in [order]), what the head is
  /// doing, where it is, and how far along the contour it has cut.
  _At at(double q) {
    const right = Offset(1, 0);
    if (order.isEmpty) return (k: 0, phase: _Phase.move, pos: s.ink.center, dir: right, d: 0);
    final time = q.clamp(0.0, 1.0) * _span;
    var i = order.length - 1;
    while (i > 0 && _move[i] > time) {
      i--;
    }
    final m = s.contourMetrics[order[i]];
    final start = m.getTangentForOffset(0)?.position ?? s.ink.center;
    if (time < _pierce[i]) {
      final from = i == 0 ? Offset(sheet.right, sheet.top) : _startOf(i - 1);
      final f = eio(c01((time - _move[i]) / math.max(1e-9, _pierce[i] - _move[i])));
      return (k: i, phase: _Phase.move, pos: Offset.lerp(from, start, f)!, dir: right, d: 0);
    }
    if (time < _cut[i]) return (k: i, phase: _Phase.pierce, pos: start, dir: right, d: 0);
    final d = math.min(m.length, time - _cut[i]);
    final tan = m.getTangentForOffset(d);
    return (k: i, phase: _Phase.cut, pos: tan?.position ?? start, dir: tan?.vector ?? right, d: d);
  }

  Offset _startOf(int i) =>
      s.contourMetrics[order[i]].getTangentForOffset(0)?.position ?? s.ink.center;

  /// The kerf cut so far.
  Path kerf(_At st) {
    final out = Path();
    for (var i = 0; i < st.k; i++) {
      out.addPath(s.contours[order[i]], Offset.zero);
    }
    if (st.phase == _Phase.cut && st.d > 0) {
      out.addPath(s.contourMetrics[order[st.k]].extractPath(0, st.d), Offset.zero);
    }
    return out;
  }

  /// The freshly cut edge behind the head, still glowing.
  void trail(Canvas c, CraftContext x, _At st) {
    final m = s.contourMetrics[order[st.k]];
    const len = 70.0;
    for (var j = 0; j < 4; j++) {
      final a = st.d - len * (1 - j / 4), b = st.d - len * (1 - (j + 1) / 4);
      if (b <= 0) continue;
      c.drawPath(
        m.extractPath(math.max(0, a), b),
        x.st(Color.lerp(const Color(0xFFB0341E), const Color(0xFFFFD27A), j / 3)!, 2.4 + j * 0.5),
      );
    }
  }

  // ── Suction cups ──────────────────────────────────────────────────────────

  final cups = <Offset>[];

  /// On the material: the middles of the longest strokes, spread out.
  void _cupsAt() {
    final strokes = [...s.strokes]..sort((a, b) => b.length.compareTo(a.length));
    for (final st in strokes) {
      if (cups.length >= 3) break;
      final (pos, _, _) = st.at(st.length / 2);
      if (!s.outline.contains(pos)) continue;
      if (cups.any((c) => (c - pos).distance < s.ink.width * 0.25)) continue;
      cups.add(pos);
    }
    if (cups.isEmpty) cups.add(s.ink.center);
  }
}
