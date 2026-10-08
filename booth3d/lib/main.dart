import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' show SceneView;
import 'package:text_slides/booth/model.dart';
import 'package:text_slides/booth/platform.dart';
import 'package:text_slides/booth/ui/booth_ui.dart';
import 'package:text_slides/deck/theme.dart';

import 'capture_stub.dart' if (dart.library.io) 'capture_io.dart';
import 'event_badge.dart';
import 'kern_chip.dart';
import 'loading.dart';
import 'perf.dart';
import 'photo_chip.dart';
import 'picture_fx.dart';
import 'quality.dart';
import 'scene_chip.dart';
import 'talk/journey_section.dart';
import 'talk/talk_overlay.dart';
import 'world/figure.dart' show Figures;
import 'tuning.dart';
import 'works_chip.dart';
import 'world/site.dart' show Site3D;
import 'world/site_plan.dart' show CityPace;
import 'world/world.dart';

/// 名前の街 · Name City — the conference booth's name builder in 3D.
///
///   flutter run -d macos                        (Flutter GPU is enabled in Info.plist)
///   --dart-define=BOOTH3D_TIMES=10,60,120       capture frames at scene times, then quit
///   --dart-define=BOOTH3D_NAMES=Ana,田中太郎      names typed at t=0 (capture)
///   --dart-define=BOOTH3D_PERF=true             log frame times, memory and scene size
///   --dart-define=BOOTH3D_SPEED=8               start fast-forwarded (as Ctrl+Shift+↑)
///   --dart-define=BOOTH3D_TALK=2,9,15           a capture's talk: started at 2, next at 9, 15, …
///
/// F5 (or Ctrl+Shift+T) tells the talk in the city, section by section:
/// → / PageDown / Space next, ← / PageUp back, Home / End the section's
/// first and last stop, 0–6 a section (0 the title), B or . to blank the
/// screen (any key back), Esc to leave it. To
/// open straight into it: on the Mac,
///   open -a "Name City" --env NAME_CITY_TALK=1      (or =05: at section 05)
/// and on the web, the page with ?talk (or ?talk=05).
void main() => runApp(const NameCityApp());

const _times = String.fromEnvironment('BOOTH3D_TIMES');
const _names = String.fromEnvironment('BOOTH3D_NAMES');
const _tag = String.fromEnvironment('BOOTH3D_TAG', defaultValue: 'city');

/// Whether to open into the talk once the city's ready (see above).
String? get _talkAtLaunch {
  final q = Uri.base.queryParameters['talk'], env = launchEnv('NAME_CITY_TALK');
  return q ?? (env == null || env.isEmpty || env == '0' ? null : env);
}

class NameCityApp extends StatefulWidget {
  const NameCityApp({super.key});

  @override
  State<NameCityApp> createState() => _NameCityAppState();
}

class _NameCityAppState extends State<NameCityApp> with SingleTickerProviderStateMixin {
  final model = BoothModel();
  final world = World3D();
  final canvasKey = GlobalKey();
  Ticker? _ticker;
  Duration _last = Duration.zero;
  double _speed = Tuning.speed;
  late final _perf = PerfLog.enabled ? PerfLog(world, model, ratio: () => Tuning.ratio ?? _quality.ratio) : null;
  final _quality = RenderQuality(log: PerfLog.enabled ? PerfLog.line : null);
  final _watch = Stopwatch();
  bool get _capturing => _times.isNotEmpty;

  @override
  void initState() {
    super.initState();
    BoothUi.of(model).title = 'Name City'; // history, toasts, operator state
    model.pace = const CityPace(); // one letter at a time, with kerning
    HardwareKeyboard.instance.addHandler(_onKey);
    if (!_capturing) {
      BoothPlatform.keepAwake();
      if (!const bool.fromEnvironment('BOOTH_WINDOWED')) {
        WidgetsBinding.instance.addPostFrameCallback((_) => BoothPlatform.enterFullScreen());
      }
    }
    world.init().then((_) {
      if (!mounted) return;
      setState(() {});
      if (_capturing) {
        _capture();
      } else {
        _perf?.start();
        _quality
          ..attach()
          ..addListener(() => setState(() {}));
        _ticker = createTicker(_tick)..start();
        if (_talkAtLaunch case final at?) _toggleTalk(at: at);
      }
    });
  }

