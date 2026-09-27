import 'package:flutter/widgets.dart';

import '../../slides/s01b_title_site.dart';
import '../../deck/deck.dart';
import '../world.dart';
import 'ambient.dart';
import 'journey_map.dart';
import 'outro.dart';
import 'pipeline.dart';
import 'ruler.dart';
import 'section.dart';
import 'transition.dart';

/// Construction site: the whole deck told as one story.
class ConstructionWorld extends World {
  const ConstructionWorld();

  @override
  String get id => 'construction';

  @override
  String get name => 'Construction site';

  @override
  Widget title() => const TitleSiteSlide();

  @override
  Widget section(SectionInfo s) => ConstructionSection(info: s);

  @override
  Widget? pipeline() => const ConstructionPipeline();

  @override
  Widget? journeyMap() => const ConstructionJourneyMap();

  @override
  Widget? outro() => const ConstructionOutro();

  @override
  Widget? ambient(BuildContext context) => const ConstructionAmbient();

  @override
  Widget? ruler(DeckController controller) => ConstructionRuler(controller: controller);

  @override
  WorldTransition? get transition => constructionTransition;
}
