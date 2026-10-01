import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../../../worlds/factory/factory_kit.dart';
import '../geometry.dart';
import '../method.dart';
import '../stage.dart';

/// コンクリート · Concrete pour: carpenters on lifts nail wooden formwork
/// along the letter's outlines, from the bottom up. A pump truck slides its
/// boom over and pours grey concrete that fills the form from the bottom,
/// heaping under the stream, while a worker shakes the bubbles out with a
/// vibrator poker. The concrete cures lighter and the formwork is stripped
/// board by board, leaving a concrete letter with board marks and pores.
class ConcreteCraft extends CraftMethod {
  const ConcreteCraft();

  @override
  String get id => 'concrete';

  @override
  String get en => 'Concrete pour';

  @override
  String get ja => 'コンクリート';

  @override
  Color get color => Mat.concrete;

  @override
  double get weight => 1.0;

  static final _forms = Expando<_Form>();
  static final _faces = Expando<_Face>();

  static _Form _form(CraftContext x) => _forms[x.s] ??= _Form(x.s, x.seed);
  static _Face _face(GlyphStage s, int seed) => _faces[s] ??= _Face(s, seed);

  // Timeline (fractions of p).
  static const _boardsStart = 0.02, _boardsEnd = 0.3;
  static const _boomOut = 0.3, _boomIn = 0.72;
  static const _pourStart = 0.35, _pourEnd = 0.71;
  static const _stripStart = 0.79, _stripEnd = 0.96;
  static const _cureStart = 0.7, _cureEnd = 0.98;

  /// How long (p) a stripped board takes to fall.
  static const _drop = 0.045;

  @override
  void paintMaking(CraftContext x, double p) {
    final s = x.s;
    if (s.contours.isEmpty) return;
    final f = _form(x);
    p = p.clamp(0.0, 1.0);

    // The pump truck fades in, and away again as the job wraps up.
    final show = seg(p, 0, 0.03) * (1 - seg(p, 0.93, 0.995));
    if (show > 0) {
      if (show < 1) {
        x.c.saveLayer(
          Rect.fromLTRB(_mastX - 20, _boomY - 10, 1480, x.floorY + 2),
          Paint()..color = Color.fromRGBO(0, 0, 0, show),
        );
      }
      _truck(x, p);
      if (show < 1) x.c.restore();
    }
    // Concrete in the form.
    if (p >= _pourEnd) {
      _concrete(x, seg(p, _cureStart, _cureEnd));
    } else if (p > _pourStart) {
      _pour(x, f, p);
    }
    _boards(x, f, p);
    _boom(x, f, p);
    _crew(x, f, p);
  }

  @override
  void paintFinished(CraftContext x) {
    if (x.s.contours.isEmpty) return;
    _concrete(x, 1);
  }

  /// The letter in concrete, from wet and dark ([cure] 0) to dry with its
  /// board marks and pores showing ([cure] 1).
  void _concrete(CraftContext x, double cure) {
    final s = x.s, c = x.c;
    final face = _face(s, x.seed);
    c.drawPath(s.outline, x.fl(Color.lerp(_wet, Mat.concrete, cure)!));
    if (cure > 0.15) {
      final a = seg(cure, 0.15, 0.8);
      c.drawPath(face.marks, x.st(_markDark.withValues(alpha: a), 2));
      c.drawPath(face.marksLight, x.st(_markLight.withValues(alpha: a * 0.8), 1.2));
      c.drawPoints(ui.PointMode.points, face.pores, x.st(_pore.withValues(alpha: a), 2.4));
      c.drawPoints(ui.PointMode.points, face.flecks, x.st(_fleck.withValues(alpha: a), 1.8));
    }
    c.drawPath(s.outline, x.st(Color.lerp(_wetEdge, _edge, cure)!, 1.8));
  }

  double _level(_Form f, double p) => f.levelAt(eio(seg(p, _pourStart, _pourEnd)));

