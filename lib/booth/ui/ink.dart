import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../deck/theme.dart';
import '../../worlds/factory/factory_kit.dart' show FactoryInk;
import '../layout.dart';

/// Where the booth UI draws on the 1600×900 canvas: the board inside
/// [BL.board], the input and the tally in [BL.bottom]. Feedback after Enter
/// briefly rises above the input (over the road's left end); the operator
/// help hangs in the sky while it's open. Nothing ever covers [BL.plot].
abstract final class UG {
  // ── Board (top left). Kept left of x ≈ 570 so the crane's jib tip (580)
  // and its hook line over the pickup (612) stay visible.
  static const left = 36.0;
  static const right = 566.0;
  static const sign = Rect.fromLTRB(left, 30, right, 198);
  static const bulbY = 40.0;
  static const titleY = 63.0; // title centre line
  static const divider = 85.0;
  static const kickerY = 91.0;

  /// The name being built: its box, and the baseline it sits on.
  static const nameBox = Rect.fromLTRB(54, 112, 548, 174);
  static const nameBase = 163.0;
  static const barY = 179.0;
  static const barH = 10.0;

  /// The ticket rail under the sign.
  static const railY = 206.0;
  static const ticketTop = 212.0;
  static const ticketH = 37.0;
  static const ticketGap = 10.0;
  static const maxTickets = 5;

  // ── Bottom band.
  static const input = BL.input; // 36..760 × 816..886
  static const field = Rect.fromLTRB(58, 827, 602, 875);
  static const key = Rect.fromLTRB(662, 828, 744, 874);
  static const counter = Rect.fromLTRB(800, 816, 1052, 886);
  static const ticker = Rect.fromLTRB(1066, 816, 1564, 886);

  // ── Feedback above the input (a receipt rises out of it).
  static const toastBottom = 806.0;
  static const toastH = 62.0;

  // ── Operator (only while in use).
  static const help = Rect.fromLTWH(620, 34, 580, 346); // 8 rows of keys + footer
  static const chip = Offset(620, 34);
}

const jaLocale = Locale('ja');

/// Text styles for the UI (Japanese glyph forms for Han characters; the
/// platform's Japanese font as fallback, which only honours [FontWeight]).
abstract final class UT {
  static TextStyle mono(double size, {Color color = BP.inkDim, double weight = 500, double? ls}) =>
      BT.mono(size, color: color, weight: weight, letterSpacing: ls).copyWith(locale: jaLocale);

  static TextStyle label(double size, {Color color = BP.ink, double weight = 500, double? height}) =>
      BT.display(size, color: color, weight: weight, height: height).copyWith(locale: jaLocale);

  /// A name, in the same face as the bricks.
  static TextStyle name(double size, {Color color = BP.ink, double weight = 600, double height = 1.15}) =>
      BT.display(size, color: color, weight: weight, height: height).copyWith(locale: jaLocale);
}

/// Laid-out text, cached. Least recently used entries are dropped past
/// [max], but never one used in the current frame (it may still be painted).
class UiText {
  UiText({this.max = 360}) {
    PaintingBinding.instance.systemFonts.addListener(clear);
  }

  final int max;
  // Insertion ordered (Dart's default map): least recently used first.
  final _map = <Object, ({TextPainter p, Object frame})>{};
  Object _frame = 0;

  /// Marks the start of a paint pass (e.g. the scene time).
  void frame(Object id) => _frame = id;

  TextPainter get(String text, TextStyle style) {
    final k = (text, style);
    final hit = _map.remove(k);
    if (hit != null) {
      _map[k] = (p: hit.p, frame: _frame);
      return hit.p;
    }
    final p = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    _map[k] = (p: p, frame: _frame);
    if (_map.length > max) _trim();
    return p;
  }

  void _trim() {
    final old = <Object>[];
    for (final e in _map.entries) {
      if (_map.length - old.length <= max * 3 ~/ 4 || e.value.frame == _frame) break;
      old.add(e.key);
    }
    for (final k in old) {
      _map.remove(k)!.p.dispose();
    }
  }

  void clear() {
    for (final e in _map.values) {
      e.p.dispose();
    }
    _map.clear();
  }
}

/// Line art for the UI, on top of the factory's ink (same strokes, lamps).
class UiInk extends FactoryInk {
  UiInk(super.c, this.text);

  final UiText text;

  TextPainter tp(String s, TextStyle style) => text.get(s, style);

  /// Paints [p] with its top-left at [o], scaled down (never up) so it fits
  /// [maxW]. Returns the painted width.
  double put(TextPainter p, Offset o, {double maxW = double.infinity}) {
    final s = p.width > maxW ? maxW / p.width : 1.0;
    if (s >= 1) {
      p.paint(c, o);
      return p.width;
    }
    c.save();
    c.translate(o.dx, o.dy + p.height * (1 - s) / 2);
    c.scale(s);
    p.paint(c, Offset.zero);
    c.restore();
    return p.width * s;
  }

