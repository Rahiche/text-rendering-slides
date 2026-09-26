import 'package:flutter/widgets.dart';

import '../deck/widgets.dart';
import '../slides/s01_title.dart';
import 'world.dart';

/// The original blueprint deck: no story layer.
class ClassicWorld extends World {
  const ClassicWorld();

  @override
  String get id => 'classic';

  @override
  String get name => 'Blueprint';

  @override
  Widget title() => const TitleSlide();

  @override
  Widget section(SectionInfo s) => SectionSlide(number: s.number, title: s.title, glyphs: s.glyphs);
}
