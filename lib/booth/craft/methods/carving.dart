import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../../../worlds/factory/factory_kit.dart';
import '../geometry.dart';
import '../method.dart';
import '../stage.dart';

/// 石彫 · Stone carving: a rough block of stone (the glyph's ink bounds and
/// a margin) stands on the dais. Two sculptors on lifts work their way down
/// it with hammer and chisel, knocking off one rough chunk after another
/// (chips flying, dust) until only the letter is left; then they polish it
/// from the bottom up, which brings out the speckled stone and its
/// chiselled edges.
class CarvingCraft extends CraftMethod {
  const CarvingCraft();

  @override
  String get id => 'carving';

  @override
  String get en => 'Stone carving';

  @override
  String get ja => '石彫';

  @override
  Color get color => Mat.stone;

  @override
  double get weight => 1.05;

  static final _blocks = Expando<_Block>();
  static final _finishes = Expando<_Finish>();

  static _Block _block(CraftContext x) => _blocks[x.s] ??= _Block(x.s, x.seed, x.daisY);
  static _Finish _finish(GlyphStage s, int seed) => _finishes[s] ??= _Finish(s, seed);

  // Timeline (fractions of p).
  static const _carveStart = 0.03, _carveEnd = 0.84;
  static const _polishStart = 0.86, _polishEnd = 0.985;

  /// How long chips fly / dust hangs after a chunk comes off.
  static const _chipLife = 0.05;

  @override
  void paintMaking(CraftContext x, double p) {
    final s = x.s;
    if (s.contours.isEmpty) return;
    final b = _block(x);
    final c = x.c;
    p = p.clamp(0.0, 1.0);

    // The letter as carved so far, under the remaining rough stone (none
    // yet while the block fades in), polished from the bottom up.
    final appear = seg(p, 0, 0.025);
    final polish = seg(p, _polishStart, _polishEnd);
    if (polish >= 1) {
      paintFinished(x);
    } else if (polish > 0) {
      final line = lerp(s.ink.bottom + 4, s.ink.top - 4, polish);
      c.save();
      c.clipRect(Rect.fromLTRB(s.ink.left - 20, s.ink.top - 30, s.ink.right + 20, line));
      _carved(x);
      c.restore();
      c.save();
      c.clipRect(Rect.fromLTRB(s.ink.left - 20, line, s.ink.right + 20, s.ink.bottom + 30));
      paintFinished(x);
      c.restore();
    } else if (appear >= 1) {
      _carved(x);
    }

    // Rough stone still on the block (fading in as the job starts).
    if (appear < 1) c.saveLayer(b.r.inflate(4), Paint()..color = Color.fromRGBO(0, 0, 0, appear));
    final texture = Path();
    for (final cell in b.cells) {
      if (cell.t <= p) continue;
      c.drawPath(cell.path, x.fl(cell.color));
      texture.addPath(cell.texture, Offset.zero);
    }
    c.drawPath(texture, x.st(_roughLine, 1.1));
    if (appear < 1) c.restore();

    // Chips and dust from the chunks that just came off.
    final chips = <Offset>[];
    for (final cell in b.cells) {
      final age = (p - cell.t) / _chipLife;
      if (age <= 0 || age >= 1) continue;
      _dust(x, cell, age);
      for (var i = 0; i < cell.chips.length; i++) {
        final (o, v, spin) = cell.chips[i];
        final tau = age * 0.8; // seconds-ish
        var at = cell.centre + o + v * tau + Offset(0, 900 * tau * tau);
        if (at.dy > x.floorY - 2) at = Offset(at.dx, x.floorY - 2);
        if (age > 0.7) {
          chips.add(at);
          continue;
        }
        _chip(x, at, 3.2 + 2.4 * rnd(i, 7), spin * age * 12, cell.color);
      }
    }
    if (chips.isNotEmpty) c.drawPoints(ui.PointMode.points, chips, x.st(_rough, 3));

    // The sculptors (left and right halves), then the polishers.
    if (p < _polishStart - 0.01) {
      for (var side = 0; side < 2; side++) {
        _sculptor(x, b, side, p);
      }
    } else {
      _polishers(x, b, p);
    }
  }

