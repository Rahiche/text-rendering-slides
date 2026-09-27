import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../deck/font_data.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The detective world's shared cast and props: the case fonts, the detective,
// rain, lamps, pins, red string, evidence tags and stamps.
// ─────────────────────────────────────────────────────────────────────────────

const jaLocale = Locale('ja');
const zhLocale = Locale('zh', 'CN');

/// The case number: 直 is U+76F4.
const caseCp = 0x76F4;
const caseChar = '直';

/// Every character the two case fonts contain (and nothing else).
const caseChars = '直骨角今令海写次化起画誤';

/// A monotonic clock shared by every scene of this world, so rain and lamps
/// keep going across slides instead of restarting.
final Stopwatch noirClock = Stopwatch()..start();

double get noirSeconds => noirClock.elapsedMicroseconds / 1e6;

String hexOf(int cp) => 'U+${cp.toRadixString(16).toUpperCase().padLeft(4, '0')}';

/// Text styles for this world.
abstract final class NT {
  /// Japanese UI text: tagged `ja`, so fallback picks a Japanese face (the
  /// very fix this deck is about).
  static TextStyle jp(double size, {Color color = BP.ink, double weight = 400, double? height}) =>
      BT.sample(size, color: color, weight: weight, height: height).copyWith(locale: jaLocale);

  /// The case fonts: tiny subsets of Noto Sans JP / SC.
  static TextStyle caseJP(double size, {Color color = BP.ink}) => TextStyle(
    fontFamily: 'CaseJP',
    fontSize: size,
    color: color,
    height: 1.0,
    locale: jaLocale,
  );

