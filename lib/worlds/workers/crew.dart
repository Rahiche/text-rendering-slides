import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The crew: tiny line-drawn workers shared by the title ("easy vs hard") and
// every scene of the workers world. A [Worker] is a pose description (where,
// facing, doing what, holding what); [poseWorker] solves the joints (simple
// two-bone IK) and [CrewPainter] draws it with its props and effects.
// ─────────────────────────────────────────────────────────────────────────────

double _seg(double t, double a, double b) =>
    b <= a ? (t >= b ? 1.0 : 0.0) : ((t - a) / (b - a)).clamp(0.0, 1.0);
double _eo(double x) => 1 - math.pow(1 - x, 3).toDouble();
double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Deterministic hash → [0, 1). Float based so web and native agree.
double _h(num a, [num b = 0, num c = 0]) {
  final s = math.sin(a * 12.9898 + b * 78.233 + c * 37.719) * 43758.5453;
  return s - s.floorToDouble();
}

Paint inkStroke(Color c, double w, [double a = 1]) => Paint()
  ..color = c.withValues(alpha: c.a * a)
  ..strokeWidth = w
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

Paint inkFill(Color c, [double a = 1]) => Paint()..color = c.withValues(alpha: c.a * a);

// ── Motion helpers (public, for the world's scenes) ─────────────────────────

/// 0..1 progress of [t] through [a, b].
double span(double t, double a, double b) => _seg(t, a, b);
double easeOut3(double x) => _eo(x.clamp(0.0, 1.0));
double easeInOut3(double x) {
  final v = x.clamp(0.0, 1.0);
  return v < 0.5 ? 4 * v * v * v : 1 - math.pow(-2 * v + 2, 3).toDouble() / 2;
}

double backOut(double x) {
  const c1 = 1.70158;
  const c3 = c1 + 1;
  return 1 + c3 * math.pow(x - 1, 3) + c1 * math.pow(x - 1, 2);
}

double mix(double a, double b, double t) => _lerp(a, b, t);

/// Deterministic hash → [0, 1).
double hash01(num a, [num b = 0, num c = 0]) => _h(a, b, c);

/// Walk from [x0] (starting at [t0]) to [x1] at speed [v]: position and
/// heading (0 once arrived).
(double, double) walkTo(double t, double t0, double x0, double x1, double v) {
  if (t <= t0) return (x0, 0);
  final d = x1 - x0;
  final dur = d.abs() / v;
  if (t >= t0 + dur) return (x1, 0);
  return (x0 + d.sign * v * (t - t0), d.sign);
}

/// When a walk that starts at [t0] from [x0] reaches [x1] at speed [v].
double arrival(double t0, double x0, double x1, double v) => t0 + (x1 - x0).abs() / v;

/// Makes the free worker nearest to [pointer] wave.
void waveNearest(List<Worker> crew, Offset? pointer, {double reach = 24}) {
  if (pointer == null) return;
  Worker? best;
  var bd = reach;
  for (final g in crew) {
    if (!g.free || g.p == Pose.carry || g.p == Pose.shoulder || g.p == Pose.ladder || g.p == Pose.lie) continue;
    final d = (Offset(g.x, g.y - 16 * g.scale) - pointer).distance;
    if (d < bd) {
      bd = d;
      best = g;
    }
  }
  best?.wave = true;
}

// ── Scene plumbing ──────────────────────────────────────────────────────────

/// A clock shared by every workers-world scene: the crews keep working
/// across slide changes instead of restarting.
final Stopwatch crewWatch = Stopwatch()..start();
double get crewSeconds => crewWatch.elapsedMicroseconds / 1e6;

/// Scene time for one scene. [t] runs faster for a moment after [rush].
class SceneClock extends ChangeNotifier {
  double t = 0;
  double real = 0;
  double rushAt = -99;
  double tapAt = -99;
  Offset? pointer;
  Offset? tapPos;

  /// 0..1: how hurried the crew is right now.
  double get hurry {
    final a = real - rushAt;
    if (a < 0 || a > 3.0) return 0;
    return _seg(a, 0, 0.25) * (1 - _seg(a, 2.4, 3.0));
  }

  void advance(double dt) {
    real += dt;
    t += dt * (1 + 2.0 * hurry);
    notifyListeners();
  }

  void rush() => rushAt = real - (hurry > 0.99 ? 0.25 : 0);

  /// Repaint now (e.g. after fonts changed).
  void poke() => notifyListeners();

  void tap(Offset p) {
    tapAt = real;
    tapPos = p;
  }

  /// Seconds since the last tap (large if never).
  double get sinceTap => real - tapAt;
}

/// Cached, disposable text painters for labels and glyphs. Painting code asks
/// for text every frame; this lays each distinct string out once.
class LabelCache {
  final Map<String, TextPainter> _map = {};

  TextPainter get(String key, TextSpan Function() span, {TextDirection dir = TextDirection.ltr}) {
    final hit = _map[key];
    if (hit != null) return hit;
    if (_map.length > 600) clear();
    return _map[key] = TextPainter(text: span(), textDirection: dir)..layout();
  }