  @override
  void paintFinished(CraftContext x) {
    final s = x.s, c = x.c;
    if (s.contours.isEmpty) return;
    final f = _finish(s, x.seed);
    c.drawPath(s.outline, x.fl(Mat.stone));
    c.drawPoints(ui.PointMode.points, f.dark, x.st(_speckDark, 2.4));
    c.drawPoints(ui.PointMode.points, f.light, x.st(_speckLight, 2.2));
    c.drawPoints(ui.PointMode.points, f.warm, x.st(_speckWarm, 1.8));
    // Chiselled edge: a shadow below-right and a bright bevel on the rim.
    c.save();
    c.translate(1.4, 1.8);
    c.drawPath(s.outline, x.st(_shadow, 1.8));
    c.restore();
    c.drawPath(s.outline, x.st(_bevel, 2.4));
  }

  /// Freshly carved (not yet polished): darker, with tool marks.
  void _carved(CraftContext x) {
    final s = x.s, c = x.c;
    final f = _finish(s, x.seed);
    c.drawPath(s.outline, x.fl(_carvedStone));
    c.drawPoints(ui.PointMode.points, f.dark, x.st(_speckDark, 2.4));
    c.drawPath(f.marks, x.st(_toolMark, 1.2));
    c.drawPath(s.outline, x.st(_carvedEdge, 1.6));
  }

  void _chip(CraftContext x, Offset at, double r, double a, Color col) {
    final cs = math.cos(a) * r, sn = math.sin(a) * r;
    final chip = Path()
      ..moveTo(at.dx + cs, at.dy + sn)
      ..lineTo(at.dx - sn * 0.8, at.dy + cs * 0.8)
      ..lineTo(at.dx - cs * 0.7, at.dy - sn * 0.9)
      ..close();
    x.c.drawPath(chip, x.fl(col));
    x.c.drawPath(chip, x.st(_roughLine, 0.8));
  }

  static final _dustPaint = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

  /// A soft puff of stone dust drifting up where a chunk came off.
  void _dust(CraftContext x, _Cell cell, double age) {
    _dustPaint.color = _dustCol.withValues(alpha: 0.45 * (1 - age));
    for (var i = 0; i < 3; i++) {
      final o = Offset((rnd(i, 3) - 0.5) * 26 + 10 * age * (rnd(i, 4) - 0.5), (rnd(i, 5) - 0.6) * 20 - 18 * age);
      x.c.drawCircle(cell.centre + o, lerp(5, 16 + 6 * rnd(i, 9), eo(age)), _dustPaint);
    }
  }

  /// Where sculptor [side] (0 left, 1 right) is at [p]: gliding to the next
  /// chunk, then striking the chisel three times before it comes off.
  void _sculptor(CraftContext x, _Block b, int side, double p) {
    final q = b.queue[side];
    final dir = side == 0 ? 1 : -1;
    if (q.isEmpty) return;
    var k = 0;
    while (k < q.length - 1 && b.cells[q[k]].t <= p) {
      k++;
    }
    final cell = b.cells[q[k]];
    final t0 = k == 0 ? _carveStart - 0.02 : b.cells[q[k - 1]].t;
    final u = cell.t <= t0 ? 1.0 : ((p - t0) / (cell.t - t0)).clamp(0.0, 1.0);
    final done = p >= cell.t;
    final from = k == 0 ? b.home[side] : b.stand(x, q[k - 1], dir);
    final to = b.stand(x, q[k], dir);
    final stand = done ? to : Offset.lerp(from, to, eio(seg(u, 0, 0.3)))!;
    final target = cell.centre - Offset(dir * cell.reach, 0);
    x.lift(stand.dx, stand.dy, w: 46);
    final feet = Offset(stand.dx, stand.dy - 4);
    final shoulder = feet + const Offset(0, -39);
    final v = target - shoulder;
    final a = math.atan2(v.dx * dir, v.dy).clamp(-0.3, 3.0);
    // Three blows while working this chunk.
    final w = done ? 0.0 : (seg(u, 0.3, 1) * 3) % 1;
    final swing = done ? 0.2 : (w < 0.75 ? ei(w / 0.75) : 1 - (w - 0.75) / 0.25);
    final pose = Pose()
      ..upB = a
      ..foB = a + 0.05
      ..upA = a + 1.3 - 1.1 * swing
      ..foA = a + 1.9 - 1.5 * swing
      ..lean = 0.08;
    final l = x.ink.worker(feet, 50, dir, pose, hat: side == 0 ? BP.amber : BP.coral);
    // Chisel in the back hand, against the stone.
    final cd = target - l.handB;
    final cu = cd / math.max(1, cd.distance);
    final tip = l.handB + cu * math.min(16, cd.distance);
    x.c.drawLine(l.handB - cu * 2, tip, x.st(Mat.steel, 2.6));
    x.c.drawLine(l.handB - cu * 4, l.handB + cu * 3, x.st(Mat.wood, 3.4));
    _mallet(x, l.elbowA, l.handA);
    if (!done && swing > 0.92 && u > 0.3) x.ink.star(tip, 6, BP.amber);
  }

