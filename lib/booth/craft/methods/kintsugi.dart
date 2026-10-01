import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../../../worlds/factory/factory_kit.dart';
import '../geometry.dart';
import '../method.dart';
import '../stage.dart';

/// 金継ぎ · Kintsugi: the letter is white porcelain, broken along a few
/// jagged cracks into pieces that lie scattered apart. Two workers on lifts
/// push the pieces back together, one by one (bottom first); then a
/// craftsperson paints every crack with gold lacquer, the brush running
/// along the seams while the gold glints.
class KintsugiCraft extends CraftMethod {
  const KintsugiCraft();

  @override
  String get id => 'kintsugi';

  @override
  String get en => 'Kintsugi';

  @override
  String get ja => '金継ぎ';

  @override
  Color get color => Mat.gold;

  @override
  double get weight => 1.05;

  static final _repairs = Expando<_Repair>();
  static final _seams = Expando<_Seams>();

  static _Seams _seamsOf(GlyphStage s, int seed) => _seams[s] ??= _Seams(s, seed);
  static _Repair _repair(CraftContext x) =>
      _repairs[x.s] ??= _Repair(x.s, _seamsOf(x.s, x.seed), x.seed);

  // Timeline (fractions of p).
  static const _joinStart = 0.03, _joinEnd = 0.46;
  static const _paintStart = 0.5, _paintEnd = 0.93;

  @override
  void paintMaking(CraftContext x, double p) {
    final s = x.s;
    if (s.contours.isEmpty) return;
    final r = _repair(x);
    final seams = r.seams;
    final c = x.c;
    p = p.clamp(0.0, 1.0);

    if (p < _joinEnd) {
      _pieces(x, r, p);
    } else {
      c.drawPath(s.outline, seams.porcelain);
      c.drawPath(s.outline, x.st(_cobalt, 2.2));
      // Hairline cracks, then gold over them as the brush passes.
      c.drawPath(seams.path, x.st(_crack, 1.4));
      final q = seg(p, _paintStart, _paintEnd);
      if (q > 0) {
        final (gold, tip, lifted) = r.painted(q);
        c.drawPath(gold, x.st(_goldDark, 5.2));
        c.drawPath(gold, x.st(_goldLight, 2));
        _glints(x, r, q, p);
        if (p < _paintEnd + 0.03) _painter(x, tip, lifted && q < 1, p);
      }
    }
    _helpers(x, r, p);
  }

  @override
  void paintFinished(CraftContext x) {
    final s = x.s, c = x.c;
    if (s.contours.isEmpty) return;
    final seams = _seamsOf(s, x.seed);
    c.drawPath(s.outline, seams.porcelain);
    c.drawPath(s.outline, x.st(_cobalt, 2.2));
    c.drawPath(seams.path, x.st(_goldDark, 5.2));
    c.drawPath(seams.path, x.st(_goldLight, 2));
  }

  /// The pieces: each clipped out of the glyph by its crack bands and drawn
  /// where it is (scattered, sliding home, or home).
  void _pieces(CraftContext x, _Repair r, double p) {
    final s = x.s, c = x.c;
    final seams = r.seams;
    // The shards fade in as the job starts.
    final appear = seg(p, 0, 0.03);
    if (appear < 1) c.saveLayer(s.ink.inflate(80), Paint()..color = Color.fromRGBO(0, 0, 0, appear));
    for (final pc in r.pieces) {
      final f = r.homeFrac(pc, p);
      final off = pc.offset * (1 - f);
      final ang = pc.angle * (1 - f);
      c.save();
      c.translate(pc.pivot.dx + off.dx, pc.pivot.dy + off.dy);
      c.rotate(ang);
      c.translate(-pc.pivot.dx, -pc.pivot.dy);
      c.clipPath(seams.vBands[pc.i]);
      c.clipPath(seams.hBands[pc.j]);
      c.drawPath(s.outline, seams.porcelain);
      c.drawPath(s.outline, x.st(_cobalt, 2.2));
      if (f >= 1) c.drawPath(seams.path, x.st(_crack, 1.4));
      c.restore();
      // A little "click" when it seats.
      final k = (p - pc.end) / 0.02;
      if (k > 0 && k < 1) {
        c.drawCircle(pc.centroid, 10 + 26 * eo(k), x.st(_goldLight.withValues(alpha: 1 - k), 2));
      }
    }
    if (appear < 1) c.restore();
  }

