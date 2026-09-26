import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../deck/theme.dart';
import '../deck/widgets.dart';

/// "Not in Flutter": eight things platform text stacks do that Flutter's
/// SkParagraph stack doesn't. Each card loops a tiny drawing of the feature
/// and gets a red stamp; clicking flips it (3D) to the workaround.
class CantSlide extends StatefulWidget {
  const CantSlide({super.key});

  @override
  State<CantSlide> createState() => _CantSlideState();
}

class _Feature {
  const _Feature(this.label, this.workaround);

  final String label;
  final String workaround;
}

const _features = [
  _Feature('vertical text', 'mongol pkg · rotate hacks'),
  _Feature('ruby / furigana', 'WidgetSpan'),
  _Feature('auto hyphenation', 'manual U+00AD'),
  _Feature('optimal line breaks', 'greedy only'),
  _Feature('kashida justify', 'spaces only'),
  _Feature('LCD subpixel AA', 'grayscale AA'),
  _Feature('web find · translate · SEO', 'semantics tree'),
  _Feature('web fonts on demand', 'tofu flash · preload'),
];

const _cardW = 350.0;
const _cardH = 300.0;
const _gapX = (1472 - 4 * _cardW) / 3;
const _gapY = 628 - 2 * _cardH;

class _CantSlideState extends State<CantSlide> {
  final _flipped = List<bool>.filled(_features.length, false);
  final _timers = <Timer>[];

  bool get _allFlipped => _flipped.every((f) => f);

