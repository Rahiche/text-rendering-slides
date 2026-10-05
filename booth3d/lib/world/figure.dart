import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'figure_rig.dart';
import 'kit.dart';
import 'site_geo.dart' show setTrs;

export 'figure_rig.dart';

/// Name City's people, drawn: everyone — the crew and the people in the
/// streets — is the same low-poly human (a torso that narrows to the waist
/// and widens to the hips, a head with a face and hair, arms with elbows
/// and mitten hands, legs with knees and shoes), posed from a [FigurePose]
/// by [FigureRig] and dressed by a [FigureLook]: work clothes, hi-vis vests,
/// hard hats, lab coats, suits, jackets, coats, skirts, bags.
///
/// One [Figures] per scene draws them all: every part is an instanced mesh
/// (one draw for everybody's heads, one for everybody's forearms…), its
/// colour per instance, its details (eyes, soles, a vest's opening) in the
/// geometry. Nothing is allocated per frame.

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

  /// Its number (its head; its arms and legs are 2n, 2n + 1).
  final int n;

  /// What they last showed (see [FigureMotion]).
  final motion = FigureMotion();
  InstancedMesh? torso, hair;
  int torsoAt = -1, hairAt = -1, hat = -1, cap = -1, vest = -1, stripes = -1, skirt = -1, backpack = -1, bag = -1, board = -1, parasol = -1;
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

/// Everybody's parts in one scene: a draw per part for everybody (about
/// 1,500 triangles a person), colours per instance. [add] a person, then
/// [draw] them every frame (or [hide] them): what's drawn is smoothed over
/// the poses' jumps (each person's [FigureMotion], on its clock).
class Figures {
  Figures._(this.scene) {
    _build();
  }

  static final _of = Expando<Figures>('figures');

  /// The scene's figures (made on first use).
  static Figures of(Scene scene) => _of[scene] ??= Figures._(scene);

  final Scene scene;
  final rig = FigureRig();
  final _bodies = <_Body>[];

  late final InstancedMesh _torso, _torsoSlim, _head, _upperArm, _forearm, _hand, _thigh, _shin, _foot;
  late final InstancedMesh _hardHat, _cap, _vest, _stripes, _skirt, _backpack, _bag, _board, _parasol;
  final _hairs = <InstancedMesh>[];
  late final PhysicallyBasedMaterial _stripeMat;

  /// The reflective stripes catch the floodlights after dark (0 day … 1
  /// night).
  set night(double v) => _stripeMat.emissiveStrength = 0.02 + 0.9 * smooth(0.15, 0.6, v);

  void _build() {
    final cloth = pbr(rgb(1, 1, 1), roughness: 0.82);
    final skin = pbr(rgb(1, 1, 1), roughness: 0.6);
    final hair = pbr(rgb(1, 1, 1), roughness: 0.55);
    final shiny = pbr(rgb(1, 1, 1), roughness: 0.3, metallic: 0.05);
    final shoe = pbr(rgb(1, 1, 1), roughness: 0.5);
    _stripeMat = pbr(rgb(1, 1, 1), roughness: 0.25, metallic: 0.25, emissive: rgb(0.85, 0.88, 0.9), emissiveStrength: 0.02);
    InstancedMesh im(MeshGeometry g, Material m, String name) {
      final mesh = InstancedMesh(geometry: g, material: m);
      scene.add(Node(name: 'people $name')..addComponent(InstancedMeshComponent(mesh)));
      return mesh;
    }

    _torso = im(_torsoGeometry(slim: false), cloth, 'torsos');
    _torsoSlim = im(_torsoGeometry(slim: true), cloth, 'slim torsos');
    _head = im(_headGeometry(), skin, 'heads');
    for (final h in Hair.values.skip(1)) {
      _hairs.add(im(_hairGeometry(h), hair, 'hair ${h.name}'));
    }
    _upperArm = im(_upperArmGeometry(), cloth, 'upper arms');
    _forearm = im(_forearmGeometry(), cloth, 'forearms');
    _hand = im(_handGeometry(), skin, 'hands');
    _thigh = im(_thighGeometry(), cloth, 'thighs');
    _shin = im(_shinGeometry(), cloth, 'shins');
    _foot = im(_footGeometry(), shoe, 'shoes');
    _hardHat = im(_hardHatGeometry(), shiny, 'hard hats');
    _cap = im(_capGeometry(), cloth, 'caps');
    _vest = im(_vestGeometry(), cloth, 'vests');
    _stripes = im(_stripesGeometry(), _stripeMat, 'vest stripes');
    _skirt = im(_skirtGeometry(), cloth, 'skirts');
    _backpack = im(_backpackGeometry(), cloth, 'backpacks');
    _bag = im(_bagGeometry(), cloth, 'bags');
    _board = im(_boardGeometry(), cloth, 'clipboards');
    _parasol = im(_parasolGeometry(), cloth, 'parasols');
  }

