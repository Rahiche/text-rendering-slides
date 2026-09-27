import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../deck/scripts.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart' show dashPath;
import '../world.dart';
import 'factory_kit.dart';

/// The five section dividers: halls on the factory tour. Each one hangs a
/// hall sign (number, title, Japanese subtitle) over its own scene, and the
/// tour group (green-helmet guide with a flag, three blue-helmet visitors)
/// moves through them in order:
///
/// 01 The line — walks in to watch the basic production line.
/// 02 Imports — on the visitors' gallery over a dock drowning in containers
///    stamped with scripts; the crane and forklifts can't keep up.
/// 03 Other factories — at the windows: four plants across the road.
/// 04 Our specs — Flutter's spec sheet: red ✕ tags on missing machines,
///    green ✓ tags on what only Flutter has.
/// 05 Follow one crate — the group follows a single crate down the line.
///
/// Click machines / windows / tags to poke them; hover a figure to wave.
class FactoryHall extends StatelessWidget {
  const FactoryHall({super.key, required this.info});

  final SectionInfo info;

  @override
  Widget build(BuildContext context) =>
      FactoryScene(painter: (clock, text, io) => _HallPainter(clock, text, io, info));
}

const hallNames = ['the line', 'imports', 'other factories', 'our specs', 'follow one crate'];

const _subtitles = [
  '「コードポイントからピクセルへ」',
  '「文字体系ごとに増えるルール」',
  '「他のエンジンはどうしている？」',
  '「Flutterのトレードオフ」',
  '「ひとつの単語の旅」',
];

const _floor = 790.0;

class _HallPainter extends CustomPainter {
  _HallPainter(this.clock, this.text, this.io, this.info) : super(repaint: clock);

  final SceneClock clock;
  final TextCache text;
  final SceneInput io;
  final SectionInfo info;

  @override
  void paint(Canvas canvas, Size size) {
    io.targets.clear();
    final h = _Hall(canvas, clock.local, text, io, info);
    switch (info.index) {
      case 0:
        h.line();
      case 1:
        h.imports();
      case 2:
        h.others();
      case 3:
        h.specs();
      default:
        h.followCrate();
    }
    h.sign();
  }

  @override
  bool shouldRepaint(_HallPainter old) => old.info.index != info.index;
}

String _hex(int cp) => 'U+${cp.toRadixString(16).toUpperCase().padLeft(4, '0')}';

String _hexOf(String g) {
  final r = g.runes.toList();
  return r.length == 1 ? _hex(r.first) : '${_hex(r.first)} +${r.length - 1}';
}

class _Hall extends FactoryInk {
  _Hall(super.c, this.t, this.txt, this.io, this.info);

  final double t;
  final TextCache txt;
  final SceneInput io;
  final SectionInfo info;

  double boost(int target, [double dur = 1.2]) => io.boost(target, t, dur);

  bool hovered(Offset feet, double h) {
    final p = io.mouse;
    return p != null && (p - feet.translate(0, -h * 0.55)).distance < h * 0.7;
  }

  /// A crew member who waves when the mouse is over them.
  Limbs guy(Offset feet, double h, int dir, Pose f, {Color hat = BP.amber}) {
    if (hovered(feet, h)) f.wave(t);
    return worker(feet, h, dir, f, hat: hat);
  }

  TextPainter mono(String s, double size, [Color col = BP.inkDim, double weight = 400]) =>
      txt.get(s, BT.mono(size, color: col, weight: weight));

  TextPainter sample(String s, double size, [Color col = BP.ink, Locale? locale]) =>
      txt.get(s, BT.sample(size, color: col).copyWith(locale: locale));

  void plate(String label, Offset center, {Color col = BP.line}) {
    final tp = mono(label, 13, col);
    final r = Rect.fromCenter(center: center, width: tp.width + 16, height: 21);
    box(r, col: BP.lineDim, w: 1);
    tp.paint(c, Offset(r.left + 8, r.top + (r.height - tp.height) / 2));
  }

  // ── The hall sign ──────────────────────────────────────────────────────────

  void sign() {
    rail(40, 1560, 34, hangers: const [150, 600, 1050, 1450]);
    final number = txt.get(
      info.number,
      BT.display(186, weight: 700, height: 1).copyWith(
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = BP.line,
      ),
      key: ('hall-number', info.number),
    );
    final title = txt.get(info.title, BT.display(62, letterSpacing: -1.2, height: 1.05));
    final kicker = mono('hall ${info.number} · ${hallNames[info.index]}', 16, BP.amber);
    final sub = sample(_subtitles[info.index], 26, BP.inkDim, jaLocale);
    final tw = math.max(title.width, math.max(sub.width, kicker.width));
    final w = 40 + number.width + 44 + tw + 56;
    const hgt = 236.0;
    // Drops in on its cables, bounces once, then hangs still.
    final drop = eo(seg(t, 0, 0.75));
    final settle = t > 0.75 ? 7 * math.exp(-(t - 0.75) * 5) * math.sin((t - 0.75) * 15) : 0.0;
    final dy = lerp(-330, 0, drop) + settle;
    final r = Rect.fromLTWH(96, 82 + dy, w, hgt);
    for (final x in [r.left + 60, r.right - 60]) {
      c.drawLine(Offset(x, 50), Offset(x, r.top), st(BP.inkDim, 1.2));
      c.drawCircle(Offset(x, r.top - 3), 3, st(BP.line, 1.2));
    }
    c.drawRect(r, fl(BP.panel));
    c.drawRect(r, st(BP.line, 1.6));
    c.drawRect(r.deflate(7), st(BP.lineDim, 1));
    for (final p in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      final q = Offset(p.dx + (p.dx < r.center.dx ? 14 : -14), p.dy + (p.dy < r.center.dy ? 14 : -14));
      c.drawCircle(q, 2.4, st(BP.lineDim, 1.2));
    }
    // Number draws on from the left, the words wipe in after it.
    final nx = r.left + 40, ny = r.center.dy - number.height / 2 + 6;
    c.save();
    c.clipRect(Rect.fromLTWH(nx - 4, r.top, (number.width + 8) * eo(seg(t, 0.25, 1.0)), hgt));
    number.paint(c, Offset(nx, ny));
    c.restore();
    final tx = nx + number.width + 44;
    c.drawLine(Offset(tx - 22, r.top + 36), Offset(tx - 22, r.bottom - 36), st(BP.lineDim, 1));
    final ty = r.top + 34;
    c.save();
    c.clipRect(Rect.fromLTWH(tx, r.top, (tw + 10) * eo(seg(t, 0.45, 1.3)), hgt));
    kicker.paint(c, Offset(tx, ty));
    title.paint(c, Offset(tx, ty + kicker.height + 8));
    sub.paint(c, Offset(tx + 2, ty + kicker.height + 8 + title.height + 14));
    c.restore();
    // A status lamp on the sign.
    lamp(Offset(r.right - 26, r.top + 26), BP.green, (t * 1.2) % 2 < 1.6, 4);
  }

  // ── 01 · The line ──────────────────────────────────────────────────────────

  static const _p1 = 1.6; // belt cycle
  static const _mv1 = 0.4; // fraction of it spent moving
  static const _beltTop = 690.0;
  static const _cw = 64.0, _ch = 46.0;

  double _slotX(double j) => 200 + 110 * j;