  /// Pouring: wet concrete up to the level, a lumpy surface heaped under
  /// the stream, and bubbles.
  void _pour(CraftContext x, _Form f, double p) {
    final s = x.s, c = x.c, ink = s.ink;
    final y = _level(f, p);
    final sx = _nozzleX(x);
    final surface = Path();
    final body = Path()..moveTo(ink.left - 6, ink.bottom + 4);
    for (var px = ink.left - 6; px <= ink.right + 6; px += 5) {
      final d = (px - sx) / 22;
      final wy =
          y +
          2.5 * math.sin(px * 0.09 + x.seed) +
          1.6 * math.sin(px * 0.21 + x.t * 0.8) -
          12 * math.exp(-d * d);
      body.lineTo(px, wy);
      px == ink.left - 6 ? surface.moveTo(px, wy) : surface.lineTo(px, wy);
    }
    body
      ..lineTo(ink.right + 6, ink.bottom + 4)
      ..close();
    s.clipped(c, () {
      c.drawPath(body, x.fl(_wet));
      c.drawPath(surface, x.st(_wetTop, 2.6));
      // Bubbles rising and popping at the surface (more by the poker).
      final poker = f.pokerX(y);
      for (var i = 0; i < 16; i++) {
        final cyc = x.t * 1.4 + rnd(i, 3);
        final n = cyc.floor();
        final u = cyc - n;
        final bx = i < 6 ? poker + (rnd(n, i, 5) - 0.5) * 34 : lerp(ink.left, ink.right, rnd(n, i, 7));
        if (!f.inside(Offset(bx, y + 6))) continue;
        if (u < 0.8) {
          c.drawCircle(Offset(bx, y + 18 - 15 * u), 1.5 + 2.8 * u, x.st(_wetTop, 1.3));
        } else {
          final k = (u - 0.8) * 5;
          c.drawCircle(Offset(bx, y), 3 + 10 * k, x.st(_wetTop.withValues(alpha: 1 - k), 1.2));
        }
      }
    });
  }

  void _boards(CraftContext x, _Form f, double p) {
    final c = x.c;
    final placed = Path();
    final nails = <Offset>[];
    for (final b in f.boards) {
      if (p < b.place - 0.012) continue;
      final strip = (p - b.strip) / _drop;
      if (strip >= 1) continue;
      if (p < b.place || strip > 0) {
        // Dropping into place, or falling off.
        c.save();
        if (p < b.place) {
          c.translate(0, -26 * (1 - eo(seg(p, b.place - 0.012, b.place))));
        } else {
          // Falls outwards and lands on the floor (never below it).
          final fall = math.min(170 * strip * strip, x.floorY - 6 - b.centre.dy);
          c.translate(b.centre.dx + b.out.dx * 16 * strip, b.centre.dy + fall);
          c.rotate(b.spin * strip);
          c.translate(-b.centre.dx, -b.centre.dy);
        }
        final a = strip > 0 ? 1 - seg(strip, 0.6, 1) : 1.0;
        c.drawPath(b.path, x.fl(Mat.wood.withValues(alpha: a)));
        c.drawPath(b.path, x.st(Mat.woodDark.withValues(alpha: a), 1));
        c.restore();
        continue;
      }
      placed.addPath(b.path, Offset.zero);
      nails
        ..add(b.nail0)
        ..add(b.nail1);
    }
    c.drawPath(placed, x.fl(Mat.wood));
    c.drawPath(placed, x.st(Mat.woodDark, 1));
    c.drawPoints(ui.PointMode.points, nails, x.st(BP.inkFaint, 2));
  }

  // ── The pump truck ────────────────────────────────────────────────────────

  static const _mastX = 1372.0;
  static const _boomY = 318.0;

  /// The hose sweeps slowly back and forth over the letter.
  double _nozzleX(CraftContext x) {
    final ink = x.s.ink;
    return lerp(ink.left + ink.width * 0.12, ink.right - ink.width * 0.12, 0.5 + 0.5 * math.sin(x.t * 1.3));
  }

