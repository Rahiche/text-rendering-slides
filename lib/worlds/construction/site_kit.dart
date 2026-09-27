import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The construction site's shared cast and props: the same stick-figure crew,
// trucks, forklifts, crates, cones and tower cranes appear on the title, the
// section dividers, the pipeline, the journey map, the outro, the ambient
// scenery and the ruler.
//
// Everything is drawn with plain strokes on the blueprint paper, as a pure
// function of a clock `t` (seconds), so nothing accumulates over time.
// ─────────────────────────────────────────────────────────────────────────────

// ── Math helpers (hashes are float based: identical on native and the web) ──

double c01(double v) => v.clamp(0.0, 1.0);
double seg01(double t, double a, double b) => c01((t - a) / (b - a));
double eio(double v) => Curves.easeInOutCubic.transform(c01(v));
double eo(double v) => Curves.easeOutCubic.transform(c01(v));
double ei(double v) => Curves.easeInCubic.transform(c01(v));
double backOut(double v) => Curves.easeOutBack.transform(c01(v));
double lerpD(double a, double b, double t) => a + (b - a) * t;

double hash1(double x) {
  final s = math.sin(x * 12.9898 + 78.233) * 43758.5453;
  return s - s.floorToDouble();
}

double hash2(double a, double b) => hash1(a * 1.618 + b * 57.31);

/// 1 inside [a+fade, b-fade], ramps at both ends, 0 outside [a, b].
double winAt(double t, double a, double b, [double fade = 0.3]) => seg01(t, a, a + fade) * (1 - seg01(t, b - fade, b));

Paint strokeP(Color c, [double w = 1]) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

Paint fillP(Color c) => Paint()..color = c;

Path lineP(Offset a, Offset b) => Path()
  ..moveTo(a.dx, a.dy)
  ..lineTo(b.dx, b.dy);

/// Japanese text: our display font first (for Latin), then the platform's
/// Japanese face (Hiragino on Apple; the web downloads Noto Sans JP).
TextStyle jaStyle(double size, {Color color = BP.ink, double weight = 400, double? height}) => BT
    .sample(size, color: color, weight: weight, height: height)
    .copyWith(
      locale: const Locale('ja'),
      fontFamilyFallback: const [BP.arabic, 'Hiragino Sans', 'Hiragino Kaku Gothic ProN'],
    );

// ── Cached label painters (a small, bounded set of strings) ─────────────────

enum LabelFont { mono, display, ja }

class SiteLabels {
  final _cache = <String, TextPainter>{};

  TextPainter get(String text, double size, Color color, {bool display = false, LabelFont? font, double weight = 400}) {
    final f = font ?? (display ? LabelFont.display : LabelFont.mono);
    // Quantise alpha so fades don't flood the cache.
    color = color.withValues(alpha: (color.a * 16).round() / 16);
    final key = '$size|${color.toARGB32()}|${f.index}|$weight|$text';
    var p = _cache[key];
    if (p == null) {
      if (_cache.length > 400) clear();
      final style = switch (f) {
        LabelFont.mono => BT.mono(size, color: color, weight: weight),
        LabelFont.display => BT.display(size, color: color, weight: weight),
        LabelFont.ja => jaStyle(size, color: color, weight: weight),
      };
      p = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      _cache[key] = p;
    }
    return p;
  }

  /// Draws [text] anchored at [at] ([ax], [ay] = 0 left/top … 1 right/bottom).
  Size draw(
    Canvas c,
    String text,
    Offset at, {
    double size = 11,
    Color color = BP.inkDim,
    double alpha = 1,
    double ax = 0,
    double ay = 0,
    bool display = false,
    LabelFont? font,
    double weight = 400,
  }) {
    final q = (alpha.clamp(0.0, 1.0) * 8).round();
    if (q == 0) return Size.zero;
    final p = get(
      text,
      size,
      color.withValues(alpha: color.a * q / 8),
      display: display,
      font: font,
      weight: weight,
    );
    p.paint(c, at - Offset(p.width * ax, p.height * ay));
    return p.size;
  }

  void clear() {
    for (final p in _cache.values) {
      p.dispose();
    }
    _cache.clear();
  }
}

