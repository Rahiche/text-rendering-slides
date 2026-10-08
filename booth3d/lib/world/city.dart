import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_scene/scene.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'city_plan.dart';
import 'city_props.dart';
import 'city_signs.dart';
import 'city_towers.dart';
import '../tuning.dart';
import 'kit.dart';
import 'sky.dart';

/// The city around the plaza: a blueprint ground, the avenue and side
/// streets, the plaza drawn like a drafting sheet, street lamps, the night
/// lighting on the build, and — in their own files — the skyline of glyph
/// towers, rooftop neon in many languages, and the street furniture.
class City3D {
  City3D(this.scene);

  final Scene scene;

  late final towers = CityTowers(scene);
  late final signs = CitySigns(scene);
  late final props = CityProps(scene);

  /// Light channels: the night's local lights (lamps, floods) only light the
  /// plaza and what is near it, never the whole city (each lit pixel loops
  /// over the lights that reach its object).
  static const sunOnly = 0x01, local = 0x02;

  final _glowMats = <(PhysicallyBasedMaterial, double)>[]; // (material, night strength)
  final _lightNodes = <Node>[];
  bool _lightsOn = false;
  late final PhysicallyBasedMaterial _bulbMat;
  final _lampLights = <PointLight>[];
  final _floods = <SpotLight>[];
  late final PhysicallyBasedMaterial _plazaMat, _groundMat;

  // The site gate in the front barriers: two leaves (a barrier, and a
  // barrier with its post) that slide aside for the delivery truck.
  late final InstancedMesh _posts;
  final _gateLeaves = <(InstancedMesh, int, double)>[]; // which, index, x
  double _gateOpen = 0;

  // The bay gate on the left, for the cleanup's truck: the barriers at
  // x = −8 and −6 and the post between them.
  final _bayLeaves = <(InstancedMesh, int, double)>[];
  double _bayOpen = 0;

  Future<void> init() async {
    _ground();
    _streets(await _grass());
    _lamps();
    _plazaLights();
    await towers.init();
    await Future.wait([signs.init(towers.roofs), props.init()]);
  }

  // ── Ground ────────────────────────────────────────────────────────────────

  Node _slab(double x0, double z0, double x1, double z1, double top, Material m, {double thick = 0.3}) {
    final n = Node(
      mesh: Mesh(CuboidGeometry(vm.Vector3(x1 - x0, thick, z1 - z0)), m),
      localTransform: trs(vm.Vector3((x0 + x1) / 2, top - thick / 2, (z0 + z1) / 2)),
    );
    scene.add(n);
    return n;
  }

  /// A slab as mesh data, its texture laid in world space ([tile] metres).
  MeshData _slabData(double x0, double z0, double x1, double z1, double top, {double thick = 0.3, double tile = 2}) {
    final d = CuboidGeometry(vm.Vector3(x1 - x0, thick, z1 - z0)).extractMeshData().transformed(vm.Matrix4.translation(vm.Vector3((x0 + x1) / 2, top - thick / 2, (z0 + z1) / 2)));
    final uv = Float32List(d.vertexCount * 2);
    for (var i = 0; i < d.vertexCount; i++) {
      uv
        ..[i * 2] = d.positions[i * 3] / tile
        ..[i * 2 + 1] = d.positions[i * 3 + 2] / tile;
    }
    return painted(d, vm.Vector4(1, 1, 1, 1), uvs: uv);
  }

