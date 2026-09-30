import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';

/// Figma: one canvas, its own text engine. Zooming shows why a canvas app
/// has to re-rasterize text at every zoom level.
class FigmaSlide extends StatelessWidget {
  const FigmaSlide({super.key});

  @override
  Widget build(BuildContext context) => SlideFrame(
    title: 'Figma',
    trailing: Reveal(
      visible: true,
      delay: const Duration(milliseconds: 600),
      offset: const Offset(16, 0),
      child: Padding(
        padding: const EdgeInsets.only(top: 22),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'one canvas, own text engine  ', style: BT.display(28, color: BP.inkDim)),
              TextSpan(text: '≈ Flutter', style: BT.display(28, color: BP.amber, weight: 600)),
            ],
          ),
        ),
      ),
    ),
    child: const _ZoomHero(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero: bitmap vs re-rendered, same zoom, same pan
// ─────────────────────────────────────────────────────────────────────────────

TextPainter _tp(String s, TextStyle style) =>
    TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();

const _vpW = 700.0;
const _vpH = 492.0;
const _vpGap = 72.0;
const _vpTop = 18.0;

class _ZoomHero extends StatefulWidget {
  const _ZoomHero();

  @override
  State<_ZoomHero> createState() => _ZoomHeroState();
}

class _ZoomHeroState extends State<_ZoomHero> with SingleTickerProviderStateMixin {
  static const _word = '文字';
  static const _fs = 14.0;
  static const _pad = 2.0;
  static const _maxV = 6.0; // 2^6 = 64×

  /// Auto zoom: in and out again; the deepest zoom lands ~4.2 s after arrival.
  static const _autoPeriod = 8.4;

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

  /// Deepest auto zoom: the whole word just fits the viewport.
  double get _peakV => (math.log(0.8 * _vpW / _small.width) / math.ln2).clamp(1.0, _maxV);

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
    _phase = (_phase + dt / _autoPeriod) % 1.0;
    setState(() {
      _v = _peakV * (0.5 - 0.5 * math.cos(2 * math.pi * _phase));
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
      final v = _v.clamp(0.0, _peakV);
      _v = v;
      _phase = math.acos((1 - 2 * v / _peakV).clamp(-1.0, 1.0)) / (2 * math.pi);
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
  }) => CustomPaint(
    foregroundPainter: _FramePainter(color),
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
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
                  child: ColoredBox(
                    color: BP.panel,
                    child: CustomPaint(painter: painter, child: const SizedBox.expand()),
                  ),
                ),
              ),
            ),
          ),
        ),
        // How many times the text has been rasterized so far.
        Positioned(
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              decoration: BoxDecoration(
                color: BP.paper.withValues(alpha: 0.92),
                border: const Border(
                  left: BorderSide(color: BP.lineDim),
                  top: BorderSide(color: BP.lineDim),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('rasterized', style: BT.mono(20, color: BP.inkDim)),
                  const SizedBox(width: 12),
                  Text(
                    '×${AnimatedCount.format(rasters)}',
                    style: BT.mono(30, color: color, weight: 600),
                  ),
                ],
              ),
            ),
          ),
        ),
        // The label, notched into the top edge.
        Positioned(
          left: 18,
          top: -18,
          child: IgnorePointer(
            child: Container(
              color: BP.paper,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(label, style: BT.display(26, color: color)),
            ),
          ),
        ),
      ],
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
          top: _vpTop,
          width: _vpW,
          height: _vpH,
          child: Reveal(
            visible: true,
            delay: const Duration(milliseconds: 150),
            child: _viewport(
              label: 'scaled bitmap',
              painter: _BitmapPainter(image: _bitmap, z: z, cam: cam, text: _textRect),
              rasters: 1,
              color: BP.inkDim,
            ),
          ),
        ),
        Positioned(
          left: _vpW + _vpGap,
          top: _vpTop,
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
          top: _vpTop + _vpH / 2 - 40,
          width: _vpGap,
          height: 80,
          child: CustomPaint(painter: _SyncPainter()),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: _vpTop + _vpH + 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ZoomSlider(
                value: _v,
                max: _maxV,
                width: 820,
                onChanged: (v) => _manual(() => _v = v),
              ),
              const SizedBox(width: 28),
              BpButton(label: 'auto', size: 20, selected: _auto, onTap: _toggleAuto),
            ],
          ),
        ),
      ],
    );
  }
}