  /// Paints [p] vertically centred on [cy].
  double putMid(TextPainter p, double x, double cy, {double maxW = double.infinity}) =>
      put(p, Offset(x, cy - p.height / 2), maxW: maxW);

  /// Paints [p] with its alphabetic baseline on [base] (whatever fonts the
  /// line falls back to), scaled down to fit [maxW]. Returns the width.
  double putBase(TextPainter p, double x, double base, {double maxW = double.infinity}) {
    final b = p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final s = p.width > maxW ? maxW / p.width : 1.0;
    c.save();
    c.translate(x, base);
    c.scale(s);
    p.paint(c, Offset(0, -b));
    c.restore();
    return p.width * s;
  }

  /// Fades everything drawn in [draw] to [alpha].
  void faded(double alpha, void Function() draw) {
    if (alpha <= 0.003) return;
    if (alpha >= 0.997) {
      draw();
      return;
    }
    c.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    draw();
    c.restore();
  }

  /// A sign panel: fill, outer frame, inner line, corner rivets (the deck's
  /// hall signs).
  void plate(Rect r, {Color edge = BP.line, double w = 1.6, Color fill = BP.panel, bool rivets = true}) {
    c.drawRect(r, fl(fill));
    c.drawRect(r, st(edge, w));
    c.drawRect(r.deflate(6), st(BP.lineDim, 1));
    if (!rivets) return;
    for (final p in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      final q = Offset(p.dx + (p.dx < r.center.dx ? 12 : -12), p.dy + (p.dy < r.center.dy ? 12 : -12));
      c.drawCircle(q, 2.2, st(BP.lineDim, 1.1));
    }
  }

  /// A light bulb, [on] 0..1.
  void bulb(Offset p, double on, {double r = 3.6, Color col = BP.amber}) {
    if (on > 0.02) {
      c.drawCircle(p, r * 2.6, fl(col.withValues(alpha: 0.14 * on)));
      c.drawCircle(p, r * 1.6, fl(col.withValues(alpha: 0.18 * on)));
      c.drawCircle(p, r, fl(Color.lerp(BP.panel, col, on)!));
      if (on > 0.6) c.drawCircle(p.translate(-r * 0.3, -r * 0.3), r * 0.35, fl(BP.ink.withValues(alpha: on)));
    } else {
      c.drawCircle(p, r, fl(BP.panel));
    }
    c.drawCircle(p, r, st(on > 0.5 ? col : BP.lineDim, 1));
  }

  /// ✓ (the fonts don't have it).
  void tick(Offset o, double s, Color col, [double w = 2.6]) {
    c.drawPath(
      Path()
        ..moveTo(o.dx - s * 0.5, o.dy + s * 0.02)
        ..lineTo(o.dx - s * 0.14, o.dy + s * 0.36)
        ..lineTo(o.dx + s * 0.52, o.dy - s * 0.34),
      st(col, w),
    );
  }

  /// ! in a badge.
  void bang(Offset o, double s, Color col, [double w = 2.8]) {
    c.drawLine(o.translate(0, -s * 0.42), o.translate(0, s * 0.14), st(col, w));
    c.drawCircle(o.translate(0, s * 0.4), w * 0.62, fl(col));
  }

  /// ↵ (the fonts don't have it): a hook arrow inside [r].
  void returnArrow(Rect r, Color col, [double w = 2.4]) {
    final x0 = r.left, x1 = r.right, y0 = r.top, y1 = r.bottom;
    final h = (y1 - y0) * 0.32;
    c.drawPath(
      Path()
        ..moveTo(x1, y0)
        ..lineTo(x1, y1 - h)
        ..lineTo(x0 + h * 0.4, y1 - h),
      st(col, w),
    );
    c.drawPath(
      Path()
        ..moveTo(x0 + h * 1.2, y1 - h * 1.9)
        ..lineTo(x0, y1 - h)
        ..lineTo(x0 + h * 1.2, y1 - h * 0.1),
      st(col, w),
    );
  }

  /// ⌫ (the fonts don't have it).
  void backspace(Rect r, Color col, [double w = 1.4]) {
    final m = r.height / 2;
    c.drawPath(
      Path()
        ..moveTo(r.left, r.center.dy)
        ..lineTo(r.left + m, r.top)
        ..lineTo(r.right, r.top)
        ..lineTo(r.right, r.bottom)
        ..lineTo(r.left + m, r.bottom)
        ..close(),
      st(col, w),
    );
    final x = Offset(r.left + m + (r.width - m) / 2, r.center.dy);
    final d = r.height * 0.18;
    c.drawLine(x.translate(-d, -d), x.translate(d, d), st(col, w));
    c.drawLine(x.translate(-d, d), x.translate(d, -d), st(col, w));
  }

  /// A small brick (count of bricks).
  void brickIcon(Offset o, Color col) {
    c.drawRect(Rect.fromLTWH(o.dx, o.dy, 14, 6), st(col, 1.2));
    c.drawRect(Rect.fromLTWH(o.dx + 4, o.dy + 6, 14, 6), st(col, 1.2));
  }

