import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../deck/theme.dart';

/// The glyph factory's shared cast and props: stick-figure workers, the tour
/// group, tools, crates, lamps and particles. Every factory scene (title,
/// hall signs, pipeline, journey map, outro, ambient, ruler) draws with these,
/// so the same crew appears everywhere.

const jaLocale = Locale('ja');

// ─────────────────────────────────────────────────────────────────────────────
// Math helpers (all scenes are pure functions of time)
// ─────────────────────────────────────────────────────────────────────────────

double c01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
double seg(double t, double a, double b) => c01((t - a) / (b - a));
double lerp(double a, double b, double t) => a + (b - a) * t;
double eio(double t) => Curves.easeInOutCubic.transform(c01(t));
double eo(double t) => Curves.easeOutCubic.transform(c01(t));
double ei(double t) => Curves.easeInCubic.transform(c01(t));
double bump(double t) => t <= 0 || t >= 1 ? 0 : math.sin(t * math.pi);

/// Deterministic pseudo-random in [0, 1) (same sequence every run).
double rnd(int a, [int b = 0, int c = 0]) {
  final v = math.sin(a * 12.9898 + b * 78.233 + c * 37.719 + 0.5) * 43758.5453;
  return v - v.floorToDouble();
}

/// Seconds on the deck-wide frame clock. Scenery that lives on every slide
/// (ambient workers, gauges) reads this so it continues across slides.
double globalSeconds() {
  try {
    return SchedulerBinding.instance.currentFrameTimeStamp.inMicroseconds / 1e6;
  } catch (_) {
    return 0;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// A clock for a scene: one ticker, a ValueNotifier painters repaint on.
// ─────────────────────────────────────────────────────────────────────────────

/// Seconds since the scene appeared ([local]) and on the global frame clock
/// ([global]). One ticker per scene; painters use `repaint: clock`.
class SceneClock extends ChangeNotifier {
  double local = 0;
  double global = 0;

  void _tick(Duration elapsed) {
    local = elapsed.inMicroseconds / 1e6;
    global = globalSeconds();
    notifyListeners();
  }
}

/// Runs a [SceneClock] for as long as it is mounted.
class SceneTicker extends StatefulWidget {
  const SceneTicker({super.key, required this.builder});

  final Widget Function(BuildContext context, SceneClock clock) builder;

  @override
  State<SceneTicker> createState() => _SceneTickerState();
}

class _SceneTickerState extends State<SceneTicker> with SingleTickerProviderStateMixin {
  final _clock = SceneClock();
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _clock.global = globalSeconds();
    _ticker = createTicker(_clock._tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _clock);
}

// ─────────────────────────────────────────────────────────────────────────────
// Text cache: lay out once, paint every frame. Cleared when fonts change
// (on the web a Noto fallback font may arrive after the first layout).
// ─────────────────────────────────────────────────────────────────────────────

class TextCache {
  TextCache() {
    PaintingBinding.instance.systemFonts.addListener(clear);
  }

  final _map = <Object, TextPainter>{};

  /// A laid-out painter for [text] in [style]. [key] distinguishes styles
  /// that don't compare equal by value (e.g. with a foreground Paint).
  TextPainter get(
    String text,
    TextStyle style, {
    Object? key,
    double maxWidth = double.infinity,
    TextAlign align = TextAlign.left,
  }) {
    final k = (text, key ?? style, maxWidth, align);
    return _map[k] ??= TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: maxWidth);
  }

  /// A laid-out painter for an arbitrary [span], cached under [key]. Pass
  /// [placeholders] when the span has WidgetSpans.
  TextPainter span(Object key, InlineSpan Function() span, {List<PlaceholderDimensions>? placeholders}) =>
      _map[('span', key)] ??= (TextPainter(text: span(), textDirection: TextDirection.ltr)
        ..setPlaceholderDimensions(placeholders)
        ..layout());

  final _images = <Object, ui.Image>{};

  /// A small raster of [text] in [style] (real engine coverage), for pixel
  /// tiles drawn with [FilterQuality.none].
  ui.Image raster(String text, TextStyle style) => _images[(text, style)] ??= () {
    final p = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
    final rec = ui.PictureRecorder();
    p.paint(Canvas(rec), const Offset(1, 0));
    final pic = rec.endRecording();
    final img = pic.toImageSync(math.max(1, (p.width + 2).ceil()), math.max(1, p.height.ceil()));
    pic.dispose();
    p.dispose();
    return img;
  }();

  void clear() {
    for (final p in _map.values) {
      p.dispose();
    }
    _map.clear();
    for (final i in _images.values) {
      i.dispose();
    }
    _images.clear();
  }

  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(clear);
    clear();
  }
}

/// Mouse position and the last click, shared between a scene widget and its
/// painter without rebuilding.
class SceneInput {
  Offset? mouse;
  Offset? tap;
  double tapAt = -1e9;
  int target = -1;
  double targetAt = -1e9;