  TextPainter mono(String text, double size, Color color, {double weight = 400}) => get(
    'm|$text|$size|${color.toARGB32()}|$weight',
    () => TextSpan(text: text, style: BT.mono(size, color: color, weight: weight)),
  );

  TextPainter display(String text, double size, Color color, {double weight = 500, double? letterSpacing}) => get(
    'd|$text|$size|${color.toARGB32()}|$weight|$letterSpacing',
    () => TextSpan(text: text, style: BT.display(size, color: color, weight: weight, letterSpacing: letterSpacing)),
  );

  /// Sample text in any script; [ja] tags it Japanese (Japanese glyph forms).
  TextPainter sample(String text, double size, Color color, {double weight = 500, bool ja = false}) => get(
    's|$text|$size|${color.toARGB32()}|$weight|$ja',
    () => TextSpan(
      text: text,
      style: BT.sample(size, color: color, weight: weight).copyWith(locale: ja ? const Locale('ja') : null),
    ),
  );

  /// The same sample drawn as an outline (under construction).
  TextPainter outline(String text, double size, Color color, {double weight = 500, double width = 2, bool ja = false}) =>
      get(
        'o|$text|$size|${color.toARGB32()}|$weight|$width|$ja',
        () => TextSpan(
          text: text,
          style: BT.sample(size, weight: weight).copyWith(
            locale: ja ? const Locale('ja') : null,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = width
              ..strokeJoin = StrokeJoin.round
              ..color = color,
          ),
        ),
      );

  void clear() {
    for (final p in _map.values) {
      p.dispose();
    }
    _map.clear();
  }
}

/// Paints [p] with its top-left at [o]; returns its size.
Size paintText(Canvas c, TextPainter p, Offset o) {
  p.paint(c, o);
  return p.size;
}

/// Paints [p] centred horizontally on [x] with its top at [y].
void paintCentered(Canvas c, TextPainter p, double x, double y) => p.paint(c, Offset(x - p.width / 2, y));

/// One ticker, one clock, one label cache, one painter: the host for every
/// scene of the workers world. Hover makes the nearest worker wave (the
/// painter reads [SceneClock.pointer]); [onTap] gets taps.
class SceneHost extends StatefulWidget {
  const SceneHost({
    super.key,
    required this.painter,
    this.onTap,
    this.children = const [],
    this.shared = false,
    this.interactive = true,
  });

  final CustomPainter Function(SceneClock clock, LabelCache labels) painter;
  final void Function(SceneClock clock, Offset p)? onTap;

  /// Widgets laid over the painting (click targets, text fields).
  final List<Widget> children;

  /// Follow the world-wide [crewWatch] instead of starting at 0.
  final bool shared;

  /// Whether the painting itself takes pointer events.
  final bool interactive;

  @override
  State<SceneHost> createState() => _SceneHostState();
}

class _SceneHostState extends State<SceneHost> with SingleTickerProviderStateMixin {
  final _clock = SceneClock();
  final _labels = LabelCache();
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.shared) _clock.t = _clock.real = crewSeconds;
    PaintingBinding.instance.systemFonts.addListener(_onFonts);
    _ticker = createTicker(_tick)..start();
  }

  void _onFonts() {
    _labels.clear();
    _clock.poke();
  }

  void _tick(Duration e) {
    var dt = (e - _last).inMicroseconds / 1e6;
    _last = e;
    if (dt < 0 || dt > 0.1) dt = 1 / 60;
    _clock.advance(dt);
  }

  @override
  void dispose() {
    _ticker.dispose();
    PaintingBinding.instance.systemFonts.removeListener(_onFonts);
    _labels.clear();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paint = RepaintBoundary(
      child: CustomPaint(painter: widget.painter(_clock, _labels), child: const SizedBox.expand()),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: widget.interactive
              ? MouseRegion(
                  onHover: (e) => _clock.pointer = e.localPosition,
                  onExit: (_) => _clock.pointer = null,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) {
                      _clock.tap(d.localPosition);
                      widget.onTap?.call(_clock, d.localPosition);
                    },
                    child: paint,
                  ),
                )
              : IgnorePointer(child: paint),
        ),
        ...widget.children,
      ],
    );
  }
}


enum Pose {
  stand,
  walk,
  run,
  carry,
  shoulder,
  reach,
  toss,
  push,
  pull,
  hammer,
  wrench,
  weld,
  climb,
  climbCarry,
  sit,
  coffee,
  lie,
  lean,
  cheer,
  highFive,
  wipe,
  signal,
  clipboard,
  pole,
  point,
  survey,
  bucket,
  ladder,
  wave2,
  kick,
}

enum Tool { none, cup, wrench, torch, clipboard, hammer, bucket, sign, flag, staff, redFlag }