  /// A small clock (time left), hands at [t] seconds.
  void clockIcon(Offset o, double r, Color col, double t) {
    c.drawCircle(o, r, st(col, 1.3));
    final a = -math.pi / 2 + t * 0.9;
    c.drawLine(o, o + Offset(math.cos(a), math.sin(a)) * r * 0.7, st(col, 1.3));
    c.drawLine(o, o + Offset(0, -r * 0.5), st(col, 1.3));
  }

  /// A diamond separator.
  void diamond(Offset o, double r, Color col) {
    c.drawPath(
      Path()
        ..moveTo(o.dx, o.dy - r)
        ..lineTo(o.dx + r, o.dy)
        ..lineTo(o.dx, o.dy + r)
        ..lineTo(o.dx - r, o.dy)
        ..close(),
      fl(col),
    );
  }

  /// A key cap; [icon] draws inside its face. [lit] makes it amber, [glow]
  /// 0..1 is the halo around it, [down] 0..1 pushes it in.
  void keyCap(Rect r, {bool lit = false, double glow = 0, double down = 0, required void Function(Rect face, Color col) icon}) {
    const depth = 4.0;
    final face = Rect.fromLTWH(r.left, r.top + depth * down, r.width, r.height - depth);
    final base = RRect.fromRectAndRadius(Rect.fromLTWH(r.left, r.top + depth, r.width, r.height - depth), const Radius.circular(6));
    c.drawRRect(base, fl(BP.paper));
    c.drawRRect(base, st(lit ? BP.amber.withValues(alpha: 0.6) : BP.lineDim, 1.2));
    final f = RRect.fromRectAndRadius(face, const Radius.circular(6));
    if (glow > 0.01) {
      c.drawRRect(f.inflate(9), fl(BP.amber.withValues(alpha: 0.07 * glow)));
      c.drawRRect(f.inflate(4), fl(BP.amber.withValues(alpha: 0.12 * glow)));
    }
    c.drawRRect(f, fl(BP.panel));
    if (lit) c.drawRRect(f, fl(BP.amber.withValues(alpha: 0.14)));
    final col = lit ? BP.amber : BP.inkDim;
    c.drawRRect(f, st(col, 1.6));
    icon(face, col);
  }

  /// An order ticket with its top edge at [r] (clipped to the rail by a peg):
  /// a queue position badge and the name. [next] marks the first in line.
  void ticket(
    Rect r,
    String name, {
    int? pos,
    bool next = false,
    double tilt = 0,
    double scale = 1,
    bool peg = true,
  }) {
    c.save();
    final pivot = r.topCenter;
    c.translate(pivot.dx, pivot.dy);
    c.rotate(tilt);
    c.scale(scale);
    c.translate(-pivot.dx, -pivot.dy);
    final edge = next ? BP.amber : BP.line;
    c.drawRect(r, fl(BP.panel));
    c.drawRect(r, st(edge, next ? 1.8 : 1.3));
    // Ticket notches.
    for (final x in [r.left, r.right]) {
      c.drawCircle(Offset(x, r.center.dy), 4, fl(BP.paper));
      c.drawArc(
        Rect.fromCircle(center: Offset(x, r.center.dy), radius: 4),
        x == r.left ? -math.pi / 2 : math.pi / 2,
        math.pi,
        false,
        st(edge, 1.1),
      );
    }
    var x = r.left + 10;
    if (pos != null) {
      final b = Rect.fromLTWH(x, r.center.dy - 11, 22, 22);
      c.drawRect(b, next ? fl(BP.amber) : fl(BP.paper));
      if (!next) c.drawRect(b, st(BP.lineDim, 1));
      final n = tp('$pos', UT.mono(14, color: next ? BP.paper : BP.inkDim, weight: 700));
      n.paint(c, Offset(b.center.dx - n.width / 2, b.center.dy - n.height / 2));
      x = b.right + 8;
    }
    final p = tp(name, UT.name(22, color: BP.ink, weight: 600, height: 1.1));
    putMid(p, x, r.center.dy + 1, maxW: r.right - 10 - x);
    if (peg) {
      // A clothes peg on the rail.
      final pg = Rect.fromCenter(center: Offset(r.center.dx, r.top - 2), width: 7, height: 13);
      c.drawRect(pg, fl(BP.lineDim));
      c.drawRect(pg, st(BP.line, 1));
    }
    c.restore();
  }

  /// Width of the ticket for [name] (with a position badge).
  double ticketWidth(String name) {
    final p = tp(name, UT.name(22, color: BP.ink, weight: 600, height: 1.1));
    return (p.width + 60).clamp(84.0, 196.0);
  }
}

/// A point on a quadratic Bézier.
Offset quad(Offset a, Offset ctrl, Offset b, double s) =>
    a * ((1 - s) * (1 - s)) + ctrl * (2 * s * (1 - s)) + b * (s * s);

/// Minutes and seconds, "1:05".
String clock(double seconds) {
  final s = math.max(0, seconds.round());
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
