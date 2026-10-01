import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:characters/characters.dart';
import 'package:flutter/painting.dart';

import '../../deck/theme.dart';
import '../../worlds/factory/factory_kit.dart' show TextCache;
import '../layout.dart';
import '../model.dart';
import '../raster.dart';
import 'site_plan.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Celebration: fireworks whose sparks are glyphs from many scripts (and from
// the name itself), confetti, and the banner hung from the crane with the
// name and its stats. Plus dust puffs. All pure functions of time (seeded by
// the job), drawn in batches: glyph sprites come from an atlas and go out in
// one drawRawAtlas call.
// ─────────────────────────────────────────────────────────────────────────────

const _ja = Locale('ja');

TextStyle jaStyle(double size, {Color color = BP.ink, double weight = 400}) => BT
    .sample(size, color: color, weight: weight)
    .copyWith(
      locale: _ja,
      fontFamilyFallback: const [BP.arabic, 'Hiragino Sans', 'Hiragino Kaku Gothic ProN'],
    );

const fireColors = [BP.amber, BP.pink, BP.green, BP.violet, BP.coral, BP.line, BP.ink];

/// Glyphs for the fireworks, grouped by burst kind.
const _flowers = ['花', '✿', '桜', '❀'];
const _stars = ['✦', '★', '☆', '✧'];
const _scripts = ['A', 'あ', 'ア', '字', 'ß', 'Ж', 'Ω', 'ض', 'क', 'ก', '한', 'é', 'ñ', 'g'];
const _all = [..._flowers, ..._stars, ..._scripts];

/// White glyph sprites in one image, tinted when drawn.
class GlyphAtlas {
  GlyphAtlas._(this.image, this.index, this.cols, this.cell);

  /// Renders [glyphs] white, one per cell, off the frame (asynchronously, so
  /// building it never stalls a frame).
  static Future<GlyphAtlas> build(List<String> glyphs, TextStyle Function(double size) style, {double cell = 64}) async {
    const cols = 8;
    final rows = (glyphs.length + cols - 1) ~/ cols;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final index = <String, int>{};
    for (var i = 0; i < glyphs.length; i++) {
      final tp = TextPainter(
        text: TextSpan(text: glyphs[i], style: style(cell * 0.62)),
        textDirection: TextDirection.ltr,
      )..layout();
      final cx = (i % cols) * cell + cell / 2;
      final cy = (i ~/ cols) * cell + cell / 2;
      tp.paint(c, Offset(cx - tp.width / 2, cy - tp.height / 2));
      tp.dispose();
      index[glyphs[i]] = i;
    }
    final pic = rec.endRecording();
    final image = await pic.toImage(cols * cell.toInt(), math.max(1, rows) * cell.toInt());
    pic.dispose();
    return GlyphAtlas._(image, index, cols, cell);
  }

  final double cell;
  final int cols;
  final ui.Image image;
  final Map<String, int> index;

  Rect rectOf(int i) => Rect.fromLTWH((i % cols) * cell, (i ~/ cols) * cell, cell, cell);

  void dispose() => image.dispose();
}

/// Collects sprites, then draws them all at once.
class SpriteBatch {
  final _xf = <double>[];
  final _rc = <double>[];
  final _cl = <int>[];

  void add(GlyphAtlas a, int glyph, Offset at, double scale, double rot, Color color) {
    final r = a.rectOf(glyph);
    final sc = math.cos(rot) * scale, ss = math.sin(rot) * scale;
    final ax = a.cell / 2, ay = a.cell / 2;
    _xf.addAll([sc, ss, at.dx - sc * ax + ss * ay, at.dy - ss * ax - sc * ay]);
    _rc.addAll([r.left, r.top, r.right, r.bottom]);
    _cl.add(color.toARGB32());
  }

  static final _paint = Paint()..filterQuality = FilterQuality.medium;

