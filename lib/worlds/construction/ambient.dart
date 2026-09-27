import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../deck/theme.dart';
import 'site_kit.dart';

// Scenery behind every content slide, kept in the margins and low-contrast:
// a faint tower crane at the far right edge whose jib runs along the very top,
// cones on the ground line, a worker strolling along the ruler and another
// one on a coffee break at the foot of the crane.
//
// The clock is global (not per slide), so the scenery doesn't restart on
// every slide change.

final _epoch = DateTime.now();

const _ground = 836.0; // the ruler's ground line
const _mastL = 1566.0;
const _mastR = 1580.0;
const _jibY = 32.0;
const _jibL = 1250.0;

class ConstructionAmbient extends StatefulWidget {
  const ConstructionAmbient({super.key});

  @override
  State<ConstructionAmbient> createState() => _ConstructionAmbientState();
}

class _ConstructionAmbientState extends State<ConstructionAmbient> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0);
  final _labels = SiteLabels();
  int _frame = 0;

  double get _now => DateTime.now().difference(_epoch).inMicroseconds / 1e6;

  @override
  void initState() {
    super.initState();
    _clock.value = _now;
    // 30 fps is plenty for slow scenery.
    _ticker = createTicker((_) {
      _frame++;
      if (_frame.isOdd) _clock.value = _now;
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    _labels.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(size: Size.infinite, painter: _AmbientPainter(_clock, _labels)),
    ),
  );
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.clock, this.labels) : super(repaint: clock);

  final ValueNotifier<double> clock;
  final SiteLabels labels;

  static Path? _mast;

  static Path _mastPath() {
    final p = Path()
      ..moveTo(_mastL, _jibY + 14)
      ..lineTo(_mastL, _ground)
      ..moveTo(_mastR, _jibY + 14)
      ..lineTo(_mastR, _ground);
    var left = true;
    for (var y = _jibY + 14; y < _ground - 1; y += 13) {
      p
        ..moveTo(left ? _mastL : _mastR, y)
        ..lineTo(left ? _mastR : _mastL, math.min(_ground, y + 13));
      left = !left;
    }
    // Jib along the top edge.
    p
      ..moveTo(_jibL, _jibY)
      ..lineTo(1600, _jibY)
      ..moveTo(_jibL, _jibY - 6)
      ..lineTo(1600, _jibY - 9);
    var up = true;
    for (var x = _jibL; x < 1600; x += 14) {
      final y0 = up ? _jibY : _jibY - 6 - 3 * (x - _jibL) / (1600 - _jibL);
      final x2 = x + 14;
      final y1 = up ? _jibY - 6 - 3 * (x2 - _jibL) / (1600 - _jibL) : _jibY;
      p
        ..moveTo(x, y0)
        ..lineTo(x2, y1);
      up = !up;
    }
    p
      ..addRect(const Rect.fromLTRB(_mastL - 4, _jibY, _mastR + 4, _jibY + 14))
      ..addRect(const Rect.fromLTRB(_mastL - 12, _ground - 6, _mastR + 12, _ground));
    return p;
  }

  @override
  void paint(Canvas c, Size size) {
    final t = clock.value;
    final crew = SiteCrew(ink: BP.inkFaint, hat: BP.amber.withValues(alpha: 0.5), width: 1.3, scale: 1.0);
    final k = SiteKit(c, t, labels, crew);

    // Crane.
    c.drawPath(_mast ??= _mastPath(), strokeP(BP.lineFaint, 1));
    // Trolley drifting along the jib, a short cable, the hook swaying.
    final ph = (t / 46) % 1.0;
    final f = ph < 0.5 ? ph * 2 : 2 - ph * 2;
    final tx = lerpD(_jibL + 40, _mastL - 30, eio(f));
    final sway = math.sin(t * 1.1) * 0.06;
    final hookY = _jibY + 18 + 4 * math.sin(t * 0.5);
    c.drawRect(Rect.fromLTRB(tx - 7, _jibY + 1, tx + 7, _jibY + 5), strokeP(BP.lineDim, 1));
    final tip = Offset(tx + math.sin(sway) * (hookY - _jibY), hookY);
    c.drawLine(Offset(tx, _jibY + 5), tip, strokeP(BP.lineFaint, 1));
    final hk = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx, tip.dy + 4)
      ..arcTo(Rect.fromCircle(center: Offset(tip.dx - 2.5, tip.dy + 4), radius: 2.5), 0, math.pi * 0.9, false);
    c.drawPath(hk, strokeP(BP.amber.withValues(alpha: 0.35), 1.2));

    // Cones.
    k.cone(const Offset(30, _ground), alpha: 0.45, s: 0.9);
    k.cone(const Offset(48, _ground), alpha: 0.45, s: 0.9);
    k.cone(const Offset(1548, _ground), alpha: 0.45, s: 0.9);

    // A worker strolling along the ground line, stopping now and then.
    const period = 150.0;
    final u = (t % period) / period;
    final out = u < 0.5;
    final g = out ? u * 2 : 2 - u * 2;
    final f3 = g * 3;
    final leg = f3.floor().clamp(0, 2);
    final r = f3 - leg;
    final pause = (out ? r : 1 - r) > 0.86;
    final pos = (leg + (out ? seg01(r, 0, 0.86) : 1 - seg01(1 - r, 0, 0.86))) / 3;
    final wx = lerpD(70, 1500, pos);
    final face = out ? 1.0 : -1.0;
    final wave = math.sin(t * 8) * 0.35;
    crew.walker(
      Offset(wx, _ground),
      face: face,
      walk: pause ? 0 : t * 7,
      stride: pause ? 0 : 0.8,
      armF: pause ? 2.7 + wave : null,
      armB: pause ? -0.1 : null,
    );

    // Coffee break at the foot of the crane.
    const seat = Offset(1536, _ground - 12);
    c.drawRect(const Rect.fromLTRB(1530, _ground - 12, 1542, _ground), strokeP(BP.lineFaint, 1));
    final sip = (t % 9.0) < 1.8;
    final (hand, _, h2) = crew.sitter(seat, face: -1, armF: 2.1, handF: sip ? null : seat + const Offset(-8, -5));
    final cup = sip ? h2 + const Offset(-4, 3) : hand;
    c.drawRect(Rect.fromCenter(center: cup, width: 4, height: 5), strokeP(BP.inkFaint, 1.1));
    if (!sip) k.steam(cup, 0.3, alpha: 0.4);
    crew.flush(c);
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => false;
}
