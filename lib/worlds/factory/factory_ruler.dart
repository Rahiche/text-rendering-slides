import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../deck/deck.dart';
import '../../deck/theme.dart';
import 'factory_kit.dart';

/// The factory floor under every slide: a conveyor with one crate per slide.
/// Past crates are sealed, the current one sits under a lamp (filling up as
/// its build steps advance), section starts hang hall signs. Click a crate to
/// jump; hover to read its slide's title; click the counter for the index.
///
/// Local coordinates: 1600 × 110 (canvas y 790–900).
class FactoryRuler extends StatefulWidget {
  const FactoryRuler({super.key, required this.controller});

  final DeckController controller;

  @override
  State<FactoryRuler> createState() => _FactoryRulerState();
}

// Layout (local).
const _x0 = 206.0;
const _x1 = 1394.0;
const _railY = 19.0;
const _crateTop = 44.0;
const _crateH = 18.0;
const _beltY = 62.0;
const _floorY = 86.0;
const _counter = Rect.fromLTRB(1418, 34, 1540, 66);

/// Hall number for a section id.
String hallOf(String section) => switch (section) {
  'intro' => 'gate',
  'basics' => 'hall 01',
  'scripts' => 'hall 02',
  'others' => 'hall 03',
  'flutter' => 'hall 04',
  'journey' => 'hall 05',
  'outro' => 'exit',
  _ => section,
};

String _signOf(String section) => switch (section) {
  'basics' => '01',
  'scripts' => '02',
  'others' => '03',
  'flutter' => '04',
  'journey' => '05',
  'outro' => 'end',
  _ => '',
};

class _Geo {
  _Geo(this.n) : pitch = (_x1 - _x0 - 16) / math.max(1, n);

  final int n;
  final double pitch;

  double cx(int i) => _x0 + 8 + pitch * (i + 0.5);
  double get crateW => math.min(24, pitch - 6);

  int? hit(Offset p) {
    if (p.dy < _crateTop - 14 || p.dy > _beltY + 8) return null;
    final i = ((p.dx - _x0 - 8) / pitch).floor();
    return i >= 0 && i < n ? i : null;
  }
}