  void line() {
    final cyc = (t / _p1).floor();
    final ph = t / _p1 - cyc;
    final e = ph < _mv1 ? eio(ph / _mv1) : 1.0;
    final dwell = ph >= _mv1;
    double dw(double a, double b) => seg(ph, _mv1 + a * (1 - _mv1), _mv1 + b * (1 - _mv1));
    final glyphs = info.glyphs;

    floor(24, 1576, _floor);
    // Targets: hopper, press, oven.
    io.targets.addAll(const [
      Rect.fromLTRB(130, 440, 270, 640),
      Rect.fromLTRB(560, 470, 720, 690),
      Rect.fromLTRB(880, 480, 1060, 710),
    ]);

    // Hopper with a scrolling roll of code points.
    final funnel = Path()
      ..moveTo(130, 470)
      ..lineTo(270, 470)
      ..lineTo(228, 552)
      ..lineTo(172, 552)
      ..close();
    c.drawPath(funnel, fl(BP.panel));
    c.drawPath(funnel, st(BP.line, 1.4));
    box(const Rect.fromLTRB(172, 552, 228, 620));
    c.drawRect(const Rect.fromLTRB(148, 478, 252, 500), st(BP.lineDim, 1));
    final roll = mono(glyphs.map((g) => _hexOf(g)).join('  '), 10, BP.lineDim);
    final off = (t * (16 + 60 * boost(0))) % (roll.width + 20);
    c.save();
    c.clipRect(const Rect.fromLTRB(149, 479, 251, 499));
    for (var x = 150 - off; x < 252; x += roll.width + 20) {
      roll.paint(c, Offset(x, 489 - roll.height / 2));
    }
    c.restore();
    plate('unicode', const Offset(200, 452));
    lamp(const Offset(214, 580), BP.amber, dwell && dw(0, 0.4) < 1 || boost(0) > 0);
    if (boost(0) > 0) puff(const Offset(200, 460), seg(t, io.targetAt, io.targetAt + 1.2), 6, 30, BP.amber);
    // Platform + ladder for the hopper's stoker.
    box(const Rect.fromLTRB(70, 520, 136, 527), w: 1.1);
    for (final x in [78.0, 128.0]) {
      c.drawLine(Offset(x, 527), Offset(x, _floor), st(BP.lineDim, 1.1));
    }
    for (final x in [44.0, 62.0]) {
      c.drawLine(Offset(x, 520), Offset(x, _floor), st(BP.lineDim, 1.2));
    }
    for (var y = 536.0; y < _floor; y += 16) {
      c.drawLine(Offset(44, y), Offset(62, y), st(BP.lineDim, 1));
    }

    // Belt.
    conveyor(150, 1350, _beltTop, _floor, (cyc - 1 + e) * 110, legEvery: 170);

    // Press frame (behind the crates).
    box(const Rect.fromLTRB(566, 496, 714, 526));
    box(const Rect.fromLTRB(572, 526, 584, _beltTop), w: 1.1);
    box(const Rect.fromLTRB(696, 526, 708, _beltTop), w: 1.1);
    c.drawCircle(const Offset(704, 486), 16, fl(BP.panel));
    c.drawCircle(const Offset(704, 486), 16, st(BP.line, 1.3));
    final fa = t * (3.2 + 8 * boost(1));
    final spokes = Path();
    for (var i = 0; i < 3; i++) {
      final d = Offset(math.cos(fa + i * 2.094), math.sin(fa + i * 2.094)) * 14;
      spokes
        ..moveTo(704, 486)
        ..lineTo(704 + d.dx, 486 + d.dy);
    }
    c.drawPath(spokes, st(BP.line, 1.2));
    plate('shape', const Offset(640, 470));

    // Crates.
    for (var k = cyc - 11; k <= cyc; k++) {
      if (k < 0) continue;
      final g = glyphs[k % glyphs.length];
      double pos;
      var y = _beltTop - _ch;
      if (k == cyc) {
        if (!dwell) continue;
        pos = 0;
        y = lerp(560, _beltTop - _ch, ei(dw(0, 0.3))) - 3 * bump(dw(0.3, 0.45));
      } else {
        pos = cyc - k - 1 + e;
      }
      if (pos > 10.2) continue;
      final x = _slotX(pos);
      var yy = y;
      if (pos > 10) {
        // Tipped into the bin.
        final f = (pos - 10) / 0.2;
        yy += 40 * f * f;
      }
      final r = Rect.fromLTWH(x - _cw / 2, yy, _cw, _ch);
      final pressed = pos > 4.001 || (pos > 3.999 && dwell && dw(0, 0.22) >= 1);
      final baked = pos > 7.001 || (pos > 6.999 && dwell && dw(0, 0.65) >= 1);
      if (k == cyc) {
        c.save();
        c.clipRect(const Rect.fromLTRB(0, 620, 1600, 900));
        _lineCrate(r, g, pressed, baked);
        c.restore();
      } else {
        _lineCrate(r, g, pressed, baked);
      }
    }

    // Press ram.
    {
      var ram = 600.0;
      var impact = -1.0;
      final underPress = cyc >= 4;
      if (underPress && dwell) {
        final down = ei(dw(0, 0.18));
        final up = eio(dw(0.35, 0.8));
        ram = lerp(600, _beltTop - _ch, down * (1 - up));
        impact = dw(0.18, 0.7);
      }
      c.drawLine(Offset(640, 526), Offset(640, ram - 30), st(BP.line, 4));
      final rr = Rect.fromLTRB(612, ram - 30, 668, ram);
      box(rr, w: 1.4);
      c.drawLine(Offset(rr.left + 5, ram - 8), Offset(rr.right - 5, ram - 8), st(BP.lineDim, 1));
      if (impact > 0 && impact < 1) {
        for (final s in [-1.0, 1.0]) {
          for (var i = 0; i < 2; i++) {
            puff(Offset(640 + s * (36 + impact * (10 + 8 * i)), _beltTop - 6 - i * 6 - impact * 8), c01(impact + i * 0.1), 2, 6 + 2.5 * i);
          }
        }
      }
      if (boost(1) > 0) sparks(Offset(640, ram + 2), seg(t, io.targetAt, io.targetAt + 0.8), 7);
    }

    // Oven (in front of the belt), with a window onto it.
    {
      const body = Rect.fromLTRB(880, 516, 1060, 708);
      const win = Rect.fromLTRB(904, 610, 1036, 684);
      final shell = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(body)
        ..addRect(win);
      c.drawPath(shell, fl(BP.panel));
      c.drawRect(body, st(BP.line, 1.4));
      c.drawRect(win, st(BP.line, 1.2));
      final heat = 0.5 + 0.5 * math.sin(t * 7.3) * math.sin(t * 2.9 + 1);
      final coil = Path()..moveTo(win.left + 6, win.top + 6);
      for (var i = 1; i <= 14; i++) {
        coil.lineTo(win.left + 6 + i * 8.6, win.top + (i.isEven ? 6 : 11));
      }
      c.drawPath(coil, st(BP.coral.withValues(alpha: 0.5 + 0.3 * heat + 0.2 * boost(2)), 1.3));
      c.drawRect(const Rect.fromLTRB(1024, 470, 1044, 516), fl(BP.panel));
      c.drawRect(const Rect.fromLTRB(1024, 470, 1044, 516), st(BP.line, 1.3));
      steam(const Offset(1034, 464), t, per: 0.5 - 0.25 * boost(2), life: 2.4, rise: 42, r: 10 + 8 * boost(2), seed: 3);
      gauge(const Offset(918, 548), 14, 0.55 + 0.2 * math.sin(t * 0.8) + 0.25 * boost(2));
      for (var i = 0; i < 3; i++) {
        lamp(Offset(990.0 + i * 16, 544), [BP.green, BP.amber, BP.red][i], rnd((t * 2).floor(), i, 5) > 0.45 || boost(2) > 0);
      }
      plate('raster', const Offset(970, 500));
      // Firebox.
      box(const Rect.fromLTRB(1068, 742, 1108, _floor), w: 1.2);
      final last = ((t / 2.4 - 0.87).floor() + 0.87) * 2.4;
      c.drawRect(const Rect.fromLTRB(1076, 752, 1100, 770), fl(BP.amber.withValues(alpha: 0.15 + 0.4 * math.exp(-(t - last) * 1.8))));
    }

    // The bin at the end of the line.
    {
      box(const Rect.fromLTRB(1356, 712, 1452, 772), w: 1.3);
      for (final x in [1370.0, 1438.0]) {
        c.drawCircle(Offset(x, 781), 8, fl(BP.panel));
        c.drawCircle(Offset(x, 781), 8, st(BP.line, 1.2));
      }
      final n = math.max(0, cyc - 11).clamp(0, 6);
      for (var i = 0; i < math.min(n, 5); i++) {
        final r = Rect.fromLTWH(1362 + (i % 3) * 30.0, 740 - (i ~/ 3) * 20.0, 28, 22);
        c.drawRect(r, fl(BP.panel));
        c.drawRect(r, st(BP.line, 1));
        final img = txt.raster(glyphs[(cyc - 12 - i) % glyphs.length], BT.sample(9));
        pixels(img, r.deflate(3), grid: false);
      }
    }

    // Crew.
    _lineCrew(cyc, ph, dwell, dw);

    // The tour group walks in and stops to watch.
    final walkIn = eio(seg(t, 0.2, 6.0));
    final gx = lerp(-60, 470, walkIn);
    final walking = walkIn > 0 && walkIn < 1;
    final pointing = walking ? 0.0 : bump(seg((t - 6) % 7, 0.3, 3.2));
    tourGroup(gx, _floor, t, walk: walking ? gx / 5.5 : -1, pointing: pointing, mouse: io.mouse);
  }

  void _lineCrate(Rect r, String g, bool pressed, bool baked) {
    final col = baked ? BP.line : (pressed ? BP.ink : BP.inkDim);
    crate(r, col, stamp: mono(_hexOf(g), 9, baked ? BP.line : BP.inkDim));
    final body = Rect.fromLTRB(r.left + 3, r.top + 12, r.right - 3, r.bottom - 3);
    if (baked) {
      pixels(txt.raster(g, BT.sample(12)), body);
    } else if (pressed) {
      paintFit(sample(g, 26), body, fitHeight: true);
    } else {
      final b = body.deflate(4);
      c.drawLine(b.topLeft, b.bottomRight, st(BP.lineFaint, 1));
      c.drawLine(b.bottomLeft, b.topRight, st(BP.lineFaint, 1));
    }
  }

