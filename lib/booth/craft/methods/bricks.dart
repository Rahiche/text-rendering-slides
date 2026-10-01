import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../../../worlds/factory/factory_kit.dart';
import '../method.dart';
import '../stage.dart';
import '../workshop_layout.dart';

/// レンガ積み · Bricklaying: a mason lays a running-bond brick wall course by
/// course from the bottom, along a taut string line: a mortar bed spread
/// with the trowel, then the bricks (cut to the glyph, every other course
/// starting with a half brick). A spirit level checks the courses, a plumb
/// line the finished wall. A helper mixes mortar next to the brick pallet.
class BricksCraft extends CraftMethod {
  const BricksCraft();

  @override
  String get id => 'bricks';

  @override
  String get en => 'Bricklaying';

  @override
  String get ja => 'レンガ積み';

  @override
  Color get color => Mat.brick;

  @override
  double get weight => 1.0;

  static final _walls = Expando<_Wall>();
  static final _pics = Expando<ui.Picture>();

  _Wall _wall(CraftContext x) => _walls[x.s] ??= _Wall(x.s, x.seed);

  static const _mortar = Color(0xFFD8D0C2);
  static const _wetMortar = Color(0xFFB9B1A4);
  static const _tones = [
    Color(0xFFD9785B),
    Color(0xFFC4644A),
    Color(0xFFE48C6B),
    Color(0xFFB65842),
    Color(0xFFCE6E51),
  ];
  static final _hi = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.3
    ..color = const Color(0x40FFFFFF);
  static final _lo = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = const Color(0x33000000);

  // ── The finished wall ─────────────────────────────────────────────────────

  /// Mortar under everything, bricks by tone, a highlight and a shadow edge
  /// per brick: a handful of draw calls, recorded once per character.
  ui.Picture _finished(CraftContext x) => _pics[x.s] ??= () {
    final s = x.s, w = _wall(x);
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.save();
    c.clipPath(s.outline);
    c.drawRect(s.ink.inflate(2), Paint()..color = _mortar);
    final fills = [for (final _ in _tones) Path()];
    final hi = Path(), lo = Path();
    for (final course in w.courses) {
      for (final b in course.bricks) {
        fills[b.tone].addRect(b.r);
        _edges(b.r, hi, lo);
      }
    }
    for (var i = 0; i < _tones.length; i++) {
      c.drawPath(fills[i], Paint()..color = _tones[i]);
    }
    c.drawPath(hi, _hi);
    c.drawPath(lo, _lo);
    c.restore();
    return rec.endRecording();
  }();

  static void _edges(Rect r, Path hi, Path lo) {
    if (r.width < 4) return;
    hi
      ..moveTo(r.left + 1.5, r.top + 1.2)
      ..lineTo(r.right - 1.5, r.top + 1.2);
    lo
      ..moveTo(r.left + 1.5, r.bottom - 1)
      ..lineTo(r.right - 1.5, r.bottom - 1);
  }

  void _brick(Canvas c, _Brick b, double joint) {
    c.drawRect(b.r.inflate(joint / 2), Paint()..color = _mortar);
    c.drawRect(b.r, Paint()..color = _tones[b.tone]);
    final hi = Path(), lo = Path();
    _edges(b.r, hi, lo);
    c.drawPath(hi, _hi);
    c.drawPath(lo, _lo);
  }

  @override
  void paintFinished(CraftContext x) => x.c.drawPicture(_finished(x));

  // ── Making ────────────────────────────────────────────────────────────────

