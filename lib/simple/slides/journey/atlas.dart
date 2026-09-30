import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../deck/font_data.dart';
import '../../../deck/scripts.dart';
import '../../../deck/theme.dart';
import '../../../deck/widgets.dart';
import '../../../slides/journey/journey.dart';
import 'frame.dart';

/// Stop 5: Impeller turns each unique glyph key (font, glyph, size, subpixel
/// offset) into a small coverage bitmap packed into a glyph atlas.
class JAtlasSlide extends StatelessWidget {
  const JAtlasSlide({super.key});

  @override
  Widget build(BuildContext context) => SJourneyFrame(
    stop: 4,
    title: (_) => 'Rasterize',
    builder: (context, d) => _Atlas(data: d),
  );
}

// Geometry (content-area coordinates, 1472 × 628): three stages, left → right.
const _stageTop = 112.0;
const _stageW = 436.0;
const _stageH = 420.0;
const _stageGap = 82.0;
const _panelPad = 14.0;

/// A unique glyph in the atlas.
class _Key {
  _Key({
    required this.text,
    required this.glyph,
    required this.bucket,
    required this.color,
    this.form = '',
  });

  final String text;

  /// Arabic positional form (init/medi/fina/isol) — rendered via ZWJ context.
  final String form;
  bool get shaped => form.isNotEmpty;
  final JGlyph glyph;

  /// Subpixel bucket 0..3 → 0, .25, .5, .75
  final int bucket;
  final bool color;

  FontData? get font => glyph.font;
  String get id => '${glyph.fontName}:${glyph.glyphId}:${color ? text : ''}:$form:$bucket';
}

/// Where each key's tile sits in its atlas texture (texels).
class _Pack {
  _Pack(this.tex, this.tiles);

  final double tex;
  final Map<int, Rect> tiles;
}

class _Atlas extends StatefulWidget {
  const _Atlas({required this.data});

  final JourneyData data;

  @override
  State<_Atlas> createState() => _AtlasState();
}

class _AtlasState extends State<_Atlas> with SingleTickerProviderStateMixin {
  static const _base = 48.0;
  static const _step = Duration(milliseconds: 380);
  static const _cycleEvery = Duration(milliseconds: 2400);
  static const _firstHold = Duration(milliseconds: 5400);

  /// Time since arrival.
  final _clock = Stopwatch()..start();
  double _scale = 1;
  int? _hover;
  int _cycle = 0;
  Timer? _timer;

  late final AnimationController _build = AnimationController(vsync: this, duration: _buildTime)
    ..addStatusListener(_onBuilt);

  Duration get _buildTime => _step * math.max(1, _keys.length);

  double get _px => _base * _scale;
  bool get _paths => _px > 250;

  late List<_Key> _keys = _computeKeys();
  late (_Pack, _Pack) _packs = _packKeys();

  @override
  void initState() {
    super.initState();
    _build.forward();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _build.dispose();
    super.dispose();
  }

  /// Built: settle on the first key, then walk the keys. On arrival the first
  /// key stays up a while, so the slide reads as a still.
  void _onBuilt(AnimationStatus s) {
    if (s != AnimationStatus.completed) return;
    _timer?.cancel();
    setState(() => _cycle = 0);
    final since = _clock.elapsed;
    final hold = since < _firstHold ? _firstHold - since : _cycleEvery;
    _timer = Timer(hold > _cycleEvery ? hold : _cycleEvery, () {
      _advance();
      _timer = Timer.periodic(_cycleEvery, (_) => _advance());
    });
  }

  void _advance() {
    if (mounted && _hover == null) {
      setState(() => _cycle = (_cycle + 1) % math.max(1, _keys.length));
    }
  }