  /// 0..1 bump over [dur] seconds after [target] was clicked.
  double boost(int t, double now, [double dur = 1.2]) =>
      target == t ? bump(seg(now, targetAt, targetAt + dur)) : 0;

  void hit(int t, double now) {
    target = t;
    targetAt = now;
  }

  /// Clickable areas, refreshed by the painter every frame.
  final targets = <Rect>[];

  /// Handles a tap at [p]: records which target was hit (if any).
  int? click(Offset p, double now) {
    tap = p;
    tapAt = now;
    for (var i = 0; i < targets.length; i++) {
      if (targets[i].contains(p)) {
        hit(i, now);
        return i;
      }
    }
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stick figures
// ─────────────────────────────────────────────────────────────────────────────

/// A worker's pose. Angles are absolute, 0 = pointing down, +π/2 = forward
/// (the way the worker faces), π = up.
class Pose {
  double lean = 0;
  double head = 0;
  double drop = 0; // hip lowered, as a fraction of height
  double bob = 0; // px up
  double thA = 0.12, shA = 0.05, thB = -0.1, shB = -0.1;
  double upA = 0.14, foA = 0.34, upB = -0.1, foB = 0.06;

  void walk(double ph, {double amp = 0.42, bool arms = true}) {
    final sn = math.sin(ph), cs = math.cos(ph);
    thA = amp * sn;
    thB = -amp * sn;
    shA = thA - 0.55 * math.max(0, cs);
    shB = thB - 0.55 * math.max(0, -cs);
    drop = (1 - math.cos(amp * sn)) * 0.48;
    if (arms) {
      upA = -0.45 * sn;
      foA = upA + 0.35;
      upB = 0.45 * sn;
      foB = upB + 0.35;
    }
  }

  void wave(double t) {
    upA = 2.65;
    foA = 3.0 + 0.5 * math.sin(t * 13);
  }

  void cheer(double t, int seed) {
    final w = 0.16 * math.sin(t * 9 + seed);
    upA = 2.75 + w;
    foA = 2.95 + w;
    upB = 2.85 - w;
    foB = 3.05 - w;
    bob = 3 * math.max(0, math.sin(t * 9 + seed));
  }

  void wipe(double t) {
    upA = 2.0;
    foA = 3.75 + 0.22 * math.sin(t * 10);
    head = -0.1;
  }

  /// Arm A straight out towards [angle] (π/2 = forward, 2.2 = up-forward).
  void point(double angle) {
    upA = angle;
    foA = angle + 0.08;
  }

  /// Both arms forward, holding something in front.
  void carry() {
    upA = 1.15;
    foA = 1.45;
    upB = 1.05;
    foB = 1.4;
  }

  /// Hands on the helmet: overwhelmed.
  void overwhelmed(double t) {
    upA = 2.6;
    foA = 4.2 + 0.1 * math.sin(t * 7);
    upB = 2.5;
    foB = 4.1 + 0.1 * math.sin(t * 7 + 1);
    head = 0.12 * math.sin(t * 5);
  }

  /// Sitting on something [seatH] px high, for a worker [h] tall.
  void sit(double h, double seatH) {
    thA = 1.35;
    shA = 0.15;
    thB = 1.25;
    shB = 0.05;
    drop = (0.48 * h - seatH) / h;
  }

  /// Arm B raised to look at a wristwatch.
  void watch() {
    upB = 0.9;
    foB = 2.2;
    head = 0.3;
  }
}

typedef Limbs = ({
  Offset handA,
  Offset handB,
  Offset head,
  Offset elbowA,
  Offset elbowB,
  Offset hip,
});

/// Line-drawing helpers bound to one canvas. [dim] fades everything (the
/// outro's lights going out).
class FactoryInk {
  FactoryInk(this.c, {this.dim = 1});

  final Canvas c;
  double dim;

  static final _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  static final _fill = Paint();

  Color _d(Color col) => dim >= 1 ? col : col.withValues(alpha: col.a * dim);

  Paint st(Color col, [double w = 1.4]) => _stroke
    ..color = _d(col)
    ..strokeWidth = w;
  Paint fl(Color col) =>
      _fill..color = dim >= 1 || col == BP.paper || col == BP.panel ? col : _d(col);

  void box(Rect r, {Color col = BP.line, double w = 1.3, Color fill = BP.panel}) {
    c.drawRect(r, fl(fill));
    c.drawRect(r, st(col, w));
  }

  /// A stick figure standing on [feet], [h] px tall, facing [dir] (±1).
  Limbs worker(
    Offset feet,
    double h,
    int dir,
    Pose f, {
    Color hat = BP.amber,
    Color ink = BP.ink,
    Color back = BP.inkDim,
    bool helmet = true,
  }) {
    Offset v(double a, double len) => Offset(math.sin(a) * dir * len, math.cos(a) * len);
    final hip = feet + Offset(0, -0.48 * h + f.drop * h - f.bob);
    final spine = 0.32 * h;
    final neck = hip + Offset(math.sin(f.lean) * dir * spine, -math.cos(f.lean) * spine);
    final hr = 0.125 * h;
    final ha = f.lean + f.head;
    final up = Offset(math.sin(ha) * dir, -math.cos(ha));
    final head = neck + up * (hr + 0.8);
    final sh = neck - Offset(math.sin(f.lean) * dir, -math.cos(f.lean)) * (0.05 * h);
    final kA = hip + v(f.thA, 0.25 * h), fA = kA + v(f.shA, 0.24 * h);
    final kB = hip + v(f.thB, 0.25 * h), fB = kB + v(f.shB, 0.24 * h);
    final eA = sh + v(f.upA, 0.17 * h), hA = eA + v(f.foA, 0.17 * h);
    final eB = sh + v(f.upB, 0.17 * h), hB = eB + v(f.foB, 0.17 * h);
    final w = h < 30 ? 1.5 : 1.8;
    c.drawPath(
      Path()
        ..moveTo(hip.dx, hip.dy)
        ..lineTo(kB.dx, kB.dy)
        ..lineTo(fB.dx, fB.dy)
        ..moveTo(sh.dx, sh.dy)
        ..lineTo(eB.dx, eB.dy)
        ..lineTo(hB.dx, hB.dy),
      st(back, w),
    );
    c.drawPath(
      Path()
        ..moveTo(fA.dx, fA.dy)
        ..lineTo(kA.dx, kA.dy)
        ..lineTo(hip.dx, hip.dy)
        ..lineTo(neck.dx, neck.dy)
        ..moveTo(sh.dx, sh.dy)
        ..lineTo(eA.dx, eA.dy)
        ..lineTo(hA.dx, hA.dy),
      st(ink, w),
    );
    c.drawCircle(head, hr, fl(BP.paper));
    c.drawCircle(head, hr, st(ink, w * 0.85));
    if (helmet) {
      final top = math.atan2(up.dy, up.dx);
      c.drawArc(
        Rect.fromCircle(center: head, radius: hr + 0.9),
        top - math.pi / 2,
        math.pi,
        true,
        fl(hat),
      );
      final fwd = Offset(-up.dy, up.dx) * dir.toDouble();
      c.drawLine(head - fwd * (hr + 0.6), head + fwd * (hr + 3.2), st(hat, 1.5));
    }
    return (handA: hA, handB: hB, head: head, elbowA: eA, elbowB: eB, hip: hip);
  }

  // ── The tour group ────────────────────────────────────────────────────────

  /// The guide (green helmet, flag) followed by three visitors (blue
  /// helmets). [x] is the guide's feet; the group trails behind [dir].
  /// [walk] ≥ 0 is the walk phase; < 0 stands. [pointing] 0..1 raises the
  /// guide's arm towards what's being shown. [wave] makes visitors wave.
  void tourGroup(
    double x,
    double floor,
    double t, {
    int dir = 1,
    double walk = -1,
    double pointing = 0,
    double h = 30,
    bool look = false,
    Offset? mouse,
  }) {
    // Visitors, back to front.
    for (var i = 3; i >= 1; i--) {
      final vx = x - dir * (i * h * 0.95 + (i == 3 ? 4 : 0));
      final f = Pose();
      if (walk >= 0) {
        f.walk(walk + i * 1.7, amp: 0.36);
      } else {
        // Idle: small shifts; one takes a photo, one looks up.
        final ep = (t / 5).floor();
        final r = rnd(ep, i, 17);
        if (i == 2 && r < 0.45) {
          f
            ..upA = 1.9
            ..foA = 2.9
            ..upB = 1.8
            ..foB = 2.8
            ..head = -0.1;
        } else if (i == 1 && look) {
          f.head = -0.35 - 0.05 * math.sin(t);
        } else if (r > 0.8) {
          f.head = 0.25;
        }
      }
      final feet = Offset(vx, floor);
      if (mouse != null && (mouse - feet.translate(0, -h * 0.55)).distance < h * 0.7) f.wave(t);
      final g = worker(feet, h * 0.92, dir, f, hat: BP.line, ink: BP.inkDim, back: BP.inkFaint);
      if (i == 2 && walk < 0 && rnd((t / 5).floor(), i, 17) < 0.45) {
        // A camera, with the occasional flash.
        final cam = Rect.fromCenter(center: g.handA + Offset(dir * 2.0, -2), width: 7, height: 5);
        c.drawRect(cam, fl(BP.panel));
        c.drawRect(cam, st(BP.inkDim, 1));
        if ((t * 0.7 + 0.3) % 5 < 0.12) star(cam.center, 6, BP.ink);
      }
    }
    // The guide.
    final f = Pose();
    if (walk >= 0) {
      f.walk(walk, amp: 0.4);
    }
    f
      ..upB = 2.65
      ..foB = 2.85;
    if (pointing > 0) {
      f.point(lerp(f.upA, 1.9, pointing));
    }
    final feet = Offset(x, floor);
    if (mouse != null && (mouse - feet.translate(0, -h * 0.55)).distance < h * 0.7) f.wave(t);
    final g = worker(feet, h, dir, f, hat: BP.green);
    flag(g.handB, t, color: BP.green);
  }

  /// A small pennant on a pole held at [hand].
  void flag(Offset hand, double t, {Color color = BP.green}) {
    final top = hand + const Offset(0, -20);
    c.drawLine(hand + const Offset(0, 4), top, st(BP.inkDim, 1.2));
    final w = math.sin(t * 5) * 1.5;
    final p = Path()
      ..moveTo(top.dx, top.dy)
      ..quadraticBezierTo(top.dx + 6, top.dy + 1 + w, top.dx + 12, top.dy + 3 + w)
      ..lineTo(top.dx, top.dy + 8)
      ..close();
    c.drawPath(p, fl(color.withValues(alpha: 0.35)));
    c.drawPath(p, st(color, 1.1));
  }

  // ── Tools & props ─────────────────────────────────────────────────────────

  void shovel(Offset back, Offset front, double ext) {
    final d = front - back;
    final n = d.distance;
    if (n < 0.1) return;
    final u = d / n;
    final tip = front + u * ext;
    c.drawLine(back - u * 3, tip, st(BP.inkDim, 1.3));
    final pp = Offset(-u.dy, u.dx);
    final blade = Path()
      ..moveTo(tip.dx + pp.dx * 4, tip.dy + pp.dy * 4)
      ..lineTo(tip.dx + u.dx * 7 + pp.dx * 3, tip.dy + u.dy * 7 + pp.dy * 3)
      ..lineTo(tip.dx + u.dx * 7 - pp.dx * 3, tip.dy + u.dy * 7 - pp.dy * 3)
      ..lineTo(tip.dx - pp.dx * 4, tip.dy - pp.dy * 4)
      ..close();
    c.drawPath(blade, fl(BP.panel));
    c.drawPath(blade, st(BP.line, 1.1));
  }

  void hammer(Offset elbow, Offset hand) {
    final d = hand - elbow;
    final n = d.distance;
    if (n < 0.1) return;
    final u = d / n;
    final end = hand + u * 7;
    c.drawLine(hand, end, st(BP.inkDim, 1.4));
    final pp = Offset(-u.dy, u.dx);
    c.drawLine(end - pp * 3.5, end + pp * 3.5, st(BP.line, 3));
  }

  void coffee(Offset hand, double t) {
    final r = Rect.fromLTWH(hand.dx - 1, hand.dy - 5, 5, 6);
    c.drawRect(r, fl(BP.panel));
    c.drawRect(r, st(BP.ink, 1));
    for (var i = 0; i < 2; i++) {
      final ph0 = t * 2 + i * 1.7;
      final p = Path()..moveTo(r.center.dx + i * 2 - 1, r.top - 2);
      for (var k = 1; k <= 6; k++) {
        p.lineTo(r.center.dx + i * 2 - 1 + math.sin(ph0 + k * 0.9) * 1.6, r.top - 2 - k * 2);
      }
      c.drawPath(p, st(BP.inkDim.withValues(alpha: 0.7), 0.9));
    }
  }

  void clipboard(Offset hand, {bool done = false}) {
    final r = Rect.fromLTWH(hand.dx - 2, hand.dy - 9, 8, 11);
    c.drawRect(r, fl(BP.panel));
    c.drawRect(r, st(BP.ink, 1));
    for (var i = 0; i < 3; i++) {
      c.drawLine(
        Offset(r.left + 2, r.top + 3 + i * 2.5),
        Offset(r.right - 2, r.top + 3 + i * 2.5),
        st(BP.inkDim, 0.7),
      );
    }
    if (done) {
      c.drawPath(
        Path()
          ..moveTo(r.left + 2, r.bottom - 3)
          ..lineTo(r.left + 3.5, r.bottom - 1.5)
          ..lineTo(r.right - 1, r.bottom - 5),
        st(BP.green, 1),
      );
    }
  }

  void magnifier(Offset hand, Offset elbow) {
    final d = hand - elbow;
    final n = d.distance;
    if (n < 0.1) return;
    final lens = hand + d / n * 6;
    c.drawLine(hand, lens, st(BP.inkDim, 1.2));
    c.drawCircle(lens, 3.4, fl(BP.line.withValues(alpha: 0.25)));
    c.drawCircle(lens, 3.4, st(BP.line, 1.1));
  }

  void broom(Offset hand, Offset elbow, double floor, double sweep) {
    final foot = Offset(hand.dx + sweep, floor - 1);
    c.drawLine(Offset.lerp(elbow, hand, 0.4)!, foot, st(BP.inkDim, 1.3));
    final bristles = Path();
    for (var i = -3; i <= 3; i++) {
      bristles
        ..moveTo(foot.dx + i * 1.4, foot.dy - 4)
        ..lineTo(foot.dx + i * 2.2, foot.dy);
    }
    c.drawPath(bristles, st(BP.line, 1));
  }

  void flashlight(Offset hand, int dir, double t, {double reach = 90}) {
    final tip = hand + Offset(dir * 6.0, -1);
    c.drawLine(hand, tip, st(BP.ink, 2.4));
    final a = 0.25 + 0.08 * math.sin(t * 1.3);
    final beam = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx + dir * reach, tip.dy + reach * math.tan(a) - 18)
      ..lineTo(tip.dx + dir * reach, tip.dy + reach * math.tan(a) + 18)
      ..close();
    c.drawPath(beam, fl(BP.amber.withValues(alpha: 0.10)));
  }

  /// A hand cart with [boxes] parcels, pushed from [hand] (or parked).
  void cart(Offset at, int dir, int boxes, double roll, Offset? hand) {
    final body = Rect.fromLTRB(at.dx - 15, at.dy - 17, at.dx + 15, at.dy - 7);
    for (var i = 0; i < boxes; i++) {
      final b = Rect.fromLTWH(body.left + 2 + i * 9.0, body.top - 8, 8, 8);
      c.drawRect(b, fl(BP.panel));
      c.drawRect(b, st(BP.amber, 1));
      c.drawLine(b.topLeft, b.bottomRight, st(BP.amber.withValues(alpha: 0.6), 0.8));
    }
    c.drawRect(body, fl(BP.panel));
    c.drawRect(body, st(BP.line, 1.2));
    final grip = Offset(at.dx - dir * 15, body.top);
    c.drawLine(grip, hand ?? grip + Offset(-dir * 5.0, -9), st(BP.line, 1.2));
    for (final wx in [at.dx - 9, at.dx + 9]) {
      final w = Offset(wx, at.dy - 4);
      c.drawCircle(w, 4, fl(BP.panel));
      c.drawCircle(w, 4, st(BP.line, 1.1));
      c.drawLine(w, w + Offset(math.cos(roll), math.sin(roll)) * 4, st(BP.line, 1));
    }
  }

  /// A forklift facing [dir] with its fork at [lift] px up; returns the fork
  /// tip (where a load sits).
  Offset forklift(
    Offset at,
    int dir,
    double lift,
    double roll, {
    Color col = BP.line,
    Pose? driver,
    double t = 0,
  }) {
    final d = dir.toDouble();
    final body = Rect.fromCenter(center: at + Offset(-d * 4, -16), width: 40, height: 18);
    c.drawRect(body, fl(BP.panel));
    c.drawRect(body, st(col, 1.3));
    // Cab frame.
    final cabBack = at.dx - d * 20, cabFront = at.dx + d * 8;
    c.drawLine(
      Offset(cabBack + d * 2, body.top),
      Offset(cabBack + d * 4, body.top - 22),
      st(col, 1.3),
    );
    c.drawLine(Offset(cabFront, body.top), Offset(cabFront - d * 2, body.top - 22), st(col, 1.3));
    c.drawLine(
      Offset(cabBack + d * 2, body.top - 22),
      Offset(cabFront + d * 2, body.top - 22),
      st(col, 1.5),
    );
    // Driver.
    final p = driver ?? (Pose()..sit(20, 6));
    if (driver == null) {
      p
        ..upA = 1.3
        ..foA = 1.6;
    }
    worker(Offset(at.dx - d * 6, body.top + 2), 20, dir, p);
    // Mast and fork.
    final mx = at.dx + d * 18;
    c.drawLine(Offset(mx, at.dy - 4), Offset(mx, at.dy - 52), st(col, 1.6));
    final fy = at.dy - 5 - lift;
    c.drawLine(Offset(mx, fy), Offset(mx + d * 22, fy), st(BP.amber, 2));
    c.drawLine(Offset(mx, fy), Offset(mx, fy - 10), st(BP.amber, 2));
    // Wheels.
    for (final (wx, r) in [(at.dx - d * 14, 6.0), (at.dx + d * 10, 5.0)]) {
      final w = Offset(wx, at.dy - r);
      c.drawCircle(w, r, fl(BP.panel));
      c.drawCircle(w, r, st(col, 1.2));
      c.drawLine(w, w + Offset(math.cos(roll), math.sin(roll)) * r, st(col, 1));
    }
    return Offset(mx + d * 11, fy);
  }

  void sweat(Offset head, double age, int dir) {
    for (var i = 0; i < 3; i++) {
      final q = age * 1.5 + i / 3;
      final a = q - q.floorToDouble();
      final p = head + Offset(-dir * (3 + a * 9 + i), -3 + 14 * a * a - 7 * math.sin(a * math.pi));
      c.drawCircle(p, 0.6 + 1.1 * (1 - a), fl(BP.line.withValues(alpha: 1 - a)));
    }
  }

  /// Rising "z z z", drawn as strokes.
  void zees(Offset head, double age, int dir) {
    for (var i = 0; i < 3; i++) {
      final q = age * 0.6 + i / 3;
      final a = q - q.floorToDouble();
      final o = Offset(head.dx + dir * (6 + a * 12), head.dy - 8 - a * 22);
      final s = 2.4 + a * 2.2;
      c.drawPath(
        Path()
          ..moveTo(o.dx - s, o.dy - s)
          ..lineTo(o.dx + s, o.dy - s)
          ..lineTo(o.dx - s, o.dy + s)
          ..lineTo(o.dx + s, o.dy + s),
        st(BP.inkDim.withValues(alpha: 1 - a * 0.7), 1),
      );
    }
  }

  /// A "!" bubble over a worker's head.
  void alarm(Offset head, double t) {
    final o = head + const Offset(0, -16);
    final k = 1 + 0.15 * math.sin(t * 12);
    c.drawCircle(o, 6 * k, fl(BP.red.withValues(alpha: 0.18)));
    c.drawCircle(o, 6 * k, st(BP.red, 1.1));
    c.drawLine(o + const Offset(0, -3), o + const Offset(0, 0.8), st(BP.red, 1.5));
    c.drawCircle(o + const Offset(0, 3), 0.9, fl(BP.red));
  }

  void sparks(Offset o, double age, int seed) {
    if (age < 0 || age > 1) return;
    final p = Path();
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 + (rnd(seed, i) - 0.5) * 2.6;
      final sp = 10 + 16 * rnd(seed, i, 2);
      final d0 = sp * age, d1 = d0 + 4 * (1 - age) + 1;
      final g = 14 * age * age;
      p
        ..moveTo(o.dx + math.cos(a) * d0, o.dy + math.sin(a) * d0 + g)
        ..lineTo(o.dx + math.cos(a) * d1, o.dy + math.sin(a) * d1 + g);
    }
    c.drawPath(p, st(BP.amber.withValues(alpha: 1 - age * 0.8), 1.3));
  }

