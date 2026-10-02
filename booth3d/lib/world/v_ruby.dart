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

/// ルビ · Ruby, a cable car in the park (west of the path): the readings
/// ride in over their text. 東京 stands on a stage; on a cable over it come
/// two cabins, とう and きょう, each stopping right over its character —
/// the small text set above its base. きょう is wider than 京, so the base
/// spreads to make room for it (the ruby mustn't run into its neighbour).
/// Then the cabins ride on, and the base closes up again.
class RubyCable extends Vignette {
  RubyCable(super.kit);

  @override
  String get name => 'ruby';
  @override
  String get kick => 'ルビ · RUBY';
  @override
  String get line => 'Small text over its base';
  @override
  String get note => 'furigana: each reading over its character, the base spaced out to fit it';

  @override
  double get loop => 13;
  @override
  double get visit => 11.4;

  /// Facing the park's path.
  @override
  final frame = trs(vm.Vector3(-6.8, 0, 59.6), rotY: -math.pi / 2);

  static const _base = ['東', '京'], _ruby = ['とう', 'きょう'];

  /// The base blocks (size, their middles in place), the cabins' widths,
  /// the line's depth, the cable's height, where the cabins hang.
  static const _b = 0.9, _gap = 0.06, _rubyW = [0.7, 1.12], _z = 1.4, _cableY = 3.7, _cabinY = 1.8;
  static const _pylon = 3.9;

  /// How far each base moves apart for きょう (the second spreads).
  static const _spread = 0.26;

  /// The timeline: the cabins in (one after the other), the base spreads,
  /// the hold, on out to the far pylon, the base closes up.
  static const _in0 = 0.5, _inLen = 2.6, _inGap = 0.9, _spreadAt = 3.4, _out0 = 8.4, _outLen = 2.2;

  static double _baseX(int k) => (k - 0.5) * (_b + _gap);

  final _blocks = <Node>[], _cabins = <Node>[];
  int _operator = -1;
  final _p = FigurePose();
  bool _ready = false;

  static const _style = TextStyle(fontFamily: BP.display, fontSize: 160, fontWeight: FontWeight.w700, locale: Locale('ja'));

  @override
  List<(String, TextStyle)> get fontRuns => [('東京 とう きょう ルビ RUBY', _style)];