// ── The crew: stick figures with amber hard hats ────────────────────────────

/// Two-bone limb from [a] to [b] with total length [len], bending to [bend].
void _limb(Path p, Offset a, Offset b, double len, double bend) {
  var d = (b - a).distance;
  if (d < 0.01) return;
  final dir = (b - a) / d;
  if (d > len) {
    b = a + dir * len;
    d = len;
  }
  final h = math.sqrt(math.max(0, len * len / 4 - d * d / 4));
  final knee = (a + b) / 2 + Offset(-dir.dy, dir.dx) * (h * bend);
  p
    ..moveTo(a.dx, a.dy)
    ..lineTo(knee.dx, knee.dy)
    ..lineTo(b.dx, b.dy);
}

/// Batches every stick figure into two paths (bodies, hard hats).
class SiteCrew {
  SiteCrew({this.ink = BP.ink, this.hat = BP.amber, this.width = 1.6, this.scale = 1.2});

  final Color ink;
  final Color hat;
  final double width;

  /// Default figure scale (1.2 ≈ 31 px tall).
  final double scale;

  final body = Path();
  final hats = Path();

  void flush(Canvas c) {
    c.drawPath(body, strokeP(ink, width));
    c.drawPath(hats, fillP(hat));
    body.reset();
    hats.reset();
  }

  /// A worker. Returns (front hand, back hand, head).
  (Offset, Offset, Offset) figure(
    Offset hip, {
    required Offset footA,
    required Offset footB,
    double face = 1,
    double lean = 0,
    double armF = 0.25,
    double armB = -0.2,
    Offset? handF,
    Offset? handB,
    double? s,
    bool hat = true,
  }) {
    final k = s ?? scale;
    _limb(body, hip, footA, 11 * k, -face);
    _limb(body, hip, footB, 11 * k, -face);
    final up = Offset(math.sin(lean) * face, -math.cos(lean));
    final sh = hip + up * (9 * k);
    body
      ..moveTo(hip.dx, hip.dy)
      ..lineTo(sh.dx, sh.dy);
    final head = sh + up * (4.6 * k);
    body.addOval(Rect.fromCircle(center: head, radius: 3.1 * k));
    Offset arm(double a) => sh + Offset(math.sin(a + lean) * face, math.cos(a + lean)) * (8.5 * k);
    final hf = handF ?? arm(armF);
    final hb = handB ?? arm(armB);
    _limb(body, sh, hf, 8.5 * k, face);
    _limb(body, sh, hb, 8.5 * k, face);
    if (hat) {
      final hc = head + up * (0.9 * k);
      hats
        ..addArc(Rect.fromCircle(center: hc, radius: 3.8 * k), math.pi + lean * face, math.pi)
        ..close();
      final bx = Offset(-up.dy, up.dx);
      final b0 = hc - bx * (4.2 * k) + up * 0.2;
      final b1 = hc + bx * (5.4 * k * face);
      hats
        ..moveTo(b0.dx, b0.dy)
        ..lineTo(b1.dx, b1.dy)
        ..lineTo(b1.dx - up.dx * 1.4 * k, b1.dy - up.dy * 1.4 * k + 1.2 * k)
        ..lineTo(b0.dx, b0.dy + 1.2 * k)
        ..close();
    }
    return (hf, hb, head);
  }

  /// Just a head and hard hat (drivers, the crane operator).
  void head(Offset head, double face, {double? s}) {
    final k = s ?? scale;
    body.addOval(Rect.fromCircle(center: head, radius: 3.1 * k));
    final hc = head + Offset(0, -0.9 * k);
    hats
      ..addArc(Rect.fromCircle(center: hc, radius: 3.8 * k), math.pi, math.pi)
      ..close()
      ..addRect(
        Rect.fromLTRB(
          hc.dx - (face > 0 ? 4.2 : 5.4) * k,
          hc.dy - 0.2,
          hc.dx + (face > 0 ? 5.4 : 4.2) * k,
          hc.dy + 1.3 * k,
        ),
      );
  }

