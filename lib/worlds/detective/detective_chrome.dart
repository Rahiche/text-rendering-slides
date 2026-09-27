import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../deck/deck.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'noir_kit.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Ruler: the case timeline. A red string with a pin per slide; clue slides
// carry amber evidence tags; the magnifying glass sits on the current pin.
// ─────────────────────────────────────────────────────────────────────────────

const _rx0 = 176.0;
const _rx1 = 1424.0;
const _ry = 44.0; // string height inside the 110 px band

double _pinX(int i, int n) => n <= 1 ? _rx0 : _rx0 + i * (_rx1 - _rx0) / (n - 1);

/// Story slides this world adds (they get evidence tags on the timeline).
bool isClueId(String id) => id.startsWith('clue-') || id.startsWith('case-');

class CaseTimeline extends StatefulWidget {
  const CaseTimeline({super.key, required this.controller});

  final DeckController controller;

  @override
  State<CaseTimeline> createState() => _CaseTimelineState();
}

class _CaseTimelineState extends State<CaseTimeline> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(0);
  final _labels = LabelCache();
  int _index = -1;
  double _fromX = 0;
  double _movedAt = -10;
  int? _hover;

  @override
  void initState() {
    super.initState();
    _index = widget.controller.index;
    _fromX = _pinX(_index, widget.controller.slides.length);
    _ticker = createTicker((d) => _time.value = d.inMicroseconds / 1e6)..start();
  }

  @override
  void didUpdateWidget(CaseTimeline old) {
    super.didUpdateWidget(old);
    final c = widget.controller;
    if (c.index != _index) {
      _fromX = _lensX(c.slides.length);
      _index = c.index;
      _movedAt = _time.value;
    }
  }

  double _lensX(int n) {
    final to = _pinX(_index, n);
    final u = segOut(_time.value - _movedAt, 0, 0.6);
    return _fromX + (to - _fromX) * u;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _labels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final n = c.slides.length;
    final cur = c.current;
    final sectionNo = _sectionNumber(c);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(painter: _TimelinePainter(this, _time)),
            ),
          ),
        ),
        // Left: the case + the current section.
        Positioned(
          left: 64,
          top: _ry - 12,
          child: IgnorePointer(
            child: Row(
              children: [
                Text(sectionNo, style: BT.mono(14, color: BP.amber)),
                const SizedBox(width: 8),
                Text(cur.section, style: BT.mono(14, color: BP.inkDim)),
              ],
            ),
          ),
        ),
        // Right: counter (tap → overview).
        Positioned(
          right: 64,
          top: _ry - 12,
          child: GestureDetector(
            onTap: c.toggleOverview,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Text(
                '${(c.index + 1).toString().padLeft(2, '0')} / ${n.toString().padLeft(2, '0')}',
                style: BT.mono(14, color: BP.line),
              ),
            ),
          ),
        ),
        // Hit areas, one per pin.
        for (var i = 0; i < n; i++)
          Positioned(
            left: _pinX(i, n) - (_rx1 - _rx0) / (n - 1) / 2,
            width: (_rx1 - _rx0) / (n - 1),
            top: _ry - 26,
            height: 56,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hover = i),
              onExit: (_) => setState(() => _hover = _hover == i ? null : _hover),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => c.goTo(i),
              ),
            ),
          ),
        if (_hover != null && _hover! < n)
          Positioned(
            left: _pinX(_hover!, n) - 300,
            width: 600,
            top: _ry - 56,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: BP.panel,
                    border: Border.all(color: isClueId(c.slides[_hover!].id) ? BP.amber : BP.line),
                  ),
                  child: Text(c.slides[_hover!].title, softWrap: false, style: BT.mono(13, color: BP.ink)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _sectionNumber(DeckController c) {
    const order = ['intro', 'basics', 'scripts', 'others', 'flutter', 'journey', 'outro'];
    final i = order.indexOf(c.current.section);
    if (i <= 0 || i >= 6) return '§';
    return i.toString().padLeft(2, '0');
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.s, this.time) : super(repaint: time);

  final _CaseTimelineState s;
  final ValueNotifier<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final c = s.widget.controller;
    final n = c.slides.length;
    final t = time.value;
    final idx = c.index;
    final since = t - s._movedAt;
    // The string gets plucked when the lens lands.
    final pluck = since < 1.6 ? math.exp(-since * 3) * math.sin(since * 26) * 4 : 0.0;
    final lensX = s._lensX(n);

    double yAt(double x) {
      final d = (x - lensX).abs();
      return _ry + pluck * math.exp(-d / 160);
    }

    // String: a sag between neighbouring pins.
    final done = Path();
    final todo = Path();
    for (var i = 0; i < n - 1; i++) {
      final a = Offset(_pinX(i, n), yAt(_pinX(i, n)));
      final b = Offset(_pinX(i + 1, n), yAt(_pinX(i + 1, n)));
      final path = i < idx ? done : todo;
      path.moveTo(a.dx, a.dy);
      final mid = Offset.lerp(a, b, 0.5)! + const Offset(0, 3.5);
      path.quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy);
    }
    canvas.drawPath(
      todo,
      Paint()
        ..color = BP.red.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawPath(
      done,
      Paint()
        ..color = BP.red.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    var section = 0;
    for (var i = 0; i < n; i++) {
      final def = c.slides[i];
      final x = _pinX(i, n);
      final y = yAt(x);
      final major = i == 0 || def.section != c.slides[i - 1].section;
      if (major && i > 0) section++;
      final passed = i <= idx;
      final hot = s._hover == i;
      if (isClueId(def.id)) {
        // A little evidence tag hanging off the pin, swaying.
        final sway = math.sin(t * 1.3 + i) * 0.12;
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(sway);
        canvas.drawLine(Offset.zero, const Offset(0, 10), Paint()
          ..color = BP.amber.withValues(alpha: 0.7)
          ..strokeWidth = 1);
        paintTag(canvas, Rect.fromLTWH(-5, 10, 11, 17),
            color: passed || hot ? BP.amber : BP.amber.withValues(alpha: 0.45));
        canvas.restore();
      }
      if (major && def.section != 'intro' && def.section != 'outro') {
        final tp = s._labels.get(section.toString().padLeft(2, '0'), BT.mono(11, color: passed ? BP.inkDim : BP.inkFaint));
        tp.paint(canvas, Offset(x - tp.width / 2, y - 30));
        canvas.drawLine(Offset(x, y - 14), Offset(x, y - 4), Paint()
          ..color = passed ? BP.inkDim : BP.inkFaint
          ..strokeWidth = 1);
      }
      final r = major ? 4.6 : 3.2;
      if (passed) {
        drawPin(canvas, Offset(x, y), r: hot ? r + 1.5 : r);
      } else {
        canvas.drawCircle(Offset(x, y), hot ? r + 1.5 : r, Paint()..color = BP.paper);
        canvas.drawCircle(
          Offset(x, y),
          hot ? r + 1.5 : r,
          Paint()
            ..color = hot ? BP.amber : BP.lineDim
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }
    }

    // The magnifying glass over the current pin (bobbing a little).
    final bob = math.sin(t * 1.7) * 1.5;
    final lc = Offset(lensX, _ry + bob);
    canvas.drawCircle(lc, 12, Paint()..color = BP.amber.withValues(alpha: 0.12));
    paintMagnifier(canvas, lc, 12, angle: 0.9, rim: BP.ink, handle: 1.1);

    // Build steps of the current slide.
    final steps = c.current.steps;
    if (steps > 1) {
      final x0 = _pinX(idx, n) - (steps * 8) / 2 + 1;
      for (var k = 0; k < steps; k++) {
        canvas.drawRect(
          Rect.fromLTWH(x0 + k * 8, _ry + 33, 5, 5),
          Paint()..color = k <= c.step ? BP.amber : BP.lineFaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Ambient: rain in the side margins, a lamp post at the right edge, a case
// stamp in the left margin. Low contrast; never touches the content area.
// ─────────────────────────────────────────────────────────────────────────────

class DetectiveAmbient extends StatefulWidget {
  const DetectiveAmbient({super.key});

  @override
  State<DetectiveAmbient> createState() => _DetectiveAmbientState();
}

class _DetectiveAmbientState extends State<DetectiveAmbient> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(0);
  final _labels = LabelCache();

  @override
  void initState() {
    super.initState();
    // ~30 fps is plenty for drizzle in the margins.
    var last = -1.0;
    _ticker = createTicker((d) {
      final t = d.inMicroseconds / 1e6;
      if (t - last >= 1 / 30) {
        last = t;
        _time.value = t;
      }
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _labels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(child: CustomPaint(painter: _AmbientPainter(this, _time))),
  );
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.s, this.time) : super(repaint: time);

  final _DetectiveAmbientState s;
  final ValueNotifier<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final t = noirSeconds;
    // Drizzle in the side margins only.
    canvas.save();
    canvas.clipRect(const Rect.fromLTWH(0, 150, 50, 640));
    paintRain(canvas, const Rect.fromLTWH(0, 150, 50, 640), t, count: 14, alpha: 0.14, salt: 11);
    canvas.restore();
    canvas.save();
    canvas.clipRect(const Rect.fromLTWH(1546, 150, 54, 640));
    paintRain(canvas, const Rect.fromLTWH(1546, 150, 54, 640), t, count: 14, alpha: 0.14, salt: 12);
    canvas.restore();

    // A lamp post along the right edge, its glow pooling at the floor.
    final post = Paint()
      ..color = BP.lineFaint
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(1580, 290), const Offset(1580, 790), post);
    canvas.drawLine(const Offset(1580, 290), const Offset(1566, 290), post);
    final flick = (t % 31) < 0.4 ? 0.4 : 1.0;
    const bulb = Offset(1566, 300);
    canvas.drawCircle(
      bulb,
      30,
      Paint()
        ..shader = ui.Gradient.radial(bulb, 30, [
          BP.amber.withValues(alpha: 0.14 * flick),
          BP.amber.withValues(alpha: 0),
        ]),
    );
    canvas.drawPath(
      Path()
        ..moveTo(1559, 294)
        ..lineTo(1573, 294)
        ..lineTo(1570, 301)
        ..lineTo(1562, 301)
        ..close(),
      Paint()..color = BP.amber.withValues(alpha: 0.5 * flick),
    );

    // Case file stamp, written up the left margin.
    final tp = s._labels.get('CASE № ${hexOf(caseCp)}  ·  $caseChar', NT.jp(12, color: BP.inkFaint));
    canvas.save();
    canvas.translate(26, 520);
    canvas.rotate(-math.pi / 2);
    tp.paint(canvas, Offset(0, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Transition: the torch. A beam from the magnifier on the timeline opens a
// circle of light that becomes the next slide. The widget tree is the same
// for the whole animation (Stack → ClipPath → IgnorePointer, CustomPaint).
// ─────────────────────────────────────────────────────────────────────────────

Widget detectiveTransition(
  BuildContext context,
  Widget child,
  Animation<double> animation, {
  required bool incoming,
  required bool forward,
}) {
  // The pin the torch shines from: the incoming slide's place on the timeline.
  var origin = const Offset(800, 790 + _ry);
  if (child is SlideScope) origin = Offset(_pinX(child.index, child.total), 790 + _ry);
  return _Torch(animation: animation, incoming: incoming, origin: origin, child: child);
}

class _Torch extends StatelessWidget {
  const _Torch({required this.animation, required this.incoming, required this.origin, required this.child});

  final Animation<double> animation;
  final bool incoming;
  final Offset origin;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final u = (incoming ? animation.value : 1 - animation.value).clamp(0.0, 1.0);
        final e = Curves.easeInOutCubic.transform(u);
        final done = !incoming || u >= 1;
        const mid = Offset(800, 450);
        final center = Offset.lerp(origin, mid, e)!;
        final radius = 14 + e * 980;
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipPath(
              clipper: _CircleClipper(center: center, radius: radius, open: done),
              child: IgnorePointer(ignoring: !incoming, child: child),
            ),
            IgnorePointer(
              child: CustomPaint(
                painter: _TorchPainter(
                  origin: origin,
                  center: center,
                  radius: radius,
                  u: u,
                  incoming: incoming,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CircleClipper extends CustomClipper<Path> {
  _CircleClipper({required this.center, required this.radius, required this.open});

  final Offset center;
  final double radius;
  final bool open;

  @override
  Path getClip(Size size) {
    if (open) return Path()..addRect(const Rect.fromLTRB(-400, -400, 2000, 1300));
    return Path()..addOval(Rect.fromCircle(center: center, radius: radius));
  }

  @override
  bool shouldReclip(_CircleClipper old) =>
      old.center != center || old.radius != radius || old.open != open;
}

class _TorchPainter extends CustomPainter {
  _TorchPainter({
    required this.origin,
    required this.center,
    required this.radius,
    required this.u,
    required this.incoming,
  });

  final Offset origin;
  final Offset center;
  final double radius;
  final double u;
  final bool incoming;

  @override
  void paint(Canvas canvas, Size size) {
    if (!incoming) {
      // The old scene goes dark as the torch moves on.
      if (u > 0 && u < 1) {
        canvas.drawRect(Offset.zero & size, Paint()..color = BP.paper.withValues(alpha: 0.6 * u));
      }
      return;
    }
    if (u >= 1) return;
    final fade = math.sin(u * math.pi).clamp(0.0, 1.0);
    // Beam: from the torch to the tangents of the circle of light.
    final d = center - origin;
    final dist = d.distance;
    if (dist > radius + 4) {
      final a = math.atan2(d.dy, d.dx);
      final half = math.asin((radius / dist).clamp(0.0, 1.0));
      final l = math.sqrt(math.max(0, dist * dist - radius * radius));
      final p1 = origin + Offset(math.cos(a - half), math.sin(a - half)) * l;
      final p2 = origin + Offset(math.cos(a + half), math.sin(a + half)) * l;
      final beam = Path()
        ..moveTo(origin.dx, origin.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close();
      canvas.drawPath(
        beam,
        Paint()
          ..shader = ui.Gradient.linear(origin, center, [
            BP.amber.withValues(alpha: 0.28 * fade),
            BP.amber.withValues(alpha: 0.06 * fade),
          ]),
      );
      final edge = Paint()
        ..color = BP.amber.withValues(alpha: 0.5 * fade)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      canvas.drawPath(dashPath(Path()
        ..moveTo(origin.dx, origin.dy)
        ..lineTo(p1.dx, p1.dy)
        ..moveTo(origin.dx, origin.dy)
        ..lineTo(p2.dx, p2.dy), dash: 10, gap: 7), edge);
    }
    // Rim of the light circle, with a warm inner glow.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(center, radius, [
          BP.amber.withValues(alpha: 0),
          BP.amber.withValues(alpha: 0),
          BP.amber.withValues(alpha: 0.16 * fade),
        ], [0, 0.8, 1]),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = BP.amber.withValues(alpha: 0.8 * fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    // The torch itself.
    paintMagnifier(canvas, origin, 12, angle: 0.9, rim: BP.ink, handle: 1.1);
  }

  @override
  bool shouldRepaint(_TorchPainter old) =>
      old.u != u || old.center != center || old.radius != radius || old.incoming != incoming;
}
