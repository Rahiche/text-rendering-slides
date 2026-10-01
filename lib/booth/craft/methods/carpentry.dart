import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../../../worlds/factory/factory_kit.dart';
import '../method.dart';
import '../stage.dart';
import '../workshop_layout.dart';

/// 木工 · Carpentry: slanted planks are laid over the glyph one by one from
/// the bottom; a carpenter runs a jigsaw along each board, the offcuts
/// outside the letter drop away (sawdust piling up), then nails it down.
/// Finally the letter is sanded (rough boards turn smooth and varnished)
/// and the sawdust swept up. Finished: a wooden letter with plank seams,
/// grain lines and nail heads.
class CarpentryCraft extends CraftMethod {
  const CarpentryCraft();

  @override
  String get id => 'carpentry';

  @override
  String get en => 'Carpentry';

  @override
  String get ja => '木工';

  @override
  Color get color => Mat.wood;

  @override
  double get weight => 1.0;

  static final _woods = Expando<_Wood>();
  static final _rawPics = Expando<ui.Picture>();
  static final _pics = Expando<ui.Picture>();

  _Wood _wood(CraftContext x) => _woods[x.s] ??= _Wood(x.s, x.seed);

  static const _tones = [
    Color(0xFFC8955C),
    Color(0xFFD6A56B),
    Color(0xFFB9854E),
    Color(0xFFCF9C60),
    Color(0xFFDDAE76),
  ];
  static const _pale = Color(0xFFEAD7B5);
  static const _seam = Color(0xFF6B4A2B);
  static const _nail = Color(0xFF4D5863);

  static Color _rawTone(int i) => Color.lerp(_tones[i], _pale, 0.38)!;

  // ── The letter (raw, or sanded and varnished) ─────────────────────────────

  ui.Picture _picture(CraftContext x, {required bool sanded}) {
    final cache = sanded ? _pics : _rawPics;
    return cache[x.s] ??= () {
      final rec = ui.PictureRecorder();
      _letter(Canvas(rec), x.s, _wood(x), sanded: sanded);
      return rec.endRecording();
    }();
  }

  void _letter(Canvas c, GlyphStage s, _Wood w, {required bool sanded}) {
    c.save();
    c.clipPath(s.outline);
    final fills = [for (final _ in _tones) Path()];
    final grain = Path(), seams = Path(), shine = Path();
    for (final pl in w.planks) {
      fills[pl.tone].addPath(w.board(pl, pl.u0, pl.u1), Offset.zero);
      grain.addPath(pl.grain, Offset.zero);
      seams
        ..moveTo(w.at(pl.u0, pl.va).dx, w.at(pl.u0, pl.va).dy)
        ..lineTo(w.at(pl.u1, pl.va).dx, w.at(pl.u1, pl.va).dy);
      shine
        ..moveTo(w.at(pl.u0, pl.va + 3).dx, w.at(pl.u0, pl.va + 3).dy)
        ..lineTo(w.at(pl.u1, pl.va + 3).dx, w.at(pl.u1, pl.va + 3).dy);
    }
    for (var i = 0; i < _tones.length; i++) {
      c.drawPath(fills[i], Paint()..color = sanded ? _tones[i] : _rawTone(i));
    }
    c.drawPath(grain, _grainPaint(sanded));
    if (sanded) c.drawPath(shine, _shinePaint);
    c.drawPath(seams, _seamPaint);
    c.restore();
    c.drawPath(s.outline, _edgePaint);
    final heads = Path(), glints = Path();
    for (final pl in w.planks) {
      for (final n in pl.nails) {
        _nailHead(n, heads, glints);
      }
    }
    c.drawPath(heads, Paint()..color = _nail);
    c.drawPath(glints, Paint()..color = const Color(0xFFB9C4CE));
  }

  static void _nailHead(Offset n, Path heads, Path glints) {
    heads.addOval(Rect.fromCircle(center: n, radius: 2.8));
    glints.addOval(Rect.fromCircle(center: n - const Offset(0.8, 0.8), radius: 1));
  }