  void flush(Canvas c, GlyphAtlas a) {
    if (_cl.isEmpty) return;
    c.drawRawAtlas(
      a.image,
      Float32List.fromList(_xf),
      Float32List.fromList(_rc),
      Int32List.fromList(_cl),
      BlendMode.modulate,
      null,
      _paint,
    );
    _xf.clear();
    _rc.clear();
    _cl.clear();
  }
}

/// Fireworks for one celebration. [box] is kept free (the banner).
class Fireworks {
  Fireworks(this.seed, this.start, this.len);

  final int seed;
  final double start;
  final double len;

  /// Bursts go left of, right of and above the banner (and never on it).
  Offset _burstAt(int k, Rect? box) {
    final h1 = hash(seed, k, 1), h2 = hash(seed, k, 2), pick = hash(seed, k, 3);
    if (box == null) return Offset(712 + 770 * h1, 70 + 260 * h2);
    final leftW = box.left - 50 - 712, rightW = 1490 - (box.right + 50);
    if (pick < 0.4 && leftW > 40) return Offset(712 + leftW * h1, 90 + 270 * h2);
    if (pick < 0.8 && rightW > 40) return Offset(box.right + 50 + rightW * h1, 90 + 270 * h2);
    final aboveH = box.top - 40 - 50;
    if (aboveH > 30) return Offset(box.left + box.width * h1, 50 + aboveH * h2);
    return Offset(712 + 770 * h1, box.bottom + 40 + 30 * h2);
  }

  void draw(Canvas c, double t, GlyphAtlas common, GlyphAtlas? name, Rect? box, SpriteBatch batch, SpriteBatch batchName) {
    final u = t - start;
    if (u < 0 || u > len + 2.5) return;
    const life = 1.9, climb = 0.55;
    final trail = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.4;
    for (var k = 0;; k++) {
      final t0 = 0.3 + k * 0.62 + 0.3 * hash(seed, k, 9);
      if (t0 > len - 1.2) break;
      final age = u - t0;
      if (age < 0 || age > climb + life) continue;
      final burst = _burstAt(k, box);
      final color = fireColors[(seed + k) % fireColors.length];
      if (age < climb) {
        final launch = Offset(burst.dx + (hash(seed, k, 5) - 0.5) * 140, BL.groundY - 30);
        final f = 1 - math.pow(1 - age / climb, 2).toDouble();
        final p = Offset.lerp(launch, burst, f)!;
        final back = Offset.lerp(launch, burst, math.max(0, f - 0.14))!;
        c.drawLine(back, p, trail..color = BP.amber.withValues(alpha: 0.8));
        c.drawCircle(p, 1.8, Paint()..color = BP.ink);
        continue;
      }
      final a = age - climb;
      final fade = 1 - math.pow(a / life, 2).toDouble();
      if (a < 0.2) {
        c.drawCircle(burst, 6 + 60 * a, Paint()..color = color.withValues(alpha: 0.35 * (1 - a / 0.2)));
        c.drawCircle(burst, 3 + 12 * a, Paint()..color = BP.ink.withValues(alpha: 0.8 * (1 - a / 0.2)));
      }
      final kind = k % 4;
      final useName = kind == 0 && name != null && name.index.isNotEmpty;
      final atlas = useName ? name : common;
      final glyphs = useName
          ? name.index.values.toList()
          : [
              for (final g in (kind == 1 ? _flowers : (kind == 2 ? _stars : _scripts)))
                ?common.index[g],
            ];
      if (glyphs.isEmpty) continue;
      final n = useName ? 14 : 16;
      final into = useName ? batchName : batch;
      // Two passes: a soft glow under every spark, then the sparks.
      for (var pass = 0; pass < 2; pass++) {
        for (var j = 0; j < n; j++) {
          final inner = j.isOdd && !useName;
          final ang = j / n * math.pi * 2 + hash(seed, k, j) * 0.4;
          final sp = (inner ? 70.0 : 125.0) + 50 * hash(seed, j, k + 3);
          final d = 6 + sp * (1 - math.exp(-2.4 * a)) / 2.4;
          final p = burst + Offset(math.cos(ang) * d, math.sin(ang) * d + 22 * a * a);
          final g = glyphs[(j + k) % glyphs.length];
          final col = useName ? fireColors[(k + j) % fireColors.length] : color;
          final scale = (useName ? 0.64 : 0.56) + 0.18 * (1 - a / life);
          final rot = (hash(seed, k, j + 50) - 0.5) * 0.7 + a * (hash(j, k) - 0.5) * 1.6;
          final alpha = c01(fade) * c01(a / 0.08);
          if (pass == 0) {
            into.add(atlas, g, p, scale * 1.75, rot, col.withValues(alpha: 0.2 * alpha));
          } else {
            into.add(atlas, g, p, scale, rot, col.withValues(alpha: alpha));
          }
        }
      }
    }
    batch.flush(c, common);
    if (name != null) batchName.flush(c, name);
  }
}

