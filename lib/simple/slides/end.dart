import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';

/// Closing slide: a balance between owning the stack (control, consistency,
/// effects) and using the platform's (native features, fidelity). Under it,
/// a control ↔ native spectrum (blue ↔ coral, like the pans); each engine
/// chip tips the beam to where it sits, on a spring. Flutter is picked first
/// and held, so the still a few seconds in shows Flutter's side.
class EndSlide extends StatefulWidget {
  const EndSlide({super.key});

  @override
  State<EndSlide> createState() => _EndSlideState();
}

class _Engine {
  const _Engine(this.name, this.tilt, this.above);

  final String name;

  /// -1 = all control, +1 = all native.
  final double tilt;

  /// Chip row on the ruler (to keep neighbours apart).
  final bool above;
}

const _engines = [
  _Engine('Chrome', 0.62, false),
  _Engine('Figma', -0.9, true),
  _Engine('macOS', 0.88, true),
  _Engine('Android', 0.04, true),
  _Engine('Flutter', -0.72, false),
];

const _flutter = 4;

// Scale geometry (content coords, 1472 × 612).
const _pivot = Offset(736, 84);
const _arm = 420.0;
const _hang = 200.0;
const _maxAngle = 0.2;
const _foot = Offset(736, 410);
const _rulerY = 522.0;
const _rulerX0 = 236.0;
const _rulerX1 = 1236.0;

double _rulerX(double tilt) => _lerp(_rulerX0, _rulerX1, (tilt + 1) / 2);
double _lerp(double a, double b, double t) => a + (b - a) * t;

Paint _stroke(Color c, [double w = 1]) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w;

/// Beam state, integrated as a damped spring.
class _Balance extends ChangeNotifier {
  double tau = 0;
  double vel = 0;

  void step(double target, double dt) {
    const k = 38.0;
    const c = 4.4;
    vel += (k * (target - tau) - c * vel) * dt;
    tau += vel * dt;
    notifyListeners();
  }
}

class _EndSlideState extends State<EndSlide> with SingleTickerProviderStateMixin {
  static const _autoOrder = [_flutter, 0, 1, 2, 3];