  /// Standing / walking worker with feet at [feet]. [walk] is the gait phase.
  (Offset, Offset, Offset) walker(
    Offset feet, {
    double face = 1,
    double walk = 0,
    double stride = 1,
    double lean = 0,
    double? armF,
    double? armB,
    Offset? handF,
    Offset? handB,
    double? s,
    bool hat = true,
  }) {
    final k = s ?? scale;
    final sw = math.sin(walk) * stride;
    final fa = feet + Offset(sw * 4 * k * face, -math.max(0, math.cos(walk)) * 2 * k * stride);
    final fb = feet + Offset(-sw * 4 * k * face, -math.max(0, -math.cos(walk)) * 2 * k * stride);
    final hip = feet + Offset(0, (-10.4 + 0.5 * math.cos(2 * walk) * stride) * k);
    return figure(
      hip,
      footA: fa,
      footB: fb,
      face: face,
      lean: lean,
      armF: armF ?? -sw * 0.55,
      armB: armB ?? sw * 0.55,
      handF: handF,
      handB: handB,
      s: k,
      hat: hat,
    );
  }

  /// Seated worker; [seat] is the point the hips rest on.
  (Offset, Offset, Offset) sitter(
    Offset seat, {
    double face = 1,
    double armF = 0.3,
    double armB = -0.1,
    Offset? handF,
    double lean = 0,
    double? s,
  }) {
    final k = s ?? scale;
    final fa = seat + Offset(7 * k * face, 9 * k);
    final fb = seat + Offset(5 * k * face, 9 * k);
    return figure(seat, footA: fa, footB: fb, face: face, armF: armF, armB: armB, handF: handF, lean: lean, s: k);
  }

  /// Arms up, hopping: the whole crew cheers.
  (Offset, Offset, Offset) cheer(Offset feet, double t, {double face = 1, double seed = 0, double? s}) {
    final hop = -(math.sin(t * 9 + seed * 2.1).abs()) * 4;
    final wave = math.sin(t * 7 + seed) * 0.25;
    return walker(feet + Offset(0, hop), face: face, stride: 0, armF: 2.75 + wave, armB: 2.9 - wave, s: s);
  }
}

// ── Props, vehicles and particles, bound to one canvas and one clock ────────

class SiteKit {
  SiteKit(this.c, this.t, this.labels, this.crew);

  final Canvas c;
  final double t;
  final SiteLabels labels;
  final SiteCrew crew;

  // Particles (stateless: a pure function of t).

  void sparks(
    Offset Function(double back) src, {
    int n = 10,
    double life = 0.45,
    double seed = 0,
    double power = 1,
    bool Function(double born)? gate,
  }) {
    final hot = Path();
    final cool = Path();
    for (var i = 0; i < n; i++) {
      final ph = t / life + i / n + seed * 0.37;
      final cyc = ph.floorToDouble();
      final age = (ph - cyc) * life;
      if (gate != null && !gate(t - age)) continue;
      final r1 = hash2(cyc + seed * 13, i.toDouble());
      final r2 = hash2(i + 0.5, cyc - seed);
      final ang = -math.pi / 2 + (r1 - 0.5) * 2.8;
      final v = Offset(math.cos(ang), math.sin(ang)) * ((50 + 150 * r2) * power);
      final pos = src(age) + v * age + Offset(0, 300 * age * age);
      final vel = v + Offset(0, 600 * age);
      final tail = pos - vel * 0.016;
      (age < life * 0.45 ? hot : cool)
        ..moveTo(tail.dx, tail.dy)
        ..lineTo(pos.dx, pos.dy);
    }
    c.drawPath(hot, strokeP(BP.amber, 1.4));
    c.drawPath(cool, strokeP(BP.coral.withValues(alpha: 0.75), 1));
  }

  void sweat(Offset head, double face, double seed) {
    for (var i = 0; i < 2; i++) {
      final ph = (t / 0.8 + i * 0.5 + seed * 0.29) % 1.0;
      final p = head + Offset(-face * (4 + ph * 9), -3 - 8 * ph + 26 * ph * ph);
      c.drawCircle(p, 1.3, fillP(BP.line.withValues(alpha: 1 - ph)));
    }
  }