  List<_Key> _computeKeys() {
    final d = widget.data;
    final probe = TextProbe(TextSpan(text: d.text, style: journeyStyle(_px)));
    final keys = <String, _Key>{};
    final hasEmoji = d.glyphs.any((g) => g.script == Script.emoji);
    if (hasEmoji) {
      for (final (s, e) in probe.graphemes()) {
        final g = d.glyphs.firstWhere((g) => g.start >= s);
        final k = _Key(text: d.text.substring(s, e), glyph: g, bucket: 0, color: true);
        keys.putIfAbsent(k.id, () => k);
      }
    } else {
      final runes = d.text.runes.toList();
      for (var gi = 0; gi < d.glyphs.length; gi++) {
        final g = d.glyphs[gi];
        final r = probe.rectFor(g.start, g.end);
        // Spaces have no ink, so no tile. Glyphs from a platform fallback font
        // (e.g. kanji) are still A8 tiles, rendered from the text itself.
        final noInk = g.font == null
            ? g.char.trim().isEmpty
            : g.font!.outline(g.glyphId).contours.isEmpty;
        if (noInk) continue;
        final x = r?.left ?? 0;
        final frac = x - x.floorToDouble();
        final bucket = (frac * 4).round() % 4;
        final (form, display) = g.script == Script.arabic ? arabicForm(runes, gi) : ('', g.char);
        final k = _Key(text: display, glyph: g, bucket: bucket, color: false, form: form);
        keys.putIfAbsent(k.id, () => k);
      }
    }
    probe.dispose();
    return keys.values.toList();
  }

  /// Shelf-pack the A8 (alpha) and RGBA (color) tiles into power-of-two textures.
  (_Pack, _Pack) _packKeys() {
    _Pack pack(bool color) {
      final which = [
        for (var i = 0; i < _keys.length; i++)
          if (_keys[i].color == color) i,
      ];
      // Tile sizes in texels (ink bounds + 1 texel padding).
      final sizes = <int, Size>{};
      for (final i in which) {
        final k = _keys[i];
        final f = k.font;
        if (k.color || f == null) {
          sizes[i] = Size(_px * 1.25, _px * 1.25);
        } else if (k.shaped) {
          final tp = TextPainter(
            text: TextSpan(text: k.text, style: journeyStyle(_px)),
            textDirection: TextDirection.rtl,
          )..layout();
          sizes[i] = Size(tp.width + 3, tp.height * 0.85);
          tp.dispose();
        } else {
          final b = f.outline(k.glyph.glyphId).bounds;
          final s = _px / f.unitsPerEm;
          sizes[i] = Size(b.width * s + 3, b.height * s + 3);
        }
      }
      var tex = 64.0;
      while (true) {
        final pos = <int, Rect>{};
        var x = 0.0, y = 0.0, shelf = 0.0;
        var ok = true;
        final order = [...which]..sort((a, b) => sizes[b]!.height.compareTo(sizes[a]!.height));
        for (final i in order) {
          final t = sizes[i]!;
          if (x + t.width > tex) {
            x = 0;
            y += shelf;
            shelf = 0;
          }
          if (y + t.height > tex || t.width > tex) {
            ok = false;
            break;
          }
          pos[i] = Offset(x, y) & t;
          x += t.width;
          shelf = math.max(shelf, t.height);
        }
        if (ok) return _Pack(tex, pos);
        tex *= 2;
      }
    }

    return (pack(false), pack(true));
  }