  void _lineCrew(int cyc, double ph, bool dwell, double Function(double, double) dw) {
    // Hopper stoker on the platform, shovelling code points in.
    {
      const per = 1.9;
      final n = (t / per).floor();
      final p = t / per - n;
      final f = Pose()
        ..thA = 0.08
        ..thB = -0.06;
      final sw = p < 0.45 ? 0.0 : (p < 0.62 ? eo((p - 0.45) / 0.17) : 1 - eio((p - 0.62) / 0.38));
      f
        ..lean = lerp(0.45, -0.05, sw)
        ..upA = lerp(0.55, 2.0, sw)
        ..foA = lerp(1.0, 2.45, sw)
        ..upB = lerp(0.25, 1.6, sw)
        ..foB = lerp(1.05, 2.4, sw);
      final g = guy(const Offset(100, 520), 30, 1, f);
      shovel(g.handB, g.handA, 10);
      final age = (t - (n + 0.58) * per) / 0.75;
      if (age >= 0 && age <= 1) {
        for (var i = 0; i < 3; i++) {
          final pt = Offset.lerp(const Offset(128, 488), Offset(170 + i * 14.0, 470), age)! + Offset(0, -40 * math.sin(age * math.pi) + i * 2);
          c.drawRect(Rect.fromCenter(center: pt, width: 6, height: 4.5), st(BP.amber, 1));
        }
      }
    }
    // Press operator pulls the lever for every stamp.
    {
      final pull = dwell ? eo(dw(0, 0.2)) * (1 - eio(dw(0.5, 0.85))) : 0.0;
      final f = Pose()
        ..upA = lerp(2.4, 1.25, pull)
        ..foA = lerp(2.75, 1.6, pull)
        ..lean = 0.12 * pull;
      final g = guy(const Offset(768, _floor), 34, -1, f);
      box(const Rect.fromLTRB(730, 752, 752, _floor), w: 1.1);
      final knob = hovered(const Offset(768, _floor), 34) ? const Offset(744, 736) : g.handA;
      c.drawLine(const Offset(741, 756), knob, st(BP.line, 1.6));
      c.drawCircle(knob, 2.6, fl(BP.amber));
    }
    // Oven stoker.
    {
      const per = 2.4;
      final n = (t / per).floor();
      final p = t / per - n;
      final toss = p >= 0.45;
      final f = Pose();
      if (!toss) {
        final sc = bump(seg(p, 0.05, 0.42));
        f
          ..lean = 0.2 + 0.45 * sc
          ..upA = 0.6
          ..foA = 0.9 + 0.3 * sc
          ..upB = 0.3
          ..foB = 0.95;
      } else {
        final sw = eo(seg(p, 0.45, 0.65)) * (1 - eio(seg(p, 0.75, 1)));
        f
          ..lean = 0.3 - 0.2 * sw
          ..upA = lerp(0.7, 1.5, sw)
          ..foA = lerp(0.9, 1.75, sw)
          ..upB = lerp(0.4, 1.2, sw)
          ..foB = lerp(1.0, 1.8, sw);
      }
      final g = guy(const Offset(1146, _floor), 34, toss ? -1 : 1, f);
      shovel(g.handB, g.handA, 11);
      final coal = Path()
        ..moveTo(1168, _floor)
        ..quadraticBezierTo(1182, 772, 1196, _floor);
      c.drawPath(coal, st(BP.lineDim, 1.2));
    }
    // Inspector at the bin with a magnifier; nods at each tile.
    {
      final f = Pose()
        ..upA = 1.35 + 0.1 * math.sin(t * 2)
        ..foA = 2.05
        ..head = 0.3;
      final g = guy(const Offset(1492, _floor), 34, -1, f);
      magnifier(g.handA, g.elbowA);
    }
  }

  // ── 02 · Imports ───────────────────────────────────────────────────────────

  static const _cntW = 128.0, _cntH = 52.0;

  List<(String, String, Color)> get _containers => [
    for (final g in info.glyphs) (g, scriptOfCluster(g).label, scriptOfCluster(g).color),
    ('かな', 'kana', Script.kana.color),
  ];

  void container(Rect r, (String, String, Color) k, {double tilt = 0}) {
    c.save();
    c.translate(r.center.dx, r.center.dy);
    c.rotate(tilt);
    final b = Rect.fromCenter(center: Offset.zero, width: r.width, height: r.height);
    c.drawRect(b, fl(BP.panel));
    final ribs = Path();
    for (var x = b.left + 8; x < b.right - 4; x += 8) {
      ribs
        ..moveTo(x, b.top + 4)
        ..lineTo(x, b.bottom - 4);
    }
    c.drawPath(ribs, st(BP.lineFaint, 1));
    c.drawRect(b, st(k.$3, 1.5));
    c.drawLine(Offset(b.right - 16, b.top + 4), Offset(b.right - 16, b.bottom - 4), st(k.$3.withValues(alpha: 0.6), 1));
    // Stamp: the script's glyph and its name.
    final g = sample(k.$1, 30, k.$3, k.$2 == 'han' || k.$2 == 'kana' ? jaLocale : null);
    final gb = Rect.fromLTWH(b.left + 6, b.top + 3, 64, b.height - 6);
    c.drawRect(gb, fl(BP.paper.withValues(alpha: 0.85)));
    c.drawRect(gb, st(k.$3.withValues(alpha: 0.7), 1));
    paintFit(g, gb.deflate(2), fitHeight: true);
    final l = mono(k.$2, 11, k.$3);
    paintFit(l, Rect.fromLTWH(gb.right + 2, b.bottom - 18, b.right - 18 - gb.right - 4, 14));
    c.restore();
  }

