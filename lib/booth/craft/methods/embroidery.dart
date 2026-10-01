import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../../../worlds/factory/factory_kit.dart';
import '../method.dart';
import '../stage.dart';
import '../workshop_layout.dart';

/// 刺繍 · Embroidery: a patch of linen is laced into a big standing frame
/// (the letter traced on it in blue); an embroiderer on a lift works a
/// giant needle stroke by stroke in writing order, filling each stroke with
/// slanted satin stitches across it, then backstitches the outline in a
/// contrasting thread. A helper pays out thread from a giant spool. The
/// frame comes off and leaves the stitched patch.
class EmbroideryCraft extends CraftMethod {
  const EmbroideryCraft();

  @override
  String get id => 'embroidery';

  @override
  String get en => 'Embroidery';

  @override
  String get ja => '刺繍';

  @override
  Color get color => Mat.thread;

  @override
  double get weight => 1.0;

  static final _works = Expando<_Work>();
  static final _pics = Expando<ui.Picture>();

  _Work _work(CraftContext x) => _works[x.s] ??= _Work(x.s, x.seed);

  static const _linen = Color(0xFFF1E8D5);
  static const _weave = Color(0x14000000);
  static const _pen = Color(0xFF5FA8E8);

  // ── Patch and stitches ────────────────────────────────────────────────────

  void _patch(Canvas c, _Work w, {double unroll = 1}) {
    final p = w.patch;
    final r = Rect.fromLTRB(p.left, p.top, p.right, p.top + p.height * unroll);
    c.drawRect(r, Paint()..color = _linen);
    c.save();
    c.clipRect(r);
    c.drawPath(w.weave, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _weave);
    c.drawPath(w.hem, _thread(w.edge, 2));
    c.restore();
  }

  static Paint _thread(Color col, double width) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..color = col;

