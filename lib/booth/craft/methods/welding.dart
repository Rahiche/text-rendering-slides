import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../../../worlds/factory/factory_kit.dart';
import '../geometry.dart';
import '../method.dart';
import '../stage.dart';

/// 溶接 · Welding: steel beams follow the glyph's outline (simplified to
/// straight runs) and are welded joint by joint by a welder on a lift;
/// then steel plates fill the inside, riveted along the edges.
class WeldingCraft extends CraftMethod {
  const WeldingCraft();

  @override
  String get id => 'welding';

  @override
  String get en => 'Welding';

  @override
  String get ja => '溶接';

  @override
  Color get color => Mat.steel;

  static final _beams = Expando<List<(Offset, Offset)>>();

  /// The outline as straight beams (canvas px), outer outlines first.
  List<(Offset, Offset)> _beamsOf(GlyphStage s) => _beams[s] ??= () {
    final eps = math.max(2.0, s.geo.inkHeight * 0.035);
    final out = <(Offset, Offset)>[];
    for (final c in s.geo.contours) {
      final p = simplifyClosed(Float64List.fromList(c.pts), eps);
      final n = p.length ~/ 2;
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        out.add((s.map(p[2 * i], p[2 * i + 1]), s.map(p[2 * j], p[2 * j + 1])));
      }
    }
    return out;
  }();

  double _width(GlyphStage s) => (s.typicalRadius * 0.55).clamp(3.5, 11.0);

  void _beam(CraftContext x, Offset a, Offset b, double w) {
    final c = x.c;
    c.drawLine(
      a,
      b,
      Paint()
        ..color = Mat.steelDark
        ..strokeWidth = w
        ..strokeCap = StrokeCap.square,
    );
    c.drawLine(a, b, x.st(Mat.steel, math.max(1, w * 0.35)));
  }

  void _plates(CraftContext x, double level) {
    final s = x.s, c = x.c;
    final top = s.ink.bottom - s.ink.height * level;
    s.clipped(c, () {
      c.drawRect(
        Rect.fromLTRB(s.ink.left - 2, top, s.ink.right + 2, s.ink.bottom + 2),
        x.fl(Mat.steel.withValues(alpha: 0.85)),
      );
      // Plate seams.
      final seam = x.st(Mat.steelDark, 1);
      for (var y = s.ink.bottom - 34.0; y > top; y -= 34) {
        c.drawLine(Offset(s.ink.left, y), Offset(s.ink.right, y), seam);
      }
    });
  }

  void _rivets(CraftContext x, double upto) {
    final s = x.s;
    final n = math.max(8, (s.outlineLength / 26).round());
    for (var i = 0; i < n * upto; i++) {
      final tan = s.outlineAt(i / n);
      final inward = Offset(-tan.vector.dy, tan.vector.dx) * 7;
      x.c.drawCircle(tan.position + inward, 1.8, x.fl(Mat.steelDark));
    }
  }

  @override
  void paintMaking(CraftContext x, double p) {
    final s = x.s, c = x.c;
    final beams = _beamsOf(s);
    final w = _width(s);
    final a = seg(p, 0, 0.74);
    final placed = a * beams.length;
    final plate = seg(p, 0.76, 0.98);
    if (plate > 0) _plates(x, eio(plate));
    // Faint chalk outline of what's coming.
    c.drawPath(s.outline, x.st(BP.lineFaint, 1));
    Offset joint = s.ink.bottomLeft;
    var welding = false;
    for (var i = 0; i < beams.length; i++) {
      final (b0, b1) = beams[i];
      if (i < placed.floor()) {
        _beam(x, b0, b1, w);
      } else if (i == placed.floor() && a < 1) {
        final f = placed - i;
        final slide = eo(seg(f, 0, 0.55));
        // The beam swings in from above, then gets welded at its far end.
        final lift = (1 - slide) * 60;
        _beam(
          x,
          b0 - Offset(0, lift),
          Offset.lerp(b0, b1, 0.35 + 0.65 * slide)! - Offset(0, lift),
          w,
        );
        joint = b0;
        welding = f > 0.55;
        if (welding) joint = Offset.lerp(b0, b1, seg(f, 0.55, 1))!;
      }
    }
    if (plate > 0) _rivets(x, plate);
    if (a >= 1) joint = s.outlineAt(plate).position;
    // The welder on a lift.
    final leftSide = joint.dx < s.ink.center.dx;
    final standX = joint.dx + (leftSide ? -44 : 44);
    final platform = x.liftFor(joint.dy);
    x.lift(standX, platform, w: 54);
    final limbs = x.reach(Offset(standX, platform - 4), joint, dir: leftSide ? 1 : -1);
    // Visor.
    final face = limbs.head + Offset(leftSide ? 4 : -4, 0);
    x.c.drawRect(Rect.fromCenter(center: face, width: 9, height: 10), x.fl(Mat.sumi));
    c.drawLine(limbs.handA, joint, x.st(BP.inkDim, 2.2));
    if (welding || (a >= 1 && plate < 1)) {
      x.glow(joint, 16, BP.amber, alpha: 0.7);
      x.c.drawCircle(joint, 3, x.fl(BP.ink));
      x.sparks(joint, n: 14);
    }
    // A helper on the floor feeding the next beam.
    final hx = s.ink.center.dx + (leftSide ? 120 : -120);
    final carry = Pose()..carry();
    final hl = x.worker(Offset(hx, x.floorY), dir: leftSide ? -1 : 1, pose: carry, h: 46);
    _beam(x, hl.handA - const Offset(26, 0), hl.handA + const Offset(26, 0), 5);
  }

  @override
  void paintFinished(CraftContext x) {
    _plates(x, 1);
    final w = _width(x.s);
    for (final (a, b) in _beamsOf(x.s)) {
      _beam(x, a, b, w);
    }
    _rivets(x, 1);
  }
}
