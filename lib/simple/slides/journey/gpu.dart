import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../deck/scripts.dart';
import '../../../deck/theme.dart';
import '../../../deck/widgets.dart';
import '../../../slides/journey/journey.dart';
import 'frame.dart';

/// Stop 6: every glyph becomes a textured quad (2 triangles) sampling the
/// glyph atlas; the whole word is one draw call. A lens shows the actual
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
const _wordTop = 24.0;

/// The word's ink is fitted into this box.
const _wordMax = Size(920, 270);

/// The word is centred in the space left of the atlas.
const _wordArea = 1090.0;
const _atlasPanel = Rect.fromLTWH(1136, 36, 336, 336);
const _statsTop = 400.0;
const _lensR = 126.0;
const _lensGap = 26.0;
const _zoom = 8.0;
const _lensMaxX = 1050.0;
const _gutter = 2.0;

// Timeline (seconds after arrival).
const _flyStart = 0.3; // first quad leaves the atlas
const _flySpread = 1.3; // …last one leaves this much later
const _flyTime = 0.7; // one quad's flight
const _introEnd = _flyStart + _flySpread + _flyTime;
const _lensIn = _introEnd + 0.1; // lens fades in on the first glyph
const _dwell = 2.5; // lens time per glyph
const _move = 0.5; // …of which moving

/// One glyph quad: a screen rectangle (paragraph coordinates, px) mapped onto
/// a tile of the atlas.
class _Quad {
  _Quad({
    required this.rect,
    required this.color,
    required this.tileKey,
    this.path,
    this.scan = false,
  });

  Rect rect;

  /// Color glyph (emoji) → RGBA atlas; otherwise the A8 alpha atlas.
  final bool color;
  final String tileKey;

  /// Exact outline in paragraph coordinates (bundled Latin glyphs).
  final Path? path;

  /// Bounds still to be tightened from the rendered pixels.
  final bool scan;

  /// Where the lens looks on this glyph (paragraph coordinates), and how
  /// many anti-aliased pixels it sees there.
  Offset? focus;
  int focusScore = 0;
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
  late final Offset _wordO;

  /// Bottom of the word's ink (paragraph coordinates): the lens hangs below.
  late final double _inkBottom;
  late final ui.Image _word;
  late final Ticker _ticker;
  double _t = 0;
  final List<_Quad> _quads = [];
  List<_Atlas> _atlases = [];

  /// Pointer in paragraph coordinates (null → the lens scans on its own).
  Offset? _mouse;
  int? _mouseHot;
  int _lastHot = 0;

