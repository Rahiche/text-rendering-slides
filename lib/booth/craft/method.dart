import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../deck/theme.dart';
import '../../worlds/factory/factory_kit.dart';
import 'stage.dart';
import 'workshop_layout.dart';

/// One way of making a character in the Name Workshop (welding, calligraphy,
/// neon…). Each character of a name gets a different craft.
///
/// A craft draws two things, both in canvas coordinates of the character on
/// the dais ([CraftContext.s]):
///
/// * [paintMaking] — the character being made at progress `p` (0 → 1), with
///   the craft's workers, tools, machines and effects around it. The
///   workshop draws the material delivery before and the inspection after.
/// * [paintFinished] — the finished piece in its material. The workshop also
///   uses it, scaled down, for the character hanging on the name sign, so
///   keep it cheap and make it read well small too.
///
/// Draw as a pure function of `p`, `x.t` and `x.seed` (no state): the same
/// inputs must give the same picture (fast-forward, capture).
abstract class CraftMethod {
  const CraftMethod();

  /// Stable id, e.g. 'welding'.
  String get id;

  /// Short English name: 'Welding'.
  String get en;

  /// Japanese name: '溶接'.
  String get ja;

  /// Signature colour (plan board, sign label).
  Color get color;

  /// Relative time on the dais (1 ≈ 20 s at the normal pace).
  double get weight => 1;

  void paintMaking(CraftContext x, double p);

  void paintFinished(CraftContext x);
}

/// Everything a craft needs to draw: the canvas, the line-art kit, cached
/// text, the character on the dais, scene time and a per-character seed.
class CraftContext {
  CraftContext({
    required this.c,
    required this.ink,
    required this.text,
    required this.s,
    required this.t,
    required this.seed,
    required this.char,
  });

  final Canvas c;
  final FactoryInk ink;
  final TextCache text;
  final GlyphStage s;

  /// Scene seconds (for flicker, sparks, idle motion).
  final double t;

  /// Stable per character (deterministic randomness: `rnd(seed, i)`).
  final int seed;

  /// The character itself ('A', '田'…).
  final String char;

  double get floorY => BW.floorY;

  /// Top of the dais the character stands on.
  double get daisY => BW.dais.top;

  Paint st(Color col, [double w = 1.4]) => ink.st(col, w);
  Paint fl(Color col) => ink.fl(col);

  /// A worker standing at [feet] (h ≈ 50 px), facing [dir].
  Limbs worker(Offset feet, {int dir = 1, Pose? pose, double h = 50, Color hat = BP.amber}) =>
      ink.worker(feet, h, dir, pose ?? Pose(), hat: hat);

  /// A worker at [feet] reaching arm A towards [target] (arm B too when
  /// [both]). Returns the limbs, e.g. to draw a tool from `handA` to the
  /// target.
  Limbs reach(
    Offset feet,
    Offset target, {
    double h = 50,
    Color hat = BP.amber,
    bool both = false,
    int? dir,
  }) {
    final d = dir ?? (target.dx >= feet.dx ? 1 : -1);
    final shoulder = feet + Offset(0, -0.78 * h);
    final v = target - shoulder;
    final a = math.atan2(v.dx * d, v.dy).clamp(-0.3, 3.0);
    final pose = Pose()..point(a);
    if (both) {
      pose
        ..upB = a - 0.15
        ..foB = a - 0.05;
    }
    return ink.worker(feet, h, d, pose, hat: hat);
  }

  /// Platform height (y) for a worker on a lift to reach [targetY].
  double liftFor(double targetY, {double h = 50}) =>
      (targetY + 0.72 * h).clamp(floorY - 340, floorY);