  void puff(Offset o, double age, double r0, double r1, [Color col = BP.inkDim]) {
    if (age <= 0 || age >= 1) return;
    c.drawCircle(o, lerp(r0, r1, eo(age)), st(col.withValues(alpha: col.a * 0.8 * (1 - age)), 1));
  }

  /// A plume of puffs rising from [o]: one every [per] s, each living [life] s.
  /// Only puffs emitted in [0, until] are drawn (so a plume can stop).
  void steam(
    Offset o,
    double t, {
    double per = 0.5,
    double life = 2.4,
    double rise = 40,
    double r = 10,
    Color col = BP.inkDim,
    int seed = 0,
    double drift = 10,
    double until = double.infinity,
  }) {
    for (var n = ((t - life) / per).floor(); n <= (t / per).floor(); n++) {
      if (n * per > until) break;
      final age = (t - n * per) / life;
      if (age <= 0 || age >= 1) continue;
      final p = Offset(
        o.dx + (drift * rnd(n, seed, 41)) * age + 3 * math.sin(age * 6 + n),
        o.dy - rise * age,
      );
      puff(p, age, 3, r + 4 * rnd(n, seed, 42), col);
    }
  }

  void star(Offset o, double r, Color col) {
    final k = r * 0.4;
    c.drawPath(
      Path()
        ..moveTo(o.dx - r, o.dy)
        ..lineTo(o.dx + r, o.dy)
        ..moveTo(o.dx, o.dy - r)
        ..lineTo(o.dx, o.dy + r)
        ..moveTo(o.dx - k, o.dy - k)
        ..lineTo(o.dx + k, o.dy + k)
        ..moveTo(o.dx + k, o.dy - k)
        ..lineTo(o.dx - k, o.dy + k),
      st(col, 1.2),
    );
  }

