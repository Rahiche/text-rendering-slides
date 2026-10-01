part of 'factory_draw.dart';

// ─────────────────────────────────────────────────────────────────────────────
// One frame
// ─────────────────────────────────────────────────────────────────────────────

/// A crate on the line: bottom centre, size, what it carries and how far it
/// has come (0 raw code points, 1 itemized, 2 has its font, 3 shaped).
class _Crate {
  _Crate(this.x, this.y, this.w, this.h, this.stage, {required this.data, this.glyph, this.alpha = 1});

  final double x, y, w, h;
  final int stage;

  /// The name it belongs to.
  final JobData data;
  final Grapheme? glyph;
  final double alpha;

  bool get lesson => glyph == null;
}

class _Frame extends FactoryInk {
  _Frame(super.c, this.m, this.sc) : t = m.t, j = m.job {
    d = sc.data(j, current: true);
    final jj = j;
    if (jj != null && jj.cutAt != null && sc.sys.cut == jj) cutAt = sc.sys.cutAt;
    _plan();
  }

  final BoothModel m;
  final FactoryScene sc;
  final double t;
  final Job? j;
  late final JobData? d;

  /// When the current job was cut short (its line and belt stop), if it was.
  double? cutAt;

  FactoryTexts get tx => sc.texts;
  FactorySystem get sys => sc.sys;

  /// Seconds since the current name arrived.
  double get s => j == null ? 1e9 : t - j!.startedAt;

  // What's happening at each station this frame.
  final crates = <_Crate>[];

  /// Dwell progress (0..1) at stations 0..4, or -1 when idle. Station 0 is
  /// the hopper reading, station 4 the kiln baking.
  final work = List<double>.filled(5, -1);
  final workOn = List<_Crate?>.filled(5, null);

  /// Lesson step (0..4) the screen and plates show, or -1.
  int step = -1;

  /// Hopper gate opening 0..1, the code point/glyph in the reader.
  double gate = 0;
  String? reading;
  bool readingHot = false;

  /// Progress of the current index move of the line (0..1), for the slats.
  double lineMove = 0;

  // ── Planning: where the lesson and production crates are ─────────────────

  void _plan() {
    final jj = j, dd = d;
    // A name cut short just before this one: its crates fade where they were.
    final old = sys.cut;
    if (old != null && old != jj && t < sys.cutAt + 0.6) {
      final od = sc.data(old);
      if (od != null) _planJob(old, od, sys.cutAt, main: false);
    }
    if (jj == null || dd == null) return;
    _planJob(jj, dd, cutAt, main: true);
  }

  /// Puts [jj]'s crates on the line. Only the [main] job drives the machines
  /// (what they work on, the screen's step).
  void _planJob(Job jj, JobData dd, double? tc, {required bool main}) {
    final tv = tc == null ? t : math.min(t, tc);
    final fade = tc == null ? 1.0 : 1 - seg(t, tc, tc + 0.6);
    if (fade <= 0) return;
    final work = main ? this.work : List<double>.filled(5, -1);

    // The lesson: the name's own crate, during intake.
    final ls = tv - jj.startedAt;
    if (ls < FL.arrive(4) + 0.6) {
      if (main) step = FL.step(ls);
      if (main && ls >= FL.landed && ls < FL.readEnd) {
        final n = dd.cps.length;
        final f = (ls - FL.landed) / (FL.readEnd - FL.landed) * n;
        final k = f.floor().clamp(0, n - 1);
        work[0] = c01((ls - FL.landed) / (FL.readEnd - FL.landed));
        reading = dd.cps[k].shown;
        readingHot = f - k < 0.8;
      }
      final w = _lessonW(dd);
      if (ls >= FL.readEnd && ls < FL.arrive(4)) {
        double x = FG.sx(0), y = FG.lineY;
        if (ls < FL.dropEnd) {
          final a = ei(seg(ls, FL.readEnd, FL.dropEnd));
          y = lerp(FG.hopperBody.bottom - 4, FG.lineY, a);
          if (main) gate = bump(seg(ls, FL.readEnd - 0.1, FL.dropEnd + 0.15));
        } else {
          for (var k = 0; k < 4; k++) {
            if (ls < FL.leave[k]) {
              x = FG.sx(k);
              if (k > 0) {
                work[k] = seg(ls, FL.arrive(k), FL.leave[k]);
              }
              break;
            }
            if (ls < FL.leave[k] + FL.mv) {
              final e = eio((ls - FL.leave[k]) / FL.mv);
              x = lerp(FG.sx(k), FG.sx(k + 1), e);
              if (main) lineMove = e;
              break;
            }
          }
        }
        var stage = 0;
        for (var k = 1; k < 4; k++) {
          if (ls >= FL.arrive(k) + 0.5 * (FL.leave[k] - FL.arrive(k))) stage = k;
        }
        final cr = _Crate(x, y, w, FG.lessonH, stage, data: dd, alpha: fade);
        crates.add(cr);
        for (var k = 1; k < 4; k++) {
          if (main && work[k] >= 0) workOn[k] = cr;
        }
      }
      if (ls >= FL.arrive(4) && ls < FL.arrive(4) + 0.6) work[4] = (ls - FL.arrive(4)) / 0.6;
    }

    // Production: a crate per pallet through the build.
    final run = dd.crates;
    if (run != null) {
      final k0 = run.kilnAt(0);
      final lo = math.max(0, ((tv - k0) / run.dc).floor() - 1);
      for (var mm = lo; mm < run.count && mm < lo + 8; mm++) {
        final kin = run.kilnAt(mm);
        final a0 = run.at(mm, 0);
        if (tc != null && a0 - run.mv - 0.6 * run.dc > tc) break;
        if (tv >= kin) {
          if (tv < kin + run.bake) {
            work[4] = (tv - kin) / run.bake;
          }
          continue;
        }
        final g = dd.crateGlyphs[mm % dd.crateGlyphs.length];
        // Being read in the hopper.
        final readFrom = a0 - run.mv - 0.6 * run.dc;
        if (tv < a0 - run.mv) {
          if (main && tv >= readFrom) {
            work[0] = (tv - readFrom) / (0.6 * run.dc);
            reading = g.text;
            readingHot = work[0] < 0.8;
          }
          continue;
        }
        double x = FG.sx(0), y = FG.lineY;
        if (tv < a0) {
          y = lerp(FG.hopperBody.bottom - 4, FG.lineY, ei((tv - (a0 - run.mv)) / run.mv));
          if (main) gate = math.max(gate, bump(seg(tv, a0 - run.mv - 0.1, a0 + 0.15)));
        } else {
          for (var q = 1; q <= 4; q++) {
            final at = run.at(mm, q);
            if (tv < at - run.mv) {
              x = FG.sx(q - 1.0);
              if (q - 1 >= 1) work[q - 1] = seg(tv, run.at(mm, q - 1), at - run.mv);
              break;
            }
            if (tv < at) {
              final e = eio((tv - (at - run.mv)) / run.mv);
              x = lerp(FG.sx(q - 1.0), FG.sx(q.toDouble()), e);
              if (main) lineMove = e;
              break;
            }
          }
        }
        var stage = 0;
        for (var q = 1; q < 4; q++) {
          if (tv >= run.at(mm, q) + 0.4 * (run.dc - run.mv)) stage = q;
        }
        final cr = _Crate(x, y, 24, FG.crateH, stage, data: dd, glyph: g, alpha: fade);
        crates.add(cr);
        for (var q = 1; q < 4; q++) {
          if (main && work[q] >= 0 && (cr.x - FG.sx(q.toDouble())).abs() < 1) workOn[q] = cr;
        }
      }
    }
    // During the build the screen replays the lesson, one step every 5 s,
    // starting where the live lesson ended (raster).
    final bs = jj.buildStart;
    if (main && jj.phase == Phase.build && bs != null && ls >= FL.arrive(4) + 0.6) {
      step = (((tv - bs) / 5).floor() + 4) % 5;
    }
  }