  void imports() {
    final list = _containers;
    floor(24, 1576, _floor);
    io.targets.addAll(const [Rect.fromLTRB(640, 380, 1560, 440), Rect.fromLTRB(1110, 690, 1300, 790)]);

    // Visitors' gallery on the left, the intake door under it.
    box(const Rect.fromLTRB(56, 648, 190, _floor), col: BP.lineDim, w: 1.2);
    for (var y = 656.0; y < 704; y += 8) {
      c.drawLine(Offset(60, y), Offset(186, y), st(BP.lineFaint, 1));
    }
    plate('intake', const Offset(123, 636));
    box(const Rect.fromLTRB(40, 604, 420, 612), w: 1.2);
    for (final x in [48.0, 210.0, 410.0]) {
      c.drawLine(Offset(x, 612), Offset(x, _floor), st(BP.lineDim, 1.1));
    }
    c.drawLine(const Offset(40, 572), const Offset(420, 572), st(BP.lineDim, 1.2));
    for (var x = 40.0; x <= 420; x += 38) {
      c.drawLine(Offset(x, 572), Offset(x, 604), st(BP.lineDim, 1));
    }
    // Stairs down.
    final stairs = Path()..moveTo(420, 608);
    for (var i = 0; i < 9; i++) {
      stairs
        ..lineTo(420 + (i + 1) * 9.0, 608 + i * 20.0)
        ..lineTo(420 + (i + 1) * 9.0, 608 + (i + 1) * 20.0);
    }
    c.drawPath(stairs, st(BP.lineDim, 1.1));

    // The crane.
    const beamY = 392.0, pickX = 1375.0, dropX = 900.0;
    for (final x in [668.0, 1528.0]) {
      c.drawLine(Offset(x - 16, _floor), Offset(x, beamY + 18), st(BP.line, 1.6));
      c.drawLine(Offset(x + 16, _floor), Offset(x, beamY + 18), st(BP.line, 1.6));
      for (var y = 470.0; y < _floor; y += 64) {
        final hw = 16 * (y - beamY - 18) / (_floor - beamY - 18);
        c.drawLine(Offset(x - hw, y), Offset(x + hw, y + 32), st(BP.lineDim, 1));
      }
    }
    box(const Rect.fromLTRB(640, beamY, 1560, beamY + 18), w: 1.4);
    for (var x = 660.0; x < 1550; x += 40) {
      c.drawLine(Offset(x, beamY + 2), Offset(x + 20, beamY + 16), st(BP.lineFaint, 1));
    }
    // Operator cab on the right leg.
    box(const Rect.fromLTRB(1480, beamY + 22, 1526, beamY + 62), w: 1.3);
    c.drawRect(const Rect.fromLTRB(1486, beamY + 28, 1520, beamY + 44), st(BP.lineDim, 1));
    final op = Pose()
      ..upA = 1.4
      ..foA = 1.7
      ..sit(22, 8);
    final opg = worker(const Offset(1504, beamY + 60), 22, -1, op);
    sweat(opg.head, t, -1);
    // Beacon.
    final beacon = (t * 3).floor().isEven;
    c.drawCircle(const Offset(1100, beamY - 6), 6, fl(beacon ? BP.red : BP.amber.withValues(alpha: 0.6)));
    c.drawCircle(const Offset(1100, beamY - 6), 6, st(BP.line, 1));
    if (beacon) c.drawCircle(const Offset(1100, beamY - 6), 14, st(BP.red.withValues(alpha: 0.4), 1));

    // Crane cycle: pick at the flatcar, swing over, drop on the pile.
    const per = 7.4;
    final cyc = (t / per).floor();
    final u = t - cyc * per;
    final kNow = list[(cyc + 1) % list.length];
    final kPrev = list[cyc % list.length];
    const up = 452.0;
    const carTop = 708.0, pileTop = _floor - 3 * _cntH;
    double x = pickX, hook = up;
    var carrying = false;
    var swing = 0.0;
    if (u < 0.9) {
      hook = lerp(up, carTop, eio(u / 0.9));
    } else if (u < 1.2) {
      hook = carTop;
      carrying = true;
    } else if (u < 2.0) {
      hook = lerp(carTop, up, eio((u - 1.2) / 0.8));
      carrying = true;
    } else if (u < 3.8) {
      final p = (u - 2.0) / 1.8;
      x = lerp(pickX, dropX, eio(p));
      carrying = true;
      swing = 0.12 * math.sin(p * math.pi * 2.2) * (1 - p * 0.5);
    } else if (u < 4.6) {
      x = dropX;
      hook = lerp(up, pileTop, eio((u - 3.8) / 0.8));
      carrying = true;
      swing = 0.05 * math.exp(-(u - 3.8) * 3) * math.sin((u - 3.8) * 9);
    } else if (u < 4.9) {
      x = dropX;
      hook = pileTop;
    } else if (u < 5.6) {
      x = dropX;
      hook = lerp(pileTop, up, eio((u - 4.9) / 0.7));
    } else {
      x = lerp(dropX, pickX, eio((u - 5.6) / 1.8));
    }
    // The pile (bottom rows fixed; the top slot holds the latest drop).
    final pile = [
      (Rect.fromLTWH(700, _floor - _cntH, _cntW, _cntH), 0),
      (Rect.fromLTWH(836, _floor - _cntH, _cntW, _cntH), 2),
      (Rect.fromLTWH(972, _floor - _cntH, _cntW, _cntH), 4),
      (Rect.fromLTWH(768, _floor - 2 * _cntH, _cntW, _cntH), 1),
      (Rect.fromLTWH(904, _floor - 2 * _cntH, _cntW, _cntH), 3),
    ];
    for (final (r, i) in pile) {
      container(r, list[i % list.length]);
    }
    final topSlot = Rect.fromLTWH(dropX - _cntW / 2, _floor - 3 * _cntH, _cntW, _cntH);
    container(topSlot, u >= 4.6 ? kNow : kPrev);
    // Overflow heap, askew.
    container(const Rect.fromLTWH(1112, _floor - _cntH, _cntW, _cntH), list[5 % list.length], tilt: 0.04);
    container(const Rect.fromLTWH(1118, _floor - 2 * _cntH - 2, _cntW, _cntH), list[6 % list.length], tilt: -0.07);
    // Flatcar with the next container; it runs off and brings another.
    var carX = 1300.0;
    var carLoaded = true;
    if (u >= 1.2 && u < 2.4) {
      carLoaded = false;
    } else if (u >= 2.4 && u < 6.6) {
      final p = (u - 2.4) / 4.2;
      carX = 1300 + 360 * (p < 0.5 ? eio(p * 2) : 1 - eio((p - 0.5) * 2));
      carLoaded = p >= 0.5;
    }
    c.drawLine(const Offset(1180, _floor - 4), const Offset(1600, _floor - 4), st(BP.lineDim, 1));
    box(Rect.fromLTRB(carX, _floor - 30, carX + 150, _floor - 20), w: 1.2);
    for (final wx in [carX + 22, carX + 128]) {
      c.drawCircle(Offset(wx, _floor - 10), 9, fl(BP.panel));
      c.drawCircle(Offset(wx, _floor - 10), 9, st(BP.line, 1.2));
    }
    if (carLoaded) container(Rect.fromLTWH(carX + 11, carTop, _cntW, _cntH), u >= 2.4 ? list[(cyc + 2) % list.length] : kNow);
    // A second car waits at the edge: the queue never ends.
    box(const Rect.fromLTRB(1540, _floor - 30, 1640, _floor - 20), w: 1.2);
    container(const Rect.fromLTWH(1548, carTop, _cntW, _cntH), list[(cyc + 3) % list.length]);

    // Trolley, cable, spreader, load.
    box(Rect.fromLTRB(x - 30, beamY + 18, x + 30, beamY + 34), w: 1.3);
    final sp = Offset(x + math.sin(swing) * (hook - beamY - 34), hook);
    c.drawLine(Offset(x - 10, beamY + 34), sp + const Offset(-10, -8), st(BP.inkDim, 1));
    c.drawLine(Offset(x + 10, beamY + 34), sp + const Offset(10, -8), st(BP.inkDim, 1));
    c.drawLine(sp + const Offset(-_cntW / 2, -4), sp + const Offset(_cntW / 2, -4), st(BP.amber, 3));
    if (carrying) {
      container(Rect.fromLTWH(sp.dx - _cntW / 2, hook, _cntW, _cntH), kNow, tilt: swing * 0.6);
    }

    // Forklift A shuttles crates from the pile to the intake.
    {
      const per = 9.0;
      final n = (t / per).floor();
      final q = t - n * per;
      double fx;
      var dir = 1;
      var lift = 4.0;
      var load = false;
      if (q < 3) {
        fx = lerp(250, 580, eio(q / 3));
      } else if (q < 4) {
        fx = 580;
        lift = lerp(4, 18, eio(q - 3));
        load = q > 3.3;
      } else if (q < 7.2) {
        fx = lerp(580, 250, eio((q - 4) / 3.2));
        dir = -1;
        lift = 18;
        load = true;
      } else {
        fx = 250;
        dir = -1;
        lift = lerp(18, 4, eio((q - 7.2) / 0.8));
        load = q < 7.8;
      }
      final roll = fx / 6;
      // Loose crates waiting by the pile.
      for (var i = 0; i < 3; i++) {
        final r = Rect.fromLTWH(624 + (i % 2) * 34.0, _floor - 26 - (i ~/ 2) * 26.0, 32, 26);
        c.drawRect(r, fl(BP.panel));
        c.drawRect(r, st(list[(n + i) % list.length].$3, 1.1));
        paintFit(sample(list[(n + i) % list.length].$1, 14, list[(n + i) % list.length].$3), r.deflate(3), fitHeight: true);
      }
      final tip = forklift(Offset(fx, _floor), dir, lift, roll);
      if (load) {
        final k = list[(n + 3) % list.length];
        final r = Rect.fromLTWH(tip.dx - 16, tip.dy - 26, 32, 26);
        c.drawRect(r, fl(BP.panel));
        c.drawRect(r, st(k.$3, 1.1));
        paintFit(sample(k.$1, 14, k.$3), r.deflate(3), fitHeight: true);
      }
    }
    // Forklift B: a whole container on its forks, tipping forward.
    {
      final strain = 0.09 + 0.03 * math.sin(t * 9) + 0.08 * boost(1);
      const pivot = Offset(1226, _floor);
      c.save();
      c.translate(pivot.dx, pivot.dy);
      c.rotate(strain);
      c.translate(-pivot.dx, -pivot.dy);
      final d = Pose()..sit(20, 6);
      d.overwhelmed(t);
      final tip = forklift(const Offset(1200, _floor), 1, 10, t * 14, driver: d);
      container(Rect.fromLTWH(tip.dx - 10, tip.dy - _cntH, _cntW, _cntH), list[2 % list.length]);
      c.restore();
      for (var i = 0; i < 3; i++) {
        final q = (t * 2.2 + i / 3) % 1;
        puff(Offset(1176 - q * 22, _floor - 4 - q * 10), q, 2, 7, BP.inkDim);
      }
      alarm(const Offset(1194, 744), t);
    }
    // Marshaller waving at the crane; a worker overwhelmed by the pile.
    {
      final w = math.sin(t * 5);
      final f = Pose()
        ..upA = 2.6 + 0.35 * w
        ..foA = 2.9 + 0.35 * w
        ..upB = 2.6 - 0.35 * w
        ..foB = 2.9 - 0.35 * w;
      final g = guy(const Offset(1560, _floor), 34, -1, f);
      c.drawLine(g.handA, g.handA + Offset(0, -8), st(BP.coral, 2.4));
      c.drawLine(g.handB, g.handB + Offset(0, -8), st(BP.coral, 2.4));
      final o = Pose()..overwhelmed(t);
      final og = guy(const Offset(606, _floor), 34, 1, o);
      alarm(og.head, t + 0.5);
      sweat(og.head, t, 1);
    }

    // The tour group on the gallery, looking up at the crane.
    final pointing = bump(seg(t % 6, 0.8, 3.6));
    tourGroup(330, 604, t, pointing: pointing, look: true, mouse: io.mouse);
  }

  // ── 03 · Other factories ───────────────────────────────────────────────────

  static const _wins = [
    Rect.fromLTRB(104, 386, 424, 656),
    Rect.fromLTRB(464, 386, 784, 656),
    Rect.fromLTRB(824, 386, 1144, 656),
    Rect.fromLTRB(1184, 386, 1504, 656),
  ];

