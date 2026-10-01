import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../layout.dart';
import 'site_plan.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The wall coming down and going away: every brick of the wall becomes a
// piece that is knocked loose (by the ball, by losing its support, or in the
// final collapse), falls with gravity, bounces, tumbles and settles on a
// rubble heap; then it is pushed by the bulldozer, scooped, dropped in the
// truck and poured out at the factory.
//
// Pieces are stored as flat typed arrays (struct of arrays) so ~1500 of
// them step and draw cheaply.
// ─────────────────────────────────────────────────────────────────────────────

enum Piece { standing, flying, resting, pushed, bucket, dropping, truck, pouring, gone }

/// Where the truck's bed is (for pieces dropped into it or poured out).
abstract class BedFrame {
  /// World position of a point given in bed coordinates (x from the rear lip
  /// towards the cab, y up from the bed floor, both in px) at [t].
  Offset world(double t, double bx, double by);

  /// Where pieces pour out (the rear lip) at [t].
  Offset lip(double t);
}

class Rubble {
  Rubble(this.site, this.count, {required int standing}) {
    final n = count;
    x = Float32List(n);
    y = Float32List(n);
    vx = Float32List(n);
    vy = Float32List(n);
    ang = Float32List(n);
    va = Float32List(n);
    state = Uint8List(n);
    since = Float32List(n);
    fromX = Float32List(n);
    fromY = Float32List(n);
    releaseAt = Float32List(n)..fillRange(0, n, double.infinity);
    ru = Float32List(n);
    rv = Float32List(n);
    for (var i = 0; i < n; i++) {
      x[i] = site.cx[i];
      y[i] = site.cy[i];
      ru[i] = hash(i, 3.1);
      rv[i] = hash(i, 7.7);
      state[i] = i < standing ? Piece.standing.index : Piece.flying.index;
    }
    standingCount = standing;
    size = site.b * 0.86;
    _anchor = _anchors();
    heap = Float32List(((_x1 - _x0) / _col).ceil() + 1);
  }

  final SitePlan site;
  final int count;
  late final Float32List x, y, vx, vy, ang, va, since, fromX, fromY, releaseAt, ru, rv;
  late final Uint8List state;
  late final double size;

  int standingCount = 0;

  /// Bumped whenever the set of standing bricks changes.
  int standingVersion = 0;

  /// Rubble stays on the site (clear of the crew's safe spots).
  static const minX = 654.0, maxX = 1486.0;

  /// Ground heap heights (px) in columns.
  static const _x0 = 560.0, _x1 = 1580.0, _col = 4.0;
  late final Float32List heap;

  /// Dust puffs to spawn (x, y, size), drained by the simulation.
  final dust = <(double, double, double)>[];
  double _lastDust = -1;

  bool _dirty = false;
  int _rest = 0;

  int _hcol(double px) => ((px - _x0) / _col).floor().clamp(0, heap.length - 1);

  double heapAt(double px, double w) {
    var h = 0.0;
    for (var i = _hcol(px - w / 2); i <= _hcol(px + w / 2); i++) {
      if (heap[i] > h) h = heap[i];
    }
    return h;
  }

  void _addHeap(double px, double w, double top) {
    for (var i = _hcol(px - w / 2); i <= _hcol(px + w / 2); i++) {
      if (heap[i] < top) heap[i] = top;
    }
  }

  // ── Knocking bricks loose ────────────────────────────────────────────────

  void release(int i, double t, double nvx, double nvy, double spin) {
    if (state[i] != Piece.standing.index) return;
    state[i] = Piece.flying.index;
    since[i] = t;
    vx[i] = nvx;
    vy[i] = nvy;
    va[i] = spin;
    standingCount--;
    standingVersion++;
    _dirty = true;
  }

  /// Schedules every standing brick to topple, top rows first, within
  /// [spread] seconds from [t0].
  void collapse(double t0, double spread) {
    final rows = site.rows;
    for (var i = 0; i < count; i++) {
      if (state[i] != Piece.standing.index) continue;
      final row = site.r.bricks[i].row;
      releaseAt[i] = math.min(releaseAt[i], t0 + spread * (row / math.max(1, rows - 1)) * 0.8 + spread * 0.2 * ru[i]);
    }
  }