  static TextStyle caseSC(double size, {Color color = BP.amber}) => TextStyle(
    fontFamily: 'CaseSC',
    fontSize: size,
    color: color,
    height: 1.0,
    locale: zhLocale,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Case fonts: real outlines of the same code point in JP and SC
// ─────────────────────────────────────────────────────────────────────────────

/// The two bundled subsets, parsed. Paths are cached in em space (a
/// 1000 × 1000 box, y down, ideographic em box from y = 880 to -120).
class CaseFonts {
  CaseFonts._(this.jp, this.sc);

  final FontData jp;
  final FontData sc;

  static CaseFonts? ready;
  static Future<CaseFonts>? _f;

  static Future<CaseFonts> load() => _f ??= () async {
    final a = await FontData.load('assets/fonts/NotoSansJP-case.ttf', 'Noto Sans JP');
    final b = await FontData.load('assets/fonts/NotoSansSC-case.ttf', 'Noto Sans SC');
    return ready = CaseFonts._(a, b);
  }();

  final Map<int, Path> _em = {};
  final Map<int, Path> _xor = {};
  final Map<int, List<bool>> _odd = {};

  FontData font(bool japanese) => japanese ? jp : sc;

  GlyphOutline outline(bool japanese, int cp) {
    final f = font(japanese);
    return f.outline(f.glyphId(cp));
  }

  int glyphId(bool japanese, int cp) => font(japanese).glyphId(cp);

  /// The glyph in em space (0..1000, y down).
  Path em(bool japanese, int cp) => _em.putIfAbsent(
    cp * 2 + (japanese ? 1 : 0),
    () => outline(japanese, cp).toPath(scale: 1, origin: const Offset(0, 880)),
  );

  /// Where the two forms disagree: JP xor SC, in em space.
  Path xor(int cp) =>
      _xor.putIfAbsent(cp, () => Path.combine(PathOperation.xor, em(true, cp), em(false, cp)));

  /// Per contour of the [japanese] form: true when the other form has no
  /// contour with (nearly) the same bounds, i.e. a stroke that differs.
  List<bool> oddContours(bool japanese, int cp) => _odd.putIfAbsent(cp * 2 + (japanese ? 1 : 0), () {
    Rect bounds(List<OutlinePoint> c) {
      var l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
      for (final p in c) {
        l = math.min(l, p.x);
        r = math.max(r, p.x);
        t = math.min(t, p.y);
        b = math.max(b, p.y);
      }
      return Rect.fromLTRB(l, t, r, b);
    }

    final mine = outline(japanese, cp).contours.map(bounds).toList();
    final other = outline(!japanese, cp).contours.map(bounds).toList();
    bool close(Rect a, Rect b) =>
        (a.left - b.left).abs() < 40 &&
        (a.right - b.right).abs() < 40 &&
        (a.top - b.top).abs() < 40 &&
        (a.bottom - b.bottom).abs() < 40;
    return [for (final m in mine) !other.any((o) => close(m, o))];
  });

  /// One contour of the glyph as its own path (em space).
  Path contour(bool japanese, int cp, int index) {
    final o = outline(japanese, cp);
    return GlyphOutline([o.contours[index]], o.bounds).toPath(scale: 1, origin: const Offset(0, 880));
  }
}

/// Maps an em-space path into [box] (a square).
Path emToBox(Path em, Rect box) {
  final s = box.width / 1000;
  final m = Float64List(16)
    ..[0] = s
    ..[5] = s
    ..[10] = 1
    ..[15] = 1
    ..[12] = box.left
    ..[13] = box.top;
  return em.transform(m);
}

/// Loads [CaseFonts] once, then builds.
class CaseFontsBuilder extends StatelessWidget {
  const CaseFontsBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, CaseFonts fonts) builder;

  @override
  Widget build(BuildContext context) {
    final r = CaseFonts.ready;
    if (r != null) return builder(context, r);
    return FutureBuilder<CaseFonts>(
      future: CaseFonts.load(),
      builder: (context, snap) => snap.hasData ? builder(context, snap.data!) : const SizedBox(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Deterministic noise (no state, no allocation)
// ─────────────────────────────────────────────────────────────────────────────

/// A stable pseudo-random number in [0, 1) for [i] and [salt].
double hash01(int i, [int salt = 0]) {
  final v = math.sin(i * 12.9898 + salt * 78.233) * 43758.5453;
  return v - v.floorToDouble();
}

double _smooth(double t) => t * t * (3 - 2 * t);

/// Eases [t] in 0..1 from [a] to [b] (clamped), easeInOutCubic.
double seg(double t, double a, double b) =>
    Curves.easeInOutCubic.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

double segOut(double t, double a, double b) =>
    Curves.easeOutCubic.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

/// Slow value noise in [-1, 1].
double noise1(double x, [int salt = 0]) {
  final i = x.floor();
  final f = x - i;
  final a = hash01(i, salt) * 2 - 1;
  final b = hash01(i + 1, salt) * 2 - 1;
  return a + (b - a) * _smooth(f);
}

// ─────────────────────────────────────────────────────────────────────────────
// Weather and light
// ─────────────────────────────────────────────────────────────────────────────

/// Slanted rain streaks inside [area]. Pure function of [t] (seconds).
void paintRain(
  Canvas canvas,
  Rect area,
  double t, {
  int count = 120,
  double alpha = 0.16,
  double length = 18,
  double speed = 620,
  double slant = 0.22,
  Color color = BP.inkDim,
  int salt = 0,
}) {
  final p = Paint()
    ..color = color.withValues(alpha: alpha)
    ..strokeWidth = 1
    ..strokeCap = StrokeCap.round;
  final h = area.height + length;
  for (var i = 0; i < count; i++) {
    final sp = speed * (0.75 + 0.5 * hash01(i, salt + 1));
    final y = (hash01(i, salt + 2) * h + t * sp) % h - length;
    final x = area.left + (hash01(i, salt + 3) * (area.width + 80) - 40 + slant * y) % (area.width + 40);
    final a = Offset(x, area.top + y);
    canvas.drawLine(a, a + Offset(slant * length, length), p);
  }
}

/// Little splash arcs on a line at [y] between [x0] and [x1].
void paintSplashes(Canvas canvas, double x0, double x1, double y, double t,
    {int count = 10, double alpha = 0.35, int salt = 0}) {
  final p = Paint()
    ..color = BP.inkDim.withValues(alpha: alpha)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  for (var i = 0; i < count; i++) {
    final period = 0.7 + hash01(i, salt + 5) * 0.9;
    final k = ((t / period) + hash01(i, salt + 6)).floor();
    final u = (t / period) + hash01(i, salt + 6) - k;
    if (u > 0.35) continue;
    final x = x0 + hash01(i * 31 + k, salt + 7) * (x1 - x0);
    final r = 2 + u * 22;
    p.color = BP.inkDim.withValues(alpha: alpha * (1 - u / 0.35));
    canvas.drawArc(Rect.fromCenter(center: Offset(x, y), width: r * 2, height: r * 0.7), math.pi, math.pi, false, p);
  }
}

/// A lamp's light cone from [lamp] down to an ellipse on [groundY].
void paintCone(
  Canvas canvas,
  Offset lamp,
  double groundY, {
  double halfWidth = 300,
  double intensity = 1,
  Color color = BP.amber,
  double topHalf = 18,
  double skew = 0,
}) {
  if (intensity <= 0.01) return;
  final bottom = Offset(lamp.dx + skew, groundY);
  final cone = Path()
    ..moveTo(lamp.dx - topHalf, lamp.dy)
    ..lineTo(bottom.dx - halfWidth, groundY)
    ..arcTo(Rect.fromCenter(center: bottom, width: halfWidth * 2, height: halfWidth * 0.22), math.pi, -math.pi, false)
    ..lineTo(lamp.dx + topHalf, lamp.dy)
    ..close();
  canvas.drawPath(
    cone,
    Paint()
      ..shader = ui.Gradient.linear(lamp, bottom, [
        color.withValues(alpha: 0.16 * intensity),
        color.withValues(alpha: 0.035 * intensity),
      ]),
  );
  // Pool of light on the ground.
  canvas.drawOval(
    Rect.fromCenter(center: bottom, width: halfWidth * 2, height: halfWidth * 0.22),
    Paint()
      ..shader = ui.Gradient.radial(bottom, halfWidth, [
        color.withValues(alpha: 0.13 * intensity),
        color.withValues(alpha: 0),
      ]),
  );
  // Edge lines of the cone, like construction lines.
  final edge = Paint()
    ..color = color.withValues(alpha: 0.22 * intensity)
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;
  canvas.drawPath(
    dashPath(Path()
      ..moveTo(lamp.dx - topHalf, lamp.dy)
      ..lineTo(bottom.dx - halfWidth, groundY)
      ..moveTo(lamp.dx + topHalf, lamp.dy)
      ..lineTo(bottom.dx + halfWidth, groundY), dash: 10, gap: 8),
    edge,
  );
}

/// A hanging lamp shade (line-drawn) with its bulb at [bulb].
void paintLampShade(Canvas canvas, Offset bulb, {double size = 36, double glow = 1, double cord = 0}) {
  final ink = Paint()
    ..color = BP.line
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;
  if (cord > 0) canvas.drawLine(bulb - Offset(0, size * 0.55 + cord), bulb - Offset(0, size * 0.55), ink);
  final shade = Path()
    ..moveTo(bulb.dx - size * 0.22, bulb.dy - size * 0.55)
    ..lineTo(bulb.dx + size * 0.22, bulb.dy - size * 0.55)
    ..lineTo(bulb.dx + size * 0.62, bulb.dy)
    ..lineTo(bulb.dx - size * 0.62, bulb.dy)
    ..close();
  canvas.drawPath(shade, Paint()..color = BP.paper);
  canvas.drawPath(shade, ink);
  if (glow > 0) {
    canvas.drawCircle(
      bulb + const Offset(0, 3),
      size * 0.9,
      Paint()
        ..shader = ui.Gradient.radial(bulb, size * 0.9, [
          BP.amber.withValues(alpha: 0.45 * glow),
          BP.amber.withValues(alpha: 0),
        ]),
    );
    canvas.drawCircle(bulb + const Offset(0, 3), size * 0.14, Paint()..color = BP.amber.withValues(alpha: 0.4 + 0.6 * glow));
  }
}

/// Soft drifting fog lines around [y].
void paintFog(Canvas canvas, double x0, double x1, double y, double t, {double alpha = 0.10, int lines = 3}) {
  final p = Paint()
    ..color = BP.inkDim.withValues(alpha: alpha)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2
    ..strokeCap = StrokeCap.round;
  for (var k = 0; k < lines; k++) {
    final path = Path();
    final phase = t * (0.25 + 0.1 * k) + k * 2.1;
    final yy = y + k * 9;
    var first = true;
    for (var x = x0; x <= x1; x += 24) {
      final dy = math.sin(x / 140 + phase) * 4 + math.sin(x / 57 - phase * 1.7) * 2;
      if (first) {
        path.moveTo(x, yy + dy);
        first = false;
      } else {
        path.lineTo(x, yy + dy);
      }
    }
    canvas.drawPath(dashPath(path, dash: 40 + 20.0 * k, gap: 26), p);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Board props: pins, red string, tags, stamps
// ─────────────────────────────────────────────────────────────────────────────

void drawPin(Canvas canvas, Offset p, {Color color = BP.red, double r = 5.5}) {
  canvas.drawLine(p, p + Offset(r * 0.5, r * 1.4), Paint()
    ..color = BP.inkFaint
    ..strokeWidth = 1.4);
  canvas.drawCircle(p, r, Paint()..color = color);
  canvas.drawCircle(p - Offset(r * 0.3, r * 0.3), r * 0.3, Paint()..color = Colors.white.withValues(alpha: 0.55));
}

/// Red string from [a] to [b], sagging by [sag]; [progress] draws it on.
Path stringPath(Offset a, Offset b, {double sag = 14}) {
  final mid = Offset.lerp(a, b, 0.5)! + Offset(0, sag);
  return Path()
    ..moveTo(a.dx, a.dy)
    ..quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy);
}

void drawString(Canvas canvas, Offset a, Offset b,
    {double sag = 14, double progress = 1, double width = 1.6, double alpha = 0.9, Color color = BP.red}) {
  if (progress <= 0) return;
  var path = stringPath(a, b, sag: sag);
  if (progress < 1) path = partialPath(path, progress);
  canvas.drawPath(
    path,
    Paint()
      ..color = color.withValues(alpha: alpha)
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round,
  );
}

/// A luggage-style evidence tag: notched left end with a hole.
Path tagShape(Rect r) {
  final n = r.height * 0.42;
  return Path()
    ..moveTo(r.left + n, r.top)
    ..lineTo(r.right, r.top)
    ..lineTo(r.right, r.bottom)
    ..lineTo(r.left + n, r.bottom)
    ..lineTo(r.left, r.bottom - n)
    ..lineTo(r.left, r.top + n)
    ..close();
}

void paintTag(Canvas canvas, Rect r, {Color color = BP.amber, bool filled = false}) {
  final shape = tagShape(r);
  canvas.drawPath(shape, Paint()..color = filled ? color : Color.alphaBlend(color.withValues(alpha: 0.13), BP.paper));
  canvas.drawPath(
    shape,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3,
  );
  canvas.drawCircle(
    Offset(r.left + r.height * 0.36, r.center.dy),
    r.height * 0.1,
    Paint()
      ..color = filled ? BP.paper : color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2,
  );
}

/// An evidence tag as a widget: `[○ label]`.
class EvidenceTag extends StatelessWidget {
  const EvidenceTag(this.text, {super.key, this.color = BP.amber, this.size = 14, this.filled = false, this.style});

  final String text;
  final Color color;
  final double size;
  final bool filled;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _TagPainter(color, filled),
    child: Padding(
      padding: EdgeInsets.fromLTRB(size * 1.55, size * 0.3, size * 0.7, size * 0.34),
      child: Text(text, softWrap: false, style: style ?? BT.mono(size, color: filled ? BP.paper : color)),
    ),
  );
}

class _TagPainter extends CustomPainter {
  _TagPainter(this.color, this.filled);

  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) => paintTag(canvas, Offset.zero & size, color: color, filled: filled);

  @override
  bool shouldRepaint(_TagPainter old) => old.color != color || old.filled != filled;
}

/// A rubber stamp: double red frame, rotated, slams in with [t] 0..1.
void paintStamp(Canvas canvas, Offset center, TextPainter label, double t,
    {double angle = -0.18, Color color = BP.red, double pad = 22}) {
  if (t <= 0) return;
  final s = 1 + 0.9 * (1 - Curves.easeOutBack.transform(t.clamp(0.0, 1.0)));
  final a = (t * 3).clamp(0.0, 1.0);
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(angle);
  canvas.scale(s);
  final w = label.width + pad * 2;
  final h = label.height + pad * 1.1;
  final r = Rect.fromCenter(center: Offset.zero, width: w, height: h);
  final p = Paint()
    ..color = color.withValues(alpha: 0.92 * a)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4;
  canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), p);
  canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(8), const Radius.circular(3)), p..strokeWidth = 1.5);
  canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: a));
  label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
  canvas.restore();
  canvas.restore();
}