class Worker {
  Worker(
    this.x,
    this.f,
    this.p, {
    this.y = 0,
    this.ph = 0,
    this.k = 0,
    this.move = false,
    this.id = 0,
    this.item = Tool.none,
    this.aim,
    this.rope,
    this.sweat = false,
    this.itemT = 0,
  });

  double x;
  double f;
  Pose p;
  double y;
  double ph;
  double k;
  bool move;
  int id;
  Tool item;
  Offset? aim;
  Offset? rope;
  bool sweat;
  double itemT;
  Offset? plant; // planted pole base (sign / flag)
  bool wave = false;
  bool visor = false;
  bool alarm = false;
  bool free = true; // may celebrate / wave
  bool fixed = false; // never moves (crane operator)
  double scale = 1; // drawn scaled about its feet
  Color hat = BP.amber; // hard hat colour (a crew's uniform)
  Color? vest; // optional vest colour (a crew's uniform)
  Color ink = BP.ink; // body colour (dimmer for background crews)
  bool _local = false; // aim / plant already mapped into pose space

  Offset hip = Offset.zero, neck = Offset.zero, head = Offset.zero;
  Offset hl = Offset.zero, hr = Offset.zero, fl = Offset.zero, fr = Offset.zero;
  Offset el = Offset.zero, er = Offset.zero, kl = Offset.zero, kr = Offset.zero;
}

Offset _ik(Offset a, Offset b, double l1, double l2, Offset hint) {
  final d = b - a;
  final dist = d.distance;
  if (dist < 1e-4) return a + Offset(0, l1);
  final u = d / dist;
  if (dist >= l1 + l2) return a + u * l1;
  final p = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist);
  final h = math.sqrt(math.max(0, l1 * l1 - p * p));
  var n = Offset(-u.dy, u.dx);
  if (n.dx * hint.dx + n.dy * hint.dy < 0) n = -n;
  return a + u * p + n * h;
}

