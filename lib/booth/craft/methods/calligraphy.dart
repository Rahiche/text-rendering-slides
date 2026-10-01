import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../../../worlds/factory/factory_kit.dart';
import '../method.dart';
import '../stage.dart';

/// 書道 · Calligraphy: a calligrapher on a lift writes the character on a
/// giant sheet of washi with a giant brush, stroke by stroke in writing
/// order; the brush uncovers exactly the glyph (each stroke as wide as the
/// glyph's own stroke there).
class CalligraphyCraft extends CraftMethod {
  const CalligraphyCraft();

  @override
  String get id => 'calligraphy';

  @override
  String get en => 'Calligraphy';

  @override
  String get ja => '書道';

  @override
  Color get color => Mat.paper;

  @override
  double get weight => 1.1;

  static final _plans = Expando<_Pen>();

  _Pen _pen(GlyphStage s) => _plans[s] ??= _Pen(s);

  Rect _sheet(GlyphStage s) {
    final m = math.max(14.0, s.ink.height * 0.1);
    return Rect.fromLTRB(s.ink.left - m, s.ink.top - m, s.ink.right + m, s.ink.bottom + m * 0.6);
  }

  void _paper(CraftContext x, Rect sheet, double unroll) {
    final c = x.c;
    final r = Rect.fromLTRB(sheet.left, sheet.top, sheet.right, sheet.top + sheet.height * unroll);
    // Easel posts behind the sheet.
    for (final px in [sheet.left + 10, sheet.right - 10]) {
      c.drawLine(Offset(px, sheet.top - 14), Offset(px, x.daisY), x.st(Mat.woodDark, 3));
    }
    c.drawRect(r, x.fl(Mat.paper));
    // Washi fibres.
    final fibre = x.st(const Color(0xFFD9D0B8), 0.8);
    for (var i = 0; i < 18; i++) {
      final y = sheet.top + rnd(x.seed, i, 1) * sheet.height;
      if (y > r.bottom) continue;
      final x0 = sheet.left + rnd(x.seed, i, 2) * sheet.width;
      c.drawLine(Offset(x0, y), Offset(x0 + 10 + 30 * rnd(i, x.seed), y + 3 * rnd(i, 4)), fibre);
    }
    // Rod at the top.
    c.drawLine(
      Offset(sheet.left - 8, sheet.top),
      Offset(sheet.right + 8, sheet.top),
      x.st(Mat.woodDark, 5),
    );
    if (unroll < 1) {
      c.drawLine(
        Offset(sheet.left - 4, r.bottom),
        Offset(sheet.right + 4, r.bottom),
        x.st(Mat.woodDark, 6),
      );
    }
  }

  @override
  void paintMaking(CraftContext x, double p) {
    final s = x.s, c = x.c;
    final sheet = _sheet(s);
    final unroll = seg(p, 0, 0.08);
    _paper(x, sheet, eio(unroll));
    if (unroll < 1) return;
    final pen = _pen(s);
    final q = seg(p, 0.1, 0.94);
    final (frac, lifted, tip) = pen.at(q);
    final ink = Paint()..color = Mat.sumi;
    if (p >= 0.97) {
      c.drawPath(s.outline, ink);
    } else {
      s.reveal(
        c,
        (c) => s.paintStrokesUpTo(c, frac, Paint()..color = const Color(0xFF000000), grow: 1.3),
        (c) => c.drawPath(s.outline, ink),
      );
    }
    // Splashes where strokes ended.
    for (var i = 0; i < s.strokes.length; i++) {
      final st = s.strokes[i];
      if (frac * s.strokeLength < st.start + st.length) break;
      final end = st.pts.last;
      for (var k = 0; k < 3; k++) {
        final o = Offset((rnd(x.seed, i, k) - 0.5) * 30, (rnd(i, x.seed, k) - 0.3) * 24);
        c.drawCircle(end + o, 1 + 2.2 * rnd(k, i, x.seed), ink);
      }
    }
    // The calligrapher on a lift, holding the brush with both hands.
    // Standing beside the brush tip, on the side nearer the sheet's edge.
    final leftHalf = tip.dx < s.ink.center.dx;
    final dir = leftHalf ? 1 : -1;
    final standX = tip.dx - dir * 46;
    final targetY = tip.dy - (lifted ? 26 : 0);
    final platform = x.liftFor(targetY - 30);
    x.lift(standX, platform, w: 54);
    final brushTip = Offset(tip.dx, targetY);
    final shoulder = Offset(standX, platform - 4 - 39);
    final limbs = x.reach(
      Offset(standX, platform - 4),
      shoulder + (brushTip - shoulder) * 0.6,
      both: true,
      dir: dir,
    );
    _brush(x, limbs.handA, brushTip, lifted);
    // An apprentice grinding ink on the floor.
    final ax = sheet.left - 54;
    final pose = Pose()
      ..sit(44, 12)
      ..upA = 1.0 + 0.15 * math.sin(x.t * 6)
      ..foA = 1.4;
    x.ink.worker(Offset(ax, x.floorY), 44, 1, pose, hat: BP.inkDim);
    c.drawRect(Rect.fromLTWH(ax + 14, x.floorY - 8, 26, 8), x.fl(Mat.sumi));
    c.drawRect(Rect.fromLTWH(ax + 14, x.floorY - 8, 26, 8), x.st(BP.lineDim, 1));
  }