  void _truck(CraftContext x, double p) {
    final c = x.c;
    final floor = x.floorY;
    // Mast (behind the truck), a yellow lattice.
    final mast = Rect.fromLTRB(_mastX - 5, _boomY, _mastX + 5, floor - 30);
    final lattice = Path();
    for (var y = mast.top; y < mast.bottom - 6; y += 14) {
      lattice
        ..moveTo(mast.left, y)
        ..lineTo(mast.right, y + 7)
        ..lineTo(mast.left, y + 14);
    }
    c.drawPath(lattice, x.st(BP.amber.withValues(alpha: 0.7), 1));
    c.drawLine(mast.topLeft, mast.bottomLeft, x.st(BP.amber, 2));
    c.drawLine(mast.topRight, mast.bottomRight, x.st(BP.amber, 2));
    // Chassis, cab, drum.
    final chassis = Rect.fromLTRB(1360, floor - 34, 1472, floor - 16);
    x.ink.box(chassis, col: BP.lineDim);
    final cab = Rect.fromLTRB(1442, floor - 72, 1472, floor - 34);
    x.ink.box(cab, col: BP.amber);
    c.drawRect(Rect.fromLTRB(cab.left + 6, cab.top + 6, cab.right - 4, cab.top + 20), x.fl(BP.lineFaint));
    final drum = Rect.fromLTRB(1380, floor - 78, 1438, floor - 36);
    final shape = Rect.fromCenter(center: Offset.zero, width: drum.width, height: drum.height);
    c.save();
    c.translate(drum.center.dx, drum.center.dy);
    c.rotate(-0.18);
    c.drawOval(shape, x.fl(_drum));
    c.save();
    c.clipPath(Path()..addOval(shape));
    final turning = p > _boomOut && p < _pourEnd + 0.02;
    final ph = (turning ? x.t * 1.6 : 0.4) % 1;
    final stripes = Path();
    for (var i = -3; i <= 3; i++) {
      final sx = (i + ph) * 16;
      stripes
        ..moveTo(sx - 10, -shape.height / 2)
        ..lineTo(sx + 10, shape.height / 2);
    }
    c.drawPath(stripes, x.st(BP.amber.withValues(alpha: 0.75), 4));
    c.restore();
    c.drawOval(shape, x.st(BP.line, 1.4));
    c.restore();
    // Wheels.
    for (final wx in [1378.0, 1408.0, 1456.0]) {
      final w = Offset(wx, floor - 10);
      c.drawCircle(w, 9.5, x.fl(BP.paper));
      c.drawCircle(w, 9.5, x.st(BP.line, 1.6));
      c.drawCircle(w, 3, x.fl(BP.lineDim));
    }
  }

  /// The boom slides out over the form, pours, and slides back.
  void _boom(CraftContext x, _Form f, double p) {
    final c = x.c;
    final out = eio(seg(p, _boomOut, _pourStart - 0.01)) * (1 - eio(seg(p, _boomIn, _boomIn + 0.04)));
    if (out <= 0) return;
    final end = lerp(_mastX, _nozzleX(x), out);
    final boom = Rect.fromLTRB(end - 4, _boomY - 4, _mastX + 4, _boomY + 5);
    c.drawRect(boom, x.fl(BP.panel));
    c.drawRect(boom, x.st(BP.amber, 1.6));
    final tick = Path();
    for (var bx = end + 6; bx < _mastX - 4; bx += 18) {
      tick
        ..moveTo(bx, boom.top)
        ..lineTo(bx + 9, boom.bottom);
    }
    c.drawPath(tick, x.st(BP.amber.withValues(alpha: 0.6), 1));
    // Hose dropping from the boom's tip, and the stream.
    final nozzle = Offset(end, _boomY + 26);
    c.drawLine(Offset(end, boom.bottom), nozzle, x.st(_hose, 5));
    c.drawLine(nozzle, nozzle + const Offset(0, 7), x.st(BP.inkDim, 8));
    if (p > _pourStart && p < _pourEnd && out > 0.98) {
      final land = f.landing(nozzle.dx, _level(f, p) - 10);
      final top = nozzle + const Offset(0, 7);
      final stream = Path()..moveTo(top.dx - 4, top.dy);
      for (var y = top.dy; y < land; y += 12) {
        stream.lineTo(top.dx - 4.5 + 1.6 * math.sin(y * 0.3 + x.t * 20), y);
      }
      stream.lineTo(top.dx - 5, land);
      for (var y = land; y > top.dy; y -= 12) {
        stream.lineTo(top.dx + 4.5 + 1.6 * math.sin(y * 0.27 - x.t * 18), y);
      }
      stream
        ..lineTo(top.dx + 4, top.dy)
        ..close();
      c.drawPath(stream, x.fl(_stream));
      c.drawPath(stream, x.st(_wetEdge, 1.2));
      // Lumps in the stream, and the splash.
      final frame = (x.t * 12).floor();
      for (var i = 0; i < 6; i++) {
        final y = lerp(top.dy, land, (x.t * 2.2 + i / 6) % 1);
        c.drawCircle(Offset(top.dx + (rnd(i, 4) - 0.5) * 4, y), 2.2, x.fl(_wetTop));
      }
      for (var i = 0; i < 6; i++) {
        final a = -math.pi * (0.1 + 0.8 * rnd(frame, i));
        final r = 7 + 9 * rnd(i, frame, 2);
        c.drawCircle(Offset(top.dx, land) + Offset(math.cos(a), math.sin(a)) * r, 2, x.fl(_wetTop));
      }
    }
  }