  /// The ball at [ball] moving with [vel] knocks bricks it touches.
  void hit(Offset ball, Offset vel, double t) {
    final w = site.wall.inflate(ballR + 2);
    if (!w.contains(ball)) return;
    final reach = ballR + size * 0.55;
    final crumble = reach + site.b * 1.6;
    final speed = vel.distance;
    if (speed < 30) return;
    var n = 0;
    for (var i = 0; i < count; i++) {
      if (state[i] != Piece.standing.index) continue;
      final dx = x[i] - ball.dx, dy = y[i] - ball.dy;
      final d2 = dx * dx + dy * dy;
      if (d2 > crumble * crumble) continue;
      final r1 = ru[i], r2 = rv[i];
      if (d2 <= reach * reach) {
        final k = 0.55 + 0.6 * r1;
        release(i, t, vel.dx * k + (r2 - 0.5) * 140, vel.dy * k * 0.5 - 90 - 200 * r2, (r1 - 0.5) * 16);
        n++;
      } else if (hash(i, t * 7.3) < 0.18) {
        release(i, t, vel.dx * 0.25 + (r2 - 0.5) * 80, -40 * r1, (r2 - 0.5) * 9);
      }
    }
    if (n > 0 && t - _lastDust > 0.08) {
      _lastDust = t;
      dust.add((ball.dx, ball.dy, 26 + math.min(30.0, n * 1.5)));
    }
  }

  /// Each connected piece of the standing wall rests on its own bottom
  /// bricks (letters above a descender line, an i's dot: all stable until
  /// struck). Computed once, from the wall as it stood.
  Uint8List? _anchor;

  Uint8List _anchors() {
    final cols = site.cols, rows = site.rows;
    final anchor = Uint8List(count);
    final comp = Int32List(cols * rows)..fillRange(0, cols * rows, -1);
    final queue = Int32List(cols * rows);
    final members = <int>[];
    var id = 0;
    for (var i = 0; i < count; i++) {
      if (state[i] != Piece.standing.index) continue;
      final b0 = site.r.bricks[i];
      final start = b0.row * cols + b0.col;
      if (comp[start] >= 0) continue;
      var head = 0, tail = 0;
      comp[start] = id;
      queue[tail++] = start;
      members.clear();
      var low = 0;
      while (head < tail) {
        final cell = queue[head++];
        members.add(cell);
        final cr = cell ~/ cols, cc = cell % cols;
        if (cr > low) low = cr;
        for (var dr = -1; dr <= 1; dr++) {
          final r = cr + dr;
          if (r < 0 || r >= rows) continue;
          for (var dc = -1; dc <= 1; dc++) {
            final c = cc + dc;
            if (c < 0 || c >= cols) continue;
            final nb = r * cols + c;
            if (comp[nb] >= 0) continue;
            final j = site.grid[nb];
            if (j < 0 || j >= count || state[j] != Piece.standing.index) continue;
            comp[nb] = id;
            queue[tail++] = nb;
          }
        }
      }
      for (final cell in members) {
        if (cell ~/ cols >= low - 1) anchor[site.grid[cell]] = 1;
      }
      id++;
    }
    return anchor;
  }

  /// Bricks no longer connected (through standing neighbours) to a brick
  /// their piece of wall rests on fall.
  void _support(double t) {
    final cols = site.cols, rows = site.rows;
    final anchor = _anchor ??= _anchors();
    final seen = Uint8List(cols * rows);
    final queue = Int32List(cols * rows);
    var head = 0, tail = 0;
    for (var i = 0; i < count; i++) {
      if (anchor[i] == 0 || state[i] != Piece.standing.index) continue;
      final b = site.r.bricks[i];
      final cell = b.row * cols + b.col;
      seen[cell] = 1;
      queue[tail++] = cell;
    }
    while (head < tail) {
      final cell = queue[head++];
      final cr = cell ~/ cols, cc = cell % cols;
      for (var dr = -1; dr <= 1; dr++) {
        final r = cr + dr;
        if (r < 0 || r >= rows) continue;
        for (var dc = -1; dc <= 1; dc++) {
          final c = cc + dc;
          if (c < 0 || c >= cols) continue;
          final nb = r * cols + c;
          if (seen[nb] == 1) continue;
          final i = site.grid[nb];
          if (i < 0 || i >= count || state[i] != Piece.standing.index) continue;
          seen[nb] = 1;
          queue[tail++] = nb;
        }
      }
    }
    for (var i = 0; i < count; i++) {
      if (state[i] != Piece.standing.index) continue;
      final b = site.r.bricks[i];
      if (seen[b.row * cols + b.col] == 1) continue;
      release(i, t, (ru[i] - 0.5) * 50, -10 * rv[i], (rv[i] - 0.5) * 6);
    }
  }