/// Magnifying glass: rim + handle. [angle] points from the lens to the handle.
void paintMagnifier(Canvas canvas, Offset center, double r,
    {double angle = math.pi / 4, Color rim = BP.ink, double handle = 1.2, double width = 1}) {
  final dir = Offset(math.cos(angle), math.sin(angle));
  final p = Paint()
    ..color = rim
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.5, r * 0.09) * width
    ..strokeCap = StrokeCap.round;
  canvas.drawCircle(center, r, p);
  canvas.drawCircle(center, r * 0.86, p..strokeWidth = math.max(0.8, r * 0.02) * width);
  final a = center + dir * (r * 1.02);
  final b = center + dir * (r * (1.02 + handle));
  canvas.drawLine(a, a + dir * (r * 0.18), Paint()
    ..color = rim
    ..strokeWidth = math.max(2, r * 0.1) * width
    ..strokeCap = StrokeCap.butt);
  canvas.drawLine(a + dir * (r * 0.18), b, Paint()
    ..color = BP.amber
    ..strokeWidth = math.max(3, r * 0.2) * width
    ..strokeCap = StrokeCap.round);
  // Glint
  canvas.drawArc(Rect.fromCircle(center: center, radius: r * 0.7), math.pi * 1.1, math.pi * 0.35, false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, r * 0.04)
        ..strokeCap = StrokeCap.round);
}