  double _lessonW(JobData dd) {
    final p = tx.get(dd.name, FS.name(12, BP.ink), key: 'n12');
    return (p.width + 12).clamp(34.0, 58.0);
  }

  // ── Drawing ───────────────────────────────────────────────────────────────

  void draw() {
    c.drawPicture(sc._back!);
    lampCones();
    elevator();
    lineSlats();
    hopperInside();
    kilnInside();
    rubble();
    for (final cr in crates) {
      lineCrate(cr);
    }
    pallets();
    exitRollers();
    c.drawPicture(sc._front!);
    hopperLive();
    sorterLive();
    fontsLive();
    pressLive();
    kilnLive();
    curtain();
    roofLive();
    clockHands();
    crew();
    platesLive();
    screen();
  }

  // ── Light ────────────────────────────────────────────────────────────────

  void lampCones() {
    for (final (x, ph) in [(112.0, 0.0), (520.0, 2.0)]) {
      final on = 0.8 + 0.2 * math.sin(t * 1.3 + ph) * math.sin(t * 0.7 + ph * 2);
      hangingLamp(Offset(x, FG.trussY), 484, FG.floor, on, spread: 46);
    }
    // The machine the screen is talking about stands in a spotlight.
    if (step >= 0) {
      final x = FG.machineX[step];
      final cone = Path()
        ..moveTo(x - 24, FG.plateY + 11)
        ..lineTo(x + 24, FG.plateY + 11)
        ..lineTo(x + 50, FG.lineY + 8)
        ..lineTo(x - 50, FG.lineY + 8)
        ..close();
      c.drawPath(cone, fl(BP.amber.withValues(alpha: 0.075)));
    }
  }

  // ── Recycling: elevator, rubble, the pile in the hopper ──────────────────

  /// 0..1 while rubble comes back (around the end of the last cleanup).
  double get recycling {
    final ce = sys.cleanupEnd;
    if (sys.cleanupLen <= 0) return 0;
    return seg(t, ce - 4.4, ce - 4.0) * (1 - seg(t, ce + 2.4, ce + 3.0));
  }