  void lamp(Offset p, Color col, bool on, [double r = 4.5]) {
    c.drawCircle(p, r, st(BP.lineDim, 1));
    if (on) c.drawCircle(p, r - 1, fl(col));
  }

  /// A round gauge with [value] 0..1 on a 250° dial.
  void gauge(Offset o, double r, double value, {Color needle = BP.amber, Color rim = BP.line}) {
    c.drawCircle(o, r, fl(BP.panel));
    c.drawCircle(o, r, st(rim, 1.2));
    for (var i = 0; i <= 6; i++) {
      final a = math.pi * (0.8 + i * 0.233);
      c.drawLine(
        o + Offset(math.cos(a), math.sin(a)) * (r * 0.72),
        o + Offset(math.cos(a), math.sin(a)) * (r * 0.92),
        st(BP.lineDim, 1),
      );
    }
    final a = math.pi * (0.8 + 1.4 * c01(value));
    c.drawLine(o, o + Offset(math.cos(a), math.sin(a)) * (r * 0.78), st(needle, 1.4));
    c.drawCircle(o, 1.6, fl(needle));
  }

  /// A hand wheel valve.
  void valve(Offset o, double r, double angle, {Color col = BP.line}) {
    c.drawCircle(o, r, st(col, 1.2));
    for (var i = 0; i < 3; i++) {
      final a = angle + i * math.pi / 3;
      final d = Offset(math.cos(a), math.sin(a)) * r;
      c.drawLine(o - d, o + d, st(col, 1));
    }
  }