  /// Adds a person who looks like [look]; returns their number for [draw].
  int add(FigureLook look) {
    final b = _Body(look, _bodies.length);
    _bodies.add(b);
    int one(InstancedMesh m, vm.Vector4 c) => m.addInstance(hidden, color: c);
    b.torso = look.slim ? _torsoSlim : _torso;
    b.torsoAt = one(b.torso!, look.top);
    one(_head, look.skin);
    if (look.hair != Hair.none) {
      b.hair = _hairs[look.hair.index - 1];
      b.hairAt = one(b.hair!, look.hairColor);
    }
    final sleeves = look.sleeves ?? look.top;
    for (var s = 0; s < 2; s++) {
      one(_upperArm, sleeves);
      one(_forearm, look.bareArms ? look.skin : sleeves);
      one(_hand, look.gloves ?? look.skin);
      one(_thigh, look.legs);
      one(_shin, look.shins ?? look.legs);
      one(_foot, look.shoes);
    }
    if (look.hardHat case final c?) b.hat = one(_hardHat, c);
    if (look.cap case final c?) b.cap = one(_cap, c);
    if (look.layer case final c?) b.vest = one(_vest, c);
    if (look.stripes) b.stripes = one(_stripes, vm.Vector4(1, 1, 1, 1));
    if (look.skirt case final c?) b.skirt = one(_skirt, c);
    if (look.backpack case final c?) b.backpack = one(_backpack, c);
    if (look.bag case final c?) b.bag = one(_bag, c);
    if (look.clipboard) b.board = one(_board, vm.Vector4(1, 1, 1, 1));
    if (look.parasol case final c?) b.parasol = one(_parasol, c);
    return b.n;
  }

  /// The look person [n] was added with.
  FigureLook lookOf(int n) => _bodies[n].look;

  /// How fast person [n] was going in the last frame (x, z, m/s).
  (double, double) velocityOf(int n) => (_bodies[n].vx, _bodies[n].vz);

  /// Hides person [n].
  void hide(int n) {
    final b = _bodies[n];
    if (b.hidden) return;
    b.hidden = true;
    b.torso!.setInstanceTransform(b.torsoAt, hidden);
    _head.setInstanceTransform(n, hidden);
    b.hair?.setInstanceTransform(b.hairAt, hidden);
    for (var k = 2 * n; k < 2 * n + 2; k++) {
      _upperArm.setInstanceTransform(k, hidden);
      _forearm.setInstanceTransform(k, hidden);
      _hand.setInstanceTransform(k, hidden);
      _thigh.setInstanceTransform(k, hidden);
      _shin.setInstanceTransform(k, hidden);
      _foot.setInstanceTransform(k, hidden);
    }
    _hideExtras(b);
  }

  void _hideExtras(_Body b) {
    if (b.hat >= 0) _hardHat.setInstanceTransform(b.hat, hidden);
    if (b.cap >= 0) _cap.setInstanceTransform(b.cap, hidden);
    if (b.vest >= 0) _vest.setInstanceTransform(b.vest, hidden);
    if (b.stripes >= 0) _stripes.setInstanceTransform(b.stripes, hidden);
    if (b.skirt >= 0) _skirt.setInstanceTransform(b.skirt, hidden);
    if (b.backpack >= 0) _backpack.setInstanceTransform(b.backpack, hidden);
    if (b.bag >= 0) _bag.setInstanceTransform(b.bag, hidden);
    if (b.board >= 0) _board.setInstanceTransform(b.board, hidden);
    if (b.parasol >= 0) _parasol.setInstanceTransform(b.parasol, hidden);
  }