  // ── The crew ──────────────────────────────────────────────────────────────

  void _crew(CraftContext x, _Form f, double p) {
    final leftX = f.box.left - 30, rightX = f.box.right + 28;
    if (p < _boardsEnd + 0.02) {
      // Nailing the formwork at the height it has reached.
      final y = f.frontAt(p);
      _carpenter(x, 0, leftX, x.liftFor(y), y, hammer: true);
      _carpenter(x, 1, rightX, x.liftFor(y), y, hammer: true);
      return;
    }
    if (p < _stripStart - 0.04) {
      _vibrator(x, f, leftX, p);
      _operator(x, rightX, p);
      return;
    }
    if (p < _stripEnd + 0.01) {
      // Prying the boards off from the top down; the right-hand lift rises
      // to join in.
      final y = f.stripFrontAt(p);
      final join = eio(seg(p, _stripStart - 0.04, _stripStart));
      final topY = x.liftFor(y);
      _carpenter(x, 0, leftX, topY, y);
      _carpenter(x, 1, rightX, lerp(x.floorY - 18, topY, join), y);
      return;
    }
    // Done.
    for (var side = 0; side < 2; side++) {
      final pose = Pose()..cheer(x.t, side);
      x.worker(
        Offset(side == 0 ? leftX : rightX, x.floorY),
        dir: side == 0 ? 1 : -1,
        pose: pose,
        hat: side == 0 ? BP.amber : BP.coral,
      );
    }
  }

  /// A carpenter on a lift at [lx] working the formwork at height [y]:
  /// hammering nails, or prying boards off with a crowbar.
  void _carpenter(CraftContext x, int side, double lx, double platform, double y, {bool hammer = false}) {
    final c = x.c;
    final dir = side == 0 ? 1 : -1;
    x.lift(lx, platform, w: 46);
    final feet = Offset(lx, platform - 4);
    final target = Offset(lx + dir * 26.0, math.min(y, feet.dy - 20));
    final v = target - (feet + const Offset(0, -39));
    final a = math.atan2(v.dx * dir, v.dy).clamp(-0.3, 3.0);
    final pose = Pose()
      ..upB = a
      ..foB = a + 0.1;
    if (hammer) {
      final sw = 0.5 + 0.5 * math.sin(x.t * 11 + side * 2);
      pose
        ..upA = a + 1.2 - sw
        ..foA = a + 1.7 - 1.2 * sw;
    } else {
      pose
        ..upA = a + 0.15
        ..foA = a + 0.3 + 0.25 * math.sin(x.t * 7 + side);
    }
    final l = x.ink.worker(feet, 50, dir, pose, hat: side == 0 ? BP.amber : BP.coral);
    if (hammer) {
      // A claw hammer.
      final d = l.handA - l.elbowA;
      final u = d / math.max(1, d.distance);
      final head = l.handA + u * 11;
      c.drawLine(l.handA - u * 2, head, x.st(Mat.wood, 2.4));
      final n = Offset(-u.dy, u.dx);
      c.drawLine(head - n * 4, head + n * 6, x.st(Mat.steelDark, 4.5));
      c.drawLine(head - n * 4, head - n * 6 - u * 3, x.st(Mat.steelDark, 2.2));
    } else {
      final d = l.handA - l.elbowA;
      final u = d / math.max(1, d.distance);
      c.drawLine(l.handA - u * 4, l.handA + u * 16, x.st(_bar, 2.4));
    }
  }

