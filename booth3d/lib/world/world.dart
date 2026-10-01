import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/web_fonts.dart';
import 'package:text_slides/booth/model.dart';
import 'package:text_slides/booth/ui/booth_ui.dart';

import '../tuning.dart';
import 'city.dart';
import 'director.dart';
import 'life.dart';
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
  bool _skipped = false; // TEMP debug

  Future<void> init() async {
    await Scene.initializeStaticResources();
    scene.antiAliasingMode = Tuning.aa;
    EnvironmentMap.radianceCubeSize = Tuning.cube;
    if (kIsWeb) await _warmUpFonts();
    sky.init();
    site.init();
    typing.init();
    await city.init();
    await life.init();
    ready = true;
  }

  /// The web has no system CJK/Arabic/… fonts: Flutter downloads Noto
  /// fallbacks on first use. The city's glyph towers and signs are built once,
  /// so fetch every script they use before building (a cold page load can
  /// take a few seconds); names typed later wait for their own glyphs.
  Future<void> _warmUpFonts() async {
    const ja = 'あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん'
        'アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲンー'
        '日目月高自門凸本字語書店活字印刷喫茶文具工事中安全第一完成名前街田中山川';
    const world = 'ب ع ا مرحبا ש שלום क ह नमस्ते ก สวัสดี 한 Ж Я Привет Ω λ Γεια σου ¶ Ⅲ ß ñ ♻ ♥';
    for (final (text, locale) in [(ja, 'ja'), (world, null), ('你好', 'zh'), ('안녕', 'ko')]) {
      await awaitFallbackFonts(
        text,
        style: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 40, locale: locale == null ? null : Locale(locale)),
        firstWait: const Duration(seconds: 4),
        quiet: const Duration(milliseconds: 700),
        max: const Duration(seconds: 15),
      );
    }
  }

  /// Call once per frame after stepping the model.
  void update(BoothModel m, double dt) {
    if (!ready) return;
    const skipAt = String.fromEnvironment('BOOTH3D_SKIP_AT'); // TEMP debug
    if (skipAt.isNotEmpty && !_skipped && m.t >= double.parse(skipAt)) {
      _skipped = true;
      m.skip();
    }
    sky.update(m.t, dt);
    city.update(sky, m.t);
    site.fx.begin();
    site.camera.setFrom(director.camera.position);
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
    life.update(m, dt, camera: director.camera.position, wallWidth: site.wallWidth, night: sky.night, work: site.delivery);
  }
}