// ─────────────────────────────────────────────────────────────────────────────
// The detective
// ─────────────────────────────────────────────────────────────────────────────

/// Pose knobs, all 0..1 unless noted.
class DetPose {
  const DetPose({
    this.walk = 0,
    this.stride = 0,
    this.lens = 0,
    this.tip = 0,
    this.point = 0,
    this.pointAngle = -0.3,
    this.crouch = 0,
    this.facing = 1,
    this.torch = 0,
    this.look = 0,
    this.notes = 0,
    this.lean = 0,
  });

  /// Walk phase in radians, and how much of a step to take.
  final double walk;
  final double stride;

  /// Raise the magnifying glass to the eye.
  final double lens;

  /// Tip the hat.
  final double tip;

  /// Point (near arm) at [pointAngle] (radians from forward, negative = up).
  final double point;
  final double pointAngle;
  final double crouch;

  /// 1 = facing right, -1 = facing left.
  final double facing;

  /// Holding a torch instead of the lens (near hand), aimed by [pointAngle].
  final double torch;

  /// Tilt the head up (positive) or down.
  final double look;

  /// Writing in a notepad.
  final double notes;

  /// Lean forward (interrogation).
  final double lean;
}

/// Where things ended up, so scenes can attach light beams etc.
class DetRig {
  const DetRig({required this.head, required this.hand, required this.lens, required this.lensR, required this.aim});

