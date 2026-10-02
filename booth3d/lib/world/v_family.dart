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

/// 家族 · A string ≠ text, on the lawn behind the site: a family out for a
/// walk, hand in hand — 👨‍👩‍👧‍👦, one emoji: a man, a woman, a girl and a
/// boy joined by three zero-width joiners (their held hands glow). Over
/// them, what it is in a string: 1 grapheme, 7 code points, 11 UTF-16
/// units, 25 UTF-8 bytes. They stop and let go: four people, four
/// graphemes (the children run about); then hands again, and on.
class ZwjFamily extends Vignette {
  ZwjFamily(super.kit);

  @override
  String get name => 'family';
  @override
  String get kick => '家族 · STRING ≠ TEXT';
  @override
  String get line => '👨‍👩‍👧‍👦 = 1 grapheme';
  @override
  String get note => '7 code points joined by ZWJ · 11 UTF-16 units · 25 bytes';

  @override
  double get loop => _loop;
  @override
  double get visit => 12.6;

  /// Facing the site (the family walks north, towards the camera).
  @override
  final frame = trs(vm.Vector3(6.6, 0, 15.2), rotY: math.pi);

  /// Across the row (x), each one's size; the walk: from z0 to z1 at a
  /// stroll, then back.
  static const _x = [-1.0, -0.36, 0.28, 0.82], _sizes = [1.02, 0.95, 0.72, 0.64];
  static const _z0 = 5.2, _z1 = -4.6, _speed = 0.85;

  // The timeline.
  static const _stop = 6.0, _apart = 6.5, _join = 10.0, _go = 10.8, _turn = 16.4, _back = 17.4;

  /// How fast the children run round (radians a second; the boy the other
  /// way).
  static const _spin = [1.9, -2.2];
  static final _home = _back + (_z0 - (_z1 + 0.0)) / _speed;
  static final _loop = _home + 1.4;

  final _slots = <int>[];
  final _poses = List.generate(4, (_) => FigurePose());
  late final Node _joined, _apartSign;
  bool _ready = false;

  static const _emoji = TextStyle(fontFamily: BP.display, fontSize: 160);

  @override
  List<(String, TextStyle)> get fontRuns => [('👨‍👩‍👧‍👦 👨 👩 👧 👦 grapheme code points UTF-16 bytes ZWJ 家族', _emoji)];

  @override
  Future<void> init() async {
    makePool(boxes: 4, glows: 8);
    final looks = [
      (0x3A5A8C, 0x2B3442, Hair.short, false),
      (0xE58F6E, 0x24304A, Hair.long, true),
      (0xF2B8C6, 0x5B6573, Hair.bob, true),
      (0x6CB59A, 0x2E4766, Hair.short, false),
    ];
    for (var i = 0; i < 4; i++) {
      final (top, legs, hair, slim) = looks[i];
      _slots.add(
        person(
          FigureLook()
            ..size = _sizes[i]
            ..top = rgbHex(top)
            ..legs = rgbHex(legs)
            ..shoes = rgbHex(i >= 2 ? 0xEDEDEA : 0x1B1C20)
            ..skin = rgbHex(i == 0 ? 0xE0BB9E : 0xEFD0BA)
            ..hairColor = rgbHex(0x2A211B)
            ..hair = hair
            ..slim = slim
            ..girth = i >= 2 ? 0.95 : 1.0
            ..backpack = i == 3 ? rgbHex(0xB0222D) : null,
        ),
      );
    }
    Future<Node> board(String big, String small) => sign(1.9, 0.86, vm.Matrix4.identity(), (c, s) {
      final r = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(s.height * 0.14));
      c.drawRRect(r, Paint()..color = const Color(0xF2F4F1EA));
      c.drawRRect(
        r.deflate(4),
        Paint()
          ..color = const Color(0xFF2E6DA8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      );
      Vignette.text(c, big, Rect.fromLTWH(0, s.height * 0.04, s.width, s.height * 0.6), s.height * 0.46, const Color(0xFF14203A));
      Vignette.text(c, small, Rect.fromLTWH(0, s.height * 0.64, s.width, s.height * 0.3), s.height * 0.16, const Color(0xFF1E2A4A));
    }, glow: 0.45);
    _joined = await board('👨‍👩‍👧‍👦  1 grapheme', '7 code points (3 × ZWJ) · 11 UTF-16 units · 25 UTF-8 bytes');
    _apartSign = await board('👨 👩 👧 👦  4 graphemes', 'let go: no joiners, four emoji');
    _joined.visible = _apartSign.visible = false;
    _ready = true;
  }

  // ── Posing ────────────────────────────────────────────────────────────────

  /// The row's middle (z) at [u], and whether it's walking.
  static (double, bool, bool) _row(double u) {
    if (u < _stop) return (_z0 - _speed * u, true, false);
    final zs = _z0 - _speed * _stop;
    if (u < _go) return (zs, false, false);
    if (u < _turn) return (zs - _speed * (u - _go), true, false);
    final zt = zs - _speed * (_turn - _go);
    if (u < _back) return (zt, false, true);
    if (u < _home) return (math.min(_z0, zt + _speed * (u - _back)), true, true);
    return (_z0, false, false);
  }