  void steam(Offset cup, double seed, {double alpha = 0.7}) {
    final p = Path();
    for (var i = 0; i < 2; i++) {
      final ph = (t * 0.6 + i * 0.5 + seed) % 1.0;
      final y = cup.dy - 3 - ph * 16;
      final x = cup.dx + math.sin(ph * 7 + i * 2) * 2.5;
      p
        ..moveTo(x, y)
        ..quadraticBezierTo(x + 2.5, y - 3, x, y - 6);
    }
    c.drawPath(p, strokeP(BP.inkDim.withValues(alpha: alpha), 1));
  }

  /// "z z" of a dozing worker; [u] is the local time of the doze.
  void snore(Offset head, double u) {
    for (var i = 0; i < 2; i++) {
      final ph = (u / 1.5 + i * 0.5) % 1.0;
      labels.draw(
        c,
        'z',
        head + Offset(-4 - 10 * ph, -10 - 16 * ph),
        size: 12,
        color: BP.inkDim,
        alpha: 1 - ph,
        ax: 0.5,
        ay: 0.5,
      );
    }
  }

  /// Puffs of dust kicked up at [at]; [age] seconds since the impact.
  void dust(
    Offset at,
    double age, {
    double seed = 0,
    int n = 6,
    double spread = 60,
    double life = 0.9,
    double alpha = 0.7,
  }) {
    if (age < 0 || age > life) return;
    final f = age / life;
    final p = strokeP(BP.inkDim.withValues(alpha: alpha * (1 - f)), 1);
    for (var i = 0; i < n; i++) {
      final side = i.isEven ? -1.0 : 1.0;
      final r = hash2(i + seed, seed * 3.1);
      final x = at.dx + side * (8 + spread * (0.3 + 0.7 * r) * eo(f));
      final y = at.dy - 4 - 16 * eo(f) * (0.5 + r);
      c.drawCircle(Offset(x, y), 3 + 9 * eo(f) * (0.6 + 0.4 * r), p);
    }
  }

  /// A firework: a rocket climbs to [burst] for [climb] s, then bursts.
  void firework(
    Offset launch,
    Offset burst,
    double age,
    double seed,
    Color color, {
    double climb = 0.7,
    double life = 1.6,
    int n = 22,
    double radius = 95,
  }) {
    if (age < 0) return;
    if (age < climb) {
      final f = eo(age / climb);
      final p = Offset.lerp(launch, burst, f)!;
      final back = Offset.lerp(launch, burst, math.max(0, f - 0.12))!;
      c.drawLine(back, p, strokeP(BP.amber.withValues(alpha: 0.8), 1.4));
      c.drawCircle(p, 1.8, fillP(BP.ink));
      return;
    }
    final u = age - climb;
    if (u > life) return;
    final f = u / life;
    final fade = 1 - ei(f);
    final hot = Path();
    for (var i = 0; i < n; i++) {
      final a = i / n * math.pi * 2 + hash2(seed, i.toDouble()) * 0.25;
      final sp = radius * (0.75 + 0.25 * hash2(i + 3.3, seed));
      final d = sp * eo(math.min(1, u / (life * 0.55)));
      final sag = 38 * f * f;
      final p = burst + Offset(math.cos(a) * d, math.sin(a) * d + sag);
      final q = burst + Offset(math.cos(a) * d * 0.82, math.sin(a) * d * 0.82 + sag * 0.8);
      hot
        ..moveTo(q.dx, q.dy)
        ..lineTo(p.dx, p.dy);
      // Glitter: a few sparks twinkle at the tips late in the burst.
      if (f > 0.45 && hash2(i.toDouble(), (t * 12).floorToDouble() + seed) > 0.6) {
        c.drawCircle(p, 1.3, fillP(BP.ink.withValues(alpha: fade)));
      }
    }
    c.drawPath(hot, strokeP(color.withValues(alpha: fade), 1.6));
    if (u < 0.12) {
      c.drawCircle(burst, 5 * (1 - u / 0.12) + 2, fillP(BP.ink.withValues(alpha: 0.5)));
    }
  }

  // Vehicles.

  void wheel(Offset at, double r, double travel, {Color ink = BP.line}) {
    c.drawCircle(at, r, fillP(BP.paper));
    c.drawCircle(at, r, strokeP(ink, 1.2));
    final a = travel / r;
    c.drawLine(at, at + Offset(math.cos(a), math.sin(a)) * (r - 1), strokeP(BP.lineDim, 1));
  }

