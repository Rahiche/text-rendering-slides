import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../../../worlds/factory/factory_kit.dart';
import '../method.dart';
import '../stage.dart';
import 'neon.dart' show missingBranches;

/// 電飾 · Light bulbs: a red sheet-metal letter box (theatre marquee letter)
/// is hauled upright with ropes; two workers on lifts screw bulbs into the
/// sockets along the glyph's centre-line strokes, one by one (each bulb
/// blinks once when it's in); then the switch is thrown and the bulbs run a
/// chase.
class MarqueeCraft extends CraftMethod {
  const MarqueeCraft();

  @override
  String get id => 'marquee';

  @override
  String get en => 'Light bulbs';

  @override
  String get ja => '電飾';

  @override
  Color get color => BP.amber;

  @override
  double get weight => 1.0;

  static final _plans = Expando<_Marquee>();

  _Marquee _plan(GlyphStage s) => _plans[s] ??= _Marquee(s);

  // Timeline (fractions of p).
  static const _rise1 = 0.13; // the box is hauled upright
  static const _bulb0 = 0.17, _bulb1 = 0.79; // bulbs screwed in
  static const _fold1 = 0.82; // lifts fold down...
  static const _roll1 = 0.85; // ...and roll aside
  static const _walk1 = 0.88; // the right fitter goes to the switch
  static const _on = 0.895; // switch thrown: bulbs light up in a wave
  static const _chase = 0.94; // then the chase runs

  /// Junction box with the switch, on the floor right of the dais.
  static const _box = Rect.fromLTWH(1364, 640, 34, 44);

  @override
  void paintMaking(CraftContext x, double p) {
    final s = x.s, c = x.c;
    final m = _plan(s);
    if (m.bulbs.isEmpty) return;

    // The letter box, hauled upright (pivoting on its bottom edge).
    final up = eio(seg(p, 0, _rise1));
    final tilt = math.sin((0.08 + 0.92 * up) * math.pi / 2);
    c.save();
    if (tilt < 1) {
      c.translate(0, s.ink.bottom * (1 - tilt));
      c.scale(1, tilt);
    }
    m.box(c);
    // Bulbs: sockets, then the ones screwed in (blinking once when done).
    final q = seg(p, _bulb0, _bulb1);
    final installed = <Offset>[], blink = <Offset>[];
    final lit = <Offset>[];
    final wave = seg(p, _on, _on + 0.03);
    for (var i = 0; i < m.bulbs.length; i++) {
      final b = m.bulbs[i];
      final at = m.doneAt[i];
      if (q < at) continue;
      if (p >= _chase) {
        (m.chaseOn(i, x.t) ? lit : installed).add(b);
      } else if (p >= _on) {
        (i / m.bulbs.length <= wave ? lit : installed).add(b);
      } else if (q - at < m.blink) {
        blink.add(b);
      } else {
        installed.add(b);
      }
    }
    m.sockets(c);
    m.unlit(c, installed);
    m.lit(c, blink, 0.8);
    m.lit(c, lit, 1);
    c.restore();

    _props(x, m, p);
    if (p < _rise1 + 0.01) {
      _haul(x, m, tilt);
    } else {
      _fitters(x, m, p, q);
    }
  }

  /// Two workers on the floor pull the box upright with ropes.
  void _haul(CraftContext x, _Marquee m, double tilt) {
    final s = x.s;
    final bottom = s.ink.bottom;
    final anchor = Offset(m.top.dx, bottom - (bottom - m.top.dy) * tilt);
    for (final side in [-1, 1]) {
      final fx = side < 0 ? math.max(786.0, s.ink.left - 70) : math.min(1340.0, s.ink.right + 70);
      final dir = -side;
      final pose = Pose()
        ..lean = -0.28
        ..upA = 1.9
        ..foA = 2.1
        ..upB = 1.7
        ..foB = 2.0
        ..walk(x.t * 3, amp: 0.12, arms: false);
      final l = x.worker(
        Offset(fx, x.floorY),
        dir: dir,
        pose: pose,
        hat: side < 0 ? BP.amber : BP.coral,
      );
      x.c.drawLine(l.handA, anchor + Offset(side * 10.0, 0), x.st(Mat.wood, 1.6));
    }
  }

