import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';

/// Day and night over the city, an 8-minute day painted in the talk's
/// blueprint palette: a cobalt day sky, an amber → coral → pink sunset, a
/// violet blue hour, a deep navy night with stars, a big moon and the city
/// glowing, then a pink dawn. A stylised gradient sky drives the background
/// (with the sun or moon disk) and, without the disk, the image-based light;
/// the sun (or the moon) is the shadow-casting key light. [night] drives
/// windows, lamps and neon.
class Sky3D {
  Sky3D(this.scene);

  final Scene scene;

  /// Seconds per day.
  static const period = 480.0;

  /// The hour of the day at scene time 0 (a bright morning).
  static const startHour = 8.0;

  /// 0 = day … 1 = night (windows, lamps, neon).
  double night = 0;

  /// 0 … 1 around sunrise and sunset (golden light).
  double twilight = 0;

  /// The hour of the day, 0 … 24.
  double hour = startHour;

  /// Directions towards the sun and the moon.
  final sun = vm.Vector3(0, 1, 0);
  final moon = vm.Vector3(0, 1, 0);

  late final GradientSkySource _sky; // background, with the disk
  late final GradientSkySource _ibl; // lighting, no disk
  late final DirectionalLight _light;
  late final UnlitMaterial _starMat, _moonMat;
  final _starNode = Node(name: 'stars');
  final _moon = Node(name: 'moon');
  late final PhysicallyBasedMaterial _cloudMat;
  late final InstancedMesh _clouds;
  final _puffs = <_Puff>[];
  double? _bakedAt;

  void init() {
    _sky = GradientSkySource();
    _ibl = GradientSkySource(sunColor: vm.Vector3.zero());
    scene.skybox = Skybox(_sky);
    _bindEnvironment();
    _light = DirectionalLight(
      direction: vm.Vector3(-0.3, -1, 0.4),
      intensity: 3,
      castsShadow: true,
      shadowMaxDistance: 80,
      shadowCascadeCount: 3,
      shadowMapResolution: 2048,
      shadowSoftness: 0.05,
      shadowDepthBias: 0.015,
      shadowNormalBias: 0.02,
    );
    scene.directionalLight = _light;
    scene.toneMapping = ToneMappingMode.aces;
    scene.postProcess.bloom
      ..enabled = true
      ..scatter = 0.72;
    scene.postProcess.colorGrading.enabled = true;
    scene.postProcess.vignette
      ..enabled = true
      ..intensity = 0.28
      ..radius = 0.8
      ..smoothness = 0.55;
    scene.fog
      ..enabled = true
      ..mode = FogMode.exponential
      ..heightFalloff = 0.035
      ..height = 0
      ..skyColorInfluence = 0.65
      ..sunInScatter = 0.35
      ..sunInScatterExponent = 10;
    _stars();
    _moonDisk();
    _cloudBank();
  }

  /// A big, soft moon (the bloom gives it its glow).
  void _moonDisk() {
    _moonMat = UnlitMaterial()..baseColorFactor = vm.Vector4(0, 0, 0, 1);
    final geo = SphereGeometry(radius: 13, segments: 28, rings: 16).extractMeshData();
    // Faint maria: darker vertex colours on one side.
    final colors = Float32List(geo.vertexCount * 4);
    for (var i = 0; i < geo.vertexCount; i++) {
      final x = geo.positions[i * 3] / 13, y = geo.positions[i * 3 + 1] / 13;
      final mare = smooth(0.55, 0.15, (vm.Vector2(x + 0.25, y - 0.2)).length) * 0.22 + smooth(0.4, 0.1, (vm.Vector2(x - 0.3, y + 0.25)).length) * 0.16;
      final v = 1 - mare;
      colors
        ..[i * 4] = v
        ..[i * 4 + 1] = v * 0.98
        ..[i * 4 + 2] = v * 0.92
        ..[i * 4 + 3] = 1;
    }
    _moon.mesh = Mesh(
      MeshGeometry.fromMeshData(MeshData(positions: geo.positions, vertexCount: geo.vertexCount, normals: geo.normals, texCoords: geo.texCoords, colors: colors, indices: geo.indices)),
      _moonMat,
    );
    _moon
      ..castsShadows = false
      ..lightChannelMask = 0x01;
    scene.add(_moon);
  }

