import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'figure.dart';
import 'kit.dart';
import 'motion.dart';
import 'site_geo.dart' show MeshBatch;
import 'shot.dart';
import 'vignette.dart';

/// 合字工房 · Shaping, in the park past the alley (on the right of the long
/// path, across from the tofu shop): a smithy where glyphs are forged into
/// ligatures. Two letters ride the conveyor into the furnace and come out
/// red-hot onto the anvil; the smith hammers them — sparks, a flash — into
/// one glyph, which cools on the rack: f + i → ﬁ, and in JetBrains Mono
/// (a code font) - + > → its arrow, ! + = → its ≠ (the font's own
/// ligatures: the joined glyph is "->" and "!=" shaped with them on). What
/// a shaper (HarfBuzz) does to a run of glyphs: swaps a sequence for the
/// single glyph the font has for it.
class LigatureForge extends Vignette {
  LigatureForge(super.kit);

  @override
  String get name => 'forge';
  @override
  String get kick => '合字工房 · SHAPING';
  @override
  String get line => 'f + i → ﬁ   - + > → ->';
  @override
  String get note => 'the shaper swaps a run of glyphs for one the font has';

  @override
  double get loop => _pairs.length * _cycle;
  @override
  double get visit => 2 * _cycle + 0.6;

  @override
  final frame = trs(vm.Vector3(6.4, 0, 46.8), rotY: math.pi / 2);

  /// The pairs and what they make (the code ones in a code font, joined
  /// by its ligatures).
  static const _pairs = [('f', 'i', 'ﬁ'), ('-', '>', '->'), ('!', '=', '!=')];
  static const _code = [false, true, true];

  /// One pair's turn (seconds): along the belt, in the fire, on the anvil
  /// (three blows), onto the rack.
  static const _cycle = 6.2;
  static const _belt = 1.5, _fire = 2.1, _outAt = 2.5, _blows = [2.95, 3.45, 3.95], _rack = 4.6, _done = 5.4;

  // The forge's parts (its frame): the belt's start and end, the
  // furnace's mouth, the anvil's top, the smith, the rack.
  static const _beltX0 = -3.4, _mouthX = -1.05, _beltY = 0.86, _anvil = (0.55, 0.92, -0.35), _rackX = 2.3;

  late final List<Glyph3D> _glyphs;
  final _mats = <PhysicallyBasedMaterial>[];
  late final Node _hammer;
  late final PhysicallyBasedMaterial _fireMat;
  int _smith = -1;
  final _p = FigurePose();
  bool _ready = false;

  static const _style = TextStyle(fontFamily: BP.display, fontSize: 160, fontWeight: FontWeight.w700);
  static const _codeStyle = TextStyle(fontFamily: BP.mono, fontSize: 160, fontVariations: [FontVariation('wght', 700)]);

  @override
  List<(String, TextStyle)> get fontRuns => [('fiﬁ → ≠ 合字工房 LIGATURE FORGE', _style), ('- > -> ! = !=', _codeStyle)];