  void _brush(CraftContext x, Offset hand, Offset tip, bool lifted) {
    final c = x.c;
    final v = tip - hand;
    final dir = v / math.max(1, v.distance);
    final ferrule = tip - dir * 22;
    c.drawLine(hand - dir * 20, ferrule, x.st(Mat.wood, 5));
    c.drawLine(ferrule, ferrule + dir * 4, x.st(BP.lineDim, 6));
    // Bristles.
    final n = Offset(-dir.dy, dir.dx);
    final tuft = Path()
      ..moveTo(ferrule.dx + n.dx * 5, ferrule.dy + n.dy * 5)
      ..quadraticBezierTo(tip.dx + n.dx * 3, tip.dy + n.dy * 3, tip.dx, tip.dy)
      ..quadraticBezierTo(
        tip.dx - n.dx * 3,
        tip.dy - n.dy * 3,
        ferrule.dx - n.dx * 5,
        ferrule.dy - n.dy * 5,
      )
      ..close();
    c.drawPath(tuft, x.fl(Mat.sumi));
    c.drawPath(tuft, x.st(BP.inkDim, 0.8));
    if (!lifted) c.drawCircle(tip, 2.5, x.fl(Mat.sumi));
  }

  @override
  void paintFinished(CraftContext x) {
    final s = x.s, c = x.c;
    final sheet = _sheet(s);
    c.drawRect(sheet, x.fl(Mat.paper));
    c.drawLine(
      Offset(sheet.left - 6, sheet.top),
      Offset(sheet.right + 6, sheet.top),
      x.st(Mat.woodDark, 5),
    );
    c.drawLine(
      Offset(sheet.left - 6, sheet.bottom),
      Offset(sheet.right + 6, sheet.bottom),
      x.st(Mat.woodDark, 5),
    );
    c.drawPath(s.outline, Paint()..color = Mat.sumi);
    // Red seal (落款) in the corner.
    final r = Rect.fromLTWH(
      sheet.right - sheet.width * 0.16,
      sheet.bottom - sheet.width * 0.2,
      sheet.width * 0.11,
      sheet.width * 0.11,
    );
    c.drawRect(r, Paint()..color = const Color(0xFFD9443A));
    final seal = x.text.get(
      '名',
      BT.sample(r.height * 0.7, color: Mat.paper, weight: 700).copyWith(locale: jaLocale),
    );
    seal.paint(c, r.center - Offset(seal.width / 2, seal.height / 2));
  }
}

/// Time on the brush: each stroke takes time by its length, with a pause
/// between strokes for lifting and moving the brush.
class _Pen {
  _Pen(GlyphStage s) : _s = s {
    final n = s.strokes.length;
    final avg = n == 0 ? 1.0 : s.strokeLength / n;
    final pause = 0.45 * avg;
    var t = 0.0;
    for (final st in s.strokes) {
      _starts.add(t);
      t += pause; // move to the stroke
      _writeStarts.add(t);
      t += math.max(st.length, 0.3 * avg);
    }
    _total = math.max(t, 1);
  }

  final GlyphStage _s;
  final _starts = <double>[];
  final _writeStarts = <double>[];
  late final double _total;

  /// For writing progress [q]: the fraction of all strokes written, whether
  /// the brush is lifted (moving between strokes), and the brush tip.
  (double, bool, Offset) at(double q) {
    final s = _s;
    if (s.strokes.isEmpty) return (q, false, s.ink.center);
    final time = q * _total;
    var i = s.strokes.length - 1;
    while (i > 0 && _starts[i] > time) {
      i--;
    }
    final st = s.strokes[i];
    if (time < _writeStarts[i]) {
      // Moving from the previous stroke's end to this one's start.
      final from = i == 0 ? st.pts.first - const Offset(40, 60) : s.strokes[i - 1].pts.last;
      final f = eio((time - _starts[i]) / (_writeStarts[i] - _starts[i]));
      return (st.start / s.strokeLength, true, Offset.lerp(from, st.pts.first, f)!);
    }
    final d = math.min(
      st.length,
      (time - _writeStarts[i]) / math.max(st.length, 0.3 * (_total / s.strokes.length)) * st.length,
    );
    final (pos, _, _) = st.at(d);
    return (((st.start + d) / s.strokeLength).clamp(0.0, 1.0), false, pos);
  }
}
