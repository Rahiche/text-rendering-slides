import 'dart:convert' show json;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'figure_rig.dart';
import 'models.dart';
import 'rig.dart';
import 'rig_mesh.dart';

/// People with real bodies and clothes: modelled in MakeHuman (CC0, via
/// MPFB in Blender: tool/blender/humans.py; assets/people/CREDITS.md), all
/// on one skeleton, posed as the city's own figures are (rig.dart: whatever
/// a scene has them doing, the hands and feet where the figure rig puts
/// them) and moved, where a scene leaves them to it, by motion-capture
/// clips (Quaternius' CC0 libraries, retargeted onto the skeleton by
/// tool/blender/motions.py): a walk's swing, a stand. From the neck up,
/// everyone is the city's own one simple head (people.glb's), hung on the
/// skeleton's 'head' bone: every face the same.
class Rigged {
  Rigged._(this.bodies, this.clips, this._meshes, this._heads, this.atlas, this.material);

  final Map<String, RigBody> bodies;
  final Map<String, RigClip> clips;
  final Map<String, RigMeshes> _meshes;
  final Map<String, Map<String, RigPart>> _heads;
  final RigAtlas atlas;

  /// Everyone's cloth: the atlas (its plain garments grey, tinted in the
  /// vertices), one material for all.
  final PhysicallyBasedMaterial material;

  /// The meshes made lately, by who they're for (body and dress), the
  /// last used last: someone back near the camera doesn't wait for theirs
  /// to be made again. (Skins are each person's own; meshes can be
  /// shared.)
  final _made = <String, SkinnedGeometry>{};
  static const _kept = 64;

  /// The people there are (`assets/people/<name>.glb`).
  static const workers = ['worker_a', 'worker_b', 'worker_c', 'worker_d'];
  static const men = ['office_m1', 'office_m2', 'office_m3', 'casual_m1', 'casual_m2', 'casual_m3', 'casual_m4'];
  static const women = ['office_f1', 'office_f2', 'office_f3', 'casual_f1', 'casual_f2', 'casual_f3', 'casual_f4'];

  /// In lab coats (nobody wears them now: the Glyph Works runs itself).
  static const labs = ['lab_m', 'lab_f'];
  static const people = [...workers, ...men, ...women, ...labs];

  /// The hairstyles of the city's head (people.glb), and its other parts.
  static const hairs = ['hair_short', 'hair_medium', 'hair_bob', 'hair_long'];
  static final _headParts = [
    for (final at in ['', '_mid']) ...['head$at', 'eyes$at', 'brows$at', for (final h in hairs) '$h$at'],
    'head_far',
    for (final h in hairs) '${h}_far',
  ];

  /// The plain garments a person's top colour tints (the rest of the tinted
  /// ones, their legs').
  static const _tops = {'namuhekam_male_polo_shirt', 'elvs_crude_t-shirt_male', 'joepal_crude_t-shirt_female', 'toigo_fisherman_sweater', 'toigo_female_suit', 'toigo_shift_dress'};

  static Future<Rigged> load() async {
    final meta = json.decode(await rootBundle.loadString('assets/people/motions.json')) as Map<String, dynamic>;
    RigClip.hips = (meta['hips'] as num).toDouble();
    final glb = await rootBundle.load('assets/people/motions.glb');
    final clips = RigClip.parse(glb.buffer.asUint8List(glb.offsetInBytes, glb.lengthInBytes), (meta['fps'] as num).toDouble());
    final atlas = RigAtlas(json.decode(await rootBundle.loadString('assets/people/atlas.json')) as Map<String, dynamic>);
    const size = kIsWeb ? '_2k' : '';
    final material = PhysicallyBasedMaterial()
      ..baseColorTexture = await Texture2D.fromAsset('assets/people/atlas$size.jpg')
      ..normalTexture = await Texture2D.fromAsset('assets/people/atlas_normal$size.jpg', content: TextureContent.normal)
      ..normalScale = 0.8
      // (How rough, tile by tile: skin a soft sheen, cloth matte;
      // tool/textures/people_rough.py.)
      ..metallicRoughnessTexture = await Texture2D.fromAsset('assets/people/atlas_rough.png', content: TextureContent.data)
      ..metallicFactor = 0
      ..roughnessFactor = 1
      ..sheenColor = vm.Vector4(0.1, 0.1, 0.11, 1)
      ..sheenRoughness = 0.6;
    final parts = await modelParts('assets/models/people.glb');
    final bodies = <String, RigBody>{}, meshes = <String, RigMeshes>{}, heads = <String, Map<String, RigPart>>{};
    for (final name in people) {
      final bytes = await rootBundle.load('assets/people/$name.glb');
      final data = bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
      final m = meshes[name] = RigMeshes.parse(data);
      final t = await Node.fromGlbBytes(data);
      final b = bodies[name] = RigBody(name, t);
      // (The template keeps its skeleton; each person's mesh is made up.)
      for (final n in t.meshNodes.toList()) {
        n.parent?.remove(n);
      }
      final nb = RigBones.neck * 3, joint = m.joints.indexOf('head');
      final neck = vm.Vector3(b.restMP[nb], b.restMP[nb + 1], b.restMP[nb + 2]);
      heads[name] = {for (final p in _headParts) p: RigPart.head(p, parts[p]!, joint, neck, b.headSize)};
    }
    // The clips fitted on the body they were made on; the hands' easy and
    // gripping fingers from two of them.
    final ref = bodies['worker_a']!;
    for (final c in clips.values) {
      ref.fit(c, centre: !c.name.startsWith('sit'));
    }
    Float64List fingers(String clip, double at) {
      final lr = Float64List(RigBones.count * 4), t = Float64List(3);
      clips[clip]!.sample(at, lr, t, RigClip.hips);
      return lr;
    }

    RigPose.relaxed = fingers('idle', 0);
    RigPose.gripping = fingers('walk_carry', 0);
    return Rigged._(bodies, clips, meshes, heads, atlas, material);
  }