  void _flipAll() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    final target = !_allFlipped;
    for (var i = 0; i < _flipped.length; i++) {
      _timers.add(Timer(Duration(milliseconds: 70 * i), () {
        if (mounted) setState(() => _flipped[i] = target);
      }));
    }
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideFrame(
      title: 'Not in Flutter',
      trailing: BpButton(
        label: 'workarounds',
        color: BP.amber,
        selected: _allFlipped,
        onTap: _flipAll,
      ),
      child: Stack(
        children: [
          for (var i = 0; i < _features.length; i++)
            Positioned(
              left: (i % 4) * (_cardW + _gapX),
              top: (i ~/ 4) * (_cardH + _gapY),
              width: _cardW,
              height: _cardH,
              child: _Card(
                index: i,
                flipped: _flipped[i],
                onTap: () => setState(() => _flipped[i] = !_flipped[i]),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card: staggered entry, red stamp slam, 3D flip
// ─────────────────────────────────────────────────────────────────────────────

class _Card extends StatefulWidget {
  const _Card({required this.index, required this.flipped, required this.onTap});

  final int index;
  final bool flipped;
  final VoidCallback onTap;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  Timer? _delay;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _delay = Timer(Duration(milliseconds: 150 + 90 * widget.index), () {
      if (mounted) _enter.forward();
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = _features[widget.index];
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _enter,
          builder: (context, _) {
            final e = _enter.value;
            final cardT = Curves.easeOutCubic.transform((e / 0.45).clamp(0.0, 1.0));
            final stampT = ((e - 0.55) / 0.3).clamp(0.0, 1.0);
            return Opacity(
              opacity: cardT,
              child: Transform.translate(
                offset: Offset(0, 36 * (1 - cardT)),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: widget.flipped ? 1.0 : 0.0),
                  duration: const Duration(milliseconds: 760),
                  curve: Curves.easeInOutCubic,
                  builder: (context, v, _) {
                    final angle = v * math.pi;
                    final lift = 1 + 0.05 * math.sin(v * math.pi);
                    final m = Matrix4.identity()
                      ..setEntry(3, 2, 0.0009)
                      ..rotateY(angle)
                      ..multiply(Matrix4.diagonal3Values(lift, lift, 1));
                    final back = angle > math.pi / 2;
                    return Transform(
                      alignment: Alignment.center,
                      transform: m,
                      child: back
                          ? Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.rotationY(math.pi),
                              child: _Back(feature: f, hover: _hover),
                            )
                          : _Front(
                              index: widget.index,
                              feature: f,
                              hover: _hover,
                              stamp: stampT,
                            ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Front extends StatelessWidget {
  const _Front({
    required this.index,
    required this.feature,
    required this.hover,
    required this.stamp,
  });

  final int index;
  final _Feature feature;
  final bool hover;
  final double stamp;

  @override
  Widget build(BuildContext context) {
    return BpPanel(
      padding: EdgeInsets.zero,
      color: hover ? BP.line : BP.lineDim,
      child: Stack(
        children: [
          Positioned(
            left: 16,
            top: 14,
            child: Text(
              (index + 1).toString().padLeft(2, '0'),
              style: BT.mono(13, color: BP.inkFaint),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            top: 40,
            bottom: 56,
            child: _Illustration(kind: index),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 52,
            height: 1,
            child: ColoredBox(color: hover ? BP.lineDim : BP.lineFaint),
          ),
          Positioned(
            left: 16,
            right: 44,
            bottom: 0,
            height: 52,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                feature.label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: BT.mono(16, color: BP.ink),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 14,
            child: Text('↻', style: BT.mono(18, color: hover ? BP.amber : BP.inkFaint)),
          ),
          Positioned(right: 12, top: 10, child: _Stamp(t: stamp)),
        ],
      ),
    );
  }
}

class _Back extends StatelessWidget {
  const _Back({required this.feature, required this.hover});

  final _Feature feature;
  final bool hover;

  @override
  Widget build(BuildContext context) {
    final parts = feature.workaround.split(' · ');
    return BpPanel(
      padding: EdgeInsets.zero,
      color: BP.amber,
      child: Stack(
        children: [
          Positioned(
            left: 16,
            top: 14,
            child: Text('workaround', style: BT.mono(13, color: BP.inkFaint)),
          ),
          Positioned.fill(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final p in parts)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(p, style: BT.mono(27, color: BP.amber, weight: 500)),
                    ),
                  const SizedBox(height: 22),
                  Text(
                    feature.label,
                    style: BT.mono(14, color: BP.inkDim).copyWith(
                      decoration: TextDecoration.lineThrough,
                      decorationColor: BP.red,
                      decorationThickness: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 14,
            child: Text('↻', style: BT.mono(18, color: hover ? BP.amber : BP.inkFaint)),
          ),
        ],
      ),
    );
  }
}

/// Red rubber stamp with a ✕ that slams down on entry.
class _Stamp extends StatelessWidget {
  const _Stamp({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    if (t <= 0) return const SizedBox(width: 50, height: 50);
    final e = Curves.easeOutBack.transform(t);
    final scale = 2.4 - 1.4 * e;
    return Opacity(
      opacity: (t * 3).clamp(0.0, 1.0),
      child: Transform.rotate(
        angle: -0.2 + 0.08 * (1 - t),
        child: Transform.scale(
          scale: scale,
          child: const CustomPaint(size: Size(50, 50), painter: _StampPainter()),
        ),
      ),
    );
  }
}

class _StampPainter extends CustomPainter {
  const _StampPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final p = Paint()
      ..color = BP.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(1), const Radius.circular(4)), p);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.deflate(5), const Radius.circular(2)),
      p..strokeWidth = 1,
    );
    canvas.drawRect(r.deflate(5), Paint()..color = BP.red.withValues(alpha: 0.12));
    final x = Paint()
      ..color = BP.red
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(r.topLeft + const Offset(15, 15), r.bottomRight - const Offset(15, 15), x);
    canvas.drawLine(r.topRight + const Offset(-15, 15), r.bottomLeft + const Offset(15, -15), x);
  }

  @override
  bool shouldRepaint(_StampPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Illustrations (each loops on its own)
// ─────────────────────────────────────────────────────────────────────────────

double _ease(double x) => Curves.easeInOutCubic.transform(x.clamp(0.0, 1.0));

/// 0 before [a], rises to 1 by [b], holds until [c], falls back to 0 by [d].
double _pulse(double t, double a, double b, double c, double d) {
  if (t <= a || t >= d) return 0;
  if (t < b) return _ease((t - a) / (b - a));
  if (t <= c) return 1;
  return 1 - _ease((t - c) / (d - c));
}

class _Fn extends CustomPainter {
  _Fn(this.fn);

  final void Function(Canvas canvas, Size size) fn;

  @override
  void paint(Canvas canvas, Size size) => fn(canvas, size);

  @override
  bool shouldRepaint(_Fn old) => true;
}

Paint _stroke(Color c, [double w = 1]) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w;

class _Illustration extends StatelessWidget {
  const _Illustration({required this.kind});

  final int kind;

  @override
  Widget build(BuildContext context) => switch (kind) {
    0 => const _VerticalIllo(),
    1 => const _RubyIllo(),
    2 => const _HyphenIllo(),
    3 => const _OptimalIllo(),
    4 => const _KashidaIllo(),
    5 => const _SubpixelIllo(),
    6 => const _FindIllo(),
    _ => const _FontsIllo(),
  };
}

// 1 · vertical text: a horizontal run folds into a top-to-bottom column.
class _VerticalIllo extends StatelessWidget {
  const _VerticalIllo();

  static const _chars = ['縦', '書', 'き'];

  @override
  Widget build(BuildContext context) {
    return LoopBuilder(
      period: const Duration(milliseconds: 4400),
      builder: (context, t, _) => LayoutBuilder(
        builder: (context, box) {
          final m = _pulse(t, 0.08, 0.36, 0.74, 0.97);
          const s = 50.0;
          const step = 56.0;
          final cx = box.maxWidth / 2;
          final cy = box.maxHeight / 2;
          Offset at(int i) => Offset.lerp(
            Offset(cx + (i - 1) * step - s / 2, cy - s / 2),
            Offset(cx - s / 2 - 14, cy + (i - 1) * step - s / 2),
            m,
          )!;
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _Fn((canvas, size) {
                    final yb = cy + s / 2 + 14;
                    drawArrow(
                      canvas,
                      Offset(cx - 1.5 * step, yb),
                      Offset(cx + 1.5 * step, yb),
                      _stroke(BP.lineDim.withValues(alpha: 1 - m)),
                      dashed: true,
                      head: 6,
                    );
                    final xv = cx + s / 2;
                    drawArrow(
                      canvas,
                      Offset(xv, cy - 1.5 * step),
                      Offset(xv, cy + 1.5 * step),
                      _stroke(BP.amber.withValues(alpha: m), 1.2),
                      dashed: true,
                      head: 6,
                    );
                    final bp = _stroke(BP.lineDim);
                    for (var i = 0; i < 3; i++) {
                      canvas.drawPath(
                        dashPath(Path()..addRect(at(i) & const Size(s, s)), dash: 3, gap: 3),
                        bp,
                      );
                    }
                  }),
                ),
              ),
              for (var i = 0; i < 3; i++)
                Positioned(
                  left: at(i).dx,
                  top: at(i).dy,
                  width: s,
                  height: s,
                  child: Center(child: Text(_chars[i], style: BT.sample(36, height: 1))),
                ),
            ],
          );
        },
      ),
    );
  }
}

// 2 · ruby: small kana settle above their base kanji.
class _RubyIllo extends StatelessWidget {
  const _RubyIllo();

  static const _pairs = [
    [('漢', 'かん'), ('字', 'じ')],
    [('東', 'とう'), ('京', 'きょう')],
  ];

  @override
  Widget build(BuildContext context) {
    return LoopBuilder(
      period: const Duration(milliseconds: 7600),
      builder: (context, t, _) {
        final which = t < 0.5 ? 0 : 1;
        final u = (t * 2) % 1;
        final r = _pulse(u, 0.12, 0.34, 0.78, 0.94);
        final base = _pulse(u, -0.01, 0.06, 0.95, 1.01);
        return Center(
          child: Opacity(
            opacity: base,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (b, ruby) in _pairs[which])
                  SizedBox(
                    width: 88,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Opacity(
                          opacity: r,
                          child: Transform.translate(
                            offset: Offset(0, -18 * (1 - r)),
                            child: Text(ruby, style: BT.sample(18, color: BP.amber)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 64 * r,
                          height: 1.5,
                          color: BP.amber.withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 6),
                        DashedBox(
                          color: BP.lineDim,
                          child: SizedBox(
                            width: 74,
                            height: 74,
                            child: Center(child: Text(b, style: BT.sample(52, height: 1))),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// 3 · hyphenation: a column narrows, the word breaks at syllables with a hyphen.
class _HyphenIllo extends StatefulWidget {
  const _HyphenIllo();

  @override
  State<_HyphenIllo> createState() => _HyphenIlloState();
}

class _HyphenIlloState extends State<_HyphenIllo> {
  static const _syl = ['hy', 'phen', 'a', 'tion'];
  final _style = BT.display(34, color: BP.ink);

  /// Width of the first k syllables (+ "-" unless it's the whole word), k = 1..4.
  late final List<double> _w = [
    for (var k = 1; k <= 4; k++) _width(_syl.take(k).join() + (k < 4 ? '-' : '')),
  ];

  double _width(String s) {
    final p = TextProbe(TextSpan(text: s, style: _style));
    final w = p.size.width;
    p.dispose();
    return w;
  }

  @override
  Widget build(BuildContext context) {
    return LoopBuilder(
      period: const Duration(milliseconds: 5200),
      builder: (context, t, _) {
        final lo = _w[1] + 6;
        final hi = _w[3] + 16;
        final w = lo + (hi - lo) * (0.5 - 0.5 * math.cos(2 * math.pi * t));
        var k = 4;
        while (k > 1 && _w[k - 1] > w) {
          k--;
        }
        final first = _syl.take(k).join();
        final rest = _syl.skip(k).join();
        const x0 = 34.0;
        const y0 = 46.0;
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _Fn((canvas, size) {
                  canvas.drawLine(
                    const Offset(x0, 14),
                    Offset(x0, size.height - 14),
                    _stroke(BP.lineDim),
                  );
                  canvas.drawPath(
                    dashPath(Path()
                      ..moveTo(x0 + w, 14)
                      ..lineTo(x0 + w, size.height - 14)),
                    _stroke(BP.amber, 1.2),
                  );
                  final a = _stroke(BP.amber.withValues(alpha: 0.6));
                  drawArrow(canvas, Offset(x0 + w / 2, 24), const Offset(x0 + 2, 24), a, head: 5);
                  drawArrow(canvas, Offset(x0 + w / 2, 24), Offset(x0 + w - 2, 24), a, head: 5);
                }),
              ),
            ),
            Positioned(
              left: x0,
              top: y0,
              child: Text.rich(
                TextSpan(
                  style: _style,
                  children: [
                    TextSpan(text: first),
                    if (rest.isNotEmpty)
                      const TextSpan(text: '-', style: TextStyle(color: BP.amber)),
                  ],
                ),
                softWrap: false,
              ),
            ),
            if (rest.isNotEmpty)
              Positioned(
                left: x0,
                top: y0 + 50,
                child: Text(rest, style: _style, softWrap: false),
              ),
          ],
        );
      },
    );
  }
}

// 4 · optimal breaks: word blocks glide from greedy (ragged, orphan) to
// whole-paragraph optimal (even) and back. Both layouts are computed here.
class _OptimalIllo extends StatefulWidget {
  const _OptimalIllo();

  @override
  State<_OptimalIllo> createState() => _OptimalIlloState();
}

class _OptimalIlloState extends State<_OptimalIllo> {
  static const _ws = [34.0, 70.0, 52.0, 70.0, 52.0, 40.0, 34.0, 26.0, 26.0, 64.0, 70.0, 30.0];
  static const _c = 236.0;
  static const _gap = 8.0;
  static const _pitch = 30.0;

  late final _greedy = _breakGreedy();
  late final _optimal = _breakOptimal();
  late final _a = _layout(_greedy);
  late final _b = _layout(_optimal);

  static List<List<int>> _breakGreedy() {
    final lines = <List<int>>[[]];
    var x = 0.0;
    for (var i = 0; i < _ws.length; i++) {
      final need = lines.last.isEmpty ? _ws[i] : x + _gap + _ws[i];
      if (lines.last.isNotEmpty && need > _c) {
        lines.add([i]);
        x = _ws[i];
      } else {
        lines.last.add(i);
        x = need;
      }
    }
    return lines;
  }

  /// Minimum total squared slack (last line free unless very short).
  static List<List<int>> _breakOptimal() {
    final n = _ws.length;
    final best = List<double>.filled(n + 1, double.infinity)..[n] = 0;
    final next = List<int>.filled(n + 1, n);
    for (var i = n - 1; i >= 0; i--) {
      var w = -_gap;
      for (var j = i + 1; j <= n; j++) {
        w += _gap + _ws[j - 1];
        if (w > _c) break;
        final slack = _c - w;
        final short = math.max(0.0, slack - _c * 0.5);
        final cost = j < n ? slack * slack : short * short;
        if (cost + best[j] < best[i]) {
          best[i] = cost + best[j];
          next[i] = j;
        }
      }
    }
    final lines = <List<int>>[];
    for (var i = 0; i < n; i = next[i]) {
      lines.add([for (var k = i; k < next[i]; k++) k]);
    }
    return lines;
  }

  static List<Offset> _layout(List<List<int>> lines) {
    final out = List<Offset>.filled(_ws.length, Offset.zero);
    for (var l = 0; l < lines.length; l++) {
      var x = 0.0;
      for (final i in lines[l]) {
        out[i] = Offset(x, l * _pitch);
        x += _ws[i] + _gap;
      }
    }
    return out;
  }

  static List<double> _ends(List<List<int>> lines) => [
    for (final l in lines) l.fold(-_gap, (a, i) => a + _ws[i] + _gap),
  ];

  @override
  Widget build(BuildContext context) {
    return LoopBuilder(
      period: const Duration(milliseconds: 5600),
      builder: (context, t, _) {
        final m = _pulse(t, 0.12, 0.4, 0.7, 0.95);
        return LayoutBuilder(
          builder: (context, box) {
            final x0 = (box.maxWidth - _c) / 2;
            const y0 = 40.0;
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _Fn((canvas, size) {
                      canvas.drawPath(
                        dashPath(Path()
                          ..moveTo(x0 + _c, y0 - 10)
                          ..lineTo(x0 + _c, y0 + 4 * _pitch)),
                        _stroke(BP.lineDim),
                      );
                      canvas.drawLine(
                        Offset(x0, y0 - 10),
                        Offset(x0, y0 + 4 * _pitch),
                        _stroke(BP.lineFaint),
                      );
                      for (var i = 0; i < _ws.length; i++) {
                        final p = Offset.lerp(_a[i], _b[i], m)!;
                        final r = Rect.fromLTWH(x0 + p.dx, y0 + p.dy, _ws[i], 14);
                        canvas.drawRect(r, Paint()..color = BP.line.withValues(alpha: 0.28));
                        canvas.drawRect(r, _stroke(BP.line));
                      }
                      // The rag: a polyline through each line's end.
                      final ea = _ends(_greedy);
                      final eb = _ends(_optimal);
                      final rag = Path();
                      for (var l = 0; l < ea.length; l++) {
                        final x = x0 + ea[l] + (eb[l] - ea[l]) * m + 5;
                        final y = y0 + l * _pitch + 7;
                        l == 0 ? rag.moveTo(x, y) : rag.lineTo(x, y);
                      }
                      canvas.drawPath(dashPath(rag, dash: 4, gap: 3), _stroke(BP.amber, 1.4));
                    }),
                  ),
                ),
                Positioned(
                  left: x0,
                  top: 4,
                  child: Stack(
                    children: [
                      Opacity(
                        opacity: 1 - m,
                        child: Text('greedy', style: BT.mono(13, color: BP.inkDim)),
                      ),
                      Opacity(
                        opacity: m,
                        child: Text('optimal', style: BT.mono(13, color: BP.amber)),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// 5 · kashida: the same Arabic words justified by stretching letters with
// tatweel (ـ) vs. by widening the space.
class _KashidaIllo extends StatefulWidget {
  const _KashidaIllo();

  @override
  State<_KashidaIllo> createState() => _KashidaIlloState();
}

class _KashidaIlloState extends State<_KashidaIllo> {
  final _style = BT.sample(30, color: BP.ink);
  final _dim = BT.sample(30, color: BP.inkDim);
  final _amber = BT.sample(30, color: BP.amber);

  late final double _tatweel = _width('ـ');
  late final double _natural = _width('نص جميل');
  late final double _w1 = _width('نص');
  late final double _w2 = _width('جميل');

  double _width(String s) {
    final p = TextProbe(TextSpan(text: s, style: _style), textDirection: TextDirection.rtl);
    final w = p.size.width;
    p.dispose();
    return w;
  }

  @override
  Widget build(BuildContext context) {
    return LoopBuilder(
      period: const Duration(milliseconds: 5000),
      builder: (context, t, _) {
        final extra = 104 * (0.5 - 0.5 * math.cos(2 * math.pi * t));
        final w = _natural + extra;
        final n = _tatweel > 0 ? (extra / _tatweel).floor() : 0;
        final n1 = n ~/ 2;
        final n2 = n - n1;
        const right = 22.0;
        const rowA = 24.0;
        const rowB = 112.0;
        return LayoutBuilder(
          builder: (context, box) {
            final xr = box.maxWidth - right;
            final xl = xr - w;
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _Fn((canvas, size) {
                      canvas.drawLine(Offset(xr, 8), Offset(xr, size.height - 8), _stroke(BP.lineDim));
                      canvas.drawPath(
                        dashPath(Path()
                          ..moveTo(xl, 8)
                          ..lineTo(xl, size.height - 8)),
                        _stroke(BP.amber, 1.2),
                      );
                      // The widened space in the lower row.
                      final g0 = xl + _w2 + 4;
                      final g1 = xr - _w1 - 4;
                      if (g1 - g0 > 6) {
                        const gy = rowB + 30;
                        final p = _stroke(BP.inkFaint, 1.2);
                        canvas.drawLine(Offset(g0, gy - 5), Offset(g0, gy + 5), p);
                        canvas.drawLine(Offset(g1, gy - 5), Offset(g1, gy + 5), p);
                        canvas.drawPath(
                          dashPath(Path()
                            ..moveTo(g0, gy)
                            ..lineTo(g1, gy), dash: 3, gap: 3),
                          p,
                        );
                      }
                    }),
                  ),
                ),
                Positioned(
                  right: right + 2,
                  top: rowA - 20,
                  child: Text('ـ kashida', style: BT.mono(11, color: BP.amber)),
                ),
                Positioned(
                  right: right,
                  top: rowA,
                  child: Text.rich(
                    TextSpan(
                      style: _style,
                      children: [
                        const TextSpan(text: 'ن'),
                        TextSpan(text: 'ـ' * n1, style: _amber),
                        const TextSpan(text: 'ص '),
                        const TextSpan(text: 'جم'),
                        TextSpan(text: 'ـ' * n2, style: _amber),
                        const TextSpan(text: 'يل'),
                      ],
                    ),
                    textDirection: TextDirection.rtl,
                    softWrap: false,
                  ),
                ),
                Positioned(
                  right: right + 2,
                  top: rowB - 20,
                  child: Text('␣ spaces', style: BT.mono(11, color: BP.inkFaint)),
                ),
                Positioned(
                  left: xl,
                  width: w,
                  top: rowB,
                  child: Row(
                    textDirection: TextDirection.rtl,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('نص', style: _dim, textDirection: TextDirection.rtl),
                      Text('جميل', style: _dim, textDirection: TextDirection.rtl),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// 6 · LCD subpixel AA: the same slanted stroke, zoomed to pixels —
// per-channel coverage (colour fringes) vs. one coverage per pixel (grey).
class _SubpixelIllo extends StatelessWidget {
  const _SubpixelIllo();

  static const n = 7;
  static const cell = 16.0;
  static const gap = 36.0;
  static const y0 = 18.0;

  @override
  Widget build(BuildContext context) {
    return LoopBuilder(
      period: const Duration(milliseconds: 4200),
      builder: (context, t, _) => LayoutBuilder(
        builder: (context, box) {
          const gw = n * cell;
          final x0 = (box.maxWidth - (2 * gw + gap)) / 2;
          return Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _SubpixelPainter(t: t, x0: x0))),
              Positioned(
                left: x0,
                width: gw,
                top: y0 + gw + 12,
                child: Center(
                  child: Text.rich(
                    TextSpan(
                      style: BT.mono(13, weight: 600),
                      children: const [
                        TextSpan(text: 'R', style: TextStyle(color: BP.red)),
                        TextSpan(text: 'G', style: TextStyle(color: BP.green)),
                        TextSpan(text: 'B', style: TextStyle(color: BP.line)),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: x0 + gw + gap,
                width: gw,
                top: y0 + gw + 12,
                child: Center(child: Text('gray', style: BT.mono(13, color: BP.inkDim))),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SubpixelPainter extends CustomPainter {
  _SubpixelPainter({required this.t, required this.x0});

  final double t;
  final double x0;

  static const _hw = 0.8;

  @override
  void paint(Canvas canvas, Size size) {
    const n = _SubpixelIllo.n;
    const cell = _SubpixelIllo.cell;
    const gw = n * cell;
    const y0 = _SubpixelIllo.y0;
    final shift = 1.9 + 0.9 * math.sin(2 * math.pi * t);
    double center(double row) => shift + (n - row) * 0.42;
    double cover(double a, double b, int row) {
      final xc = center(row + 0.5);
      final lo = math.max(a, xc - _hw);
      final hi = math.min(b, xc + _hw);
      return ((hi - lo) / (b - a)).clamp(0.0, 1.0);
    }

    double mix(double a, double b, double k) => a + (b - a) * k;
    const bg = BP.panel;
    const ink = BP.ink;
    final grid = _stroke(BP.lineFaint);
    for (var g = 0; g < 2; g++) {
      final ox = x0 + g * (gw + _SubpixelIllo.gap);
      for (var r = 0; r < n; r++) {
        for (var c = 0; c < n; c++) {
          final rect = Rect.fromLTWH(ox + c * cell, y0 + r * cell, cell, cell);
          final Color col;
          if (g == 0) {
            final cr = cover(c.toDouble(), c + 1 / 3, r);
            final cg = cover(c + 1 / 3, c + 2 / 3, r);
            final cb = cover(c + 2 / 3, c + 1.0, r);
            col = Color.from(
              alpha: 1,
              red: mix(bg.r, ink.r, cr),
              green: mix(bg.g, ink.g, cg),
              blue: mix(bg.b, ink.b, cb),
            );
          } else {
            col = Color.lerp(bg, ink, cover(c.toDouble(), c + 1.0, r))!;
          }
          canvas.drawRect(rect, Paint()..color = col);
          if (g == 0) {
            final s = Paint()
              ..color = BP.lineFaint.withValues(alpha: 0.5)
              ..strokeWidth = 0.6;
            canvas.drawLine(rect.topLeft + const Offset(cell / 3, 0), rect.bottomLeft + const Offset(cell / 3, 0), s);
            canvas.drawLine(rect.topLeft + const Offset(2 * cell / 3, 0), rect.bottomLeft + const Offset(2 * cell / 3, 0), s);
          }
          canvas.drawRect(rect, grid);
        }
      }
      // The ideal outline of the stroke.
      final edge = _stroke(BP.amber.withValues(alpha: 0.8), 1);
      for (final sgn in [-1.0, 1.0]) {
        final path = Path()
          ..moveTo(ox + (center(0) + sgn * _hw) * cell, y0)
          ..lineTo(ox + (center(n.toDouble()) + sgn * _hw) * cell, y0 + gw);
        canvas.drawPath(dashPath(path, dash: 3, gap: 3), edge);
      }
      canvas.drawRect(Rect.fromLTWH(ox, y0, gw, gw), _stroke(BP.lineDim));
    }
  }

  @override
  bool shouldRepaint(_SubpixelPainter old) => old.t != t || old.x0 != x0;
}

// 7 · find in page: the browser types a query and walks the matches.
class _FindIllo extends StatelessWidget {
  const _FindIllo();

  static const _lines = [
    'the text on a page',
    'is real DOM text',
    'find · translate · index',
    'every text node',
  ];

  @override
  Widget build(BuildContext context) {
    return LoopBuilder(
      period: const Duration(milliseconds: 6000),
      builder: (context, t, _) {
        final typed = t < 0.3 ? (t / 0.3 * 5).floor().clamp(0, 4) : 4;
        final q = 'text'.substring(0, typed);
        final hits = <(int, int)>[];
        if (q.isNotEmpty) {
          for (var l = 0; l < _lines.length; l++) {
            var i = _lines[l].indexOf(q);
            while (i >= 0) {
              hits.add((l, i));
              i = _lines[l].indexOf(q, i + q.length);
            }
          }
        }
        final cur = hits.isEmpty || t < 0.36 ? -1 : ((t - 0.36) / 0.16).floor() % hits.length;
        final caret = (t * 12).floor().isEven;
        final style = BT.sample(18, color: BP.inkDim);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  width: 190,
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(border: Border.all(color: BP.line)),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 15, color: BP.inkDim),
                      const SizedBox(width: 6),
                      Text(q, style: BT.mono(14, color: BP.ink)),
                      Container(width: 1.5, height: 16, color: caret ? BP.amber : Colors.transparent),
                      const Spacer(),
                      Text(
                        hits.isEmpty ? '' : '${cur < 0 ? 1 : cur + 1}/${hits.length}',
                        style: BT.mono(12, color: BP.amber),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (var l = 0; l < _lines.length; l++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text.rich(_spans(l, q, hits, cur, style)),
                ),
            ],
          ),
        );
      },
    );
  }

  static TextSpan _spans(int l, String q, List<(int, int)> hits, int cur, TextStyle style) {
    final text = _lines[l];
    final out = <TextSpan>[];
    var i = 0;
    for (var h = 0; h < hits.length; h++) {
      final (line, start) = hits[h];
      if (line != l) continue;
      if (start > i) out.add(TextSpan(text: text.substring(i, start)));
      final active = h == cur;
      out.add(TextSpan(
        text: text.substring(start, start + q.length),
        style: TextStyle(
          color: active ? BP.paper : BP.ink,
          backgroundColor: active ? BP.amber : BP.amber.withValues(alpha: 0.32),
        ),
      ));
      i = start + q.length;
    }
    if (i < text.length) out.add(TextSpan(text: text.substring(i)));
    return TextSpan(style: style, children: out);
  }
}

// 8 · fonts on demand: DOM text shows up at once with local fonts; canvas
// text shows tofu until a font file arrives.
class _FontsIllo extends StatefulWidget {
  const _FontsIllo();

  @override
  State<_FontsIllo> createState() => _FontsIlloState();
}

class _FontsIlloState extends State<_FontsIllo> {
  static const _word = 'สวัสดี';

  TextProbe? _probe;
  final _boxes = <Rect>[];
  final _hex = <TextPainter>[];

  @override
  void initState() {
    super.initState();
    _build();
    PaintingBinding.instance.systemFonts.addListener(_onFonts);
  }

  void _onFonts() {
    if (!mounted) return;
    setState(_build);
  }

  void _build() {
    _probe?.dispose();
    for (final h in _hex) {
      h.dispose();
    }
    _boxes.clear();
    _hex.clear();
    final p = TextProbe(TextSpan(text: _word, style: BT.sample(40)));
    _probe = p;
    for (final (s, e) in p.graphemes()) {
      _boxes.add(p.rectFor(s, e) ?? Rect.zero);
      final hex = _word.substring(s, e).runes.first.toRadixString(16).toUpperCase().padLeft(4, '0');
      _hex.add(TextPainter(
        text: TextSpan(
          text: '${hex.substring(0, 2)}\n${hex.substring(2)}',
          style: BT.mono(9, color: BP.inkDim, height: 1.1),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout());
    }
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_onFonts);
    _probe?.dispose();
    for (final h in _hex) {
      h.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const yA = 10.0;
    const yB = 98.0;
    return LoopBuilder(
      period: const Duration(milliseconds: 4600),
      builder: (context, t, _) {
        final tofu = t < 0.62 ? 1.0 : 1 - _ease((t - 0.62) / 0.06);
        final glyph = _ease((t - 0.64) / 0.1);
        final load = _ease((t - 0.2) / 0.4);
        final showBar = t > 0.16 && t < 0.72;
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _Fn((canvas, size) {
                  final p = _probe!;
                  final x = (size.width - p.size.width) / 2 + 26;
                  p.paint(canvas, Offset(x, yA));
                  final ob = Offset(x, yB);
                  if (glyph > 0) {
                    canvas.saveLayer(
                      (ob & p.size).inflate(10),
                      Paint()..color = Color.fromRGBO(0, 0, 0, glyph),
                    );
                    p.paint(canvas, ob);
                    canvas.restore();
                  }
                  if (tofu > 0) {
                    for (var i = 0; i < _boxes.length; i++) {
                      final b = _boxes[i].shift(ob);
                      final r = Rect.fromLTWH(b.left + 2, b.top + b.height * 0.2, b.width - 4, b.height * 0.6);
                      canvas.drawRect(r, _stroke(BP.inkDim.withValues(alpha: tofu), 1.2));
                      if (tofu > 0.5 && r.width > 14) {
                        final h = _hex[i];
                        h.paint(canvas, r.center - Offset(h.width / 2, h.height / 2));
                      }
                    }
                  }
                  if (showBar) {
                    final by = yB + p.size.height + 6;
                    canvas.drawLine(Offset(x, by), Offset(x + p.size.width, by), _stroke(BP.lineFaint, 3));
                    canvas.drawLine(Offset(x, by), Offset(x + p.size.width * load, by), _stroke(BP.amber, 3));
                    final ay = by - 14 + 4 * math.sin(t * 40);
                    drawArrow(
                      canvas,
                      Offset(x + p.size.width + 16, ay - 12),
                      Offset(x + p.size.width + 16, ay + 4),
                      _stroke(BP.amber, 1.4),
                      head: 5,
                    );
                  }
                }),
              ),
            ),
            Positioned(left: 8, top: yA + 20, child: Text('DOM', style: BT.mono(12, color: BP.green))),
            Positioned(left: 8, top: yB + 20, child: Text('canvas', style: BT.mono(12, color: BP.inkFaint))),
          ],
        );
      },
    );
  }
}
