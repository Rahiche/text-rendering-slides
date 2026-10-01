import 'package:flutter/painting.dart';

import '../../deck/theme.dart';
import '../../worlds/factory/factory_kit.dart' show c01, eo;
import '../model.dart';
import 'booth_ui.dart';
import 'ink.dart';

/// Operator only: the help (Ctrl+Shift+H), feedback for each shortcut, and a
/// reminder while fast-forward is on (so it isn't left on for visitors).
void paintOperator(UiInk k, BoothModel m, BoothUi ui) {
  final f = ui.flash != null && ui.flash!.age < 3 ? ui.flash : null;
  if (ui.help) {
    // Everything goes in the panel (nothing may hang down over the site).
    _help(k, m, ui, f);
    return;
  }
  var y = UG.chip.dy;
  if (ui.speed > 1) {
    _chip(
      k,
      Offset(UG.chip.dx, y),
      '▶▶ ×${ui.speed.round()} fast-forward · 早送り中 · Ctrl⇧↓',
      BP.amber,
      1,
    );
    y += 42;
  }
  if (f != null) {
    final a = f.age;
    _chip(
      k,
      Offset(UG.chip.dx, y),
      '${f.en} · ${f.ja}',
      f.warn ? BP.coral : BP.green,
      eo(a / 0.15) * (1 - c01((a - 2.6) / 0.4)),
    );
  }
}

void _chip(UiInk k, Offset o, String s, Color col, double alpha) {
  k.faded(alpha, () {
    final p = k.tp(s, UT.mono(15, color: col, weight: 600));
    final r = Rect.fromLTWH(o.dx, o.dy, p.width + 28, 32);
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(16));
    k.c.drawRRect(rr, k.fl(BP.panel));
    k.c.drawRRect(rr, k.st(col, 1.5));
    p.paint(k.c, Offset(r.left + 14, r.center.dy - p.height / 2));
  });
}

/// A small key cap; returns its right edge.
double _key(UiInk k, String label, double x, double y, {void Function(Rect face)? icon}) {
  final p = label.isEmpty ? null : k.tp(label, UT.mono(13, color: BP.ink, weight: 600));
  final w = icon != null ? 30.0 : (p!.width + 14).clamp(26.0, 60.0);
  final r = Rect.fromLTWH(x, y, w, 24);
  final rr = RRect.fromRectAndRadius(r, const Radius.circular(4));
  k.c.drawRRect(rr.shift(const Offset(0, 2)), k.fl(BP.paper));
  k.c.drawRRect(rr, k.fl(BP.panel));
  k.c.drawRRect(rr, k.st(BP.inkDim, 1.1));
  if (icon != null) {
    icon(r);
  } else {
    p!.paint(k.c, Offset(r.center.dx - p.width / 2, r.center.dy - p.height / 2));
  }
  return r.right;
}

const _rows = [
  ('S', 'Skip the current name', 'スキップ'),
  ('⌫', 'Remove the last name in line', '最後の予約を削除'),
  ('M', 'Factory ↔ Workshop (next name)', '工場 ↔ 工房'),
  ('F', 'Full screen on / off', '全画面'),
  ('↑↓', 'Fast-forward ×2 / slower', '早送り'),
  ('R', 'Reset today’s count (twice)', '今日の記録をリセット'),
  ('H', 'Show / hide this help', 'ヘルプ'),
];

void _help(UiInk k, BoothModel m, BoothUi ui, Flash? flash) {
  final c = k.c;
  const r = UG.help;
  k.plate(r, edge: BP.amber);
  final title = k.tp('Operator keys · オペレーター用', UT.label(21, weight: 600));
  title.paint(c, Offset(r.left + 22, r.top + 15));
  final status = k.tp(
    '×${ui.speed.round()} · in line ${m.queue.length} · today ${ui.today.length}',
    UT.mono(13, color: BP.inkDim),
  );
  status.paint(c, Offset(r.right - 22 - status.width, r.top + 22));

  var y = r.top + 54;
  for (final (key, en, ja) in _rows) {
    final armed = key == 'R' && ui.armed;
    if (armed) {
      c.drawRect(
        Rect.fromLTRB(r.left + 12, y - 4, r.right - 12, y + 28),
        k.fl(BP.coral.withValues(alpha: 0.12)),
      );
    }
    var x = _key(k, 'Ctrl', r.left + 22, y) + 5;
    x = _key(k, '⇧', x, y) + 5;
    switch (key) {
      case '⌫':
        _key(
          k,
          '',
          x,
          y,
          icon: (f) =>
              k.backspace(Rect.fromCenter(center: f.center, width: 18, height: 12), BP.ink, 1.3),
        );
      case '↑↓':
        x = _key(k, '↑', x, y) + 4;
        _key(k, '↓', x, y);
      default:
        _key(k, key, x, y);
    }
    final col = armed ? BP.coral : BP.ink;
    final pe = k.tp(armed ? 'Press R again to reset' : en, UT.label(17, color: col, weight: 500));
    final pj = k.tp(
      armed ? 'もう一度押すとリセット' : ja,
      UT.label(14, color: armed ? BP.coral : BP.inkDim, weight: 500),
    );
    final tx = r.left + 176;
    pe.paint(c, Offset(tx, y + 12 - pe.height / 2));
    k.put(
      pj,
      Offset(tx + pe.width + 12, y + 12 - pj.height / 2),
      maxW: r.right - 22 - (tx + pe.width + 12),
    );
    y += 33;
  }
  // Footer: the last operator action, else where the history is kept.
  final loc = ui.history.store.location;
  final foot = flash != null
      ? k.tp(
          '${flash.en} · ${flash.ja}',
          UT.mono(13, color: flash.warn ? BP.coral : BP.green, weight: 600),
        )
      : k.tp(
          loc == null ? 'history: this session only' : 'history: $loc',
          UT.mono(11, color: BP.inkFaint),
        );
  k.put(foot, Offset(r.left + 22, r.bottom - 16 - foot.height / 2), maxW: r.width - 44);
}
