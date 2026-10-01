import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../../../worlds/factory/factory_kit.dart';
import '../geometry.dart';
import '../method.dart';
import '../stage.dart';
import '../workshop_layout.dart';

/// ブロック · Toy blocks: the glyph is fitted to a coarse grid (cells mostly
/// inside it, thin strokes kept), and a toy tower crane stacks colourful
/// studded bricks on it from the bottom up, each load clicking into place
/// ("カチッ") while a banksman signals from the dais.
class BlocksCraft extends CraftMethod {
  const BlocksCraft();

  @override
  String get id => 'blocks';

  @override
  String get en => 'Toy blocks';

  @override
  String get ja => 'ブロック';

  @override
  Color get color => BP.green;

  @override
  double get weight => 0.95;

  static final _grids = Expando<_Grid>();
  static final _pics = Expando<ui.Picture>();

  _Grid _grid(CraftContext x) => _grids[x.s] ??= _Grid(x.s, x.seed);

  static const _colors = [
    Color(0xFFFF5A5F), // red
    Color(0xFFFFC94A), // yellow
    Color(0xFF4D9DFF), // blue
    Color(0xFF45CC7F), // green
    Color(0xFFFF8F3D), // orange
    Color(0xFFB18CFF), // purple
  ];
  static final _edge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.3
    ..strokeJoin = StrokeJoin.round
    ..color = const Color(0x66000000);
  static final _shine = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..strokeCap = StrokeCap.round
    ..color = const Color(0x55FFFFFF);

  // ── Drawing bricks ────────────────────────────────────────────────────────

  /// Adds brick [b] (shifted by [o]) to the per-colour [bodies] and [studs]
  /// paths and the shared [edges] and [shine]; [studOn] says which of its
  /// units show a stud.
  void _add(
    _Grid g,
    _Block b,
    Offset o,
    List<Path> bodies,
    List<Path> studs,
    Path edges,
    Path shine,
    bool Function(int col) studOn,
  ) {
    final r = g.rect(b).shift(o);
    final body = RRect.fromRectAndRadius(r.deflate(0.6), Radius.circular(g.u * 0.08));
    bodies[b.color].addRRect(body);
    edges.addRRect(body);
    shine
      ..moveTo(r.left + g.u * 0.18, r.top + g.u * 0.2)
      ..lineTo(r.right - g.u * 0.18, r.top + g.u * 0.2);
    for (var i = 0; i < b.len; i++) {
      if (!studOn(b.col + i)) continue;
      final cx = r.left + (i + 0.5) * g.u;
      final stud = RRect.fromLTRBAndCorners(
        cx - g.u * 0.27,
        r.top - g.u * 0.17,
        cx + g.u * 0.27,
        r.top + 0.8,
        topLeft: Radius.circular(g.u * 0.07),
        topRight: Radius.circular(g.u * 0.07),
      );
      studs[b.color].addRRect(stud);
      edges.addRRect(stud);
    }
  }

  void _flush(Canvas c, List<Path> bodies, List<Path> studs, Path edges, Path shine) {
    for (var i = 0; i < _colors.length; i++) {
      c.drawPath(bodies[i], Paint()..color = _colors[i]);
      c.drawPath(studs[i], Paint()..color = _colors[i]);
    }
    c.drawPath(edges, _edge);
    c.drawPath(shine, _shine);
  }

  /// Bricks [0, n) as stacked so far (studs on every top that's still open),
  /// plus bricks [extraFrom, extraTo) shifted by [extraOffset] (the load on
  /// the hook).
  void _stack(Canvas c, _Grid g, int n, {int extraFrom = 0, int extraTo = 0, Offset extraOffset = Offset.zero}) {
    final bodies = [for (final _ in _colors) Path()];
    final studs = [for (final _ in _colors) Path()];
    final edges = Path(), shine = Path();
    for (var i = 0; i < n; i++) {
      final b = g.bricks[i];
      _add(g, b, Offset.zero, bodies, studs, edges, shine, (col) => g.brickAt(col, b.row + 1) >= n);
    }
    for (var i = extraFrom; i < extraTo; i++) {
      _add(g, g.bricks[i], extraOffset, bodies, studs, edges, shine, (_) => true);
    }
    _flush(c, bodies, studs, edges, shine);
  }

  ui.Picture _finished(CraftContext x) => _pics[x.s] ??= () {
    final g = _grid(x);
    final rec = ui.PictureRecorder();
    _stack(Canvas(rec), g, g.bricks.length);
    return rec.endRecording();
  }();