  void elevator() {
    const x = FG.elevX, top = FG.elevTop, bot = FG.elevBot, r = FG.elevR;
    const side = bot - top;
    const len = 2 * side + 2 * math.pi * r;
    final pos = sys.elevator(t);
    // Pulleys.
    for (final y in [top, bot]) {
      final o = Offset(x, y);
      c.drawCircle(o, r, fl(BP.panel));
      c.drawCircle(o, r, st(BP.line, 1.2));
      final a = pos / r;
      final sp = Path();
      for (var i = 0; i < 3; i++) {
        final dd = Offset(math.cos(a + i * math.pi / 3), math.sin(a + i * math.pi / 3)) * (r - 2);
        sp
          ..moveTo(o.dx - dd.dx, o.dy - dd.dy)
          ..lineTo(o.dx + dd.dx, o.dy + dd.dy);
      }
      c.drawPath(sp, st(BP.lineDim, 1));
    }
    // Chain.
    c.drawLine(Offset(x + r, top), Offset(x + r, bot), st(BP.lineDim, 1));
    c.drawLine(Offset(x - r, top), Offset(x - r, bot), st(BP.lineDim, 1));
    // Buckets: up the right side, over the head, down the left.
    final full = recycling > 0;
    const n = 13;
    for (var i = 0; i < n; i++) {
      final dd = (pos + i * len / n) % len;
      final (p, out) = _loop(dd, x, top, bot, r, side);
      final tang = Offset(-out.dy, out.dx);
      final mouth = p + out * 8;
      final bucket = Path()
        ..moveTo(p.dx + tang.dx * 3, p.dy + tang.dy * 3)
        ..lineTo(mouth.dx + tang.dx * 4, mouth.dy + tang.dy * 4)
        ..lineTo(mouth.dx - tang.dx * 3, mouth.dy - tang.dy * 3)
        ..lineTo(p.dx - tang.dx * 3, p.dy - tang.dy * 3)
        ..close();
      c.drawPath(bucket, fl(BP.panel));
      c.drawPath(bucket, st(BP.line, 1));
      if (full && dd < side + 6) {
        // Rubble riding up.
        for (var k = 0; k < 3; k++) {
          final q = p + out * (3.0 + k * 2) + tang * (rnd(i, k, 3) * 4 - 1) - const Offset(0, 3);
          c.drawRect(Rect.fromCenter(center: q, width: 2.6, height: 2.6), fl(brickColor(0.35 + 0.6 * rnd(i, k, 4))));
        }
      }
    }
  }

  /// A point on the elevator loop [dd] px from the boot's right side, and
  /// the outward normal there.
  (Offset, Offset) _loop(double dd, double x, double top, double bot, double r, double side) {
    if (dd < side) return (Offset(x + r, bot - dd), const Offset(1, 0));
    dd -= side;
    final arc = math.pi * r;
    if (dd < arc) {
      final a = dd / r; // 0 → π over the top
      final n = Offset(math.cos(a), -math.sin(a));
      return (Offset(x, top) + n * r, n);
    }
    dd -= arc;
    if (dd < side) return (Offset(x - r, top + dd), const Offset(-1, 0));
    dd -= side;
    final a = math.pi + dd / r;
    final n = Offset(math.cos(a), -math.sin(a));
    return (Offset(x, bot) + n * r, n);
  }

  void rubble() {
    final ce = sys.cleanupEnd;
    if (sys.cleanupLen <= 0 || t < ce - 4.2 || t > ce + 3.2) return;
    final pieces = (sys.rubble / 24).clamp(16, 44).round();
    // Into the bin from the street (the truck tips it), over its lip.
    for (var k = 0; k < pieces; k++) {
      final at = ce - 4.0 + 3.5 * math.pow(rnd(k, 71), 0.8);
      final a = (t - at) / 0.8;
      if (a < 0 || a > 1) continue;
      final from = Offset(146 + 52 * rnd(k, 72), FG.floor + 8);
      final to = Offset(50 + 74 * rnd(k, 73), FG.binTop + 8);
      final p = Offset.lerp(from, to, a)! + Offset(0, -54 * math.sin(a * math.pi) * (0.65 + 0.5 * rnd(k, 74)));
      c.save();
      c.translate(p.dx, p.dy);
      c.rotate(a * 6 * (rnd(k, 75) - 0.5));
      c.drawRect(const Rect.fromLTWH(-2.6, -1.9, 5.2, 3.8), fl(brickColor(0.3 + 0.7 * rnd(k, 76))));
      c.restore();
    }
    // The heap in the bin, rising then carried off by the elevator.
    final heap = seg(t, ce - 3.6, ce - 1.0) * (1 - seg(t, ce - 0.2, ce + 2.6));
    if (heap > 0) {
      for (var k = 0; k < 20; k++) {
        final x = 46 + k * 4.4;
        final top = heap * 12 * math.sin((k + 0.5) / 20 * math.pi) + rnd(k, 77) * 2;
        for (var y = 0.0; y < top; y += 3.4) {
          c.drawRect(Rect.fromLTWH(x, FG.binTop + 1 - y - 3, 4, 3), fl(brickColor(0.3 + 0.6 * rnd(k, y.floor(), 78))));
        }
      }
    }
    // Pouring from the elevator head down the chute into the hopper.
    if (t > ce - 2.8 && t < ce + 2.4) {
      for (var k = 0; k < 7; k++) {
        final a = ((t - ce) * 1.6 + k / 7) % 1;
        final p = Offset(lerp(FG.elevX + 8, FG.elevX + 26, a), lerp(FG.elevTop - 4, FG.elevTop + 6, a) + 10 * a * a);
        c.drawRect(Rect.fromCenter(center: p, width: 2.8, height: 2.8), fl(brickColor(0.4 + 0.5 * rnd(k, 79))));
      }
    }
  }

  /// How full the hopper is with recycled pixels (0..1).
  double get pile {
    final ce = sys.cleanupEnd;
    final fill = sys.cleanupLen <= 0 ? 1.0 : seg(t, ce - 2.6, ce + 2.4);
    return c01(0.3 + 0.55 * fill * (1 - 0.7 * seg(t, ce + 4, ce + 80)));
  }