  void _tick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    dt = math.min(dt, 0.1) * _speed;
    final total = dt;
    while (dt > 0) {
      final step = math.min(dt, 1 / 30);
      model.update(step);
      dt -= step;
    }
    if (_perf case final perf?) {
      _watch
        ..reset()
        ..start();
      world.update(model, total);
      perf.frame(_watch.elapsedMicroseconds / 1000);
    } else {
      world.update(model, total);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _ticker?.dispose();
    _quality.dispose();
    model.dispose();
    super.dispose();
  }

  /// Operator keys, as in the 2D booth (Ctrl+Shift+…); the talk's keys.
  bool _onKey(KeyEvent e) {
    final k = HardwareKeyboard.instance;
    if (_talkKey(e)) return true;
    if (!k.isControlPressed || !k.isShiftPressed || k.isAltPressed || k.isMetaPressed) return false;
    final ui = BoothUi.of(model);
    final key = e.logicalKey;
    final void Function() action;
    if (key == LogicalKeyboardKey.keyS) {
      action = ui.operatorSkip;
    } else if (key == LogicalKeyboardKey.backspace) {
      action = ui.operatorDropLast;
    } else if (key == LogicalKeyboardKey.keyF) {
      action = BoothPlatform.toggleFullScreen;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      action = () => ui.operatorSpeed(_speed = math.min(_speed * 2, 32));
    } else if (key == LogicalKeyboardKey.arrowDown) {
      action = () => ui.operatorSpeed(_speed = math.max(_speed / 2, 1));
    } else if (key == LogicalKeyboardKey.keyH) {
      action = ui.toggleHelp;
    } else if (key == LogicalKeyboardKey.keyR) {
      action = ui.operatorReset;
    } else if (key == LogicalKeyboardKey.keyQ) {
      action = BoothPlatform.quit;
    } else if (key == LogicalKeyboardKey.keyT) {
      action = _toggleTalk;
    } else {
      return false;
    }
    if (e is KeyDownEvent) action();
    return e is! KeyUpEvent;
  }

  /// F5 starts (or ends) the talk; while it's on, the clicker's keys move
  /// along it. (Held keys don't repeat: one press, one stop.)
  bool _talkKey(KeyEvent e) {
    final key = e.logicalKey;
    final talk = world.talk;
    if (key == LogicalKeyboardKey.f5) {
      if (e is KeyDownEvent) _toggleTalk();
      return true;
    }
    if (!talk.on || HardwareKeyboard.instance.isMetaPressed) return false;
    // A clicker's blank key (B, or .): the screen to navy and back. While
    // it's blank, the other keys only bring the talk back (Esc still ends
    // it).
    if (key == LogicalKeyboardKey.keyB || key == LogicalKeyboardKey.period) {
      if (e is KeyDownEvent) talk.blank.value = !talk.blank.value;
      return true;
    }
    final void Function()? action = switch (key) {
      LogicalKeyboardKey.arrowRight || LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.pageDown || LogicalKeyboardKey.space || LogicalKeyboardKey.enter => talk.next,
      LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.arrowUp || LogicalKeyboardKey.pageUp || LogicalKeyboardKey.backspace => talk.back,
      LogicalKeyboardKey.home => talk.first,
      LogicalKeyboardKey.end => talk.last,
      LogicalKeyboardKey.escape => talk.end,
      _ => switch (_digit(key)) {
        final d? => () => talk.jump(_sectionOf(d.toString().padLeft(2, '0'))),
        null => null,
      },
    };
    if (action == null) return false;
    if (e is KeyDownEvent) {
      if (talk.blank.value && action != talk.end) {
        talk.blank.value = false;
      } else {
        action();
      }
    }
    return true;
  }

