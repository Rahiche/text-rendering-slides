import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../tuning.dart';
import 'kit.dart';

/// The sky over the city, always by day, in the talk's blueprint palette: a
/// cobalt sky, white clouds drifting over. It's always morning: the sun
/// swings gently between early and mid-morning every 8 minutes, low in the
/// east-south-east, so it lights everything from the side (the letters,
/// the bricks and the people modelled, their shadows long across the
/// plaza) rather than flat from behind the camera as at noon. A stylised
/// gradient sky drives the background (with the sun's disk) and, without
/// the disk, the image-based light; the sun is the shadow-casting key
/// light.
class Sky3D {
  Sky3D(this.scene);

  final Scene scene;

  /// Seconds for the sun to go from early to mid-morning and back.
  static const period = 480.0;

  /// The hours it goes between (at scene time 0, the earlier).
  static const startHour = 7.9, endHour = 9.7;

  /// 0 = day … 1 = night (windows, lamps, neon): always 0 now, the sun
  /// never going down; what lights up after dark stays off.
  double night = 0;

  /// 0 … 1 around sunrise and sunset (golden light): 0, as [night].
  double twilight = 0;

  /// The hour of the day, 0 … 24.
  double hour = startHour;

  /// The direction towards the sun.
  final sun = vm.Vector3(0, 1, 0);

  late final GradientSkySource _sky; // background, with the disk
  late final GradientSkySource _ibl; // lighting, no disk
  late final DirectionalLight _light;
  late final PhysicallyBasedMaterial _cloudMat;
  late final InstancedMesh _clouds;
  final _puffs = <_Puff>[];
  double? _bakedAt;

  /// The image-based light, baked once for each of [_iblHours] as the city
  /// starts and then followed in steps through the day. Re-baking it live
  /// every few seconds (a [SkyEnvironment] on an interval) cost a late frame
  /// or two every time, whatever the bake's size.
  final _iblKeys = <EnvironmentMap>[];
  int _iblKey = -1, _frames = 0;

