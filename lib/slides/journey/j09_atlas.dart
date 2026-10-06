import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../deck/font_data.dart';
import '../../deck/scripts.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'journey.dart';

/// Stop 9: Impeller turns each unique glyph key (font, glyph, size, subpixel
/// offset) into a small coverage bitmap packed into a glyph atlas.
class JAtlasSlide extends StatelessWidget {
  const JAtlasSlide({super.key});

  @override
  Widget build(BuildContext context) => JourneyFrame(
    stop: 9,
    title: (_) => 'Rasterize',
    builder: (context, d) => _Atlas(data: d),
  );
}

/// A unique glyph in the atlas.
class _Key {
  _Key({
    required this.text,
    required this.glyph,
    required this.bucket,
    required this.x,
    required this.color,
    this.form = '',
    int? gid,
  }) : gid = gid ?? glyph.glyphId;

  final String text;

  /// Its glyph id: a ligature's own (t t: #906), not its first letter's.
  final int gid;

  /// Arabic positional form (init/medi/fina/isol) — rendered via ZWJ context.
  final String form;
  bool get shaped => form.isNotEmpty;
  final JGlyph glyph;

  /// Subpixel bucket 0..3 → 0, .25, .5, .75
  final int bucket;
  final double x;
  final bool color;
  int uses = 1;

  FontData? get font => glyph.font;
  String get id => '${glyph.fontName}:$gid:${color ? text : ''}:$form:$bucket';
}

class _Atlas extends StatefulWidget {
  const _Atlas({required this.data});

  final JourneyData data;

  @override
  State<_Atlas> createState() => _AtlasState();
}

class _AtlasState extends State<_Atlas> with SingleTickerProviderStateMixin {
  static const _base = 48.0;
  double _scale = 1;
  int? _hover;
  int _cycle = 0;
  Timer? _timer;
  int _rebuilds = 0;

  late final AnimationController _build = AnimationController(vsync: this, duration: _buildTime);

  Duration get _buildTime => Duration(milliseconds: 500 * (_keys.isEmpty ? 1 : _keys.length) + 400);

  double get _px => _base * _scale;
  bool get _paths => _px > 250;

  late List<_Key> _keys = _computeKeys();