  static Paint _grainPaint(bool sanded) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.1
    ..color = (sanded ? Mat.woodDark : const Color(0xFFA88158)).withValues(alpha: 0.55);
  static final _seamPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.8
    ..color = _seam;
  static final _shinePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..color = const Color(0x40FFFFFF);
  static final _edgePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeJoin = StrokeJoin.round
    ..color = _seam;

  @override
  void paintFinished(CraftContext x) => x.c.drawPicture(_picture(x, sanded: true));

  // ── Making ────────────────────────────────────────────────────────────────

  @override
  void paintMaking(CraftContext x, double p) {
    final s = x.s, c = x.c;
    final w = _wood(x);
    final n = w.planks.length;
    final build = seg(p, 0, 0.8);
    final sand = seg(p, 0.81, 0.96);
    c.drawPath(s.outline, x.st(BP.lineFaint, 1.2));
    _yard(x, w, build, p);
    if (n == 0) return;
    final pt = build * n;
    final i = math.min(n - 1, pt.floor());
    final f = build >= 1 ? 1.0 : pt - i;
    final done = build >= 1 ? n : i;

    if (sand >= 1) {
      c.drawPicture(_picture(x, sanded: true));
      return;
    }
    // Boards already cut and nailed: the raw letter up to the current one.
    if (done > 0) {
      c.save();
      c.clipPath(w.halfPlane(w.planks[done - 1].va));
      c.drawPicture(_picture(x, sanded: false));
      c.restore();
    }
    if (build >= 1) {
      // Sanding: the sanded letter shows where the sander has been.
      if (sand > 0) {
        c.save();
        c.clipPath(w.sanded(s, sand));
        c.drawPicture(_picture(x, sanded: true));
        c.restore();
      }
      if (sand > 0) _sander(x, w, sand);
      return;
    }
    _board(x, w, w.planks[i], f);
  }

  /// The board being worked: dropped in, sawn along (offcuts falling
  /// behind the saw), nailed.
  void _board(CraftContext x, _Wood w, _Plank pl, double f) {
    final s = x.s, c = x.c;
    final drop = 1 - eo(seg(f, 0, 0.15));
    final saw = seg(f, 0.15, 0.68);
    final cutU = lerp(pl.u0, pl.u1, saw);
    final tone = _rawTone(pl.tone);
    final raw = Paint()..color = tone;

    // Not yet cut: the whole board (with its pencil line), dropping in
    // (resting on the dais, not through it).
    c.save();
    c.clipRect(Rect.fromLTRB(BW.hall.left, BW.hall.top, BW.hall.right, x.daisY));
    c.translate(-w.n.dx * 46 * drop, -w.n.dy * 46 * drop);
    final uncut = w.board(pl, cutU, pl.u1);
    c.drawPath(uncut, raw);
    c.save();
    c.clipPath(uncut);
    c.drawPath(pl.grain, _grainPaint(false));
    c.drawPath(s.outline, x.st(_seam.withValues(alpha: 0.75), 1.2));
    c.restore();
    c.drawPath(uncut, x.st(_seam, 1.2));
    c.restore();
    if (saw <= 0) {
      _carpenter(x, w.at(pl.u0, (pl.va + pl.vb) / 2), null);
      return;
    }

    // Cut: the letter's part of the board.
    final cut = w.board(pl, pl.u0, cutU);
    c.save();
    c.clipPath(cut);
    c.clipPath(s.outline);
    c.drawPath(cut, raw);
    c.drawPath(pl.grain, _grainPaint(false));
    c.restore();
    c.save();
    c.clipPath(cut);
    c.drawPath(s.outline, _edgePaint);
    c.restore();
    // Offcuts: chunks outside the letter fall once the saw has passed.
    _offcuts(x, w, pl, cutU, f, tone);

    // Nails, one per hammer blow.
    final nf = seg(f, 0.7, 1);
    final shown = (nf * pl.nails.length).floor();
    final heads = Path(), glints = Path();
    for (var k = 0; k < shown; k++) {
      _nailHead(pl.nails[k], heads, glints);
    }
    c.drawPath(heads, x.fl(_nail));
    c.drawPath(glints, x.fl(const Color(0xFFB9C4CE)));

    if (f < 0.7) {
      final at = w.at(cutU, (pl.va + pl.vb) / 2);
      _carpenter(x, at, (limbs) => _jigsaw(x, limbs, at));
      x.sparks(at + Offset(0, (pl.vb - pl.va) / 2), n: 7, color: _pale, size: 0.7, salt: 5);
    } else if (pl.nails.isNotEmpty) {
      final k = math.min(pl.nails.length - 1, shown);
      final nail = pl.nails[k];
      final blow = (nf * pl.nails.length) % 1;
      _carpenter(x, nail, (limbs) => _hammer(x, limbs, nail, blow));
    }
  }

