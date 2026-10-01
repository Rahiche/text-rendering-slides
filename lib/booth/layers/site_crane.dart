import 'dart:math' as math;
import 'dart:ui';

import '../../deck/theme.dart';
import '../layout.dart';
import 'site_plan.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The tower crane: a timeline of hook moves (trolley x, hook height), the
// wrecking ball's swing, and the line drawing.
// ─────────────────────────────────────────────────────────────────────────────

const mastL = BL.craneMastX - 14;
const mastR = BL.craneMastX + 14;
const mastTop = 146.0;
const jibTipTop = BL.craneJibY - 8;
const jibRootTop = BL.craneJibY - 22;
const catHead = Offset(BL.craneMastX, 50);

/// The trolley never runs past these.
const trolleyMin = BL.craneJibLeft + 16;
const trolleyMax = ballParkX + 2;

/// One move of the hook: hold, straight line, or hoist-travel-lower arch.
class CraneMove {
  CraneMove.hold(this.t0, double dur, Offset p, {this.grounded = false})
    : t1 = t0 + dur,
      a = p,
      b = p,
      apex = 0,
      kind = 0;

  CraneMove.line(this.t0, double dur, this.a, this.b, {this.grounded = false})
    : t1 = t0 + dur,
      apex = 0,
      kind = 1;

  CraneMove.arch(this.t0, double dur, this.a, this.b, this.apex)
    : t1 = t0 + dur,
      grounded = false,
      kind = 2;

  final double t0, t1;

  /// Poses as (trolley x, hook bottom y).
  final Offset a, b;
  final double apex;
  final int kind;

  /// The hook rests on a load that stands on the ground (no sway).
  final bool grounded;

  Offset at(double t) {
    final u = seg(t, t0, t1);
    switch (kind) {
      case 0:
        return a;
      case 1:
        return Offset.lerp(a, b, eio(u))!;
      default:
        final x = mix(a.dx, b.dx, eio(seg(u, 0.14, 0.86)));
        final top = math.min(a.dy, b.dy);
        if (apex >= top - 2) return Offset(x, mix(a.dy, b.dy, eio(u)));
        final y = u < 0.5 ? mix(a.dy, apex, eio(seg(u, 0, 0.42))) : mix(apex, b.dy, eio(seg(u, 0.58, 1)));
        return Offset(x, y);
    }
  }
}

/// The hook's whole future, appended to as phases come.
class CraneTimeline {
  final moves = <CraneMove>[];
  Offset rest = const Offset(1080, 300);

  CraneMove? _find(double t) {
    for (var i = moves.length - 1; i >= 0; i--) {
      if (moves[i].t0 <= t) return moves[i];
    }
    return null;
  }

  Offset at(double t) => _find(t)?.at(t) ?? (moves.isEmpty ? rest : moves.first.a);

  bool grounded(double t) {
    final m = _find(t);
    return m != null && m.grounded && t <= m.t1;
  }

  double get end => moves.isEmpty ? double.negativeInfinity : moves.last.t1;
  Offset get endPose => moves.isEmpty ? rest : moves.last.b;

  /// Drops everything planned after [t]; the hook holds where it is.
  void truncate(double t) {
    final p = at(t);
    moves.removeWhere((m) => m.t0 > t);
    moves.add(CraneMove.hold(t, 0, p));
  }

  /// Forgets moves that ended a while ago.
  void prune(double t) {
    while (moves.length > 1 && moves[1].t0 < t - 1) {
      moves.removeAt(0);
    }
  }

  void add(CraneMove m) => moves.add(m);

  /// Appends an arch from the planned end pose to [to], starting at
  /// [from] or when the timeline ends, whichever is later. Returns the end
  /// time.
  double goTo(double from, Offset to, {double? dur, double clear = 60, double speed = 520}) {
    final t0 = math.max(from, end);
    final a = endPose;
    final d = dur ?? (0.7 + (to.dx - a.dx).abs() / speed + (a.dy - to.dy).abs().clamp(0, 400) / 900);
    final apex = math.min(math.min(a.dy, to.dy) - clear, 560.0).clamp(trolleyY + 30, 900.0);
    add(CraneMove.arch(t0, d, a, to, apex));
    return t0 + d;
  }

  double hold(double from, double dur, {bool grounded = false}) {
    final t0 = math.max(from, end);
    add(CraneMove.hold(t0, dur, endPose, grounded: grounded));
    return t0 + dur;
  }

  double line(double from, Offset to, double dur, {bool grounded = false}) {
    final t0 = math.max(from, end);
    add(CraneMove.line(t0, dur, endPose, to, grounded: grounded));
    return t0 + dur;
  }
}

/// The wrecking ball's angle script during a demolition: eases (pull back,
/// settle) and free swings (a damped pendulum).
class SwingSeg {
  SwingSeg.ease(this.t0, this.t1, this.from, this.to)
    : free = false,
      omega = 0,
      decay = 0;
  SwingSeg.swing(this.t0, this.t1, this.from, double length, {this.decay = 0.22})
    : free = true,
      to = 0,
      omega = math.sqrt(gravity / math.max(80, length));

