import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'figure.dart';
import 'kit.dart';
import 'motion.dart';
import 'shot.dart';
import 'vignette.dart';

/// 字形倉庫 · The glyph atlas, across the right-hand side street from the
/// plaza (where a block was): a warehouse whose back wall is the atlas —
/// every glyph drawn so far, baked once into a little bitmap and packed
/// onto shelves, row by row (each shelf as tall as what's on it). A new
/// glyph comes off the rasterizer's press (its key on its tag: the font,
/// the glyph, the size, the subpixel offset), and the forklift slots it in
/// at the end of the first shelf with room. Then a frame is drawn: each
/// letter of "Flutter" is a quad cut from the atlas — beams from the tiles
/// to the screen, all in one go (one draw call); the t twice, baked once.
class GlyphAtlas extends Vignette {
  GlyphAtlas(super.kit);

  @override
  String get name => 'atlas';
  @override
  String get kick => 'GLYPH ATLAS';
  @override
  String get line => 'Baked once, drawn every frame';
  @override
  String get note => 'each glyph a bitmap packed on a shelf; a word is quads cut from it';

  @override
  double get loop => 15;
  @override
  double get visit => 12.0;

  /// Facing the plaza across the street.
  @override
  final frame = trs(vm.Vector3(28.4, 0, 12.8), rotY: math.pi / 2);

  /// The atlas board (its middle, size) on the back wall.
  static const _ax = 0.0, _ay = 2.45, _az = 7.6, _aw = 8.4, _ah = 3.6;

  /// What's on its shelves (in packing order): each glyph and its size
  /// (pixels, as baked).
  static const _baked = [
    ('F', 64), ('l', 64), ('u', 64), ('t', 64), ('e', 64), ('r', 64), ('K', 64), ('a', 64), ('i', 64), ('g', 64), //
    ('文', 56), ('字', 56), ('あ', 56), ('ア', 56), ('ب', 56), ('ت', 56), ('क', 56), ('ก', 56), //
    ('H', 44), ('o', 44), ('n', 44), ('d', 44), ('W', 44), ('y', 44), ('Ω', 44), ('ж', 44), ('Å', 44), //
    ('1', 36), ('2', 36), ('?', 36), ('&', 36), ('@', 36), ('3', 36), ('4', 36), ('5', 36), ('6', 36), ('7', 36), ('8', 36), //
    ('9', 36), ('0', 36), ('#', 36), ('+', 36), ('=', 36), ('*', 36),
  ];

  /// The new one, and the word drawn (the atlas's glyphs, by index).
  static const _newGlyph = '%';
  static const _word = [0, 1, 2, 3, 3, 4, 5];

  /// Where each baked glyph's tile is on the board (its middle, size;
  /// metres, in the board's plane), and the free spot the new one goes to.
  final _tiles = <Rect>[];
  late Rect _free;

  // The timeline: baked, carried, lifted in; the frame drawn.
  static const _press = 0.6, _baked1 = 1.8, _carry = 2.2, _there = 5.2, _lift = 6.4, _in = 7.0, _draw = 7.8, _drawn = 10.5;

  late final Node _newTile, _screenText;
  int _driver = -1;
  final _p = FigurePose();
  bool _ready = false;

  @override
  List<(String, TextStyle)> get fontRuns => [
    (_baked.map((e) => e.$1).join(), const TextStyle(fontFamily: BP.display)),
    ('GLYPH ATLAS Flutter %', const TextStyle(fontFamily: BP.display)),
  ];

