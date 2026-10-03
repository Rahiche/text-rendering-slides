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
/// them. A tractor works the rows one by one, like a scanline, and leaves
/// each plot planted as much as the outline covers it — a full crop where
/// it's all inside, a thinner, lower one on the edges (the greys that
/// smooth a glyph's edge), bare earth outside. From the air: an "a",
/// anti-aliased. Then the harvest, and again.
class PixelFarm extends Vignette {
  PixelFarm(super.kit);

  @override
  String get name => 'farm';
  @override
  String get kick => '画素畑 · RASTERIZATION';
  @override
  String get line => 'Coverage → grey';
  @override
  String get note => 'each pixel as dark as the outline covers it: anti-aliasing';

  @override
  double get loop => 17;
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

  /// The rows' turns (the tractor's scanline), the hold, the harvest.
  static const _scan0 = 0.8, _perRow = 0.55, _harvest = 15.0;
  static const _scanEnd = _scan0 + _rows * _perRow;

  /// The fence (half its width and depth): round the plots with room for
  /// the tractor to go past a row's end and turn.
  static const _fenceX = _cols * _cell / 2 + 1.45, _fenceZ = _rows * _cell / 2 + 1.05;

  late final InstancedMesh _crops;
  int _farmer = -1;
  final _p = FigurePose();
  bool _ready = false;
  final _m = vm.Matrix4.identity();
  final _q = vm.Quaternion.identity();

  static const _glyph = 'a';
  static const _style = TextStyle(fontFamily: BP.display, fontWeight: FontWeight.w700);

  @override
  List<(String, TextStyle)> get fontRuns => [('$_glyph 画素畑 PIXEL FARM', _style)];

  @override
  Future<void> init() async {
    makePool(boxes: 16, glows: 8, cyls: 6);
    await _rasterize();
    final b = Batch();
    final m = pbr(rgb(1, 1, 1), roughness: 0.95);
    // The field's earth, its plots' furrows, a fence round it (room inside
    // it for the tractor to turn at the rows' ends).
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
      Vignette.text(c, '画素畑 · PIXEL FARM', Rect.fromLTWH(0, 0, s.width, s.height * 0.62), s.height * 0.44, const Color(0xFFF4EBD8), lang: 'ja');
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
    final harvest = smooth(_harvest, _harvest + 1.2, u);
    // The scanline: which row the tractor's on, and how far along it
    // (back and forth).
    final row = ((u - _scan0) / _perRow).floor().clamp(-1, _rows), along = ((u - _scan0) / _perRow) - row;
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final i = r * _cols + c, cover = _cover[i];
        // Planted once the tractor's past it on its row.
        final forward = r.isEven, at = forward ? c / _cols : 1 - (c + 1) / _cols;
        final done = r < row || (r == row && along > at);
        final grow = done ? smooth(0, 0.35, r < row ? 1 : (along - at) * 3) : 0.0;
        final g = cover * grow * (1 - harvest);
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
    // The tractor on its row, and the scanline's light along it; waiting at
    // the first row's start before; after the last (which ends at the
    // field's left), round and back up its side to the start (never a
    // jump).
    final r = row.clamp(0, _rows - 1), forward = r.isEven;
    final x0 = _x(0) - 0.6, x1 = _x(_cols - 1) + 0.6;
    final x = lerp(x0, x1, forward ? along : 1 - along);
    final z = _z(r);
    final scanning = u > _scan0 && u < _scanEnd;
    double tx, tz, yaw;
    if (scanning) {
      tx = x;
      tz = z;
      yaw = forward ? -math.pi / 2 : math.pi / 2;
    } else if (u <= _scan0) {
      tx = x0;
      tz = _z(0);
      yaw = -math.pi / 2;
    } else {
      final f = seg(u, _scanEnd, _scanEnd + 2.6);
      tx = x0;
      tz = lerp(_z(_rows - 1), _z(0), smooth(0.15, 0.85, f));
      yaw = f < 0.85 ? lerp(math.pi / 2, math.pi, smooth(0, 0.15, f)) : lerp(math.pi, 1.5 * math.pi, smooth(0.85, 1, f));
    }
    _tractor(tx, tz, yaw);
    if (scanning) pglow(0, 0.1, z, _cols * _cell, 0.02, _cell * 0.9, vm.Vector4(1.6, 1.4, 0.5, 1));
    // The farmer at the wheel.
    final p = _p..rest();
    p.pos.setValues(tx - math.sin(yaw) * -0.2, 0.55, tz - math.cos(yaw) * -0.2);
    p.legPitch[0] = p.legPitch[1] = 1.45;
    p.yaw = yaw;
    final m = Manner.of(190);
    Idle.breathe(p, t, m);
    Idle.glance(p, t, m, look: 0.4);
    p.armPitch[0] = p.armPitch[1] = 1.0;
    p.armRoll[0] = p.armRoll[1] = -0.15;
    draw(_farmer, p);
    pool.end();
  }

  /// A little tractor at (x, z) facing [yaw].
  void _tractor(double x, double z, double yaw) {
    final red = Vignette.c(0xC8442F), dark = Vignette.c(0x2B2E33);
    final fx = -math.sin(yaw), fz = -math.cos(yaw);
    pbox(x + fx * 0.3, 0.55, z + fz * 0.3, 0.7, 0.45, 1.1, red, yaw: yaw);
    pbox(x + fx * 0.75, 0.75, z + fz * 0.75, 0.5, 0.35, 0.4, red, yaw: yaw);
    for (final s in [-1.0, 1.0]) {
      final sx = fz * s * 0.42, sz = -fx * s * 0.42;
      // (It only ever drives along the rows: the axles across them.)
      pcyl(x - fx * 0.15 + sx, 0.38, z - fz * 0.15 + sz, 0.38, 0.18, dark, pitch: math.pi / 2);
      pcyl(x + fx * 0.75 + sx * 0.8, 0.22, z + fz * 0.75 + sz * 0.8, 0.22, 0.14, dark, pitch: math.pi / 2);
    }
  }

  // ── The camera ────────────────────────────────────────────────────────────

  @override
  Shot shot(double u) {
    // Low at the field's corner with the tractor, then up into the air as
    // it works: the glyph shows from above.
    final k = smooth(1.0, _scanEnd, u);
    final eye = vm.Vector3(lerp(-5.5, -0.6, k), lerp(2.2, 15.5, k), lerp(-8.5, -9.5, k));
    final tg = vm.Vector3(lerp(-2.0, 0, k), 0.2, lerp(-1.0, 0.4, k));
    return Shot(eye, tg, fov: lerp(46, 40, k), settle: 1.2, drift: 0.4);
  }
}