  void others() {
    floor(24, 1576, _floor);
    io.targets.addAll(_wins);
    // Wall.
    c.drawLine(const Offset(40, 362), const Offset(1560, 362), st(BP.lineDim, 1.2));
    // The view through each window.
    for (var i = 0; i < 4; i++) {
      final w = _wins[i];
      c.save();
      c.clipRect(w);
      c.drawRect(w, fl(BP.bg));
      // Distant skyline.
      final sky = Path();
      for (var x = w.left; x < w.right; x += 36) {
        final hh = 20 + 30 * rnd(x.round(), 9);
        sky.addRect(Rect.fromLTWH(x, 560 - hh, 28, hh));
      }
      c.drawPath(sky, st(BP.lineFaint.withValues(alpha: 0.6), 1));
      // Road.
      c.drawLine(Offset(w.left, 604), Offset(w.right, 604), st(BP.lineDim, 1));
      c.drawLine(Offset(w.left, 640), Offset(w.right, 640), st(BP.lineDim, 1));
      c.drawPath(dashPath(Path()
        ..moveTo(w.left, 622)
        ..lineTo(w.right, 622), dash: 14, gap: 10), st(BP.lineFaint, 1.2));
      final b = boost(i);
      switch (i) {
        case 0:
          _chrome(w, b);
        case 1:
          _figma(w, b);
        case 2:
          _apple(w, b);
        default:
          _android(w, b);
      }
      // A truck drives by across all four windows.
      final tx = (t * 150) % 2400 - 300;
      final truck = Rect.fromLTWH(tx, 612, 70, 22);
      c.drawRect(truck, fl(BP.panel));
      c.drawRect(truck, st(BP.lineDim, 1.1));
      c.drawRect(Rect.fromLTWH(tx + 70, 618, 20, 16), st(BP.lineDim, 1.1));
      for (final wx in [tx + 14, tx + 58, tx + 80]) {
        c.drawCircle(Offset(wx, 636), 4, fl(BP.bg));
        c.drawCircle(Offset(wx, 636), 4, st(BP.lineDim, 1));
      }
      c.restore();
      // Frame and mullions.
      c.drawRect(w, st(BP.line, 2));
      c.drawRect(w.inflate(6), st(BP.lineDim, 1));
      c.drawLine(Offset(w.left, w.top + 96), Offset(w.right, w.top + 96), st(BP.line, 1.4));
      c.drawLine(Offset(w.center.dx, w.top), Offset(w.center.dx, w.top + 96), st(BP.line, 1.4));
      // Glint.
      c.drawLine(Offset(w.left + 14, w.top + 40), Offset(w.left + 40, w.top + 14), st(BP.line.withValues(alpha: 0.25), 1.2));
      // Sill.
      box(Rect.fromLTRB(w.left - 12, w.bottom + 6, w.right + 12, w.bottom + 16), w: 1.2);
    }
    // Wall below the windows: a pipe run and panels.
    c.drawLine(const Offset(40, 700), const Offset(1560, 700), st(BP.lineFaint, 1));
    c.drawLine(const Offset(40, 706), const Offset(1560, 706), st(BP.lineFaint, 1));
    for (var x = 120.0; x < 1560; x += 240) {
      c.drawLine(Offset(x, 712), Offset(x, _floor), st(BP.lineFaint, 1));
    }

    // Window cleaner on a stepladder at window 4.
    {
      const lx = 1420.0;
      final ladder = Path()
        ..moveTo(lx - 20, _floor)
        ..lineTo(lx - 6, 700)
        ..lineTo(lx + 6, 700)
        ..lineTo(lx + 20, _floor);
      c.drawPath(ladder, st(BP.lineDim, 1.2));
      for (var y = 724.0; y < _floor; y += 22) {
        final hw = 6 + 14 * (y - 700) / 90;
        c.drawLine(Offset(lx - hw, y), Offset(lx + hw, y), st(BP.lineDim, 1));
      }
      final a = math.sin(t * 2.4);
      final f = Pose()
        ..upA = 2.3 + 0.3 * a
        ..foA = 2.7 + 0.35 * a
        ..head = -0.2;
      final g = guy(const Offset(lx, 700), 34, -1, f);
      final sq = g.handA + const Offset(-4, -6);
      c.drawLine(sq + const Offset(-7, 0), sq + const Offset(7, 0), st(BP.ink, 2.2));
      c.drawLine(g.handA, sq, st(BP.inkDim, 1.2));
      // Wet streak on the glass.
      final streak = Path()..addArc(Rect.fromCircle(center: const Offset(1400, 628), radius: 34), -2.6, 1.8);
      c.drawPath(streak, st(BP.line.withValues(alpha: 0.2 + 0.1 * a), 1.2));
      // A bucket.
      box(const Rect.fromLTRB(1452, 772, 1470, _floor), w: 1.1);
    }

    // The tour group at the windows.
    final pointing = 0.4 + 0.6 * bump(seg(t % 5, 0.4, 3.4));
    tourGroup(720, _floor, t, pointing: pointing, look: true, mouse: io.mouse);
  }

  void _plantSign(String name, Offset center) {
    final tp = mono(name, 15, BP.ink, 600);
    final r = Rect.fromCenter(center: center, width: tp.width + 18, height: 24);
    c.drawRect(r, fl(BP.paper));
    c.drawRect(r, st(BP.line, 1.2));
    tp.paint(c, Offset(r.left + 9, r.top + (24 - tp.height) / 2));
  }

  void _product(String g, Offset at, Color col) {
    final r = Rect.fromCenter(center: at, width: 34, height: 28);
    c.drawRect(r, fl(BP.panel));
    c.drawRect(r, st(col, 1.2));
    paintFit(sample(g, 18, col), r.deflate(3), fitHeight: true);
  }

  /// Chrome: DOM text rides out on trays.
  void _chrome(Rect w, double b) {
    final x0 = w.left + 40, x1 = w.right - 40;
    // Sawtooth roof.
    final roof = Path()..moveTo(x0, 600);
    roof.lineTo(x0, 470);
    for (var i = 0; i < 5; i++) {
      final a = x0 + (x1 - x0) * i / 5, bb = x0 + (x1 - x0) * (i + 1) / 5;
      roof
        ..lineTo(a, 452)
        ..lineTo(bb, 470);
    }
    roof
      ..lineTo(x1, 600)
      ..close();
    c.drawPath(roof, fl(BP.panel));
    c.drawPath(roof, st(BP.line, 1.3));
    for (var i = 0; i < 4; i++) {
      c.drawRect(Rect.fromLTWH(x0 + 16 + i * 58.0, 488, 40, 26), st(BP.lineDim, 1));
    }
    _plantSign('Chrome', Offset(w.center.dx, 532));
    // Tray conveyor in front: DOM text on trays.
    c.drawLine(Offset(w.left, 596), Offset(w.right, 596), st(BP.lineDim, 1.2));
    const tags = ['<p>', 'Aa', '<b>', '<div>', '<i>', 'Aa'];
    final v = 34 + 60 * b;
    for (var i = 0; i < 8; i++) {
      final x = w.left - 40 + ((t * v + i * 52) % (w.width + 80));
      final tr = Rect.fromLTWH(x, 578, 40, 16);
      c.drawRect(tr, fl(BP.panel));
      c.drawRect(tr, st(BP.line, 1));
      paintFit(mono(tags[i % tags.length], 10, BP.ink), tr.deflate(2));
    }
    steam(Offset(x1 - 16, 446), t, per: 0.6, life: 2.4, rise: 34, r: 8, seed: 11);
    _product(info.glyphs[0], Offset(x0 + 8, 560), BP.line);
  }

  /// Figma: a vector press stamps Bézier outlines.
  void _figma(Rect w, double b) {
    final x0 = w.left + 44, x1 = w.right - 44;
    final body = Rect.fromLTRB(x0, 458, x1, 600);
    c.drawRect(body, fl(BP.panel));
    c.drawRect(body, st(BP.line, 1.3));
    _plantSign('Figma', Offset(w.center.dx, 446));
    // Press.
    final per = 2.2 - 0.9 * b;
    final p = (t % per) / per;
    final ramY = lerp(486, 530, bump(seg(p, 0.1, 0.5)));
    c.drawLine(Offset(w.center.dx, 470), Offset(w.center.dx, ramY), st(BP.line, 3));
    box(Rect.fromLTRB(w.center.dx - 40, ramY, w.center.dx + 40, ramY + 12), w: 1.2);
    // The sheet with a Bézier path and its handles.
    final sx = w.center.dx - 70, sy = 556.0;
    final wob = math.sin(t * 1.2) * 6;
    final a0 = Offset(sx, sy + 20), a1 = Offset(sx + 140, sy + 20);
    final h0 = Offset(sx + 30, sy - 26 + wob), h1 = Offset(sx + 110, sy + 44 - wob);
    final path = Path()
      ..moveTo(a0.dx, a0.dy)
      ..cubicTo(h0.dx, h0.dy, h1.dx, h1.dy, a1.dx, a1.dy);
    c.drawPath(path, st(BP.ink, 1.8));
    c.drawLine(a0, h0, st(BP.violet, 1));
    c.drawLine(a1, h1, st(BP.violet, 1));
    for (final q in [h0, h1]) {
      c.drawCircle(q, 3, fl(BP.violet));
    }
    for (final q in [a0, a1]) {
      c.drawRect(Rect.fromCenter(center: q, width: 6, height: 6), fl(BP.paper));
      c.drawRect(Rect.fromCenter(center: q, width: 6, height: 6), st(BP.ink, 1.2));
    }
    _product(info.glyphs[1], Offset(x1 + 22, 586), BP.violet);
  }

