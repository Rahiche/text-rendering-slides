import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:characters/characters.dart';
import 'package:flutter/painting.dart';

import '../../deck/theme.dart';
import '../../worlds/factory/factory_kit.dart';
import '../layout.dart';
import 'ambient_kit.dart';

/// The elevated line across the city: a viaduct at [BL.trainY] and, every
/// 40–60 s, a letter train (a word split into grapheme clusters, one crate
/// per flatcar) under a Tokyo line colour, with its destination on the cab.
class TrainArt {
  ui.Picture? _pillars;
  ui.Picture? _deck;

  void dispose() {
    _pillars?.dispose();
    _deck?.dispose();
  }

  static const rail = BL.trainY;
  static const _deckBottom = rail + 13;
  static const _pillarXs = [100.0, 310.0, 520.0, 730.0, 940.0, 1150.0, 1360.0, 1570.0];

  /// Pillars: behind the skyline (the city hides their feet).
  void paintPillars(AmbientFrame f) {
    f.c.drawPicture(_pillars ??= _recordPillars());
  }

  /// Deck and trains: in front of the skyline.
  void paintDeck(AmbientFrame f) {
    f.c.drawPicture(_deck ??= _recordDeck());
    final k = ((f.t - 6) / _every).floor();
    for (var j = k - 1; j <= k; j++) {
      _train(f, j);
    }
  }

