import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:slug/slug.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';

/// Slug (Lengyel, JCGT 2017): the same headline as Flutter `Text` (glyph
/// atlas) and as `SlugText` (per-pixel coverage from the outline, in a
/// fragment shader), inside identical transforms. Zoom 1×–200×, tilt in 3D,
/// and inspect bands, curves and pixels.
class SlugLabSlide extends StatefulWidget {
  const SlugLabSlide({super.key});

  @override
  State<SlugLabSlide> createState() => _SlugLabSlideState();
}

const _panelTop = 60.0;
const _panelH = 488.0;
const _panelW = 716.0;
const _gap = 40.0;
const _panelSize = Size(_panelW, _panelH);
const _fontSize = 120.0;
const _maxZoom = 200.0;
const _perspective = 0.0011;
const _loupeD = 196.0;
const _loupeZoom = 8.0;
const _cycle = 18.0; // seconds per auto zoom cycle

enum _Headline { mixed, kana, latin }

class _SlugLabSlideState extends State<SlugLabSlide> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _time = 0;
  double _autoStart = 0;

  SlugFont? _sg;
  SlugFont? _jp;
  SlugAtlas? _atlas;

  _Headline _headline = _Headline.mixed;
  bool _auto = true;
  bool _bands = false;
  bool _curves = false;
  bool _pixels = false;

  // Content point q (relative to the panel centre c) lands, before the
  // tilt, at c + _pan + _zoom * q.
  double _zoom = 1;
  Offset _pan = Offset.zero;
  double _rx = 0;
  double _ry = 0;
  Offset? _focus; // pre-tilt panel point the slider zooms about
  Offset? _target; // cached _autoTarget
  Offset _loupe = const Offset(_panelW * 0.36, _panelH * 0.46);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    SlugFont.load('assets/fonts/SpaceGrotesk.ttf').then((f) {
      if (!mounted) return;
      setState(() {
        _sg = f;
        _target = null;
      });
    });
    SlugFont.load('assets/fonts/NotoSansJP-case.ttf').then((f) {
      if (!mounted) return;
      setState(() {
        _jp = f;
        _target = null;
      });
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration d) {
    _time = d.inMicroseconds / 1e6;
    if (!_auto) return;
    // Continuous zoom 1× → 200× → 1× into a detail, while the page tilts.
    final t = (_time - _autoStart) / _cycle;
    final u = 0.5 - 0.5 * math.cos(2 * math.pi * t);
    final z = math.pow(_maxZoom, math.pow(u, 1.25)).toDouble();
    final q = _autoTarget();
    setState(() {
      _zoom = z;
      _pan = q * (1 - z);
      _ry = 0.62 * math.sin(2 * math.pi * t * 0.5);
      _rx = 0.34 + 0.2 * math.sin(2 * math.pi * t * 0.75 + 1);
      _focus = null;
    });
  }

  /// A detail worth zooming into, relative to the panel centre.
  Offset _autoTarget() => _target ??= _computeTarget();

  Offset _computeTarget() {
    final spans = _spans();
    if (spans == null) return Offset.zero;
    final tp = TextPainter(
      text: TextSpan(children: [for (final s in spans) TextSpan(text: s.text, style: s.style)]),
      textDirection: TextDirection.ltr,
    )..layout();
    final first = tp.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1));
    final size = tp.size;
    tp.dispose();
    if (first.isEmpty) return Offset.zero;
    final b = first.first.toRect();
    final (fx, fy) = switch (_headline) {
      _Headline.mixed => (0.30, 0.33), // 直: stroke junctions
      _Headline.kana => (0.62, 0.40), // ほ: the loop
      _Headline.latin => (0.22, 0.30), // S: the spine
    };
    return Offset(b.left + fx * b.width - size.width / 2, b.top + fy * b.height - size.height / 2);
  }

  void _stopAuto() {
    if (_auto) setState(() => _auto = false);
  }

  void _toggleAuto() {
    setState(() {
      _auto = !_auto;
      if (_auto) {
        // Resume from a matching phase: find t with the current zoom.
        final u = _zoom <= 1 ? 0.0 : math.pow(math.log(_zoom) / math.log(_maxZoom), 1 / 1.25).toDouble();
        final t = math.acos((1 - 2 * u.clamp(0.0, 1.0))) / (2 * math.pi);
        _autoStart = _time - t * _cycle;
      }
    });
  }

  void _reset() {
    setState(() {
      _auto = false;
      _zoom = 1;
      _pan = Offset.zero;
      _rx = 0;
      _ry = 0;
      _focus = null;
    });
  }

  List<SlugSpan>? _spans() {
    final sg = _sg, jp = _jp;
    if (sg == null || jp == null) return null;
    final latin = TextStyle(
      fontFamily: BP.display,
      fontSize: _fontSize,
      color: BP.ink,
      height: 1.2,
      // The outlines are the font's default instance: pin the axes to it.
      fontVariations: [for (final e in sg.defaultAxes.entries) ui.FontVariation(e.key, e.value)],
    );
    const cjk = TextStyle(fontFamily: 'CaseJP', fontSize: _fontSize, color: BP.ink, height: 1.2);
    return switch (_headline) {
      _Headline.mixed => [SlugSpan('直', font: jp, style: cjk), SlugSpan(' Text', font: sg, style: latin)],
      _Headline.kana => [SlugSpan('ほんもの', font: jp, style: cjk)],
      _Headline.latin => [SlugSpan('Slug', font: sg, style: latin)],
    };
  }

  // ── transform ──────────────────────────────────────────────────────────

  static const _c = Offset(_panelW / 2, _panelH / 2);

  Matrix4 get _tilt => Matrix4.translationValues(_c.dx, _c.dy, 0)
    ..multiply(Matrix4.identity()..setEntry(3, 2, _perspective))
    ..multiply(Matrix4.rotationX(_rx))
    ..multiply(Matrix4.rotationY(_ry))
    ..multiply(Matrix4.translationValues(-_c.dx, -_c.dy, 0));

  Matrix4 get _matrix => _tilt
    ..multiply(Matrix4.translationValues(_c.dx + _pan.dx, _c.dy + _pan.dy, 0))
    ..multiply(Matrix4.diagonal3Values(_zoom, _zoom, 1))
    ..multiply(Matrix4.translationValues(-_c.dx, -_c.dy, 0));

  /// Panel point (after tilt) → the pre-tilt plane, by inverting the
  /// homography of the tilt on z = 0.
  Offset _untilt(Offset s) {
    final m = _tilt.storage;
    final a = m[0], b = m[4], c = m[12], d = m[1], e = m[5], f = m[13], g = m[3], h = m[7], i = m[15];
    // Inverse of [[a b c][d e f][g h i]] applied to (s, 1).
    final x = (e * i - f * h) * s.dx + (c * h - b * i) * s.dy + (b * f - c * e);
    final y = (f * g - d * i) * s.dx + (a * i - c * g) * s.dy + (c * d - a * f);
    final w = (d * h - e * g) * s.dx + (b * g - a * h) * s.dy + (a * e - b * d);
    return w.abs() < 1e-9 ? s : Offset(x / w, y / w);
  }

  void _zoomAbout(Offset pre, double z) {
    z = z.clamp(1.0, _maxZoom);
    final q = (pre - _c - _pan) / _zoom;
    setState(() {
      _zoom = z;
      _pan = z <= 1.0001 ? Offset.zero : pre - _c - q * z;
    });
  }

  void _onDrag(DragUpdateDetails d) {
    _stopAuto();
    setState(() {
      _ry = (_ry + d.delta.dx * 0.006).clamp(-1.25, 1.25);
      _rx = (_rx - d.delta.dy * 0.006).clamp(-1.25, 1.25);
    });
  }

  void _onScroll(PointerSignalEvent e, Offset local) {
    if (e is! PointerScrollEvent) return;
    _stopAuto();
    _zoomAbout(_untilt(local), _zoom * math.exp(-e.scrollDelta.dy * 0.0025));
  }

  void _onPinch(PointerPanZoomUpdateEvent e, Offset local) {
    if (e.scale == 1) return;
    _stopAuto();
    _zoomAbout(_untilt(local), _zoom * math.pow(e.scale, 0.08));
  }

  void _onTap(Offset local) {
    _stopAuto();
    setState(() => _focus = _untilt(local));
  }

  void _onSlider(double logZ) {
    _stopAuto();
    _zoomAbout(_focus ?? _c + _pan + _autoTarget() * _zoom, math.exp(logZ));
  }

  /// Approximate device pixels per em (ignores perspective foreshortening).
  double _devicePxPerEm(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final deck = math.min(screen.width / BP.canvas.width, screen.height / BP.canvas.height);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return _fontSize * _zoom * deck * dpr;
  }

  // ── build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final spans = _spans();
    final m = _matrix;
    final pxEm = _devicePxPerEm(context);
    final atlas = _atlas;
    return SlideFrame(
      title: 'Slug · GPU text',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            child: Row(
              children: [
                BpSegmented<_Headline>(
                  values: _Headline.values,
                  selected: _headline,
                  size: 14,
                  labelOf: (h) => switch (h) {
                    _Headline.mixed => '直 Text',
                    _Headline.kana => 'ほんもの',
                    _Headline.latin => 'Slug',
                  },
                  onChanged: (h) => setState(() {
                    _headline = h;
                    _target = null;
                    _focus = null;
                  }),
                ),
                const SizedBox(width: 28),
                BpButton(label: 'auto', size: 14, color: BP.amber, selected: _auto, onTap: _toggleAuto),
                const SizedBox(width: 8),
                BpButton(label: 'bands', size: 14, selected: _bands, onTap: () => setState(() => _bands = !_bands)),
                const SizedBox(width: 8),
                BpButton(label: 'curves', size: 14, selected: _curves, onTap: () => setState(() => _curves = !_curves)),
                const SizedBox(width: 8),
                BpButton(label: 'pixels', size: 14, selected: _pixels, onTap: () => setState(() => _pixels = !_pixels)),
                const Spacer(),
                BpSlider(
                  label: 'zoom',
                  value: math.log(_zoom),
                  max: math.log(_maxZoom),
                  width: 280,
                  ticks: 8,
                  color: BP.amber,
                  onChanged: _onSlider,
                  format: (v) => '×${math.exp(v).toStringAsFixed(math.exp(v) < 10 ? 1 : 0)}',
                ),
              ],
            ),
          ),
          Positioned(left: 0, top: _panelTop, child: _panel(slug: false, spans: spans, m: m)),
          Positioned(left: _panelW + _gap, top: _panelTop, child: _panel(slug: true, spans: spans, m: m)),
          // What each side is doing.
          Positioned(
            left: 0,
            top: _panelTop + _panelH + 16,
            child: Row(
              children: [
                BpTag(pxEm > 250 ? 'glyph → path' : 'glyph → A8 atlas', color: BP.line),
                const SizedBox(width: 14),
                Text('≈ ${AnimatedCount.format(pxEm)} px/em', style: BT.mono(14, color: BP.inkDim)),
              ],
            ),
          ),
          Positioned(
            left: _panelW + _gap,
            top: _panelTop + _panelH + 16,
            child: Row(
              children: [
                const BpTag('curves → coverage / px', color: BP.amber),
                const SizedBox(width: 14),
                if (atlas != null)
                  Text(
                    '${atlas.curveCount} curves · ${atlas.bandCount} bands · '
                    '${(atlas.data.byteSize / 1024).toStringAsFixed(0)} KB',
                    style: BT.mono(14, color: BP.inkDim),
                  ),
                if (_bands) ...[const SizedBox(width: 18), const _HeatLegend()],
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Row(
              children: [
                Text('drag · tilt   scroll · zoom   tap · focus   2× tap · reset',
                    style: BT.mono(12, color: BP.inkFaint)),
                const Spacer(),
                Text('Slug — E. Lengyel, JCGT 2017 · patent dedicated to public domain 2026',
                    style: BT.mono(12, color: BP.inkDim)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel({required bool slug, required List<SlugSpan>? spans, required Matrix4 m}) {
    Widget content = const SizedBox.shrink();
    if (spans != null) {
      if (slug) {
        content = SlugText(
          spans,
          heatMap: _bands,
          showBands: _bands,
          showCurves: _curves,
          debugColors: _debugColors,
          onAtlas: (a) {
            if (mounted) setState(() => _atlas = a);
          },
        );
      } else {
        content = Stack(
          alignment: Alignment.center,
          children: [
            RichText(
              textScaler: TextScaler.noScaling,
              text: TextSpan(children: [for (final s in spans) TextSpan(text: s.text, style: s.style)]),
            ),
            // The true outline over the atlas text: same curves, no fill.
            if (_curves)
              SlugText(
                [
                  for (final s in spans)
                    SlugSpan(s.text, font: s.font, style: s.style.copyWith(color: const Color(0x00000000))),
                ],
                showCurves: true,
                debugColors: _debugColors,
              ),
          ],
        );
      }
    }
    final focus = _focus;
    return SizedBox.fromSize(
      size: _panelSize,
      child: BpPanel(
        label: slug ? 'SlugText · shader' : 'Text · Flutter',
        color: slug ? BP.amber : BP.lineDim,
        padding: EdgeInsets.zero,
        child: ClipRect(
          child: Listener(
            onPointerSignal: (e) => _onScroll(e, e.localPosition),
            onPointerPanZoomUpdate: (e) => _onPinch(e, e.localPosition),
            child: MouseRegion(
              onHover: _pixels ? (e) => setState(() => _loupe = e.localPosition) : null,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) {
                  if (_pixels) setState(() => _loupe = d.localPosition);
                  _onDrag(d);
                },
                onTapUp: (d) => _onTap(d.localPosition),
                onDoubleTap: _reset,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Transform(
                        transform: m,
                        child: SizedBox.fromSize(size: _panelSize, child: Center(child: content)),
                      ),
                    ),
                    if (focus != null && !_auto)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(painter: _FocusPainter(MatrixUtils.transformPoint(_tilt, focus))),
                        ),
                      ),
                    if (_pixels)
                      Positioned(
                        left: _loupe.dx - _loupeD / 2,
                        top: _loupe.dy - _loupeD / 2,
                        child: const IgnorePointer(child: _Loupe()),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _debugColors = SlugDebugColors(
  curve: BP.amber,
  control: BP.line,
  band: Color(0x995FB8FF),
);

/// Heat map legend: curves tested per pixel (shader: 0 → 32).
class _HeatLegend extends StatelessWidget {
  const _HeatLegend();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('0', style: BT.mono(12, color: BP.inkDim)),
      const SizedBox(width: 6),
      Container(
        width: 90,
        height: 8,
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF2E6DA8), Color(0xFFFFC66D), Color(0xFFFF6F7D)]),
        ),
      ),
      const SizedBox(width: 6),
      Text('32 curves', style: BT.mono(12, color: BP.inkDim)),
    ],
  );
}

class _FocusPainter extends CustomPainter {
  _FocusPainter(this.p);

  final Offset p;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = BP.amber
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(p, 9, paint);
    for (final d in const [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)]) {
      canvas.drawLine(p + d * 13, p + d * 20, paint);
    }
  }

  @override
  bool shouldRepaint(_FocusPainter old) => old.p != p;
}

/// A round loupe that shows the device pixels behind it, magnified with
/// nearest-neighbour sampling (no smoothing), so anti-aliasing is visible.
class _Loupe extends StatelessWidget {
  const _Loupe();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _loupeD,
    height: _loupeD,
    child: Stack(
      children: [
        const ClipOval(child: _Magnify(child: SizedBox.expand())),
        Positioned.fill(child: CustomPaint(painter: _LoupeRim())),
        Positioned(
          right: 18,
          bottom: 14,
          child: Text('×${_loupeZoom.toInt()}', style: BT.mono(13, color: BP.amber)),
        ),
      ],
    ),
  );
}

class _LoupeRim extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(
      c,
      size.width / 2 - 1,
      Paint()
        ..color = BP.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final tick = Paint()
      ..color = BP.amber.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    for (final d in const [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)]) {
      canvas.drawLine(c + d * (size.width / 2 - 12), c + d * (size.width / 2 - 2), tick);
    }
  }

  @override
  bool shouldRepaint(_LoupeRim old) => false;
}

class _Magnify extends SingleChildRenderObjectWidget {
  const _Magnify({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMagnify();
}

class _RenderMagnify extends RenderProxyBox {
  @override
  bool get alwaysNeedsCompositing => true;

  @override
  BackdropFilterLayer? get layer => super.layer as BackdropFilterLayer?;

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = size.center(offset);
    final m = Matrix4.translationValues(c.dx * (1 - _loupeZoom), c.dy * (1 - _loupeZoom), 0)
      ..scaleByDouble(_loupeZoom, _loupeZoom, 1, 1);
    final filter = ui.ImageFilter.matrix(m.storage, filterQuality: FilterQuality.none);
    (layer ??= BackdropFilterLayer()).filter = filter;
    context.pushLayer(layer!, super.paint, offset);
  }
}