  /// (Re)binds the sky to the lighting; a fresh binding bakes at once (used
  /// after a jump in time, e.g. capture or fast-forward).
  void _bindEnvironment() {
    scene.skyEnvironment = SkyEnvironment(
      _ibl,
      refresh: SkyEnvironmentRefresh.interval,
      interval: const Duration(milliseconds: 1500),
      faceResolution: 64,
      equirectWidth: 256,
    );
  }

  void _stars() {
    _starMat = UnlitMaterial()..baseColorFactor = vm.Vector4(0, 0, 0, 1);
    final stars = InstancedMesh(geometry: IcosphereGeometry(radius: 1, subdivisions: 0), material: _starMat);
    const tints = [0xFFFFFF, 0xE3F2FF, 0xFFE2B0, 0xC9DEFF, 0xFFD0E8];
    for (var i = 0; i < 520; i++) {
      final a = rnd(i, 1) * math.pi * 2;
      // More stars low in the sky, where the camera mostly looks.
      final e = math.asin(0.04 + 0.92 * math.pow(rnd(i, 2), 1.6));
      final d = vm.Vector3(math.cos(a) * math.cos(e), math.sin(e), math.sin(a) * math.cos(e));
      final big = rnd(i, 3);
      final size = 0.5 + 1.7 * big * big * big;
      final k = 0.35 + 0.65 * rnd(i, 4) + 1.6 * big * big;
      stars.addInstance(trs(d * 620, s: vm.Vector3.all(size)), color: v4(hex3(tints[i % tints.length], k)));
    }
    scene.add(
      _starNode
        ..castsShadows = false
        ..lightChannelMask = 0x01
        ..addComponent(InstancedMeshComponent(stars)),
    );
  }

  void _cloudBank() {
    final puff = IcosphereGeometry(radius: 1, subdivisions: 2).extractMeshData().transformed(
      vm.Matrix4.diagonal3Values(1, 0.62, 1),
    );
    _cloudMat = pbr(rgb(0.92, 0.95, 1.0), roughness: 1)
      ..emissiveFactor = vm.Vector4(1, 1, 1, 1)
      ..emissiveStrength = 0;
    _clouds = InstancedMesh(geometry: MeshGeometry.fromMeshData(puff), material: _cloudMat);
    for (var c = 0; c < 14; c++) {
      // A ring of clouds, mostly over the city (the +Z half, where the camera looks).
      final az = (-0.55 + 1.1 * (c / 13)) * math.pi + (rnd(c, 7) - 0.5) * 0.3;
      final dist = 260 + 200 * rnd(c, 8);
      final cx = math.sin(az) * dist, cz = math.cos(az) * dist;
      final cy = 55 + 85 * rnd(c, 9);
      final scale = 9 + 9 * rnd(c, 10);
      final n = 4 + (rnd(c, 11) * 4).floor();
      for (var p = 0; p < n; p++) {
        final u = n == 1 ? 0.0 : p / (n - 1) - 0.5;
        final r = scale * (1 - 0.9 * u * u) * (0.75 + 0.35 * rnd(c, p, 1));
        _puffs.add(
          _Puff(
            cx + u * scale * 3.4 + (rnd(c, p, 2) - 0.5) * scale * 0.6,
            cy + r * 0.25 + (rnd(c, p, 3) - 0.3) * scale * 0.25,
            cz + (rnd(c, p, 4) - 0.5) * scale * 1.2,
            r,
          ),
        );
        _clouds.addInstance(hidden);
      }
    }
    scene.add(
      Node(name: 'clouds')
        ..castsShadows = false
        ..lightChannelMask = 0x01
        ..addComponent(InstancedMeshComponent(_clouds)),
    );
  }

