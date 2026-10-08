import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart' show dashPath;
import '../../worlds/factory/factory_kit.dart' show bump, c01, ei, eio, eo;
import '../layout.dart';
import '../model.dart';
import 'board.dart';
import 'booth_ui.dart';
import 'ink.dart';

/// After Enter: a receipt rises out of the input with the visitor's ticket
/// as its stub; the ticket tears off and flies up to the rail. Or a kind
/// "not quite" in the same place.
void paintFx(UiInk k, BoothModel m, BoothUi ui) {
  _receipt(k, m, ui, m.t);
  if (ui.flights.isEmpty) return;
  final rail = railLayout(m, k);
  for (final f in ui.flights) {
    _flight(k, m, rail, f, m.t);
  }
}

/// Where a receipt's ticket stub sits once the receipt is up.
Rect _stub(UiInk k, String name) => Rect.fromLTWH(
  UG.left + 14,
  UG.toastBottom - UG.toastH / 2 - UG.ticketH / 2,
  k.ticketWidth(name),
  UG.ticketH,
);

int? _posOf(BoothModel m, int serial) {
  final i = m.queue.indexWhere((j) => j.serial == serial);
  return i < 0 ? null : i + 1;
}

void _receipt(UiInk k, BoothModel m, BoothUi ui, double t) {
  final s = ui.toast;
  if (s == null) return;
  final age = t - s.at;
  if (age < 0 || age > s.life + 0.4) return;
  final c = k.c;
  final col = s.ok ? BP.green : BP.coral;
  final name = s.name;
  final stub = name == null ? null : _stub(k, name);
  final stubW = stub == null ? 0.0 : stub.width + 28;
  final badgeX = stubW + 34;
  final textX = stubW + 64;
  const h = UG.toastH;
  final en = k.tp(s.en, UT.label(22, weight: 600));
  final tw = math.min(UG.input.width - textX - 16, en.width);
  // Rises out of the input's top edge, and sinks back when done.
  final dy = (1 - eo(age / 0.3) + ei(c01((age - s.life) / 0.35))) * (h + 14);
  final r = Rect.fromLTWH(UG.left, UG.toastBottom - h + dy, textX + tw + 18, h);

  c.save();
  c.clipRect(Rect.fromLTRB(0, 0, BL.size.width, UG.input.top));
  // A speech bubble, its tail pointing down into the input.
  final tx = r.left + (stub == null ? 36 : stubW + 34);
  final tail = Path()
    ..moveTo(tx - 10, r.bottom - 1)
    ..lineTo(tx, r.bottom + 9)
    ..lineTo(tx + 10, r.bottom - 1);
  c.drawRect(r, k.fl(BP.panel));
  c.drawRect(r, k.st(col, 1.8));
  c.drawRect(Rect.fromLTRB(tx - 9, r.bottom - 2, tx + 9, r.bottom + 1), k.fl(BP.panel));
  c.drawPath(tail, k.fl(BP.panel));
  c.drawPath(tail, k.st(col, 1.8));

  if (stub != null) {
    // The ticket stub, then a perforation: it tears off and flies away.
    final x = r.left + stubW;
    c.drawPath(
      dashPath(Path()..moveTo(x, r.top + 7)..lineTo(x, r.bottom - 7), dash: 4, gap: 4),
      k.st(col.withValues(alpha: 0.7), 1.3),
    );
    final sr = stub.shift(Offset(0, dy));
    final f = ui.flightFor(s.serial!);
    if (f != null && t - f.at < Flight.leaves) {
      final pos = _posOf(m, s.serial!);
      k.ticket(sr, name!, pos: pos, next: pos == 1, peg: false, tilt: 0.05 * math.sin(age * 11) * (1 - c01(age / 0.8)));
    } else {
      c.drawPath(dashPath(Path()..addRect(sr), dash: 5, gap: 4), k.st(BP.lineFaint, 1.1));
    }
  }

  final b = Offset(r.left + badgeX, r.center.dy);
  c.drawCircle(b, 17, k.fl(col.withValues(alpha: 0.14)));
  c.drawCircle(b, 17, k.st(col, 2));
  if (s.ok) {
    k.tick(b, 16, col, 3);
  } else {
    k.bang(b, 18, col, 3);
  }
  k.put(en, Offset(r.left + textX, r.center.dy - en.height / 2), maxW: tw);
  c.restore();
}

void _flight(UiInk k, BoothModel m, RailLayout rail, Flight f, double t) {
  final age = t - f.at;
  // Until it tears off, the ticket is part of its receipt.
  if (age < Flight.leaves || age >= Flight.lands) return;
  final pos = _posOf(m, f.serial);
  final start = _stub(k, f.name);
  // Its place: its own ticket on the rail; else it is absorbed by the
  // "+N more" tag, or by the board's name if its build has already begun.
  final slot = rail.rectOf(f.serial);
  final building = m.job?.serial == f.serial;
  final Rect? dest = slot ??
      (building
          ? Rect.fromLTWH(UG.nameBox.left, UG.nameBox.top + 8, start.width, start.height)
          : pos != null
          ? rail.moreRect
          : null);
  final p = eio((age - Flight.leaves) / (Flight.lands - Flight.leaves));
  if (dest == null) {
    // Removed from the line meanwhile: the ticket just fades.
    k.faded(1 - p, () => k.ticket(start, f.name, peg: false));
    return;
  }
  // Straight up the left side, then across to its place: never over the
  // construction site.
  final a = start.center, b = dest.center;
  final ctrl = Offset(a.dx, b.dy + 90);
  for (final (lag, alpha) in [(0.10, 0.16), (0.05, 0.32), (0.0, 1.0)]) {
    final q = c01(p - lag);
    if (lag > 0 && (q <= 0 || q >= 1)) continue;
    final sz = slot != null ? Size.lerp(start.size, slot.size, q)! : start.size * (1 - 0.3 * q);
    k.faded(alpha * (slot == null ? 1 - eo(c01((q - 0.75) / 0.25)) : 1), () {
      k.ticket(
        Rect.fromCenter(center: quad(a, ctrl, b, q), width: sz.width, height: sz.height),
        f.name,
        pos: pos,
        next: pos == 1,
        peg: slot != null && q > 0.9,
        tilt: 0.3 * bump(q) * (b.dx >= a.dx ? 1 : -1),
        scale: 1 + 0.18 * bump(q),
      );
    });
  }
}