/// Poses a stick figure: feet on (x, y), ~33 px tall with its hard hat.
void poseWorker(Worker g, double time) {
  // A scaled worker is posed at scale 1 about its feet: map its targets in.
  if (g.scale != 1 && !g._local) {
    Offset? local(Offset? p) => p == null ? null : Offset(g.x + (p.dx - g.x) / g.scale, g.y + (p.dy - g.y) / g.scale);
    g
      ..aim = local(g.aim)
      ..plant = local(g.plant)
      .._local = true;
  }
  final f = g.f;
  final x = g.x;
  var y = g.y;
  final s = math.sin(g.ph), c = math.cos(g.ph);
  var hipH = 13.0;
  var lean = 0.0;
  var fl = Offset(x - 2.6, y), fr = Offset(x + 2.6, y);
  var kneeHint = Offset(f, -0.15);

  void legs(double stride, double lift) {
    fl = Offset(x + f * stride * s, y - lift * math.max(0, c));
    fr = Offset(x - f * stride * s, y - lift * math.max(0, -c));
    hipH += 0.6 * c.abs() - 0.3;
  }

  switch (g.p) {
    case Pose.walk || Pose.bucket || Pose.ladder:
      legs(4.8, 2.4);
      lean = g.p == Pose.bucket ? -0.06 : 0.05;
    case Pose.run:
      legs(7.0, 3.6);
      lean = 0.3;
    case Pose.carry || Pose.shoulder || Pose.toss:
      if (g.move) legs(4.2, 2.0);
      hipH -= 4.5 * g.k;
    case Pose.push:
      lean = 0.55;
      fl = Offset(x - f * (7.5 - 1.5 * s), y);
      fr = Offset(x + f * 1.5, y - 1.4 * math.max(0, s));
    case Pose.pull:
      lean = -0.38;
      fl = Offset(x + f * 5.5, y);
      fr = Offset(x - f * (2.5 + 1.0 * s), y);
    case Pose.hammer || Pose.weld:
      hipH = 7.5;
      lean = 0.18;
      fl = Offset(x - f * 7, y);
      fr = Offset(x + f * 5, y);
    case Pose.climb || Pose.climbCarry:
      lean = 0.1;
      fl = Offset(x + f * 1.5, y - 3 * math.max(0, s));
      fr = Offset(x + f * 1.5, y - 3 * math.max(0, -s));
    case Pose.sit || Pose.coffee:
      hipH = 4.2;
      lean = -0.08;
      fl = Offset(x + f * 10.5, y);
      fr = Offset(x + f * 12.5, y - 0.4);
      kneeHint = const Offset(0, -1);
    case Pose.lie:
      hipH = 3.3 + 0.3 * math.sin(time * 1.8 + g.id);
      lean = math.pi / 2;
      fl = Offset(x - f * 12.5, y - 1.2);
      fr = Offset(x - f * 13.2, y - 3.2);
      kneeHint = const Offset(0, -1);
    case Pose.lean:
      lean = -0.26;
      fl = Offset(x + f * 5.5, y);
      fr = Offset(x + f * 8.2, y);
    case Pose.cheer:
      y -= math.max(0, math.sin(time * 9 + g.id)) * 5;
      fl = Offset(x - 2.8, y + 0.5);
      fr = Offset(x + 2.8, y + 0.5);
    case Pose.highFive:
      y -= math.max(0, math.sin(time * 6 + g.k)) * 2.5;
      fl = Offset(x - 2.6, y);
      fr = Offset(x + 2.6, y);
      lean = 0.08;
    case Pose.wipe:
      lean = 0.12;
    case Pose.survey:
      lean = 0.42;
    case Pose.kick:
      lean = -0.18;
      fl = Offset(x + f * (3 + 9 * g.k), y - 1 - 8 * g.k);
      fr = Offset(x - f * 2, y);
    case Pose.stand ||
        Pose.wave2 ||
        Pose.reach ||
        Pose.wrench ||
        Pose.signal ||
        Pose.clipboard ||
        Pose.pole ||
        Pose.point:
      if (g.p == Pose.wrench) lean = 0.3;
      if (g.move) legs(4.8, 2.4);
  }

  final hip = Offset(x, y - hipH);
  final dir = Offset(math.sin(lean) * f, -math.cos(lean));
  final neck = hip + dir * 9.5;
  final head = neck + dir * 4.7;

  var hl = neck + const Offset(-2.8, 10.2);
  var hr = neck + const Offset(2.8, 10.2);
  var hintL = Offset(-f * 0.5, 1);
  var hintR = Offset(-f * 0.5, 1);

  switch (g.p) {
    case Pose.walk:
      hl = neck + Offset(-f * 3.8 * s, 10.2);
      hr = neck + Offset(f * 3.8 * s, 10.2);
    case Pose.run:
      hl = neck + Offset(f * (2 - 4.5 * s), 6.5);
      hr = neck + Offset(f * (2 + 4.5 * s), 6.5);
      hintL = hintR = Offset(-f, 0.6);
    case Pose.carry || Pose.climbCarry:
      hl = neck + const Offset(-2.6, -9.4);
      hr = neck + const Offset(2.6, -9.4);
      hintL = const Offset(-1, 0.2);
      hintR = const Offset(1, 0.2);
    case Pose.shoulder:
      hr = neck + Offset(f * 1.2, -7.5);
      hl = neck + Offset(-f * 3.8 * s * (g.move ? 1 : 0), 10.2);
      hintR = Offset(f, 0.3);
    case Pose.reach:
      final a = g.aim ?? neck + Offset(f * 6, -9);
      final d = a - neck;
      hr = neck + d / math.max(1, d.distance) * 11;
      hintR = Offset(f, 0.4);
    case Pose.toss:
      final k = g.itemT;
      hr = neck + Offset(f * (1.2 + 8 * k), -7.5 + 2 * k);
      hintR = Offset(f * -0.3, 1);
    case Pose.push:
      hl = neck + Offset(f * 9.5, 1.5);
      hr = neck + Offset(f * 9.5, 3.5);
      hintL = hintR = const Offset(0, 1);
    case Pose.pull:
      hl = neck + Offset(f * 9.2, 3.5 + 1.2 * s);
      hr = neck + Offset(f * 8.2, 4.5 + 1.2 * s);
      hintL = hintR = const Offset(0, 1);
    case Pose.hammer:
      final sw = 0.5 + 0.5 * s;
      final th = _lerp(-2.1, 0.45, sw * sw);
      hr = neck + Offset(f * math.cos(th) * 10.5, math.sin(th) * 10.5);
      hl = neck + Offset(f * 4, 8.5);
      hintR = Offset(-f * 0.3, 1);
    case Pose.wrench:
      final a = g.aim ?? neck + Offset(f * 16, 6);
      final ang = -0.5 + 0.55 * s;
      final end = a + Offset(-f * 15 * math.cos(ang), 15 * math.sin(ang));
      hr = end;
      hl = end + Offset(f * 2.8, 0.6);
      hintL = hintR = const Offset(0, 1);
    case Pose.weld:
      final a = g.aim ?? neck + Offset(f * 12, 8);
      hr = a - Offset(f * 7, 1);
      hl = hr + Offset(-f * 2, 2);
      hintL = hintR = const Offset(0, 1);
    case Pose.climb:
      hl = neck + Offset(f * 3, -6.5 + 3 * s);
      hr = neck + Offset(f * 3, -6.5 - 3 * s);
      hintL = hintR = Offset(-f, 0.5);
    case Pose.sit:
      hl = neck + Offset(f * 6.5, 6);
      hr = neck + Offset(f * 7.5, 7);
    case Pose.coffee:
      final sip = _seg(math.sin(time * 1.1 + g.id), 0.55, 0.9);
      hr = Offset.lerp(neck + Offset(f * 6.5, 5.5), head + Offset(f * 3.2, 1.8), sip)!;
      hl = neck + Offset(f * 6, 7.5);
      g.k = sip;
    case Pose.lie:
      hl = neck + Offset(-f * 6, 1.8);
      hr = neck + Offset(-f * 3.5, -1.6);
      hintL = hintR = const Offset(0, -1);
    case Pose.lean:
      if (g.k > 0.5) {
        hr = neck + Offset(f * 6.5, 0.2);
        hl = hr + Offset(-f * 1.2, 1.6);
        hintR = hintL = const Offset(0, 1);
      } else {
        hl = neck + Offset(f * 3.2, 5.5);
        hr = neck + Offset(f * 2.4, 4.4);
      }
    case Pose.cheer:
      hl = neck + const Offset(-4, -9.8);
      hr = neck + const Offset(4, -9.8);
      hintL = const Offset(-1, 0);
      hintR = const Offset(1, 0);
    case Pose.highFive:
      hr = g.aim ?? neck + Offset(f * 6, -9.2);
      hintR = Offset(-f, 0.2);
    case Pose.wipe:
      hr = head + Offset(f * (0.8 + 2.4 * math.sin(time * 7 + g.id)), -1.8);
      hintR = Offset(f, 0.5);
    case Pose.signal:
      hl = neck + Offset(-5, -2 + 6 * s);
      hr = neck + Offset(5, -2 - 6 * s);
      hintL = const Offset(-1, 0.2);
      hintR = const Offset(1, 0.2);
    case Pose.clipboard:
      hl = neck + Offset(f * 5.5, 5);
      hr = neck + Offset(f * (6.2 + 1.3 * math.sin(time * 11)), 3.6 + 0.8 * math.cos(time * 8));
    case Pose.wave2:
      hl = Offset(g.plant?.dx ?? neck.dx + f * 4.5, neck.dy + 2);
      hr = neck + Offset(-f * 3 + 3.2 * math.sin(time * 14), -10.4);
      hintR = Offset(-f, 0);
    case Pose.pole:
      hl = neck + Offset(f * 4.5, -1.5);
      hr = neck + Offset(f * 4.5, 5.5);
      if (g.plant != null) {
        hl = Offset(g.plant!.dx, neck.dy - 1.5);
        hr = Offset(g.plant!.dx, neck.dy + 5.5);
      }
    case Pose.point:
      final a = g.aim;
      if (a != null) {
        final d = a - neck;
        hr = neck + d / math.max(1, d.distance) * 11;
      }
      hintR = const Offset(0, 1);
    case Pose.survey:
      final a = g.aim ?? neck + Offset(f * 8, 2);
      hl = a + const Offset(0, 1.5);
      hr = a + const Offset(0, -1);
      hintL = hintR = const Offset(0, 1);
    case Pose.bucket:
      hr = neck + Offset(f * 2, 10.8);
      hl = neck + Offset(-f * 5.5, 5.5);
    case Pose.kick:
      hl = neck + Offset(-f * 6, 3);
      hr = neck + Offset(f * 5, 5);
    case Pose.ladder:
      hr = neck + Offset(f * 2, -3.5);
      hl = neck + Offset(-f * 2.5, -3.5);
      hintL = hintR = const Offset(0, 1);
    case Pose.stand:
      if (g.move) {
        hl = neck + Offset(-f * 3.8 * s, 10.2);
        hr = neck + Offset(f * 3.8 * s, 10.2);
      }
  }

  if (g.wave) {
    hr = neck + Offset(f * 3 + 3.2 * math.sin(time * 14), -10.4);
    hintR = Offset(f, 0);
  }

  g
    ..hip = hip
    ..neck = neck
    ..head = head
    ..hl = hl
    ..hr = hr
    ..fl = fl
    ..fr = fr
    ..el = _ik(neck, hl, 5.6, 5.6, hintL)
    ..er = _ik(neck, hr, 5.6, 5.6, hintR)
    ..kl = _ik(hip, fl, 7, 7, kneeHint)
    ..kr = _ik(hip, fr, 7, 7, kneeHint);
}