  void _offcuts(CraftContext x, _Wood w, _Plank pl, double cutU, double f, Color tone) {
    final c = x.c;
    const chunk = 42.0;
    final sawStart = 0.15, sawLen = 0.53;
    for (var u = pl.u0; u < cutU; u += chunk) {
      final u1 = math.min(cutU, u + chunk);
      // When the saw passed this chunk's far end.
      final passed = sawStart + sawLen * ((u1 - pl.u0) / math.max(1, pl.u1 - pl.u0));
      final age = (f - passed) / 0.12;
      if (age >= 1) continue;
      final fall = age <= 0 ? 0.0 : 90 * age * age;
      final spin = age <= 0 ? 0.0 : 0.5 * age * (rnd(x.seed, u.round(), 3) - 0.5);
      final a = 1 - c01(age);
      final piece = w.board(pl, u, u1);
      final mid = w.at((u + u1) / 2, (pl.va + pl.vb) / 2);
      c.save();
      // They drop behind the dais (into the scrap bin).
      c.clipRect(Rect.fromLTRB(BW.hall.left, BW.hall.top, BW.hall.right, x.daisY));
      c.translate(mid.dx, mid.dy + fall);
      c.rotate(spin);
      c.translate(-mid.dx, -mid.dy);
      c.clipPath(piece);
      c.clipPath(w.complement);
      c.drawPath(piece, Paint()..color = tone.withValues(alpha: a));
      c.drawPath(piece, x.st(_seam.withValues(alpha: a), 1.2));
      c.restore();
    }
  }

  /// The carpenter, on a lift when the work is high, standing beside
  /// [work] on the side nearer the letter's edge.
  void _carpenter(CraftContext x, Offset work, void Function(Limbs limbs)? tool) {
    final s = x.s;
    final leftHalf = work.dx < s.ink.center.dx;
    final dir = leftHalf ? 1 : -1;
    final standX = work.dx - dir * 40;
    final platform = x.liftFor(work.dy - 4);
    Offset feet;
    if (platform < x.floorY - 26) {
      x.lift(standX, platform, w: 50);
      feet = Offset(standX, platform - 4);
    } else {
      final onDais = standX > BW.dais.left + 6 && standX < BW.dais.right - 6;
      feet = Offset(standX, onDais ? x.daisY : x.floorY);
    }
    final limbs = x.reach(feet, work, dir: dir, both: true);
    tool?.call(limbs);
  }

