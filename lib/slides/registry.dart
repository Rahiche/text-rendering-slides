import '../deck/deck.dart';
import '../deck/widgets.dart';
import 's01_title.dart';
import 's03_string.dart';
import 's04_pipeline.dart';
import 's05_itemize.dart';
import 's06_fallback.dart';
import 's07_shaping.dart';
import 's08_linebreak.dart';
import 's09_bidi.dart';
import 's10_raster.dart';
import 's12_unicode.dart';
import 's13_rules.dart';
import 's14_mixing.dart';
import 's16_engines.dart';
import 's17_chrome.dart';
import 's18_figma.dart';
import 's19_apple.dart';
import 's20_android.dart';
import 's22_cant.dart';
import 's23_can.dart';
import 's29_web.dart';
import 's30_end.dart';
import 'journey/j00_map.dart';
import 'journey/j01_widget.dart';
import 'journey/j02_string.dart';
import 'journey/j03_builder.dart';
import 'journey/j04_unicode.dart';
import 'journey/j05_font.dart';
import 'journey/j06_shape.dart';
import 'journey/j07_layout.dart';
import 'journey/j08_record.dart';
import 'journey/j09_atlas.dart';
import 'journey/j10_gpu.dart';

final slides = <SlideDef>[
  SlideDef(id: 'title', section: 'intro', title: 'Text rendering', builder: (_) => const TitleSlide()),

  // 01 — how text rendering works
  SlideDef(
    id: 'sec-basics',
    section: 'basics',
    title: 'From code points to pixels',
    builder: (_) => const SectionSlide(
      number: '01',
      title: 'From code points to pixels',
      glyphs: ['A', 'ب', 'क', '文', 'ก', '😀'],
    ),
  ),
  SlideDef(id: 'string', section: 'basics', title: 'A string ≠ text', builder: (_) => const StringSlide()),
  SlideDef(id: 'pipeline', section: 'basics', title: 'The pipeline', steps: 7, builder: (_) => const PipelineSlide()),
  SlideDef(id: 'itemize', section: 'basics', title: 'Itemize', steps: 4, builder: (_) => const ItemizeSlide()),
  SlideDef(id: 'fallback', section: 'basics', title: 'Font fallback', builder: (_) => const FallbackSlide()),
  SlideDef(id: 'shaping', section: 'basics', title: 'Shaping', builder: (_) => const ShapingSlide()),
  SlideDef(id: 'linebreak', section: 'basics', title: 'Line breaking', builder: (_) => const LineBreakSlide()),
  SlideDef(id: 'bidi', section: 'basics', title: 'Memory ≠ screen', builder: (_) => const BidiSlide()),
  SlideDef(id: 'raster', section: 'basics', title: 'Rasterization', builder: (_) => const RasterSlide()),

  // 02 — more scripts, more rules
  SlideDef(
    id: 'sec-scripts',
    section: 'scripts',
    title: 'Every script adds rules',
    builder: (_) => const SectionSlide(
      number: '02',
      title: 'Every script adds rules',
      glyphs: ['ع', 'कि', 'ปั่น', '한', '縦', '👋🏽'],
    ),
  ),
  SlideDef(id: 'unicode', section: 'scripts', title: '128 → 172,808', builder: (_) => const UnicodeSlide()),
  SlideDef(id: 'rules', section: 'scripts', title: 'Every script breaks a rule', builder: (_) => const ScriptRulesSlide()),
  SlideDef(id: 'mixing', section: 'scripts', title: 'Mixing multiplies', builder: (_) => const MixingSlide()),

  // 03 — how others do it
  SlideDef(
    id: 'sec-others',
    section: 'others',
    title: 'How others do it',
    builder: (_) => const SectionSlide(
      number: '03',
      title: 'How others do it',
      glyphs: ['Aa', 'ش', 'ह', '字'],
    ),
  ),
  SlideDef(id: 'engines', section: 'others', title: 'Five engines', steps: 3, builder: (_) => const EnginesSlide()),
  SlideDef(id: 'chrome', section: 'others', title: 'Chrome', builder: (_) => const ChromeSlide()),
  SlideDef(id: 'figma', section: 'others', title: 'Figma', builder: (_) => const FigmaSlide()),
  SlideDef(id: 'apple', section: 'others', title: 'macOS · Core Text', builder: (_) => const AppleSlide()),
  SlideDef(id: 'android', section: 'others', title: 'Android · Minikin', builder: (_) => const AndroidSlide()),

  // 04 — Flutter's trade-off
  SlideDef(
    id: 'sec-flutter',
    section: 'flutter',
    title: "Flutter's trade-off",
    builder: (_) => const SectionSlide(
      number: '04',
      title: "Flutter's trade-off",
      glyphs: ['✕', '✓'],
    ),
  ),
  SlideDef(id: 'cant', section: 'flutter', title: 'Not in Flutter', builder: (_) => const CantSlide()),
  SlideDef(id: 'can', section: 'flutter', title: 'Only in Flutter', steps: 5, builder: (_) => const CanSlide()),
  SlideDef(id: 'web', section: 'flutter', title: 'On the web', builder: (_) => const WebSlide()),

  // 05 — one word's journey
  SlideDef(
    id: 'sec-journey',
    section: 'journey',
    title: "One word's journey",
    builder: (_) => const SectionSlide(
      number: '05',
      title: "One word's journey",
      glyphs: ['F', '→', '#9', '→', '▦'],
    ),
  ),
  SlideDef(id: 'j-map', section: 'journey', title: "One word's journey", builder: (_) => const JMapSlide()),
  SlideDef(id: 'j-widget', section: 'journey', title: 'Text()', builder: (_) => const JWidgetSlide()),
  SlideDef(id: 'j-string', section: 'journey', title: 'A Dart String', builder: (_) => const JStringSlide()),
  SlideDef(id: 'j-builder', section: 'journey', title: 'Into the engine', builder: (_) => const JBuilderSlide()),
  SlideDef(id: 'j-unicode', section: 'journey', title: 'Unicode analysis', builder: (_) => const JUnicodeSlide()),
  SlideDef(id: 'j-font', section: 'journey', title: 'Find the glyphs', builder: (_) => const JFontSlide()),
  SlideDef(id: 'j-shape', section: 'journey', title: 'Shape', builder: (_) => const JShapeSlide()),
  SlideDef(id: 'j-layout', section: 'journey', title: 'Lay out', builder: (_) => const JLayoutSlide()),
  SlideDef(id: 'j-record', section: 'journey', title: 'Record', builder: (_) => const JRecordSlide()),
  SlideDef(id: 'j-atlas', section: 'journey', title: 'Rasterize', builder: (_) => const JAtlasSlide()),
  SlideDef(id: 'j-gpu', section: 'journey', title: 'Draw', builder: (_) => const JGpuSlide()),
  SlideDef(id: 'end', section: 'outro', title: 'The trade-off', builder: (_) => const EndSlide()),
];
