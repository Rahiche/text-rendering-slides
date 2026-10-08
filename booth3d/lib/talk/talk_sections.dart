import 'package:vector_math/vector_math.dart' as vm;

import '../world/shot.dart';
import '../world/site.dart';
import 'city_section.dart';
import 'journey_section.dart';
import 'talk_section.dart';

/// The talk's sections, in the deck's order (lib/slides/registry.dart):
/// the title, 01 from code points to pixels, 02 every script adds rules,
/// 03 how others do it, 04 Flutter's trade-off, 05 one word's journey, 06
/// unsolved → solved, and the end. Each stop is the place in the city that
/// shows it, its card the deck's slide in a few lines, with its numbers.
List<TalkSection> talkSections(Site3D site) {
  CitySection section(String number, String title, List<String> glyphs, List<CityStop> stops) => CitySection(
    number: number,
    title: title,
    glyphs: glyphs,
    cityStops: stops,
    vignettes: site.vignettes,
    alley: site.alley,
    fx: site.fx,
    glyphShapes: () => site.scriptShapes,
  );

  return [
    // (Its eight scripts are in the air round the title: the scene 'scripts'.)
    section('', 'Text rendering', const [], [
      CityStop(
        'title',
        const TalkCard(
          'Text rendering',
          'from code points to pixels · and how Flutter does it',
          [
            FactLetters('one word, eight scripts', [
              ('Text', 'latin', true),
              ('نص', 'arabic', false),
              ('टेक्स्ट', 'devanagari', false),
              ('文字', 'japanese', false),
              ('טקסט', 'hebrew', false),
              ('ข้อความ', 'thai', false),
              ('텍스트', 'korean', false),
              ('Текст', 'cyrillic', false),
            ]),
            FactRow('flutter / text', 'told in Name City, a stop a place', accent: true),
          ],
          true,
        ),
        [CityBeat.scene('scripts', hold: 10.0, fly: 6.0, lead: 4.6, shift: 0, cardAt: 1e9, chapter: true)],
      ),
    ]),
    section('01', 'From code points to pixels', const ['A', 'ب', 'क', '文', 'ก', '😀'], [
      CityStop(
        'intro',
        const TalkCard(
          'From code points to pixels',
          'A string goes in, pixels come out. In between, every step of the way is a place in this city.',
          [
            FactLetters('', [('A', '', false), ('ب', '', false), ('क', '', false), ('文', '', false), ('ก', '', false), ('😀', '', false)]),
          ],
          true,
        ),
        [
          CityBeat.at(
            _cityMap,
            fly: 3.0,
            shift: 0.3,
            cardAt: 2.8,
            chapter: true,
            pins: [
              _pin(6.6, 2.4, 15.2, 'STRING'),
              _pin(28.4, 6.6, 29.2, 'ITEMIZE'),
              _pin(-6.6, 3.6, 48.5, 'FALLBACK'),
              _pin(6.4, 3.0, 46.8, 'SHAPING'),
              _pin(1.0, 3.4, 66.6, 'LINES'),
              _pin(-28.4, 6.6, 11.2, 'BIDI'),
              _pin(-9.0, 1.6, 79.0, 'RASTER'),
            ],
          ),
        ],
      ),
      CityStop(
        'pipeline',
        const TalkCard(
          'The pipeline',
          'Seven stages, each owned by a different library: code points become runs, fonts, glyphs, '
              'lines, positions, and finally pixels. Each is a stop in this city, in this order.',
          [
            FactCode(
              '01 string    unicode\n02 itemize   ICU\n03 fallback  font manager\n04 shaping   HarfBuzz\n'
              '05 lines     ICU · UAX #14\n06 bidi      ICU · layout\n07 raster    Skia · GPU',
            ),
          ],
        ),
        // (Still over the city: its stops numbered in the order a string
        // goes through them.)
        [CityBeat.at(_cityMap, fly: 1.0, shift: 0.3, pins: _stages)],
      ),
      CityStop(
        'string',
        const TalkCard(
          'A string ≠ text',
          "Dart's String.length counts UTF-16 units, not what you see. The family is one grapheme: "
              'four people joined by three zero-width joiners. Let go, it is four.',
          [
            // (What a reader sees, code points, UTF-16 units, UTF-8 bytes.)
            FactTable(
              ['', '.characters', '.runes', '.length', 'utf8.encode'],
              [
                ['e\u0301', '1', '2', '2', '3'],
                ['\u{1F1EF}\u{1F1F5}', '1', '2', '4', '8'],
                ['\u{1F44D}\u{1F3FD}', '1', '2', '4', '8'],
                ['\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}', '1', '7', '11', '25'],
                ['Flutter', '7', '7', '7', '7'],
              ],
              lit: 1,
            ),
          ],
        ),
        [CityBeat.scene('family', hold: 6.1, fly: 2.6, pull: 1.1), CityBeat.scene('family', from: 6.1, hold: 10.75, fly: 0.8, pull: 1.1)],
      ),
      CityStop(
        'itemize',
        const TalkCard(
          'Itemize',
          'Before shaping, the string is cut where the script changes. Each run gets one script, one '
              'direction and one font; every later stage works on runs.',
          [
            FactLetters('Hi مرحبا 世界 👋 → 4 runs', [('Hi', 'Latin →', true), ('مرحبا', 'Arabic ←', false), ('世界', 'Han →', false), ('👋', 'Emoji', false)]),
            FactRow('fonts', 'Space Grotesk · Noto Kufi Arabic · CJK · Emoji'),
          ],
        ),
        [CityBeat.scene('itemize', hold: 8.6, fly: 3.0, pull: 1.7, shift: 0.38)],
      ),
      CityStop(
        'fallback',
        const TalkCard(
          'Font fallback',
          "Fonts are asked in order, one character at a time: the app's, then the platform's. When "
              'none has it, .notdef draws tofu: □.',
          [
            FactRow('A', 'Space Grotesk · 1 lookup'),
            FactRow('ب', 'Noto Kufi Arabic · 2 lookups'),
            FactRow('字', 'system CJK · 3 lookups'),
            FactRow('😀', 'system emoji · 4 lookups'),
            FactRow('U+0378', '.notdef → □ tofu', accent: true),
          ],
        ),
        [CityBeat.scene('tofu', hold: 16.0, fly: 2.8, pull: 1.3, shift: 0.36)],
      ),
      CityStop(
        'shaping',
        const TalkCard(
          'Shaping',
          'HarfBuzz turns code points into glyph ids and positions, and not one for one: letters join, '
              'merge, shift, swap places or collapse into one.',
          [
            FactRow('join', '\u2067ك ت ا ب\u2069 → \u2067كتاب\u2069'),
            FactRow('ligature', 'f + i → ﬁ    - + > → ->', accent: true),
            FactRow('kerning', 'AVATAR To'),
            FactRow('reorder', 'क + ि → कि'),
            FactRow('emoji ZWJ', '5 code points → 1 glyph'),
          ],
        ),
        [CityBeat.scene('forge', fly: 2.4, shift: 0.52)],
      ),
      CityStop(
        'lines',
        const TalkCard(
          'Line breaking',
          'Greedy: fill each line up to maxWidth, then start the next. Where a line may break depends '
              'on the script.',
          [
            FactRow('spaces', 'UAX #14 break opportunities', example: 'the|quick|brown|fox'),
            FactRow('Thai', 'no spaces: ICU dictionary', example: 'สวัสดี|ครับ'),
            FactRow('CJK', 'almost anywhere, but 。 never starts a line (kinsoku)', accent: true, example: '行|頭|に|来|ま|せ|ん。'),
            FactRow('too long', 'an emergency break inside the word', example: 'Donaudampfsch|ifffahrt'),
          ],
        ),
        // (The tram's paragraph; then a phone turned on its side: the same
        // words, a new maxWidth, new lines.)
        [
          // (Back at the end for the whole train: all three lines beside
          // the card.)
          CityBeat.scene(
            'tram',
            hold: 11.6,
            fly: 3.0,
            pull: 1.5,
            shift: 0.38,
            // (From the park's path, clear of the cable car.)
            view: Shot(vm.Vector3(0, 4.5, -22), vm.Vector3(-6.94, 1.0, 0), fov: 27, drift: 0.3),
            viewFrom: 9.8,
          ),
          CityBeat.scene('phones', hold: 7.0, fly: 3.0),
        ],
      ),
      CityStop(
        'bidi',
        const TalkCard(
          'Memory ≠ screen',
          'Text is stored in typing order; the bidi algorithm reorders it for display. A right-to-left '
              'run is reversed, its number stays left to right.',
          [
            FactRow('memory', '\u202DH i ␠ ש ל ו ם ␠ 2 0 2 6 !\u202C'),
            FactRow('screen', '\u202DH i ␠ 2 0 2 6 ␠ ם ו ל ש !\u202C', accent: true),
            FactRow('so', 'index i in memory ≠ position i on screen'),
          ],
        ),
        [CityBeat.scene('bidi', hold: 9.5, fly: 3.0, shift: 0.36)],
      ),
      CityStop(
        'raster',
        const TalkCard(
          'Rasterization',
          'Glyphs are outlines. At a small size, each pixel is shaded by how much of it the outline '
              'covers.',
          [
            FactRow('aliased', 'on if coverage ≥ 0.5'),
            FactRow('grayscale', 'coverage → grey · Flutter / Impeller', accent: true),
            FactRow('subpixel', 'R G B thirds · macOS: off since 10.14'),
          ],
        ),
        [CityBeat.scene('farm', hold: 12.0, fly: 3.0)],
      ),
    ]),
    section('02', 'Every script adds rules', const ['ع', 'कि', 'ปั่น', '한', '縦', '👋🏽'], [
      CityStop(
        'intro',
        const TalkCard(
          'Every script adds rules',
          'Latin lets you assume a lot. Every other script breaks one of those assumptions, and a real '
              'paragraph mixes them.',
          [
            FactLetters('', [('ع', '', false), ('कि', '', false), ('ปั่น', '', false), ('한', '', false), ('縦', '', false), ('👋🏽', '', false)]),
          ],
          true,
        ),
        [
          CityBeat.at(
            talkShot(-45, 45, -20, 6, 8, 60, 56, drift: 0.9),
            fly: 3.0,
            shift: 0.22,
            cardAt: 2.8,
            chapter: true,
            pins: [
              _pin(0, 3.4, 26.06, 'SCRIPT ALLEY'),
              _pin(32.2, 34, 90.4, 'UNICODE'),
              _pin(-28.4, 6.6, 25.2, 'LOCALE'),
            ],
          ),
        ],
      ),
      CityStop(
        'unicode',
        const TalkCard(
          '128 → 172,808',
          "From ASCII's 128 characters to Unicode 18's 172,808, across 170+ scripts, and still only "
              '15.5% of the codespace.',
          [
            FactRow('1963 · ASCII', '128'),
            FactRow('1991 · Unicode 1', '~7,000'),
            FactRow('2010 · Unicode 6', '109,449 · emoji arrive'),
            FactRow('2026 · Unicode 18', '172,808', accent: true),
            FactRow('codespace', '15.5% of 1,114,112'),
          ],
        ),
        [CityBeat.scene('tower', hold: 12.0, fly: 3.4)],
      ),
      CityStop(
        'alley',
        const TalkCard(
          'Every script breaks a rule',
          'Each script breaks an assumption Latin lets you make. Script Alley has a stall for six of '
              'them.',
          [
            FactRow('direction', 'right to left · Hebrew'),
            FactRow('shape', 'by its neighbours · Arabic'),
            FactRow('order', 'stored after, drawn before · Devanagari'),
            FactRow('marks', 'stacked · Thai'),
            FactRow('syllables', 'built into blocks · Hangul'),
            FactRow('lines', 'top to bottom · Japanese', accent: true),
          ],
        ),
        [CityBeat.at(talkShot(0.9, 2.2, 22.8, -0.3, 2.0, 35.5, 52, drift: 0.6), fly: 2.6)],
      ),
      CityStop(
        'rtl',
        const TalkCard(
          'Right to left',
          'שלום is written from the right: index 0 is the rightmost letter, and the caret moves left '
              'as you type.',
          [
            FactLetters('memory', [('ש', '0', true), ('ל', '1', false), ('ו', '2', false), ('ם', '3', false)]),
            FactRow('screen', 'שלום', accent: true),
            FactRow('also', 'Arabic \u2067مرحبا\u2069 · Persian \u2067سلام\u2069 · Urdu \u2067اردو\u2069'),
          ],
        ),
        [CityBeat.stall(0)],
      ),
      CityStop(
        'joining',
        const TalkCard(
          'Joining',
          'An Arabic letter takes a shape for its neighbours: isolated, initial, medial or final.',
          [
            FactRow('letters', '\u2067ب ي ت\u2069'),
            FactRow('joined', 'بيت', accent: true),
            FactLetters('one letter, four forms', [('ع', 'isol', false), ('عـ', 'init', false), ('ـعـ', 'medi', true), ('ـع', 'fina', false)]),
          ],
        ),
        [CityBeat.stall(1)],
      ),
      CityStop(
        'reorder',
        const TalkCard(
          'Reordering',
          'The Devanagari vowel sign ि is stored after its consonant, but drawn before it.',
          [
            FactLetters('memory', [('क', 'U+0915', false), ('ि', 'U+093F', true)]),
            FactRow('screen', 'कि', accent: true),
            FactLetters('the same in three scripts', [('कि', 'Hindi', true), ('কি', 'Bengali', false), ('ਕਿ', 'Punjabi', false)]),
          ],
        ),
        [CityBeat.stall(2)],
      ),
      CityStop(
        'stacking',
        const TalkCard(
          'Stacking',
          "Thai marks stack on their letter: a vowel above it, a tone mark above that, raised so they "
              "don't collide. And no spaces between words: a dictionary finds them.",
          [
            FactLetters('ป + ั + ่', [('ป', 'base', false), ('ั', 'vowel', false), ('่', 'tone', true)]),
            FactRow('result', 'ปั่น', accent: true),
            FactRow('also', 'Vietnamese ệ = e + \u25CC\u0302 + \u25CC\u0323'),
          ],
        ),
        [CityBeat.stall(3)],
      ),
      CityStop(
        'blocks',
        const TalkCard(
          'Composition',
          'Hangul letters (jamo) are composed into one square syllable block.',
          [
            FactLetters('ㅎ + ㅏ + ㄴ', [('ㅎ', '', false), ('ㅏ', '', false), ('ㄴ', '', false)]),
            FactRow('syllable', '한 · U+D55C', accent: true),
            FactLetters('한글: two blocks, six letters', [('한', 'ㅎ ㅏ ㄴ', true), ('글', 'ㄱ ㅡ ㄹ', false)]),
          ],
        ),
        [CityBeat.stall(4)],
      ),
      CityStop(
        'vertical',
        const TalkCard(
          'Vertical',
          'Japanese can be set top to bottom, its columns right to left.',
          [
            FactRow('reads', 'down each column, the columns right to left'),
            FactRow('also', 'Chinese · Mongolian (its columns left to right)'),
            FactRow('in Flutter', 'not built in (section 04)', accent: true),
          ],
        ),
        [CityBeat.stall(5)],
      ),
      CityStop(
        'locale',
        const TalkCard(
          'One code point, two glyphs',
          'Han characters are unified: Japanese and Chinese share a code point but draw it differently. '
              'The locale picks the font.',
          [
            FactLetters('ja · zh-Hans', [('直', 'U+76F4', true), ('角', 'U+89D2', false), ('骨', 'U+9AA8', false), ('写', 'U+5199', false)]),
            FactRow('fix', "locale: Locale('ja')", accent: true),
          ],
        ),
        [CityBeat.scene('locale', hold: 12.5, fly: 3.2, pull: 1.3, shift: 0.38)],
      ),
      CityStop(
        'mixing',
        const TalkCard(
          'Mixing multiplies',
          'Every script you add multiplies the work. One mixed paragraph exercises the whole '
              'pipeline at once.',
          [
            FactCode('Hello مرحبا שלום नमस्ते สวัสดี\nこんにちは世界 👋🏽🌍 world'),
            FactRow('runs × bidi', '9 × 2'),
            FactRow('fonts × shapers', '7 × 5'),
            FactRow('line breakers', '3'),
            FactRow('combinations', '1,890', accent: true),
          ],
        ),
        // (The mixed paragraph itself, hung over the city: its runs, their
        // cuts, their directions.)
        [CityBeat.scene('mix', hold: 8.0, fly: 3.0, shift: 0)],
      ),
    ]),
    section('03', 'How others do it', const ['Aa', 'ش', 'ह', '字'], [
      CityStop(
        'engines',
        const TalkCard(
          'How others do it',
          "Five engines, five places between owning the whole stack and using the platform's. Four "
              'share one shaper, HarfBuzz; Apple has its own.',
          [
            FactRow('Chrome', 'LayoutNG · HarfBuzz · Skia'),
            FactRow('Figma', 'own C++ → WASM · HarfBuzz · WebGPU'),
            FactRow('macOS', 'TextKit 2 · Core Text (own shaper)'),
            FactRow('Android', 'StaticLayout · Minikin · HarfBuzz'),
            FactRow('Flutter', 'RenderParagraph · SkParagraph · Impeller', accent: true),
          ],
          true,
        ),
        [CityBeat.at(_overview, fly: 3.2, shift: 0.2, cardAt: 2.8, chapter: true, pins: _engines)],
      ),
      // (The four others, each a screen showing what its way of setting
      // text gives it: hung in a row over the east side street, the camera
      // gliding along it.)
      CityStop(
        'chrome',
        const TalkCard(
          'Chrome',
          'Text lives in the DOM, so the browser gets the rest for free: CSS sets it, and the page can '
              'find it, select it and translate it.',
          [
            FactRow('stack', '<p> → CSS → LayoutNG → HarfBuzz → Skia'),
            FactRow('for free', 'balance · hyphens · vertical · ruby', accent: true),
            FactRow('and', 'find · select · translate · a11y · SEO'),
          ],
        ),
        [CityBeat.scene('engines', hold: 8.6, fly: 3.4, shift: 0.37)],
      ),
      CityStop(
        'figma',
        const TalkCard(
          'Figma',
          'One canvas with its own text engine: the same on every OS, re-rendered at every zoom, and '
              'every feature theirs to build.',
          [
            FactRow('stack', 'C++ → WASM · HarfBuzz + ICU · own renderer'),
            FactRow('✓', 'RTL (2022) · same on every OS'),
            FactRow('✕', 'vertical · color fonts'),
            FactRow('≈ Flutter', 'canvas + own engine', accent: true),
          ],
        ),
        [CityBeat.scene('engines', from: 10, hold: 18.6, fly: 1.8, shift: 0.37)],
      ),
      CityStop(
        'macos',
        const TalkCard(
          'macOS · Core Text',
          'Apple owns the whole stack, its own shaper included: a paragraph into lines, lines into '
              'runs, runs into glyphs, and book typesetting built in.',
          [
            FactCode('CTFrame › CTLine › CTRun › CGGlyph'),
            FactRow('built in', 'justify · hyphenate · vertical · ruby', accent: true),
            FactRow('optical size', 'automatic tracking (SF Pro)'),
            FactRow('AA', 'subpixel off since 10.14'),
          ],
        ),
        [CityBeat.scene('engines', from: 20, hold: 28.6, fly: 1.8, shift: 0.37)],
      ),
      CityStop(
        'android',
        const TalkCard(
          'Android · Minikin',
          "Minikin weighs the whole paragraph before it breaks a line. Flutter's text stack came from "
              'it, and kept only the first-fit breaker.',
          [
            FactRow('simple', 'first fit · = Flutter', accent: true),
            FactRow('balanced', 'even lines'),
            FactRow('high quality', 'whole-paragraph optimum, hyphens'),
            FactRow('lineage', 'Minikin → libtxt → SkParagraph (2022)'),
          ],
        ),
        [CityBeat.scene('engines', from: 30, hold: 38.6, fly: 1.8)],
      ),
    ]),
    section('04', "Flutter's trade-off", const ['✕', '✓'], [
      CityStop(
        'intro',
        const TalkCard(
          "Flutter's trade-off",
          'Flutter draws every pixel itself. That buys consistency and effects, and costs the features '
              'the platform would have given it.',
          [
            FactLetters('', [('✕', '', false), ('✓', '', true)]),
          ],
          true,
        ),
        [CityBeat.at(talkShot(30, 26, 13, 52.6, 20.5, 33.5, 42), fly: 3.4, pins: [_engines[4]], cardAt: 2.8, chapter: true)],
      ),
      CityStop(
        'missing',
        const TalkCard(
          'Not in Flutter',
          "Owning the stack means rebuilding every platform feature. Chrome's page, set by Flutter: what's "
              'still missing, or has only workarounds.',
          [
            FactRow('vertical text', '✕ → mongol pkg · rotate'),
            FactRow('ruby', '✕ → WidgetSpan'),
            FactRow('hyphenation', '✕ → manual U+00AD'),
            FactRow('optimal breaks', '✕ → greedy only'),
            FactRow('kashida', '✕ → spaces only'),
            FactRow('LCD subpixel', '✕ → grayscale AA'),
            FactRow('web find · SEO', '✕ → semantics tree'),
            FactRow('web fonts', '✕ → tofu flash · preload', accent: true),
          ],
        ),
        // (Back to the row of screens, to its last: the web page as Flutter
        // sets it; then ruby and hyphenation, acted out.)
        [CityBeat.scene('engines', from: 40, hold: 46, fly: 3.0, shift: 0.37), CityBeat.scene('ruby', hold: 6.0, fly: 3.0), CityBeat.scene('hyphen', hold: 8.0, fly: 2.6)],
      ),
      CityStop(
        'only',
        const TalkCard(
          'Only in Flutter',
          "Because Flutter owns every pixel, its text can do what native text can't.",
          [
            FactRow('same everywhere', '1 layout: iOS · Android · web · macOS', accent: true),
            FactRow('paint', 'shaders · stroke · FontVariation'),
            FactRow('widgets in text', 'WidgetSpan'),
            FactRow('every glyph', 'a box for each grapheme'),
            FactRow('3D', 'Matrix4, no relayout'),
          ],
        ),
        // (The same everywhere: two phones, native then Flutter; a variable
        // font; every glyph a box, turned in 3D.)
        [
          CityBeat.scene('phones', from: 20, hold: 31.0, fly: 3.0),
          // (Wider, from in front of the park bench: the letters and the
          // wght board beside them.)
          CityBeat.scene('gym', hold: 7.6, fly: 3.0, shift: 0.34, view: Shot(vm.Vector3(-1.58, 1.5, -2.94), vm.Vector3(-0.58, 1.3, 1.26), fov: 46, drift: 0.4)),
          CityBeat.scene('word', hold: 7.0, fly: 3.0, shift: 0.26),
        ],
      ),
      CityStop(
        'web',
        const TalkCard(
          'On the web',
          "On the web Flutter ships its own engine as WASM: text on a canvas the browser can't search, "
              'and fonts that arrive late, as tofu until then.',
          [
            FactRow('DOM <p>', 'found by Ctrl+F ✓'),
            FactRow('<canvas>', 'invisible to find ✕', accent: true),
            FactRow('fonts', 'Noto from fonts.gstatic.com, tofu till then'),
            FactRow('engine', 'canvaskit · skwasm; breaks from Intl.Segmenter'),
          ],
        ),
        // (Two browsers: the font arriving late, then find on each page.)
        [CityBeat.scene('phones', from: 60, hold: 68.0, fly: 3.2, shift: 0.4)],
      ),
    ]),
    JourneySection(site.works),
    section('06', 'Unsolved → solved', const ['文節', '」「', '◇'], [
      CityStop(
        'intro',
        const TalkCard(
          'Unsolved → solved',
          "Three things Flutter's text doesn't do well today, and small packages that fix them "
              'without touching the engine.',
          [
            FactLetters('', [('文節', '', false), ('」「', '', false), ('◇', '', false)]),
          ],
          true,
        ),
        [CityBeat.at(talkShot(0, 10, 46, 0, 2, 64, 50, drift: 0.8), fly: 3.4, shift: 0.24, cardAt: 2.8, chapter: true)],
      ),
      CityStop(
        'phrases',
        const TalkCard(
          'Phrase breaking',
          'Japanese may break almost anywhere, so Flutter splits words mid-phrase. kumihan finds the '
              'phrases (BudouX) and glues each with invisible word joiners.',
          [
            FactRow('Text()', '今日は天気｜です。'),
            FactRow('KumihanText()', '今日は｜天気です。', accent: true),
            FactRow('how', 'U+2060 inside each phrase'),
            FactCode("KumihanText('Flutterで日本語の改行を\n  きれいにする方法', balance: true)"),
          ],
        ),
        // (Two phones: the same sentence as Text() breaks it and as
        // KumihanText() does.)
        [CityBeat.scene('phones', from: 40, hold: 47.5, fly: 3.0)],
      ),
      CityStop(
        'punctuation',
        const TalkCard(
          'Punctuation spacing',
          "Full-width punctuation carries half an em of blank. Where two marks meet, the gap should "
              "close: kumihan applies the font's 'halt' glyph by glyph, where they meet.",
          [
            FactRow('Text()', '「こんにちは」「世界」。'),
            FactRow('kumihan', '−0.5 em where 」「 meet', accent: true),
            FactRow("'chws'", 'not in Noto Sans JP · Hiragino'),
          ],
        ),
        // (The first phone on its side: the marks before and after.)
        [CityBeat.scene('phones', from: 47.5, hold: 55.5, fly: 1.6, lead: 1.6)],
      ),
      CityStop(
        'slug',
        const TalkCard(
          'Slug · GPU text',
          'Draw glyphs straight from their curves in a fragment shader: sharp at any zoom, rotation or '
              'perspective, with no atlas to re-rasterize.',
          [
            FactRow('Text', 'glyph → A8 atlas'),
            FactRow('SlugText', 'curves → coverage per pixel', accent: true),
            FactRow('patent', 'public domain since March 2026'),
          ],
        ),
        [CityBeat.scene('word', from: 20, hold: 33.5, fly: 3.6, shift: 0.26)],
      ),
    ]),
    section('', 'The trade-off', const ['control', '⇄', 'native'], [
      CityStop(
        'trade-off',
        const TalkCard(
          'The trade-off',
          "Every engine picks a point between owning the stack and using the platform's. Flutter chose "
              'control, consistency and effects.',
          [
            FactScale('owns the stack', 'uses the platform', [
              ('Figma', -0.9, false),
              ('Flutter', -0.72, true),
              ('Android', 0.04, false),
              ('Chrome', 0.62, false),
              ('macOS', 0.88, false),
            ]),
            FactRow('Flutter chose', 'control · consistency · effects', accent: true),
          ],
          true,
        ),
        [CityBeat.at(talkShot(0, 9, -32, 0, 4, 0, 50, drift: 0.8), fly: 3.4, shift: 0.22, cardAt: 2.8, chapter: true)],
      ),
      CityStop(
        'thanks',
        const TalkCard('Thank you', 'questions?', [], true, 'ありがとうございました'),
        [CityBeat.scene('scripts', from: 100, hold: 110, fly: 4.0, shift: 0, fireworks: true, cardAt: 1e9, chapter: true)],
      ),
    ]),
  ];
}

