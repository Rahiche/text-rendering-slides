import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../deck/theme.dart';
import 'layer.dart';
import 'layers/ambient.dart';
import 'layers/factory.dart';
import 'layers/site.dart';
import 'layers/workshop.dart';
import 'layout.dart';
import 'model.dart';
import 'platform.dart';
import 'ui/booth_ui.dart';

/// The booth loop: the city, the factory and the construction site on one
/// 1600×900 canvas scaled to the screen, plus the name input.
///
/// [live] drives the model from a ticker; capture mode steps it instead.
class BoothScene extends StatefulWidget {
  const BoothScene({super.key, required this.model, this.canvasKey, this.live = true});

  final BoothModel model;
  final GlobalKey? canvasKey;
  final bool live;

  @override
  State<BoothScene> createState() => _BoothSceneState();
}

class _BoothSceneState extends State<BoothScene> with SingleTickerProviderStateMixin {
  // Back to front. The city is always there; the rest depends on how the
  // current name is being built.
  final _ambient = AmbientLayer();
  final Map<BuildMode, List<BoothLayer>> _byMode = {
    BuildMode.bricks: [FactoryLayer(), SiteLayer()],
    BuildMode.craft: [WorkshopLayer()],
  };
  BuildMode? _active;
  List<BoothLayer> _layers = const [];
  List<CustomPainter> _painters = const [];
  List<CustomPainter> _fronts = const [];
  Ticker? _ticker;
  Duration _last = Duration.zero;

  /// Operator fast-forward (Ctrl+Shift+↑/↓).
  double _speed = 1;

  @override
  void initState() {
    super.initState();
    final m = widget.model;
    _activate(m.job?.mode ?? m.mode);
    m.addListener(_onModel);
    if (widget.live) {
      _ticker = createTicker((elapsed) {
        var dt = (elapsed - _last).inMicroseconds / 1e6;
        _last = elapsed;
        dt = math.min(dt, 0.1) * _speed;
        // Big fast-forward steps are split so simulations stay stable.
        while (dt > 0) {
          final step = math.min(dt, 1 / 30);
          m.update(step);
          dt -= step;
        }
      })..start();
    }
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  /// Shows the layers for [mode] and steps only their simulations.
  void _activate(BuildMode mode) {
    if (_active == mode) return;
    final m = widget.model;
    for (final l in _layers) {
      if (l.system case final s?) m.systems.remove(s);
    }
    _active = mode;
    _layers = [_ambient, ..._byMode[mode]!];
    for (final l in _layers) {
      if (l.system case final s?) m.systems.add(s);
    }
    _painters = [for (final l in _layers) l.painter(m)];
    _fronts = [for (final l in _layers) ?l.foreground(m)];
  }

  void _onModel() {
    final mode = widget.model.job?.mode;
    if (mode != null && mode != _active) setState(() => _activate(mode));
  }

  @override
  void dispose() {
    widget.model.removeListener(_onModel);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _ticker?.dispose();
    _ambient.dispose();
    for (final ls in _byMode.values) {
      for (final l in ls) {
        l.dispose();
      }
    }
    super.dispose();
  }

  /// Operator shortcuts (Ctrl+Shift+…): S skip, ⌫ drop the last queued name,
  /// F full screen, ↑/↓ fast-forward, H help, R reset today's count (press
  /// twice), M Name Factory ↔ Name Workshop (from the next name). Only exactly these combinations are taken: everything else
  /// (typing, the input method's own keys) goes on to the name input.
  bool _onKey(KeyEvent e) {
    final k = HardwareKeyboard.instance;
    if (!k.isControlPressed || !k.isShiftPressed || k.isAltPressed || k.isMetaPressed) return false;
    final ui = BoothUi.of(widget.model);
    final key = e.logicalKey;
    final void Function() action;
    if (key == LogicalKeyboardKey.keyS) {
      action = ui.operatorSkip;
    } else if (key == LogicalKeyboardKey.backspace) {
      action = ui.operatorDropLast;
    } else if (key == LogicalKeyboardKey.keyM) {
      action = ui.operatorMode;
    } else if (key == LogicalKeyboardKey.keyQ) {
      action = BoothPlatform.quit;
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
    } else {
      return false;
    }
    if (e is KeyDownEvent) action();
    // Held down, a combination repeats: swallow the repeats too, or e.g.
    // Ctrl+H / Ctrl+⌫ would reach the text field and delete what was typed.
    return e is! KeyUpEvent;
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    return ColoredBox(
      color: BP.bg,
      child: Center(
        child: FittedBox(
          child: RepaintBoundary(
            key: widget.canvasKey,
            child: SizedBox.fromSize(
              size: BL.size,
              child: Stack(
                children: [
                  for (final p in _painters) Positioned.fill(child: CustomPaint(painter: p)),
                  for (final p in _fronts) Positioned.fill(child: CustomPaint(painter: p)),
                  // The UI (lib/booth/ui/): board, input, tally, help.
                  Positioned.fill(child: BoothOverlay(model: m)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
