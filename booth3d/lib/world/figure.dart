import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'figure_rig.dart';
import 'kit.dart';
import 'models.dart';
import 'site_geo.dart' show setTrs;

export 'figure_rig.dart';

/// Name City's people, drawn: everyone — the crew and the people in the
/// streets — is the same human (a torso that narrows to the waist and
/// widens to the hips, a head with one simple face for all, hair, arms
/// with elbows and hands, legs with knees and shoes), posed from a
/// [FigurePose] by [FigureRig] and dressed by a [FigureLook]: work clothes,
/// hi-vis vests, hard hats, lab coats, suits, jackets, coats, skirts, bags.
/// The head, its hair, the hands and the shoes are sculpted in Blender
/// (tool/blender/people.py).
///
/// One [Figures] per scene draws them all: every part is an instanced mesh
/// (one draw for everybody's heads, one for everybody's forearms…), its
/// colour per instance, its shading in its vertex colours; people near the
/// camera wear the full parts, those far from it simpler ones, and each
/// frame the meshes hold just who's showing. Nothing is allocated per
/// frame.

// ── What they wear ──────────────────────────────────────────────────────────

/// The hairstyles: none (or under a hat, cropped), short, medium (over the
/// ears), a bob, long.
enum Hair { none, short, medium, bob, long }

/// What a person looks like: their build, skin and hair, and what they
/// wear (linear colours). Fixed for good when they're added to [Figures].
class FigureLook {
  /// Height (1: 1.72 m), girth (1: average), and a slimmer build (narrow
  /// shoulders, a waist, wider hips).
  double size = 1, girth = 1;
  bool slim = false;

  vm.Vector4 skin = _white, hairColor = _white;
  Hair hair = Hair.short;

  /// The top (shirt, jacket, coat) and its sleeves (null: the top's), an
  /// open layer over it (a vest, an open jacket; null: none) and the
  /// reflective stripes on it.
  vm.Vector4 top = _white;
  vm.Vector4? sleeves, layer;
  bool stripes = false;

  /// Bare forearms (short sleeves).
  bool bareArms = false;

  /// Trousers (the thighs and shins), the shins if not (bare legs or
  /// tights under a skirt), the shoes; gloves (null: bare hands).
  vm.Vector4 legs = _white, shoes = _white;
  vm.Vector4? shins, gloves;

  /// The shoes' soles (null: to go with them, see [Figures]).
  vm.Vector4? soles;

  /// A skirt, or a coat's or a lab coat's tail, and its length (1: to the
  /// knee).
  vm.Vector4? skirt;
  double skirtLength = 1;

  /// A hard hat, a cap.
  vm.Vector4? hardHat, cap;

  /// A backpack, a bag in the left hand, a parasol in the right, a
  /// clipboard in the left.
  vm.Vector4? backpack, bag, parasol;
  bool clipboard = false;

  static final _white = vm.Vector4(1, 1, 1, 1);
}

/// sRGB 0xRRGGBB as a linear colour.
vm.Vector4 rgbHex(int c) => v4(hex3(c));

// ── Drawing them ────────────────────────────────────────────────────────────

/// One person's instances.
class _Body {
  _Body(this.look, this.n);

  /// (Capture runs: feet off the ground, last frame; the last frames.)
  bool aloft = false;

  /// Sitting (on a bench, a seat): on whatever they sit on, not out of it.
  bool seated = false;

  /// (Capture runs: this frame's chest, inverted, and palms; its arms, for
  /// the log.)
  String pose = '';
  final chestInv = vm.Matrix4.identity();
  final palms = [vm.Vector3.zero(), vm.Vector3.zero()];
  List<String>? ring;
  final FigureLook look;

  /// Its number.
  final int n;

  /// What they last showed (see [FigureMotion]).
  final motion = FigureMotion();

  /// Its parts (the ones its look has), and by name; drawn near the camera
  /// (in full) or far from it (simpler).
  final uses = <_Use>[];
  late final _Use torso, hips, head, eyes, brows;
  _Use? hair, hat, cap, vest, lapels, stripes, skirt, backpack, bag, board, parasol;
  final upper = <_Use>[], lower = <_Use>[], hand = <_Use>[], thigh = <_Use>[], shin = <_Use>[], foot = <_Use>[], sole = <_Use>[];
  bool near = false;
  bool hidden = false;

  /// Where they were drawn in the last frame (feet, without the nudge),
  /// how wide, which way they faced, whether walking or steering; when.
  double x = 0, y = 0, z = 0, r = 0.25, yaw = 0, seen = double.nan;
  bool walking = false, steer = true;

  /// Their nudge (see [FigurePose.nudgeX]), and where it's heading.
  double nx = 0, nz = 0, tx = 0, tz = 0;

  /// How fast they were going (m/s, from the frame before).
  double vx = 0, vz = 0;
}

/// One of a person's instances of a part (one side's, of a pair): where it's
/// drawn this frame, in what colour; whether it's shown.
class _Use {
  _Use(this.part, this.color);
  final _Part part;
  final vm.Vector4 color;
  final m = vm.Matrix4.identity();
  bool on = false;
}

/// One of the people's parts: its mesh near the camera and the simpler one
/// for far from it ([far] null: the same one, or, [farShown] false, none).
class _Part {
  _Part(this.near, [this.far, this.farShown = true]);
  final _Slots near;
  final _Slots? far;
  final bool farShown;

  _Slots? at(bool isNear) => isNear ? near : (far ?? (farShown ? near : null));
}

/// A mesh's instances, packed afresh each frame: just whoever's showing it
/// (its colour set only when its owner changes).
class _Slots {
  _Slots(this.mesh);
  final InstancedMesh mesh;
  final _owners = <_Use?>[];
  int _used = 0;

  void put(_Use u) {
    final i = _used++;
    if (i < _owners.length) {
      mesh.setInstanceTransform(i, u.m);
      if (!identical(_owners[i], u)) {
        mesh.setInstanceColor(i, u.color);
        _owners[i] = u;
      }
    } else {
      mesh.addInstance(u.m, color: u.color);
      _owners.add(u);
    }
  }

  /// Drops the instances no one used this frame.
  void end() {
    while (_owners.length > _used) {
      mesh.removeInstanceAt(_owners.length - 1);
      _owners.removeLast();
    }
    _used = 0;
  }
}

/// Everybody's parts in one scene: a draw per part for everybody, colours
/// per instance; people near the camera in full, those far from it simpler.
/// [add] a person, then [draw] them every frame (or [hide] them), and
/// [commit] the frame once everyone's drawn: what's drawn is smoothed over
/// the poses' jumps (each person's [FigureMotion], on its clock).
class Figures {
  Figures._(this.scene) {
    _build();
  }

  static final _of = Expando<Figures>('figures');

  /// The sculpted parts (people.glb), loaded before anyone's drawn.
  static Map<String, MeshData>? _parts;
  static Future<void> load() async => _parts ??= await modelParts('assets/models/people.glb');

  /// The scene's figures (made on first use).
  static Figures of(Scene scene) => _of[scene] ??= Figures._(scene);

  final Scene scene;
  final rig = FigureRig();
  final _bodies = <_Body>[];

  late final _Part _torso, _torsoSlim, _hips, _head, _eyes, _brows, _upperArm, _forearm, _hand, _thigh, _shin, _foot, _sole;
  late final _Part _hardHat, _cap, _vest, _lapels, _stripes, _skirt, _backpack, _bag, _board, _parasol;
  final _hairs = <_Part>[];
  final _slots = <_Slots>[];
  late final PhysicallyBasedMaterial _stripeMat;

  /// The reflective stripes catch the floodlights after dark (0 day … 1
  /// night).
  set night(double v) => _stripeMat.emissiveStrength = 0.02 + 0.9 * smooth(0.15, 0.6, v);

  void _build() {
    // (Fabric: a soft sheen where it turns away.)
    final cloth = pbr(rgb(1, 1, 1), roughness: 0.82)
      ..sheenColor = vm.Vector4(0.16, 0.16, 0.17, 1)
      ..sheenRoughness = 0.55;
    final skin = pbr(rgb(1, 1, 1), roughness: 0.55);
    final hair = pbr(rgb(1, 1, 1), roughness: 0.5);
    final eye = pbr(rgb(1, 1, 1), roughness: 0.22);
    final rubber = pbr(rgb(1, 1, 1), roughness: 0.85);
    final shiny = pbr(rgb(1, 1, 1), roughness: 0.3, metallic: 0.05);
    final shoe = pbr(rgb(1, 1, 1), roughness: 0.5);
    _stripeMat = pbr(rgb(1, 1, 1), roughness: 0.25, metallic: 0.25, emissive: rgb(0.85, 0.88, 0.9), emissiveStrength: 0.02);
    _Slots im(MeshGeometry g, Material m, String name) {
      final mesh = InstancedMesh(geometry: g, material: m, cullInstances: true);
      scene.add(Node(name: 'people $name')..addComponent(InstancedMeshComponent(mesh)));
      final slots = _Slots(mesh);
      _slots.add(slots);
      return slots;
    }

    final parts = _parts!;
    MeshGeometry sculpted(String name) => MeshGeometry.fromMeshData(parts[name]!);
    _Part both(String name, Material m, String label) => _Part(im(sculpted(name), m, label), im(sculpted('${name}_far'), m, '$label far'));
    _Part lofted(MeshGeometry Function(bool near) g, Material m, String label) => _Part(im(g(true), m, label), im(g(false), m, '$label far'));
    _Part one(MeshGeometry g, Material m, String label) => _Part(im(g, m, label));

    _torso = lofted((near) => _torsoGeometry(slim: false, near: near), cloth, 'torsos');
    _torsoSlim = lofted((near) => _torsoGeometry(slim: true, near: near), cloth, 'slim torsos');
    _hips = lofted(_hipsGeometry, cloth, 'hips');
    _head = both('head', skin, 'heads');
    // (Eyes and brows: too small to see from afar.)
    _eyes = _Part(im(sculpted('eyes'), eye, 'eyes'), null, false);
    _brows = _Part(im(sculpted('brows'), hair, 'brows'), null, false);
    for (final h in Hair.values.skip(1)) {
      _hairs.add(both('hair_${h.name}', hair, 'hair ${h.name}'));
    }
    _upperArm = lofted(_upperArmGeometry, cloth, 'upper arms');
    _forearm = lofted(_forearmGeometry, cloth, 'forearms');
    _hand = both('hand', skin, 'hands');
    _thigh = lofted(_thighGeometry, cloth, 'thighs');
    _shin = lofted(_shinGeometry, cloth, 'shins');
    _foot = both('shoe', shoe, 'shoes');
    _sole = both('sole', rubber, 'soles');
    _hardHat = one(_hardHatGeometry(), shiny, 'hard hats');
    _cap = one(_capGeometry(), cloth, 'caps');
    _vest = one(_vestGeometry(), cloth, 'vests');
    _lapels = one(_lapelsGeometry(), cloth, 'lapels');
    _stripes = one(_stripesGeometry(), _stripeMat, 'vest stripes');
    _skirt = one(_skirtGeometry(), cloth, 'skirts');
    _backpack = one(_backpackGeometry(), cloth, 'backpacks');
    _bag = one(_bagGeometry(), cloth, 'bags');
    _board = one(_boardGeometry(), cloth, 'clipboards');
    _parasol = one(_parasolGeometry(), cloth, 'parasols');
  }

