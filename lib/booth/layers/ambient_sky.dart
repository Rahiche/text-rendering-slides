import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../deck/theme.dart';
import '../../worlds/factory/factory_kit.dart';
import '../layout.dart';
import 'ambient_kit.dart';

/// The sky over the city of text: day/night gradient, the sun 日 and the
/// moon 月, glyph stars, drifting word-clouds, flocks of glyph-birds and,
/// every few minutes, the talk's blimp.
class SkyArt {
  SkyArt() {
    _stars = _makeStars();
  }

  late final List<_Star> _stars;
  final _puffs = <(String, double), Path>{};

  // ── Sky & celestial ───────────────────────────────────────────────────────

  void paintSky(AmbientFrame f) {
    f.c.drawRect(BL.sky, Paint()..shader = f.sky.shader());
    _horizonGlow(f);
    _paintStars(f);
    _sunOrMoon(f);
  }

  /// Dawn and dusk light up the sky on the side where the sun is.
  void _horizonGlow(AmbientFrame f) {
    final c = f.c;
    // The city's own light at night, low over the rooftops.
    final n = smoothstep(0.4, 1, f.d.night);
    if (n > 0) {
      c.save();
      c.translate(820, 380);
      c.scale(1, 0.2);
      c.drawCircle(
        Offset.zero,
        980,
        Paint()
          ..shader = ui.Gradient.radial(Offset.zero, 980, [
            BP.violet.withValues(alpha: 0.10 * n),
            BP.amber.withValues(alpha: 0.03 * n),
            BP.violet.withValues(alpha: 0),
          ], const [0, 0.45, 1]),
      );
      c.restore();
    }
    final g = f.d.glow;
    if (g < 0.02) return;
    final evening = f.d.evening;
    final at = evening ? const Offset(1520, 352) : const Offset(640, 352);
    final col = evening ? BP.coral : BP.pink;
    c.save();
    c.translate(at.dx, at.dy);
    c.scale(1, 0.42);
    c.drawCircle(
      Offset.zero,
      620,
      Paint()
        ..shader = ui.Gradient.radial(Offset.zero, 620, [
          col.withValues(alpha: 0.32 * g),
          BP.amber.withValues(alpha: 0.10 * g),
          col.withValues(alpha: 0),
        ], const [0, 0.38, 1]),
    );
    c.restore();
  }

  /// Sun by day, moon by night, on the same arc over the city (kept clear of
  /// the UI board on the left).
  static Offset arc(double u) => Offset(lerp(600, 1560, u), 354 - 292 * math.sin(math.pi * u));

  void _sunOrMoon(AmbientFrame f) {
    final d = f.d;
    if (d.phase < 0.5) {
      _sun(f, arc(d.phase / 0.5));
    } else {
      _moon(f, arc((d.phase - 0.5) / 0.5));
    }
  }

  void _sun(AmbientFrame f, Offset p) {
    final c = f.c;
    // Low sun turns coral (quantised so the glyph's painter is cached).
    final low = (4 * (1 - smoothstep(0.02, 0.4, f.d.sun))).round() / 4;
    final col = Color.lerp(BP.amber, BP.coral, low * 0.85)!;
    c.drawCircle(
      p,
      130,
      Paint()
        ..shader = ui.Gradient.radial(p, 130, [
          col.withValues(alpha: 0.22),
          col.withValues(alpha: 0.07),
          col.withValues(alpha: 0),
        ], const [0, 0.32, 1]),
    );
    final rays = Path();
    final rot = f.t * 0.05;
    for (var i = 0; i < 16; i++) {
      final a = rot + i * math.pi / 8;
      final r1 = i.isEven ? 47.0 : 41.0;
      rays
        ..moveTo(p.dx + math.cos(a) * 35, p.dy + math.sin(a) * 35)
        ..lineTo(p.dx + math.cos(a) * r1, p.dy + math.sin(a) * r1);
    }
    c.drawPath(rays, strokeOf(col.withValues(alpha: 0.6), 1.5));
    c.drawCircle(p, 26, fillOf(Color.lerp(f.sky.at(p.dy), col, 0.2)!));
    c.drawCircle(p, 26, strokeOf(col, 1.8));
    c.drawCircle(p, 30.5, strokeOf(col.withValues(alpha: 0.35), 1));
    f.centered(f.text.get('日', BT.sample(28, color: col, weight: 600).copyWith(locale: jaLocale)), p + const Offset(0, 1));
  }