  @override
  Future<void> init() async {
    makePool(boxes: 16, glows: 12, cyls: 6);
    final b = Batch();
    final m = pbr(rgb(1, 1, 1), roughness: 0.8);
    final steel = Vignette.c(0x8A8F98), dark = Vignette.c(0x3A4252);
    // The stage, the two pylons (lattice-ish: four legs and braces), the
    // cable between them, the operator's box.
    box(b, m, 3.2, 0.5, 1.1, 0, 0.25, _z, Vignette.c(0x9C6B3C));
    box(b, m, 3.3, 0.05, 1.2, 0, 0.52, _z, Vignette.c(0x8A5C32));
    for (final x in [-_pylon, _pylon]) {
      for (final dx in [-0.22, 0.22]) {
        for (final dz in [-0.22, 0.22]) {
          box(b, m, 0.07, _cableY + 0.3, 0.07, x + dx, (_cableY + 0.3) / 2, _z + dz, dark);
        }
      }
      for (var y = 0.6; y < _cableY; y += 0.7) {
        box(b, m, 0.5, 0.05, 0.05, x, y, _z - 0.22, steel);
        box(b, m, 0.5, 0.05, 0.05, x, y, _z + 0.22, steel);
      }
      box(b, m, 0.7, 0.18, 0.7, x, _cableY + 0.3, _z, dark);
      box(b, m, 0.3, 0.3, 0.3, x, _cableY, _z, Vignette.c(0xC8442F));
    }
    box(b, m, _pylon * 2, 0.025, 0.025, 0, _cableY, _z, Vignette.c(0x1B1C20));
    box(b, m, 0.6, 1.0, 0.5, _pylon + 0.9, 0.5, _z + 0.2, Vignette.c(0x2E6DA8));
    b.buildInto(detail, 'ruby cable', lightChannelMask: 0x01);
    final ink = const Color(0xFF14203A);
    final nodes = await Future.wait([
      sign(4.6, 0.8, vm.Matrix4.translation(vm.Vector3(0, _cableY + 0.95, _z + 0.1)), (c, s) {
        c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF1E2433));
        Vignette.text(c, 'ルビ · RUBY', Rect.fromLTWH(0, 0, s.width, s.height * 0.62), s.height * 0.46, const Color(0xFFF2C94C), lang: 'ja');
        Vignette.text(c, 'small text over its base', Rect.fromLTWH(0, s.height * 0.6, s.width, s.height * 0.34), s.height * 0.24, const Color(0xFFF4EBD8));
      }, glow: 0.5),
      for (var k = 0; k < 2; k++)
        sign(
          _b,
          _b,
          vm.Matrix4.identity(),
          (c, s) {
            c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFF7F4EC));
            Vignette.text(c, _base[k], Rect.fromLTWH(0, 0, s.width, s.height), s.height * 0.78, ink, lang: 'ja', weight: FontWeight.w700);
          },
          px: 360,
          glow: 0.2,
          thick: 0.22,
        ),
      for (var k = 0; k < 2; k++)
        sign(
          _rubyW[k],
          0.36,
          vm.Matrix4.identity(),
          (c, s) {
            c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFE8505F));
            c.drawRect(Rect.fromLTWH(s.width * 0.04, s.height * 0.1, s.width * 0.92, s.height * 0.8), Paint()..color = const Color(0xFFF7F4EC));
            Vignette.text(c, _ruby[k], Rect.fromLTWH(0, 0, s.width, s.height), s.height * 0.6, ink, lang: 'ja', weight: FontWeight.w700);
          },
          px: 400,
          glow: 0.3,
          thick: 0.3,
        ),
    ]);
    _blocks.addAll(nodes.sublist(1, 3));
    _cabins.addAll(nodes.sublist(3, 5));
    _operator = person(
      FigureLook()
        ..top = rgbHex(0x2E6DA8)
        ..legs = rgbHex(0x2B3442)
        ..shoes = rgbHex(0x1B1C20)
        ..skin = rgbHex(0xE0BB9E)
        ..hairColor = rgbHex(0x3D2B20)
        ..cap = rgbHex(0xE8505F),
    );
    _ready = true;
  }

  // ── Posing ────────────────────────────────────────────────────────────────

  final _mm = vm.Matrix4.identity();

  void _place(Node n, double x, double y, double z, {double roll = 0}) {
    _mm
      ..setIdentity()
      ..setTranslationRaw(x, y, z)
      ..rotateZ(roll);
    n.localTransform = frame * _mm;
  }

  /// How far the base has spread at [u] (0 … 1).
  static double _spreadOf(double u) => eio(seg(u, _spreadAt, _spreadAt + 0.7)) * (1 - eio(seg(u, _out0 + 0.8, _out0 + 1.6)));

  /// Base [k]'s middle at [u].
  static double _baseAt(int k, double u) => _baseX(k) + (k == 0 ? -0.04 : _spread) * _spreadOf(u);

  @override
  void pose(double u, double t, double night) {
    if (!_ready) return;
    pool.begin();
    for (var k = 0; k < 2; k++) {
      _place(_blocks[k], _baseAt(k, u), 0.55 + _b / 2, _z);
    }
    var moving = false;
    for (var k = 0; k < 2; k++) {
      // In from the near pylon to stop over its base, and on out to the
      // far one: とう first both ways (on one cable they can't pass).
      final a = _in0 + _inGap * k, inF = eio(seg(u, a, a + _inLen));
      final outA = _out0 + 0.4 * k, outF = eio(seg(u, outA, outA + _outLen));
      final over = _baseAt(k, u);
      final x = outF > 0 ? lerp(over, -_pylon - 0.8, outF) : lerp(_pylon + 0.8, over, inF);
      moving |= (inF > 0 && inF < 1) || (outF > 0 && outF < 1);
      // Swinging a little as it rides, settling when it stops.
      final sway = 0.05 * math.sin(t * 3.1 + k) * ((inF > 0 && inF < 1) || (outF > 0 && outF < 1) ? 1 : 0.25);
      final shown = u >= a && outF < 0.99;
      final n = _cabins[k]..visible = shown;
      if (!shown) continue;
      _place(n, x, _cabinY, _z, roll: sway);
      // The hanger up to the cable, the grip on it.
      final hy = (_cableY + _cabinY + 0.18) / 2;
      pbox(x - sway * (hy - _cabinY), hy, _z, 0.03, _cableY - _cabinY - 0.18, 0.03, Vignette.c(0x2B2E33), roll: sway);
      pbox(x, _cableY + 0.02, _z, 0.16, 0.08, 0.08, Vignette.c(0x5A6470));
      // Stopped over its base: a line of light between them (it belongs to
      // that character).
      final held = seg(u, a + _inLen, a + _inLen + 0.3) * (1 - seg(u, outA - 0.2, outA));
      if (held > 0.01) {
        final g = 1.6 * held;
        pglow(over, (_cabinY - 0.18 + 0.55 + _b) / 2, _z - 0.13, 0.02, _cabinY - 0.18 - 0.55 - _b, 0.02, vm.Vector4(1.0 * g, 0.4 * g, 0.4 * g, 1));
      }
    }
    // The base's width against its ruby's: a bracket of light under each
    // (wider for きょう's base once it's spread).
    final sp = _spreadOf(u);
    if (sp > 0.01) {
      for (var k = 0; k < 2; k++) {
        final w = k == 0 ? _b : _rubyW[1], c = 1.4 * sp;
        pglow(_baseAt(k, u), 0.57, _z - 0.62, w, 0.02, 0.03, vm.Vector4(0.4 * c, 0.8 * c, 1.6 * c, 1));
      }
    }
    // The operator at the far box, a hand on its lever.
    final p = _p..rest();
    p.pos.setValues(_pylon + 0.9, 0, _z + 0.85);
    p.yaw = 0.4;
    Idle.stand(p, t, Manner.of(230), look: 0.4, at: vm.Vector3(0, _cabinY, _z));
    worldPose(p);
    final lever = moving ? 0.08 : 0.0;
    kit.crew.aim(p, 0, world(_pylon + 0.78, 1.08 - lever, _z + 0.2));
    kit.figures.draw(_operator, p);
    pbox(_pylon + 0.78, 1.0 - lever / 2, _z + 0.2, 0.03, 0.16, 0.03, Vignette.c(0x2B2E33));
    pool.end();
  }

  // ── The camera ────────────────────────────────────────────────────────────

  @override
  Shot shot(double u) {
    // From the path: the whole line, in a little on the base while it
    // spreads.
    final k = smooth(_spreadAt - 0.6, _spreadAt + 0.6, u) * (1 - smooth(_out0, _out0 + 1.0, u));
    return Shot(
      vm.Vector3(lerp(0.4, 0.3, k), lerp(2.2, 2.0, k), lerp(-5.4, -3.9, k)),
      vm.Vector3(0.1, lerp(2.0, 1.75, k), _z),
      fov: 50,
      settle: 1.0,
      drift: 0.35,
    );
  }
}
