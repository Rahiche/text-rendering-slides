import '../deck/deck.dart';
import '../worlds/factory/factory_outro.dart';
import '../worlds/world.dart';
import 'slides/can.dart';
import 'slides/cant.dart';
import 'slides/end.dart';
import 'slides/engines.dart';
import 'slides/figma.dart';
import 'slides/itemize.dart';
import 'slides/journey/atlas.dart';
import 'slides/journey/font.dart';
import 'slides/journey/gpu.dart';
import 'slides/journey/layout.dart';
import 'slides/journey/shape.dart';
import 'slides/journey/widget.dart';
import 'slides/linebreak.dart';
import 'slides/pipeline.dart';
import 'slides/raster.dart';
import 'slides/rules.dart';
import 'slides/shaping.dart';
import 'slides/string.dart';
import 'slides/title.dart';
import 'slides/unicode.dart';

const simpleSections = [
  SectionInfo(
    index: 0,
    number: '01',
    id: 'basics',
    title: 'From code points to pixels',
    glyphs: ['A', 'ب', 'क', '文', 'ก', '😀'],
  ),
  SectionInfo(
    index: 1,
    number: '02',
    id: 'scripts',
    title: 'Every script adds rules',
    glyphs: ['ع', 'कि', 'ปั่น', '한', '縦', '👋🏽'],
  ),
  SectionInfo(
    index: 2,
    number: '03',
    id: 'others',
    title: 'How others do it',
    glyphs: ['Aa', 'ش', 'ह', '字'],
  ),
  SectionInfo(
    index: 3,
    number: '04',
    id: 'flutter',
    title: "Flutter's trade-off",
    glyphs: ['✕', '✓'],
  ),
  SectionInfo(
    index: 4,
    number: '05',
    id: 'journey',
    title: "One word's journey",
    glyphs: ['F', '→', '#9', '→', '▦'],
  ),
];

/// "Inside Flutter's Text Pipeline": the simplified Glyph factory deck.
List<SlideDef> buildSimpleSlides(World w) {
  SlideDef section(int i) => SlideDef(
    id: 'sec-${simpleSections[i].id}',
    section: simpleSections[i].id,
    title: simpleSections[i].title,
    builder: (_) => w.section(simpleSections[i]),
  );
  return [
    SlideDef(
      id: 'title',
      section: 'intro',
      title: "Inside Flutter's Text Pipeline",
      builder: (_) => const TitleFactorySlide(),
    ),

    // 01 — how text rendering works
    section(0),
    SlideDef(
      id: 'string',
      section: 'basics',
      title: 'A string ≠ text',
      builder: (_) => const StringSlide(),
    ),
    SlideDef(
      id: 'pipeline',
      section: 'basics',
      title: 'The pipeline',
      steps: 7,
      builder: (_) => const FactoryPipeline(),
    ),
    SlideDef(
      id: 'itemize',
      section: 'basics',
      title: 'Itemize',
      steps: 4,
      builder: (_) => const ItemizeSlide(),
    ),
    SlideDef(
      id: 'shaping',
      section: 'basics',
      title: 'Shaping',
      builder: (_) => const ShapingSlide(),
    ),
    SlideDef(
      id: 'linebreak',
      section: 'basics',
      title: 'Line breaking',
      builder: (_) => const LineBreakSlide(),
    ),
    SlideDef(
      id: 'raster',
      section: 'basics',
      title: 'Rasterization',
      builder: (_) => const RasterSlide(),
    ),

    // 02 — more scripts, more rules
    section(1),
    SlideDef(
      id: 'unicode',
      section: 'scripts',
      title: '128 → 172,808',
      builder: (_) => const UnicodeSlide(),
    ),
    SlideDef(
      id: 'rules',
      section: 'scripts',
      title: 'Every script breaks a rule',
      builder: (_) => const ScriptRulesSlide(),
    ),

    // 03 — how others do it
    section(2),
    SlideDef(
      id: 'engines',
      section: 'others',
      title: 'Five engines',
      steps: 3,
      builder: (_) => const EnginesSlide(),
    ),
    SlideDef(id: 'figma', section: 'others', title: 'Figma', builder: (_) => const FigmaSlide()),

    // 04 — Flutter's trade-off
    section(3),
    SlideDef(
      id: 'cant',
      section: 'flutter',
      title: 'Not in Flutter',
      builder: (_) => const CantSlide(),
    ),
    SlideDef(
      id: 'can',
      section: 'flutter',
      title: 'Only in Flutter',
      steps: 5,
      builder: (_) => const CanSlide(),
    ),

    // 05 — one word's journey through Flutter
    section(4),
    SlideDef(
      id: 'j-widget',
      section: 'journey',
      title: 'Text()',
      builder: (_) => const JWidgetSlide(),
    ),
    SlideDef(
      id: 'j-font',
      section: 'journey',
      title: 'Find the glyphs',
      builder: (_) => const JFontSlide(),
    ),
    SlideDef(
      id: 'j-shape',
      section: 'journey',
      title: 'Shape',
      builder: (_) => const JShapeSlide(),
    ),
    SlideDef(
      id: 'j-layout',
      section: 'journey',
      title: 'Lay out',
      builder: (_) => const JLayoutSlide(),
    ),
    SlideDef(
      id: 'j-atlas',
      section: 'journey',
      title: 'Rasterize',
      builder: (_) => const JAtlasSlide(),
    ),
    SlideDef(id: 'j-gpu', section: 'journey', title: 'Draw', builder: (_) => const JGpuSlide()),

    SlideDef(id: 'end', section: 'outro', title: 'The trade-off', builder: (_) => const EndSlide()),
    SlideDef(
      id: 'outro',
      section: 'outro',
      title: 'Thank you',
      builder: (_) => const FactoryOutro(),
    ),
  ];
}
