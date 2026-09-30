import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';

/// Rasterization: the glyph's outline over a pixel grid, and the pixels that
/// come out. Coverage is REAL: the glyph is drawn 12× supersampled into an
/// image and averaged per pixel (and per horizontal third for subpixel AA).
class RasterSlide extends StatefulWidget {
  const RasterSlide({super.key});

  @override
  State<RasterSlide> createState() => _RasterSlideState();
}

enum _Mode { aliased, grayscale, subpixel }

const _glyphs = ['a', 'g', 'ع', '字', '&'];

const _ss = 12; // supersampling per pixel edge
const _panelTop = 76.0;
const _panelH = 468.0;
const _panelW = 610.0;
const _leftPanel = Rect.fromLTWH(0, _panelTop, _panelW, _panelH);
const _rightPanel = Rect.fromLTWH(640, _panelTop, _panelW, _panelH);
const _colX = 1284.0;

// Subpixel stripe colors (R, G, B) drawn from the palette.
const _stripe = [BP.red, BP.green, BP.line];

class _RasterSlideState extends State<RasterSlide> with TickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final AnimationController _scan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  )..repeat();

  String _glyph = 'a';
  double _size = 16;
  _Mode _mode = _Mode.grayscale;
  _Raster? _r;

  bool _busy = false;
  bool _dirty = false;
  bool _sweepNext = true;
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    _request(sweep: true);
  }

  void _request({bool sweep = false}) {
    if (sweep) _sweepNext = true;
    if (_busy) {
      _dirty = true;
      return;
    }
    _run();
  }

  Future<void> _run() async {
    _busy = true;
    do {
      _dirty = false;
      final r = await _Raster.compute(_glyph, _size.round());
      if (!mounted) {
        r.dispose();
        return;
      }
      final old = _r;
      setState(() => _r = r);
      if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      if (_sweepNext) {
        _sweepNext = false;
        _sweep.forward(from: 0);
      }
    } while (_dirty && mounted);
    _busy = false;
  }

  void _setSize(double v) {
    final px = v.roundToDouble();
    if (px == _size) return;
    setState(() => _size = px);
    if (_sweep.isAnimating) _sweep.value = 1;
    _request();
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 260), () {
      if (mounted) _sweep.forward(from: 0);
    });
  }

  void _setGlyph(String g) {
    if (g == _glyph) return;
    setState(() => _glyph = g);
    _request(sweep: true);
  }

  void _setMode(_Mode m) {
    if (m == _mode) return;
    setState(() => _mode = m);
    _sweep.forward(from: 0);
  }

  @override
  void dispose() {
    _settle?.cancel();
    _sweep.dispose();
    _scan.dispose();
    _r?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideFrame(
      title: 'Rasterization',
      child: Stack(
        children: [
          Positioned.fromRect(
            rect: _leftPanel,
            child: const BpPanel(label: 'outline', child: SizedBox.expand()),
          ),
          Positioned.fromRect(
            rect: _rightPanel,
            child: BpPanel(label: _mode.name, color: BP.amber, child: const SizedBox.expand()),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _RasterPainter(r: _r, mode: _mode, sweep: _sweep, scan: _scan),
                ),
              ),
            ),
          ),
          // Controls
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            child: Row(
              children: [
                for (final g in _glyphs) ...[
                  _GlyphChip(glyph: g, selected: g == _glyph, onTap: () => _setGlyph(g)),
                  const SizedBox(width: 8),
                ],
                const SizedBox(width: 30),
                BpSegmented<_Mode>(
                  values: _Mode.values,
                  selected: _mode,
                  onChanged: _setMode,
                  color: BP.amber,
                  labelOf: (m) => m.name,
                ),
                const Spacer(),
                BpSlider(
                  label: 'px / em',
                  value: _size,
                  min: 8,
                  max: 48,
                  width: 300,
                  ticks: 8,
                  onChanged: _setSize,
                  format: (v) => '${v.round()} px',
                ),
              ],
            ),
          ),
          Positioned(
            left: _colX,
            top: _panelTop - 6,
            child: Text('actual size', style: BT.mono(14, color: BP.inkDim)),
          ),
          const Positioned(
            left: 0,
            bottom: 0,
            child: Row(
              children: [
                BpTag('Flutter / Impeller: grayscale AA', color: BP.green),
                SizedBox(width: 14),
                BpTag('macOS: subpixel off since 10.14', color: BP.inkDim),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlyphChip extends StatelessWidget {
  const _GlyphChip({required this.glyph, required this.selected, required this.onTap});

  final String glyph;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 56,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? BP.line.withValues(alpha: 0.16) : Colors.transparent,
          border: Border.all(color: selected ? BP.amber : BP.lineDim, width: selected ? 2 : 1),
        ),
        child: Text(glyph, style: BT.sample(26, color: selected ? BP.ink : BP.inkDim, height: 1.1)),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Real coverage
// ─────────────────────────────────────────────────────────────────────────────

class _Raster {
  _Raster._({
    required this.size,
    required this.cols,
    required this.rows,
    required this.cov,
    required this.cell,
    required this.glyphOrigin,
    required this.baseline,
    required this.outline,
    required this.engine,
    required this.covImage,
    required this.pixels,
    required this.previews,
  });

  final int size;
  final int cols;
  final int rows;

  /// Average coverage per pixel, row-major.
  final Float32List cov;

  /// Display size of one pixel in the big panels.
  final double cell;

  /// Where the text was painted, in pixel units relative to the cropped grid.
  final Offset glyphOrigin;
  final double baseline;

  final TextPainter outline;
  final TextPainter engine;
  final ui.Image covImage;
  final Map<_Mode, ui.Image> pixels;
  final Map<_Mode, ui.Image> previews;

  static Future<_Raster> compute(String glyph, int px) async {
    final style = BT.sample(px.toDouble(), color: const Color(0xFFFFFFFF));
    final tp = TextPainter(text: TextSpan(text: glyph, style: style), textDirection: TextDirection.ltr)..layout();
    const pad = 2;
    final fullCols = tp.width.ceil() + pad * 2;
    final fullRows = tp.height.ceil() + pad * 2;
    final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic) + pad;

    // Draw the glyph 12× larger (same layout, scaled canvas) and read it back.
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.scale(_ss.toDouble());
    tp.paint(canvas, const Offset(pad * 1.0, pad * 1.0));
    tp.dispose();
    final pic = rec.endRecording();
    final img = await pic.toImage(fullCols * _ss, fullRows * _ss);
    pic.dispose();
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final w = img.width;
    img.dispose();
    final bytes = data!.buffer.asUint8List();

    // Sum alpha per pixel third.
    final thirdsFull = Float32List(fullCols * fullRows * 3);
    for (var y = 0; y < fullRows * _ss; y++) {
      final rowBase = (y ~/ _ss) * fullCols;
      final line = y * w * 4 + 3;
      for (var x = 0; x < fullCols * _ss; x++) {
        final a = bytes[line + x * 4];
        if (a == 0) continue;
        thirdsFull[(rowBase + x ~/ _ss) * 3 + (x % _ss) ~/ (_ss ~/ 3)] += a;
      }
    }
    const norm = 255.0 * _ss * (_ss ~/ 3);
    for (var i = 0; i < thirdsFull.length; i++) {
      thirdsFull[i] = thirdsFull[i] / norm;
    }

    // Crop to the ink, keeping one empty pixel around it.
    var r0 = fullRows, r1 = -1, c0 = fullCols, c1 = -1;
    for (var r = 0; r < fullRows; r++) {
      for (var c = 0; c < fullCols; c++) {
        final i = (r * fullCols + c) * 3;
        if (thirdsFull[i] + thirdsFull[i + 1] + thirdsFull[i + 2] > 0.003) {
          r0 = math.min(r0, r);
          r1 = math.max(r1, r);
          c0 = math.min(c0, c);
          c1 = math.max(c1, c);
        }
      }
    }
    if (r1 < 0) {
      r0 = 0;
      r1 = fullRows - 1;
      c0 = 0;
      c1 = fullCols - 1;
    }
    r0 = math.max(0, r0 - 1);
    c0 = math.max(0, c0 - 1);
    r1 = math.min(fullRows - 1, r1 + 1);
    c1 = math.min(fullCols - 1, c1 + 1);
    final cols = c1 - c0 + 1;
    final rows = r1 - r0 + 1;
    final cov = Float32List(cols * rows);
    final thirds = Float32List(cols * rows * 3);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final src = ((r + r0) * fullCols + (c + c0)) * 3;
        final dst = (r * cols + c) * 3;
        var sum = 0.0;
        for (var k = 0; k < 3; k++) {
          final v = thirdsFull[src + k].clamp(0.0, 1.0);
          thirds[dst + k] = v;
          sum += v;
        }
        cov[r * cols + c] = sum / 3;
      }
    }

    final inner = _leftPanel.deflate(28);
    final cell = math.min(inner.width / cols, inner.height / rows);

    final outline = TextPainter(
      text: TextSpan(
        text: glyph,
        style: BT.sample(px.toDouble()).copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6 / cell
            ..color = BP.line,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final engine = TextPainter(
      text: TextSpan(text: glyph, style: BT.sample(px.toDouble(), color: BP.ink)),
      textDirection: TextDirection.ltr,
    )..layout();

    // Opaque images (so premultiplication never matters), drawn with nearest
    // sampling: one texel per pixel (or per subpixel stripe).
    final covImage = await _image(cols, rows, (i, out) {
      _mix(out, BP.panel, BP.line, cov[i] * 0.22);
    });
    final pixels = <_Mode, ui.Image>{
      _Mode.aliased: await _image(cols, rows, (i, out) => _mix(out, BP.bg, BP.ink, cov[i] >= 0.5 ? 1 : 0)),
      _Mode.grayscale: await _image(cols, rows, (i, out) => _mix(out, BP.bg, BP.ink, cov[i])),
      _Mode.subpixel: await _image(cols * 3, rows, (i, out) {
        final k = i % 3;
        _mix(out, BP.bg, _stripe[k], thirds[i]);
      }),
    };
    // Actual-size previews: true per-channel coverage for subpixel.
    final previews = <_Mode, ui.Image>{
      _Mode.aliased: await _image(cols, rows, (i, out) => _mix(out, BP.paper, BP.ink, cov[i] >= 0.5 ? 1 : 0)),
      _Mode.grayscale: await _image(cols, rows, (i, out) => _mix(out, BP.paper, BP.ink, cov[i])),
      _Mode.subpixel: await _image(cols, rows, (i, out) {
        const bg = BP.paper;
        const ink = BP.ink;
        out[0] = _ch(bg.r, ink.r, thirds[i * 3]);
        out[1] = _ch(bg.g, ink.g, thirds[i * 3 + 1]);
        out[2] = _ch(bg.b, ink.b, thirds[i * 3 + 2]);
        out[3] = 255;
      }),
    };

    return _Raster._(
      size: px,
      cols: cols,
      rows: rows,
      cov: cov,
      cell: cell,
      glyphOrigin: Offset(pad - c0 * 1.0, pad - r0 * 1.0),
      baseline: baseline - r0,
      outline: outline,
      engine: engine,
      covImage: covImage,
      pixels: pixels,
      previews: previews,
    );
  }

  static int _ch(double a, double b, double t) => ((a + (b - a) * t.clamp(0.0, 1.0)) * 255).round().clamp(0, 255);

  static void _mix(Uint8List out, Color bg, Color ink, double t) {
    out[0] = _ch(bg.r, ink.r, t);
    out[1] = _ch(bg.g, ink.g, t);
    out[2] = _ch(bg.b, ink.b, t);
    out[3] = 255;
  }

  static Future<ui.Image> _image(int w, int h, void Function(int i, Uint8List out) fill) {
    final buf = Uint8List(w * h * 4);
    final px = Uint8List(4);
    for (var i = 0; i < w * h; i++) {
      fill(i, px);
      buf.setRange(i * 4, i * 4 + 4, px);
    }
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(buf, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

  void dispose() {
    outline.dispose();
    engine.dispose();
    covImage.dispose();
    for (final i in [...pixels.values, ...previews.values]) {
      i.dispose();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────────────────

class _RasterPainter extends CustomPainter {
  _RasterPainter({required this.r, required this.mode, required this.sweep, required this.scan})
    : super(repaint: Listenable.merge([sweep, scan]));

  final _Raster? r;
  final _Mode mode;
  final Animation<double> sweep;
  final Animation<double> scan;

  @override
  void paint(Canvas canvas, Size size) {
    final r = this.r;
    if (r == null) return;
    final cell = r.cell;
    final gw = r.cols * cell;
    final gh = r.rows * cell;
    final lo = _leftPanel.center - Offset(gw / 2, gh / 2);
    final ro = _rightPanel.center - Offset(gw / 2, gh / 2);
    final lg = lo & Size(gw, gh);
    final rg = ro & Size(gw, gh);
    final nearest = Paint()..filterQuality = FilterQuality.none;
    final beam = scan.value * (r.rows + 6) - 3;

    // ── Left: coverage tint, grid, baseline, outline ──
    canvas.drawImageRect(r.covImage, Rect.fromLTWH(0, 0, r.cols * 1.0, r.rows * 1.0), lg, nearest);
    _grid(canvas, lg, r, BP.lineFaint);
    _beamBand(canvas, lg, beam, cell);
    final by = lo.dy + r.baseline * cell;
    canvas.drawPath(
      dashPath(Path()
        ..moveTo(_leftPanel.left + 12, by)
        ..lineTo(_leftPanel.right - 12, by), dash: 8, gap: 5),
      Paint()
        ..color = BP.amber.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke,
    );
    _text(canvas, 'baseline', BT.mono(11, color: BP.amber), Offset(_leftPanel.left + 14, by - 16));
    canvas.save();
    canvas.clipRect(_leftPanel.deflate(2));
    canvas.translate(lo.dx + r.glyphOrigin.dx * cell, lo.dy + r.glyphOrigin.dy * cell);
    canvas.scale(cell);
    r.outline.paint(canvas, Offset.zero);
    canvas.restore();

    // Coverage values ride the beam.
    if (cell >= 22) {
      final fs = math.min(12.0, cell * 0.34);
      for (var row = beam.floor(); row <= beam.ceil(); row++) {
        if (row < 0 || row >= r.rows) continue;
        final a = (1 - (row - beam).abs()).clamp(0.0, 1.0);
        for (var c = 0; c < r.cols; c++) {
          final v = r.cov[row * r.cols + c];
          if (v < 0.01) continue;
          _text(
            canvas,
            (v * 100).round().toString(),
            BT.mono(fs, color: BP.amber.withValues(alpha: a)),
            Offset(lo.dx + (c + 0.5) * cell, lo.dy + (row + 0.5) * cell),
            center: true,
          );
        }
      }
    }

    // ── Right: the pixels, revealed by a sweeping scanline ──
    canvas.drawRect(rg, Paint()..color = BP.bg);
    final sw = Curves.easeInOutCubic.transform(sweep.value);
    final revealRows = sw >= 1 ? r.rows.toDouble() : (sw * r.rows).floorToDouble();
    final img = r.pixels[mode]!;
    if (revealRows > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(rg.left, rg.top, rg.width, revealRows * cell));
      canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width * 1.0, img.height * 1.0), rg, nearest);
      canvas.restore();
    }
    _grid(canvas, rg, r, BP.gridMajor);
    _beamBand(canvas, rg, beam, cell);
    if (sw < 1) {
      final y = rg.top + sw * gh;
      canvas.drawRect(
        Rect.fromLTRB(rg.left - 10, y - 26, rg.right + 10, y),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [BP.amber.withValues(alpha: 0), BP.amber.withValues(alpha: 0.22)],
          ).createShader(Rect.fromLTRB(rg.left, y - 26, rg.right, y)),
      );
      canvas.drawLine(
        Offset(rg.left - 14, y),
        Offset(rg.right + 14, y),
        Paint()
          ..color = BP.amber
          ..strokeWidth = 2,
      );
    }
    _text(canvas, '${r.cols} × ${r.rows} px', BT.mono(13, color: BP.inkDim), Offset(_rightPanel.left + 16, _rightPanel.bottom - 28));

    // ── Actual size ──
    final pv = r.previews[mode]!;
    var y = _panelTop + 30;
    _text(canvas, '1×', BT.mono(12, color: BP.inkFaint), Offset(_colX, y));
    y += 20;
    canvas.drawImageRect(pv, Rect.fromLTWH(0, 0, pv.width * 1.0, pv.height * 1.0),
        Rect.fromLTWH(_colX, y, r.cols * 1.0, r.rows * 1.0), nearest);
    // The engine's own rendering, same size, for comparison.
    final ex = _colX + r.cols + 30;
    _text(canvas, 'engine', BT.mono(12, color: BP.inkFaint), Offset(ex, y - 20));
    final engineTop = r.baseline - r.engine.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    r.engine.paint(canvas, Offset(ex, y + engineTop));
    y += math.max(r.rows * 1.0, engineTop + r.engine.height) + 30;
    final zoom = math.max(1, math.min(4, math.min(170 / r.cols, 200 / r.rows).floor()));
    _text(canvas, '$zoom×', BT.mono(12, color: BP.inkFaint), Offset(_colX, y));
    y += 20;
    final zr = Rect.fromLTWH(_colX, y, r.cols * zoom * 1.0, r.rows * zoom * 1.0);
    canvas.drawImageRect(pv, Rect.fromLTWH(0, 0, pv.width * 1.0, pv.height * 1.0), zr, nearest);
    canvas.drawRect(
      zr.inflate(0.5),
      Paint()
        ..color = BP.lineFaint
        ..style = PaintingStyle.stroke,
    );
  }

  void _grid(Canvas canvas, Rect g, _Raster r, Color color) {
    if (r.cell < 4) return;
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var c = 0; c <= r.cols; c++) {
      final x = g.left + c * r.cell;
      canvas.drawLine(Offset(x, g.top), Offset(x, g.bottom), p);
    }
    for (var row = 0; row <= r.rows; row++) {
      final y = g.top + row * r.cell;
      canvas.drawLine(Offset(g.left, y), Offset(g.right, y), p);
    }
  }

  void _beamBand(Canvas canvas, Rect g, double beam, double cell) {
    final row = beam.round();
    final top = g.top + row * cell;
    if (top < g.top || top + cell > g.bottom + 0.5) return;
    final rect = Rect.fromLTWH(g.left, top, g.width, cell);
    canvas.drawRect(rect, Paint()..color = BP.amber.withValues(alpha: 0.06));
    final p = Paint()
      ..color = BP.amber.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    canvas.drawLine(rect.topLeft, rect.topRight, p);
    canvas.drawLine(rect.bottomLeft, rect.bottomRight, p);
  }

  static void _text(Canvas canvas, String s, TextStyle style, Offset at, {bool center = false}) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, center ? at - Offset(tp.width / 2, tp.height / 2) : at);
    tp.dispose();
  }

  @override
  bool shouldRepaint(_RasterPainter old) => old.r != r || old.mode != mode;
}