  /// The left worker rides the rising level with the vibrator poker.
  void _vibrator(CraftContext x, _Form f, double leftX, double p) {
    final c = x.c;
    final level = p <= _pourStart ? x.s.ink.bottom - 10 : _level(f, p);
    final active = p > _pourStart && p < _pourEnd;
    final shake = active ? 1.6 * math.sin(x.t * 60) : 0.0;
    final head = Offset(f.pokerX(level) + shake, level + 14);
    final platform = x.liftFor(level - 18);
    x.lift(leftX, platform, w: 46);
    final l = x.reach(Offset(leftX, platform - 4), head + const Offset(-12, -34), both: true, dir: 1);
    final hose = Path()
      ..moveTo(l.handA.dx, l.handA.dy)
      ..quadraticBezierTo(head.dx - 6, l.handA.dy - 8, head.dx, head.dy - 16);
    c.drawPath(hose, x.st(_hose, 3));
    final poker = Rect.fromCenter(center: head + const Offset(0, -5), width: 6, height: 18);
    c.drawRect(poker, x.fl(Mat.steel));
    c.drawRect(poker, x.st(Mat.steelDark, 1));
    if (active) {
      for (var i = 0; i < 3; i++) {
        final o = Offset(_alt(i) * 7.0, -14 - 4.0 * i);
        c.drawLine(head + o, head + o + Offset(_alt(i) * 4.0, -2), x.st(BP.ink, 1.2));
      }
    }
  }

  static int _alt(int i) => i.isEven ? -1 : 1;

  /// The right worker on the floor with the pump's remote control.
  void _operator(CraftContext x, double rightX, double p) {
    final c = x.c;
    final op = x.worker(Offset(rightX + 4, x.floorY), dir: 1, pose: Pose()..carry(), hat: BP.coral);
    final box = Rect.fromCenter(center: op.handA + const Offset(3, -2), width: 10, height: 8);
    c.drawRect(box, x.fl(BP.panel));
    c.drawRect(box, x.st(BP.amber, 1.2));
    final on = p > _boomOut && p < _pourEnd && (x.t * 2).floor().isEven;
    x.ink.lamp(box.center + const Offset(0, -7), BP.green, on, 2.2);
  }
}

// Concrete and site colours.
const _wet = Color(0xFF6C747B);
const _wetTop = Color(0xFF9AA3AA);
const _stream = Color(0xFF858D94);
const _wetEdge = Color(0xFF4F565C);
const _edge = Color(0xFF6E767C);
const _markDark = Color(0xFF7E858B);
const _markLight = Color(0xFFB9BFC3);
const _pore = Color(0xFF6A7177);
const _fleck = Color(0xFFC3C8CB);
const _drum = Color(0xFF16304D);
const _hose = Color(0xFF2A2F36);
const _bar = Color(0xFFD9443A);

class _Board {
  _Board(this.path, this.centre, this.out, this.nail0, this.nail1, this.spin);

  final Path path;
  final Offset centre;
  final Offset out;
  final Offset nail0;
  final Offset nail1;
  final double spin;
  double place = 0;
  double strip = 1;
}