  /// The two fitters on lifts, each working through the bulbs on its side;
  /// then down, and one walks to the switch.
  void _fitters(CraftContext x, _Marquee m, double p, double q) {
    final s = x.s;
    for (final side in [0, 1]) {
      final idx = m.sides[side];
      final hat = side == 0 ? BP.amber : BP.coral;
      final dirOut = side == 0 ? 1 : -1; // faces the letter
      if (idx.isEmpty) {
        x.worker(
          Offset(side == 0 ? s.ink.left - 50 : s.ink.right + 50, x.floorY),
          dir: dirOut,
          hat: hat,
        );
        continue;
      }
      // Which bulb, and how far through its slot (move, then screw).
      final f = q * idx.length;
      final j = math.min(idx.length - 1, f.floor());
      final u = q >= 1 ? 1.0 : f - j;
      final cur = m.bulbs[idx[j]];
      final prev = j == 0 ? cur : m.bulbs[idx[j - 1]];
      final move = eio(seg(u, 0, 0.35));
      final target = Offset.lerp(prev, cur, move)!;
      final standX = (target.dx + (side == 0 ? -40.0 : 40.0)).clamp(720.0, 1380.0);
      // Rising from the floor at the start, folding down at the end.
      final low = x.floorY - 16;
      final rise = eio(seg(p, _bulb0 - 0.04, _bulb0));
      final down = eio(seg(p, _bulb1, _fold1));
      var platform = math.min(x.liftFor(target.dy), low);
      platform = lerp(low, platform, rise * (1 - down));
      if (p < _fold1) {
        x.lift(standX, platform, w: 54, col: BP.amber);
        final feet = Offset(standX, platform - 4);
        final dir = target.dx >= standX ? 1 : -1;
        if (rise < 1 || down > 0) {
          final pose = Pose()..upA = 0.4;
          final l = x.worker(feet, dir: dir, pose: pose, hat: hat);
          _bulbInHand(x, m, l.handA);
        } else {
          final screwing = u > 0.35 && q < 1;
          final reach = screwing
              ? cur + Offset(math.cos(x.t * 20) * 1.5, math.sin(x.t * 20) * 1.5)
              : target;
          final l = x.reach(feet, reach, dir: dir, hat: hat);
          if (!screwing) _bulbInHand(x, m, l.handA);
          if (screwing) {
            // The bulb going in, with a turning glint.
            final g = (u - 0.35) / 0.65;
            m.unlit(x.c, [cur], scale: 0.6 + 0.4 * g);
            final a = x.t * 14;
            x.c.drawLine(
              cur + Offset(math.cos(a), math.sin(a)) * (m.r * 1.6),
              cur - Offset(math.cos(a), math.sin(a)) * (m.r * 1.6),
              x.st(BP.ink.withValues(alpha: 0.8), 1.2),
            );
          }
        }
        continue;
      }
      // Folded down, each lift rolls aside with its fitter on it.
      final restX = side == 0
          ? math.max(782.0, s.ink.left - 46)
          : math.min(1316.0, s.ink.right + 46);
      final rx = lerp(standX, restX, eio(seg(p, _fold1, _roll1)));
      x.lift(rx, low, w: 54, col: BP.amber);
      final lit = p >= _on + 0.02;
      if (side == 0 || p < _roll1) {
        x.worker(
          Offset(rx, low - 4),
          dir: dirOut,
          pose: lit ? (Pose()..cheer(x.t, side)) : null,
          hat: hat,
        );
        continue;
      }
      // The right fitter hops off, walks to the switch and throws it.
      final w = seg(p, _roll1, _walk1);
      final fx = lerp(restX, _box.right + 24, eio(w));
      if (lit) {
        x.worker(Offset(fx, x.floorY), dir: -1, pose: Pose()..cheer(x.t, 2), hat: hat);
      } else if (w >= 1) {
        x.reach(Offset(fx, x.floorY), _lever(p), dir: -1, hat: hat);
      } else {
        x.worker(Offset(fx, x.floorY), dir: 1, pose: Pose()..walk(x.t * 9), hat: hat);
      }
    }
  }

  void _bulbInHand(CraftContext x, _Marquee m, Offset hand) =>
      m.unlit(x.c, [hand + Offset(0, -m.r * 0.6)], scale: 0.8);