  /// Hours the lighting is baked for: every half hour or so through the
  /// morning.
  static const _iblHours = <double>[7.85, 8.3, 8.75, 9.2, 9.65];

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
      shadowCascadeCount: Tuning.cascades,
      shadowMapResolution: Tuning.shadowRes,
      shadowSoftness: 0.05,
      shadowDepthBias: 0.015,
      shadowNormalBias: 0.02,
    );
    scene.directionalLight = _light;
    // Contact occlusion: feet on the ground, bricks on bricks, kerbs, the
    // stalls' counters: darker where things meet, so nothing floats.
    scene.ambientOcclusion
      ..enabled = Tuning.ao
      ..method = AmbientOcclusionMethod.groundTruth
      ..intensity = 0.9
      ..radius = 0.45
      ..power = 1.5
      ..halfResolution = true;
    _light
      ..contactShadows = Tuning.ao
      ..contactShadowDistance = 0.35;
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
    _cloudBank();
  }

  /// (Re)binds the sky to the lighting; a fresh binding bakes at once (used
  /// after a jump in time, e.g. capture or fast-forward).
  void _bindEnvironment() {
    scene.skyEnvironment = SkyEnvironment(
      _ibl,
      refresh: Tuning.iblInterval ? SkyEnvironmentRefresh.interval : SkyEnvironmentRefresh.manual,
      interval: Duration(milliseconds: (Tuning.iblSeconds * 1000).round()),
      faceResolution: Tuning.iblFace,
      equirectWidth: Tuning.iblEquirect,
    );
  }

  /// The lighting's sky at [look], with the sun towards [sunDir]: a soft
  /// share of the sun's glow (warm light from its side of the sky), not its
  /// hot disk.
  void _iblAt(_Look look, vm.Vector3 sunDir) {
    _ibl
      ..zenithColor = look.zenith
      ..horizonColor = look.horizon
      ..groundColor = look.ground * 1.6
      ..sunDirection = sunDir
      ..sunSharpness = 300
      ..sunColor = look.disk * 0.18;
  }

  /// Bakes the next keys (two a frame, once a few frames have been shown: a
  /// WebGL context bakes them wrong before that), and once they're all
  /// there, lights the scene with the one for this hour.
  void _followKeys() {
    if (_iblKeys.length < _iblHours.length) {
      if (++_frames < 20) return;
      final sunDir = vm.Vector3.zero();
      for (var n = 0; n < 2 && _iblKeys.length < _iblHours.length; n++) {
        final h = _iblHours[_iblKeys.length];
        _sunAt(h, sunDir);
        _iblAt(_Look.at(h), sunDir);
        _iblKeys.add(EnvironmentMap.fromSky(_ibl, faceResolution: Tuning.iblFace, equirectWidth: Tuning.iblEquirect));
      }
      if (_iblKeys.length < _iblHours.length) return;
      scene.skyEnvironment = null;
    }
    // The nearest key.
    var best = 0;
    var bestD = 99.0;
    for (var k = 0; k < _iblHours.length; k++) {
      final d = (hour - _iblHours[k]).abs();
      if (d < bestD) {
        bestD = d;
        best = k;
      }
    }
    if (best != _iblKey) {
      _iblKey = best;
      scene.environment = _iblKeys[best];
    }
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
    final keyed = Tuning.iblKeys && _iblKeys.length == _iblHours.length;
    if (!keyed && dt == 0 && (_bakedAt == null || (t - _bakedAt!).abs() > 0.5)) {
      _bindEnvironment();
      _bakedAt = t;
    }

    hour = hourAt(t);
    if (Tuning.iblKeys) _followKeys();
    _sunAt(hour, sun);
    final look = _Look.at(hour);
    final y = sun.y;
    night = 1 - smooth(-0.17, 0.10, y);
    twilight = 1 - smooth(0.04, 0.32, y.abs());

    // Background sky, with the sun's disk.
    _sky
      ..zenithColor = look.zenith
      ..horizonColor = look.horizon
      ..groundColor = look.ground
      ..sunDirection = sun
      ..sunSharpness = 2600
      ..sunColor = look.disk;
    if (!keyed) _iblAt(look, sun);

    // Key light: the sun.
    _light
      ..direction = -sun
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

  /// The hour at scene time [t]: from [startHour] to [endHour] and back,
  /// easing at each end.
  static double hourAt(double t) => (startHour + endHour) / 2 - (endHour - startHour) / 2 * math.cos(2 * math.pi * t / period);

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
    (6.6, _Look(hex3(0x3466B4), hex3(0xFFC98C), hex3(0x2A3B5C), hex3(0xFFC66D, 14), hex3(0xFFC98C), 2.3, 1.35, 1.08, 0.0035)),
    // (The morning's shade lifted a little: a lighter bounce off the
    // ground, more of the sky's light, so nobody stands in a gloom.)
    (8.0, _Look(hex3(0x2A6CCB), hex3(0x9AD3FF), hex3(0x2A3E62), hex3(0xFFF4DC, 16), hex3(0xFFF0D8), 3.5, 1.25, 1.0, 0.003)),
    (12.0, _Look(hex3(0x2063C9), hex3(0x90CEFF), hex3(0x2A3E62), hex3(0xFFFBF0, 16), hex3(0xFFF8EE), 3.9, 1.2, 1.0, 0.003)),
    (15.6, _Look(hex3(0x2763C3), hex3(0x9FD1F9), hex3(0x152842), hex3(0xFFF0D8, 16), hex3(0xFFEFD6), 3.6, 1.0, 1.0, 0.003)),
    (17.0, _Look(hex3(0x3457A8), hex3(0xFFCF8A), hex3(0x1A2440), hex3(0xFFC66D, 16), hex3(0xFFC27A), 3.0, 1.05, 1.03, 0.0034)),
  ];

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
