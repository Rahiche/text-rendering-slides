import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../deck/theme.dart';
import '../deck/widgets.dart';

/// Figma: one canvas, its own text engine. Zooming shows why a canvas app
/// has to re-rasterize text at every zoom level.
class FigmaSlide extends StatelessWidget {
  const FigmaSlide({super.key});

  @override
  Widget build(BuildContext context) => const SlideFrame(
    title: 'Figma',
    child: _EngineLayout(
      hero: _ZoomHero(),
      layers: [
        _Layer('C++ editor', 'own text layout engine'),
        _Layer('HarfBuzz + ICU', 'shaping · bidi'),
        _Layer('Noto fallback', 'per character'),
        _Layer('WASM', 'Emscripten'),
        _Layer('own renderer', 'one canvas'),
        _Layer('WebGPU / WebGL', 'WebGPU since 2025'),
      ],
      caps: [
        _Cap('RTL · 2022', _K.yes),
        _Cap('vertical', _K.no),
        _Cap('color fonts', _K.no),
        _Cap('same on every OS', _K.yes),
        _Cap('≈ Flutter · canvas + own engine', _K.flutter),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero: bitmap vs re-rendered, same zoom, same pan
// ─────────────────────────────────────────────────────────────────────────────

TextPainter _tp(String s, TextStyle style) =>
    TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();

const _vpW = 470.0;
const _vpH = 506.0;
const _vpGap = 40.0;

class _ZoomHero extends StatefulWidget {
  const _ZoomHero();

  @override
  State<_ZoomHero> createState() => _ZoomHeroState();
}

class _ZoomHeroState extends State<_ZoomHero> with SingleTickerProviderStateMixin {
  static const _word = 'Type';
  static const _fs = 14.0;
  static const _pad = 2.0;
  static const _maxV = 6.0; // 2^6 = 64×

  late final TextPainter _small = _tp(_word, _style(_fs));
  ui.Image? _bitmap;
  TextPainter? _big;
  double _bigZ = -1;
  int _rasters = 0;

  double _v = 0; // log2(zoom)
  Offset _pan = Offset.zero; // in 1× units, relative to the word's centre
  bool _auto = true;
  double _phase = 0;
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  static TextStyle _style(double s) => BT.display(s, weight: 500);
  double get _z => math.pow(2, _v).toDouble();
  Rect get _textRect => Rect.fromLTWH(_pad, _pad, _small.width, _small.height);

  @override
  void initState() {
    super.initState();
    _rasterizeOnce();
    _ticker = createTicker(_tick)..start();
  }

  /// Rendered ONCE at 1× into a small bitmap, never again.
  Future<void> _rasterizeOnce() async {
    final w = (_small.width + 2 * _pad).ceil();
    final h = (_small.height + 2 * _pad).ceil();
    final rec = ui.PictureRecorder();
    _small.paint(Canvas(rec), const Offset(_pad, _pad));
    final pic = rec.endRecording();
    final img = await pic.toImage(w, h);
    pic.dispose();
    if (!mounted) {
      img.dispose();
      return;
    }
    setState(() => _bitmap = img);
  }

  void _tick(Duration e) {
    final dt = ((e - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = e;
    if (!_auto) return;
    _phase = (_phase + dt / 11) % 1.0;
    setState(() {
      _v = _maxV * (0.5 - 0.5 * math.cos(2 * math.pi * _phase));
      _pan = _pan * math.pow(0.08, dt).toDouble();
    });
  }

  void _manual(VoidCallback f) => setState(() {
    _auto = false;
    f();
  });

  void _toggleAuto() => setState(() {
    _auto = !_auto;
    if (_auto) {
      _phase = math.acos((1 - 2 * _v / _maxV).clamp(-1.0, 1.0)) / (2 * math.pi);
    }
  });

  Offset _clampPan(Offset p) {
    final hx = _small.width / 2 + 4;
    final hy = _small.height / 2 + 4;
    return Offset(p.dx.clamp(-hx, hx), p.dy.clamp(-hy, hy));
  }

  /// Canvas apps lay out and paint the text again for every zoom level.
  TextPainter _bigFor(double z) {
    if (_big == null || _bigZ != z) {
      _big?.dispose();
      _big = _tp(_word, _style(_fs * z));
      _bigZ = z;
      _rasters++;
    }
    return _big!;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _small.dispose();
    _big?.dispose();
    _bitmap?.dispose();
    super.dispose();
  }

  Widget _viewport({
    required String label,
    required CustomPainter painter,
    required int rasters,
    required Color color,
  }) => BpPanel(
    label: label,
    padding: EdgeInsets.zero,
    child: Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) {
          _manual(() => _v = (_v - e.scrollDelta.dy / 240).clamp(0.0, _maxV));
        }
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => _manual(() {}),
          onPanUpdate: (d) => _manual(() => _pan = _clampPan(_pan - d.delta / _z)),
          onDoubleTap: () => _manual(() => _pan = Offset.zero),
          child: ClipRect(
            child: Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: painter)),
                Positioned(
                  left: 16,
                  bottom: 12,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('rasterized', style: BT.mono(13, color: BP.inkFaint)),
                      const SizedBox(width: 8),
                      Text(
                        '×${AnimatedCount.format(rasters)}',
                        style: BT.mono(20, color: color, weight: 600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final z = _z;
    final big = _bigFor(z);
    final cam = _textRect.center + _pan;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          top: 0,
          width: _vpW,
          height: _vpH,
          child: Reveal(
            visible: true,
            delay: const Duration(milliseconds: 150),
            child: _viewport(
              label: 'bitmap',
              painter: _BitmapPainter(image: _bitmap, z: z, cam: cam, text: _textRect),
              rasters: 1,
              color: BP.inkDim,
            ),
          ),
        ),
        Positioned(
          left: _vpW + _vpGap,
          top: 0,
          width: _vpW,
          height: _vpH,
          child: Reveal(
            visible: true,
            delay: const Duration(milliseconds: 300),
            child: _viewport(
              label: 're-rendered',
              painter: _CrispPainter(tp: big, z: z, cam: cam, text: _textRect),
              rasters: _rasters,
              color: BP.amber,
            ),
          ),
        ),
        const Positioned(
          left: _vpW,
          top: _vpH / 2 - 30,
          width: _vpGap,
          height: 60,
          child: CustomPaint(painter: _SyncPainter()),
        ),
        Positioned(
          left: 0,
          top: _vpH + 40,
          child: Row(
            children: [
              BpSlider(
                label: 'zoom',
                value: _v,
                min: 0,
                max: _maxV,
                width: 560,
                ticks: 6,
                format: (v) => '${(math.pow(2, v) * 100).round()}%',
                onChanged: (v) => _manual(() => _v = v),
              ),
              const SizedBox(width: 10),
              BpButton(label: 'auto', size: 14, selected: _auto, onTap: _toggleAuto),
            ],
          ),
        ),
      ],
    );
  }
}

/// Figma-style selection: blue box with square handles, constant screen size.
void _drawSelection(Canvas canvas, Rect r) {
  canvas.drawRect(
    r,
    Paint()
      ..color = BP.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2,
  );
  for (final p in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
    final h = Rect.fromCenter(center: p, width: 8, height: 8);
    canvas.drawRect(h, Paint()..color = BP.ink);
    canvas.drawRect(
      h,
      Paint()
        ..color = BP.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }
}

class _BitmapPainter extends CustomPainter {
  _BitmapPainter({required this.image, required this.z, required this.cam, required this.text});

  final ui.Image? image;
  final double z;
  final Offset cam;
  final Rect text;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    Offset s(Offset w) => (w - cam) * z + c;
    final img = image;
    if (img != null) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(z);
      canvas.translate(-cam.dx, -cam.dy);
      canvas.drawImage(img, Offset.zero, Paint()..filterQuality = FilterQuality.none);
      canvas.restore();

      // The bitmap's pixel grid fades in as the pixels get big.
      final a = ((z - 3) / 6).clamp(0.0, 1.0);
      if (a > 0) {
        final grid = Paint()
          ..color = BP.line.withValues(alpha: 0.3 * a)
          ..strokeWidth = 1;
        final tl = s(Offset.zero);
        final br = s(Offset(img.width.toDouble(), img.height.toDouble()));
        final top = math.max(0.0, tl.dy);
        final bottom = math.min(size.height, br.dy);
        final left = math.max(0.0, tl.dx);
        final right = math.min(size.width, br.dx);
        for (var px = 0; px <= img.width; px++) {
          final x = tl.dx + px * z;
          if (x < 0 || x > size.width) continue;
          canvas.drawLine(Offset(x, top), Offset(x, bottom), grid);
        }
        for (var py = 0; py <= img.height; py++) {
          final y = tl.dy + py * z;
          if (y < 0 || y > size.height) continue;
          canvas.drawLine(Offset(left, y), Offset(right, y), grid);
        }
      }
    }
    _drawSelection(canvas, Rect.fromPoints(s(text.topLeft), s(text.bottomRight)));
  }

  @override
  bool shouldRepaint(_BitmapPainter old) =>
      old.image != image || old.z != z || old.cam != cam || old.text != text;
}

class _CrispPainter extends CustomPainter {
  _CrispPainter({required this.tp, required this.z, required this.cam, required this.text});

  final TextPainter tp;
  final double z;
  final Offset cam;
  final Rect text;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    Offset s(Offset w) => (w - cam) * z + c;
    tp.paint(canvas, s(text.topLeft));
    _drawSelection(canvas, Rect.fromPoints(s(text.topLeft), s(text.bottomRight)));
  }

  @override
  bool shouldRepaint(_CrispPainter old) =>
      old.tp != tp || old.z != z || old.cam != cam || old.text != text;
}

/// Two dashed arrows between the viewports: zoom and pan stay in sync.
class _SyncPainter extends CustomPainter {
  const _SyncPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = BP.lineDim
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final y1 = size.height * 0.35;
    final y2 = size.height * 0.65;
    canvas.drawPath(dashPath(Path()
      ..moveTo(4, y1)
      ..lineTo(size.width - 4, y1), dash: 4, gap: 3), p);
    canvas.drawPath(dashPath(Path()
      ..moveTo(size.width - 4, y2)
      ..lineTo(4, y2), dash: 4, gap: 3), p);
    drawArrowHead(canvas, Offset(size.width - 4, y1), Offset(4, y1), p, 6);
    drawArrowHead(canvas, Offset(4, y2), Offset(size.width - 4, y2), p, 6);
  }

  @override
  bool shouldRepaint(_SyncPainter old) => false;
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
