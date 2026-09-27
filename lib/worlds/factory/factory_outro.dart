import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import 'factory_kit.dart';

/// End of shift. The LED marquee over the floor prints 「ありがとうございました」
/// pixel by pixel (real engine coverage, shown as LEDs), and a ticker scrolls
/// "thank you · questions? · ご質問は？". Below it the crew finish up, clock out
/// one by one at the time clock and leave through the door; the lamps go out
/// left to right, the paper dims, and a night watchman starts his rounds with
/// a flashlight. The tour group stays under the last lamp, waving and bowing.
///
/// Click the marquee to print it again; click the time clock to punch a card;
/// hover a figure to make it wave. Runs forever as a pure function of time.
class FactoryOutro extends StatelessWidget {
  const FactoryOutro({super.key});

  @override
  Widget build(BuildContext context) => FactoryScene(painter: (clock, text, io) => _OutroPainter(clock, text, io));
}

const _floor = 790.0;
const _board = Rect.fromLTRB(170, 92, 1430, 384);
const _big = Rect.fromLTRB(196, 116, 1404, 272);
const _ticker = Rect.fromLTRB(206, 300, 1394, 356);
const _clock = Rect.fromLTRB(1330, 640, 1382, 704);
const _door = Rect.fromLTRB(1446, 652, 1520, _floor);
const _punchX = 1310.0;
const _doorX = 1483.0;
const _speed = 88.0;

const _thanks = '「ありがとうございました」';
const _tickerText = 'thank you  ·  questions?  ·  ご質問は？  ·  ありがとうございました  ·  ';

const _lampX = [120.0, 380.0, 640.0, 900.0, 1160.0, 1478.0];
const _nightLamp = 2;

/// The crew, right to left: (start x, facing, prop).
const _crew = [
  (1086.0, -1, 'inspect'),
  (938.0, -1, 'wipe'),
  (792.0, 1, 'coffee'),
  (486.0, 1, 'watch'),
  (318.0, 1, 'sweep'),
  (170.0, 1, 'yawn'),
];

/// When each worker leaves their spot, reaches the clock, and leaves it.
final _schedule = () {
  final out = <({double leave, double atClock, double done, double exit})>[];
  var prevAt = -1e9;
  for (var k = 0; k < _crew.length; k++) {
    final travel = (_punchX - _crew[k].$1) / _speed;
    final leave = math.max(3.5 + 1.6 * k, prevAt + 1.7 - travel);
    final at = leave + travel;
    final done = at + 1.0;
    out.add((leave: leave, atClock: at, done: done, exit: done + (_doorX - _punchX) / _speed));
    prevAt = at;
  }
  return out;
}();

final _allGone = _schedule.last.exit + 0.6;

class _OutroPainter extends CustomPainter {
  _OutroPainter(this.clock, this.text, this.io) : super(repaint: clock);

  final SceneClock clock;
  final TextCache text;
  final SceneInput io;

  @override
  void paint(Canvas canvas, Size size) {
    io.targets
      ..clear()
      ..addAll(const [_board, Rect.fromLTRB(1300, 630, 1392, 712)]);
    _Outro(canvas, clock.local, text, io).draw();
  }

  @override
  bool shouldRepaint(_OutroPainter old) => false;
}

class _Outro extends FactoryInk {
  _Outro(super.c, this.t, this.txt, this.io);

  final double t;
  final TextCache txt;
  final SceneInput io;

  static final _led = Paint()..filterQuality = FilterQuality.none;

  /// Lamp m's brightness: each goes out in turn, with a flicker.
  double lampOn(int m) {
    final off = m == _lampX.length - 1 ? _allGone + 0.8 : 7.0 + 2.3 * m;
    final floorLevel = m == _nightLamp ? 0.35 : 0.0;
    if (t < off) return 1;
    final a = t - off;
    if (a < 0.5) return rnd((a * 24).floor(), m, 9) > 0.5 ? 1 : floorLevel;
    return floorLevel;
  }

  /// How far the lights are down, 0..1.
  double get darkness => eio(seg(t, 6.5, _allGone));

  Limbs guy(Offset feet, double h, int dir, Pose f, {Color hat = BP.amber, Color ink = BP.ink, Color back = BP.inkDim}) {
    final m = io.mouse;
    if (m != null && (m - feet.translate(0, -h * 0.55)).distance < h * 0.7) f.wave(t);
    return worker(feet, h, dir, f, hat: hat, ink: ink, back: back);
  }

