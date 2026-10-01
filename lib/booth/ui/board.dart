import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart' show dashPath;
import '../../worlds/factory/factory_kit.dart' show bump, c01, eo, rnd;
import '../model.dart';
import 'booth_ui.dart';
import 'ink.dart';

/// One order ticket on the rail.
class RailSlot {
  const RailSlot(this.job, this.rect, this.pos);
  final Job job;
  final Rect rect;

  /// Place in line, 1 = next.
  final int pos;
}

/// The tickets that fit on the rail, then "+N more".
class RailLayout {
  const RailLayout(this.slots, this.more, this.end);
  final List<RailSlot> slots;

  /// Names in line without a ticket on show.
  final int more;

  /// Where the tickets end (the "+N more" tag hangs here).
  final double end;

  static const moreW = 148.0;

  Rect get moreRect => Rect.fromLTWH(end, UG.ticketTop + 4, moreW, 29);

  Rect? rectOf(int serial) {
    for (final s in slots) {
      if (s.job.serial == serial) return s.rect;
    }
    return null;
  }
}

RailLayout railLayout(BoothModel m, UiInk k) {
  final q = m.queue;
  final slots = <RailSlot>[];
  var x = UG.left + 8;
  for (var i = 0; i < q.length && i < UG.maxTickets; i++) {
    final w = k.ticketWidth(q[i].name);
    final rest = q.length - i - 1;
    if (x + w + (rest > 0 ? RailLayout.moreW + UG.ticketGap : 0) > UG.right) break;
    slots.add(RailSlot(q[i], Rect.fromLTWH(x, UG.ticketTop, w, UG.ticketH), i + 1));
    x += w + UG.ticketGap;
  }
  return RailLayout(slots, q.length - slots.length, x);
}

/// Top left: the factory's signboard, the name being built (big) and its
/// progress, then who's next as order tickets on a rail.
void paintBoard(UiInk k, BoothModel m, BoothUi ui) {
  final j = m.job;
  _sign(k, j, m.t);
  if (j != null) _nowBuilding(k, m, j, m.t);
  _rail(k, m, ui, m.t);
}

enum _Bulbs { wave, chase, party, dim }

void _sign(UiInk k, Job? j, double t) {
  final c = k.c;
  const r = UG.sign;
  // Hung from above on two cables, like the deck's hall signs.
  for (final x in [r.left + 64, r.right - 64]) {
    c.drawLine(Offset(x, 0), Offset(x, r.top - 5), k.st(BP.inkDim, 1.2));
    c.drawCircle(Offset(x, r.top - 3), 2.6, k.st(BP.line, 1.2));
  }
  k.plate(r);

  // Marquee bulbs: a slow wave while warming up, a chase while building,
  // everything flashing for the celebration.
  final mode = switch (j) {
    null => _Bulbs.wave,
    Job(sample: true) => _Bulbs.wave,
    Job(phase: Phase.intake || Phase.build || Phase.reveal) => _Bulbs.chase,
    Job(phase: Phase.celebrate) => _Bulbs.party,
    Job() => _Bulbs.dim,
  };
  const n = 25;
  const x0 = UG.left + 24, x1 = UG.right - 24;
  for (var i = 0; i < n; i++) {
    final on = switch (mode) {
      _Bulbs.wave => 0.2 + 0.8 * c01(math.sin(t * 1.7 - i * 0.42) * 1.4),
      _Bulbs.chase => (i + (t * 7).floor()) % 3 == 0 ? 1.0 : 0.1,
      _Bulbs.party => (i + (t * 5).floor()) % 2 == 0 ? 1.0 : 0.3,
      _Bulbs.dim => 0.1,
    };
    k.bulb(Offset(x0 + (x1 - x0) * i / (n - 1), UG.bulbY), on);
  }

  // 名前工場 · Name Factory (bricks), or 名前工房 · Name Workshop (crafts).
  final workshop = j?.mode == BuildMode.craft;
  final ja = k.tp(workshop ? '名前工房' : '名前工場', UT.label(29, weight: 700));
  final dot = k.tp('·', UT.label(29, color: BP.inkDim));
  final en = k.tp(workshop ? 'Name Workshop' : 'Name Factory', UT.label(29, weight: 600));
  final w = ja.width + 12 + dot.width + 12 + en.width;
  var x = r.center.dx - w / 2;
  for (final p in [ja, dot, en]) {
    p.paint(c, Offset(x, UG.titleY - p.height / 2));
    x += p.width + 12;
  }
  c.drawLine(Offset(r.left + 6, UG.divider), Offset(r.right - 6, UG.divider), k.st(BP.lineDim, 1));
}