  /// Gold glints twinkling along the painted seams (settling at the end).
  void _glints(CraftContext x, _Repair r, double q, double p) {
    final seams = r.seams;
    final fade = 1 - seg(p, 0.96, 0.995);
    if (fade <= 0) return;
    for (var i = 0; i < seams.glints.length; i++) {
      final (pt, at) = seams.glints[i];
      if (at > q) continue;
      final tw = math.sin(x.t * 3.1 + i * 2.3);
      if (tw < 0.35) continue;
      x.ink.star(pt, (3 + 6 * (tw - 0.35)) * fade, _goldLight);
    }
  }

  /// The lacquer painter on a lift, brush on the seam.
  void _painter(CraftContext x, Offset tip, bool lifted, double p) {
    final c = x.c;
    final standX = (tip.dx + 40).clamp(700.0, 1470.0);
    final brushTip = tip - Offset(0, lifted ? 10 : 0);
    final platform = x.liftFor(brushTip.dy - 20);
    x.lift(standX, platform, w: 46);
    final feet = Offset(standX, platform - 4);
    final shoulder = feet + const Offset(0, -39);
    // The artisan: no hard hat, a headband (hachimaki) with its ends
    // fluttering behind.
    final v = shoulder + (brushTip - shoulder) * 0.6 - shoulder;
    final a = math.atan2(-v.dx, v.dy).clamp(-0.3, 3.0);
    final limbs = x.ink.worker(feet, 50, -1, Pose()..point(a), helmet: false);
    final head = limbs.head;
    c.drawLine(head + const Offset(-6.5, -2.5), head + const Offset(6.5, -2.5), x.st(_band, 2.2));
    final flap = math.sin(x.t * 8) * 1.5;
    c.drawLine(head + const Offset(6, -2.5), head + Offset(12, -5 + flap), x.st(_band, 1.6));
    c.drawLine(head + const Offset(6, -2), head + Offset(11, 1 + flap), x.st(_band, 1.6));
    final d = brushTip - limbs.handA;
    final u = d / math.max(1, d.distance);
    c.drawLine(limbs.handA - u * 4, brushTip - u * 5, x.st(_lacquer, 2.4));
    c.drawLine(brushTip - u * 6, brushTip, x.st(_goldLight, 3));
    if (!lifted) {
      x.glow(brushTip, 10, _goldLight, alpha: 0.5);
      x.sparks(brushTip, n: 4, color: _goldLight, size: 0.35, salt: 9);
    }
    // A small pot of gold on the deck.
    final pot = Rect.fromLTWH(standX + 8, platform - 12, 10, 8);
    c.drawRect(pot, x.fl(_lacquer));
    c.drawLine(pot.topLeft, pot.topRight, x.st(_goldLight, 2));
  }

  /// The two workers bringing the pieces together (and resting after).
  void _helpers(CraftContext x, _Repair r, double p) {
    for (var side = 0; side < 2; side++) {
      final dir = side == 0 ? 1 : -1;
      final hat = side == 0 ? BP.amber : BP.coral;
      final (stand, hand, pushing) = r.helperAt(x, side, p);
      if (p < _joinEnd + 0.02) {
        x.lift(stand.dx, stand.dy, w: 46);
        final l = x.reach(Offset(stand.dx, stand.dy - 4), hand, both: true, dir: dir, hat: hat);
        if (pushing) x.ink.sweat(l.head, x.t, dir);
        continue;
      }
      // Done: back on the floor with a cup of tea, cheering at the end.
      final feet = Offset(side == 0 ? r.homeX[0] : r.homeX[1], x.floorY);
      final pose = Pose();
      if (p > _paintEnd) {
        pose.cheer(x.t, side);
      } else {
        pose.upA = 1.5;
      }
      final l = x.worker(feet, dir: dir, pose: pose, hat: hat);
      if (p <= _paintEnd) x.ink.coffee(l.handA, x.t + side);
    }
  }
}