  void draw() {
    lamps();
    line();
    wall();
    crew();
    // The paper itself dims as the lights go out.
    c.drawRect(const Rect.fromLTRB(0, 0, 1600, _floor + 2), fl(BP.bg.withValues(alpha: 0.42 * darkness)));
    watchman();
    marquee();
    group();
  }

  // ── Lamps and the dark line ───────────────────────────────────────────────

  void lamps() {
    rail(40, 1560, 34, hangers: const [150, 600, 1050, 1450]);
    for (var m = 0; m < _lampX.length; m++) {
      hangingLamp(Offset(_lampX[m], 50), 452, _floor, lampOn(m), spread: 96);
    }
  }

  void line() {
    // The day's work sits finished on the belt, the machines idle.
    final heat = 1 - seg(t, 2, 14);
    conveyor(60, 1190, 700, _floor, 0, legEvery: 190);
    // Hopper.
    final funnel = Path()
      ..moveTo(78, 560)
      ..lineTo(198, 560)
      ..lineTo(164, 620)
      ..lineTo(112, 620)
      ..close();
    c.drawPath(funnel, fl(BP.panel));
    c.drawPath(funnel, st(BP.lineDim, 1.3));
    box(const Rect.fromLTRB(112, 620, 164, 676), col: BP.lineDim);
    // Press.
    box(const Rect.fromLTRB(426, 588, 546, 614), col: BP.lineDim);
    box(const Rect.fromLTRB(432, 614, 442, 700), col: BP.lineDim, w: 1.1);
    box(const Rect.fromLTRB(530, 614, 540, 700), col: BP.lineDim, w: 1.1);
    box(const Rect.fromLTRB(460, 632, 512, 656), col: BP.lineDim);
    // Oven, cooling down.
    const body = Rect.fromLTRB(800, 578, 980, 716);
    const win = Rect.fromLTRB(822, 640, 958, 698);
    final shell = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(body)
      ..addRect(win);
    c.drawPath(shell, fl(BP.panel));
    c.drawRect(body, st(BP.lineDim, 1.3));
    c.drawRect(win, st(BP.lineDim, 1.1));
    final coil = Path()..moveTo(win.left + 6, win.top + 6);
    for (var i = 1; i <= 14; i++) {
      coil.lineTo(win.left + 6 + i * 8.9, win.top + (i.isEven ? 6 : 11));
    }
    c.drawPath(coil, st(BP.coral.withValues(alpha: 0.15 + 0.5 * heat), 1.2));
    box(const Rect.fromLTRB(946, 540, 964, 578), col: BP.lineDim);
    steam(const Offset(955, 534), t, per: 0.7, life: 2.6, rise: 36, r: 9, seed: 4, until: 14);
    // Finished crates: today's output, as pixel tiles.
    const out = ['あ', 'り', 'が', 'と', 'う'];
    for (var i = 0; i < out.length; i++) {
      final r = Rect.fromLTWH(1000 + i * 36.0, 666, 32, 34);
      box(r, col: BP.lineDim, w: 1);
      pixels(txt.raster(out[i], BT.sample(11).copyWith(locale: jaLocale)), r.deflate(3), grid: false);
    }
    floor(24, 1576, _floor);
  }