  /// The lens starts on the glyph with the most anti-aliasing to show.
  int _lensStart = 0;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    TextProbe probe(double fs) => TextProbe(
      TextSpan(text: d.text, style: journeyStyle(fs)),
      textDirection: d.rtl ? TextDirection.rtl : TextDirection.ltr,
    );
    const base = 360.0;
    final m = probe(base);
    final (t0, b0) = _inkY(m, base);
    final fit = math.min(
      1.0,
      math.min(_wordMax.width / math.max(m.size.width, 1), _wordMax.height / math.max(b0 - t0, 1)),
    );
    m.dispose();
    _fs = (base * fit).floorToDouble();
    _probe = probe(_fs);
    final (inkTop, inkBottom) = _inkY(_probe, _fs);
    _inkBottom = inkBottom;
    _wordO = Offset(
      math.max(20, (_wordArea - _probe.size.width) / 2).roundToDouble(),
      (_wordTop - inkTop).roundToDouble(),
    );
    _word = _render();
    _buildQuads();
    _atlases = _pack();
    _ticker = createTicker((e) => setState(() => _t = e.inMicroseconds / 1e6))..start();
    _word.toByteData(format: ui.ImageByteFormat.rawRgba).then(_onPixels);
  }

  @override
  void dispose() {
    _ticker.dispose();
    for (final a in _atlases) {
      a.image.dispose();
    }
    _word.dispose();
    _probe.dispose();
    super.dispose();
  }

  /// Top and bottom of the word's ink at [fs] (paragraph coordinates): from
  /// the glyph outlines where we have them, the line box otherwise.
  (double, double) _inkY(TextProbe p, double fs) {
    final lines = p.lines;
    if (lines.isEmpty) return (0, p.size.height);
    final base = lines.first.baseline;
    var top = double.infinity, bottom = double.negativeInfinity;
    for (final g in widget.data.glyphs) {
      final f = g.font;
      if (f == null) {
        final r = p.rectFor(g.start, g.end);
        if (r == null || g.char.trim().isEmpty) continue;
        top = math.min(top, r.top);
        bottom = math.max(bottom, r.bottom);
        continue;
      }
      final o = f.outline(g.glyphId);
      if (o.contours.isEmpty) continue;
      final k = fs / f.unitsPerEm;
      // Arabic positional forms differ a little from the nominal outline.
      final pad = g.script == Script.arabic ? 0.12 * fs : 0.0;
      top = math.min(top, base - o.bounds.bottom * k - pad);
      bottom = math.max(bottom, base - o.bounds.top * k + pad);
    }
    if (!top.isFinite || !bottom.isFinite) return (0, p.size.height);
    return (math.max(0.0, top), math.min(p.size.height, bottom));
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
          color: false,
          tileKey: '${f.name}:${g.glyphId}',
          path: o.toPath(scale: k, origin: pen),
        ));
      }
    }
    // Reading order, for the fly-in and the lens.
    _quads.sort((a, b) => d.rtl ? b.rect.left.compareTo(a.rect.left) : a.rect.left.compareTo(b.rect.left));
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
    _pickFocus(keep, px, w, h);
    final old = _atlases;
    setState(() {
      _quads
        ..clear()
        ..addAll(keep);
      _atlases = _pack();
      var best = 0;
      for (var i = 0; i < _quads.length; i++) {
        if (_quads[i].focusScore > _quads[best].focusScore) best = i;
      }
      _lensStart = best;
      _lastHot = best;
    });
    for (final a in old) {
      a.image.dispose();
    }
  }

  /// For each glyph, the spot where the lens sees the most anti-aliasing on a
  /// curve or a diagonal (partially covered pixels whose edge runs neither
  /// straight across nor straight down) — from the real pixels, via a
  /// summed-area table.
  void _pickFocus(List<_Quad> quads, Uint8List px, int w, int h) {
    int alpha(int x, int y) => x < 0 || y < 0 || x >= w || y >= h ? 0 : px[(y * w + x) * 4 + 3];
    final sat = Int32List((w + 1) * (h + 1));
    for (var y = 0; y < h; y++) {
      var row = 0;
      for (var x = 0; x < w; x++) {
        final a = alpha(x, y);
        if (a > 24 && a < 232) {
          final gx = (alpha(x + 1, y) - alpha(x - 1, y)).abs();
          final gy = (alpha(x, y + 1) - alpha(x, y - 1)).abs();
          if (gx > 16 && gy > 16) row++;
        }
        sat[(y + 1) * (w + 1) + x + 1] = sat[y * (w + 1) + x + 1] + row;
      }
    }
    int sum(int x0, int y0, int x1, int y1) {
      x0 = x0.clamp(0, w);
      x1 = x1.clamp(0, w);
      y0 = y0.clamp(0, h);
      y1 = y1.clamp(0, h);
      return sat[y1 * (w + 1) + x1] - sat[y0 * (w + 1) + x1] - sat[y1 * (w + 1) + x0] + sat[y0 * (w + 1) + x0];
    }

    final half = (_lensR / _zoom).round();
    for (final q in quads) {
      final r = q.rect;
      var best = -1;
      Offset? at;
      for (var y = r.top.ceil() + half ~/ 2; y < r.bottom - half ~/ 2; y += 2) {
        for (var x = r.left.ceil() + half ~/ 2; x < r.right - half ~/ 2; x += 2) {
          final s = sum(x - half, y - half, x + half, y + half);
          if (s > best) {
            best = s;
            at = Offset(x + 0.5, y + 0.5);
          }
        }
      }
      q.focus = at;
      q.focusScore = math.max(0, best);
    }
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
    final inner = _atlasPanel.deflate(18);
    if (out.length == 1) {
      out.first.display = inner;
    } else {
      final s = (inner.width - 12) / 2;
      for (var i = 0; i < out.length; i++) {
        out[i].display = Rect.fromLTWH(inner.left + i * (s + 12), inner.top + (inner.height - s) / 2, s, s);
      }
    }
    return out;
  }

  Offset _scanTarget(int k) {
    final q = _quads[k];
    return q.focus ?? Offset(q.rect.left + q.rect.width * 0.28, q.rect.top + q.rect.height * 0.5);
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

  /// Flight progress of quad [i]: <0 still in the atlas, 0..1 flying, 1 landed.
  double _fly(int i, int n) {
    final start = _flyStart + (n <= 1 ? 0 : _flySpread * i / (n - 1));
    return (_t - start) / _flyTime;
  }

  @override
  Widget build(BuildContext context) {
    final n = _quads.length;
    final ps = _probe.size;
    final fly = [for (var i = 0; i < n; i++) _fly(i, n)];
    final landed = fly.where((f) => f >= 1).length;

    // Lens: after the fly-in, walk from glyph to glyph (or follow the mouse).
    Offset? pointer = _mouse;
    int? hot;
    var lensAlpha = 1.0;
    if (_mouse != null) {
      hot = _mouseHot;
    } else if (n > 0 && _t >= _lensIn) {
      final lt = (_t - _lensIn) / _dwell;
      final seg = (_lensStart + lt.floor()) % n;
      final local = (lt - lt.floor()) * _dwell;
      hot = seg;
      final to = _scanTarget(seg);
      if (lt < 1) {
        pointer = to;
        lensAlpha = ((_t - _lensIn) / 0.4).clamp(0.0, 1.0);
      } else {
        final from = _scanTarget((seg - 1 + n) % n);
        pointer = Offset.lerp(from, to, Curves.easeInOutCubic.transform((local / _move).clamp(0.0, 1.0)));
      }
    }
    // The draw call: every triangle lights up once the last quad lands.
    final flash = (1 - (_t - _introEnd) / 0.8).clamp(0.0, 1.0) * (_t >= _introEnd ? 1 : 0);
    final atlasHot = hot ?? (_t < _introEnd ? null : _lastHot);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: _atlasPanel.left,
          top: 0,
          child: Text('glyph atlas', style: BT.mono(20, color: BP.inkDim)),
        ),
        Positioned.fromRect(
          rect: _atlasPanel,
          child: const BpPanel(padding: EdgeInsets.zero, child: SizedBox.expand()),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _ScenePainter(
                origin: _wordO,
                inkBottom: _inkBottom,
                probe: _probe,
                quads: _quads,
                atlases: _atlases,
                word: _word,
                fly: fly,
                hot: atlasHot == null || atlasHot >= n ? null : atlasHot,
                pointer: pointer,
                lensAlpha: lensAlpha,
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
          left: _atlasPanel.left,
          top: _statsTop,
          width: _atlasPanel.width,
          child: _Stats(glyphs: landed, flash: flash),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scene: atlas texture, quads flying out of it, the word, the lens
// ─────────────────────────────────────────────────────────────────────────────

class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.origin,
    required this.inkBottom,
    required this.probe,
    required this.quads,
    required this.atlases,
    required this.word,
    required this.fly,
    required this.hot,
    required this.pointer,
    required this.lensAlpha,
    required this.flash,
  });

  /// Where the word sits (content coordinates).
  final Offset origin;
  final double inkBottom;
  final TextProbe probe;
  final List<_Quad> quads;
  final List<_Atlas> atlases;
  final ui.Image word;
  final List<double> fly;
  final int? hot;
  final Offset? pointer;
  final double lensAlpha;
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
    final hq = hot == null ? null : quads[hot!];

    // Atlas textures + packer rects.
    for (final a in atlases) {
      final d = a.display;
      canvas.drawRect(d, Paint()..color = const Color(0xFF02070D));
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
          _stroke(isHot ? BP.amber : (a.color ? BP.violet : BP.lineDim).withValues(alpha: 0.9), isHot ? 2.5 : 1),
        );
      }
      canvas.drawRect(d, _stroke(a.color ? BP.violet : BP.lineFaint));
    }

    // The word: landed quads show the real paragraph, flying ones the texture.
    final allLanded = fly.every((f) => f >= 1);
    if (allLanded) {
      probe.paint(canvas, origin);
    } else {
      for (var i = 0; i < quads.length; i++) {
        if (fly[i] < 1) continue;
        canvas.save();
        canvas.clipRect(quads[i].rect.shift(origin));
        probe.paint(canvas, origin);
        canvas.restore();
      }
    }

    // Quads: 2 triangles each.
    for (var i = 0; i < quads.length; i++) {
      final q = quads[i];
      final f = fly[i];
      if (f <= 0) continue;
      final target = q.rect.shift(origin);
      var r = target;
      if (f < 1) {
        final tile = _tileRect(q);
        final a = _atlasOf(q);
        if (tile == null || a == null) continue;
        r = Rect.lerp(tile, target, Curves.easeInOutCubic.transform(f))!;
        final src = a.tiles[q.tileKey]!;
        canvas.drawImageRect(
          a.image,
          src,
          r,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..colorFilter = q.color ? null : const ColorFilter.mode(BP.ink, BlendMode.srcIn),
        );
      }
      final isHot = i == hot;
      final flying = f < 1;
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
        canvas.drawPath(t1, Paint()..color = BP.amber.withValues(alpha: 0.26 * flash));
        canvas.drawPath(t2, Paint()..color = BP.amber.withValues(alpha: 0.14 * flash));
      }
      if (isHot) {
        canvas.drawPath(t1, Paint()..color = BP.amber.withValues(alpha: 0.14));
        canvas.drawPath(t2, Paint()..color = BP.amber.withValues(alpha: 0.06));
      }
      final c = isHot || flying ? BP.amber : (q.color ? BP.violet : BP.line);
      canvas.drawRect(r, _stroke(c.withValues(alpha: isHot ? 1 : 0.8), isHot ? 2.4 : 1.4));
      canvas.drawLine(r.topLeft, r.bottomRight, _stroke(c.withValues(alpha: isHot ? 0.9 : 0.55), isHot ? 1.8 : 1.1));
      for (final v in [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]) {
        canvas.drawCircle(v, isHot ? 4.5 : 3, Paint()..color = c);
      }
    }

    // Hot quad → its tile, corner to corner (the UVs).
    if (hq != null && fly[hot!] >= 1) {
      final t = _tileRect(hq);
      if (t != null) {
        final r = hq.rect.shift(origin);
        final pen = _stroke(BP.amber.withValues(alpha: 0.7), 1.4);
        final from = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
        final to = [t.topLeft, t.topRight, t.bottomRight, t.bottomLeft];
        for (var v = 0; v < 4; v++) {
          canvas.drawLine(from[v], to[v], pen);
          canvas.drawCircle(to[v], 3.5, Paint()..color = BP.amber);
        }
      }
    }

    // Lens: the actual 1× pixels, nearest-neighbour.
    final p = pointer;
    if (p != null && lensAlpha > 0) {
      if (lensAlpha < 1) {
        canvas.saveLayer(Offset.zero & size, Paint()..color = Color.fromRGBO(0, 0, 0, lensAlpha));
      }
      _lens(canvas, p);
      if (lensAlpha < 1) canvas.restore();
    }
  }

  /// A magnifier under the word, joined to the spot it samples.
  void _lens(Canvas canvas, Offset p) {
    const r = _lensR;
    final sample = origin + p;
    final c = Offset(
      sample.dx.clamp(r + 8, _lensMaxX - r),
      origin.dy + inkBottom + _lensGap + r,
    );
    final half = r / _zoom;
    final sq = Rect.fromCenter(center: sample, width: 2 * half, height: 2 * half);
    final amber = _stroke(BP.amber, 2);
    canvas.drawRect(sq, amber);
    final dir = sq.bottomCenter - c;
    final rim = c + dir / dir.distance * (r + 4);
    canvas.drawLine(sq.bottomCenter, rim, amber);

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
    canvas.restore();
    canvas.drawCircle(c, r, _stroke(BP.amber, 3));
    canvas.drawCircle(c, r + 6, _stroke(BP.amber.withValues(alpha: 0.3), 1.5));
  }

  @override
  bool shouldRepaint(_ScenePainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// The punchline
// ─────────────────────────────────────────────────────────────────────────────

/// Glyphs and triangles count up as quads land; it is all one draw call,
/// which flashes when the batch is complete.
class _Stats extends StatelessWidget {
  const _Stats({required this.glyphs, required this.flash});

  final int glyphs;
  final double flash;

  @override
  Widget build(BuildContext context) {
    Widget stat(int value, String label, Color c, [double glow = 0]) => Container(
      height: 64,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: BP.amber.withValues(alpha: 0.18 * glow),
        border: Border.all(color: BP.amber.withValues(alpha: glow), width: 1 + glow),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 116,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: BT.display(60, color: c, weight: 400, height: 1),
            ),
          ),
          const SizedBox(width: 22),
          Text(label, style: BT.display(30, color: c, weight: 400)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        stat(glyphs, glyphs == 1 ? 'glyph' : 'glyphs', BP.ink),
        stat(glyphs * 2, 'triangles', BP.line),
        stat(1, 'draw call', BP.amber, flash),
      ],
    );
  }
}