// Porcelain and lacquer colours.
const _porcelainHi = Color(0xFFFDFEFF);
const _porcelainLo = Color(0xFFCBD5E0);
const _cobalt = Color(0xFF3F6FC6);
const _crack = Color(0xFF7F8B99);
const _goldDark = Color(0xFFD4952F);
const _goldLight = Color(0xFFFFE28A);
const _lacquer = Color(0xFF3A1F1A);
const _band = Color(0xFFE8E2D4);

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

/// The cracks (jagged lines across the glyph), the bands between them, and
/// the gold seams: the cracks' runs inside the glyph. Also the porcelain
/// paint. Cheap enough for [KintsugiCraft.paintFinished].
class _Seams {
  _Seams(GlyphStage s, int seed) {
    final ink = s.ink;
    final rng = math.Random(seed ^ 0x6a1d);
    porcelain = Paint()
      ..shader = ui.Gradient.linear(
        ink.topLeft,
        ink.bottomRight,
        const [_porcelainHi, Color(0xFFEAF0F5), _porcelainLo],
        const [0.0, 0.55, 1.0],
      );
    var cols = (ink.width / 150).round().clamp(1, 3);
    var rows = (ink.height / 150).round().clamp(1, 3);
    if (cols * rows == 1) {
      ink.width > ink.height ? cols = 2 : rows = 2;
    }
    const ext = 40.0;
    final top = ink.top - ext, bottom = ink.bottom + ext;
    final left = ink.left - ext, right = ink.right + ext;
    // Vertical cracks: jagged, a little slanted.
    for (var i = 1; i < cols; i++) {
      final cw = ink.width / cols;
      final x0 = ink.left + cw * i + (rng.nextDouble() - 0.5) * cw * 0.5;
      final x1 = ink.left + cw * i + (rng.nextDouble() - 0.5) * cw * 0.5;
      vCracks.add(_jagged(Offset(x0, top), Offset(x1, bottom), rng));
    }
    for (var j = 1; j < rows; j++) {
      final ch = ink.height / rows;
      final y0 = ink.top + ch * j + (rng.nextDouble() - 0.5) * ch * 0.5;
      final y1 = ink.top + ch * j + (rng.nextDouble() - 0.5) * ch * 0.5;
      hCracks.add(_jagged(Offset(left, y0), Offset(right, y1), rng));
    }
    // Bands between consecutive cracks (the outer ones reach far out).
    final farL = [Offset(left - 400, top), Offset(left - 400, bottom)];
    final farR = [Offset(right + 400, top), Offset(right + 400, bottom)];
    final vs = [farL, ...vCracks, farR];
    for (var i = 0; i + 1 < vs.length; i++) {
      vBands.add(Path()..addPolygon([...vs[i], ...vs[i + 1].reversed], true));
    }
    final farT = [Offset(left, top - 400), Offset(right, top - 400)];
    final farB = [Offset(left, bottom + 400), Offset(right, bottom + 400)];
    final hs = [farT, ...hCracks, farB];
    for (var j = 0; j + 1 < hs.length; j++) {
      hBands.add(Path()..addPolygon([...hs[j], ...hs[j + 1].reversed], true));
    }

    // Hairline branches off the main cracks (gilded too, but not breaks).
    final branches = <List<Offset>>[];
    for (final crack in [...vCracks, ...hCracks]) {
      final k = 3 + rng.nextInt(math.max(1, crack.length - 6));
      final from = crack[k];
      final along = crack[k + 1] - crack[k - 1];
      final a = math.atan2(along.dy, along.dx) + (rng.nextBool() ? 1 : -1) * (0.5 + 0.5 * rng.nextDouble());
      final len = 34 + 40 * rng.nextDouble();
      branches.add(_jagged(from, from + Offset(math.cos(a), math.sin(a)) * len, rng, n: 5, amp: 6));
    }

    // Seams: the cracks' runs inside the glyph (resampled every 1.5 px).
    final inside = _Inside(s);
    for (final crack in [...vCracks, ...hCracks, ...branches]) {
      var run = <Offset>[];
      void flush() {
        if (run.length >= 3) runs.add(run);
        run = <Offset>[];
      }

      for (var k = 1; k < crack.length; k++) {
        final a = crack[k - 1], b = crack[k];
        final n = math.max(1, ((b - a).distance / 1.5).ceil());
        for (var m = 0; m < n; m++) {
          final pt = Offset.lerp(a, b, m / n)!;
          if (inside(pt)) {
            run.add(pt);
          } else {
            flush();
          }
        }
      }
      flush();
    }
    for (final run in runs) {
      path.moveTo(run.first.dx, run.first.dy);
      for (final pt in run.skip(1)) {
        path.lineTo(pt.dx, pt.dy);
      }
    }
  }

