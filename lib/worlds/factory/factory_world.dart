import 'package:flutter/widgets.dart';

import '../../deck/deck.dart';
import '../../slides/s01c_title_factory.dart';
import '../world.dart';
import 'factory_ambient.dart';
import 'factory_halls.dart';
import 'factory_journey.dart';
import 'factory_outro.dart';
import 'factory_pipeline.dart';
import 'factory_ruler.dart';
import 'factory_transition.dart';

/// Glyph factory: the whole talk is a guided tour of a factory that turns
/// code points into pixels. The five sections are halls on the tour, the
/// ruler is the conveyor under every slide, and slides ride in as panels.
class FactoryWorld extends World {
  const FactoryWorld();

  @override
  String get id => 'factory';

  @override
  String get name => 'Glyph factory';

  @override
  Widget title() => const TitleFactorySlide();

  @override
  Widget section(SectionInfo s) => FactoryHall(info: s);

  @override
  Widget? pipeline() => const FactoryPipeline();

  @override
  Widget? journeyMap() => const FactoryJourneyMap();

  @override
  Widget? outro() => const FactoryOutro();

  @override
  Widget? ambient(BuildContext context) => const FactoryAmbient();

  @override
  Widget? ruler(DeckController controller) => FactoryRuler(controller: controller);

  @override
  WorldTransition? get transition => factoryTransition;
}