  /// A grid texture: [cells]×[cells] cells of [px] px, minor lines of
  /// [minor] px, a major line of [major] px on the tile's edge.
  Texture2D _grid({required int cells, required int px, required int minor, required int major, required int base, required int minorC, required int majorC}) {
    final n = cells * px;
    final out = Uint8List(n * n * 4);
    final b = Color(0xFF000000 | base), mi = Color(0xFF000000 | minorC), ma = Color(0xFF000000 | majorC);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final ex = math.min(x, n - 1 - x), ey = math.min(y, n - 1 - y);
        final onMajor = ex < major / 2 || ey < major / 2;
        final mx = x % px, my = y % px;
        final onMinor = math.min(mx, px - 1 - mx) < minor / 2 || math.min(my, px - 1 - my) < minor / 2;
        final c = onMajor ? ma : (onMinor ? mi : b);
        final i = (y * n + x) * 4;
        out
          ..[i] = (c.r * 255).round()
          ..[i + 1] = (c.g * 255).round()
          ..[i + 2] = (c.b * 255).round()
          ..[i + 3] = 255;
      }
    }
    return Texture2D.fromPixels(out, n, n);
  }

  void _ground() {
    // The world: a navy blueprint with a faint 4 m grid that glows at night.
    final groundBase = _grid(cells: 4, px: 96, minor: 3, major: 6, base: 0x0A1B2E, minorC: 0x10294A, majorC: 0x173A63);
    final groundGlow = _grid(cells: 4, px: 96, minor: 3, major: 6, base: 0x000000, minorC: 0x2A4A70, majorC: 0x5FB8FF);
    const size = 1400.0, tile = 16.0;
    final tt = TextureTransform(scale: vm.Vector2(size / tile, size / tile));
    _groundMat = PhysicallyBasedMaterial()
      ..baseColorTexture = groundBase
      ..baseColorTextureTransform = tt
      ..metallicFactor = 0
      ..roughnessFactor = 0.92
      ..emissiveTexture = groundGlow
      ..emissiveTextureTransform = tt
      ..emissiveFactor = v4(lin3(BP.line))
      ..emissiveStrength = 0;
    _glowMats.add((_groundMat, 0.22));
    _slab(-size / 2, -size / 2, size / 2, size / 2, -0.12, _groundMat).lightChannelMask = sunOnly;

    // The plaza: a drafting sheet, 1 m grid and a 4 m major grid.
    final sheetBase = _grid(cells: 4, px: 64, minor: 2, major: 4, base: 0x0F2C4E, minorC: 0x1A4373, majorC: 0x2F6AA8);
    final sheetGlow = _grid(cells: 4, px: 64, minor: 2, major: 4, base: 0x000000, minorC: 0x1E4F86, majorC: 0x5FB8FF);
    const px = Plan.plazaX, z0 = Plan.plazaZ0, z1 = Plan.plazaZ1;
    final st = TextureTransform(scale: vm.Vector2(2 * px / 4, (z1 - z0) / 4));
    _plazaMat = PhysicallyBasedMaterial()
      ..baseColorTexture = sheetBase
      ..baseColorTextureTransform = st
      ..metallicFactor = 0
      ..roughnessFactor = 0.8
      ..emissiveTexture = sheetGlow
      ..emissiveTextureTransform = st
      ..emissiveFactor = v4(lin3(BP.line))
      ..emissiveStrength = 0;
    _glowMats.add((_plazaMat, 0.55));
    _slab(-px, z0, px, z1, 0, _plazaMat);
    // The sheet's border, a bright ruled line.
    final border = pbr(lin(BP.line), roughness: 0.4, emissive: lin(BP.line), emissiveStrength: 0);
    _glowMats.add((border, 2.2));
    final bars = InstancedMesh(geometry: CuboidGeometry(vm.Vector3.all(1)), material: border);
    for (final (x, z, w, d) in [
      (0.0, z0 + 0.25, 2 * px - 0.5, 0.12),
      (0.0, z1 - 0.25, 2 * px - 0.5, 0.12),
      (-px + 0.25, (z0 + z1) / 2, 0.12, z1 - z0 - 0.5),
      (px - 0.25, (z0 + z1) / 2, 0.12, z1 - z0 - 0.5),
    ]) {
      bars.addInstance(trs(vm.Vector3(x, 0.005, z), s: vm.Vector3(w, 0.02, d)));
    }
    scene.add(Node(name: 'sheet border')..addComponent(InstancedMeshComponent(bars)));
  }

  // ── Streets ───────────────────────────────────────────────────────────────

  /// The park's lawn: a grass photo's detail (Poly Haven's CC0 "Grass
  /// Ground": its luminance only, the lawn's own colour over it) and its
  /// relief, laid in world space a tile every 3 m.
  Future<PhysicallyBasedMaterial> _grass() async {
    final detail = await Texture2D.fromAsset('assets/textures/grass_detail.jpg');
    final relief = await Texture2D.fromAsset('assets/textures/grass_normal.jpg', content: TextureContent.normal);
    // (The detail's mean is 0.58 linear: the lawn keeps its colour on
    // average.)
    final c = lin(const Color(0xFF1F4A45));
    return PhysicallyBasedMaterial()
      ..baseColorTexture = detail
      ..baseColorFactor = vm.Vector4(c.x / 0.58, c.y / 0.58, c.z / 0.58, 1)
      ..normalTexture = relief
      ..normalScale = 0.9
      ..metallicFactor = 0
      ..roughnessFactor = 0.95;
  }

  void _streets(PhysicallyBasedMaterial lawn) {
    final asphalt = pbr(lin(const Color(0xFF111B2C)), roughness: 0.82);
    final paving = PhysicallyBasedMaterial()
      ..baseColorTexture = _grid(cells: 4, px: 32, minor: 2, major: 2, base: 0x2A3E5A, minorC: 0x22344D, majorC: 0x22344D)
      ..metallicFactor = 0
      ..roughnessFactor = 0.85;
    // Near the plaza (lit by the lamps at night) and the rest of the city.
    final near = Batch(), rest = Batch();
    void piece(Material m, double x0, double z0, double x1, double z1, double top) {
      // Cut at the near zone's edges (|x| < 36, z < 24) so each piece is
      // wholly near or far.
      final xs = [x0, for (final c in [-36.0, 36.0]) if (c > x0 && c < x1) c, x1];
      final zs = [z0, if (24 > z0 && 24 < z1) 24.0, z1];
      for (var i = 0; i + 1 < xs.length; i++) {
        for (var j = 0; j + 1 < zs.length; j++) {
          final cx = (xs[i] + xs[i + 1]) / 2, cz = (zs[j] + zs[j + 1]) / 2;
          (cx.abs() < 36 && cz < 24 && cz > Plan.aveZ0 - 4 ? near : rest).add(m, _slabData(xs[i], zs[j], xs[i + 1], zs[j + 1], top));
        }
      }
    }

    const far = 700.0, sx = Plan.streetX, sh = Plan.streetHalf, bx = Plan.blockX;
    // Roads.
    piece(asphalt, -far, Plan.aveZ0, far, Plan.aveZ1, Plan.road);
    for (final s in [-1.0, 1.0]) {
      piece(asphalt, s * sx - sh, Plan.aveZ1, s * sx + sh, far, Plan.road);
      piece(asphalt, s * sx - sh, -far, s * sx + sh, Plan.aveZ0, Plan.road);
    }
    // Sidewalks: the plaza block's ring, the outer blocks' fronts, the far side.
    void sw(double x0, double z0, double x1, double z1) => piece(paving, x0, z0, x1, z1, 0.02);
    sw(-bx, Plan.aveZ1, bx, Plan.plazaZ0); // front
    for (final s in [-1.0, 1.0]) {
      final a = s * Plan.plazaX, b = s * bx;
      sw(math.min(a, b), Plan.plazaZ0, math.max(a, b), Plan.parkZ1); // plaza flanks, into the park
      final c = s * (sx + sh), d = s * (sx + sh + 2.2);
      sw(math.min(c, d), Plan.aveZ1, math.max(c, d), 90); // outer blocks along the side street
      sw(math.min(d, s * 130), Plan.aveZ1, math.max(d, s * 130), Plan.aveZ1 + 2.2); // outer blocks along the avenue
    }
    // The camera side of the avenue (the side streets cut through it).
    sw(-130, Plan.aveZ0 - 2.4, -sx - sh, Plan.aveZ0);
    sw(-sx + sh, Plan.aveZ0 - 2.4, sx - sh, Plan.aveZ0);
    sw(sx + sh, Plan.aveZ0 - 2.4, 130, Plan.aveZ0);
    // The park behind the plaza: a lawn with paths.
    scene.add(Node(name: 'lawn', mesh: Mesh(MeshGeometry.fromMeshData(_slabData(-Plan.plazaX, Plan.parkZ0, Plan.plazaX, Plan.parkZ1, 0.0, tile: 3)), lawn)));
    sw(-2, Plan.parkZ0, 2, Plan.parkZ1);
    sw(-Plan.plazaX, Plan.parkZ0 + 14, Plan.plazaX, Plan.parkZ0 + 17);
    near.build(scene, 'streets');
    rest.build(scene, 'streets far', lightChannelMask: sunOnly);

    // Curbs.
    final curbMat = pbr(lin(const Color(0xFF8FA6C2)), roughness: 0.7);
    final curbs = InstancedMesh(geometry: CuboidGeometry(vm.Vector3.all(1)), material: curbMat);
    void curb(double x0, double z0, double x1, double z1) {
      curbs.addInstance(trs(vm.Vector3((x0 + x1) / 2, 0.0, (z0 + z1) / 2), s: vm.Vector3(math.max(x1 - x0, 0.2), 0.2, math.max(z1 - z0, 0.2))));
    }

    curb(-bx, Plan.aveZ1, bx, Plan.aveZ1);
    curb(-130, Plan.aveZ0, -sx - sh, Plan.aveZ0);
    curb(-sx + sh, Plan.aveZ0, sx - sh, Plan.aveZ0);
    curb(sx + sh, Plan.aveZ0, 130, Plan.aveZ0);
    for (final s in [-1.0, 1.0]) {
      curb(math.min(s * (sx + sh), s * 130), Plan.aveZ1, math.max(s * (sx + sh), s * 130), Plan.aveZ1);
      curb(s * (sx - sh), Plan.aveZ1, s * (sx - sh), 90);
      curb(s * (sx + sh), Plan.aveZ1, s * (sx + sh), 90);
    }
    scene.add(
      Node(name: 'curbs')
        ..lightChannelMask = sunOnly
        ..addComponent(InstancedMeshComponent(curbs)),
    );

    // Markings: dashed centre lines, stop lines, crosswalks (zebras).
    final paint = pbr(rgb(0.82, 0.86, 0.9), roughness: 0.55, emissive: rgb(0.6, 0.75, 0.9), emissiveStrength: 0);
    _glowMats.add((paint, 0.08));
    final marks = InstancedMesh(geometry: CuboidGeometry(vm.Vector3.all(1)), material: paint);
    void mark(double x, double z, double w, double d) => marks.addInstance(trs(vm.Vector3(x, Plan.road + 0.012, z), s: vm.Vector3(w, 0.02, d)));
    bool nearCross(double x) => Plan.crossX.any((c) => (x - c).abs() < Plan.crossHalf + 1.5) || (x.abs() - sx).abs() < sh + 4.5;
    for (var x = -300.0; x < 300; x += 6) {
      if (!nearCross(x)) mark(x, Plan.aveZ, 3, 0.15);
    }
    for (final s in [-1.0, 1.0]) {
      for (var z = Plan.aveZ1 + 6; z < 300; z += 6) {
        mark(s * sx, z, 0.15, 3);
      }
      for (var z = Plan.aveZ0 - 6; z > -300; z -= 6) {
        mark(s * sx, z, 0.15, 3);
      }
    }
    // Zebra crossings over the avenue at the plaza's corners, and over the
    // side streets.
    for (final cx in Plan.crossX) {
      for (var z = Plan.aveZ0 + 0.6; z < Plan.aveZ1 - 0.3; z += 0.9) {
        mark(cx, z, 2 * Plan.crossHalf, 0.45);
      }
      // Stop lines before them.
      mark(cx - Plan.crossHalf - 1.2, (Plan.laneEast + Plan.aveZ1) / 2 - 0.1, 0.35, 3.6);
      mark(cx + Plan.crossHalf + 1.2, (Plan.laneWest + Plan.aveZ0) / 2 + 0.1, 0.35, 3.6);
    }
    for (final s in [-1.0, 1.0]) {
      for (final cz in [Plan.aveZ1 + 2.2, Plan.aveZ0 - 2.2]) {
        for (var x = s * sx - sh + 0.5; x < s * sx + sh - 0.3; x += 0.9) {
          mark(x, cz, 0.45, 2.6);
        }
      }
    }
    scene.add(
      Node(name: 'road marks')
        ..lightChannelMask = sunOnly
        ..addComponent(InstancedMeshComponent(marks)),
    );

    // Safety barriers along the plaza's front: amber and navy, like a site
    // fence.
    final barrier = InstancedMesh(geometry: CuboidGeometry(vm.Vector3(1.8, 0.55, 0.14)), material: pbr(rgb(1, 1, 1), roughness: 0.5));
    final posts = _posts = InstancedMesh(geometry: CuboidGeometry(vm.Vector3(0.1, 0.95, 0.5)), material: pbr(lin(const Color(0xFF2C3B52)), roughness: 0.6));
    for (var x = -Plan.plazaX + 1; x <= Plan.plazaX - 0.9; x += 2.0) {
      final k = (x / 2).round();
      final b = barrier.addInstance(trs(vm.Vector3(x, 0.62, Plan.plazaZ0 - 0.3)), color: k.isEven ? lin(BP.amber) : lin(const Color(0xFF1B2A44)));
      final p = posts.addInstance(trs(vm.Vector3(x - 0.95, 0.475, Plan.plazaZ0 - 0.3)));
      // The gate: the barriers at x = 12 and 14, and the post between them.
      if ((x - 12).abs() < 0.1) _gateLeaves.add((barrier, b, x));
      if ((x - 14).abs() < 0.1) _gateLeaves.addAll([(barrier, b, x), (posts, p, x - 0.95)]);
      if ((x + 8).abs() < 0.1) _bayLeaves.add((barrier, b, x));
      if ((x + 6).abs() < 0.1) _bayLeaves.addAll([(barrier, b, x), (posts, p, x - 0.95)]);
    }
    scene.add(Node(name: 'barriers')..addComponent(InstancedMeshComponent(barrier)));
    scene.add(Node(name: 'barrier posts')..addComponent(InstancedMeshComponent(posts)));
  }

  // ── Lamps ────────────────────────────────────────────────────────────────

  void _lamps() {
    final poleMat = pbr(lin(const Color(0xFF26354D)), metallic: 0.6, roughness: 0.4);
    final pole = InstancedMesh(geometry: CylinderGeometry(bottomRadius: 0.09, topRadius: 0.06, height: 5, radialSegments: 10), material: poleMat);
    final arm = InstancedMesh(geometry: CuboidGeometry(vm.Vector3(0.9, 0.08, 0.08)), material: poleMat);
    _bulbMat = pbr(rgb(1, 0.92, 0.78), roughness: 0.3, emissive: lin(const Color(0xFFFFD9A0)), emissiveStrength: 0);
    final bulb = InstancedMesh(geometry: SphereGeometry(radius: 0.3, segments: 14, rings: 8), material: _bulbMat);
    void lamp(double x, double z, double towards, {bool light = false}) {
      // (None in front of the mini world's buildings.)
      if (Plan.inLot(x, z, 1.5)) return;
      // The arm reaches over the road side (towards +x when towards > 0).
      pole.addInstance(trs(vm.Vector3(x, 2.5, z)));
      (props.solids['lamp posts'] ??= []).add((vm.Vector3(x, 2.5, z), vm.Vector3(0.09, 2.5, 0.09)));
      final ax = x + 0.4 * towards;
      arm.addInstance(trs(vm.Vector3(ax, 4.95, z)));
      final head = vm.Vector3(x + 0.85 * towards, 4.85, z);
      bulb.addInstance(trs(head));
      if (light) {
        final l = PointLight(color: lin3(const Color(0xFFFFCB8A)), intensity: 0, range: 12, falloffExponent: 1.6, channelMask: local);
        _lampLights.add(l);
        _lightNodes.add(Node(name: 'lamp light', localTransform: vm.Matrix4.translation(head - vm.Vector3(0, 0.5, 0)))..addComponent(PointLightComponent(l)));
      }
    }

    // Round the plaza (only beside and behind the wall: nothing tall may
    // stand between the camera's arc and the name), and the park.
    for (final s in [-1.0, 1.0]) {
      lamp(s * Plan.lampFlank, 3.5, -s, light: true);
      lamp(s * Plan.lampFlank, 10.5, -s, light: true);
      for (var z = 20.0; z < Plan.parkZ1; z += 14) {
        lamp(s * Plan.lampFlank, z, -s);
      }
      // The outer blocks' fronts, along the side streets.
      for (var z = -4.0; z < 90; z += 13) {
        lamp(s * (Plan.walkBlock - 0.6), z, -s);
      }
      // Along the avenue, beyond the camera's arc.
      for (var x = 36.0; x < 130; x += 13) {
        lamp(s * x, Plan.aveZ1 + 1, 0);
        lamp(s * x, Plan.lampFar, 0);
      }
    }
    for (var z = 18.0; z < Plan.parkZ1; z += 12) {
      lamp(-2.6, z, 0);
      lamp(2.6, z, 0);
    }
    for (final m in [pole, arm, bulb]) {
      scene.add(
        Node(name: 'lamps')
          ..lightChannelMask = sunOnly
          ..addComponent(InstancedMeshComponent(m)),
      );
    }

    // Low bollard lights along the front: they light the pavement and the
    // crowd without ever blocking the view of the wall.
    final post = InstancedMesh(geometry: CylinderGeometry(bottomRadius: 0.11, topRadius: 0.11, height: 0.75, radialSegments: 10), material: poleMat);
    final cap = InstancedMesh(geometry: CylinderGeometry(bottomRadius: 0.12, topRadius: 0.12, height: 0.16, radialSegments: 10), material: _bulbMat);
    // (None in the site gate's driveway: that one stands west of it.)
    for (var x = -16.0; x <= 16.01; x += 4) {
      final bx = (x - 12).abs() < 0.1 ? 10.4 : x;
      post.addInstance(trs(vm.Vector3(bx, 0.395, Plan.bollardZ)));
      (props.solids['bollards'] ??= []).add((vm.Vector3(bx, 0.4, Plan.bollardZ), vm.Vector3(0.11, 0.4, 0.11)));
      cap.addInstance(trs(vm.Vector3(bx, 0.84, Plan.bollardZ)));
    }
    scene.add(Node(name: 'bollards')..addComponent(InstancedMeshComponent(post)));
    scene.add(Node(name: 'bollard caps')..addComponent(InstancedMeshComponent(cap)));
    for (final x in [-12.0, 10.4]) {
      final l = PointLight(color: lin3(const Color(0xFFFFCB8A)), intensity: 0, range: 9, falloffExponent: 1.6, channelMask: local);
      _lampLights.add(l);
      _lightNodes.add(Node(name: 'bollard light', localTransform: vm.Matrix4.translation(vm.Vector3(x, 1.2, Plan.bollardZ + 0.2)))..addComponent(PointLightComponent(l)));
    }
  }

  /// Night lights on the build: two warm floods high over the avenue (no
  /// fixtures: they hang above the camera's path) aimed at the wall, so the
  /// name is always the brightest, sharpest thing in the frame.
  void _plazaLights() {
    for (final s in [-1.0, 1.0]) {
      final at = vm.Vector3(s * 10, 19, -21);
      final aim = (vm.Vector3(s * 2, 2.6, 0) - at)..normalize();
      final l = SpotLight(
        color: lin3(const Color(0xFFFFE2C0)),
        intensity: 0,
        range: 48,
        falloffExponent: 2,
        direction: aim,
        innerConeAngle: 0.32,
        outerConeAngle: 0.56,
        // One flood casts the wall's shadow (enough for depth; two cost a
        // second shadow map every frame).
        castsShadow: s < 0 && Tuning.floodShadow,
        shadowMapResolution: 1024,
        shadowSoftness: 1.2,
        channelMask: local,
      );
      _floods.add(l);
      _lightNodes.add(Node(name: 'flood', localTransform: vm.Matrix4.translation(at))..addComponent(SpotLightComponent(l)));
    }
  }

  /// Opens the site gate (0 shut … 1 open): its leaves step in behind the
  /// fence and slide aside, the left one west, the right one east.
  set gate(double open) {
    if (open == _gateOpen) return;
    _gateOpen = open;
    final f = eio(open);
    final inward = 0.24 * c01(f * 3);
    for (final (mesh, i, x) in _gateLeaves) {
      final dx = x < 12.5 ? -1.95 * c01((f - 0.2) / 0.8) : 1.9 * c01((f - 0.2) / 0.8);
      final y = identical(mesh, _posts) ? 0.475 : 0.62;
      mesh.setInstanceTransform(i, trs(vm.Vector3(x + dx, y, Plan.plazaZ0 - 0.3 + inward)));
    }
  }

  /// Opens the bay gate on the left (0 shut … 1 open) for the cleanup's
  /// truck: its leaves step in behind the fence and slide aside, the left
  /// one west, the right one (with its post) east.
  set bayGate(double open) {
    if (open == _bayOpen) return;
    _bayOpen = open;
    final f = eio(open);
    final inward = 0.24 * c01(f * 3);
    for (final (mesh, i, x) in _bayLeaves) {
      final dx = x < -7 ? -1.6 * c01((f - 0.2) / 0.8) : 2.25 * c01((f - 0.2) / 0.8);
      final y = identical(mesh, _posts) ? 0.475 : 0.62;
      mesh.setInstanceTransform(i, trs(vm.Vector3(x + dx, y, Plan.plazaZ0 - 0.3 + inward)));
    }
  }

  /// Night falls: windows, lamps, the plaza's grid and the floods come on.
  void update(Sky3D sky, double t) {
    final night = sky.night;
    // The local lights exist only after dusk (by day they would cost every
    // lit pixel a loop for nothing).
    final want = night > (_lightsOn ? 0.1 : 0.16);
    if (want != _lightsOn) {
      _lightsOn = want;
      for (final n in _lightNodes) {
        want ? scene.add(n) : scene.remove(n);
      }
    }
    towers.update(night, t);
    signs.update(night, t);
    props.update(night, t);
    for (final (m, k) in _glowMats) {
      m.emissiveStrength = k * night;
    }
    _bulbMat.emissiveStrength = 9 * smooth(0.15, 0.5, night);
    for (final l in _lampLights) {
      l.intensity = 26 * smooth(0.2, 0.6, night);
    }
    for (final f in _floods) {
      f.intensity = 1150 * smooth(0.3, 0.75, night);
    }
  }
}