  /// Apple: its own shaper machine, gears and all.
  void _apple(Rect w, double b) {
    final body = RRect.fromRectAndRadius(Rect.fromLTRB(w.left + 40, 452, w.right - 40, 600), const Radius.circular(26));
    c.drawRRect(body, fl(BP.panel));
    c.drawRRect(body, st(BP.line, 1.3));
    _plantSign('Apple', Offset(w.center.dx, 474));
    // Glass front.
    for (var x = body.left + 26; x < body.right - 20; x += 32) {
      c.drawLine(Offset(x, 496), Offset(x, 596), st(BP.lineFaint, 1));
    }
    // Two meshing gears labelled as the house shaper.
    final a = t * (0.9 + 2 * b);
    _gear(Offset(w.center.dx - 34, 548), 26, 10, a);
    _gear(Offset(w.center.dx + 16, 548), 18, 7, -a * 26 / 18 + 0.2);
    final lbl = mono('own shaper', 11, BP.amber);
    lbl.paint(c, Offset(w.center.dx + 40, 544 - lbl.height));
    final ct = mono('Core Text', 11, BP.inkDim);
    ct.paint(c, Offset(w.center.dx + 40, 548));
    _product(info.glyphs[2], Offset(body.right + 20, 586), BP.green);
  }

  void _gear(Offset o, double r, int teeth, double a) {
    final p = Path();
    for (var i = 0; i < teeth * 2; i++) {
      final ang = a + i * math.pi / teeth;
      final rr = i.isEven ? r : r * 0.8;
      final q = o + Offset(math.cos(ang), math.sin(ang)) * rr;
      i == 0 ? p.moveTo(q.dx, q.dy) : p.lineTo(q.dx, q.dy);
    }
    p.close();
    c.drawPath(p, fl(BP.panel));
    c.drawPath(p, st(BP.line, 1.2));
    c.drawCircle(o, r * 0.3, st(BP.lineDim, 1));
  }

  /// Android: Minikin cuts the ribbon into balanced lines.
  void _android(Rect w, double b) {
    final body = Rect.fromLTRB(w.left + 40, 466, w.right - 40, 600);
    c.drawRect(body, fl(BP.panel));
    c.drawRect(body, st(BP.line, 1.3));
    // Two antennae on the roof.
    c.drawLine(Offset(body.left + 40, body.top), Offset(body.left + 26, body.top - 22), st(BP.line, 1.3));
    c.drawLine(Offset(body.right - 40, body.top), Offset(body.right - 26, body.top - 22), st(BP.line, 1.3));
    _plantSign('Android', Offset(w.center.dx, 488));
    final m = mono('Minikin', 11, BP.amber);
    m.paint(c, Offset(body.left + 14, 512));
    // Ribbon in; balanced lines out.
    final p = (t * (0.35 + 0.6 * b)) % 1;
    final rib = Rect.fromLTWH(body.left + 14, 538, 120 * (1 - eio(seg(p, 0.1, 0.5))) + 10, 8);
    c.drawRect(rib, fl(BP.green.withValues(alpha: 0.5)));
    final out = eio(seg(p, 0.45, 0.8));
    for (var i = 0; i < 3; i++) {
      final lw = [84.0, 80.0, 76.0][i];
      final r = Rect.fromLTWH(body.right - 110, 534 + i * 14.0, lw * out, 8);
      c.drawRect(r, fl(BP.green.withValues(alpha: 0.7)));
    }
    c.drawLine(Offset(body.right - 116, 530), Offset(body.right - 116, 576), st(BP.amber, 1.4));
    _product(info.glyphs[3], Offset(body.left - 18, 586), BP.green);
  }

  // ── 04 · Our specs ─────────────────────────────────────────────────────────

  static const _specX = [214.0, 400.0, 586.0, 772.0, 1012.0, 1198.0, 1384.0];
  static const _specNames = [
    'vertical press',
    'ruby press',
    'hyphenator',
    'LCD painter',
    'same parts',
    'shaders',
    'widgets in text',
  ];
  static const _hookY = 616.0;

  double _hungAt(int i) => 0.9 + i * 0.78;

  void specs() {
    floor(24, 1576, _floor);
    // The sheet.
    const sheet = Rect.fromLTRB(100, 352, 1500, 700);
    c.drawRect(sheet, fl(BP.panel));
    c.drawRect(sheet, st(BP.line, 1.5));
    c.drawRect(sheet.deflate(6), st(BP.lineDim, 1));
    for (final p in [sheet.topLeft + const Offset(20, 0), sheet.topRight + const Offset(-20, 0)]) {
      c.drawCircle(p + const Offset(0, 12), 4, st(BP.line, 1.2));
    }
    mono('flutter · spec', 14, BP.inkDim).paint(c, const Offset(122, 366));
    final missing = mono('missing', 13, BP.red);
    missing.paint(c, Offset(_specX[0] - 80, 390));
    final only = mono('only here', 13, BP.green);
    only.paint(c, Offset(_specX[4] - 80, 390));
    c.drawPath(dashPath(Path()
      ..moveTo(892, 380)
      ..lineTo(892, 684), dash: 6, gap: 6), st(BP.lineDim, 1));

    for (var i = 0; i < 7; i++) {
      final cx = _specX[i];
      final area = Rect.fromCenter(center: Offset(cx, 492), width: 160, height: 150);
      final ok = i >= 4;
      if (ok) {
        _specUnique(i, area);
      } else {
        _specMissing(i, area);
      }
      final l = mono(_specNames[i], 14, ok ? BP.ink : BP.inkDim);
      l.paint(c, Offset(cx - l.width / 2, 580));
      // Hook.
      c.drawCircle(Offset(cx, _hookY), 3, st(BP.line, 1.2));
      io.targets.add(Rect.fromCenter(center: Offset(cx, _hookY + 42), width: 70, height: 84));
      _tag(i, cx, ok);
    }

    // Inspector with a tag pole walks the sheet, hanging tags.
    {
      double x;
      var reach = 0.0;
      var walking = false;
      final lastT = _hungAt(6) + 0.4;
      if (t < _hungAt(0) - 0.4) {
        x = lerp(40, _specX[0] - 26, eio(t / (_hungAt(0) - 0.4)));
        walking = true;
      } else if (t < lastT) {
        final i = ((t - (_hungAt(0) - 0.4)) / 0.78).floor().clamp(0, 6);
        final u = t - (_hungAt(i) - 0.4);
        if (u < 0.55) {
          x = _specX[i] - 26;
          reach = bump(u / 0.55);
        } else {
          final nx = i < 6 ? _specX[i + 1] - 26 : 1470.0;
          x = lerp(_specX[i] - 26, nx, eio((u - 0.55) / 0.23));
          walking = true;
        }
      } else {
        x = lerp(_specX[6] - 26, 1470, eio((t - lastT) / 0.8));
        walking = t - lastT < 0.8;
      }
      final f = Pose();
      if (walking) f.walk(x / 5, amp: 0.4);
      f
        ..upA = lerp(walking ? f.upA : 0.9, 2.7, reach)
        ..foA = lerp(walking ? f.foA : 1.6, 2.8, reach);
      final g = guy(Offset(x, _floor), 34, 1, f);
      if (reach > 0.05) {
        final top = Offset(x + 26, _hookY + 4);
        c.drawLine(g.handA, Offset.lerp(g.handA, top, reach)!, st(BP.inkDim, 1.3));
      } else {
        clipboard(g.handB, done: t > lastT);
      }
    }
    tourGroup(250, _floor, t, pointing: bump(seg(t % 6, 1.0, 4.0)), look: true, mouse: io.mouse);
  }

  void _tag(int i, double cx, bool ok) {
    final since = t - _hungAt(i);
    if (since < 0) return;
    final kick = io.target == i ? t - io.targetAt : 1e9;
    var ang = 0.5 * math.exp(-since * 2.2) * math.sin(since * 7) + 0.035 * math.sin(t * 1.3 + i * 1.7);
    if (kick < 6) ang += 0.45 * math.exp(-kick * 1.6) * math.sin(kick * 8);
    final drop = eo(seg(since, 0, 0.25));
    c.save();
    c.translate(cx, _hookY);
    c.rotate(ang);
    final col = ok ? BP.green : BP.red;
    final len = 26 * drop;
    c.drawLine(Offset.zero, Offset(0, len), st(BP.inkDim, 1));
    final body = Path()
      ..moveTo(-8, len)
      ..lineTo(8, len)
      ..lineTo(22, len + 12)
      ..lineTo(22, len + 52)
      ..lineTo(-22, len + 52)
      ..lineTo(-22, len + 12)
      ..close();
    c.drawPath(body, fl(BP.paper));
    c.drawPath(body, fl(col.withValues(alpha: 0.16)));
    c.drawPath(body, st(col, 1.5));
    c.drawCircle(Offset(0, len + 7), 2.2, st(col, 1));
    final m = Offset(0, len + 32);
    if (ok) {
      c.drawPath(
        Path()
          ..moveTo(m.dx - 9, m.dy)
          ..lineTo(m.dx - 2, m.dy + 7)
          ..lineTo(m.dx + 11, m.dy - 9),
        st(col, 3),
      );
    } else {
      c.drawLine(m + const Offset(-8, -8), m + const Offset(8, 8), st(col, 3));
      c.drawLine(m + const Offset(8, -8), m + const Offset(-8, 8), st(col, 3));
    }
    c.restore();
  }