  /// A carver's mallet in the hand: a short handle and a heavy head.
  void _mallet(CraftContext x, Offset elbow, Offset hand) {
    final d = hand - elbow;
    final u = d / math.max(1, d.distance);
    final head = hand + u * 11;
    x.c.drawLine(hand - u * 2, head, x.st(Mat.wood, 2.4));
    final n = Offset(-u.dy, u.dx);
    x.c.drawLine(head - n * 5, head + n * 5, x.st(Mat.steelDark, 6));
    x.c.drawLine(head - n * 5, head + n * 5, x.st(Mat.steel, 2));
  }

  /// Polishing from the bottom up: a pad each side, riding up on the lifts.
  void _polishers(CraftContext x, _Block b, double p) {
    final s = x.s;
    final polish = seg(p, _polishStart, _polishEnd);
    final y = lerp(s.ink.bottom - 6, s.ink.top + 6, polish);
    final (l, r) = b.extentAt(y);
    for (var side = 0; side < 2; side++) {
      final dir = side == 0 ? 1 : -1;
      final edge = side == 0 ? l : r;
      final rub = 5 * math.sin(x.t * 18 + side * 2);
      final pad = Offset(edge + dir * (8 + rub), y);
      final standX = edge - dir * 40;
      final platform = x.liftFor(y);
      x.lift(standX, platform, w: 46);
      final limbs = x.reach(
        Offset(standX, platform - 4),
        pad,
        both: true,
        dir: dir,
        hat: side == 0 ? BP.amber : BP.coral,
      );
      x.c.drawLine(limbs.handA, pad, x.st(BP.inkDim, 2));
      final disc = Rect.fromCenter(center: pad, width: 9, height: 18);
      x.c.drawOval(disc, x.fl(_pad));
      x.c.drawOval(disc, x.st(BP.ink, 1.2));
      if (polish < 0.97) {
        final frame = (x.t * 12).floor();
        for (var i = 0; i < 2; i++) {
          final o = Offset(dir * 14 * rnd(frame, i, side), -14 * rnd(i, frame, side + 3));
          x.ink.star(pad + o, 3 + 3 * rnd(frame, i + 5), _bevel);
        }
      }
    }
    // A bright line where the polish has reached.
    x.c.save();
    x.c.clipPath(s.outline);
    x.c.drawLine(Offset(s.ink.left, y), Offset(s.ink.right, y), x.st(_bevel.withValues(alpha: 0.7), 2));
    x.c.restore();
  }
}