/// Confetti raining over the site during a celebration.
void confetti(Canvas c, double t, double start, double len, int seed) {
  final u = t - start;
  if (u < 0 || u > len + 4) return;
  const n = 190;
  final pos = Float32List(n * 8);
  final col = Int32List(n * 4);
  final idx = Uint16List(n * 6);
  var m = 0;
  for (var i = 0; i < n; i++) {
    final s = 0.3 + (len - 3) * hash(i, seed, 5);
    final a = u - s;
    if (a < 0) continue;
    final fall = 55 + 55 * hash(i, 6, seed);
    final y = 20 + 60 * hash(i, 7) + fall * a;
    if (y > BL.groundY - 2) continue;
    final x = 670 + 820 * hash(i, 8, seed) + (12 + 16 * hash(i, 9)) * math.sin(a * (1.6 + 1.6 * hash(i, 10)) + i);
    final spin = a * (5 + 7 * hash(i, 11)) + i;
    final w = 5.0, h = 1.4 + 2.8 * math.cos(spin).abs();
    final rot = 0.6 * math.sin(spin * 0.7);
    final fade = 1 - seg(y, BL.groundY - 40, BL.groundY - 2);
    final cl = fireColors[i % (fireColors.length - 1)].withValues(alpha: 0.9 * fade);
    final ca = math.cos(rot), sa = math.sin(rot);
    final p = m * 8;
    final ux = ca * w, uy = sa * w, vx = -sa * h, vy = ca * h;
    pos[p] = x - ux - vx;
    pos[p + 1] = y - uy - vy;
    pos[p + 2] = x + ux - vx;
    pos[p + 3] = y + uy - vy;
    pos[p + 4] = x + ux + vx;
    pos[p + 5] = y + uy + vy;
    pos[p + 6] = x - ux + vx;
    pos[p + 7] = y - uy + vy;
    final argb = cl.toARGB32();
    for (var j = 0; j < 4; j++) {
      col[m * 4 + j] = argb;
    }
    final q = m * 6, v = m * 4;
    idx[q] = v;
    idx[q + 1] = v + 1;
    idx[q + 2] = v + 2;
    idx[q + 3] = v;
    idx[q + 4] = v + 2;
    idx[q + 5] = v + 3;
    m++;
  }
  if (m == 0) return;
  final verts = ui.Vertices.raw(
    ui.VertexMode.triangles,
    Float32List.sublistView(pos, 0, m * 8),
    colors: Int32List.sublistView(col, 0, m * 4),
    indices: Uint16List.sublistView(idx, 0, m * 6),
  );
  c.drawVertices(verts, BlendMode.dst, Paint());
  verts.dispose();
}

// ── Stats ───────────────────────────────────────────────────────────────────