  final _m = vm.Matrix4.identity(), _t = vm.Matrix4.identity();

  /// Poses person [n] as [p] and draws them ([p.visible] false hides them).
  void draw(int n, FigurePose p) {
    final b = _bodies[n], look = b.look;
    if (!p.visible) {
      hide(n);
      return;
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
    _put(b.torso!, b.torsoAt, r.chest, g, size, g);
    // Children's heads are big for their size.
    final hs = size < 0.95 ? math.pow(size, 0.55).toDouble() : size;
    _put(_head, n, r.head, hs, hs, hs);
    if (b.hair case final h?) _put(h, b.hairAt, r.head, hs, hs, hs);
    // (A touch sturdier than life: they read better from afar.)
    final arm = math.sqrt(look.girth) * size * 1.05, leg = math.sqrt(look.girth) * size * 1.08;
    for (var s = 0; s < 2; s++) {
      final k = 2 * n + s;
      _put(_upperArm, k, r.upper[s], arm, size, arm);
      _put(_forearm, k, r.lower[s], arm, size, arm);
      _put(_hand, k, r.hand[s], size, size, size);
      _put(_thigh, k, r.thighs[s], leg, size, leg);
      _put(_shin, k, r.shins[s], leg, size, leg);
      _put(_foot, k, r.feet[s], size, size, size);
    }
    if (b.hat >= 0) {
      // On the head; or tossed in the air, spinning.
      _t
        ..setFrom(r.head)
        ..multiply(setTrs(_m, 0, p.hatUp, 0, yaw: p.hatSpin, roll: 0.3 * math.sin(p.hatSpin)));
      _put(_hardHat, b.hat, _t, hs, hs, hs);
    }
    if (b.cap >= 0) _put(_cap, b.cap, r.head, hs, hs, hs);
    if (b.vest >= 0) _put(_vest, b.vest, r.chest, g, size, g);
    if (b.stripes >= 0) _put(_stripes, b.stripes, r.chest, g, size, g);
    if (b.skirt >= 0) _put(_skirt, b.skirt, r.pelvis, g, size * look.skirtLength, g);
    if (b.backpack >= 0) _put(_backpack, b.backpack, r.chest, size, size, size);
    if (b.bag >= 0) {
      // Hanging from the left hand.
      final at = r.palms[0];
      _put(_bag, b.bag, FigureRig.yawAt(_t, at.x, at.y, at.z, p.yaw), size, size, size);
    }
    if (b.board >= 0) {
      if (p.clipboard) {
        // Held up in the left hand, its face tilted to be read.
        _t
          ..setFrom(r.hand[0])
          ..multiply(setTrs(_m, 0, -0.075, -0.12, pitch: -0.35));
        _put(_board, b.board, _t, size, size, size);
      } else {
        _board.setInstanceTransform(b.board, hidden);
      }
    }
    if (b.parasol >= 0) {
      final at = r.palms[1];
      _put(_parasol, b.parasol, FigureRig.yawAt(_t, at.x, at.y, at.z, p.yaw), size, size, size);
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

  void _put(InstancedMesh mesh, int i, vm.Matrix4 frame, double sx, double sy, double sz) {
    final s = _m.storage, f = frame.storage;
    for (var k = 0; k < 16; k++) {
      s[k] = f[k];
    }
    for (var k = 0; k < 3; k++) {
      s[k] *= sx;
      s[4 + k] *= sy;
      s[8 + k] *= sz;
    }
    mesh.setInstanceTransform(i, _m);
  }

  // ── The parts' shapes (size 1; each in its own frame: y up, z back) ─────

  static final _w = vm.Vector4(1, 1, 1, 1);

  /// The torso, from the crotch to the neck, its origin at the hip joints'
  /// height: hips, waist, chest, shoulders (the arms' tops round them off).
  static MeshGeometry _torsoGeometry({required bool slim}) {
    final m = _Mesh();
    // (y, half width, half depth, z offset)
    final rings = slim
        ? const [
            [-0.128, 0.0, 0.0, 0.012],
            [-0.115, 0.115, 0.085, 0.012],
            [-0.07, 0.172, 0.112, 0.008],
            [0.0, 0.17, 0.108, 0.0],
            [0.09, 0.138, 0.094, -0.004],
            [0.2, 0.142, 0.096, -0.008],
            [0.3, 0.156, 0.112, -0.022],
            [0.38, 0.163, 0.108, -0.014],
            [0.45, 0.168, 0.094, -0.004],
            [0.51, 0.122, 0.074, 0.004],
            [0.552, 0.058, 0.054, 0.004],
            [0.562, 0.0, 0.0, 0.004],
          ]
        : const [
            [-0.128, 0.0, 0.0, 0.012],
            [-0.115, 0.118, 0.085, 0.012],
            [-0.07, 0.162, 0.108, 0.006],
            [0.0, 0.168, 0.112, 0.0],
            [0.09, 0.157, 0.104, -0.006],
            [0.2, 0.162, 0.108, -0.01],
            [0.32, 0.178, 0.116, -0.012],
            [0.42, 0.188, 0.112, -0.006],
            [0.48, 0.186, 0.098, 0.0],
            [0.53, 0.13, 0.078, 0.005],
            [0.565, 0.064, 0.058, 0.005],
            [0.575, 0.0, 0.0, 0.005],
          ];
    m.loft(rings, seg: 14, e: 2.6, color: _w);
    return m.build();
  }

  /// The head and neck, origin at the neck's pivot, the face to −z: skull,
  /// jaw and chin, a nose, ears, eyes and a mouth (dark, in the geometry).
  static MeshGeometry _headGeometry() {
    final m = _Mesh();
    // The neck, from inside the collar up under the jaw.
    m.loft(
      const [
        [-0.06, 0.046, 0.048, 0.006],
        [0.03, 0.044, 0.046, 0.0],
        [0.07, 0.042, 0.044, 0.006],
      ],
      seg: 10,
      color: _w,
      capStart: false,
    );
    m.loft(_skull, seg: 12, e: 2.15, color: _w);
    // Nose: a small wedge.
    final nose = [vm.Vector3(0, 0.142, -0.094), vm.Vector3(0, 0.103, -0.121), vm.Vector3(-0.017, 0.097, -0.097), vm.Vector3(0.017, 0.097, -0.097)];
    final c = vm.Vector3(0, 0.11, -0.08);
    m
      ..tri(nose[0], nose[2], nose[1], _w, c)
      ..tri(nose[0], nose[1], nose[3], _w, c)
      ..tri(nose[2], nose[3], nose[1], _w, c);
    // Ears, eyes (dark brown: the skin colour barely shows), the mouth.
    for (final side in const [-1.0, 1.0]) {
      m.ellipsoid(side * 0.078, 0.122, 0.006, 0.012, 0.028, 0.019, _w, seg: 6, rings: 3);
      m.ellipsoid(side * 0.031, 0.132, -0.086, 0.011, 0.0085, 0.008, _eye, seg: 6, rings: 3);
    }
    m.box(0, 0.07, -0.095, 0.016, 0.0035, 0.004, _lips);
    return m.build();
  }

  static final _eye = vm.Vector4(0.035, 0.028, 0.025, 1), _lips = vm.Vector4(0.62, 0.36, 0.34, 1);

  /// The skull, from the chin up (y, half width, half depth, z offset).
  static const _skull = [
    [0.012, 0.0, 0.0, -0.062],
    [0.022, 0.03, 0.026, -0.068],
    [0.04, 0.052, 0.05, -0.044],
    [0.068, 0.066, 0.076, -0.022],
    [0.1, 0.074, 0.09, -0.008],
    [0.13, 0.078, 0.096, -0.002],
    [0.16, 0.08, 0.098, 0.002],
    [0.19, 0.076, 0.093, 0.004],
    [0.22, 0.062, 0.076, 0.006],
    [0.243, 0.038, 0.047, 0.008],
    [0.255, 0.0, 0.0, 0.008],
  ];

  /// The skull's half width, half depth and z offset at height [y].
  static (double, double, double) _skullAt(double y) {
    if (y <= _skull.first[0]) return (_skull.first[1], _skull.first[2], _skull.first[3]);
    for (var i = 0; i + 1 < _skull.length; i++) {
      final a = _skull[i], b = _skull[i + 1];
      if (y <= b[0]) {
        final f = (y - a[0]) / (b[0] - a[0]);
        return (lerp(a[1], b[1], f), lerp(a[2], b[2], f), lerp(a[3], b[3], f));
      }
    }
    return (0, 0, _skull.last[3]);
  }

  /// A hairstyle over the skull (and the brows, in the hair's colour).
  static MeshGeometry _hairGeometry(Hair h) {
    final m = _Mesh();
    // Where the hair stops, by angle round the head (a: 0 at the right,
    // π/2 at the back, −π/2 at the face), and how thick it is there.
    double edge(double a) {
      final face = math.max(0.0, -math.sin(a)); // 1 at the face
      final back = math.max(0.0, math.sin(a));
      return switch (h) {
        Hair.short => lerp(lerp(0.148, 0.192, face * face), 0.07, back),
        Hair.medium => lerp(lerp(0.11, 0.17, face * face), 0.04, back),
        Hair.bob => lerp(0.035, 0.168, smooth(0.6, 0.82, face)),
        _ => lerp(lerp(0.03, -0.2, smooth(0.3, 0.8, back)), 0.172, smooth(0.6, 0.82, face)),
      };
    }

    final puff = switch (h) {
      Hair.short => 0.009,
      Hair.medium => 0.014,
      _ => 0.016,
    };
    m.shell(edge, puff, flare: h == Hair.bob || h == Hair.long ? 0.02 : 0.0, seg: 14, rings: 5);
    // Brows.
    for (final side in const [-1.0, 1.0]) {
      m.box(side * 0.032, 0.153, -0.089, 0.017, 0.004, 0.006, _w, rotZ: side * 0.12);
    }
    return m.build();
  }

  /// Shoulder to elbow (a rounded top over the joint).
  static MeshGeometry _upperArmGeometry() =>
      (_Mesh()..loft(
            const [
              [0.032, 0.0, 0.0, 0.0],
              [0.02, 0.036, 0.04, 0.0],
              [-0.015, 0.053, 0.053, 0.0],
              [-0.08, 0.053, 0.05, 0.0],
              [-0.16, 0.05, 0.047, 0.0],
              [-0.25, 0.044, 0.043, 0.0],
              [-0.3, 0.041, 0.041, 0.0],
              [-0.325, 0.0, 0.0, 0.0],
            ],
            seg: 8,
            color: _w,
          ))
          .build();

  /// Elbow to wrist (the sleeve's cuff at the wrist).
  static MeshGeometry _forearmGeometry() =>
      (_Mesh()..loft(
            const [
              [0.03, 0.0, 0.0, 0.0],
              [0.012, 0.04, 0.04, 0.0],
              [-0.05, 0.044, 0.041, 0.0],
              [-0.15, 0.036, 0.032, 0.0],
              [-0.235, 0.031, 0.027, 0.0],
              [-0.252, 0.0, 0.0, 0.0],
            ],
            seg: 8,
            color: _w,
          ))
          .build();

  /// A mitten from the wrist: flat (the palm faces ±x), the thumb forward.
  static MeshGeometry _handGeometry() {
    final m = _Mesh()
      ..loft(
        const [
          [0.012, 0.0, 0.0, 0.0],
          [0.0, 0.019, 0.024, 0.0],
          [-0.03, 0.021, 0.037, 0.0],
          [-0.075, 0.021, 0.042, 0.0],
          [-0.12, 0.017, 0.04, 0.003],
          [-0.155, 0.011, 0.03, 0.006],
          [-0.168, 0.0, 0.0, 0.006],
        ],
        seg: 6,
        e: 2.4,
        color: _w,
      );
    m.limb(vm.Vector3(0, -0.035, -0.028), vm.Vector3(0, -0.085, -0.062), 0.012, 0.009, _w, seg: 6);
    return m.build();
  }

  /// Hip to knee (its top inside the hips).
  static MeshGeometry _thighGeometry() =>
      (_Mesh()..loft(
            const [
              [0.07, 0.0, 0.0, 0.0],
              [0.045, 0.062, 0.062, 0.0],
              [0.0, 0.08, 0.086, 0.0],
              [-0.1, 0.075, 0.08, 0.0],
              [-0.24, 0.066, 0.068, 0.004],
              [-0.37, 0.055, 0.056, 0.0],
              [-0.43, 0.052, 0.054, -0.004],
              [-0.455, 0.0, 0.0, -0.004],
            ],
            seg: 8,
            color: _w,
          ))
          .build();

  /// Knee to ankle: the calf, the trousers' hem over the shoe.
  static MeshGeometry _shinGeometry() =>
      (_Mesh()..loft(
            const [
              [0.035, 0.0, 0.0, 0.0],
              [0.012, 0.05, 0.051, 0.0],
              [-0.09, 0.05, 0.054, 0.008],
              [-0.22, 0.042, 0.043, 0.004],
              [-0.36, 0.037, 0.037, 0.0],
              [-0.395, 0.039, 0.04, 0.0],
              [-0.41, 0.0, 0.0, 0.0],
            ],
            seg: 8,
            color: _w,
          ))
          .build();

  /// A shoe from the ankle: heel, instep, toe; the sole a shade darker.
  static MeshGeometry _footGeometry() {
    final m = _Mesh();
    // Sections along −z (forward): (z, half width, top y, bottom y).
    const secs = [
      [0.065, 0.0, -0.035, -0.055],
      [0.058, 0.034, -0.005, -0.08],
      [0.02, 0.042, 0.025, -0.08],
      [-0.06, 0.046, -0.012, -0.08],
      [-0.14, 0.046, -0.038, -0.08],
      [-0.185, 0.036, -0.05, -0.08],
      [-0.2, 0.0, -0.062, -0.074],
    ];
    m.sweepZ(secs, seg: 8, e: 3.2, top: _w, sole: _sole);
    return m.build();
  }

  static final _sole = vm.Vector4(0.55, 0.55, 0.55, 1);

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
    m.loft(_vestRings, seg: 14, e: 2.6, color: _w, capStart: false, capEnd: false, keep: _vestKeep);
    return m.build();
  }

  static const _vestRings = [
    [-0.07, 0.18, 0.124, 0.006],
    [0.07, 0.172, 0.118, -0.006],
    [0.2, 0.174, 0.12, -0.012],
    [0.32, 0.19, 0.128, -0.014],
    [0.42, 0.2, 0.124, -0.006],
    [0.485, 0.198, 0.108, 0.0],
    [0.535, 0.142, 0.088, 0.005],
  ];

  /// The vest's V: open at the front, wider towards the top.
  static bool _vestKeep(double a, double y) {
    final face = -math.sin(a); // 1 at the front
    final open = lerp(0.97, 0.72, smooth(0.07, 0.5, y));
    return face < open;
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
      m.loft(rings, seg: 14, e: 2.6, color: _w, capStart: false, capEnd: false, keep: _vestKeep);
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

  static (double, double, double) _vestAt(double y) {
    for (var i = 0; i + 1 < _vestRings.length; i++) {
      final a = _vestRings[i], b = _vestRings[i + 1];
      if (y <= b[0]) {
        final f = ((y - a[0]) / (b[0] - a[0])).clamp(0.0, 1.0);
        return (lerp(a[1], b[1], f), lerp(a[2], b[2], f), lerp(a[3], b[3], f));
      }
    }
    final l = _vestRings.last;
    return (l[1], l[2], l[3]);
  }

  /// A skirt from the waist to the knee, flared (and a coat's tail).
  static MeshGeometry _skirtGeometry() =>
      (_Mesh()..loft(
            const [
              [-0.45, 0.25, 0.22, 0.01],
              [-0.3, 0.225, 0.19, 0.008],
              [-0.15, 0.198, 0.158, 0.006],
              [0.0, 0.178, 0.128, 0.004],
              [0.1, 0.165, 0.112, 0.0],
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
      m.strip(vm.Vector3(side * 0.085, 0.47, 0.05), vm.Vector3(side * 0.095, 0.47, -0.08), 0.03, vm.Vector3(0, 1, 0), _strap);
      m.strip(vm.Vector3(side * 0.095, 0.47, -0.105), vm.Vector3(side * 0.1, 0.17, -0.12), 0.03, vm.Vector3(0, 0, -1), _strap);
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

  /// A sweep along −z through sections (z, half width, top y, bottom y),
  /// boxy (superellipse [e]); the lowest vertices take [sole].
  void sweepZ(List<List<double>> secs, {int seg = 10, double e = 3, required vm.Vector4 top, required vm.Vector4 sole}) {
    final base = <int>[];
    for (final s in secs) {
      base.add(_n);
      final cy = (s[2] + s[3]) / 2, hy = (s[2] - s[3]) / 2;
      if (s[1] == 0) {
        _v(0, cy, s[0], top);
        continue;
      }
      for (var j = 0; j < seg; j++) {
        final a = j / seg * 2 * math.pi;
        final c = math.cos(a), n = math.sin(a);
        final x = s[1] * c.sign * math.pow(c.abs(), 2 / e), y = cy + hy * n.sign * math.pow(n.abs(), 2 / e);
        _v(x, y, s[0], y < s[3] + 0.012 ? sole : top);
      }
    }
    int at(int k, int j) => secs[k][1] == 0 ? base[k] : base[k] + (j % seg);
    for (var k = 0; k + 1 < secs.length; k++) {
      final s0 = secs[k], s1 = secs[k + 1];
      final iz = (s0[0] + s1[0]) / 2, iy = (s0[2] + s0[3] + s1[2] + s1[3]) / 4;
      for (var j = 0; j < seg; j++) {
        final p00 = at(k, j), p01 = at(k, j + 1), p10 = at(k + 1, j), p11 = at(k + 1, j + 1);
        final ref = s0[1] == 0 ? s1[0] : (s1[1] == 0 ? s0[0] : iz);
        if (s0[1] == 0) {
          _tri(p00, p11, p10, 0, iy, ref);
        } else if (s1[1] == 0) {
          _tri(p00, p01, p11, 0, iy, ref);
        } else {
          _tri(p00, p01, p11, 0, iy, ref);
          _tri(p00, p11, p10, 0, iy, ref);
        }
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

  /// Hair over the skull: from where it stops ([edge] by angle) up to the
  /// crown, [puff] out from the skull, flaring by [flare] at the bottom.
  void shell(double Function(double a) edge, double puff, {double flare = 0, int seg = 16, int rings = 6}) {
    final base = _n;
    for (var k = 0; k <= rings; k++) {
      final t = k / rings;
      for (var j = 0; j < seg; j++) {
        final a = j / seg * 2 * math.pi;
        final y0 = edge(a), y = lerp(y0, 0.258, math.pow(t, 0.85).toDouble());
        // (Below the cheekbones it hangs straight down.)
        final (hx, hz, oz) = Figures._skullAt(math.max(0.13, y));
        final k1 = 1 + (puff + flare * (1 - t) * (1 - t)) / math.max(0.03, math.min(hx, hz)) * (1 - 0.3 * t);
        _v(hx * k1 * math.cos(a), y + puff * 0.6 * t, oz + hz * k1 * math.sin(a), FigureLook._white);
      }
    }
    for (var k = 0; k < rings; k++) {
      for (var j = 0; j < seg; j++) {
        final p00 = base + k * seg + j, p01 = base + k * seg + (j + 1) % seg;
        final p10 = p00 + seg, p11 = p01 + seg;
        final iy = _p[p00 * 3 + 1];
        _tri(p00, p01, p11, 0, iy - 0.02, 0.0);
        _tri(p00, p11, p10, 0, iy - 0.02, 0.0);
      }
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
