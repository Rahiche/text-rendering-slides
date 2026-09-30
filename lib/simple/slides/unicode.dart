import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data
// ─────────────────────────────────────────────────────────────────────────────

class _Release {
  const _Release(this.year, this.count, this.name, this.tag, this.countLabel, [this.note]);

  final double year;
  final double count;
  final String name;

  /// Label next to the marker.
  final String tag;
  final String countLabel;
  final String? note;
}

const _releases = [
  _Release(1963, 128, 'ASCII', 'ASCII', '128'),
  _Release(1991, 7000, 'Unicode 1.0', '1.0', '~7,000'),
  _Release(1999, 49194, 'Unicode 3.0', '3.0', '49,194'),
  _Release(2010, 109449, 'Unicode 6.0', '6.0', '109,449', 'emoji arrive'),
  _Release(2026, 172808, 'Unicode 18.0', '18.0', '172,808', '170+ scripts'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Timeline: a short hold on ASCII, then one eased segment per release.
// The run takes [_run] and starts [_delay] after the slide arrives, so
// 172,808 has landed ~3.4 s in (the exported still shows the punchline).
// ─────────────────────────────────────────────────────────────────────────────

const _delay = Duration(milliseconds: 300);
const _run = Duration(milliseconds: 3200);
const _hold = 0.35;
const _weights = [1.0, 0.85, 0.85, 1.1];

/// Time after the last segment for 18.0 to land and settle.
const _tail = 0.45;
final double _total = _hold + _weights.reduce((a, b) => a + b) + _tail;

typedef _Head = ({double year, double count, int reached});

_Head _headAt(double t) {
  var u = t * _total - _hold;
  if (u <= 0) {
    return (year: _releases.first.year, count: _releases.first.count, reached: 0);
  }
  for (var i = 0; i < _weights.length; i++) {
    if (u < _weights[i]) {
      final e = Curves.easeInOutCubic.transform(u / _weights[i]);
      final a = _releases[i];
      final b = _releases[i + 1];
      return (
        year: ui.lerpDouble(a.year, b.year, e)!,
        count: ui.lerpDouble(a.count, b.count, e)!,
        reached: i,
      );
    }
    u -= _weights[i];
  }
  final last = _releases.last;
  return (year: last.year, count: last.count, reached: _releases.length - 1);
}

/// 0..1 "pop" of release [k] since the head arrived there.
double _popOf(double t, int k) {
  var at = k == 0 ? 0.08 : _hold;
  for (var i = 0; i < k; i++) {
    at += _weights[i];
  }
  return ((t * _total - at) / 0.28).clamp(0.0, 1.0);
}

// ─────────────────────────────────────────────────────────────────────────────
// Chart geometry: the chart fills the content area; the count sits in the
// empty upper-left corner above the flat ASCII years.
// ─────────────────────────────────────────────────────────────────────────────

const _chartSize = Size(1472, 628);
const _plot = Rect.fromLTRB(36, 40, 1410, 560);
const _yearMin = 1960.0;
const _yearMax = 2030.0;
const _countMax = 180000.0;

Offset _pt(double year, double count) => Offset(
  _plot.left + (year - _yearMin) / (_yearMax - _yearMin) * _plot.width,
  _plot.bottom - count / _countMax * _plot.height,
);

Offset _ptOf(int k) => _pt(_releases[k].year, _releases[k].count);

// ─────────────────────────────────────────────────────────────────────────────
// Slide
// ─────────────────────────────────────────────────────────────────────────────

/// 128 → 172,808: the chart draws itself while the count ticks up in sync and
/// a rain of glyphs from more and more scripts thickens behind it.
/// Hover a marker for its release; click the chart to replay.
class UnicodeSlide extends StatefulWidget {
  const UnicodeSlide({super.key});

  @override
  State<UnicodeSlide> createState() => _UnicodeSlideState();
}

class _UnicodeSlideState extends State<UnicodeSlide> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: _run);
  Timer? _start;
  int? _hover;
  List<_Drop> _drops = const [];

  @override
  void initState() {
    super.initState();
    _drops = _makeDrops();
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
    _start = Timer(_delay, () {
      if (mounted) _c.forward();
    });
  }

  void _fontsChanged() {
    if (!mounted) return;
    setState(() {
      for (final d in _drops) {
        d.painter.dispose();
      }
      _drops = _makeDrops();
    });
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    _start?.cancel();
    _c.dispose();
    for (final d in _drops) {
      d.painter.dispose();
    }
    super.dispose();
  }

  void _replay() {
    _start?.cancel();
    _c.forward(from: 0);
  }

  void _onHover(Offset p) {
    final head = _headAt(_c.value);
    int? best;
    var bestD = 64.0;
    for (var k = 0; k <= head.reached; k++) {
      final d = (_ptOf(k) - p).distance;
      if (d < bestD) {
        bestD = d;
        best = k;
      }
    }
    if (best != _hover) setState(() => _hover = best);
  }

  @override
  Widget build(BuildContext context) {
    return SlideFrame(
      title: '128 → 172,808',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Glyph rain, thickening with the count.
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: ElapsedBuilder(
                  builder: (context, elapsed) => CustomPaint(
                    painter: _RainPainter(
                      drops: _drops,
                      seconds: elapsed.inMicroseconds / 1e6,
                      count: _headAt(_c.value).count,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // The count, in the chart's empty upper-left corner.
          Positioned(
            left: _plot.left + 56,
            top: 0,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => _Readout(t: _c.value),
              ),
            ),
          ),

          // Chart
          Positioned.fill(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onHover: (e) => _onHover(e.localPosition),
              onExit: (_) => setState(() => _hover = null),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _replay,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => CustomPaint(
                    size: _chartSize,
                    painter: _ChartPainter(t: _c.value, hover: _hover),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final head = _headAt(t);
    final done = _popOf(t, _releases.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AnimatedCount.format(head.count),
          style: BT.display(
            176,
            weight: 600,
            height: 1.0,
            letterSpacing: -6,
            color: Color.lerp(BP.ink, BP.amber, done)!,
          ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('characters', style: BT.display(32, color: BP.inkDim)),
            Opacity(
              opacity: done,
              child: Text('  ·  170+ scripts', style: BT.display(32, color: BP.amber)),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chart painter
// ─────────────────────────────────────────────────────────────────────────────

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.t, required this.hover});

  final double t;
  final int? hover;

  @override
  void paint(Canvas canvas, Size size) {
    final head = _headAt(t);
    _axes(canvas);

    // Data line + hatched area up to the head.
    final pts = [for (var k = 0; k <= head.reached; k++) _ptOf(k)];
    final h = _pt(head.year, head.count);
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    line.lineTo(h.dx, h.dy);
    final area = Path.from(line)
      ..lineTo(h.dx, _plot.bottom)
      ..lineTo(pts.first.dx, _plot.bottom)
      ..close();
    canvas.drawPath(area, Paint()..color = BP.line.withValues(alpha: 0.06));
    canvas.save();
    canvas.clipPath(area);
    final hatch = Paint()
      ..color = BP.line.withValues(alpha: 0.16)
      ..strokeWidth = 1;
    for (var x = _plot.left - _plot.height; x < _plot.right; x += 12) {
      canvas.drawLine(Offset(x, _plot.bottom), Offset(x + _plot.height, _plot.top), hatch);
    }
    canvas.restore();
    canvas.drawPath(
      line,
      Paint()
        ..color = BP.line
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // Release markers and tags.
    final last = _releases.length - 1;
    for (var k = 0; k < _releases.length; k++) {
      final p = _popOf(t, k);
      if (p <= 0) continue;
      final o = _ptOf(k);
      final s = Curves.easeOutBack.transform(p);
      final hot = hover == k || k == last;
      final r = (k == last ? 10.0 : 8.0) * s;
      canvas.drawCircle(o, r, Paint()..color = hot ? BP.amber : BP.paper);
      canvas.drawCircle(
        o,
        r,
        Paint()
          ..color = hot ? BP.amber : BP.line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      final rel = _releases[k];
      final style = BT.mono(
        k == last ? 30 : 24,
        color: (k == last ? BP.amber : BP.ink).withValues(alpha: p),
        weight: k == last ? 600 : 500,
      );
      if (k == 0) {
        _text(canvas, rel.tag, style, o + const Offset(-6, -16), ay: 1);
      } else {
        _text(canvas, rel.tag, style, o + const Offset(-18, -12), ax: 1, ay: 1);
      }
      if (rel.note == 'emoji arrive') _emojiNote(canvas, o, p);
    }

    // Head: glowing pen + crosshair while drawing.
    if (t > 0 && t < 1) {
      final dash = Paint()
        ..color = BP.amber.withValues(alpha: 0.55)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      canvas.drawPath(
        dashPath(Path()
          ..moveTo(h.dx, h.dy)
          ..lineTo(h.dx, _plot.bottom), dash: 5, gap: 5),
        dash,
      );
      _axisTag(canvas, '${head.year.round()}', Offset(h.dx, _plot.bottom));
      canvas.drawCircle(
        h,
        20,
        Paint()
          ..color = BP.amber.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawCircle(h, 7, Paint()..color = BP.amber);
    }

    if (hover != null) _tooltip(canvas, hover!);
  }

  void _axes(Canvas canvas) {
    final axis = Paint()
      ..color = BP.lineDim
      ..strokeWidth = 1.5;
    canvas.drawLine(_plot.bottomLeft, _plot.bottomRight + const Offset(24, 0), axis);
    canvas.drawLine(_plot.bottomLeft, _plot.topLeft - const Offset(0, 24), axis);
    drawArrowHead(canvas, _plot.bottomRight + const Offset(24, 0), _plot.bottomRight, axis, 9);
    drawArrowHead(canvas, _plot.topLeft - const Offset(0, 24), _plot.topLeft, axis, 9);

    for (var y = 1960; y <= 2030; y += 5) {
      final x = _pt(y.toDouble(), 0).dx;
      final major = y % 10 == 0;
      canvas.drawLine(Offset(x, _plot.bottom), Offset(x, _plot.bottom + (major ? 12 : 6)), axis);
      if (major && y > 1960 && y < 2030) {
        _text(canvas, '$y', BT.mono(20, color: BP.inkDim), Offset(x, _plot.bottom + 18), ax: 0.5);
      }
    }
  }

  void _emojiNote(Canvas canvas, Offset o, double p) {
    final at = o + const Offset(22, 14);
    final tp = TextPainter(
      text: TextSpan(text: '😀', style: BT.sample(48)),
      textDirection: TextDirection.ltr,
    )..layout();
    final r = at & tp.size;
    canvas.saveLayer(r.inflate(4), Paint()..color = Color.fromRGBO(0, 0, 0, p));
    tp.paint(canvas, at);
    canvas.restore();
    tp.dispose();
  }

  void _axisTag(Canvas canvas, String s, Offset at) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: BT.mono(20, color: BP.paper, weight: 600)),
      textDirection: TextDirection.ltr,
    )..layout();
    final r = Rect.fromCenter(
      center: at + Offset(0, tp.height / 2 + 16),
      width: tp.width + 16,
      height: tp.height + 6,
    );
    canvas.drawRect(r, Paint()..color = BP.amber);
    tp.paint(canvas, r.topLeft + const Offset(8, 3));
    tp.dispose();
  }

  void _tooltip(Canvas canvas, int k) {
    final r = _releases[k];
    final o = _ptOf(k);
    final dash = Paint()
      ..color = BP.amber.withValues(alpha: 0.7)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(dashPath(Path()
      ..moveTo(o.dx, o.dy)
      ..lineTo(o.dx, _plot.bottom), dash: 5, gap: 4), dash);
    canvas.drawCircle(
      o,
      16,
      Paint()
        ..color = BP.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final title = TextPainter(
      text: TextSpan(text: r.name, style: BT.display(28, color: BP.ink)),
      textDirection: TextDirection.ltr,
    )..layout();
    final sub = TextPainter(
      text: TextSpan(text: '${r.year.round()} · ${r.countLabel}', style: BT.mono(22, color: BP.amber)),
      textDirection: TextDirection.ltr,
    )..layout();
    final note = r.note == null
        ? null
        : (TextPainter(
            text: TextSpan(text: r.note, style: BT.mono(20, color: BP.inkDim)),
            textDirection: TextDirection.ltr,
          )..layout());
    const pad = 18.0;
    final w = [title.width, sub.width, note?.width ?? 0].reduce(math.max) + pad * 2;
    final h = title.height + sub.height + (note == null ? 0 : note.height + 6) + pad * 2 + 6;
    var left = o.dx - w - 28;
    if (left < _plot.left + 8) left = o.dx + 28;
    final top = (o.dy - h / 2).clamp(0.0, _plot.bottom - h - 24);
    final box = Rect.fromLTWH(left, top, w, h);
    canvas.drawRect(box, Paint()..color = BP.panel);
    canvas.drawRect(
      box,
      Paint()
        ..color = BP.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    var y = top + pad;
    title.paint(canvas, Offset(left + pad, y));
    y += title.height + 6;
    sub.paint(canvas, Offset(left + pad, y));
    y += sub.height + 6;
    note?.paint(canvas, Offset(left + pad, y));
    title.dispose();
    sub.dispose();
    note?.dispose();
  }

  static void _text(
    Canvas canvas,
    String s,
    TextStyle style,
    Offset at, {
    double ax = 0,
    double ay = 0,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width * ax, tp.height * ay));
    tp.dispose();
  }

  @override
  bool shouldRepaint(_ChartPainter old) => old.t != t || old.hover != hover;
}

// ─────────────────────────────────────────────────────────────────────────────
// Glyph rain
// ─────────────────────────────────────────────────────────────────────────────

const _asciiPool = ['A', 'a', 'g', 'R', '&', '@', '#', '7', '{', '?', 'Q', 'z', '%', 'k'];
const _v1Pool = [
  'Ω', 'λ', 'ψ', 'Ж', 'я', 'Щ', 'ع', 'ب', 'ش', 'ك', 'א', 'ש', 'ל', 'क', 'ह', 'ॐ', //
  'অ', 'ক', 'ก', 'ข', 'ษ', 'ა', 'ქ', 'Ա', 'Ֆ', '字', '文', '永', 'あ', 'カ', 'の', //
  '한', '글', 'த', 'ਗ', 'ગ', 'ລ', 'అ', 'ಕ', 'മ',
];
const _v3Pool = [
  'ሀ', 'ጀ', 'ቐ', 'Ꭰ', 'Ꮳ', 'Ꮿ', 'ᐃ', 'ᓄ', 'ᕙ', 'ཀ', 'ཨ', 'ས', 'ස', 'ක', 'ក', 'ខ', 'က', 'ဪ', //
  '龍', '鬱', '書',
];
const _emojiPool = ['😀', '🌍', '🎉', '🔥', '👋', '🚀', '🍕', '🌈', '🐙', '🎸'];

class _Drop {
  _Drop({
    required this.painter,
    required this.x,
    required this.phase,
    required this.speed,
    required this.sway,
    required this.threshold,
    required this.emoji,
  });

  final TextPainter painter;
  final double x;
  final double phase;
  final double speed;
  final double sway;

  /// Appears once the character count passes this.
  final double threshold;
  final bool emoji;
}

List<_Drop> _makeDrops() {
  final rnd = math.Random(11);
  const n = 150;
  const always = 10;
  final out = <_Drop>[];
  for (var k = 0; k < n; k++) {
    final th = k < always ? 0.0 : 128 + (k - always) / (n - always) * (172808 - 128);
    final List<String> pool;
    if (th < 7000) {
      pool = _asciiPool;
    } else if (th < 49194) {
      pool = _v1Pool;
    } else if (th < 109449) {
      pool = rnd.nextDouble() < 0.6 ? _v1Pool : _v3Pool;
    } else {
      final r = rnd.nextDouble();
      pool = r < 0.35 ? _emojiPool : (r < 0.7 ? _v1Pool : _v3Pool);
    }
    final g = pool[rnd.nextInt(pool.length)];
    final size = 14 + rnd.nextDouble() * 30;
    final alpha = 0.17 - (size - 14) / 30 * 0.08;
    final color = (rnd.nextDouble() < 0.75 ? BP.line : BP.inkDim).withValues(alpha: alpha);
    out.add(
      _Drop(
        painter: TextPainter(
          text: TextSpan(text: g, style: BT.sample(size, color: color)),
          textDirection: TextDirection.ltr,
        )..layout(),
        x: rnd.nextDouble(),
        phase: rnd.nextDouble(),
        speed: 0.018 + size * 0.0006,
        sway: 4 + rnd.nextDouble() * 12,
        threshold: th,
        emoji: identical(pool, _emojiPool),
      ),
    );
  }
  return out;
}

class _RainPainter extends CustomPainter {
  _RainPainter({required this.drops, required this.seconds, required this.count});

  final List<_Drop> drops;
  final double seconds;
  final double count;

  @override
  void paint(Canvas canvas, Size size) {
    final emoji = <(_Drop, Offset, double)>[];
    for (final d in drops) {
      if (count < d.threshold) continue;
      final grow = d.threshold == 0 ? 1.0 : ((count - d.threshold) / 6000).clamp(0.0, 1.0);
      final s = Curves.easeOutBack.transform(grow);
      if (s < 0.03) continue;
      final span = size.height + 120;
      final y = ((d.phase + seconds * d.speed) % 1.0) * span - 60;
      final x = d.x * size.width + math.sin(seconds * 0.35 + d.phase * 9) * d.sway;
      if (d.emoji) {
        emoji.add((d, Offset(x, y), s));
      } else {
        _draw(canvas, d, Offset(x, y), s);
      }
    }
    if (emoji.isEmpty) return;
    // Emoji are color glyphs: tint them into faint blueprint silhouettes.
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..colorFilter = ColorFilter.mode(BP.line.withValues(alpha: 0.12), BlendMode.srcIn),
    );
    for (final (d, o, s) in emoji) {
      _draw(canvas, d, o, s);
    }
    canvas.restore();
  }

  static void _draw(Canvas canvas, _Drop d, Offset at, double s) {
    final p = d.painter;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.scale(s);
    p.paint(canvas, Offset(-p.width / 2, -p.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RainPainter old) =>
      old.seconds != seconds || old.count != count || old.drops != drops;
}