  void wall() {
    // Back wall on the right: time clock, card rack, the door out.
    c.drawLine(const Offset(1250, 600), const Offset(1560, 600), st(BP.lineFaint, 1));
    box(const Rect.fromLTRB(1292, 648, 1322, 704), col: BP.lineDim, w: 1);
    final punched = _schedule.where((s) => t > s.atClock + 0.5).length;
    for (var i = 0; i < 6; i++) {
      final y = 654.0 + i * 8;
      final out = i < punched;
      c.drawRect(Rect.fromLTWH(1298, y, 18, 5), st(out ? BP.amber : BP.lineDim, 1));
    }
    box(_clock, w: 1.3);
    final face = _clock.topCenter + const Offset(0, 22);
    c.drawCircle(face, 15, st(BP.line, 1.2));
    // It reads a few minutes past six, and keeps going.
    final mins = 5 + t / 20;
    final ma = mins / 60 * 2 * math.pi - math.pi / 2;
    final ha = (6 + mins / 60) / 12 * 2 * math.pi - math.pi / 2;
    c.drawLine(face, face + Offset(math.cos(ma), math.sin(ma)) * 12, st(BP.ink, 1.2));
    c.drawLine(face, face + Offset(math.cos(ha), math.sin(ha)) * 8, st(BP.ink, 1.8));
    c.drawRect(Rect.fromLTWH(_clock.left + 12, _clock.bottom - 16, _clock.width - 24, 5), st(BP.lineDim, 1));
    final kick = io.target == 1 ? t - io.targetAt : 1e9;
    for (final s in _schedule) {
      final a = t - (s.atClock + 0.45);
      if (a >= 0 && a < 0.5) star(Offset(_clock.center.dx, _clock.bottom - 13), 5 + 8 * a, BP.amber);
    }
    if (kick < 0.5) star(Offset(_clock.center.dx, _clock.bottom - 13), 5 + 8 * kick, BP.amber);
    // The door: it swings open for each worker going out.
    var open = 0.0;
    for (final s in _schedule) {
      open = math.max(open, bump(seg(t, s.exit - 1.0, s.exit + 0.8)));
    }
    c.drawRect(_door, fl(BP.bg));
    c.drawRect(_door, st(BP.line, 1.4));
    final leafW = _door.width * (1 - 0.8 * open);
    final leaf = Path()
      ..moveTo(_door.left, _door.top)
      ..lineTo(_door.left + leafW, _door.top + 6 * open)
      ..lineTo(_door.left + leafW, _door.bottom - 4 * open)
      ..lineTo(_door.left, _door.bottom)
      ..close();
    c.drawPath(leaf, fl(BP.panel));
    c.drawPath(leaf, st(BP.lineDim, 1.2));
    c.drawCircle(Offset(_door.left + leafW - 8, 724), 2.5, st(BP.line, 1));
    // Exit sign: a lit arrow, no words.
    final sign = Rect.fromCenter(center: Offset(_door.center.dx, _door.top - 18), width: 40, height: 18);
    c.drawRect(sign, fl(BP.green.withValues(alpha: 0.18)));
    c.drawRect(sign, st(BP.green, 1.2));
    drawArrow(sign.centerLeft.translate(9, 0), sign.centerRight.translate(-9, 0));
  }

  void drawArrow(Offset a, Offset b) {
    c.drawLine(a, b, st(BP.green, 1.6));
    c.drawLine(b, b + const Offset(-5, -4), st(BP.green, 1.6));
    c.drawLine(b, b + const Offset(-5, 4), st(BP.green, 1.6));
  }

  // ── The crew clocks out ───────────────────────────────────────────────────

  void crew() {
    for (var k = 0; k < _crew.length; k++) {
      final (x0, dir0, prop) = _crew[k];
      final s = _schedule[k];
      if (t >= s.exit + 0.6) continue;
      final f = Pose();
      double x;
      var dir = 1;
      var walking = false;
      if (t < s.leave) {
        x = x0;
        dir = dir0;
        idle(f, prop, k);
      } else if (t < s.atClock) {
        x = x0 + (t - s.leave) * _speed;
        walking = true;
      } else if (t < s.done) {
        x = _punchX;
        f.point(lerp(0.9, 1.75, bump(seg(t, s.atClock, s.done))));
      } else if (t < s.exit) {
        x = _punchX + (t - s.done) * _speed;
        walking = true;
      } else {
        x = _doorX;
        dim = 1 - (t - s.exit) / 0.6;
      }
      if (walking) f.walk(x / 5, amp: 0.4, arms: prop != 'coffee' && prop != 'sweep');
      if (walking && prop == 'coffee') {
        f
          ..upA = 1.1
          ..foA = 1.9;
      }
      final g = guy(Offset(x, _floor), 34, dir, f);
      final idleNow = t < s.leave;
      switch (prop) {
        case 'inspect':
          if (idleNow) {
            magnifier(g.handA, g.elbowA);
          } else {
            clipboard(g.handB, done: true);
          }
        case 'wipe':
          if (idleNow) sweat(g.head, t, dir);
        case 'coffee':
          coffee(g.handA, t);
        case 'sweep':
          broom(g.handA, g.elbowA, _floor, idleNow ? 7 * math.sin(t * 3) : -10.0 * dir);
        case 'yawn':
          if (idleNow && (t % 5) > 2.2) zees(g.head, t, dir);
      }
      dim = 1;
    }
  }