  final _bal = _Balance();
  final _labels = <String, TextPainter>{};
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _time = 0;
  double _userAt = -100;
  double _nextAuto = 1.0;
  int _autoI = 0;
  int _sel = -1;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _bal.dispose();
    for (final p in _labels.values) {
      p.dispose();
    }
    super.dispose();
  }

  void _tick(Duration d) {
    final dt = ((d - _last).inMicroseconds / 1e6).clamp(0.0, 1 / 30);
    _last = d;
    _time += dt;
    if (_time - _userAt > 10 && _time >= _nextAuto) {
      final next = _autoOrder[_autoI++ % _autoOrder.length];
      setState(() => _sel = next);
      // Flutter stays on longer: it's the point (and the exported still).
      _nextAuto = _time + (next == _flutter ? 6.0 : 3.4);
    }
    _bal.step(_sel < 0 ? 0 : _engines[_sel].tilt, dt);
  }

  void _select(int i) {
    setState(() => _sel = i);
    _userAt = _time;
  }

  TextPainter _label(String s) => _labels.putIfAbsent(
    s,
    () => TextPainter(
      text: TextSpan(text: s, style: BT.mono(22, color: BP.ink)),
      textDirection: TextDirection.ltr,
    )..layout(),
  );

  @override
  Widget build(BuildContext context) {
    return SlideFrame(
      title: 'The trade-off',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _ScalePainter(balance: _bal, label: _label, selected: _sel),
            ),
          ),
          // Engine chips, sitting on the ruler where each engine sits
          for (var i = 0; i < _engines.length; i++)
            Positioned(
              left: _rulerX(_engines[i].tilt),
              top: _engines[i].above ? _rulerY - 74 : _rulerY + 30,
              child: FractionalTranslation(
                translation: const Offset(-0.5, 0),
                child: BpButton(
                  label: _engines[i].name,
                  selected: _sel == i,
                  size: 21,
                  color: i == _flutter ? BP.amber : BP.line,
                  onTap: () => _select(i),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScalePainter extends CustomPainter {
  _ScalePainter({required this.balance, required this.label, required this.selected})
    : super(repaint: balance);

  final _Balance balance;
  final TextPainter Function(String) label;
  final int selected;

  static const _left = ['control', 'consistency', 'effects'];
  static const _right = ['native features', 'platform fidelity'];

  @override
  void paint(Canvas canvas, Size size) {
    final tau = balance.tau;
    final a = tau * _maxAngle;
    final omega = balance.vel * _maxAngle;
    final swing = (-omega * 0.35).clamp(-0.35, 0.35);
    final dir = Offset(math.cos(a), math.sin(a));
    final eL = _pivot - dir * _arm;
    final eR = _pivot + dir * _arm;

    // Stand
    canvas.drawPath(
      dashPath(Path()
        ..moveTo(_foot.dx - 300, _foot.dy + 18)
        ..lineTo(_foot.dx + 300, _foot.dy + 18), dash: 8, gap: 6),
      _stroke(BP.lineDim),
    );
    final base = Path()
      ..moveTo(_foot.dx - 96, _foot.dy + 18)
      ..lineTo(_foot.dx - 30, _foot.dy)
      ..lineTo(_foot.dx + 30, _foot.dy)
      ..lineTo(_foot.dx + 96, _foot.dy + 18)
      ..close();
    canvas.drawPath(base, Paint()..color = BP.panel);
    canvas.drawPath(base, _stroke(BP.line, 1.6));
    canvas.drawLine(_pivot, _foot, _stroke(BP.line, 2.4));
    canvas.drawLine(_pivot + const Offset(-7, 0), _foot + const Offset(-7, 0), _stroke(BP.lineDim));
    canvas.drawLine(_pivot + const Offset(7, 0), _foot + const Offset(7, 0), _stroke(BP.lineDim));

    // Dial + needle
    const r = 78.0;
    final arcRect = Rect.fromCircle(center: _pivot, radius: r);
    canvas.drawArc(arcRect, -math.pi / 2 - 0.62, 1.24, false, _stroke(BP.lineDim, 1.2));
    for (var k = -4; k <= 4; k++) {
      final th = -math.pi / 2 + k * 0.15;
      final u = Offset(math.cos(th), math.sin(th));
      final l = k == 0 ? 14.0 : (k.isEven ? 9.0 : 6.0);
      canvas.drawLine(_pivot + u * r, _pivot + u * (r - l), _stroke(k == 0 ? BP.line : BP.lineDim, 1.2));
    }
    final th = -math.pi / 2 + a * 2.8;
    canvas.drawLine(
      _pivot,
      _pivot + Offset(math.cos(th), math.sin(th)) * (r - 4),
      Paint()
        ..color = BP.amber
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // Pans (drawn before the beam so the beam sits on top of the hooks)
    _pan(canvas, eL, swing, _left, BP.line, (1 - tau) / 2);
    _pan(canvas, eR, swing, _right, BP.coral, (1 + tau) / 2);

    // Beam
    canvas.save();
    canvas.translate(_pivot.dx, _pivot.dy);
    canvas.rotate(a);
    final beam = Rect.fromLTRB(-_arm - 14, -6, _arm + 14, 6);
    canvas.drawRect(beam, Paint()..color = BP.panel);
    canvas.drawRect(beam, _stroke(BP.line, 1.8));
    for (var x = -_arm + 30; x < _arm - 10; x += 30) {
      if (x.abs() < 20) continue;
      canvas.drawLine(Offset(x, -6), Offset(x, x % 60 == 0 ? 3 : 0), _stroke(BP.lineDim));
    }
    for (final x in [-_arm, _arm]) {
      canvas.drawCircle(Offset(x, 0), 7, Paint()..color = BP.paper);
      canvas.drawCircle(Offset(x, 0), 7, _stroke(BP.line, 1.8));
    }
    canvas.restore();

    // Pivot
    final d = Path()
      ..moveTo(_pivot.dx, _pivot.dy - 13)
      ..lineTo(_pivot.dx + 13, _pivot.dy)
      ..lineTo(_pivot.dx, _pivot.dy + 13)
      ..lineTo(_pivot.dx - 13, _pivot.dy)
      ..close();
    canvas.drawPath(d, Paint()..color = BP.amber);

    // Spectrum ruler: control (blue, like the left pan) ↔ native (coral).
    const x0 = _rulerX0;
    const x1 = _rulerX1;
    final rl = Paint()
      ..strokeWidth = 2.4
      ..shader = const LinearGradient(
        colors: [BP.line, BP.lineDim, BP.coral],
      ).createShader(Rect.fromLTRB(x0, _rulerY - 1, x1, _rulerY + 1));
    canvas.drawLine(const Offset(x0 - 16, _rulerY), const Offset(x1 + 16, _rulerY), rl);
    drawArrowHead(canvas, const Offset(x0 - 18, _rulerY), const Offset(x0, _rulerY), _stroke(BP.line, 2.4), 11);
    drawArrowHead(canvas, const Offset(x1 + 18, _rulerY), const Offset(x1, _rulerY), _stroke(BP.coral, 2.4), 11);
    for (var k = 0; k <= 20; k++) {
      final x = _lerp(x0, x1, k / 20);
      final h = k % 10 == 0 ? 12.0 : (k % 5 == 0 ? 8.0 : 4.0);
      canvas.drawLine(Offset(x, _rulerY - h), Offset(x, _rulerY + h), _stroke(BP.lineDim, 1.2));
    }
    for (var i = 0; i < _engines.length; i++) {
      final e = _engines[i];
      final x = _rulerX(e.tilt);
      final hot = i == selected;
      final c = hot ? BP.amber : BP.line;
      final y1 = e.above ? _rulerY - 30 : _rulerY + 30;
      canvas.drawLine(Offset(x, _rulerY), Offset(x, y1), _stroke(c, hot ? 2.4 : 1.4));
      canvas.drawCircle(Offset(x, _rulerY), hot ? 6.5 : 4.5, Paint()..color = c);
    }
    // Where the beam actually is right now
    final px = _rulerX(tau.clamp(-1.1, 1.1));
    final tri = Path()
      ..moveTo(px, _rulerY - 4)
      ..lineTo(px - 11, _rulerY - 22)
      ..lineTo(px + 11, _rulerY - 22)
      ..close();
    canvas.drawPath(tri, Paint()..color = BP.amber);
  }

  void _pan(Canvas canvas, Offset hook, double swing, List<String> words, Color c, double weight) {
    final w = weight.clamp(0.0, 1.0);
    canvas.save();
    canvas.translate(hook.dx, hook.dy);
    canvas.rotate(swing);
    const rim = _hang;
    const half = 156.0;
    final string = _stroke(BP.lineDim, 1.2);
    canvas.drawLine(Offset.zero, const Offset(-half + 6, rim), string);
    canvas.drawLine(Offset.zero, const Offset(half - 6, rim), string);

    // Weights, stacked bottom-up; they grow with how much this side matters.
    var y = rim - 2;
    for (final word in words.reversed) {
      final tp = label(word);
      final h = 36 + 16 * w;
      final bw = tp.width + 36;
      final r = Rect.fromLTWH(-bw / 2, y - h, bw, h);
      canvas.drawRect(r, Paint()..color = BP.panel);
      canvas.drawRect(r, Paint()..color = c.withValues(alpha: 0.06 + 0.22 * w));
      canvas.drawRect(r, _stroke(c, 1.2 + w));
      tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
      y -= h + 6;
    }

    final bowl = Path()
      ..moveTo(-half - 8, rim)
      ..quadraticBezierTo(0, rim + 56, half + 8, rim)
      ..close();
    canvas.drawPath(bowl, Paint()..color = BP.panel);
    canvas.drawPath(bowl, _stroke(BP.line, 1.8));
    canvas.drawCircle(Offset.zero, 5, Paint()..color = BP.line);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScalePainter old) => old.selected != selected || old.balance != balance;
}