  Paint _ghost() => st(BP.red.withValues(alpha: 0.45), 1.2);

  void _dashedRect(Rect r) => c.drawPath(dashPath(Path()..addRect(r), dash: 5, gap: 4), _ghost());

  void _specMissing(int i, Rect a) {
    switch (i) {
      case 0: // vertical press: a press over a column of vertical text
        _dashedRect(Rect.fromLTRB(a.left + 20, a.top + 4, a.right - 20, a.top + 26));
        _dashedRect(Rect.fromLTRB(a.left + 24, a.top + 26, a.left + 34, a.bottom - 4));
        _dashedRect(Rect.fromLTRB(a.right - 34, a.top + 26, a.right - 24, a.bottom - 4));
        var y = a.top + 34;
        for (final g in ['縦', '書', 'き']) {
          final tp = sample(g, 30, BP.inkFaint, jaLocale);
          tp.paint(c, Offset(a.center.dx - tp.width / 2, y));
          y += 34;
        }
      case 1: // ruby press: base text with small reading above
        _dashedRect(Rect.fromLTRB(a.left + 14, a.top + 14, a.right - 14, a.bottom - 14));
        final ruby = sample('かんじ', 15, BP.inkFaint, jaLocale);
        final base = sample('漢字', 44, BP.inkFaint, jaLocale);
        final y = a.center.dy - (ruby.height + base.height) / 2 + 4;
        ruby.paint(c, Offset(a.center.dx - ruby.width / 2, y));
        base.paint(c, Offset(a.center.dx - base.width / 2, y + ruby.height - 4));
      case 2: // hyphenator: a word cut in two with a hyphen
        _dashedRect(Rect.fromLTRB(a.left + 14, a.top + 14, a.right - 14, a.bottom - 14));
        final l1 = sample('hyphen-', 26, BP.inkFaint);
        final l2 = sample('ation', 26, BP.inkFaint);
        l1.paint(c, Offset(a.left + 30, a.center.dy - l1.height));
        l2.paint(c, Offset(a.left + 30, a.center.dy + 2));
        final blade = Path()
          ..moveTo(a.right - 36, a.top + 20)
          ..lineTo(a.right - 24, a.top + 20)
          ..lineTo(a.right - 24, a.center.dy + 6)
          ..lineTo(a.right - 36, a.center.dy - 4)
          ..close();
        c.drawPath(dashPath(blade, dash: 4, gap: 3), _ghost());
      default: // LCD painter: subpixel stripes
        _dashedRect(Rect.fromLTRB(a.left + 14, a.top + 14, a.right - 14, a.bottom - 14));
        const cols = [BP.red, BP.green, BP.line];
        final grid = Rect.fromCenter(center: a.center, width: 96, height: 96);
        const n = 6;
        final cell = grid.width / n;
        for (var yy = 0; yy < n; yy++) {
          for (var xx = 0; xx < n; xx++) {
            final on = rnd(xx, yy, 77) > 0.45 || (xx == 2 || yy == 3);
            if (!on) continue;
            for (var s = 0; s < 3; s++) {
              c.drawRect(
                Rect.fromLTWH(grid.left + xx * cell + s * cell / 3, grid.top + yy * cell, cell / 3 - 1, cell - 1),
                fl(cols[s].withValues(alpha: 0.16)),
              );
            }
          }
        }
        c.drawRect(grid, st(BP.inkFaint, 1));
    }
  }

  void _specUnique(int i, Rect a) {
    switch (i) {
      case 4: // same parts on every platform: three identical stampers
        final p = (t % 1.6) / 1.6;
        final ram = bump(seg(p, 0.1, 0.45));
        for (var k = 0; k < 3; k++) {
          final x = a.left + 14 + k * 46.0;
          box(Rect.fromLTWH(x, a.top + 6, 40, 14), w: 1.1);
          c.drawLine(Offset(x + 20, a.top + 20), Offset(x + 20, a.top + 32 + 20 * ram), st(BP.line, 2));
          box(Rect.fromLTWH(x + 8, a.top + 32 + 20 * ram, 24, 8), w: 1);
          final out = Rect.fromLTWH(x + 2, a.top + 72, 36, 36);
          c.drawRect(out, fl(BP.paper));
          c.drawRect(out, st(BP.green, 1.2));
          paintFit(sample('あ', 24, BP.ink, jaLocale), out.deflate(4), fitHeight: true);
          final os = ['ios', 'android', 'web'][k];
          final l = mono(os, 10, BP.inkDim);
          l.paint(c, Offset(x + 20 - l.width / 2, a.top + 114));
        }
      case 5: // shaders: a spray gun paints a moving gradient into the letters
        final word = txt.get('Aa', BT.display(84, weight: 600, height: 1));
        final o = Offset(a.center.dx - word.width / 2, a.top + 34);
        final wr = o & word.size;
        c.saveLayer(wr.inflate(4), Paint());
        word.paint(c, o);
        final s = (t * 0.35) % 1;
        c.drawRect(
          wr.inflate(4),
          Paint()
            ..blendMode = BlendMode.srcIn
            ..shader = ui.Gradient.linear(
              Offset(wr.left - wr.width * (1 - s), wr.top),
              Offset(wr.right + wr.width * s, wr.bottom),
              const [BP.pink, BP.amber, BP.green, BP.line, BP.violet, BP.pink],
              const [0, 0.2, 0.4, 0.6, 0.8, 1],
            ),
        );
        c.restore();
        // The gun sweeps over the word.
        final gx = lerp(wr.left, wr.right, 0.5 + 0.5 * math.sin(t * 1.6));
        final gun = Offset(gx, a.top + 12);
        box(Rect.fromCenter(center: gun, width: 26, height: 12), w: 1.2);
        c.drawLine(gun + const Offset(0, 6), gun + const Offset(0, 12), st(BP.line, 2));
        for (var k = 0; k < 6; k++) {
          final q = (t * 3 + k / 6) % 1;
          final d = Offset((rnd(k, (t * 3).floor()) - 0.5) * 30 * q, 10 + 26 * q);
          c.drawCircle(gun + const Offset(0, 12) + d, 1.2, fl(BP.amber.withValues(alpha: 1 - q)));
        }
      default: // widgets in text: a real placeholder in a real paragraph
        final tp = txt.span(
          'widget-line',
          () => TextSpan(
            style: BT.display(34, color: BP.ink),
            children: const [
              TextSpan(text: 'text '),
              WidgetSpan(child: SizedBox(width: 34, height: 34), alignment: PlaceholderAlignment.middle),
              TextSpan(text: ' text'),
            ],
          ),
          placeholders: const [PlaceholderDimensions(size: Size(34, 34), alignment: PlaceholderAlignment.middle)],
        );
        final o = Offset(a.center.dx - tp.width / 2, a.center.dy - tp.height / 2);
        tp.paint(c, o);
        final boxes = tp.inlinePlaceholderBoxes ?? const <TextBox>[];
        if (boxes.isNotEmpty) {
          final r = boxes.first.toRect().shift(o);
          c.drawPath(dashPath(Path()..addRect(r.inflate(3)), dash: 3, gap: 3), st(BP.green, 1));
          _gear(r.center, 14, 8, t * 1.8);
          c.drawCircle(r.center, 3, fl(BP.amber));
        }
    }
  }

  // ── 05 · Follow one crate ──────────────────────────────────────────────────

  static const _belt5 = 660.0;
  static const _st5 = [360.0, 740.0, 1100.0];

  ({double x, int stage, bool moving, double dwellP, int at}) _crate5(double u) {
    // Travel legs and dwells, in seconds.
    const legs = [
      (0.0, 2.2, 40.0, 360.0),
      (3.6, 5.4, 360.0, 740.0),
      (6.8, 8.6, 740.0, 1100.0),
      (10.4, 12.0, 1100.0, 1330.0),
    ];
    const dwells = [(2.2, 3.6, 0), (5.4, 6.8, 1), (8.6, 10.4, 2)];
    for (final (a, b, x0, x1) in legs) {
      if (u >= a && u < b) {
        final stage = x0 <= 40 ? 0 : (x0 <= 360 ? 1 : (x0 <= 740 ? 2 : 3));
        return (x: lerp(x0, x1, eio((u - a) / (b - a))), stage: stage, moving: true, dwellP: 0, at: -1);
      }
    }
    for (final (a, b, i) in dwells) {
      if (u >= a && u < b) {
        final p = (u - a) / (b - a);
        final done = p > 0.4;
        return (x: _st5[i], stage: i + (done ? 1 : 0), moving: false, dwellP: p, at: i);
      }
    }
    return (x: 1330, stage: 3, moving: false, dwellP: 0, at: 3);
  }