  @override
  Future<void> init() async {
    makePool(boxes: 24, glows: 40, cyls: 8);
    _pack();
    final b = Batch();
    final m = pbr(rgb(1, 1, 1), roughness: 0.75);
    final glass = pbr(rgb(1, 1, 1), roughness: 0.15, metallic: 0.4);
    final wall = Vignette.c(0xCFC8BA), trim = Vignette.c(0xE8A33D);
    box(b, m, 13, 0.2, 9.6, 0, 0.1, 4.8, Vignette.c(0x8E8A82));
    box(b, m, 13, 9, 0.3, 0, 4.5, 9.45, wall);
    for (final x in [-6.35, 6.35]) {
      box(b, m, 0.3, 9, 9.6, x, 4.5, 4.8, wall);
    }
    box(b, m, 13, 4.2, 0.3, 0, 6.9, 0.15, wall);
    box(b, m, 13.2, 0.25, 0.4, 0, 4.85, 0.1, trim);
    for (var k = -4; k <= 4; k++) {
      box(b, glass, 1.0, 1.4, 0.05, k * 1.35, 6.9, -0.02, Vignette.c(0x9CC4E0));
    }
    box(b, m, 13.4, 0.3, 10, 0, 9.1, 4.8, Vignette.c(0x5A6470));
    b.buildInto(shell, 'glyph atlas', lightChannelMask: 0x01);
    // The atlas's frame and its shelves' ledges; the press at the left; the
    // screen on the right-hand wall.
    box(b, m, _aw + 0.3, _ah + 0.3, 0.1, _ax, _ay, _az + 0.12, Vignette.c(0x2B2E33));
    box(b, m, 1.2, 1.1, 1.0, -5.2, 0.55, 2.4, Vignette.c(0x3A4252));
    box(b, m, 1.0, 0.25, 0.8, -5.2, 1.55, 2.4, Vignette.c(0x5A6470));
    box(b, m, 0.12, 2.2, 0.12, -5.65, 1.1, 2.0, Vignette.c(0x3A4252));
    box(b, m, 0.12, 2.2, 0.12, -4.75, 1.1, 2.0, Vignette.c(0x3A4252));
    box(b, m, 0.1, 1.9, 3.2, 6.15, 2.9, 4.2, Vignette.c(0x14171D));
    b.buildInto(detail, 'glyph atlas inside', lightChannelMask: 0x01);
    await Future.wait([
      _atlasBoard(),
      sign(
        6.6,
        1.2,
        vm.Matrix4.translation(vm.Vector3(0, 7.6, -0.05)),
        (c, s) {
          c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF14171D));
          Vignette.text(c, 'GLYPH ATLAS', Rect.fromLTWH(0, 0, s.width, s.height * 0.64), s.height * 0.46, const Color(0xFFE8A33D), lang: 'ja');
          Vignette.text(
            c,
            'BAKED ONCE · DRAWN EVERY FRAME',
            Rect.fromLTWH(0, s.height * 0.6, s.width, s.height * 0.34),
            s.height * 0.2,
            const Color(0xFFF4EBD8),
          );
        },
        glow: 0.5,
        shell: true,
      ),
    ]);
    // The new tile (its glyph and its key), and the screen's word.
    _newTile = await sign(
      _free.width,
      _free.height,
      vm.Matrix4.identity(),
      (c, s) {
        c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF000000));
        Vignette.text(c, _newGlyph, Rect.fromLTWH(0, 0, s.width, s.height * 0.78), s.height * 0.6, const Color(0xFFFFFFFF));
        c.drawRect(Rect.fromLTWH(0, s.height * 0.78, s.width, s.height * 0.22), Paint()..color = const Color(0xFFE8A33D));
        Vignette.text(c, 'Grotesk · % · 64px · .25', Rect.fromLTWH(0, s.height * 0.78, s.width, s.height * 0.22), s.height * 0.1, const Color(0xFF14171D));
      },
      px: 256,
      glow: 0.4,
      thick: 0.03,
    );
    _screenText = await sign(
      3.0,
      1.0,
      vm.Matrix4.identity(),
      (c, s) {
        c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF0E1016));
        Vignette.text(c, 'Flutter', Rect.fromLTWH(0, 0, s.width, s.height), s.height * 0.62, const Color(0xFFF4F1EA));
      },
      glow: 1.0,
      thick: 0.01,
    );
    _newTile.visible = _screenText.visible = false;
    _driver = person(
      FigureLook()
        ..top = rgbHex(0x3E4A5E)
        ..layer = rgbHex(0xE8A33D)
        ..legs = rgbHex(0x2B3A55)
        ..shoes = rgbHex(0x24211F)
        ..skin = rgbHex(0xD6AE90)
        ..hairColor = rgbHex(0x1A1714)
        ..hardHat = rgbHex(0xFFD23F),
    );
    _ready = true;
  }

  /// Packs the baked glyphs onto shelves, like an atlas does: left to
  /// right, a new shelf (as tall as its first glyph) when one's full; the
  /// new glyph on the first shelf tall enough with room at its end (else
  /// a new one).
  void _pack() {
    const pxPerM = 72.0, gap = 0.05;
    final left = _ax - _aw / 2 + gap, right = _ax + _aw / 2 - gap;
    // Each shelf: its top, its height, where it's filled to.
    final shelves = <(double, double, double)>[];
    var y = _ay + _ah / 2 - gap;
    for (final (_, px) in _baked) {
      final h = px / pxPerM, w = h * 0.72;
      if (shelves.isEmpty || shelves.last.$3 + w > right) {
        if (shelves.isNotEmpty) y -= shelves.last.$2 + gap;
        shelves.add((y, h, left));
      }
      final (top, sh, x) = shelves.last;
      _tiles.add(Rect.fromLTWH(x, top - h, w, h));
      shelves[shelves.length - 1] = (top, math.max(sh, h), x + w + gap);
    }
    const h = 64 / pxPerM, w = h * 0.72;
    for (final (top, sh, x) in shelves) {
      if (sh >= h - 1e-6 && x + w <= right) {
        _free = Rect.fromLTWH(x, top - h, w, h);
        return;
      }
    }
    final (top, sh, _) = shelves.last;
    _free = Rect.fromLTWH(left, top - sh - gap - h, w, h);
  }

  /// The atlas: black, the glyphs white (coverage), on its shelves.
  Future<void> _atlasBoard() async {
    await sign(
      _aw,
      _ah,
      vm.Matrix4.translation(vm.Vector3(_ax, _ay, _az + 0.05)),
      (c, s) {
        c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF000000));
        final kx = s.width / _aw, ky = s.height / _ah;
        Rect toPx(Rect r) =>
            Rect.fromLTRB((r.left - (_ax - _aw / 2)) * kx, ((_ay + _ah / 2) - r.bottom) * ky, (r.right - (_ax - _aw / 2)) * kx, ((_ay + _ah / 2) - r.top) * ky);
        for (var i = 0; i < _tiles.length; i++) {
          final r = toPx(_tiles[i]);
          c.drawRect(r, Paint()..color = const Color(0xFF15181E));
          Vignette.text(c, _baked[i].$1, r, r.height * 0.8, const Color(0xFFFFFFFF), weight: FontWeight.w600);
        }
        // The shelves' lines.
        final p = Paint()
          ..color = const Color(0xFF3A4252)
          ..strokeWidth = 2;
        final ys = {for (final t in _tiles) t.bottom};
        for (final y in ys) {
          final py = ((_ay + _ah / 2) - y) * ky + 3;
          c.drawLine(Offset(0, py), Offset(s.width, py), p);
        }
      },
      px: 1600,
      glow: 0.7,
      thick: 0.02,
    );
  }

  // ── Posing ────────────────────────────────────────────────────────────────

  final _mm = vm.Matrix4.identity();

  @override
  void pose(double u, double t, double night) {
    if (!_ready) return;
    pool.begin();
    // The press: down on a fresh tile, a flash.
    final pressY = 1.42 - 0.18 * math.sin(math.pi * seg(u, _press, _baked1));
    pbox(-5.2, pressY + 0.35, 2.4, 0.9, 0.1, 0.7, Vignette.c(0x8A8F98));
    if (u > _baked1 - 0.25 && u < _baked1 + 0.2) pglow(-5.2, 1.3, 1.85, 0.6, 0.3, 0.02, vm.Vector4(2.4, 2.2, 1.6, 1));
    // The forklift: from the press to the wall, the tile on its forks, up
    // to its spot; back.
    final f = eio(seg(u, _carry, _there)), back = eio(seg(u, _in + 0.2, _in + 2.6));
    final fx = lerp(lerp(-4.4, _free.center.dx, f), -4.4, back), fz = lerp(lerp(2.0, _az - 1.25, f), 2.0, back);
    final up = eio(seg(u, _there, _lift)) * (1 - eio(seg(u, _in + 0.2, _in + 0.9)));
    final forkY = lerp(0.35, _free.center.dy, up);
    _forklift(fx, fz, forkY, (f > 0 && f < 1 || back > 0 && back < 1) && (t * 3).floor().isEven);
    // The new tile: on the press, on the forks, slotted in.
    final tileShown = u >= _baked1;
    _newTile.visible = tileShown;
    if (tileShown) {
      double tx, ty, tz;
      if (u < _carry) {
        tx = -5.2;
        ty = 1.25;
        tz = 1.85;
      } else if (u < _in) {
        tx = fx;
        ty = forkY + 0.3;
        tz = fz + 0.55 + 0.6 * seg(u, _lift, _in);
      } else {
        tx = _free.center.dx;
        ty = _free.center.dy;
        tz = _az - 0.01;
      }
      _mm
        ..setIdentity()
        ..setTranslationRaw(tx, ty, tz);
      _newTile.localTransform = frame * _mm;
    }
    // The frame: each letter of "Flutter" lit on the atlas, a beam to the
    // screen, the word on it.
    final drawing = smooth(_draw, _draw + 0.3, u) * (1 - smooth(_drawn + 0.8, _drawn + 1.4, u));
    _screenText.visible = drawing > 0.5;
    if (drawing > 0.5) {
      _mm
        ..setIdentity()
        ..setTranslationRaw(6.08, 2.9, 4.2)
        ..rotateY(math.pi / 2);
      _screenText.localTransform = frame * _mm;
    }
    if (drawing > 0.01) {
      for (var k = 0; k < _word.length; k++) {
        final r = _tiles[_word[k]];
        final lit = smooth(_draw + 0.12 * k, _draw + 0.12 * k + 0.2, u) * drawing;
        if (lit <= 0) continue;
        final c = vm.Vector4(1.8 * lit, 1.4 * lit, 0.5 * lit, 1);
        // Its tile outlined: the quad cut from the atlas.
        final e = 0.025;
        pglow(r.center.dx, r.top - e, _az - 0.02, r.width + 2 * e, e, 0.01, c);
        pglow(r.center.dx, r.bottom + e, _az - 0.02, r.width + 2 * e, e, 0.01, c);
        pglow(r.left - e, r.center.dy, _az - 0.02, e, r.height, 0.01, c);
        pglow(r.right + e, r.center.dy, _az - 0.02, e, r.height, 0.01, c);
        // A beam from the tile to its place on the screen.
        final to = vm.Vector3(6.0, 2.6 + 0.0, 4.2 - 1.05 + 0.3 * k);
        final from = vm.Vector3(r.center.dx, r.center.dy, _az - 0.05);
        final mid = (from + to)..scale(0.5);
        final d = to - from;
        final len = d.length;
        pglow(mid.x, mid.y, mid.z, 0.02, 0.02, len, c, yaw: math.atan2(d.x, d.z), pitch: -math.asin(d.y / len));
      }
    }
    // The driver, on the forklift.
    final p = _p..rest();
    p.pos.setValues(fx - 0.05, 0.42, fz - 0.55);
    p.legPitch[0] = p.legPitch[1] = 1.45;
    // (Facing the wall, there and back: it reverses home.)
    p.yaw = math.pi;
    final m = Manner.of(180);
    Idle.breathe(p, t, m);
    Idle.glance(p, t, m, look: 0.5);
    p.armPitch[0] = p.armPitch[1] = 0.9;
    p.armRoll[0] = p.armRoll[1] = -0.1;
    draw(_driver, p);
    pool.end();
  }

  /// The forklift at (x, z), its forks at [forkY]; [blink]: its light on.
  void _forklift(double x, double z, double forkY, bool blink) {
    final yellow = Vignette.c(0xF2C94C), dark = Vignette.c(0x2B2E33);
    pbox(x, 0.45, z - 0.5, 0.9, 0.5, 1.1, yellow);
    pbox(x, 1.15, z - 0.85, 0.9, 0.08, 0.6, dark);
    for (final dx in [-0.42, 0.42]) {
      pbox(x + dx, 0.75, z - 0.6, 0.05, 0.9, 0.05, dark);
      pbox(x + dx, 1.3, z + 0.1, 0.06, 2.4, 0.06, dark);
      pcyl(x + dx, 0.18, z - 0.95, 0.18, 0.1, dark, roll: math.pi / 2);
      pcyl(x + dx, 0.18, z - 0.1, 0.18, 0.1, dark, roll: math.pi / 2);
    }
    for (final dx in [-0.2, 0.2]) {
      pbox(x + dx, forkY, z + 0.45, 0.08, 0.04, 0.8, dark);
    }
    pbox(x, forkY + 0.25, z + 0.14, 0.7, 0.5, 0.04, dark);
    if (blink) pglow(x, 1.25, z - 0.85, 0.1, 0.06, 0.1, vm.Vector4(2.6, 1.4, 0.2, 1));
  }

  // ── The camera ────────────────────────────────────────────────────────────

  @override
  Shot shot(double u) {
    // From the plaza's edge, in through the open front: the atlas wall,
    // the forklift; round towards the screen for the frame.
    final k = smooth(0.4, 2.2, u), s = smooth(_draw - 1.0, _draw + 0.4, u);
    final eye = vm.Vector3(lerp(lerp(-2.4, -2.0, k), -3.0, s), lerp(4.4, 2.9, k), lerp(-9.8, -6.8, k));
    final tg = vm.Vector3(lerp(lerp(0, -0.8, k), 2.4, s), lerp(3.0, 2.2, k), lerp(4.0, 6.0, k));
    return Shot(eye, tg, fov: lerp(52, 50, k), settle: 1.1, drift: 0.4);
  }
}
