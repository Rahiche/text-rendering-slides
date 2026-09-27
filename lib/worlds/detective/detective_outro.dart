import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'noir_kit.dart';

/// The end: the case file gets its CASE CLOSED stamp, the rain stops, dawn
/// comes up over the street and the detective tips his hat.
/// Poke: click the detective (hat), click the file (stamp again).
class DetectiveOutro extends StatefulWidget {
  const DetectiveOutro({super.key});

  @override
  State<DetectiveOutro> createState() => _DetectiveOutroState();
}

const _street = 756.0;
const _hero = Offset(1250, _street);
const _heroH = 330.0;
const _folder = Rect.fromLTWH(96, 70, 560, 360);

class _DetectiveOutroState extends State<DetectiveOutro> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(0);
  final _labels = LabelCache();
  double _tipAt = 2.6;
  double _stampAt = 1.0;

  @override
  void initState() {
    super.initState();
    CaseFonts.load();
    _ticker = createTicker((d) => _time.value = d.inMicroseconds / 1e6)..start();
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
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (e) {
        final p = e.localPosition;
        if (_folder.contains(p)) {
          _stampAt = _time.value;
        } else if (Rect.fromLTRB(_hero.dx - 120, _hero.dy - _heroH, _hero.dx + 120, _hero.dy).contains(p)) {
          _tipAt = _time.value;
        }
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(child: CustomPaint(painter: _OutroPainter(this, _time))),
          ),
          Positioned(
            left: 100,
            top: 492,
            child: Reveal(
              visible: true,
              delay: const Duration(milliseconds: 1400),
              child: Text('ありがとうございました', style: NT.jp(76, color: BP.ink, weight: 600, height: 1.2)),
            ),
          ),
          Positioned(
            left: 106,
            top: 612,
            child: Reveal(
              visible: true,
              delay: const Duration(milliseconds: 1800),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('thank you', style: BT.display(44, color: BP.inkDim, letterSpacing: -0.5)),
                  const SizedBox(width: 28),
                  Container(width: 36, height: 1.5, color: BP.amber),
                  const SizedBox(width: 18),
                  Text('questions?', style: BT.mono(26, color: BP.amber)),
                  const SizedBox(width: 14),
                  Text('·', style: BT.mono(26, color: BP.inkDim)),
                  const SizedBox(width: 14),
                  Text('ご質問は？', style: NT.jp(28, color: BP.amber)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutroPainter extends CustomPainter {
  _OutroPainter(this.s, this.time) : super(repaint: time);

  final _DetectiveOutroState s;
  final ValueNotifier<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final clock = noirSeconds;
    // The rain eases off; dawn comes up.
    final rain = 1 - seg(t, 1.5, 9);
    final dawn = seg(t, 3, 12);
    if (dawn > 0) {
      final r = Rect.fromLTRB(64, 360, 1536, _street);
      canvas.drawRect(
        r,
        Paint()
          ..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, [
            BP.amber.withValues(alpha: 0),
            BP.amber.withValues(alpha: 0.07 * dawn),
          ]),
      );
      // The sun, peeking over the street.
      final sun = Offset(930, _street);
      canvas.drawArc(Rect.fromCircle(center: sun, radius: 70 + 6 * dawn), math.pi, math.pi, false, Paint()
        ..color = BP.amber.withValues(alpha: 0.55 * dawn)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
      for (var i = 0; i < 9; i++) {
        final a = math.pi + (i + 0.5) * math.pi / 9;
        final d = Offset(math.cos(a), math.sin(a));
        final wob = 6 * math.sin(clock * 0.8 + i);
        canvas.drawLine(sun + d * (90 + wob), sun + d * (118 + wob), Paint()
          ..color = BP.amber.withValues(alpha: 0.35 * dawn)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round);
      }
    }
    if (rain > 0.01) paintRain(canvas, Offset.zero & size, clock, count: 140, alpha: 0.14 * rain, salt: 3);

    // Lamp post: switches off as the day comes.
    final post = Paint()
      ..color = BP.lineDim
      ..strokeWidth = 3;
    canvas.drawLine(const Offset(1470, _street), const Offset(1470, 250), post);
    canvas.drawLine(const Offset(1470, 254), const Offset(1400, 254), post);
    final on = (1 - seg(t, 5, 7)) * ((clock % 1.3) < 0.1 && t > 4 ? 0.3 : 1);
    paintLampShade(canvas, const Offset(1400, 290), size: 40, glow: on, cord: 22);
    if (on > 0.05) paintCone(canvas, const Offset(1400, 296), _street, halfWidth: 200, intensity: on);

    paintStreet(canvas, _street, 64, 1536);
    if (rain > 0.05) paintSplashes(canvas, 80, 1520, _street, clock, count: (12 * rain).round() + 1);

    _paintFolder(canvas, t);

    // The detective: tips his hat now and then (and when clicked).
    final tipAge = t - s._tipAt;
    final auto = (t % 9.0);
    var tip = tipAge >= 0 && tipAge < 1.8 ? math.sin(tipAge / 1.8 * math.pi) : 0.0;
    if (t > 6 && auto < 1.8) tip = math.max(tip, math.sin(auto / 1.8 * math.pi));
    canvas.drawOval(Rect.fromCenter(center: _hero + const Offset(0, 2), width: 180, height: 26),
        Paint()..color = Colors.black.withValues(alpha: 0.3));
    paintDetective(canvas, _hero, _heroH, DetPose(tip: tip, facing: -1, look: 0.2 * math.sin(clock * 0.5)));
  }

  void _paintFolder(Canvas canvas, double t) {
    final lab = s._labels;
    canvas.save();
    canvas.translate(_folder.center.dx, _folder.center.dy);
    canvas.rotate(-0.035);
    canvas.translate(-_folder.center.dx, -_folder.center.dy);
    final r = _folder;
    // Tab + body.
    final tab = Rect.fromLTWH(r.left + 20, r.top - 34, 250, 36);
    final ink = Paint()
      ..color = BP.inkDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawRect(tab, Paint()..color = BP.panel);
    canvas.drawRect(tab, ink);
    lab.get('CASE № ${hexOf(caseCp)}', BT.mono(17, color: BP.amber, weight: 600)).paint(canvas, tab.topLeft + const Offset(14, 8));
    canvas.drawRect(r, Paint()..color = BP.panel);
    canvas.drawRect(r, ink);
    // Contents: the JP photo and the summary.
    final photo = Rect.fromLTWH(r.left + 26, r.top + 30, 200, 220);
    canvas.drawRect(photo, Paint()..color = BP.paper);
    canvas.drawRect(photo, Paint()
      ..color = BP.line
      ..style = PaintingStyle.stroke);
    drawPin(canvas, photo.topCenter + const Offset(0, 8));
    final g = lab.get(caseChar, NT.caseJP(150, color: BP.line));
    g.paint(canvas, Offset(photo.center.dx - g.width / 2, photo.center.dy - g.height / 2 + 6));
    final lines = [
      ('suspect', 'font fallback'),
      ('motive', 'en_US'),
      ('fix', "Locale('ja')"),
      ('status', 'closed'),
    ];
    for (var i = 0; i < lines.length; i++) {
      final y = r.top + 44 + i * 50.0;
      lab.get(lines[i].$1, BT.mono(14, color: BP.inkFaint)).paint(canvas, Offset(r.left + 250, y));
      lab.get(lines[i].$2, BT.mono(19, color: i == 3 ? BP.green : BP.ink)).paint(canvas, Offset(r.left + 250, y + 18));
    }
    lab.get('demo: Noto Sans JP', BT.mono(11, color: BP.inkFaint)).paint(canvas, photo.bottomLeft + const Offset(0, 10));
    canvas.restore();
    // The stamp.
    final st = lab.get('CASE CLOSED', BT.display(52, color: BP.red, weight: 700, letterSpacing: 2));
    final u = ((t - s._stampAt) / 0.5).clamp(0.0, 1.0);
    paintStamp(canvas, Offset(r.center.dx + 60, r.bottom - 40), st, u, angle: -0.16);
    if (u >= 1) {
      final kanji = lab.get('解決', NT.jp(30, color: BP.red, weight: 700));
      final k = ((t - s._stampAt - 0.35) / 0.4).clamp(0.0, 1.0);
      paintStamp(canvas, Offset(r.right - 40, r.top + 36), kanji, k, angle: 0.2, pad: 12);
    }
  }

  @override
  bool shouldRepaint(_OutroPainter old) => old.s != s;
}