final _halo = Paint()
  ..color = BP.paper
  ..strokeWidth = 4.6
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;
final _body = Paint()
  ..color = BP.ink
  ..strokeWidth = 1.9
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;
final _headFill = Paint()..color = BP.paper;
final _headLine = Paint()
  ..color = BP.ink
  ..strokeWidth = 1.6
  ..style = PaintingStyle.stroke;
final _hatFill = Paint()..color = BP.amber;

Path _hatPath(double f) => Path()
  ..addArc(Rect.fromCircle(center: const Offset(0, -1.2), radius: 4.4), math.pi, math.pi)
  ..close()
  ..addRect(Rect.fromLTRB(f > 0 ? -4.9 : -6.9, -1.7, f > 0 ? 6.9 : 4.9, -0.4));
final _hatR = _hatPath(1);
final _hatL = _hatPath(-1);


/// The crew's shared paints, for props drawn outside [CrewPainter] (the crane
/// operator's head, for instance).
abstract final class CrewInk {
  static Paint get headFill => _headFill;
  static Paint get headLine => _headLine;
  static Paint get hatFill => _hatFill;
  static Path get hatLeft => _hatL;
  static Path get hatRight => _hatR;
}

/// Draws workers, their props and little effects (sparks, dust, sweat, zzz,
/// steam) on [cv] at scene time [time].
class CrewPainter {
  CrewPainter(this.cv, this.time, {this.flagSplit = 800});

