import 'package:flutter_scene/scene.dart' show AntiAliasingMode;

import 'perf.dart';
import 'perf_stub.dart' if (dart.library.io) 'perf_io.dart' show perfEnv;

/// Render settings. A perf build (BOOTH3D_PERF) reads overrides from the
/// environment, to compare what each costs without rebuilding:
///   BOOTH3D_RATIO=1.25  BOOTH3D_AA=smaa  BOOTH3D_CASCADES=2  BOOTH3D_SHADOWRES=1536
///   BOOTH3D_IBL=manual  BOOTH3D_FLOODSHADOW=0  BOOTH3D_SPEED=8
abstract final class Tuning {
  static String? _env(String key) => PerfLog.enabled ? perfEnv(key) : null;
  static double? _num(String key) => double.tryParse(_env(key) ?? '');

  /// A fixed render pixel ratio for the 3D view (null: the device's).
  static final double? ratio = _num('BOOTH3D_RATIO');
  static final AntiAliasingMode aa = AntiAliasingMode.values.asNameMap()[_env('BOOTH3D_AA')] ?? AntiAliasingMode.auto;
  static final int cascades = _num('BOOTH3D_CASCADES')?.toInt() ?? 3;
  static final int shadowRes = _num('BOOTH3D_SHADOWRES')?.toInt() ?? 2048;
  static final bool iblInterval = _env('BOOTH3D_IBL') != 'manual';
  static final bool floodShadow = _env('BOOTH3D_FLOODSHADOW') != '0';
  static final double speed = _num('BOOTH3D_SPEED') ?? const int.fromEnvironment('BOOTH3D_SPEED', defaultValue: 1).toDouble();
}
