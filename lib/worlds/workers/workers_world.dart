import 'package:flutter/widgets.dart';

import '../../deck/deck.dart';
import '../../slides/s01a_title_split.dart';
import '../world.dart';
import 'ambient.dart';
import 'floor.dart';
import 'haul.dart';
import 'outro.dart';
import 'pipeline.dart';
import 'relay_map.dart';
import 'sections.dart';

/// Easy vs hard: the whole deck told as one story. "It takes a crew": Latin
/// needs three lazy workers; every other script needs a crew that keeps
/// growing as the talk goes deeper.
class WorkersWorld extends World {
  const WorkersWorld();

  @override
  String get id => 'workers';

  @override
  String get name => 'Easy vs hard';

  @override
  Widget title() => const TitleSplitSlide();

  @override
  Widget section(SectionInfo s) => WorkersSection(info: s);

  @override
  Widget? pipeline() => const WorkersPipeline();

  @override
  Widget? journeyMap() => const WorkersJourneyMap();

  @override
  Widget? outro() => const WorkersOutro();

  @override
  Widget? ambient(BuildContext context) => const WorkersAmbient();

  @override
  Widget? ruler(DeckController controller) => WorkersFloor(controller: controller);

  @override
  WorldTransition? get transition => workersHaul;
}