  final Canvas cv;
  final double time;

  /// Planted flags left of this x fly to the right, others to the left.
  final double flagSplit;

  /// A point in [g]'s pose space, in canvas space (applies [Worker.scale]).
  Offset _world(Worker g, Offset p) =>
      g.scale == 1 ? p : Offset(g.x + (p.dx - g.x) * g.scale, g.y + (p.dy - g.y) * g.scale);

  /// Sparks flying from [o]: a burst [age] seconds old.
  void burst(Offset o, double age, int seed, {int n = 7, Color color = BP.amber, double up = 1, double speed = 1}) {
    if (age < 0 || age > 0.55) return;
    for (var i = 0; i < n; i++) {
      final life = 0.3 + 0.25 * _h(seed, i, 1);
      if (age > life) continue;
      final ang = -math.pi / 2 * up + (_h(seed, i, 2) - 0.5) * 2.6;
      final sp = (60 + 110 * _h(seed, i, 3)) * speed;
      final v = Offset(math.cos(ang) * sp, math.sin(ang) * sp + 420 * age);
      final p = o + Offset(math.cos(ang) * sp * age, math.sin(ang) * sp * age + 210 * age * age);
      final tail = p - v / math.max(1, v.distance) * 4;
      cv.drawLine(tail, p, inkStroke(color, 1.4, 1 - age / life));
    }
  }

  /// A continuous spark stream (welding).
  void stream(Offset o, double t, int seed, {Color color = BP.amber}) {
    const period = 0.42;
    for (var i = 0; i < 9; i++) {
      final off = _h(seed, i, 9) * period;
      final k = ((t + off) / period).floor();
      final age = (t + off) - k * period;
      burst(o, age, seed * 31 + i * 7 + k, n: 1, color: color, speed: 1.1);
    }
  }

  void dust(Offset o, double age, {double spread = 1}) {
    if (age < 0 || age > 0.8) return;
    final a = age / 0.8;
    for (var i = 0; i < 7; i++) {
      final side = i.isEven ? 1 : -1;
      final dx = side * (4 + (18 + 16 * _h(i, 3)) * spread * _eo(a));
      final dy = -2 - 9 * a * _h(i, 4);
      cv.drawCircle(o + Offset(dx, dy), 2 + 6 * a * (0.6 + 0.4 * _h(i, 5)), inkStroke(BP.inkDim, 1, 0.7 * (1 - a)));
    }
  }

  void rope(Offset a, Offset b, {double sag = 4, Color color = BP.amber, double w = 1.4}) {
    final m = Offset.lerp(a, b, 0.5)! + Offset(0, sag);
    cv.drawPath(
      Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(m.dx, m.dy, b.dx, b.dy),
      inkStroke(color, w),
    );
  }

  void ladder(Offset foot, Offset top, {double a = 1}) {
    final d = top - foot;
    final len = d.distance;
    if (len < 2) return;
    final u = d / len;
    final n = Offset(-u.dy, u.dx) * 4.6;
    final p = inkStroke(BP.inkDim, 1.4, a);
    cv
      ..drawLine(foot + n, top + n, p)
      ..drawLine(foot - n, top - n, p);
    for (var s = 7.0; s < len - 3; s += 9) {
      final q = foot + u * s;
      cv.drawLine(q + n, q - n, p);
    }
  }

  void zzz(Offset o, double t) {
    for (var j = 0; j < 3; j++) {
      final p = (t * 0.35 + j / 3) % 1;
      final s = 2.4 + p * 2.6;
      final c = o + Offset(4 + p * 12, -6 - p * 22);
      final path = Path()
        ..moveTo(c.dx - s, c.dy - s)
        ..lineTo(c.dx + s, c.dy - s)
        ..lineTo(c.dx - s, c.dy + s)
        ..lineTo(c.dx + s, c.dy + s);
      cv.drawPath(path, inkStroke(BP.inkDim, 1.3, math.sin(p * math.pi)));
    }
  }

  void steam(Offset o, double t) {
    for (var j = 0; j < 3; j++) {
      final p = (t * 0.55 + j / 3) % 1;
      final path = Path();
      for (var k = 0; k <= 6; k++) {
        final yy = o.dy - 2 - p * 14 - k * 1.6;
        final xx = o.dx + (j - 1) * 2 + math.sin(p * 6 + k * 0.9) * 1.6;
        k == 0 ? path.moveTo(xx, yy) : path.lineTo(xx, yy);
      }
      cv.drawPath(path, inkStroke(BP.inkDim, 1, math.sin(p * math.pi) * 0.8));
    }
  }

