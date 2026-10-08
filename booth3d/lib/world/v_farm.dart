import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'figure.dart';
import 'kit.dart';
import 'motion.dart';
import 'shot.dart';
import 'site_geo.dart' show setTqs;
import 'vignette.dart';

/// 画素畑 · Rasterization, a field beyond the park (north of the tram):
/// its plots are pixels, and the outline of an "a" is marked out across
/// them. An irrigation boom as wide as the field rolls down it row by row,
/// like a scanline (the water reaching its nozzles left to right), and
/// each plot it waters comes up as much as the outline covers it — a full
/// crop where it's all inside, a thinner, lower one on the edges (the
/// greys that smooth a glyph's edge), bare earth outside. From the air: an
/// "a", anti-aliased. Then the boom rolls back, clearing the field for the
/// next one; the farmer walks beside it.
class PixelFarm extends Vignette {
  PixelFarm(super.kit);

  @override
  String get name => 'farm';
  @override
  String get kick => 'RASTERIZATION';
  @override
  String get line => 'Coverage → grey';
  @override
  String get note => 'each pixel as dark as the outline covers it: anti-aliasing';

  @override
  double get loop => 20;
  @override
  double get visit => 13.4;

  @override
  final frame = trs(vm.Vector3(-9, 0, 79));

  /// The field: plots across and down, each plot's size.
  static const _cols = 24, _rows = 18, _cell = 0.5;
  static double _x(int c) => (c - (_cols - 1) / 2) * _cell;
  static double _z(int r) => ((_rows - 1) / 2 - r) * _cell;

  /// Each plot's coverage (0..1), from the glyph rasterized 4 × 4 per plot;
  /// its middle in the world.
  final _cover = List.filled(_cols * _rows, 0.0);
  late final _at = [
    for (var r = 0; r < _rows; r++)
      for (var c = 0; c < _cols; c++) frame.transform3(vm.Vector3(_x(c), 0, _z(r))),
  ];

  /// The boom's sweep down the rows (the scanline), the hold, the way back
  /// (clearing them).
  static const _scan0 = 0.8, _scanEnd = 10.8, _back0 = 13.2, _back1 = 19.6;

  /// Where the boom waits (its line across the rows): before the first
  /// row, and past the last.
  static const _zStart = _rows * _cell / 2 + 0.55, _zEnd = -_zStart;

  /// Its end towers (x), the farmer's way beside the right one.
  static const _towerX = _cols * _cell / 2 + 0.55, _walkX = _towerX + 0.6;

  /// The fence (half its width and depth): round the plots with room for
  /// the boom's towers and the farmer.
  static const _fenceX = _cols * _cell / 2 + 1.45, _fenceZ = _rows * _cell / 2 + 1.05;

  /// 0..1 over [a]–[b] at a steady pace, easing in and out over half a
  /// second at each end (as a machine starts and stops).
  static double _ramp(double u, double a, double b) {
    const e = 0.5;
    final t = u - a, len = b - a, v = 1 / (len - e);
    if (t <= 0) return 0;
    if (t >= len) return 1;
    if (t < e) return 0.5 * v / e * t * t;
    if (t > len - e) return 1 - 0.5 * v / e * (len - t) * (len - t);
    return 0.5 * v * e + v * (t - e);
  }

  /// The boom's line at [u].
  static double _boomZ(double u) => u < _back0 ? lerp(_zStart, _zEnd, _ramp(u, _scan0, _scanEnd)) : lerp(_zEnd, _zStart, _ramp(u, _back0, _back1));

  late final InstancedMesh _crops;
  int _farmer = -1;
  final _p = FigurePose();
  bool _ready = false;
  final _m = vm.Matrix4.identity();
  final _q = vm.Quaternion.identity();

  static const _glyph = 'a';
  static const _style = TextStyle(fontFamily: BP.display, fontWeight: FontWeight.w700);

  @override
  List<(String, TextStyle)> get fontRuns => [('$_glyph PIXEL FARM', _style)];