class _FactoryRulerState extends State<FactoryRuler> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _anim = ValueNotifier<double>(10); // seconds since the lamp set off
  final _text = TextCache();
  int? _hover;
  bool _hoverCounter = false;
  int _index = -1;
  double _from = 0; // lamp position (slide units) when it set off
  double _to = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) {
      _anim.value = d.inMicroseconds / 1e6;
      if (_anim.value > 2.6) _ticker.stop();
    });
    _index = widget.controller.index;
    _from = _to = _index.toDouble();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _anim.dispose();
    _text.dispose();
    super.dispose();
  }

  /// Where the lamp is right now, in slide units.
  double get _lampPos => _lampAt(_anim.value);

  double _lampAt(double a) {
    final dur = _travel;
    return lerp(_from, _to, eio(a / dur));
  }

  double get _travel => 0.45 + math.min(0.5, (_to - _from).abs() * 0.05);

  void _sync() {
    final i = widget.controller.index;
    if (i == _index) return;
    final now = _lampPos;
    _index = i;
    _from = now;
    _to = i.toDouble();
    _ticker.stop();
    _anim.value = 0;
    _ticker.start();
  }

  @override
  Widget build(BuildContext context) {
    _sync();
    final c = widget.controller;
    final geo = _Geo(c.slides.length);
    return RepaintBoundary(
      child: MouseRegion(
        cursor: _hover != null || _hoverCounter ? SystemMouseCursors.click : MouseCursor.defer,
        onHover: (e) {
          final h = geo.hit(e.localPosition);
          final hc = _counter.contains(e.localPosition);
          if (h != _hover || hc != _hoverCounter) {
            setState(() {
              _hover = h;
              _hoverCounter = hc;
            });
          }
        },
        onExit: (_) {
          if (_hover != null || _hoverCounter) {
            setState(() {
              _hover = null;
              _hoverCounter = false;
            });
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (d) {
            final h = geo.hit(d.localPosition);
            if (h != null) {
              c.goTo(h);
            } else if (_counter.contains(d.localPosition)) {
              c.toggleOverview();
            }
          },
          child: CustomPaint(
            size: Size.infinite,
            painter: _RulerPainter(
              anim: _anim,
              state: this,
              geo: geo,
              slides: c.slides,
              index: c.index,
              step: c.step,
              hover: _hover,
              hoverCounter: _hoverCounter,
            ),
          ),
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.anim,
    required this.state,
    required this.geo,
    required this.slides,
    required this.index,
    required this.step,
    required this.hover,
    required this.hoverCounter,
  }) : super(repaint: anim);

  final ValueNotifier<double> anim;
  final _FactoryRulerState state;
  final _Geo geo;
  final List<SlideDef> slides;
  final int index;
  final int step;
  final int? hover;
  final bool hoverCounter;

  @override
  void paint(Canvas canvas, Size size) {
    final k = FactoryInk(canvas);
    final a = anim.value;
    final txt = state._text;
    final lamp = state._lampAt(a);
    final moving = a < state._travel;

    // Floor.
    k.floor(44, 1556, _floorY, col: BP.lineDim);

    // Belt: frame, legs, rollers. The belt slats creep while the lamp moves.
    final shift = (lamp * 9) % 18;
    canvas.drawRect(Rect.fromLTRB(_x0, _beltY, _x1, _beltY + 7), k.fl(BP.panel));
    final slats = Path();
    for (var x = _x0 + 4 + shift; x < _x1 - 2; x += 18) {
      slats
        ..moveTo(x, _beltY + 1)
        ..lineTo(x - 3, _beltY + 6);
    }
    canvas.drawPath(slats, k.st(BP.lineFaint, 1));
    canvas.drawLine(const Offset(_x0, _beltY), const Offset(_x1, _beltY), k.st(BP.lineDim, 1.2));
    canvas.drawLine(const Offset(_x0, _beltY + 7), const Offset(_x1, _beltY + 7), k.st(BP.lineDim, 1.2));
    canvas.drawCircle(const Offset(_x0, _beltY + 3.5), 3.5, k.st(BP.lineDim, 1));
    canvas.drawCircle(const Offset(_x1, _beltY + 3.5), 3.5, k.st(BP.lineDim, 1));
    final legs = Path();
    for (var i = 0; i <= 8; i++) {
      final x = lerp(_x0 + 14, _x1 - 14, i / 8);
      legs
        ..moveTo(x - 2.5, _beltY + 7)
        ..lineTo(x - 2.5, _floorY)
        ..moveTo(x + 2.5, _beltY + 7)
        ..lineTo(x + 2.5, _floorY)
        ..moveTo(x - 7, _floorY - 1)
        ..lineTo(x + 7, _floorY - 1);
    }
    canvas.drawPath(legs, k.st(BP.lineFaint, 1.1));
    final rollers = Path();
    final ra = lamp * 2.2;
    for (var x = _x0 + 30.0; x < _x1 - 10; x += 44) {
      rollers
        ..addOval(Rect.fromCircle(center: Offset(x, _beltY + 12), radius: 3))
        ..moveTo(x, _beltY + 12)
        ..lineTo(x + math.cos(ra) * 3, _beltY + 12 + math.sin(ra) * 3);
    }
    canvas.drawPath(rollers, k.st(BP.lineFaint, 1));

    // Overhead rail for signs and the lamp trolley.
    canvas.drawLine(const Offset(_x0 - 6, _railY), const Offset(_x1 + 6, _railY), k.st(BP.lineFaint, 1.2));
    for (final x in [_x0 - 6, _x1 + 6]) {
      canvas.drawLine(Offset(x, _railY - 4), Offset(x, _railY + 4), k.st(BP.lineDim, 1.2));
    }

    // Hall signs at section starts.
    for (var i = 0; i < slides.length; i++) {
      if (i > 0 && slides[i].section == slides[i - 1].section) continue;
      final label = _signOf(slides[i].section);
      if (label.isEmpty) continue;
      final x = geo.cx(i) - geo.pitch / 2;
      final active = slides[index].section == slides[i].section;
      final tp = txt.get(label, BT.mono(10, color: active ? BP.amber : BP.inkDim, weight: active ? 600 : 400));
      final r = Rect.fromCenter(center: Offset(x, _railY + 10), width: tp.width + 8, height: 12);
      canvas.drawLine(Offset(x, _railY), Offset(x, r.top), k.st(BP.lineDim, 1));
      canvas.drawRect(r, k.fl(BP.paper));
      canvas.drawRect(r, k.st(active ? BP.amber : BP.lineDim, 1));
      tp.paint(canvas, Offset(r.left + 4, r.top + (r.height - tp.height) / 2));
      // A floor mark where the hall begins.
      canvas.drawLine(Offset(x, _beltY + 9), Offset(x, _floorY), k.st(active ? BP.amber.withValues(alpha: 0.5) : BP.lineFaint, 1));
    }

    // Crates.
    final w = geo.crateW;
    for (var i = 0; i < slides.length; i++) {
      final cx = geo.cx(i);
      final hot = hover == i;
      final lift = hot ? 4.0 : 0.0;
      final r = Rect.fromLTWH(cx - w / 2, _crateTop - lift, w, _crateH);
      if (i == index) {
        // The current crate: open, filling as the build steps advance.
        canvas.drawRect(r, k.fl(BP.panel));
        final steps = slides[i].steps;
        final f = (step + 1) / steps;
        final fillTop = lerp(r.bottom - 2, r.top + 2, f);
        canvas.drawRect(Rect.fromLTRB(r.left + 2, fillTop, r.right - 2, r.bottom - 2), k.fl(BP.amber.withValues(alpha: 0.35)));
        if (steps > 1) {
          for (var s = 1; s < steps; s++) {
            final y = lerp(r.bottom - 2, r.top + 2, s / steps);
            canvas.drawLine(Offset(r.left + 2, y), Offset(r.left + 5, y), k.st(BP.amber.withValues(alpha: 0.7), 1));
          }
        }
        canvas.drawRect(r, k.st(BP.amber, 1.6));
        // Flaps open.
        canvas.drawLine(r.topLeft, r.topLeft + const Offset(-5, -4), k.st(BP.amber, 1.3));
        canvas.drawLine(r.topRight, r.topRight + const Offset(5, -4), k.st(BP.amber, 1.3));
      } else if (i < index) {
        // Sealed and inspected.
        canvas.drawRect(r, k.fl(BP.panel));
        canvas.drawRect(r, k.st(hot ? BP.amber : BP.line.withValues(alpha: 0.75), 1.1));
        canvas.drawLine(Offset(r.left, r.top + 5), Offset(r.right, r.top + 5), k.st(BP.lineDim, 0.8));
        final m = Offset(r.center.dx, r.center.dy + 2.5);
        canvas.drawPath(
          Path()
            ..moveTo(m.dx - 3.5, m.dy)
            ..lineTo(m.dx - 1, m.dy + 2.5)
            ..lineTo(m.dx + 4, m.dy - 3),
          k.st(BP.green.withValues(alpha: 0.75), 1.1),
        );
      } else {
        // Still to come: empty outlines.
        canvas.drawRect(r, k.fl(BP.paper));
        canvas.drawRect(r, k.st(hot ? BP.amber : BP.lineDim, 1));
      }
    }

    // The lamp trolley over the current crate.
    final lx = lerp(geo.cx(lamp.floor().clamp(0, geo.n - 1)), geo.cx(lamp.ceil().clamp(0, geo.n - 1)), lamp - lamp.floorToDouble());
    final since = a - state._travel;
    final swing = moving
        ? -0.25 * math.sin(math.pi * seg(a, 0, state._travel)) * (state._to > state._from ? 1 : -1)
        : 0.22 * math.exp(-since * 2.6) * math.sin(since * 9) * (state._to > state._from ? 1 : -1);
    final troll = Rect.fromCenter(center: Offset(lx, _railY - 1), width: 14, height: 6);
    canvas.drawRect(troll, k.fl(BP.panel));
    canvas.drawRect(troll, k.st(BP.line, 1.1));
    const cable = 9.0;
    final shade = Offset(lx + math.sin(swing) * cable, _railY + 2 + math.cos(swing) * cable);
    canvas.drawLine(Offset(lx, _railY + 2), shade, k.st(BP.lineDim, 1));
    final cone = Path()
      ..moveTo(shade.dx - 4, shade.dy + 4)
      ..lineTo(shade.dx + 4, shade.dy + 4)
      ..lineTo(lx + w / 2 + 6, _crateTop)
      ..lineTo(lx - w / 2 - 6, _crateTop)
      ..close();
    canvas.drawPath(cone, k.fl(BP.amber.withValues(alpha: moving ? 0.06 : 0.14)));
    canvas.save();
    canvas.translate(shade.dx, shade.dy);
    canvas.rotate(-swing);
    final sp = Path()
      ..moveTo(-3, 0)
      ..lineTo(3, 0)
      ..lineTo(7, 5)
      ..lineTo(-7, 5)
      ..close();
    canvas.drawPath(sp, k.fl(BP.panel));
    canvas.drawPath(sp, k.st(BP.amber, 1.1));
    canvas.drawCircle(const Offset(0, 5.5), 2, k.fl(BP.amber.withValues(alpha: moving ? 0.5 : 1)));
    canvas.restore();

    // A small check mark flashes on the crate when it lands.
    final qc = seg(since, 0.1, 1.4);
    if (!moving && qc > 0 && qc < 1) {
      final cx = geo.cx(index);
      final o = Offset(cx + w / 2 + 7, _crateTop - 4 - 6 * eo(qc));
      final p = Path()
        ..moveTo(o.dx - 3.5, o.dy)
        ..lineTo(o.dx - 1, o.dy + 2.8)
        ..lineTo(o.dx + 4.5, o.dy - 3.5);
      canvas.drawPath(p, k.st(BP.green.withValues(alpha: 1 - qc), 1.5));
    }

    // Section, left; counter, right.
    final sec = slides[index].section;
    final hall = txt.get(hallOf(sec), BT.mono(11, color: BP.inkFaint));
    hall.paint(canvas, const Offset(64, 34));
    final name = txt.get(sec, BT.mono(15, color: BP.inkDim));
    name.paint(canvas, Offset(64, 34 + hall.height));
    final n = slides.length;
    final count = txt.get(
      '${(index + 1).toString().padLeft(2, '0')} / ${n.toString().padLeft(2, '0')}',
      BT.mono(15, color: hoverCounter ? BP.amber : BP.line),
    );
    count.paint(canvas, Offset(_counter.right - 4 - count.width, _counter.center.dy - count.height / 2));

    // Tooltip.
    final h = hover;
    if (h != null) {
      final tp = txt.get(slides[h].title, BT.mono(13, color: BP.ink));
      final cx = geo.cx(h).clamp(tp.width / 2 + 80, size.width - tp.width / 2 - 80);
      final r = Rect.fromCenter(center: Offset(cx, 4), width: tp.width + 20, height: tp.height + 8);
      canvas.drawRect(r, k.fl(BP.panel));
      canvas.drawRect(r, k.st(BP.line, 1));
      tp.paint(canvas, Offset(r.left + 10, r.top + 4));
      canvas.drawLine(Offset(geo.cx(h), r.bottom), Offset(geo.cx(h), _crateTop - 6), k.st(BP.line, 1));
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.index != index || old.step != step || old.hover != hover || old.hoverCounter != hoverCounter || old.geo.n != geo.n;
}