// Stone colours.
const _rough = Color(0xFF837D71);
const _roughLine = Color(0xFF5F5A50);
const _carvedStone = Color(0xFFA7A296);
const _carvedEdge = Color(0xFF7C776C);
const _toolMark = Color(0xFF878276);
const _speckDark = Color(0xFF8A857A);
const _speckLight = Color(0xFFD3CFC5);
const _speckWarm = Color(0xFFC2A98E);
const _bevel = Color(0xFFF1EEE6);
const _shadow = Color(0xFF5E5A51);
const _dustCol = Color(0xFFCFCABE);
const _pad = Color(0xFFE6E0D2);

/// Where the lifts may stand (clear of the craft's sign on the left and
/// the hall's column on the right).
const _minX = 790.0, _maxX = 1450.0;

/// One rough chunk of the block.
class _Cell {
  _Cell(this.path, this.centre, this.color, this.texture, this.chips, this.reach);

  final Path path;
  final Offset centre;
  final Color color;
  final Path texture;

  /// Chips flying off: (offset from the centre, velocity px/s, spin).
  final List<(Offset, Offset, double)> chips;

  /// How far from the centre the chisel bites (towards the sculptor).
  final double reach;

  /// When it comes off (p).
  double t = 1;
}

/// The block of stone and the order its chunks come off in.
class _Block {
  _Block(GlyphStage s, int seed, double daisY) {
    final ink = s.ink;
    final rng = math.Random(seed);
    final m = (ink.height * 0.08).clamp(14.0, 26.0);
    r = Rect.fromLTRB(ink.left - m, ink.top - m, ink.right + m, daisY);
    final nx = math.max(2, (r.width / 40).round());
    final ny = math.max(2, (r.height / 40).round());
    final cw = r.width / nx, ch = r.height / ny;
    final v = <Offset>[];
    for (var j = 0; j <= ny; j++) {
      for (var i = 0; i <= nx; i++) {
        var px = r.left + cw * i;
        var py = r.top + ch * j;
        if (i > 0 && i < nx) px += (rng.nextDouble() - 0.5) * cw * 0.55;
        if (j > 0 && j < ny) py += (rng.nextDouble() - 0.5) * ch * 0.55;
        v.add(Offset(px, py));
      }
    }
    final rows = <List<int>>[for (var j = 0; j < ny; j++) []];
    for (var j = 0; j < ny; j++) {
      for (var i = 0; i < nx; i++) {
        final q = [
          v[j * (nx + 1) + i],
          v[j * (nx + 1) + i + 1],
          v[(j + 1) * (nx + 1) + i + 1],
          v[(j + 1) * (nx + 1) + i],
        ];
        final centre = (q[0] + q[1] + q[2] + q[3]) / 4;
        final shade = 0.9 + 0.16 * rng.nextDouble();
        final color = Color.from(
          alpha: 1,
          red: (_rough.r * shade).clamp(0.0, 1.0),
          green: (_rough.g * shade).clamp(0.0, 1.0),
          blue: (_rough.b * shade).clamp(0.0, 1.0),
        );
        // A couple of pits and cracks on the rough face.
        final tex = Path();
        for (var k = 0; k < 2; k++) {
          final o = centre + Offset((rng.nextDouble() - 0.5) * cw * 0.7, (rng.nextDouble() - 0.5) * ch * 0.7);
          final a = rng.nextDouble() * math.pi;
          final l = 4 + 6 * rng.nextDouble();
          tex
            ..moveTo(o.dx, o.dy)
            ..lineTo(o.dx + math.cos(a) * l, o.dy + math.sin(a) * l)
            ..lineTo(o.dx + math.cos(a) * l + 3, o.dy + math.sin(a) * l + 2);
        }
        final chips = <(Offset, Offset, double)>[];
        final out = centre.dx < ink.center.dx ? -1.0 : 1.0;
        for (var k = 0; k < 5; k++) {
          chips.add((
            Offset((rng.nextDouble() - 0.5) * cw * 0.6, (rng.nextDouble() - 0.5) * ch * 0.6),
            Offset(out * (40 + 140 * rng.nextDouble()), -(60 + 160 * rng.nextDouble())),
            rng.nextDouble() - 0.5,
          ));
        }
        rows[j].add(cells.length);
        cells.add(_Cell(Path()..addPolygon(q, true), centre, color, tex, chips, cw * 0.3));
      }
    }
    // Each sculptor takes a half, row by row from the top, snaking (outside
    // in, then back out) so the lifts glide instead of jumping.
    for (var j = 0; j < ny; j++) {
      final left = [for (final k in rows[j]) if (cells[k].centre.dx < r.center.dx) k];
      final right = [for (final k in rows[j]) if (cells[k].centre.dx >= r.center.dx) k]
        ..sort((a, b) => cells[b].centre.dx.compareTo(cells[a].centre.dx));
      queue[0].addAll(j.isEven ? left : left.reversed);
      queue[1].addAll(j.isEven ? right : right.reversed);
    }
    for (var side = 0; side < 2; side++) {
      final q = queue[side];
      for (var k = 0; k < q.length; k++) {
        final cell = cells[q[k]];
        final jitter = (rng.nextDouble() - 0.5) * 0.35 / math.max(1, q.length);
        cell.t = CarvingCraft._carveStart +
            (CarvingCraft._carveEnd - CarvingCraft._carveStart) * ((k + 1) / q.length) +
            jitter;
      }
    }
    home = [
      Offset(math.max(_minX, r.left - 34), daisY),
      Offset(math.min(_maxX, r.right + 34), daisY),
    ];
    // Left/right extent of the letter per raster row (for the polishers).
    for (final row in s.rows) {
      final e = _extent[row.top];
      _extent[row.top] = e == null
          ? (row.left, row.right)
          : (math.min(e.$1, row.left), math.max(e.$2, row.right));
    }
    _rowTops = _extent.keys.toList()..sort();
    _ink = ink;
  }

