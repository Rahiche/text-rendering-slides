import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'figure.dart';
import 'kit.dart';
import 'motion.dart';
import 'shot.dart';
import 'vignette.dart';

/// 太さジム · Variable fonts, an outdoor gym on the lawn behind the site
/// (left of the park's path): "Aa" in JetBrains Mono, a variable font, at
/// its workout. Each squat it comes up bolder — wght 100, 275, 450, 625,
/// 800, read off the gym's board — a flex at the top, then it eases back
/// down to 100: one font file, every weight in between. Its trainer
/// counts the reps.
class WeightGym extends Vignette {
  WeightGym(super.kit);

  @override
  String get name => 'gym';
  @override
  String get kick => '太さジム · VARIABLE FONTS';
  @override
  String get line => 'wght 100 → 800';
  @override
  String get note => 'one font file, any weight in between (JetBrains Mono)';

  @override
  double get loop => 14;
  @override
  double get visit => 10.2;

  /// Facing the park's path.
  @override
  final frame = trs(vm.Vector3(-6.9, 0, 14.6), rotY: -math.pi / 2);

  static const _weights = [100, 275, 450, 625, 800];

  /// For a talk: a board behind the letters (left of the wght board).
  @override
  ({vm.Vector3 at, double w, double h})? get backdrop => (at: vm.Vector3(-0.9, 0, 1.15), w: 2.2, h: 2.7);

  /// The reps (each at its own second), the flex, the way back down.
  static const _reps = [1.3, 2.9, 4.5, 6.1], _rep = 1.2, _flex = 7.4, _ease = 8.7;

  static TextStyle _style(int w) => TextStyle(fontFamily: BP.mono, fontSize: 160, fontVariations: [FontVariation('wght', w.toDouble())]);

  late final List<Glyph3D> _aa;
  int _trainer = -1;
  final _p = FigurePose();
  bool _ready = false;

  @override
  List<(String, TextStyle)> get fontRuns => [
    for (final w in _weights) ('Aa wght', _style(w)),
    ('太さジム VARIABLE FONTS', const TextStyle(fontFamily: BP.display)),
  ];