  /// Adds a person who looks like [look]; returns their number for [draw].
  int add(FigureLook look) {
    final b = _Body(look, _bodies.length);
    _bodies.add(b);
    _Use use(_Part p, vm.Vector4 c) {
      final u = _Use(p, c);
      b.uses.add(u);
      return u;
    }

    final skin = _toned(look.skin);
    b
      ..torso = use(look.slim ? _torsoSlim : _torso, look.top)
      // (The seat of the trousers, or under the skirt in its colour.)
      ..hips = use(_hips, look.skirt ?? look.legs)
      ..head = use(_head, skin)
      ..eyes = use(_eyes, vm.Vector4(1, 1, 1, 1))
      ..brows = use(_brows, look.hairColor);
    if (look.hair != Hair.none) b.hair = use(_hairs[look.hair.index - 1], look.hairColor);
    final sleeves = look.sleeves ?? look.top;
    for (var s = 0; s < 2; s++) {
      b.upper.add(use(_upperArm, sleeves));
      b.lower.add(use(_forearm, look.bareArms ? skin : sleeves));
      b.hand.add(use(_hand, look.gloves ?? skin));
      b.thigh.add(use(_thigh, look.legs));
      b.shin.add(use(_shin, look.shins == null ? look.legs : (look.shins == look.skin ? skin : look.shins!)));
      b.foot.add(use(_foot, look.shoes));
      b.sole.add(use(_sole, look.soles ?? _soleFor(look.shoes)));
    }
    if (look.hardHat case final c?) b.hat = use(_hardHat, c);
    if (look.cap case final c?) b.cap = use(_cap, c);
    if (look.layer case final c?) {
      b.vest = use(_vest, c);
      // (An open jacket, its sleeves of a piece with it: lapels, a collar.)
      if (look.sleeves == c) b.lapels = use(_lapels, c);
    }
    if (look.stripes) b.stripes = use(_stripes, vm.Vector4(1, 1, 1, 1));
    if (look.skirt case final c?) b.skirt = use(_skirt, c);
    if (look.backpack case final c?) b.backpack = use(_backpack, c);
    if (look.bag case final c?) b.bag = use(_bag, c);
    if (look.clipboard) b.board = use(_board, vm.Vector4(1, 1, 1, 1));
    if (look.parasol case final c?) b.parasol = use(_parasol, c);
    return b.n;
  }

  /// The look person [n] was added with.
  FigureLook lookOf(int n) => _bodies[n].look;

  /// How fast person [n] was going in the last frame (x, z, m/s).
  (double, double) velocityOf(int n) => (_bodies[n].vx, _bodies[n].vz);

  /// Hides person [n].
  void hide(int n) => _bodies[n].hidden = true;

  /// One tiny instance of every part at [at] (in view), so the shaders'
  /// warm-up draws them all: the first frame's [commit] takes them away.
  void prime(vm.Vector3 at) {
    final m = vm.Matrix4.compose(at, vm.Quaternion.identity(), vm.Vector3.all(0.01));
    for (final s in _slots) {
      if (s._owners.isNotEmpty) continue;
      s.mesh.addInstance(m);
      s._owners.add(null);
    }
  }

  /// The nearest the camera people are drawn simpler from (and they stay in
  /// full until a little further).
  static const _nearAt = 16.0, _farAt = 18.0;

  /// Packs this frame's people into their parts' meshes: just who's
  /// showing, in full near [eye] (the camera), simpler far from it. Once a
  /// frame, after everyone's been drawn.
  void commit(vm.Vector3 eye) {
    for (final b in _bodies) {
      if (b.hidden || b.seen.isNaN) continue;
      final dx = b.x - eye.x, dy = b.y - eye.y, dz = b.z - eye.z;
      final d2 = dx * dx + dy * dy + dz * dz;
      b.near = d2 < (b.near ? _farAt * _farAt : _nearAt * _nearAt);
      for (final u in b.uses) {
        if (u.on) u.part.at(b.near)?.put(u);
      }
    }
    for (final s in _slots) {
      s.end();
    }
  }

  final _m = vm.Matrix4.identity(), _t = vm.Matrix4.identity();