  void idle(Pose f, String prop, int k) {
    switch (prop) {
      case 'inspect':
        f
          ..upA = 1.35 + 0.1 * math.sin(t * 2)
          ..foA = 2.05
          ..head = 0.3;
      case 'wipe':
        f.wipe(t);
      case 'coffee':
        final sip = bump(seg(t % 4, 1.0, 2.4));
        f
          ..upA = lerp(1.0, 1.9, sip)
          ..foA = lerp(1.7, 3.3, sip)
          ..head = -0.15 * sip;
      case 'watch':
        if ((t + k) % 4 < 1.8) f.watch();
      case 'sweep':
        final sw = math.sin(t * 3);
        f
          ..lean = 0.18
          ..upA = 0.75 + 0.15 * sw
          ..foA = 1.0 + 0.2 * sw
          ..upB = 0.6 + 0.15 * sw
          ..foB = 0.9 + 0.2 * sw;
      default: // yawn and stretch
        final st = bump(seg(t % 5, 0.2, 2.0));
        f
          ..upA = lerp(0.1, 2.9, st)
          ..foA = lerp(0.1, 3.0, st)
          ..upB = lerp(-0.1, 2.8, st)
          ..foB = lerp(-0.1, 2.9, st)
          ..head = -0.3 * st;
    }
  }

  /// After everyone has gone: the night watchman's rounds, forever.
  void watchman() {
    final t0 = _allGone + 2.5;
    if (t < t0) return;
    const left = 230.0, right = 1470.0, v = 62.0;
    const leg = (right - left) / v;
    const period = 2 * leg + 7;
    final u = (t - t0) % period;
    double x;
    int dir;
    var walking = true;
    if (u < leg) {
      x = right - u * v;
      dir = -1;
    } else if (u < leg + 3.5) {
      x = left;
      dir = -1;
      walking = false;
    } else if (u < 2 * leg + 3.5) {
      x = left + (u - leg - 3.5) * v;
      dir = 1;
    } else {
      x = right;
      dir = 1;
      walking = false;
    }
    dim = c01((t - t0) / 0.8);
    final f = Pose();
    if (walking) f.walk(x / 4.5, amp: 0.34);
    f
      ..upA = 1.35
      ..foA = 1.55;
    if (!walking) f.head = 0.25 * math.sin(t * 0.9);
    final g = guy(Offset(x, _floor), 34, dir, f, hat: BP.inkDim);
    c.save();
    c.clipRect(const Rect.fromLTRB(0, 0, 1600, _floor));
    flashlight(g.handA, dir, t, reach: 130);
    c.restore();
    dim = 1;
  }

  // ── The marquee ───────────────────────────────────────────────────────────