  final Offset head;
  final Offset hand;
  final Offset lens;
  final double lensR;

  /// Unit direction the near hand aims (torch beam direction).
  final Offset aim;
}

/// Two-bone IK: the elbow for a shoulder [s], a hand target [h], bending
/// towards [bend] (±1).
Offset _elbow(Offset s, Offset h, double l1, double l2, double bend) {
  var d = h - s;
  var dist = d.distance;
  if (dist < 1e-3) return s + Offset(0, l1);
  if (dist > l1 + l2 - 0.01) {
    d = d / dist * (l1 + l2 - 0.01);
    dist = l1 + l2 - 0.01;
  }
  final a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist);
  final hh = math.sqrt(math.max(0, l1 * l1 - a * a));
  final u = d / dist;
  final n = Offset(-u.dy, u.dx) * bend;
  return s + u * a + n * hh;
}

/// Draws the detective standing on [feet] (the point between the feet),
/// [h] tall from sole to hat crown.
DetRig paintDetective(
  Canvas canvas,
  Offset feet,
  double h,
  DetPose p, {
  Color ink = BP.ink,
  Color hat = BP.amber,
  Color fill = BP.paper,
  double alpha = 1,
}) {
  final f = p.facing;
  final k = p.crouch;
  final bob = (math.sin(p.walk * 2).abs()) * 0.012 * p.stride;
  // Local (x forward, y up) in units of h → canvas.
  Offset P(double x, double y) => feet + Offset(x * f * h, -(y + bob) * h);

  final line = Paint()
    ..color = ink.withValues(alpha: alpha)
    ..strokeWidth = math.max(1.6, h * 0.016)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final thin = Paint()
    ..color = ink.withValues(alpha: alpha * 0.8)
    ..strokeWidth = math.max(1, h * 0.009)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final solid = Paint()..color = fill.withValues(alpha: alpha);

  final hipY = 0.42 - 0.13 * k;
  final lean = 0.06 * k + 0.08 * p.lean;
  final hip = P(0, hipY);
  final shoulderL = Offset(lean, 0.71 - 0.13 * k - 0.03 * p.lean);
  final shoulder = P(shoulderL.dx, shoulderL.dy);
  final headL = shoulderL + Offset(0.03 + 0.03 * p.lean, 0.115);
  final head = P(headL.dx, headL.dy);
  final headR = 0.066 * h;

  // Legs (drawn first, the coat covers their tops).
  final swing = 0.42 * p.stride * math.sin(p.walk);
  final stance = 0.1 * (1 - p.stride) * (1 - k);
  for (final s in [swing + stance, -swing - stance]) {
    final len = hipY;
    final back = s < 0 ? -s : 0.0;
    final knee = P(math.sin(s) * len * 0.5 + k * 0.08 + back * 0.03, hipY - math.cos(s) * len * 0.5 + k * 0.02);
    final foot = P(math.sin(s) * len * (1 - 0.45 * k) - k * 0.02, back * 0.05 * p.stride);
    canvas.drawLine(hip, knee, line);
    canvas.drawLine(knee, foot, line);
    canvas.drawLine(foot, foot + Offset(0.05 * f * h, 0), line);
  }

  // Far arm (tips the hat, or holds the notepad, or swings).
  final l1 = 0.17 * h, l2 = 0.16 * h;
  final farS = shoulder + Offset(-0.02 * f * h, 0);
  final farRest = P(shoulderL.dx - 0.08 * math.sin(p.walk) * p.stride, shoulderL.dy - 0.31);
  final farTip = P(headL.dx + 0.06, headL.dy + 0.07);
  final farNotes = P(shoulderL.dx + 0.14, shoulderL.dy - 0.12);
  var farHand = Offset.lerp(farRest, farNotes, p.notes)!;
  farHand = Offset.lerp(farHand, farTip, p.tip)!;
  final farElbow = _elbow(farS, farHand, l1, l2, -f);
  canvas.drawLine(farS, farElbow, line);
  canvas.drawLine(farElbow, farHand, line);

  // Trench coat: collar, a slight flare, the back tail swinging.
  final hemY = 0.22 - 0.06 * k;
  final flap = 0.03 * math.sin(p.walk) * p.stride;
  final coat = Path()
    ..moveTo(shoulder.dx - 0.075 * f * h, shoulder.dy + 0.01 * h)
    ..lineTo(P(-0.1 + lean * 0.6, 0.45 - 0.12 * k).dx, P(0, 0.45 - 0.12 * k).dy)
    ..lineTo(P(-0.13 + flap + lean * 0.5, hemY - 0.01).dx, P(0, hemY - 0.01).dy)
    ..lineTo(P(0.115 + lean * 0.5, hemY).dx, P(0, hemY).dy)
    ..lineTo(P(0.1 + lean * 0.6, 0.45 - 0.12 * k).dx, P(0, 0.45 - 0.12 * k).dy)
    ..lineTo(shoulder.dx + 0.075 * f * h, shoulder.dy + 0.01 * h)
    ..close();
  canvas.drawPath(coat, solid);
  canvas.drawPath(coat, line);
  // Collar V, belt, buttons.
  final neck = P(shoulderL.dx + 0.02, shoulderL.dy + 0.01);
  canvas.drawLine(shoulder + Offset(-0.05 * f * h, 0), P(shoulderL.dx + 0.03, shoulderL.dy - 0.09), thin);
  canvas.drawLine(shoulder + Offset(0.06 * f * h, 0), P(shoulderL.dx + 0.03, shoulderL.dy - 0.09), thin);
  final beltY = 0.47 - 0.12 * k;
  canvas.drawLine(P(-0.11 + lean * 0.6, beltY), P(0.12 + lean * 0.6, beltY), line);
  canvas.drawRect(Rect.fromCenter(center: P(0.03 + lean * 0.6, beltY), width: 0.035 * h, height: 0.03 * h),
      Paint()..color = hat.withValues(alpha: alpha));
  for (final by in [0.60, 0.36]) {
    canvas.drawCircle(P(0.05 + lean * (by > 0.5 ? 0.8 : 0.4), by - 0.12 * k), h * 0.006, Paint()..color = ink.withValues(alpha: alpha * 0.8));
  }
  canvas.drawLine(neck, P(shoulderL.dx + 0.03, shoulderL.dy + 0.04), line);

  // Head + face.
  canvas.drawCircle(head, headR, solid);
  canvas.drawCircle(head, headR, line);
  final lookY = p.look * 0.02;
  canvas.drawLine(P(headL.dx + 0.062, headL.dy - 0.005 + lookY), P(headL.dx + 0.085, headL.dy - 0.02 + lookY), line);
  canvas.drawCircle(P(headL.dx + 0.03, headL.dy + 0.012 + lookY), h * 0.006, Paint()..color = ink.withValues(alpha: alpha));

  // Hat (lifted and tilted when tipping).
  canvas.save();
  final brimFront = P(headL.dx + 0.1, headL.dy + 0.035);
  canvas.translate(brimFront.dx, brimFront.dy);
  canvas.rotate(-0.35 * p.tip * f);
  canvas.translate(-brimFront.dx, -brimFront.dy - 0.06 * h * p.tip);
  final brimY = headL.dy + 0.035;
  final crown = Path()
    ..moveTo(P(headL.dx - 0.07, brimY).dx, P(0, brimY).dy)
    ..lineTo(P(headL.dx - 0.06, brimY + 0.085).dx, P(0, brimY + 0.085).dy)
    ..lineTo(P(headL.dx - 0.005, brimY + 0.07).dx, P(0, brimY + 0.07).dy)
    ..lineTo(P(headL.dx + 0.06, brimY + 0.085).dx, P(0, brimY + 0.085).dy)
    ..lineTo(P(headL.dx + 0.07, brimY).dx, P(0, brimY).dy)
    ..close();
  final hatPaint = Paint()
    ..color = hat.withValues(alpha: alpha)
    ..strokeWidth = line.strokeWidth
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;
  canvas.drawPath(crown, Paint()..color = Color.alphaBlend(hat.withValues(alpha: 0.18 * alpha), fill.withValues(alpha: alpha)));
  canvas.drawPath(crown, hatPaint);
  canvas.drawLine(P(headL.dx - 0.068, brimY + 0.022), P(headL.dx + 0.068, brimY + 0.022), hatPaint..strokeWidth = line.strokeWidth * 1.6);
  hatPaint.strokeWidth = line.strokeWidth;
  final brim = Path()
    ..moveTo(P(headL.dx - 0.13, brimY - 0.012).dx, P(0, brimY - 0.012).dy)
    ..quadraticBezierTo(P(headL.dx, brimY + 0.01).dx, P(0, brimY + 0.01).dy, P(headL.dx + 0.14, brimY - 0.018).dx,
        P(0, brimY - 0.018).dy);
  canvas.drawPath(brim, hatPaint);
  canvas.restore();

  // Notepad in the far hand.
  if (p.notes > 0.3) {
    final pad = Rect.fromCenter(center: farHand + Offset(0.02 * f * h, -0.03 * h), width: 0.07 * h, height: 0.09 * h);
    canvas.drawRect(pad, Paint()..color = BP.paper.withValues(alpha: alpha));
    canvas.drawRect(pad, thin);
    for (var i = 0; i < 3; i++) {
      final y = pad.top + pad.height * (0.3 + i * 0.22);
      canvas.drawLine(Offset(pad.left + pad.width * 0.18, y), Offset(pad.right - pad.width * 0.18, y), thin);
    }
  }

  // Near arm: hangs & swings, raises the lens, points, or aims a torch.
  final nearS = shoulder + Offset(0.02 * f * h, 0);
  final rest = P(shoulderL.dx + 0.08 * math.sin(p.walk) * p.stride + 0.02, shoulderL.dy - 0.31);
  final eye = P(headL.dx + 0.17, headL.dy - 0.02);
  final pa = p.pointAngle;
  final reach = P(shoulderL.dx, shoulderL.dy) + Offset(math.cos(pa) * f, math.sin(pa)) * (0.3 * h);
  final writing = P(shoulderL.dx + 0.12, shoulderL.dy - 0.1);
  var hand = Offset.lerp(rest, eye, p.lens)!;
  hand = Offset.lerp(hand, reach, math.max(p.point, p.torch))!;
  hand = Offset.lerp(hand, writing, p.notes * (1 - p.lens))!;
  final nearElbow = _elbow(nearS, hand, l1, l2, f);
  canvas.drawLine(nearS, nearElbow, line);
  canvas.drawLine(nearElbow, hand, line);

  // Held item.
  final aimA = p.torch > 0 ? pa : -1.2 + 1.2 * (1 - p.lens);
  final aim = Offset(math.cos(aimA) * f, math.sin(aimA));
  var lensC = hand;
  var lensR = 0.0;
  if (p.torch > 0.5) {
    final a = hand;
    final b = hand + aim * (0.07 * h);
    canvas.drawLine(a, b, Paint()
      ..color = ink.withValues(alpha: alpha)
      ..strokeWidth = h * 0.028
      ..strokeCap = StrokeCap.butt);
    canvas.drawCircle(b, h * 0.012, Paint()..color = BP.amber.withValues(alpha: alpha));
    lensC = b;
  } else if (p.notes > 0.5 && p.lens < 0.2) {
    // pencil
    canvas.drawLine(hand, hand + Offset(0.02 * f * h, -0.05 * h), thin);
  } else {
    // Magnifier: handle in hand, lens up/forward (or dangling when relaxed).
    final up = p.lens;
    final ang = (1 - up) * (math.pi / 2 - 0.2 * f) + up * (-0.25);
    final dir = Offset(math.cos(ang) * (up > 0.5 ? f : 1), math.sin(ang));
    lensR = 0.05 * h * (1 + 0.25 * up);
    lensC = hand + dir * (lensR + 0.05 * h);
    paintMagnifier(canvas, lensC, lensR,
        angle: math.atan2(-dir.dy, -dir.dx), rim: ink.withValues(alpha: alpha), handle: 0.9);
  }
  return DetRig(head: head, hand: hand, lens: lensC, lensR: lensR, aim: aim);
}

