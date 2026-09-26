import 'package:flutter/widgets.dart';

import '../../deck/widgets.dart';
import '../../slides/s01a_title_split.dart';
import '../world.dart';

/// Easy vs hard: the whole deck told as one story.
class WorkersWorld extends World {
  const WorkersWorld();

  @override
  String get id => 'workers';

  @override
  String get name => 'Easy vs hard';

  @override
  Widget title() => const TitleSplitSlide();

  @override
  Widget section(SectionInfo s) => SectionSlide(number: s.number, title: s.title, glyphs: s.glyphs);
}