  void marquee() {
    for (final x in [_board.left + 90, _board.right - 90]) {
      c.drawLine(Offset(x, 50), Offset(x, _board.top), st(BP.inkDim, 1.2));
      c.drawCircle(Offset(x, _board.top - 3), 3, st(BP.line, 1.2));
    }
    c.drawRect(_board, fl(BP.panel));
    c.drawRect(_board, st(BP.line, 1.6));
    c.drawRect(_board.deflate(7), st(BP.lineDim, 1));
    for (final p in [_board.topLeft, _board.topRight, _board.bottomLeft, _board.bottomRight]) {
      final q = Offset(p.dx + (p.dx < _board.center.dx ? 14 : -14), p.dy + (p.dy < _board.center.dy ? 14 : -14));
      c.drawCircle(q, 2.4, st(BP.lineDim, 1.2));
    }
    lamp(Offset(_board.right - 26, _board.bottom - 20), BP.green, (t * 1.2) % 2 < 1.6, 4);
    c.drawLine(Offset(_ticker.left, _big.bottom + 12), Offset(_ticker.right, _big.bottom + 12), st(BP.lineFaint, 1));

    // Big line: printed in LED column by LED column. Click to print again.
    // (The first print waits for the slide transition to finish.)
    final tp = io.target == 0 ? t - io.targetAt + 0.6 : t;
    final img = txt.raster(_thanks, BT.sample(19, color: BP.amber).copyWith(locale: jaLocale));
    final iw = img.width, ih = img.height;
    final s = math.max(1, math.min(_big.width / iw, _big.height / ih).floor()).toDouble();
    final dst = Rect.fromCenter(center: _big.center, width: iw * s, height: ih * s);
    final p = eo(seg(tp, 0.9, 3.4));
    final cols = (iw * p).floor();
    c.save();
    c.clipRect(Rect.fromLTRB(dst.left, dst.top, dst.left + cols * s, dst.bottom));
    c.drawRect(dst, fl(BP.amber.withValues(alpha: 0.05)));
    c.drawImageRect(img, Rect.fromLTWH(0, 0, iw.toDouble(), ih.toDouble()), dst, _led);
    c.restore();
    ledGrid(dst, s, iw, ih);
    if (p > 0 && p < 1) {
      final hx = dst.left + cols * s;
      c.drawLine(Offset(hx, dst.top - 8), Offset(hx, dst.bottom + 8), st(BP.amber, 1.4));
      box(Rect.fromCenter(center: Offset(hx, _board.top + 4), width: 26, height: 12), col: BP.amber, w: 1.2);
      sparks(Offset(hx, dst.center.dy), (tp * 3) % 1, (tp * 3).floor());
    }

    // Ticker: scrolls one LED at a time.
    final on = seg(tp, 3.2, 3.8);
    if (on <= 0) return;
    final tk = txt.raster(_tickerText, BT.sample(12, color: BP.line).copyWith(locale: jaLocale));
    final tw = tk.width, th = tk.height;
    final ts = math.max(1, (_ticker.height / th).floor()).toDouble();
    final top = _ticker.center.dy - th * ts / 2;
    final off = ((t * 22).floor() % tw) * ts;
    _led.color = Color.fromRGBO(0, 0, 0, on);
    c.save();
    c.clipRect(_ticker);
    for (var x = _ticker.left - off; x < _ticker.right; x += tw * ts) {
      c.drawImageRect(tk, Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()), Rect.fromLTWH(x, top, tw * ts, th * ts), _led);
    }
    c.restore();
    _led.color = const Color(0xFF000000);
    final n = ((_ticker.width) / ts).floor();
    ledGrid(Rect.fromLTWH(_ticker.left, top, n * ts, th * ts), ts, n, th);
  }

  /// Dark gaps between LEDs, so the pixels read as a dot-matrix sign.
  void ledGrid(Rect r, double s, int nx, int ny) {
    if (s < 3) return;
    final g = Path();
    for (var i = 0; i <= nx; i++) {
      g
        ..moveTo(r.left + i * s, r.top)
        ..lineTo(r.left + i * s, r.bottom);
    }
    for (var j = 0; j <= ny; j++) {
      g
        ..moveTo(r.left, r.top + j * s)
        ..lineTo(r.right, r.top + j * s);
    }
    c.drawPath(g, st(BP.panel, s >= 5 ? 1.4 : 1));
  }

  // ── The tour group says goodbye ───────────────────────────────────────────

  void group() {
    const gx = 700.0;
    const h = 30.0;
    for (var i = 3; i >= 1; i--) {
      final f = Pose();
      final ep = ((t + i * 1.3) / 6).floor();
      if (rnd(ep, i, 3) < 0.5) {
        f.wave(t + i);
      } else {
        f.cheer(t, i * 3);
      }
      guy(Offset(gx - (i * h * 0.95 + (i == 3 ? 4 : 0)), _floor), h * 0.92, 1, f, hat: BP.line, ink: BP.inkDim, back: BP.inkFaint);
    }
    // The guide: waves the flag, and bows now and then (お辞儀).
    final bow = bump(seg(t % 9, 6.2, 8.0));
    final f = Pose()
      ..upB = 2.65
      ..foB = 2.85
      ..upA = 2.3 + 0.35 * math.sin(t * 6) * (1 - bow)
      ..foA = 2.7 + 0.35 * math.sin(t * 6) * (1 - bow)
      ..lean = 0.6 * bow
      ..head = 0.25 * bow;
    final g = guy(const Offset(gx, _floor), h, 1, f, hat: BP.green);
    flag(g.handB, t * (1 + 1.5 * (1 - bow)), color: BP.green);
  }
}