  Offset _lever(double p) {
    final thrown = eio(seg(p, _on - 0.02, _on));
    final a = lerp(-2.1, -0.4, thrown);
    final pivot = Offset(_box.right + 2, _box.top + 26);
    return pivot + Offset(math.cos(a), math.sin(a)) * 16;
  }

  /// Bulb crate, cable and the junction box with its lever.
  void _props(CraftContext x, _Marquee m, double p) {
    final c = x.c;
    // Crate of bulbs.
    const crate = Rect.fromLTWH(1438, 668, 36, 32);
    x.ink.crate(crate, BP.amber);
    final left = (6 * (1 - seg(p, _bulb0, _bulb1))).ceil();
    final pts = [
      for (var i = 0; i < left; i++)
        Offset(crate.left + 7 + (i % 3) * 13.0, crate.top - 3 - (i ~/ 3) * 7.0),
    ];
    m.unlit(c, pts, scale: 0.75, r: 5);
    // Cable from the letter to the junction box.
    if (p >= _bulb1) {
      final s = x.s;
      final from = Offset(math.min(s.ink.right - 30, s.ink.center.dx + 60), s.ink.bottom);
      final cable = Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(from.dx + 20, x.floorY + 2, (from.dx + _box.left) / 2, x.floorY - 1)
        ..lineTo(_box.left - 10, x.floorY - 1)
        ..quadraticBezierTo(_box.left - 2, x.floorY - 1, _box.left, _box.bottom - 8);
      final metric = cable.computeMetrics().first;
      final part = metric.extractPath(0, metric.length * eo(seg(p, _bulb1, _bulb1 + 0.05)));
      c.drawPath(part, x.st(const Color(0xFF151A22), 4));
      c.drawPath(part, x.st(BP.inkDim, 1));
    }
    // Junction box with a lever.
    x.ink.box(_box, col: BP.inkDim, fill: const Color(0xFF1E2633));
    final on = p >= _on;
    x.ink.lamp(Offset(_box.center.dx, _box.top + 9), BP.amber, on, 4);
    final v = x.text.get('100V', BT.mono(9, color: BP.inkDim, weight: 600));
    v.paint(c, Offset(_box.center.dx - v.width / 2, _box.bottom - v.height - 4));
    final pivot = Offset(_box.right + 2, _box.top + 26);
    final h = _lever(p);
    c.drawLine(pivot, h, x.st(BP.ink, 2.4));
    c.drawCircle(h, 3, x.fl(BP.red));
    c.drawCircle(pivot, 2.2, x.fl(BP.inkDim));
  }

  @override
  void paintFinished(CraftContext x) {
    final m = _plan(x.s);
    if (m.bulbs.isEmpty) return;
    final c = x.c;
    m.box(c);
    m.sockets(c);
    final on = <Offset>[], off = <Offset>[];
    for (var i = 0; i < m.bulbs.length; i++) {
      (m.chaseOn(i, x.t) ? on : off).add(m.bulbs[i]);
    }
    m.unlit(c, off);
    m.lit(c, on, 1);
  }
}

/// The letter box and its bulbs for one character.
class _Marquee {
  _Marquee(this.s) {
    final rad = s.typicalRadius;
    r = (rad * 0.36).clamp(3.2, 9.0);
    gap = math.max(r * 3.2, 11.0);
    final dotty = s.strokes.isEmpty || s.strokeLength < 2.4 * rad;
    if (dotty) {
      _grid();
    } else {
      _alongStrokes();
    }
    if (bulbs.isEmpty) bulbs.add(s.ink.center);
    // Which fitter does which bulb, and when each one is in.
    for (var i = 0; i < bulbs.length; i++) {
      sides[bulbs[i].dx < s.ink.center.dx ? 0 : 1].add(i);
    }
    doneAt = List.filled(bulbs.length, 0);
    for (final idx in sides) {
      for (var j = 0; j < idx.length; j++) {
        doneAt[idx[j]] = (j + 1) / idx.length;
      }
    }
    blink = 0.4 / math.max(sides[0].length, sides[1].length);
    // Where the haul ropes are tied: the top of the glyph.
    final rows = s.rows;
    top = rows.isEmpty ? s.ink.topCenter : rows.first.center;
    back = s.outline.shift(Offset(depth, depth));
  }

  final GlyphStage s;
  late final double r;
  late final double gap;
  final bulbs = <Offset>[];
  final sides = [<int>[], <int>[]];
  late final List<double> doneAt;
  late final double blink;
  late final Offset top;
  late final Path back;

