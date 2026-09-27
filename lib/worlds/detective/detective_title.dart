import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'noir_kit.dart';

/// Title: a huge 直 under a street lamp in the rain. Outside the magnifying
/// glass it is the Japanese form (real Noto Sans JP outline); inside, the
/// same code point in its Chinese form (Noto Sans SC), where they differ
/// flashes red. The detective walks the street below.
class DetectiveTitle extends StatefulWidget {
  const DetectiveTitle({super.key});

  @override
  State<DetectiveTitle> createState() => _DetectiveTitleState();
}

// Exhibits: 直 keeps coming back between the others.
const _exhibits = '直今直骨直令直角直海直誤直次直画';
const _exhibitSecs = 17.0;

// Scene geometry (canvas coordinates).
const _box = Rect.fromLTWH(1010, 100, 456, 456);
const _lamp = Offset(1238, 58);
const _street = 770.0;
const _lensR = 112.0;
const _detH = 140.0;
const _home = 900.0;

class _DetectiveTitleState extends State<DetectiveTitle> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(0);
  final _labels = LabelCache();

  int _exhibit = 0;
  int _prevExhibit = 0;
  double _since = 0;
  Offset? _pointer;
  double _pointerAt = -99;
  double _tipAt = -99;
  Offset _lens = _box.center;
  double _lastT = 0;

  int get cp => _exhibits.runes.elementAt(_exhibit % _exhibits.runes.length);
  int get prevCp => _exhibits.runes.elementAt(_prevExhibit % _exhibits.runes.length);

  @override
  void initState() {
    super.initState();
    CaseFonts.load().then((_) {
      if (mounted) setState(() {});
    });
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration d) {
    final t = d.inMicroseconds / 1e6;
    final dt = (t - _lastT).clamp(0.0, 0.1);
    _lastT = t;
    if (t - _since > _exhibitSecs) _next(t);
    // Lens target: the pointer when the presenter hovers the glyph,
    // otherwise a patrol over the strokes that differ.
    final fonts = CaseFonts.ready;
    Offset target = _box.center;
    if (_pointer != null && t - _pointerAt < 4) {
      target = _pointer!;
    } else if (fonts != null) {
      target = _patrol(fonts, t);
    }
    final k = 1 - math.pow(0.02, dt).toDouble();
    _lens = Offset.lerp(_lens, target, k.clamp(0.0, 1.0))!;
    _time.value = t;
  }

  /// Hot spots: centres of the contours that have no twin in the other form.
  Offset _patrol(CaseFonts f, double t) {
    final spots = _spots(f, cp);
    if (spots.isEmpty) return _box.center;
    const hop = 3.6;
    final u = (t - _since) / hop;
    final i = u.floor();
    final a = spots[i % spots.length];
    final b = spots[(i + 1) % spots.length];
    final m = seg(u - i, 0.55, 1.0);
    final jitter = Offset(noise1(t * 0.9, 3), noise1(t * 0.9, 7)) * 6;
    return Offset.lerp(a, b, m)! + jitter;
  }

  final Map<int, List<Offset>> _spotCache = {};

  List<Offset> _spots(CaseFonts f, int c) => _spotCache.putIfAbsent(c, () {
    final out = <Offset>[];
    for (final jp in [true, false]) {
      final odd = f.oddContours(jp, c);
      for (var i = 0; i < odd.length; i++) {
        if (!odd[i]) continue;
        final r = emToBox(f.contour(jp, c, i), _box).getBounds();
        final p = r.center;
        if (out.every((q) => (q - p).distance > 90)) out.add(p);
      }
    }
    // Keep the lens mostly inside the glyph.
    return out.take(5).toList();
  });

  void _next(double t) {
    _prevExhibit = _exhibit;
    _exhibit = (_exhibit + 1) % _exhibits.runes.length;
    _since = t;
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
    return MouseRegion(
      onHover: (e) {
        final p = e.localPosition;
        if (_box.inflate(80).contains(p)) {
          _pointer = p;
          _pointerAt = _lastT;
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (e) {
          final p = e.localPosition;
          if (_box.contains(p)) {
            _next(_lastT);
          } else if (Rect.fromLTRB(0, _street - _detH - 30, 1600, _street + 10).contains(p)) {
            _tipAt = _lastT;
          }
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(painter: _TitlePainter(this, _time)),
              ),
            ),
            // Case file tag + series label.
            Positioned(
              left: 64,
              top: 58,
              child: Reveal(
                visible: true,
                delay: const Duration(milliseconds: 150),
                offset: const Offset(-20, 0),
                child: Row(
                  children: [
                    Transform.rotate(
                      angle: -0.03,
                      child: EvidenceTag('CASE № ${hexOf(caseCp)}', size: 18, filled: true),
                    ),
                    const SizedBox(width: 22),
                    Text('flutter / text', style: BT.mono(16, color: BP.inkDim)),
                  ],
                ),
              ),
            ),
            // The title.
            Positioned(
              left: 56,
              top: 124,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Reveal(
                    visible: true,
                    delay: const Duration(milliseconds: 300),
                    child: Text('Text', style: BT.display(172, letterSpacing: -5, height: 0.98)),
                  ),
                  Reveal(
                    visible: true,
                    delay: const Duration(milliseconds: 450),
                    child: Text('rendering', style: BT.display(172, letterSpacing: -5, height: 0.98)),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 64,
              top: 506,
              child: Reveal(
                visible: true,
                delay: const Duration(milliseconds: 750),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(width: 36, height: 1.5, color: BP.amber),
                        const SizedBox(width: 12),
                        Text(
                          'from code points to pixels · and how Flutter does it',
                          style: BT.mono(20, color: BP.inkDim),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.only(left: 48),
                      child: Text('テキストレンダリング', style: NT.jp(30, color: BP.ink, weight: 500)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitlePainter extends CustomPainter {
  _TitlePainter(this.s, this.time) : super(repaint: time);

  final _DetectiveTitleState s;
  final ValueNotifier<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final clock = noirSeconds;

    // Lamp flicker: a short stutter every ~23 s.
    final fl = (clock % 23.0);
    var glow = 1.0;
    if (fl < 0.7) glow = 0.35 + 0.65 * (hash01((fl * 20).floor(), 4) > 0.45 ? 1 : 0);

    // Lamp post and arm.
    final post = Paint()
      ..color = BP.lineDim
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(1536, _street), const Offset(1536, 60), post);
    canvas.drawPath(
      Path()
        ..moveTo(1536, 64)
        ..quadraticBezierTo(1536, 30, 1496, 30)
        ..lineTo(_lamp.dx, 30),
      post,
    );
    canvas.drawLine(const Offset(1518, _street), const Offset(1554, _street), post..strokeWidth = 5);

    // Light cone + lit rain inside it.
    paintCone(canvas, _lamp + const Offset(0, 6), _street, halfWidth: 330, intensity: glow);
    final cone = Path()
      ..moveTo(_lamp.dx - 18, _lamp.dy)
      ..lineTo(_lamp.dx - 330, _street)
      ..lineTo(_lamp.dx + 330, _street)
      ..lineTo(_lamp.dx + 18, _lamp.dy)
      ..close();
    paintRain(canvas, Offset.zero & size, clock, count: 150, alpha: 0.12, salt: 1);
    canvas.save();
    canvas.clipPath(cone);
    paintRain(canvas, Offset.zero & size, clock, count: 150, alpha: 0.28 * glow, color: BP.amber, salt: 1);
    canvas.restore();
    paintLampShade(canvas, _lamp, size: 46, glow: glow, cord: 3);

    // Street, splashes, fog.
    paintStreet(canvas, _street, 64, 1536);
    paintSplashes(canvas, 80, 1520, _street, clock, count: 14);
    paintFog(canvas, 64, 1536, _street - 26, clock, alpha: 0.08);

    final fonts = CaseFonts.ready;
    if (fonts != null) _paintGlyph(canvas, fonts, t, clock, glow);
    _paintDetective(canvas, t);
  }

  void _paintGlyph(Canvas canvas, CaseFonts f, double t, double clock, double glow) {
    final age = t - s._since;
    final cp = s.cp;
    final jp = emToBox(f.em(true, cp), _box);
    final sc = emToBox(f.em(false, cp), _box);

    // Em box: dashed square, corner ticks, a dimension line.
    final faint = Paint()
      ..color = BP.lineFaint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(dashPath(Path()..addRect(_box), dash: 7, gap: 6), faint);
    final tick = Paint()
      ..color = BP.line
      ..strokeWidth = 1.5;
    for (final c in [_box.topLeft, _box.topRight, _box.bottomLeft, _box.bottomRight]) {
      final dx = c.dx < _box.center.dx ? 12.0 : -12.0;
      final dy = c.dy < _box.center.dy ? 12.0 : -12.0;
      canvas.drawLine(c, c + Offset(dx, 0), tick);
      canvas.drawLine(c, c + Offset(0, dy), tick);
    }
    // Baseline (y = 0 in font units → 880 in em space).
    final base = _box.top + _box.height * 0.88;
    canvas.drawPath(
      dashPath(Path()
        ..moveTo(_box.left - 24, base)
        ..lineTo(_box.right + 24, base), dash: 3, gap: 5),
      Paint()
        ..color = BP.lineDim
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );

    // Previous exhibit fades out.
    final fadeOut = 1 - segOut(age, 0, 0.5);
    if (fadeOut > 0 && s.prevCp != cp) {
      final old = emToBox(f.em(true, s.prevCp), _box);
      canvas.drawPath(old, Paint()..color = BP.line.withValues(alpha: 0.14 * fadeOut));
      canvas.drawPath(old, Paint()
        ..color = BP.line.withValues(alpha: fadeOut)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5);
    }

    // JP: the outline draws on, then fills.
    final draw = seg(age, 0.2, 1.6);
    final fill = segOut(age, 1.2, 2.0);
    canvas.drawPath(jp, Paint()..color = BP.line.withValues(alpha: 0.3 * fill * (0.8 + 0.2 * glow)));
    canvas.drawPath(
      draw >= 1 ? jp : partialPath(jp, draw),
      Paint()
        ..color = BP.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
    // On-curve points as tiny squares (blueprint detail).
    if (fill > 0) {
      final pt = Paint()..color = BP.line.withValues(alpha: 0.7 * fill);
      final o = f.outline(true, cp);
      final sc0 = _box.width / 1000;
      for (final c in o.contours) {
        for (final p in c) {
          if (!p.onCurve) continue;
          final q = Offset(_box.left + p.x * sc0, _box.top + (880 - p.y) * sc0);
          canvas.drawRect(Rect.fromCenter(center: q, width: 4, height: 4), pt);
        }
      }
    }

    // The lens: inside it, the other form of the same code point.
    final lensOn = segOut(age, 1.4, 2.2);
    if (lensOn <= 0) return;
    final c = s._lens;
    final r = _lensR * (0.6 + 0.4 * lensOn);
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    canvas.drawCircle(c, r, Paint()..color = BP.paper.withValues(alpha: 0.94));
    // Faint grid under the glass.
    final g = Paint()
      ..color = BP.gridMajor
      ..strokeWidth = 1;
    for (var x = (c.dx - r) - (c.dx - r) % 24; x < c.dx + r; x += 24) {
      canvas.drawLine(Offset(x, c.dy - r), Offset(x, c.dy + r), g);
    }
    for (var y = (c.dy - r) - (c.dy - r) % 24; y < c.dy + r; y += 24) {
      canvas.drawLine(Offset(c.dx - r, y), Offset(c.dx + r, y), g);
    }
    final pulse = 0.5 + 0.5 * math.sin(clock * 5.2);
    canvas.drawPath(emToBox(f.xor(cp), _box), Paint()..color = BP.red.withValues(alpha: (0.18 + 0.32 * pulse) * lensOn));
    canvas.drawPath(sc, Paint()..color = BP.amber.withValues(alpha: 0.3));
    canvas.drawPath(sc, Paint()
      ..color = BP.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeJoin = StrokeJoin.round);
    canvas.drawPath(dashPath(jp, dash: 4, gap: 5), Paint()
      ..color = BP.line.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
    canvas.restore();
    paintMagnifier(canvas, c, r, angle: 0.95, rim: BP.ink, handle: 1.25);
    // Lens tag.
    final tag = s._labels.get('zh-Hans · SC', BT.mono(13, color: BP.amber));
    final tr = Rect.fromLTWH(c.dx - r * 0.95 - tag.width - 30, c.dy - r * 0.6, tag.width + 32, tag.height + 8);
    paintTag(canvas, tr, color: BP.amber);
    tag.paint(canvas, Offset(tr.left + 24, tr.top + 4));

    // Legend: real counts from the fonts.
    final oj = f.outline(true, cp);
    final os = f.outline(false, cp);
    final legend = [
      ('JP  ${oj.contours.length} contours · ${oj.pointCount} pts', BP.line),
      ('SC  ${os.contours.length} contours · ${os.pointCount} pts', BP.amber),
    ];
    var y = _box.bottom + 14;
    for (final (text, color) in legend) {
      final tp = s._labels.get(text, BT.mono(14, color: color));
      canvas.drawRect(Rect.fromLTWH(_box.left, y + 4, 10, 10), Paint()..color = color);
      tp.paint(canvas, Offset(_box.left + 18, y));
      y += 24;
    }
    final id = s._labels.get('${String.fromCharCode(cp)}  ${hexOf(cp)}', BT.mono(14, color: BP.inkDim));
    id.paint(canvas, Offset(_box.right - id.width, _box.bottom + 14));
    final demo = s._labels.get('demo: Noto Sans JP / SC', BT.mono(12, color: BP.inkFaint));
    demo.paint(canvas, Offset(_box.right - demo.width, _box.bottom + 38));
  }

  void _paintDetective(Canvas canvas, double t) {
    final st = _walker(t);
    final tipAge = t - s._tipAt;
    final tip = tipAge < 1.6 ? math.sin((tipAge / 1.6) * math.pi) : 0.0;
    paintDetective(
      canvas,
      Offset(st.x, _street),
      _detH,
      DetPose(
        walk: st.phase,
        stride: st.stride,
        facing: st.facing,
        lens: st.lens,
        tip: math.max(tip, st.tip),
        notes: st.notes,
        look: st.look,
      ),
    );
  }

  /// The detective's day: a 32 s loop, re-planned each loop from a seeded
  /// random, always starting and ending at home.
  _Walker _walker(double t) {
    const loop = 32.0;
    final n = (t / loop).floor();
    final u = t - n * loop;
    final rng = math.Random(n * 7919 + 17);
    const speed = 105.0;
    final xa = 1060 + rng.nextDouble() * 360;
    final xb = rng.nextBool() ? 640 + rng.nextDouble() * 180 : 1330 + rng.nextDouble() * 120;
    final act = rng.nextInt(3);
    final plan = <_Leg>[
      _Leg.stay(_home, 2.2, look: 1),
      _Leg.walk(_home, xa, speed),
      _Leg.stay(xa, 3.6, lens: 1, look: 0.6),
      _Leg.walk(xa, xb, speed),
      _Leg.stay(xb, act == 0 ? 2.0 : 3.2, tip: act == 0 ? 1 : 0, notes: act == 1 ? 1 : 0, look: act == 2 ? 1 : 0),
      _Leg.walk(xb, _home, speed),
    ];
    var t0 = 0.0;
    for (final leg in plan) {
      if (u < t0 + leg.dur) return leg.at(u - t0);
      t0 += leg.dur;
    }
    return _Leg.stay(_home, 1).at(0);
  }

  @override
  bool shouldRepaint(_TitlePainter old) => old.s != s;
}

class _Walker {
  const _Walker(this.x, this.phase, this.stride, this.facing,
      {this.lens = 0, this.tip = 0, this.notes = 0, this.look = 0});

  final double x;
  final double phase;
  final double stride;
  final double facing;
  final double lens;
  final double tip;
  final double notes;
  final double look;
}

class _Leg {
  _Leg.walk(this.x0, this.x1, double speed)
    : dur = (x1 - x0).abs() / speed + 0.01,
      lens = 0,
      tip = 0,
      notes = 0,
      look = 0;

  _Leg.stay(double x, this.dur, {this.lens = 0, this.tip = 0, this.notes = 0, this.look = 0})
    : x0 = x,
      x1 = x;

  final double x0;
  final double x1;
  final double dur;
  final double lens;
  final double tip;
  final double notes;
  final double look;

  _Walker at(double u) {
    final walking = x0 != x1;
    final facing = x1 >= x0 ? 1.0 : -1.0;
    if (walking) {
      final x = x0 + (x1 - x0) * (u / dur);
      final stride = (math.min(u, dur - u) / 0.25).clamp(0.0, 1.0);
      return _Walker(x, (x - x0).abs() / (_detH * 0.19), stride, facing);
    }
    // Ease the pose in and out of the hold.
    final e = math.min(seg(u, 0, 0.5), 1 - seg(u, dur - 0.5, dur));
    final face = x0 > _box.center.dx ? -1.0 : 1.0;
    return _Walker(x0, 0, 0, face, lens: lens * e, tip: tip * e, notes: notes * e, look: look * e);
  }
}
