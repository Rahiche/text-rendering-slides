import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../deck/scripts.dart';
import '../deck/theme.dart';
import '../deck/widgets.dart';

/// Closing slide: a balance between owning the stack (control, consistency,
/// effects) and using the platform's (native features, fidelity). Each engine
/// chip tips the beam to where it sits, on a spring. Then: "Text", cycling.
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

// Scale geometry (content coords).
const _pivot = Offset(480, 118);
const _arm = 300.0;
const _hang = 190.0;
const _maxAngle = 0.24;
const _rulerY = 520.0;
const _rulerX0 = 120.0;
const _rulerX1 = 840.0;

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
  static const _autoOrder = [4, 0, 1, 2, 3];

  final _bal = _Balance();
  final _labels = <String, TextPainter>{};
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _time = 0;
  double _userAt = -100;
  double _nextAuto = 1.6;
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
      setState(() => _sel = _autoOrder[_autoI++ % _autoOrder.length]);
      _nextAuto = _time + 3.4;
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
      text: TextSpan(text: s, style: BT.mono(15, color: BP.ink)),
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
          // Ends of the spectrum
          Positioned(
            right: 1472 - _rulerX0 + 16,
            top: _rulerY - 11,
            child: Text('control', style: BT.mono(16, color: BP.line)),
          ),
          Positioned(
            left: _rulerX1 + 16,
            top: _rulerY - 11,
            child: Text('native', style: BT.mono(16, color: BP.coral)),
          ),
          // Engine chips, sitting on the ruler where each engine sits
          for (var i = 0; i < _engines.length; i++)
            Positioned(
              left: _rulerX(_engines[i].tilt),
              top: _engines[i].above ? _rulerY - 62 : _rulerY + 26,
              child: FractionalTranslation(
                translation: const Offset(-0.5, 0),
                child: BpButton(
                  label: _engines[i].name,
                  selected: _sel == i,
                  color: _engines[i].name == 'Flutter' ? BP.amber : BP.line,
                  onTap: () => _select(i),
                ),
              ),
            ),
          // Separator + finale
          Positioned(
            left: 968,
            top: 0,
            bottom: 0,
            width: 2,
            child: CustomPaint(painter: _VDashPainter()),
          ),
          const Positioned(left: 1000, top: 0, right: 0, bottom: 0, child: _Finale()),
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
    const foot = Offset(480, 424);
    canvas.drawPath(
      dashPath(Path()
        ..moveTo(260, foot.dy + 16)
        ..lineTo(700, foot.dy + 16), dash: 8, gap: 6),
      _stroke(BP.lineDim),
    );
    final base = Path()
      ..moveTo(foot.dx - 80, foot.dy + 16)
      ..lineTo(foot.dx - 26, foot.dy)
      ..lineTo(foot.dx + 26, foot.dy)
      ..lineTo(foot.dx + 80, foot.dy + 16)
      ..close();
    canvas.drawPath(base, Paint()..color = BP.panel);
    canvas.drawPath(base, _stroke(BP.line, 1.5));
    canvas.drawLine(_pivot, foot, _stroke(BP.line, 2));
    canvas.drawLine(_pivot + const Offset(-6, 0), foot + const Offset(-6, 0), _stroke(BP.lineDim));
    canvas.drawLine(_pivot + const Offset(6, 0), foot + const Offset(6, 0), _stroke(BP.lineDim));

    // Dial + needle
    const r = 66.0;
    final arcRect = Rect.fromCircle(center: _pivot, radius: r);
    canvas.drawArc(arcRect, -math.pi / 2 - 0.62, 1.24, false, _stroke(BP.lineDim));
    for (var k = -4; k <= 4; k++) {
      final th = -math.pi / 2 + k * 0.15;
      final u = Offset(math.cos(th), math.sin(th));
      final l = k == 0 ? 12.0 : (k.isEven ? 8.0 : 5.0);
      canvas.drawLine(_pivot + u * r, _pivot + u * (r - l), _stroke(k == 0 ? BP.line : BP.lineDim));
    }
    final th = -math.pi / 2 + a * 2.4;
    canvas.drawLine(
      _pivot,
      _pivot + Offset(math.cos(th), math.sin(th)) * (r - 4),
      Paint()
        ..color = BP.amber
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    // Pans (drawn before the beam so the beam sits on top of the hooks)
    _pan(canvas, eL, swing, _left, BP.line, (1 - tau) / 2);
    _pan(canvas, eR, swing, _right, BP.coral, (1 + tau) / 2);

    // Beam
    canvas.save();
    canvas.translate(_pivot.dx, _pivot.dy);
    canvas.rotate(a);
    final beam = Rect.fromLTRB(-_arm - 12, -5, _arm + 12, 5);
    canvas.drawRect(beam, Paint()..color = BP.panel);
    canvas.drawRect(beam, _stroke(BP.line, 1.5));
    for (var x = -_arm + 30; x < _arm - 10; x += 30) {
      if (x.abs() < 20) continue;
      canvas.drawLine(Offset(x, -5), Offset(x, x % 60 == 0 ? 3 : 0), _stroke(BP.lineDim));
    }
    for (final x in [-_arm, _arm]) {
      canvas.drawCircle(Offset(x, 0), 6, Paint()..color = BP.paper);
      canvas.drawCircle(Offset(x, 0), 6, _stroke(BP.line, 1.5));
    }
    canvas.restore();

    // Pivot
    final d = Path()
      ..moveTo(_pivot.dx, _pivot.dy - 11)
      ..lineTo(_pivot.dx + 11, _pivot.dy)
      ..lineTo(_pivot.dx, _pivot.dy + 11)
      ..lineTo(_pivot.dx - 11, _pivot.dy)
      ..close();
    canvas.drawPath(d, Paint()..color = BP.amber);

    // Ruler
    final rl = _stroke(BP.lineDim, 1.5);
    canvas.drawLine(const Offset(_rulerX0, _rulerY), const Offset(_rulerX1, _rulerY), rl);
    for (var k = 0; k <= 20; k++) {
      final x = _lerp(_rulerX0, _rulerX1, k / 20);
      final h = k % 10 == 0 ? 10.0 : (k % 5 == 0 ? 7.0 : 4.0);
      canvas.drawLine(Offset(x, _rulerY - h), Offset(x, _rulerY + h), _stroke(BP.lineDim));
    }
    for (var i = 0; i < _engines.length; i++) {
      final e = _engines[i];
      final x = _rulerX(e.tilt);
      final hot = i == selected;
      final p = _stroke(hot ? BP.amber : BP.line, hot ? 2 : 1.2);
      final y1 = e.above ? _rulerY - 24 : _rulerY + 24;
      canvas.drawLine(Offset(x, _rulerY), Offset(x, y1), p);
      canvas.drawCircle(Offset(x, _rulerY), hot ? 5 : 3.5, Paint()..color = hot ? BP.amber : BP.line);
    }
    // Where the beam actually is right now
    final px = _rulerX(tau.clamp(-1.1, 1.1));
    final tri = Path()
      ..moveTo(px, _rulerY - 3)
      ..lineTo(px - 9, _rulerY - 17)
      ..lineTo(px + 9, _rulerY - 17)
      ..close();
    canvas.drawPath(tri, Paint()..color = BP.amber);
  }

  void _pan(Canvas canvas, Offset hook, double swing, List<String> words, Color c, double weight) {
    final w = weight.clamp(0.0, 1.0);
    canvas.save();
    canvas.translate(hook.dx, hook.dy);
    canvas.rotate(swing);
    const rim = _hang;
    const half = 118.0;
    final string = _stroke(BP.lineDim);
    canvas.drawLine(Offset.zero, const Offset(-half + 6, rim), string);
    canvas.drawLine(Offset.zero, const Offset(half - 6, rim), string);

    // Weights, stacked bottom-up; they grow with how much this side matters.
    var y = rim - 2;
    for (final word in words.reversed) {
      final tp = label(word);
      final h = 26 + 16 * w;
      final bw = tp.width + 28;
      final r = Rect.fromLTWH(-bw / 2, y - h, bw, h);
      canvas.drawRect(r, Paint()..color = BP.panel);
      canvas.drawRect(r, Paint()..color = c.withValues(alpha: 0.06 + 0.22 * w));
      canvas.drawRect(r, _stroke(c, 1 + w));
      tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
      y -= h + 5;
    }

    final bowl = Path()
      ..moveTo(-half - 6, rim)
      ..quadraticBezierTo(0, rim + 50, half + 6, rim)
      ..close();
    canvas.drawPath(bowl, Paint()..color = BP.panel);
    canvas.drawPath(bowl, _stroke(BP.line, 1.5));
    canvas.drawCircle(Offset.zero, 4, Paint()..color = BP.line);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScalePainter old) => old.selected != selected || old.balance != balance;
}

