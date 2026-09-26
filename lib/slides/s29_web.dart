import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../deck/scripts.dart';
import '../deck/theme.dart';
import '../deck/widgets.dart';

/// "On the web": a Flutter paragraph painted on a <canvas> inside a browser.
/// Adding a script shows tofu until its Noto font arrives from
/// fonts.gstatic.com; find-in-page sees the DOM but not the canvas; the side
/// diagram shows what the WASM engine ships (and what it borrows from Chrome).
class WebSlide extends StatefulWidget {
  const WebSlide({super.key});

  @override
  State<WebSlide> createState() => _WebSlideState();
}

enum _Sc {
  thai('Thai', 'สวัสดี', 'Noto Sans Thai', Script.thai),
  deva('Devanagari', 'नमस्ते', 'Noto Sans Devanagari', Script.devanagari),
  cjk('CJK', '你好', 'Noto Sans SC', Script.han),
  emoji('Emoji', '👋🌍', 'Noto Color Emoji', Script.emoji);

  const _Sc(this.label, this.word, this.font, this.script);

  final String label;
  final String word;
  final String font;
  final Script script;

  Color get color => script.color;
}

// Geometry, in content-area coordinates (1472 × 628).
const _browser = Rect.fromLTWH(0, 92, 900, 536);
const _domRect = Rect.fromLTWH(20, 94, 860, 62); // inside the browser
const _canvasRect = Rect.fromLTWH(20, 172, 860, 344); // inside the browser
const _paraPad = Offset(28, 46); // paragraph origin inside the canvas
const _paraMaxW = 860 - 56.0;
const _cloudC = Offset(768, 38);
const _diagramX = 952.0;

const _domText = 'Hello, DOM';
const _canvasBase = 'Hello, canvas';

double _ease(double x) => Curves.easeInOutCubic.transform(x.clamp(0.0, 1.0));

double _pulse(double t, double a, double b, double c, double d) {
  if (t <= a || t >= d) return 0;
  if (t < b) return _ease((t - a) / (b - a));
  if (t <= c) return 1;
  return 1 - _ease((t - c) / (d - c));
}

Paint _stroke(Color c, [double w = 1]) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w;

TextStyle get _paraStyle => BT.sample(50, height: 1.3);

/// One missing glyph cluster: its box in paragraph coordinates + its hex code.
typedef _Tofu = (Rect box, String hex);

