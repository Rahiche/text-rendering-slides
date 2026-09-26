import 'package:flutter/widgets.dart';

import '../../deck/widgets.dart';
import '../../slides/s01_title.dart';
import '../world.dart';

/// The case of 直: the talk as an investigation into why kanji render in
/// their Chinese forms, solved by following the text pipeline.
class DetectiveWorld extends World {
  const DetectiveWorld();

  @override
  String get id => 'detective';

  @override
  String get name => 'The case of 直';

  @override
  Widget title() => const TitleSlide();

  @override
  Widget section(SectionInfo s) => SectionSlide(number: s.number, title: s.title, glyphs: s.glyphs);
}