/// Common scene painter bits: a blueprint "street" line with a curb.
void paintStreet(Canvas canvas, double y, double x0, double x1) {
  final p = Paint()
    ..color = BP.lineDim
    ..strokeWidth = 1.5;
  canvas.drawLine(Offset(x0, y), Offset(x1, y), p);
  canvas.drawPath(
    dashPath(Path()
      ..moveTo(x0, y + 10)
      ..lineTo(x1, y + 10), dash: 18, gap: 14),
    Paint()
      ..color = BP.lineFaint
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke,
  );
}

/// A cached set of [TextPainter]s for painters (never laid out per frame).
class LabelCache {
  final Map<String, TextPainter> _m = {};

  TextPainter get(String text, TextStyle style, {double maxWidth = double.infinity, TextAlign align = TextAlign.left}) {
    final k = '$text|${style.hashCode}|$maxWidth|$align';
    final hit = _m[k];
    if (hit != null) return hit;
    if (_m.length > 200) clear();
    return _m[k] = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: maxWidth);
  }

  void clear() {
    for (final p in _m.values) {
      p.dispose();
    }
    _m.clear();
  }

  void dispose() => clear();
}

/// A repaint driver: one ticker, a time notifier, no widget rebuilds.
class NoirTicker extends StatefulWidget {
  const NoirTicker({super.key, required this.builder});