/// Viewport outline with blueprint corner ticks.
class _FramePainter extends CustomPainter {
  _FramePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..color = color == BP.amber ? BP.amber.withValues(alpha: 0.7) : BP.lineDim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    final t = Paint()
      ..color = BP.line
      ..strokeWidth = 2;
    const l = 10.0;
    for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      final dx = c.dx == 0 ? l : -l;
      final dy = c.dy == 0 ? l : -l;
      canvas.drawLine(c, c + Offset(dx, 0), t);
      canvas.drawLine(c, c + Offset(0, dy), t);
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.color != color;
}

/// Ruler-style zoom slider (a larger copy of [BpSlider]): ticks at every
/// doubling, a diamond thumb, and the zoom as a big readout.
class _ZoomSlider extends StatelessWidget {
  const _ZoomSlider({
    required this.value,
    required this.max,
    required this.width,
    required this.onChanged,
  });

  final double value;
  final double max;
  final double width;
  final ValueChanged<double> onChanged;

  static String _format(double v) {
    final z = math.pow(2, v).toDouble();
    return '${z < 10 ? z.toStringAsFixed(1) : z.round()}×';
  }

  @override
  Widget build(BuildContext context) {
    void update(Offset p) => onChanged((p.dx / width).clamp(0.0, 1.0) * max);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('zoom', style: BT.mono(22, color: BP.inkDim)),
        const SizedBox(width: 20),
        SizedBox(
          width: width,
          height: 48,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (d) => update(d.localPosition),
              onPanUpdate: (d) => update(d.localPosition),
              child: CustomPaint(
                painter: _SliderPainter(t: (value / max).clamp(0.0, 1.0), ticks: max.round()),
              ),
            ),
          ),
        ),
        const SizedBox(width: 20),
        SizedBox(
          width: 100,
          child: Text(_format(value), style: BT.mono(28, color: BP.amber, weight: 600)),
        ),
      ],
    );
  }
}

class _SliderPainter extends CustomPainter {
  _SliderPainter({required this.t, required this.ticks});

  final double t;
  final int ticks;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final dim = Paint()
      ..color = BP.lineDim
      ..strokeWidth = 1.5;
    final hot = Paint()
      ..color = BP.line
      ..strokeWidth = 3;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), dim);
    for (var i = 0; i <= ticks; i++) {
      final x = size.width * i / ticks;
      canvas.drawLine(Offset(x, y - 10), Offset(x, y + 10), dim);
    }
    final x = size.width * t;
    canvas.drawLine(Offset(0, y), Offset(x, y), hot);
    final d = Path()
      ..moveTo(x, y - 13)
      ..lineTo(x + 13, y)
      ..lineTo(x, y + 13)
      ..lineTo(x - 13, y)
      ..close();
    canvas.drawPath(d, Paint()..color = BP.paper);
    canvas.drawPath(
      d,
      Paint()
        ..color = BP.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_SliderPainter old) => old.t != t || old.ticks != ticks;
}

/// Figma-style selection: blue box with square handles, constant screen size.
void _drawSelection(Canvas canvas, Rect r) {
  canvas.drawRect(
    r,
    Paint()
      ..color = BP.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5,
  );
  for (final p in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
    final h = Rect.fromCenter(center: p, width: 10, height: 10);
    canvas.drawRect(h, Paint()..color = BP.ink);
    canvas.drawRect(
      h,
      Paint()
        ..color = BP.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
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
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final y1 = size.height * 0.35;
    final y2 = size.height * 0.65;
    canvas.drawPath(dashPath(Path()
      ..moveTo(8, y1)
      ..lineTo(size.width - 8, y1), dash: 5, gap: 4), p);
    canvas.drawPath(dashPath(Path()
      ..moveTo(size.width - 8, y2)
      ..lineTo(8, y2), dash: 5, gap: 4), p);
    drawArrowHead(canvas, Offset(size.width - 8, y1), Offset(8, y1), p, 9);
    drawArrowHead(canvas, Offset(8, y2), Offset(size.width - 8, y2), p, 9);
  }

  @override
  bool shouldRepaint(_SyncPainter old) => false;
}