  final double t0, t1;
  final double from, to;
  final bool free;
  final double omega;
  final double decay;

  double at(double t) {
    if (!free) return mix(from, to, eio(seg(t, t0, t1)));
    final tau = math.max(0.0, t - t0);
    return from * math.cos(omega * tau) * math.exp(-decay * tau);
  }
}

class BallScript {
  final segs = <SwingSeg>[];

  double? theta(double t) {
    for (var i = segs.length - 1; i >= 0; i--) {
      final s = segs[i];
      if (t >= s.t0) return t <= s.t1 ? s.at(t) : (i == segs.length - 1 ? null : s.at(s.t1));
    }
    return null;
  }

  double get end => segs.isEmpty ? double.negativeInfinity : segs.last.t1;

  void clear() => segs.clear();
}

// ─────────────────────────────────────────────────────────────────────────────
// Drawing
// ─────────────────────────────────────────────────────────────────────────────

Paint _st(Color c, [double w = 1.2]) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = c;

Paint _fl(Color c) => Paint()..color = c;

class CraneArt {
  Path? _frame;
  Path? _web;

  Path _buildFrame() {
    final p = Path();
    // Mast.
    p
      ..moveTo(mastL, mastTop)
      ..lineTo(mastL, BL.groundY - 8)
      ..moveTo(mastR, mastTop)
      ..lineTo(mastR, BL.groundY - 8);
    // Jib chords.
    p
      ..moveTo(BL.craneJibLeft, BL.craneJibY)
      ..lineTo(mastL, BL.craneJibY)
      ..moveTo(BL.craneJibLeft, jibTipTop)
      ..lineTo(mastL, jibRootTop)
      ..moveTo(BL.craneJibLeft, jibTipTop)
      ..lineTo(BL.craneJibLeft, BL.craneJibY)
      // Counter-jib.
      ..moveTo(mastR, BL.craneJibY)
      ..lineTo(1598, BL.craneJibY)
      ..moveTo(mastR, BL.craneJibY - 12)
      ..lineTo(1598, BL.craneJibY - 12)
      ..moveTo(1598, BL.craneJibY - 12)
      ..lineTo(1598, BL.craneJibY)
      // Tower head (cat-head) and pendants.
      ..moveTo(mastL, jibRootTop)
      ..lineTo(catHead.dx, catHead.dy)
      ..lineTo(mastR, jibRootTop)
      ..moveTo(catHead.dx, catHead.dy)
      ..lineTo(catHead.dx, mastTop - 14)
      ..moveTo(catHead.dx, catHead.dy)
      ..lineTo(980, jibTop(980))
      ..moveTo(catHead.dx, catHead.dy)
      ..lineTo(1596, BL.craneJibY - 12)
      // Slewing ring.
      ..addRect(const Rect.fromLTRB(mastL - 6, mastTop - 14, mastR + 6, mastTop))
      // Concrete footing.
      ..addRect(const Rect.fromLTRB(mastL - 18, BL.groundY - 8, mastR + 18, BL.groundY));
    return p;
  }

  static double jibTop(double x) => mix(jibTipTop, jibRootTop, (x - BL.craneJibLeft) / (mastL - BL.craneJibLeft));

  Path _buildWeb() {
    final p = Path();
    var left = true;
    const step = 14.0;
    for (var y = mastTop; y < BL.groundY - 9; y += step) {
      p
        ..moveTo(left ? mastL : mastR, y)
        ..lineTo(left ? mastR : mastL, math.min(BL.groundY - 8, y + step));
      left = !left;
    }
    var up = true;
    for (var x = BL.craneJibLeft; x < mastL - 1; x += 16) {
      final x2 = math.min(mastL, x + 16);
      if (up) {
        p
          ..moveTo(x, BL.craneJibY)
          ..lineTo(x2, jibTop(x2));
      } else {
        p
          ..moveTo(x, jibTop(x))
          ..lineTo(x2, BL.craneJibY);
      }
      up = !up;
    }
    for (var x = mastR; x < 1597; x += 12) {
      p
        ..moveTo(x, BL.craneJibY)
        ..lineTo(math.min(1598, x + 6), BL.craneJibY - 12)
        ..lineTo(math.min(1598, x + 12), BL.craneJibY);
    }
    return p;
  }

