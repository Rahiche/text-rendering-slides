import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../../../worlds/factory/factory_kit.dart';
import '../geometry.dart';
import '../method.dart';
import '../stage.dart';

/// 鋳造 · Casting: a sand mould, cut away to show the glyph-shaped cavity.
/// A worker shovels the sand in; another fills a crucible at the furnace,
/// rides a lift up and pours: the metal runs down the sprue and fills the
/// cavity from the bottom with a glowing, wavy surface. It cools from
/// yellow-hot through red to a dull casting, the mould is knocked apart
/// (the sand crumbles off) and a polish brings out the bronze.
class CastingCraft extends CraftMethod {
  const CastingCraft();

  @override
  String get id => 'casting';

  @override
  String get en => 'Casting';

  @override
  String get ja => '鋳造';

  @override
  Color get color => Mat.bronze;

  @override
  double get weight => 1.0;

  static final _moulds = Expando<_Mould>();
  static final _bronzes = Expando<Paint>();

  static _Mould _mould(CraftContext x) => _moulds[x.s] ??= _Mould(x.s, x.seed, x.daisY, x.floorY);

  /// Polished bronze: a diagonal gradient with a soft sheen band.
  static Paint _bronze(GlyphStage s) => _bronzes[s] ??= Paint()
    ..shader = ui.Gradient.linear(
      s.ink.topLeft,
      s.ink.bottomRight,
      const [_bronzeHi, Mat.bronze, _sheen, _bronzeMid, _bronzeLo],
      const [0.0, 0.36, 0.47, 0.6, 1.0],
    );

  // ── Timeline (fractions of p) ─────────────────────────────────────────────
  static const _sandEnd = 0.14; // sand shovelled into the flask
  static const _tapStart = 0.09, _tapEnd = 0.21; // furnace → crucible
  static const _riseStart = 0.22, _riseEnd = 0.29;
  static const _pourStart = 0.31, _pourEnd = 0.61;
  static const _lowerStart = 0.65, _lowerEnd = 0.74;
  static const _coolStart = 0.6, _coolEnd = 0.84;
  static const _knockStart = 0.79; // hammer blows every _blow
  static const _blow = 0.025;
  static const _crumbleStart = 0.875;
  static const _polishStart = 0.94;

  @override
  void paintMaking(CraftContext x, double p) {
    final s = x.s;
    if (s.contours.isEmpty) return;
    final m = _mould(x);
    p = p.clamp(0.0, 1.0);

    // The furnace fades in, and away again as the job wraps up.
    final show = seg(p, 0, 0.03) * (1 - seg(p, 0.93, 0.995));
    if (show > 0) {
      if (show < 1) {
        final r = Rect.fromLTRB(math.min(m.launderEnd.dx, m.furnaceX - 30) - 12, 430, m.furnaceX + 40, x.floorY + 2);
        x.c.saveLayer(r, Paint()..color = Color.fromRGBO(0, 0, 0, show));
      }
      _furnace(x, m, p);
      if (show < 1) x.c.restore();
    }
    if (p < _crumbleStart) {
      _mouldBox(x, m, p);
    } else {
      _letter(x, p);
      _crumble(x, m, p);
    }
    _flask(x, m, p);
    _steam(x, m, p);
    _pourer(x, m, p);
    _helper(x, m, p);
    _grains(x, m, p);
  }

  @override
  void paintFinished(CraftContext x) {
    final s = x.s;
    if (s.contours.isEmpty) return;
    x.c.drawPath(s.outline, _bronze(s));
    x.c.drawPath(s.outline, x.st(_bronzeEdge, 2.2));
  }

  // ── The mould ─────────────────────────────────────────────────────────────