  @override
  void paintMaking(CraftContext x, double p) {
    final s = x.s, c = x.c;
    final w = _wall(x);
    final lay = seg(p, 0.02, 0.86);
    c.drawPath(s.outline, x.st(BP.lineFaint, 1.2));
    _yard(x, lay);
    if (w.courses.isEmpty) return;
    final (ci, f) = w.at(lay);
    final done = lay >= 1 ? w.courses.length : ci;
    if (done > 0) {
      // Finished courses: the finished wall up to their top.
      c.save();
      c.clipRect(
        Rect.fromLTRB(s.ink.left - 8, w.courses[done - 1].top, s.ink.right + 8, s.ink.bottom + 8),
      );
      c.drawPicture(_finished(x));
      c.restore();
    }
    if (lay >= 1) {
      _plumbCheck(x, seg(p, 0.87, 0.97));
      return;
    }
    final course = w.courses[ci];
    final nb = course.bricks.length;
    final u = f * course.units;
    _stringLine(x, course.top);

    // Mortar bed along the course (spread ahead of the bricks), then the
    // bricks laid so far.
    final spread = u < _Wall.spreadUnits ? u / _Wall.spreadUnits : 1.0;
    final placed = u < _Wall.spreadUnits ? 0 : math.min(nb, (u - _Wall.spreadUnits).floor());
    final front = _bed(x, course, w.joint, spread);
    s.clipped(c, () {
      for (var j = 0; j < placed; j++) {
        _brick(c, course.bricks[j], w.joint);
      }
    });

    // What the mason is doing.
    final dir = course.dir;
    if (u < _Wall.spreadUnits) {
      final tip = Offset(front, course.bottom - w.joint);
      _mason(x, tip, dir, (limbs) => _trowel(x, limbs.handA, tip));
    } else if (placed < nb) {
      // A brick on its way from the mason's hand to its place.
      final b = course.bricks[placed];
      final m = (u - _Wall.spreadUnits) - placed;
      final fly = Offset(dir * 22.0, -w.h * 1.6) * (1 - eo(seg(m, 0, 0.8)));
      final tap = -2.5 * bump(seg(m, 0.8, 1));
      final off = fly + Offset(0, tap);
      c.save();
      c.translate(off.dx, off.dy);
      c.clipPath(s.outline);
      _brick(c, b, 0);
      c.restore();
      final grip = Offset(dir > 0 ? b.r.right : b.r.left, b.r.center.dy) + off;
      _mason(x, grip, dir, (limbs) {
        c.drawLine(limbs.handA, grip, x.st(BP.ink, 1.6));
      });
    } else {
      // Level check on top of the course.
      final g = (u - _Wall.spreadUnits - nb) / _Wall.levelUnits;
      final at = Offset(course.levelX, course.top - 5 - 18 * (1 - eo(seg(g, 0, 0.2))));
      final settle = math.sin(x.t * 11) * 5 * (1 - seg(g, 0.15, 0.7));
      _level(x, at, w.h * 3.6, settle);
      _mason(x, at + Offset(dir * w.h * 1.8, 0), dir, (limbs) {
        c.drawLine(limbs.handA, at + Offset(dir * w.h * 1.6, 0), x.st(BP.ink, 1.6));
      });
    }
  }

  /// Spreads the mortar bed along the course's spans in laying order up to
  /// [f]; returns the x of the spreading front.
  double _bed(CraftContext x, _Course course, double joint, double f) {
    final total = course.spans.fold<double>(0, (a, sp) => a + sp.$2 - sp.$1);
    var left = f * total;
    var front = course.dir > 0 ? course.spans.first.$1 : course.spans.last.$2;
    final rects = <Rect>[];
    final spans = course.dir > 0 ? course.spans : course.spans.reversed;
    for (final (a, b) in spans) {
      if (left <= 0) break;
      final len = math.min(left, b - a);
      left -= len;
      final (x0, x1) = course.dir > 0 ? (a, a + len) : (b - len, b);
      front = course.dir > 0 ? x1 : x0;
      rects.add(Rect.fromLTRB(x0, course.bottom - joint * 1.8, x1, course.bottom + joint * 0.5));
    }
    x.s.clipped(x.c, () {
      for (final r in rects) {
        x.c.drawRect(r, x.fl(_wetMortar));
      }
    });
    return front;
  }

  /// The mason's line: a string pulled taut along the top of the course,
  /// tied to two line blocks.
  void _stringLine(CraftContext x, double y) {
    final s = x.s;
    final a = Offset(s.ink.left - 18, y), b = Offset(s.ink.right + 18, y);
    x.c.drawLine(a, b, x.st(BP.amber.withValues(alpha: 0.85), 1));
    for (final e in [a, b]) {
      final r = Rect.fromCenter(center: e + const Offset(0, 4), width: 8, height: 10);
      x.c.drawRect(r, x.fl(Mat.wood));
      x.c.drawRect(r, x.st(Mat.woodDark, 1));
    }
  }

