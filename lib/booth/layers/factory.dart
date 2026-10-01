import 'package:flutter/rendering.dart';

import '../layer.dart';
import '../model.dart';
import 'factory_draw.dart';
import 'factory_plan.dart';

/// The glyph factory 「グリフ工場 · Glyph Works」: the text pipeline in
/// miniature, on the left of the booth scene.
///
/// Each name arrives by pneumatic tube into the hopper, which reads its code
/// points; a crate carries it through itemize (script runs), fonts, shape
/// (the press) and into the raster kiln, while the screen above the line
/// explains each step. The kiln bakes the name's real pixels and sends them
/// out in pallets of bricks along the belt, timed to the shared brick
/// schedule so each pallet reaches the crane's pickup exactly when the site
/// takes it over. During the build the line keeps producing (a crate for
/// every pallet) and the screen replays the lesson; after the demolition the
/// rubble comes back through the recycling bin and up the bucket elevator
/// into the hopper.
///
/// Everything is drawn from the scene time and the model; the little state
/// it needs (the belt's banked travel, a name cut short, the last load of
/// rubble) lives in [FactorySystem].
class FactoryLayer extends BoothLayer {
  FactoryLayer() : _sys = FactorySystem() {
    _scene = FactoryScene(_sys);
  }

  final FactorySystem _sys;
  late final FactoryScene _scene;

  @override
  BoothSystem get system => _sys;

  @override
  CustomPainter painter(BoothModel m) => _FactoryPainter(m, _scene);

  @override
  void dispose() => _scene.dispose();
}

class _FactoryPainter extends CustomPainter {
  _FactoryPainter(this.m, this.scene) : super(repaint: m);

  final BoothModel m;
  final FactoryScene scene;

  @override
  void paint(Canvas canvas, Size size) => scene.paint(canvas, m);

  @override
  bool shouldRepaint(_FactoryPainter old) => false;
}