  void _mouldBox(CraftContext x, _Mould m, double p) {
    final s = x.s, c = x.c, box = m.box;
    final sandIn = eo(seg(p, 0, _sandEnd));
    final top = lerp(box.bottom, box.top, sandIn);
    if (sandIn > 0) {
      c.save();
      c.clipRect(Rect.fromLTRB(box.left, top, box.right, box.bottom));
      c.drawRect(box, x.fl(_sand));
      c.drawPoints(ui.PointMode.points, m.speckDark, x.st(_sandShade, 2.2));
      c.drawPoints(ui.PointMode.points, m.speckLight, x.st(_sandLight, 2.2));
      c.drawPath(s.outline, x.fl(_cavity));
      c.drawPath(m.gates, x.fl(_cavity));
      c.drawPath(s.outline, x.st(_sandShade, 2.4));
      c.restore();
      if (sandIn < 1) {
        // A heaped surface where the sand lands.
        final heap = Path()..moveTo(box.left, top);
        for (var i = 1; i <= 8; i++) {
          final hx = box.left + box.width * i / 8;
          heap.quadraticBezierTo(hx - box.width / 16, top - 9 * rnd(i, x.seed, 5), hx, top);
        }
        heap.close();
        c.drawPath(heap, x.fl(_sand));
      }
    }
    if (p < _pourStart) return;
    final level = eio(seg(p, _pourStart, _pourEnd));
    final cool = seg(p, _coolStart, _coolEnd);
    if (p < _pourEnd) {
      _pourMetal(x, m, level);
    } else {
      _coolMetal(x, cool);
    }
    // Pouring cup, sprue and runner full of metal.
    c.drawPath(m.gates, x.fl(p < _pourEnd ? _orange : _coolBase(cool)));
    if (p < _pourEnd) c.drawPath(m.gates, x.st(_white, 1.4));
    _cracks(x, m, p);
  }

