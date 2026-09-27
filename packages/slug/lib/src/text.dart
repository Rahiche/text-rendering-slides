import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import 'encoder.dart';
import 'font.dart';
import 'painter.dart';

/// A run of text drawn with [font]'s outlines.
///
/// [style] lays the run out (through a real paragraph, so advances and
/// kerning match Flutter's `Text`); its `fontFamily` should name the same
/// font file as [font]. `fontSize` and `color` are used for drawing.
@immutable
class SlugSpan {
  const SlugSpan(this.text, {required this.font, required this.style});

  final String text;
  final SlugFont font;
  final TextStyle style;

  @override
  bool operator ==(Object other) =>
      other is SlugSpan && other.text == text && other.font == font && other.style == style;

  @override
  int get hashCode => Object.hash(text, font, style);
}

/// Colours for [SlugText]'s debug overlays.
@immutable
class SlugDebugColors {
  const SlugDebugColors({
    this.curve = const Color(0xFFFFC66D),
    this.control = const Color(0xFF5FB8FF),
    this.band = const Color(0x665FB8FF),
  });

  final Color curve;
  final Color control;
  final Color band;
}

/// Text drawn with the Slug algorithm: every glyph is one quad whose pixels
/// compute their coverage from the outline, so it stays sharp under any
/// scale, rotation or perspective (no glyph atlas, no re-rasterization).
///
/// Glyph placement comes from a [TextPainter] laid out with the spans'
/// styles (one glyph per code point: no ligatures, marks or RTL shaping).
class SlugText extends StatefulWidget {
  const SlugText(
    this.spans, {
    super.key,
    this.textAlign = TextAlign.start,
    this.textScaler = TextScaler.noScaling,
    this.heatMap = false,
    this.showCurves = false,
    this.showBands = false,
    this.dilate = true,
    this.debugColors = const SlugDebugColors(),
    this.onAtlas,
  });

  final List<SlugSpan> spans;
  final TextAlign textAlign;
  final TextScaler textScaler;

  /// Colour each pixel by the number of curves its two rays tested.
  final bool heatMap;

  /// Overlay the quadratic curves and their control points.
  final bool showCurves;

  /// Overlay each glyph's quad and band boundaries.
  final bool showBands;

  /// Grow each quad by half a device pixel (dynamic dilation), so edge
  /// pixels on the glyph box get anti-aliased.
  final bool dilate;
  final SlugDebugColors debugColors;

  /// Called when the glyph data texture for [spans] is ready.
  final ValueChanged<SlugAtlas>? onAtlas;

  @override
  State<SlugText> createState() => _SlugTextState();
}

class _SlugTextState extends State<SlugText> {
  ui.FragmentProgram? _program;
  SlugAtlas? _atlas;
  SlugPainter? _painter;
  String? _key;

  @override
  void initState() {
    super.initState();
    _program = SlugShader.loaded;
    if (_program == null) {
      SlugShader.load().then((p) {
        if (!mounted) return;
        setState(() {
          _program = p;
          _rebuildPainter();
        });
      });
    }
    _ensureAtlas();
  }

  @override
  void didUpdateWidget(SlugText old) {
    super.didUpdateWidget(old);
    _ensureAtlas();
  }

  String _keyOf(List<SlugSpan> spans) {
    final glyphs = <String>{
      for (final s in spans)
        for (final cp in s.text.runes) '${s.font.id}:${s.font.glyphId(cp)}',
    }.toList()..sort();
    return glyphs.join(',');
  }

  void _ensureAtlas() {
    final key = _keyOf(widget.spans);
    if (key == _key) return;
    _key = key;
    SlugAtlas.forText([for (final s in widget.spans) (s.font, s.text)]).then((atlas) {
      if (!mounted || key != _key) {
        atlas.dispose();
        return;
      }
      final oldAtlas = _atlas;
      setState(() {
        _atlas = atlas;
        _rebuildPainter();
      });
      widget.onAtlas?.call(atlas);
      if (oldAtlas != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => oldAtlas.dispose());
      }
    });
  }

  void _rebuildPainter() {
    final program = _program, atlas = _atlas;
    if (program == null || atlas == null) return;
    final old = _painter;
    _painter = SlugPainter(program, atlas);
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    _painter?.dispose();
    _atlas?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SlugTextLeaf(
    spans: widget.spans,
    painter: _painter,
    textAlign: widget.textAlign,
    textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
    textScaler: widget.textScaler,
    devicePixelRatio:
        MediaQuery.maybeDevicePixelRatioOf(context) ?? View.of(context).devicePixelRatio,
    heatMap: widget.heatMap,
    showCurves: widget.showCurves,
    showBands: widget.showBands,
    dilate: widget.dilate,
    colors: widget.debugColors,
  );
}