  /// Satin stitches of strokes [0, upto) plus the first [partial] stitches of
  /// stroke [upto], over the underlay revealed up to [frac] of the strokes.
  void _satin(Canvas c, GlyphStage s, _Work w, int upto, int partial, double frac) {
    c.save();
    c.clipPath(s.outline);
    if (upto >= w.strokes.length) {
      // All stitched: the underlay fills the whole letter (no gaps at
      // corners the strokes' brushes miss).
      c.drawPath(s.outline, Paint()..color = w.under);
    } else {
      s.paintStrokesUpTo(c, frac, Paint()..color = w.under, grow: 1.35);
    }
    final shades = [for (final _ in w.shades) Path()];
    final sheen = Path();
    for (var i = 0; i <= upto && i < w.strokes.length; i++) {
      final st = w.strokes[i];
      final n = i < upto ? st.length : math.min(partial, st.length);
      for (var j = 0; j < n; j++) {
        final (a, b) = st[j];
        shades[i % w.shades.length]
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy);
        final m = Offset.lerp(a, b, 0.5)!;
        final h = (b - a) * 0.32;
        sheen
          ..moveTo(m.dx - h.dx - 0.5, m.dy - h.dy - 0.5)
          ..lineTo(m.dx + h.dx - 0.5, m.dy + h.dy - 0.5);
      }
    }
    for (var k = 0; k < w.shades.length; k++) {
      c.drawPath(shades[k], _thread(w.shades[k], w.gap * 0.8)..strokeCap = StrokeCap.butt);
    }
    c.drawPath(sheen, _thread(const Color(0x55FFFFFF), math.max(0.8, w.gap * 0.22)));
    c.restore();
  }

  /// The first [n] backstitches of the outline.
  void _outline(Canvas c, _Work w, int n) {
    final path = Path();
    for (var k = 0; k < math.min(n, w.dashes.length); k++) {
      final (a, b) = w.dashes[k];
      path
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy);
    }
    c.drawPath(path, _thread(w.edge, w.edgeWidth));
  }

  ui.Picture _finished(CraftContext x) => _pics[x.s] ??= () {
    final s = x.s, w = _work(x);
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    _patch(c, w);
    _satin(c, s, w, w.strokes.length, 0, 1);
    _outline(c, w, w.dashes.length);
    return rec.endRecording();
  }();

  @override
  void paintFinished(CraftContext x) => x.c.drawPicture(_finished(x));

  // ── Making ────────────────────────────────────────────────────────────────

  @override
  void paintMaking(CraftContext x, double p) {
    final s = x.s, c = x.c;
    final w = _work(x);
    final frameIn = eo(seg(p, 0, 0.04));
    final unroll = eio(seg(p, 0.03, 0.09));
    final satin = seg(p, 0.1, 0.8);
    final edge = seg(p, 0.81, 0.94);
    final frameOut = eio(seg(p, 0.95, 1));

    if (p >= 1) {
      c.drawPicture(_finished(x));
      return;
    }
    if (unroll > 0) _patch(c, w, unroll: unroll);
    if (unroll < 1) {
      c.drawPath(s.outline, x.st(BP.lineFaint, 1.2));
    } else if (edge < 1) {
      // The design traced on the linen (covered by the outline stitch).
      c.drawPath(s.outline, x.st(_pen.withValues(alpha: 0.75), 1.3));
    }

    // Satin stitching, stroke by stroke.
    final at = w.at(satin);
    if (satin > 0) {
      if (satin >= 1) {
        _satin(c, s, w, w.strokes.length, 0, 1);
      } else {
        _satin(c, s, w, at.stroke, at.stitch, at.frac);
      }
    }
    // Then the outline, backstitch by backstitch.
    final dashes = (edge * w.dashes.length).floor();
    if (edge > 0) _outline(c, w, dashes);

    // The frame around the patch (and the lacing), on and off.
    final alpha = math.min(frameIn, 1 - frameOut);
    if (alpha > 0) {
      final fade = alpha < 1;
      if (fade) {
        final p = w.patch;
        c.saveLayer(
          Rect.fromLTRB(p.left - 70, math.max(306.0, p.top - 40), p.right + 70, x.floorY + 4),
          Paint()..color = Color.fromRGBO(0, 0, 0, alpha),
        );
      }
      _frame(x, w, spread: 26 * frameOut, laced: unroll >= 1 && frameOut <= 0);
      if (fade) c.restore();
    }

    // The needle: where it is, which thread it carries.
    Offset tip;
    Color thread;
    var active = true;
    if (satin > 0 && satin < 1) {
      tip = at.tip;
      thread = w.shades[at.stroke % w.shades.length];
    } else if (edge > 0 && edge < 1 && w.dashes.isNotEmpty) {
      final (a, b) = w.dashes[math.min(w.dashes.length - 1, dashes)];
      tip = (edge * w.dashes.length) % 1 < 0.5 ? a : b;
      thread = w.edge;
    } else {
      // Waiting at the first stroke, or done (parked by the frame).
      tip = satin <= 0 ? w.firstTip : Offset(w.patch.right + 4, w.patch.bottom - 24);
      thread = satin <= 0 ? w.shades.first : w.edge;
      active = false;
    }
    if (unroll >= 1 && frameOut < 1) _embroiderer(x, w, tip, thread, active: active, fade: 1 - frameOut);
  }

  /// The standing frame: two side bars down to the floor and a top roller
  /// the linen hangs from, laced to the bars; [spread] moves the bars apart
  /// as it comes off.
  void _frame(CraftContext x, _Work w, {required double spread, required bool laced}) {
    final c = x.c, p = w.patch;
    final lx = p.left - 18 - spread, rx = p.right + 18 + spread;
    final top = p.top - 10;
    for (final bx in [lx, rx]) {
      final bar = Rect.fromLTRB(bx - 5, top - 6, bx + 5, x.floorY);
      c.drawRect(bar, x.fl(Mat.wood));
      c.drawRect(bar, x.st(Mat.woodDark, 1.2));
      c.drawCircle(Offset(bx, top - 9), 6, x.fl(Mat.woodDark));
      // Feet.
      c.drawLine(Offset(bx - 14, x.floorY - 1), Offset(bx + 14, x.floorY - 1), x.st(Mat.woodDark, 4));
    }
    final roller = RRect.fromLTRBR(lx - 12, top - 5 - spread * 0.4, rx + 12, top + 5 - spread * 0.4, const Radius.circular(5));
    c.drawRRect(roller, x.fl(Mat.wood));
    c.drawRRect(roller, x.st(Mat.woodDark, 1.2));
    if (!laced) return;
    final lace = Path();
    for (final (edgeX, barX) in [(p.left + 3, lx), (p.right - 3, rx)]) {
      var y = p.top + 10;
      lace.moveTo(edgeX, y);
      var toBar = true;
      while (y < p.bottom - 14) {
        y += 11;
        lace.lineTo(toBar ? barX : edgeX, y);
        toBar = !toBar;
      }
    }
    c.drawPath(lace, x.st(BP.inkDim, 1));
  }

  /// The embroiderer (on a lift when it's high) driving the giant needle to
  /// [tip]; the thread runs from the eye back to a giant spool on the floor.
  void _embroiderer(CraftContext x, _Work w, Offset tip, Color thread, {required bool active, required double fade}) {
    final s = x.s, c = x.c;
    final leftHalf = tip.dx < s.ink.center.dx;
    final dir = leftHalf ? 1 : -1;
    // The needle comes in from above, slanted towards the worker.
    final double stab = active ? 6 * (0.5 + 0.5 * math.sin(x.t * 18)) : 10;
    // Slanted up towards the worker; flatter near the top so the worker
    // stays below the name sign.
    const len = 88.0;
    final up = math.min(0.83, math.max(0.2, (tip.dy - 8 - 338) / (len + 8)));
    final axis = Offset(-dir * math.sqrt(1 - up * up), -up);
    final point = tip + axis * stab;
    final eye = point + axis * len;
    final standX = eye.dx - dir * 18;
    final platform = x.liftFor(eye.dy + 8);
    Offset feet;
    if (platform < x.floorY - 26) {
      x.lift(standX, platform, w: 50, col: BP.pink);
      feet = Offset(standX, platform - 4);
    } else {
      final onDais = standX > BW.dais.left + 6 && standX < BW.dais.right - 6;
      feet = Offset(standX, onDais ? x.daisY : x.floorY);
    }
    final limbs = x.reach(feet, eye + axis * -8, dir: dir, both: true, hat: BP.pink);
    // Spool and the thread up to the eye.
    final spool = Offset(1430, x.floorY - 30);
    final helper = x.worker(Offset(1392, x.floorY), dir: 1, pose: Pose()..carry(), h: 46, hat: BP.amber);
    final eyeHole = eye - axis * 6;
    final threadPath = Path()
      ..moveTo(spool.dx - 6, spool.dy - 12)
      ..quadraticBezierTo((spool.dx + eyeHole.dx) / 2, math.max(spool.dy, eyeHole.dy) + 40, eyeHole.dx, eyeHole.dy);
    c.drawPath(threadPath, x.st(thread.withValues(alpha: 0.9 * fade), 1.6));
    if (active) c.drawLine(eyeHole, point, x.st(thread.withValues(alpha: 0.6), 1.2));
    _spool(x, spool, thread, active);
    c.drawLine(helper.handA, spool + const Offset(-14, -6), x.st(BP.ink, 1.2));
    // The needle.
    final nrm = Offset(-axis.dy, axis.dx);
    final shaft = Path()
      ..moveTo(point.dx, point.dy)
      ..lineTo(eye.dx + nrm.dx * 4.2, eye.dy + nrm.dy * 4.2)
      ..quadraticBezierTo(eye.dx + axis.dx * 8, eye.dy + axis.dy * 8, eye.dx - nrm.dx * 4.2, eye.dy - nrm.dy * 4.2)
      ..close();
    c.drawPath(shaft, x.fl(Mat.porcelain));
    c.drawPath(shaft, x.st(Mat.steelDark, 1.2));
    c.drawLine(eyeHole - axis * 3.5, eyeHole + axis * 3.5, x.st(Mat.steelDark, 2));
    c.drawLine(limbs.handA, eye - axis * 4, x.st(BP.ink, 1.2));
  }

  void _spool(CraftContext x, Offset o, Color thread, bool turning) {
    final c = x.c;
    final body = Rect.fromCenter(center: o, width: 34, height: 40);
    c.drawRect(Rect.fromLTRB(body.left + 3, body.top + 4, body.right - 3, body.bottom - 4), x.fl(thread));
    final wraps = Path();
    final roll = turning ? (x.t * 9) % 4 : 0.0;
    for (var y = body.top + 6 + roll; y < body.bottom - 5; y += 4) {
      wraps
        ..moveTo(body.left + 4, y)
        ..lineTo(body.right - 4, y + 1.5);
    }
    c.drawPath(wraps, x.st(Color.lerp(thread, BP.paper, 0.35)!, 0.8));
    for (final y in [body.top, body.bottom - 5]) {
      final flange = Rect.fromLTRB(body.left - 3, y, body.right + 3, y + 5);
      c.drawRect(flange, x.fl(Mat.wood));
      c.drawRect(flange, x.st(Mat.woodDark, 1));
    }
    c.drawLine(Offset(o.dx, body.bottom), Offset(o.dx, x.floorY), x.st(Mat.woodDark, 3));
  }
}