  /// The mason at [work] (on a lift when it's high), facing back along the
  /// course ([dir] is the laying direction); [tool] draws what's in hand.
  void _mason(CraftContext x, Offset work, int dir, void Function(Limbs limbs) tool) {
    final standX = work.dx + dir * 30;
    final feet = _stand(x, standX, work.dy);
    _bucket(x, feet + Offset(dir * 15.0, 0));
    final limbs = x.reach(feet, work, dir: -dir, hat: BP.coral);
    tool(limbs);
  }

  /// A mortar bucket standing at [base].
  void _bucket(CraftContext x, Offset base) {
    final c = x.c;
    final pail = Path()
      ..moveTo(base.dx - 8, base.dy - 15)
      ..lineTo(base.dx + 8, base.dy - 15)
      ..lineTo(base.dx + 6, base.dy)
      ..lineTo(base.dx - 6, base.dy)
      ..close();
    c.drawPath(pail, x.fl(Mat.steelDark));
    c.drawRect(Rect.fromLTRB(base.dx - 7, base.dy - 15, base.dx + 7, base.dy - 11), x.fl(_wetMortar));
    c.drawPath(pail, x.st(BP.ink, 1.1));
    c.drawArc(
      Rect.fromCenter(center: Offset(base.dx, base.dy - 15), width: 16, height: 12),
      math.pi,
      math.pi,
      false,
      x.st(BP.inkDim, 1),
    );
  }

  /// Puts a worker's feet where a hand can reach [targetY]: on a scissor lift
  /// when it's high, else on the dais (or the floor beside it).
  Offset _stand(CraftContext x, double sx, double targetY) {
    final platform = x.liftFor(targetY - 6);
    if (platform < x.floorY - 26) {
      x.lift(sx, platform, w: 48, col: BP.coral);
      return Offset(sx, platform - 4);
    }
    final onDais = sx > BW.dais.left + 6 && sx < BW.dais.right - 6;
    return Offset(sx, onDais ? x.daisY : x.floorY);
  }

  void _trowel(CraftContext x, Offset hand, Offset tip) {
    final c = x.c;
    final v = tip - hand;
    final l = v.distance;
    if (l < 1) return;
    final u = v / l;
    final n = Offset(-u.dy, u.dx);
    final heel = tip - u * 30;
    c.drawLine(hand - u * 3, heel - u * 2, x.st(Mat.woodDark, 4));
    final blade = Path()
      ..moveTo(heel.dx + n.dx * 10, heel.dy + n.dy * 10)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(heel.dx - n.dx * 10, heel.dy - n.dy * 10)
      ..close();
    c.drawPath(blade, x.fl(Mat.steel));
    c.drawPath(blade, x.st(Mat.steelDark, 1.2));
    // A dollop of mortar on the blade.
    c.drawCircle(Offset.lerp(heel, tip, 0.4)!, 4.5, x.fl(_wetMortar));
  }

  /// A spirit level lying at [at] ([len] long) with its bubble off by [off].
  void _level(CraftContext x, Offset at, double len, double off) {
    final c = x.c;
    final body = Rect.fromCenter(center: at, width: len, height: 9);
    c.drawRect(body, x.fl(BP.amber));
    c.drawRect(body, x.st(const Color(0xFF8A6A2A), 1.2));
    final vial = Rect.fromCenter(center: at, width: 18, height: 6);
    c.drawRRect(RRect.fromRectAndRadius(vial, const Radius.circular(3)), x.fl(const Color(0xFFB8F08A)));
    c.drawLine(vial.topCenter + const Offset(-4, 0), vial.bottomCenter + const Offset(-4, 0), x.st(BP.inkDim, 0.8));
    c.drawLine(vial.topCenter + const Offset(4, 0), vial.bottomCenter + const Offset(4, 0), x.st(BP.inkDim, 0.8));
    c.drawCircle(at + Offset(off.clamp(-6.0, 6.0), 0), 2.2, x.fl(BP.ink));
  }

