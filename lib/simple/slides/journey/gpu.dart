import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../deck/scripts.dart';
import '../../../deck/theme.dart';
import '../../../deck/widgets.dart';
import '../../../slides/journey/journey.dart';
import 'frame.dart';

/// Stop 10: every glyph becomes a textured quad (2 triangles) sampling the
/// glyph atlas; the whole frame is one draw call. A lens shows the actual
/// pixels of the word rendered at 1×.
class JGpuSlide extends StatelessWidget {
  const JGpuSlide({super.key});

  @override
  Widget build(BuildContext context) => SJourneyFrame(
    stop: 5,
    title: (_) => 'Draw',
    builder: (context, d) => _Gpu(data: d),
  );
}

// Geometry (content-area coordinates, 1472 × 628).
const _wordO = Offset(40, 52);
const _atlasPanel = Rect.fromLTWH(1130, 12, 342, 372);
const _bottomY = 408.0;
const _lensR = 92.0;
const _zoom = 8.0;
const _lensMaxX = 1100.0;
const _gutter = 2.0;

String _f1(double v) => v.toStringAsFixed(1);

/// One glyph quad: a screen rectangle (paragraph coordinates, px) mapped onto
/// a tile of the atlas.
class _Quad {
  _Quad({
    required this.rect,
    required this.label,
    required this.id,
    required this.color,
    required this.tileKey,
    this.path,
    this.scan = false,
  });

  Rect rect;
  final String label;
  final int? id;

  /// Color glyph (emoji) → RGBA atlas; otherwise the A8 alpha atlas.
  final bool color;
  final String tileKey;

  /// Exact outline in paragraph coordinates (bundled Latin glyphs).
  final Path? path;

  /// Bounds still to be tightened from the rendered pixels.
  final bool scan;
}

class _Atlas {
  _Atlas({required this.color, required this.tex, required this.image, required this.tiles});

  final bool color;
  final double tex;
  final ui.Image image;

  /// tile key → rect in texels.
  final Map<String, Rect> tiles;
  Rect display = Rect.zero;
}

// ─────────────────────────────────────────────────────────────────────────────
// Arabic joining (to tell contextual forms apart as atlas keys).
// ─────────────────────────────────────────────────────────────────────────────

const _rightJoining = {
  0x0622, 0x0623, 0x0624, 0x0625, 0x0627, 0x0629, 0x062F, 0x0630, 0x0631, 0x0632, //
  0x0648, 0x0671, 0x0672, 0x0673, 0x0675, 0x0676, 0x0677, 0x06C0, 0x06CD, 0x06CF,
  0x06D2, 0x06D3, 0x06D5, 0x06EE, 0x06EF,
};

String _joining(int c) {
  if ((c >= 0x064B && c <= 0x065F) || c == 0x0670 || (c >= 0x06D6 && c <= 0x06DC) || (c >= 0x06DF && c <= 0x06E4)) {
    return 'T';
  }
  if (_rightJoining.contains(c) || (c >= 0x0688 && c <= 0x0699) || (c >= 0x06C3 && c <= 0x06CB)) return 'R';
  if (c == 0x0640) return 'C';
  if (c == 0x0621 || c == 0x0674 || c == 0x06D4 || c == 0x06DD) return 'U';
  if ((c >= 0x0620 && c <= 0x064A) || (c >= 0x066E && c <= 0x06FF)) return 'D';
  return 'U';
}

/// isol / init / medi / fina for letter i.
String _form(List<JGlyph> gs, int i) {
  final t = _joining(gs[i].codePoint);
  if (t == 'U' || t == 'T') return 'isol';
  String near(int from, int step) {
    for (var k = from; k >= 0 && k < gs.length; k += step) {
      final j = _joining(gs[k].codePoint);
      if (j != 'T') return j;
    }
    return 'U';
  }

  final prev = near(i - 1, -1);
  final next = near(i + 1, 1);
  final p = prev == 'D' || prev == 'C';
  final n = (t == 'D' || t == 'C') && (next == 'D' || next == 'R' || next == 'C');
  return p ? (n ? 'medi' : 'fina') : (n ? 'init' : 'isol');
}

