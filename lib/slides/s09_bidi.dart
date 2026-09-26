import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../deck/scripts.dart';
import '../deck/theme.dart';
import '../deck/widgets.dart';

/// Memory ≠ screen: each character's chip flies from its logical slot to its
/// REAL visual x (from the laid-out paragraph). Digits inside RTL stay LTR.
class BidiSlide extends StatefulWidget {
  const BidiSlide({super.key});

  @override
  State<BidiSlide> createState() => _BidiSlideState();
}

const _presets = ['Hi שלום עולם 2026!', 'Hello مرحبا 123'];

const _rowX = 130.0;
const _rowW = 1472.0 - _rowX;
const _textTop = 150.0;
const _chipH = 62.0;

Color _dirColor(bool rtl) => rtl ? BP.amber : BP.line;

class _BidiSlideState extends State<BidiSlide> with TickerProviderStateMixin {
  late final TextEditingController _ctrl = TextEditingController(text: _presets.first);
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 6400),
  )..repeat();
  late final AnimationController _manual = AnimationController(vsync: this);
  late final AnimationController _march = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  late _BidiLayout _layout = _BidiLayout.of(_ctrl.text);
  int _mode = 0; // 0 auto · 1 memory · 2 screen
  int? _hover;

  void _setText(String s) {
    if (_ctrl.text != s) _ctrl.text = s;
    final old = _layout;
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    setState(() {
      _layout = _BidiLayout.of(s);
      _hover = null;
    });
    if (_mode == 0) {
      _loop.value = 0;
      _loop.repeat();
    } else {
      _manual.value = 0;
      _manual.animateTo(_mode == 2 ? 1 : 0, duration: const Duration(milliseconds: 1400));
    }
  }

  void _setMode(int mode) {
    if (mode == _mode) return;
    if (mode == 0) {
      _loop.value = 0;
      _loop.repeat();
    } else {
      _loop.stop();
      _manual.animateTo(
        mode == 2 ? 1 : 0,
        duration: const Duration(milliseconds: 1400),
      );
    }
    setState(() => _mode = mode);
  }

  void _onHover(Offset p) {
    final h = _layout.hit(p);
    if (h != _hover) setState(() => _hover = h);
  }

  @override
  void dispose() {
    _loop.dispose();
    _manual.dispose();
    _march.dispose();
    _ctrl.dispose();
    _layout.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideFrame(
      title: 'Memory ≠ screen',
      child: Stack(
        children: [
          Positioned.fill(
            child: MouseRegion(
              onHover: (e) => _onHover(e.localPosition),
              onExit: (_) => setState(() => _hover = null),
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _BidiPainter(
                    layout: _layout,
                    loop: _loop,
                    manual: _manual,
                    march: _march,
                    auto: _mode == 0,
                    hover: _hover,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                BpTextField(controller: _ctrl, width: 440, style: BT.sample(28), onChanged: _setText),
                const SizedBox(width: 28),
                for (final p in _presets) ...[
                  _Chip(text: p, selected: p == _ctrl.text, onTap: () => _setText(p)),
                  const SizedBox(width: 10),
                ],
                const Spacer(),
                BpSegmented<int>(
                  values: const [0, 1, 2],
                  selected: _mode,
                  color: BP.amber,
                  onChanged: _setMode,
                  labelOf: (i) => const ['auto', 'memory', 'screen'][i],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.selected, required this.onTap});

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? BP.line.withValues(alpha: 0.16) : Colors.transparent,
          border: Border.all(color: selected ? BP.amber : BP.lineDim, width: selected ? 2 : 1),
        ),
        child: Text(text, style: BT.sample(20, color: selected ? BP.ink : BP.inkDim)),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Layout from the real paragraph
// ─────────────────────────────────────────────────────────────────────────────

class _Arrow {
  const _Arrow(this.x0, this.x1, this.lane, this.rtl);

  final double x0;
  final double x1;
  final int lane;
  final bool rtl;
}

final _digit = RegExp(r'[0-9\u0660-\u0669\u06F0-\u06F9]');

class _BidiLayout {
  _BidiLayout._({
    required this.probe,
    required this.origin,
    required this.vis,
    required this.rtl,
    required this.mem,
    required this.scr,
    required this.charTp,
    required this.idxTp,
    required this.arrows,
  });

  factory _BidiLayout.of(String text) {
    var fs = 84.0;
    var probe = TextProbe(TextSpan(text: text, style: BT.sample(fs)));
    if (probe.size.width > _rowW - 20) {
      fs = math.max(24.0, fs * (_rowW - 20) / probe.size.width);
      probe.dispose();
      probe = TextProbe(TextSpan(text: text, style: BT.sample(fs)));
    }
    final origin = Offset(_rowX + (_rowW - probe.size.width) / 2, _textTop);
    final ranges = probe.graphemes();
    final n = ranges.length;

    final vis = <Rect>[];
    final rtl = <bool>[];
    final chars = <String>[];
    for (final (s, e) in ranges) {
      final boxes = probe.boxes(s, e);
      chars.add(text.substring(s, e));
      if (boxes.isEmpty) {
        vis.add(Rect.fromLTWH(origin.dx, origin.dy, 0, probe.size.height));
        rtl.add(false);
        continue;
      }
      var r = boxes.first.toRect();
      for (final b in boxes.skip(1)) {
        r = r.expandToInclude(b.toRect());
      }
      vis.add(r.shift(origin));
      rtl.add(boxes.first.direction == TextDirection.rtl);
    }

    // Approximate embedding levels, only to stack the run arrows:
    // RTL → 1; digits after a strong RTL char → 2 (they stay LTR); else 0.
    final level = List<int>.filled(n, 0);
    bool? lastStrongRtl;
    for (var i = 0; i < n; i++) {
      final g = chars[i];
      if (rtl[i]) {
        level[i] = 1;
      } else if (_digit.hasMatch(g) && lastStrongRtl == true) {
        level[i] = 2;
      }
      final sc = scriptOfCluster(g);
      if (sc != Script.common && sc != Script.emoji) lastStrongRtl = sc.rtl;
    }
    // Separators between two level-2 digits (2,026) join them.
    for (var i = 1; i < n - 1; i++) {
      if (level[i] == 0 && level[i - 1] == 2 && level[i + 1] == 2) level[i] = 2;
    }

    // Visual runs → arrows.
    final order = List<int>.generate(n, (i) => i)..sort((a, b) => vis[a].left.compareTo(vis[b].left));
    final arrows = <_Arrow>[];
    void spans(bool Function(int lvl) test, int lane, bool dirRtl) {
      int? start;
      for (var k = 0; k <= order.length; k++) {
        final ok = k < order.length && vis[order[k]].width > 0 && test(level[order[k]]);
        if (ok && start == null) start = k;
        if (!ok && start != null) {
          final a = vis[order[start]].left;
          final b = vis[order[k - 1]].right;
          if (b - a > 4) arrows.add(_Arrow(a, b, lane, dirRtl));
          start = null;
        }
      }
    }

    spans((l) => l == 0, 0, false);
    spans((l) => l >= 1, 0, true);
    spans((l) => l >= 2, 1, false);

    // Chip rects.
    const gap = 8.0;
    final cw = n == 0 ? 60.0 : math.min(60.0, (_rowW - (n - 1) * gap) / n);
    final memW = n * cw + math.max(0, n - 1) * gap;
    final memX = _rowX + (_rowW - memW) / 2;
    final scrY = origin.dy + probe.size.height + 18;
    final memY = scrY + _chipH + 150;
    final mem = [for (var i = 0; i < n; i++) Rect.fromLTWH(memX + i * (cw + gap), memY, cw, _chipH)];
    final scr = [for (var i = 0; i < n; i++) Rect.fromLTWH(vis[i].left, scrY, math.max(vis[i].width, 6), _chipH)];

    final charTp = <TextPainter>[];
    final idxTp = <TextPainter>[];
    for (var i = 0; i < n; i++) {
      final g = chars[i] == ' ' ? '␠' : chars[i];
      charTp.add(
        TextPainter(
          text: TextSpan(text: g, style: BT.sample(26, color: chars[i] == ' ' ? BP.inkFaint : BP.ink)),
          textDirection: TextDirection.ltr,
        )..layout(),
      );
      idxTp.add(
        TextPainter(
          text: TextSpan(text: '$i', style: BT.mono(11, color: _dirColor(rtl[i]))),
          textDirection: TextDirection.ltr,
        )..layout(),
      );
    }

    return _BidiLayout._(
      probe: probe,
      origin: origin,
      vis: vis,
      rtl: rtl,
      mem: mem,
      scr: scr,
      charTp: charTp,
      idxTp: idxTp,
      arrows: arrows,
    );
  }

  final TextProbe probe;
  final Offset origin;
  final List<Rect> vis;
  final List<bool> rtl;
  final List<Rect> mem;
  final List<Rect> scr;
  final List<TextPainter> charTp;
  final List<TextPainter> idxTp;
  final List<_Arrow> arrows;

  int get length => vis.length;

  int? hit(Offset p) {
    for (var i = 0; i < length; i++) {
      if (mem[i].contains(p) || scr[i].contains(p) || (vis[i].width > 0 && vis[i].contains(p))) return i;
    }
    return null;
  }

  void dispose() {
    probe.dispose();
    for (final t in [...charTp, ...idxTp]) {
      t.dispose();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────────────────

double _ease(double t) => Curves.easeInOutCubic.transform(t.clamp(0.0, 1.0));
double _win(double v, double a, double b) => _ease((v - a) / (b - a));

class _BidiPainter extends CustomPainter {
  _BidiPainter({
    required this.layout,
    required this.loop,
    required this.manual,
    required this.march,
    required this.auto,
    required this.hover,
  }) : super(repaint: Listenable.merge([loop, manual, march]));

  final _BidiLayout layout;
  final Animation<double> loop;
  final Animation<double> manual;
  final Animation<double> march;
  final bool auto;
  final int? hover;

  /// 0 = in memory, 1 = on screen, for chip [i].
  double _progress(int i, int n) {
    if (auto) {
      final t = loop.value;
      final st = 0.3 / math.max(1, n);
      if (t < 0.84) return _win(t, 0.08 + i * st, 0.08 + i * st + 0.16);
      return 1 - _win(t, 0.84, 0.97);
    }
    final st = 0.55 / math.max(1, n);
    return _win(manual.value, i * st, i * st + 0.45);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final l = layout;
    final n = l.length;
    if (n == 0) return;
    final scrY = l.scr.first.top;
    final memY = l.mem.first.top;

    // Row labels
    _text(canvas, 'screen', BT.mono(16, color: BP.inkDim), Offset(0, scrY + _chipH / 2 - 10));
    _text(canvas, 'memory', BT.mono(16, color: BP.inkDim), Offset(0, memY + _chipH / 2 - 10));

    // Run arrows overhead, stacked by (approximate) level.
    for (final a in l.arrows) {
      final y = _textTop - 16 - a.lane * 26;
      final c = _dirColor(a.rtl);
      final p = Paint()
        ..color = c
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final from = a.rtl ? a.x1 - 3 : a.x0 + 3;
      final to = a.rtl ? a.x0 + 3 : a.x1 - 3;
      canvas.drawLine(Offset(from, y), Offset(to, y), p..color = c.withValues(alpha: 0.5));
      drawArrowHead(canvas, Offset(to, y), Offset(from, y), p..color = c, 8);
      canvas.drawLine(Offset(from, y - 5), Offset(from, y + 5), p);
      final dir = a.rtl ? -1.0 : 1.0;
      final len = (to - from).abs();
      for (var d = march.value * 18; d < len - 12; d += 18) {
        final x = from + dir * d;
        final fade = math.min(1.0, math.min(d, len - d) / 16);
        drawArrowHead(canvas, Offset(x, y), Offset(x - dir, y), Paint()
          ..color = c.withValues(alpha: 0.8 * fade)
          ..strokeWidth = 1.4, 4.5);
      }
    }

    // Hovered glyph in the real text.
    if (hover != null && l.vis[hover!].width > 0) {
      final r = l.vis[hover!];
      canvas.drawRect(r, Paint()..color = BP.amber.withValues(alpha: 0.16));
      canvas.drawRect(
        r,
        Paint()
          ..color = BP.amber
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // Faint glyph boxes, colored by resolved direction.
    for (var i = 0; i < n; i++) {
      if (l.vis[i].width <= 0) continue;
      canvas.drawPath(
        dashPath(Path()..addRect(l.vis[i].deflate(0.5)), dash: 3, gap: 4),
        Paint()
          ..color = _dirColor(l.rtl[i]).withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke,
      );
    }
    l.probe.paint(canvas, l.origin);

    // Wires memory → screen (they cross wherever the order flips).
    for (var i = 0; i < n; i++) {
      final hot = hover == i;
      final a = l.mem[i].topCenter;
      final b = l.scr[i].bottomCenter;
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo(a.dx, a.dy - 70, b.dx, b.dy + 70, b.dx, b.dy);
      canvas.drawPath(
        path,
        Paint()
          ..color = hot ? BP.amber : _dirColor(l.rtl[i]).withValues(alpha: hover == null ? 0.22 : 0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = hot ? 2.2 : 1,
      );
    }

    // Memory row (fixed, logical order).
    for (var i = 0; i < n; i++) {
      _chip(canvas, l.mem[i], i, solid: true, hot: hover == i);
    }
    // Screen slots at the real visual x.
    for (var i = 0; i < n; i++) {
      final r = l.scr[i];
      canvas.drawPath(
        dashPath(Path()..addRect(r.deflate(1)), dash: 4, gap: 3),
        Paint()
          ..color = hover == i ? BP.amber : BP.lineFaint
          ..style = PaintingStyle.stroke,
      );
    }
    // Flying chips, hovered one last so it's on top.
    final order = [for (var i = 0; i < n; i++) if (i != hover) i, ?hover];
    for (final i in order) {
      final p = _progress(i, n);
      if (p <= 0.001) continue;
      final from = l.mem[i];
      final to = l.scr[i];
      final r = Rect.lerp(from, to, p)!;
      final bend = math.sin(math.pi * p) * (to.center.dx < from.center.dx ? -30 : 30);
      _chip(canvas, r.shift(Offset(bend, 0)), i, solid: true, hot: hover == i, lift: math.sin(math.pi * p));
    }
  }

  void _chip(Canvas canvas, Rect r, int i, {required bool solid, required bool hot, double lift = 0}) {
    final l = layout;
    final c = hot ? BP.amber : _dirColor(l.rtl[i]);
    canvas.drawRect(r, Paint()..color = BP.panel);
    canvas.drawRect(r, Paint()..color = c.withValues(alpha: 0.10 + 0.08 * lift));
    canvas.drawRect(
      r,
      Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = hot ? 2 : 1.2,
    );
    final ct = l.charTp[i];
    final it = l.idxTp[i];
    canvas.save();
    canvas.clipRect(r);
    final s = math.min(1.0, (r.width - 4) / math.max(1, ct.width));
    canvas.translate(r.center.dx, r.top + 36);
    canvas.scale(s);
    ct.paint(canvas, Offset(-ct.width / 2, -ct.height / 2));
    canvas.restore();
    if (r.width >= it.width + 4) {
      it.paint(canvas, Offset(r.center.dx - it.width / 2, r.top + 4));
    }
  }

  static void _text(Canvas canvas, String s, TextStyle style, Offset at) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, at);
    tp.dispose();
  }

  @override
  bool shouldRepaint(_BidiPainter old) =>
      old.layout != layout || old.auto != auto || old.hover != hover;
}