/// Scripts used by [name], Japanese + English.
List<String> scriptsOf(String name) {
  final found = <String>[];
  void add(String s) {
    if (!found.contains(s)) found.add(s);
  }

  for (final r in name.runes) {
    if ((r >= 0x4E00 && r <= 0x9FFF) || (r >= 0x3400 && r <= 0x4DBF) || r == 0x3005 || r == 0x3006 || (r >= 0xF900 && r <= 0xFAFF) || r >= 0x20000) {
      add('漢字 Kanji');
    } else if (r >= 0x3040 && r <= 0x309F) {
      add('ひらがな Hiragana');
    } else if ((r >= 0x30A0 && r <= 0x30FF && r != 0x30FB) || (r >= 0x31F0 && r <= 0x31FF) || (r >= 0xFF66 && r <= 0xFF9F)) {
      add('カタカナ Katakana');
    } else if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A) || (r >= 0xC0 && r <= 0x24F) || (r >= 0x1E00 && r <= 0x1EFF)) {
      add('ラテン Latin');
    } else if ((r >= 0xAC00 && r <= 0xD7AF) || (r >= 0x1100 && r <= 0x11FF) || (r >= 0x3130 && r <= 0x318F)) {
      add('ハングル Hangul');
    } else if (r >= 0x400 && r <= 0x4FF) {
      add('キリル Cyrillic');
    } else if (r >= 0x370 && r <= 0x3FF) {
      add('ギリシャ Greek');
    } else if (r >= 0x600 && r <= 0x6FF) {
      add('アラビア Arabic');
    } else if (r >= 0x590 && r <= 0x5FF) {
      add('ヘブライ Hebrew');
    } else if (r >= 0x900 && r <= 0x97F) {
      add('デーヴァナーガリー Devanagari');
    } else if (r >= 0xE00 && r <= 0xE7F) {
      add('タイ Thai');
    } else if (r >= 0x30 && r <= 0x39) {
      add('数字 Digits');
    }
  }
  return found;
}

int glyphCount(String name) => name.characters.where((g) => g.trim().isNotEmpty).length;

String mmss(double s) {
  final v = s.round();
  return '${v ~/ 60}:${(v % 60).toString().padLeft(2, '0')}';
}

/// The banner the crane holds up: 「完成！ Done!」, the name ✓, stats.
class Banner {
  Banner(Job j, TextCache text) {
    final r = j.raster!;
    title = text.get('完成！ Done!', jaStyle(26, color: BP.amber, weight: 600));
    name = text.get(j.name, NameRaster.nameStyle(40, color: BP.ink));
    tick = text.get(' ✓', BT.sample(36, color: BP.green, weight: 700));
    final scripts = scriptsOf(j.name);
    line1 = text.get(
      '${r.bricks.length} bricks · レンガ    built in · 建設 ${mmss(j.buildLen)}',
      jaStyle(15, color: BP.inkDim),
    );
    line2 = text.get(
      '${glyphCount(j.name)} ${glyphCount(j.name) == 1 ? 'glyph' : 'glyphs'} · 文字    ${scripts.isEmpty ? 'script · 文字体系 ?' : scripts.join(' + ')}',
      jaStyle(15, color: BP.inkDim),
    );
    final w = [title.width, name.width + tick.width, line1.width, line2.width].reduce(math.max) + 48;
    width = w.clamp(380.0, 720.0);
    height = 22 + title.height + name.height + line1.height + line2.height + 18;
  }

  late final TextPainter title, name, tick, line1, line2;
  late final double width;
  late final double height;

  /// Where it hangs for a wall centred at [cx].
  Rect rect(double cx) {
    final x = cx.clamp(680 + width / 2, 1488 - width / 2);
    return Rect.fromLTWH(x - width / 2, 156, width, height);
  }

