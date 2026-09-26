import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../deck/theme.dart';
import '../deck/widgets.dart';

/// Android: Minikin's three break strategies side by side on one paragraph,
/// and how Flutter's text stack descends from it.
class AndroidSlide extends StatelessWidget {
  const AndroidSlide({super.key});

  @override
  Widget build(BuildContext context) => const SlideFrame(
    title: 'Android · Minikin',
    child: _EngineLayout(
      hero: _BreakHero(),
      layers: [
        _Layer('TextView / Compose', 'UI toolkit'),
        _Layer('StaticLayout', 'android.text'),
        _Layer('Minikin', 'itemize · fallback · breaks · hyphens'),
        _Layer('HarfBuzz', 'shaping'),
        _Layer('HWUI / Skia', 'GPU'),
      ],
      caps: [
        _Cap('hyphenation', _K.yes),
        _Cap('phrase breaks (JA) · 13', _K.yes),
        _Cap('inter-character justify · 15', _K.yes),
        _Cap('vertical Paint flag · 16'),
      ],
    ),
  );
}

TextPainter _tp(String s, TextStyle style) =>
    TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();

double _spaceOf(TextStyle style) {
  final a = _tp('a a', style);
  final b = _tp('aa', style);
  final w = a.width - b.width;
  a.dispose();
  b.dispose();
  return w;
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero: simple · balanced · high quality
// ─────────────────────────────────────────────────────────────────────────────

typedef _Lines = List<(int, int)>;

class _BreakHero extends StatefulWidget {
  const _BreakHero();

  @override
  State<_BreakHero> createState() => _BreakHeroState();
}

class _BreakHeroState extends State<_BreakHero> with SingleTickerProviderStateMixin {
  static const _text =
      'Minikin weighs the whole paragraph before it breaks a single line, so one '
      'extraordinarily long word near the end can reshape every line above it.';
  static const _fs = 19.0;
  static const _lh = 27.0;
  static const _colW = 300.0;
  static const _colGap = 40.0;
  static const _paraTop = 70.0;
  static const _maxW = _colW;
  static const _names = ['simple', 'balanced', 'high quality'];
  static const _consts = [
    'BREAK_STRATEGY_SIMPLE',
    'BREAK_STRATEGY_BALANCED',
    'BREAK_STRATEGY_HIGH_QUALITY',
  ];

  late final TextStyle _style = BT.display(_fs);
  late final List<TextPainter> _tps = [for (final w in _text.split(' ')) _tp(w, _style)];
  late final List<double> _ww = [for (final t in _tps) t.width];
  late final double _space = _spaceOf(_style);
  late final double _minW = (_ww.reduce(math.max) + 16).ceilToDouble();

  double _w = 250;
  bool _sweep = true;
  double _phase = 0.3;
  double _laidW = -1;
  List<_Lines> _lines = const [[], [], []];
  List<List<Offset>> _target = const [];
  List<List<Offset>> _cur = const [];
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  int _lineageNonce = 0;

  int get _n => _tps.length;

  @override
  void initState() {
    super.initState();
    _w = _widthAt(_phase);
    _relayout();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    for (final t in _tps) {
      t.dispose();
    }
    super.dispose();
  }

  double _widthAt(double p) => _minW + (_maxW - _minW) * (0.5 - 0.5 * math.cos(2 * math.pi * p));

  void _tick(Duration e) {
    final dt = ((e - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = e;
    if (_sweep) {
      _phase = (_phase + dt / 14) % 1.0;
      _w = _widthAt(_phase);
    }
    _relayout();
    // Words glide to their new line positions.
    final k = 1 - math.exp(-dt * 10);
    var moving = false;
    for (var s = 0; s < 3; s++) {
      for (var i = 0; i < _n; i++) {
        final d = _target[s][i] - _cur[s][i];
        if (d.distance > 0.05) {
          _cur[s][i] += d * k;
          moving = true;
        } else {
          _cur[s][i] = _target[s][i];
        }
      }
    }
    if (moving || _sweep) setState(() {});
  }

  void _toggleSweep() => setState(() {
    _sweep = !_sweep;
    if (_sweep) {
      final u = ((_w - _minW) / (_maxW - _minW)).clamp(0.0, 1.0);
      _phase = math.acos(1 - 2 * u) / (2 * math.pi);
    }
  });

  // ── line breaking ──

  double _len(int i, int j) {
    var s = 0.0;
    for (var k = i; k < j; k++) {
      s += _ww[k];
    }
    return s + _space * (j - i - 1);
  }

  /// SIMPLE: first fit, one line at a time (what SkParagraph does too).
  _Lines _greedy(double w) {
    final out = <(int, int)>[];
    var i = 0;
    while (i < _n) {
      var j = i + 1;
      while (j < _n && _len(i, j + 1) <= w) {
        j++;
      }
      out.add((i, j));
      i = j;
    }
    return out;
  }

  /// HIGH_QUALITY: whole-paragraph DP minimising Σ slack², last line free.
  _Lines _optimal(double w) {
    final f = List<double>.filled(_n + 1, double.infinity);
    final from = List<int>.filled(_n + 1, 0);
    f[0] = 0;
    for (var j = 1; j <= _n; j++) {
      for (var i = j - 1; i >= 0; i--) {
        final l = _len(i, j);
        if (l > w && j - i > 1) break;
        final slack = w - l;
        final cost = l > w ? 1e9 : (j == _n ? 0.0 : slack * slack);
        if (f[i] + cost < f[j]) {
          f[j] = f[i] + cost;
          from[j] = i;
        }
      }
    }
    return _backtrack((j) => from[j]);
  }

  /// BALANCED: same line count as greedy, minimising Σ slack² including the
  /// last line (= minimum variance of line lengths).
  _Lines _balanced(double w, int count) {
    const inf = double.infinity;
    final g = List.generate(count + 1, (_) => List<double>.filled(_n + 1, inf));
    final from = List.generate(count + 1, (_) => List<int>.filled(_n + 1, 0));
    g[0][0] = 0;
    for (var m = 1; m <= count; m++) {
      for (var j = 1; j <= _n; j++) {
        for (var i = j - 1; i >= 0; i--) {
          final l = _len(i, j);
          if (l > w && j - i > 1) break;
          if (g[m - 1][i] == inf) continue;
          final slack = w - l;
          final c = g[m - 1][i] + (l > w ? 1e9 : slack * slack);
          if (c < g[m][j]) {
            g[m][j] = c;
            from[m][j] = i;
          }
        }
      }
    }
    if (g[count][_n] == inf) return _greedy(w);
    final out = <(int, int)>[];
    var j = _n;
    for (var m = count; m > 0; m--) {
      final i = from[m][j];
      out.insert(0, (i, j));
      j = i;
    }
    return out;
  }

  _Lines _backtrack(int Function(int j) from) {
    final out = <(int, int)>[];
    var j = _n;
    while (j > 0) {
      final i = from(j);
      out.insert(0, (i, j));
      j = i;
    }
    return out;
  }

  List<Offset> _place(_Lines lines) {
    final pos = List<Offset>.filled(_n, Offset.zero);
    for (var li = 0; li < lines.length; li++) {
      var x = 0.0;
      for (var i = lines[li].$1; i < lines[li].$2; i++) {
        pos[i] = Offset(x, li * _lh);
        x += _ww[i] + _space;
      }
    }
    return pos;
  }

  void _relayout() {
    final w = _w.roundToDouble();
    if (w == _laidW) return;
    _laidW = w;
    final g = _greedy(w);
    _lines = [g, _balanced(w, g.length), _optimal(w)];
    _target = [for (final l in _lines) _place(l)];
    if (_cur.isEmpty) _cur = [for (final t in _target) List.of(t)];
  }

  // ── build ──

  Widget _column(int s) => Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned(
        left: 0,
        top: 0,
        right: 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_names[s], style: BT.display(24, color: BP.ink)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(_consts[s], style: BT.mono(11, color: BP.inkFaint)),
                const Spacer(),
                Text('${_lines[s].length} lines', style: BT.mono(11, color: BP.inkDim)),
              ],
            ),
          ],
        ),
      ),
      Positioned(
        left: 0,
        top: _paraTop,
        right: 0,
        bottom: 0,
        child: CustomPaint(
          painter: _ColumnPainter(
            tps: _tps,
            ww: _ww,
            pos: _cur[s],
            lines: _lines[s],
            width: _laidW,
            countLast: s == 1,
            lh: _lh,
          ),
        ),
      ),
      if (s == 0)
        AnimatedPositioned(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          left: 0,
          top: _paraTop + _lines[0].length * _lh + 14,
          child: const BpTag('= Flutter', color: BP.amber, size: 14),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var s = 0; s < 3; s++)
          Positioned(
            left: s * (_colW + _colGap),
            top: 0,
            width: _colW,
            height: 410,
            child: Reveal(
              visible: true,
              delay: Duration(milliseconds: 150 + 150 * s),
              child: _column(s),
            ),
          ),
        Positioned(
          left: 0,
          top: 420,
          child: Row(
            children: [
              BpSlider(
                label: 'width',
                value: _w.clamp(_minW, _maxW),
                min: _minW,
                max: _maxW,
                width: 420,
                format: (v) => '${v.round()} px',
                onChanged: (v) => setState(() {
                  _sweep = false;
                  _w = v;
                }),
              ),
              const SizedBox(width: 10),
              BpButton(label: 'sweep', size: 14, selected: _sweep, onTap: _toggleSweep),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 486,
          bottom: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _lineageNonce++),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: BpPanel(
                label: 'lineage',
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: _Lineage(key: ValueKey(_lineageNonce)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ColumnPainter extends CustomPainter {
  _ColumnPainter({
    required this.tps,
    required this.ww,
    required this.pos,
    required this.lines,
    required this.width,
    required this.countLast,
    required this.lh,
  });

  final List<TextPainter> tps;
  final List<double> ww;
  final List<Offset> pos;
  final _Lines lines;
  final double width;
  final bool countLast;
  final double lh;

  @override
  void paint(Canvas canvas, Size size) {
    final bottom = lines.length * lh + 6;
    canvas.drawLine(
      const Offset(-8, -8),
      Offset(-8, bottom),
      Paint()
        ..color = BP.lineDim
        ..strokeWidth = 1,
    );
    canvas.drawPath(
      dashPath(Path()
        ..moveTo(width, -8)
        ..lineTo(width, bottom), dash: 5, gap: 4),
      Paint()
        ..color = BP.amber.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Raggedness: the slack left at the end of every line.
    final fill = Paint()..color = BP.coral.withValues(alpha: 0.6);
    final outline = Paint()
      ..color = BP.coral.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke;
    for (var li = 0; li < lines.length; li++) {
      final (a, b) = lines[li];
      var end = 0.0;
      for (var i = a; i < b; i++) {
        end = math.max(end, pos[i].dx + ww[i]);
      }
      final from = end + 6;
      if (from >= width - 1) continue;
      final y = li * lh + 13;
      final r = Rect.fromLTRB(from, y - 3, width - 1, y + 3);
      final last = li == lines.length - 1;
      if (last && !countLast) {
        canvas.drawPath(dashPath(Path()..addRect(r), dash: 3, gap: 3), outline);
      } else {
        canvas.drawRect(r, fill);
      }
    }

    for (var i = 0; i < tps.length; i++) {
      tps[i].paint(canvas, pos[i]);
    }
  }

  @override
  bool shouldRepaint(_ColumnPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Lineage: Minikin → libtxt → SkParagraph
// ─────────────────────────────────────────────────────────────────────────────

class _Lineage extends StatelessWidget {
  const _Lineage({super.key});

  static const _nodes = [
    ('Minikin', 'Android'),
    ('libtxt', "Flutter's fork"),
    ('SkParagraph', 'default · Flutter 3.0 · 2022'),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final w = box.maxWidth;
      final xs = [w * 0.1, w * 0.5, w * 0.9];
      const y = 24.0;
      return LoopBuilder(
        period: const Duration(milliseconds: 8000),
        builder: (context, t, _) {
          double seg(double a, double b) =>
              Curves.easeInOutCubic.transform(((t - a) / (b - a)).clamp(0.0, 1.0));
          final fade = 1 - seg(0.94, 1.0);
          final p1 = seg(0.08, 0.34);
          final p2 = seg(0.44, 0.70);
          final lit = [seg(0.0, 0.08) * fade, seg(0.32, 0.40) * fade, seg(0.68, 0.76) * fade];
          final strike = seg(0.78, 0.88) * fade;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _LineagePainter(xs: xs, y: y, p1: p1, p2: p2, lit: lit, fade: fade),
                ),
              ),
              for (final (i, label) in ['fork', 'replaced by'].indexed)
                Positioned(
                  left: (xs[i] + xs[i + 1]) / 2 - 80,
                  width: 160,
                  top: y - 22,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: BT.mono(12, color: BP.inkDim),
                  ),
                ),
              for (var i = 0; i < 3; i++)
                Positioned(
                  left: xs[i] - 130,
                  width: 260,
                  top: y + 14,
                  child: Column(
                    children: [
                      CustomPaint(
                        foregroundPainter: _StrikePainter(i == 1 ? strike : 0),
                        child: Text(
                          _nodes[i].$1,
                          style: BT.display(
                            21,
                            color: Color.lerp(BP.inkDim, i == 2 ? BP.amber : BP.ink, lit[i])!,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(_nodes[i].$2, style: BT.mono(12, color: BP.inkFaint)),
                    ],
                  ),
                ),
              Positioned(
                left: xs[1] + 60,
                top: y + 16,
                child: Opacity(
                  opacity: strike,
                  child: _CapTags._tag(const _Cap('removed · 3.10 · 2023', _K.no)),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

class _StrikePainter extends CustomPainter {
  _StrikePainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final y = size.height * 0.55;
    canvas.drawLine(
      Offset(-4, y),
      Offset(-4 + (size.width + 8) * t, y),
      Paint()
        ..color = BP.red
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_StrikePainter old) => old.t != t;
}

class _LineagePainter extends CustomPainter {
  _LineagePainter({
    required this.xs,
    required this.y,
    required this.p1,
    required this.p2,
    required this.lit,
    required this.fade,
  });

  final List<double> xs;
  final double y;
  final double p1;
  final double p2;
  final List<double> lit;
  final double fade;

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..color = BP.lineDim
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 2; i++) {
      final a = Offset(xs[i] + 14, y);
      final b = Offset(xs[i + 1] - 14, y);
      canvas.drawPath(dashPath(Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy), dash: 6, gap: 4), base);
      drawArrowHead(canvas, b, a, base, 7);
    }
    final hot = Paint()
      ..color = BP.line.withValues(alpha: fade)
      ..strokeWidth = 2;
    final x1 = xs[0] + (xs[1] - xs[0]) * p1;
    final x2 = xs[1] + (xs[2] - xs[1]) * p2;
    if (p1 > 0) canvas.drawLine(Offset(xs[0], y), Offset(x1, y), hot);
    if (p2 > 0) canvas.drawLine(Offset(xs[1], y), Offset(x2, y), hot);

    for (var i = 0; i < 3; i++) {
      final c = Offset(xs[i], y);
      final d = Path()
        ..moveTo(c.dx, c.dy - 10)
        ..lineTo(c.dx + 10, c.dy)
        ..lineTo(c.dx, c.dy + 10)
        ..lineTo(c.dx - 10, c.dy)
        ..close();
      final on = i == 2 ? BP.amber : BP.line;
      canvas.drawPath(d, Paint()..color = Color.lerp(BP.paper, on.withValues(alpha: 0.35), lit[i])!);
      canvas.drawPath(
        d,
        Paint()
          ..color = Color.lerp(BP.lineDim, on, lit[i])!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }

    // Packet
    double? px;
    if (p1 > 0 && p1 < 1) px = x1;
    if (p2 > 0 && p2 < 1) px = x2;
    if (px != null) {
      for (var k = 1; k <= 6; k++) {
        canvas.drawCircle(
          Offset(px - k * 9, y),
          3.5 - k * 0.45,
          Paint()..color = BP.amber.withValues(alpha: 0.5 - k * 0.07),
        );
      }
      final d = Path()
        ..moveTo(px, y - 7)
        ..lineTo(px + 7, y)
        ..lineTo(px, y + 7)
        ..lineTo(px - 7, y)
        ..close();
      canvas.drawPath(d, Paint()..color = BP.amber);
    }
  }

  @override
  bool shouldRepaint(_LineagePainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Engine layout: hero (≈ 2/3) · stack strip · capability tags
// ─────────────────────────────────────────────────────────────────────────────

const _heroW = 980.0;
const _sideX = 1016.0;
const _stripH = 440.0;

class _Layer {
  const _Layer(this.name, this.sub);

  final String name;
  final String sub;
}

enum _K { yes, no, info, flutter }

class _Cap {
  const _Cap(this.text, [this.kind = _K.info]);

  final String text;
  final _K kind;
}

class _EngineLayout extends StatelessWidget {
  const _EngineLayout({required this.hero, required this.layers, required this.caps});

  final Widget hero;
  final List<_Layer> layers;
  final List<_Cap> caps;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned(left: 0, top: 0, width: _heroW, bottom: 0, child: hero),
      Positioned(
        left: _sideX,
        top: 0,
        right: 0,
        height: _stripH,
        child: Reveal(
          visible: true,
          delay: const Duration(milliseconds: 250),
          offset: const Offset(24, 0),
          child: _StackStrip(layers: layers),
        ),
      ),
      Positioned(
        left: _sideX,
        top: _stripH + 30,
        right: 0,
        bottom: 0,
        child: _CapTags(caps: caps),
      ),
    ],
  );
}

class _CapTags extends StatelessWidget {
  const _CapTags({required this.caps});

  final List<_Cap> caps;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      for (var i = 0; i < caps.length; i++)
        Reveal(
          visible: true,
          delay: Duration(milliseconds: 900 + 110 * i),
          offset: const Offset(0, 12),
          child: _tag(caps[i]),
        ),
    ],
  );

  static Widget _tag(_Cap c) {
    final color = switch (c.kind) {
      _K.yes => BP.green,
      _K.no => BP.red,
      _K.flutter => BP.amber,
      _K.info => BP.line,
    };
    final mark = c.kind == _K.yes || c.kind == _K.no;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mark) ...[
            _Mark(yes: c.kind == _K.yes, color: color, size: 12),
            const SizedBox(width: 7),
          ],
          Text(c.text, style: BT.mono(14, color: color)),
        ],
      ),
    );
  }
}

/// A drawn ✓ / ✕ (the mono font has no check mark).
class _Mark extends StatelessWidget {
  const _Mark({required this.yes, required this.color, this.size = 13});

  final bool yes;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _MarkPainter(yes, color)),
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.yes, this.color);

  final bool yes;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = math.max(1.6, s.width * 0.15)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = s.width;
    final h = s.height;
    final path = yes
        ? (Path()
            ..moveTo(w * 0.1, h * 0.55)
            ..lineTo(w * 0.4, h * 0.84)
            ..lineTo(w * 0.92, h * 0.18))
        : (Path()
            ..moveTo(w * 0.18, h * 0.18)
            ..lineTo(w * 0.82, h * 0.82)
            ..moveTo(w * 0.82, h * 0.18)
            ..lineTo(w * 0.18, h * 0.82));
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.yes != yes || old.color != color;
}

/// The engine's layers, top to bottom, with a packet hopping through them.
class _StackStrip extends StatefulWidget {
  const _StackStrip({required this.layers});

  final List<_Layer> layers;

  @override
  State<_StackStrip> createState() => _StackStripState();
}

class _StackStripState extends State<_StackStrip> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final n = widget.layers.length;
    return BpPanel(
      label: 'stack',
      padding: const EdgeInsets.fromLTRB(14, 30, 18, 18),
      child: LayoutBuilder(
        builder: (context, box) {
          final slot = box.maxHeight / n;
          final h = math.min(54.0, slot - 14);
          return LoopBuilder(
            period: Duration(milliseconds: 1000 * n + 1600),
            builder: (context, t, _) {
              final travel = n - 1.0;
              final u = t * (travel + 1.6);
              var pos = travel;
              if (u < travel) {
                final seg = u.floor();
                final f = ((u - seg - 0.3) / 0.7).clamp(0.0, 1.0);
                pos = seg + Curves.easeInOutCubic.transform(f);
              }
              final fade = u < 0.15
                  ? u / 0.15
                  : (u > travel + 1.0 ? (1 - (u - travel - 1.0) / 0.6).clamp(0.0, 1.0) : 1.0);
              final active = (pos - pos.round()).abs() < 0.2 && fade > 0.3 ? pos.round() : -1;
              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RailPainter(n: n, slot: slot, pos: pos, alpha: fade, boxLeft: 34),
                    ),
                  ),
                  for (var i = 0; i < n; i++)
                    Positioned(
                      left: 34,
                      right: 0,
                      top: slot * i + (slot - h) / 2,
                      height: h,
                      child: Reveal(
                        visible: true,
                        delay: Duration(milliseconds: 400 + 90 * i),
                        offset: const Offset(16, 0),
                        child: MouseRegion(
                          onEnter: (_) => setState(() => _hover = i),
                          onExit: (_) => setState(() => _hover = null),
                          child: _LayerBox(
                            layer: widget.layers[i],
                            hot: i == active || i == _hover,
                            passed: pos >= i - 0.01 && fade > 0.3,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _LayerBox extends StatelessWidget {
  const _LayerBox({required this.layer, required this.hot, required this.passed});

  final _Layer layer;
  final bool hot;
  final bool passed;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 220),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: hot ? BP.amber.withValues(alpha: 0.10) : BP.panel,
      border: Border.all(
        color: hot ? BP.amber : (passed ? BP.line.withValues(alpha: 0.7) : BP.lineDim),
        width: hot ? 1.6 : 1,
      ),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          layer.name,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          style: BT.mono(16, color: hot ? BP.amber : BP.ink, weight: 500, height: 1.2),
        ),
        const SizedBox(height: 2),
        Text(
          layer.sub,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          style: BT.mono(11.5, color: BP.inkFaint, height: 1.2),
        ),
      ],
    ),
  );
}

class _RailPainter extends CustomPainter {
  _RailPainter({
    required this.n,
    required this.slot,
    required this.pos,
    required this.alpha,
    required this.boxLeft,
  });

  final int n;
  final double slot;
  final double pos;
  final double alpha;
  final double boxLeft;

  @override
  void paint(Canvas canvas, Size size) {
    const x = 10.0;
    double y(double i) => slot * i + slot / 2;
    canvas.drawLine(
      Offset(x, y(0)),
      Offset(x, y(n - 1.0)),
      Paint()
        ..color = BP.lineDim
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(x, y(0)),
      Offset(x, y(pos)),
      Paint()
        ..color = BP.line.withValues(alpha: 0.8 * alpha)
        ..strokeWidth = 2,
    );
    for (var i = 0; i < n; i++) {
      final yi = y(i.toDouble());
      final on = pos >= i - 0.01 && alpha > 0.3;
      canvas.drawLine(
        Offset(x, yi),
        Offset(boxLeft, yi),
        Paint()
          ..color = (on ? BP.line : BP.lineDim)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(Offset(x, yi), 4.5, Paint()..color = BP.paper);
      canvas.drawCircle(
        Offset(x, yi),
        4.5,
        Paint()
          ..color = (on ? BP.line : BP.lineDim)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      if (i < n - 1) {
        final ym = y(i + 0.5);
        drawArrowHead(
          canvas,
          Offset(x, ym + 3),
          Offset(x, ym - 5),
          Paint()
            ..color = BP.lineDim
            ..strokeWidth = 1.2,
          5,
        );
      }
    }
    if (alpha <= 0.01) return;
    final py = y(pos);
    for (var k = 1; k <= 6; k++) {
      final ty = py - k * 7;
      if (ty < y(0)) break;
      canvas.drawCircle(
        Offset(x, ty),
        3.5 - k * 0.45,
        Paint()..color = BP.amber.withValues(alpha: (0.5 - k * 0.07) * alpha),
      );
    }
    final d = Path()
      ..moveTo(x, py - 9)
      ..lineTo(x + 9, py)
      ..lineTo(x, py + 9)
      ..lineTo(x - 9, py)
      ..close();
    canvas.drawPath(d, Paint()..color = BP.amber.withValues(alpha: alpha));
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.pos != pos || old.alpha != alpha || old.n != n || old.slot != slot;
}