class _SlugTextLeaf extends LeafRenderObjectWidget {
  const _SlugTextLeaf({
    required this.spans,
    required this.painter,
    required this.textAlign,
    required this.textDirection,
    required this.textScaler,
    required this.devicePixelRatio,
    required this.heatMap,
    required this.showCurves,
    required this.showBands,
    required this.dilate,
    required this.colors,
  });

  final List<SlugSpan> spans;
  final SlugPainter? painter;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final double devicePixelRatio;
  final bool heatMap, showCurves, showBands, dilate;
  final SlugDebugColors colors;

  @override
  RenderSlugText createRenderObject(BuildContext context) => RenderSlugText(
    spans: spans,
    painter: painter,
    textAlign: textAlign,
    textDirection: textDirection,
    textScaler: textScaler,
    devicePixelRatio: devicePixelRatio,
  )..setDebug(heatMap: heatMap, showCurves: showCurves, showBands: showBands, dilate: dilate, colors: colors);

  @override
  void updateRenderObject(BuildContext context, RenderSlugText r) {
    r
      ..spans = spans
      ..painter = painter
      ..textAlign = textAlign
      ..textDirection = textDirection
      ..textScaler = textScaler
      ..devicePixelRatio = devicePixelRatio
      ..setDebug(heatMap: heatMap, showCurves: showCurves, showBands: showBands, dilate: dilate, colors: colors);
  }
}

class _Placed {
  _Placed(this.font, this.gid, this.pen, this.scale, this.color);

  final SlugFont font;
  final int gid;
  final Offset pen; // box-local, on the baseline
  final double scale; // local px per font unit
  final Color color;
}

/// Lays text out with a [TextPainter] and draws each glyph with [SlugPainter].
class RenderSlugText extends RenderBox {
  RenderSlugText({
    required List<SlugSpan> spans,
    required SlugPainter? painter,
    required TextAlign textAlign,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required double devicePixelRatio,
  }) : _spans = spans,
       _painter = painter,
       _devicePixelRatio = devicePixelRatio,
       _tp = TextPainter(textAlign: textAlign, textDirection: textDirection, textScaler: textScaler);

  final TextPainter _tp;
  List<_Placed> _placed = const [];

  List<SlugSpan> get spans => _spans;
  List<SlugSpan> _spans;
  set spans(List<SlugSpan> v) {
    if (listEquals(v, _spans)) return;
    _spans = v;
    markNeedsLayout();
  }

  SlugPainter? get painter => _painter;
  SlugPainter? _painter;
  set painter(SlugPainter? v) {
    if (v == _painter) return;
    _painter = v;
    markNeedsPaint();
  }

  set textAlign(TextAlign v) {
    if (v == _tp.textAlign) return;
    _tp.textAlign = v;
    markNeedsLayout();
  }

  set textDirection(TextDirection v) {
    if (v == _tp.textDirection) return;
    _tp.textDirection = v;
    markNeedsLayout();
  }

  set textScaler(TextScaler v) {
    if (v == _tp.textScaler) return;
    _tp.textScaler = v;
    markNeedsLayout();
  }

  double _devicePixelRatio;
  set devicePixelRatio(double v) {
    if (v == _devicePixelRatio) return;
    _devicePixelRatio = v;
    markNeedsPaint();
  }

  bool _heat = false, _curves = false, _bands = false, _dilate = true;
  SlugDebugColors _colors = const SlugDebugColors();

  void setDebug({
    required bool heatMap,
    required bool showCurves,
    required bool showBands,
    required bool dilate,
    required SlugDebugColors colors,
  }) {
    if (heatMap == _heat &&
        showCurves == _curves &&
        showBands == _bands &&
        dilate == _dilate &&
        colors == _colors) {
      return;
    }
    _heat = heatMap;
    _curves = showCurves;
    _bands = showBands;
    _dilate = dilate;
    _colors = colors;
    markNeedsPaint();
  }

  /// The outlines are the font's default instance: pin variable axes to it
  /// (otherwise e.g. FontWeight.normal can pick a heavier, wider instance).
  static TextStyle _layoutStyle(SlugSpan s) {
    if (s.style.fontVariations != null || s.font.defaultAxes.isEmpty) return s.style;
    return s.style.copyWith(
      fontVariations: [for (final e in s.font.defaultAxes.entries) ui.FontVariation(e.key, e.value)],
    );
  }

  void _layoutText(double maxWidth) {
    _tp.text = TextSpan(children: [for (final s in _spans) TextSpan(text: s.text, style: _layoutStyle(s))]);
    _tp.layout(maxWidth: maxWidth);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    _layoutText(constraints.maxWidth);
    return constraints.constrain(_tp.size);
  }