void _nowBuilding(UiInk k, BoothModel m, Job j, double t) {
  final c = k.c;
  // Name Factory counts bricks; Name Workshop counts finished characters.
  final craft = j.mode == BuildMode.craft;
  final plan = j.plan;
  final total = craft ? (plan?.chars.length ?? 0) : j.total;
  final laid = craft
      ? (plan == null ? 0 : plan.chars.where((ch) => ch.end <= j.buildProgress(t)).length)
      : j.laid(t);
  final next = m.queue.isEmpty ? null : m.queue.first.name;
  final clearing = j.phase == Phase.demolish || j.phase == Phase.cleanup;

  // What the board says, per phase.
  String kick;
  var kickCol = BP.amber;
  var nameCol = BP.amber;
  var barCol = BP.amber;
  var bar = craft ? j.buildProgress(t) : (total == 0 ? 0.0 : laid / total);
  String? right; // right of the kicker
  String time; // right of the bar
  var timeIcon = 1; // 1 clock, 2 tick, 0 none
  if (j.sample) {
    final makingRoom = next != null;
    kick = makingRoom ? 'MAKING ROOM · まもなく開始' : 'WARMING UP · 準備中';
    kickCol = BP.line;
    nameCol = makingRoom || clearing ? BP.inkFaint : BP.line;
    barCol = BP.lineDim;
    if (clearing) bar = 0;
    right = makingRoom ? 'next: $next' : 'sample · 見本';
    timeIcon = 0;
    time = makingRoom ? 'your turn soon' : 'type your name ↓';
  } else {
    switch (j.phase) {
      case Phase.intake || Phase.build:
        kick = 'NOW BUILDING FOR · 建設中';
        right = total == 0 ? 'reading… · 解析中' : '$laid / $total';
        final left = j.phase == Phase.intake
            ? j.phaseLen - j.since(t) + j.buildLen
            : j.phaseLen - j.since(t);
        time = j.phase == Phase.intake && j.buildLen == 0 ? '…' : clock(left);
      case Phase.reveal:
        kick = 'NOW BUILDING FOR · 建設中';
        right = '$total / $total';
        time = 'finishing · 仕上げ';
        timeIcon = 0;
      case Phase.celebrate:
        kick = 'BUILT FOR · 完成！';
        kickCol = BP.green;
        barCol = BP.green;
        bar = 1;
        right = craft ? '$total characters · 文字' : '$total bricks';
        time = clock(j.phaseStart - j.startedAt);
        timeIcon = 2;
      case Phase.demolish || Phase.cleanup:
        kick = 'CLEARING THE SITE · 解体中';
        kickCol = BP.inkDim;
        nameCol = BP.inkFaint;
        barCol = BP.lineDim;
        bar = j.phase == Phase.demolish ? 1 - j.progress(t) : 0;
        right = next == null ? null : 'next: $next';
        final left =
            j.phaseLen -
            j.since(t) +
            (j.phase == Phase.demolish ? phaseSeconds[Phase.cleanup]! : 0);
        time = clock(left);
    }
  }

  const box = UG.nameBox;
  // Kicker, and bricks laid (or who's next) on the right.
  final kp = k.tp(kick, UT.mono(17, color: kickCol, weight: 600, ls: 0.8));
  kp.paint(c, Offset(box.left, UG.kickerY - 1));
  if (right != null) {
    final isCount = right.contains(' / ');
    final rp = k.tp(right, UT.mono(15, color: BP.inkDim, weight: 500));
    final rx = box.right - rp.width;
    rp.paint(c, Offset(rx, UG.kickerY + 1));
    if (isCount) k.brickIcon(Offset(rx - 26, UG.kickerY + 4), BP.inkDim);
  }

  // The name, big, on a baseline (Japanese falls back to another font with
  // other metrics). Long names shrink to fit.
  final np = k.tp(j.name, UT.name(56, color: nameCol, weight: 600, height: 1.0));
  final nw = k.putBase(np, box.left, UG.nameBase, maxW: box.width);
  if (!j.sample && j.phase == Phase.celebrate) {
    // Sparkles around the name.
    for (var i = 0; i < 8; i++) {
      final ph = (t * 0.9 + rnd(i, j.serial)) % 1;
      final p = Offset(
        box.left + 8 + (nw + 24) * rnd(i, 3),
        box.top + 4 + (box.height - 8) * rnd(i, 7),
      );
      k.star(p, 8 * bump(ph), i.isEven ? BP.amber : BP.ink);
    }
  }

  // Progress: a course of bricks, then the time left.
  final tp = k.tp(time, UT.mono(15, color: BP.inkDim, weight: 500));
  final tw = tp.width + (timeIcon == 0 ? 0 : 24);
  final bx0 = box.left;
  final bx1 = box.right - tw - 16;
  const cw = 13.0, gap = 3.0;
  final cells = ((bx1 - bx0 + gap) / (cw + gap)).floor();
  final fill = bar * cells;
  for (var i = 0; i < cells; i++) {
    final r = Rect.fromLTWH(bx0 + i * (cw + gap), UG.barY, cw, UG.barH);
    final f = c01(fill - i);
    if (f > 0) c.drawRect(Rect.fromLTWH(r.left, r.top, r.width * f, r.height), k.fl(barCol));
    c.drawRect(r, k.st(f >= 1 ? barCol : BP.lineFaint, 1));
  }
  final tx = box.right - tp.width;
  final cy = UG.barY + UG.barH / 2;
  tp.paint(c, Offset(tx, cy - tp.height / 2));
  if (timeIcon == 1) k.clockIcon(Offset(tx - 13, cy), 7, BP.inkDim, t);
  if (timeIcon == 2) k.tick(Offset(tx - 13, cy), 13, BP.green, 2.2);
}