  void hopperInside() {
    final w = FG.hopperPile;
    c.drawRect(w, fl(_glass));
    final level = pile;
    final shake = work[0] >= 0 ? math.sin(t * 60) * 0.8 : 0.0;
    c.save();
    c.clipRect(w);
    for (var k = 0; k < 9; k++) {
      final x = w.left + 2 + k * 4.0;
      final h = level * 13 * (0.75 + 0.25 * math.sin(k * 1.7 + 0.4)) + 2;
      for (var y = 0.0; y < h; y += 3.2) {
        final col = brickColor(0.25 + 0.7 * rnd(k, (y * 3).floor(), 5));
        c.drawRect(Rect.fromLTWH(x + shake * ((k + y.floor()).isEven ? 1 : -1), w.bottom - 3 - y, 3, 2.6), fl(col));
      }
    }
    c.restore();
    // Reader window: the character being read.
    final r = FG.hopperReader;
    c.drawRect(r, fl(_glass));
    final rd = reading;
    if (rd != null) {
      final col = readingHot ? BP.amber : BP.inkDim;
      paintFit(tx.get(rd, FS.name(22, col), key: readingHot ? 'rd1' : 'rd0'), r.deflate(3), fitHeight: true);
      // Scan beam.
      final y = r.top + 3 + (r.height - 6) * (0.5 + 0.5 * math.sin(t * 9));
      c.drawLine(Offset(r.left + 2, y), Offset(r.right - 2, y), st(BP.amber.withValues(alpha: 0.5), 1));
    } else if ((t * 1.5).floor().isEven) {
      c.drawRect(Rect.fromLTWH(r.left + 6, r.bottom - 9, 8, 3), fl(BP.inkDim));
    }
  }

  void hopperLive() {
    // Gate flaps under the body.
    for (final sg in [-1.0, 1.0]) {
      final hinge = Offset(FG.sx(0) + sg * 28, FG.hopperBody.bottom);
      final a = gate * 1.2;
      final tip = hinge + Offset(-sg * 26 * math.cos(a), 26 * math.sin(a));
      c.drawLine(hinge, tip, st(BP.line, 1.8));
    }
    lamp(const Offset(88, 594), BP.amber, work[0] >= 0 && (t * 6).floor().isEven, 2.4);
    lamp(const Offset(116, 594), BP.green, gate > 0.05 || j != null, 2.4);
    // The capsule bringing the name, and the ticket dropping in.
    final jj = j;
    if (jj == null) return;
    final ls = s;
    if (ls >= 0 && ls < FL.landed) {
      final a = ei(ls / (FL.landed - 0.12));
      final tan = _tubeMetric.getTangentForOffset(_tubeMetric.length * c01(a));
      if (tan != null && a < 1) {
        c.save();
        c.translate(tan.position.dx, tan.position.dy);
        c.rotate(-tan.angle);
        final cap = RRect.fromRectAndRadius(const Rect.fromLTWH(-7, -3, 14, 6), const Radius.circular(3));
        c.drawRRect(cap, fl(BP.amber));
        c.restore();
      }
      // Ticket fluttering from the nozzle into the funnel.
      final b = seg(ls, FL.landed - 0.2, FL.landed);
      if (b > 0 && b < 1) {
        c.save();
        c.translate(_tubeX + 4 * math.sin(b * 9), 526 + 12 * b);
        c.rotate(0.3 * math.sin(b * 11));
        final card = Rect.fromCenter(center: Offset.zero, width: 16, height: 10);
        c.drawRect(card, fl(BP.ink));
        c.drawLine(Offset(card.left + 3, 0), Offset(card.right - 3, 0), st(BP.panel, 1.2));
        c.restore();
      }
    }
    if (ls >= FL.landed && ls < FL.landed + 0.5) {
      puff(const Offset(_tubeX, 528), (ls - FL.landed) / 0.5, 3, 16, BP.amber);
    }
  }

  // ── The line ─────────────────────────────────────────────────────────────

  void lineSlats() {
    // With nothing on it, the line still indexes now and then.
    if (crates.isEmpty) lineMove = eio(seg(t % 4.5, 0, 0.9));
    final shift = (FG.pitch * lineMove) % 16;
    final p = Path();
    for (var x = FG.lineL + 6 + shift; x < FG.lineR - 2; x += 16) {
      p
        ..moveTo(x, FG.lineY + 1)
        ..lineTo(x - 4, FG.lineY + 7);
    }
    c.drawPath(p, st(BP.lineFaint, 1));
  }