  /// A hanging lamp: cable from [top], shade at [shade], light cone down to
  /// [floor] with brightness [on] 0..1.
  void hangingLamp(Offset top, double shadeY, double floor, double on, {double spread = 70}) {
    final s = Offset(top.dx, shadeY);
    c.drawLine(top, s, st(BP.lineDim, 1));
    if (on > 0.01) {
      final cone = Path()
        ..moveTo(s.dx - 9, s.dy + 8)
        ..lineTo(s.dx + 9, s.dy + 8)
        ..lineTo(s.dx + spread, floor)
        ..lineTo(s.dx - spread, floor)
        ..close();
      c.drawPath(cone, fl(BP.amber.withValues(alpha: 0.05 * on)));
    }
    final shade = Path()
      ..moveTo(s.dx - 4, s.dy)
      ..lineTo(s.dx + 4, s.dy)
      ..lineTo(s.dx + 11, s.dy + 8)
      ..lineTo(s.dx - 11, s.dy + 8)
      ..close();
    c.drawPath(shade, fl(BP.panel));
    c.drawPath(shade, st(BP.line, 1.2));
    c.drawArc(
      Rect.fromCenter(center: Offset(s.dx, s.dy + 8), width: 10, height: 8),
      0,
      math.pi,
      false,
      on > 0.05 ? fl(BP.amber.withValues(alpha: 0.4 + 0.6 * on)) : st(BP.lineDim, 1),
    );
  }