  @override
  void performLayout() {
    _layoutText(constraints.maxWidth);
    size = constraints.constrain(_tp.size);
    final lines = _tp.computeLineMetrics();
    final placed = <_Placed>[];
    var offset = 0;
    for (final s in _spans) {
      final fontSize = _tp.textScaler.scale(s.style.fontSize ?? 14);
      final scale = fontSize / s.font.unitsPerEm;
      final color = s.style.color ?? const Color(0xFF000000);
      for (final cp in s.text.runes) {
        final len = cp > 0xFFFF ? 2 : 1;
        final boxes = _tp.getBoxesForSelection(
          TextSelection(baseOffset: offset, extentOffset: offset + len),
        );
        offset += len;
        if (boxes.isEmpty || lines.isEmpty) continue;
        final box = boxes.first;
        final cy = (box.top + box.bottom) / 2;
        // (No firstWhere/orElse: on the web the list's runtime element type
        // is an engine subtype, so a covariant orElse closure throws.)
        var line = lines.first;
        for (final l in lines) {
          if (cy >= l.baseline - l.ascent - 0.5 && cy <= l.baseline + l.descent + 0.5) {
            line = l;
            break;
          }
        }
        final x = box.direction == TextDirection.rtl ? box.right - s.font.advance(s.font.glyphId(cp)) * scale : box.left;
        placed.add(_Placed(s.font, s.font.glyphId(cp), Offset(x, line.baseline), scale, color));
      }
    }
    _placed = placed;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final p = _painter;
    if (p == null || _placed.isEmpty) return;
    final canvas = context.canvas;
    // Canvas coordinates → device pixels: (c - offset) → global → × dpr.
    final m = Matrix4.diagonal3Values(_devicePixelRatio, _devicePixelRatio, 1)
      ..multiply(getTransformTo(null))
      ..multiply(Matrix4.translationValues(-offset.dx, -offset.dy, 0));
    final toDevice = m.storage;
    final quads = <(Rect, SlugGlyphData, _Placed)>[];
    for (final g in _placed) {
      final data = p.atlas.glyph(g.font, g.gid);
      if (data == null) continue;
      final quad = p.drawGlyph(
        canvas,
        data,
        pen: offset + g.pen,
        scale: g.scale,
        toDevice: toDevice,
        color: g.color,
        heat: _heat,
        dilate: _dilate,
      );
      quads.add((quad, data, g));
    }
    if (_bands) _paintBands(canvas, offset, quads);
    if (_curves) _paintCurves(canvas, offset, toDevice, quads);
  }

  void _paintBands(Canvas canvas, Offset offset, List<(Rect, SlugGlyphData, _Placed)> quads) {
    final hair = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0
      ..color = _colors.band;
    for (final (quad, d, g) in quads) {
      canvas.drawRect(quad, hair);
      final pen = offset + g.pen;
      final b = d.bounds;
      for (final y in d.hBandEdges.skip(1).take(d.hBandCount - 1)) {
        final ly = pen.dy - y * g.scale;
        canvas.drawLine(Offset(pen.dx + b.left * g.scale, ly), Offset(pen.dx + b.right * g.scale, ly), hair);
      }
      for (final x in d.vBandEdges.skip(1).take(d.vBandCount - 1)) {
        final lx = pen.dx + x * g.scale;
        canvas.drawLine(Offset(lx, pen.dy - b.top * g.scale), Offset(lx, pen.dy - b.bottom * g.scale), hair);
      }
    }
  }

  void _paintCurves(
    Canvas canvas,
    Offset offset,
    Float64List toDevice,
    List<(Rect, SlugGlyphData, _Placed)> quads,
  ) {
    final curve = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0
      ..color = _colors.curve;
    final poly = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0
      ..color = _colors.control.withValues(alpha: _colors.control.a * 0.6);
    final dot = Paint()..color = _colors.control;
    for (final (quad, d, g) in quads) {
      final pen = offset + g.pen;
      final q = d.quantum;
      Offset map(double gx, double gy) =>
          Offset(pen.dx + (d.originX + gx * q) * g.scale, pen.dy - (d.originY + gy * q) * g.scale);
      final c = quad.center;
      final r = 2.5 * slugLocalPerPixel(toDevice, c.dx, c.dy);
      final path = Path();
      final ctrl = Path();
      for (final k in d.curves) {
        final a = map(k.x1, k.y1), m = map(k.x2, k.y2), e = map(k.x3, k.y3);
        path
          ..moveTo(a.dx, a.dy)
          ..quadraticBezierTo(m.dx, m.dy, e.dx, e.dy);
        final isLine = k.x2 == k.x3 && k.y2 == k.y3;
        if (!isLine) {
          ctrl
            ..moveTo(a.dx, a.dy)
            ..lineTo(m.dx, m.dy)
            ..lineTo(e.dx, e.dy);
          canvas.drawCircle(m, r * 0.8, dot);
        }
        canvas.drawRect(Rect.fromCenter(center: a, width: 2 * r, height: 2 * r), dot);
      }
      canvas.drawPath(ctrl, poly);
      canvas.drawPath(path, curve);
    }
  }

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  void dispose() {
    _tp.dispose();
    super.dispose();
  }

  @visibleForTesting
  List<(Offset, double)> get debugPlacements => [for (final p in _placed) (p.pen, p.scale)];
}
