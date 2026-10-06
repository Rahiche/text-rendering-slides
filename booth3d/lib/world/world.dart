import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/web_fonts.dart';
import 'package:text_slides/booth/model.dart';
import 'package:text_slides/booth/ui/booth_ui.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../perf.dart' show PerfLog;
import '../talk/talk.dart';
import '../talk/talk_sections.dart';
import '../tuning.dart';
import 'city.dart';
import 'city_signs.dart' show CitySigns;
import 'director.dart';
import 'figure.dart' show Figures;
import 'figure_rig.dart' show FigureMotion;
import 'ease.dart' show approach, smooth;
import 'kit.dart' show lerp;
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

  /// The talk, told here (talk/talk.dart): its sections, in the deck's
  /// order.
  late final talk = Talk(director, talkSections(site));
  bool ready = false;
  bool _skipped = false;

  /// What's being got ready, for the loading screen: 'fonts' (the web),
  /// 'city', 'people'; [ready] once done.
  final stage = ValueNotifier<String>('');

  Future<void> init() async {
    await Scene.initializeStaticResources();
    scene.antiAliasingMode = Tuning.aa;
    scene.depthOfField
      ..quality = DepthOfFieldQuality.low
      ..maxBackgroundBlur = 18
      ..maxForegroundBlur = 14;
    EnvironmentMap.radianceCubeSize = Tuning.cube;
    if (kIsWeb) {
      stage.value = 'fonts';
      await _warmUpFonts();
    }
    stage.value = 'city';
    await Physics.ensureReady();
    if (const String.fromEnvironment('BOOTH3D_TIMES') != '') debugPrint(Physics.selfTest());
    site.physics.warmUp();
    sky.init();
    site.init();
    typing.init();
    await Future.wait([city.init(), site.alley.init(), site.vignettes.init()]);
    director.solids = city.towers.solids;
    // The street furniture: everyone keeps out of it.
    Figures.of(scene).addFixed(city.props.solids);
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
        '喫煙所 あきかん 旅 文字工場 文字列 デコード フォント シェーピング アウトライン ラスタライズ 画面 テキストパイプラインの中 次の建物 記念写真 はい、チーズ！ 字間'
        ' 地図 ウィジェット エンジンへ 解析 記録 描画 レイアウト'; // (the talk's cards)
    const world = 'ب ع ا مرحبا ש שלום क ह नमस्ते ก สวัสดี 한 Ж Я Привет Ω λ Γεια σου ¶ Ⅲ ß ñ ♻ ♥';
    TextStyle style(String? locale) => TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 40, locale: locale == null ? null : Locale(locale));
    await awaitFallbackFontsAll(
      [
        (ja, style('ja')),
        (world, style(null)),
        ('你好', style('zh')),
        ('안녕', style('ko')),
        ...ScriptAlley.fontRuns,
        ...site.vignettes.fontRuns,
        ...CitySigns.fontRuns,
        // The talk's cards (in the UI's faces, Japanese forms for Han).
        (talk.allText, style('ja')),
      ],
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
    // (A perf build says what took the time in a slow update.)
    final watch = PerfLog.enabled ? (Stopwatch()..start()) : null;
    final marks = watch == null ? null : <(String, int)>[];
    void mark(String what) => marks?.add((what, watch!.elapsedMicroseconds));

    FigureMotion.clock = m.t;
    // (A talk sets the works' clock and the camera before the site goes.)
    talk.update(m.t, dt);
    // The talk's look comes in with it (and goes with it).
    sky.talk = dt <= 0 ? (talk.on ? 1.0 : 0.0) : approach(sky.talk, talk.on ? 1.0 : 0.0, dt, 0.5);
    sky.update(m.t, dt);
    city.update(sky, m.t);
    mark('sky+city');
    site.fx
      ..night = sky.night
      ..begin();
    site.camera.setFrom(director.camera.position);
    site.cameraTarget.setFrom(director.camera.target);
    site.update(m, dt, night: sky.night);
    talk.caption();
    mark('site');
    city
      ..gate = math.max(site.delivery.gateOpen(m.t), site.verdict.gateOpen(m.t))
      ..bayGate = site.bayGateOpen(m.t);
    typing
      ..attach(BoothUi.of(m))
      ..update(m, dt, site.fx);
    site.fx.end();
    mark('typing+fx');
    director
      ..typingWeight = typing.weight
      ..night = sky.night
      ..update(m, dt, site);
    talk.framed();
    site.captionFor(m, director.shotLabel);
    // The site's people (the crew, the new manager's party on the
    // pavement, the driver): the crowd walks round them.
    final crew = site.crew.poses;
    final out = [
      for (var i = 0; i < crew.length; i++)
        if (crew[i].visible && crew[i].pos.y < 0.5) () {
          final (vx, vz) = site.crew.velocityOf(i);
          return (vm.Vector3(crew[i].pos.x + crew[i].nudgeX, 0, crew[i].pos.z + crew[i].nudgeZ), vx, vz);
        }(),
      for (final w in site.vignettes.kit.walkers) (w, 0.0, 0.0),
    ];
    mark('director');
    life.update(m, dt, camera: director.camera.position, wallWidth: site.wallWidth, night: sky.night, work: site.streetWork, others: out);
    mark('life');
    if (watch != null && marks != null && watch.elapsedMicroseconds > 12000) {
      var last = 0;
      PerfLog.line('slow update at t=${m.t.toStringAsFixed(1)} (${m.job?.phase.name}): ${[
        for (final (w, at) in marks) () {
          final d = at - last;
          last = at;
          return '$w ${(d / 1000).toStringAsFixed(1)}';
        }(),
      ].join(', ')} ms');
    }
    // The lens: close-ups go shallow, the background soft; in the talk,
    // the middle distance a little soft behind too (what it's about stands
    // out from the city).
    final c = math.max(director.closeness, sky.talk * 0.5 * smooth(48, 14, director.focus));
    scene.depthOfField
      ..enabled = Tuning.dof && c > 0.02
      ..focusDistance = director.focus
      ..fStop = lerp(16, 2.4, c);
  }
}