  @override
  void paintFinished(CraftContext x) => x.c.drawPicture(_finished(x));

  // ── Making ────────────────────────────────────────────────────────────────

  @override
  void paintMaking(CraftContext x, double p) {
    final s = x.s, c = x.c;
    final g = _grid(x);
    c.drawPath(s.outline, x.st(BP.lineFaint, 1.2));
    _gridMarks(x, g, 1 - seg(p, 0.85, 0.95));
    final crane = _Crane(s);
    final stackQ = seg(p, 0.06, 0.9);
    final lifts = g.lifts;
    if (lifts.isEmpty) return;
    final lt = stackQ * lifts.length;
    final j = math.min(lifts.length - 1, lt.floor());
    final f = stackQ >= 1 ? 1.0 : lt - j;
    final lift = lifts[j];
    // Released when the load has clicked in.
    final released = f >= 0.72;
    final placed = stackQ >= 1 ? g.bricks.length : (released ? lift.end : lift.start);

    // Where the trolley and the hook are: each trip starts by the mast (a
    // wide load left of it) and the empty hook heads back for the next.
    final rootX = crane.rootFor(lift);
    final nextRoot = j + 1 < lifts.length ? crane.rootFor(lifts[j + 1]) : crane.rootX;
    final topY = crane.hookTop;
    final hang = lift.count > 1 ? 30.0 : 20.0;
    final slotHook = lift.bounds.top - hang;
    double tx, hy;
    if (stackQ >= 1) {
      tx = rootX;
      hy = topY;
    } else if (f < 0.3) {
      tx = lerp(rootX, lift.bounds.center.dx, eio(f / 0.3));
      hy = topY;
    } else if (f < 0.72) {
      tx = lift.bounds.center.dx;
      hy = lerp(topY, slotHook, eio((f - 0.3) / 0.42));
    } else if (f < 0.8) {
      tx = lift.bounds.center.dx;
      hy = slotHook;
    } else {
      final r = eio((f - 0.8) / 0.2);
      tx = lerp(lift.bounds.center.dx, nextRoot, r);
      hy = lerp(slotHook, topY, r);
    }
    // (No load while the crane is still being put up.)
    final loaded = stackQ > 0 && stackQ < 1 && f < 0.72;
    final loadOffset = Offset(tx - lift.bounds.center.dx, hy - slotHook);
    _stack(
      c,
      g,
      placed,
      extraFrom: loaded ? lift.start : 0,
      extraTo: loaded ? lift.end : 0,
      extraOffset: loadOffset,
    );

    // The crane (fades in, and out once the letter stands).
    final rise = 1 - eo(seg(p, 0, 0.05));
    final alpha = math.min(seg(p, 0, 0.04), 1 - seg(p, 0.92, 0.99));
    if (alpha > 0) {
      final fade = alpha < 1;
      final area = Rect.fromLTRB(BW.hall.left, 306, BW.hall.right, x.floorY + 1);
      if (fade) c.saveLayer(area, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
      c.save();
      // It rises out of the floor.
      c.clipRect(area);
      c.translate(0, rise * 40);
      _drawCrane(x, crane, tx, hy, loaded ? lift : null, g, loadOffset);
      c.restore();
      if (fade) c.restore();
    }

    // Click!
    if (released && stackQ < 1 && f < 0.95) {
      _click(x, lift.bounds, seg(f, 0.72, 0.95));
    }
    _banksman(x, Offset(tx, hy), p, cheer: released && stackQ < 1 && f < 0.86);
  }

  /// Faint grid on the outline while the crane works: where the bricks go.
  void _gridMarks(CraftContext x, _Grid g, double a) {
    if (a <= 0) return;
    final c = x.c;
    final path = Path();
    for (var r = 0; r <= g.rows; r++) {
      final y = g.bottom - r * g.u;
      path
        ..moveTo(g.left, y)
        ..lineTo(g.left + g.cols * g.u, y);
    }
    for (var col = 0; col <= g.cols; col++) {
      final gx = g.left + col * g.u;
      path
        ..moveTo(gx, g.bottom)
        ..lineTo(gx, g.bottom - g.rows * g.u);
    }
    c.drawPath(path, x.st(BP.lineFaint.withValues(alpha: 0.5 * a), 0.8));
  }

  void _click(CraftContext x, Rect r, double q) {
    if (q <= 0 || q >= 1) return;
    final c = x.c;
    final burst = Path();
    for (final side in const [-1.0, 1.0]) {
      final o = Offset(side > 0 ? r.right + 2 : r.left - 2, r.bottom - 5);
      for (var i = 0; i < 3; i++) {
        final a = (i - 1) * 0.55;
        final dir = Offset(side * math.cos(a), math.sin(a) - 0.25);
        burst
          ..moveTo(o.dx + dir.dx * (3 + 6 * q), o.dy + dir.dy * (3 + 6 * q))
          ..lineTo(o.dx + dir.dx * (9 + 10 * q), o.dy + dir.dy * (9 + 10 * q));
      }
    }
    c.drawPath(burst, x.st(BP.ink.withValues(alpha: 1 - q), 1.6));
    final label = x.text.get(
      'カチッ',
      BT.sample(17, color: BP.amber, weight: 700).copyWith(locale: jaLocale),
    );
    final k = 0.6 + 0.5 * eo(seg(q, 0, 0.35));
    c.save();
    c.translate(r.center.dx + 14, r.top - 22 - 10 * q);
    c.scale(k);
    label.paint(c, Offset(-label.width / 2, -label.height / 2));
    c.restore();
  }

  // ── The crane ─────────────────────────────────────────────────────────────

  static const _yellow = Color(0xFFFFC94A);
  static const _red = Color(0xFFFF5A5F);

  void _drawCrane(CraftContext x, _Crane k, double tx, double hy, _Lift? load, _Grid g, Offset off) {
    final c = x.c;
    final mx = k.mastX, jy = k.jibY;
    final floor = x.floorY;
    // Base.
    final base = Rect.fromLTRB(mx - 24, floor - 10, mx + 24, floor);
    c.drawRect(base, x.fl(Mat.concrete));
    c.drawRect(base, x.st(BP.inkDim, 1.2));
    // Mast (lattice).
    final mast = Path()
      ..moveTo(mx - 8, floor - 10)
      ..lineTo(mx - 8, jy + 8)
      ..moveTo(mx + 8, floor - 10)
      ..lineTo(mx + 8, jy + 8);
    for (var y = floor - 10; y > jy + 16; y -= 16) {
      mast
        ..moveTo(mx - 8, y)
        ..lineTo(mx + 8, y - 16);
    }
    c.drawPath(mast, x.st(_yellow, 2));
    // Jib and counter-jib (lattice), apex and ties.
    final jib = Path()
      ..moveTo(k.tipX, jy)
      ..lineTo(mx + 62, jy)
      ..moveTo(k.tipX, jy + 8)
      ..lineTo(mx + 62, jy + 8);
    for (var gx = k.tipX; gx < mx + 54; gx += 14) {
      jib
        ..moveTo(gx, jy + 8)
        ..lineTo(gx + 7, jy)
        ..lineTo(gx + 14, jy + 8);
    }
    c.drawPath(jib, x.st(_yellow, 1.8));
    final apex = Offset(mx, jy - 26);
    final ties = Path()
      ..moveTo(mx - 8, jy)
      ..lineTo(apex.dx, apex.dy)
      ..lineTo(mx + 8, jy)
      ..moveTo(apex.dx, apex.dy)
      ..lineTo(lerp(mx, k.tipX, 0.62), jy)
      ..moveTo(apex.dx, apex.dy)
      ..lineTo(mx + 60, jy);
    c.drawPath(ties, x.st(_yellow.withValues(alpha: 0.85), 1.2));
    // Counterweight.
    final cw = Rect.fromLTRB(mx + 36, jy + 8, mx + 62, jy + 30);
    c.drawRect(cw, x.fl(Mat.concrete));
    c.drawRect(cw, x.st(BP.inkDim, 1.2));
    // Cab with the operator.
    final cab = Rect.fromLTRB(mx - 30, jy + 9, mx - 8, jy + 29);
    c.drawRect(cab, x.fl(_red));
    c.drawRect(Rect.fromLTRB(cab.left + 3, cab.top + 3, cab.right - 3, cab.top + 11), x.fl(BP.paper));
    c.drawCircle(Offset(cab.center.dx, cab.top + 8), 3, x.fl(BP.ink));
    c.drawRect(cab, x.st(BP.ink, 1.2));
    // Trolley, cable, hook block.
    final trolley = Rect.fromLTRB(tx - 9, jy + 8, tx + 9, jy + 14);
    c.drawRect(trolley, x.fl(_red));
    c.drawRect(trolley, x.st(BP.ink, 1));
    c.drawLine(Offset(tx - 3, jy + 14), Offset(tx - 3, hy - 6), x.st(BP.ink, 1));
    c.drawLine(Offset(tx + 3, jy + 14), Offset(tx + 3, hy - 6), x.st(BP.ink, 1));
    final block = Rect.fromLTRB(tx - 6, hy - 7, tx + 6, hy + 3);
    c.drawRect(block, x.fl(_red));
    c.drawRect(block, x.st(BP.ink, 1));
    final hook = Path()
      ..moveTo(tx, hy + 3)
      ..lineTo(tx, hy + 9)
      ..arcToPoint(Offset(tx - 6, hy + 9), radius: const Radius.circular(3.2));
    c.drawPath(hook, x.st(BP.ink, 1.6));
    // The load: slings (and a spreader bar for a row of bricks).
    if (load != null) {
      final sling = x.st(BP.inkDim, 1);
      final hookPt = Offset(tx - 1, hy + 10);
      final rects = [for (var i = load.start; i < load.end; i++) g.rect(g.bricks[i]).shift(off)];
      if (rects.length == 1) {
        final r = rects.first;
        c.drawLine(hookPt, Offset(r.left + 3, r.top - g.u * 0.17), sling);
        c.drawLine(hookPt, Offset(r.right - 3, r.top - g.u * 0.17), sling);
      } else {
        final b = load.bounds.shift(off);
        final barY = b.top - 12;
        c.drawLine(hookPt, Offset(b.left + 4, barY), sling);
        c.drawLine(hookPt, Offset(b.right - 4, barY), sling);
        c.drawLine(Offset(b.left, barY), Offset(b.right, barY), x.st(_yellow, 3));
        for (var i = load.start; i < load.end; i++) {
          final bk = g.bricks[i];
          var covered = false;
          for (var col = bk.col; col < bk.col + bk.len && !covered; col++) {
            final above = g.brickAt(col, bk.row + 1);
            covered = above >= load.start && above < load.end;
          }
          if (covered) continue;
          final r = rects[i - load.start];
          c.drawLine(Offset(r.center.dx, barY), Offset(r.center.dx, r.top - g.u * 0.17), sling);
        }
      }
    }
    // Toy box at the foot of the mast.
    final box = Rect.fromLTRB(mx + 16, floor - 22, mx + 56, floor);
    for (var i = 0; i < 4; i++) {
      final r = Rect.fromLTWH(box.left + 3 + i * 9, box.top - 5 - (i.isOdd ? 3 : 0), 8, 8);
      c.drawRect(r, x.fl(_colors[i + 1]));
    }
    c.drawRect(box, x.fl(BP.panel));
    c.drawRect(box, x.st(_red, 1.4));
  }

  /// A banksman on the dais signalling the crane (cheers at each click and
  /// at the end).
  void _banksman(CraftContext x, Offset hook, double p, {required bool cheer}) {
    final feet = Offset(math.max(BW.dais.left + 22, x.s.ink.left - 34), x.daisY);
    if (cheer || p > 0.9) {
      x.worker(feet, dir: 1, pose: Pose()..cheer(x.t, 2), hat: BP.green);
      return;
    }
    final limbs = x.reach(feet, hook, hat: BP.green, dir: 1);
    // A little signalling paddle.
    x.c.drawCircle(limbs.handA, 3.4, x.fl(BP.green));
  }
}

/// Where the toy tower crane stands: right of the dais, its jib over the
/// glyph (below the name sign).
class _Crane {
  _Crane(GlyphStage s)
    : mastX = 1388,
      jibY = math.max(338.0, s.ink.top - 52),
      tipX = s.ink.left - 22;