  late final Paint porcelain;
  final vCracks = <List<Offset>>[];
  final hCracks = <List<Offset>>[];
  final vBands = <Path>[];
  final hBands = <Path>[];

  /// Inside runs of the cracks (polylines), and all of them as one path.
  final runs = <List<Offset>>[];
  final path = Path();

  /// Glint spots along the seams: (point, painting progress it's reached).
  final glints = <(Offset, double)>[];

  /// A crack from [a] to [b]: a sideways random walk with uneven steps.
  static List<Offset> _jagged(Offset a, Offset b, math.Random rng, {int n = 14, double amp = 16}) {
    final d = b - a;
    final nrm = Offset(-d.dy, d.dx) / d.distance;
    var off = 0.0;
    final pts = <Offset>[a];
    for (var k = 1; k < n; k++) {
      off = (off + (rng.nextDouble() - 0.5) * amp).clamp(-amp, amp);
      pts.add(a + d * ((k + (rng.nextDouble() - 0.5) * 0.5) / n) + nrm * off);
    }
    return pts..add(b);
  }
}

class _Piece {
  _Piece(this.i, this.j, this.centroid, this.bounds);

  final int i;
  final int j;
  final Offset centroid;
  final Rect bounds;

  /// Where it lies scattered (relative to home) and how it's tilted.
  Offset offset = Offset.zero;
  double angle = 0;
  Offset pivot = Offset.zero;

  /// When it's pushed home: worker arrives at [start], piece seated at [end].
  double start = 0;
  double end = 0;
  int side = 0;
}