  static ui.Picture _recordPillars() {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    // Pillars fade out downwards, into the city haze.
    final body = Paint()
      ..shader = ui.Gradient.linear(const Offset(0, _deckBottom), const Offset(0, 430), [
        const Color(0xFF0B1F36),
        const Color(0x000B1F36),
      ]);
    final edge = Paint()
      ..shader = ui.Gradient.linear(const Offset(0, _deckBottom), const Offset(0, 430), [
        BP.lineFaint,
        BP.lineFaint.withValues(alpha: 0),
      ])
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final x in _pillarXs) {
      c.drawRect(Rect.fromLTRB(x - 6, _deckBottom, x + 6, 430), body);
      final p = edge;
      c.drawLine(Offset(x - 6, _deckBottom), Offset(x - 6, 430), p);
      c.drawLine(Offset(x + 6, _deckBottom), Offset(x + 6, 430), p);
      // Pier cap.
      c.drawRect(Rect.fromLTRB(x - 14, _deckBottom, x + 14, _deckBottom + 6), fillOf(const Color(0xFF0B1F36)));
      c.drawRect(Rect.fromLTRB(x - 14, _deckBottom, x + 14, _deckBottom + 6), strokeOf(BP.lineFaint, 1));
    }
    return rec.endRecording();
  }

  static ui.Picture _recordDeck() {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    const deck = Rect.fromLTRB(-10, rail + 2, 1610, _deckBottom);
    c.drawRect(deck, fillOf(const Color(0xFF0B1F36)));
    // Girder ribs.
    final ribs = Path();
    for (var x = 0.0; x < 1600; x += 14) {
      ribs
        ..moveTo(x, rail + 4)
        ..lineTo(x, _deckBottom - 1);
    }
    c.drawPath(ribs, strokeOf(BP.lineFaint.withValues(alpha: 0.8), 0.8));
    c.drawLine(const Offset(-10, _deckBottom), const Offset(1610, _deckBottom), strokeOf(BP.lineFaint, 1));
    // Rail and sleepers.
    c.drawLine(const Offset(-10, rail + 2), const Offset(1610, rail + 2), strokeOf(BP.lineDim, 1.2));
    c.drawLine(const Offset(-10, rail), const Offset(1610, rail), strokeOf(BP.lineDim, 1.4));
    return rec.endRecording();
  }

  // ── Trains ────────────────────────────────────────────────────────────────

  static const _every = 50.0;

  static const _words = [
    'TEXT', 'GLYPH', 'かな', 'カタカナ', '文字列', 'FONT', 'ШРИФТ', '글자', 'ΓΡΑΜΜΑ', 'अक्षर', //
    'Kerning', 'Pixels', 'こんにちは', 'Unicode', 'ひらがな', 'Dart', 'ไทย', 'ქართული', 'Shaping', 'Emoji',
    // Mixed loads: one letter from each of many scripts.
    'Aあ字Жกक한', 'Ωアשé文بñ', 'ㄅΣカ가ดדR',
  ];

  static const _dests = [
    ('東京', 'Tokyo'),
    ('渋谷', 'Shibuya'),
    ('新宿', 'Shinjuku'),
    ('品川', 'Shinagawa'),
    ('上野', 'Ueno'),
    ('池袋', 'Ikebukuro'),
    ('秋葉原', 'Akihabara'),
    ('横浜', 'Yokohama'),
  ];

  /// Tokyo line colours: Yamanote green, Chūō orange, Keihin-Tōhoku blue,
  /// Sōbu yellow.
  static const _lines = [BP.green, BP.coral, BP.line, BP.amber];

  static const _crateColors = [BP.amber, BP.green, BP.violet, BP.coral, BP.line, BP.pink];

  static const _cab = 112.0, _car = 50.0, _gap = 4.0;

  void _train(AmbientFrame f, int k) {
    final start = 6 + k * _every + 10 * rnd(k, 81);
    final dir = rnd(k, 82) < 0.5 ? 1 : -1;
    final speed = 150 + 40 * rnd(k, 83);
    // Now and then a train runs empty, back to the depot (回送).
    final empty = k % 13 == 7;
    final word = empty ? '   ' : _words[(rnd(k, 84) * _words.length).floor() % _words.length];
    final cargo = word.characters.take(7).toList();
    final len = _cab + cargo.length * (_car + _gap);
    final front = speed * (f.t - start) - 30;
    if (front < 0 || front - len > 1640) return;
    final d = dir.toDouble();
    double wx(double s) => dir > 0 ? s : 1600 - s;
    final line = _lines[(rnd(k, 85) * _lines.length).floor() % _lines.length];
    final night = f.d.night;
    final c = f.c;
    final roll = (f.t - start) * speed / 2.6;

    // Headlight beam at night.
    if (night > 0.2) {
      final hx = wx(front);
      final beam = Path()
        ..moveTo(hx, rail - 12)
        ..lineTo(hx + d * 150, rail - 26)
        ..lineTo(hx + d * 150, rail + 2)
        ..close();
      c.drawPath(
        beam,
        Paint()
          ..shader = ui.Gradient.linear(Offset(hx, 0), Offset(hx + d * 150, 0), [
            BP.amber.withValues(alpha: 0.2 * night),
            BP.amber.withValues(alpha: 0),
          ]),
      );
    }

    // Flatcars with one crate (one grapheme cluster) each, back to front.
    for (var i = cargo.length - 1; i >= 0; i--) {
      final s1 = front - _cab - _gap - i * (_car + _gap);
      final a = wx(s1), b = wx(s1 - _car);
      final l = math.min(a, b), r = math.max(a, b);
      if (r < -10 || l > 1610) continue;
      final deck = Rect.fromLTRB(l, rail - 8, r, rail - 3);
      c.drawRect(deck, fillOf(BP.panel));
      c.drawRect(deck, strokeOf(BP.lineDim, 1));
      _bogies(c, l, r, roll);
      // Coupler to the car in front.
      c.drawLine(Offset(dir > 0 ? r : l - _gap, rail - 5), Offset(dir > 0 ? r + _gap : l, rail - 5), strokeOf(BP.lineDim, 1.2));
      if (i == cargo.length - 1 && night > 0.2) {
        c.drawCircle(Offset(dir > 0 ? l + 1 : r - 1, rail - 9), 1.8, fillOf(BP.red.withValues(alpha: 0.9)));
      }
      if (empty) continue;
      final col = _crateColors[(rnd(k, i, 86) * _crateColors.length).floor() % _crateColors.length];
      final crate = Rect.fromCenter(center: Offset((l + r) / 2, rail - 18.5), width: 30, height: 21);
      c.drawRect(crate, fillOf(BP.panel));
      c.drawRect(crate, strokeOf(col.withValues(alpha: 0.85), 1.1));
      c.drawLine(Offset(crate.left, crate.top + 4), Offset(crate.right, crate.top + 4), strokeOf(col.withValues(alpha: 0.4), 0.8));
      // Wagon i trails the cab: lay the word out to read left to right.
      final glyph = cargo[dir > 0 ? cargo.length - 1 - i : i];
      final g = f.text.get(glyph, BT.sample(14, color: BP.ink, weight: 600).copyWith(locale: jaLocale));
      final k2 = math.min(1.0, 24 / math.max(g.width, 1));
      c.save();
      c.translate(crate.center.dx, crate.center.dy + 2);
      c.scale(k2);
      g.paint(c, Offset(-g.width / 2, -g.height / 2));
      c.restore();
    }

    // The cab, with the line colour and the destination board.
    final xf = wx(front), xr = wx(front - _cab);
    final l = math.min(xf, xr), r = math.max(xf, xr);
    if (r < -10 || l > 1610) return;
    double ux(double u) => xr + d * u;
    const top = rail - 27.0, bot = rail - 3.0;
    final body = Path()
      ..moveTo(xr, bot)
      ..lineTo(xr, top + 2)
      ..lineTo(ux(_cab - 20), top)
      ..quadraticBezierTo(ux(_cab - 4), top + 1, xf, top + 14)
      ..lineTo(xf, bot)
      ..close();
    c.drawPath(body, fillOf(BP.panel));
    c.drawPath(body, strokeOf(BP.line.withValues(alpha: 0.85), 1.2));
    // Windscreen on the nose.
    final ws = Path()
      ..moveTo(ux(_cab - 18), top + 3)
      ..quadraticBezierTo(ux(_cab - 6), top + 3.5, ux(_cab - 2.5), top + 11)
      ..lineTo(ux(_cab - 16), top + 11)
      ..close();
    final lit = night > 0.4;
    c.drawPath(ws, fillOf(lit ? BP.ink.withValues(alpha: 0.45) : BP.lineFaint));
    // Destination board (side display), then windows up to the nose.
    final (ja, en) = empty ? ('回送', 'Not in service') : _dests[(rnd(k, 88) * _dests.length).floor() % _dests.length];
    final dest = f.text.span(
      ('dest', ja),
      () => TextSpan(
        children: [
          TextSpan(text: '$ja ', style: BT.sample(9, color: BP.amber, weight: 600).copyWith(locale: jaLocale)),
          TextSpan(text: en, style: BT.display(7.5, color: BP.amber, weight: 500)),
        ],
      ),
    );
    final bw = dest.width + 8;
    final board = Rect.fromLTWH(dir > 0 ? ux(7) : ux(7) - bw, top + 2.5, bw, 11);
    c.drawRect(board, fillOf(const Color(0xFF06111F)));
    c.drawRect(board, strokeOf(BP.lineDim, 0.8));
    if (lit) glow(c, board, BP.amber.withValues(alpha: 0.18 * night), 4, radius: 2);
    dest.paint(c, Offset(board.center.dx - dest.width / 2, board.center.dy - dest.height / 2));
    for (var u = 7 + bw + 5; u + 7 < _cab - 20; u += 11) {
      final w = Rect.fromLTWH(dir > 0 ? ux(u) : ux(u) - 7, top + 4, 7, 7);
      c.drawRect(w, fillOf(lit ? const Color(0xFFFFE6B8).withValues(alpha: 0.7) : BP.lineFaint));
    }
    // Line-colour stripe.
    c.drawLine(Offset(xr, bot - 4), Offset(xf, bot - 4), strokeOf(line, 2.2));
    _bogies(c, l, r, roll);
    // Headlight.
    c.drawCircle(Offset(xf - d * 2, bot - 9), 1.8, fillOf(night > 0.2 ? BP.amber : BP.lineDim));
  }

  void _bogies(Canvas c, double l, double r, double roll) {
    for (final cx in [l + 11, r - 11]) {
      for (final o in [-4.0, 4.0]) {
        final w = Offset(cx + o, rail - 2);
        c.drawCircle(w, 2.6, fillOf(BP.panel));
        c.drawCircle(w, 2.6, strokeOf(BP.lineDim, 1));
        c.drawLine(w, w + Offset(math.cos(roll), math.sin(roll)) * 2.4, strokeOf(BP.lineDim, 0.8));
      }
    }
  }
}