  void lineCrate(_Crate cr) {
    final r = Rect.fromLTWH(cr.x - cr.w / 2, cr.y - cr.h, cr.w, cr.h);
    c.save();
    // Into the kiln through its mouth: hidden behind its wall.
    c.clipRect(const Rect.fromLTRB(FG.left, 380, 391, FG.floor));
    if (cr.alpha < 1) dim = cr.alpha;
    final g = cr.glyph;
    final dd = cr.data;
    final Color col;
    if (cr.stage >= 1) {
      col = g != null ? g.script.color : (dd.runs.isEmpty ? BP.line : dd.runs.first.script.color);
    } else {
      col = BP.inkDim;
    }
    c.drawRect(r, fl(BP.panel));
    c.drawRect(r, st(col, cr.stage >= 1 ? 1.6 : 1.2));
    final strip = r.top + 6;
    c.drawLine(Offset(r.left, strip), Offset(r.right, strip), st(col.withValues(alpha: 0.5), 0.8));
    final body = Rect.fromLTRB(r.left + 3, strip + 1, r.right - 3, r.bottom - 2);
    if (cr.stage < 2) {
      if (g == null) {
        // The raw string: one tick per code point, coloured once itemized.
        final n = dd.cps.length;
        final wTick = body.width / math.max(1, n);
        for (var k = 0; k < n; k++) {
          final gi = dd.graphemeOfCp(k);
          final tc = cr.stage >= 1 ? dd.graphemes[gi].script.color : BP.inkDim;
          final x = body.left + wTick * (k + 0.5);
          c.drawLine(Offset(x, body.top + 2), Offset(x, body.bottom - 1), st(tc, math.min(2.2, wTick * 0.6)));
        }
      } else {
        final b = body.deflate(3);
        c.drawLine(b.topLeft, b.bottomRight, st(BP.lineFaint, 1));
        c.drawLine(b.bottomLeft, b.topRight, st(BP.lineFaint, 1));
      }
    } else {
      final ink = cr.stage >= 3 ? BP.ink : BP.inkDim;
      final text = g?.text ?? dd.name;
      paintFit(tx.get(text, FS.name(16, ink), key: cr.stage >= 3 ? 'cr1' : 'cr0'), body, fitHeight: true);
      if (cr.stage >= 3) {
        c.drawLine(Offset(body.left + 2, r.bottom - 2), Offset(body.right - 2, r.bottom - 2), st(BP.amber.withValues(alpha: 0.8), 1));
      }
    }
    // The font tag clipped on after the fonts machine.
    if (cr.stage >= 2) {
      final tag = Rect.fromLTWH(r.right - 7, r.top - 3, 7, 5);
      c.drawRect(tag, fl(col));
    }
    dim = 1;
    c.restore();
  }

  void sorterLive() {
    const x = 182.0;
    final w = work[1];
    final cr = workOn[1];
    var gy = 592.0;
    if (w >= 0 && cr != null) {
      final down = eio(seg(w, 0, 0.2));
      final up = eio(seg(w, 0.55, 0.85));
      gy = lerp(592, cr.y - cr.h - 1, down * (1 - up));
    }
    c.drawLine(Offset(x, 590), Offset(x, gy - 3), st(BP.line, 2));
    c.drawLine(Offset(x - 10, gy - 3), Offset(x + 10, gy - 3), st(BP.line, 1.6));
    c.drawLine(Offset(x - 10, gy - 3), Offset(x - 11, gy + 2), st(BP.line, 1.4));
    c.drawLine(Offset(x + 10, gy - 3), Offset(x + 11, gy + 2), st(BP.line, 1.4));
    // Display: the runs, in their scripts' colours.
    final dd = d;
    final scr = _sortScreen.deflate(3);
    final lit = <Script>{};
    if (dd != null && (w >= 0 || step == 1)) {
      if (cr != null && !cr.lesson) {
        final g = cr.glyph!;
        lit.add(g.script);
        c.drawRect(scr, fl(g.script.color.withValues(alpha: 0.18)));
        paintFit(tx.get(g.script.label, BT.mono(10, color: g.script.color, weight: 600), key: 'sl'), scr, fitHeight: true);
      } else {
        final total = dd.graphemes.length;
        var x0 = scr.left;
        for (final r in dd.runs) {
          final n = dd.graphemes.where((g) => g.start >= r.start && g.start < r.end).length;
          final ww = scr.width * n / math.max(1, total);
          final rr = Rect.fromLTWH(x0, scr.top, ww, scr.height);
          c.drawRect(rr.deflate(0.6), fl(r.script.color.withValues(alpha: 0.22)));
          c.drawRect(rr.deflate(0.6), st(r.script.color, 1));
          lit.add(r.script);
          x0 += ww;
        }
      }
    } else {
      // Idle: a scan bar sweeps the display.
      final x0 = scr.left + (scr.width - 6) * (0.5 + 0.5 * math.sin(t * 1.4));
      c.drawRect(Rect.fromLTWH(x0, scr.top, 6, scr.height), fl(BP.line.withValues(alpha: 0.12)));
    }
    const lampScripts = [Script.latin, Script.kana, Script.han];
    for (var i = 0; i < 4; i++) {
      final on = i < 3 ? lit.contains(lampScripts[i]) : lit.any((s) => !lampScripts.contains(s));
      final col = i < 3 ? lampScripts[i].color : BP.violet;
      lamp(Offset(161 + 14.0 * i, 577), col, on || (lit.isEmpty && rnd((t * 1.5).floor(), i, 3) > 0.8), 3.6);
    }
  }