  final _hands = List.generate(3, (_) => vm.Vector3.zero());

  @override
  void pose(double u, double t, double night) {
    if (!_ready) return;
    pool.begin();
    final (z, walking, away) = _row(u);
    final apart = smooth(_stop + 0.2, _apart, u) * (1 - smooth(_join - 0.2, _go - 0.1, u));
    final held = 1 - apart;
    final face = away ? math.pi : 0.0;
    // Facing them round at the turns.
    final turning = u >= _turn && u < _back ? smooth(_turn, _back, u) : (u >= _home ? 1 - smooth(_home, _loop, u) : (away ? 1.0 : 0.0));
    final yaw = math.pi * turning;
    for (var i = 0; i < 4; i++) {
      final p = _poses[i]..rest();
      final m = Manner.of(150 + i);
      var x = _x[i], zz = z;
      // Apart: the parents step back a little; the children run about.
      if (apart > 0) {
        if (i >= 2) {
          final a = (u - _apart) * _spin[i - 2] + i;
          x += apart * (0.85 * math.sin(a) + (i == 2 ? -0.5 : 0.6));
          zz += apart * (0.7 - 0.7 * math.cos(a) - 0.9);
        } else {
          zz += apart * 0.25;
        }
      }
      p.pos.setValues(x, 0, zz);
      final size = _sizes[i];
      if (walking && apart < 0.01) {
        final d = (u < _stop ? u : (u < _turn ? u - _go : u - _back)) * _speed;
        Gait.walk(p, Gait.phaseAt(d, _speed, size, m) + (i.isEven ? 0.4 : 1.9), _speed, m, size: size);
        p.yaw = face;
      } else if (i >= 2 && apart > 0.5) {
        // Running round (the girl one way, the boy the other), facing the
        // way they go.
        final w = _spin[i - 2], a = (u - _apart) * w + i;
        final vx = 0.85 * w * math.cos(a), vz = 0.7 * w * math.sin(a);
        final v = math.sqrt(vx * vx + vz * vz);
        Gait.walk(p, Gait.phaseAt((u - _apart) * v, v, size, m), v, m, size: size, amount: apart);
        p.yaw = math.atan2(-vx, -vz);
      } else {
        Idle.stand(p, t, m, size: size, look: 0.6);
        p.yaw = yaw;
        if (i < 2 && apart > 0.3) {
          // Watching the children.
          p.headYaw += 0.4 * apart;
          p.headPitch += 0.2 * apart;
        }
      }
    }
    // Held hands: each pair's hands meet between them (at the smaller
    // one's height); a joiner's glow there.
    for (var j = 0; j < 3; j++) {
      final a = _poses[j], b = _poses[j + 1];
      final h = math.min(_sizes[j], _sizes[j + 1]) * 0.6 + 0.06;
      _hands[j].setValues((a.pos.x + b.pos.x) / 2, h, (a.pos.z + b.pos.z) / 2 + 0.05);
    }
    for (var i = 0; i < 4; i++) {
      final p = _poses[i];
      worldPose(p);
      if (held > 0.5) {
        if (i > 0) kit.crew.aim(p, away ? 1 : 0, world(_hands[i - 1].x, _hands[i - 1].y, _hands[i - 1].z));
        if (i < 3) kit.crew.aim(p, away ? 0 : 1, world(_hands[i].x, _hands[i].y, _hands[i].z));
      }
      kit.figures.draw(_slots[i], p);
      kit.walkers.add(p.pos);
    }
    if (held > 0.5) {
      for (final h in _hands) {
        final pulse = 1.6 + 0.6 * math.sin(t * 5 + h.x * 3);
        pglow(h.x, h.y + 0.02, h.z, 0.07, 0.07, 0.07, vm.Vector4(0.5 * pulse, 1.1 * pulse, 2.2 * pulse, 1));
      }
    }
    // The sign over them: 1 grapheme while they're joined, 4 apart.
    final flip = apart > 0.5;
    _joined.visible = !flip;
    _apartSign.visible = flip;
    final n = flip ? _apartSign : _joined;
    final pop = 1 - 0.25 * math.sin(math.pi * (apart < 0.5 ? apart * 2 : (1 - apart) * 2)).abs();
    _m
      ..setIdentity()
      ..setTranslationRaw(-0.05, 2.45 + 0.05 * math.sin(t * 1.3), z - 0.2)
      ..rotateY(away ? math.pi : 0)
      ..scaleByDouble(pop, pop, pop, 1);
    n.localTransform = frame * _m;
    pool.end();
  }

  final _m = vm.Matrix4.identity();

  // ── The camera ────────────────────────────────────────────────────────────

  @override
  Shot shot(double u) {
    // In front of them, going back as they come on; lower for the
    // children running about.
    final (z, _, _) = _row(u);
    final low = smooth(_stop, _apart + 0.5, u) * (1 - smooth(_join, _go + 0.6, u));
    return Shot(
      vm.Vector3(-0.6, lerp(1.9, 1.6, low), z - lerp(6.2, 5.6, low)),
      vm.Vector3(-0.1, lerp(1.45, 1.3, low), z),
      fov: lerp(42, 46, low),
      settle: 1.1,
      drift: 0.4,
    );
  }
}
