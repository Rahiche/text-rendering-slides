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

/// 双方向 · Bidi, across the left-hand side street from the plaza (where a
/// block was): a works whose open ground floor shows "Hi שלום 2026!" twice.
/// Above, as it is in memory — the characters in the order they were typed
/// (logical order); below, as it goes on the screen. The machine drops
/// them down one at a time, left to right on the screen: the Hebrew run is
/// laid out right to left, so its letters cross over each other on the
/// way (ש ends up rightmost), while the number inside it stays left to
/// right (2026, not 6202) — what the Unicode bidi algorithm works out from
/// each character's direction. Then back up, and again.
class BidiWorks extends Vignette {
  BidiWorks(super.kit);

  @override
  String get name => 'bidi';
  @override
  String get kick => 'BIDI';
  @override
  String get line => 'Memory ≠ screen';
  @override
  String get note => 'a right-to-left run reversed for display; its numbers stay left to right';

  @override
  double get loop => 15;
  @override
  double get visit => 11.2;

  /// Facing the plaza across the street.
  @override
  final frame = trs(vm.Vector3(-28.4, 0, 11.2), rotY: -math.pi / 2);

  /// The text in memory (logical order), and where each character goes
  /// on screen (visual order: LTR paragraph, the R run and the number in
  /// it reordered by the bidi algorithm); each character's direction
  /// (0 left to right, 1 right to left, 2 a number).
  static const _chars = ['H', 'i', ' ', 'ש', 'ל', 'ו', 'ם', ' ', '2', '0', '2', '6', '!'];
  static const _screen = [0, 1, 2, 11, 10, 9, 8, 7, 3, 4, 5, 6, 12];
  static const _dir = [0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 0];

  /// The slots' spacing and the rows (x of the first, y, z).
  static const _pitch = 0.6, _memY = 2.55, _screenY = 1.05, _rowZ = 1.25;
  static double _slotX(int i) => (i - (_chars.length - 1) / 2) * _pitch;

  /// The timeline: the runs light up, the drops (in screen order), the
  /// hold, back up.
  static const _light = 1.2, _drop0 = 2.2, _dropEvery = 0.42, _hold = 8.0, _up = 11.6;

  static const _style = TextStyle(fontFamily: BP.display, fontSize: 160, fontWeight: FontWeight.w700);

  final _glyphs = <Glyph3D?>[];
  final _mats = <PhysicallyBasedMaterial>[];
  int _operator = -1;
  final _p = FigurePose();
  bool _ready = false;

  @override
  List<(String, TextStyle)> get fontRuns => [('Hi שלום 2026! BIDI MEMORY SCREEN ORDER', _style)];

  static const _colors = [0x6C9BE0, 0xF2A33A, 0x58C08E];