  /// The cavity filling: metal up to [level] with a wavy, glowing surface.
  void _pourMetal(CraftContext x, _Mould m, double level) {
    final s = x.s, c = x.c, ink = s.ink;
    final y = m.levelAt(level);
    final body = Path()..moveTo(ink.left - 6, ink.bottom + 4);
    final surface = Path();
    for (var px = ink.left - 6; px <= ink.right + 6; px += 5) {
      final wy = y + 2.4 * math.sin(px * 0.07 + x.t * 7) + 1.5 * math.sin(px * 0.17 - x.t * 4.3);
      body.lineTo(px, wy);
      px == ink.left - 6 ? surface.moveTo(px, wy) : surface.lineTo(px, wy);
    }
    body
      ..lineTo(ink.right + 6, ink.bottom + 4)
      ..close();
    s.clipped(c, () {
      c.drawPath(
        body,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, y - 4),
            Offset(0, y + 70),
            const [_white, Mat.molten, _orange],
            const [0, 0.3, 1],
          ),
      );
      c.drawPath(surface, x.st(_white, 3));
    });
  }

  static Color _coolBase(double cool) => cool < 0.5
      ? Color.lerp(_orange, _red, cool / 0.5)!
      : Color.lerp(_red, _dull, (cool - 0.5) / 0.5)!;

  /// Full of metal, cooling from the outside in: the hot core (along the
  /// strokes' centre lines) narrows and fades as the base turns dull.
  void _coolMetal(CraftContext x, double cool) {
    final s = x.s, c = x.c;
    c.drawPath(s.outline, x.fl(_coolBase(cool)));
    if (cool < 1) {
      // The core along the strokes, softened by one blur over the layer.
      final sigma = math.max(2.0, s.typicalRadius * 0.45);
      final core = Paint()..color = Color.lerp(_core, Mat.molten, cool)!.withValues(alpha: 1 - 0.7 * cool);
      s.clipped(c, () {
        c.saveLayer(s.ink.inflate(4), Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma));
        s.paintStrokesUpTo(c, 1, core, grow: 1.25 * (1 - cool));
        c.restore();
      });
    }
    c.drawPath(s.outline, x.st(_bronzeEdge.withValues(alpha: cool), 2.2));
  }

  void _cracks(CraftContext x, _Mould m, double p) {
    if (p < _knockStart + _blow) return;
    final c = x.c;
    c.save();
    c.clipPath(m.sand);
    for (var k = 0; k < m.cracks.length; k++) {
      final hit = _knockStart + _blow * (1 + k % 3);
      final f = seg(p, hit, hit + 0.02);
      if (f <= 0) continue;
      final pts = m.cracks[k];
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      final upto = f * (pts.length - 1);
      for (var i = 1; i < pts.length; i++) {
        if (i - 1 >= upto) break;
        final q = math.min(1.0, upto - (i - 1));
        final o = Offset.lerp(pts[i - 1], pts[i], q)!;
        path.lineTo(o.dx, o.dy);
      }
      c.drawPath(path, x.st(_crack, 2.2));
    }
    c.restore();
  }

  /// The casting after knock-out: dull, then polished by a sweeping shine.
  void _letter(CraftContext x, double p) {
    final s = x.s, c = x.c, ink = s.ink;
    final pol = seg(p, _polishStart, 0.995);
    if (pol >= 1) {
      paintFinished(x);
      return;
    }
    c.drawPath(s.outline, x.fl(_dull));
    c.drawPath(s.outline, x.st(_bronzeEdge, 2.2));
    if (pol <= 0) return;
    final slant = ink.height * 0.35;
    final sx = lerp(ink.left - slant, ink.right + slant, eio(pol));
    final top = ink.top - 10, bottom = ink.bottom + 10;
    final done = Path()
      ..moveTo(ink.left - 2 * slant - 20, top)
      ..lineTo(sx + slant / 2, top)
      ..lineTo(sx - slant / 2, bottom)
      ..lineTo(ink.left - 2 * slant - 20, bottom)
      ..close();
    c.save();
    c.clipPath(done);
    paintFinished(x);
    c.restore();
    s.clipped(
      c,
      () => c.drawLine(
        Offset(sx + slant / 2, top),
        Offset(sx - slant / 2, bottom),
        x.st(_white.withValues(alpha: 0.85), 7),
      ),
    );
  }

  static final _dust = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);

  /// Knock-out: the sand breaks into chunks that tumble off the letter,
  /// puffing up dust where they land.
  void _crumble(CraftContext x, _Mould m, double p) {
    final c = x.c;
    for (final ch in m.chunks) {
      final u = (p - ch.start) / 0.045;
      if (u > 0.55 && u < 1.6) {
        final k = (u - 0.55) / 1.05;
        _dust.color = _sandLight.withValues(alpha: 0.4 * (1 - k));
        c.drawCircle(Offset(ch.centre.dx + ch.drift, x.floorY - 8 - 10 * k), 8 + 16 * k, _dust);
      }
      if (u >= 1) continue;
      final a = 1 - seg(u, 0.55, 1);
      c.save();
      if (u > 0) {
        c.translate(ch.centre.dx + ch.drift * u, ch.centre.dy + ch.drop * u * u);
        c.rotate(ch.spin * u);
        c.translate(-ch.centre.dx, -ch.centre.dy);
      }
      c.clipPath(ch.path);
      c.drawPath(m.sand, x.fl(_sand.withValues(alpha: a)));
      if (ch.specks.isNotEmpty) {
        c.drawPoints(ui.PointMode.points, ch.specks, x.st(_sandShade.withValues(alpha: a), 2.2));
      }
      c.drawPath(ch.path, x.st(_crack.withValues(alpha: 0.6 * a * seg(u, 0, 0.2)), 1.4));
      c.restore();
    }
  }

  /// The flask: two wooden sides with flanges at the parting line; they
  /// tip outwards and fade at knock-out.
  void _flask(CraftContext x, _Mould m, double p) {
    final c = x.c, box = m.box;
    final off = seg(p, 0.87, 0.93);
    if (off >= 1) return;
    final a = (1 - off) * seg(p, 0, 0.03); // fades in, then out at knock-out
    final mid = box.top + box.height * 0.45;
    for (final side in [-1, 1]) {
      final pivot = Offset(side < 0 ? box.left - 9 : box.right + 9, box.bottom);
      c.save();
      c.translate(pivot.dx, pivot.dy);
      c.rotate(side * 0.35 * ei(off));
      c.translate(-pivot.dx, -pivot.dy);
      final x0 = side < 0 ? box.left - 9 : box.right;
      final board = Rect.fromLTWH(x0, box.top - 6, 9, box.height + 6);
      c.drawRect(board, x.fl(Mat.wood.withValues(alpha: a)));
      final grain = Path();
      for (var i = 0; i < 3; i++) {
        final gx = x0 + 2.5 + i * 2.2;
        grain
          ..moveTo(gx, board.top + 6 + 9 * i)
          ..lineTo(gx, board.bottom - 4 - 13 * i);
      }
      c.drawPath(grain, x.st(Mat.woodDark.withValues(alpha: 0.6 * a), 0.8));
      c.drawRect(board, x.st(Mat.woodDark.withValues(alpha: a), 1.4));
      // Flanges (cope above, drag below) with a pin.
      final fx = side < 0 ? x0 - 7 : x0 + 9;
      for (final fy in [mid - 9, mid + 1]) {
        final f = Rect.fromLTWH(fx, fy, 7, 8);
        c.drawRect(f, x.fl(Mat.woodDark.withValues(alpha: a)));
      }
      c.drawLine(Offset(fx + 3.5, mid - 13), Offset(fx + 3.5, mid + 13), x.st(Mat.steel.withValues(alpha: a), 2));
      c.restore();
    }
    // Parting line between cope and drag.
    if (off <= 0 && p >= _sandEnd) {
      c.drawLine(Offset(box.left, mid), Offset(box.left + 14, mid), x.st(_sandShade, 1.6));
      c.drawLine(Offset(box.right - 14, mid), Offset(box.right, mid), x.st(_sandShade, 1.6));
    }
  }

  // ── Furnace, crucible and pourer ──────────────────────────────────────────

  void _furnace(CraftContext x, _Mould m, double p) {
    final c = x.c;
    final fx = m.furnaceX;
    final body = Rect.fromLTRB(fx - 28, 578, fx + 28, x.floorY);
    final stack = Rect.fromLTRB(fx - 9, 528, fx + 9, body.top);
    x.ink.steam(Offset(fx, stack.top - 4), x.t, per: 0.45, life: 2.2, rise: 58, r: 8, seed: 3);
    c.drawRect(stack, x.fl(_brick));
    c.drawRect(stack, x.st(_brickLine, 1.3));
    c.drawRect(body, x.fl(_brick));
    final joints = Path();
    var row = 0;
    for (var y = body.top + 11; y < body.bottom; y += 11, row++) {
      joints
        ..moveTo(body.left, y)
        ..lineTo(body.right, y);
      for (var bx = body.left + (row.isEven ? 14 : 4); bx < body.right; bx += 20) {
        joints
          ..moveTo(bx, y)
          ..lineTo(bx, y + 11);
      }
    }
    c.drawPath(joints, x.st(_brickLine.withValues(alpha: 0.7), 1));
    c.drawRect(body, x.st(_brickLine, 1.6));
    // The fire in its mouth.
    final flick = 0.7 + 0.3 * math.sin(x.t * 13) * math.sin(x.t * 7.3 + 1);
    final mouth = Rect.fromLTRB(fx - 15, body.bottom - 42, fx + 15, body.bottom - 12);
    x.glow(mouth.center, 30, Mat.molten, alpha: 0.32 * flick);
    c.drawRRect(
      RRect.fromRectAndCorners(
        mouth,
        topLeft: const Radius.circular(15),
        topRight: const Radius.circular(15),
      ),
      x.fl(Color.lerp(_orange, Mat.molten, flick)!),
    );
    final flame = Path();
    for (var i = 0; i < 3; i++) {
      final cx = mouth.left + 7 + i * 8;
      final h = 10 + 6 * math.sin(x.t * (9 + i) + i);
      flame
        ..moveTo(cx - 5, mouth.bottom)
        ..quadraticBezierTo(cx, mouth.bottom - h * 1.6, cx + 5, mouth.bottom)
        ..close();
    }
    c.drawPath(flame, x.fl(_white.withValues(alpha: 0.85)));
    // Launder: a trough from the tap hole down to the crucible's low spot.
    final tapEnd = m.launderEnd;
    final tapStart = Offset(body.left, 600);
    c.drawLine(tapStart, tapEnd, x.st(_iron, 8));
    c.drawLine(tapStart, tapEnd, x.st(BP.inkDim, 1.2));
    final tapping = p >= _tapStart && p < _tapEnd;
    if (tapping) {
      c.drawLine(tapStart + const Offset(0, -2), tapEnd + const Offset(0, -2), x.st(Mat.molten, 3.2));
      final into = Offset(tapEnd.dx, m.pivotLow.dy - 12);
      c.drawLine(tapEnd, into, x.st(Mat.molten, 4.5));
      c.drawLine(tapEnd, into, x.st(_white, 1.6));
      x.glow(into, 16, Mat.molten, alpha: 0.5);
      x.sparks(into, n: 6, size: 0.5, salt: 11);
    }
  }

  /// The crucible tipped [angle] towards the mould (left) around its middle
  /// [pivot], holding [fill] of metal.
  void _crucible(CraftContext x, Offset pivot, double angle, double fill) {
    final c = x.c;
    c.save();
    c.translate(pivot.dx, pivot.dy);
    c.rotate(-angle);
    c.scale(_cs);
    final body = Path()
      ..moveTo(-14, -12)
      ..lineTo(14, -12)
      ..lineTo(10, 12)
      ..lineTo(-10, 12)
      ..close();
    c.drawPath(body, x.fl(_iron));
    if (fill > 0.02 && angle < 0.25) {
      final y = 11 - 21 * fill;
      final hw = 10 + 4 * (12 - y) / 24;
      final metal = Path()
        ..moveTo(-hw + 1.5, y)
        ..lineTo(hw - 1.5, y)
        ..lineTo(8.5, 10.5)
        ..lineTo(-8.5, 10.5)
        ..close();
      c.drawPath(metal, x.fl(Mat.molten));
      c.drawLine(Offset(-hw + 2, y), Offset(hw - 2, y), x.st(_white, 2));
    }
    c.drawPath(body, x.st(BP.inkDim, 1.6));
    c.drawLine(const Offset(-16, -12), const Offset(15, -12), x.st(BP.ink, 2.4));
    c.drawLine(const Offset(-12.5, 0), const Offset(12.5, 0), x.st(Mat.steelDark, 3.2));
    c.restore();
    if (fill > 0.02) x.glow(pivot + _rot(const Offset(0, -12 * _cs), -angle), 16, Mat.molten, alpha: 0.45);
  }

  void _pourer(CraftContext x, _Mould m, double p) {
    final c = x.c;
    final up = eio(seg(p, _riseStart, _riseEnd)) - eio(seg(p, _lowerStart, _lowerEnd));
    final pivot = Offset.lerp(m.pivotLow, m.pivotPour, up)!;
    final angle =
        _pourAngle * eio(seg(p, 0.29, 0.33)) +
        0.32 * seg(p, 0.33, _pourEnd) -
        (_pourAngle + 0.32) * eio(seg(p, _pourEnd, 0.65));
    final fill = seg(p, _tapStart + 0.01, _tapEnd) - seg(p, _pourStart, _pourEnd);
    final platform = pivot.dy + 47;
    x.lift(m.liftX, platform, w: 50);
    // The stream from the lip into the pouring cup.
    final pouring = p > _pourStart - 0.005 && p < _pourEnd;
    if (pouring) {
      final lip = pivot + _rot(_lip, -angle);
      final cup = Offset(m.sprueX, m.box.top + 12);
      final wob = 1.5 * math.sin(x.t * 23);
      final stream = Path()
        ..moveTo(lip.dx, lip.dy)
        ..quadraticBezierTo(lip.dx - 3 + wob, (lip.dy + cup.dy) / 2, cup.dx, cup.dy);
      x.glow(cup, 22, Mat.molten, alpha: 0.6);
      c.drawPath(stream, x.st(Mat.molten, 6));
      c.drawPath(stream, x.st(_white, 2.2));
      x.sparks(Offset(cup.dx, m.box.top), n: 7, size: 0.55, salt: 5);
    }
    _crucible(x, pivot, angle, fill);
    final hands = pivot + const Offset(_shank, 0);
    final limbs = x.reach(Offset(m.liftX, platform - 4), hands, both: true, dir: -1, hat: BP.amber);
    // Shank from the hands to the crucible's ring, with a cross handle.
    c.drawLine(limbs.handA + const Offset(7, 0), pivot, x.st(Mat.steelDark, 3));
    c.drawLine(limbs.handA + const Offset(7, -6), limbs.handA + const Offset(7, 6), x.st(Mat.steelDark, 2.6));
    // Face shield while the metal is out.
    if (fill > 0.02 || pouring) {
      final face = limbs.head + const Offset(-4, 0);
      c.drawRect(Rect.fromCenter(center: face, width: 8, height: 10), x.fl(_visor));
    }
    if (p > _lowerEnd && p < 0.86) x.ink.sweat(limbs.head, x.t, -1);
  }

  /// The helper on the left: shovels sand in, waits with a coffee, then
  /// knocks the mould open with a sledgehammer.
  void _helper(CraftContext x, _Mould m, double p) {
    final c = x.c, box = m.box;
    final feet = Offset(math.max(774.0, box.left - 30), x.floorY);
    if (p < _sandEnd + 0.02) {
      final k = 0.5 + 0.5 * math.sin(x.t * 4.4);
      final pose = Pose()
        ..upA = lerp(0.75, 2.2, k)
        ..foA = lerp(1.25, 2.5, k)
        ..upB = lerp(0.95, 2.0, k)
        ..foB = lerp(1.35, 2.4, k)
        ..lean = lerp(0.4, -0.05, k)
        ..drop = lerp(0.07, 0, k);
      final l = x.worker(feet, dir: 1, pose: pose, hat: BP.coral);
      x.ink.shovel(l.elbowA, l.handA, 12);
      if (p < _sandEnd) {
        // A spray of sand arcing into the flask.
        final from = l.handA + const Offset(14, -8);
        final level = lerp(box.bottom, box.top, eo(seg(p, 0, _sandEnd)));
        final to = Offset(box.left + math.min(60, box.width * 0.25), level - 6);
        final h = 40 + (from.dy - to.dy) * 0.25;
        final grains = <Offset>[];
        for (var i = 0; i < 18; i++) {
          final u = (x.t * 1.3 + i / 18) % 1;
          final y = lerp(from.dy, to.dy, u) - 4 * h * u * (1 - u);
          grains.add(Offset(lerp(from.dx, to.dx, u) + 4 * (rnd(i, 3) - 0.5), y));
        }
        c.drawPoints(ui.PointMode.points, grains, x.st(_sand, 3.2));
      }
      return;
    }
    if (p < _knockStart) {
      final pose = Pose()..upA = 1.5;
      final l = x.worker(feet, dir: 1, pose: pose, hat: BP.coral);
      x.ink.coffee(l.handA, x.t);
      return;
    }
    if (p < _crumbleStart) {
      // Three blows with a sledgehammer at the flask.
      final u = ((p - _knockStart) / _blow) % 1;
      final a = lerp(3.0, 1.45, ei(u));
      final pose = Pose()
        ..upA = a
        ..foA = a + 0.12
        ..upB = a - 0.1
        ..foB = a + 0.02
        ..lean = 0.1;
      final hf = Offset(box.left - 27, x.floorY);
      final l = x.worker(hf, dir: 1, pose: pose, hat: BP.coral);
      final d = l.handA - l.elbowA;
      final u2 = d / math.max(1, d.distance);
      final head = l.handA + u2 * 17;
      c.drawLine(l.handA - u2 * 3, head, x.st(Mat.wood, 2.4));
      final n = Offset(-u2.dy, u2.dx);
      c.drawLine(head - n * 6, head + n * 6, x.st(Mat.steelDark, 6));
      if (u > 0.9 || u < 0.08) x.ink.star(Offset(box.left - 6, l.handA.dy), 8, BP.amber);
      return;
    }
    final pose = Pose()..cheer(x.t, 1);
    x.worker(feet, dir: 1, pose: pose, hat: BP.coral);
  }

  /// Steam off the cooling mould.
  void _steam(CraftContext x, _Mould m, double p) {
    if (p < _pourEnd - 0.02 || p > _crumbleStart + 0.02) return;
    final a = math.min(seg(p, _pourEnd - 0.02, _pourEnd + 0.04), 1 - seg(p, 0.84, _crumbleStart + 0.02));
    final col = BP.inkDim.withValues(alpha: 0.9 * a);
    final box = m.box;
    for (var i = 0; i < 3; i++) {
      final vx = i == 2 ? m.sprueX : box.left + box.width * (0.22 + 0.3 * i);
      x.ink.steam(Offset(vx, box.top - 2), x.t + i * 0.37, per: 0.5, life: 1.8, rise: 26, r: 6, col: col, seed: 17 + i);
    }
  }

  /// Sand still trickling off the letter right after knock-out.
  void _grains(CraftContext x, _Mould m, double p) {
    if (p < 0.9 || p >= 0.995) return;
    final pts = <Offset>[];
    for (var i = 0; i < m.tops.length; i++) {
      final t0 = 0.9 + 0.07 * rnd(i, x.seed, 21);
      final u = (p - t0) / 0.03;
      if (u <= 0 || u >= 1) continue;
      final o = m.tops[i];
      pts.add(Offset(o.dx + 3 * (rnd(i, 4) - 0.5), o.dy + 60 * u * u));
    }
    if (pts.isNotEmpty) x.c.drawPoints(ui.PointMode.points, pts, x.st(_sand, 3));
  }
}