  @override
  void initState() {
    super.initState();
    _build.forward();
    _timer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
      if (_build.isCompleted && _hover == null && mounted) {
        setState(() => _cycle = (_cycle + 1) % math.max(1, _keys.length));
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _build.dispose();
    super.dispose();
  }

  List<_Key> _computeKeys() {
    final d = widget.data;
    final probe = TextProbe(TextSpan(text: d.text, style: journeyStyle(_px)));
    final keys = <String, _Key>{};
    final hasEmoji = d.glyphs.any((g) => g.script == Script.emoji);
    if (hasEmoji) {
      for (final (s, e) in probe.graphemes()) {
        final r = probe.rectFor(s, e);
        final g = d.glyphs.firstWhere((g) => g.start >= s);
        final k = _Key(
          text: d.text.substring(s, e),
          glyph: g,
          bucket: 0,
          x: r?.left ?? 0,
          color: true,
        );
        keys.putIfAbsent(k.id, () => k);
      }
    } else {
      final runes = d.text.runes.toList();
      // A key a glyph as shaped: a ligature (t t) is one glyph, one key.
      for (final run in d.run) {
        final gi = run.parts.first;
        final g = d.glyphs[gi];
        final text = d.text.substring(run.start, run.end);
        final r = probe.rectFor(run.start, run.end);
        // Spaces have no ink, so no tile. Glyphs from a platform fallback font
        // (e.g. kanji) are still A8 tiles, rendered from the text itself.
        final noInk = run.font == null ? text.trim().isEmpty : run.font!.outline(run.glyphId).contours.isEmpty;
        if (noInk) continue;
        final x = r?.left ?? 0;
        final frac = x - x.floorToDouble();
        final bucket = (frac * 4).round() % 4;
        final (form, display) = g.script == Script.arabic ? arabicForm(runes, gi) : ('', text);
        final k = _Key(text: display, glyph: g, gid: run.glyphId, bucket: bucket, x: x, color: false, form: form);
        final existing = keys[k.id];
        if (existing != null) {
          existing.uses++;
        } else {
          keys[k.id] = k;
        }
      }
    }
    probe.dispose();
    return keys.values.toList();
  }

  void _setScale(double s) {
    final snapped = (s * 4).round() / 4;
    if (snapped == _scale) return;
    setState(() {
      _scale = snapped;
      _keys = _computeKeys();
      _rebuilds++;
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
        final built = _paths
            ? 0
            : (_build.value * _buildTime.inMilliseconds / 500).floor().clamp(0, n);
        final current = _hover ?? (_build.isCompleted || _paths ? _cycle : math.min(built, n - 1));
        final sel = n == 0 ? null : _keys[current.clamp(0, n - 1)];
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Controls
            Positioned(
              left: 0,
              top: 0,
              child: Row(
                children: [
                  BpSlider(
                    label: 'scale',
                    value: _scale,
                    min: 0.5,
                    max: 6,
                    width: 300,
                    onChanged: _setScale,
                    format: (v) => '${v.toStringAsFixed(2)}×',
                  ),
                  const SizedBox(width: 10),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      '${_px.round()} px${_paths ? '  > 250 → paths' : ''}',
                      key: ValueKey(_paths),
                      style: BT.mono(16, color: _paths ? BP.red : BP.inkDim),
                    ),
                  ),
                ],
              ),
            ),
            // Glyph keys
            Positioned(
              left: 0,
              top: 70,
              width: 420,
              bottom: 0,
              child: _KeyList(
                keys: _keys,
                built: built,
                current: current,
                paths: _paths,
                onHover: (i) => setState(() => _hover = i),
              ),
            ),
            // Pipeline for the selected key
            if (sel != null)
              Positioned(
                left: 460,
                top: 70,
                width: 420,
                bottom: 0,
                child: _Pipeline(key: ValueKey('${sel.id}@$_px'), k: sel, px: _px, paths: _paths),
              ),
            // Atlases
            Positioned(
              left: 920,
              top: 0,
              right: 0,
              bottom: 0,
              child: _Atlases(
                keys: _keys,
                built: built,
                current: current,
                px: _px,
                paths: _paths,
                rebuilds: _rebuilds,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _KeyList extends StatelessWidget {
  const _KeyList({
    required this.keys,
    required this.built,
    required this.current,
    required this.paths,
    required this.onHover,
  });

  final List<_Key> keys;
  final int built;
  final int current;
  final bool paths;
  final ValueChanged<int?> onHover;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('glyph keys', style: BT.mono(14, color: BP.amber)),
        const SizedBox(height: 4),
        Text('font · glyph · size · subpixel x', style: BT.mono(12, color: BP.inkFaint)),
        const SizedBox(height: 14),
        for (var i = 0; i < math.min(keys.length, 9); i++)
          MouseRegion(
            onEnter: (_) => onHover(i),
            onExit: (_) => onHover(null),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: i == current ? BP.amber.withValues(alpha: 0.12) : Colors.transparent,
                border: Border.all(
                  color: i == current ? BP.amber : (i < built ? BP.lineDim : BP.lineFaint),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(width: 44, child: Text(keys[i].text, style: journeyStyle(26))),
                  Expanded(
                    child: Text(
                      keys[i].color
                          ? 'system · color'
                          : keys[i].font == null
                          ? 'system fallback · .${['00', '25', '50', '75'][keys[i].bucket]}'
                          : '${_short(keys[i].glyph.fontName)} · #${keys[i].gid}${keys[i].shaped ? '→${keys[i].form}' : ''} · .${['00', '25', '50', '75'][keys[i].bucket]}',
                      style: BT.mono(13, color: i < built || paths ? BP.ink : BP.inkFaint),
                    ),
                  ),
                  if (keys[i].uses > 1)
                    Text('×${keys[i].uses}', style: BT.mono(14, color: BP.green)),
                  const SizedBox(width: 8),
                  Text(
                    paths ? 'path' : (i < built ? (keys[i].color ? 'RGBA' : 'A8') : '…'),
                    style: BT.mono(
                      12,
                      color: paths ? BP.red : (keys[i].color ? BP.violet : BP.line),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static String _short(String f) => f.split(' ').map((w) => w[0]).join();
}

/// outline → Skia scaler → coverage bitmap, for one key.
class _Pipeline extends StatelessWidget {
  const _Pipeline({super.key, required this.k, required this.px, required this.paths});

  final _Key k;
  final double px;
  final bool paths;

  @override
  Widget build(BuildContext context) {
    final font = k.font;
    return Column(
      children: [
        SizedBox(
          height: 200,
          child: BpPanel(
            label: k.color
                ? 'color glyph'
                : (font == null
                      ? 'platform fallback glyph'
                      : (k.shaped ? 'cmap outline · before GSUB' : 'glyf outline')),
            padding: const EdgeInsets.all(10),
            child: SizedBox.expand(
              child: k.color || font == null
                  ? Center(child: Text(k.text, style: journeyStyle(110)))
                  : CustomPaint(
                      painter: _OutlinePainter(font.outline(k.gid), font, paths),
                    ),
            ),
          ),
        ),
        SizedBox(
          height: 58,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 50,
                child: DrawOn(
                  key: ValueKey('$px${k.id}'),
                  arrow: true,
                  color: paths ? BP.red : BP.amber,
                  path: (s) => Path()
                    ..moveTo(s.width / 2, 4)
                    ..lineTo(s.width / 2, s.height - 4),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                paths ? 'fill path each frame' : 'Skia scaler · grayscale AA',
                style: BT.mono(13, color: paths ? BP.red : BP.amber),
              ),
            ],
          ),
        ),
        Expanded(
          child: BpPanel(
            label: paths ? 'no bitmap' : 'coverage @ ${px.round()} px',
            padding: const EdgeInsets.all(10),
            color: paths ? BP.red : BP.lineDim,
            child: paths
                ? Center(
                    child: Text('→ DrawPath', style: BT.mono(22, color: BP.red)),
                  )
                : _CoverageView(text: k.text, px: px, bucket: k.bucket, color: k.color),
          ),
        ),
      ],
    );
  }
}

class _OutlinePainter extends CustomPainter {
  _OutlinePainter(this.outline, this.font, this.solid);

  final GlyphOutline outline;
  final FontData font;
  final bool solid;

  @override
  void paint(Canvas canvas, Size size) {
    final b = outline.bounds;
    if (b.isEmpty) return;
    final s = math.min((size.width - 20) / b.width, (size.height - 20) / b.height);
    final origin = Offset(
      (size.width - b.width * s) / 2 - b.left * s,
      (size.height - b.height * s) / 2 + b.bottom * s,
    );
    final path = outline.toPath(scale: s, origin: origin);
    canvas.drawPath(
      path,
      Paint()..color = (solid ? BP.red : BP.ink).withValues(alpha: solid ? 0.35 : 0.08),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = solid ? BP.red : BP.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    for (final c in outline.contours) {
      for (final p in c) {
        final o = Offset(origin.dx + p.x * s, origin.dy - p.y * s);
        if (p.onCurve) {
          canvas.drawRect(
            Rect.fromCenter(center: o, width: 5, height: 5),
            Paint()..color = BP.amber,
          );
        } else {
          canvas.drawCircle(
            o,
            2.6,
            Paint()
              ..color = BP.line
              ..style = PaintingStyle.stroke,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_OutlinePainter old) => old.outline != outline || old.solid != solid;
}

/// Real coverage: the glyph is rendered to an image and its pixels shown.
class _CoverageView extends StatefulWidget {
  const _CoverageView({
    required this.text,
    required this.px,
    required this.bucket,
    required this.color,
  });

  final String text;
  final double px;
  final int bucket;
  final bool color;

  @override
  State<_CoverageView> createState() => _CoverageViewState();
}

class _Bitmap {
  _Bitmap(this.w, this.h, this.rgba);

  final int w;
  final int h;
  final Uint8List rgba;
}

class _CoverageViewState extends State<_CoverageView> {
  static final _cache = <String, Future<_Bitmap>>{};
  late Future<_Bitmap> _f = _load();

  Future<_Bitmap> _load() {
    // Shown at up to 64 px so individual pixels stay visible.
    final px = math.min(widget.px, 64.0);
    final key = '${widget.text}@$px:${widget.bucket}';
    return _cache.putIfAbsent(key, () => _rasterize(widget.text, px, widget.bucket / 4));
  }

  @override
  void didUpdateWidget(_CoverageView old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.px != widget.px || old.bucket != widget.bucket) _f = _load();
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
      return Column(
        children: [
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 700),
              builder: (context, t, _) =>
                  CustomPaint(painter: _BitmapPainter(b, widget.color, t), size: Size.infinite),
            ),
          ),
          Text('${b.w} × ${b.h} px', style: BT.mono(12, color: BP.inkFaint)),
        ],
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
    final cell = math.min(size.width / b.w, size.height / b.h);
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
        ..color = BP.lineFaint.withValues(alpha: 0.6)
        ..strokeWidth = 0.5;
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
        Offset(o.dx - 6, y),
        Offset(o.dx + b.w * cell + 6, y),
        Paint()
          ..color = BP.amber
          ..strokeWidth = 2,
      );
    }
  }

  /// Undo premultiplication for display.
  static int _un(int c, int a) => a == 0 ? 0 : math.min(255, (c * 255 / a).round());

  @override
  bool shouldRepaint(_BitmapPainter old) => old.b != b || old.t != t;
}

/// The A8 (alpha) and RGBA (color) atlases, shelf-packed.
class _Atlases extends StatelessWidget {
  const _Atlases({
    required this.keys,
    required this.built,
    required this.current,
    required this.px,
    required this.paths,
    required this.rebuilds,
  });

  final List<_Key> keys;
  final int built;
  final int current;
  final double px;
  final bool paths;
  final int rebuilds;

  @override
  Widget build(BuildContext context) {
    final mask = [
      for (var i = 0; i < keys.length; i++)
        if (!keys[i].color) i,
    ];
    final color = [
      for (var i = 0; i < keys.length; i++)
        if (keys[i].color) i,
    ];
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: paths ? 0.25 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('glyph atlas', style: BT.mono(16, color: BP.amber)),
              const Spacer(),
              Text('re-rasterized ×$rebuilds', style: BT.mono(13, color: BP.inkFaint)),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            flex: 3,
            child: BpPanel(
              label: 'A8 · alpha',
              padding: const EdgeInsets.all(12),
              child: CustomPaint(
                painter: _AtlasPainter(
                  keys: keys,
                  which: mask,
                  built: built,
                  current: current,
                  px: px,
                  rgba: false,
                ),
                size: Size.infinite,
              ),
            ),
          ),
          const SizedBox(height: 26),
          Expanded(
            flex: 2,
            child: BpPanel(
              label: 'RGBA · color',
              color: BP.violet,
              padding: const EdgeInsets.all(12),
              child: CustomPaint(
                painter: _AtlasPainter(
                  keys: keys,
                  which: color,
                  built: built,
                  current: current,
                  px: px,
                  rgba: true,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AtlasPainter extends CustomPainter {
  _AtlasPainter({
    required this.keys,
    required this.which,
    required this.built,
    required this.current,
    required this.px,
    required this.rgba,
  });

  final List<_Key> keys;
  final List<int> which;
  final int built;
  final int current;
  final double px;
  final bool rgba;

  @override
  void paint(Canvas canvas, Size size) {
    // Texture background
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF02070D));
    if (which.isEmpty) {
      _text(canvas, size.center(Offset.zero), 'empty', BP.inkFaint, center: true);
      return;
    }
    // Tile sizes in texels (ink bounds + 1 texel padding).
    final tiles = <int, Size>{};
    for (final i in which) {
      final k = keys[i];
      final f = k.font;
      if (k.color || f == null) {
        tiles[i] = Size(px * 1.25, px * 1.25);
      } else if (k.shaped) {
        final tp = TextPainter(
          text: TextSpan(text: k.text, style: journeyStyle(px)),
          textDirection: TextDirection.rtl,
        )..layout();
        tiles[i] = Size(tp.width + 3, tp.height * 0.85);
        tp.dispose();
      } else {
        final b = f.outline(k.gid).bounds;
        final s = px / f.unitsPerEm;
        tiles[i] = Size(b.width * s + 3, b.height * s + 3);
      }
    }
    // Shelf pack into a power-of-two texture.
    var tex = 64.0;
    late Map<int, Offset> pos;
    while (true) {
      pos = {};
      var x = 0.0, y = 0.0, shelf = 0.0;
      var ok = true;
      final order = [...which]..sort((a, b) => tiles[b]!.height.compareTo(tiles[a]!.height));
      for (final i in order) {
        final t = tiles[i]!;
        if (x + t.width > tex) {
          x = 0;
          y += shelf;
          shelf = 0;
        }
        if (y + t.height > tex || t.width > tex) {
          ok = false;
          break;
        }
        pos[i] = Offset(x, y);
        x += t.width;
        shelf = math.max(shelf, t.height);
      }
      if (ok) break;
      tex *= 2;
    }
    final scale = math.min(size.width, size.height) / tex;
    final o = Offset((size.width - tex * scale) / 2, 0);
    canvas.drawRect(
      (o & Size(tex * scale, tex * scale)),
      Paint()
        ..color = BP.lineFaint
        ..style = PaintingStyle.stroke,
    );
    _text(canvas, o + Offset(tex * scale + 8, 0), '${tex.round()}²', BP.inkFaint);

    for (final i in which) {
      if (i >= built) continue;
      final k = keys[i];
      final r = (o + pos[i]! * scale) & (tiles[i]! * scale);
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
        final b = f.outline(k.gid).bounds;
        final s = px / f.unitsPerEm * scale;
        final path = f
            .outline(k.gid)
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
      canvas.drawRect(
        r,
        Paint()
          ..color = hot ? BP.amber : (rgba ? BP.violet : BP.lineDim).withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = hot ? 2 : 0.8,
      );
    }
  }

  void _text(Canvas c, Offset at, String s, Color color, {bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: BT.mono(12, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center ? at - Offset(tp.width / 2, tp.height / 2) : at);
    tp.dispose();
  }

  @override
  bool shouldRepaint(_AtlasPainter old) =>
      old.built != built || old.current != current || old.px != px || old.keys != keys;
}
