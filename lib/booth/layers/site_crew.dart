import 'dart:math' as math;
import 'dart:ui';

import '../../deck/theme.dart';
import '../../worlds/factory/factory_kit.dart' show FactoryInk, Pose;
import '../layout.dart';
import 'site_plan.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The crew. Builders are "movers": the simulation gives each a goal (a spot
// on some scaffold deck) every step and they walk, climb or hop down to it at
// a believable speed. What their arms do is decided when painting, from the
// brick schedule (so a brick always leaves the right hands at the right
// time).
// ─────────────────────────────────────────────────────────────────────────────

/// One hard-hat colour per zone, so you can tell who lays what.
const zoneHats = [BP.amber, BP.coral, BP.green, BP.violet, BP.pink, BP.line];

/// What a builder is doing at its goal.
enum Act { idle, work, watch, cheer, shovel, hammer, stretch, react, coffee, plank }

class Mover {
  Mover(this.x, [this.face = -1]);

  double x;
  double y = BL.groundY;
  double face;

  /// Deck under the feet (0 = the ground) while not climbing.
  int deck = 0;
  double walkPh = 0;
  double speed = 0;
  bool climbing = false;
  int climbTo = 0;
  double climbPh = 0;
  double climbX = 0;
  double climbFrom = BL.groundY;
  bool falling = false;
  double vy = 0;

  // Goal.
  double gx = 0;
  int gDeck = 0;
  bool hurry = false;
  Act act = Act.idle;

  /// Facing wanted when standing still (0 = keep).
  double gFace = 0;

  /// Steps towards the goal. [deckY] maps decks to heights; [ladder] gives
  /// where to climb down from x.
  void step(double dt, double Function(int) deckY, double Function(double) ladder, int maxDeck) {
    final gd = gDeck.clamp(0, maxDeck);
    if (falling) {
      vy += gravity * dt;
      y += vy * dt;
      final floor = deckY(gd);
      if (y >= floor) {
        y = floor;
        deck = gd;
        falling = false;
        vy = 0;
      }
      speed = 0;
      return;
    }
    if (climbing) {
      final target = deckY(climbTo);
      final up = target < y;
      final v = up ? 85.0 : (hurry ? 190.0 : 120.0);
      final dy = target - y;
      final stepY = v * dt;
      climbPh += stepY * 0.32;
      speed = 0;
      if (dy.abs() <= stepY) {
        y = target;
        deck = climbTo;
        climbing = false;
      } else {
        y += dy.sign * stepY;
      }
      return;
    }
    if (deck != gd) {
      final up = gd > deck;
      // Up one lift: right where we are. Down, or several lifts: from the
      // ladders at the scaffold's ends.
      final cx = up && gd - deck == 1 ? x : ladder(x);
      if ((x - cx).abs() > 1.5) {
        _walk(dt, cx, true);
        return;
      }
      climbing = true;
      climbTo = up ? deck + 1 : deck - 1;
      climbX = x;
      climbFrom = y;
      speed = 0;
      return;
    }
    y = deckY(deck);
    _walk(dt, gx, hurry);
  }

  void _walk(double dt, double tx, bool fast) {
    final dx = tx - x;
    final vmax = fast ? 165.0 : 75.0;
    final v = math.min(vmax, dx.abs() * 6);
    if (dx.abs() < 0.4) {
      speed = 0;
      if (gFace != 0) face = gFace;
      return;
    }
    final s = math.min(dx.abs(), v * dt);
    x += dx.sign * s;
    face = dx.sign;
    speed = v;
    walkPh += s * 0.2;
  }

  /// Leaves the scaffold at once (jumps down to the ground).
  void drop() {
    if (y < BL.groundY - 0.5 && !falling) {
      falling = true;
      climbing = false;
      vy = -60;
    }
    gDeck = 0;
  }
}

// ── Drawing helpers ─────────────────────────────────────────────────────────

/// Shoulder of a [FactoryInk.worker] figure (same maths as the kit).
Offset shoulderOf(Offset feet, double h, double dir, Pose f) {
  final hip = feet + Offset(0, -0.48 * h + f.drop * h - f.bob);
  final spine = 0.32 * h;
  final neck = hip + Offset(math.sin(f.lean) * dir * spine, -math.cos(f.lean) * spine);
  return neck - Offset(math.sin(f.lean) * dir, -math.cos(f.lean)) * (0.05 * h);
}

/// Two-bone IK for one arm: sets (upper, fore) angles so the hand reaches
/// [target] (or points at it when out of reach).
(double, double) reach(Offset sh, Offset target, double h, double dir, {double bend = 1}) {
  final d = target - sh;
  final seg = 0.17 * h;
  final dist = d.distance.clamp(0.05, 2 * seg - 0.01);
  final phi = math.atan2(d.dx * dir, d.dy);
  final a = math.acos((dist / (2 * seg)).clamp(-1.0, 1.0));
  return (phi - a * bend, phi + a * bend);
}