  void fontsLive() {
    final w = work[2];
    final cr = workOn[2];
    final dd = d;
    final hot = <int>{};
    final names = <String>[];
    if (dd != null && cr != null && w >= 0) {
      if (cr.lesson) {
        for (final f in dd.fonts) {
          hot.add(fontCell(f.script));
          names.add(f.font);
        }
      } else {
        hot.add(fontCell(cr.glyph!.script));
        names.add(fontOf(cr.glyph!.script));
      }
    } else if (dd != null && step == 2) {
      for (final f in dd.fonts) {
        hot.add(fontCell(f.script));
        names.add(f.font);
      }
    }
    final pulse = w >= 0 ? 0.75 + 0.25 * math.sin(t * 14) : 1.0;
    for (final i in hot) {
      final r = _fontCellRect(i).deflate(1);
      c.drawRect(r, fl(BP.amber.withValues(alpha: 0.2)));
      c.drawRect(r, st(BP.amber.withValues(alpha: pulse), 1.6));
    }
    if (hot.isEmpty) {
      // Idle: a light walks the cartridges.
      final i = (t * 0.8).floor() % 4;
      c.drawRect(_fontCellRect(i).deflate(1.5), st(BP.lineDim, 1.2));
    } else {
      // Several fonts take turns on the strip.
      final name = _fontShort(names[(t / 1.2).floor() % names.length]);
      paintFit(tx.get(name, BT.sample(9, color: BP.amber, weight: 600), key: 'fs'), _fontStrip.deflate(1.5), fitHeight: true);
    }
    lamp(const Offset(237, 584), BP.amber, w >= 0 && w < 0.5, 2.6);
    lamp(const Offset(247, 584), BP.green, hot.isNotEmpty, 2.6);
    // A cartridge card drops from the chute into the crate.
    if (cr != null && w >= 0) {
      final a = seg(w, 0.1, 0.4);
      if (a > 0 && a < 1) {
        final y = lerp(586, cr.y - cr.h + 4, ei(a));
        final card = Rect.fromCenter(center: Offset(264, y), width: 10, height: 7);
        c.drawRect(card, fl(BP.amber));
      }
    }
  }

  void pressLive() {
    const x = 342.0;
    final w = work[3];
    final cr = workOn[3];
    var y = 586.0;
    var impact = -1.0;
    if (w >= 0 && cr != null) {
      final down = ei(seg(w, 0, 0.2));
      final up = eio(seg(w, 0.4, 0.85));
      y = lerp(586, cr.y - cr.h, down * (1 - up));
      impact = seg(w, 0.2, 0.75);
    }
    c.drawLine(Offset(x, 552), Offset(x, y - 14), st(BP.line, 4));
    final ram = Rect.fromLTRB(x - 15, y - 14, x + 15, y);
    box(ram, w: 1.4);
    c.drawLine(Offset(ram.left + 3, y - 5), Offset(ram.right - 3, y - 5), st(BP.lineDim, 1));
    if (impact > 0 && impact < 1 && cr != null) {
      for (final sg in [-1.0, 1.0]) {
        for (var i = 0; i < 2; i++) {
          puff(Offset(x + sg * (cr.w / 2 + 5 + impact * (6 + 5 * i)), FG.lineY - 6 - i * 5 - impact * 6), c01(impact + i * 0.1), 2, 5 + 2.0 * i);
        }
      }
      sparks(Offset(x, cr.y - cr.h), impact, (t / 2).floor());
    }
    // Flywheel and pressure gauge.
    final a = t * (2.4 + (w >= 0 ? 5 : 0));
    final sp = Path();
    for (var i = 0; i < 3; i++) {
      final dd = Offset(math.cos(a + i * 2.094), math.sin(a + i * 2.094)) * 7.5;
      sp
        ..moveTo(_flywheel.dx, _flywheel.dy)
        ..lineTo(_flywheel.dx + dd.dx, _flywheel.dy + dd.dy);
    }
    c.drawPath(sp, st(BP.line, 1.2));
    final pr = w >= 0 ? 1 - seg(w, 0.18, 0.9) : 0.35 + 0.08 * math.sin(t * 0.9);
    _needle(_pressGauge, 6, pr);
  }

  void _needle(Offset o, double r, double v) {
    final a = math.pi * (0.8 + 1.4 * c01(v));
    c.drawLine(o, o + Offset(math.cos(a), math.sin(a)) * r, st(BP.amber, 1.3));
    c.drawCircle(o, 1.3, fl(BP.amber));
  }

  // ── The kiln ─────────────────────────────────────────────────────────────

  /// Bricks already gone out of the kiln (on pallets) and how hot the rest is.
  int get _shipped {
    final jj = j, deps = d?.departs;
    if (jj == null || deps == null) return 0;
    final tc = cutAt ?? t;
    var n = 0;
    for (var i = 0; i < deps.length; i++) {
      if (deps[i] > tc) break;
      n = math.min(jj.total, (i + 1) * palletSize);
    }
    return n;
  }

  double get heat {
    final jj = j;
    if (jj == null) return 0.3;
    switch (jj.phase) {
      case Phase.intake:
        return 0.35 + 0.65 * seg(s, 0.5, FL.arrive(4));
      case Phase.build:
        return 1;
      case Phase.reveal || Phase.celebrate:
        return 1 - 0.6 * seg(jj.since(t), 0, 6);
      case Phase.demolish || Phase.cleanup:
        return 0.35;
    }
  }