/// The broken letter: its pieces, where they lie, the order they're joined
/// in, and the brush's schedule along the seams.
class _Repair {
  _Repair(GlyphStage s, this.seams, int seed) : _s = s {
    final ink = s.ink;
    final rng = math.Random(seed ^ 0x917);
    final nv = seams.vBands.length, nh = seams.hBands.length;
    // Which piece is each bit of the glyph in? Sample the raster rows.
    final count = List.filled(nv * nh, 0);
    final sx = List.filled(nv * nh, 0.0), sy = List.filled(nv * nh, 0.0);
    final bounds = List<Rect?>.filled(nv * nh, null);
    for (final r in s.rows) {
      for (var px = r.left + 1; px < r.right; px += 3) {
        final pt = Offset(px, r.center.dy);
        final i = _bandOf(seams.vCracks, pt, vertical: true);
        final j = _bandOf(seams.hCracks, pt, vertical: false);
        final k = j * nv + i;
        count[k]++;
        sx[k] += pt.dx;
        sy[k] += pt.dy;
        final b = Rect.fromLTRB(px - 1.5, r.top, px + 1.5, r.bottom);
        bounds[k] = bounds[k]?.expandToInclude(b) ?? b;
      }
    }
    final centre = ink.center;
    for (var j = 0; j < nh; j++) {
      for (var i = 0; i < nv; i++) {
        final k = j * nv + i;
        if (count[k] == 0) continue;
        final pc = _Piece(i, j, Offset(sx[k] / count[k], sy[k] / count[k]), bounds[k]!);
        final v = pc.centroid - centre;
        final dir = v.distance < 1 ? const Offset(0, -1) : v / v.distance;
        final onFloor = pc.bounds.bottom >= ink.bottom - 4;
        if (onFloor) {
          final sgn = dir.dx.abs() < 0.2 ? (rng.nextBool() ? 1.0 : -1.0) : dir.dx.sign;
          pc
            ..offset = Offset(_keepIn(pc.bounds, sgn * (16 + 18 * rng.nextDouble())), 0)
            ..angle = sgn * (0.04 + 0.06 * rng.nextDouble())
            ..pivot = Offset(pc.centroid.dx, pc.bounds.bottom);
        } else {
          final o = dir * (26 + 22 * rng.nextDouble()) + const Offset(0, -6);
          pc
            // Not up into the name sign, nor out of the hall.
            ..offset = Offset(
              _keepIn(pc.bounds, o.dx),
              math.max(o.dy, 342 - pc.bounds.top),
            )
            ..angle = (rng.nextDouble() - 0.5) * 0.36
            ..pivot = pc.centroid;
        }
        pc.side = pc.centroid.dx < centre.dx ? 0 : 1;
        pieces.add(pc);
      }
    }
    // Joined bottom first, outer pieces before inner ones at each height.
    final order = [...pieces]
      ..sort((a, b) {
        final c = b.bounds.bottom.compareTo(a.bounds.bottom);
        if (c.abs() > 0 && (a.bounds.bottom - b.bounds.bottom).abs() > 8) return c;
        return (b.centroid.dx - centre.dx).abs().compareTo((a.centroid.dx - centre.dx).abs());
      });
    final n = math.max(1, order.length);
    for (var k = 0; k < order.length; k++) {
      final span = (KintsugiCraft._joinEnd - 0.03 - KintsugiCraft._joinStart) / n;
      order[k]
        ..start = KintsugiCraft._joinStart + span * k
        ..end = KintsugiCraft._joinStart + span * (k + 1);
    }
    _order = order;
    homeX = [
      math.max(780.0, ink.left - 40),
      math.min(1460.0, ink.right + 40),
    ];

    // Brush schedule: each seam run in turn (sorted top-down, then left to
    // right), moving between them with the brush lifted.
    final rs = [...seams.runs]
      ..sort((a, b) {
        final c = (a.first.dy / 40).floor().compareTo((b.first.dy / 40).floor());
        return c != 0 ? c : a.first.dx.compareTo(b.first.dx);
      });
    var t = 0.0;
    Offset? last;
    for (final run in rs) {
      final path = Path()..moveTo(run.first.dx, run.first.dy);
      for (final pt in run.skip(1)) {
        path.lineTo(pt.dx, pt.dy);
      }
      final m = path.computeMetrics().firstOrNull;
      if (m == null) continue;
      final move = last == null ? 20.0 : math.min(90.0, (run.first - last).distance) * 0.6 + 8;
      _runs.add((m, t, t + move));
      t += move + m.length;
      last = run.last;
    }
    _total = math.max(1, t);
    // Glints every ~70 px along the seams.
    for (final (m, _, paintStart) in _runs) {
      for (var d = 20.0; d < m.length; d += 70) {
        final tan = m.getTangentForOffset(d);
        if (tan != null) seams.glints.add((tan.position, (paintStart + d) / _total));
      }
    }
  }

  final GlyphStage _s;
  final _Seams seams;
  final pieces = <_Piece>[];
  late final List<_Piece> _order;
  late final List<double> homeX;

  /// Per seam run: its metric, when the brush starts moving to it, and when
  /// it starts painting it (schedule units).
  final _runs = <(ui.PathMetric, double, double)>[];
  late final double _total;

  /// A sideways shift [dx] for a piece with [b] bounds that keeps it (and
  /// the worker pushing it) clear of the craft's sign and the hall's column.
  static double _keepIn(Rect b, double dx) => math.min(math.max(dx, 800 - b.left), 1440 - b.right);

