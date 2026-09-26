import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../deck/theme.dart';
import '../deck/widgets.dart';

/// Chrome: text lives in the DOM, so the browser gets six features for free.
/// Hero = six live illustrations; right = Blink's text stack + tags.
class ChromeSlide extends StatelessWidget {
  const ChromeSlide({super.key});

  @override
  Widget build(BuildContext context) => const SlideFrame(
    title: 'Chrome',
    child: _EngineLayout(
      hero: _FeatureGrid(),
      layers: [
        _Layer('<p> DOM text', 'Blink · real nodes'),
        _Layer('style', 'CSS → font · size · wrap'),
        _Layer('LayoutNG', 'inline · ICU breaks · bidi'),
        _Layer('HarfBuzzShaper', 'HarfBuzz'),
        _Layer('paint', 'display items'),
        _Layer('Skia', 'Ganesh · Graphite'),
        _Layer('GPU', 'glyph atlas · big glyphs = paths'),
      ],
      caps: [
        _Cap('selection', _K.yes),
        _Cap('a11y', _K.yes),
        _Cap('SEO', _K.yes),
        _Cap('text-wrap: pretty', _K.yes),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero: six live features
// ─────────────────────────────────────────────────────────────────────────────

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid();

  @override
  Widget build(BuildContext context) {
    const cells = <Widget>[
      _VerticalDemo(),
      _RubyDemo(),
      _HyphenDemo(),
      _BalanceDemo(),
      _FindDemo(),
      _TranslateDemo(),
    ];
    return BpPanel(
      label: 'real DOM text',
      padding: const EdgeInsets.fromLTRB(22, 30, 22, 22),
      child: LayoutBuilder(
        builder: (context, box) {
          const gap = 18.0;
          final w = (box.maxWidth - 2 * gap) / 3;
          final h = (box.maxHeight - gap) / 2;
          return Stack(
            children: [
              for (var i = 0; i < cells.length; i++)
                Positioned(
                  left: (i % 3) * (w + gap),
                  top: (i ~/ 3) * (h + gap),
                  width: w,
                  height: h,
                  child: Reveal(
                    visible: true,
                    delay: Duration(milliseconds: 150 + 110 * i),
                    child: cells[i],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// One feature tile: live illustration on top, "label ✓ · css hint" below.
class _Cell extends StatefulWidget {
  const _Cell({required this.label, required this.hint, required this.child, this.onTap});

  final String label;
  final String hint;
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final edge = _hover ? BP.line : BP.lineFaint;
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: _hover ? BP.line.withValues(alpha: 0.05) : BP.paper.withValues(alpha: 0.4),
            border: Border.all(color: edge),
          ),
          child: Column(
            children: [
              Expanded(
                child: ClipRect(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    child: widget.child,
                  ),
                ),
              ),
              AnimatedContainer(duration: const Duration(milliseconds: 200), height: 1, color: edge),
              SizedBox(
                height: 40,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Text(widget.label, style: BT.mono(16, color: BP.ink)),
                      const SizedBox(width: 8),
                      const _Mark(yes: true, color: BP.green, size: 14),
                      const Spacer(),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          widget.hint,
                          key: ValueKey(widget.hint),
                          style: BT.mono(12, color: BP.inkFaint),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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

Path _rectPath(Rect r) => Path()..addRect(r);

// ── 1. vertical ──────────────────────────────────────────────────────────────

class _VerticalDemo extends StatefulWidget {
  const _VerticalDemo();

  @override
  State<_VerticalDemo> createState() => _VerticalDemoState();
}

class _VerticalDemoState extends State<_VerticalDemo> with TickerProviderStateMixin {
  // "Vertical writing goes right to left", one column each.
  static const _cols = ['縦書きは', '右から左へ'];

  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
    value: 1,
  );
  late final AnimationController _read = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  )..repeat();
  late final List<(int, int, TextPainter)> _glyphs = [
    for (var c = 0; c < _cols.length; c++)
      for (final (r, ch) in _cols[c].characters.indexed) (c, r, _tp(ch, BT.sample(27))),
  ];
  bool _vertical = true;

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
  }

  // CJK comes from fallback fonts (downloaded on demand on the web).
  void _fontsChanged() {
    if (!mounted) return;
    setState(() {
      for (final g in _glyphs) {
        g.$3
          ..markNeedsLayout()
          ..layout();
      }
    });
  }

  void _toggle() {
    setState(() => _vertical = !_vertical);
    _vertical ? _flip.forward() : _flip.reverse();
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    _flip.dispose();
    _read.dispose();
    for (final g in _glyphs) {
      g.$3.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Cell(
    label: 'vertical',
    hint: _vertical ? 'vertical-rl' : 'horizontal-tb',
    onTap: _toggle,
    child: CustomPaint(
      size: Size.infinite,
      painter: _VerticalPainter(glyphs: _glyphs, flip: _flip, read: _read),
    ),
  );
}

class _VerticalPainter extends CustomPainter {
  _VerticalPainter({required this.glyphs, required this.flip, required this.read})
    : super(repaint: Listenable.merge([flip, read]));

  final List<(int, int, TextPainter)> glyphs;
  final Animation<double> flip;
  final Animation<double> read;

  static const _pitch = 38.0;

  @override
  void paint(Canvas canvas, Size size) {
    const cols = 2;
    const rows = 5;
    final c = size.center(Offset.zero);
    final vo = c - const Offset(cols * _pitch / 2, rows * _pitch / 2);
    final ho = c - const Offset(rows * _pitch / 2, cols * _pitch / 2);
    Rect vCell(int col, int row) =>
        Rect.fromLTWH(vo.dx + (cols - 1 - col) * _pitch, vo.dy + row * _pitch, _pitch, _pitch);
    Rect hCell(int col, int row) =>
        Rect.fromLTWH(ho.dx + row * _pitch, ho.dy + col * _pitch, _pitch, _pitch);

    final f = flip.value;
    final n = glyphs.length;
    const stagger = 0.045;
    final rects = <Rect>[];
    for (var i = 0; i < n; i++) {
      final (col, row, _) = glyphs[i];
      final lt = ((f - i * stagger) / (1 - (n - 1) * stagger)).clamp(0.0, 1.0);
      final e = Curves.easeInOutCubic.transform(lt);
      final arc = math.sin(e * math.pi);
      rects.add(Rect.lerp(hCell(col, row), vCell(col, row), e)!.shift(Offset(arc * 12, -arc * 12)));
    }

    // Rules: column rules when vertical, line rules when horizontal.
    for (var k = 0; k <= cols; k++) {
      if (f > 0.01) {
        final x = vo.dx + k * _pitch;
        canvas.drawPath(
          dashPath(Path()
            ..moveTo(x, vo.dy - 10)
            ..lineTo(x, vo.dy + rows * _pitch + 10), dash: 4, gap: 4),
          Paint()
            ..color = BP.lineDim.withValues(alpha: 0.9 * f)
            ..style = PaintingStyle.stroke,
        );
      }
      if (f < 0.99) {
        final y = ho.dy + k * _pitch;
        canvas.drawPath(
          dashPath(Path()
            ..moveTo(ho.dx - 10, y)
            ..lineTo(ho.dx + rows * _pitch + 10, y), dash: 4, gap: 4),
          Paint()
            ..color = BP.lineDim.withValues(alpha: 0.9 * (1 - f))
            ..style = PaintingStyle.stroke,
        );
      }
    }

    // Reading order: a thread drawn through the glyphs, first column first.
    final rp = (read.value * 1.25).clamp(0.0, 1.0);
    final thread = Path()..moveTo(rects[0].center.dx, rects[0].center.dy);
    for (var i = 1; i < n; i++) {
      thread.lineTo(rects[i].center.dx, rects[i].center.dy);
    }
    final amber = Paint()
      ..color = BP.amber.withValues(alpha: 0.45)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(partialPath(thread, rp), amber);
    var head = rects[0].center;
    final metrics = thread.computeMetrics().toList();
    if (metrics.isNotEmpty) {
      final m = metrics.first;
      final tan = m.getTangentForOffset(m.length * rp);
      final back = m.getTangentForOffset(math.max(0, m.length * rp - 8));
      if (tan != null) {
        head = tan.position;
        if (back != null && rp > 0.02) {
          drawArrowHead(canvas, tan.position, back.position, amber..color = BP.amber, 7);
        }
      }
    }
    var hot = 0;
    var best = double.infinity;
    for (var i = 0; i < n; i++) {
      final d = (rects[i].center - head).distance;
      if (d < best) {
        best = d;
        hot = i;
      }
    }

    // Em boxes + glyphs.
    final box = Paint()
      ..color = BP.lineFaint
      ..style = PaintingStyle.stroke;
    final hotBox = Paint()
      ..color = BP.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 0; i < n; i++) {
      final r = rects[i].deflate(3);
      final isHot = i == hot && rp < 1;
      if (isHot) canvas.drawRect(r, Paint()..color = BP.amber.withValues(alpha: 0.14));
      canvas.drawPath(dashPath(_rectPath(r), dash: 3, gap: 3), isHot ? hotBox : box);
      final tp = glyphs[i].$3;
      tp.paint(canvas, rects[i].center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_VerticalPainter old) => old.glyphs != glyphs;
}

// ── 2. ruby ──────────────────────────────────────────────────────────────────

class _RubyDemo extends StatefulWidget {
  const _RubyDemo();

  @override
  State<_RubyDemo> createState() => _RubyDemoState();
}

class _RubyDemoState extends State<_RubyDemo> with SingleTickerProviderStateMixin {
  static const _examples = <List<(String, String)>>[
    [('漢', 'かん'), ('字', 'じ')],
    [('東', 'とう'), ('京', 'きょう')],
    [('振', 'ふ'), ('り', ''), ('仮', 'が'), ('名', 'な')],
  ];

  int _i = 0;
  List<(TextPainter, TextPainter?)> _painters = [];
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3800),
  );

  @override
  void initState() {
    super.initState();
    _prepare();
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });
    _c.forward();
  }

  void _prepare() {
    _disposePainters();
    _painters = [
      for (final (base, ruby) in _examples[_i])
        (_tp(base, BT.sample(52)), ruby.isEmpty ? null : _tp(ruby, BT.sample(17, color: BP.amber))),
    ];
  }

  void _fontsChanged() {
    if (mounted) setState(_prepare);
  }

  void _next() {
    if (!mounted) return;
    setState(() {
      _i = (_i + 1) % _examples.length;
      _prepare();
    });
    _c.forward(from: 0);
  }

  void _disposePainters() {
    for (final (a, b) in _painters) {
      a.dispose();
      b?.dispose();
    }
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    _c.dispose();
    _disposePainters();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Cell(
    label: 'ruby',
    hint: '<ruby> · <rt>',
    onTap: _next,
    child: CustomPaint(size: Size.infinite, painter: _RubyPainter(_painters, _c)),
  );
}

class _RubyPainter extends CustomPainter {
  _RubyPainter(this.painters, this.anim) : super(repaint: anim);

  final List<(TextPainter, TextPainter?)> painters;
  final Animation<double> anim;

  static void _faded(Canvas canvas, TextPainter tp, Offset o, double a) {
    if (a <= 0.01) return;
    if (a >= 0.99) {
      tp.paint(canvas, o);
      return;
    }
    canvas.saveLayer(
      (o & tp.size).inflate(4),
      Paint()..color = Color.fromRGBO(0, 0, 0, a),
    );
    tp.paint(canvas, o);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value;
    double seg(double a, double b) =>
        Curves.easeOutCubic.transform(((t - a) / (b - a)).clamp(0.0, 1.0));
    final out = 1 - seg(0.9, 1.0);
    const fs = 52.0;
    final baseline = size.height / 2 + 34;
    final total = painters.fold(0.0, (a, p) => a + p.$1.width);
    var x = (size.width - total) / 2;

    canvas.drawLine(
      Offset(4, baseline),
      Offset(size.width - 4, baseline),
      Paint()..color = BP.lineFaint,
    );
    for (var k = 0; k < painters.length; k++) {
      final (base, ruby) = painters[k];
      final w = base.width;
      final emTop = baseline - fs * 0.88;
      final em = Rect.fromLTRB(x, emTop, x + w, baseline + fs * 0.12);
      final a0 = seg(0.02 + k * 0.05, 0.2 + k * 0.05) * out;
      canvas.drawPath(
        dashPath(_rectPath(em), dash: 4, gap: 3),
        Paint()
          ..color = BP.lineDim.withValues(alpha: a0)
          ..style = PaintingStyle.stroke,
      );
      _faded(
        canvas,
        base,
        Offset(x, baseline - base.computeDistanceToActualBaseline(TextBaseline.alphabetic)),
        a0,
      );
      if (ruby != null) {
        final rt = seg(0.22 + k * 0.1, 0.5 + k * 0.1);
        final a = rt * out;
        final rb = emTop - 11 - (1 - rt) * 18;
        _faded(
          canvas,
          ruby,
          Offset(
            x + (w - ruby.width) / 2,
            rb - ruby.computeDistanceToActualBaseline(TextBaseline.alphabetic),
          ),
          a,
        );
        // Bracket: which base the annotation belongs to.
        final bp = Paint()
          ..color = BP.amber.withValues(alpha: 0.7 * a)
          ..strokeWidth = 1;
        final by = emTop - 5;
        canvas.drawLine(Offset(x + 5, by), Offset(x + w - 5, by), bp);
        canvas.drawLine(Offset(x + 5, by), Offset(x + 5, by + 4), bp);
        canvas.drawLine(Offset(x + w - 5, by), Offset(x + w - 5, by + 4), bp);
      }
      x += w;
    }
  }

  @override
  bool shouldRepaint(_RubyPainter old) => old.painters != painters;
}

// ── 3. hyphens ───────────────────────────────────────────────────────────────

class _Piece {
  const _Piece(this.tp, this.x, this.line, {this.hyphen = false});

  final TextPainter tp;
  final double x;
  final int line;
  final bool hyphen;
}

class _HyphenDemo extends StatefulWidget {
  const _HyphenDemo();

  @override
  State<_HyphenDemo> createState() => _HyphenDemoState();
}

class _HyphenDemoState extends State<_HyphenDemo> with SingleTickerProviderStateMixin {
  static const _words = [
    ['Hy', 'phen', 'ation'],
    ['keeps'],
    ['ex', 'traor', 'di', 'nar', 'i', 'ly'],
    ['nar', 'row'],
    ['col', 'umns'],
    ['read', 'able.'],
  ];
  static const _minW = 92.0;
  static const _inset = 6.0;

  late final TextStyle _style = BT.sample(18);
  late final List<List<TextPainter>> _pieces = [
    for (final w in _words) [for (final s in w) _tp(s, _style)],
  ];
  late final TextPainter _hyphen = _tp('-', BT.sample(18, color: BP.amber, weight: 700));
  late final double _space = _spaceOf(_style);

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _phase = 0.1;
  double _omega = 0.1;
  bool _dragging = false;
  bool _hyph = true;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration e) {
    final dt = (e - _last).inMicroseconds / 1e6;
    _last = e;
    if (_dragging) return;
    _phase = (_phase + dt / 7) % 1.0;
    setState(() => _omega = 0.5 - 0.5 * math.cos(2 * math.pi * _phase));
  }

  @override
  void dispose() {
    _ticker.dispose();
    for (final w in _pieces) {
      for (final p in w) {
        p.dispose();
      }
    }
    _hyphen.dispose();
    super.dispose();
  }

  /// Greedy line filling; when a word doesn't fit, take the longest
  /// syllable prefix that still fits with a hyphen.
  List<_Piece> _layout(double w) {
    final out = <_Piece>[];
    var line = 0;
    var x = 0.0;
    for (final ps in _pieces) {
      final widths = [for (final p in ps) p.width];
      double sum(int a, int b) {
        var s = 0.0;
        for (var k = a; k < b; k++) {
          s += widths[k];
        }
        return s;
      }

      var start = 0;
      while (start < ps.length) {
        final sp = x > 0 ? _space : 0.0;
        final rest = sum(start, ps.length);
        if (x + sp + rest <= w) {
          var px = x + sp;
          for (var k = start; k < ps.length; k++) {
            out.add(_Piece(ps[k], px, line));
            px += widths[k];
          }
          x = px;
          break;
        }
        var cut = -1;
        if (_hyph) {
          for (var k = ps.length - 1; k > start; k--) {
            if (x + sp + sum(start, k) + _hyphen.width <= w) {
              cut = k;
              break;
            }
          }
        }
        if (cut > 0) {
          var px = x + sp;
          for (var k = start; k < cut; k++) {
            out.add(_Piece(ps[k], px, line));
            px += widths[k];
          }
          out.add(_Piece(_hyphen, px, line, hyphen: true));
          line++;
          x = 0;
          start = cut;
          continue;
        }
        if (x > 0) {
          line++;
          x = 0;
          continue;
        }
        // Empty line and still nothing fits: it overflows.
        var px = 0.0;
        for (var k = start; k < ps.length; k++) {
          out.add(_Piece(ps[k], px, line));
          px += widths[k];
        }
        x = px;
        break;
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) => _Cell(
    label: 'hyphens',
    hint: _hyph ? 'hyphens: auto' : 'hyphens: none',
    onTap: () => setState(() => _hyph = !_hyph),
    child: LayoutBuilder(
      builder: (context, box) {
        final maxW = box.maxWidth - 2 * _inset;
        final w = _minW + (maxW - _minW) * _omega;
        return MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            onHorizontalDragStart: (_) => _dragging = true,
            onHorizontalDragUpdate: (d) => setState(() {
              _omega = ((d.localPosition.dx - _inset - _minW) / (maxW - _minW)).clamp(0.0, 1.0);
            }),
            onHorizontalDragEnd: (_) {
              _dragging = false;
              _phase = math.acos(1 - 2 * _omega) / (2 * math.pi);
            },
            child: CustomPaint(
              size: Size.infinite,
              painter: _HyphenPainter(pieces: _layout(w), width: w, inset: _inset),
            ),
          ),
        );
      },
    ),
  );
}

class _HyphenPainter extends CustomPainter {
  _HyphenPainter({required this.pieces, required this.width, required this.inset});

  final List<_Piece> pieces;
  final double width;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    const lh = 23.0;
    const top = 6.0;
    final right = inset + width;
    final edge = Paint()
      ..color = BP.lineDim
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(0, 0), Offset(0, size.height), edge);
    canvas.drawLine(const Offset(0, 0), Offset(right, 0), edge..color = BP.lineFaint);
    canvas.drawLine(Offset(0, size.height), Offset(right, size.height), edge);
    canvas.drawPath(
      dashPath(Path()
        ..moveTo(right, 0)
        ..lineTo(right, size.height), dash: 5, gap: 4),
      Paint()
        ..color = BP.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    // Handle
    final hy = size.height / 2;
    final d = Path()
      ..moveTo(right, hy - 7)
      ..lineTo(right + 7, hy)
      ..lineTo(right, hy + 7)
      ..lineTo(right - 7, hy)
      ..close();
    canvas.drawPath(d, Paint()..color = BP.paper);
    canvas.drawPath(
      d,
      Paint()
        ..color = BP.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    for (final p in pieces) {
      final o = Offset(inset + p.x, top + p.line * lh);
      p.tp.paint(canvas, o);
      final end = inset + p.x + p.tp.width;
      if (end > right + 0.5) {
        final from = math.max(o.dx, right);
        canvas.drawRect(
          Rect.fromLTRB(from, o.dy + 2, end, o.dy + p.tp.height - 2),
          Paint()..color = BP.red.withValues(alpha: 0.22),
        );
        canvas.drawLine(
          Offset(from, o.dy + p.tp.height - 1),
          Offset(end, o.dy + p.tp.height - 1),
          Paint()
            ..color = BP.red
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_HyphenPainter old) => true;
}

// ── 4. balance ───────────────────────────────────────────────────────────────

class _BalanceDemo extends StatefulWidget {
  const _BalanceDemo();

  @override
  State<_BalanceDemo> createState() => _BalanceDemoState();
}

class _BalanceDemoState extends State<_BalanceDemo> with SingleTickerProviderStateMixin {
  static const _headline = 'Balanced headlines never leave one word alone';
  static const _lh = 31.0;

  late final TextStyle _style = BT.display(23, weight: 600);
  late final List<TextPainter> _tps = [for (final w in _headline.split(' ')) _tp(w, _style)];
  late final double _space = _spaceOf(_style);
  late final AnimationController _m = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );
  Timer? _timer;
  bool _balanced = false;

  Size _area = Size.zero;
  double _wrapW = 0;
  List<List<int>> _g = const [];
  List<List<int>> _b = const [];

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 3000), (_) => _toggle());
  }

  void _toggle() {
    if (!mounted) return;
    setState(() => _balanced = !_balanced);
    _balanced ? _m.forward() : _m.reverse();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _m.dispose();
    for (final t in _tps) {
      t.dispose();
    }
    super.dispose();
  }

  double _lineW(List<int> l) =>
      l.fold(0.0, (a, i) => a + _tps[i].width) + _space * (l.length - 1);

  List<List<int>> _greedy(double w) {
    final lines = <List<int>>[];
    var cur = <int>[];
    var x = 0.0;
    for (var i = 0; i < _tps.length; i++) {
      final ww = _tps[i].width;
      final add = cur.isEmpty ? ww : _space + ww;
      if (cur.isNotEmpty && x + add > w) {
        lines.add(cur);
        cur = [i];
        x = ww;
      } else {
        cur.add(i);
        x += add;
      }
    }
    if (cur.isNotEmpty) lines.add(cur);
    return lines;
  }

  /// Picks the box width where greedy strands the loneliest last line, then
  /// balances like Blink: the narrowest width that keeps the same line count.
  void _solve(Size area) {
    if (area == _area) return;
    _area = area;
    var bestW = area.width;
    var best = 2.0;
    for (var w = area.width * 0.62; w <= area.width; w += 1) {
      final g = _greedy(w);
      if (g.length < 2 || g.length > 4) continue;
      final score = _lineW(g.last) / w;
      if (score < best - 1e-6) {
        best = score;
        bestW = w;
      }
    }
    _wrapW = bestW;
    _g = _greedy(bestW);
    var lo = _tps.map((t) => t.width).reduce(math.max);
    var hi = bestW;
    for (var k = 0; k < 30; k++) {
      final mid = (lo + hi) / 2;
      if (_greedy(mid).length <= _g.length) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    _b = _greedy(hi);
  }

  (List<Offset>, List<(double, double)>) _place(List<List<int>> lines, Size area) {
    final pos = List<Offset>.filled(_tps.length, Offset.zero);
    final ext = <(double, double)>[];
    final top = (area.height - lines.length * _lh) / 2;
    for (var li = 0; li < lines.length; li++) {
      final lw = _lineW(lines[li]);
      var x = (area.width - lw) / 2;
      ext.add((x, x + lw));
      for (final i in lines[li]) {
        pos[i] = Offset(x, top + li * _lh);
        x += _tps[i].width + _space;
      }
    }
    return (pos, ext);
  }

  @override
  Widget build(BuildContext context) => _Cell(
    label: 'balance',
    hint: _balanced ? 'text-wrap: balance' : 'text-wrap: wrap',
    onTap: () {
      _startTimer();
      _toggle();
    },
    child: LayoutBuilder(
      builder: (context, box) {
        final area = Size(box.maxWidth, box.maxHeight);
        _solve(area);
        final (gp, ge) = _place(_g, area);
        final (bp, be) = _place(_b, area);
        return CustomPaint(
          size: Size.infinite,
          painter: _BalancePainter(
            tps: _tps,
            greedy: gp,
            balanced: bp,
            greedyExt: ge,
            balancedExt: be,
            wrapW: _wrapW,
            top: (area.height - _g.length * _lh) / 2,
            lh: _lh,
            m: _m,
          ),
        );
      },
    ),
  );
}

class _BalancePainter extends CustomPainter {
  _BalancePainter({
    required this.tps,
    required this.greedy,
    required this.balanced,
    required this.greedyExt,
    required this.balancedExt,
    required this.wrapW,
    required this.top,
    required this.lh,
    required this.m,
  }) : super(repaint: m);

  final List<TextPainter> tps;
  final List<Offset> greedy;
  final List<Offset> balanced;
  final List<(double, double)> greedyExt;
  final List<(double, double)> balancedExt;
  final double wrapW;
  final double top;
  final double lh;
  final Animation<double> m;

  @override
  void paint(Canvas canvas, Size size) {
    final t = m.value;
    final e = Curves.easeInOutCubic.transform(t);
    final l = (size.width - wrapW) / 2;
    final r = (size.width + wrapW) / 2;
    final y0 = top - 12;
    final y1 = top + greedyExt.length * lh + 8;
    final dim = Paint()
      ..color = BP.lineDim
      ..style = PaintingStyle.stroke;
    for (final x in [l, r]) {
      canvas.drawPath(dashPath(Path()
        ..moveTo(x, y0)
        ..lineTo(x, y1), dash: 4, gap: 4), dim);
    }
    // Balanced block edges.
    if (e > 0.01) {
      var bl = double.infinity;
      var br = -double.infinity;
      for (final (a, b) in balancedExt) {
        bl = math.min(bl, a);
        br = math.max(br, b);
      }
      final amber = Paint()
        ..color = BP.amber.withValues(alpha: 0.8 * e)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      for (final x in [bl, br]) {
        canvas.drawPath(dashPath(Path()
          ..moveTo(x, y0 + 4)
          ..lineTo(x, y1 - 4), dash: 3, gap: 3), amber);
      }
    }
    // Line length brackets.
    final bracket = Paint()
      ..color = BP.amber.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var li = 0; li < greedyExt.length && li < balancedExt.length; li++) {
      final a = greedyExt[li].$1 + (balancedExt[li].$1 - greedyExt[li].$1) * e;
      final b = greedyExt[li].$2 + (balancedExt[li].$2 - greedyExt[li].$2) * e;
      final y = top + li * lh + lh - 2;
      canvas.drawLine(Offset(a, y), Offset(b, y), bracket);
      canvas.drawLine(Offset(a, y - 3), Offset(a, y), bracket);
      canvas.drawLine(Offset(b, y - 3), Offset(b, y), bracket);
    }
    // Words fly between the two layouts.
    final n = tps.length;
    const spread = 0.5;
    for (var i = 0; i < n; i++) {
      final lt = (t * (1 + spread) - spread * i / (n - 1)).clamp(0.0, 1.0);
      final we = Curves.easeInOutCubic.transform(lt);
      tps[i].paint(canvas, Offset.lerp(greedy[i], balanced[i], we)!);
    }
  }

  @override
  bool shouldRepaint(_BalancePainter old) =>
      old.greedy != greedy || old.balanced != balanced || old.wrapW != wrapW;
}

// ── 5. find ──────────────────────────────────────────────────────────────────

class _FindDemo extends StatefulWidget {
  const _FindDemo();

  @override
  State<_FindDemo> createState() => _FindDemoState();
}

class _FindDemoState extends State<_FindDemo> with SingleTickerProviderStateMixin {
  static const _text =
      'Real text lives in the DOM, so the browser can find text, select text, '
      'translate text and read text aloud.';

  final _q = TextEditingController(text: 'text');
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: 1,
  );
  Timer? _timer;
  TextProbe? _probe;
  double _probeW = -1;
  List<List<Rect>> _matches = [];
  int _cur = 0;
  int _prev = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1300), (_) {
      if (!mounted || _matches.length < 2) return;
      setState(() {
        _prev = _cur;
        _cur = (_cur + 1) % _matches.length;
      });
      _sweep.forward(from: 0);
    });
  }

  void _find() {
    _matches = [];
    _cur = 0;
    _prev = 0;
    final p = _probe;
    final q = _q.text.toLowerCase();
    if (p == null || q.isEmpty) return;
    final t = _text.toLowerCase();
    var i = t.indexOf(q);
    while (i >= 0) {
      final rs = [for (final b in p.boxes(i, i + q.length)) b.toRect()];
      if (rs.isNotEmpty) _matches.add(rs);
      i = t.indexOf(q, i + q.length);
    }
  }

  void _ensureProbe(double w) {
    if (w == _probeW) return;
    _probeW = w;
    _probe?.dispose();
    _probe = TextProbe(
      TextSpan(text: _text, style: BT.sample(16.5, color: BP.ink, height: 1.5)),
      maxWidth: w,
    );
    _find();
    // Created during layout: refresh the match counter next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sweep.dispose();
    _q.dispose();
    _probe?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final none = _matches.isEmpty;
    return _Cell(
      label: 'find',
      hint: 'Ctrl+F',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                const Icon(Icons.search, size: 17, color: BP.inkDim),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _q,
                    onChanged: (_) => setState(_find),
                    style: BT.mono(15, color: BP.ink),
                    cursorColor: BP.amber,
                    onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 6),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: BP.lineDim)),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: BP.amber, width: 2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  none ? '0/0' : '${_cur + 1}/${_matches.length}',
                  style: BT.mono(14, color: none ? BP.red : BP.amber),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                _ensureProbe(box.maxWidth - 14);
                return CustomPaint(
                  size: Size.infinite,
                  painter: _FindPainter(
                    probe: _probe!,
                    matches: _matches,
                    cur: _cur,
                    prev: _prev,
                    sweep: _sweep,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FindPainter extends CustomPainter {
  _FindPainter({
    required this.probe,
    required this.matches,
    required this.cur,
    required this.prev,
    required this.sweep,
  }) : super(repaint: sweep);

  final TextProbe probe;
  final List<List<Rect>> matches;
  final int cur;
  final int prev;
  final Animation<double> sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final all = Paint()..color = BP.amber.withValues(alpha: 0.22);
    for (final m in matches) {
      for (final r in m) {
        canvas.drawRect(r.inflate(1), all);
      }
    }
    if (matches.isNotEmpty) {
      final from = matches[prev.clamp(0, matches.length - 1)].first;
      final to = matches[cur.clamp(0, matches.length - 1)].first;
      final r = Rect.lerp(from, to, Curves.easeInOutCubic.transform(sweep.value))!.inflate(2);
      canvas.drawRect(r, Paint()..color = BP.amber.withValues(alpha: 0.45));
      canvas.drawRect(
        r,
        Paint()
          ..color = BP.amber
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    probe.paint(canvas, Offset.zero);

    // Scrollbar with match ticks, like the browser's.
    final x = size.width - 4;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = BP.lineFaint
        ..strokeWidth = 3,
    );
    final h = math.max(probe.size.height, 1.0);
    for (var i = 0; i < matches.length; i++) {
      final y = matches[i].first.center.dy / h * size.height;
      canvas.drawLine(
        Offset(x - 5, y),
        Offset(x + 4, y),
        Paint()
          ..color = i == cur ? BP.amber : BP.amber.withValues(alpha: 0.5)
          ..strokeWidth = i == cur ? 3 : 2,
      );
    }
  }

  @override
  bool shouldRepaint(_FindPainter old) =>
      old.matches != matches || old.cur != cur || old.prev != prev || old.probe != probe;
}

// ── 6. translate ─────────────────────────────────────────────────────────────

class _TranslateDemo extends StatefulWidget {
  const _TranslateDemo();

  @override
  State<_TranslateDemo> createState() => _TranslateDemoState();
}

class _TranslateDemoState extends State<_TranslateDemo> with SingleTickerProviderStateMixin {
  static const _langs = [
    ('en', 'Real text, real words', false),
    ('fr', 'Du vrai texte, de vrais mots', false),
    ('ar', 'نص حقيقي، كلمات حقيقية', true),
  ];

  int _i = 0;
  int _prev = 2;
  bool _moved = false;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
    value: 1,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(milliseconds: 2800),
      (_) => _go((_i + 1) % _langs.length),
    );
  }

  void _go(int i) {
    if (!mounted || i == _i) return;
    setState(() {
      _prev = _i;
      _i = i;
      _moved = true;
    });
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  Widget _text(int k) {
    final (_, s, rtl) = _langs[k];
    return SizedBox.expand(
      child: Text(
        s,
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        style: BT.sample(27, weight: 500, height: 1.35),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rtl = _langs[_i].$3;
    return _Cell(
      label: 'translate',
      hint: _moved ? '${_langs[_prev].$1} → ${_langs[_i].$1}' : _langs[_i].$1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var k = 0; k < _langs.length; k++) ...[
                BpButton(
                  label: _langs[k].$1.toUpperCase(),
                  size: 12,
                  selected: k == _i,
                  onTap: () {
                    _startTimer();
                    _go(k);
                  },
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => LayoutBuilder(
                builder: (context, box) {
                  final e = Curves.easeInOutCubic.transform(_c.value);
                  final x = rtl ? (1 - e) * box.maxWidth : e * box.maxWidth;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRect(clipper: _SideClip(x, keepLeft: rtl), child: _text(_prev)),
                      ClipRect(clipper: _SideClip(x, keepLeft: !rtl), child: _text(_i)),
                      if (_c.value < 1)
                        Positioned(
                          left: x - 1,
                          top: -4,
                          bottom: 0,
                          width: 2,
                          child: ColoredBox(
                            color: BP.amber.withValues(alpha: math.sin(e * math.pi)),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          SizedBox(
            height: 20,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: CustomPaint(
                key: ValueKey(rtl),
                size: Size.infinite,
                painter: _DirPainter(rtl),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideClip extends CustomClipper<Rect> {
  const _SideClip(this.x, {required this.keepLeft});

  final double x;
  final bool keepLeft;

  @override
  Rect getClip(Size size) => keepLeft
      ? Rect.fromLTRB(-40, -40, x, size.height + 40)
      : Rect.fromLTRB(x, -40, size.width + 40, size.height + 40);

  @override
  bool shouldReclip(_SideClip old) => old.x != x || old.keepLeft != keepLeft;
}

class _DirPainter extends CustomPainter {
  _DirPainter(this.rtl);

  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final a = Offset(rtl ? size.width : 0, y);
    final b = Offset(rtl ? 0 : size.width, y);
    final p = Paint()
      ..color = BP.amber.withValues(alpha: 0.8)
      ..strokeWidth = 1.2;
    canvas.drawPath(dashPath(Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy), dash: 5, gap: 4), p..style = PaintingStyle.stroke);
    drawArrowHead(canvas, b, a, p, 8);
  }

  @override
  bool shouldRepaint(_DirPainter old) => old.rtl != rtl;
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