TalkPin _pin(double x, double y, double z, String name, {int? order, String? sub}) => TalkPin(vm.Vector3(x, y, z), name, order: order, sub: sub);

/// The city from above the avenue, looking north over the plaza and the
/// park: every stop of section 01 in view.
final _cityMap = talkShot(0, 58, -40, 0, 0, 40, 54, drift: 1.0);

/// Section 01's stops as the pipeline's stages, in the order a string goes
/// through them (each with the library that does it).
final _stages = [
  _pin(6.6, 2.4, 15.2, 'STRING', order: 1, sub: 'unicode'),
  _pin(28.4, 6.6, 29.2, 'ITEMIZE', order: 2, sub: 'ICU'),
  _pin(-6.6, 3.6, 48.5, 'FALLBACK', order: 3, sub: 'font manager'),
  _pin(6.4, 3.0, 46.8, 'SHAPING', order: 4, sub: 'HarfBuzz'),
  _pin(1.0, 3.4, 66.6, 'LINES', order: 5, sub: 'ICU'),
  _pin(-28.4, 6.6, 11.2, 'BIDI', order: 6, sub: 'ICU · layout'),
  _pin(-9.0, 1.6, 79.0, 'RASTER', order: 7, sub: 'Skia'),
];

/// The city's east side from above, its rooftop signs: the five engines'
/// buildings.
final _overview = talkShot(-30, 55, -40, 48, 10, 30, 56, drift: 1.0);

/// Five buildings along the east side as the five engines' headquarters
/// (Flutter's has its name on the roof).
final _engines = [
  _pin(33.6, 14.6, -2.2, 'CHROME'),
  _pin(51.5, 27.2, 14.8, 'FIGMA'),
  _pin(51.3, 18.6, 48.6, 'MACOS'),
  _pin(34.0, 14.5, 57.6, 'ANDROID'),
  _pin(52.6, 22.6, 33.5, 'FLUTTER'),
];