const _pourAngle = 1.75;

/// Crucible scale, its pouring lip (local, at that scale) and the shank's
/// length to the worker's hands.
const _cs = 1.25;
const _lip = Offset(-14 * _cs, -12 * _cs);
const _shank = 34.0;

Offset _rot(Offset v, double a) {
  final cs = math.cos(a), sn = math.sin(a);
  return Offset(v.dx * cs - v.dy * sn, v.dx * sn + v.dy * cs);
}

// Materials.
const _sand = Color(0xFFC9B088);
const _sandShade = Color(0xFF9E855F);
const _sandLight = Color(0xFFE6D5B0);
const _cavity = Color(0xFF060E1A);
const _crack = Color(0xFF6E5A3E);
const _white = Color(0xFFFFF4C8);
const _core = Color(0xFFFFD873);
const _orange = Color(0xFFFF8E36);
const _red = Color(0xFFC4462A);
const _dull = Color(0xFF86603F);
const _bronzeHi = Color(0xFFF0C88E);
const _bronzeMid = Color(0xFFC48748);
const _bronzeLo = Color(0xFF9A6534);
const _bronzeEdge = Color(0xFF6E4524);
const _sheen = Color(0xFFFFE6BE);
const _iron = Color(0xFF3B4250);
const _visor = Color(0xFF1F3B3A);
const _brick = Color(0xFF4A2F28);
const _brickLine = Color(0xFFB8735A);