  void followCrate() {
    const per = 20.0;
    final u = t % per;
    final loop = (t / per).floor();
    final cr = _crate5(u);
    floor(24, 1576, _floor);
    io.targets.addAll([
      for (final x in _st5) Rect.fromCenter(center: Offset(x, 580), width: 150, height: 170),
      const Rect.fromLTRB(1350, 440, 1560, 700),
    ]);
    conveyor(30, 1340, _belt5, _floor, cr.x, legEvery: 190);

    // Stations.
    // 1 · fonts: a vending machine that drops the glyph in.
    {
      const r = Rect.fromLTRB(300, 470, 420, 612);
      box(r);
      for (var i = 0; i < 6; i++) {
        final cell = Rect.fromLTWH(r.left + 10 + (i % 3) * 34.0, r.top + 10 + (i ~/ 3) * 34.0, 30, 30);
        c.drawRect(cell, st(i == 1 && cr.at == 0 ? BP.amber : BP.lineFaint, i == 1 && cr.at == 0 ? 1.6 : 1));
        paintFit(sample(['Aa', 'F', 'あ', 'ب', '字', '👋'][i], 16, BP.inkDim, jaLocale), cell.deflate(4), fitHeight: true);
      }
      c.drawRect(const Rect.fromLTRB(344, 596, 376, 612), st(BP.line, 1.2));
      plate('fonts', const Offset(360, 454));
    }
    // 2 · shape: a press stamps the glyph id.
    {
      box(const Rect.fromLTRB(670, 488, 810, 516));
      box(const Rect.fromLTRB(676, 516, 688, _belt5), w: 1.1);
      box(const Rect.fromLTRB(792, 516, 804, _belt5), w: 1.1);
      var ram = 560.0;
      if (cr.at == 1) ram = lerp(560, _belt5 - _ch - 6, bump(seg(cr.dwellP, 0.2, 0.6)));
      c.drawLine(Offset(740, 516), Offset(740, ram - 26), st(BP.line, 4));
      box(Rect.fromLTRB(712, ram - 26, 768, ram), w: 1.4);
      if (cr.at == 1 && cr.dwellP > 0.38 && cr.dwellP < 0.7) sparks(Offset(740, _belt5 - _ch - 2), seg(cr.dwellP, 0.38, 0.7), loop);
      plate('shape', const Offset(740, 472));
    }
    // 3 · raster: the oven (front drawn after the crate).
    const oven = Rect.fromLTRB(1020, 500, 1180, 680);
    const win = Rect.fromLTRB(1040, 584, 1160, 660);

    // Past route: an amber dashed trail.
    if (cr.x > 50) {
      c.drawPath(dashPath(Path()
        ..moveTo(40, _belt5 - 4)
        ..lineTo(cr.x - 40, _belt5 - 4), dash: 8, gap: 6), st(BP.amber.withValues(alpha: 0.6), 1.6));
    }
    // Other crates, parked and dim: we only follow one.
    for (final x in [120.0, 200.0]) {
      final r = Rect.fromLTWH(x - 26, _floor - 40, 52, 40);
      c.drawRect(r, fl(BP.panel));
      c.drawRect(r, st(BP.lineFaint, 1));
    }

    // Spotlight on a trolley.
    c.drawLine(const Offset(30, 404), const Offset(1570, 404), st(BP.lineDim, 1.2));
    final lx = cr.x;
    box(Rect.fromCenter(center: Offset(lx, 404), width: 26, height: 10), w: 1.1);
    final spot = Path()
      ..moveTo(lx - 10, 430)
      ..lineTo(lx + 10, 430)
      ..lineTo(lx + 64, _belt5)
      ..lineTo(lx - 64, _belt5)
      ..close();
    final arriving = u > 12;
    if (!arriving) c.drawPath(spot, fl(BP.amber.withValues(alpha: 0.07)));
    c.drawLine(Offset(lx, 409), Offset(lx, 418), st(BP.lineDim, 1));
    final shade = Path()
      ..moveTo(lx - 5, 418)
      ..lineTo(lx + 5, 418)
      ..lineTo(lx + 12, 430)
      ..lineTo(lx - 12, 430)
      ..close();
    c.drawPath(shade, fl(BP.panel));
    c.drawPath(shade, st(BP.amber, 1.2));

    // The crate.
    final g = info.glyphs[0];
    final id = info.glyphs[2];
    if (u < 12.6) {
      const y = _belt5 - _ch;
      var x = cr.x;
      var clip = false;
      if (u >= 12.0) {
        x = lerp(1330, 1380, (u - 12) / 0.6);
        clip = true;
      }
      final r = Rect.fromLTWH(x - _cw / 2, y, _cw, _ch);
      if (clip) {
        c.save();
        c.clipRect(const Rect.fromLTRB(0, 0, 1352, 900));
      }
      final stage = cr.stage;
      final col = stage >= 3 ? BP.line : (stage >= 1 ? BP.amber : BP.inkDim);
      crate(r, col, stamp: stage >= 2 ? mono(id, 10, BP.amber, 600) : mono(_hexOf(g), 9, BP.inkDim));
      final body = Rect.fromLTRB(r.left + 3, r.top + 12, r.right - 3, r.bottom - 3);
      if (stage >= 3) {
        pixels(txt.raster(g, BT.sample(12)), body);
      } else if (stage >= 1) {
        var dy = 0.0;
        if (cr.at == 0) dy = -(1 - ei(seg(cr.dwellP, 0.2, 0.4))) * 50;
        c.save();
        c.clipRect(Rect.fromLTRB(r.left, r.top - 60, r.right, r.bottom));
        paintFit(sample(g, 28), body.shift(Offset(0, dy)), fitHeight: true);
        c.restore();
      } else {
        final b = body.deflate(4);
        c.drawLine(b.topLeft, b.bottomRight, st(BP.lineFaint, 1));
        c.drawLine(b.bottomLeft, b.topRight, st(BP.lineFaint, 1));
      }
      if (clip) c.restore();
      if (cr.at == 0 && cr.dwellP > 0.1 && cr.dwellP < 0.4) {
        final dy = lerp(612, r.top + 12, ei(seg(cr.dwellP, 0.1, 0.4)));
        paintFit(sample(g, 20), Rect.fromCenter(center: Offset(r.center.dx, dy), width: 30, height: 24), fitHeight: true);
      }
    }

    // Oven front.
    {
      final shell = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(oven)
        ..addRect(win);
      c.drawPath(shell, fl(BP.panel));
      c.drawRect(oven, st(BP.line, 1.4));
      c.drawRect(win, st(BP.line, 1.2));
      final heat = cr.at == 2 ? bump(cr.dwellP) : 0.0;
      final coil = Path()..moveTo(win.left + 6, win.top + 6);
      for (var i = 1; i <= 13; i++) {
        coil.lineTo(win.left + 6 + i * 8.3, win.top + (i.isEven ? 6 : 11));
      }
      c.drawPath(coil, st(BP.coral.withValues(alpha: 0.45 + 0.5 * heat), 1.3));
      c.drawRect(const Rect.fromLTRB(1150, 458, 1168, 500), fl(BP.panel));
      c.drawRect(const Rect.fromLTRB(1150, 458, 1168, 500), st(BP.line, 1.3));
      steam(const Offset(1159, 452), t, per: 0.45, life: 2.2, rise: 36, r: 9 + 8 * heat, seed: 5);
      plate('raster', const Offset(1100, 484));
    }

    // The screen at the end: the glyph as pixels, big.
    {
      const scr = Rect.fromLTRB(1364, 470, 1548, 640);
      box(scr, w: 1.6);
      c.drawLine(const Offset(1456, 640), const Offset(1456, 740), st(BP.line, 1.6));
      c.drawLine(const Offset(1416, _floor), const Offset(1456, 740), st(BP.line, 1.6));
      c.drawLine(const Offset(1496, _floor), const Offset(1456, 740), st(BP.line, 1.6));
      final inner = scr.deflate(12);
      final on = seg(u, 12.4, 13.0) * (1 - seg(u, 19.2, 20));
      if (on > 0) {
        c.drawRect(inner, fl(BP.line.withValues(alpha: 0.05 * on)));
        pixels(txt.raster(g, BT.sample(14)), inner.deflate(6), opacity: on);
      } else {
        for (var y = inner.top + 4; y < inner.bottom; y += 6) {
          c.drawLine(Offset(inner.left, y), Offset(inner.right, y), st(BP.lineFaint, 1));
        }
      }
      lamp(Offset(scr.right - 12, scr.bottom - 8), BP.green, on > 0.5, 3.5);
    }

    // The tour group follows the crate, cheers at the screen, jogs back.
    double gx;
    var walk = -1.0;
    var cheer = false;
    if (u < 12.0) {
      gx = math.max(-40, cr.x - 110);
      if (cr.moving) walk = gx / 5.5;
    } else if (u < 13.6) {
      gx = 1220;
      cheer = u > 12.4;
    } else {
      final p = eio((u - 13.6) / 6.4);
      gx = lerp(1220, -70, p);
      walk = gx / 4;
    }
    if (cheer) {
      for (var i = 0; i < 4; i++) {
        final f = Pose()..cheer(t, i * 3);
        worker(Offset(gx - i * 28.0, _floor), i == 0 ? 30 : 27.6, 1, f, hat: i == 0 ? BP.green : BP.line, ink: i == 0 ? BP.ink : BP.inkDim);
      }
    } else {
      tourGroup(gx, _floor, t, dir: u >= 13.6 ? -1 : 1, walk: walk, pointing: cr.moving ? 0 : 1, mouse: io.mouse);
    }
  }
}