  /// Poses person [n] as [p] and draws them ([p.visible] false hides them).
  void draw(int n, FigurePose p) {
    final b = _bodies[n], look = b.look;
    if (!p.visible) {
      hide(n);
      return;
    }
    for (final u in b.uses) {
      u.on = false;
    }
    final now = FigureMotion.clock;
    if (now != _frameAt) _nudge(now);
    b.hidden = false;
    final size = look.size, g = look.girth * size, r = rig;
    // Out of the way of whoever was in it.
    p
      ..nudgeX = p.steer && _nudgeOn ? b.nx : 0
      ..nudgeZ = p.steer && _nudgeOn ? b.nz : 0;
    if (b.seen != now) _seen.add(n);
    final since = now - b.seen;
    // (Capture runs: someone jumping somewhere between two frames.)
    if (_counting && since > 1e-4 && since < 0.07) {
      final jx = p.pos.x - b.x, jz = p.pos.z - b.z, jump = math.sqrt(jx * jx + jz * jz);
      if (jump > 0.8 && _jumps.length < 40) {
        _jumps.add('#$n at t=${now.toStringAsFixed(2)}: ${jump.toStringAsFixed(1)} m from ${b.x.toStringAsFixed(1)},${b.z.toStringAsFixed(1)} to ${p.pos.x.toStringAsFixed(1)},${p.pos.z.toStringAsFixed(1)}');
      }
    }
    if (since > 1e-4 && since < 0.25) {
      b
        ..vx = (p.pos.x - b.x) / since
        ..vz = (p.pos.z - b.z) / since;
    } else if (!(since <= 1e-4)) {
      b.vx = b.vz = 0;
    }
    b
      ..x = p.pos.x
      ..y = p.pos.y
      ..z = p.pos.z
      ..r = 0.24 * size * math.sqrt(look.girth)
      ..yaw = p.yaw
      ..walking = p.stride.isFinite
      ..steer = p.steer
      ..seated = math.min(p.legPitch[0], p.legPitch[1]) > 0.9
      ..seen = now;
    p.motion = b.motion;
    r.solve(p, size: size, width: look.slim ? 0.92 : 1, motion: b.motion);
    if (_counting) {
      b.chestInv
        ..setFrom(r.chest)
        ..invert();
      b.palms[0].setFrom(r.palms[0]);
      b.palms[1].setFrom(r.palms[1]);
      String f(double v) => v.toStringAsFixed(2);
      b.pose = 'pitch ${f(p.armPitch[0])}/${f(p.armPitch[1])} roll ${f(p.armRoll[0])}/${f(p.armRoll[1])} elbow ${f(p.elbow[0])}/${f(p.elbow[1])} reach ${p.reachingWith(0)}/${p.reachingWith(1)} lean ${f(p.lean)} stoop ${f(p.stoop)} twist ${f(p.twist)} stride ${p.stride.isFinite} clip ${p.clipboard}';
    }
    if (_counting) {
      // (Capture runs: anyone whose feet leave the ground, not sitting; the
      // frames before it, for the first few.)
      final foot = math.min(r.feet[0].storage[13], r.feet[1].storage[13]) - p.pos.y;
      // (Up: half a metre; walking, not running, a third of one. Down: the
      // ankle below the ground.)
      final pace = math.sqrt(b.vx * b.vx + b.vz * b.vz);
      final aloft = !b.seated && (foot > 0.5 || (foot > 0.3 && pace < 2.6) || foot < 0.0);
      final o = b.motion.now;
      (b.ring ??= []).add('      t=${now.toStringAsFixed(3)} posed hip ${(r.joints[FigureRig.jHipY] - o[FigureRig.jHipY]).toStringAsFixed(2)} shown ${r.joints[FigureRig.jHipY].toStringAsFixed(2)} feet ${foot.toStringAsFixed(2)} thigh ${(r.joints[FigureRig.jLeg] - o[FigureRig.jLeg]).toStringAsFixed(2)}${o[FigureRig.jLeg] >= 0 ? '+' : ''}${o[FigureRig.jLeg].toStringAsFixed(2)} knee ${(r.joints[FigureRig.jLeg + 1] - o[FigureRig.jLeg + 1]).toStringAsFixed(2)}${o[FigureRig.jLeg + 1] >= 0 ? '+' : ''}${o[FigureRig.jLeg + 1].toStringAsFixed(2)} bob ${p.bob.toStringAsFixed(2)} lean ${p.lean.toStringAsFixed(2)} stoop ${p.stoop.toStringAsFixed(2)} stride ${p.stride.toStringAsFixed(1)} y ${p.pos.y.toStringAsFixed(2)}');
      if (b.ring!.length > 7) b.ring!.removeAt(0);
      if (aloft) _aloftFrames++;
      if (aloft && !b.aloft) _aloftEvents++;
      if (aloft && !b.aloft && _events < 4) {
        _events++;
        _aloft.addAll(b.ring!);
      }
      if (aloft && !b.aloft && _aloft.length < 200) {
        _aloft.add('#$n at t=${now.toStringAsFixed(2)}: feet ${foot.toStringAsFixed(2)} m up, hips ${r.joints[FigureRig.jHipY].toStringAsFixed(2)} (offset ${b.motion.now[FigureRig.jHipY].toStringAsFixed(2)}), bob ${p.bob.toStringAsFixed(2)} stride ${p.stride.toStringAsFixed(2)} legs ${p.legPitch[0].toStringAsFixed(2)}/${p.legPitch[1].toStringAsFixed(2)} at ${p.pos.x.toStringAsFixed(1)},${p.pos.y.toStringAsFixed(2)},${p.pos.z.toStringAsFixed(1)}${look.hardHat != null ? ' (hard hat)' : ''}');
      } else if (!aloft && b.aloft && _aloft.length < 200) {
        _aloft.add('  #$n down at t=${now.toStringAsFixed(2)}');
      }
      b.aloft = aloft;
    }
    _set(b.torso, r.chest, g, size, g);
    _set(b.hips, r.pelvis, g, size, g);
    // Children's heads are big for their size.
    final hs = size < 0.95 ? math.pow(size, 0.55).toDouble() : size;
    _set(b.head, r.head, hs, hs, hs);
    _set(b.eyes, r.head, hs, hs, hs);
    _set(b.brows, r.head, hs, hs, hs);
    if (b.hair case final u?) _set(u, r.head, hs, hs, hs);
    // (A touch sturdier than life: they read better from afar.)
    final arm = math.sqrt(look.girth) * size * 1.05, leg = math.sqrt(look.girth) * size * 1.08;
    for (var s = 0; s < 2; s++) {
      _set(b.upper[s], r.upper[s], arm, size, arm);
      _set(b.lower[s], r.lower[s], arm, size, arm);
      // (The right hand, sculpted; the left, its mirror.)
      _set(b.hand[s], r.hand[s], s == 0 ? -size : size, size, size);
      _set(b.thigh[s], r.thighs[s], leg, size, leg);
      _set(b.shin[s], r.shins[s], leg, size, leg);
      _set(b.foot[s], r.feet[s], size, size, size);
      _set(b.sole[s], r.feet[s], size, size, size);
    }
    if (b.hat case final u?) {
      // On the head; or tossed in the air, spinning.
      _t
        ..setFrom(r.head)
        ..multiply(setTrs(_m, 0, p.hatUp, 0, yaw: p.hatSpin, roll: 0.3 * math.sin(p.hatSpin)));
      _set(u, _t, hs, hs, hs);
    }
    // (A size up: over the hair.)
    if (b.cap case final u?) _set(u, r.head, hs * 1.06, hs * 1.06, hs * 1.06);
    if (b.vest case final u?) _set(u, r.chest, g, size, g);
    if (b.lapels case final u?) _set(u, r.chest, g, size, g);
    if (b.stripes case final u?) _set(u, r.chest, g, size, g);
    if (b.skirt case final u?) _set(u, r.pelvis, g, size * look.skirtLength, g);
    if (b.backpack case final u?) _set(u, r.chest, size, size, size);
    if (b.bag case final u?) {
      // Hanging from the left hand.
      final at = r.palms[0];
      _set(u, FigureRig.yawAt(_t, at.x, at.y, at.z, p.yaw), size, size, size);
    }
    if (b.board case final u?) {
      if (p.clipboard) {
        // Held up in the left hand, its face tilted to be read.
        _t
          ..setFrom(r.hand[0])
          ..multiply(setTrs(_m, 0, -0.075, -0.12, pitch: -0.35));
        _set(u, _t, size, size, size);
      } else {
        u.on = false;
      }
    }
    if (b.parasol case final u?) {
      final at = r.palms[1];
      _set(u, FigureRig.yawAt(_t, at.x, at.y, at.z, p.yaw), size, size, size);
    }
  }

  // ── Out of each other's way ───────────────────────────────────────────────

  /// Who was drawn in the frame at [_frameAt].
  final _seen = <int>[];
  double _frameAt = double.nan;

  /// Capture runs count people still walking into each other (the ones
  /// that steer): frames, pairs overlapping (summed), the deepest.
  int _frames = 0, _bumps = 0;
  double _deepest = 0, _deepestAt = 0;
  String _deepestWho = '';

  /// The worst moments (each a second or more apart): (depth, when, who).
  final _worst = <(double, double, String)>[];

  String overlapReport() =>
      'FIGURES overlap: ${_frames == 0 ? 0 : (_bumps / _frames).toStringAsFixed(2)} pairs a frame over $_frames frames, deepest ${(_deepest * 100).round()} cm at t=${_deepestAt.toStringAsFixed(1)} ($_deepestWho)\n'
      '${[for (final (d, t, w) in (_worst..sort((a, b) => b.$1.compareTo(a.$1))).take(12)) '  ${(d * 100).round()} cm at t=${t.toStringAsFixed(1)}: $w'].join('\n')}\n'
      'FIGURES jumps: ${_jumps.length}${[for (final j in _jumps) '\n  $j'].join()}\n'
      'FIGURES aloft: $_aloftEvents times, $_aloftFrames frames${[for (final j in _aloft.take(80)) '\n  $j'].join()}\n'
      'FIGURES in solids: ${[for (final e in _inside.entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1))) '\n  ${e.key}: ${e.value.$1} frames, worst ${(e.value.$2 * 100).round()} cm at t=${e.value.$3.toStringAsFixed(1)} (${e.value.$4})'].join()}\n'
      'FIGURES hands in: ${[for (final e in _hands.entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1))) '\n  ${e.key}: ${e.value.$1} frames, worst ${(e.value.$2 * 100).round()} cm at t=${e.value.$3.toStringAsFixed(1)} (${e.value.$4})'].join()}'
      '${[for (final l in _selfLog) '\n    $l'].join()}';

  /// Solid things people keep out of (and capture runs check they did), by
  /// kind: each a box (centre, half extents). Whoever has them sets them
  /// (and clears them when they're gone).
  final solids = <String, List<(vm.Vector3, vm.Vector3)>>{};

  /// The ones that never move (the street furniture: hundreds of them), by
  /// kind, and by grid cell for looking up only those nearby.
  final fixed = <String, List<(vm.Vector3, vm.Vector3)>>{};
  final _cells = <int, List<(vm.Vector3, vm.Vector3)>>{};
  static const _cellSize = 4.0;
  static int _cellOf(int i, int k) => (i + 4096) * 8192 + (k + 4096);

  /// Adds [kinds] to the [fixed] solids.
  void addFixed(Map<String, List<(vm.Vector3, vm.Vector3)>> kinds) {
    for (final MapEntry(key: kind, value: boxes) in kinds.entries) {
      (fixed[kind] ??= []).addAll(boxes);
      for (final box in boxes) {
        // (In every cell its footprint, and a person's reach, touches.)
        final (c, h) = box;
        final i0 = ((c.x - h.x - 0.6) / _cellSize).floor(), i1 = ((c.x + h.x + 0.6) / _cellSize).floor();
        final k0 = ((c.z - h.z - 0.6) / _cellSize).floor(), k1 = ((c.z + h.z + 0.6) / _cellSize).floor();
        for (var i = i0; i <= i1; i++) {
          for (var k = k0; k <= k1; k++) {
            (_cells[_cellOf(i, k)] ??= []).add(box);
          }
        }
      }
    }
  }

  static const _none = <(vm.Vector3, vm.Vector3)>[];
  List<(vm.Vector3, vm.Vector3)> _fixedNear(double x, double z) => _cells[_cellOf((x / _cellSize).floor(), (z / _cellSize).floor())] ?? _none;

  /// Whether a capture run is counting.
  static bool get checking => _counting;