  /// Gantry rail (an I-beam hung from the ceiling) across [x0, x1] at [y].
  void rail(double x0, double x1, double y, {List<double> hangers = const []}) {
    for (final x in hangers) {
      c.drawLine(Offset(x, 0), Offset(x, y - 2), st(BP.lineDim, 1));
      c.drawRect(Rect.fromLTWH(x - 8, y - 5, 16, 5), st(BP.lineDim, 1));
    }
    box(Rect.fromLTRB(x0, y, x1, y + 16), w: 1.2);
    c.drawLine(Offset(x0, y + 4), Offset(x1, y + 4), st(BP.lineDim, 1));
    c.drawLine(Offset(x0, y + 12), Offset(x1, y + 12), st(BP.lineDim, 1));
    final rivets = <Offset>[for (var x = x0 + 16; x < x1 - 8; x += 48) Offset(x, y + 8)];
    c.drawPoints(ui.PointMode.points, rivets, st(BP.lineDim, 2.4));
  }

  /// A hatched floor line.
  void floor(double x0, double x1, double y, {Color col = BP.line}) {
    c.drawLine(Offset(x0, y), Offset(x1, y), st(col, 1.4));
    final hatch = Path();
    for (var x = x0 + 6; x < x1; x += 12) {
      hatch
        ..moveTo(x, y)
        ..lineTo(x - 7, y + 8);
    }
    c.drawPath(hatch, st(BP.lineFaint, 1));
  }