  // ── Stepping ──────────────────────────────────────────────────────────────

  void step(double t, double dt) {
    for (var i = 0; i < count; i++) {
      if (state[i] == Piece.standing.index && releaseAt[i] <= t) {
        final side = x[i] < site.wall.center.dx ? -1.0 : 1.0;
        release(i, t, side * (40 + 110 * ru[i]) + (rv[i] - 0.5) * 70, -50 * rv[i], (ru[i] - 0.5) * 10);
      }
    }
    if (_dirty) {
      _dirty = false;
      _support(t);
    }
    final g = gravity * dt;
    for (var i = 0; i < count; i++) {
      final s = state[i];
      if (s == Piece.flying.index) {
        vy[i] += g;
        vx[i] *= 1 - 0.3 * dt;
        x[i] += vx[i] * dt;
        y[i] += vy[i] * dt;
        ang[i] += va[i] * dt;
        if (x[i] < minX) {
          x[i] = minX;
          vx[i] = vx[i].abs() * 0.4;
        } else if (x[i] > maxX) {
          x[i] = maxX;
          vx[i] = -vx[i].abs() * 0.4;
        }
        final floor = BL.groundY - heapAt(x[i], size) - size / 2;
        if (y[i] >= floor && vy[i] > 0) {
          if (vy[i] > 170) {
            if (vy[i] > 420 && t - _lastDust > 0.05) {
              _lastDust = t;
              dust.add((x[i], BL.groundY - heapAt(x[i], size), 8 + 6 * ru[i]));
            }
            y[i] = floor;
            vy[i] = -vy[i] * 0.28;
            vx[i] *= 0.6;
            va[i] *= 0.5;
          } else {
            _settle(i);
          }
        }
      } else if (s == Piece.dropping.index || s == Piece.pouring.index) {
        vy[i] += g;
        x[i] += vx[i] * dt;
        y[i] += vy[i] * dt;
        ang[i] += va[i] * dt;
      }
    }
  }

  void _settle(int i) {
    final s = size;
    var px = x[i];
    // Roll a little down the heap.
    for (var k = 0; k < 6; k++) {
      final here = heapAt(px, s);
      final l = heapAt(px - s, s), r = heapAt(px + s, s);
      if (l < here - s * 0.55 && l <= r) {
        px -= s;
      } else if (r < here - s * 0.55) {
        px += s;
      } else {
        break;
      }
    }
    final h = heapAt(px, s);
    x[i] = px;
    y[i] = BL.groundY - h - s / 2 + s * 0.12;
    const q = math.pi / 2;
    ang[i] = (ang[i] / q).roundToDouble() * q + (ru[i] - 0.5) * 0.5;
    vx[i] = 0;
    vy[i] = 0;
    va[i] = 0;
    state[i] = Piece.resting.index;
    _addHeap(px, s * 0.8, h + s * 0.3);
    _rest++;
  }

  int get resting => _rest;

  // ── Cleanup ───────────────────────────────────────────────────────────────

  /// The bulldozer's blade (moving left) catches pieces at or right of
  /// [bladeX] and carries them as a mound in front of it.
  void push(double bladeX, double t) {
    for (var i = 0; i < count; i++) {
      final s = state[i];
      if ((s == Piece.resting.index || (s == Piece.flying.index && y[i] > BL.groundY - 40)) &&
          x[i] >= bladeX - size * 0.5) {
        state[i] = Piece.pushed.index;
        since[i] = t;
        fromX[i] = x[i];
        fromY[i] = y[i];
      }
    }
  }