  void kilnInside() {
    final win = FG.kilnWin;
    final h = heat;
    final flick = 0.5 + 0.5 * math.sin(t * 7.3) * math.sin(t * 2.9 + 1);
    c.drawRect(win, fl(_glass));
    c.drawRect(win, fl(BP.coral.withValues(alpha: 0.05 + 0.08 * h + 0.03 * flick)));
    // Heating coil across the top.
    final coil = Path()..moveTo(win.left + 4, win.top + 5);
    for (var i = 1; i <= 12; i++) {
      coil.lineTo(win.left + 4 + i * (win.width - 8) / 12, win.top + (i.isEven ? 5 : 9));
    }
    c.drawPath(coil, st(BP.coral.withValues(alpha: 0.3 + 0.3 * flick * h + 0.3 * h), 1.2));
    // The name's pixels baking.
    final dots = d?.dots;
    final jj = j;
    if (dots != null && jj != null && jj.phase != Phase.demolish && jj.phase != Phase.cleanup) {
      final area = Rect.fromLTRB(win.left + 4, win.top + 12, win.right - 4, win.bottom - 4);
      final k = math.min(area.width / dots.cols, area.height / dots.rows);
      final o = Offset(area.center.dx - dots.cols * k / 2, area.center.dy - dots.rows * k / 2);
      final shipped = _shipped;
      final reveal = jj.phase == Phase.intake ? seg(s, 0.4, FL.arrive(4) + 0.3) : 1.0;
      c.save();
      c.translate(o.dx, o.dy);
      c.scale(k);
      final p = Paint()
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.square;
      for (var l = 0; l < RasterDots.levels; l++) {
        final xy = dots.xy[l];
        final cut = dots.before(l, shipped);
        final cover = RasterDots.coverOf(l);
        // Shipped: cooled down.
        if (cut > 0) {
          p.color = Color.lerp(BP.panel, BP.inkDim, cover)!;
          c.drawRawPoints(ui.PointMode.points, Float32List.sublistView(xy, 0, cut * 2), p);
        }
        // Still in the kiln: glowing.
        if (cut < xy.length ~/ 2) {
          final g = (0.35 + 0.65 * h) * reveal * (0.85 + 0.15 * flick);
          p.color = Color.lerp(BP.panel, Color.lerp(BP.coral, BP.amber, cover)!, cover * g)!;
          c.drawRawPoints(ui.PointMode.points, Float32List.sublistView(xy, cut * 2), p);
        }
      }
      c.restore();
      // Scan line developing the raster during intake.
      if (jj.phase == Phase.intake && reveal > 0 && reveal < 1) {
        final y = area.bottom - (area.height) * reveal;
        c.drawLine(Offset(area.left, y), Offset(area.right, y), st(BP.amber, 1));
      }
    }
  }

  void kilnLive() {
    final h = heat;
    final flick = 0.5 + 0.5 * math.sin(t * 7.3) * math.sin(t * 2.9 + 1);
    // Firebox glow, flaring every few seconds.
    final last = ((t / 2.6 - 0.3).floor() + 0.3) * 2.6;
    final flare = math.exp(-(t - last) * 1.6);
    c.drawRect(_firebox.deflate(7), fl(BP.amber.withValues(alpha: 0.12 + 0.25 * flare * h + 0.1 * flick)));
    final flames = Path();
    for (var i = 0; i < 4; i++) {
      final x = _firebox.left + 11 + i * 7.5;
      final hh = 5 + 6 * h * (0.5 + 0.5 * math.sin(t * 9 + i * 1.7));
      flames
        ..moveTo(x - 2.5, _firebox.bottom - 8)
        ..quadraticBezierTo(x, _firebox.bottom - 8 - hh * 1.4, x + 2.5, _firebox.bottom - 8);
    }
    c.drawPath(flames, st(BP.coral.withValues(alpha: 0.5 + 0.4 * h), 1.1));
    _needle(_kilnGauge, 6.5, 0.3 + 0.55 * h + 0.05 * math.sin(t * 1.7));
    const cols = [BP.green, BP.amber, BP.red];
    for (var i = 0; i < 3; i++) {
      final on = i == 0 ? j != null : (i == 1 ? work[4] >= 0 || rnd((t * 2.2).floor(), i, 5) > 0.5 : h > 0.9 && (t * 2).floor() % 4 == 0);
      lamp(Offset(428 + 12.0 * i, 603), cols[i], on, 3.6);
    }
    // Mouth flaps swing as crates go in / pallets come out.
    final inSwing = work[4] >= 0 && work[4] < 0.5 ? bump(work[4] * 2) : 0.0;
    var outSwing = 0.0;
    final deps = d?.departs;
    if (deps != null) {
      for (final dep in deps) {
        if (dep > t + 1) break;
        if (cutAt != null && dep > cutAt!) break;
        outSwing = math.max(outSwing, bump(seg(t, dep - 0.5, dep + 0.35)));
      }
    }
    for (final (hinge, sw, dir, len) in [(const Offset(392, 598), inSwing, 1.0, 28.0), (const Offset(468, 660), outSwing, 1.0, 22.0)]) {
      final a = sw * 0.9;
      c.drawLine(hinge, hinge + Offset(dir * math.sin(a) * len, math.cos(a) * len), st(BP.line, 1.8));
    }
    // Steam from the flue.
    // A plume drifting off with the wind, over the roof.
    const per = 0.42, life = 2.8;
    for (var n = ((t - life) / per).floor(); n <= (t / per).floor(); n++) {
      final a = (t - n * per) / life;
      if (a <= 0 || a >= 1) continue;
      final o = Offset(FG.flueX + 66 * a + 2 * math.sin(a * 7 + n), 389 - 7 * eo(a) + 1.5 * math.sin(n * 1.3));
      puff(o, a, 2.5, 6 + 4 * h + 3 * rnd(n, 9), BP.inkDim);
    }
    if (work[4] >= 0) {
      puff(const Offset(FG.flueX + 4, 388), work[4], 3, 9, BP.amber);
    }
  }

  // ── Pallets on the exit belt ─────────────────────────────────────────────

  void pallets() {
    final jj = j;
    if (jj != null) _palletsOf(jj, cutAt);
    // A name cut short just before this one: its pallets fade where they are.
    final old = sys.cut;
    if (old != null && old != jj && t < sys.cutAt + 0.6) _palletsOf(old, sys.cutAt);
  }

