import 'package:vector_math/vector_math.dart' as vm;

import '../world/glyph_works.dart';
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
  CitySection section(String number, String title, String ja, List<String> glyphs, List<CityStop> stops) => CitySection(
    number: number,
    title: title,
    ja: ja,
    glyphs: glyphs,
    cityStops: stops,
    vignettes: site.vignettes,
    alley: site.alley,
    fx: site.fx,
    glyphShapes: () => site.scriptShapes,
  );

  return [
    section('', 'Text rendering', 'テキストレンダリング', const ['Text', 'نص', 'टेक्स्ट', '文字', 'טקסט', 'ข้อความ', '텍스트', 'Текст'], [
      CityStop(
        'title',
        const TalkCard(
          'テキストレンダリング',
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
        [CityBeat.at(talkShot(0, 26, -50, 0, 12, 55, 52, drift: 1.0), fly: 6.0, shift: 0.18, cardAt: 5.6, chapter: true)],
      ),
    ]),
    section('01', 'From code points to pixels', 'コードポイントから画素へ', const ['A', 'ب', 'क', '文', 'ก', '😀'], [
      CityStop(
        'intro',
        const TalkCard(
          'コードポイントから画素へ',
          'From code points to pixels',
          'A string goes in, pixels come out. In between, every step of the way is a place in this city.',
          [
            FactLetters('', [('A', '', false), ('ب', '', false), ('क', '', false), ('文', '', false), ('ก', '', false), ('😀', '', false)]),
          ],
          true,
        ),
        [
          CityBeat.at(
            talkShot(0, 58, -40, 0, 0, 40, 54, drift: 1.0),
            fly: 3.0,
            shift: 0.22,
            cardAt: 2.8,
            chapter: true,
            pins: [
              _pin(6.6, 2.4, 15.2, '家族', 'STRING'),
              _pin(-12.55, 3.3, 6.2, '文字工場', 'PIPELINE'),
              _pin(28.4, 6.6, 29.2, '分割', 'ITEMIZE'),
              _pin(-6.6, 3.6, 48.5, '豆腐屋', 'FALLBACK'),
              _pin(6.4, 3.0, 46.8, '合字工房', 'SHAPING'),
              _pin(1.0, 3.4, 66.6, '改行電車', 'LINES'),
              _pin(-28.4, 6.6, 11.2, '双方向', 'BIDI'),
              _pin(-9.0, 1.6, 79.0, '画素畑', 'RASTER'),
            ],
          ),
        ],
      ),
      CityStop(
        'string',
        const TalkCard(
          '文字列 ≠ テキスト',
          'A string ≠ text',
          "Dart's String.length counts UTF-16 units, not what you see. The family is one grapheme: "
              'four people joined by three zero-width joiners. Let go, it is four.',
          [
            FactRow('graphemes', 's.characters.length → 1', accent: true),
            FactRow('code points', 's.runes.length → 7'),
            FactRow('UTF-16 units', 's.length → 11'),
            FactRow('UTF-8 bytes', 'utf8.encode(s).length → 25'),
          ],
        ),
        [CityBeat.scene('family', hold: 6.1, fly: 2.6), CityBeat.scene('family', from: 6.1, hold: 10.75, fly: 0.8)],
      ),
      CityStop(
        'pipeline',
        const TalkCard(
          'パイプライン',
          'The pipeline',
          'Seven stages, each owned by a different library: code points become runs, fonts, glyphs, '
              'lines, positions, and finally pixels.',
          [
            FactCode(
              '01 text      unicode\n02 itemize   ICU\n03 fonts     font manager\n04 shape     HarfBuzz\n'
              '05 wrap      ICU · UAX #14\n06 position  layout\n07 raster    Skia · GPU',
            ),
          ],
        ),
        [CityBeat.at(GlyphWorks.front, fly: 2.6)],
      ),
      CityStop(
        'itemize',
        const TalkCard(
          '分割',
          'Itemize',
          'Before shaping, the string is cut where the script changes. Each run gets one script, one '
              'direction and one font; every later stage works on runs.',
          [
            FactLetters('Hi مرحبا 世界 👋 → 4 runs', [('Hi', 'Latin →', true), ('مرحبا', 'Arabic ←', false), ('世界', 'Han →', false), ('👋', 'Emoji', false)]),
            FactRow('fonts', 'Space Grotesk · Noto Kufi Arabic · CJK · Emoji'),
          ],
        ),
        [CityBeat.scene('itemize', hold: 8.6, fly: 3.0)],
      ),
      CityStop(
        'fallback',
        const TalkCard(
          'フォントフォールバック',
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
        [CityBeat.scene('tofu', hold: 16.0, fly: 2.8)],
      ),
      CityStop(
        'shaping',
        const TalkCard(
          'シェーピング',
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
        [CityBeat.scene('forge', fly: 2.4)],
      ),
      CityStop(
        'lines',
        const TalkCard(
          '改行',
          'Line breaking',
          'Greedy: fill each line up to maxWidth, then start the next. Where a line may break depends '
              'on the script.',
          [
            FactRow('spaces', 'UAX #14 break opportunities'),
            FactRow('Thai', 'no spaces: ICU dictionary'),
            FactRow('CJK', 'almost anywhere, but 。 never starts a line (禁則)', accent: true),
            FactRow('too long', 'an emergency break inside the word'),
          ],
        ),
        [CityBeat.scene('tram', hold: 11.6, fly: 3.0)],
      ),
      CityStop(
        'bidi',
        const TalkCard(
          '双方向',
          'Memory ≠ screen',
          'Text is stored in typing order; the bidi algorithm reorders it for display. A right-to-left '
              'run is reversed, its number stays left to right.',
          [
            FactRow('memory', '\u202DH i ␠ ש ל ו ם ␠ 2 0 2 6 !\u202C'),
            FactRow('screen', '\u202DH i ␠ 2 0 2 6 ␠ ם ו ל ש !\u202C', accent: true),
            FactRow('so', 'index i in memory ≠ position i on screen'),
          ],
        ),
        [CityBeat.scene('bidi', hold: 9.5, fly: 3.0)],
      ),
      CityStop(
        'raster',
        const TalkCard(
          'ラスタライズ',
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
    section('02', 'Every script adds rules', 'すべての文字にルールがある', const ['ع', 'कि', 'ปั่น', '한', '縦', '👋🏽'], [
      CityStop(
        'intro',
        const TalkCard(
          'すべての文字にルールがある',
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
              _pin(0, 3.4, 26.06, '文字横丁', 'SCRIPT ALLEY'),
              _pin(32.2, 34, 90.4, 'ユニコード塔', 'UNICODE'),
              _pin(-28.4, 6.6, 25.2, 'ロケール', 'LOCALE'),
            ],
          ),
        ],
      ),
      CityStop(
        'unicode',
        const TalkCard(
          'ユニコード',
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
          '文字横丁',
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
          '右から左',
          'Right to left',
          'שלום is written from the right: index 0 is the rightmost letter, and the caret moves left '
              'as you type.',
          [
            FactLetters('memory', [('ש', '0', true), ('ל', '1', false), ('ו', '2', false), ('ם', '3', false)]),
            FactRow('screen', 'שלום', accent: true),
          ],
        ),
        [CityBeat.stall(0)],
      ),
      CityStop(
        'joining',
        const TalkCard(
          'つながる',
          'Joining',
          'An Arabic letter takes a shape for its neighbours: isolated, initial, medial or final.',
          [
            FactRow('letters', '\u2067ب ي ت\u2069'),
            FactRow('joined', 'بيت', accent: true),
            FactRow('forms', 'isol · init · medi · fina'),
          ],
        ),
        [CityBeat.stall(1)],
      ),
      CityStop(
        'reorder',
        const TalkCard(
          '並べ替え',
          'Reordering',
          'The Devanagari vowel sign ि is stored after its consonant, but drawn before it.',
          [
            FactLetters('memory', [('क', 'U+0915', false), ('ि', 'U+093F', true)]),
            FactRow('screen', 'कि', accent: true),
          ],
        ),
        [CityBeat.stall(2)],
      ),
      CityStop(
        'stacking',
        const TalkCard(
          '積み重ね',
          'Stacking',
          "Thai marks stack on their letter: a vowel above it, a tone mark above that, raised so they "
              "don't collide. And no spaces between words: a dictionary finds them.",
          [
            FactLetters('ป + ั + ่', [('ป', 'base', false), ('ั', 'vowel', false), ('่', 'tone', true)]),
            FactRow('result', 'ปั่น', accent: true),
          ],
        ),
        [CityBeat.stall(3)],
      ),
      CityStop(
        'blocks',
        const TalkCard(
          '組み立て',
          'Composition',
          'Hangul letters (jamo) are composed into one square syllable block.',
          [
            FactLetters('ㅎ + ㅏ + ㄴ', [('ㅎ', '', false), ('ㅏ', '', false), ('ㄴ', '', false)]),
            FactRow('syllable', '한 · U+D55C', accent: true),
          ],
        ),
        [CityBeat.stall(4)],
      ),
      CityStop(
        'vertical',
        const TalkCard(
          '縦書き',
          'Vertical',
          'Japanese can be set top to bottom, its columns right to left.',
          [
            FactRow('reads', '縦書きは右から左へ読む'),
            FactRow('in Flutter', 'not built in (section 04)', accent: true),
          ],
        ),
        [CityBeat.stall(5)],
      ),
      CityStop(
        'locale',
        const TalkCard(
          'ロケール',
          'One code point, two glyphs',
          'Han characters are unified: Japanese and Chinese share a code point but draw it differently. '
              'The locale picks the font.',
          [
            FactLetters('ja · zh-Hans', [('直', 'U+76F4', true), ('角', 'U+89D2', false), ('骨', 'U+9AA8', false), ('写', 'U+5199', false)]),
            FactRow('fix', "locale: Locale('ja')", accent: true),
          ],
        ),
        [CityBeat.scene('locale', hold: 12.5, fly: 3.2)],
      ),
      CityStop(
        'mixing',
        const TalkCard(
          '混在',
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
        [CityBeat.at(talkShot(0, 30, -30, 0, 18, 40, 60, drift: 0.8), fly: 3.0, shift: 0.2)],
      ),
    ]),
    section('03', 'How others do it', 'ほかのエンジン', const ['Aa', 'ش', 'ह', '字'], [
      CityStop(
        'intro',
        const TalkCard(
          'ほかのエンジン',
          'How others do it',
          "Five engines, five places on a line between owning the whole stack and using the "
              "platform's.",
          [
            FactLetters('', [('Aa', '', false), ('ش', '', false), ('ह', '', false), ('字', '', false)]),
          ],
          true,
        ),
        [CityBeat.at(_overview, fly: 3.2, shift: 0.2, cardAt: 2.8, chapter: true)],
      ),
      CityStop(
        'engines',
        const TalkCard(
          '五つのエンジン',
          'Five engines',
          'Four of the five share one shaper, HarfBuzz; Apple has its own. The differences are in '
              'the layers around it.',
          [
            FactRow('Chrome', 'LayoutNG · HarfBuzz · Skia'),
            FactRow('Figma', 'own C++ → WASM · HarfBuzz · WebGPU'),
            FactRow('macOS', 'TextKit 2 · Core Text (own shaper)'),
            FactRow('Android', 'StaticLayout · Minikin · HarfBuzz'),
            FactRow('Flutter', 'RenderParagraph · SkParagraph · Impeller', accent: true),
          ],
        ),
        [CityBeat.at(_overview, fly: 1.0, shift: 0.2, pins: _engines)],
      ),
      CityStop(
        'chrome',
        const TalkCard(
          'ブラウザ',
          'Chrome',
          'Text lives in the DOM, so the browser gets the rest for free.',
          [
            FactRow('stack', '<p> → CSS → LayoutNG → HarfBuzz → Skia'),
            FactRow('for free', 'vertical · ruby · hyphens · balance', accent: true),
            FactRow('and', 'find · select · translate · a11y · SEO'),
          ],
        ),
        [CityBeat.at(talkShot(16, 21, -20, 33.6, 13.0, -2.2, 42), fly: 2.8, pins: [_engines[0]])],
      ),
      CityStop(
        'figma',
        const TalkCard(
          'デザイン',
          'Figma',
          'One canvas with its own text engine: the same on every OS, but text is re-rendered at every '
              'zoom, and every feature is theirs to build.',
          [
            FactRow('stack', 'C++ → WASM · HarfBuzz + ICU · own renderer'),
            FactRow('✓', 'RTL (2022) · same on every OS'),
            FactRow('✕', 'vertical · color fonts'),
            FactRow('≈ Flutter', 'canvas + own engine', accent: true),
          ],
        ),
        [CityBeat.at(talkShot(30, 31, -6, 51.5, 25.0, 14.8, 42), fly: 2.6, pins: [_engines[1]])],
      ),
      CityStop(
        'macos',
        const TalkCard(
          'アップル',
          'macOS · Core Text',
          'Apple owns the whole stack, its own shaper included: a paragraph into lines, lines into '
              'runs, runs into glyphs.',
          [
            FactCode('CTFrame › CTLine › CTRun › CGGlyph'),
            FactRow('built in', 'vertical · ruby · hyphenation', accent: true),
            FactRow('optical size', 'automatic tracking (SF Pro)'),
            FactRow('AA', 'subpixel off since 10.14'),
          ],
        ),
        [CityBeat.at(talkShot(30, 24, 28, 51.3, 17, 48.6, 42), fly: 3.0, pins: [_engines[2]])],
      ),
      CityStop(
        'android',
        const TalkCard(
          'アンドロイド',
          'Android · Minikin',
          "Minikin weighs the whole paragraph before it breaks a line. Flutter's text stack came from "
              'it, and kept only the greedy breaker.',
          [
            FactRow('simple', 'first fit · = Flutter', accent: true),
            FactRow('balanced', 'even lines'),
            FactRow('high quality', 'whole-paragraph optimum'),
            FactRow('lineage', 'Minikin → libtxt → SkParagraph (2022)'),
          ],
        ),
        [CityBeat.at(talkShot(14, 20, 38, 34, 13, 57.6, 42), fly: 2.6, pins: [_engines[3]])],
      ),
    ]),
    section('04', "Flutter's trade-off", 'Flutterのトレードオフ', const ['✕', '✓'], [
      CityStop(
        'intro',
        const TalkCard(
          'Flutterのトレードオフ',
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
          'できないこと',
          'Not in Flutter',
          'Owning the stack means rebuilding every platform feature. These are still missing, or '
              'have only workarounds.',
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
        [CityBeat.scene('ruby', hold: 6.0, fly: 3.0), CityBeat.scene('hyphen', hold: 8.0, fly: 2.6), CityBeat.stall(5, fly: 2.6)],
      ),
      CityStop(
        'only',
        const TalkCard(
          'できること',
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
        [CityBeat.scene('gym', hold: 7.6, fly: 3.0), CityBeat.at(_glyphTower, fly: 3.4, shift: 0.26)],
      ),
      CityStop(
        'web',
        const TalkCard(
          'ウェブ',
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
        [CityBeat.at(talkShot(-0.3, 2.6, 45.4, -6.6, 1.8, 50.6, 52), fly: 3.2)],
      ),
    ]),
    JourneySection(site.works),
    section('06', 'Unsolved → solved', '未解決 → 解決', const ['文節', '」「', '◇'], [
      CityStop(
        'intro',
        const TalkCard(
          '未解決 → 解決',
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
          '文節で改行',
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
        [CityBeat.scene('tram', hold: 11.6, fly: 2.4)],
      ),
      CityStop(
        'punctuation',
        const TalkCard(
          '約物の詰め',
          'Punctuation spacing',
          "Full-width punctuation carries half an em of blank. Where two marks meet, the gap should "
              "close: kumihan applies the font's 'halt' glyph by glyph, where they meet.",
          [
            FactRow('Text()', '「こんにちは」「世界」。'),
            FactRow('kumihan', '−0.5 em where 」「 meet', accent: true),
            FactRow("'chws'", 'not in Noto Sans JP · Hiragino'),
          ],
        ),
        [CityBeat.at(talkShot(-12.3, 1.7, -12.4, -13.8, 1.3, -8.55, 40), fly: 3.4)],
      ),
      CityStop(
        'slug',
        const TalkCard(
          'スラッグ',
          'Slug · GPU text',
          'Draw glyphs straight from their curves in a fragment shader: sharp at any zoom, rotation or '
              'perspective, with no atlas to re-rasterize.',
          [
            FactRow('Text', 'glyph → A8 atlas'),
            FactRow('SlugText', 'curves → coverage per pixel', accent: true),
            FactRow('patent', 'public domain since March 2026'),
          ],
        ),
        [CityBeat.at(_glyphBelow, fly: 3.6, shift: 0.26)],
      ),
    ]),
    section('', 'The trade-off', 'トレードオフ', const ['control', '⇄', 'native'], [
      CityStop(
        'trade-off',
        const TalkCard(
          'トレードオフ',
          'The trade-off',
          "Every engine picks a point between owning the stack and using the platform's. Flutter chose "
              'control, consistency and effects.',
          [
            FactRow('Figma', '−0.9 · control'),
            FactRow('Flutter', '−0.72', accent: true),
            FactRow('Android', '+0.04'),
            FactRow('Chrome', '+0.62'),
            FactRow('macOS', '+0.88 · native'),
          ],
          true,
        ),
        [CityBeat.at(talkShot(0, 9, -32, 0, 4, 0, 50, drift: 0.8), fly: 3.4, shift: 0.22, cardAt: 2.8, chapter: true)],
      ),
      CityStop(
        'thanks',
        const TalkCard(
          'ありがとうございました',
          'Thank you',
          'questions? · ご質問は？',
          [],
          true,
        ),
        [CityBeat.at(talkShot(0, 7, -30, 0, 9.5, 6, 56, drift: 0.8), fly: 4.0, shift: 0, fireworks: true, cardAt: 1e9, chapter: true)],
      ),
    ]),
  ];
}

TalkPin _pin(double x, double y, double z, String ja, String en) => TalkPin(vm.Vector3(x, y, z), ja, en);

/// The city's east side from above, its rooftop signs: the five engines'
/// buildings.
final _overview = talkShot(-30, 55, -40, 48, 10, 30, 56, drift: 1.0);

/// Five buildings along the east side as the five engines' headquarters
/// (Flutter's has its name on the roof).
final _engines = [
  _pin(33.6, 14.6, -2.2, 'ブラウザ', 'CHROME'),
  _pin(51.5, 27.2, 14.8, 'デザイン', 'FIGMA'),
  _pin(51.3, 18.6, 48.6, 'アップル', 'MACOS'),
  _pin(34.0, 14.5, 57.6, 'アンドロイド', 'ANDROID'),
  _pin(52.6, 22.6, 33.5, 'フラッター', 'FLUTTER'),
];

/// Glyphs of the skyline (あ, A and 字, 15–27 m tall) together; and the A
/// from below, in perspective.
final _glyphTower = talkShot(-52, 16, 41, -91, 13, 56, 58, drift: 0.6), _glyphBelow = talkShot(-80, 4, 24, -106, 16, 32, 56, drift: 0.5);