  @override
  Future<void> init() async {
    makePool(boxes: 24, glows: 12);
    final b = Batch();
    final m = pbr(rgb(1, 1, 1), roughness: 0.8);
    final steel = pbr(rgb(1, 1, 1), roughness: 0.35, metallic: 0.8);
    final brick = Vignette.c(0x8C4B3A), soot = Vignette.c(0x2A2626), iron = Vignette.c(0x3C4048), wood = Vignette.c(0x8A6440);
    // The furnace: brick, a dark mouth, a chimney.
    box(b, m, 1.4, 1.9, 1.3, -1.75, 0.95, 0.35, brick);
    box(b, m, 0.62, 0.5, 0.06, _mouthX - 0.65, 0.88, -0.33, soot);
    box(b, m, 0.5, 1.6, 0.5, -1.9, 2.6, 0.55, brick);
    // The belt on its legs, running into the mouth.
    box(b, m, _mouthX - _beltX0, 0.08, 0.5, (_beltX0 + _mouthX) / 2 - 0.35, _beltY - 0.06, -0.62, iron);
    for (final x in [_beltX0 + 0.1, _mouthX - 0.8]) {
      box(b, m, 0.07, _beltY - 0.1, 0.07, x, (_beltY - 0.1) / 2, -0.82, iron);
      box(b, m, 0.07, _beltY - 0.1, 0.07, x, (_beltY - 0.1) / 2, -0.42, iron);
    }
    // The anvil on its stump; the rack; a quench tub.
    cylinder(b, m, 0.24, 0.55, _anvil.$1, 0.275, _anvil.$3, wood);
    box(b, steel, 0.52, 0.2, 0.24, _anvil.$1, 0.66, _anvil.$3, iron);
    box(b, steel, 0.68, 0.14, 0.26, _anvil.$1 - 0.05, 0.83, _anvil.$3, iron);
    box(b, m, 1.5, 0.06, 0.4, _rackX, 1.25, 0.15, wood);
    box(b, m, 1.5, 0.06, 0.4, _rackX, 0.75, 0.15, wood);
    for (final x in [_rackX - 0.72, _rackX + 0.72]) {
      box(b, m, 0.06, 1.5, 0.06, x, 0.75, 0.32, wood);
    }
    cylinder(b, m, 0.3, 0.42, 1.55, 0.21, -0.75, Vignette.c(0x5A6470));
    // A roof over the lot, on posts.
    for (final (x, z) in [(-2.6, -1.2), (3.2, -1.2), (-2.6, 1.3), (3.2, 1.3)]) {
      box(b, m, 0.12, 2.9, 0.12, x, 1.45, z, wood);
    }
    box(b, m, 6.4, 0.1, 3.0, 0.3, 2.95, 0.05, Vignette.c(0x3A3F48), rotX: 0.06);
    b.buildInto(detail, 'forge', castsShadows: false, lightChannelMask: 0x01);
    // The fire in the mouth.
    _fireMat = pbr(rgb(1, 0.5, 0.1), roughness: 0.9, emissive: rgb(1, 0.45, 0.12), emissiveStrength: 3);
    detail.add(
      Node(
        name: 'forge fire',
        mesh: Mesh(CuboidGeometry(vm.Vector3(0.5, 0.36, 0.04)), _fireMat),
        localTransform: place(trs(vm.Vector3(_mouthX - 0.65, 0.84, -0.36))),
      )..castsShadows = false,
    );
    // The hammer: a handle and a head, held in the smith's right hand.
    final hb = MeshBatch()
      ..box(vm.Vector3(0, -0.16, 0), vm.Vector3(0.035, 0.36, 0.035))
      ..box(vm.Vector3(0, -0.34, -0.04), vm.Vector3(0.09, 0.09, 0.2));
    _hammer = Node(name: 'forge hammer', mesh: Mesh(hb.build(), pbr(Vignette.c(0x4A4E56), roughness: 0.4, metallic: 0.7)))..castsShadows = false;
    detail.add(_hammer);
    // The glyphs: each its own material (each heats and cools).
    final texts = [
      for (final (i, (a, c, l)) in _pairs.indexed)
        for (final x in [a, c, l]) (x, _code[i] ? _codeStyle : _style),
    ];
    for (var i = 0; i < texts.length; i++) {
      _mats.add(pbr(Vignette.c(0xD9B45A), roughness: 0.32, metallic: 0.65, emissive: rgb(1, 0.42, 0.1), emissiveStrength: 0));
    }
    final solids = await extrudeTextsAt(texts, unitsPerPx: 0.34 / 160, depth: 0.08);
    _glyphs = [
      for (var i = 0; i < solids.length; i++)
        () {
          final n = Node(name: 'forge glyph', mesh: Mesh(glyphGeometry(solids[i].mesh), _mats[i]))
            ..castsShadows = false
            ..visible = false;
          detail.add(n);
          return Glyph3D(solids[i], n);
        }(),
    ];
    await sign(2.6, 0.5, vm.Matrix4.translation(vm.Vector3(0.3, 2.62, -1.32)), (c, s) {
      c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF2B2422));
      Vignette.text(c, '合字工房 · LIGATURES', Rect.fromLTWH(0, 0, s.width, s.height * 0.62), s.height * 0.4, const Color(0xFFF2C94C), lang: 'ja');
      Vignette.text(
        c,
        'f + i → ﬁ    - + > → ->    ! + = → !=',
        Rect.fromLTWH(0, s.height * 0.6, s.width, s.height * 0.36),
        s.height * 0.22,
        const Color(0xFFF4EBD8),
        family: BP.mono,
      );
    });
    _smith = person(
      FigureLook()
        ..top = rgbHex(0x5B4B3A)
        ..legs = rgbHex(0x2B3442)
        ..skirt = rgbHex(0x3A2E26)
        ..skirtLength = 1.05
        ..shoes = rgbHex(0x1B1C20)
        ..skin = rgbHex(0xC59A7C)
        ..hairColor = rgbHex(0x2A211B)
        ..hair = Hair.short
        ..gloves = rgbHex(0x6B4A2E)
        ..girth = 1.12,
    );
    _ready = true;
  }

  // ── Posing ────────────────────────────────────────────────────────────────

  final _hm = vm.Matrix4.identity();

  @override
  void pose(double u, double t, double night) {
    if (!_ready) return;
    pool.begin();
    final k = (u / _cycle).floor() % _pairs.length, c = u % _cycle;
    // The belt's slats, moving.
    for (var i = 0; i < 9; i++) {
      final x = _beltX0 + ((i * 0.3 + c * 0.9) % 2.7) - 0.35;
      if (x < _mouthX - 0.5) pbox(x, _beltY - 0.01, -0.62, 0.05, 0.02, 0.46, Vignette.c(0x22252B));
    }
    // The fire breathes; brighter while a pair's in it.
    final inFire = smooth(_belt, _belt + 0.3, c) * (1 - smooth(_fire, _outAt, c));
    _fireMat.emissiveStrength = 2.4 + 0.6 * math.sin(t * 7) + 0.4 * math.sin(t * 13.1) + 3 * inFire;
    // Smoke from the chimney.
    for (var n = 0; n < 3; n++) {
      final age = ((t * 0.35 + n / 3) % 1);
      final w = world(-1.9, 3.5, 0.55);
      kit.fx.puff(w.x, w.y, w.z, age, 0.35, seed: n + 40, n: 2);
    }
    // Every glyph not in this turn (or on the rack) hidden.
    for (final g in _glyphs) {
      g.node.visible = false;
    }
    // The rack: what's been forged this time round, cooled.
    for (var j = 0; j < k; j++) {
      _show(3 * j + 2, _rackX - 0.45 + 0.45 * j, 1.48, 0.12, 0);
    }
    final a = 3 * k, b = 3 * k + 1, lig = 3 * k + 2;
    final ax = _anvil.$1, ay = _anvil.$2 + 0.22, az = _anvil.$3;
    var heat = 0.0;
    if (c < _fire) {
      // Along the belt into the mouth (in the fire from _belt).
      final f = seg(c, 0, _fire);
      final x = lerp(_beltX0, _mouthX - 0.4, f);
      heat = smooth(_belt, _fire, c);
      final shown = c < _fire - 0.15;
      if (shown) {
        _show(a, x - 0.14, _beltY + 0.22, -0.62, heat);
        _show(b, x + 0.14, _beltY + 0.22, -0.62, heat);
      }
    } else if (c < _blows.last + 0.05) {
      // Out onto the anvil, red-hot, pressed closer at each blow; at the
      // last, one glyph.
      final f = eio(seg(c, _fire, _outAt));
      heat = 1;
      final x = lerp(_mouthX - 0.4, ax, f), y = lerp(_beltY + 0.22, ay, f), z = lerp(-0.62, az, f);
      var gap = 0.14;
      for (final at in _blows) {
        if (c >= at) gap -= 0.045;
      }
      if (c < _blows.last) {
        _show(a, x - gap, y, z, heat);
        _show(b, x + gap, y, z, heat);
      } else {
        _show(lig, x, y, z, heat);
      }
    } else if (c < _done) {
      // Picked up, cooling, onto the rack.
      final f = eio(seg(c, _rack - 0.2, _done));
      heat = 1 - seg(c, _blows.last, _done);
      _show(lig, lerp(ax, _rackX - 0.45 + 0.45 * k, f), lerp(ay, 1.48, f) + 0.3 * math.sin(math.pi * f), lerp(az, 0.12, f), heat);
    } else {
      _show(lig, _rackX - 0.45 + 0.45 * k, 1.48, 0.12, 0);
    }
    // Sparks and a flash at each blow.
    for (final at in _blows) {
      final age = c - at;
      if (age < 0 || age > 0.7) continue;
      final w = world(ax, ay, az);
      for (var s = 0; s < 16; s++) {
        final ang = rnd(s, k, 3) * math.pi * 2, up = 1.2 + 2.2 * rnd(s, k, 4), out = 0.8 + 1.6 * rnd(s, k, 5);
        final px = w.x + math.cos(ang) * out * age, pz = w.z + math.sin(ang) * out * age, py = w.y + up * age - 4.9 * age * age;
        kit.fx.spark(px, py, pz, 0.02 * (1 - age / 0.7), vm.Vector4(1, 0.55, 0.15, 1), 7, math.cos(ang) * out, up - 9.8 * age, math.sin(ang) * out);
      }
      if (age < 0.15) kit.fx.flashes.add((w.clone(), vm.Vector4(1, 0.5, 0.15, 1), 1 - age / 0.15));
    }
    // The smith: hammer up and down at the blows; else tending the fire,
    // a look at the work.
    final p = _p..rest();
    p.pos.setValues(ax + 0.15, 0, az + 0.72);
    final m = Manner.of(140);
    Idle.stand(p, t, m, look: 0.25, shift: 0.4);
    p.yaw = -0.15;
    var raise = 0.0;
    for (final at in _blows) {
      raise = math.max(raise, smooth(at - 0.42, at - 0.18, c) * (1 - smooth(at - 0.06, at, c)));
    }
    final striking = c > _blows.first - 0.5 && c < _blows.last + 0.25;
    if (striking) {
      // Short blows: the hammer up to the shoulder, the elbow folding.
      p.lean = 0.25 + 0.06 * (1 - raise);
      p.armPitch[1] = lerp(1.05, 1.6, raise);
      p.armRoll[1] = 0.12;
      p.elbow[1] = lerp(0.5, 1.45, raise);
      p.headPitch = 0.3;
    }
    worldPose(p);
    if (c > _fire && c < _done) {
      // The tongs' hand on the work.
      kit.crew.aim(p, 0, world(ax - 0.2, ay + 0.02, az - 0.05));
    }
    kit.figures.draw(_smith, p);
    // The hammer in the right hand.
    _hm
      ..setFrom(kit.figures.rig.hand[1])
      ..translateByDouble(0.0, -0.06, 0.0, 1.0);
    _hammer.localTransform = _hm;
    pool.end();
  }

  /// Glyph [i] at (x, y, z) of the frame, [heat] 0 cold … 1 red-hot.
  void _show(int i, double x, double y, double z, double heat) {
    put(_glyphs[i], x, y, z);
    _mats[i]
      ..emissiveStrength = 3.2 * heat
      ..baseColorFactor = vm.Vector4(lerp(0.72, 1, heat), lerp(0.45, 0.3, heat), lerp(0.1, 0.06, heat), 1);
  }

  // ── The camera ────────────────────────────────────────────────────────────

  @override
  Shot shot(double u) {
    final c = u % _cycle;
    // From the path: the belt and the fire, then in on the anvil for the
    // blows.
    final close = smooth(_fire - 0.6, _outAt, c) * (1 - smooth(_rack, _done + 0.4, c));
    final eye = vm.Vector3(lerp(-0.6, 0.1, close), lerp(2.0, 1.6, close), lerp(-6.4, -3.2, close));
    final tg = vm.Vector3(lerp(-0.6, _anvil.$1, close), lerp(1.2, 1.0, close), lerp(0, _anvil.$3, close));
    return Shot(eye, tg, fov: 42, settle: 0.9, drift: 0.4);
  }
}