  /// (x, z) moved out of every solid that spans someone [r] wide standing
  /// at height [y] there, by as little as it takes (into [out]: x, z): out
  /// the side they came from ([fromX], [fromZ]: where they were before
  /// being moved there, if they weren't in it), else the nearer side.
  void outOfSolids(double x, double y, double z, double r, List<double> out, {double? fromX, double? fromZ}) {
    void outOf(List<(vm.Vector3, vm.Vector3)> boxes) {
      for (final (c, h) in boxes) {
        if (y > c.y + h.y - 0.05 || y + 1.6 < c.y - h.y) continue;
        final hx = h.x + r + 0.02, hz = h.z + r + 0.02, dx = x - c.x, dz = z - c.z;
        if (dx.abs() >= hx || dz.abs() >= hz) continue;
        // (The side they came from, if they came from outside it.)
        final ox = fromX == null ? 0.0 : fromX - c.x, oz = fromZ == null ? 0.0 : fromZ - c.z;
        final outX = fromX != null && ox.abs() >= hx, outZ = fromZ != null && oz.abs() >= hz;
        final px = hx - dx.abs(), pz = hz - dz.abs();
        if (outX && !outZ) {
          x = c.x + (ox >= 0 ? hx : -hx);
        } else if (outZ && !outX) {
          z = c.z + (oz >= 0 ? hz : -hz);
        } else if (px < pz) {
          x += dx >= 0 ? px : -px;
        } else {
          z += dz >= 0 ? pz : -pz;
        }
      }
    }

    for (var pass = 0; pass < 2; pass++) {
      for (final boxes in solids.values) {
        outOf(boxes);
      }
      outOf(_fixedNear(x, z));
    }
    out
      ..[0] = x
      ..[1] = z;
  }

  final _out = [0.0, 0.0];

  /// Which solids (kind and box) are within a metre of (x, z): for logs.
  String solidsAt(double x, double z) => [
    for (final MapEntry(key: kind, value: boxes) in [...solids.entries, ...fixed.entries])
      for (final (c, h) in boxes)
        if ((x - c.x).abs() < h.x + 1 && (z - c.z).abs() < h.z + 1) '$kind (${c.x.toStringAsFixed(2)},${c.y.toStringAsFixed(2)},${c.z.toStringAsFixed(2)} ±${h.x.toStringAsFixed(2)},${h.y.toStringAsFixed(2)},${h.z.toStringAsFixed(2)})',
  ].join('; ');

  /// People who jumped somewhere between two frames (capture runs).
  final _jumps = <String>[], _aloft = <String>[];
  var _events = 0, _aloftEvents = 0, _aloftFrames = 0;

  /// People found inside [solids], by kind: frames, the worst (depth,
  /// when, who).
  final _inside = <String, (int, double, double, String)>{};

  static const _counting = String.fromEnvironment('BOOTH3D_TIMES') != '';

  /// How far ahead (seconds) a walker looks for someone they'd walk into.
  static const _ahead = 0.9;

  /// (BOOTH3D_NUDGE=0: nobody steers round anybody, to compare.)
  static const _nudgeOn = String.fromEnvironment('BOOTH3D_NUDGE', defaultValue: '1') != '0';

  /// Each person's nudge for this frame, from where everyone was drawn in
  /// the last: a walker eases sideways round whoever's in their way (to
  /// the side they're already on; two coming at each other keep left),
  /// then whoever's still touching is eased apart (a few rounds of it, so a
  /// close crowd sorts itself out: between two who steer, half each;
  /// someone standing gives way less to someone walking). People who don't
  /// steer ([FigurePose.steer] false) are only walked round. Nobody goes
  /// more than 0.6 m out of their way, and it comes and goes over a moment.
  void _nudge(double now) {
    final dt = (now - _frameAt).isFinite ? (now - _frameAt).clamp(0.0, 0.1) : 0.0;
    final k = 1 - math.exp(-dt / 0.06);
    final seen = _seen;
    // Where each wants to be pushed to (from where they are, raw). A walker
    // looks where whoever's about will be, the way both are going, up to
    // [_ahead] seconds on: if they'd come too close, a step aside now, off
    // their own line to the side away from the other (two meeting head-on
    // keep left, as the city's crowd does), the sooner the more.
    for (final i in seen) {
      final a = _bodies[i];
      a
        ..tx = 0
        ..tz = 0;
      if (!a.steer || !a.walking) continue;
      final fx = -math.sin(a.yaw), fz = -math.cos(a.yaw);
      for (final j in seen) {
        if (j == i) continue;
        final b = _bodies[j];
        final rx = b.x - a.x, rz = b.z - a.z;
        if (rx.abs() > 3.5 || rz.abs() > 3.5 || (b.y - a.y).abs() > 0.5) continue;
        final minD = a.r + b.r + 0.08;
        final vx = b.vx - a.vx, vz = b.vz - a.vz, v2 = vx * vx + vz * vz;
        final tc = v2 > 1e-4 ? (-(rx * vx + rz * vz) / v2).clamp(0.0, _ahead) : 0.0;
        // Where the other is (relative to them) when they're closest: away
        // from there (a step aside, or back: a moment's wait), by as much as
        // they'd overlap; dead on (meeting head-on: to their left).
        final cx = rx + vx * tc, cz = rz + vz * tc, d = math.sqrt(cx * cx + cz * cz);
        if (d >= minD) continue;
        final w = 1 - 0.7 * tc / _ahead;
        final share = b.steer && b.walking ? 0.5 : (b.steer ? 0.75 : 1.0);
        double ux, uz;
        if (d > 0.05) {
          ux = -cx / d;
          uz = -cz / d;
        } else {
          final meeting = b.walking && fx * -math.sin(b.yaw) + fz * -math.cos(b.yaw) < -0.3;
          final vb2 = b.vx * b.vx + b.vz * b.vz;
          if (!meeting && vb2 > 0.04 && v2 > 1e-4) {
            // Crossing their way: behind them (across the way the two
            // close, on the side they're coming from).
            final rv = math.sqrt(v2);
            ux = -vz / rv;
            uz = vx / rv;
            if (ux * b.vx + uz * b.vz > 0) {
              ux = -ux;
              uz = -uz;
            }
          } else {
            final side = meeting || i < j ? 1.0 : -1.0;
            ux = -fz * side;
            uz = fx * side;
          }
        }
        final need = (minD - d) * share * w;
        a
          ..tx += ux * need
          ..tz += uz * need;
      }
    }
    // Still touching: apart, a few rounds.
    for (var round = 0; round < 3; round++) {
      for (var p = 0; p < seen.length; p++) {
        final a = _bodies[seen[p]];
        for (var q = p + 1; q < seen.length; q++) {
          final b = _bodies[seen[q]];
          if (!a.steer && !b.steer) continue;
          var dx = b.x + b.tx - a.x - a.tx, dz = b.z + b.tz - a.z - a.tz;
          if (dx.abs() > 0.8 || dz.abs() > 0.8 || (b.y - a.y).abs() > 0.5) continue;
          final minD = a.r + b.r + 0.04, d = math.sqrt(dx * dx + dz * dz);
          if (d >= minD) continue;
          if (d > 1e-4) {
            dx /= d;
            dz /= d;
          } else {
            dx = 1;
            dz = 0;
          }
          // How much each gives: none if they don't steer; someone standing
          // a little to someone walking.
          // (And none sitting down.)
          double give(_Body x, _Body y) => !x.steer || x.seated ? 0.0 : (!x.walking && y.walking ? 0.25 : 1.0);
          final ga = give(a, b), gb = give(b, a), sum = ga + gb;
          if (sum <= 0) continue;
          final o = minD - d;
          a
            ..tx -= dx * o * ga / sum
            ..tz -= dz * o * ga / sum;
          b
            ..tx += dx * o * gb / sum
            ..tz += dz * o * gb / sum;
        }
      }
    }
    for (final i in seen) {
      final a = _bodies[i];
      if (!a.steer) continue;
      var tx = a.tx, tz = a.tz;
      final m = math.sqrt(tx * tx + tz * tz);
      if (m > 0.6) {
        tx *= 0.6 / m;
        tz *= 0.6 / m;
      }
      a
        ..nx += (tx - a.nx) * k
        ..nz += (tz - a.nz) * k;
      // Never into anything solid (at once: walking into it, along it).
      if (a.seated) continue;
      outOfSolids(a.x + a.nx, a.y, a.z + a.nz, a.r, _out, fromX: a.x, fromZ: a.z);
      a
        ..nx = _out[0] - a.x
        ..nz = _out[1] - a.z;
    }
    if (_counting && seen.isNotEmpty) _count(now);
    // Whoever wasn't drawn starts afresh.
    for (final b in _bodies) {
      if (b.seen != _frameAt) b.nx = b.nz = 0;
    }
    seen.clear();
    _frameAt = now;
  }

  /// How far (metres) a point [pt] is inside [b]'s torso (≤ 0: outside):
  /// in its chest's frame, an elliptic tube a little inside the mesh (the
  /// hand's own thickness: touching isn't in).
  final _local = vm.Vector3.zero();
  double _inTorso(_Body b, vm.Vector3 pt) {
    _local.setFrom(pt);
    b.chestInv.transform3(_local);
    final size = b.look.size, g = b.look.girth * size;
    final y = _local.y / size;
    if (y < -0.06 || y > 0.5) return 0;
    final hw = 0.15 * g, hd = 0.095 * g;
    final e = math.sqrt((_local.x / hw) * (_local.x / hw) + (_local.z / hd) * (_local.z / hd));
    return e < 1 ? (1 - e) * hd : 0;
  }

  /// Hands inside bodies (their own, someone else's) and inside solid
  /// things: frames, worst depth, when, who.
  final _hands = <String, (int, double, double, String)>{};
  final _selfLog = <String>[];
  double _selfAt = -1e9;
  void _handIn(String kind, double depth, double now, String who) {
    final was = _hands[kind];
    _hands[kind] = was == null || depth > was.$2 ? ((was?.$1 ?? 0) + 1, depth, now, who) : (was.$1 + 1, was.$2, was.$3, was.$4);
  }