void _rail(UiInk k, BoothModel m, BoothUi ui, double t) {
  final c = k.c;
  final rail = railLayout(m, k);
  // The wire, between two posts.
  c.drawLine(
    const Offset(UG.left, UG.railY),
    const Offset(UG.right, UG.railY),
    k.st(BP.lineDim, 1.4),
  );
  for (final x in [UG.left, UG.right]) {
    c.drawRect(
      Rect.fromCenter(center: Offset(x, UG.railY), width: 6, height: 12),
      k.fl(BP.lineDim),
    );
  }

  // The first ticket just went to the factory: the rest slide up.
  var shift = 0.0;
  final j = m.job;
  if (j != null && !j.sample) {
    final age = t - j.startedAt;
    final f = ui.flightFor(j.serial);
    if (age >= 0 && age < 0.9 && (f == null || f.landed(t))) {
      // Its ticket is pulled up into the sign.
      final w = k.ticketWidth(j.name);
      shift = (1 - eo(age / 0.9)) * (w + UG.ticketGap);
      final rise = (UG.ticketTop + UG.ticketH - UG.sign.bottom) * eo(age / 0.7);
      c.save();
      c.clipRect(Rect.fromLTRB(0, UG.sign.bottom, UG.right + 20, UG.ticketTop + UG.ticketH + 10));
      k.ticket(
        Rect.fromLTWH(UG.left + 8, UG.ticketTop - rise, w, UG.ticketH),
        j.name,
        pos: 1,
        next: true,
      );
      c.restore();
    }
  }

  for (final s in rail.slots) {
    final f = ui.flightFor(s.job.serial);
    if (f != null && !f.landed(t)) continue; // still flying in: its place is kept
    final landed = f == null ? 9.0 : t - f.at - Flight.lands;
    final bounce = landed < 0.4 ? 0.1 * bump(landed / 0.4) : 0.0;
    k.ticket(
      s.rect.shift(Offset(shift, 0)),
      s.job.name,
      pos: s.pos,
      next: s.pos == 1,
      tilt: 0.022 * math.sin(t * 1.3 + s.job.serial * 1.7),
      scale: 1 + bounce,
    );
  }

  if (rail.more > 0) {
    // Bounces when a ticket lands on it.
    var bounce = 0.0;
    for (final f in ui.flights) {
      final a = t - f.at - Flight.lands;
      if (a >= 0 && a < 0.4 && rail.rectOf(f.serial) == null) bounce = 0.12 * bump(a / 0.4);
    }
    final r0 = rail.moreRect.shift(Offset(shift, 0));
    final r = Rect.fromCenter(
      center: r0.center,
      width: r0.width * (1 + bounce),
      height: r0.height * (1 + bounce),
    );
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(14));
    c.drawRRect(rr, k.fl(BP.panel));
    c.drawRRect(rr, k.st(bounce > 0 ? BP.amber : BP.lineDim, 1.2));
    final p = k.tp(
      '+${rail.more} more · 他${rail.more}名',
      UT.mono(15, color: BP.inkDim, weight: 600),
    );
    k.putMid(p, r.left + 12, r.center.dy, maxW: r.width - 22);
  }

  if (m.queue.isEmpty && (j == null || j.sample || t - j.startedAt > 0.9)) {
    // An empty ticket: this could be you.
    final p = k.tp('your name here? · ここにあなたの名前', UT.mono(15, color: BP.inkFaint, weight: 500));
    final r = Rect.fromLTWH(UG.left + 8, UG.ticketTop, p.width + 28, UG.ticketH);
    c.drawPath(dashPath(Path()..addRect(r), dash: 5, gap: 4), k.st(BP.inkFaint, 1.1));
    final pg = Rect.fromCenter(center: Offset(r.center.dx, r.top - 2), width: 7, height: 13);
    c.drawRect(pg, k.st(BP.lineDim, 1));
    k.putMid(p, r.left + 14, r.center.dy);
  }
}