  /// kind: 0 box truck, 1 mixer, 2 dump truck, 3 flatbed with crates,
  /// 4 empty flatbed (the caller draws the load at `lane - 16`).
  /// [lane] is the chassis line; the wheels sit 7 px under it.
  void truck(
    double x,
    double lane,
    double face,
    int kind,
    String? label, {
    double load = 0,
    Color loadColor = BP.ink,
    double labelSize = 10,
  }) {
    Offset p(double lx, double ly) => Offset(x + lx * face, lane + ly);
    Path poly(List<(double, double)> pts) {
      final path = Path();
      for (var i = 0; i < pts.length; i++) {
        final o = p(pts[i].$1, pts[i].$2);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      return path..close();
    }

    final ink = strokeP(BP.line, 1.3);
    final paper = fillP(BP.paper);
    final cab = poly(const [(30, -12), (30, -42), (48, -42), (63, -27), (63, -12)]);
    c.drawPath(cab, paper);
    c.drawPath(cab, ink);
    c.drawPath(poly(const [(34, -38), (47, -38), (58, -28), (34, -28)]), strokeP(BP.lineDim, 1));
    crew.head(p(41, -31), face);
    c.drawLine(p(-90, -12), p(63, -12), ink);
    switch (kind) {
      case 0:
        final box = poly(const [(-92, -54), (26, -54), (26, -14), (-92, -14)]);
        c.drawPath(box, paper);
        c.drawPath(box, ink);
        if (label != null) {
          labels.draw(c, label, p(-33, -34), size: labelSize, color: BP.amber, ax: 0.5, ay: 0.5);
        }
      case 1:
        final ctr = p(-30, -34);
        c.save();
        c.translate(ctr.dx, ctr.dy);
        c.rotate(-0.14 * face);
        final drum = Rect.fromCenter(center: Offset.zero, width: 100, height: 38);
        c.drawOval(drum, paper);
        c.drawOval(drum, ink);
        c.clipPath(Path()..addOval(drum));
        final stripes = Path();
        for (var i = 0; i < 5; i++) {
          final sx = ((i / 5 + t * 0.35 * face) % 1.0) * 120 - 60;
          stripes
            ..moveTo(sx - 8, -19)
            ..lineTo(sx + 8, 19);
        }
        c.drawPath(stripes, strokeP(BP.lineDim, 1.2));
        c.restore();
      case 2:
        final bed = poly(const [(-92, -46), (24, -46), (24, -14), (-84, -14)]);
        c.drawPath(bed, paper);
        c.drawPath(bed, ink);
        if (load > 0) {
          final rubble = Path();
          final n = (14 * load).round();
          for (var i = 0; i < n; i++) {
            final o = p(-84 + 102 * hash1(i + 0.3), -50 - 6 * hash1(i + 7.7));
            rubble.addRect(Rect.fromCenter(center: o, width: 5, height: 5));
          }
          c.drawPath(rubble, fillP(loadColor.withValues(alpha: 0.8)));
        }
      case 3:
        c.drawLine(p(-92, -16), p(26, -16), ink);
        for (var i = 0; i < 3; i++) {
          final r = Rect.fromPoints(p(-88 + i * 34.0, -16), p(-62 + i * 34.0, -34));
          c.drawRect(r, paper);
          c.drawRect(r, strokeP(BP.line, 1.1));
          c.drawLine(r.topLeft, r.bottomRight, strokeP(BP.lineDim, 1));
        }
      default:
        c.drawLine(p(-92, -16), p(26, -16), ink);
        c.drawLine(p(-92, -16), p(-92, -22), ink);
    }
    for (final wx in const [-70.0, -52.0, 44.0]) {
      wheel(p(wx, -7), 7, x);
    }
  }

  /// Forklift at [ax] (fork tip x) on [lane]; the forks drop to [ground].
  void forklift(double ax, double lane, double ground, double lift) {
    final y = lane;
    final forkY = lerpD(y - 6, ground, lift);
    final body = Path()
      ..moveTo(ax - 62, y - 6)
      ..lineTo(ax - 62, y - 17)
      ..lineTo(ax - 55, y - 21)
      ..lineTo(ax - 27, y - 21)
      ..lineTo(ax - 27, y - 6)
      ..close();
    c.drawPath(body, fillP(BP.paper));
    c.drawPath(body, strokeP(BP.line, 1.2));
    final guard = Path()
      ..moveTo(ax - 53, y - 21)
      ..lineTo(ax - 53, y - 44)
      ..lineTo(ax - 30, y - 44)
      ..lineTo(ax - 30, y - 21);
    c.drawPath(guard, strokeP(BP.lineDim, 1.2));
    c.drawLine(Offset(ax - 25, y - 4), Offset(ax - 25, y - 48), strokeP(BP.line, 1.6));
    c.drawLine(Offset(ax - 25, forkY), Offset(ax + 20, forkY), strokeP(BP.line, 1.8));
    for (final wx in [ax - 52.0, ax - 34.0]) {
      wheel(Offset(wx, y - 5), 5, ax);
    }
    crew.sitter(Offset(ax - 43, y - 21), face: 1, handF: Offset(ax - 32, y - 27));
  }

  // Props.

  /// A crate stamped with [label]; [open] pops the lid, [gone] folds it.
  void crate(
    Offset bottom,
    String label,
    double open,
    double gone, {
    Color stamp = BP.amber,
    double w = 44,
    double h = 26,
    double labelSize = 9.5,
  }) {
    if (gone >= 1) return;
    final a = 1 - gone;
    final hh = h * (1 - 0.8 * ei(gone));
    final r = Rect.fromLTRB(bottom.dx - w / 2, bottom.dy - hh, bottom.dx + w / 2, bottom.dy);
    c.drawRect(r, fillP(BP.paper));
    c.drawRect(r, strokeP(BP.line.withValues(alpha: a), 1.2));
    c.drawLine(
      r.topLeft + const Offset(0, 5),
      r.topRight + const Offset(0, 5),
      strokeP(BP.lineDim.withValues(alpha: a), 1),
    );
    if (gone < 0.3) {
      labels.draw(c, label, r.center + const Offset(0, 3), size: labelSize, color: stamp, ax: 0.5, ay: 0.5, alpha: a);
    }
    if (open < 1) {
      final e = eo(open);
      c.save();
      c.translate(r.center.dx + 16 * e, r.top - 2 - 18 * math.sin(e * math.pi * 0.8));
      c.rotate(-0.7 * e);
      c.drawLine(Offset(-w / 2 - 1, 0), Offset(w / 2 + 1, 0), strokeP(BP.line.withValues(alpha: 1 - e), 2.4));
      c.restore();
    }
  }

  /// A traffic cone standing on [base].
  void cone(Offset base, {double alpha = 1, double s = 1}) {
    final p = Path()
      ..moveTo(base.dx - 5 * s, base.dy)
      ..lineTo(base.dx, base.dy - 13 * s)
      ..lineTo(base.dx + 5 * s, base.dy)
      ..close();
    c.drawPath(p, strokeP(BP.coral.withValues(alpha: alpha), 1.2));
    c.drawLine(
      Offset(base.dx - 2.8 * s, base.dy - 6 * s),
      Offset(base.dx + 2.8 * s, base.dy - 6 * s),
      strokeP(BP.ink.withValues(alpha: alpha), 1),
    );
    c.drawLine(
      Offset(base.dx - 7 * s, base.dy),
      Offset(base.dx + 7 * s, base.dy),
      strokeP(BP.coral.withValues(alpha: alpha), 1.2),
    );
  }

  /// A hanging cradle for a worker on ropes; ropes go up to [ropeTop].
  void cradle(Offset feet, double ropeTop) {
    c.drawLine(Offset(feet.dx - 11, feet.dy + 1), Offset(feet.dx + 11, feet.dy + 1), strokeP(BP.lineDim, 2.4));
    final rope = strokeP(BP.lineFaint, 1);
    c.drawLine(Offset(feet.dx - 10, feet.dy), Offset(feet.dx - 10, ropeTop), rope);
    c.drawLine(Offset(feet.dx + 10, feet.dy), Offset(feet.dx + 10, ropeTop), rope);
  }

  /// Trolley on the jib at [x], cables down to a hook block at [hookY].
  void trolley(double x, double jibY, double hookY, {double alpha = 1}) {
    final line = strokeP(BP.line.withValues(alpha: alpha), 1.2);
    final r = Rect.fromLTRB(x - 10, jibY + 1, x + 10, jibY + 8);
    c.drawRect(r, fillP(BP.paper));
    c.drawRect(r, line);
    final cable = strokeP(BP.inkDim.withValues(alpha: alpha), 1);
    c.drawLine(Offset(x - 3, jibY + 8), Offset(x - 3, hookY - 10), cable);
    c.drawLine(Offset(x + 3, jibY + 8), Offset(x + 3, hookY - 10), cable);
    hook(x, hookY, alpha: alpha);
  }

  /// Hook block + hook; [y] is the bottom of the block.
  void hook(double x, double y, {double alpha = 1, Color color = BP.amber}) {
    final block = Rect.fromLTRB(x - 6, y - 11, x + 6, y - 2);
    c.drawRect(block, fillP(BP.paper));
    c.drawRect(block, strokeP(color.withValues(alpha: alpha), 1.3));
    final h = Path()
      ..moveTo(x, y - 2)
      ..lineTo(x, y + 3)
      ..arcTo(Rect.fromCircle(center: Offset(x - 3, y + 3), radius: 3), 0, math.pi * 0.9, false);
    c.drawPath(h, strokeP(color.withValues(alpha: alpha), 1.5));
  }

  /// Two slings from the hook at [hook] to [a] and [b].
  void slings(Offset hook, Offset a, Offset b, {double alpha = 1}) {
    final p = strokeP(BP.inkDim.withValues(alpha: alpha), 1);
    c.drawLine(hook, a, p);
    c.drawLine(hook, b, p);
  }

  /// A steel I-beam, drawn as its side view.
  void beam(Rect r, {Color color = BP.line, double alpha = 1, bool holes = true}) {
    final col = color.withValues(alpha: alpha);
    c.drawRect(r, fillP(BP.paper));
    c.drawLine(r.topLeft, r.topRight, strokeP(col, 2.4));
    c.drawLine(r.bottomLeft, r.bottomRight, strokeP(col, 2.4));
    c.drawRect(r.deflate(0.5), strokeP(col.withValues(alpha: col.a * 0.6), 1));
    if (holes && r.width > 60) {
      for (final x in [r.left + 9, r.right - 9]) {
        c.drawCircle(Offset(x, r.center.dy), 2, strokeP(col, 1));
      }
    }
  }

  /// Site board: a sign on two posts planted at [ground].
  Rect board(Offset center, double w, double h, double ground, {Color color = BP.lineDim, double alpha = 1}) {
    final r = Rect.fromCenter(center: center, width: w, height: h);
    final col = color.withValues(alpha: alpha);
    c.drawLine(Offset(r.left + w * 0.22, r.bottom), Offset(r.left + w * 0.22, ground), strokeP(col, 1.2));
    c.drawLine(Offset(r.right - w * 0.22, r.bottom), Offset(r.right - w * 0.22, ground), strokeP(col, 1.2));
    c.drawRect(r, fillP(BP.paper));
    c.drawRect(r, strokeP(col, 1.2));
    return r;
  }

  /// A tower crane in the title's style. Static, so its path is cached.
  void towerCrane({
    required double mastL,
    required double mastR,
    required double ground,
    required double jibY,
    required double jibL,
    required double jibR,
    Color color = BP.lineDim,
    double alpha = 1,
    bool operator = true,
  }) {
    final key = '$mastL|$mastR|$ground|$jibY|$jibL|$jibR';
    final path = _cranes[key] ??= _cranePath(mastL, mastR, ground, jibY, jibL, jibR);
    if (_cranes.length > 24) _cranes.clear();
    c.drawPath(path, strokeP(color.withValues(alpha: color.a * alpha), 1.1));
    c.drawLine(Offset(jibL, jibY), Offset(jibR, jibY), strokeP(BP.line.withValues(alpha: alpha), 1.3));
    if (operator) crew.head(Offset(mastL - 16, jibY + 23), -1);
  }

  static final _cranes = <String, Path>{};

  static Path _cranePath(double mastL, double mastR, double ground, double jibY, double jibL, double jibR) {
    final p = Path();
    final jibTop = jibY - 20;
    final top = jibY + 32;
    final mid = (mastL + mastR) / 2;
    p
      ..moveTo(mastL, top)
      ..lineTo(mastL, ground)
      ..moveTo(mastR, top)
      ..lineTo(mastR, ground);
    var left = true;
    final step = (mastR - mastL) * 0.46;
    for (var y = top; y < ground - 1; y += step) {
      p
        ..moveTo(left ? mastL : mastR, y)
        ..lineTo(left ? mastR : mastL, math.min(ground, y + step));
      left = !left;
    }
    // Slewing unit + cat-head.
    p
      ..addRect(Rect.fromLTRB(mastL - 6, jibY + 18, mastR + 6, top))
      ..moveTo(mastL, jibTop)
      ..lineTo(mid, jibY - 56)
      ..lineTo(mastR, jibTop)
      ..moveTo(mid, jibY - 56)
      ..lineTo(mid, jibY + 18);
    // Jib: the top chord tapers towards the tip.
    p
      ..moveTo(jibL, jibY - 8)
      ..lineTo(mastL, jibTop)
      ..moveTo(mastR, jibTop + 6)
      ..lineTo(jibR, jibTop + 6)
      ..moveTo(jibL, jibY - 8)
      ..lineTo(jibL, jibY)
      ..moveTo(jibR, jibTop + 6)
      ..lineTo(jibR, jibY);
    double topAt(double x) => lerpD(jibY - 8, jibTop, (x - jibL) / (mastL - jibL));
    var up = true;
    for (var x = jibL; x < mastL - 1; x += 16) {
      final x2 = math.min(mastL, x + 16);
      if (up) {
        p
          ..moveTo(x, jibY)
          ..lineTo(x2, topAt(x2));
      } else {
        p
          ..moveTo(x, topAt(x))
          ..lineTo(x2, jibY);
      }
      up = !up;
    }
    for (var x = mastR; x < jibR - 1; x += 19) {
      p
        ..moveTo(x, jibY)
        ..lineTo(math.min(jibR, x + 9.5), jibTop + 6)
        ..lineTo(math.min(jibR, x + 19), jibY);
    }
    // Pendants from the cat-head.
    final pend = lerpD(jibL, mastL, 0.45);
    p
      ..moveTo(mid, jibY - 56)
      ..lineTo(pend, topAt(pend))
      ..moveTo(mid, jibY - 56)
      ..lineTo(jibR - 4, jibTop + 6);
    // Counterweights, cab, concrete base.
    for (var i = 0; i < 3; i++) {
      p.addRect(Rect.fromLTWH(jibR - 44, jibY + i * 10, 40, 10));
    }
    p
      ..addRect(Rect.fromLTRB(mastL - 32, jibY + 4, mastL - 2, jibY + 34))
      ..moveTo(mastL - 32, jibY + 14)
      ..lineTo(mastL - 2, jibY + 14)
      ..addRect(Rect.fromLTRB(mastL - 18, ground - 8, mastR + 18, ground));
    return p;
  }

  /// A lattice mast (hoist tower) between [x0] and [x1], [top] to [bottom].
  void lattice(double x0, double x1, double top, double bottom, {Color color = BP.lineDim, double w = 1}) {
    final p = Path()
      ..moveTo(x0, top)
      ..lineTo(x0, bottom)
      ..moveTo(x1, top)
      ..lineTo(x1, bottom);
    final step = (x1 - x0) * 0.9;
    var left = true;
    for (var y = top; y < bottom - 1; y += step) {
      p
        ..moveTo(left ? x0 : x1, y)
        ..lineTo(left ? x1 : x0, math.min(bottom, y + step));
      left = !left;
    }
    c.drawPath(p, strokeP(color, w));
  }

  /// Dashed survey / construction line.
  void dashed(Offset a, Offset b, Color color, {double w = 1, double dash = 6, double gap = 5}) {
    c.drawPath(dashPath(lineP(a, b), dash: dash, gap: gap), strokeP(color, w));
  }
}