  /// After the last course: a plumb line held beside the wall swings and
  /// settles.
  void _plumbCheck(CraftContext x, double g) {
    if (g <= 0 || g >= 1) return;
    final s = x.s, c = x.c;
    final lineX = s.ink.right + 14;
    final hold = Offset(lineX, s.ink.top + 8);
    final feet = _stand(x, lineX + 30, hold.dy + 10);
    final limbs = x.reach(feet, hold, dir: -1, hat: BP.coral);
    final swing = math.sin(x.t * 6) * 12 * math.pow(1 - g, 2);
    final bob = Offset(lineX + swing, s.ink.bottom - 30);
    c.drawLine(limbs.handA, hold, x.st(BP.ink, 1.2));
    c.drawLine(hold, bob, x.st(BP.ink, 1));
    final cone = Path()
      ..moveTo(bob.dx - 6, bob.dy)
      ..lineTo(bob.dx + 6, bob.dy)
      ..lineTo(bob.dx, bob.dy + 14)
      ..close();
    c.drawPath(cone, x.fl(Mat.bronze));
    c.drawPath(cone, x.st(const Color(0xFF8A5A2B), 1));
  }

  /// Right of the dais: a pallet of bricks that empties as the wall grows,
  /// and a helper mixing mortar in a tub.
  void _yard(CraftContext x, double lay) {
    final c = x.c, y = x.floorY;
    // Pallet.
    final pallet = Rect.fromLTRB(1426, y - 7, 1472, y);
    c.drawRect(pallet, x.fl(Mat.woodDark));
    c.drawRect(pallet, x.st(const Color(0xFF5E4024), 1));
    final left = (9 * (1 - lay)).ceil();
    for (var i = 0; i < left; i++) {
      final row = i ~/ 3, col = i % 3;
      final r = Rect.fromLTWH(1428 + col * 14.5 + (row.isOdd ? 3 : 0), y - 16 - row * 9, 14, 8);
      c.drawRect(r, x.fl(_tones[(i * 3) % _tones.length]));
      c.drawRect(r, x.st(const Color(0xFF7A3A2A), 1));
    }
    // Mortar tub.
    final tub = Path()
      ..moveTo(1374, y - 22)
      ..lineTo(1420, y - 22)
      ..lineTo(1414, y)
      ..lineTo(1380, y)
      ..close();
    c.drawPath(tub, x.fl(BP.panel));
    c.drawRect(Rect.fromLTRB(1376, y - 21, 1418, y - 15), x.fl(_wetMortar));
    c.drawPath(tub, x.st(BP.inkDim, 1.4));
    // The helper with a hoe.
    final mix = math.sin(x.t * 4.2);
    final pose = Pose()
      ..lean = 0.18
      ..upA = 1.0 + 0.25 * mix
      ..foA = 1.5 + 0.2 * mix
      ..upB = 0.8 + 0.2 * mix
      ..foB = 1.3;
    final limbs = x.worker(Offset(1364, y), dir: 1, pose: pose, h: 46, hat: BP.amber);
    final blade = Offset(1394 + 9 * mix, y - 17);
    c.drawLine(limbs.handB, blade, x.st(Mat.woodDark, 2));
    c.drawLine(blade - const Offset(0, 4), blade + const Offset(0, 3), x.st(Mat.steelDark, 3));
  }
}

class _Brick {
  _Brick(this.r, this.tone);

  /// The brick itself (mortar joints around it excluded), canvas px.
  final Rect r;
  final int tone;
}

class _Course {
  _Course(this.top, this.bottom, this.spans, this.bricks, this.dir, this.levelX, {required this.level});

  final double top;
  final double bottom;

  /// Inside spans of the glyph across the course, left to right.
  final List<(double, double)> spans;

  /// In laying order.
  final List<_Brick> bricks;

  /// Laying direction (1: left → right).
  final int dir;

  /// Where the spirit level goes (middle of the widest span).
  final double levelX;

  /// Whether the course ends with a level check.
  final bool level;

  double get units => _Wall.spreadUnits + bricks.length + (level ? _Wall.levelUnits : 0);
}

