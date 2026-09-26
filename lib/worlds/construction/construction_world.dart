import 'package:flutter/widgets.dart';

import '../../deck/widgets.dart';
import '../../slides/s01b_title_site.dart';
import '../world.dart';

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
  Widget section(SectionInfo s) => SectionSlide(number: s.number, title: s.title, glyphs: s.glyphs);
}