  late final Rect r;
  final cells = <_Cell>[];
  final queue = <List<int>>[[], []];
  late final List<Offset> home;
  final _extent = <double, (double, double)>{};
  late final List<double> _rowTops;
  late final Rect _ink;

  /// Lift position (x, platform y) for working on cell [k] from side [dir].
  Offset stand(CraftContext x, int k, int dir) {
    final cell = cells[k];
    final sx = (cell.centre.dx - dir * (cell.reach + 34)).clamp(_minX, _maxX);
    return Offset(sx, x.liftFor(cell.centre.dy));
  }

  /// The letter's left and right edges around height [y].
  (double, double) extentAt(double y) {
    if (_rowTops.isEmpty) return (_ink.left, _ink.right);
    var best = _rowTops.first;
    for (final t in _rowTops) {
      if ((t - y).abs() < (best - y).abs()) best = t;
    }
    return _extent[best]!;
  }
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

/// Texture of the finished stone: speckles and tool marks inside the glyph
/// (kept clear of the edges, so nothing pokes out).
class _Finish {
  _Finish(GlyphStage s, int seed) {
    final rng = math.Random(seed ^ 0x5eed);
    final inside = _Inside(s);
    for (final r in s.rows) {
      final expected = r.width * r.height / 70;
      var n = expected.floor();
      if (rng.nextDouble() < expected - n) n++;
      for (var i = 0; i < n; i++) {
        final pt = Offset(r.left + rng.nextDouble() * r.width, r.top + rng.nextDouble() * r.height);
        if (!inside(pt, 2.6)) continue;
        final pick = rng.nextDouble();
        (pick < 0.45 ? dark : (pick < 0.85 ? light : warm)).add(pt);
      }
      // Tool marks: short diagonal strokes.
      final m = (r.width * r.height / 260).floor();
      for (var i = 0; i < m; i++) {
        final o = Offset(r.left + rng.nextDouble() * r.width, r.top + rng.nextDouble() * r.height);
        if (!inside(o, 4.5)) continue;
        marks
          ..moveTo(o.dx - 3, o.dy + 2.5)
          ..lineTo(o.dx + 3, o.dy - 2.5);
      }
    }
  }

  final dark = <Offset>[];
  final light = <Offset>[];
  final warm = <Offset>[];
  final marks = Path();
}