  final double mastX;
  final double jibY;
  final double tipX;

  double get rootX => mastX - 46;

  /// Where the trip with [l] starts: by the mast, the load clear of it.
  double rootFor(_Lift l) => math.min(rootX, mastX - 16 - l.bounds.width / 2);
  double get hookTop => jibY + 40;
}

class _Block {
  _Block(this.row, this.col, this.len, this.color);

  final int row;
  final int col;
  final int len;
  final int color;
}

/// One trip of the crane: bricks [start, end) (one brick, or a run of a row
/// on a spreader bar for big glyphs).
class _Lift {
  _Lift(this.start, this.end, this.bounds);

  final int start;
  final int end;
  final Rect bounds;

  int get count => end - start;
}

/// The glyph on a coarse grid of square cells (rows from the dais up), cut
/// into bricks of 1–4 units with staggered seams.
class _Grid {
  _Grid(GlyphStage s, int seed) {
    final ink = s.ink;
    bottom = ink.bottom;
    final byRow = <int, List<Span>>{};
    for (final sp in s.geo.spans) {
      byRow.putIfAbsent(sp.y, () => []).add(sp);
    }
    // Cells about half a stroke wide (a stroke gets two, whatever the grid's
    // phase); pick the size (±10 %) and horizontal phase that match best.
    final u0 = (2 * s.typicalRadius * 0.55).clamp(12.0, 26.0);
    var best = (fill: <bool>[], err: double.infinity, u: u0, rows: 1, left: ink.left, cols: 1);
    for (final f in const [0.9, 1.0, 1.1]) {
      final nr = math.max(1, (ink.height / (u0 * f)).round());
      final cu = ink.height / nr;
      for (final phase in const [0.0, 0.25, 0.5, 0.75]) {
        final l = ink.left - phase * cu;
        final n = ((ink.right - l) / cu).ceil();
        final (fill, err) = _fill(s, byRow, l, n, cu, nr);
        final area = err * cu * cu;
        if (area < best.err) best = (fill: fill, err: area, u: cu, rows: nr, left: l, cols: n);
      }
    }
    final filled = best.fill;
    u = best.u;
    rows = best.rows;
    left = best.left;
    cols = best.cols;
    if (!filled.contains(true)) filled[(rows ~/ 2) * cols + cols ~/ 2] = true;
    // Bricks, row by row from the bottom; seams every 4 units, staggered.
    // Cheerful colours, no two alike side by side; a busy glyph gets three
    // colours (mostly the first) so its shape isn't lost in confetti.
    final busy = filled.where((f) => f).length > 110;
    const sets = [
      [0, 1, 2],
      [3, 4, 5],
      [1, 4, 0],
      [2, 3, 5],
    ];
    final set = sets[(rnd(seed, 17, 4) * sets.length).floor()];
    _cell = List.filled(cols * rows, -1);
    for (var r = 0; r < rows; r++) {
      var col = 0;
      while (col < cols) {
        if (!filled[r * cols + col]) {
          col++;
          continue;
        }
        final c0 = col;
        while (col < cols && filled[r * cols + col]) {
          col++;
        }
        for (final (a, len) in _pieces(c0, col, r.isOdd ? 2 : 0)) {
          final left = _raw(a - 1, r), below = _raw(a, r - 1);
          final roll = rnd(seed, r * 97 + a, 3);
          var color = busy
              ? set[roll < 0.55 ? 0 : (roll < 0.82 ? 1 : 2)]
              : (roll * BlocksCraft._colors.length).floor();
          for (var tries = 0; !busy && tries < BlocksCraft._colors.length; tries++) {
            final clash =
                (left >= 0 && bricks[left].color == color) || (below >= 0 && bricks[below].color == color);
            if (!clash) break;
            color = (color + 1) % BlocksCraft._colors.length;
          }
          for (var i = 0; i < len; i++) {
            _cell[r * cols + a + i] = bricks.length;
          }
          bricks.add(_Block(r, a, len, color));
        }
      }
    }
    // Crane trips: one brick each, or part of a row (or a few rows) on a
    // spreader bar for bigger glyphs.
    const maxLifts = 16;
    if (bricks.length <= maxLifts) {
      for (var i = 0; i < bricks.length; i++) {
        lifts.add(_lift(i, i + 1));
      }
      return;
    }
    final rowRuns = <(int, int)>[];
    for (var i = 0; i < bricks.length;) {
      var e = i;
      while (e < bricks.length && bricks[e].row == bricks[i].row) {
        e++;
      }
      rowRuns.add((i, e));
      i = e;
    }
    if (rowRuns.length >= maxLifts) {
      final per = rowRuns.length / maxLifts;
      for (var gi = 0; gi < maxLifts; gi++) {
        final a = (gi * per).round(), b = ((gi + 1) * per).round();
        if (b > a) lifts.add(_lift(rowRuns[a].$1, rowRuns[b - 1].$2));
      }
      return;
    }
    for (final (i, e) in rowRuns) {
      final n = e - i;
      final groups = math.max(1, (n * maxLifts / bricks.length).round()).clamp(1, n);
      for (var gi = 0; gi < groups; gi++) {
        final a = i + (n * gi / groups).round(), b = i + (n * (gi + 1) / groups).round();
        if (b > a) lifts.add(_lift(a, b));
      }
    }
  }