/// Raster-row lookup: is a canvas point inside the glyph (by [inset] px)?
class _Inside {
  _Inside(GlyphStage s) : _k = s.k, _o = s.origin {
    for (final sp in s.geo.spans) {
      (_rows[sp.y] ??= <Span>[]).add(sp);
    }
  }

  final double _k;
  final Offset _o;
  final _rows = <int, List<Span>>{};

  bool call(Offset p, [double inset = 0]) {
    if (inset > 0) {
      return call(p) &&
          call(p + Offset(inset, 0)) &&
          call(p - Offset(inset, 0)) &&
          call(p + Offset(0, inset)) &&
          call(p - Offset(0, inset));
    }
    final row = _rows[((p.dy - _o.dy) / _k).floor()];
    if (row == null) return false;
    final rx = (p.dx - _o.dx) / _k;
    for (final sp in row) {
      if (rx >= sp.x0 && rx < sp.x1) return true;
    }
    return false;
  }
}

/// The formwork (planks along the outlines, on the outside of the
/// material) and the fill table, for one glyph.
class _Form {
  _Form(GlyphStage s, int seed) : inside = _Inside(s), _s = s {
    final ink = s.ink;
    final rng = math.Random(seed);
    final w = (s.typicalRadius * 0.45).clamp(3.5, 7.0);
    final eps = math.max(1.0, s.geo.inkHeight * 0.016);
    for (final cont in s.geo.contours) {
      final pr = simplifyClosed(Float64List.fromList(cont.pts), eps);
      final n = pr.length ~/ 2;
      if (n < 3) continue;
      final pts = [for (var i = 0; i < n; i++) s.map(pr[2 * i], pr[2 * i + 1])];
      var area = 0.0;
      for (var i = 0; i < n; i++) {
        final a = pts[i], b = pts[(i + 1) % n];
        area += a.dx * b.dy - b.dx * a.dy;
      }
      for (var i = 0; i < n; i++) {
        final a = pts[i], b = pts[(i + 1) % n];
        final d = b - a;
        final len = d.distance;
        if (len < 0.5) continue;
        final t = d / len;
        // The polygon's inside is on the (−t.dy, t.dx) side when area > 0;
        // boards go on the side away from the material.
        final nIn = area > 0 ? Offset(-t.dy, t.dx) : Offset(t.dy, -t.dx);
        final out = cont.hole ? nIn : -nIn;
        // Planks no longer than ~44 px.
        final pieces = math.max(1, (len / 44).ceil());
        for (var k = 0; k < pieces; k++) {
          final p0 = a + d * (k / pieces) - t * (w * 0.5);
          final p1 = a + d * ((k + 1) / pieces) + t * (w * 0.5);
          final q = [p0, p1, p1 + out * w, p0 + out * w];
          boards.add(
            _Board(
              Path()..addPolygon(q, true),
              (p0 + p1) / 2 + out * (w / 2),
              out,
              p0 + t * 3 + out * (w / 2),
              p1 - t * 3 + out * (w / 2),
              (rng.nextDouble() - 0.5) * 2.4,
            ),
          );
        }
      }
    }
    box = boards.isEmpty
        ? ink.inflate(w)
        : boards.map((b) => b.path.getBounds()).reduce((a, b) => a.expandToInclude(b));
    // Placed bottom-up; stripped top-down.
    final order = [for (var i = 0; i < boards.length; i++) i]
      ..sort((a, b) => boards[b].centre.dy.compareTo(boards[a].centre.dy));
    final n = math.max(1, order.length);
    for (var r = 0; r < order.length; r++) {
      final b = boards[order[r]];
      b.place =
          ConcreteCraft._boardsStart + (ConcreteCraft._boardsEnd - ConcreteCraft._boardsStart) * (r + 1) / n;
      b.strip =
          ConcreteCraft._stripStart +
          (ConcreteCraft._stripEnd - ConcreteCraft._drop - ConcreteCraft._stripStart) * (n - 1 - r) / n;
    }
    _order = order;

    // Fill table: rows bottom-up with their inside width.
    final widths = <double, double>{};
    for (final r in s.rows) {
      widths[r.top] = (widths[r.top] ?? 0) + r.width;
    }
    _tops = widths.keys.toList()..sort((a, b) => b.compareTo(a));
    _widths = [for (final y in _tops) widths[y]!];
    _total = _widths.fold(0.0, (a, b) => a + b);
  }