/// The wall: courses of real-proportion bricks (length ≈ 3 × course height)
/// in running bond, fitted to the glyph's spans.
class _Wall {
  _Wall(GlyphStage s, int seed) {
    final ink = s.ink;
    final n = math.max(1, (ink.height / 19).round()).clamp(1, 18);
    h = ink.height / n;
    joint = (h * 0.14).clamp(1.6, 3.0);
    final len = h * 3;
    for (var ci = 0; ci < n; ci++) {
      final bottom = ink.bottom - ci * h, top = bottom - h;
      final spans = _bandSpans(s, top, bottom);
      if (spans.isEmpty) continue;
      final dir = courses.length.isEven ? 1 : -1;
      final bricks = <_Brick>[];
      for (final (a, b) in spans) {
        for (final (x0, x1) in _pieces(a, b, len, half: ci.isOdd)) {
          final tone = (rnd(seed, ci * 131 + bricks.length, 5) * BricksCraft._tones.length).floor();
          bricks.add(
            _Brick(
              Rect.fromLTRB(x0 + joint / 2, top + joint / 2, x1 - joint / 2, bottom - joint / 2),
              tone,
            ),
          );
        }
      }
      var widest = spans.first;
      for (final sp in spans) {
        if (sp.$2 - sp.$1 > widest.$2 - widest.$1) widest = sp;
      }
      final level = (courses.length + 1) % 4 == 0;
      courses.add(
        _Course(
          top,
          bottom,
          spans,
          dir > 0 ? bricks : bricks.reversed.toList(),
          dir,
          (widest.$1 + widest.$2) / 2,
          level: level,
        ),
      );
    }
    var t = 0.0;
    for (final c in courses) {
      _starts.add(t);
      t += c.units;
    }
    _total = math.max(t, 1);
  }

  static const spreadUnits = 2.0;
  static const levelUnits = 3.0;

  late final double h;
  late final double joint;
  final courses = <_Course>[];
  final _starts = <double>[];
  late final double _total;

  /// The course being laid at laying progress [q], and how far into it.
  (int, double) at(double q) {
    final time = q.clamp(0.0, 1.0) * _total;
    var i = courses.length - 1;
    while (i > 0 && _starts[i] > time) {
      i--;
    }
    return (i, ((time - _starts[i]) / courses[i].units).clamp(0.0, 1.0));
  }

  /// Splits the span a..b into bricks of [len]: every other course starts
  /// with a half brick; the end is closed with a cut brick (two shorter
  /// ones rather than a sliver).
  static List<(double, double)> _pieces(double a, double b, double len, {required bool half}) {
    if (b - a <= len * 0.75) return [(a, b)];
    final out = <(double, double)>[];
    var x = a;
    var next = half ? len / 2 : len;
    while (b - x > next + len * 0.25) {
      out.add((x, x + next));
      x += next;
      next = len;
    }
    final rem = b - x;
    if (rem > len * 1.15) {
      out
        ..add((x, x + rem / 2))
        ..add((x + rem / 2, b));
    } else {
      out.add((x, b));
    }
    return out;
  }

  /// The glyph's inside across the band [y0, y1) (canvas): the union of
  /// the outline's inside along a few lines through the band.
  static List<(double, double)> _bandSpans(GlyphStage s, double y0, double y1) {
    final raw = <(double, double)>[
      for (final f in const [0.03, 0.25, 0.5, 0.75, 0.97]) ..._scan(s, lerp(y0, y1, f)),
    ];
    if (raw.isEmpty) return const [];
    raw.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(double, double)>[];
    var (a, b) = raw.first;
    for (final (c, d) in raw.skip(1)) {
      if (c <= b + 1) {
        b = math.max(b, d);
      } else {
        merged.add((a, b));
        (a, b) = (c, d);
      }
    }
    merged.add((a, b));
    return [
      for (final sp in merged)
        if (sp.$2 - sp.$1 >= 2) sp,
    ];
  }

  /// Inside intervals (canvas x, left to right) of the glyph's outline along
  /// the horizontal line [y] (even-odd over every contour).
  static List<(double, double)> _scan(GlyphStage s, double y) {
    final xs = <double>[];
    final ox = s.origin.dx, oy = s.origin.dy, k = s.k;
    for (final c in s.geo.contours) {
      final n = c.count, pts = c.pts;
      for (var i = 0; i < n; i++) {
        final j = i + 1 == n ? 0 : i + 1;
        final ay = oy + pts[2 * i + 1] * k, by = oy + pts[2 * j + 1] * k;
        if ((ay <= y) == (by <= y)) continue;
        final ax = ox + pts[2 * i] * k, bx = ox + pts[2 * j] * k;
        xs.add(ax + (y - ay) / (by - ay) * (bx - ax));
      }
    }
    xs.sort();
    return [for (var i = 0; i + 1 < xs.length; i += 2) (xs[i], xs[i + 1])];
  }
}