  @override
  Future<void> init() async {
    makePool(boxes: 12, glows: 40);
    final b = Batch();
    final m = pbr(rgb(1, 1, 1), roughness: 0.8);
    final steel = pbr(rgb(1, 1, 1), roughness: 0.35, metallic: 0.8);
    // The mat, the podium, a rack of dumbbells, the board's frame.
    box(b, m, 6.0, 0.04, 3.6, 0, 0.02, 0.3, Vignette.c(0x2E5E4E));
    box(b, m, 1.9, 0.24, 1.3, -0.6, 0.12, 0.2, Vignette.c(0x22262E));
    box(b, m, 1.96, 0.03, 1.36, -0.6, 0.255, 0.2, Vignette.c(0xF2C94C));
    box(b, steel, 1.5, 0.06, 0.36, 2.0, 0.55, 1.2, Vignette.c(0x5A6470));
    for (final x in [1.35, 2.65]) {
      box(b, steel, 0.06, 0.55, 0.36, x, 0.28, 1.2, Vignette.c(0x5A6470));
    }
    for (var k = 0; k < 4; k++) {
      final x = 1.5 + 0.33 * k, r = 0.06 + 0.012 * k;
      box(b, steel, 0.24, 0.035, 0.035, x, 0.62, 1.2, Vignette.c(0x2B2E33));
      cylinder(b, steel, r, 0.05, x - 0.12, 0.62, 1.2, Vignette.c(0x1E2125), rotZ: math.pi / 2);
      cylinder(b, steel, r, 0.05, x + 0.12, 0.62, 1.2, Vignette.c(0x1E2125), rotZ: math.pi / 2);
    }
    for (final x in [0.55, 3.45]) {
      box(b, m, 0.1, 2.6, 0.1, x, 1.3, 1.9, Vignette.c(0x3A4C6E));
    }
    box(b, m, 3.0, 1.0, 0.08, 2.0, 2.1, 1.92, Vignette.c(0x14171D));
    b.buildInto(detail, 'weight gym', castsShadows: false, lightChannelMask: 0x01);
    await Future.wait([
      sign(3.0, 0.5, vm.Matrix4.translation(vm.Vector3(2.0, 2.92, 1.88)), (c, s) {
        c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFE8505F));
        Vignette.text(c, '太さジム · wght GYM', Rect.fromLTWH(0, 0, s.width, s.height), s.height * 0.56, const Color(0xFFFFFFFF), lang: 'ja');
      }),
      sign(
        0.9,
        0.42,
        vm.Matrix4.translation(vm.Vector3(1.05, 2.1, 1.86)),
        (c, s) {
          c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF14171D));
          Vignette.text(c, 'wght', Rect.fromLTWH(0, 0, s.width, s.height), s.height * 0.7, const Color(0xFFF2A33A), family: BP.mono);
        },
        glow: 0.9,
        thick: 0.01,
      ),
    ]);
    final mat = pbr(Vignette.c(0xF2C94C), roughness: 0.35, metallic: 0.3, emissive: Vignette.c(0xF2C94C), emissiveStrength: 0.08);
    _aa = await letters([for (final w in _weights) ('Aa', _style(w))], mat, unitsPerPx: 0.95 / 160, depth: 0.14);
    _trainer = person(
      FigureLook()
        ..top = rgbHex(0xE8505F)
        ..legs = rgbHex(0x1C1F26)
        ..shoes = rgbHex(0xF4F4F0)
        ..skin = rgbHex(0xC59A7C)
        ..hairColor = rgbHex(0x1A1714)
        ..hair = Hair.short
        ..cap = rgbHex(0x1C1F26),
    );
    _ready = true;
  }

  // ── Posing ────────────────────────────────────────────────────────────────

  /// Which weight [u] seconds in (and how far through the step to it).
  static (int, double) _weightAt(double u) {
    var k = 0, pop = 1.0;
    for (var i = 0; i < _reps.length; i++) {
      final top = _reps[i] + _rep * 0.62;
      if (u >= top) {
        k = i + 1;
        pop = seg(u, top, top + 0.35);
      }
    }
    // Easing back down a weight at a time.
    for (var i = 0; i < 4; i++) {
      final at = _ease + 0.35 * i;
      if (u >= at) {
        k = 3 - i;
        pop = seg(u, at, at + 0.3);
      }
    }
    return (k, pop);
  }

  @override
  void pose(double u, double t, double night) {
    if (!_ready) return;
    pool.begin();
    final (k, pop) = _weightAt(u);
    // The squat: down, a squash; up, a stretch; the new weight pops in at
    // the top.
    var sy = 1.0, sx = 1.0, lift = 0.0;
    for (final r in _reps) {
      final f = seg(u, r, r + _rep);
      if (f <= 0 || f >= 1) continue;
      final down = math.sin(math.pi * math.min(1, f / 0.62));
      sy -= 0.16 * down;
      sx += 0.08 * down;
      if (f > 0.62) lift = 0.12 * math.sin(math.pi * (f - 0.62) / 0.38);
    }
    final flex = smooth(_flex - 0.4, _flex, u) * (1 - smooth(_ease - 0.3, _ease, u));
    final bounce = 1 + 0.12 * math.sin(math.pi * pop) + 0.05 * flex * math.sin(t * 8);
    for (var i = 0; i < _aa.length; i++) {
      final g = _aa[i];
      if (i != k) {
        g.node.visible = false;
        continue;
      }
      put(g, -0.6, 0.27 + g.height * bounce / 2 + lift, 0.2, s: bounce);
      // (Squash and stretch: scaled in y, out in x.)
      g.node.localTransform = g.node.localTransform * vm.Matrix4.diagonal3Values(sx, sy, 1);
    }
    // Sweat, flying off at the top of each rep.
    for (final r in _reps) {
      final age = (u - r - _rep * 0.6) / 0.7;
      if (age < 0 || age >= 1) continue;
      for (var d = 0; d < 3; d++) {
        final a = 0.6 + 0.9 * d + rnd(d, r.round());
        pglow(
          -0.6 + math.cos(a) * (0.5 + 0.6 * age),
          1.35 + 0.5 * age - 1.2 * age * age,
          0.2 - 0.2 * math.sin(a),
          0.04,
          0.06,
          0.04,
          vm.Vector4(0.6, 1.4, 2.4, 1),
        );
      }
    }
    // The board: wght, the number.
    final w = _weights[k];
    digits('$w'.padLeft(3), 2.45, 2.12, 1.86, size: 0.46);
    // The trainer: counting the reps (a clap at each), a fist pump at 800.
    final p = _p..rest();
    p.pos.setValues(-2.2, 0, 0.1);
    final m = Manner.of(160);
    p.yaw = -1.3;
    Idle.stand(p, t, m, look: 0.3, at: vm.Vector3(-0.6, 1.0, 0.2));
    var clap = 0.0;
    for (final r in _reps) {
      clap = math.max(clap, math.sin(math.pi * seg(u, r + _rep * 0.55, r + _rep * 0.85)));
    }
    if (flex > 0.05) {
      // A fist pump, chest high.
      p.handTo(1, 0.22, 0.3 + 0.05 * math.sin(t * 9), -0.24, flex);
    } else if (clap > 0) {
      final open = 0.03 + 0.12 * (1 - clap), k = math.min(1.0, clap * 3);
      p.handTo(0, -open, 0.27, -0.3, k);
      p.handTo(1, open, 0.27, -0.3, k);
    }
    draw(_trainer, p);
    pool.end();
  }

  // ── The camera ────────────────────────────────────────────────────────────

  @override
  Shot shot(double u) {
    // Low, in front: the letters big, the board behind; in a little for
    // the flex.
    final k = smooth(_flex - 1.0, _flex, u);
    return Shot(
      vm.Vector3(lerp(0.3, -0.1, k), lerp(1.55, 1.35, k), lerp(-4.2, -3.3, k)),
      vm.Vector3(lerp(0.2, -0.3, k), 1.15, 0.6),
      fov: 42,
      settle: 1.0,
      drift: 0.4,
    );
  }
}
