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
import 'kern_chip.dart';
import 'perf.dart';
import 'photo_chip.dart';
import 'quality.dart';
import 'tuning.dart';
import 'world/site_plan.dart' show CityPace;
import 'world/world.dart';

/// 名前の街 · Name City — the conference booth's name builder in 3D.
///
///   flutter run -d macos                        (Flutter GPU is enabled in Info.plist)
///   --dart-define=BOOTH3D_TIMES=10,60,120       capture frames at scene times, then quit
///   --dart-define=BOOTH3D_NAMES=Ana,田中太郎      names typed at t=0 (capture)
///   --dart-define=BOOTH3D_PERF=true             log frame times, memory and scene size
///   --dart-define=BOOTH3D_SPEED=8               start fast-forwarded (as Ctrl+Shift+↑)
void main() => runApp(const NameCityApp());

const _times = String.fromEnvironment('BOOTH3D_TIMES');
const _names = String.fromEnvironment('BOOTH3D_NAMES');
const _tag = String.fromEnvironment('BOOTH3D_TAG', defaultValue: 'city');

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
    BoothUi.of(model).title = (ja: '名前の街', en: 'Name City'); // history, toasts, operator state
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

  /// Operator keys, as in the 2D booth (Ctrl+Shift+…).
  bool _onKey(KeyEvent e) {
    final k = HardwareKeyboard.instance;
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
    } else {
      return false;
    }
    if (e is KeyDownEvent) action();
    return e is! KeyUpEvent;
  }

  Future<void> _capture() async {
    final out = CaptureSink(_tag);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    model.update(1 / 30);
    for (final n in _names.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
      model.submit(n);
    }
    final targets = _times.split(',').map((s) => double.parse(s.trim())).toList()..sort();
    for (final target in targets) {
      while (model.t < target) {
        final step = math.min(1 / 30, target - model.t + 1e-9);
        model.update(step);
        world.update(model, step);
        if (model.pending case final p?) await p;
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
      // Whole seconds as t0020; fractions keep a decimal (t0020.5).
      final stamp = target == target.roundToDouble() ? target.toStringAsFixed(0).padLeft(4, '0') : target.toStringAsFixed(1).padLeft(6, '0');
      final name = 't${stamp}_${j?.phase.name ?? 'none'}.png';
      out
        ..save(name, png!.buffer.asUint8List())
        ..log('captured $name  (${j?.name} · ${j?.phase.name} ${(j?.progress(model.t) ?? 0).toStringAsFixed(2)})');
    }
    out.finish();
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
          BoothOverlay(model: model),
          KernChip(model: model, caption: world.site.kern.caption),
          PhotoChip(model: model, cue: world.site.photo.cue),
        ],
      ),
    );
    return MaterialApp(
      title: '名前の街 · Name City',
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
