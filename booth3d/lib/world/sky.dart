import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../tuning.dart';
import 'ease.dart';

/// The sky over the city: a photographed one, Poly Haven's "Kloofendal 38°
/// Partly Cloudy (Pure Sky)" (CC0, assets/sky/CREDITS.md): high cloud over
/// a hazy horizon, a morning sun 38° up. The photograph is the background
/// and the image-based light; its sun, measured and lifted out of it
/// (tool/sky/sky_sun.py), is the directional light that casts the shadows,
/// at the strength it had in the photograph, so sun and shade keep the
/// balance they had that morning. The sky is turned so that the sun stands
/// where the city's always has: behind the camera's right, lighting the
/// plaza, the letters and the people from the side.
class Sky3D {
  Sky3D(this.scene);

  final Scene scene;

  /// 0 = day … 1 = night (windows, lamps, neon): always day, so 0; what
  /// lights up after dark stays off.
  double night = 0;

  /// 0 … 1 around sunrise and sunset (golden light): 0, as [night].
  double twilight = 0;

  /// How far the talk's look is on (0 the booth's … 1 the talk's, set by
  /// the world): deeper air (the city's far side fading into the haze, for
  /// scale), calmer colour, the frame's edges a little darker.
  double talk = 0;

  /// How far the camera's underground (0 … 1, set by the world): down the
  /// Unicode archive's stair, the air goes dark (no sky to take the colour
  /// of, no sun to scatter), and thicker.
  double underground = 0;

  /// The direction towards the sun.
  final sun = vm.Vector3(0, 1, 0);

  /// The photograph: 4K on the Mac, 2K on the web (a quarter of the
  /// download, and the decode runs on the page's one thread there).
  static const _asset = kIsWeb ? 'assets/sky/sky_2k.hdr' : 'assets/sky/sky_4k.hdr';

  /// Measured in it (sky_sun.py): the sun's direction in the photograph's
  /// own frame, its irradiance (RGB, in the photograph's units), and the
  /// horizon's radiance (the haze's colour).
  static final _skySun = vm.Vector3(0.63779, 0.61571, 0.46274);
  static final _sunRgb = vm.Vector3(2.94, 2.776, 2.483);
  static final _horizon = vm.Vector3(0.3995, 0.4293, 0.453);

  /// Where the sun stands over the city, as a compass direction (x, z):
  /// east-south-east, as it did at mid-morning on the old painted sky.
  static const _heading = (0.589, -0.808);

  /// The balance, a little sunnier than the photograph's (its sun was
  /// behind thin cloud: under it, shade was nearly as bright as sun): the
  /// sun [_sunBoost] times as strong, the sky's fill [_fill] of it (the sky
  /// itself shown as bright as ever), about 3 : 1 on the ground. Then the
  /// exposure that brings a sunlit grey ground to a mid grey.
  static const _sunBoost = 1.8, _fill = 0.7, _exposure = 0.85;

  late final DirectionalLight _light;

  Future<void> init() async {
    // The sky's sampled at (its transform × the world's direction): turn it
    // so that its sun comes round to [_heading].
    final theta = math.atan2(_skySun.z, _skySun.x) - math.atan2(_heading.$2, _heading.$1);
    await scene.loadEnvironment(_asset, rotationY: -theta, intensity: _fill, exposure: _exposure);
    scene.skybox?.intensity = 1 / _fill;
    sun.setFrom(scene.environmentTransform.transposed().transformed(_skySun));
    final lum = _sunRgb.dot(vm.Vector3(0.2126, 0.7152, 0.0722));
    _light = DirectionalLight(
      direction: -sun,
      color: _sunRgb / lum,
      intensity: lum * _sunBoost,
      castsShadow: true,
      shadowMaxDistance: 80,
      shadowCascadeCount: Tuning.cascades,
      shadowMapResolution: Tuning.shadowRes,
      // Contact-hardening: crisp where things meet the ground, softer the
      // further the shadow falls (the sun's real size), never mushy.
      shadowFilter: DirectionalShadowFilter.pcss,
      angularRadius: 0.0047,
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
    // A film's response: highlights roll off without bending their hue.
    scene.toneMapping = ToneMappingMode.agx;
    scene.postProcess.bloom
      ..enabled = true
      ..scatter = 0.7;
    scene.postProcess.colorGrading.enabled = true;
    scene.postProcess.vignette
      ..enabled = true
      ..radius = 0.8
      ..smoothness = 0.55;
    // The air: a height fog in the horizon's colour, taking the sky's own
    // colour where it's looked through, brighter towards the sun.
    scene.fog
      ..enabled = true
      ..mode = FogMode.exponential
      ..color = _horizon
      ..heightFalloff = 0.035
      ..height = 0
      ..skyColorInfluence = 0.85
      ..sunInScatter = 0.3
      ..sunInScatterExponent = 10;
  }

  void update(double t, [double dt = 1 / 60]) {
    final k = talk, g = underground;
    scene.exposure = _exposure * lerp(1, 0.97, k);
    scene.fog
      ..density = lerp(lerp(0.0014, 0.0022, k), 0.0035, g)
      ..color.setValues(lerp(_horizon.x, 0.006, g), lerp(_horizon.y, 0.007, g), lerp(_horizon.z, 0.009, g))
      ..heightFalloff = lerp(0.035, 0.0, g)
      ..skyColorInfluence = lerp(0.85, 0.0, g)
      ..sunInScatter = lerp(0.3, 0.0, g);
    scene.postProcess.bloom
      ..threshold = lerp(1.4, 1.3, k)
      ..intensity = lerp(0.07, 0.09, k);
    scene.postProcess.colorGrading
      ..saturation = lerp(1.04, 0.98, k)
      ..contrast = lerp(1.04, 1.08, k)
      ..temperature = lerp(0.0, 0.03, k);
    scene.postProcess.vignette.intensity = lerp(0.18, 0.3, k);
    scene.ambientOcclusion.intensity = lerp(0.9, 1.05, k);
  }
}