  /// A new [name] in [scene] (its skeleton; no mesh until it's dressed:
  /// [RiggedPerson.dress]), hidden.
  RiggedPerson spawn(Scene scene, String name) {
    final b = bodies[name]!, m = _meshes[name]!;
    final root = b.template.clone()..visible = false;
    final bones = [for (final n in RigBones.names) root.getChildByName(n)!];
    final skin = Skin();
    for (final j in m.joints) {
      skin.joints.add(root.getChildByName(j));
    }
    skin.inverseBindMatrices.addAll(m.inverseBinds);
    // (Its shadow is cast by the city's figure posed as it is: a skinned
    // mesh in every shadow cascade costs far more. See Figures.)
    final mesh = Node(name: '$name mesh')
      ..skin = skin
      ..castsShadows = false;
    root.add(mesh);
    scene.add(root);
    return RiggedPerson._(this, b, root, bones, mesh);
  }
}

/// One of [Rigged]'s people in the scene: dressed as someone, posed each
/// frame as the city's figure rig has them ([show]).
class RiggedPerson {
  RiggedPerson._(this._lib, this.body, this.root, this._bones, this._mesh) : pose = RigPose(body) {
    for (var i = 0; i < RigBones.count; i++) {
      _bones[i].localTransform = _mats[i];
    }
    root.localTransform = _rootMat;
  }

  final Rigged _lib;
  final RigBody body;
  final Node root;
  final List<Node> _bones;
  final Node _mesh;
  final RigPose pose;
  final _mats = List.generate(RigBones.count, (_) => vm.Matrix4.identity());
  final _rootMat = vm.Matrix4.identity();

  String get name => body.name;

  bool get visible => root.visible;
  set visible(bool v) {
    if (root.visible != v) root.visible = v;
  }

  /// The clip it stands with (idle, arms folded, on the phone…).
  String stand = 'idle';

  /// What it was last dressed in.
  String _dressed = '';

  /// Dresses it as someone: [skin] and [hairColor] (linear), a hairstyle
  /// ([Rigged.hairs]; null: none, under a hat); the plain garments' colours
  /// ([top], [legs]), a hi-vis [vest] (null: none) and [gloves]; [stand]
  /// its clip for standing about, [seed] when in it it starts; [near] and
  /// [close], see them. (Its mesh is made again only if what it wears
  /// changed.)
  void dress({
    required vm.Vector4 skin,
    required vm.Vector4 hairColor,
    String? hair,
    vm.Vector4? top,
    vm.Vector4? legs,
    vm.Vector4? vest,
    vm.Vector4? gloves,
    String stand = 'idle',
    int seed = 0,
    bool near = true,
    bool close = false,
  }) {
    this.stand = stand;
    _offset = 13.7 * ((seed * 0.6180339887) % 1.0);
    _t = double.nan;
    String hex(vm.Vector4? c) => c == null ? '-' : '${c.x.toStringAsFixed(3)},${c.y.toStringAsFixed(3)},${c.z.toStringAsFixed(3)}';
    final dressed = [hex(skin), hex(hairColor), hair, hex(top), hex(legs), hex(vest), hex(gloves)].join('|');
    if (dressed == _dressed && near == _near && close == _close) return;
    _dressed = dressed;
    _near = near;
    _close = close;
    _wears = (skin, hairColor, hair, top, legs, vest, gloves);
    _make();
  }