  /// Mast, jib, counter-jib, cab with its operator.
  void structure(Canvas c, double t, {double cheer = 0}) {
    c.drawPath(_web ??= _buildWeb(), _st(BP.lineFaint, 1));
    c.drawPath(_frame ??= _buildFrame(), _st(BP.lineDim, 1.3));
    c.drawLine(
      const Offset(BL.craneJibLeft, BL.craneJibY),
      const Offset(mastL, BL.craneJibY),
      _st(BP.line, 1.4),
    );
    // Counterweights on the counter-jib.
    for (var i = 0; i < 3; i++) {
      final r = Rect.fromLTWH(1570, BL.craneJibY - 13 - (i + 1) * 9.0, 26, 9);
      c.drawRect(r, _fl(BP.panel));
      c.drawRect(r, _st(BP.lineDim, 1.1));
    }
    // Cab, hung on the mast under the counter-jib, operator inside.
    const cab = Rect.fromLTRB(mastR + 2, BL.craneJibY + 4, mastR + 32, BL.craneJibY + 32);
    c.drawRect(cab, _fl(BP.panel));
    c.drawRect(cab, _st(BP.line, 1.2));
    c.drawRect(cab.deflate(4), _st(BP.lineDim, 1));
    final head = Offset(cab.center.dx - 2, cab.center.dy + 3 - 2 * cheer * (0.5 + 0.5 * math.sin(t * 9)));
    c.drawCircle(head, 3.4, _fl(BP.paper));
    c.drawCircle(head, 3.4, _st(BP.ink, 1.2));
    c.drawArc(Rect.fromCircle(center: head + const Offset(0, -0.8), radius: 4.2), math.pi, math.pi, true, _fl(BP.amber));
    if (cheer > 0.5) {
      // The operator waves from the window.
      final w = math.sin(t * 11) * 0.5;
      c.drawLine(head + const Offset(-3, 2), head + Offset(-8 + w * 3, -7), _st(BP.ink, 1.3));
    }
    // Aircraft warning light on the cat-head.
    final blink = (t * 0.8) % 1.0 < 0.18;
    c.drawCircle(catHead + const Offset(0, -3), 2.6, _fl(blink ? BP.red : BP.red.withValues(alpha: 0.35)));
  }

  /// The trolley riding the jib's bottom chord.
  void trolley(Canvas c, double x) {
    final r = Rect.fromLTRB(x - 10, BL.craneJibY + 1, x + 10, trolleyY);
    c.drawRect(r, _fl(BP.paper));
    c.drawRect(r, _st(BP.line, 1.2));
    for (final w in [-4.0, 4.0]) {
      c.drawCircle(Offset(x + w, BL.craneJibY + 1), 1.8, _st(BP.lineDim, 1));
    }
  }

  /// Hoist cables from the trolley at [trolleyX] down to the hook block
  /// whose bottom is at [hook].
  void hook(Canvas c, double trolleyX, Offset hook) {
    final cable = _st(BP.inkDim, 1);
    c.drawLine(Offset(trolleyX - 3, trolleyY), Offset(hook.dx - 3, hook.dy - 11), cable);
    c.drawLine(Offset(trolleyX + 3, trolleyY), Offset(hook.dx + 3, hook.dy - 11), cable);
    final block = Rect.fromLTRB(hook.dx - 6, hook.dy - 11, hook.dx + 6, hook.dy - 2);
    c.drawRect(block, _fl(BP.paper));
    c.drawRect(block, _st(BP.amber, 1.3));
    final h = Path()
      ..moveTo(hook.dx, hook.dy - 2)
      ..lineTo(hook.dx, hook.dy + 3)
      ..arcTo(Rect.fromCircle(center: Offset(hook.dx - 3, hook.dy + 3), radius: 3), 0, math.pi * 0.9, false);
    c.drawPath(h, _st(BP.amber, 1.5));
  }

  /// Slings from the hook to the top corners of a load [w] wide.
  void slings(Canvas c, Offset hook, double topY, double w) {
    final p = _st(BP.inkDim, 1);
    c.drawLine(hook + const Offset(0, 3), Offset(hook.dx - w / 2 + 1, topY), p);
    c.drawLine(hook + const Offset(0, 3), Offset(hook.dx + w / 2 - 1, topY), p);
  }

  /// The wrecking ball hanging at [center] from the line that leaves the
  /// trolley at [top], with the hook block [blockAt] along it.
  void ball(Canvas c, Offset top, Offset blockAt, Offset center, {bool cable = true}) {
    if (cable) {
      c.drawLine(top, blockAt, _st(BP.inkDim, 1.2));
      final block = Rect.fromCenter(center: blockAt, width: 12, height: 9);
      c.drawRect(block, _fl(BP.paper));
      c.drawRect(block, _st(BP.amber, 1.3));
      // Chain links down to the ball.
      final d = center - blockAt;
      final n = d.distance;
      if (n > 1) {
        final u = d / n;
        final links = Path();
        for (var s = 6.0; s < n - ballR + 2; s += 4) {
          final p = blockAt + u * s;
          links.addOval(Rect.fromCenter(center: p, width: 3, height: 4));
        }
        c.drawPath(links, _st(BP.lineDim, 1));
      }
    }
    c.drawCircle(center, ballR, _fl(const Color(0xFF1A2F47)));
    c.drawCircle(center, ballR, _st(BP.line, 1.5));
    c.drawArc(
      Rect.fromCircle(center: center, radius: ballR - 4),
      math.pi * 1.1,
      math.pi * 0.45,
      false,
      _st(BP.ink.withValues(alpha: 0.6), 1.4),
    );
    c.drawCircle(center + const Offset(0, -ballR), 2.2, _st(BP.lineDim, 1.2));
  }
}