class _WebSlideState extends State<WebSlide> with TickerProviderStateMixin {
  final _added = <_Sc>[];
  final _cached = <_Sc>{};
  late final Map<_Sc, AnimationController> _ctl = {
    for (final s in _Sc.values)
      s: AnimationController(vsync: this, duration: const Duration(milliseconds: 2900))
        ..addStatusListener((st) {
          if (st == AnimationStatus.completed) _cached.add(s);
        }),
  };
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4000),
  )..repeat();
  late final Listenable _anim = Listenable.merge([_loop, ..._ctl.values]);
  late final _query = TextEditingController(text: 'Hello');
  bool _chromium = true;

  TextProbe? _probe;
  final _words = <_Sc, Rect>{};
  final _tofu = <_Sc, List<_Tofu>>{};
  final _hex = <String, TextPainter>{};
  final _labels = <_Sc, TextPainter>{};
  late final TextPainter _cloudLabel = TextPainter(
    text: TextSpan(text: 'fonts.gstatic.com', style: BT.mono(13, color: BP.ink)),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void initState() {
    super.initState();
    _rebuild();
    PaintingBinding.instance.systemFonts.addListener(_onFonts);
  }

  void _onFonts() {
    if (mounted) setState(_rebuild);
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_onFonts);
    for (final c in _ctl.values) {
      c.dispose();
    }
    _loop.dispose();
    _query.dispose();
    _probe?.dispose();
    for (final p in [..._hex.values, ..._labels.values, _cloudLabel]) {
      p.dispose();
    }
    super.dispose();
  }

  void _rebuild() {
    final b = StringBuffer(_canvasBase);
    final ranges = <_Sc, (int, int)>{};
    for (final s in _added) {
      b.write(' ');
      final start = b.length;
      b.write(s.word);
      ranges[s] = (start, b.length);
    }
    final text = b.toString();
    _probe?.dispose();
    final p = TextProbe(TextSpan(text: text, style: _paraStyle), maxWidth: _paraMaxW);
    _probe = p;
    _words.clear();
    _tofu.clear();
    for (final MapEntry(key: s, value: (a, e)) in ranges.entries) {
      _words[s] = p.rectFor(a, e) ?? Rect.zero;
      final list = <_Tofu>[];
      var i = a;
      for (final g in text.substring(a, e).characters) {
        final r = p.rectFor(i, i + g.length);
        i += g.length;
        if (r == null) continue;
        var hex = g.runes.first.toRadixString(16).toUpperCase();
        hex = hex.padLeft(hex.length <= 4 ? 4 : 6, '0');
        list.add((r, hex));
      }
      _tofu[s] = list;
    }
  }

  TextPainter _hexPainter(String hex) => _hex.putIfAbsent(hex, () {
    final half = hex.length ~/ 2;
    return TextPainter(
      text: TextSpan(
        text: '${hex.substring(0, half)}\n${hex.substring(half)}',
        style: BT.mono(10, color: BP.inkDim, height: 1.1),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
  });

  TextPainter _packetLabel(_Sc s) => _labels.putIfAbsent(
    s,
    () => TextPainter(
      text: TextSpan(text: s.font, style: BT.mono(13, color: s.color)),
      textDirection: TextDirection.ltr,
    )..layout(),
  );

  void _toggle(_Sc s) {
    setState(() {
      if (_added.contains(s)) {
        _added.remove(s);
        _ctl[s]!.reset();
      } else {
        _added.add(s);
        if (_cached.contains(s)) {
          _ctl[s]!.value = 1;
        } else {
          _ctl[s]!.forward(from: 0);
        }
      }
      _rebuild();
    });
  }

  void _reset() {
    setState(() {
      _added.clear();
      _cached.clear();
      for (final c in _ctl.values) {
        c.reset();
      }
      _rebuild();
    });
  }

  static int _count(String text, String q) {
    if (q.isEmpty) return 0;
    final lower = text.toLowerCase();
    var n = 0;
    for (var i = lower.indexOf(q); i >= 0; i = lower.indexOf(q, i + q.length)) {
      n++;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim().toLowerCase();
    final domHits = _count(_domText, q);
    final canvasHits = _count(_probe!.text, q);
    final canvasOrigin = _browser.topLeft + _canvasRect.topLeft;
    final targets = {
      for (final e in _words.entries) e.key: canvasOrigin + _paraPad + e.value.center,
    };

    return SlideFrame(
      title: 'On the web',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Script chips
          Positioned(
            left: 0,
            top: 0,
            child: Row(
              children: [
                for (final s in _Sc.values) ...[
                  BpButton(
                    label: '+ ${s.label}',
                    color: s.color,
                    selected: _added.contains(s),
                    onTap: () => _toggle(s),
                  ),
                  const SizedBox(width: 10),
                ],
                BpButton(label: 'reset', icon: Icons.refresh, color: BP.inkDim, onTap: _reset),
              ],
            ),
          ),

          // Browser window
          Positioned.fromRect(
            rect: _browser,
            child: const CustomPaint(painter: _BrowserPainter()),
          ),
          Positioned(
            left: _browser.left + 44,
            top: _browser.top + 9,
            child: Text('my_app', style: BT.mono(13, color: BP.inkDim)),
          ),
          Positioned(
            left: _browser.left + 118,
            top: _browser.top + 48,
            child: Text('localhost:8080', style: BT.mono(14, color: BP.inkDim)),
          ),
          // Find bar
          Positioned(
            left: _browser.left + 520,
            top: _browser.top + 40,
            width: 366,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: BP.paper,
                border: Border.all(color: q.isEmpty ? BP.lineDim : BP.amber),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  const Icon(Icons.search, size: 18, color: BP.inkDim),
                  const SizedBox(width: 4),
                  BpTextField(
                    controller: _query,
                    width: 200,
                    style: BT.mono(17, color: BP.ink),
                    hint: 'find',
                    onChanged: (_) => setState(() {}),
                  ),
                  const Spacer(),
                  Text(
                    '${domHits == 0 ? 0 : 1}/$domHits',
                    style: BT.mono(15, color: domHits > 0 ? BP.green : BP.red),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
          // DOM text
          Positioned.fromRect(
            rect: _domRect.shift(_browser.topLeft),
            child: CustomPaint(
              painter: DashedRectPainter(color: BP.lineFaint),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Text('<p>', style: BT.mono(14, color: BP.inkFaint)),
                    const SizedBox(width: 16),
                    Text.rich(_highlight(_domText, q, BT.sample(30))),
                    const Spacer(),
                    AnimatedOpacity(
                      opacity: domHits > 0 ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const BpTag('found', color: BP.green),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // The canvas
          Positioned.fromRect(
            rect: _canvasRect.shift(_browser.topLeft),
            child: CustomPaint(
              painter: DashedRectPainter(color: BP.lineDim),
              foregroundPainter: _CanvasPainter(
                repaint: _anim,
                loop: _loop,
                probe: _probe!,
                words: _words,
                tofu: _tofu,
                progress: (s) => _ctl[s]!.value,
                query: q,
                hex: _hexPainter,
              ),
              child: Stack(
                children: [
                  const Positioned(left: 12, top: 10, child: BpTag('<canvas>', color: BP.line)),
                  Positioned(
                    right: 12,
                    top: 10,
                    child: AnimatedOpacity(
                      opacity: canvasHits > 0 ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const BpTag('invisible to find', color: BP.red),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Cloud + font packets
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _SkyPainter(
                  repaint: _anim,
                  loop: _loop,
                  targets: targets,
                  progress: (s) => _ctl[s]!.value,
                  label: _packetLabel,
                  cloudLabel: _cloudLabel,
                ),
              ),
            ),
          ),

          // Side diagram
          Positioned(
            left: _diagramX,
            top: 0,
            right: 0,
            bottom: 0,
            child: _Diagram(
              chromium: _chromium,
              loop: _loop,
              onChanged: (v) => setState(() => _chromium = v),
            ),
          ),
        ],
      ),
    );
  }

  static TextSpan _highlight(String text, String q, TextStyle style) {
    if (q.isEmpty) return TextSpan(text: text, style: style);
    final lower = text.toLowerCase();
    final out = <TextSpan>[];
    var i = 0;
    for (var j = lower.indexOf(q); j >= 0; j = lower.indexOf(q, j + q.length)) {
      if (j > i) out.add(TextSpan(text: text.substring(i, j)));
      out.add(TextSpan(
        text: text.substring(j, j + q.length),
        style: TextStyle(backgroundColor: BP.green.withValues(alpha: 0.35), color: BP.ink),
      ));
      i = j + q.length;
    }
    if (i < text.length) out.add(TextSpan(text: text.substring(i)));
    return TextSpan(style: style, children: out);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Browser chrome
// ─────────────────────────────────────────────────────────────────────────────

class _BrowserPainter extends CustomPainter {
  const _BrowserPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final outer = RRect.fromRectAndRadius(r, const Radius.circular(10));
    canvas.drawRRect(outer, Paint()..color = BP.panel);
    canvas.drawRRect(outer, _stroke(BP.line, 1.5));
    final dim = _stroke(BP.lineDim);
    // tab
    final tab = Path()
      ..moveTo(14, 36)
      ..lineTo(24, 6)
      ..lineTo(200, 6)
      ..lineTo(210, 36);
    canvas.drawPath(tab, dim);
    canvas.drawLine(const Offset(182, 16), const Offset(190, 24), dim);
    canvas.drawLine(const Offset(190, 16), const Offset(182, 24), dim);
    canvas.drawCircle(const Offset(34, 21), 5, dim);
    canvas.drawLine(Offset(210, 36), Offset(size.width, 36), dim);
    canvas.drawLine(const Offset(0, 36), const Offset(14, 36), dim);
    // toolbar
    drawArrowHead(canvas, const Offset(18, 58), const Offset(28, 58), dim, 7);
    drawArrowHead(canvas, const Offset(58, 58), const Offset(48, 58), dim, 7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(80, 42, 424, 32), const Radius.circular(16)),
      dim,
    );
    canvas.drawRect(const Rect.fromLTWH(96, 56, 10, 8), dim);
    canvas.drawArc(const Rect.fromLTWH(97, 49, 8, 10), math.pi, math.pi, false, dim);
    canvas.drawLine(Offset(0, 84), Offset(size.width, 84), dim);
  }

  @override
  bool shouldRepaint(_BrowserPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Canvas: the paragraph, tofu for scripts whose font hasn't arrived yet,
// find matches the browser can't see.
// ─────────────────────────────────────────────────────────────────────────────

class _CanvasPainter extends CustomPainter {
  _CanvasPainter({
    required Listenable repaint,
    required this.loop,
    required this.probe,
    required this.words,
    required this.tofu,
    required this.progress,
    required this.query,
    required this.hex,
  }) : super(repaint: repaint);

  final Animation<double> loop;
  final TextProbe probe;
  final Map<_Sc, Rect> words;
  final Map<_Sc, List<_Tofu>> tofu;
  final double Function(_Sc) progress;
  final String query;
  final TextPainter Function(String) hex;

  @override
  void paint(Canvas canvas, Size size) {
    const o = _paraPad;
    final loading = [for (final s in words.keys) if (progress(s) < 1) s];

    // 1. Everything whose font is ready.
    canvas.save();
    for (final s in loading) {
      canvas.clipRect(words[s]!.shift(o).inflate(3), clipOp: ui.ClipOp.difference);
    }
    probe.paint(canvas, o);
    canvas.restore();

    // 2. Words still waiting: tofu, then the real glyphs fade in.
    for (final s in loading) {
      final v = progress(s);
      final r = words[s]!.shift(o).inflate(3);
      final glyph = _ease((v - 0.74) / 0.12);
      if (glyph > 0) {
        canvas.saveLayer(r.inflate(4), Paint()..color = Color.fromRGBO(0, 0, 0, glyph));
        canvas.clipRect(r);
        probe.paint(canvas, o);
        canvas.restore();
      }
      final show = _ease(v / 0.06) * (v < 0.74 ? 1.0 : 1 - _ease((v - 0.74) / 0.06));
      if (show > 0) {
        for (final (box, code) in tofu[s] ?? const <_Tofu>[]) {
          final b = box.shift(o);
          final t = Rect.fromLTWH(
            b.left + 3,
            b.top + b.height * 0.14,
            math.max(6, b.width - 6),
            b.height * 0.66,
          );
          canvas.drawRect(t, Paint()..color = BP.inkDim.withValues(alpha: 0.07 * show));
          canvas.drawRect(t, _stroke(BP.inkDim.withValues(alpha: show), 1.5));
          final h = hex(code);
          if (show > 0.6 && t.width > h.width + 4) {
            h.paint(canvas, t.center - Offset(h.width / 2, h.height / 2));
          }
        }
      }
      final flash = _pulse(v, 0.7, 0.76, 0.8, 0.98);
      if (flash > 0) {
        canvas.drawRect(
          r.inflate(4 + 12 * (1 - flash)),
          _stroke(s.color.withValues(alpha: flash), 2),
        );
      }
    }

    // 3. Find-in-page can't see any of this.
    if (query.isNotEmpty) {
      final lower = probe.text.toLowerCase();
      final red = _stroke(BP.red, 1.5);
      for (var i = lower.indexOf(query); i >= 0; i = lower.indexOf(query, i + query.length)) {
        final r = probe.rectFor(i, i + query.length);
        if (r == null) continue;
        final box = r.shift(o).inflate(5);
        canvas.drawPath(dashPath(Path()..addRect(box), dash: 5, gap: 4), red);
        final c = box.topRight;
        final x = Paint()
          ..color = BP.red
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round;
        canvas.drawCircle(c, 10, Paint()..color = BP.panel);
        canvas.drawCircle(c, 10, red);
        canvas.drawLine(c - const Offset(4, 4), c + const Offset(4, 4), x);
        canvas.drawLine(c + const Offset(4, -4), c + const Offset(-4, 4), x);
      }
    }

    // 4. Blinking caret at the end of the paragraph.
    if ((loop.value * 6).floor().isEven) {
      final end = probe.painter.getOffsetForCaret(
        TextPosition(offset: probe.text.length),
        Rect.zero,
      );
      final lines = probe.lines;
      final h = lines.isEmpty ? 50.0 : lines.last.ascent + lines.last.descent;
      final top = lines.isEmpty ? end.dy : lines.last.baseline - lines.last.ascent;
      canvas.drawRect(Rect.fromLTWH(o.dx + end.dx + 6, o.dy + top, 3, h), Paint()..color = BP.amber);
    }
  }

  @override
  bool shouldRepaint(_CanvasPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Cloud + font packets flying into the canvas
// ─────────────────────────────────────────────────────────────────────────────

class _SkyPainter extends CustomPainter {
  _SkyPainter({
    required Listenable repaint,
    required this.loop,
    required this.targets,
    required this.progress,
    required this.label,
    required this.cloudLabel,
  }) : super(repaint: repaint);

  final Animation<double> loop;
  final Map<_Sc, Offset> targets;
  final double Function(_Sc) progress;
  final TextPainter Function(_Sc) label;
  final TextPainter cloudLabel;

  static final Path _cloud = _makeCloud();

  static Path _makeCloud() {
    final parts = [
      Path()..addOval(Rect.fromCircle(center: const Offset(-66, 8), radius: 24)),
      Path()..addOval(Rect.fromCircle(center: const Offset(-24, -8), radius: 34)),
      Path()..addOval(Rect.fromCircle(center: const Offset(26, -4), radius: 30)),
      Path()..addOval(Rect.fromCircle(center: const Offset(68, 10), radius: 20)),
      Path()
        ..addRRect(RRect.fromRectAndRadius(
          const Rect.fromLTRB(-92, 6, 94, 34),
          const Radius.circular(14),
        )),
    ];
    var out = parts.first;
    for (final p in parts.skip(1)) {
      out = Path.combine(PathOperation.union, out, p);
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = _cloudC + Offset(0, 4 * math.sin(2 * math.pi * loop.value));
    var send = 0.0;
    for (final s in targets.keys) {
      send = math.max(send, _pulse(progress(s), 0.08, 0.14, 0.2, 0.32));
    }
    final cloud = _cloud.shift(c);
    canvas.drawPath(cloud, Paint()..color = BP.panel);
    canvas.drawPath(cloud, _stroke(Color.lerp(BP.line, BP.amber, send)!, 1.5 + send));
    cloudLabel.paint(canvas, c + Offset(-cloudLabel.width / 2, 10 - cloudLabel.height / 2));

    for (final MapEntry(key: s, value: end) in targets.entries) {
      final v = progress(s);
      if (v <= 0.1 || v >= 0.78) continue;
      final u = _ease((v - 0.12) / 0.58);
      final start = c + const Offset(0, 36);
      final ctrl = Offset(start.dx - 60, end.dy - 40);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);
      final alpha = _pulse(v, 0.1, 0.14, 0.7, 0.78);
      canvas.drawPath(
        dashPath(partialPath(path, u), dash: 5, gap: 5),
        _stroke(s.color.withValues(alpha: 0.7 * alpha), 1.4),
      );
      final m = path.computeMetrics().first;
      final tan = m.getTangentForOffset(m.length * u);
      if (tan == null) continue;
      final lp = label(s);
      final box = Rect.fromCenter(
        center: tan.position,
        width: lp.width + 38,
        height: lp.height + 14,
      );
      canvas.drawRect(box, Paint()..color = BP.paper.withValues(alpha: alpha));
      canvas.drawRect(box, _stroke(s.color.withValues(alpha: alpha), 1.5));
      final ay = box.center.dy;
      final ax = box.left + 14;
      final ap = _stroke(s.color.withValues(alpha: alpha), 1.6);
      canvas.drawLine(Offset(ax, ay - 6), Offset(ax, ay + 5), ap);
      drawArrowHead(canvas, Offset(ax, ay + 6), Offset(ax, ay - 6), ap, 5);
      canvas.saveLayer(box, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
      lp.paint(canvas, Offset(box.left + 28, box.top + 7));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Side diagram: what the WASM engine ships, and what it borrows
// ─────────────────────────────────────────────────────────────────────────────

class _Diagram extends StatelessWidget {
  const _Diagram({required this.chromium, required this.loop, required this.onChanged});

  final bool chromium;
  final Animation<double> loop;
  final ValueChanged<bool> onChanged;

  static const _w = 520.0;
  static const _panelTop = 64.0;
  static const _blockW = 220.0;
  static const _blockH = 62.0;
  static const _browserTop = 384.0;

  // Blocks, relative to the diagram.
  static const _blocks = [
    ('Skia', Offset(20, _panelTop + 42)),
    ('SkParagraph', Offset(260, _panelTop + 42)),
    ('HarfBuzz', Offset(20, _panelTop + 120)),
    ('ICU data', Offset(260, _panelTop + 120)),
  ];

  @override
  Widget build(BuildContext context) {
    final icu = _blocks[3].$2 + const Offset(_blockW / 2, _blockH);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          top: 0,
          child: BpSegmented<bool>(
            values: const [true, false],
            selected: chromium,
            labelOf: (v) => v ? 'Chrome' : 'Safari · Firefox',
            onChanged: onChanged,
          ),
        ),
        Positioned(
          left: 0,
          top: _panelTop,
          width: _w,
          height: 206,
          child: BpPanel(
            label: 'canvaskit.wasm · skwasm',
            color: BP.line,
            padding: EdgeInsets.zero,
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 10, right: 12),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: chromium
                      ? const BpTag('chromium · skwasm', key: ValueKey(1), color: BP.amber)
                      : const BpTag('canvaskit · skwasm_heavy', key: ValueKey(2), color: BP.inkDim),
                ),
              ),
            ),
          ),
        ),
        for (final (i, (name, at)) in _blocks.indexed)
          Positioned(
            left: at.dx,
            top: at.dy,
            width: _blockW,
            height: _blockH,
            child: _Block(name: name, removed: i == 3 && chromium, hot: i == 1),
          ),
        // SkParagraph asks the browser for breaks instead of ICU.
        Positioned(
          left: icu.dx - 20,
          top: icu.dy,
          width: 40,
          height: _browserTop - icu.dy,
          child: DrawOn(
            visible: chromium,
            arrow: true,
            color: BP.amber,
            duration: const Duration(milliseconds: 600),
            path: (s) => Path()
              ..moveTo(s.width / 2, 2)
              ..lineTo(s.width / 2, s.height - 4),
            child: AnimatedOpacity(
              opacity: chromium ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: CustomPaint(painter: _PacketPainter(loop), child: const SizedBox.expand()),
            ),
          ),
        ),
        Positioned(
          left: icu.dx + 18,
          top: icu.dy + 60,
          child: AnimatedOpacity(
            opacity: chromium ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: Text('breaks', style: BT.mono(14, color: BP.amber)),
          ),
        ),
        Positioned(
          left: 0,
          top: _browserTop,
          width: _w,
          height: 124,
          child: AnimatedOpacity(
            opacity: chromium ? 1 : 0.4,
            duration: const Duration(milliseconds: 300),
            child: BpPanel(
              label: 'browser',
              color: chromium ? BP.amber : BP.lineDim,
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Intl.Segmenter', style: BT.mono(21, color: BP.ink)),
                  const SizedBox(height: 8),
                  Text('Intl.v8BreakIterator', style: BT.mono(21, color: BP.ink)),
                ],
              ),
            ),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              BpTag('HTML renderer removed · 3.29', color: BP.coral, size: 14),
              BpTag('WebParagraph · experimental', color: BP.violet, size: 14),
            ],
          ),
        ),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.name, required this.removed, required this.hot});

  final String name;
  final bool removed;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    final c = removed ? BP.red : (hot ? BP.line : BP.lineDim);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 350),
      opacity: removed ? 0.75 : 1,
      child: CustomPaint(
        painter: removed ? DashedRectPainter(color: BP.red, strokeWidth: 1.5) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: removed ? BP.red.withValues(alpha: 0.06) : BP.line.withValues(alpha: hot ? 0.12 : 0.05),
            border: removed ? null : Border.all(color: c, width: hot ? 1.5 : 1),
          ),
          child: Text(
            name,
            style: BT.mono(19, color: removed ? BP.red : BP.ink).copyWith(
              decoration: removed ? TextDecoration.lineThrough : null,
              decorationColor: BP.red,
              decorationThickness: 2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Queries down, answers up, along the SkParagraph → browser arrow.
class _PacketPainter extends CustomPainter {
  _PacketPainter(this.loop) : super(repaint: loop);

  final Animation<double> loop;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    for (var k = 0; k < 3; k++) {
      final u = (loop.value * 2 + k / 3) % 1;
      final down = k.isEven;
      final y = down ? 8 + (size.height - 20) * u : size.height - 12 - (size.height - 20) * u;
      final a = math.sin(u * math.pi);
      final d = Path()
        ..moveTo(x, y - 6)
        ..lineTo(x + 6, y)
        ..lineTo(x, y + 6)
        ..lineTo(x - 6, y)
        ..close();
      canvas.drawPath(d, Paint()..color = (down ? BP.amber : BP.green).withValues(alpha: a));
    }
  }

  @override
  bool shouldRepaint(_PacketPainter old) => false;
}
