import 'package:flutter/widgets.dart';

import '../../deck/widgets.dart';
import '../../slides/s01c_title_factory.dart';
import '../world.dart';

/// Glyph factory: the whole deck told as one story.
class FactoryWorld extends World {
  const FactoryWorld();

  @override
  String get id => 'factory';

  @override
  String get name => 'Glyph factory';

  @override
  Widget title() => const TitleFactorySlide();

  @override
  Widget section(SectionInfo s) => SectionSlide(number: s.number, title: s.title, glyphs: s.glyphs);
}