/// Everything derived from the glyph for one casting.
class _Mould {
  _Mould(GlyphStage s, int seed, double daisY, double floorY) {
    final ink = s.ink;
    final rng = math.Random(seed);
    final inside = _Inside(s);
    final m = (ink.height * 0.06).clamp(10.0, 16.0);
    sprueX = ink.right + m + 9;
    box = Rect.fromLTRB(ink.left - m, ink.top - m, sprueX + 15, daisY);

    // Runner: from the sprue into the lowest, right-most part of the glyph.
    final low = ink.bottom - math.max(6.0, ink.height * 0.05);
    Rect? target;
    for (final r in s.rows) {
      if (r.bottom >= low && (target == null || r.right > target.right)) target = r;
    }
    final ry = math.min(target?.center.dy ?? ink.bottom - 6, box.bottom - 6);
    final rx = (target?.right ?? ink.right) - 3;
    gates = Path()
      ..addPolygon([
        Offset(sprueX - 13, box.top - 0.5),
        Offset(sprueX + 13, box.top - 0.5),
        Offset(sprueX + 4, box.top + 13),
        Offset(sprueX - 4, box.top + 13),
      ], true)
      ..addRect(Rect.fromLTRB(sprueX - 4, box.top + 10, sprueX + 4, ry + 4))
      ..addRect(Rect.fromLTRB(rx, ry - 4, sprueX + 4, ry + 4));
    sand = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(box)
      ..addPath(s.outline, Offset.zero);

    // Crucible positions: over the pouring cup, and low by the furnace.
    pivotPour = Offset(sprueX + 2, box.top - 4) - _rot(_lip, -_pourAngle);
    liftX = pivotPour.dx + _shank + 14;
    pivotLow = Offset(pivotPour.dx, floorY - 18 - 47);
    furnaceX = math.max(1440.0, liftX + 64);
    launderEnd = Offset(pivotLow.dx + 2, pivotLow.dy - 27);

    // Fill table: rows bottom-up with their inside width.
    final widths = <double, double>{};
    for (final r in s.rows) {
      widths[r.top] = (widths[r.top] ?? 0) + r.width;
    }
    _tops = widths.keys.toList()..sort((a, b) => b.compareTo(a));
    _widths = [for (final y in _tops) widths[y]!];
    _total = _widths.fold(0.0, (a, b) => a + b);
    _rowH = s.k;
    _ink = ink;

    // Chunks of sand for the knock-out (a jittered grid).
    final nx = math.max(3, (box.width / 72).round());
    final ny = math.max(3, (box.height / 72).round());
    final v = <Offset>[];
    for (var j = 0; j <= ny; j++) {
      for (var i = 0; i <= nx; i++) {
        var px = box.left + box.width * i / nx;
        var py = box.top + box.height * j / ny;
        if (i > 0 && i < nx) px += (rng.nextDouble() - 0.5) * box.width / nx * 0.5;
        if (j > 0 && j < ny) py += (rng.nextDouble() - 0.5) * box.height / ny * 0.5;
        v.add(Offset(px, py));
      }
    }
    for (var j = 0; j < ny; j++) {
      for (var i = 0; i < nx; i++) {
        final q = [
          v[j * (nx + 1) + i],
          v[j * (nx + 1) + i + 1],
          v[(j + 1) * (nx + 1) + i + 1],
          v[(j + 1) * (nx + 1) + i],
        ];
        final centre = (q[0] + q[1] + q[2] + q[3]) / 4;
        chunks.add(
          _Chunk(
            Path()..addPolygon(q, true),
            centre,
            start: 0.875 + 0.05 * (0.6 * j / ny + 0.4 * rng.nextDouble()),
            drop: floorY + 14 - centre.dy,
            drift: (centre.dx < ink.center.dx ? -1 : 1) * (8 + 26 * rng.nextDouble()),
            spin: (rng.nextDouble() - 0.5) * 1.4,
          ),
        );
      }
    }

    // Sand speckles (outside the cavity), each also listed in its chunk.
    final n = (box.width * box.height / 420).round().clamp(80, 420);
    final perChunk = [for (final _ in chunks) <Offset>[]];
    for (var i = 0; i < n; i++) {
      final pt = Offset(
        box.left + rng.nextDouble() * box.width,
        box.top + rng.nextDouble() * box.height,
      );
      if (inside(pt) || gates.contains(pt)) continue;
      (i.isEven ? speckDark : speckLight).add(pt);
      for (var k = 0; k < chunks.length; k++) {
        if (chunks[k].path.contains(pt)) {
          perChunk[k].add(pt);
          break;
        }
      }
    }
    for (var k = 0; k < chunks.length; k++) {
      chunks[k].specks = perChunk[k];
    }

    // Cracks from the hammer's blows on the left of the flask.
    final hit = Offset(box.left, floorY - 38);
    for (var k = 0; k < 5; k++) {
      final pts = [hit];
      var a = -0.75 + 1.2 * k / 4 + (rng.nextDouble() - 0.5) * 0.3;
      final reach = box.width * (0.45 + 0.4 * rng.nextDouble());
      var len = 0.0;
      while (len < reach) {
        a += (rng.nextDouble() - 0.5) * 0.9;
        a = a.clamp(-1.3, 0.9);
        final step = 12 + 10 * rng.nextDouble();
        final next = pts.last + Offset(math.cos(a), math.sin(a)) * step;
        if (!box.deflate(2).contains(next)) break;
        pts.add(next);
        len += step;
      }
      if (pts.length > 1) cracks.add(pts);
    }

    // Spots on the letter's upper edges for trickling sand.
    final rows = s.rows;
    for (var i = 0; i < 40 && tops.length < 14 && rows.isNotEmpty; i++) {
      final r = rows[rng.nextInt(rows.length)];
      final pt = Offset(r.left + rng.nextDouble() * r.width, r.top);
      if (!inside(pt - const Offset(0, 4))) tops.add(pt);
    }
  }