  void check(Offset o, double s, Paint p) {
    cv.drawPath(
      Path()
        ..moveTo(o.dx, o.dy)
        ..lineTo(o.dx + s * 0.35, o.dy + s * 0.35)
        ..lineTo(o.dx + s, o.dy - s * 0.45),
      p,
    );
  }


  void drawCrew(List<Worker> figs, {double minX = -99, double maxX = 1630}) {
    for (final g in figs) {
      poseWorker(g, time);
    }
    // ropes behind bodies
    for (final g in figs) {
      final r = g.rope;
      if (r == null || g.x < minX || g.x > maxX) continue;
      rope(_world(g, Offset.lerp(g.hl, g.hr, 0.5)!), r, sag: 3);
    }
    for (final g in figs) {
      if (g.x < minX || g.x > maxX) continue;
      fig(g);
    }
  }

  void fig(Worker g) {
    final c = cv;
    final f = g.f;
    final scaled = g.scale != 1;
    if (scaled) {
      c
        ..save()
        ..translate(g.x, g.y)
        ..scale(g.scale)
        ..translate(-g.x, -g.y);
    }
    final path = Path()
      ..moveTo(g.fl.dx, g.fl.dy)
      ..lineTo(g.kl.dx, g.kl.dy)
      ..lineTo(g.hip.dx, g.hip.dy)
      ..lineTo(g.kr.dx, g.kr.dy)
      ..lineTo(g.fr.dx, g.fr.dy)
      ..moveTo(g.hip.dx, g.hip.dy)
      ..lineTo(g.neck.dx, g.neck.dy)
      ..moveTo(g.hl.dx, g.hl.dy)
      ..lineTo(g.el.dx, g.el.dy)
      ..lineTo(g.neck.dx, g.neck.dy)
      ..lineTo(g.er.dx, g.er.dy)
      ..lineTo(g.hr.dx, g.hr.dy);
    final plain = g.ink == BP.ink;
    c
      ..drawPath(path, _halo)
      ..drawPath(path, plain ? _body : inkStroke(g.ink, 1.9))
      ..drawCircle(g.head, 3.8, _headFill)
      ..drawCircle(g.head, 3.8, plain ? _headLine : (inkStroke(g.ink, 1.6)..strokeCap = StrokeCap.butt));
    final vest = g.vest;
    if (vest != null) {
      c.drawLine(Offset.lerp(g.hip, g.neck, 0.18)!, Offset.lerp(g.hip, g.neck, 0.8)!, inkStroke(vest, 3.8));
    }
    final up = g.neck - g.hip;
    final ang = math.atan2(up.dx, -up.dy);
    c
      ..save()
      ..translate(g.head.dx, g.head.dy)
      ..rotate(ang);
    if (g.p == Pose.lie) {
      c.rotate(f * 1.1);
      c.translate(0, 1.6);
    }
    c.drawPath(f > 0 ? _hatR : _hatL, g.hat == BP.amber ? _hatFill : inkFill(g.hat));
    if (g.visor) {
      c.drawRect(Rect.fromLTWH(f > 0 ? 1.4 : -4.4, -0.8, 3, 4.6), inkFill(BP.amber, 0.85));
    }
    c.restore();
    item(g);
    if (g.sweat) sweat(g);
    if (g.alarm) {
      final o = g.head + const Offset(0, -9);
      c
        ..drawLine(o + const Offset(0, -9), o + const Offset(0, -2.5), inkStroke(BP.amber, 2))
        ..drawCircle(o + const Offset(0, 0.6), 1.1, inkFill(BP.amber));
    }
    if (scaled) c.restore();
  }

  void sweat(Worker g) {
    const period = 0.95;
    for (var j = 0; j < 2; j++) {
      final t = time + g.id * 0.37 + j * period / 2;
      final age = t % period;
      if (age > 0.6) continue;
      final side = (((t / period).floor() + j) % 2 == 0) ? 1.0 : -1.0;
      final p = g.head + Offset(side * (3 + 16 * age), -4 - 22 * age + 70 * age * age);
      final a = 1 - age / 0.6;
      cv
        ..drawCircle(p, 1.3, inkFill(BP.line, a))
        ..drawLine(p + const Offset(0, -1.1), p + const Offset(0, -3), inkStroke(BP.line, 1, a));
    }
  }