  static final _pix = Paint()..filterQuality = FilterQuality.none;

  /// Draws [img] as big square pixels, centred in [box] (integer scale when
  /// it fits), with a faint pixel grid. Returns the pixel rect.
  Rect pixels(ui.Image img, Rect box, {bool grid = true, double opacity = 1}) {
    final iw = img.width.toDouble(), ih = img.height.toDouble();
    var s = math.min(box.width / iw, box.height / ih);
    if (s > 2) s = s.floorToDouble();
    final dst = Rect.fromCenter(center: box.center, width: iw * s, height: ih * s);
    _pix.color = Color.fromRGBO(0, 0, 0, opacity * (dim < 1 ? dim : 1));
    c.drawImageRect(img, Rect.fromLTWH(0, 0, iw, ih), dst, _pix);
    if (grid && s >= 3) {
      final g = Path();
      for (var x = 0; x <= img.width; x++) {
        g
          ..moveTo(dst.left + x * s, dst.top)
          ..lineTo(dst.left + x * s, dst.bottom);
      }
      for (var y = 0; y <= img.height; y++) {
        g
          ..moveTo(dst.left, dst.top + y * s)
          ..lineTo(dst.right, dst.top + y * s);
      }
      c.drawPath(g, st(BP.lineFaint.withValues(alpha: 0.8 * opacity), 0.6));
    }
    return dst;
  }