  late final Rect box;
  late final double sprueX;

  /// Pouring cup, sprue and runner (one path).
  late final Path gates;

  /// The sand: the box minus the cavity (even-odd).
  late final Path sand;

  late final Offset pivotPour;
  late final Offset pivotLow;
  late final double liftX;
  late final double furnaceX;
  late final Offset launderEnd;

  final speckDark = <Offset>[];
  final speckLight = <Offset>[];
  final chunks = <_Chunk>[];
  final cracks = <List<Offset>>[];
  final tops = <Offset>[];

  late final List<double> _tops;
  late final List<double> _widths;
  late final double _total;
  late final double _rowH;
  late final Rect _ink;

  /// The metal's level when [f] of the cavity is full: by volume (so it
  /// speeds up through thin parts), softened towards a steady rise.
  double levelAt(double f) {
    final lin = _ink.bottom - _ink.height * f;
    if (_total <= 0) return lin;
    final target = f * _total;
    var acc = 0.0;
    var y = _ink.top;
    for (var i = 0; i < _tops.length; i++) {
      final w = _widths[i];
      if (acc + w >= target) {
        final frac = w <= 0 ? 0.0 : (target - acc) / w;
        y = _tops[i] + _rowH * (1 - frac);
        break;
      }
      acc += w;
    }
    return lerp(y, lin, 0.35);
  }
}

/// Raster-row lookup: is a canvas point inside the glyph?
class _Inside {
  _Inside(GlyphStage s) : _k = s.k, _o = s.origin {
    for (final sp in s.geo.spans) {
      (_rows[sp.y] ??= <Span>[]).add(sp);
    }
  }

  final double _k;
  final Offset _o;
  final _rows = <int, List<Span>>{};

  bool call(Offset p) {
    final row = _rows[((p.dy - _o.dy) / _k).floor()];
    if (row == null) return false;
    final rx = (p.dx - _o.dx) / _k;
    for (final sp in row) {
      if (rx >= sp.x0 && rx < sp.x1) return true;
    }
    return false;
  }
}

class _Chunk {
  _Chunk(
    this.path,
    this.centre, {
    required this.start,
    required this.drop,
    required this.drift,
    required this.spin,
  });

  final Path path;
  final Offset centre;
  final double start;
  final double drop;
  final double drift;
  final double spin;
  List<Offset> specks = const [];
}