  /// A jigsaw cutting at [at]: body in the hands, blade buzzing up and down.
  void _jigsaw(CraftContext x, Limbs limbs, Offset at) {
    final c = x.c;
    final buzz = math.sin(x.t * 60) * 3.5;
    final body = Rect.fromCenter(center: at + const Offset(0, -19), width: 38, height: 17);
    c.drawLine(limbs.handA, body.topCenter + const Offset(0, -9), x.st(BP.ink, 1.4));
    c.drawLine(at + Offset(0, -12 + buzz), at + Offset(0, 13 + buzz), x.st(Mat.steel, 3));
    // Base plate on the board.
    c.drawLine(Offset(body.left + 3, body.bottom + 2), Offset(body.right - 3, body.bottom + 2), x.st(Mat.steelDark, 3));
    c.drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(5)), x.fl(BP.amber));
    c.drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(5)), x.st(const Color(0xFF8A6A2A), 1.4));
    c.drawLine(body.centerLeft + const Offset(6, 0), body.center + const Offset(6, 0), x.st(const Color(0xFF8A6A2A), 2));
    final handle = Path()
      ..moveTo(body.left + 6, body.top)
      ..quadraticBezierTo(body.center.dx, body.top - 18, body.right - 6, body.top);
    c.drawPath(handle, x.st(BP.panel, 5));
    c.drawPath(handle, x.st(const Color(0xFF8A6A2A), 1.6));
  }

  /// A claw hammer coming down on the nail at [nail] ([blow] 0 → 1 per
  /// nail: raised, then struck).
  void _hammer(CraftContext x, Limbs limbs, Offset nail, double blow) {
    final c = x.c;
    final lift = 30 * (1 - eo(seg(blow, 0.35, 0.85)));
    final head = nail + Offset(0, -9 - lift);
    final grip = limbs.handA;
    final v = head - grip;
    final l = v.distance;
    if (l < 1) return;
    final u = v / l, nrm = Offset(-u.dy, u.dx);
    c.drawLine(grip - u * 6, head, x.st(Mat.woodDark, 3.6));
    c.drawLine(head - nrm * 10, head + nrm * 9, x.st(Mat.steelDark, 8));
    c.drawLine(head - nrm * 9, head + nrm * 8, x.st(Mat.steel, 3));
    if (blow > 0.82 && blow < 0.95) x.ink.star(nail + const Offset(0, -3), 10, BP.ink);
    // The nail still standing proud before the blow.
    if (blow < 0.85) c.drawLine(nail, nail + const Offset(0, -8), x.st(Mat.steel, 2));
  }

  /// An orbital sander working in passes over the letter; dust puffs.
  void _sander(CraftContext x, _Wood w, double q) {
    final s = x.s, c = x.c;
    final (pos, _) = w.sanderAt(s, q);
    final pad = Rect.fromCenter(center: pos, width: 44, height: 24);
    final wob = math.sin(x.t * 50) * 1.2;
    c.drawRRect(RRect.fromRectAndRadius(pad.shift(Offset(wob, 0)), const Radius.circular(5)), x.fl(BP.green));
    c.drawRRect(
      RRect.fromRectAndRadius(pad.shift(Offset(wob, 0)), const Radius.circular(5)),
      x.st(const Color(0xFF2E7D5B), 1.4),
    );
    c.drawRect(Rect.fromLTRB(pad.left + 2, pad.bottom - 5, pad.right - 2, pad.bottom - 1), x.fl(_pale));
    final knob = pad.topCenter + const Offset(0, -6);
    c.drawCircle(knob, 6, x.fl(BP.panel));
    c.drawCircle(knob, 6, x.st(const Color(0xFF2E7D5B), 1.4));
    for (var k = 0; k < 3; k++) {
      x.ink.puff(pad.bottomCenter + Offset(-14.0 + 14 * k, 4), (x.t * 1.8 + k / 3) % 1, 3, 12, _pale);
    }
    _carpenter(x, knob, null);
  }

  /// A plank stack and a helper carrying the next board on the right; a
  /// sawdust pile at the letter's foot (swept up at the end).
  void _yard(CraftContext x, _Wood w, double build, double p) {
    final c = x.c, y = x.floorY;
    final left = (6 * (1 - build)).ceil();
    for (var k = 0; k < left; k++) {
      final r = Rect.fromLTWH(1400 + (k.isOdd ? 4 : 0), y - 8 - k * 7, 72, 6);
      c.drawRect(r, x.fl(_tones[k % _tones.length]));
      c.drawRect(r, x.st(_seam, 1));
    }
    if (build < 1) {
      final pose = Pose()..carry();
      final l = x.worker(Offset(1376, y), dir: -1, pose: pose, h: 46, hat: BP.coral);
      final board = Rect.fromCenter(center: l.handA + const Offset(4, -3), width: 70, height: 6);
      c.drawRect(board, x.fl(_tones[2]));
      c.drawRect(board, x.st(_seam, 1));
    }
    // Sawdust: grows with every cut, swept away while sanding.
    final pile = (build * 1.2).clamp(0.0, 1.0) * (1 - seg(p, 0.84, 0.97));
    if (pile > 0.02) {
      final base = Offset(x.s.ink.right + 26, x.daisY);
      final pw = 18 + 34 * pile, ph = 4 + 12 * pile;
      final mound = Path()
        ..moveTo(base.dx - pw / 2, base.dy)
        ..quadraticBezierTo(base.dx, base.dy - ph * 2, base.dx + pw / 2, base.dy)
        ..close();
      c.drawPath(mound, x.fl(_pale));
      c.drawPath(mound, x.st(const Color(0xFFB79A6E), 1));
    }
    if (p > 0.82 && p < 0.98) {
      final sweep = Pose()..wipe(x.t);
      final bx = x.s.ink.right + 66;
      final l = x.worker(Offset(bx, x.daisY), dir: -1, pose: sweep, h: 46, hat: BP.amber);
      x.ink.broom(l.handA, l.elbowA, x.daisY, math.sin(x.t * 5) * 6 - 8);
    }
  }
}

