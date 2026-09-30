import 'package:flutter/widgets.dart';

import '../worlds/factory/factory_world.dart';
import 'slides/pipeline.dart';
import 'slides/title.dart';

/// The simplified Glyph factory talk, "Inside Flutter's Text Pipeline":
/// the same factory story with fewer, quieter slides and bigger demos.
/// Its slide list is [buildSimpleSlides].
class SimpleFactoryWorld extends FactoryWorld {
  const SimpleFactoryWorld();

  @override
  String get id => 'factory-simple';

  @override
  String get name => "Inside Flutter's Text Pipeline";

  @override
  bool get minimal => true;

  @override
  Widget title() => const TitleFactorySlide();

  @override
  Widget? pipeline() => const FactoryPipeline();

  @override
  Widget? journeyMap() => null;
}