  /// Pushed pieces ride in the mound before the blade; scooped ones in the
  /// bucket (each easing into its place).
  void follow(double t, double bladeX, Offset bucket) {
    for (var i = 0; i < count; i++) {
      final s = state[i];
      Offset to;
      double ease;
      if (s == Piece.pushed.index) {
        final slot = moundSlot(i);
        to = Offset(bladeX + slot.dx, BL.groundY + slot.dy);
        ease = 0.25;
      } else if (s == Piece.bucket.index) {
        to = bucket + bucketSlot(i);
        ease = 0.3;
      } else {
        continue;
      }
      final f = eio(seg(t, since[i], since[i] + ease));
      x[i] = fromX[i] + (to.dx - fromX[i]) * f;
      y[i] = fromY[i] + (to.dy - fromY[i]) * f;
    }
  }

  /// Everything left on the ground goes into the bucket.
  void scoop(double t) {
    for (var i = 0; i < count; i++) {
      final s = state[i];
      if (s == Piece.pushed.index || s == Piece.resting.index || s == Piece.flying.index) {
        fromX[i] = x[i];
        fromY[i] = y[i];
        state[i] = Piece.bucket.index;
        since[i] = t;
      }
    }
  }

  /// The bucket tips: pieces fall towards the truck's bed.
  void dump(double t, Offset from) {
    for (var i = 0; i < count; i++) {
      if (state[i] != Piece.bucket.index) continue;
      state[i] = Piece.dropping.index;
      since[i] = t;
      x[i] = from.dx + (ru[i] - 0.5) * 22;
      y[i] = from.dy + (rv[i] - 0.5) * 8;
      vx[i] = -30 + (ru[i] - 0.5) * 70;
      vy[i] = -40 * rv[i];
      va[i] = (ru[i] - 0.5) * 8;
    }
  }

  /// Pieces dropping into the bed land on the load.
  void land(double t, BedFrame bed) {
    for (var i = 0; i < count; i++) {
      if (state[i] != Piece.dropping.index) continue;
      final slot = bed.world(t, bedX(i), bedY(i));
      if (y[i] >= slot.dy && vy[i] > 0) {
        state[i] = Piece.truck.index;
        since[i] = t;
      }
    }
  }

  /// Pours the load out over [from]..[to] (rear of the bed first).
  void pour(double t, double from, double to, BedFrame bed) {
    final f = seg(t, from, to);
    final lip = bed.lip(t);
    for (var i = 0; i < count; i++) {
      final s = state[i];
      if (s == Piece.truck.index && ru[i] * 0.92 <= f) {
        state[i] = Piece.pouring.index;
        since[i] = t;
        x[i] = lip.dx + (rv[i] - 0.5) * 6;
        y[i] = lip.dy - 4 * rv[i];
        vx[i] = -40 - 50 * rv[i];
        vy[i] = 10 + 30 * ru[i];
        va[i] = (rv[i] - 0.5) * 10;
      } else if (s == Piece.pouring.index && t - since[i] > 0.75) {
        state[i] = Piece.gone.index;
      }
    }
  }

  /// Bed coordinates of piece [i]'s place in the load (a heap that rises
  /// above the bed's sides).
  double bedX(int i) => 6 + ru[i] * 104;
  double bedY(int i) {
    final fill = c01(count / 700);
    final h = 30 + (6 + 22 * fill) * (0.25 + 0.75 * bump(0.06 + ru[i] * 0.88));
    return h * math.pow(rv[i], 0.45);
  }

  /// Mound in front of the blade (offset from the blade's foot).
  Offset moundSlot(int i) {
    final w = (36 + 0.05 * count).clamp(36.0, 104.0);
    final h = (12 + 0.028 * count).clamp(12.0, 44.0);
    final u = ru[i], v = rv[i];
    return Offset(-(3 + u * w), -size * 0.4 - v * h * math.pow(1 - u, 0.9));
  }

  /// Heap in the bucket (offset from the bucket's floor centre).
  Offset bucketSlot(int i) {
    final u = ru[i], v = rv[i];
    return Offset((u - 0.5) * 24, -2 - v * (6 + 10 * bump(u)));
  }

  bool get anyLeft {
    for (var i = 0; i < count; i++) {
      if (state[i] != Piece.gone.index) return true;
    }
    return false;
  }
}
