import 'package:flutter/rendering.dart';

import 'model.dart';

/// One slice of the booth scene. Layers are painted back to front in the
/// order the scene lists them; foregrounds after all backgrounds.
abstract class BoothLayer {
  /// A simulation stepped with the model (falling bricks, the crane…).
  BoothSystem? get system => null;

  /// Painted in order, behind later layers.
  CustomPainter painter(BoothModel m);

  /// Optional pass painted after every layer's [painter] (e.g. pedestrians
  /// walking in front of the construction site).
  CustomPainter? foreground(BoothModel m) => null;

  /// Free resources (cached text, images).
  void dispose() {}
}