  final Widget Function(BuildContext context, ValueListenable<double> time) builder;

  @override
  State<NoirTicker> createState() => _NoirTickerState();
}

class _NoirTickerState extends State<NoirTicker> with SingleTickerProviderStateMixin {
  final _time = ValueNotifier<double>(0);
  late final _ticker = createTicker((d) => _time.value = d.inMicroseconds / 1e6)..start();

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _time);
}

/// Paints a case glyph from its real outline (FontData), fitted in a square
/// centred in the canvas. Optional: the JP/SC difference, on-curve points.
class CaseGlyphPainter extends CustomPainter {
  CaseGlyphPainter({
    required this.cp,
    required this.japanese,
    this.fill,
    this.stroke,
    this.strokeWidth = 2,
    this.diff = 0,
    this.points = 0,
    this.dashed = false,
    super.repaint,
  });

  final int cp;
  final bool japanese;
  final Color? fill;
  final Color? stroke;
  final double strokeWidth;

  /// Alpha of the red JP-xor-SC overlay (0 = off).
  final double diff;

  /// Alpha of the on-curve point markers (0 = off).
  final double points;
  final bool dashed;

  static Rect squareIn(Size size) {
    final s = math.min(size.width, size.height);
    return Rect.fromLTWH((size.width - s) / 2, (size.height - s) / 2, s, s);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final f = CaseFonts.ready;
    if (f == null) return;
    final box = squareIn(size);
    final path = emToBox(f.em(japanese, cp), box);
    if (fill != null) canvas.drawPath(path, Paint()..color = fill!);
    if (diff > 0) {
      canvas.drawPath(emToBox(f.xor(cp), box), Paint()..color = BP.red.withValues(alpha: diff));
    }
    if (stroke != null) {
      canvas.drawPath(
        dashed ? dashPath(path, dash: 5, gap: 4) : path,
        Paint()
          ..color = stroke!
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeJoin = StrokeJoin.round,
      );
    }
    if (points > 0) {
      final s = box.width / 1000;
      final on = Paint()..color = (stroke ?? BP.line).withValues(alpha: points);
      final off = Paint()
        ..color = (stroke ?? BP.line).withValues(alpha: points * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      for (final c in f.outline(japanese, cp).contours) {
        for (final p in c) {
          final q = Offset(box.left + p.x * s, box.top + (880 - p.y) * s);
          if (p.onCurve) {
            canvas.drawRect(Rect.fromCenter(center: q, width: 5, height: 5), on);
          } else {
            canvas.drawCircle(q, 2.6, off);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(CaseGlyphPainter old) =>
      old.cp != cp ||
      old.japanese != japanese ||
      old.fill != fill ||
      old.stroke != stroke ||
      old.diff != diff ||
      old.points != points ||
      old.strokeWidth != strokeWidth ||
      old.dashed != dashed;
}

/// A pinned "photo" frame (polaroid-ish, line-drawn) with a caption slot.
class PinnedPhoto extends StatelessWidget {
  const PinnedPhoto({
    super.key,
    required this.child,
    this.caption,
    this.width = 300,
    this.height = 360,
    this.color = BP.lineDim,
    this.fill = BP.panel,
    this.pin = true,
  });

  final Widget child;
  final Widget? caption;
  final double width;
  final double height;
  final Color color;
  final Color fill;
  final bool pin;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: CustomPaint(
      painter: _PhotoPainter(color, fill, pin),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
        child: Column(
          children: [
            Expanded(child: child),
            if (caption != null) ...[const SizedBox(height: 10), caption!],
          ],
        ),
      ),
    ),
  );
}

class _PhotoPainter extends CustomPainter {
  _PhotoPainter(this.color, this.fill, this.pin);

  final Color color;
  final Color fill;
  final bool pin;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = fill);
    canvas.drawRect(
      r,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    final t = Paint()
      ..color = BP.line
      ..strokeWidth = 2;
    for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      final dx = c.dx == 0 ? 8.0 : -8.0;
      final dy = c.dy == 0 ? 8.0 : -8.0;
      canvas.drawLine(c, c + Offset(dx, 0), t);
      canvas.drawLine(c, c + Offset(0, dy), t);
    }
    if (pin) drawPin(canvas, Offset(size.width / 2, 8), r: 6);
  }

  @override
  bool shouldRepaint(_PhotoPainter old) => old.color != color || old.fill != fill || old.pin != pin;
}