  /// A scissor lift at [x] with its platform at [platformY] (worker stands
  /// on the platform).
  void lift(double x, double platformY, {double w = 64, Color col = BP.amber}) {
    final base = Rect.fromCenter(center: Offset(x, floorY - 7), width: w + 10, height: 14);
    ink.box(base, col: BP.lineDim);
    c.drawCircle(Offset(base.left + 8, floorY - 1), 4, fl(BP.paper));
    c.drawCircle(Offset(base.left + 8, floorY - 1), 4, st(BP.lineDim, 1.2));
    c.drawCircle(Offset(base.right - 8, floorY - 1), 4, fl(BP.paper));
    c.drawCircle(Offset(base.right - 8, floorY - 1), 4, st(BP.lineDim, 1.2));
    final top = platformY, bottom = floorY - 14;
    final n = math.max(1, ((bottom - top) / 34).round());
    final hgt = (bottom - top) / n;
    final p = Path();
    for (var i = 0; i < n; i++) {
      final y0 = bottom - i * hgt, y1 = y0 - hgt;
      p
        ..moveTo(x - w / 2 + 4, y0)
        ..lineTo(x + w / 2 - 4, y1)
        ..moveTo(x + w / 2 - 4, y0)
        ..lineTo(x - w / 2 + 4, y1);
    }
    c.drawPath(p, st(col.withValues(alpha: 0.8), 1.4));
    final deck = Rect.fromLTWH(x - w / 2, top - 4, w, 6);
    ink.box(deck, col: col);
    c.drawLine(Offset(deck.left, top - 4), Offset(deck.left, top - 26), st(col, 1.2));
    c.drawLine(Offset(deck.right, top - 4), Offset(deck.right, top - 26), st(col, 1.2));
    c.drawLine(Offset(deck.left, top - 26), Offset(deck.right, top - 26), st(col, 1.2));
  }

  /// A short spray of sparks at [at] (deterministic in [t]).
  void sparks(Offset at, {int n = 12, Color color = BP.amber, double size = 1, int salt = 0}) {
    final frame = (t * 30).floor();
    for (var i = 0; i < n; i++) {
      final a = rnd(frame, i, seed + salt) * math.pi * 2;
      final l = (6 + 26 * rnd(i, frame, 3 + salt)) * size;
      final v = Offset(math.cos(a), math.sin(a) - 0.4);
      c.drawLine(
        at + v * (l * 0.3),
        at + v * l,
        st(Color.lerp(color, BP.ink, rnd(i, frame, 7))!, 1.3),
      );
    }
  }

  /// A soft glow at [at].
  void glow(Offset at, double r, Color color, {double alpha = 0.55}) {
    c.drawCircle(
      at,
      r,
      Paint()
        ..color = color.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.6),
    );
  }

  /// Fills the whole glyph with [paint].
  void fillGlyph(Paint paint) => c.drawPath(s.outline, paint);

  /// Fills the glyph's rows from the bottom up to fraction [p] (a level).
  void fillRowsUp(double p, Paint paint) {
    final rows = s.rows;
    if (rows.isEmpty) return;
    final level = s.ink.bottom - s.ink.height * p.clamp(0.0, 1.0);
    s.clipped(
      c,
      () => c.drawRect(
        Rect.fromLTRB(s.ink.left - 2, level, s.ink.right + 2, s.ink.bottom + 2),
        paint,
      ),
    );
  }
}

/// Material colours shared by the crafts (blueprint-friendly).
abstract final class Mat {
  static const steel = Color(0xFF9FB8D4);
  static const steelDark = Color(0xFF5E7A99);
  static const bronze = Color(0xFFD69A5B);
  static const molten = Color(0xFFFFB347);
  static const wood = Color(0xFFC89A63);
  static const woodDark = Color(0xFF8A6238);
  static const stone = Color(0xFFB7B3A8);
  static const concrete = Color(0xFF9EA4A8);
  static const paper = Color(0xFFEDE6D3);
  static const sumi = Color(0xFF1A1C24);
  static const neon = Color(0xFFFF6FB5);
  static const gold = Color(0xFFFFD36B);
  static const porcelain = Color(0xFFE9EEF2);
  static const leaf = Color(0xFF6CC48A);
  static const thread = Color(0xFFFF7B7B);
  static const plastic = Color(0xFFB896FF);
  static const brick = Color(0xFFD9785B);
}