// ─────────────────────────────────────────────────────────────────────────────

class _Gpu extends StatefulWidget {
  const _Gpu({required this.data});

  final JourneyData data;

  @override
  State<_Gpu> createState() => _GpuState();
}

class _GpuState extends State<_Gpu> with SingleTickerProviderStateMixin {
  late final double _fs;
  late final TextProbe _probe;
  late final ui.Image _word;
  late final AnimationController _clock;
  final List<_Quad> _quads = [];
  List<_Atlas> _atlases = [];
  Uint8List? _pixels;

  /// Pointer in paragraph coordinates (null → the lens scans on its own).
  Offset? _mouse;
  int? _mouseHot;
  int _lastHot = 0;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    TextProbe probe(double fs) => TextProbe(
      TextSpan(text: d.text, style: journeyStyle(fs)),
      textDirection: d.rtl ? TextDirection.rtl : TextDirection.ltr,
    );
    final m = probe(170);
    final fit = math.min(1.0, math.min(940 / math.max(m.size.width, 1), 280 / math.max(m.size.height, 1)));
    m.dispose();
    _fs = (170 * fit).floorToDouble();
    _probe = probe(_fs);
    _word = _render();
    _buildQuads();
    _atlases = _pack();
    _clock = AnimationController(vsync: this, duration: _period)..repeat();
    _word.toByteData(format: ui.ImageByteFormat.rawRgba).then(_onPixels);
  }

  Duration get _period => Duration(milliseconds: 1900 * math.max(1, _quads.length));

  @override
  void dispose() {
    _clock.dispose();
    for (final a in _atlases) {
      a.image.dispose();
    }
    _word.dispose();
    _probe.dispose();
    super.dispose();
  }

  /// The word rendered once at 1× — the pixels the lens shows.
  ui.Image _render() {
    final rec = ui.PictureRecorder();
    _probe.paint(Canvas(rec), Offset.zero);
    final pic = rec.endRecording();
    final img = pic.toImageSync(math.max(1, _probe.size.width.ceil()), math.max(1, _probe.size.height.ceil()));
    pic.dispose();
    return img;
  }

  void _buildQuads() {
    final d = widget.data;
    final lines = _probe.lines;
    if (lines.isEmpty) return;
    final base = lines.first.baseline;
    for (final (s, e) in _probe.graphemes()) {
      final idx = [
        for (var i = 0; i < d.glyphs.length; i++)
          if (d.glyphs[i].start >= s && d.glyphs[i].start < e) i,
      ];
      final cluster = _probe.rectFor(s, e);
      if (idx.isEmpty || cluster == null) continue;
      final text = d.text.substring(s, e);
      if (idx.every((i) => d.glyphs[i].font == null)) {
        if (text.trim().isEmpty) continue;
        _quads.add(_Quad(
          rect: cluster,
          label: text,
          id: null,
          color: scriptOfCluster(text) == Script.emoji,
          tileKey: 'sys:$text',
          scan: true,
        ));
        continue;
      }
      for (final i in idx) {
        final g = d.glyphs[i];
        final f = g.font;
        if (f == null) continue;
        var r = _probe.rectFor(g.start, g.end);
        if (r == null || r.width < 0.5) r = cluster;
        if (g.script == Script.arabic) {
          // Contextual forms: bounds come from the rendered pixels.
          _quads.add(_Quad(
            rect: r,
            label: g.char,
            id: g.glyphId,
            color: false,
            tileKey: 'ar:${g.codePoint}:${_form(d.glyphs, i)}',
            scan: true,
          ));
          continue;
        }
        final o = f.outline(g.glyphId);
        if (o.contours.isEmpty) continue; // a space: no ink, no quad
        final k = _fs / f.unitsPerEm;
        final pen = Offset(r.left, base);
        final b = o.bounds; // font units, y up: (xMin, yMin, xMax, yMax)
        final ink = Rect.fromLTRB(pen.dx + b.left * k, base - b.bottom * k, pen.dx + b.right * k, base - b.top * k);
        final q = ink.inflate(1);
        _quads.add(_Quad(
          rect: Rect.fromLTWH(q.left, q.top, q.width.ceilToDouble(), q.height.ceilToDouble()),
          label: g.char,
          id: g.glyphId,
          color: false,
          tileKey: '${f.name}:${g.glyphId}',
          path: o.toPath(scale: k, origin: pen),
        ));
      }
    }
  }

  void _onPixels(ByteData? bd) {
    if (!mounted || bd == null) return;
    final w = _word.width;
    final h = _word.height;
    final px = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
    final keep = <_Quad>[];
    for (final q in _quads) {
      if (!q.scan) {
        keep.add(q);
        continue;
      }
      final x0 = q.rect.left.floor().clamp(0, w);
      final x1 = q.rect.right.ceil().clamp(0, w);
      var minX = w, minY = h, maxX = -1, maxY = -1;
      for (var y = 0; y < h; y++) {
        for (var x = x0; x < x1; x++) {
          if (px[(y * w + x) * 4 + 3] > 8) {
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }
      if (maxX < 0) continue;
      q.rect = Rect.fromLTRB(
        math.max(0, minX - 1).toDouble(),
        math.max(0, minY - 1).toDouble(),
        math.min(w, maxX + 2).toDouble(),
        math.min(h, maxY + 2).toDouble(),
      );
      keep.add(q);
    }
    final old = _atlases;
    setState(() {
      _pixels = px;
      _quads
        ..clear()
        ..addAll(keep);
      _atlases = _pack();
      _lastHot = _lastHot.clamp(0, math.max(0, _quads.length - 1));
    });
    for (final a in old) {
      a.image.dispose();
    }
    _clock
      ..duration = _period
      ..repeat();
  }

  /// Shelf-pack unique tiles into power-of-two textures and render them.
  List<_Atlas> _pack() {
    final out = <_Atlas>[];
    for (final color in [false, true]) {
      final first = <String, _Quad>{};
      for (final q in _quads) {
        if (q.color == color) first.putIfAbsent(q.tileKey, () => q);
      }
      if (first.isEmpty) continue;
      final order = first.entries.toList()..sort((a, b) => b.value.rect.height.compareTo(a.value.rect.height));
      var tex = 64.0;
      late Map<String, Rect> tiles;
      while (true) {
        tiles = {};
        var x = 0.0, y = 0.0, shelf = 0.0;
        var ok = true;
        for (final e in order) {
          final w = e.value.rect.width.ceilToDouble();
          final h = e.value.rect.height.ceilToDouble();
          if (x + w > tex) {
            x = 0;
            y += shelf + _gutter;
            shelf = 0;
          }
          if (w > tex || y + h > tex) {
            ok = false;
            break;
          }
          tiles[e.key] = Rect.fromLTWH(x, y, w, h);
          x += w + _gutter;
          shelf = math.max(shelf, h);
        }
        if (ok) break;
        tex *= 2;
      }
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      for (final e in order) {
        final q = e.value;
        final t = tiles[e.key]!;
        if (q.path != null) {
          c.save();
          c.clipRect(t);
          c.translate(t.left - q.rect.left, t.top - q.rect.top);
          c.drawPath(q.path!, Paint()..color = Colors.white);
          c.restore();
        } else {
          final src = q.rect.intersect(Offset.zero & Size(_word.width.toDouble(), _word.height.toDouble()));
          c.drawImageRect(
            _word,
            src,
            Rect.fromLTWH(t.left + src.left - q.rect.left, t.top + src.top - q.rect.top, src.width, src.height),
            Paint()..colorFilter = color ? null : const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          );
        }
      }
      final pic = rec.endRecording();
      final img = pic.toImageSync(tex.toInt(), tex.toInt());
      pic.dispose();
      out.add(_Atlas(color: color, tex: tex, image: img, tiles: tiles));
    }
    // Where each texture sits in the panel.
    final inner = Rect.fromLTWH(_atlasPanel.left + 21, _atlasPanel.top + 30, 300, 300);
    if (out.length == 1) {
      out.first.display = inner;
    } else {
      for (var i = 0; i < out.length; i++) {
        out[i].display = Rect.fromLTWH(inner.left + i * 155, inner.top, 145, 145);
      }
    }
    return out;
  }

  _Atlas? _atlasOf(_Quad q) {
    for (final a in _atlases) {
      if (a.color == q.color) return a;
    }
    return null;
  }

  Offset _scanTarget(int k) {
    final r = _quads[k].rect;
    return Offset(r.left + r.width * 0.28, r.top + r.height * 0.5);
  }

  void _hover(Offset local) {
    final p = local - const Offset(24, 24);
    int? hit;
    for (var k = 0; k < _quads.length; k++) {
      if (_quads[k].rect.inflate(4).contains(p)) hit = k;
    }
    setState(() {
      _mouse = p;
      _mouseHot = hit;
      if (hit != null) _lastHot = hit;
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = _quads.length;
    final ps = _probe.size;
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) {
        // Auto mode: walk from glyph to glyph.
        final t = _clock.value * math.max(1, n);
        final seg = n == 0 ? 0 : t.floor().clamp(0, n - 1);
        final local = t - t.floor();
        Offset? pointer = _mouse;
        int? hot;
        if (_mouse != null) {
          hot = _mouseHot;
        } else if (n > 0) {
          hot = seg;
          final from = _scanTarget((seg - 1 + n) % n);
          final to = _scanTarget(seg);
          pointer = Offset.lerp(from, to, Curves.easeInOutCubic.transform((local / 0.3).clamp(0.0, 1.0)));
        }
        final shown = n == 0 ? null : (hot ?? _lastHot).clamp(0, n - 1);
        final flash = n > 0 && seg == 0 && _mouse == null ? (1 - local / 0.3).clamp(0.0, 1.0) : 0.0;
        final q = shown == null ? null : _quads[shown];
        final atlas = q == null ? null : _atlasOf(q);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fromRect(
              rect: _atlasPanel,
              child: BpPanel(
                label: 'glyph atlas · ${_atlases.fold<int>(0, (a, e) => a + e.tiles.length)} tiles',
                child: const SizedBox.expand(),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ScenePainter(
                    probe: _probe,
                    quads: _quads,
                    atlases: _atlases,
                    word: _word,
                    pixels: _pixels,
                    hot: hot,
                    pointer: pointer,
                    flash: flash,
                  ),
                ),
              ),
            ),
            Positioned(
              left: _wordO.dx - 24,
              top: _wordO.dy - 24,
              width: ps.width + 48,
              height: ps.height + 48,
              child: MouseRegion(
                cursor: SystemMouseCursors.precise,
                onHover: (e) => _hover(e.localPosition),
                onExit: (_) => setState(() {
                  _mouse = null;
                  _mouseHot = null;
                }),
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: 0,
              top: _bottomY,
              width: 470,
              height: 628 - _bottomY,
              child: _VertexTable(
                index: shown,
                quad: q,
                tile: q == null ? null : atlas?.tiles[q.tileKey],
                tex: atlas?.tex ?? 1,
              ),
            ),
            Positioned(
              left: 500,
              top: _bottomY,
              width: 590,
              height: 136,
              child: _ShaderPanel(color: q?.color ?? false),
            ),
            Positioned(
              left: 500,
              top: _bottomY + 160,
              child: Row(
                children: [
                  SizedBox(
                    width: 60,
                    height: 20,
                    child: DrawOn(
                      arrow: true,
                      color: BP.amber,
                      path: (s) => Path()
                        ..moveTo(4, s.height / 2)
                        ..lineTo(s.width - 4, s.height / 2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const BpTag('Metal / Vulkan → framebuffer', color: BP.amber, size: 15),
                ],
              ),
            ),
            Positioned(
              left: _atlasPanel.left,
              top: _bottomY,
              width: _atlasPanel.width,
              height: 628 - _bottomY,
              child: _Stats(glyphs: n, flash: flash),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scene: word, quads, atlas textures, UV links, lens
// ─────────────────────────────────────────────────────────────────────────────

class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.probe,
    required this.quads,
    required this.atlases,
    required this.word,
    required this.pixels,
    required this.hot,
    required this.pointer,
    required this.flash,
  });

  final TextProbe probe;
  final List<_Quad> quads;
  final List<_Atlas> atlases;
  final ui.Image word;
  final Uint8List? pixels;
  final int? hot;
  final Offset? pointer;
  final double flash;

  static Paint _stroke(Color c, [double w = 1]) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w;

  _Atlas? _atlasOf(_Quad q) {
    for (final a in atlases) {
      if (a.color == q.color) return a;
    }
    return null;
  }

  /// A tile rect (texels) in content coordinates.
  Rect? _tileRect(_Quad q) {
    final a = _atlasOf(q);
    final t = a?.tiles[q.tileKey];
    if (a == null || t == null) return null;
    final k = a.display.width / a.tex;
    return Rect.fromLTWH(a.display.left + t.left * k, a.display.top + t.top * k, t.width * k, t.height * k);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final hq = hot == null || hot! >= quads.length ? null : quads[hot!];

    // Atlas textures + packer rects.
    for (final a in atlases) {
      final d = a.display;
      canvas.drawRect(d, Paint()..color = BP.bg);
      canvas.drawImageRect(
        a.image,
        Rect.fromLTWH(0, 0, a.tex, a.tex),
        d,
        Paint()..filterQuality = FilterQuality.medium,
      );
      final k = d.width / a.tex;
      for (final e in a.tiles.entries) {
        final r = Rect.fromLTWH(d.left + e.value.left * k, d.top + e.value.top * k, e.value.width * k, e.value.height * k);
        final isHot = hq != null && hq.color == a.color && hq.tileKey == e.key;
        canvas.drawRect(
          r,
          _stroke(isHot ? BP.amber : (a.color ? BP.violet : BP.lineDim).withValues(alpha: 0.9), isHot ? 2 : 0.8),
        );
      }
      canvas.drawRect(d, _stroke(a.color ? BP.violet : BP.lineFaint));
      _text(canvas, '${a.color ? 'RGBA' : 'A8'} · ${a.tex.toInt()}²', Offset(d.left, d.bottom + 8), a.color ? BP.violet : BP.inkDim);
    }

    // Quad → tile links (UVs), curving over the word.
    for (var i = 0; i < quads.length; i++) {
      final q = quads[i];
      final t = _tileRect(q);
      if (t == null || i == hot) continue;
      final a = Offset(_wordO.dx + q.rect.center.dx, _wordO.dy + q.rect.top);
      final b = t.center;
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo(a.dx, a.dy - 46, b.dx - 160, b.dy, b.dx, b.dy);
      canvas.drawPath(dashPath(path, dash: 3, gap: 4), _stroke((q.color ? BP.violet : BP.line).withValues(alpha: 0.35)));
    }

    // The word, as the engine draws it.
    probe.paint(canvas, _wordO);

    // Quads: 2 triangles each.
    for (var i = 0; i < quads.length; i++) {
      final q = quads[i];
      final r = q.rect.shift(_wordO);
      final isHot = i == hot;
      final t1 = Path()
        ..moveTo(r.left, r.top)
        ..lineTo(r.right, r.top)
        ..lineTo(r.right, r.bottom)
        ..close();
      final t2 = Path()
        ..moveTo(r.left, r.top)
        ..lineTo(r.right, r.bottom)
        ..lineTo(r.left, r.bottom)
        ..close();
      if (flash > 0) {
        canvas.drawPath(t1, Paint()..color = BP.line.withValues(alpha: 0.22 * flash));
        canvas.drawPath(t2, Paint()..color = BP.line.withValues(alpha: 0.14 * flash));
      }
      if (isHot) {
        canvas.drawPath(t1, Paint()..color = BP.amber.withValues(alpha: 0.16));
        canvas.drawPath(t2, Paint()..color = BP.amber.withValues(alpha: 0.07));
      }
      final c = isHot ? BP.amber : (q.color ? BP.violet : BP.line);
      canvas.drawRect(r, _stroke(c.withValues(alpha: isHot ? 1 : 0.75), isHot ? 1.8 : 1));
      canvas.drawLine(r.topLeft, r.bottomRight, _stroke(c.withValues(alpha: isHot ? 0.9 : 0.5), isHot ? 1.4 : 0.8));
      final corners = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
      for (var v = 0; v < 4; v++) {
        canvas.drawCircle(corners[v], isHot ? 3.5 : 2.2, Paint()..color = c);
        if (isHot) {
          final off = Offset(v == 1 || v == 2 ? 6 : -16, v < 2 ? -18 : 4);
          _text(canvas, '$v', corners[v] + off, BP.amber);
        }
      }
    }

    // Lens: the actual 1× pixels, nearest-neighbour.
    final p = pointer;
    if (p != null) _lens(canvas, p);

    // Hot quad → its tile, corner to corner.
    if (hq != null) {
      final t = _tileRect(hq);
      if (t != null) {
        final r = hq.rect.shift(_wordO);
        final pen = _stroke(BP.amber.withValues(alpha: 0.75), 1);
        final from = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
        final to = [t.topLeft, t.topRight, t.bottomRight, t.bottomLeft];
        for (var v = 0; v < 4; v++) {
          canvas.drawLine(from[v], to[v], pen);
          canvas.drawCircle(to[v], 2.5, Paint()..color = BP.amber);
        }
      }
    }
  }

  void _lens(Canvas canvas, Offset p) {
    const r = _lensR;
    final sample = _wordO + p;
    final right = sample.dx + 36 + 2 * r < _lensMaxX;
    final c = Offset(
      right ? sample.dx + 36 + r : sample.dx - 36 - r,
      sample.dy.clamp(r - 40, _bottomY - r - 20),
    );
    // The sampled region and the callout.
    final half = r / _zoom;
    final sq = Rect.fromCenter(center: sample, width: 2 * half, height: 2 * half);
    final amber = _stroke(BP.amber, 1.3);
    canvas.drawRect(sq, amber);
    final edge = Offset(right ? sq.right : sq.left, sample.dy);
    final dir = edge - c;
    final rim = c + dir / dir.distance * r;
    canvas.drawLine(edge, rim, amber);

    final circle = Rect.fromCircle(center: c, radius: r);
    canvas.save();
    canvas.clipPath(Path()..addOval(circle));
    canvas.drawRect(circle, Paint()..color = BP.bg);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(_zoom);
    canvas.translate(-p.dx, -p.dy);
    canvas.drawImage(word, Offset.zero, Paint()..filterQuality = FilterQuality.none);
    canvas.restore();
    // Pixel grid
    final grid = _stroke(BP.lineFaint.withValues(alpha: 0.8), 1);
    for (var ix = (p.dx - half).floor(); ix <= (p.dx + half).ceil(); ix++) {
      final x = c.dx + (ix - p.dx) * _zoom;
      canvas.drawLine(Offset(x, c.dy - r), Offset(x, c.dy + r), grid);
    }
    for (var iy = (p.dy - half).floor(); iy <= (p.dy + half).ceil(); iy++) {
      final y = c.dy + (iy - p.dy) * _zoom;
      canvas.drawLine(Offset(c.dx - r, y), Offset(c.dx + r, y), grid);
    }
    // The pixel under the crosshair.
    final px = p.dx.floorToDouble();
    final py = p.dy.floorToDouble();
    canvas.drawRect(
      Rect.fromLTWH(c.dx + (px - p.dx) * _zoom, c.dy + (py - p.dy) * _zoom, _zoom, _zoom),
      _stroke(BP.amber, 1.6),
    );
    canvas.restore();
    canvas.drawCircle(c, r, _stroke(BP.amber, 2));
    canvas.drawCircle(c, r + 4, _stroke(BP.amber.withValues(alpha: 0.3), 1));

    // Coverage of that pixel, from the real image bytes.
    var label = 'pixels @1×';
    final bytes = pixels;
    if (bytes != null) {
      final ix = px.toInt();
      final iy = py.toInt();
      if (ix >= 0 && iy >= 0 && ix < word.width && iy < word.height) {
        final a = bytes[(iy * word.width + ix) * 4 + 3] / 255;
        label = 'pixels @1×   α ${a.toStringAsFixed(2)}';
      }
    }
    _text(canvas, label, Offset(c.dx, c.dy + r + 10), BP.amber, center: true);
  }

  void _text(Canvas c, String s, Offset at, Color color, {bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: BT.mono(12, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center ? at - Offset(tp.width / 2, 0) : at);
    tp.dispose();
  }

  @override
  bool shouldRepaint(_ScenePainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Panels
// ─────────────────────────────────────────────────────────────────────────────

class _VertexTable extends StatelessWidget {
  const _VertexTable({required this.index, required this.quad, required this.tile, required this.tex});

  final int? index;
  final _Quad? quad;
  final Rect? tile;
  final double tex;

  @override
  Widget build(BuildContext context) {
    final q = quad;
    final t = tile;
    final label = q == null ? 'vertices' : "quad $index · '${q.label}'${q.id == null ? '' : ' #${q.id}'}";
    Widget cell(String s, double w, Color c, {double size = 15}) => SizedBox(
      width: w,
      child: Text(s, textAlign: TextAlign.right, style: BT.mono(size, color: c)),
    );
    final rows = <Widget>[
      Row(
        children: [
          cell('', 30, BP.inkFaint, size: 13),
          cell('x', 88, BP.inkFaint, size: 13),
          cell('y', 88, BP.inkFaint, size: 13),
          cell('u', 88, BP.inkFaint, size: 13),
          cell('v', 88, BP.inkFaint, size: 13),
        ],
      ),
      const SizedBox(height: 6),
    ];
    if (q != null && t != null) {
      final r = q.rect;
      final pos = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
      final uv = [
        Offset(t.left / tex, t.top / tex),
        Offset(t.right / tex, t.top / tex),
        Offset(t.right / tex, t.bottom / tex),
        Offset(t.left / tex, t.bottom / tex),
      ];
      for (var v = 0; v < 4; v++) {
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(
            children: [
              cell('$v', 30, BP.amber),
              cell(_f1(pos[v].dx), 88, BP.ink),
              cell(_f1(pos[v].dy), 88, BP.ink),
              cell(uv[v].dx.toStringAsFixed(3), 88, q.color ? BP.violet : BP.line),
              cell(uv[v].dy.toStringAsFixed(3), 88, q.color ? BP.violet : BP.line),
            ],
          ),
        ));
      }
      rows.add(const SizedBox(height: 8));
      rows.add(Text('triangles  0 1 2 · 0 2 3', style: BT.mono(13, color: BP.inkDim)));
    }
    return BpPanel(
      label: label,
      color: q == null ? BP.lineDim : BP.amber,
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
    );
  }
}

class _ShaderPanel extends StatelessWidget {
  const _ShaderPanel({required this.color});

  final bool color;

  @override
  Widget build(BuildContext context) {
    Widget line(String code, String note, bool active) => AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: active ? 1 : 0.4,
      child: Row(
        children: [
          SizedBox(width: 22, child: Text(active ? '▸' : '', style: BT.mono(17, color: BP.amber))),
          SizedBox(width: 330, child: Text(code, style: BT.mono(17, color: active ? BP.ink : BP.inkDim))),
          Text(note, style: BT.mono(13, color: active ? (color ? BP.violet : BP.line) : BP.inkFaint)),
        ],
      ),
    );
    return BpPanel(
      label: 'fragment shader',
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              line('color = text_color * atlas.r', '// A8 glyphs', !color),
              const SizedBox(height: 14),
              line('color = atlas.rgba', '// color glyphs', color),
            ],
          ),
          const Positioned(right: 0, top: -24, child: BpTag('pseudo-code', color: BP.inkDim, size: 11)),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.glyphs, required this.flash});

  final int glyphs;
  final double flash;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, int value, Color c, [double glow = 0]) => Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: BP.amber.withValues(alpha: 0.18 * glow),
          border: Border.all(color: Color.lerp(BP.lineFaint, BP.amber, glow)!, width: 1 + glow),
        ),
        child: Column(
          children: [
            Text('$value', style: BT.display(48, color: c, weight: 400, height: 1.1)),
            const SizedBox(height: 6),
            Text(label, style: BT.mono(13, color: BP.inkDim)),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Row(
          children: [
            stat('glyphs', glyphs, BP.ink),
            stat('triangles', glyphs * 2, BP.line),
            stat('draw calls', 1, BP.amber, flash),
          ],
        ),
        const SizedBox(height: 14),
        Text('one frame · one draw', style: BT.mono(13, color: BP.inkFaint)),
      ],
    );
  }
}