class _VDashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      dashPath(Path()
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width / 2, size.height), dash: 6, gap: 6),
      _stroke(BP.lineFaint),
    );
  }

  @override
  bool shouldRepaint(_VDashPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Finale: "Text" in many scripts, then questions.
// ─────────────────────────────────────────────────────────────────────────────

class _Finale extends StatefulWidget {
  const _Finale();

  @override
  State<_Finale> createState() => _FinaleState();
}

class _FinaleState extends State<_Finale> {
  static const _words = ['Text', 'نص', 'टेक्स्ट', '文字', 'טקסט', 'ข้อความ', '텍스트', 'Текст'];

  int _i = 0;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      setState(() => _i = (_i + 1) % _words.length);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final word = _words[_i];
    final script = itemize(word).first.script;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 20,
          height: 340,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 650),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (cur, prev) => Stack(fit: StackFit.expand, children: [...prev, ?cur]),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.05), end: Offset.zero).animate(anim),
                child: child,
              ),
            ),
            child: CustomPaint(key: ValueKey(word), painter: _WordPainter(word)),
          ),
        ),
        Positioned(
          left: 0,
          top: 372,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: Text(
              script.label,
              key: ValueKey(word),
              style: BT.mono(15, color: script.color),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 470,
          child: LoopBuilder(
            period: const Duration(milliseconds: 1100),
            builder: (context, t, _) => Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('questions?', style: BT.mono(34, color: BP.amber, weight: 500)),
                const SizedBox(width: 8),
                Opacity(
                  opacity: t < 0.5 ? 1 : 0,
                  child: Container(width: 18, height: 38, color: BP.amber),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The word on a baseline, with its grapheme boxes from the real layout.
class _WordPainter extends CustomPainter {
  _WordPainter(this.word);

  final String word;

  static const _baseline = 230.0;

  @override
  void paint(Canvas canvas, Size size) {
    TextProbe make(double s) => TextProbe(
      TextSpan(text: word, style: BT.sample(s, weight: 500)),
      textDirection: itemize(word).first.rtl ? TextDirection.rtl : TextDirection.ltr,
    );
    var probe = make(150);
    final maxW = size.width - 20;
    if (probe.size.width > maxW) {
      final s = 150 * maxW / probe.size.width;
      probe.dispose();
      probe = make(s);
    }
    final line = probe.lines.first;
    final origin = Offset(0, _baseline - line.baseline);

    final g = _stroke(BP.lineDim);
    for (final y in [_baseline - line.ascent, _baseline + line.descent]) {
      canvas.drawPath(
        dashPath(Path()
          ..moveTo(0, y)
          ..lineTo(size.width, y), dash: 8, gap: 6),
        g,
      );
    }
    canvas.drawLine(Offset(0, _baseline), Offset(size.width, _baseline), _stroke(BP.line, 1.5));

    final box = _stroke(BP.lineDim);
    for (final (s, e) in probe.graphemes()) {
      for (final b in probe.boxes(s, e)) {
        canvas.drawPath(dashPath(Path()..addRect(b.toRect().shift(origin)), dash: 5, gap: 5), box);
      }
    }
    probe.paint(canvas, origin);
    probe.dispose();
  }

  @override
  bool shouldRepaint(_WordPainter old) => old.word != word;
}