  double get depth => (s.typicalRadius * 0.22).clamp(3.0, 7.0);

  void _add(Offset p) {
    for (final b in bulbs) {
      if ((b - p).distance < gap * 0.72) return;
    }
    bulbs.add(p);
  }

  void _alongStrokes() {
    for (final st in s.strokes) {
      final l = st.length;
      if (l < gap * 0.6) {
        _add(st.at(l / 2).$1);
        continue;
      }
      final n = math.max(1, (l / gap).round());
      for (var i = 0; i <= n; i++) {
        _add(st.at(l * i / n).$1);
      }
    }
    // Bars the skeleton lost (the crossbar of an 'f').
    for (final (a, b) in missingBranches(s.geo)) {
      final pa = s.map(a.dx, a.dy), pb = s.map(b.dx, b.dy);
      final n = math.max(1, ((pb - pa).distance / gap).round());
      for (var i = 0; i <= n; i++) {
        _add(Offset.lerp(pa, pb, i / n)!);
      }
    }
  }

  /// A dot of a glyph ('.'): fill it with a grid of bulbs.
  void _grid() {
    final ink = s.ink;
    var row = 0;
    for (var y = ink.top + gap * 0.6; y < ink.bottom - gap * 0.3; y += gap * 0.87, row++) {
      for (var x = ink.left + gap * (row.isEven ? 0.5 : 1.0); x < ink.right; x += gap) {
        final p = Offset(x, y);
        final m = r + 3;
        if (s.outline.contains(p) &&
            s.outline.contains(p + Offset(m, 0)) &&
            s.outline.contains(p - Offset(m, 0)) &&
            s.outline.contains(p + Offset(0, m)) &&
            s.outline.contains(p - Offset(0, m))) {
          _add(p);
        }
      }
    }
  }

  /// Chase: two of every three bulbs lit, the gap running along the strokes.
  bool chaseOn(int i, double t) => (i + (t * 7).floor()) % 3 != 0;

  static const _face = Color(0xFFB8323F);
  static const _return = Color(0xFF5A1520);
  static const _socket = Color(0xFF3A0C14);

  static final _fill = Paint();
  static final _pts = Paint()
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  static final _trim = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;

  /// The sheet-metal box: its side (return), the painted face, gold trim.
  void box(Canvas c) {
    _fill.color = _return;
    c.drawPath(back, _fill);
    _fill.color = _face;
    c.drawPath(s.outline, _fill);
    _trim
      ..strokeWidth = 1.8
      ..color = BP.amber.withValues(alpha: 0.85);
    c.drawPath(s.outline, _trim);
  }

  void sockets(Canvas c) {
    _pts
      ..strokeWidth = 2 * r + 3
      ..color = _socket;
    c.drawPoints(PointMode.points, bulbs, _pts);
  }

  void unlit(Canvas c, List<Offset> at, {double scale = 1, double? r}) {
    if (at.isEmpty) return;
    final rr = (r ?? this.r) * scale;
    _pts
      ..strokeWidth = 2 * rr
      ..color = const Color(0xFFE6DCC2);
    c.drawPoints(PointMode.points, at, _pts);
    _pts
      ..strokeWidth = rr * 0.7
      ..color = const Color(0xFFFFFFFF);
    c.drawPoints(PointMode.points, [for (final p in at) p - Offset(rr * 0.3, rr * 0.3)], _pts);
  }

  void lit(Canvas c, List<Offset> at, double a) {
    if (at.isEmpty) return;
    _pts
      ..strokeWidth = 2 * r * 2.5
      ..color = BP.amber.withValues(alpha: 0.22 * a);
    c.drawPoints(PointMode.points, at, _pts);
    _pts
      ..strokeWidth = 2 * r * 1.5
      ..color = BP.amber.withValues(alpha: 0.4 * a);
    c.drawPoints(PointMode.points, at, _pts);
    _pts
      ..strokeWidth = 2 * r
      ..color = Color.lerp(BP.amber, const Color(0xFFFFFFFF), 0.45)!.withValues(alpha: a);
    c.drawPoints(PointMode.points, at, _pts);
    _pts
      ..strokeWidth = r
      ..color = const Color(0xFFFFFFFF).withValues(alpha: a);
    c.drawPoints(PointMode.points, at, _pts);
  }
}
