import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../deck/theme.dart';
import '../../worlds/factory/factory_kit.dart' show eio;
import '../model.dart';
import 'booth_ui.dart';
import 'ink.dart';

/// Bottom right: "Built today · 今日" on a rolling counter, and a slow
/// ticker of the names built today (newest first, from the saved history).
void paintTally(UiInk k, BoothModel m, BoothUi ui) {
  final today = ui.today;
  _counter(k, today.length, ui, m.t);
  _ticker(k, [for (final b in today.reversed.take(24)) b.name], m.t);
}

void _counter(UiInk k, int n, BoothUi ui, double t) {
  final c = k.c;
  const r = UG.counter;
  k.plate(r, rivets: false);
  final en = k.tp('Built today', UT.label(22, weight: 600));
  en.paint(c, Offset(r.left + 16, r.center.dy - en.height / 2));

  // Mechanical counter: one wheel per digit, rolling when it changes.
  final digits = math.max(3, '$n'.length);
  final now = '$n'.padLeft(digits, '0');
  final from = '${ui.countFrom}'.padLeft(digits, '0');
  final was = from.substring(from.length - digits);
  final roll = eio((t - ui.countAt) / 0.8);
  const dw = 30.0, dh = 48.0, gap = 4.0;
  var x = r.right - 14 - digits * dw - (digits - 1) * gap;
  final y = r.center.dy - dh / 2;
  for (var i = 0; i < digits; i++) {
    final cell = Rect.fromLTWH(x, y, dw, dh);
    c.drawRect(cell, k.fl(BP.paper));
    c.drawRect(cell, k.st(BP.lineDim, 1.1));
    final a = was[i];
    final b = now[i];
    final style = UT.mono(34, color: BP.amber, weight: 600);
    c.save();
    c.clipRect(cell.deflate(1));
    if (a == b || roll >= 1) {
      final p = k.tp(b, style);
      p.paint(c, Offset(cell.center.dx - p.width / 2, cell.center.dy - p.height / 2));
    } else {
      final pa = k.tp(a, style), pb = k.tp(b, style);
      pa.paint(c, Offset(cell.center.dx - pa.width / 2, cell.center.dy - pa.height / 2 - dh * roll));
      pb.paint(c, Offset(cell.center.dx - pb.width / 2, cell.center.dy - pb.height / 2 + dh * (1 - roll)));
    }
    c.restore();
    // The wheel's axle line.
    c.drawLine(Offset(cell.left, cell.center.dy), Offset(cell.left + 3, cell.center.dy), k.st(BP.lineDim, 1));
    x += dw + gap;
  }
}

void _ticker(UiInk k, List<String> names, double t) {
  final c = k.c;
  const r = UG.ticker;
  k.plate(r, rivets: false);
  final inner = r.deflate(10);
  if (names.isEmpty) {
    final en = k.tp('Be the first today!', UT.label(23, color: BP.inkDim, weight: 600));
    en.paint(c, Offset(inner.center.dx - en.width / 2, inner.center.dy - en.height / 2));
    return;
  }
  const sep = 40.0; // room for the diamond between names
  final ps = [for (final n in names) k.tp(n, UT.name(28, color: BP.ink, weight: 500, height: 1.1))];
  final width = ps.fold<double>(0, (a, p) => a + p.width + sep);
  c.save();
  c.clipRect(inner);
  // Static while everything fits; otherwise a slow marquee, right to left.
  final scroll = width - sep > inner.width;
  var x = scroll ? inner.left - (t * 34) % width : inner.left + 6;
  final cy = inner.center.dy;
  while (x < inner.right) {
    for (var i = 0; i < ps.length; i++) {
      final p = ps[i];
      if (x + p.width > inner.left && x < inner.right) p.paint(c, Offset(x, cy - p.height / 2));
      x += p.width;
      final last = !scroll && i == ps.length - 1;
      if (!last && x + sep > inner.left && x < inner.right) k.diamond(Offset(x + sep / 2, cy), 4, BP.amber);
      x += sep;
    }
    if (!scroll) break;
  }
  c.restore();
  // Soft edges where names slide in and out.
  if (scroll) {
    for (final left in [true, false]) {
      final e = Rect.fromLTWH(left ? inner.left : inner.right - 28, inner.top, 28, inner.height);
      c.drawRect(
        e,
        Paint()
          ..shader = LinearGradient(
            begin: left ? Alignment.centerLeft : Alignment.centerRight,
            end: left ? Alignment.centerRight : Alignment.centerLeft,
            colors: [BP.panel, BP.panel.withValues(alpha: 0)],
          ).createShader(e),
      );
    }
  }
}