  void _palletsOf(Job jj, double? tc) {
    final r = jj.raster;
    final bs = jj.buildStart;
    if (r == null || bs == null || jj.total == 0) return;
    final tv = tc == null ? t : math.min(t, tc);
    final fade = tc == null ? 1.0 : 1 - seg(t, tc, tc + 0.6);
    if (fade <= 0) return;
    final w = palletWidth(jj);
    var i = math.max(0, ((tv + craneLead - bs) * jj.total / (palletSize * jj.buildLen)).floor() - 1);
    while (i < jj.pallets && jj.palletAtPickup(i)! <= tv) {
      i++;
    }
    c.save();
    // Out of the kiln's door, never past the pickup.
    c.clipRect(const Rect.fromLTRB(FBelt.x0 - 2, 600, BL.beltEnd, FG.floor));
    final deps = sc.data(jj)?.departs;
    for (; i < jj.pallets; i++) {
      final dep = deps != null && i < deps.length ? deps[i] : FBelt.depart(jj, i);
      if (dep - 0.8 > tv) break;
      final x = FBelt.x(jj, i, tv);
      if (tc != null && dep > tc) break;
      paintPallet(c, r, i, Offset(x, BL.beltY), width: w, opacity: fade);
    }
    c.restore();
  }

  void exitRollers() {
    final pos = sys.belt(t);
    const r = 2.6;
    final a = pos / r;
    final dv = Offset(math.cos(a), math.sin(a)) * r;
    final p = Path();
    for (var x = BL.beltStart + 8; x < BL.beltEnd - 4; x += 13) {
      const y = BL.beltY + 4;
      p
        ..addOval(Rect.fromCircle(center: Offset(x, y), radius: r))
        ..moveTo(x - dv.dx, y - dv.dy)
        ..lineTo(x + dv.dx, y + dv.dy);
    }
    c.drawPath(p, st(BP.lineDim, 1));
  }

  void curtain() {
    // Strip curtain in the door: pallets push through it.
    final jj = j, deps = d?.departs;
    var push = 0.0;
    if (jj != null && deps != null && (cutAt == null || t < cutAt! + 0.6)) {
      final tv = cutAt ?? t;
      for (var i = 0; i < deps.length; i++) {
        if (deps[i] > tv) break;
        if (jj.palletAtPickup(i)! <= tv) continue;
        final x = FBelt.x(jj, i, tv);
        push = math.max(push, bump(c01((x - (FG.right - 26)) / 34)));
      }
    }
    for (var k = 0; k < 4; k++) {
      final x = FG.right - 9 + k * 2.5;
      final a = push * (0.9 - k * 0.12) + 0.03 * math.sin(t * 2 + k);
      final top = Offset(x, FG.doorTop + 3);
      c.drawLine(top, top + Offset(math.sin(a) * 28, math.cos(a) * 28), st(BP.inkDim.withValues(alpha: 0.7), 1.4));
    }
  }

  /// The wall clock keeps scene time (from 10:08 when the booth opens).
  void clockHands() {
    final secs = 10 * 3600 + 8 * 60 + 30 + t;
    final tick = secs.floor() + eo(c01((secs - secs.floor()) * 6));
    for (final (turns, len, w, col) in [
      (secs / 43200, 5.0, 1.8, BP.ink),
      (secs / 3600, 7.5, 1.4, BP.ink),
      (tick / 60, 8.5, 0.9, BP.amber),
    ]) {
      final a = 2 * math.pi * turns - math.pi / 2;
      c.drawLine(_clock, _clock + Offset(math.cos(a), math.sin(a)) * len, st(col, w));
    }
    c.drawCircle(_clock, 1.4, fl(BP.amber));
  }

  // ── Roof ─────────────────────────────────────────────────────────────────

  void roofLive() {
    // Chasing bulbs around the sign.
    final p = tx.get('グリフ工場 · Glyph Works', FS.sign, key: 'sign');
    final r = Rect.fromCenter(center: const Offset(306, 392), width: p.width + 28, height: 21);
    final n = ((r.width - 8) / 12).floor();
    final chase = (t * 6).floor();
    final celebrating = j?.phase == Phase.celebrate;
    for (var i = 0; i <= n; i++) {
      final x = r.left + 4 + i * (r.width - 8) / n;
      for (final (y, off) in [(r.top + 0.5, 0), (r.bottom - 0.5, 1)]) {
        final on = celebrating ? (chase + i + off).isEven : (chase - i + off * 2) % 4 == 0;
        c.drawCircle(Offset(x, y), 1.4, fl(on ? BP.amber : BP.lineFaint));
      }
    }
  }

  // ── Plates ───────────────────────────────────────────────────────────────

  void platesLive() {
    if (step < 0) return;
    final r = _plates(tx)[step];
    box(r, col: BP.amber, w: 1.6, fill: Color.alphaBlend(BP.amber.withValues(alpha: 0.14), BP.panel));
    final p = tx.get(FG.machineNames[step], FS.plateHot, key: 'plateHot');
    p.paint(c, Offset(r.center.dx - p.width / 2, r.center.dy - p.height / 2));
    // A pointer from the screen down to the plate (for those under it).
    final x = r.center.dx;
    if (x > FG.screen.left + 8 && x < FG.screen.right - 8) {
      final tri = Path()
        ..moveTo(x - 6, FG.screen.bottom)
        ..lineTo(x + 6, FG.screen.bottom)
        ..lineTo(x, FG.screen.bottom + 4)
        ..close();
      c.drawPath(tri, fl(BP.amber));
    }
  }
}