  static int _bandOf(List<List<Offset>> cracks, Offset pt, {required bool vertical}) {
    var n = 0;
    for (final cr in cracks) {
      final v = vertical ? pt.dy : pt.dx;
      // The crack's coordinate across (x for vertical cracks) at [v].
      var across = vertical ? cr.first.dx : cr.first.dy;
      for (var k = 1; k < cr.length; k++) {
        final a = cr[k - 1], b = cr[k];
        final a0 = vertical ? a.dy : a.dx, b0 = vertical ? b.dy : b.dx;
        if ((v - a0) * (v - b0) <= 0 && a0 != b0) {
          final f = (v - a0) / (b0 - a0);
          across = vertical ? lerp(a.dx, b.dx, f) : lerp(a.dy, b.dy, f);
          break;
        }
      }
      if ((vertical ? pt.dx : pt.dy) > across) n++;
    }
    return n;
  }

  /// How far piece [pc] is home at [p] (0 scattered, 1 seated).
  double homeFrac(_Piece pc, double p) {
    final dur = pc.end - pc.start;
    return eio(seg(p, pc.start + dur * 0.35, pc.end));
  }

  /// Helper [side]'s lift position (x, platform), hand target, and whether
  /// they're pushing right now.
  (Offset, Offset, bool) helperAt(CraftContext x, int side, double p) {
    final mine = [for (final pc in _order) if (pc.side == side) pc];
    final dir = side == 0 ? 1.0 : -1.0;
    final home = Offset(homeX[side], x.floorY - 18);
    if (mine.isEmpty) return (home, home + Offset(dir * 20, -40), false);
    Offset standFor(_Piece pc, double f) {
      final off = pc.offset * (1 - f);
      final edgeX = (side == 0 ? pc.bounds.left : pc.bounds.right) + off.dx;
      final y = pc.centroid.dy + off.dy;
      return Offset(edgeX - dir * 22, x.liftFor(y));
    }

    Offset handFor(_Piece pc, double f) {
      final off = pc.offset * (1 - f);
      final edgeX = (side == 0 ? pc.bounds.left : pc.bounds.right) + off.dx;
      return Offset(edgeX + dir * 2, pc.centroid.dy + off.dy);
    }

    var k = 0;
    while (k < mine.length - 1 && mine[k].end <= p) {
      k++;
    }
    final pc = mine[k];
    final f = homeFrac(pc, p);
    if (p < pc.start) {
      // Waiting (or gliding over from the last one).
      final from = k == 0 ? home : standFor(mine[k - 1], 1);
      final fromHand = k == 0 ? home + Offset(dir * 20, -40) : handFor(mine[k - 1], 1);
      return (from, fromHand, false);
    }
    final dur = pc.end - pc.start;
    final glide = eio(seg(p, pc.start, pc.start + dur * 0.35));
    final from = k == 0 ? home : standFor(mine[k - 1], 1);
    final stand = Offset.lerp(from, standFor(pc, f), glide)!;
    return (stand, handFor(pc, f), glide >= 1 && f < 1);
  }

  /// The gold painted at brush progress [q]: the path, the brush tip and
  /// whether the brush is lifted (moving between seams).
  (Path, Offset, bool) painted(double q) {
    final out = Path();
    final time = q * _total;
    var tip = _runs.isEmpty ? _s.ink.center : _runs.first.$1.getTangentForOffset(0)!.position;
    var lifted = true;
    for (var i = 0; i < _runs.length; i++) {
      final (m, moveAt, paintAt) = _runs[i];
      if (time < moveAt) break;
      if (time < paintAt) {
        // Moving over from the previous run's end.
        final from = i == 0 ? tip : _runs[i - 1].$1.getTangentForOffset(_runs[i - 1].$1.length)!.position;
        final to = m.getTangentForOffset(0)!.position;
        tip = Offset.lerp(from, to, eio((time - moveAt) / math.max(1e-6, paintAt - moveAt)))!;
        lifted = true;
        break;
      }
      final d = math.min(m.length, time - paintAt);
      out.addPath(m.extractPath(0, d), Offset.zero);
      tip = m.getTangentForOffset(d)!.position;
      lifted = false;
    }
    return (out, tip, lifted);
  }
}