/// One plank: a band across the glyph between normal offsets [va] and [vb]
/// (the board running from [u0] to [u1] along it), its pieces inside the
/// letter, nails and grain.
class _Plank {
  _Plank(this.va, this.vb, this.u0, this.u1, this.tone, this.nails, this.grain);

  final double va;
  final double vb;
  final double u0;
  final double u1;
  final int tone;
  final List<Offset> nails;
  final Path grain;
}

/// The glyph cut into slanted planks (bottom first).
class _Wood {
  _Wood(GlyphStage s, int seed) {
    final ink = s.ink;
    final a = (rnd(seed, 1, 21) < 0.5 ? -1 : 1) * (0.26 + 0.12 * rnd(seed, 2, 21));
    d = Offset(math.cos(a), math.sin(a));
    n = Offset(-math.sin(a), math.cos(a));
    final corners = [ink.topLeft, ink.topRight, ink.bottomLeft, ink.bottomRight];
    final vs = [for (final p in corners) _dot(p, n)], us = [for (final p in corners) _dot(p, d)];
    final vMin = vs.reduce(math.min), vMax = vs.reduce(math.max);
    uMin = us.reduce(math.min) - 20;
    uMax = us.reduce(math.max) + 20;
    final count = ((vMax - vMin) / 36).round().clamp(5, 12);
    final width = (vMax - vMin) / count;
    vBottom = vMax;
    // The outline's edges in plank coordinates (u along, v across).
    final edges = <(double, double, double, double)>[];
    for (final c in s.geo.contours) {
      final cnt = c.count;
      for (var k = 0; k < cnt; k++) {
        final j = k + 1 == cnt ? 0 : k + 1;
        final a = s.map(c.pts[2 * k], c.pts[2 * k + 1]), b = s.map(c.pts[2 * j], c.pts[2 * j + 1]);
        edges.add((_dot(a, d), _dot(a, n), _dot(b, d), _dot(b, n)));
      }
    }
    // Inside intervals along the plank line v (even-odd over the outline).
    List<(double, double)> along(double v) {
      final us = <double>[];
      for (final (ua, va, ub, vb) in edges) {
        if ((va <= v) == (vb <= v)) continue;
        us.add(ua + (v - va) / (vb - va) * (ub - ua));
      }
      us.sort();
      return [for (var k = 0; k + 1 < us.length; k += 2) (us[k], us[k + 1])];
    }

    for (var i = 0; i < count; i++) {
      final vb = vMax - i * width, va = vb - width;
      // How far the letter reaches along the band (a few lines across it).
      var lo = double.infinity, hi = -double.infinity;
      for (final fr in const [0.02, 0.25, 0.5, 0.75, 0.98]) {
        for (final (u0, u1) in along(va + width * fr)) {
          lo = math.min(lo, u0);
          hi = math.max(hi, u1);
        }
      }
      if (hi < lo) continue;
      // Pieces along the middle of the band, a nail near each end.
      final mid = (va + vb) / 2;
      final nails = <Offset>[];
      for (final (p0, p1) in along(mid)) {
        final len = p1 - p0;
        if (len < 6) continue;
        if (len < 22) {
          nails.add(at((p0 + p1) / 2, mid));
        } else {
          nails
            ..add(at(p0 + 8, mid))
            ..add(at(p1 - 8, mid));
        }
      }
      // At most 10 nails a board (evenly picked).
      final picked = nails.length <= 10
          ? nails
          : [for (var k = 0; k < 10; k++) nails[(k * (nails.length - 1) / 9).round()]];
      // Grain: wavy lines along the board, and the odd knot.
      final grain = Path();
      for (var g = 0; g < 3; g++) {
        final v = va + width * (0.25 + 0.27 * g) + (rnd(seed, i * 7 + g, 4) - 0.5) * 3;
        final ph = rnd(seed, i * 7 + g, 5) * 6;
        final p0 = at(lo - 12, v);
        grain.moveTo(p0.dx, p0.dy);
        for (var u = lo - 12; u <= hi + 12; u += 9) {
          final q = at(u, v + math.sin(u * 0.045 + ph) * 1.7);
          grain.lineTo(q.dx, q.dy);
        }
      }
      if (hi - lo > 60) {
        final ku = lerp(lo + 20, hi - 20, rnd(seed, i, 6));
        final kc = at(ku, va + width * (0.3 + 0.4 * rnd(seed, i, 7)));
        grain.addOval(Rect.fromCenter(center: kc, width: 11, height: 6));
      }
      planks.add(
        _Plank(va, vb, lo - 12, hi + 12, (rnd(seed, i, 8) * CarpentryCraft._tones.length).floor(), picked, grain),
      );
    }
    complement = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(ink.inflate(400))
      ..addPath(s.outline, Offset.zero);
  }