/// Everything the embroidery needs for one glyph: the patch, the satin
/// stitches per stroke, the outline backstitches, the threads' colours and
/// the needle's timing.
class _Work {
  _Work(GlyphStage s, int seed) {
    final ink = s.ink;
    final m = (ink.height * 0.06).clamp(10.0, 18.0);
    patch = Rect.fromLTRB(ink.left - m, ink.top - m, ink.right + m, ink.bottom + m * 0.6);
    // Threads: a main colour (three shades, alternating by stroke) and a
    // contrasting outline.
    const pairs = [
      (Color(0xFFFF6B6B), Color(0xFF2B3A55)),
      (Color(0xFF2BB5A8), Color(0xFF203A5C)),
      (Color(0xFF4A7BFF), Color(0xFFE8A93A)),
      (Color(0xFFFF7EB6), Color(0xFF2B3A55)),
      (Color(0xFF3FB86B), Color(0xFF8A3B2B)),
      (Color(0xFF9B6BFF), Color(0xFFE8A93A)),
    ];
    final (main, outline) = pairs[(rnd(seed, 5, 31) * pairs.length).floor()];
    shades = [
      main,
      Color.lerp(main, const Color(0xFFFFFFFF), 0.16)!,
      Color.lerp(main, const Color(0xFF000000), 0.12)!,
    ];
    under = Color.lerp(main, const Color(0xFF000000), 0.42)!;
    edge = outline;
    // Weave and hem.
    for (var y = patch.top + 4; y < patch.bottom; y += 7) {
      weave
        ..moveTo(patch.left, y)
        ..lineTo(patch.right, y);
    }
    for (var xx = patch.left + 4; xx < patch.right; xx += 7) {
      weave
        ..moveTo(xx, patch.top)
        ..lineTo(xx, patch.bottom);
    }
    final hemRect = patch.deflate(4.5);
    for (final (a, b) in [
      (hemRect.topLeft, hemRect.topRight),
      (hemRect.topRight, hemRect.bottomRight),
      (hemRect.bottomRight, hemRect.bottomLeft),
      (hemRect.bottomLeft, hemRect.topLeft),
    ]) {
      final len = (b - a).distance;
      final u = (b - a) / len;
      for (var d = 0.0; d < len - 2; d += 8) {
        final e = math.min(len, d + 5);
        hem
          ..moveTo(a.dx + u.dx * d, a.dy + u.dy * d)
          ..lineTo(a.dx + u.dx * e, a.dy + u.dy * e);
      }
    }
    // Satin stitches: across each stroke (extended by its radius at both
    // ends), slanted, a little longer than the stroke is wide (the glyph
    // clips them).
    gap = (s.typicalRadius * 0.28).clamp(2.6, 4.4);
    const slant = 0.38;
    for (final st in s.strokes) {
      final pts = st.pts;
      final r0 = st.radius.first, r1 = st.radius.last;
      final d0 = _unit(pts[1] - pts[0]), d1 = _unit(pts.last - pts[pts.length - 2]);
      final ext = [pts.first - d0 * r0 * 0.9, ...pts, pts.last + d1 * r1 * 0.9];
      final rad = [r0, ...st.radius, r1];
      final arc = <double>[0];
      for (var i = 1; i < ext.length; i++) {
        arc.add(arc.last + (ext[i] - ext[i - 1]).distance);
      }
      final list = <(Offset, Offset)>[];
      final fracs = <double>[];
      var si = 1;
      for (var a = gap / 2; a < arc.last; a += gap) {
        while (si < ext.length - 1 && arc[si] < a) {
          si++;
        }
        final f = (a - arc[si - 1]) / math.max(1e-6, arc[si] - arc[si - 1]);
        final pos = Offset.lerp(ext[si - 1], ext[si], f)!;
        final r = rad[si - 1] + (rad[si] - rad[si - 1]) * f;
        // Direction: averaged over a stretch of the stroke so corners turn
        // smoothly.
        final reach = math.max(r * 1.2, 3 * gap);
        final back = _pointAt(ext, arc, a - reach), ahead = _pointAt(ext, arc, a + reach);
        final t = _unit(ahead - back);
        final nrm = Offset(-t.dy, t.dx);
        final dir = nrm * math.cos(slant) + t * math.sin(slant);
        final half = r * 1.32;
        list.add((pos - dir * half, pos + dir * half));
        // The underlay (a round-capped brush) stays just behind the stitches.
        final along = (a - r0 * 0.9 - r * 1.35).clamp(0.0, st.length);
        fracs.add(((st.start + along) / math.max(1, s.strokeLength)).clamp(0.0, 1.0));
      }
      strokes.add(list);
      _fracs.add(fracs);
    }
    // Backstitch along every outline.
    edgeWidth = (s.typicalRadius * 0.16).clamp(2.0, 3.6);
    for (final cm in s.contourMetrics) {
      final step = 7.0 + edgeWidth;
      for (var d = 0.0; d < cm.length - 1; d += step) {
        final a = cm.getTangentForOffset(d)?.position;
        final b = cm.getTangentForOffset(math.min(cm.length, d + step - 2.2))?.position;
        if (a != null && b != null) dashes.add((a, b));
      }
    }
    // Timing: each stroke by its stitches, plus a pause to move the needle.
    var t = 0.0;
    for (final st in strokes) {
      _starts.add(t);
      t += 5 + st.length;
    }
    _total = math.max(1, t);
    firstTip = strokes.isEmpty || strokes.first.isEmpty ? ink.center : strokes.first.first.$1;
  }