  void _setScale(double s) {
    final snapped = (s * 4).round() / 4;
    if (snapped == _scale) return;
    _timer?.cancel();
    setState(() {
      _scale = snapped;
      _keys = _computeKeys();
      _packs = _packKeys();
      _cycle = 0;
      _build.duration = _buildTime;
    });
    _build.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _build,
      builder: (context, _) {
        final n = _keys.length;
        final building = !_build.isCompleted;
        final built = building ? math.min(n, (_build.value * n).floor() + 1) : n;
        final current = n == 0 ? 0 : (_hover ?? (building ? built - 1 : _cycle)).clamp(0, n - 1);
        final sel = n == 0 ? null : _keys[current];
        final pack = sel != null && sel.color ? _packs.$2 : _packs.$1;
        final anim = building ? const Duration(milliseconds: 300) : const Duration(milliseconds: 650);
        final font = sel?.font;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Size
            Positioned(
              left: 0,
              top: 0,
              child: Row(
                children: [
                  _BigSlider(value: _scale, min: 0.5, max: 6, width: 520, onChanged: _setScale),
                  const SizedBox(width: 28),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 250),
                    style: BT.mono(24, color: _paths ? BP.red : BP.amber),
                    child: Text('${_px.round()} px${_paths ? '  → drawn as paths' : ''}'),
                  ),
                ],
              ),
            ),
            if (sel != null) ...[
              // 1 · outline
              _stage(
                0,
                title: 'outline',
                caption: sel.color
                    ? 'color glyph'
                    : font == null
                    ? 'system font'
                    : 'glyph #${sel.glyph.glyphId}${sel.shaped ? ' → ${sel.form}' : ''}',
                color: _paths ? BP.red : BP.lineDim,
                child: sel.color || font == null
                    ? Center(child: Text(sel.text, style: journeyStyle(220)))
                    : _OutlineView(
                        key: ValueKey('${sel.id}@$_px'),
                        outline: font.outline(sel.glyph.glyphId),
                        solid: _paths,
                        duration: anim,
                      ),
              ),
              // 2 · pixels
              _stage(
                1,
                title: 'pixels',
                caption: _paths ? 'no bitmap' : null,
                captionColor: BP.red,
                captionWidget: _paths
                    ? null
                    : FutureBuilder<_Bitmap>(
                        future: _coverage(sel.text, _px, sel.bucket),
                        builder: (context, snap) => Text(
                          snap.data == null ? '' : '${snap.data!.w} × ${snap.data!.h} px',
                          style: BT.mono(20, color: BP.inkDim),
                        ),
                      ),
                color: _paths ? BP.red : BP.lineDim,
                child: _paths
                    ? Center(child: Text('fill the path\nevery frame', textAlign: TextAlign.center, style: BT.mono(26, color: BP.red, height: 1.5)))
                    : _CoverageView(
                        key: ValueKey('${sel.id}@$_px'),
                        text: sel.text,
                        px: _px,
                        bucket: sel.bucket,
                        color: sel.color,
                        duration: anim,
                      ),
              ),
              // 3 · atlas
              _stage(
                2,
                title: 'atlas',
                caption: _paths
                    ? 'not used'
                    : '${pack.tiles.length} tile${pack.tiles.length == 1 ? '' : 's'}'
                          ' · ${pack.tex.round()} × ${pack.tex.round()}',
                captionColor: _paths ? BP.red : BP.inkDim,
                color: sel.color ? BP.violet : BP.lineDim,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: _paths ? 0.25 : 1,
                  child: LayoutBuilder(
                    builder: (context, box) => MouseRegion(
                      onHover: (e) {
                        final i = _tileAt(pack, box.biggest, e.localPosition);
                        if (i != _hover) setState(() => _hover = i);
                      },
                      onExit: (_) => setState(() => _hover = null),
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _AtlasPainter(
                          keys: _keys,
                          pack: pack,
                          built: _paths ? 0 : built,
                          building: building,
                          current: current,
                          px: _px,
                          rgba: sel.color,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // → arrows between the stages
              for (var i = 0; i < 2; i++)
                Positioned(
                  left: _stageW + i * (_stageW + _stageGap) + 12,
                  top: _stageTop + _stageH / 2 - 16,
                  width: _stageGap - 24,
                  height: 32,
                  child: DrawOn(
                    key: ValueKey('arrow$i$_paths'),
                    arrow: true,
                    strokeWidth: 2.5,
                    delay: Duration(milliseconds: 150 + 250 * i),
                    color: _paths ? BP.red : BP.amber,
                    path: (s) => Path()
                      ..moveTo(0, s.height / 2)
                      ..lineTo(s.width, s.height / 2),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  int? _tileAt(_Pack pack, Size size, Offset p) {
    final (o, scale) = _AtlasPainter.texRect(size, pack.tex);
    for (final e in pack.tiles.entries) {
      final r = (o + e.value.topLeft * scale) & (e.value.size * scale);
      if (r.contains(p)) return e.key;
    }
    return null;
  }

  Widget _stage(
    int i, {
    required String title,
    required Widget child,
    String? caption,
    Widget? captionWidget,
    Color captionColor = BP.inkDim,
    Color color = BP.lineDim,
  }) {
    final left = i * (_stageW + _stageGap);
    return Positioned(
      left: left,
      top: _stageTop - 42,
      width: _stageW,
      height: _stageH + 42 + 46,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: BT.display(28, color: BP.ink, weight: 400, height: 1)),
          const SizedBox(height: 14),
          SizedBox(
            height: _stageH,
            child: BpPanel(
              color: color,
              padding: const EdgeInsets.all(_panelPad),
              child: SizedBox.expand(child: child),
            ),
          ),
          const SizedBox(height: 12),
          ?captionWidget,
          if (caption != null) Text(caption, style: BT.mono(20, color: captionColor)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stage 1: the outline, drawn on
// ─────────────────────────────────────────────────────────────────────────────

class _OutlineView extends StatefulWidget {
  const _OutlineView({super.key, required this.outline, required this.solid, required this.duration});

  final GlyphOutline outline;
  final bool solid;
  final Duration duration;

  @override
  State<_OutlineView> createState() => _OutlineViewState();
}

class _OutlineViewState extends State<_OutlineView> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration)..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => CustomPaint(
      size: Size.infinite,
      painter: _OutlinePainter(widget.outline, widget.solid, Curves.easeInOutCubic.transform(_c.value)),
    ),
  );
}

class _OutlinePainter extends CustomPainter {
  _OutlinePainter(this.outline, this.solid, this.t);

  final GlyphOutline outline;
  final bool solid;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final b = outline.bounds;
    if (b.isEmpty) return;
    final s = math.min((size.width - 60) / b.width, (size.height - 60) / b.height);
    final origin = Offset(
      (size.width - b.width * s) / 2 - b.left * s,
      (size.height - b.height * s) / 2 + b.bottom * s,
    );
    final path = outline.toPath(scale: s, origin: origin);
    final fill = ((t - 0.6) / 0.4).clamp(0.0, 1.0);
    canvas.drawPath(
      path,
      Paint()..color = (solid ? BP.red : BP.ink).withValues(alpha: (solid ? 0.35 : 0.1) * fill),
    );
    canvas.drawPath(
      partialPath(path, t),
      Paint()
        ..color = solid ? BP.red : BP.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );
    for (final c in outline.contours) {
      for (final p in c) {
        final o = Offset(origin.dx + p.x * s, origin.dy - p.y * s);
        if (p.onCurve) {
          canvas.drawRect(
            Rect.fromCenter(center: o, width: 9 * fill, height: 9 * fill),
            Paint()..color = BP.amber,
          );
        } else {
          canvas.drawCircle(
            o,
            4.5 * fill,
            Paint()
              ..color = BP.line
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_OutlinePainter old) => old.outline != outline || old.solid != solid || old.t != t;
}

// ─────────────────────────────────────────────────────────────────────────────
// Stage 2: real coverage — the glyph rendered to an image, its pixels shown
// ─────────────────────────────────────────────────────────────────────────────

class _CoverageView extends StatefulWidget {
  const _CoverageView({
    super.key,
    required this.text,
    required this.px,
    required this.bucket,
    required this.color,
    required this.duration,
  });

  final String text;
  final double px;
  final int bucket;
  final bool color;
  final Duration duration;

  @override
  State<_CoverageView> createState() => _CoverageViewState();
}

class _Bitmap {
  _Bitmap(this.w, this.h, this.rgba);

  final int w;
  final int h;
  final Uint8List rgba;
}

final _coverageCache = <String, Future<_Bitmap>>{};

/// The coverage bitmap of [text] at [px] (shown at up to 64 px so individual
/// pixels stay visible), shifted by a subpixel [bucket].
Future<_Bitmap> _coverage(String text, double px, int bucket) {
  final size = math.min(px, 64.0);
  return _coverageCache.putIfAbsent(
    '$text@$size:$bucket',
    () => _CoverageViewState._rasterize(text, size, bucket / 4),
  );
}

class _CoverageViewState extends State<_CoverageView> {
  late Future<_Bitmap> _f = _coverage(widget.text, widget.px, widget.bucket);

  @override
  void didUpdateWidget(_CoverageView old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.px != widget.px || old.bucket != widget.bucket) {
      _f = _coverage(widget.text, widget.px, widget.bucket);
    }
  }

  static Future<_Bitmap> _rasterize(String text, double px, double dx) async {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: journeyStyle(px, color: Colors.white),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = (tp.width + 2).ceil().clamp(1, 200);
    final h = tp.height.ceil().clamp(1, 200);
    final rec = ui.PictureRecorder();
    tp.paint(Canvas(rec), Offset(1 + dx, 0));
    tp.dispose();
    final img = await rec.endRecording().toImage(w, h);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    final all = bytes!.buffer.asUint8List();
    // Crop to the inked pixels, like the atlas tile.
    var minX = w, minY = h, maxX = -1, maxY = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (all[(y * w + x) * 4 + 3] > 0) {
          minX = math.min(minX, x);
          maxX = math.max(maxX, x);
          minY = math.min(minY, y);
          maxY = math.max(maxY, y);
        }
      }
    }
    if (maxX < 0) return _Bitmap(1, 1, Uint8List(4));
    final cw = maxX - minX + 1;
    final ch = maxY - minY + 1;
    final out = Uint8List(cw * ch * 4);
    for (var y = 0; y < ch; y++) {
      for (var x = 0; x < cw; x++) {
        final s = ((y + minY) * w + (x + minX)) * 4;
        final d = (y * cw + x) * 4;
        out.setRange(d, d + 4, all, s);
      }
    }
    return _Bitmap(cw, ch, out);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_Bitmap>(
    future: _f,
    builder: (context, snap) {
      final b = snap.data;
      if (b == null) return const SizedBox.expand();
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: widget.duration,
        builder: (context, t, _) => CustomPaint(painter: _BitmapPainter(b, widget.color, t), size: Size.infinite),
      );
    },
  );
}

class _BitmapPainter extends CustomPainter {
  _BitmapPainter(this.b, this.color, this.t);

  final _Bitmap b;
  final bool color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = math.min((size.width - 24) / b.w, (size.height - 24) / b.h);
    final o = Offset((size.width - cell * b.w) / 2, (size.height - cell * b.h) / 2);
    final rows = (b.h * t).ceil();
    final paint = Paint();
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < b.w; x++) {
        final i = (y * b.w + x) * 4;
        final a = b.rgba[i + 3];
        if (a == 0) continue;
        paint.color = color
            ? Color.fromARGB(
                255,
                _un(b.rgba[i], a),
                _un(b.rgba[i + 1], a),
                _un(b.rgba[i + 2], a),
              ).withValues(alpha: a / 255)
            : Color.fromARGB(a, 255, 255, 255);
        canvas.drawRect(Rect.fromLTWH(o.dx + x * cell, o.dy + y * cell, cell, cell), paint);
      }
    }
    if (cell >= 4) {
      final grid = Paint()
        ..color = BP.lineFaint.withValues(alpha: 0.7)
        ..strokeWidth = 0.8;
      for (var x = 0; x <= b.w; x++) {
        canvas.drawLine(
          Offset(o.dx + x * cell, o.dy),
          Offset(o.dx + x * cell, o.dy + b.h * cell),
          grid,
        );
      }
      for (var y = 0; y <= b.h; y++) {
        canvas.drawLine(
          Offset(o.dx, o.dy + y * cell),
          Offset(o.dx + b.w * cell, o.dy + y * cell),
          grid,
        );
      }
    }
    // Scan line while "rasterizing"
    if (t < 1) {
      final y = o.dy + rows * cell;
      canvas.drawLine(
        Offset(o.dx - 10, y),
        Offset(o.dx + b.w * cell + 10, y),
        Paint()
          ..color = BP.amber
          ..strokeWidth = 3,
      );
    }
  }

  /// Undo premultiplication for display.
  static int _un(int c, int a) => a == 0 ? 0 : math.min(255, (c * 255 / a).round());

  @override
  bool shouldRepaint(_BitmapPainter old) => old.b != b || old.t != t;
}

// ─────────────────────────────────────────────────────────────────────────────
// Stage 3: the atlas texture, shelf-packed
// ─────────────────────────────────────────────────────────────────────────────

class _AtlasPainter extends CustomPainter {
  _AtlasPainter({
    required this.keys,
    required this.pack,
    required this.built,
    required this.building,
    required this.current,
    required this.px,
    required this.rgba,
  });

  final List<_Key> keys;
  final _Pack pack;
  final int built;
  final bool building;
  final int current;
  final double px;
  final bool rgba;

  /// The texture's top-left and texel → pixel scale within [size].
  static (Offset, double) texRect(Size size, double tex) {
    final scale = math.min(size.width, size.height) / tex;
    return (Offset((size.width - tex * scale) / 2, (size.height - tex * scale) / 2), scale);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final tex = pack.tex;
    final (o, scale) = texRect(size, tex);
    final texR = o & Size(tex * scale, tex * scale);
    canvas.drawRect(texR, Paint()..color = const Color(0xFF02070D));
    canvas.drawRect(
      texR,
      Paint()
        ..color = rgba ? BP.violet.withValues(alpha: 0.6) : BP.lineFaint
        ..style = PaintingStyle.stroke,
    );

    for (final e in pack.tiles.entries) {
      final i = e.key;
      if (i >= built) continue;
      final k = keys[i];
      final r = (o + e.value.topLeft * scale) & (e.value.size * scale);
      final hot = i == current;
      canvas.save();
      canvas.clipRect(r);
      if (k.color || k.font == null || k.shaped) {
        final tp = TextPainter(
          text: TextSpan(
            text: k.text,
            style: journeyStyle(px * scale, color: Colors.white),
          ),
          textDirection: k.shaped ? TextDirection.rtl : TextDirection.ltr,
        )..layout();
        tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
        tp.dispose();
      } else {
        final f = k.font!;
        final b = f.outline(k.glyph.glyphId).bounds;
        final s = px / f.unitsPerEm * scale;
        final path = f
            .outline(k.glyph.glyphId)
            .toPath(
              scale: s,
              origin: Offset(
                r.left + 1.5 * scale - b.left * s + k.bucket / 4 * scale,
                r.top + 1.5 * scale + b.bottom * s,
              ),
            );
        canvas.drawPath(path, Paint()..color = Colors.white);
      }
      canvas.restore();
      if (hot) {
        canvas.drawRect(r, Paint()..color = BP.amber.withValues(alpha: building ? 0.3 : 0.16));
      }
      canvas.drawRect(
        r,
        Paint()
          ..color = hot ? BP.amber : (rgba ? BP.violet : BP.lineDim).withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = hot ? 3 : 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(_AtlasPainter old) =>
      old.built != built || old.current != current || old.px != px || old.keys != keys || old.pack != pack;
}

// ─────────────────────────────────────────────────────────────────────────────
// A big ruler slider (the deck's BpSlider, sized for the back of the room)
// ─────────────────────────────────────────────────────────────────────────────

class _BigSlider extends StatelessWidget {
  const _BigSlider({
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
    required this.width,
  });

  final double value;
  final double min;
  final double max;
  final double width;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    void update(Offset p) => onChanged(min + (p.dx / width).clamp(0.0, 1.0) * (max - min));
    final t = ((value - min) / (max - min)).clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('size', style: BT.mono(24, color: BP.inkDim)),
        const SizedBox(width: 22),
        SizedBox(
          width: width,
          height: 48,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (d) => update(d.localPosition),
              onPanUpdate: (d) => update(d.localPosition),
              child: CustomPaint(painter: _SliderPainter(t)),
            ),
          ),
        ),
      ],
    );
  }
}

class _SliderPainter extends CustomPainter {
  _SliderPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final dim = Paint()
      ..color = BP.lineDim
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), dim);
    const ticks = 10;
    for (var i = 0; i <= ticks; i++) {
      final x = size.width * i / ticks;
      final h = i % 5 == 0 ? 12.0 : 6.0;
      canvas.drawLine(Offset(x, y - h), Offset(x, y + h), dim);
    }
    final x = size.width * t;
    canvas.drawLine(
      Offset(0, y),
      Offset(x, y),
      Paint()
        ..color = BP.line
        ..strokeWidth = 3,
    );
    final d = Path()
      ..moveTo(x, y - 15)
      ..lineTo(x + 15, y)
      ..lineTo(x, y + 15)
      ..lineTo(x - 15, y)
      ..close();
    canvas.drawPath(d, Paint()..color = BP.paper);
    canvas.drawPath(
      d,
      Paint()
        ..color = BP.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_SliderPainter old) => old.t != t;
}