  void _countHands(double now) {
    for (final i in _seen) {
      final a = _bodies[i];
      for (var s = 0; s < 2; s++) {
        final pt = a.palms[s];
        final self = _inTorso(a, pt);
        if (self > 0.02) {
          _handIn('own body', self, now, '#${a.n} hand $s at ${pt.x.toStringAsFixed(1)},${pt.y.toStringAsFixed(2)},${pt.z.toStringAsFixed(1)}, in its chest ${_local.x.toStringAsFixed(2)},${_local.y.toStringAsFixed(2)},${_local.z.toStringAsFixed(2)} (${a.pose})');
          if (_selfLog.length < 12 && (now - _selfAt).abs() > 2) {
            _selfAt = now;
            _selfLog.add('#${a.n} hand $s t=${now.toStringAsFixed(2)} ${(self * 100).round()} cm, chest-local ${_local.x.toStringAsFixed(2)},${_local.y.toStringAsFixed(2)},${_local.z.toStringAsFixed(2)} (${a.pose})');
          }
        }
        for (final j in _seen) {
          if (j == i) continue;
          final b = _bodies[j];
          if ((b.x - a.x).abs() > 1.2 || (b.z - a.z).abs() > 1.2 || (b.y - a.y).abs() > 1.0) continue;
          final d = _inTorso(b, pt);
          if (d > 0.02) _handIn('someone else', d, now, '#${a.n} hand $s in #${b.n} at ${pt.x.toStringAsFixed(1)},${pt.z.toStringAsFixed(1)}');
        }
        // Solid things: deeper than a grip.
        void boxes(String kind, List<(vm.Vector3, vm.Vector3)> list) {
          for (final (c, h) in list) {
            final dx = h.x - (pt.x - c.x).abs(), dy = h.y - (pt.y - c.y).abs(), dz = h.z - (pt.z - c.z).abs();
            final d = math.min(dx, math.min(dy, dz));
            if (d > 0.05) _handIn(kind, d, now, '#${a.n} hand $s at ${pt.x.toStringAsFixed(1)},${pt.y.toStringAsFixed(2)},${pt.z.toStringAsFixed(1)}');
          }
        }
        for (final MapEntry(key: kind, value: list) in solids.entries) {
          boxes(kind, list);
        }
        boxes('furniture', _fixedNear(pt.x, pt.z));
      }
    }
  }

  void _count(double now) {
    _frames++;
    _countHands(now);
    // In something solid: a circle round the feet against each box's
    // footprint, while the box spans the person's height.
    for (final i in _seen) {
      final a = _bodies[i];
      if (a.seated) continue;
      final x = a.x + a.nx, z = a.z + a.nz;
      for (final MapEntry(key: kind, value: boxes) in [...solids.entries, ...fixed.entries]) {
        var worst = 0.0;
        for (final (c, h) in boxes) {
          if (a.y > c.y + h.y - 0.05 || a.y + 1.6 < c.y - h.y) continue;
          final dx = (x - c.x).abs() - h.x, dz = (z - c.z).abs() - h.z;
          final depth = dx <= 0 && dz <= 0 ? a.r - math.max(dx, dz) : a.r - math.sqrt(math.pow(math.max(dx, 0.0), 2) + math.pow(math.max(dz, 0.0), 2));
          worst = math.max(worst, depth);
        }
        if (worst <= 0.04) continue;
        final was = _inside[kind];
        final who = '#${a.n}${a.walking ? ' walking' : ''}${a.steer ? '' : ' (crowd)'} at ${x.toStringAsFixed(1)},${z.toStringAsFixed(1)}';
        _inside[kind] = was == null || worst > was.$2 ? ((was?.$1 ?? 0) + 1, worst, now, who) : (was.$1 + 1, was.$2, was.$3, was.$4);
      }
    }
    for (var p = 0; p < _seen.length; p++) {
      final a = _bodies[_seen[p]];
      for (var q = p + 1; q < _seen.length; q++) {
        final b = _bodies[_seen[q]];
        if (!a.steer && !b.steer) continue;
        final on = _nudgeOn ? 1.0 : 0.0;
        final dx = b.x + (b.nx - a.nx) * on - a.x, dz = b.z + (b.nz - a.nz) * on - a.z;
        if (dx.abs() > 0.8 || dz.abs() > 0.8 || (b.y - a.y).abs() > 0.5) continue;
        final d = math.sqrt(dx * dx + dz * dz), minD = a.r + b.r;
        if (d < minD) {
          _bumps++;
          String who(_Body q) => '#${q.n}${q.walking ? ' walking' : ''}${q.steer ? '' : ' (crowd)'} at ${q.x.toStringAsFixed(1)},${q.z.toStringAsFixed(1)}';
          if (minD - d > _deepest) {
            _deepest = minD - d;
            _deepestAt = now;
            _deepestWho = '${who(a)} + ${who(b)}';
          }
          if (minD - d > 0.12) {
            final near = _worst.indexWhere((w) => (w.$2 - now).abs() < 1.0);
            if (near < 0) {
              _worst.add((minD - d, now, '${who(a)} + ${who(b)}'));
            } else if (_worst[near].$1 < minD - d) {
              _worst[near] = (minD - d, now, '${who(a)} + ${who(b)}');
            }
          }
        }
      }
    }
  }

  /// [u] shown this frame at [frame], scaled (x, y, z).
  static void _set(_Use u, vm.Matrix4 frame, double sx, double sy, double sz) {
    final s = u.m.storage, f = frame.storage;
    for (var k = 0; k < 16; k++) {
      s[k] = f[k];
    }
    for (var k = 0; k < 3; k++) {
      s[k] *= sx;
      s[4 + k] *= sy;
      s[8 + k] *= sz;
    }
    u.on = true;
  }

  /// [rings] smoothed for [near] (see [_soft]), as they are for far.
  static List<List<double>> _soften(bool near, List<List<double>> rings) => near ? _soft(rings) : rings;

  /// [rings] (y, half width, half depth, z offset) smoothed: [k] for each one
  /// between (a curve through them that doesn't overshoot), and a point at
  /// either end rounded into a dome.
  static List<List<double>> _soft(List<List<double>> rings, {int k = 3, int dome = 3}) {
    bool point(List<double> r) => r[1] == 0 && r[2] == 0;
    final startCap = point(rings.first), endCap = point(rings.last);
    final body = rings.sublist(startCap ? 1 : 0, endCap ? rings.length - 1 : rings.length);
    final out = <List<double>>[];
    for (var i = 0; i + 1 < body.length; i++) {
      final p0 = body[math.max(0, i - 1)], p1 = body[i], p2 = body[i + 1], p3 = body[math.min(body.length - 1, i + 2)];
      for (var j = 0; j < k; j++) {
        final t = j / k;
        out.add([
          for (var c = 0; c < 4; c++)
            () {
              final v = 0.5 * (2 * p1[c] + (-p0[c] + p2[c]) * t + (2 * p0[c] - 5 * p1[c] + 4 * p2[c] - p3[c]) * t * t + (-p0[c] + 3 * p1[c] - 3 * p2[c] + p3[c]) * t * t * t);
              final lo = math.min(p1[c], p2[c]), hi = math.max(p1[c], p2[c]), pad = (hi - lo) * 0.15;
              return c == 0 ? v : v.clamp(lo - pad, hi + pad).toDouble();
            }(),
        ]);
      }
    }
    out.add(body.last);
    List<List<double>> cap(List<double> edge, List<double> tip) => [
      for (var j = 1; j < dome; j++)
        () {
          final a = j / dome * math.pi / 2;
          final c = math.cos(a), sn = math.sin(a);
          return [edge[0] + (tip[0] - edge[0]) * sn, edge[1] * c, edge[2] * c, edge[3] + (tip[3] - edge[3]) * sn];
        }(),
      tip,
    ];
    if (startCap) out.insertAll(0, cap(out.first, rings.first).reversed);
    if (endCap) out.addAll(cap(out.last, rings.last));
    return out;
  }

  /// [c] as skin under the city's light: a little deeper and warmer (light
  /// skin otherwise washes out to white in the sun).
  static vm.Vector4 _toned(vm.Vector4 c) =>
      vm.Vector4(math.pow(c.x, 1.15) * 0.96, math.pow(c.y, 1.15) * 0.93, math.pow(c.z, 1.15) * 0.9, c.w);

  /// The soles under shoes of colour [c]: dark under dark leather and dark
  /// shoes, white under trainers (light or coloured ones).
  static vm.Vector4 _soleFor(vm.Vector4 c) {
    final lum = 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z;
    return lum < 0.08 ? vm.Vector4(c.x * 0.55 + 0.008, c.y * 0.55 + 0.008, c.z * 0.55 + 0.008, 1) : vm.Vector4(0.82, 0.81, 0.78, 1);
  }

  // ── The parts' shapes (size 1; each in its own frame: y up, z back) ─────

  static final _w = vm.Vector4(1, 1, 1, 1);

  /// The torso, from the shirt's hem to the neck, its origin at the hip
  /// joints' height: waist, chest, square shoulders (over the arms' tops)
  /// sloping up to the neck. The hem hangs a little loose, wide of the
  /// trousers' seat ([_hipsGeometry]) and the tops of the legs, so it ends
  /// in one clean line: the legs never poke through it. [near]: smooth, for
  /// close; else simpler.
  static MeshGeometry _torsoGeometry({required bool slim, required bool near}) {
    final rings = slim ? _torsoSlimRings : _torsoRings;
    return (_Mesh()..loft(near ? _soft(rings) : rings, seg: near ? 28 : 12, e: near ? 2.4 : 2.6, color: _w)).build();
  }

