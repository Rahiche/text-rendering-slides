import 'package:flutter/widgets.dart';

import '../../deck/deck.dart';
import '../world.dart';
import 'clue_case_open.dart';
import 'clue_codepoint.dart';
import 'clue_evidence.dart';
import 'clue_fallback.dart';
import 'clue_locl.dart';
import 'clue_motive.dart';
import 'clue_script.dart';
import 'clue_solved.dart';
import 'detective_chapters.dart';
import 'detective_chrome.dart';
import 'detective_journey.dart';
import 'detective_lineup.dart';
import 'detective_outro.dart';
import 'detective_title.dart';

/// The case of 直: the talk as an investigation into why kanji render in
/// their Chinese forms, solved by following the text pipeline.
class DetectiveWorld extends World {
  const DetectiveWorld();

  @override
  String get id => 'detective';

  @override
  String get name => 'The case of 直';

  @override
  Widget title() => const DetectiveTitle();

  @override
  Widget section(SectionInfo s) => DetectiveChapter(info: s);

  @override
  Widget? pipeline() => const DetectiveLineup();

  @override
  Widget? journeyMap() => const DetectiveJourney();

  @override
  Widget? outro() => const DetectiveOutro();

  @override
  List<SlideDef> after(String slideId) => switch (slideId) {
    'title' => [
      SlideDef(id: 'case-open', section: 'intro', title: 'The case of 直', builder: (_) => const CaseOpenSlide()),
    ],
    'string' => [
      SlideDef(id: 'clue-codepoint', section: 'basics', title: 'The code point: innocent', builder: (_) => const CodePointClueSlide()),
    ],
    'itemize' => [
      SlideDef(id: 'clue-script', section: 'basics', title: 'Script ≠ language', builder: (_) => const ScriptClueSlide()),
    ],
    'fallback' => [
      SlideDef(id: 'clue-fallback', section: 'basics', title: 'The suspect: fallback', builder: (_) => const FallbackClueSlide()),
    ],
    'shaping' => [
      SlideDef(id: 'clue-locl', section: 'basics', title: 'The accomplice: locl', builder: (_) => const LoclClueSlide()),
    ],
    'web' => [
      SlideDef(id: 'clue-motive', section: 'flutter', title: 'The motive: en_US', builder: (_) => const MotiveClueSlide()),
    ],
    'j-font' => [
      SlideDef(id: 'clue-evidence', section: 'journey', title: 'Forensic report', builder: (_) => const EvidenceClueSlide()),
    ],
    'end' => [
      SlideDef(id: 'case-solved', section: 'outro', title: 'Case solved', builder: (_) => const SolvedSlide()),
    ],
    _ => const [],
  };

  @override
  Widget? ambient(BuildContext context) => const DetectiveAmbient();

  @override
  Widget? ruler(DeckController controller) => CaseTimeline(controller: controller);

  @override
  WorldTransition? get transition => detectiveTransition;
}