  /// The digit [key] is (top row or keypad), or null.
  static int? _digit(LogicalKeyboardKey key) {
    for (var d = 0; d <= 9; d++) {
      if (key == LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + d) || key == LogicalKeyboardKey(LogicalKeyboardKey.numpad0.keyId + d)) return d;
    }
    return null;
  }

  /// The talk's section numbered [n] ('05'); the first (the title) for
  /// '00' or none.
  int _sectionOf(String n) => world.talk.sections.indexWhere((s) => s.number == n).clamp(0, world.talk.sections.length - 1);

  /// Starts the talk (at section [at], '05'; else from the start), or ends
  /// it.
  void _toggleTalk({String? at}) {
    if (!world.ready) return;
    final talk = world.talk;
    if (talk.on) {
      talk.end();
    } else {
      // (At the booth's own pace.)
      _speed = 1;
      // (=1 or a bare ?talk: from the start; =05: at section 05.)
      final from = at == null || at.length < 2 ? 0 : _sectionOf(at);
      talk.start(world.director.camera, at: from);
    }
  }

  Future<void> _capture() async {
    final out = CaptureSink(_tag);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    model.update(1 / 30);
    for (final n in _names.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
      model.submit(n);
    }
    final targets = _times.split(',').map((s) => double.parse(s.trim())).toList()..sort();
    // The shot list: every cut (or new shot glided to), as it happens.
    final d = world.director;
    var shot = '', cuts = 0;
    for (final (i, target) in targets.indexed) {
      Site3D.lookIndex = i;
      while (model.t < target) {
        final step = math.min(1 / 30, target - model.t + 1e-9);
        model.update(step);
        world.update(model, step);
        if (d.shotLabel != shot || d.cuts != cuts) {
          out.log('SHOT ${model.t.toStringAsFixed(2)} ${d.cuts != cuts ? 'cut  ' : 'glide'} ${model.job?.phase.name ?? '-'} · ${d.shotLabel}');
          shot = d.shotLabel;
          cuts = d.cuts;
        }
        if (model.pending case final p?) await p;
        // The Glyph Works' name (its atlas, its pixels) before going on.
        if (world.site.works.pending case final p?) await p;
        if (world.talk.pending case final p?) await p;
      }
      // Let the async letter meshes and the IBL bake catch up, then render.
      for (var i = 0; i < 6; i++) {
        world.update(model, 0);
        await WidgetsBinding.instance.endOfFrame;
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      final boundary = canvasKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final j = model.job;
      // Whole seconds as t0020; fractions keep two decimals (t0020.50).
      final stamp = target == target.roundToDouble() ? target.toStringAsFixed(0).padLeft(4, '0') : target.toStringAsFixed(2).padLeft(7, '0');
      final name = 't${stamp}_${j?.phase.name ?? 'none'}.png';
      out
        ..save(name, png!.buffer.asUint8List())
        ..log('captured $name  (${j?.name} · ${j?.phase.name} ${(j?.progress(model.t) ?? 0).toStringAsFixed(2)} · ${world.director.shotLabel})');
    }
    out
      ..log(world.life.overlapReport())
      ..log(Figures.of(world.scene).overlapReport())
      ..finish();
  }

  @override
  Widget build(BuildContext context) {
    // The canvas is scaled to fit the window: render no finer than it shows.
    final size = MediaQuery.sizeOf(context);
    _quality.screen(
      native: MediaQuery.devicePixelRatioOf(context) * math.min(size.width / BP.canvas.width, size.height / BP.canvas.height),
      refreshRate: View.of(context).display.refreshRate,
    );
    final view = world.ready
        ? SceneView(
            world.scene,
            cameraBuilder: (_) => world.director.camera,
            pixelRatio: _capturing ? 1 : Tuning.ratio ?? _quality.ratio,
          )
        : const ColoredBox(color: BP.bg);
    final canvas = SizedBox.fromSize(
      size: BP.canvas,
      child: Stack(
        fit: StackFit.expand,
        children: [
          view,
          PictureFx(model: model),
          // The booth's own on screen, unless the talk is on.
          ListenableBuilder(
            listenable: world.talk,
            builder: (context, _) => world.talk.on
                ? const SizedBox.shrink()
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      BoothOverlay(model: model),
                      KernChip(model: model, caption: world.site.kern.caption),
                      PhotoChip(model: model, cue: world.site.photo.cue),
                      SceneChip(model: model, caption: world.site.caption),
                    ],
                  ),
          ),
          // (In the talk, only while its journey has the works.)
          ListenableBuilder(
            listenable: world.talk,
            builder: (context, _) => world.talk.on && world.talk.section is! JourneySection
                ? const SizedBox.shrink()
                : WorksChip(model: model, caption: world.site.works.caption),
          ),
          TalkOverlay(talk: world.talk, animate: !_capturing),
          if (!_capturing) LoadingCurtain(stage: world.stage, ready: world.ready),
          ListenableBuilder(
            listenable: world.talk,
            builder: (context, _) => world.talk.on ? const SizedBox.shrink() : const EventBadge(),
          ),
        ],
      ),
    );
    return MaterialApp(
      title: 'Name City',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: BP.bg,
        textSelectionTheme: TextSelectionThemeData(cursorColor: BP.amber, selectionColor: BP.line.withValues(alpha: 0.35)),
      ),
      home: Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle(
          style: const TextStyle(fontFamily: BP.display, fontSize: 16, color: BP.ink),
          child: ColoredBox(
            color: BP.bg,
            child: Center(
              child: FittedBox(child: RepaintBoundary(key: canvasKey, child: canvas)),
            ),
          ),
        ),
      ),
    );
  }
}
