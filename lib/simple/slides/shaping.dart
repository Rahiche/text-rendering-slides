import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';

/// Shaping: five before → after demos, all rendered by the real shaper.
class ShapingSlide extends StatefulWidget {
  const ShapingSlide({super.key});

  @override
  State<ShapingSlide> createState() => _ShapingSlideState();
}

enum _Tab {
  join('join', 'isolated', 'joined'),
  ligature('ligature', 'calt off', 'calt on'),
  kerning('kerning', 'kern off', 'kern on'),
  reorder('reorder', 'code points', 'glyphs'),
  zwj('emoji ZWJ', 'sequence', 'cluster');

  const _Tab(this.label, this.before, this.after);

  final String label;
  final String before;
  final String after;
}

class _ShapingSlideState extends State<ShapingSlide> with TickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3400),
  )..repeat();
  late final AnimationController _manual = AnimationController(vsync: this);
  late final Animation<double> _auto = _loop.drive(
    TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0), weight: 18),
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 34,
      ),
      TweenSequenceItem(tween: ConstantTween(1), weight: 34),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 14,
      ),
    ]),
  );

  _Tab _tab = _Tab.join;
  int _mode = 0; // 0 auto · 1 before · 2 after
  late _Demo _demo = _make(_tab);

  Animation<double> get _m => _mode == 0 ? _auto : _manual;

  static _Demo _make(_Tab t) => switch (t) {
    _Tab.join => _JoinDemo(),
    _Tab.ligature => _LigatureDemo(),
    _Tab.kerning => _KernDemo(),
    _Tab.reorder => _ReorderDemo(),
    _Tab.zwj => _ZwjDemo(),
  };

  void _select(_Tab t) {
    if (t == _tab) return;
    final old = _demo;
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    setState(() {
      _tab = t;
      _demo = _make(t);
    });
    if (_mode == 0) {
      _loop.value = 0;
      _loop.repeat();
    }
  }

  void _setMode(int mode) {
    if (mode == _mode) return;
    if (mode == 0) {
      _loop.repeat();
    } else {
      _manual.value = _m.value;
      _loop.stop();
      _manual.animateTo(
        mode == 2 ? 1 : 0,
        duration: const Duration(milliseconds: 1100),
        curve: Curves.easeInOutCubic,
      );
    }
    setState(() => _mode = mode);
  }

  @override
  void dispose() {
    _loop.dispose();
    _manual.dispose();
    _demo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideFrame(
      title: 'Shaping',
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 84,
            bottom: 34,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _StagePainter(demo: _demo, m: _m, tab: _tab),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: BpSegmented<_Tab>(
              values: _Tab.values,
              selected: _tab,
              onChanged: _select,
              labelOf: (t) => t.label,
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: BpSegmented<int>(
              values: const [0, 1, 2],
              selected: _mode,
              onChanged: _setMode,
              color: BP.amber,
              labelOf: (i) => switch (i) {
                0 => 'auto',
                1 => _tab.before,
                _ => _tab.after,
              },
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Row(
              children: [
                Container(width: 24, height: 1, color: BP.lineDim),
                const SizedBox(width: 10),
                Text('HarfBuzz: code points → glyph ids + positions', style: BT.mono(14, color: BP.inkDim)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared painting helpers
// ─────────────────────────────────────────────────────────────────────────────

double _ease(double t) => Curves.easeInOutCubic.transform(t.clamp(0.0, 1.0));
double _win(double v, double a, double b) => _ease((v - a) / (b - a));
double _lerp(double a, double b, double t) => lerpDouble(a, b, t)!;

void _paintAlpha(Canvas canvas, TextProbe probe, Offset o, double alpha) {
  if (alpha <= 0.001) return;
  if (alpha >= 0.999) {
    probe.paint(canvas, o);
    return;
  }
  canvas.saveLayer((o & probe.size).inflate(60), Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
  probe.paint(canvas, o);
  canvas.restore();
}

void _label(Canvas canvas, String text, TextStyle style, Offset center, {double alpha = 1}) {
  if (alpha <= 0.001) return;
  final c = style.color ?? BP.ink;
  final tp = TextPainter(
    text: TextSpan(text: text, style: style.copyWith(color: c.withValues(alpha: c.a * alpha))),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  tp.dispose();
}

void _dashRect(Canvas canvas, Rect r, Color color, {double width = 1}) {
  canvas.drawPath(
    dashPath(Path()..addRect(r), dash: 5, gap: 4),
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width,
  );
}

/// |←— label —→| drawn directly on a canvas.
void _dim(Canvas canvas, double x0, double x1, double y, String label, Color color, {double alpha = 1}) {
  if (alpha <= 0.001) return;
  final p = Paint()
    ..color = color.withValues(alpha: alpha)
    ..strokeWidth = 1.2
    ..style = PaintingStyle.stroke;
  canvas.drawLine(Offset(x0, y), Offset(x1, y), p);
  canvas.drawLine(Offset(x0, y - 8), Offset(x0, y + 8), p);
  canvas.drawLine(Offset(x1, y - 8), Offset(x1, y + 8), p);
  if ((x1 - x0).abs() > 14) {
    drawArrowHead(canvas, Offset(x0, y), Offset(x0 + 10, y), p, 5);
    drawArrowHead(canvas, Offset(x1, y), Offset(x1 - 10, y), p, 5);
  }
  _label(canvas, label, BT.mono(14, color: color), Offset((x0 + x1) / 2, y + 18), alpha: alpha);
}

String _u(int cp) => 'U+${cp.toRadixString(16).toUpperCase().padLeft(4, '0')}';

class _StagePainter extends CustomPainter {
  _StagePainter({required this.demo, required this.m, required this.tab}) : super(repaint: m);

  final _Demo demo;
  final Animation<double> m;
  final _Tab tab;

  @override
  void paint(Canvas canvas, Size size) {
    final v = m.value.clamp(0.0, 1.0);
    demo.paint(canvas, Size(size.width, size.height - 40), v);

    // before ─◆─ after indicator
    final y = size.height - 12;
    const x0 = 120.0;
    const x1 = 300.0;
    _label(canvas, tab.before, BT.mono(14, color: Color.lerp(BP.ink, BP.inkFaint, v)!), Offset(x0 - 60, y));
    _label(canvas, tab.after, BT.mono(14, color: Color.lerp(BP.inkFaint, BP.amber, v)!), Offset(x1 + 60, y));
    canvas.drawLine(Offset(x0, y), Offset(x1, y), Paint()..color = BP.lineDim);
    final dx = _lerp(x0, x1, v);
    final d = Path()
      ..moveTo(dx, y - 7)
      ..lineTo(dx + 7, y)
      ..lineTo(dx, y + 7)
      ..lineTo(dx - 7, y)
      ..close();
    canvas.drawPath(d, Paint()..color = BP.amber);
  }

  @override
  bool shouldRepaint(_StagePainter old) => old.demo != demo || old.m != m || old.tab != tab;
}

abstract class _Demo {
  void paint(Canvas canvas, Size size, double m);
  void dispose();
}

// ─────────────────────────────────────────────────────────────────────────────
// a) Arabic joining
// ─────────────────────────────────────────────────────────────────────────────

class _JoinDemo implements _Demo {
  _JoinDemo() {
    final style = BT.sample(128, color: BP.ink);
    for (final l in _letters) {
      _iso.add(TextProbe(TextSpan(text: l, style: style), textDirection: TextDirection.rtl));
    }
    _joined = TextProbe(TextSpan(text: _letters.join(), style: style), textDirection: TextDirection.rtl);
  }

  static const _letters = ['ك', 'ت', 'ا', 'ب'];
  static const _forms = ['init', 'medi', 'fina', 'isol'];

  final _iso = <TextProbe>[];
  late final TextProbe _joined;

  @override
  void paint(Canvas canvas, Size size, double m) {
    final p1 = _win(m, 0, 0.55);
    final p2 = _win(m, 0.45, 0.85);
    final cx = size.width / 2;
    final top = math.max(0.0, (size.height - _joined.size.height) / 2 - 50);
    const gap = 80.0;

    // Before: isolated letters, right to left, with gaps.
    final total = _iso.fold<double>(0, (a, p) => a + p.size.width) + gap * (_iso.length - 1);
    var cursor = cx + total / 2;
    final beforeLeft = <double>[];
    for (final p in _iso) {
      cursor -= p.size.width;
      beforeLeft.add(cursor);
      cursor -= gap;
    }
    final jo = Offset(cx - _joined.size.width / 2, top);
    final jBoxes = [
      for (var i = 0; i < _letters.length; i++) (_joined.rectFor(i, i + 1) ?? Rect.zero).shift(jo),
    ];

    // Baseline
    final lines = _joined.lines;
    if (lines.isNotEmpty) {
      final by = top + lines.first.baseline;
      canvas.drawPath(
        dashPath(Path()
          ..moveTo(cx - 520, by)
          ..lineTo(cx + 520, by), dash: 8, gap: 6),
        Paint()
          ..color = BP.lineFaint
          ..style = PaintingStyle.stroke,
      );
    }

    for (var i = 0; i < _letters.length; i++) {
      final local = _iso[i].rectFor(0, 1) ?? (Offset.zero & _iso[i].size);
      final afterLeft = jBoxes[i].center.dx - local.center.dx;
      final o = Offset(_lerp(beforeLeft[i], afterLeft, p1), top);
      _paintAlpha(canvas, _iso[i], o, 1 - p2);
      final box = Rect.lerp(local.shift(o), jBoxes[i], p2)!;
      _dashRect(canvas, box.deflate(1), Color.lerp(BP.lineDim, BP.line, p2)!);

      // Joined boxes are narrow: stagger odd labels onto a second tier.
      final tier = i.isOdd ? 58.0 * p2 : 0.0;
      final ly = box.bottom + 24 + tier;
      if (tier > 1) {
        canvas.drawLine(
          Offset(box.center.dx, box.bottom + 4),
          Offset(box.center.dx, ly - 10),
          Paint()
            ..color = BP.lineFaint
            ..strokeWidth = 1,
        );
      }
      _label(canvas, _u(_letters[i].runes.first), BT.mono(14, color: BP.inkDim), Offset(box.center.dx, ly));
      final changed = _forms[i] != 'isol';
      _label(canvas, 'isol', BT.mono(17, color: BP.inkFaint), Offset(box.center.dx, ly + 28), alpha: changed ? 1 - p2 : 1);
      if (changed) {
        _label(canvas, _forms[i], BT.mono(17, color: BP.amber, weight: 600), Offset(box.center.dx, ly + 28), alpha: p2);
      }
    }
    _paintAlpha(canvas, _joined, jo, p2);

    // Reading direction
    final ay = top - 6;
    final a = Paint()
      ..color = BP.amber.withValues(alpha: 0.8)
      ..strokeWidth = 1.5;
    drawArrow(canvas, Offset(cx + 120, ay), Offset(cx - 120, ay), a);
    _label(canvas, 'rtl', BT.mono(13, color: BP.amber), Offset(cx + 150, ay));
  }

  @override
  void dispose() {
    for (final p in _iso) {
      p.dispose();
    }
    _joined.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// b) Code ligatures (JetBrains Mono 'calt')
// ─────────────────────────────────────────────────────────────────────────────

class _LigatureDemo implements _Demo {
  _LigatureDemo() {
    final base = BT.mono(104, color: BP.ink);
    _off = TextProbe(TextSpan(text: _text, style: base.copyWith(fontFeatures: const [FontFeature.disable('calt')])));
    _on = TextProbe(TextSpan(text: _text, style: base.copyWith(fontFeatures: const [FontFeature.enable('calt')])));
    var s = -1;
    for (var i = 0; i <= _text.length; i++) {
      final space = i == _text.length || _text[i] == ' ';
      if (!space && s < 0) s = i;
      if (space && s >= 0) {
        _tokens.add((s, i));
        s = -1;
      }
    }
  }

  static const _text = '-> => != >= ===';

  late final TextProbe _off;
  late final TextProbe _on;
  final _tokens = <(int, int)>[];

  @override
  void paint(Canvas canvas, Size size, double m) {
    final o = Offset((size.width - _off.size.width) / 2, math.max(40.0, (size.height - _off.size.height) / 2 - 40));

    // Monospace cells (same advances before and after).
    for (var i = 0; i < _text.length; i++) {
      if (_text[i] == ' ') continue;
      final r = _off.rectFor(i, i + 1);
      if (r != null) _dashRect(canvas, r.shift(o).deflate(2), BP.lineFaint);
    }

    for (var k = 0; k < _tokens.length; k++) {
      final (s, e) = _tokens[k];
      final pk = _win(m, 0.04 + k * 0.08, 0.42 + k * 0.08);
      final r = (_off.rectFor(s, e) ?? Rect.zero).shift(o);
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(r.left, r.top - 40, r.right, r.bottom + 40));
      _paintAlpha(canvas, _off, o + Offset(0, -18 * pk), 1 - pk);
      _paintAlpha(canvas, _on, o + Offset(0, 18 * (1 - pk)), pk);
      canvas.restore();

      // Bracket: one symbol on screen.
      final y = r.top + 6;
      final bracket = Path()
        ..moveTo(r.left + 6, y + 10)
        ..lineTo(r.left + 6, y)
        ..lineTo(r.right - 6, y)
        ..lineTo(r.right - 6, y + 10);
      canvas.drawPath(
        partialPath(bracket, pk),
        Paint()
          ..color = BP.amber
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );

      // The code points underneath never change.
      final cps = _text.substring(s, e).codeUnits.map((c) => c.toRadixString(16).toUpperCase()).join(' ');
      _label(canvas, cps, BT.mono(14, color: BP.inkDim), Offset(r.center.dx, r.bottom + 22));
    }

    final cy = o.dy + _off.size.height + 84;
    _label(canvas, "FontFeature.disable('calt')", BT.mono(18, color: BP.inkDim), Offset(size.width / 2, cy), alpha: 1 - m);
    _label(canvas, "FontFeature.enable('calt')", BT.mono(18, color: BP.amber), Offset(size.width / 2, cy), alpha: m);
  }

  @override
  void dispose() {
    _off.dispose();
    _on.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// c) Kerning
// ─────────────────────────────────────────────────────────────────────────────

class _KernDemo implements _Demo {
  _KernDemo() {
    final base = BT.display(150, weight: 500);
    final offStyle = base.copyWith(fontFeatures: const [FontFeature.disable('kern')]);
    _off = TextProbe(TextSpan(text: _text, style: offStyle));
    _on = TextProbe(TextSpan(text: _text, style: base.copyWith(fontFeatures: const [FontFeature.enable('kern')])));
    for (var i = 0; i < _text.length; i++) {
      _glyphs.add(TextProbe(TextSpan(text: _text[i], style: offStyle)));
      _offBoxes.add(_off.rectFor(i, i + 1) ?? Rect.zero);
      _onBoxes.add(_on.rectFor(i, i + 1) ?? Rect.zero);
    }
  }

  static const _text = 'AVATAR To';

  late final TextProbe _off;
  late final TextProbe _on;
  final _glyphs = <TextProbe>[];
  final _offBoxes = <Rect>[];
  final _onBoxes = <Rect>[];

  @override
  void paint(Canvas canvas, Size size, double m) {
    final p = _win(m, 0.08, 0.72);
    final o = Offset((size.width - _off.size.width) / 2, math.max(60.0, (size.height - _off.size.height) / 2));
    final offW = _off.size.width;
    final onW = _on.size.width;
    final w = _lerp(offW, onW, p);

    final lines = _off.lines;
    if (lines.isNotEmpty) {
      final by = o.dy + lines.first.baseline;
      canvas.drawPath(
        dashPath(Path()
          ..moveTo(o.dx - 60, by)
          ..lineTo(o.dx + offW + 60, by), dash: 8, gap: 6),
        Paint()
          ..color = BP.lineFaint
          ..style = PaintingStyle.stroke,
      );
    }

    for (var i = 0; i < _text.length; i++) {
      if (_text[i] == ' ') continue;
      final left = _lerp(_offBoxes[i].left, _onBoxes[i].left, p);
      final box = Rect.lerp(_offBoxes[i], _onBoxes[i], p)!.shift(o);
      canvas.drawRect(box.deflate(1), Paint()..color = BP.line.withValues(alpha: 0.04));
      _dashRect(canvas, box.deflate(1), BP.lineDim);
      _glyphs[i].paint(canvas, o + Offset(left, 0));
    }

    // Real pair adjustments, measured from both layouts.
    for (var i = 0; i < _text.length - 1; i++) {
      final delta = (_onBoxes[i + 1].left - _onBoxes[i].left) - (_offBoxes[i + 1].left - _offBoxes[i].left);
      if (delta.abs() < 0.5) continue;
      final x = o.dx + _lerp(_offBoxes[i + 1].left, _onBoxes[i + 1].left, p);
      final y = o.dy + _off.size.height + 8;
      canvas.drawLine(
        Offset(x, y - 16),
        Offset(x, y),
        Paint()
          ..color = BP.amber.withValues(alpha: p)
          ..strokeWidth = 1.5,
      );
      _label(canvas, delta.toStringAsFixed(1).replaceFirst('-', '−'), BT.mono(14, color: BP.amber), Offset(x, y + 14),
          alpha: p);
    }

    // Widths
    final topY = o.dy - 26;
    _dim(canvas, o.dx, o.dx + w, topY, '${w.toStringAsFixed(1)} px', BP.inkDim);
    final dy = o.dy + _off.size.height + 64;
    final diff = onW - offW;
    _dim(canvas, o.dx + onW, o.dx + offW, dy, 'Δ ${diff.toStringAsFixed(1).replaceFirst('-', '−')} px', BP.amber,
        alpha: p);
  }

  @override
  void dispose() {
    _off.dispose();
    _on.dispose();
    for (final g in _glyphs) {
      g.dispose();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// d) Devanagari reordering: कि = क + ि, but ि is drawn first
// ─────────────────────────────────────────────────────────────────────────────

class _ReorderDemo implements _Demo {
  _ReorderDemo() {
    final style = BT.sample(170, color: BP.ink);
    _shaped = TextProbe(TextSpan(text: 'कि', style: style));
    _ka = TextProbe(TextSpan(text: 'क', style: style));
    _i = TextProbe(TextSpan(text: '\u093F', style: style.copyWith(color: BP.violet)));
    _chipKa = TextProbe(TextSpan(text: 'क', style: BT.sample(44, color: BP.ink)));
    _chipI = TextProbe(TextSpan(text: '\u093F', style: BT.sample(44, color: BP.violet)));
  }

  late final TextProbe _shaped;
  late final TextProbe _ka;
  late final TextProbe _i;
  late final TextProbe _chipKa;
  late final TextProbe _chipI;

  @override
  void paint(Canvas canvas, Size size, double m) {
    final p1 = _win(m, 0, 0.5);
    final p2 = _win(m, 0.45, 0.9);
    final cx = size.width / 2;
    const top = 0.0;
    const gap = 70.0;

    // Glyph pieces: logical order → reordered → shaped cluster.
    final sx = cx - _shaped.size.width / 2;
    final kaX0 = cx - (_ka.size.width + gap + _i.size.width) / 2;
    final iX0 = kaX0 + _ka.size.width + gap;
    final kaX1 = sx + _shaped.size.width - _ka.size.width;
    final iX1 = sx - _i.size.width * 0.15;
    final kaX = _lerp(kaX0, kaX1, p1);
    final iX = _lerp(iX0, iX1, p1);
    final hop = -70 * math.sin(math.pi * p1);
    _paintAlpha(canvas, _ka, Offset(kaX, top), 1 - p2);
    _paintAlpha(canvas, _i, Offset(iX, top + hop), 1 - p2);
    _paintAlpha(canvas, _shaped, Offset(sx, top), p2);
    final cluster = (_shaped.rectFor(0, 2) ?? (Offset.zero & _shaped.size)).shift(Offset(sx, top));
    _dashRect(canvas, cluster.deflate(1), BP.line.withValues(alpha: p2));
    _label(canvas, '1 cluster', BT.mono(13, color: BP.line), Offset(cluster.right + 56, cluster.top + 16), alpha: p2);

    // Chips: code points → glyph order.
    const cw = 150.0;
    const ch = 100.0;
    final cy = _shaped.size.height + 60;
    final c0 = cx - cw - 12;
    final c1 = cx + 12;
    final kaChip = Rect.fromLTWH(_lerp(c0, c1, p1), cy + 14 * math.sin(math.pi * p1), cw, ch);
    final iChip = Rect.fromLTWH(_lerp(c1, c0, p1), cy - 110 * math.sin(math.pi * p1), cw, ch);

    // Wires from chips up to their glyph pieces.
    final kaPiece = Offset.lerp(
      Offset(kaX + _ka.size.width / 2, cluster.bottom - 30),
      Offset(cluster.left + cluster.width * 0.62, cluster.bottom - 30),
      p2,
    )!;
    final iPiece = Offset.lerp(
      Offset(iX + _i.size.width / 2, cluster.bottom - 30 + hop),
      Offset(cluster.left + cluster.width * 0.2, cluster.bottom - 30),
      p2,
    )!;
    _wire(canvas, kaChip.topCenter, kaPiece, BP.line);
    _wire(canvas, iChip.topCenter, iPiece, BP.violet);

    _chip(canvas, kaChip, _chipKa, 'U+0915', BP.line);
    _chip(canvas, iChip, _chipI, 'U+093F', BP.violet);

    _label(canvas, 'code points', BT.mono(16, color: BP.inkDim), Offset(c0 - 120, cy + ch / 2), alpha: 1 - p1);
    _label(canvas, 'glyphs', BT.mono(16, color: BP.amber), Offset(c0 - 120, cy + ch / 2), alpha: p1);
    // Index badges keep the memory order visible.
    _label(canvas, '0', BT.mono(12, color: BP.inkFaint), kaChip.topLeft + const Offset(12, 12));
    _label(canvas, '1', BT.mono(12, color: BP.inkFaint), iChip.topLeft + const Offset(12, 12));
  }

  void _wire(Canvas canvas, Offset a, Offset b, Color c) {
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..cubicTo(a.dx, a.dy - 40, b.dx, b.dy + 40, b.dx, b.dy);
    canvas.drawPath(
      dashPath(path, dash: 4, gap: 4),
      Paint()
        ..color = c.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawCircle(b, 3.5, Paint()..color = c);
  }

  void _chip(Canvas canvas, Rect r, TextProbe glyph, String cp, Color c) {
    canvas.drawRect(r, Paint()..color = BP.panel);
    canvas.drawRect(r, Paint()..color = c.withValues(alpha: 0.10));
    canvas.drawRect(
      r,
      Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    glyph.paint(canvas, Offset(r.center.dx - glyph.size.width / 2, r.top + 30 - glyph.size.height / 2 + 6));
    _label(canvas, cp, BT.mono(14, color: c), Offset(r.center.dx, r.bottom - 18));
  }

  @override
  void dispose() {
    for (final p in [_shaped, _ka, _i, _chipKa, _chipI]) {
      p.dispose();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// e) Emoji ZWJ sequence
// ─────────────────────────────────────────────────────────────────────────────

class _ZwjDemo implements _Demo {
  _ZwjDemo() {
    for (final e in _emoji) {
      _parts.add(TextProbe(TextSpan(text: e, style: BT.sample(84))));
    }
    _family = TextProbe(TextSpan(text: _emoji.join('\u200D'), style: BT.sample(150)));
  }

  static const _emoji = ['👨', '👩', '👧'];

  final _parts = <TextProbe>[];
  late final TextProbe _family;

  @override
  void paint(Canvas canvas, Size size, double m) {
    final p1 = _win(m, 0, 0.45);
    final p2 = _win(m, 0.4, 0.82);
    final cx = size.width / 2;
    const ew = 150.0;
    const zw = 110.0;
    const eh = 140.0;
    const g = 22.0;
    final cy = math.max(40.0, (size.height - eh) / 2 - 30);
    final total = 3 * ew + 2 * zw + 4 * g;
    final x0 = cx - total / 2;

    // Row slots (before).
    final slots = <Rect>[];
    var x = x0;
    for (var k = 0; k < 5; k++) {
      final w = k.isEven ? ew : zw;
      slots.add(Rect.fromLTWH(x, cy, w, eh));
      x += w + g;
    }

    // ZWJ chips shrink away as the emoji close in.
    for (final k in [1, 3]) {
      final s = 1 - p1;
      if (s <= 0.01) continue;
      final mid = Offset.lerp(slots[k].center, Offset(cx + (k == 1 ? -55 : 55), slots[k].center.dy), p1)!;
      final r = Rect.fromCenter(center: mid, width: zw * s, height: eh * s);
      canvas.drawRect(r, Paint()..color = BP.violet.withValues(alpha: 0.10 * s));
      canvas.drawRect(
        r,
        Paint()
          ..color = BP.violet.withValues(alpha: s)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      canvas.save();
      canvas.translate(mid.dx, mid.dy);
      canvas.scale(s);
      _label(canvas, 'ZWJ', BT.mono(24, color: BP.violet, weight: 600), const Offset(0, -12));
      _label(canvas, 'U+200D', BT.mono(13, color: BP.violet), const Offset(0, 40));
      canvas.restore();
    }

    // Emoji: row → huddle → one glyph.
    for (var j = 0; j < 3; j++) {
      final before = slots[j * 2].center;
      final mid = Offset(cx + (j - 1) * 110, before.dy);
      final end = Offset(cx, before.dy);
      final c = Offset.lerp(Offset.lerp(before, mid, p1)!, end, p2)!;
      final alpha = 1 - p2;
      final r = Rect.fromCenter(center: c, width: ew, height: eh);
      canvas.drawRect(
        r,
        Paint()
          ..color = BP.line.withValues(alpha: 0.8 * alpha)
          ..style = PaintingStyle.stroke,
      );
      final probe = _parts[j];
      _paintAlpha(canvas, probe, c - Offset(probe.size.width / 2, probe.size.height / 2 + 10), alpha);
      _label(canvas, _u(_emoji[j].runes.first), BT.mono(13, color: BP.line), Offset(c.dx, r.bottom - 16), alpha: alpha);
    }

    // The shaped cluster.
    final fo = Offset(cx - _family.size.width / 2, cy + eh / 2 - _family.size.height / 2);
    _paintAlpha(canvas, _family, fo, p2);
    final fr = (_family.rectFor(0, _family.text.length) ?? (Offset.zero & _family.size)).shift(fo);
    _dashRect(canvas, fr.deflate(1), BP.amber.withValues(alpha: p2), width: 1.5);

    final ly = cy + eh + 70;
    _label(canvas, '5 code points', BT.mono(18, color: BP.inkDim), Offset(cx, ly), alpha: 1 - p2);
    _label(canvas, '1 glyph', BT.mono(18, color: BP.amber, weight: 600), Offset(cx, ly), alpha: p2);
  }

  @override
  void dispose() {
    for (final p in _parts) {
      p.dispose();
    }
    _family.dispose();
  }
}
