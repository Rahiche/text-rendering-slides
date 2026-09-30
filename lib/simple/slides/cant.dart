import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';

/// "Not in Flutter": six things platform text stacks do that Flutter's
/// SkParagraph stack doesn't, Japanese vertical text and ruby first. Each
/// card loops a big drawing of the feature and gets a red stamp; clicking
/// flips it (3D) to the workaround.
///
/// Every loop runs on a clock started with the slide and is timed so the
/// feature is fully "on" from ~2 s to ~6 s after arrival (the exported still).
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
  _Feature('hyphenation', 'manual U+00AD'),
  _Feature('kashida justify', 'spaces only'),
  _Feature('find & translate (web)', 'semantics tree'),
  _Feature('fonts on demand (web)', 'tofu flash · preload'),
];

const _cols = 3;
const _gapX = 28.0;
const _gapY = 20.0;
const _cardW = (1472 - (_cols - 1) * _gapX) / _cols;
const _cardH = 296.0;
const _labelH = 64.0;

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
        size: 18,
        selected: _allFlipped,
        onTap: _flipAll,
      ),
      child: Stack(
        children: [
          for (var i = 0; i < _features.length; i++)
            Positioned(
              left: (i % _cols) * (_cardW + _gapX),
              top: (i ~/ _cols) * (_cardH + _gapY),
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
                              child: _Back(feature: f),
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
            right: 16,
            top: 12,
            bottom: _labelH + 6,
            child: _Illustration(kind: index),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: _labelH,
            height: 1,
            child: ColoredBox(color: hover ? BP.lineDim : BP.lineFaint),
          ),
          Positioned(
            left: 24,
            right: 84,
            bottom: 0,
            height: _labelH,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                feature.label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: BT.display(27, color: BP.ink),
              ),
            ),
          ),
          Positioned(right: 18, bottom: (_labelH - 48) / 2, child: _Stamp(t: stamp)),
        ],
      ),
    );
  }
}

class _Back extends StatelessWidget {
  const _Back({required this.feature});

  final _Feature feature;