  (vm.Vector4, vm.Vector4, String?, vm.Vector4?, vm.Vector4?, vm.Vector4?, vm.Vector4?)? _wears;

  /// Near the camera: its head and hair as the city's figures have them
  /// near (further off, the simpler ones they wear from afar).
  bool get near => _near;
  set near(bool v) {
    if (v == _near) return;
    _near = v;
    _make();
  }

  bool _near = true;

  /// Close to the camera: its head and hair in full. (Only then: further
  /// off, so many triangles in so few pixels cost more than they show.)
  bool get close => _close;
  set close(bool v) {
    if (v == _close) return;
    _close = v;
    _make();
  }

  bool _close = false;

  /// Its mesh, as dressed, at its detail: one made lately, or a new one.
  void _make() {
    final w = _wears;
    if (w == null) return;
    final (skin, hairColor, hair, top, legs, vest, gloves) = w;
    final lib = _lib;
    final key = '$name|$_dressed|${_close ? 'close' : (_near ? 'near' : 'far')}';
    if (lib._made.remove(key) case final g?) {
      lib._made[key] = g;
      _mesh.mesh = Mesh(g, lib.material);
      return;
    }
    final a = lib.atlas, m = lib._meshes[name]!, white = vm.Vector4(1, 1, 1, 1);
    vm.Vector4 tint(vm.Vector4? c) => c == null ? white : vm.Vector4(c.x / a.grey, c.y / a.grey, c.z / a.grey, 1);
    final shirt = m.parts.keys.firstWhere(Rigged._tops.contains, orElse: () => '');
    final pieces = <RigPiece>[];
    for (final MapEntry(key: k, value: p) in m.parts.entries) {
      if (k == '${name}_body') {
        pieces.add((p, 0, skin));
      } else if (k == 'hivis_vest') {
        // (Cut from the shirt: its cloth, in the vest's colour.)
        if (vest != null) pieces.add((p, a.tiles[shirt] ?? 0, tint(vest)));
      } else if (k == 'hivis_tape') {
        if (vest != null) pieces.add((p, 0, vm.Vector4(0.78, 0.79, 0.8, 1)));
      } else if (k == 'toigo_gloves_short') {
        if (gloves != null) pieces.add((p, a.tiles[k] ?? 0, tint(gloves)));
      } else if (k == 'toigo_female_suit' && Rigged.labs.contains(name)) {
        // A lab coat: plain cotton in its colour (not the suit's cloth).
        pieces.add((p, a.tiles['plain'] ?? 0, top ?? white));
      } else {
        final c = !a.tinted.contains(k) ? null : (Rigged._tops.contains(k) ? top : legs);
        pieces.add((p, a.tiles[k] ?? 0, tint(c)));
      }
    }
    final h = lib._heads[name]!, at = _close ? '' : (_near ? '_mid' : '_far');
    pieces.add((h['head$at']!, 0, skin));
    // (The eyes and brows are too small to see from afar.)
    if (_near || _close) {
      pieces
        ..add((h['eyes$at']!, 0, white))
        ..add((h['brows$at']!, 0, hairColor));
    }
    if (hair != null) pieces.add((h['$hair$at']!, 0, hairColor));
    final g = rigGeometry(pieces, a);
    lib._made[key] = g;
    while (lib._made.length > Rigged._kept) {
      lib._made.remove(lib._made.keys.first);
    }
    _mesh.mesh = Mesh(g, lib.material);
  }

  // How much of each part the clip has (eased), which clip, since when.
  double _t = double.nan, _offset = 0;
  final _w = Float64List(5), _grip = Float64List(2);
  String? _clip;
  double _since = 0;