  /// [open] 0..1 unrolls it from the top bar.
  void draw(Canvas c, Rect r, double open, double t) {
    final st = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // Ropes up to the jib.
    for (final x in [r.left + 26, r.right - 26]) {
      c.drawLine(Offset(x, BL.craneJibY + 1), Offset(x, r.top), st..color = BP.inkDim..strokeWidth = 1);
    }
    final bar = Rect.fromLTRB(r.left - 6, r.top - 4, r.right + 6, r.top + 2);
    c.drawRect(bar, Paint()..color = BP.panel);
    c.drawRect(bar, st..color = BP.lineDim..strokeWidth = 1.2);
    if (open <= 0.01) return;
    final h = r.height * open;
    final sway = math.sin(t * 1.3) * 1.5 * open;
    final cloth = Path()
      ..moveTo(r.left, r.top + 2)
      ..lineTo(r.right, r.top + 2)
      ..lineTo(r.right + sway, r.top + h)
      ..quadraticBezierTo(r.center.dx + sway, r.top + h + 6 * open, r.left + sway, r.top + h)
      ..close();
    c.drawPath(cloth, Paint()..color = const Color(0xFF0E2340));
    c.save();
    c.clipPath(cloth);
    var y = r.top + 14;
    title.paint(c, Offset(r.center.dx - title.width / 2, y));
    y += title.height;
    final nw = name.width + tick.width;
    name.paint(c, Offset(r.center.dx - nw / 2, y));
    tick.paint(c, Offset(r.center.dx - nw / 2 + name.width, y + (name.height - tick.height) / 2));
    y += name.height + 4;
    line1.paint(c, Offset(r.center.dx - line1.width / 2, y));
    y += line1.height;
    line2.paint(c, Offset(r.center.dx - line2.width / 2, y));
    c.restore();
    c.drawPath(cloth, st..color = BP.amber..strokeWidth = 2);
    // Rolled-up end while unrolling.
    if (open < 1) {
      final roll = Rect.fromLTRB(r.left - 2 + sway, r.top + h - 4, r.right + 2 + sway, r.top + h + 4);
      c.drawRRect(RRect.fromRectAndRadius(roll, const Radius.circular(4)), Paint()..color = BP.panel);
      c.drawRRect(RRect.fromRectAndRadius(roll, const Radius.circular(4)), st..color = BP.amber..strokeWidth = 1.4);
    }
  }
}

/// Dust: a few expanding, fading outlines per puff.
class Dust {
  final _puffs = <(double, double, double, double)>[]; // x, y, size, born

  void add(double x, double y, double size, double t) {
    _puffs.removeWhere((q) => t - q.$4 > 1.6);
    _puffs.add((x, y, size, t));
    if (_puffs.length > 48) _puffs.removeAt(0);
  }

  void clear() => _puffs.clear();

  void draw(Canvas c, double t) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final fill = Paint();
    for (final (x, y, s, born) in _puffs) {
      final a = (t - born) / 1.6;
      if (a < 0 || a >= 1) continue;
      final e = eo(a);
      for (var k = 0; k < 5; k++) {
        final side = (k - 2) / 2;
        final ox = side * s * (0.35 + 0.6 * e);
        final oy = -s * (0.15 + 0.5 * e) * (1 - 0.4 * side.abs()) - 10 * a;
        final r = s * (0.22 + 0.4 * e) * (1 - 0.25 * side.abs());
        final alpha = (1 - a) * (1 - a);
        fill.color = BP.inkFaint.withValues(alpha: 0.32 * alpha);
        c.drawCircle(Offset(x + ox, y + oy), r, fill);
        if (k.isEven) {
          p.color = BP.inkDim.withValues(alpha: 0.35 * alpha);
          c.drawCircle(Offset(x + ox, y + oy), r, p);
        }
      }
    }
  }
}

/// Common glyph atlas for the fireworks.
Future<GlyphAtlas> commonGlyphs() =>
    GlyphAtlas.build(_all, (s) => jaStyle(s, color: const Color(0xFFFFFFFF), weight: 600));

/// The name's own glyphs (graphemes) as sprites.
Future<GlyphAtlas> nameGlyphs(String name) {
  final gs = <String>[];
  for (final g in name.characters) {
    if (g.trim().isEmpty || gs.contains(g)) continue;
    gs.add(g);
  }
  return GlyphAtlas.build(gs.isEmpty ? ['✦'] : gs, (s) => NameRaster.nameStyle(s, color: const Color(0xFFFFFFFF)));
}