  @override
  Future<void> init() async {
    makePool(boxes: 8, glows: 24);
    final b = Batch();
    final m = pbr(rgb(1, 1, 1), roughness: 0.75);
    final glass = pbr(rgb(1, 1, 1), roughness: 0.15, metallic: 0.4);
    final wall = Vignette.c(0xD8D2C4), dark = Vignette.c(0x1E2433), trim = Vignette.c(0x2E6DA8);
    // The building: floor, back and side walls, the upper floors over an
    // open ground floor, windows, the roof.
    box(b, m, 12, 0.2, 9.6, 0, 0.1, 4.8, Vignette.c(0x9A968E));
    box(b, m, 12, 10, 0.3, 0, 5, 9.45, wall);
    for (final x in [-5.85, 5.85]) {
      box(b, m, 0.3, 10, 9.6, x, 5, 4.8, wall);
    }
    box(b, m, 12, 6.2, 0.3, 0, 6.9, 0.15, wall);
    box(b, m, 12.2, 0.25, 0.4, 0, 3.85, 0.1, trim);
    for (final y in [5.0, 7.6]) {
      for (var k = -4; k <= 4; k++) {
        box(b, glass, 0.95, 1.3, 0.05, k * 1.3, y + 0.6, -0.02, Vignette.c(0x9CC4E0));
      }
    }
    box(b, m, 12.4, 0.3, 10, 0, 10.1, 4.8, Vignette.c(0x5A6470));
    b.buildInto(shell, 'bidi works', lightChannelMask: 0x01);
    // The machine: a dark board behind the two rows, their ledges, the
    // housing between them with its chutes.
    box(b, m, 9.4, 3.1, 0.1, 0, 1.95, _rowZ + 0.45, dark);
    for (final y in [_memY - 0.33, _screenY - 0.33]) {
      box(b, m, 8.6, 0.06, 0.5, 0, y, _rowZ, Vignette.c(0x8A8F98));
    }
    box(b, m, 8.6, 0.32, 0.4, 0, (_memY + _screenY) / 2 - 0.1, _rowZ + 0.15, Vignette.c(0x3A4252));
    b.buildInto(detail, 'bidi machine', lightChannelMask: 0x01);
    await Future.wait([
      sign(
        7.0,
        1.3,
        vm.Matrix4.translation(vm.Vector3(0, 6.2, -0.05)),
        (c, s) {
          c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF1E2433));
          Vignette.text(c, 'BIDI', Rect.fromLTWH(0, 0, s.width, s.height * 0.66), s.height * 0.5, const Color(0xFFF2C94C), lang: 'ja');
          Vignette.text(c, 'MEMORY ≠ SCREEN', Rect.fromLTWH(0, s.height * 0.62, s.width, s.height * 0.32), s.height * 0.22, const Color(0xFFF4EBD8));
        },
        glow: 0.5,
        shell: true,
      ),
      // The rows' labels, at their left.
      sign(
        1.0,
        0.36,
        vm.Matrix4.translation(vm.Vector3(-4.85, _memY + 0.1, _rowZ + 0.38)),
        (c, s) {
          c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF2E3546));
          Vignette.text(c, 'MEMORY ORDER', Rect.fromLTWH(0, 0, s.width, s.height), s.height * 0.4, const Color(0xFFF4EBD8), lang: 'ja');
        },
        glow: 0.6,
        thick: 0.01,
      ),
      sign(
        1.0,
        0.36,
        vm.Matrix4.translation(vm.Vector3(-4.85, _screenY + 0.1, _rowZ + 0.38)),
        (c, s) {
          c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF2E3546));
          Vignette.text(c, 'SCREEN ORDER', Rect.fromLTWH(0, 0, s.width, s.height), s.height * 0.4, const Color(0xFFF4EBD8), lang: 'ja');
        },
        glow: 0.6,
        thick: 0.01,
      ),
    ]);
    // The characters (spaces: none), each its own material (lit in its
    // direction's colour).
    final solids = await extrudeTextsAt([for (final c in _chars) (c == ' ' ? '·' : c, _style)], unitsPerPx: 0.5 / 160, depth: 0.08);
    for (var i = 0; i < _chars.length; i++) {
      final mat = pbr(Vignette.c(0xF4F1EA), roughness: 0.4, emissive: Vignette.c(_colors[_dir[i]]), emissiveStrength: 0);
      _mats.add(mat);
      if (_chars[i] == ' ') {
        _glyphs.add(null);
        continue;
      }
      final n = Node(name: 'bidi glyph', mesh: Mesh(glyphGeometry(solids[i].mesh), mat))
        ..castsShadows = false
        ..visible = false;
      detail.add(n);
      _glyphs.add(Glyph3D(solids[i], n));
    }
    _operator = person(
      FigureLook()
        ..top = rgbHex(0xF2F0EA)
        ..layer = rgbHex(0x2E6DA8)
        ..legs = rgbHex(0x2B3442)
        ..shoes = rgbHex(0x1B1C20)
        ..skin = rgbHex(0xE8C6AC)
        ..hairColor = rgbHex(0x2A211B)
        ..hair = Hair.bob
        ..slim = true,
    );
    _ready = true;
  }

  // ── Posing ────────────────────────────────────────────────────────────────

  /// When character [i] drops (in screen order, left to right).
  static double _dropAt(int i) => _drop0 + _dropEvery * _screen[i];

  @override
  void pose(double u, double t, double night) {
    if (!_ready) return;
    pool.begin();
    final lit = smooth(_light, _light + 0.5, u) * (1 - smooth(_up + 1.2, _up + 1.8, u));
    for (var i = 0; i < _chars.length; i++) {
      final g = _glyphs[i];
      if (g == null) continue;
      final a = _dropAt(i);
      final f = eio(seg(u, a, a + 0.62)), back = eio(seg(u, _up + 0.04 * i, _up + 0.04 * i + 0.8));
      final k = f * (1 - back);
      final x0 = _slotX(i), x1 = _slotX(_screen[i]);
      // Down (out over the ledge and in), the reversed ones arcing past
      // each other; back up together.
      final x = lerp(x0, x1, k), y = lerp(_memY, _screenY, k) + 0.25 * math.sin(math.pi * k) * (_dir[i] == 1 ? 1.6 : 0.6);
      final z = _rowZ - 0.2 - 0.35 * math.sin(math.pi * k) * (_dir[i] == 1 ? 1 : 0.4);
      put(g, x, y, z);
      _mats[i].emissiveStrength = 0.9 * lit;
      // The ghost of it left in memory (it's still there: only the screen
      // shows the other order).
      if (k > 0.05) pglow(x0, _memY - 0.2, _rowZ - 0.05, g.width, 0.04, 0.02, vm.Vector4(0.2, 0.25, 0.35, 1));
    }
    // The runs' directions: arrows of light over the screen row once it's
    // filled (→ for left-to-right, ← over the reversed run).
    final shown = smooth(_hold - 0.4, _hold, u) * (1 - smooth(_up, _up + 0.4, u));
    if (shown > 0.01) {
      void arrow(double x0, double x1, double y, vm.Vector4 c) {
        final dir = x1 > x0 ? 1.0 : -1.0;
        pglow((x0 + x1) / 2, y, _rowZ - 0.25, (x1 - x0).abs(), 0.04, 0.02, c);
        pglow(x1 - dir * 0.07, y + 0.04, _rowZ - 0.25, 0.14, 0.04, 0.02, c, roll: -dir * 0.6);
        pglow(x1 - dir * 0.07, y - 0.04, _rowZ - 0.25, 0.14, 0.04, 0.02, c, roll: dir * 0.6);
      }

      final c = shown * 2.2;
      arrow(_slotX(0) - 0.2, _slotX(1) + 0.2, _screenY - 0.48, vm.Vector4(0.4 * c, 0.6 * c, 1.0 * c, 1));
      arrow(_slotX(3) - 0.2, _slotX(6) + 0.2, _screenY - 0.48, vm.Vector4(0.3 * c, 1.0 * c, 0.5 * c, 1));
      arrow(_slotX(11) + 0.2, _slotX(8) - 0.2, _screenY - 0.48, vm.Vector4(1.0 * c, 0.6 * c, 0.15 * c, 1));
    }
    // The operator at the machine's left, watching it work.
    final p = _p..rest();
    p.pos.setValues(-5.0, 0.2, _rowZ - 1.0);
    p.yaw = -1.1;
    Idle.stand(p, t, Manner.of(170), look: 0.3, at: vm.Vector3(0, 1.8, _rowZ));
    draw(_operator, p);
    pool.end();
  }

  // ── The camera ────────────────────────────────────────────────────────────

  @override
  Shot shot(double u) {
    // From the plaza's edge across the street: the works, then in on the
    // two rows (from high enough to see them over the heads of whoever's
    // walking past on the pavement).
    final k = smooth(0.4, 2.0, u);
    return Shot(
      vm.Vector3(lerp(2.9, 2.0, k), lerp(5.2, 6.4, k), lerp(-9.5, -9.2, k)),
      vm.Vector3(lerp(0.4, 0.2, k), lerp(3.4, 1.8, k), lerp(1.0, _rowZ, k)),
      fov: lerp(52, 44, k),
      settle: 1.1,
      drift: 0.4,
    );
  }
}