  // (y, half width, half depth, z offset)
  static const _torsoRings = [
    [-0.036, 0.0, 0.0, 0.006],
    [-0.032, 0.205, 0.13, 0.006],
    [0.0, 0.177, 0.116, 0.0],
    [0.09, 0.158, 0.104, -0.006],
    [0.2, 0.163, 0.108, -0.01],
    [0.32, 0.178, 0.116, -0.012],
    [0.42, 0.19, 0.112, -0.006],
    [0.47, 0.194, 0.104, -0.002],
    [0.505, 0.193, 0.096, 0.002],
    [0.53, 0.183, 0.086, 0.004],
    [0.548, 0.155, 0.074, 0.005],
    [0.559, 0.105, 0.064, 0.005],
    [0.566, 0.066, 0.058, 0.005],
    [0.572, 0.0, 0.0, 0.005],
  ];
  static const _torsoSlimRings = [
    [-0.036, 0.0, 0.0, 0.008],
    [-0.032, 0.208, 0.128, 0.008],
    [0.0, 0.178, 0.112, 0.0],
    [0.09, 0.138, 0.094, -0.004],
    [0.2, 0.142, 0.096, -0.008],
    [0.3, 0.156, 0.112, -0.022],
    [0.38, 0.163, 0.108, -0.014],
    [0.44, 0.174, 0.097, -0.006],
    [0.49, 0.18, 0.089, 0.0],
    [0.52, 0.176, 0.08, 0.003],
    [0.538, 0.148, 0.07, 0.004],
    [0.549, 0.1, 0.06, 0.004],
    [0.556, 0.06, 0.054, 0.004],
    [0.562, 0.0, 0.0, 0.004],
  ];

  /// The seat of the trousers, from the crotch up under the shirt's hem
  /// (its origin at the hip joints, as the torso's; it moves with the
  /// pelvis, the shirt with the chest).
  static MeshGeometry _hipsGeometry(bool near) {
    final m = _Mesh();
    m.loft(
      _soften(near, const [
        [-0.13, 0.0, 0.0, 0.012],
        [-0.117, 0.12, 0.087, 0.012],
        [-0.07, 0.172, 0.112, 0.007],
        [-0.036, 0.172, 0.112, 0.003],
        // (Above the hem, well inside the shirt: the chest twists against
        // the pelvis as they walk, and the seat must never show through.)
        [-0.008, 0.148, 0.096, 0.0],
        [0.008, 0.0, 0.0, 0.0],
      ]),
      seg: near ? 28 : 12,
      e: near ? 2.4 : 2.6,
      color: _w,
    );
    return m.build();
  }

  /// Shoulder to elbow (a rounded top over the joint).
  static MeshGeometry _upperArmGeometry(bool near) =>
      (_Mesh()..loft(
            _soften(near, const [
              [0.032, 0.0, 0.0, 0.0],
              [0.02, 0.036, 0.04, 0.0],
              [-0.015, 0.053, 0.053, 0.0],
              [-0.08, 0.053, 0.05, 0.0],
              [-0.16, 0.05, 0.047, 0.0],
              [-0.25, 0.044, 0.043, 0.0],
              [-0.3, 0.041, 0.041, 0.0],
              [-0.325, 0.0, 0.0, 0.0],
            ]),
            seg: near ? 16 : 8,
            color: _w,
          ))
          .build();

  /// Elbow to wrist (the sleeve's cuff at the wrist).
  static MeshGeometry _forearmGeometry(bool near) =>
      (_Mesh()..loft(
            _soften(near, const [
              [0.03, 0.0, 0.0, 0.0],
              [0.012, 0.04, 0.04, 0.0],
              [-0.05, 0.044, 0.041, 0.0],
              [-0.15, 0.036, 0.032, 0.0],
              [-0.215, 0.032, 0.028, 0.0],
              [-0.232, 0.0335, 0.0295, 0.0],
              [-0.244, 0.031, 0.027, 0.0],
              [-0.252, 0.0, 0.0, 0.0],
            ]),
            seg: near ? 16 : 8,
            color: _w,
          ))
          .build();

  /// Hip to knee (its top inside the hips).
  static MeshGeometry _thighGeometry(bool near) =>
      (_Mesh()..loft(
            _soften(near, const [
              // (Its top, round the hip joint, slim: always under the shirt
              // and the trousers' seat, it mustn't show through the shirt
              // as the chest twists against the pelvis in a stride.)
              [0.04, 0.0, 0.0, 0.0],
              [0.025, 0.045, 0.048, 0.0],
              [0.0, 0.062, 0.066, 0.0],
              [-0.1, 0.075, 0.08, 0.0],
              [-0.24, 0.066, 0.068, 0.004],
              [-0.37, 0.055, 0.056, 0.0],
              [-0.43, 0.052, 0.054, -0.004],
              [-0.455, 0.0, 0.0, -0.004],
            ]),
            seg: near ? 16 : 8,
            color: _w,
          ))
          .build();

  /// Knee to ankle: the calf, the trousers' hem over the shoe.
  static MeshGeometry _shinGeometry(bool near) =>
      (_Mesh()..loft(
            _soften(near, const [
              [0.035, 0.0, 0.0, 0.0],
              [0.012, 0.05, 0.051, 0.0],
              [-0.09, 0.05, 0.054, 0.008],
              [-0.22, 0.042, 0.043, 0.004],
              [-0.35, 0.037, 0.037, 0.0],
              [-0.378, 0.0395, 0.0405, 0.0],
              [-0.398, 0.0395, 0.0405, 0.0],
              [-0.41, 0.0, 0.0, 0.0],
            ]),
            seg: near ? 16 : 8,
            color: _w,
          ))
          .build();

  /// A hard hat: the dome, a ridge along the top, the brim (a peak at the
  /// front).
  static MeshGeometry _hardHatGeometry() {
    final m = _Mesh();
    m.loft(
      const [
        [0.168, 0.106, 0.124, 0.006],
        [0.205, 0.103, 0.121, 0.006],
        [0.24, 0.092, 0.108, 0.008],
        [0.268, 0.07, 0.083, 0.01],
        [0.286, 0.04, 0.048, 0.011],
        [0.292, 0.0, 0.0, 0.011],
      ],
      seg: 12,
      color: _w,
      capStart: false,
    );
    m.box(0, 0.282, 0.008, 0.012, 0.012, 0.095, _w);
    m.brim(0.168, 0.102, 0.12, 0.026, 0.006, peak: 0.05, seg: 12, color: _w);
    return m.build();
  }

  /// A cap: a soft crown and a visor.
  static MeshGeometry _capGeometry() {
    final m = _Mesh();
    m.loft(
      const [
        [0.165, 0.088, 0.106, 0.006],
        [0.2, 0.087, 0.104, 0.006],
        [0.235, 0.075, 0.09, 0.008],
        [0.258, 0.048, 0.058, 0.01],
        [0.266, 0.0, 0.0, 0.01],
      ],
      seg: 14,
      color: _w,
      capStart: false,
    );
    m.visor(0.168, -0.095, 0.075, 0.075, _w);
    return m.build();
  }

  /// An open layer over the torso (a hi-vis vest; an open jacket's front):
  /// from the waist over the shoulders, open down the front in a V.
  static MeshGeometry _vestGeometry() {
    final m = _Mesh();
    m.arc(_vestSoft, _vestGap, seg: 28, e: 2.4, color: _w);
    return m.build();
  }

  static const _vestRings = [
    [-0.07, 0.215, 0.138, 0.006],
    [0.07, 0.198, 0.128, -0.006],
    [0.2, 0.174, 0.12, -0.012],
    [0.32, 0.19, 0.128, -0.014],
    [0.42, 0.2, 0.124, -0.006],
    [0.47, 0.203, 0.114, -0.002],
    [0.505, 0.201, 0.106, 0.002],
    [0.535, 0.19, 0.095, 0.004],
    [0.553, 0.16, 0.082, 0.005],
  ];

  /// The vest's V: open at the front, wider towards the top.
  /// The vest's V at height [y]: how far each side of it is from the front
  /// (radians round the ring): nearly closed at the bottom, a hand's width
  /// at the top.
  static double _vestGap(double y) => lerp(0.05, 0.3, smooth(0.06, 0.48, y));

  /// The vest's rings, eased (as it's built).
  static final _vestSoft = _soft(_vestRings, k: 2);

  /// An open jacket's lapels, folded back along its V (wider towards the
  /// top), and its collar, standing round the back of the neck (both
  /// sides of it).
  static MeshGeometry _lapelsGeometry() {
    final m = _Mesh();
    const steps = 10;
    for (final side in const [-1.0, 1.0]) {
      final edge = <vm.Vector3>[], fold = <vm.Vector3>[];
      for (var i = 0; i <= steps; i++) {
        final y = lerp(0.26, 0.535, i / steps);
        final (hw, hd, zo) = _vestAt(y);
        // (A point on the vest at angle a, [out] off it.)
        vm.Vector3 at(double a, double out) {
          final c = math.cos(a), s = math.sin(a), k = 1 + out / math.min(hw, hd);
          return vm.Vector3(hw * k * c.sign * math.pow(c.abs(), 2 / 2.4), y, zo + hd * k * s.sign * math.pow(s.abs(), 2 / 2.4));
        }

        final a = -math.pi / 2 + side * _vestGap(y);
        edge.add(at(a, 0.0048));
        fold.add(at(a + side * (0.004 + 0.032 * smooth(0.26, 0.5, y)) / hw, 0.0036));
      }
      for (var i = 0; i < steps; i++) {
        final inside = vm.Vector3(0, edge[i].y, 0);
        m
          ..tri(edge[i], fold[i], fold[i + 1], _w, inside)
          ..tri(edge[i], fold[i + 1], edge[i + 1], _w, inside);
      }
    }
    const collar = [
      [0.546, 0.118, 0.084, 0.006],
      [0.562, 0.088, 0.072, 0.007],
      [0.578, 0.072, 0.066, 0.008],
    ];
    bool back(double a, double y) => math.sin(a) > -0.8;
    m
      ..loft(collar, seg: 24, e: 2.4, color: _w, capStart: false, capEnd: false, keep: back)
      ..loft(collar, seg: 24, e: 2.4, color: _w, capStart: false, capEnd: false, keep: back, inward: true);
    return m.build();
  }

