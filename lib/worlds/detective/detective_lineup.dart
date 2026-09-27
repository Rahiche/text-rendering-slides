import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../deck/deck.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'noir_kit.dart';

/// The pipeline as a police line-up: the seven stages are the suspects,
/// in front of a height chart. Each build step brings the next one in to
/// step forward with its alibi. Click a suspect to interrogate it (jump to
/// its slide).
class DetectiveLineup extends StatefulWidget {
  const DetectiveLineup({super.key});

  @override
  State<DetectiveLineup> createState() => _DetectiveLineupState();
}

class _Suspect {
  const _Suspect(this.name, this.lib, this.slideId, this.alibi, this.height, this.prop);

  final String name;
  final String lib;
  final String slideId;
  final String alibi;
  final double height;
  final String prop;
}

const _suspects = [
  _Suspect('text', 'unicode', 'string', 'same U+76F4 everywhere', 232, 'U+'),
  _Suspect('itemize', 'ICU', 'itemize', 'said Hani, not ja', 250, 'Hani'),
  _Suspect('fonts', 'font manager', 'fallback', 'asked the platform · with a locale', 218, 'Aa'),
  _Suspect('shape', 'HarfBuzz', 'shaping', 'locl needs a language', 258, '#'),
  _Suspect('wrap', 'ICU · UAX #14', 'linebreak', 'only breaks lines', 238, r'\n'),
  _Suspect('position', 'layout', 'bidi', 'only places glyphs', 226, 'x,y'),
  _Suspect('raster', 'Skia · GPU', 'raster', 'paints what it gets', 248, 'px'),
];

const _floorY = 452.0;
double _slotX(int i) => 96 + i * 178.0;