  late final Offset d;
  late final Offset n;
  late final double uMin;
  late final double uMax;
  late final double vBottom;
  final planks = <_Plank>[];

  /// Everything outside the glyph (for the offcuts).
  late final Path complement;

  static double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

  /// The canvas point [u] along the planks, [v] across them.
  Offset at(double u, double v) => d * u + n * v;

  /// The board of [pl] between [u0] and [u1].
  Path board(_Plank pl, double u0, double u1) {
    final a = at(u0, pl.va), b = at(u1, pl.va), c = at(u1, pl.vb), e = at(u0, pl.vb);
    return Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy)
      ..lineTo(e.dx, e.dy)
      ..close();
  }

  /// Everything below the line v = [v] (the boards laid so far).
  Path halfPlane(double v) {
    final a = at(uMin - 50, v), b = at(uMax + 50, v);
    final c = at(uMax + 50, vBottom + 60), e = at(uMin - 50, vBottom + 60);
    return Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy)
      ..lineTo(e.dx, e.dy)
      ..close();
  }

  static const _passes = 5;

  /// The sander's pad centre at sanding progress [q] (zig-zag passes from
  /// the top), and which pass it's on.
  (Offset, int) sanderAt(GlyphStage s, double q) {
    final ink = s.ink;
    final t = q * _passes;
    final k = math.min(_passes - 1, t.floor());
    final f = t - k;
    final h = ink.height / _passes;
    final y = ink.top + h * (k + 0.5);
    final x = k.isEven ? lerp(ink.left, ink.right, f) : lerp(ink.right, ink.left, f);
    return (Offset(x, y), k);
  }

  /// Where the sander has been at progress [q].
  Path sanded(GlyphStage s, double q) {
    final ink = s.ink.inflate(4);
    final (pos, k) = sanderAt(s, q);
    final h = ink.height / _passes;
    final out = Path()..addRect(Rect.fromLTRB(ink.left, ink.top - 4, ink.right, ink.top + h * k));
    final band = Rect.fromLTRB(ink.left, ink.top + h * k, ink.right, ink.top + h * (k + 1));
    out.addRect(
      k.isEven
          ? Rect.fromLTRB(band.left, band.top, pos.dx + 22, band.bottom)
          : Rect.fromLTRB(pos.dx - 22, band.top, band.right, band.bottom),
    );
    if (q >= 1) out.addRect(ink.inflate(8));
    return out;
  }
}
