import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/web_fonts.dart';
import 'package:text_slides/booth/model.dart';
import 'package:text_slides/booth/ui/booth_ui.dart';

import '../tuning.dart';
import 'city.dart';
import 'city_signs.dart' show CitySigns;
import 'director.dart';
import 'life.dart';
import 'physics.dart';
import 'script_alley.dart' show ScriptAlley;
import 'site.dart';
import 'sky.dart';
import 'typing.dart';

/// 名前の街 · Name City: the whole 3D world, driven by the booth model.
class World3D {
  final scene = Scene();
  late final city = City3D(scene);
  late final sky = Sky3D(scene);
  late final site = Site3D(scene);
  late final typing = Typing3D(scene);
  late final life = Life3D(scene);
  final director = Director();
  bool ready = false;
  bool _skipped = false;

  /// What's being got ready, for the loading screen: 'fonts' (the web),
  /// 'city', 'people'; [ready] once done.
  final stage = ValueNotifier<String>('');

  Future<void> init() async {
    await Scene.initializeStaticResources();
    scene.antiAliasingMode = Tuning.aa;
    EnvironmentMap.radianceCubeSize = Tuning.cube;
    if (kIsWeb) {
      stage.value = 'fonts';
      await _warmUpFonts();
    }
    stage.value = 'city';
    await Physics.ensureReady();
    if (const String.fromEnvironment('BOOTH3D_TIMES') != '') debugPrint(Physics.selfTest());
    sky.init();
    site.init();
    typing.init();
    await Future.wait([city.init(), site.alley.init()]);
    stage.value = 'people';
    await life.init();
    ready = true;
  }

  /// The web has no system CJK/Arabic/… fonts: Flutter downloads Noto
  /// fallbacks on first use. What's drawn once (the glyph towers, the signs,
  /// the props' and the factory's lettering, the blueprint) needs every
  /// script it uses first, so fetch them all at once, in one wait (a cold
  /// page load takes a few seconds); names typed later wait for their own.
  Future<void> _warmUpFonts() async {
    const ja = 'あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん'
        'アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲンー'
        '日目月高自門凸本字語書店活字印刷喫茶文具工事中安全第一完成名前街田中山川'
        '喫煙所 あきかん 旅 文字工場 文字列 デコード フォント シェーピング アウトライン ラスタライズ 画面 テキストパイプラインの中 次の建物 記念写真 はい、チーズ！ 字間';
    const world = 'ب ع ا مرحبا ש שלום क ह नमस्ते ก สวัสดี 한 Ж Я Привет Ω λ Γεια σου ¶ Ⅲ ß ñ ♻ ♥';
    TextStyle style(String? locale) => TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 40, locale: locale == null ? null : Locale(locale));
    await awaitFallbackFontsAll(
      [(ja, style('ja')), (world, style(null)), ('你好', style('zh')), ('안녕', style('ko')), ...ScriptAlley.fontRuns, ...CitySigns.fontRuns],
      firstWait: const Duration(seconds: 4),
      quiet: const Duration(milliseconds: 700),
      max: const Duration(seconds: 15),
    );
  }

  /// Call once per frame after stepping the model.
  void update(BoothModel m, double dt) {
    if (!ready) return;
    // Capture aid: --dart-define=BOOTH3D_SKIP_AT=<t> presses the operator's
    // skip at scene time t (to check what an interrupted build does).
    const skipAt = String.fromEnvironment('BOOTH3D_SKIP_AT');
    if (skipAt.isNotEmpty && !_skipped && m.t >= double.parse(skipAt)) {
      _skipped = true;
      m.skip();
    }
    sky.update(m.t, dt);
    city.update(sky, m.t);
    site.fx
      ..night = sky.night
      ..begin();
    site.camera.setFrom(director.camera.position);
    site.cameraTarget.setFrom(director.camera.target);
    site.update(m, dt, night: sky.night);
    city.gate = math.max(site.delivery.gateOpen(m.t), site.verdict.gateOpen(m.t));
    typing
      ..attach(BoothUi.of(m))
      ..update(m, dt, site.fx);
    site.fx.end();
    director
      ..typingWeight = typing.weight
      ..night = sky.night
      ..update(m, dt, site);
    site.captionFor(m, director.shotLabel);
    life.update(m, dt, camera: director.camera.position, wallWidth: site.wallWidth, night: sky.night, work: site.streetWork);
  }
}