  final GlyphStage _s;
  final _Inside inside;
  final boards = <_Board>[];
  late final Rect box;
  late final List<int> _order;
  late final List<double> _tops;
  late final List<double> _widths;
  late final double _total;

  /// Height of the board being nailed at [p].
  double frontAt(double p) {
    if (_order.isEmpty) return _s.ink.bottom;
    final f = seg(p, ConcreteCraft._boardsStart, ConcreteCraft._boardsEnd);
    return boards[_order[(f * (_order.length - 1)).round()]].centre.dy;
  }

  /// Height of the board being pried off at [p].
  double stripFrontAt(double p) {
    if (_order.isEmpty) return _s.ink.bottom;
    final f = seg(p, ConcreteCraft._stripStart, ConcreteCraft._stripEnd - ConcreteCraft._drop);
    return boards[_order[((1 - f) * (_order.length - 1)).round()]].centre.dy;
  }

  /// The top of the concrete when [f] of the form is full (by volume,
  /// softened towards a steady rise).
  double levelAt(double f) {
    final ink = _s.ink;
    final lin = ink.bottom - ink.height * f;
    if (_total <= 0) return lin;
    final target = f * _total;
    var acc = 0.0;
    var y = ink.top;
    for (var i = 0; i < _tops.length; i++) {
      final w = _widths[i];
      if (acc + w >= target) {
        final frac = w <= 0 ? 0.0 : (target - acc) / w;
        y = _tops[i] + _s.k * (1 - frac);
        break;
      }
      acc += w;
    }
    return lerp(y, lin, 0.35);
  }

  /// Where a stream falling at [x] from [from] meets concrete (or the dais).
  double landing(double x, double from) {
    final ink = _s.ink;
    for (var y = math.max(from, ink.top); y < ink.bottom; y += 3) {
      if (inside(Offset(x, y))) return y;
    }
    return ink.bottom;
  }

  /// The vibrator's spot near the left of the letter at height [y].
  double pokerX(double y) {
    final ink = _s.ink;
    for (var px = ink.left + 2; px < ink.right; px += 3) {
      if (inside(Offset(px, y + 8))) return px + 10;
    }
    return ink.left + 10;
  }
}

/// The cured face: board marks (horizontal, from the face formwork) and
/// pores, inside the glyph.
class _Face {
  _Face(GlyphStage s, int seed) {
    final inside = _Inside(s);
    final rng = math.Random(seed ^ 0xc0de);
    final ink = s.ink;
    const pitch = 17.0;
    for (var y = ink.bottom - 9; y > ink.top + 3; y -= pitch) {
      var run = false;
      double x0 = 0;
      for (var px = ink.left; px <= ink.right + 2; px += 2) {
        final inn = inside(Offset(px, y), 1.6) && inside(Offset(px, y + 2.2), 1.6);
        if (inn && !run) {
          x0 = px;
          run = true;
        } else if (!inn && run) {
          run = false;
          if (px - x0 > 4) {
            marks
              ..moveTo(x0, y)
              ..lineTo(px - 2, y);
            marksLight
              ..moveTo(x0, y + 2.2)
              ..lineTo(px - 2, y + 2.2);
          }
        }
      }
    }
    for (final r in s.rows) {
      final expected = r.width * r.height / 150;
      var n = expected.floor();
      if (rng.nextDouble() < expected - n) n++;
      for (var i = 0; i < n; i++) {
        final pt = Offset(r.left + rng.nextDouble() * r.width, r.top + rng.nextDouble() * r.height);
        if (!inside(pt, 2.2)) continue;
        (rng.nextDouble() < 0.6 ? pores : flecks).add(pt);
      }
    }
  }

  final marks = Path();
  final marksLight = Path();
  final pores = <Offset>[];
  final flecks = <Offset>[];
}