  void item(Worker g) {
    final c = cv;
    final f = g.f;
    switch (g.item) {
      case Tool.none:
        break;
      case Tool.cup:
        final o = g.hr + Offset(f * 1.4, -1.6);
        c
          ..drawRect(Rect.fromCenter(center: o, width: 3.6, height: 4.2), inkFill(BP.paper))
          ..drawRect(Rect.fromCenter(center: o, width: 3.6, height: 4.2), inkStroke(BP.ink, 1.1));
        if (g.k < 0.2) steam(o + const Offset(0, -2), time + g.id);
      case Tool.wrench:
        final a = g.p == Pose.wrench ? g.aim : null;
        final end = a ?? g.hr + Offset(f * 7, -5);
        c
          ..drawLine(g.hr, end, inkStroke(BP.inkDim, 2.4))
          ..drawCircle(end, 2.4, inkStroke(BP.amber, 1.4));
      case Tool.torch:
        final a = g.p == Pose.weld ? g.aim : null;
        final end = a ?? g.hr + Offset(f * 6, -2);
        c.drawLine(g.hr, end, inkStroke(BP.ink, 1.8));
        if (a != null) c.drawCircle(end, 2, inkFill(BP.amber));
      case Tool.clipboard:
        final r = Rect.fromCenter(center: g.hl + Offset(f * 1.2, -2.5), width: 6, height: 8);
        c
          ..drawRect(r, inkFill(BP.paper))
          ..drawRect(r, inkStroke(BP.inkDim, 1.1))
          ..drawLine(r.topLeft + const Offset(1.5, 3), r.topRight + const Offset(-1.5, 3), inkStroke(BP.inkDim, 0.8))
          ..drawLine(r.topLeft + const Offset(1.5, 5), r.topRight + const Offset(-1.5, 5), inkStroke(BP.inkDim, 0.8));
      case Tool.hammer:
        final d = g.hr - g.er;
        final u = d / math.max(0.01, d.distance);
        final end = g.hr + u * 6.5;
        final n = Offset(-u.dy, u.dx) * 2.8;
        c
          ..drawLine(g.hr, end, inkStroke(BP.inkDim, 1.4))
          ..drawLine(end - n, end + n, inkStroke(BP.ink, 2.8));
      case Tool.bucket:
        final top = g.hr + const Offset(0, 2.5);
        final path = Path()
          ..moveTo(top.dx - 3.6, top.dy)
          ..lineTo(top.dx - 2.7, top.dy + 6)
          ..lineTo(top.dx + 2.7, top.dy + 6)
          ..lineTo(top.dx + 3.6, top.dy);
        c
          ..drawPath(path, inkStroke(BP.line, 1.3))
          ..drawLine(top + const Offset(-3.2, 1.6), top + const Offset(3.2, 1.6), inkStroke(BP.line, 1, 0.6))
          ..drawArc(Rect.fromCircle(center: top, radius: 3.6), math.pi, math.pi, false, inkStroke(BP.inkDim, 0.9));
      case Tool.sign:
        final base = g.plant ?? Offset(g.hr.dx, g.hr.dy + 16);
        final top = base + const Offset(0, -128);
        c.drawLine(base, top, inkStroke(BP.inkDim, 2));
        final board = Rect.fromCenter(center: top + const Offset(0, 17), width: 70, height: 34);
        c
          ..drawRect(board, inkFill(BP.paper))
          ..drawRect(board, inkStroke(BP.amber, 1.6));
        final a = board.center + const Offset(21, 0), b = board.center + const Offset(-21, 0);
        c.drawLine(a, b, inkStroke(BP.amber, 2.6));
        drawArrowHead(c, b, a, inkStroke(BP.amber, 2.6), 9);
      case Tool.flag:
        final base = g.plant ?? Offset(g.hr.dx, g.hr.dy + 14);
        const h = 100.0;
        final top = base + const Offset(0, -h);
        c.drawLine(base, top, inkStroke(BP.inkDim, 2));
        final fy = top.dy + (1 - g.itemT) * (h - 30);
        final wv = math.sin(time * 5) * 2;
        final fd = base.dx > flagSplit ? -1.0 : 1.0; // fly away from the word
        final path = Path()
          ..moveTo(top.dx, fy)
          ..quadraticBezierTo(top.dx + fd * 20, fy - wv, top.dx + fd * 40, fy + wv)
          ..lineTo(top.dx + fd * 40, fy + 26 + wv)
          ..quadraticBezierTo(top.dx + fd * 20, fy + 26 - wv, top.dx, fy + 26)
          ..close();
        c
          ..drawPath(path, inkFill(BP.green, 0.18))
          ..drawPath(path, inkStroke(BP.green, 1.6));
        check(Offset(top.dx + (fd > 0 ? 11 : -29), fy + 13), 18, inkStroke(BP.green, 2.6));
      case Tool.redFlag:
        final top = g.hr + const Offset(0, -15);
        final wv = math.sin(time * 14) * 2.5;
        c
          ..drawLine(g.hr, top, inkStroke(BP.inkDim, 1.4))
          ..drawPath(
            Path()
              ..moveTo(top.dx, top.dy)
              ..lineTo(top.dx + f * 10, top.dy + 3 + wv)
              ..lineTo(top.dx, top.dy + 7)
              ..close(),
            inkFill(BP.red),
          );
      case Tool.staff:
        final x = g.hr.dx + f * 2.5;
        for (var i = 0; i < 7; i++) {
          c.drawLine(
            Offset(x, g.y - i * 10.0),
            Offset(x, g.y - i * 10.0 - 10),
            inkStroke(i.isEven ? BP.amber : BP.inkDim, 2.2),
          );
        }
    }
  }
}