class _DetectiveLineupState extends State<DetectiveLineup> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(0);
  final _labels = LabelCache();
  final Map<int, double> _since = {};
  int _step = -1;
  int? _hover;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => _time.value = d.inMicroseconds / 1e6)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _labels.dispose();
    super.dispose();
  }

  void _sync(int step) {
    if (step == _step) return;
    final now = _time.value;
    final first = _step < 0;
    for (var i = 0; i <= step; i++) {
      // On first show, the earlier suspects are already standing in line.
      _since.putIfAbsent(i, () => first && i < step ? now - 10 : now + (first ? 0.3 : 0));
    }
    _since.removeWhere((k, _) => k > step);
    _step = step;
  }

  @override
  Widget build(BuildContext context) {
    final step = SlideScope.of(context).step.clamp(0, 6);
    _sync(step);
    final focus = _hover ?? step;
    final s = _suspects[focus];
    return SlideFrame(
      title: 'The pipeline line-up',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _LineupPainter(this, _time, step)),
            ),
          ),
          for (var i = 0; i <= step; i++)
            Positioned(
              left: _slotX(i) - 70,
              top: _floorY - 290,
              width: 140,
              height: 320,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hover = i),
                onExit: (_) => setState(() => _hover = _hover == i ? null : _hover),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => DeckScope.read(context).goToId(_suspects[i].slideId),
                ),
              ),
            ),
          // The alibi of whoever is under the light.
          Positioned(
            left: 0,
            right: 0,
            top: 540,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Row(
                key: ValueKey(focus),
                children: [
                  Text('#${(focus + 1).toString().padLeft(2, '0')}  ${s.name}', style: BT.mono(20, color: BP.amber)),
                  const SizedBox(width: 18),
                  Text(s.lib, style: BT.mono(16, color: BP.inkDim)),
                  const SizedBox(width: 22),
                  Container(width: 30, height: 1, color: BP.lineDim),
                  const SizedBox(width: 22),
                  Text('alibi: ', style: BT.mono(16, color: BP.inkFaint)),
                  Text(s.alibi, style: BT.mono(20, color: focus == 2 ? BP.red : BP.ink)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineupPainter extends CustomPainter {
  _LineupPainter(this.s, this.time, this.step) : super(repaint: time);

  final _DetectiveLineupState s;
  final ValueNotifier<double> time;
  final int step;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final lab = s._labels;
    // Height chart.
    for (var k = 0; k <= 10; k++) {
      final y = _floorY - k * 30.0;
      final major = k.isEven;
      canvas.drawLine(Offset(0, y), Offset(size.width - 120, y), Paint()
        ..color = major ? BP.lineDim.withValues(alpha: 0.7) : BP.lineFaint
        ..strokeWidth = major ? 1.2 : 1);
      if (major && k > 0) {
        lab.get('${k * 10 + 100}', BT.mono(11, color: BP.inkFaint)).paint(canvas, Offset(size.width - 112, y - 7));
      }
    }
    canvas.drawLine(Offset(0, _floorY), Offset(size.width, _floorY), Paint()
      ..color = BP.line
      ..strokeWidth = 1.5);
    final focus = s._hover ?? step;

    for (var i = 0; i < _suspects.length; i++) {
      final x0 = _slotX(i);
      // Slot number on the floor.
      final n = lab.get('${i + 1}', BT.mono(16, color: i <= step ? BP.inkDim : BP.lineFaint));
      n.paint(canvas, Offset(x0 - n.width / 2, _floorY + 10));
      final since = s._since[i];
      if (since == null) continue;
      final age = t - since;
      if (age < 0) continue;
      // Walk in from the right, then step forward when called.
      final walk = seg(age, 0, 1.1);
      final x = x0 + (1 - walk) * (size.width + 60 - x0);
      final hot = i == focus;
      final fwd = hot ? segOut(age, 1.1, 1.5) : 0.0;
      final feet = Offset(x, _floorY + 26 * fwd);
      if (hot) {
        paintCone(canvas, Offset(x0, -150), _floorY + 30, halfWidth: 110, topHalf: 10, intensity: 0.9);
      }
      _suspect(canvas, i, feet, t, walking: walk < 1, hot: hot, scale: 1 + 0.06 * fwd, lab: lab);
    }

    // The detective, watching from the side; at the end he fixes on #3.
    final end = step >= 6;
    paintDetective(
      canvas,
      Offset(size.width - 40, _floorY),
      200,
      DetPose(facing: -1, lens: end ? 1 : 0.7 + 0.2 * math.sin(t * 0.9), look: end ? 0.2 : 0.4),
    );
    if (step >= 2) {
      // The fonts suspect gets an evidence tag: the one to question.
      final x = _slotX(2);
      final sway = math.sin(t * 1.6) * 0.08;
      final top = Offset(x, _floorY - _suspects[2].height - 50);
      canvas.save();
      canvas.translate(top.dx, top.dy);
      canvas.rotate(sway);
      final tp = lab.get(end ? 'prime suspect' : 'suspicious', BT.mono(13, color: BP.paper));
      final r = Rect.fromLTWH(-tp.width / 2 - 20, 0, tp.width + 34, tp.height + 8);
      canvas.drawLine(const Offset(0, -18), Offset.zero, Paint()
        ..color = BP.red
        ..strokeWidth = 1.2);
      drawPin(canvas, const Offset(0, -18), r: 4);
      paintTag(canvas, r, color: BP.red, filled: true);
      tp.paint(canvas, Offset(r.left + 26, r.top + 4));
      canvas.restore();
    }
  }

  /// A suspect: stick figure holding a placard, with a prop above the head.
  void _suspect(Canvas canvas, int i, Offset feet, double t,
      {required bool walking, required bool hot, required double scale, required LabelCache lab}) {
    final sp = _suspects[i];
    final h = sp.height * scale;
    final ink = Paint()
      ..color = hot ? BP.ink : BP.inkDim
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final sway = walking ? 0.0 : math.sin(t * 0.8 + i * 1.7) * 3;
    final phase = t * 9;
    final hip = feet + Offset(sway * 0.3, -h * 0.45);
    final neck = feet + Offset(sway, -h * 0.78);
    final head = neck + Offset(0, -h * 0.08);
    // Legs.
    final st = walking ? math.sin(phase) * 0.35 : 0.08;
    for (final a in [st, -st]) {
      final foot = feet + Offset(math.sin(a) * h * 0.45, 0);
      canvas.drawLine(hip, foot, ink);
      canvas.drawLine(foot, foot + const Offset(-8, 0), ink);
    }
    canvas.drawLine(hip, neck, ink);
    canvas.drawCircle(head, h * 0.075, Paint()..color = BP.paper);
    canvas.drawCircle(head, h * 0.075, ink);
    // Eyes glance sideways now and then.
    final glance = noise1(t * 0.5, i) * h * 0.02;
    canvas.drawCircle(head + Offset(-h * 0.022 + glance, -h * 0.005), 1.8, Paint()..color = ink.color);
    canvas.drawCircle(head + Offset(h * 0.022 + glance, -h * 0.005), 1.8, Paint()..color = ink.color);
    // Arms to the placard.
    final plate = Rect.fromCenter(center: neck + Offset(0, h * 0.25), width: 132, height: 64);
    final shoulder = neck + Offset(0, h * 0.04);
    canvas.drawLine(shoulder, plate.bottomLeft + const Offset(12, -8), ink);
    canvas.drawLine(shoulder, plate.bottomRight + const Offset(-12, -8), ink);
    canvas.drawRect(plate, Paint()..color = hot ? Color.alphaBlend(BP.amber.withValues(alpha: 0.14), BP.paper) : BP.paper);
    canvas.drawRect(plate, Paint()
      ..color = hot ? BP.amber : BP.lineDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4);
    final num = lab.get((i + 1).toString().padLeft(2, '0'), BT.mono(12, color: BP.inkFaint));
    num.paint(canvas, plate.topLeft + const Offset(8, 6));
    final name = lab.get(sp.name, BT.display(22, color: hot ? BP.amber : BP.ink));
    name.paint(canvas, Offset(plate.center.dx - name.width / 2, plate.top + 10));
    final libTp = lab.get(sp.lib, BT.mono(11, color: BP.inkDim));
    libTp.paint(canvas, Offset(plate.center.dx - libTp.width / 2, plate.bottom - 20));
    // Prop above the head (what they carry around).
    final prop = lab.get(sp.prop, BT.mono(15, color: hot ? BP.amber : BP.inkFaint));
    final pr = Rect.fromCenter(center: head + Offset(0, -h * 0.075 - 22), width: prop.width + 14, height: prop.height + 4);
    canvas.drawRect(pr, Paint()
      ..color = (hot ? BP.amber : BP.lineFaint)
      ..style = PaintingStyle.stroke);
    prop.paint(canvas, pr.center - Offset(prop.width / 2, prop.height / 2));
  }

  @override
  bool shouldRepaint(_LineupPainter old) => old.s != s || old.step != step;
}