  _Lift _lift(int a, int b) {
    var bounds = rect(bricks[a]);
    for (var k = a + 1; k < b; k++) {
      bounds = bounds.expandToInclude(rect(bricks[k]));
    }
    return _Lift(a, b, bounds);
  }

  late final double u;
  late final double left;
  late final double bottom;
  late final int cols;
  late final int rows;
  late final List<int> _cell;
  final bricks = <_Block>[];
  final lifts = <_Lift>[];

  /// Index of the brick covering cell ([col], [row]), or a huge number when
  /// there's none (so "is it placed yet?" checks read as no).
  int brickAt(int col, int row) {
    if (col < 0 || col >= cols || row < 0 || row >= rows) return 1 << 30;
    final i = _cell[row * cols + col];
    return i < 0 ? 1 << 30 : i;
  }

  int _raw(int col, int row) =>
      col < 0 || col >= cols || row < 0 || row >= rows ? -1 : _cell[row * cols + col];

  Rect rect(_Block b) => Rect.fromLTWH(left + b.col * u, bottom - (b.row + 1) * u, b.len * u, u);

  /// Which cells to fill for a grid of [u] cells starting at [l] with [n]
  /// columns and [rows] rows, and the mismatch (area wrongly filled or left
  /// empty, in cells).
  (List<bool>, double) _fill(
    GlyphStage s,
    Map<int, List<Span>> byRow,
    double l,
    int n,
    double u,
    int rows,
  ) {
    final cov = List.filled(n * rows, 0.0);
    final k = s.k, ox = s.origin.dx, oy = s.origin.dy;
    for (var r = 0; r < rows; r++) {
      final y1 = (bottom - r * u - oy) / k, y0 = (bottom - (r + 1) * u - oy) / k;
      for (var ry = y0.floor(); ry < y1.ceil(); ry++) {
        final wy = math.min(ry + 1.0, y1) - math.max(ry.toDouble(), y0);
        if (wy <= 0) continue;
        for (final sp in byRow[ry] ?? const <Span>[]) {
          // Cells this span touches.
          final a = (ox + sp.x0 * k - l) / u, b = (ox + sp.x1 * k - l) / u;
          for (var col = math.max(0, a.floor()); col < math.min(n, b.ceil()); col++) {
            final wx = math.min(b, col + 1.0) - math.max(a, col.toDouble());
            if (wx > 0) cov[r * n + col] += wx * u / k * wy;
          }
        }
      }
    }
    final cellArea = (u / k) * (u / k);
    // Cells the strokes' centre lines pass through.
    final skel = List.filled(n * rows, false);
    for (final st in s.strokes) {
      for (var i = 1; i < st.pts.length; i++) {
        final a = st.pts[i - 1], b = st.pts[i];
        final steps = math.max(1, ((b - a).distance / (u / 4)).ceil());
        for (var q = 0; q <= steps; q++) {
          final pt = Offset.lerp(a, b, q / steps)!;
          final col = ((pt.dx - l) / u).floor(), row = ((bottom - pt.dy) / u).floor();
          if (col >= 0 && col < n && row >= 0 && row < rows) skel[row * n + col] = true;
        }
      }
    }
    var err = 0.0;
    final out = List.filled(n * rows, false);
    for (var i = 0; i < n * rows; i++) {
      final f = cov[i] / cellArea;
      out[i] = f >= 0.5 || (f >= 0.18 && skel[i]);
      err += out[i] ? 1 - f : f;
    }
    return (out, err);
  }

  /// Splits the run of cells [c0, c1) at seams every 4 units (shifted by
  /// [shift]), merging single units into a neighbour when it fits.
  static List<(int, int)> _pieces(int c0, int c1, int shift) {
    final cuts = <int>[c0];
    for (var col = c0 + 1; col < c1; col++) {
      if ((col + shift) % 4 == 0) cuts.add(col);
    }
    cuts.add(c1);
    final lens = <int>[for (var i = 1; i < cuts.length; i++) cuts[i] - cuts[i - 1]];
    // Merge 1-unit ends into their neighbour when the result stays ≤ 4.
    if (lens.length > 1 && lens.first == 1 && lens[1] <= 3) {
      lens[1] += 1;
      lens.removeAt(0);
    }
    if (lens.length > 1 && lens.last == 1 && lens[lens.length - 2] <= 3) {
      lens[lens.length - 2] += 1;
      lens.removeLast();
    }
    final out = <(int, int)>[];
    var at = c0;
    for (final len in lens) {
      out.add((at, len));
      at += len;
    }
    return out;
  }
}