  /// [dt] 0 means "about to be shown after a jump" (the capture's settle
  /// frames): the lighting is re-baked at once instead of catching up over
  /// the next frames.
  void update(double t, [double dt = 1 / 60]) {
    if (dt == 0 && (_bakedAt == null || (t - _bakedAt!).abs() > 0.5)) {
      _bindEnvironment();
      _bakedAt = t;
    }

    hour = (startHour + 24 * t / period) % 24;
    _sunAt(hour, sun);
    _moonAt(hour, moon);
    final look = _Look.at(hour);
    final y = sun.y;
    night = 1 - smooth(-0.17, 0.10, y);
    twilight = 1 - smooth(0.04, 0.32, y.abs());

    // Background sky (with the sun, or at night the moon, as its disk).
    final moonUp = night > 0.5;
    _sky
      ..zenithColor = look.zenith
      ..horizonColor = look.horizon
      ..groundColor = look.ground
      ..sunDirection = moonUp ? moon : sun
      ..sunSharpness = moonUp ? 4000 : 2600
      ..sunColor = moonUp ? hex3(0xC9D8FF, 0.32 * smooth(0.5, 0.9, night)) : look.disk;
    // The lighting gets a soft share of the sun's glow (warm light from its
    // side of the sky), not its hot disk.
    _ibl
      ..zenithColor = look.zenith
      ..horizonColor = look.horizon
      ..groundColor = look.ground * 1.6
      ..sunDirection = sun
      ..sunSharpness = 300
      ..sunColor = look.disk * 0.18;

    // Key light: the sun (kept a little above the horizon at twilight so
    // the last light rakes across the plaza), then the moon.
    final lowSun = vm.Vector3(sun.x, math.max(sun.y, 0.07), sun.z)..normalize();
    final m = smooth(0.55, 0.9, night);
    final dir = (lowSun * (1 - m) + moon * m)..normalize();
    _light
      ..direction = -dir
      ..color = look.light
      ..intensity = look.lightPower;

    scene.environmentIntensity = look.ambient;
    scene.exposure = look.exposure;
    scene.fog
      ..color = mix3(look.horizon, look.zenith, 0.3)
      ..density = look.fog;
    scene.postProcess.bloom
      ..threshold = lerp(1.05, 0.8, night)
      ..intensity = lerp(0.12, 0.26, night);
    scene.postProcess.colorGrading
      ..saturation = lerp(1.12, 1.18, night) + 0.06 * twilight
      ..contrast = lerp(1.08, 1.05, night)
      ..temperature = 0.06 * twilight - 0.04 * night;

    // Stars and the moon come out after dusk.
    final starK = 3.2 * smooth(0.55, 0.95, night);
    _starMat.baseColorFactor = vm.Vector4(starK, starK, starK, 1);
    _starNode.visible = starK > 0.01;
    final moonK = 4.2 * smooth(0.45, 0.9, night);
    _moonMat.baseColorFactor = vm.Vector4(moonK, moonK * 0.98, moonK * 0.9, 1);
    _moon.localTransform = vm.Matrix4.translation(moon * 560);
    _moon.visible = moonK > 0.01;

    // Clouds drift west → east, catching the sky's colour.
    _cloudMat.emissiveFactor = v4(mix3(look.horizon, look.zenith, 0.35));
    _cloudMat.emissiveStrength = lerp(0.35, 0.8, night);
    _cloudMat.baseColorFactor = v4(mix3(vm.Vector3(0.95, 0.97, 1.0), vm.Vector3(0.25, 0.3, 0.45), night));
    _clouds.updateInstanceTransforms((list) {
      for (var i = 0; i < _puffs.length; i++) {
        final p = _puffs[i];
        final x = (p.x + 1.6 * t + 700) % 1400 - 700;
        setTrsY(list[i], x, p.y, p.z, 0, p.r);
      }
    });
  }

  /// The sun's path: rises in the east-south-east, high in the south (behind
  /// the camera, lighting the wall's face) at noon, sets in the
  /// west-south-west.
  static void _sunAt(double hour, vm.Vector3 out) {
    final phi = (hour - 6) / 12 * math.pi;
    final e = math.sin(phi) * 1.0;
    final ax = math.cos(phi), az = -math.sin(phi) - 0.35;
    final l = math.sqrt(ax * ax + az * az);
    out
      ..x = ax / l * math.cos(e)
      ..y = math.sin(e)
      ..z = az / l * math.cos(e);
  }

  /// A big moon low over the city (north-north-east), drifting slowly.
  static void _moonAt(double hour, vm.Vector3 out) {
    final n = ((hour - 18 + 24) % 24) / 12; // 0 at dusk … 1 at dawn
    final az = (0.42 - 0.5 * n) * 1.0; // radians east of north
    final el = (0.17 + 0.16 * math.sin(n * math.pi)) * 1.0;
    out
      ..x = math.sin(az) * math.cos(el)
      ..y = math.sin(el)
      ..z = math.cos(az) * math.cos(el);
  }
}