  /// A crate: outlined box with a label strip on top.
  void crate(Rect r, Color col, {TextPainter? stamp, double w = 1.2}) {
    c.drawRect(r, fl(BP.panel));
    c.drawRect(r, st(col, w));
    final strip = r.top + math.min(10, r.height * 0.3);
    c.drawLine(Offset(r.left, strip), Offset(r.right, strip), st(col.withValues(alpha: 0.5), 0.8));
    if (stamp != null) paintFit(stamp, Rect.fromLTRB(r.left + 3, r.top + 1, r.right - 3, strip));
  }

  /// Paints [p] centred in [box], shrunk to fit its width (and height if
  /// [fitHeight]).
  void paintFit(TextPainter p, Rect box, {bool fitHeight = false, double maxScale = 1}) {
    var k = math.min(maxScale, box.width / math.max(1, p.width));
    if (fitHeight) k = math.min(k, box.height / math.max(1, p.height));
    c.save();
    c.translate(box.center.dx, box.center.dy);
    c.scale(k);
    p.paint(c, Offset(-p.width / 2, -p.height / 2));
    c.restore();
  }

  /// A conveyor: belt surface [top]..[top]+[h], slats scrolling by [shift],
  /// rollers and legs down to [floorY].
  void conveyor(
    double x0,
    double x1,
    double top,
    double floorY,
    double shift, {
    double h = 10,
    double legEvery = 180,
    Color col = BP.line,
  }) {
    c.drawRect(Rect.fromLTRB(x0, top, x1, top + h), fl(BP.panel));
    final slats = Path();
    const gap = 18.0;
    for (var x = x0 + 4 + shift % gap; x < x1 - 2; x += gap) {
      slats
        ..moveTo(x, top + 1)
        ..lineTo(x - 4, top + h - 1);
    }
    c.drawPath(slats, st(BP.lineFaint, 1));
    c.drawLine(Offset(x0, top), Offset(x1, top), st(col, 1.3));
    c.drawLine(Offset(x0, top + h), Offset(x1, top + h), st(col, 1.3));
    c.drawCircle(Offset(x0, top + h / 2), h / 2, st(col, 1.1));
    c.drawCircle(Offset(x1, top + h / 2), h / 2, st(col, 1.1));
    final legs = Path();
    final n = math.max(1, ((x1 - x0) / legEvery).round());
    for (var i = 0; i <= n; i++) {
      final x = lerp(x0 + 12, x1 - 12, i / n);
      legs
        ..moveTo(x - 3, top + h)
        ..lineTo(x - 3, floorY)
        ..moveTo(x + 3, top + h)
        ..lineTo(x + 3, floorY)
        ..moveTo(x - 8, floorY - 1)
        ..lineTo(x + 8, floorY - 1);
    }
    c.drawPath(legs, st(BP.lineDim, 1.2));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// A full-bleed scene: one ticker, one painter, hover + click targets.
// ─────────────────────────────────────────────────────────────────────────────

typedef ScenePainter = CustomPainter Function(SceneClock clock, TextCache text, SceneInput io);

class FactoryScene extends StatefulWidget {
  const FactoryScene({super.key, required this.painter, this.onTarget});

  final ScenePainter painter;

  /// Called with the index of a clicked target (after it has been recorded).
  final void Function(BuildContext context, int target)? onTarget;

  @override
  State<FactoryScene> createState() => _FactorySceneState();
}

class _FactorySceneState extends State<FactoryScene> {
  final _text = TextCache();
  final _io = SceneInput();
  SceneClock? _clock;
  bool _over = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _over ? SystemMouseCursors.click : MouseCursor.defer,
      onHover: (e) {
        _io.mouse = e.localPosition;
        final over = _io.targets.any((r) => r.contains(e.localPosition));
        if (over != _over) setState(() => _over = over);
      },
      onExit: (_) {
        _io.mouse = null;
        if (_over) setState(() => _over = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final i = _io.click(d.localPosition, _clock?.local ?? 0);
          if (i != null) widget.onTarget?.call(context, i);
        },
        child: SceneTicker(
          builder: (context, clock) {
            _clock = clock;
            return CustomPaint(size: Size.infinite, painter: widget.painter(clock, _text, _io));
          },
        ),
      ),
    );
  }
}