  /// Poses it as [r] has the figure (just solved for [p], [size] its
  /// size) at the scene's time [now]: the rig's pose, and the clip's where
  /// the pose is a plain walk or stand.
  void show(FigureRig r, FigurePose p, double size, double now) {
    final dt = _t.isNaN ? 1.0 : (now - _t).clamp(0.0, 1.0);
    _t = now;
    final walking = p.stride.isFinite;
    // What the scene leaves to the clip: a plain walk's or stand's spine
    // and arms. (The legs stay the rig's: a walk's feet planted, its
    // stride its own; a stand's feet as near as people's are, the clips'
    // stand wide.)
    final walk = walking ? p.walked : 0.0, stand = !walking && p.stood ? 1.0 : 0.0;
    final clip = walk > 0 ? 'walk' : (stand > 0 ? this.stand : _clip);
    // (A hand at work keeps the back the scene's too: a clip's spine sways
    // with its own arms.)
    final busy = !p.armLeft(0) || !p.armLeft(1);
    final targets = [
      0.0,
      (walk > 0 ? 0.85 * walk : stand) * (busy ? 0.25 : 1),
      for (var s = 0; s < 2; s++) (walk > 0 ? walk : stand) * (p.armLeft(RigBones.figureSide(s)) ? 1 : 0),
    ];
    final ease = 1 - math.exp(-dt / 0.12);
    for (var i = 0; i < 4; i++) {
      _w[i] += (targets[i] - _w[i]) * (dt >= 1 ? 1 : ease);
    }
    for (var s = 0; s < 2; s++) {
      final target = p.reachingWith(RigBones.figureSide(s)) ? 1.0 : 0.0;
      _grip[s] += (target - _grip[s]) * (dt >= 1 ? 1 : ease);
    }
    final ps = pose;
    if (clip != null && clip != _clip) {
      // A new clip: faded in from the last.
      ps
        ..from = _clip == null ? null : _lib.clips[_clip]
        ..fromTime = ps.time
        ..fade = _clip == null ? 1 : 0;
      _clip = clip;
      _since = now;
    }
    final c = _clip == null ? null : _lib.clips[_clip];
    ps
      ..clip = c
      ..legs = _w[0]
      ..spine = _w[1]
      ..fade = math.min(1.0, ps.fade + dt / 0.3);
    ps.arms[0] = _w[2];
    ps.arms[1] = _w[3];
    ps.grip[0] = _grip[0];
    ps.grip[1] = _grip[1];
    if (c != null) {
      ps.fromTime += dt;
      if (_clip == 'walk') {
        // In step with the rig's stride (its side-0 heel strikes at π/2);
        // on from there once it stops.
        ps.time = walking ? c.strike + (p.stride - math.pi / 2) / (2 * math.pi) * c.period : ps.time + dt;
      } else {
        ps.time = now - _since + _offset;
      }
    }
    ps.solve(r, size);
    ps.write(_mats, _rootMat);
    for (final b in _bones) {
      b.markTransformDirty();
    }
    root.markTransformDirty();
  }

  /// Where the city's head is on it (as last shown): the frame a figure's
  /// head is drawn in, scaled to it (hats go on this).
  vm.Matrix4 head(vm.Matrix4 out) {
    final b = body, ps = pose, h = RigBones.head;
    final place = _headPlace ??= () {
      final nb = RigBones.neck * 3;
      return vm.Matrix4.inverted(vm.Matrix4.compose(
        vm.Vector3(b.restMP[h * 3], b.restMP[h * 3 + 1], b.restMP[h * 3 + 2]),
        vm.Quaternion(b.restMR[h * 4], b.restMR[h * 4 + 1], b.restMR[h * 4 + 2], b.restMR[h * 4 + 3]),
        vm.Vector3.all(1),
      ))
        ..multiply(vm.Matrix4.translationValues(b.restMP[nb], b.restMP[nb + 1], b.restMP[nb + 2]))
        ..multiply(vm.Matrix4.diagonal3Values(b.headSize, b.headSize, -b.headSize));
    }();
    _q.setValues(ps.mr[h * 4], ps.mr[h * 4 + 1], ps.mr[h * 4 + 2], ps.mr[h * 4 + 3]);
    _p.setValues(ps.mp[h * 3], ps.mp[h * 3 + 1], ps.mp[h * 3 + 2]);
    return out
      ..setFrom(_rootMat)
      ..multiply(_joint..setFromTranslationRotation(_p, _q))
      ..multiply(place);
  }

  vm.Matrix4? _headPlace;
  final _joint = vm.Matrix4.identity(), _q = vm.Quaternion.identity(), _p = vm.Vector3.zero();

  /// Palm [s]'s middle (the city figure's side [s]), where it was last
  /// shown.
  vm.Vector3 palm(int s, vm.Vector3 out) {
    final k = 1 - s, h = RigBones.hand(k), ps = pose, at = _at;
    Q.rotate(ps.mr, h * 4, body.palm, k * 3, at, 0);
    for (var c = 0; c < 3; c++) {
      at[c] += ps.mp[h * 3 + c];
    }
    ps.toCity(at, 0, out);
    return out;
  }

  final _at = Float64List(3);
}