  /// The vest's reflective bands: two round it, and two over each shoulder.
  static MeshGeometry _stripesGeometry() {
    final m = _Mesh();
    for (final y in const [0.16, 0.3]) {
      final rings = [
        for (final dy in const [-0.022, 0.022])
          () {
            final r = _vestAt(y + dy);
            return [y + dy, r.$1 + 0.004, r.$2 + 0.004, r.$3];
          }(),
      ];
      m.arc(rings, _vestGap, seg: 28, e: 2.4, color: _w);
    }
    // Over the shoulders: front and back.
    for (final side in const [-1.0, 1.0]) {
      for (final back in const [-1.0, 1.0]) {
        final y0 = 0.32, y1 = 0.5;
        final r0 = _vestAt(y0), r1 = _vestAt(y1);
        final x = side * (back < 0 ? 0.148 : 0.12);
        final z0 = r0.$3 + back * (r0.$2 * 0.9 + 0.005), z1 = r1.$3 + back * (r1.$2 * 0.88 + 0.005);
        m.strip(vm.Vector3(x, y0, z0), vm.Vector3(x, y1, z1), 0.022, vm.Vector3(0, 0, back), _w);
      }
    }
    return m.build();
  }

  /// The vest's half width, half depth and z offset at height [y].
  static (double, double, double) _vestAt(double y) {
    final rings = _vestSoft;
    for (var i = 0; i + 1 < rings.length; i++) {
      final a = rings[i], b = rings[i + 1];
      if (y <= b[0]) {
        final f = ((y - a[0]) / (b[0] - a[0])).clamp(0.0, 1.0);
        return (lerp(a[1], b[1], f), lerp(a[2], b[2], f), lerp(a[3], b[3], f));
      }
    }
    final l = rings.last;
    return (l[1], l[2], l[3]);
  }

  /// A skirt from the waist to the knee, flared (and a coat's tail).
  static MeshGeometry _skirtGeometry() =>
      (_Mesh()..loft(
            const [
              [-0.45, 0.25, 0.22, 0.01],
              [-0.3, 0.225, 0.19, 0.008],
              [-0.15, 0.222, 0.17, 0.006],
              [0.0, 0.21, 0.14, 0.004],
              [0.1, 0.185, 0.122, 0.0],
            ],
            seg: 16,
            e: 2.2,
            color: _w,
            capStart: false,
            capEnd: false,
          ))
          .build();

  /// A backpack on the back, its straps over the shoulders.
  static MeshGeometry _backpackGeometry() {
    final m = _Mesh()
      ..loft(
        const [
          [0.12, 0.12, 0.055, 0.185],
          [0.16, 0.13, 0.065, 0.19],
          [0.36, 0.13, 0.065, 0.19],
          [0.43, 0.115, 0.055, 0.185],
          [0.45, 0.0, 0.0, 0.18],
        ],
        seg: 10,
        e: 4,
        color: _w,
      );
    for (final side in const [-1.0, 1.0]) {
      final x = side * 0.09;
      final path = [
        vm.Vector3(x, 0.43, 0.116),
        vm.Vector3(x, 0.535, 0.09),
        vm.Vector3(x, 0.569, 0.02),
        vm.Vector3(x * 1.03, 0.562, -0.058),
        vm.Vector3(x * 1.06, 0.5, -0.104),
        vm.Vector3(x * 1.12, 0.17, -0.122),
      ];
      for (var i = 0; i + 1 < path.length; i++) {
        final d = path[i + 1] - path[i];
        // (Facing away from the body: out of the band's way, across it.)
        final out = vm.Vector3(0, -d.z, d.y)..normalize();
        if (out.dot(vm.Vector3(0, path[i].y - 0.45, path[i].z)) < 0) out.negate();
        m.strip(path[i], path[i + 1], 0.03, out, _strap);
      }
    }
    return m.build();
  }

  static final _strap = vm.Vector4(0.45, 0.45, 0.45, 1);

  /// A tote bag hanging from the hand (its origin at the palm).
  static MeshGeometry _bagGeometry() {
    final m = _Mesh()..box(0, -0.26, 0, 0.045, 0.14, 0.15, _w);
    for (final z in const [-0.06, 0.06]) {
      m.strip(vm.Vector3(0, -0.12, z), vm.Vector3(0, 0.0, z * 0.25), 0.014, vm.Vector3(1, 0, 0), _strap);
    }
    return m.build();
  }

  /// A clipboard: the board, its sheet and its clip.
  static MeshGeometry _boardGeometry() {
    final m = _Mesh()
      ..box(0, 0, 0, 0.11, 0.006, 0.15, _masonite)
      ..box(0, 0.0065, 0.008, 0.098, 0.001, 0.13, _w)
      ..box(0, 0.011, -0.13, 0.04, 0.006, 0.014, _clip);
    return m.build();
  }

  static final _masonite = rgbHex(0x8A6A44), _clip = rgbHex(0xB8C2CE);

  /// A parasol held up from the hand: its stick and canopy.
  static MeshGeometry _parasolGeometry() {
    final m = _Mesh()..limb(vm.Vector3(0, -0.04, 0), vm.Vector3(0, 0.86, 0), 0.008, 0.008, _strap, seg: 5);
    m.loft(
      const [
        [0.62, 0.48, 0.48, 0.0],
        [0.74, 0.32, 0.32, 0.0],
        [0.84, 0.08, 0.08, 0.0],
        [0.86, 0.0, 0.0, 0.0],
      ],
      seg: 10,
      color: _w,
      capStart: false,
    );
    m.loft(
      const [
        [0.84, 0.08, 0.08, 0.0],
        [0.74, 0.32, 0.32, 0.0],
        [0.62, 0.48, 0.48, 0.0],
      ],
      seg: 10,
      color: _w,
      capStart: false,
      capEnd: false,
      inward: true,
    );
    return m.build();
  }
}

// ── Building the shapes ─────────────────────────────────────────────────────

/// Collects triangles (positions, vertex colours) for one part; normals are
/// worked out when it's built (smooth across shared vertices).
class _Mesh {
  final _p = <double>[], _c = <double>[];
  final _i = <int>[];

  int get _n => _p.length ~/ 3;

  int _v(double x, double y, double z, vm.Vector4 c) {
    _p
      ..add(x)
      ..add(y)
      ..add(z);
    _c
      ..add(c.x)
      ..add(c.y)
      ..add(c.z)
      ..add(c.w);
    return _n - 1;
  }

  /// Triangle (a, b, c), wound to face away from the point (ix, iy, iz).
  void _tri(int a, int b, int c, double ix, double iy, double iz) {
    final ax = _p[a * 3], ay = _p[a * 3 + 1], az = _p[a * 3 + 2];
    final ux = _p[b * 3] - ax, uy = _p[b * 3 + 1] - ay, uz = _p[b * 3 + 2] - az;
    final wx = _p[c * 3] - ax, wy = _p[c * 3 + 1] - ay, wz = _p[c * 3 + 2] - az;
    final nx = uy * wz - uz * wy, ny = uz * wx - ux * wz, nz = ux * wy - uy * wx;
    final ox = (_p[a * 3] + _p[b * 3] + _p[c * 3]) / 3 - ix;
    final oy = (_p[a * 3 + 1] + _p[b * 3 + 1] + _p[c * 3 + 1]) / 3 - iy;
    final oz = (_p[a * 3 + 2] + _p[b * 3 + 2] + _p[c * 3 + 2]) / 3 - iz;
    if (nx * ox + ny * oy + nz * oz >= 0) {
      _i
        ..add(a)
        ..add(b)
        ..add(c);
    } else {
      _i
        ..add(a)
        ..add(c)
        ..add(b);
    }
  }

  /// A flat-shaded triangle facing away from [inside].
  void tri(vm.Vector3 a, vm.Vector3 b, vm.Vector3 c, vm.Vector4 col, vm.Vector3 inside) {
    _tri(_v(a.x, a.y, a.z, col), _v(b.x, b.y, b.z, col), _v(c.x, c.y, c.z, col), inside.x, inside.y, inside.z);
  }

