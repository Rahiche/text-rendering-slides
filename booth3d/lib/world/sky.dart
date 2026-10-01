import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';

/// Day and night over the city (an 8-minute cycle, like the 2D booth):
/// the physical sky follows the sun, the sun (or the moon) lights the city,
/// stars come out, and [night] drives windows and lamps.
class Sky3D {
  Sky3D(this.scene);

  final Scene scene;
  late final PhysicalSkySource _sky;
  late final DirectionalLight _light;
  late final InstancedMesh _stars;
  late final PhysicallyBasedMaterial _starMat;

  static const period = 480.0;

  /// 0 = day, 1 = night.
  double night = 0;

  void init() {
    _sky = PhysicalSkySource(sunDirection: vm.Vector3(0.3, 0.5, -0.6), turbidity: 6);
    scene.skybox = Skybox(_sky);
    scene.skyEnvironment = SkyEnvironment(_sky, refresh: SkyEnvironmentRefresh.interval, interval: const Duration(seconds: 2));
    _light = DirectionalLight(
      direction: vm.Vector3(-0.3, -1, 0.4),
      intensity: 3,
      castsShadow: true,
      shadowMaxDistance: 90,
      shadowMapResolution: 2048,
      shadowSoftness: 0.12,
    );
    scene.directionalLight = _light;
    scene.toneMapping = ToneMappingMode.agx;
    scene.postProcess.bloom
      ..enabled = true
      ..threshold = 1.2
      ..intensity = 0.22;
    scene.postProcess.colorGrading
      ..enabled = true
      ..saturation = 1.25
      ..contrast = 1.12;
    scene.fog
      ..enabled = true
      ..mode = FogMode.exponential
      ..density = 0.0012;
    _starMat = pbr(rgb(1, 1, 1), emissive: rgb(1, 1, 1), emissiveStrength: 0);
    _stars = InstancedMesh(geometry: SphereGeometry(radius: 0.5, segments: 6, rings: 4), material: _starMat);
    for (var i = 0; i < 260; i++) {
      final a = rnd(i, 1) * math.pi * 2, e = 0.15 + rnd(i, 2) * 1.3;
      final d = vm.Vector3(math.cos(a) * math.cos(e), math.sin(e), math.sin(a) * math.cos(e));
      _stars.addInstance(trs(d * 260, s: vm.Vector3.all(0.5 + rnd(i, 3) * 0.9)));
    }
    scene.add(Node(name: 'stars')..addComponent(InstancedMeshComponent(_stars)));
  }

  void update(double t) {
    // Starts mid-morning; elevation follows a sine over the period.
    final phase = (t / period + 0.12) % 1.0;
    final elevation = math.sin(phase * 2 * math.pi) * 1.05; // radians-ish
    final az = phase * 2 * math.pi + 0.6;
    final toSun = vm.Vector3(math.cos(az) * math.cos(elevation), math.sin(elevation), math.sin(az) * math.cos(elevation) - 0.4)..normalize();
    _sky.sunDirection = toSun;
    final day = c01((toSun.y + 0.08) / 0.3); // 0 night … 1 day
    night = 1 - day;
    // Sun by day, a cool moon (opposite the sun) by night.
    final moon = -toSun;
    final useMoon = toSun.y < 0;
    final dir = useMoon ? moon : toSun;
    _light
      ..direction = -dir
      ..intensity = useMoon ? 0.35 : 4.6 * c01(toSun.y / 0.25 + 0.15)
      ..color = useMoon ? vm.Vector3(0.6, 0.7, 1.0) : vm.Vector3(1.0, 0.92 + 0.08 * day, 0.82 + 0.18 * day);
    _sky.energy = 0.08 + 0.92 * day;
    scene.environmentIntensity = 0.08 + 0.42 * day;
    scene.exposure = 0.9 + 0.9 * night;
    scene.fog.color = vm.Vector3(0.01, 0.02, 0.05) * (1 - day) + vm.Vector3(0.32, 0.42, 0.58) * day;
    _starMat.emissiveStrength = 3.5 * c01(night * 1.4 - 0.4);
  }
}
