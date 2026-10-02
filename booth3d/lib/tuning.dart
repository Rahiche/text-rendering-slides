import 'package:flutter_scene/scene.dart' show AntiAliasingMode;

import 'perf.dart';
import 'quality.dart' show RenderQuality;
import 'perf_stub.dart' if (dart.library.io) 'perf_io.dart' show perfEnv;

/// Render settings, tuned on the booth machine (a fanless MacBook Air M3,
/// 8 GB), where Name City used to drop frames after a while:
///
/// - The sky's lighting was re-baked every 1.5 s into a 512² reflection cube
///   (8 prefilter bands × 6 faces): the GPU was busy with it most of the time
///   and each cycle stalled a frame for 100–200 ms. Even small and every 4 s,
///   a live re-bake still cost a late frame or two per cycle. Now it's baked
///   once per key hour as the city starts (see `Sky3D`), into a 128² cube
///   (the city's materials are mostly rough: it looks the same).
/// - The 3D view rendered at the screen's full density (3200×1800 on a
///   Retina laptop); [RenderQuality] now picks the ratio, unless fixed.
/// - [staticShadows]: see there.
///
/// A perf build (BOOTH3D_PERF) reads overrides from the environment, to
/// compare what each costs without rebuilding:
///   BOOTH3D_RATIO=1.25  BOOTH3D_AA=smaa  BOOTH3D_CASCADES=2  BOOTH3D_SHADOWRES=1536  BOOTH3D_FLOODSHADOW=0
///   BOOTH3D_IBL=interval|manual  BOOTH3D_IBLSEC=4  BOOTH3D_CUBE=128  BOOTH3D_IBLFACE=64  BOOTH3D_IBLEQ=256
///   BOOTH3D_STATICSHADOW=1  BOOTH3D_SPEED=8  BOOTH3D_AO=0
abstract final class Tuning {
  static String? _env(String key) => PerfLog.enabled ? perfEnv(key) : null;
  static double? _num(String key) => double.tryParse(_env(key) ?? '');

  /// A fixed render pixel ratio for the 3D view (null: [RenderQuality]'s).
  static final double? ratio = _num('BOOTH3D_RATIO');
  static final AntiAliasingMode aa = AntiAliasingMode.values.asNameMap()[_env('BOOTH3D_AA')] ?? AntiAliasingMode.auto;
  static final int cascades = _num('BOOTH3D_CASCADES')?.toInt() ?? 3;
  static final int shadowRes = _num('BOOTH3D_SHADOWRES')?.toInt() ?? 2048;

  /// The sky's lighting: baked once per key hour and followed in steps
  /// ('keys', the default), re-baked live on an interval, or baked once.
  static final bool iblKeys = (_env('BOOTH3D_IBL') ?? 'keys') == 'keys';
  static final bool iblInterval = _env('BOOTH3D_IBL') != 'manual';
  static final int cube = _num('BOOTH3D_CUBE')?.toInt() ?? 128;
  static final double iblSeconds = _num('BOOTH3D_IBLSEC') ?? 4;
  static final int iblFace = _num('BOOTH3D_IBLFACE')?.toInt() ?? 64;
  static final int iblEquirect = _num('BOOTH3D_IBLEQ')?.toInt() ?? 256;
  static final bool floodShadow = _env('BOOTH3D_FLOODSHADOW') != '0';

  /// `Node.shadowStatic` caches casters' shadows across frames, but the
  /// cache starts over (new tiles for every cascade) whenever the light turns,
  /// and the sun here turns every frame: with it, each frame allocated and
  /// re-rendered three 2048² tiles. So no static shadows.
  static final bool staticShadows = _env('BOOTH3D_STATICSHADOW') == '1';
  /// Contact occlusion (ambient occlusion at half resolution, and the
  /// sun's contact shadows): things darken where they meet the ground and
  /// each other, so nothing floats. The capture build reads it from a
  /// define (to compare), a perf build from the environment.
  static final bool ao = (_env('BOOTH3D_AO') ?? const String.fromEnvironment('BOOTH3D_AO', defaultValue: '1')) != '0';

  static final double speed = _num('BOOTH3D_SPEED') ?? const int.fromEnvironment('BOOTH3D_SPEED', defaultValue: 1).toDouble();
}