  @override
  Future<void> init() async {
    makePool(boxes: 64, glows: 8, cyls: 10);
    await _rasterize();
    final b = Batch();
    final m = pbr(rgb(1, 1, 1), roughness: 0.95);
    // The field's earth, its plots' furrows, a fence round it (room inside
    // it for the boom's towers, and the farmer).
    final w = _fenceX, d = _fenceZ;
    box(b, m, 2 * w - 0.2, 0.06, 2 * d - 0.2, 0, 0.03, 0, Vignette.c(0xC9AE84));
    for (var c = 0; c <= _cols; c++) {
      box(b, m, 0.03, 0.065, _rows * _cell, (c - _cols / 2) * _cell, 0.035, 0, Vignette.c(0x9E8662));
    }
    for (var r = 0; r <= _rows; r++) {
      box(b, m, _cols * _cell, 0.065, 0.03, 0, 0.035, (r - _rows / 2) * _cell, Vignette.c(0x9E8662));
    }
    for (final (x0, z0, x1, z1) in [(-w, -d, w, -d), (-w, d, w, d), (-w, -d, -w, d), (w, -d, w, d)]) {
      final len = math.sqrt((x1 - x0) * (x1 - x0) + (z1 - z0) * (z1 - z0));
      box(b, m, x0 == x1 ? 0.06 : len, 0.06, x0 == x1 ? len : 0.06, (x0 + x1) / 2, 0.55, (z0 + z1) / 2, Vignette.c(0xF4F1EA));
      for (var k = 0; k <= len / 1.5; k++) {
        final f = k / (len / 1.5);
        box(b, m, 0.08, 0.7, 0.08, lerp(x0, x1, f), 0.35, lerp(z0, z1, f), Vignette.c(0xF4F1EA));
      }
    }
    b.buildInto(detail, 'pixel farm', castsShadows: false, lightChannelMask: 0x01);
    // The crops: one instance a plot.
    _crops = InstancedMesh(geometry: CuboidGeometry(vm.Vector3.all(1)), material: pbr(rgb(1, 1, 1), roughness: 0.9));
    for (var i = 0; i < _cols * _rows; i++) {
      _crops.addInstance(hidden, color: rgb(1, 1, 1));
    }
    detail.add(
      Node(name: 'pixel farm crops')
        ..addComponent(InstancedMeshComponent(_crops))
        ..castsShadows = false,
    );
    await sign(4.2, 0.9, vm.Matrix4.translation(vm.Vector3(0, 1.4, -_fenceZ - 0.3)), (c, s) {
      c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF2E5E2E));
      Vignette.text(c, 'PIXEL FARM', Rect.fromLTWH(0, 0, s.width, s.height * 0.62), s.height * 0.44, const Color(0xFFF4EBD8), lang: 'ja');
      Vignette.text(c, 'coverage → grey', Rect.fromLTWH(0, s.height * 0.6, s.width, s.height * 0.34), s.height * 0.24, const Color(0xFFF2C94C));
    });
    _farmer = person(
      FigureLook()
        ..top = rgbHex(0x3A5A8C)
        ..legs = rgbHex(0x5B4B3A)
        ..shoes = rgbHex(0x3A2E26)
        ..skin = rgbHex(0xC59A7C)
        ..hairColor = rgbHex(0x8F8B86)
        ..cap = rgbHex(0xE9E2D2),
    );
    _ready = true;
  }

  /// The glyph, set on the field (4 × 4 samples a plot), read back: each
  /// plot's share of ink.
  Future<void> _rasterize() async {
    const k = 4, w = _cols * k, h = _rows * k;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    final tp = TextPainter(
      text: TextSpan(
        text: _glyph,
        style: _style.copyWith(fontSize: h * 1.25, color: const Color(0xFFFFFFFF)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((w - tp.width) / 2, (h - tp.height) / 2 - h * 0.08));
    tp.dispose();
    final image = await rec.endRecording().toImage(w, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (data == null) return;
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        var sum = 0;
        for (var y = 0; y < k; y++) {
          for (var x = 0; x < k; x++) {
            sum += data.getUint8(((r * k + y) * w + c * k + x) * 4 + 3);
          }
        }
        _cover[r * _cols + c] = sum / (255 * k * k);
      }
    }
  }

  // ── Posing ────────────────────────────────────────────────────────────────

  @override
  void pose(double u, double t, double night) {
    if (!_ready) return;
    pool.begin();
    // The boom's line; whether it's watering (on its way down) or clearing
    // (on its way back).
    final bz = _boomZ(u), back = u >= _back0;
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final i = r * _cols + c, cover = _cover[i];
        // Up once the boom's water reaches it (the far nozzles a moment
        // after the near ones); gone once it's rolled back over it.
        final z = _z(r), lag = c / _cols * 0.35;
        final grow = back ? 1 - smooth(0, 0.5, bz - (z - _cell / 2)) : smooth(0, 0.6, z + _cell / 2 - bz - lag);
        final g = cover * grow;
        if (g < 0.02) {
          _crops.setInstanceTransform(i, hidden);
          continue;
        }
        final hgt = 0.06 + 0.55 * g;
        _q.setEuler(kit.yawOf(frame), 0, 0);
        _crops.setInstanceTransform(i, setTqs(_m, _at[i].x, 0.06 + hgt / 2, _at[i].z, _q, _cell * 0.86, hgt, _cell * 0.86));
        // Darker, the more it covers (as ink would be).
        final dark = 0.85 - 0.75 * g;
        _crops.setInstanceColor(i, vm.Vector4(0.22 * dark + 0.05, 0.42 * dark + 0.08, 0.16 * dark + 0.04, 1));
      }
    }
    final sweeping = u > _scan0 && u < _scanEnd;
    _boom(bz, watering: sweeping);
    // The scanline: a light along the row it's over.
    if (sweeping) pglow(0, 0.08, bz, _cols * _cell, 0.02, 0.14, vm.Vector4(1.6, 1.4, 0.5, 1));
    // The farmer, walking beside it (a step behind its right tower);
    // waiting, he watches the field.
    final p = _p..rest();
    final pace = u < _back0 ? (_zStart - _zEnd) / (_scanEnd - _scan0 - 0.5) : (_zStart - _zEnd) / (_back1 - _back0 - 0.5);
    final dz = _boomZ(u + 0.02) - _boomZ(u - 0.02), speed = dz.abs() / 0.04, walking = speed / pace;
    p.pos.setValues(_walkX, 0, (bz + 0.45).clamp(-_fenceZ + 0.35, _fenceZ - 0.35));
    final m = Manner.of(190);
    if (walking > 0.05) {
      final dist = back ? bz - _zEnd : _zStart - bz;
      Gait.walk(p, Gait.phaseAt(dist, math.max(speed, 0.3), 1, m), math.max(speed, 0.3), m, amount: c01(walking * 1.5));
      p.yaw = lerp(math.pi / 2, back ? math.pi : 0, c01(walking * 1.5));
    } else {
      Idle.stand(p, t, m);
      p.yaw = math.pi / 2 + Idle.facing(t, m, 0.25);
    }
    draw(_farmer, p);
    pool.end();
  }

  /// The irrigation boom across the field at [z]: a truss on two wheeled
  /// towers, a drop pipe and nozzle every metre (spraying, when it's
  /// [watering]).
  void _boom(double z, {required bool watering}) {
    final steel = Vignette.c(0xC9CDD2), dark = Vignette.c(0x2B2E33), pipe = Vignette.c(0x6F7780), motor = Vignette.c(0xC8442F);
    const span = 2 * _towerX;
    pbox(0, 1.55, z, span, 0.07, 0.07, steel);
    pbox(0, 1.17, z, span, 0.06, 0.06, steel);
    for (var k = 0; k <= 10; k++) {
      pbox(lerp(-_towerX, _towerX, k / 10), 1.36, z, 0.04, 0.38, 0.04, steel);
    }
    for (var k = 0; k < 12; k++) {
      final x = _x(2 * k) + _cell / 2;
      pbox(x, 0.82, z, 0.03, 0.68, 0.03, pipe);
      pbox(x, 0.46, z, 0.08, 0.06, 0.08, dark);
      // The spray: a fine curtain down to the plants.
      if (watering) pbox(x, 0.26, z, 0.34, 0.36, 0.02, vm.Vector4(0.62, 0.78, 0.92, 1));
    }
    for (final x in [-_towerX, _towerX]) {
      pbox(x, 0.9, z, 0.12, 1.3, 0.12, steel);
      pbox(x, 0.34, z, 0.32, 0.18, 0.66, dark);
      for (final dz in [-0.25, 0.25]) {
        for (final dx in [-0.2, 0.2]) {
          pcyl(x + dx, 0.2, z + dz, 0.2, 0.08, dark, roll: math.pi / 2);
        }
      }
    }
    // The drive and its controls, on the right tower.
    pbox(_towerX + 0.05, 0.72, z - 0.18, 0.26, 0.3, 0.2, motor);
  }

  // ── The camera ────────────────────────────────────────────────────────────

  @override
  Shot shot(double u) {
    // Low at the field's corner as the boom sets off, then up into the air
    // as it works: the glyph shows from above.
    final k = smooth(1.0, _scanEnd, u);
    final eye = vm.Vector3(lerp(-5.5, -0.6, k), lerp(2.2, 15.5, k), lerp(-8.5, -9.5, k));
    final tg = vm.Vector3(lerp(-2.0, 0, k), 0.2, lerp(-1.0, 0.4, k));
    return Shot(eye, tg, fov: lerp(46, 40, k), settle: 1.2, drift: 0.4);
  }
}