  late final Rect patch;
  late final List<Color> shades;
  late final Color under;
  late final Color edge;
  late final double gap;
  late final double edgeWidth;
  late final Offset firstTip;
  final weave = Path();
  final hem = Path();

  /// Per stroke, its stitches in order.
  final strokes = <List<(Offset, Offset)>>[];
  final _fracs = <List<double>>[];
  final dashes = <(Offset, Offset)>[];
  final _starts = <double>[];
  late final double _total;

  static Offset _unit(Offset v) {
    final l = v.distance;
    return l < 1e-6 ? const Offset(1, 0) : v / l;
  }

  static Offset _pointAt(List<Offset> pts, List<double> arc, double a) {
    if (a <= 0) return pts.first;
    if (a >= arc.last) return pts.last;
    var i = 1;
    while (i < pts.length - 1 && arc[i] < a) {
      i++;
    }
    final f = (a - arc[i - 1]) / math.max(1e-6, arc[i] - arc[i - 1]);
    return Offset.lerp(pts[i - 1], pts[i], f)!;
  }

  /// At satin progress [q]: the stroke being stitched, how many of its
  /// stitches are done, the underlay fraction and the needle tip.
  ({int stroke, int stitch, double frac, Offset tip}) at(double q) {
    if (strokes.isEmpty) return (stroke: 0, stitch: 0, frac: q, tip: firstTip);
    final time = q.clamp(0.0, 1.0) * _total;
    var i = strokes.length - 1;
    while (i > 0 && _starts[i] > time) {
      i--;
    }
    final st = strokes[i];
    final local = time - _starts[i] - 5;
    if (local < 0 || st.isEmpty) {
      // Moving the needle to this stroke's first stitch.
      final from = i == 0 || strokes[i - 1].isEmpty ? firstTip : strokes[i - 1].last.$2;
      final to = st.isEmpty ? from : st.first.$1;
      final f = eio((time - _starts[i]) / 5);
      final frac = i == 0 || _fracs[i - 1].isEmpty ? 0.0 : _fracs[i - 1].last;
      return (stroke: i, stitch: 0, frac: frac, tip: Offset.lerp(from, to, f)!);
    }
    final k = math.min(st.length - 1, local.floor());
    final within = local - local.floor();
    final (a, b) = st[k];
    // Down at one end, up at the other.
    final tip = within < 0.5 ? a : b;
    return (stroke: i, stitch: k + (within >= 0.5 ? 1 : 0), frac: _fracs[i][k], tip: tip);
  }
}