  /// A tube along y through [rings] (y, half width, half depth, z offset),
  /// [seg] round, a superellipse of exponent [e]; a ring of half width 0
  /// closes it to a point. [keep] drops the quads it says no to (by angle,
  /// 0 at +x, π/2 at +z (back); and height). [inward] faces it inwards.
  void loft(
    List<List<double>> rings, {
    int seg = 10,
    double e = 2,
    required vm.Vector4 color,
    bool capStart = true,
    bool capEnd = true,
    bool Function(double a, double y)? keep,
    bool inward = false,
  }) {
    final base = <int>[];
    for (final r in rings) {
      base.add(_n);
      if (r[1] == 0 && r[2] == 0) {
        _v(0, r[0], r[3], color);
        continue;
      }
      for (var j = 0; j < seg; j++) {
        final a = j / seg * 2 * math.pi;
        final c = math.cos(a), s = math.sin(a);
        final x = r[1] * c.sign * math.pow(c.abs(), 2 / e), z = r[2] * s.sign * math.pow(s.abs(), 2 / e);
        _v(x, r[0], r[3] + z, color);
      }
    }
    int at(int ring, int j) => rings[ring][1] == 0 && rings[ring][2] == 0 ? base[ring] : base[ring] + (j % seg);
    for (var k = 0; k + 1 < rings.length; k++) {
      final r0 = rings[k], r1 = rings[k + 1];
      final iy = (r0[0] + r1[0]) / 2, iz = (r0[3] + r1[3]) / 2;
      final point0 = r0[1] == 0 && r0[2] == 0, point1 = r1[1] == 0 && r1[2] == 0;
      if ((point0 && !capStart && k == 0) || (point1 && !capEnd && k + 2 == rings.length)) continue;
      for (var j = 0; j < seg; j++) {
        final a = (j + 0.5) / seg * 2 * math.pi;
        if (keep != null && !keep(a, iy)) continue;
        // Inside: the axis (or, facing in, a point far out).
        final ix = inward ? 50 * math.cos(a) : 0.0, izz = inward ? iz + 50 * math.sin(a) : iz;
        final iyy = inward ? iy : (point0 ? r1[0] : (point1 ? r0[0] : iy));
        final p00 = at(k, j), p01 = at(k, j + 1), p10 = at(k + 1, j), p11 = at(k + 1, j + 1);
        if (point0) {
          _tri(p00, p11, p10, ix, iyy, izz);
        } else if (point1) {
          _tri(p00, p01, p11, ix, iyy, izz);
        } else {
          _tri(p00, p01, p11, ix, iyy, izz);
          _tri(p00, p11, p10, ix, iyy, izz);
        }
      }
    }
  }

  /// Like [loft], but open at the front: each ring from [gap] (its y)
  /// radians past the front (−π/2) round the back to as far short of it on
  /// the other side; a vest's or a jacket's V, its edge exact.
  void arc(List<List<double>> rings, double Function(double y) gap, {int seg = 24, double e = 2, required vm.Vector4 color}) {
    final base = <int>[];
    for (final r in rings) {
      base.add(_n);
      final g = gap(r[0]);
      for (var j = 0; j <= seg; j++) {
        final a = -math.pi / 2 + g + j / seg * (2 * math.pi - 2 * g);
        final c = math.cos(a), s = math.sin(a);
        _v(r[1] * c.sign * math.pow(c.abs(), 2 / e), r[0], r[3] + r[2] * s.sign * math.pow(s.abs(), 2 / e), color);
      }
    }
    for (var k = 0; k + 1 < rings.length; k++) {
      final iy = (rings[k][0] + rings[k + 1][0]) / 2, iz = (rings[k][3] + rings[k + 1][3]) / 2;
      for (var j = 0; j < seg; j++) {
        final p00 = base[k] + j, p10 = base[k + 1] + j;
        _tri(p00, p00 + 1, p10 + 1, 0, iy, iz);
        _tri(p00, p10 + 1, p10, 0, iy, iz);
      }
    }
  }

  /// An ellipsoid at (x, y, z).
  void ellipsoid(double x, double y, double z, double rx, double ry, double rz, vm.Vector4 col, {int seg = 8, int rings = 5}) {
    final r = <List<double>>[];
    for (var k = 0; k <= rings; k++) {
      final t = -math.pi / 2 + k / rings * math.pi;
      final w = math.cos(t);
      r.add([y + ry * math.sin(t), k == 0 || k == rings ? 0 : rx * w, k == 0 || k == rings ? 0 : rz * w, z]);
    }
    final first = _n;
    loft(r, seg: seg, color: col);
    for (var v = first; v < _n; v++) {
      _p[v * 3] += x;
    }
  }

  /// A box (flat faces) at (x, y, z), half sizes (hx, hy, hz), turned [rotZ].
  void box(double x, double y, double z, double hx, double hy, double hz, vm.Vector4 col, {double rotZ = 0}) {
    final c = math.cos(rotZ), s = math.sin(rotZ);
    vm.Vector3 p(double a, double b, double d) => vm.Vector3(x + a * hx * c - b * hy * s, y + a * hx * s + b * hy * c, z + d * hz);
    final centre = vm.Vector3(x, y, z);
    final corners = [
      for (final a in const [-1.0, 1.0])
        for (final b in const [-1.0, 1.0])
          for (final d in const [-1.0, 1.0]) p(a, b, d),
    ];
    // Faces as corner indices (a*4 + b*2 + d).
    const faces = [
      [0, 1, 3, 2], [4, 6, 7, 5], // -x, +x
      [0, 4, 5, 1], [2, 3, 7, 6], // -y, +y
      [0, 2, 6, 4], [1, 5, 7, 3], // -z, +z
    ];
    for (final f in faces) {
      final q = [for (final i in f) corners[i]];
      tri(q[0], q[1], q[2], col, centre);
      tri(q[0], q[2], q[3], col, centre);
    }
  }

  /// A flat band from [a] to [b], [w] wide, facing along [out].
  void strip(vm.Vector3 a, vm.Vector3 b, double w, vm.Vector3 out, vm.Vector4 col) {
    final d = (b - a)..normalize();
    final side = d.cross(out)
      ..normalize()
      ..scale(w / 2);
    final lift = out.normalized()..scale(0.003);
    final p0 = a - side + lift, p1 = a + side + lift, p2 = b + side + lift, p3 = b - side + lift;
    final inside = (a + b) * 0.5 - out.normalized() * 0.05;
    tri(p0, p1, p2, col, inside);
    tri(p0, p2, p3, col, inside);
  }

  /// A tapered round rod from [a] (radius [ra]) to [b] (radius [rb]).
  void limb(vm.Vector3 a, vm.Vector3 b, double ra, double rb, vm.Vector4 col, {int seg = 6}) {
    final d = b - a;
    final len = d.length;
    final first = _n;
    loft(
      [
        [0.0, 0.0, 0.0, 0.0],
        [0.0, ra, ra, 0.0],
        [len, rb, rb, 0.0],
        [len + rb * 0.5, 0.0, 0.0, 0.0],
      ],
      seg: seg,
      color: col,
    );
    // Turn +y onto the rod's direction, then move it to [a].
    final y = d / len;
    final ref = y.y.abs() < 0.9 ? vm.Vector3(0, 1, 0) : vm.Vector3(1, 0, 0);
    final x = ref.cross(y)..normalize();
    final z = x.cross(y)..normalize();
    for (var v = first; v < _n; v++) {
      final px = _p[v * 3], py = _p[v * 3 + 1], pz = _p[v * 3 + 2];
      _p[v * 3] = a.x + x.x * px + y.x * py + z.x * pz;
      _p[v * 3 + 1] = a.y + x.y * px + y.y * py + z.y * pz;
      _p[v * 3 + 2] = a.z + x.z * px + y.z * py + z.z * pz;
    }
  }

  /// A flat ring (a brim) at height [y] round the head: inner radius
  /// [rx]×[rz], [w] wide, [t] thick, wider by [peak] at the front.
  void brim(double y, double rx, double rz, double w, double t, {double peak = 0, int seg = 16, required vm.Vector4 color}) {
    final rim = <(double, double, double, double)>[];
    for (var j = 0; j < seg; j++) {
      final a = j / seg * 2 * math.pi;
      final c = math.cos(a), s = math.sin(a);
      final front = math.max(0.0, -s);
      final ww = w + peak * front * front;
      rim.add((rx * c, rz * s, (rx + ww) * c, (rz + ww) * s));
    }
    for (final (yy, up) in [(y + t, true), (y, false)]) {
      final base = _n;
      for (final (ix, iz, ox, oz) in rim) {
        _v(ix, yy, iz, color);
        _v(ox, up ? yy - 0.004 : yy, oz, color);
      }
      for (var j = 0; j < seg; j++) {
        final a0 = base + 2 * j, a1 = base + 2 * ((j + 1) % seg);
        final ref = up ? yy - 1 : yy + 1;
        _tri(a0, a0 + 1, a1 + 1, 0, ref, 0);
        _tri(a0, a1 + 1, a1, 0, ref, 0);
      }
    }
    // The outer edge.
    final top = _n - 4 * seg;
    for (var j = 0; j < seg; j++) {
      final u0 = top + 2 * j + 1, u1 = top + 2 * ((j + 1) % seg) + 1;
      final d0 = u0 + 2 * seg, d1 = u1 + 2 * seg;
      _tri(u0, d0, d1, 0, y, 0);
      _tri(u0, d1, u1, 0, y, 0);
    }
  }

  /// A cap's visor: a flat curved peak at the front, at height [y], from
  /// [z0] out by [len], [hw] half wide.
  void visor(double y, double z0, double len, double hw, vm.Vector4 col) {
    for (final (yy, up) in [(y + 0.007, true), (y, false)]) {
      final base = _n;
      for (var j = 0; j <= 6; j++) {
        final u = j / 6 * 2 - 1;
        final x = hw * u;
        final back = z0 + 0.02 * u * u;
        final out = z0 - len * math.sqrt(math.max(0.0, 1 - u * u * 0.75));
        _v(x, yy, back, col);
        _v(x, yy - 0.012 * (1 - u * u), out, col);
      }
      for (var j = 0; j < 6; j++) {
        final a0 = base + 2 * j, a1 = a0 + 2;
        _tri(a0, a0 + 1, a1 + 1, 0, up ? yy - 1 : yy + 1, z0);
        _tri(a0, a1 + 1, a1, 0, up ? yy - 1 : yy + 1, z0);
      }
    }
  }

  MeshGeometry build() => MeshGeometry.fromMeshData(
    MeshData.build(positions: Float32List.fromList(_p), colors: Float32List.fromList(_c), indices: _i, texCoords: Float32List(_n * 2)),
  );
}