class _Puff {
  _Puff(this.x, this.y, this.z, this.r);
  final double x, y, z, r;
}

/// One moment of the day's look; [at] blends the keys.
class _Look {
  _Look(this.zenith, this.horizon, this.ground, this.disk, this.light, this.lightPower, this.ambient, this.exposure, this.fog);

  final vm.Vector3 zenith, horizon, ground, disk, light;
  final double lightPower, ambient, exposure, fog;

  static final _keys = <(double, _Look)>[
    (0.0, _night),
    (4.6, _Look(hex3(0x050F27), hex3(0x18295A), hex3(0x050B16), vm.Vector3.zero(), hex3(0x9DB8FF), 0.32, 3.4, 1.55, 0.0045)),
    (5.3, _Look(hex3(0x131E4C), hex3(0x3E447F), hex3(0x0A1024), hex3(0xFF9E9A, 3), hex3(0xB7A6FF), 0.25, 2.2, 1.4, 0.0045)),
    (5.85, _Look(hex3(0x22377E), hex3(0xB58BA6), hex3(0x121A35), hex3(0xFF9E7A, 9), hex3(0xFFA894), 0.9, 1.4, 1.2, 0.004)),
    (6.6, _Look(hex3(0x3466B4), hex3(0xFFC98C), hex3(0x16243F), hex3(0xFFC66D, 14), hex3(0xFFC98C), 2.3, 1.15, 1.08, 0.0035)),
    (8.0, _Look(hex3(0x2A6CCB), hex3(0x9AD3FF), hex3(0x152842), hex3(0xFFF4DC, 16), hex3(0xFFF0D8), 3.5, 1.0, 1.0, 0.003)),
    (12.0, _Look(hex3(0x2063C9), hex3(0x90CEFF), hex3(0x152842), hex3(0xFFFBF0, 16), hex3(0xFFF8EE), 3.9, 1.0, 1.0, 0.003)),
    (15.6, _Look(hex3(0x2763C3), hex3(0x9FD1F9), hex3(0x152842), hex3(0xFFF0D8, 16), hex3(0xFFEFD6), 3.6, 1.0, 1.0, 0.003)),
    (17.0, _Look(hex3(0x3457A8), hex3(0xFFCF8A), hex3(0x1A2440), hex3(0xFFC66D, 16), hex3(0xFFC27A), 3.0, 1.05, 1.03, 0.0034)),
    (17.9, _Look(hex3(0x273077), hex3(0xEE8E78), hex3(0x1A1C38), hex3(0xFF9E7A, 14), hex3(0xFF9A72), 1.8, 1.25, 1.1, 0.0038)),
    (18.5, _Look(hex3(0x172360), hex3(0x7E5A9C), hex3(0x120F2A), hex3(0xFF8F7A, 7), hex3(0xE59AA6), 0.5, 1.6, 1.25, 0.0042)),
    (19.1, _Look(hex3(0x0C1846), hex3(0x3F4392), hex3(0x0A0E24), hex3(0xC39BFF, 1.5), hex3(0x9DA6FF), 0.22, 2.4, 1.45, 0.0045)),
    (19.8, _night),
    (24.0, _night),
  ];

  static final _night = _Look(
    hex3(0x030916),
    hex3(0x0E2048),
    hex3(0x040A15),
    vm.Vector3.zero(),
    hex3(0x9DB8FF),
    0.34,
    3.6,
    1.6,
    0.0045,
  );

  static _Look at(double hour) {
    var i = 0;
    while (i < _keys.length - 2 && hour >= _keys[i + 1].$1) {
      i++;
    }
    final (h0, a) = _keys[i];
    final (h1, b) = _keys[i + 1];
    final f = smooth(0, 1, (hour - h0) / (h1 - h0));
    return _Look(
      mix3(a.zenith, b.zenith, f),
      mix3(a.horizon, b.horizon, f),
      mix3(a.ground, b.ground, f),
      mix3(a.disk, b.disk, f),
      mix3(a.light, b.light, f),
      lerp(a.lightPower, b.lightPower, f),
      lerp(a.ambient, b.ambient, f),
      lerp(a.exposure, b.exposure, f),
      lerp(a.fog, b.fog, f),
    );
  }
}