  static final _crescent = Path.combine(
    PathOperation.difference,
    Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: 22)),
    Path()..addOval(Rect.fromCircle(center: const Offset(-9, -4), radius: 20)),
  );

  void _moon(AmbientFrame f, Offset p) {
    final c = f.c;
    c.drawCircle(
      p,
      100,
      Paint()
        ..shader = ui.Gradient.radial(p, 100, [
          BP.ink.withValues(alpha: 0.12),
          BP.ink.withValues(alpha: 0.035),
          BP.ink.withValues(alpha: 0),
        ], const [0, 0.3, 1]),
    );
    c.drawCircle(p, 22, fillOf(Color.lerp(f.sky.at(p.dy), BP.ink, 0.07)!));
    c.save();
    c.translate(p.dx, p.dy);
    c.drawPath(_crescent, fillOf(BP.ink.withValues(alpha: 0.13)));
    c.restore();
    c.drawCircle(p, 22, strokeOf(BP.ink.withValues(alpha: 0.75), 1.5));
    c.drawCircle(p, 26.5, strokeOf(BP.ink.withValues(alpha: 0.18), 1));
    f.centered(f.text.get('月', BT.sample(23, color: BP.ink, weight: 500).copyWith(locale: jaLocale)), p + const Offset(0, 1));
  }

  // ── Stars ─────────────────────────────────────────────────────────────────

  static List<_Star> _makeStars() {
    final out = <_Star>[];
    for (var i = 0; out.length < 120 && i < 600; i++) {
      final y = 10 + 300 * math.pow(rnd(i, 1), 1.35);
      final p = Offset(8 + 1584 * rnd(i, 2), y.toDouble());
      if (BL.board.inflate(24).contains(p)) continue;
      final r = rnd(i, 3);
      final int glyph;
      final double k;
      if (r < 0.62) {
        glyph = Spr.dot;
        k = 0.8 + 0.5 * rnd(i, 4);
      } else if (r < 0.8) {
        glyph = Spr.sparkle;
        k = 0.65 + 0.45 * rnd(i, 4);
      } else if (r < 0.91) {
        glyph = Spr.asterisk;
        k = 0.7 + 0.35 * rnd(i, 4);
      } else {
        glyph = Spr.starKanji;
        k = 0.8 + 0.3 * rnd(i, 4);
      }
      final hue = rnd(i, 5);
      out.add(
        _Star(
          p,
          glyph,
          k,
          0.45 + 0.5 * rnd(i, 6),
          0.7 + 2.2 * rnd(i, 7),
          6.28 * rnd(i, 8),
          hue < 0.72 ? BP.ink : (hue < 0.88 ? BP.amber : BP.line),
        ),
      );
    }
    return out;
  }

  void _paintStars(AmbientFrame f) {
    final vis = smoothstep(0.3, 0.9, f.d.night);
    if (vis <= 0) return;
    final t = f.t;
    for (final s in _stars) {
      var tw = 0.62 + 0.38 * math.sin(t * s.w + s.ph);
      // Now and then a star flares.
      final fl = fract(t * 0.045 + s.ph * 0.37);
      if (fl < 0.025) tw += 0.9 * bump(fl / 0.025);
      // Dimmer down where the city glows.
      final haze = 1 - 0.5 * smoothstep(200, 320, s.p.dy);
      f.batch.add(f.sprites, s.glyph, s.p.dx, s.p.dy, s.k * (1 + 0.15 * (tw - 0.6)), s.col.withValues(alpha: c01(s.base * tw * vis * haze)));
    }
    _shootingStar(f, vis);
    f.batch.flush(f.c, f.sprites);
  }

  void _shootingStar(AmbientFrame f, double vis) {
    const per = 17.0;
    final k = (f.t / per).floor();
    if (rnd(k, 31) > 0.5 || vis < 0.6) return;
    final age = (f.t - k * per - 3 - 9 * rnd(k, 32)) / 1.1;
    if (age < 0 || age > 1) return;
    final p0 = Offset(820 + 640 * rnd(k, 33), 24 + 120 * rnd(k, 34));
    final dir = Offset(-math.cos(0.42), math.sin(0.42));
    final head = p0 + dir * (260 * age);
    final tail = head - dir * (90 * (1 - 0.6 * age));
    final a = vis * bump(age);
    f.c.drawLine(
      tail,
      head,
      Paint()
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(tail, head, [BP.ink.withValues(alpha: 0), BP.ink.withValues(alpha: 0.85 * a)]),
    );
    f.batch.add(f.sprites, Spr.sparkle, head.dx, head.dy, 0.9, BP.ink.withValues(alpha: a));
  }

  // ── Word-clouds ───────────────────────────────────────────────────────────

  static const _cloudWords = <(String, Locale?)>[
    ('雲', jaLocale),
    ('cloud', null),
    ('nube', null),
    ('구름', Locale('ko')),
    ('nuage', null),
    ('Wolke', null),
    ('облако', null),
    ('くも', jaLocale),
    ('nuvem', null),
    ('σύννεφο', null),
    ('बादल', null),
    ('เมฆ', null),
    ('ענן', null),
    ('سحابة', null),
    ('nuvola', null),
    ('bulut', null),
  ];

  /// (font size, speed px/s, y, start offset, depth 0 far .. 2 near)
  static const _clouds = <(double, double, double, double, int)>[
    (21, 4.2, 70, 300, 0),
    (23, 4.8, 128, 1250, 0),
    (30, 7.0, 104, 820, 1),
    (32, 7.8, 186, 1900, 1),
    (42, 10.5, 152, 160, 2),
    (38, 9.6, 222, 1500, 2),
  ];

  static const _cloudMargin = 300.0;

  void paintClouds(AmbientFrame f) {
    final c = f.c;
    const span = 1600 + 2 * _cloudMargin;
    final night = f.d.night;
    final tint = f.d.glow * (f.d.evening ? 0.75 : 0.55);
    final edge = Color.lerp(BP.inkDim, f.d.evening ? BP.coral : BP.pink, tint)!;
    for (var i = 0; i < _clouds.length; i++) {
      final (size, speed, y, x0, depth) = _clouds[i];
      final run = x0 + speed * f.t;
      final lap = (run / span).floor();
      final x = 1600 + _cloudMargin - (run - lap * span);
      final wi = (rnd(i, lap, 7) * _cloudWords.length).floor() % _cloudWords.length;
      final (word, locale) = _cloudWords[wi];
      final yy = y + 10 * math.sin(f.t * 0.05 + i * 1.7) + 14 * (rnd(i, lap, 8) - 0.5);
      final probe = f.text.get(word, _cloudStyle(size, 1, locale), key: ('cloud', size, 12));
      final w = probe.width, h = probe.height;
      final box = Rect.fromCenter(center: Offset(x, yy), width: w + h * 1.6, height: h * 1.5);
      if (box.right < -10 || box.left > 1610) continue;
      final a = (0.5 + 0.22 * depth) * boardCalm(box, floor: 0.12) * (1 - 0.4 * night);
      final puff = _puffs[(word, size)] ??= _puff(w, h, wi * 31 + size.round());
      c.save();
      c.translate(x, yy);
      c.drawPath(puff, fillOf(Color.lerp(f.sky.at(yy), BP.ink, 0.05 + 0.02 * depth)!.withValues(alpha: 0.9 * a)));
      c.drawPath(puff, strokeOf(edge.withValues(alpha: 0.55 * a), 1.2));
      c.restore();
      final level = (a * 12).round().clamp(1, 12);
      final tp = f.text.get(word, _cloudStyle(size, level / 12, locale), key: ('cloud', size, level));
      tp.paint(c, Offset(x - tp.width / 2, yy - tp.height / 2 + h * 0.04));
    }
  }

  static TextStyle _cloudStyle(double size, double alpha, Locale? locale) =>
      BT.sample(size, weight: 500).copyWith(
        locale: locale,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size > 34 ? 1.2 : 1.0
          ..strokeJoin = StrokeJoin.round
          ..color = BP.ink.withValues(alpha: 0.62 * alpha),
      );

  /// A flat-bottomed puff around a [w]×[h] word, centred on the origin.
  static Path _puff(double w, double h, int seed) {
    var p = Path()
      ..addRRect(
        RRect.fromLTRBR(-w / 2 - h * 0.55, -h * 0.12, w / 2 + h * 0.55, h * 0.58, Radius.circular(h * 0.34)),
      );
    final n = math.max(2, (w / (h * 0.75)).round());
    for (var i = 0; i < n; i++) {
      final cx = lerp(-w / 2 - h * 0.05, w / 2 + h * 0.05, i / (n - 1)) + (rnd(seed, i, 3) - 0.5) * h * 0.2;
      final r = h * (0.36 + 0.2 * rnd(seed, i, 4));
      p = Path.combine(
        PathOperation.union,
        p,
        Path()..addOval(Rect.fromCircle(center: Offset(cx, -h * 0.08 - r * 0.3), radius: r)),
      );
    }
    return p;
  }

  // ── Birds ─────────────────────────────────────────────────────────────────

  void paintBirds(AmbientFrame f) {
    const per = 41.0;
    final k0 = (f.t / per).floor();
    for (var k = k0 - 1; k <= k0; k++) {
      if (rnd(k, 51) > 0.7) continue;
      final start = k * per + 12 * rnd(k, 52);
      // Birds fly by day (and in the dawn/dusk light).
      if (DayClock(start).day < 0.35) continue;
      final dir = rnd(k, 53) < 0.5 ? 1 : -1;
      final speed = 52 + 26 * rnd(k, 54);
      final y0 = 128 + 120 * rnd(k, 55);
      final n = 5 + (rnd(k, 56) * 5).floor();
      final lead = dir > 0 ? -40 + speed * (f.t - start) : 1640 - speed * (f.t - start);
      if (dir > 0 ? lead - 220 > 1640 : lead + 220 < -40) continue;
      for (var i = 0; i < n; i++) {
        final rank = (i + 1) ~/ 2;
        final side = i.isOdd ? -1 : 1;
        final x = lead - dir * (rank * 17 + 6 * rnd(k, i, 57));
        final y = y0 + side * rank * 9 + 4 * math.sin(f.t * 1.6 + i) + 3 * rnd(k, i, 58);
        if (x < -20 || x > 1620) continue;
        final flap = fract(f.t * (2.6 + 0.5 * rnd(k, i, 59)) + rnd(k, i, 60)) < 0.5;
        final a = 0.7 * boardCalmAt(Offset(x, y), floor: 0.2);
        f.batch.add(f.sprites, flap ? Spr.birdUp : Spr.birdFlat, x, y, 0.85 + 0.25 * rnd(k, i, 61), BP.ink.withValues(alpha: a));
      }
    }
    f.batch.flush(f.c, f.sprites);
  }

  // ── Balloons ──────────────────────────────────────────────────────────────

  static const _balloonColors = [BP.pink, BP.amber, BP.green, BP.violet, BP.coral];
  static const _balloonGlyphs = ['あ', 'A', '字', 'Ω', 'ア', '文', 'ñ', '한'];

  /// Now and then somebody in the city lets go of a balloon.
  void paintBalloons(AmbientFrame f) {
    const per = 37.0;
    final k0 = (f.t / per).floor();
    for (var k = k0 - 1; k <= k0; k++) {
      if (rnd(k, 91) > 0.5) continue;
      final start = k * per + 10 * rnd(k, 92);
      if (DayClock(start).day < 0.3) continue;
      final u = f.t - start;
      final y = 430 - 13 * u;
      if (u < 0 || y < -30) continue;
      final x = 700 + 800 * rnd(k, 93) - 5 * u + 7 * math.sin(u * 0.7 + k);
      final col = _balloonColors[(rnd(k, 94) * _balloonColors.length).floor() % _balloonColors.length];
      final a = boardCalmAt(Offset(x, y), floor: 0.2);
      final c = f.c;
      final p = Offset(x, y);
      final string = Path()..moveTo(x, y + 7);
      for (var i = 1; i <= 4; i++) {
        string.lineTo(x + 2.2 * math.sin(u * 3 + i * 1.3), y + 7 + i * 4);
      }
      c.drawPath(string, strokeOf(BP.inkDim.withValues(alpha: 0.7 * a), 0.8));
      c.drawCircle(p, 7, fillOf(Color.lerp(f.sky.at(y), col, 0.3)!.withValues(alpha: a)));
      c.drawCircle(p, 7, strokeOf(col.withValues(alpha: 0.9 * a), 1.2));
      if (a > 0.9) {
        final g = f.text.get(
          _balloonGlyphs[(rnd(k, 95) * _balloonGlyphs.length).floor() % _balloonGlyphs.length],
          BT.sample(7.5, color: col, weight: 700).copyWith(locale: jaLocale),
        );
        f.centered(g, p + const Offset(0, 0.5));
      }
    }
  }

  // ── Blimp ─────────────────────────────────────────────────────────────────

  static const _blimpEvery = 210.0;
  static const _blimpSpeed = 18.0;
  static const _blimpW = 250.0;
  static const _turnTime = 9.0;

  /// Every few minutes the talk's blimp drifts in from the right, turns
  /// around over the site (never reaching the UI board) and drifts away.
  void paintBlimp(AmbientFrame f) {
    final k = (f.t / _blimpEvery).floor();
    for (var j = k - 1; j <= k; j++) {
      final u = f.t - (j * _blimpEvery + 25 + 40 * rnd(j, 71));
      if (u < 0) continue;
      const enter = 1600 + _blimpW / 2 + 12;
      final turnX = 860 + 110 * rnd(j, 73);
      final leg = (enter - turnX) / _blimpSpeed;
      double x, facing;
      if (u < leg) {
        x = enter - _blimpSpeed * u;
        facing = -1;
      } else if (u < leg + _turnTime) {
        final q = (u - leg) / _turnTime;
        x = turnX - 8 * math.sin(math.pi * q);
        facing = -math.cos(math.pi * eio(q));
      } else if (u < 2 * leg + _turnTime) {
        x = turnX + _blimpSpeed * (u - leg - _turnTime);
        facing = 1;
      } else {
        continue;
      }
      final y = 150 + 28 * rnd(j, 72) + 5 * math.sin(f.t * 0.35);
      _blimp(f, Offset(x, y), facing);
    }
  }

  /// The blimp centred on [o]; [facing] −1 (nose left) .. 1 (nose right),
  /// squashed in between while it turns.
  void _blimp(AmbientFrame f, Offset o, double facing) {
    final c = f.c;
    final d = facing < 0 ? -1.0 : 1.0;
    final night = f.d.night;
    c.save();
    c.translate(o.dx, o.dy);
    c.scale(math.max(0.26, facing.abs()), 1);
    // Envelope: a teardrop, nose towards [d].
    const half = _blimpW / 2;
    final nose = d * half, tail = -d * half;
    final env = Path()
      ..moveTo(nose, 0)
      ..cubicTo(nose, -40, -d * 40, -33, tail, -6)
      ..lineTo(tail, 6)
      ..cubicTo(-d * 40, 33, nose, 40, nose, 0)
      ..close();
    final fins = Path()
      ..moveTo(tail + d * 30, -14)
      ..lineTo(tail - d * 6, -34)
      ..lineTo(tail - d * 2, -5)
      ..moveTo(tail + d * 30, 14)
      ..lineTo(tail - d * 6, 34)
      ..lineTo(tail - d * 2, 5);
    c.drawPath(fins, fillOf(BP.panel));
    c.drawPath(fins, strokeOf(BP.lineDim, 1.2));
    c.drawPath(env, fillOf(Color.lerp(BP.panel, f.sky.at(o.dy), 0.25)!));
    for (final s in [-0.55, 0.55]) {
      final seam = Path()
        ..moveTo(nose - d * 8, s * 6)
        ..quadraticBezierTo(0, s * 52, tail + d * 4, s * 8);
      c.drawPath(seam, strokeOf(BP.lineFaint, 1));
    }
    c.drawPath(env, strokeOf(BP.line.withValues(alpha: 0.8), 1.4));
    // Gondola and propeller.
    final g = Rect.fromCenter(center: Offset(d * 18, 36), width: 52, height: 12);
    c.drawLine(Offset(d * 2, 26), g.topCenter + Offset(-d * 8, 0), strokeOf(BP.lineDim, 1));
    c.drawLine(Offset(d * 34, 26), g.topCenter + Offset(d * 12, 0), strokeOf(BP.lineDim, 1));
    final gr = RRect.fromRectAndRadius(g, const Radius.circular(5));
    c.drawRRect(gr, fillOf(BP.panel));
    c.drawRRect(gr, strokeOf(BP.line.withValues(alpha: 0.8), 1.2));
    for (var i = 0; i < 4; i++) {
      final w = Rect.fromLTWH(g.left + 8 + i * 9.5, g.top + 3.5, 5, 4);
      c.drawRect(w, fillOf(night > 0.5 ? BP.amber.withValues(alpha: 0.8) : BP.lineDim));
    }
    final prop = Offset(d < 0 ? g.right + 4 : g.left - 4, g.center.dy);
    final spin = math.sin(f.t * 30);
    c.drawLine(prop + Offset(0, -7 * spin), prop + Offset(0, 7 * spin), strokeOf(BP.inkDim, 1.4));
    // The banner (in English and Japanese, like the title slide).
    final title = f.text.get("Inside Flutter's Text Pipeline", BT.display(13, color: BP.ink, weight: 600));
    title.paint(c, Offset(-title.width / 2 - d * 6, -15));
    final ja = f.text.get(
      'Flutterテキストパイプラインの内側',
      BT.sample(9.5, color: BP.amber, weight: 500).copyWith(locale: jaLocale),
    );
    ja.paint(c, Offset(-ja.width / 2 - d * 6, 3));
    // Navigation lights blink at night.
    if (night > 0.3 && fract(f.t * 0.8) < 0.18) {
      c.drawCircle(Offset(tail - d * 4, -34), 2.2, fillOf(BP.red));
      c.drawCircle(Offset(nose - d * 3, 0), 2, fillOf(BP.green));
    }
    c.restore();
  }
}

class _Star {
  const _Star(this.p, this.glyph, this.k, this.base, this.w, this.ph, this.col);
  final Offset p;
  final int glyph;
  final double k;
  final double base;
  final double w;
  final double ph;
  final Color col;
}