  @override
  Widget build(BuildContext context) {
    final parts = feature.workaround.split(' · ');
    return BpPanel(
      padding: EdgeInsets.zero,
      color: BP.amber,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in parts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(p, style: BT.mono(32, color: BP.amber, weight: 500)),
              ),
            const SizedBox(height: 26),
            Text(
              feature.label,
              style: BT.display(22, color: BP.inkDim).copyWith(
                decoration: TextDecoration.lineThrough,
                decorationColor: BP.red,
                decorationThickness: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Red rubber stamp with a ✕ that slams down on entry.
class _Stamp extends StatelessWidget {
  const _Stamp({required this.t});

  final double t;

  static const _size = Size(48, 48);

  @override
  Widget build(BuildContext context) {
    if (t <= 0) return SizedBox.fromSize(size: _size);
    final e = Curves.easeOutBack.transform(t);
    final scale = 2.4 - 1.4 * e;
    return Opacity(
      opacity: (t * 3).clamp(0.0, 1.0),
      child: Transform.rotate(
        angle: -0.2 + 0.08 * (1 - t),
        child: Transform.scale(
          scale: scale,
          child: const CustomPaint(size: _size, painter: _StampPainter()),
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
    final u = size.width / 50;
    final p = Paint()
      ..color = BP.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6;
    canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(1), const Radius.circular(4)), p);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.deflate(5 * u), const Radius.circular(2)),
      p..strokeWidth = 1,
    );
    canvas.drawRect(r.deflate(5 * u), Paint()..color = BP.red.withValues(alpha: 0.14));
    final x = Paint()
      ..color = BP.red
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final i = 15 * u;
    canvas.drawLine(r.topLeft + Offset(i, i), r.bottomRight - Offset(i, i), x);
    canvas.drawLine(r.topRight + Offset(-i, i), r.bottomLeft + Offset(i, -i), x);
  }

  @override
  bool shouldRepaint(_StampPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Illustrations (each loops on its own clock, started with the slide)
// ─────────────────────────────────────────────────────────────────────────────

double _ease(double x) => Curves.easeInOutCubic.transform(x.clamp(0.0, 1.0));

/// 0 before [a], rises to 1 by [b], holds until [c], falls back to 0 by [d].
double _pulse(double t, double a, double b, double c, double d) {
  if (t <= a || t >= d) return 0;
  if (t < b) return _ease((t - a) / (b - a));
  if (t <= c) return 1;
  return 1 - _ease((t - c) / (d - c));
}

/// Rebuilds every frame with the seconds since it was first built.
class _Clock extends StatefulWidget {
  const _Clock({required this.builder});

  final Widget Function(BuildContext context, double seconds) builder;

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _s = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => setState(() => _s = d.inMicroseconds / 1e6))..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _s);
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
    3 => const _KashidaIllo(),
    4 => const _FindIllo(),
    _ => const _FontsIllo(),
  };
}

// 1 · vertical text: a horizontal run folds into a top-to-bottom column.
class _VerticalIllo extends StatelessWidget {
  const _VerticalIllo();

  static const _chars = ['縦', '書', 'き'];

  @override
  Widget build(BuildContext context) {
    return _Clock(
      builder: (context, sec) => LayoutBuilder(
        builder: (context, box) {
          final m = _pulse((sec / 7) % 1, 0.14, 0.3, 0.9, 1.0);
          const s = 62.0;
          const step = 68.0;
          final cx = box.maxWidth / 2;
          final cy = box.maxHeight / 2;
          Offset at(int i) => Offset.lerp(
            Offset(cx + (i - 1) * step - s / 2, cy - s / 2 - 12),
            Offset(cx - s / 2 - 18, cy + (i - 1) * step - s / 2),
            m,
          )!;
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _Fn((canvas, size) {
                    final yb = cy + s / 2 + 8;
                    drawArrow(
                      canvas,
                      Offset(cx - 1.5 * step, yb),
                      Offset(cx + 1.5 * step, yb),
                      _stroke(BP.lineDim.withValues(alpha: 1 - m), 1.4),
                      dashed: true,
                      head: 8,
                    );
                    final xv = cx + s / 2 + 4;
                    drawArrow(
                      canvas,
                      Offset(xv, cy - 1.5 * step),
                      Offset(xv, cy + 1.5 * step),
                      _stroke(BP.amber.withValues(alpha: m), 1.6),
                      dashed: true,
                      head: 8,
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
                  child: Center(child: Text(_chars[i], style: BT.sample(46, height: 1))),
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

  static const _words = [
    [('漢', 'かん'), ('字', 'じ')],
    [('東', 'とう'), ('京', 'きょう')],
  ];

  @override
  Widget build(BuildContext context) {
    return _Clock(
      builder: (context, sec) {
        final cycle = sec / 7;
        final which = cycle.floor() % _words.length;
        final u = cycle % 1;
        final r = _pulse(u, 0.1, 0.26, 0.86, 0.94);
        final base = _pulse(u, -0.01, 0.05, 0.95, 1.01);
        return Center(
          child: Opacity(
            opacity: base,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (b, ruby) in _words[which])
                  SizedBox(
                    width: 118,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Opacity(
                          opacity: r,
                          child: Transform.translate(
                            offset: Offset(0, -22 * (1 - r)),
                            child: Text(ruby, style: BT.sample(27, color: BP.amber, height: 1.2)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 84 * r,
                          height: 2,
                          color: BP.amber.withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 8),
                        DashedBox(
                          color: BP.lineDim,
                          child: SizedBox(
                            width: 100,
                            height: 100,
                            child: Center(child: Text(b, style: BT.sample(74, height: 1))),
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

// 3 · hyphenation: a column narrows, the word breaks at a syllable with a hyphen.
class _HyphenIllo extends StatefulWidget {
  const _HyphenIllo();

  @override
  State<_HyphenIllo> createState() => _HyphenIlloState();
}

class _HyphenIlloState extends State<_HyphenIllo> {
  static const _syl = ['hy', 'phen', 'a', 'tion'];
  final _style = BT.display(52, color: BP.ink, height: 1.2);

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
    return _Clock(
      builder: (context, sec) => LayoutBuilder(
        builder: (context, box) {
          final lo = _w[1] + 8;
          final hi = _w[3] + 20;
          final w = hi - (hi - lo) * _pulse((sec / 8) % 1, 0.1, 0.3, 0.8, 0.95);
          var k = 4;
          while (k > 1 && _w[k - 1] > w) {
            k--;
          }
          final first = _syl.take(k).join();
          final rest = _syl.skip(k).join();
          final x0 = (box.maxWidth - hi) / 2;
          const y0 = 50.0;
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _Fn((canvas, size) {
                    canvas.drawLine(
                      Offset(x0, 12),
                      Offset(x0, size.height - 8),
                      _stroke(BP.lineDim, 1.4),
                    );
                    canvas.drawPath(
                      dashPath(Path()
                        ..moveTo(x0 + w, 12)
                        ..lineTo(x0 + w, size.height - 8)),
                      _stroke(BP.amber, 1.6),
                    );
                    final a = _stroke(BP.amber.withValues(alpha: 0.7), 1.4);
                    drawArrow(canvas, Offset(x0 + w / 2, 26), Offset(x0 + 3, 26), a, head: 7);
                    drawArrow(canvas, Offset(x0 + w / 2, 26), Offset(x0 + w - 3, 26), a, head: 7);
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
                  top: y0 + 66,
                  child: Text(rest, style: _style, softWrap: false),
                ),
            ],
          );
        },
      ),
    );
  }
}

// 4 · kashida: the same Arabic words justified by stretching letters with
// tatweel (ـ, amber) vs. by widening the space (dim, below).
class _KashidaIllo extends StatefulWidget {
  const _KashidaIllo();

  @override
  State<_KashidaIllo> createState() => _KashidaIlloState();
}

class _KashidaIlloState extends State<_KashidaIllo> {
  static const _size = 42.0;
  static const _maxExtra = 150.0;

  final _style = BT.sample(_size, color: BP.ink, height: 1.35);
  final _dim = BT.sample(_size, color: BP.inkDim, height: 1.35);
  final _amber = BT.sample(_size, color: BP.amber, height: 1.35);

  late final double _tatweel = _measure('ـ').width;
  late final Size _natural = _measure('نص جميل');
  late final double _w1 = _measure('نص').width;
  late final double _w2 = _measure('جميل').width;

  Size _measure(String s) {
    final p = TextProbe(TextSpan(text: s, style: _style), textDirection: TextDirection.rtl);
    final size = p.size;
    p.dispose();
    return size;
  }

  @override
  Widget build(BuildContext context) {
    return _Clock(
      builder: (context, sec) {
        final extra = _maxExtra * _pulse((sec / 8) % 1, 0.1, 0.3, 0.8, 0.95);
        final w = _natural.width + extra;
        final n = _tatweel > 0 ? (extra / _tatweel).floor() : 0;
        final n1 = n ~/ 2;
        final n2 = n - n1;
        final rowH = _natural.height;
        return LayoutBuilder(
          builder: (context, box) {
            final xr = (box.maxWidth + _natural.width + _maxExtra) / 2;
            final xl = xr - w;
            final rowA = (box.maxHeight - 2 * rowH - 16) / 2;
            final rowB = rowA + rowH + 16;
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _Fn((canvas, size) {
                      canvas.drawLine(
                        Offset(xr, 6),
                        Offset(xr, size.height - 6),
                        _stroke(BP.lineDim, 1.4),
                      );
                      canvas.drawPath(
                        dashPath(Path()
                          ..moveTo(xl, 6)
                          ..lineTo(xl, size.height - 6)),
                        _stroke(BP.amber, 1.6),
                      );
                      // The widened space in the lower row.
                      final g0 = xl + _w2 + 6;
                      final g1 = xr - _w1 - 6;
                      if (g1 - g0 > 8) {
                        final gy = rowB + rowH * 0.55;
                        final p = _stroke(BP.inkFaint, 1.6);
                        canvas.drawLine(Offset(g0, gy - 7), Offset(g0, gy + 7), p);
                        canvas.drawLine(Offset(g1, gy - 7), Offset(g1, gy + 7), p);
                        canvas.drawPath(
                          dashPath(Path()
                            ..moveTo(g0, gy)
                            ..lineTo(g1, gy), dash: 4, gap: 4),
                          p,
                        );
                      }
                    }),
                  ),
                ),
                Positioned(
                  left: 0,
                  width: xr,
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

// 5 · find in page: the browser types a query and walks the matches, because
// the page's text is real DOM text (so translate and search engines see it too).
class _FindIllo extends StatelessWidget {
  const _FindIllo();

  static const _lines = ['the text on a page', 'is real DOM text:', 'find · translate', 'every text node'];

  @override
  Widget build(BuildContext context) {
    return _Clock(
      builder: (context, sec) {
        final t = (sec / 8) % 1;
        final typed = t > 0.96 ? 0 : (((t - 0.04) / 0.14) * 4).floor().clamp(0, 4);
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
        final cur = hits.isEmpty || t < 0.22 ? -1 : ((t - 0.22) / 0.1).floor() % hits.length;
        final caret = (sec * 2.5).floor().isEven;
        final style = BT.sample(25, color: BP.inkDim, height: 1.3);
        return Center(
          child: SizedBox(
            width: 330,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 250,
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(border: Border.all(color: BP.line, width: 1.4)),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 22, color: BP.inkDim),
                      const SizedBox(width: 8),
                      Text(q, style: BT.mono(22, color: BP.ink)),
                      Container(width: 2, height: 24, color: caret ? BP.amber : Colors.transparent),
                      const Spacer(),
                      Text(
                        hits.isEmpty ? '' : '${cur < 0 ? 1 : cur + 1}/${hits.length}',
                        style: BT.mono(18, color: BP.amber),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                for (var l = 0; l < _lines.length; l++)
                  Text.rich(_spans(l, q, hits, cur, style)),
              ],
            ),
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

// 6 · fonts on demand: canvas text is tofu until the whole font file arrives
// (the browser would have used a local font, or fetched just a subset).
class _FontsIllo extends StatefulWidget {
  const _FontsIllo();

  @override
  State<_FontsIllo> createState() => _FontsIlloState();
}

class _FontsIlloState extends State<_FontsIllo> {
  static const _word = '日本語';

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
    final p = TextProbe(TextSpan(text: _word, style: BT.sample(90, height: 1.2)));
    _probe = p;
    for (final (s, e) in p.graphemes()) {
      _boxes.add(p.rectFor(s, e) ?? Rect.zero);
      final hex = _word.substring(s, e).runes.first.toRadixString(16).toUpperCase().padLeft(4, '0');
      _hex.add(TextPainter(
        text: TextSpan(
          text: '${hex.substring(0, 2)}\n${hex.substring(2)}',
          style: BT.mono(17, color: BP.inkDim, height: 1.15),
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
    return _Clock(
      builder: (context, sec) {
        final t = (sec / 8) % 1;
        final tofu = t < 0.74 ? 1.0 : 1 - _ease((t - 0.74) / 0.05);
        final glyph = _ease((t - 0.76) / 0.08);
        final load = _ease((t - 0.1) / 0.62);
        final showBar = t > 0.06 && t < 0.78;
        return CustomPaint(
          painter: _Fn((canvas, size) {
            final p = _probe!;
            final o = Offset((size.width - p.size.width) / 2, (size.height - p.size.height) / 2 - 16);
            if (glyph > 0) {
              canvas.saveLayer(
                (o & p.size).inflate(10),
                Paint()..color = Color.fromRGBO(0, 0, 0, glyph),
              );
              p.paint(canvas, o);
              canvas.restore();
            }
            if (tofu > 0) {
              for (var i = 0; i < _boxes.length; i++) {
                final b = _boxes[i].shift(o);
                final r = Rect.fromLTWH(b.left + 5, b.top + b.height * 0.14, b.width - 10, b.height * 0.72);
                canvas.drawRect(r, _stroke(BP.inkDim.withValues(alpha: tofu), 1.6));
                if (tofu > 0.5) {
                  final h = _hex[i];
                  h.paint(canvas, r.center - Offset(h.width / 2, h.height / 2));
                }
              }
            }
            if (showBar) {
              final by = o.dy + p.size.height + 14;
              final x0 = o.dx;
              final x1 = o.dx + p.size.width;
              canvas.drawLine(Offset(x0, by), Offset(x1, by), _stroke(BP.lineFaint, 5));
              canvas.drawLine(Offset(x0, by), Offset(x0 + (x1 - x0) * load, by), _stroke(BP.amber, 5));
              final ay = by - 22 + 5 * math.sin(sec * 7);
              drawArrow(
                canvas,
                Offset(x1 + 28, ay - 18),
                Offset(x1 + 28, ay + 6),
                _stroke(BP.amber, 2),
                head: 8,
              );
            }
          }),
        );
      },
    );
  }
}
