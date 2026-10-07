import 'dart:convert' show utf8;
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'figure.dart';
import 'kit.dart';
import 'motion.dart';
import 'shot.dart';
import 'v_phones.dart' show TalkPhones;
import 'vignette.dart';

/// 家族 · A string ≠ text, on the lawn behind the site: a family out for a
/// walk, hand in hand — 👨‍👩‍👧‍👦, one emoji: a man, a woman, a girl and a
/// boy joined by three zero-width joiners (their held hands glow). Over
/// them, a phone with the emoji in a text field and what a String makes of
/// it: 1 character, 7 runes, length 11, 25 UTF-8 bytes. They stop and let
/// go: four people, four characters (the children run about); then hands
/// again, and on.
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

  /// The children's loops: their radii (x, z) and their middles (from
  /// their places in the row).
  static const _runs = [(0.7, 0.5, -0.83, -0.75), (0.85, 0.7, 0.6, -0.2)];
  static final _home = _back + (_z0 - (_z1 + 0.0)) / _speed;
  static final _loop = _home + 1.4;

  final _slots = <int>[];
  final _poses = List.generate(4, (_) => FigurePose());
  bool _ready = false;

  /// The phone over them (landscape): its size, and its screen's; the
  /// emoji in its text field, joined or not.
  static const _pw = 2.8, _ph = 1.3, _pd = 0.1, _sw = 2.64, _sh = 1.17;
  static const _family = '👨‍👩‍👧‍👦', _four = '👨👩👧👦';
  late final Node _phone, _screen;
  late final PhysicallyBasedMaterial _screenMat;
  late final Texture2D _joinedField, _apartField;

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
    _joinedField = await _field(_family, 1);
    _apartField = await _field(_four, 4);
    _screenMat = TalkPhones.screenMat(_joinedField);
    _phone = Node(name: 'family phone', mesh: Mesh(glyphGeometry(TalkPhones.slab(_pw, _ph, 0.16, _pd)), pbr(Vignette.c(0x8E9298), metallic: 0.7, roughness: 0.42)))
      ..castsShadows = false
      ..visible = false;
    _screen = Node(name: 'family phone screen', mesh: Mesh(boardGeometry(_sw, _sh, thick: 0.01), _screenMat))
      ..castsShadows = false
      ..visible = false;
    detail
      ..add(_phone)
      ..add(_screen);
    _ready = true;
  }

  /// The phone's screen (dark: the family emoji is pale grey silhouettes,
  /// lost on white): [text] in a text field (a caret after it), and what a
  /// String makes of it — its [characters] (what a reader sees), runes,
  /// UTF-16 length and UTF-8 bytes.
  Future<Texture2D> _field(String text, int characters) => paintedTexture(1200, 532, (c, s) {
    TalkPhones.chrome(c, s, '', '', bar: false, dark: true);
    final field = RRect.fromRectAndRadius(Rect.fromLTWH(40, 84, s.width - 80, 186), const Radius.circular(44));
    c
      ..drawRRect(field, Paint()..color = const Color(0xFF242A35))
      ..drawRRect(
        field,
        Paint()
          ..color = const Color(0xFF4F7CC4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      );
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(fontSize: 136)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(80, 84 + (186 - tp.height) / 2));
    c.drawRect(Rect.fromLTWH(80 + tp.width + 12, 112, 7, 130), Paint()..color = const Color(0xFF64B5F6));
    tp.dispose();
    final counts = [
      ('.characters', characters, true),
      ('.runes', text.runes.length, false),
      ('.length', text.length, false),
      ('utf8 bytes', utf8.encode(text).length, false),
    ];
    for (final (i, (name, n, lit)) in counts.indexed) {
      final x = 64.0 + i * 280;
      TalkPhones.label(c, name, Offset(x, 292), 30, const Color(0xFF9AA3B2), weight: FontWeight.w700, family: BP.mono);
      TalkPhones.label(c, '$n', Offset(x - 4, 328), 108, lit ? const Color(0xFFFFC66D) : const Color(0xFFF2F4F8), weight: FontWeight.w800, family: BP.mono);
    }
    TalkPhones.home(c, s, dark: true);
  });

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
      // Apart: the parents step back a little; the children run about (the
      // girl in front of her parents, the boy off to the side).
      if (apart > 0) {
        if (i >= 2) {
          final a = (u - _apart) * _spin[i - 2] + i;
          final (rx, rz, cx, cz) = _runs[i - 2];
          x += apart * (rx * math.sin(a) + cx);
          zz += apart * (cz - rz * math.cos(a));
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
        final (rx, rz, _, _) = _runs[i - 2];
        final vx = rx * w * math.cos(a), vz = rz * w * math.sin(a);
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
    // The phone over them: the emoji joined while they hold hands, four
    // apart. (Only while the camera's here.)
    final flip = apart > 0.5;
    _phone.visible = _screen.visible = visited;
    _screenMat.baseColorTexture = _screenMat.emissiveTexture = flip ? _apartField : _joinedField;
    final pop = 1 - 0.25 * math.sin(math.pi * (apart < 0.5 ? apart * 2 : (1 - apart) * 2)).abs();
    final y = 2.58 + 0.05 * math.sin(t * 1.3);
    _m
      ..setIdentity()
      ..setTranslationRaw(-0.05, y, z - 0.2)
      ..rotateY(away ? math.pi : 0)
      ..scaleByDouble(pop, pop, pop, 1);
    // (The body stands on its bottom edge; the screen just in front.)
    _phone.localTransform = frame * _m * vm.Matrix4.translation(vm.Vector3(0, -_ph / 2, 0));
    _screen.localTransform = frame * _m * vm.Matrix4.translation(vm.Vector3(0, 0, -(_pd / 2 + 0.008)));
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