void climbPose(Pose p, double ph) {
  final s = math.sin(ph);
  p
    ..upA = 2.55 + 0.4 * s
    ..foA = 2.75 + 0.4 * s
    ..upB = 2.55 - 0.4 * s
    ..foB = 2.75 - 0.4 * s
    ..thA = 0.4 + 0.7 * math.max(0, s)
    ..shA = -0.3 + 0.2 * math.max(0, s)
    ..thB = 0.4 + 0.7 * math.max(0, -s)
    ..shB = -0.3 + 0.2 * math.max(0, -s)
    ..drop = 0.04;
}

/// Arms up in a V (both visible at this size), hopping.
void cheerPose(Pose p, double t, double seed) {
  final w = 0.28 * math.sin(t * 9 + seed);
  p
    ..upA = 2.2 + w
    ..foA = 2.55 + w
    ..upB = -2.2 + w
    ..foB = -2.55 + w
    ..head = -0.15
    ..bob = 3.2 * math.max(0, math.sin(t * 9 + seed));
}

/// A short ladder between two heights at [x] (drawn while someone climbs).
void ladder(Canvas c, double x, double top, double bottom, {double alpha = 1}) {
  final p = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = BP.inkFaint.withValues(alpha: alpha);
  c.drawLine(Offset(x - 4, bottom), Offset(x - 4, top - 6), p);
  c.drawLine(Offset(x + 4, bottom), Offset(x + 4, top - 6), p);
  for (var y = bottom - 5; y > top - 4; y -= 6) {
    c.drawLine(Offset(x - 4, y), Offset(x + 4, y), p);
  }
}

/// A small brick held in a hand.
void heldBrick(Canvas c, Offset at, double s, Color col) {
  final r = Rect.fromCenter(center: at, width: s, height: s);
  c.drawRect(r, Paint()..color = col);
  c.drawRect(
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = BP.paper.withValues(alpha: 0.7),
  );
}

/// Theodolite on its tripod at [foot] (the instrument head is returned).
Offset theodolite(FactoryInk ink, Offset foot, {double fold = 0}) {
  final c = ink.c;
  final top = foot + const Offset(0, -24);
  final spread = 9 * (1 - fold);
  c.drawPath(
    Path()
      ..moveTo(foot.dx - spread, foot.dy)
      ..lineTo(top.dx, top.dy)
      ..lineTo(foot.dx + spread, foot.dy)
      ..moveTo(top.dx, top.dy)
      ..lineTo(top.dx + spread * 0.2, foot.dy),
    ink.st(BP.lineDim, 1.1),
  );
  final head = Rect.fromCenter(center: top + const Offset(0, -5), width: 9, height: 8);
  c.drawRect(head, ink.fl(BP.panel));
  c.drawRect(head, ink.st(BP.line, 1.1));
  c.drawLine(head.centerLeft + const Offset(-4, -1), head.centerLeft + const Offset(0, -1), ink.st(BP.line, 2));
  return head.center;
}

/// Survey staff (graduated pole) held at [hand], foot on [ground].
void staff(Canvas c, double x, double ground, double height) {
  final p = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..color = BP.amber;
  c.drawLine(Offset(x, ground), Offset(x, ground - height), p);
  final t = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = BP.paper;
  for (var y = ground - 6; y > ground - height; y -= 6) {
    c.drawLine(Offset(x - 1, y), Offset(x + 1, y), t);
  }
}

/// Little drum mixer at [at] (feet on the ground); [spin] turns the drum.
void mixer(FactoryInk ink, Offset at, double spin) {
  final c = ink.c;
  c.drawPath(
    Path()
      ..moveTo(at.dx - 12, at.dy)
      ..lineTo(at.dx - 4, at.dy - 18)
      ..lineTo(at.dx + 6, at.dy)
      ..moveTo(at.dx + 10, at.dy)
      ..lineTo(at.dx + 10, at.dy - 12),
    ink.st(BP.lineDim, 1.2),
  );
  c.drawCircle(Offset(at.dx - 12, at.dy - 4), 4, ink.st(BP.lineDim, 1.1));
  c.save();
  c.translate(at.dx, at.dy - 26);
  c.rotate(-0.45);
  final drum = Rect.fromCenter(center: Offset.zero, width: 30, height: 20);
  c.drawOval(drum, ink.fl(BP.panel));
  c.drawOval(drum, ink.st(BP.line, 1.3));
  c.clipPath(Path()..addOval(drum));
  final stripes = Path();
  for (var i = 0; i < 4; i++) {
    final sx = ((i / 4 + spin) % 1.0) * 40 - 20;
    stripes
      ..moveTo(sx - 5, -10)
      ..lineTo(sx + 5, 10);
  }
  c.drawPath(stripes, ink.st(BP.lineDim, 1.2));
  c.restore();
  // Mouth of the drum.
  final m = at + const Offset(-14, -36);
  c.drawOval(Rect.fromCenter(center: m, width: 8, height: 5), ink.st(BP.line, 1.1));
}
