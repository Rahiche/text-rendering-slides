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
import 'ui/board.dart';
import 'ui/input.dart';

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
  /// F full screen, ↑/↓ fast-forward.
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    final k = HardwareKeyboard.instance;
    if (!(k.isControlPressed && k.isShiftPressed)) return false;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.keyS) {
      widget.model.skip();
    } else if (key == LogicalKeyboardKey.backspace) {
      widget.model.dropLast();
    } else if (key == LogicalKeyboardKey.keyM) {
      // Factory ↔ Workshop, from the next name on.
      final m = widget.model;
      m.mode = m.mode == BuildMode.bricks ? BuildMode.craft : BuildMode.bricks;
    } else if (key == LogicalKeyboardKey.keyF) {
      BoothPlatform.toggleFullScreen();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _speed = math.min(_speed * 2, 32);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _speed = math.max(_speed / 2, 1);
    } else {
      return false;
    }
    return true;
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
                  Positioned.fromRect(
                    rect: BL.board,
                    child: BoothBoard(model: m),
                  ),
                  Positioned.fromRect(
                    rect: BL.input,
                    child: NameInput(model: m),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
