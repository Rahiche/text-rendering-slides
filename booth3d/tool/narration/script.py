"""The presentation's narration (booth3d/lib/talk/presentation.dart): a clip
per beat of the talk, in its order (lib/talk/talk_sections.dart), spoken in
the presenter's own voice by gen.py. Written to be spoken: symbols and code
are spelled out the way they're said ("S.K. Paragraph", "U plus zero three
seven eight"), and Japanese is written in Japanese.

A beat added to the talk needs its clip here, in the same place.
"""
BEATS = [
    ("title", """
Hi everyone, I'm Raouf. Today we're going to follow a piece of text from the moment it's a string in memory, to the moment it becomes pixels on your screen, and see how Flutter handles every step along the way.
Around the title, you can see one word, text, written in eight different scripts: Latin, Arabic, Devanagari, Japanese, Hebrew, Thai, Korean and Cyrillic. Every one of them has to go through the same pipeline.
And instead of slides, I'm going to tell this story in a city, where every idea has its own place.
"""),
    ("01 pipeline", """
Let's start with the big picture. A string goes in, and pixels come out. In between, there are seven stages, and each one is owned by a different library.
First, the string itself, which is Unicode. Then itemizing, done by I.C.U. Then font fallback, handled by the font manager. Then shaping, with HarfBuzz. Then line breaking, again with I.C.U. Then bidi, which reorders right-to-left text. And finally, rasterization, with Skia and the GPU.
Every one of these stages is a stop in this city, numbered in the order a string goes through them. So let's visit them, one by one.
"""),
    ("01 string1", """
First stop: a string is not the same thing as text.
In Dart, string dot length counts UTF-16 code units, not the things you actually see on screen.
Look at this family, out for a walk in the park. On screen, it's a single emoji, one grapheme. But under the hood, it's four people, glued together by three invisible zero-width joiners.
And it's not just emoji: accented letters, flags and skin tones all work the same way.
"""),
    ("01 string2", """
Take the joiners out, and the family falls apart into four separate people.
That one emoji is seven code points, eleven UTF-16 units, and twenty-five bytes in UTF-8. Even a simple accented e can be two code points.
So whenever you count text, the first question is: count what? Characters, runes, code units, or bytes? In Flutter, the characters package gives you what users actually see.
"""),
    ("01 itemize", """
Before anything can be shaped, the string is cut into runs, wherever the script changes.
Take this one: hi, marhaba, sekai, and a waving hand. That's four runs: Latin, going left to right. Arabic, going right to left. Han characters. And an emoji.
Each run gets exactly one script, one direction, and one font. And from here on, every stage of the pipeline works on runs, not on the whole string. That's why a single text span can end up drawn with several fonts.
"""),
    ("01 fallback", """
Next, font fallback. Fonts are asked in order, one character at a time: first the app's own fonts, then the platform's. In Flutter, you control the first part of that list, with font family and font family fallback.
Our courier here carries a code point from kiosk to kiosk, and asks each font if it has it. A Latin A is found in Space Grotesk on the very first try. An Arabic letter takes two lookups. A Chinese character takes three, and an emoji, four.
But this code point, U plus zero three seven eight, isn't assigned to anything. No font has it. So the last font draws its not-def glyph, the empty box we call tofu.
"""),
    ("01 shaping", """
Now, my favorite stage: shaping. HarfBuzz turns code points into glyph IDs and positions, and it's not one to one.
Arabic letters join with their neighbours into one connected word. An f and an i can merge into a single ligature, and in coding fonts, a dash and a greater-than sign become an arrow. Kerning pulls pairs like A and V closer together. In Devanagari, a vowel sign swaps places with its consonant. And five code points of an emoji sequence can collapse into one single glyph.
This forge is where letters go in, and glyphs come out.
"""),
    ("01 lines1", """
Then comes line breaking. Flutter's approach is greedy: fill each line up to the max width, then start the next one.
But where a line is allowed to break depends on the script. In English, you break at spaces, following the Unicode line breaking rules. Thai has no spaces at all, so I.C.U. uses a dictionary to find the words. And in Japanese, you can break almost anywhere, with one catch: a closing mark, like the full stop, may never start a line. That rule is called kinsoku.
"""),
    ("01 lines2", """
Here's the same paragraph on a phone. Turn the phone on its side, and you get a new max width, so the very same words flow into brand new lines.
And when a single word is longer than the whole line, like this famous German one, the breaker has no choice left. It makes an emergency break, right in the middle of the word.
"""),
    ("01 bidi", """
Next: memory is not the screen. Text is stored in the order you typed it, and the bidirectional algorithm reorders it for display.
Here's hi, then the word Urdu, written in Urdu, then the year twenty twenty-six. On screen, the Urdu run is reversed, but the number keeps reading left to right.
So index i in memory is not position i on screen. And that matters for cursors, for selection, and for hit testing. Flutter's TextPainter does that math for you, so lean on it instead of doing it by hand.
"""),
    ("01 raster", """
And the last stage of the pipeline: rasterization. Glyphs are outlines, made of curves. But a screen is a grid of pixels.
So at small sizes, each pixel is shaded by how much of it the outline covers. That's what this pixel farm is growing.
Aliased rendering just turns a pixel on when it's at least half covered, which looks jagged. Grayscale anti-aliasing maps the coverage to a shade of grey, and that's what Flutter and Impeller do. Subpixel rendering uses the red, green and blue thirds of each pixel, but macOS turned it off back in version ten fourteen.
"""),
    ("02 intro", """
Section two: every script adds rules.
Latin lets you assume a lot. Letters go from left to right, each letter has one shape, and they simply sit side by side.
Every other script breaks at least one of those assumptions. And a real paragraph doesn't stick to just one script. It mixes them. Let's see how far that goes.
"""),
    ("02 unicode", """
Here's the scale of the problem. In nineteen sixty-three, ASCII had a hundred and twenty-eight characters. Unicode one, in ninety-one, had about seven thousand. Emoji arrived with Unicode six, in twenty ten.
And today, Unicode eighteen has a hundred and seventy-two thousand, eight hundred and eight characters, across more than a hundred and seventy scripts.
And all of that is still only fifteen and a half percent of the code space. Every new version adds characters that fonts and renderers have to keep up with.
"""),
    ("02 alley", """
Welcome to Script Alley. Here are six things Latin lets you assume, and a script that breaks each one, with a stall for each.
Direction, with Urdu. Shape, with Arabic. Order, with Devanagari. Stacked marks, with Thai. Syllable blocks, with Korean. And lines that run from top to bottom, with Japanese.
Each stall breaks one assumption, and together they break all six. Let's walk down the alley.
"""),
    ("02 rtl", """
The first stall is right to left.
Urdu is written starting from the right. Here's the word Urdu itself: index zero is the rightmost letter, and as you type, the caret moves to the left.
Arabic, Persian and Hebrew work the same way. So your layout code can't assume that the start of a string is on the left. That's why Flutter's text align has start and end, and not just left and right.
"""),
    ("02 joining", """
Second stall: joining.
An Arabic letter changes its shape depending on its neighbours. This one, ain, has four forms: isolated, initial, medial, and final.
Three separate letters spell bayt, which means house, and they join into one connected word. So the glyph you draw depends on context, not just on the character. HarfBuzz picks the right form for every letter, using the font's own tables.
"""),
    ("02 reorder", """
Third stall: reordering.
In Devanagari, the vowel sign i is stored after its consonant, ka. But it's drawn before it.
So even inside a single syllable, the order in memory is not the order on screen. And you'll find the very same thing in Bengali, and in Punjabi. Again, the shaper takes care of it, as long as the font has the right tables.
"""),
    ("02 stacking", """
Fourth stall: stacking.
Thai marks stack on top of their letter. A vowel sits above the consonant, and the tone mark goes above that, raised so the two of them don't collide.
Vietnamese does something similar, with an e that carries one mark above, and another one below. Placing those marks is the font's job, with anchor points, and the shaper applies them.
"""),
    ("02 blocks", """
Fifth stall: composition.
Korean Hangul letters, called jamo, are composed into square syllable blocks. The letters h, a, and n become one block: han, a single code point.
And the word Hangul itself is two of those blocks, built from six letters. Unicode actually has precomposed code points for more than eleven thousand of these syllables.
"""),
    ("02 vertical", """
And the last stall is vertical text.
Japanese can be set from top to bottom, with the columns running from right to left. Chinese can do the same, and Mongolian also runs top to bottom, but with its columns going left to right.
In Flutter, vertical text is not built in, and we'll come back to that in section four.
"""),
    ("02 locale", """
Now, one code point, two glyphs. Chinese and Japanese characters were unified in Unicode, so both languages share the same code point for each of these characters.
But each language draws them differently. Look closely at the strokes, they don't match.
The locale picks the font. So in Flutter, set the locale to Japanese on Japanese text, or your users will see the Chinese forms instead. This is called Han unification, and it's one of the most common rendering bugs in apps made for Japan.
"""),
    ("02 mixing", """
And mixing multiplies everything. Here's one paragraph with English, Arabic, Hebrew, Hindi, Thai, Japanese and emoji.
That's nine runs in two directions, seven fonts with five shapers, and three different line breakers. Altogether, one thousand eight hundred and ninety combinations.
One mixed paragraph exercises the entire pipeline, all at once. And this is exactly the kind of text your users will type.
"""),
    ("03 engines", """
Section three: how others do it. Here are five engines, and each one sits somewhere between owning the whole stack, and using the platform's.
Chrome uses LayoutNG, with HarfBuzz and Skia. Figma has its own engine, written in C plus plus and compiled to WebAssembly. macOS has TextKit and Core Text, with Apple's own shaper. Android uses Minikin and HarfBuzz. And Flutter uses RenderParagraph, SkParagraph and Impeller.
Four of the five share the same shaper, HarfBuzz. Apple has its own. Let's look at what each of them gets from where it sits.
"""),
    ("03 chrome", """
Chrome first. In the browser, text lives in the DOM, so the browser gets the rest for free.
CSS can balance lines, hyphenate words, set text vertically, and add ruby annotations. And because it's real text in the page, you can find it, select it and translate it, and screen readers and search engines can read it too. The price is that the platform decides how your text looks, and that can differ from one browser to another.
"""),
    ("03 figma", """
Figma is the closest to Flutter. It's one canvas, with its own text engine, built on HarfBuzz and I.C.U., and its own renderer.
So text looks exactly the same on every operating system, and it re-renders at every zoom level. But every single feature is theirs to build. Right-to-left support only arrived in twenty twenty-two, and vertical text and color fonts are still missing.
"""),
    ("03 macos", """
On macOS, Apple owns the entire stack, including its own shaper. Core Text splits a paragraph into lines, lines into runs, and runs into glyphs.
Justification, hyphenation, vertical text and ruby are all built in, like a book typesetter. It even adjusts the tracking automatically, with San Francisco's optical sizes.
And as we saw earlier, subpixel anti-aliasing has been off since ten fourteen.
"""),
    ("03 android", """
And Android, with Minikin. Minikin can weigh the whole paragraph before it breaks a single line.
It has three strategies. Simple, which is first fit. Balanced, which evens out the lines. And high quality, which finds the best breaks for the whole paragraph, with hyphens.
Flutter's text stack actually came from Minikin, through libtxt, to SkParagraph. But along the way, it only kept the simple, first-fit breaker.
"""),
    ("04 intro", """
Section four: Flutter's trade-off.
Flutter draws every single pixel itself. That buys it consistency, because text looks the same everywhere, and it buys effects that native text simply can't do.
But it costs all the features the platform would otherwise have given it for free. Let's look at both sides.
"""),
    ("04 missing1", """
First, what's not in Flutter. Owning the stack means rebuilding every platform feature yourself.
Here's Chrome's page from before, set by Flutter this time. There's no vertical text, so you need a package like mongol, or you rotate things by hand. And there's no optimal line breaking, only the greedy breaker, so the lines come out ragged instead of balanced. Some of these have workarounds, and some of them don't.
"""),
    ("04 missing2", """
There's no ruby either. Those are the small reading hints, furigana, that sit above Japanese characters, like on this cable car riding over Tokyo.
In Flutter, you have to build them yourself, with widget spans. It works, but then the ruby isn't really part of the paragraph anymore.
"""),
    ("04 missing3", """
And there's no automatic hyphenation. In this sawmill, a long word gets cut at its soft hyphen, and in Flutter, you have to insert those by hand.
The list goes on: no kashida justification for Arabic, no subpixel rendering, and on the web, no find in page and no SEO. And web fonts can flash as tofu while they load, unless you preload them.
"""),
    ("04 only1", """
But there's another side to this. Because Flutter owns every pixel, its text can do things native text can't.
First, it's the same everywhere. There's one layout engine, so the same paragraph breaks into exactly the same lines on iOS, Android, the web and macOS.
Here are two phones. With native text, the result depends on the platform. With Flutter, it's identical, pixel for pixel.
"""),
    ("04 only2", """
Second, you can paint text however you like: with shaders, with strokes, and with variable fonts.
In this gym, the letters are lifting weights, and as they do, the font's weight axis goes up and down, smoothly, frame by frame. And because it's all just painting, you can mix text with anything else on screen.
"""),
    ("04 only3", """
And third, you get every glyph. Flutter can give you a box for each grapheme, so you can animate letters one by one, and even turn them in 3D with a matrix, without any relayout. That's how this whole city builds its letters: every glyph is a shape you can move.
"""),
    ("04 web", """
On the web, Flutter ships its own engine as WebAssembly. That means the text is drawn on a canvas, and the browser can't search it. Press control F, and it finds nothing.
And fonts arrive late. Noto fonts are downloaded from Google's servers, and until they arrive, you see tofu. Even the line breaks there come from the browser's segmenter. For accessibility, Flutter builds a semantics tree, so screen readers still work, but find in page doesn't.
"""),
    ("05 map", """
Section five: one word's journey. Let's follow a Text widget saying Flutter, all the way down to pixels.
Layout takes it down through the framework and dart U.I., into the engine. Paint records it, and the GPU draws it.
And all of it happens right here, in the Glyph Works, next to the plaza where the crew is building names. We'll follow the first letter down the line, and the rest of the word will catch up with it.
"""),
    ("05 widget", """
It starts with a widget. Text only describes: a string, and a style.
Underneath, Text builds a RichText, which creates a RenderParagraph. The RenderParagraph owns a TextPainter, and the TextPainter builds the paragraph.
At this point, Dart keeps the string as UTF-16 code units, and Flutter is seven of them. The widget is just a description: the real work happens in the render object.
"""),
    ("05 engine", """
Into the engine. Across dart U.I., the engine's paragraph builder hands the text to S.K. Paragraph, which keeps it as UTF-8.
Here, the bytes come out of the feeder, and go into the decoder. I.C.U. marks the graphemes, the line breaks, the direction and the script, and the text is itemized into runs. For Flutter, that's just one run: one script, one direction, one font.
"""),
    ("05 fonts", """
Next, find the glyphs. Each code point is looked up in the style's fonts, in order: the font family, then the fallbacks, then the platform's.
The font's cmap table maps each code point to a glyph ID. And for Flutter, every letter is found in Space Grotesk, the very first font. No fallback needed. If a letter were missing, this is where fallback would kick in, just like we saw at the tofu shop.
"""),
    ("05 shape", """
Then: shape, and lay out. HarfBuzz shapes the whole run at once, producing glyphs, and how far each one advances.
Notice the two t's. The font joins them into a single ligature glyph, so seven code points become six glyphs.
Then layout wraps the run to the max width, and measures each line. Shaping is the expensive part, so it's done once, and the text can be wrapped again as many times as the width changes.
"""),
    ("05 raster", """
Record, then rasterize. Paint doesn't actually draw anything yet. The paragraph is recorded into a display list, as glyph IDs and positions, for the raster thread.
There, every glyph that's not in the atlas yet is rasterized once, as coverage: solid pixels inside, and grey pixels along the anti-aliased edges. The atlas is a cache: the next time this glyph shows up at this size, it's simply reused.
"""),
    ("05 draw", """
And finally, draw. Each glyph becomes a quad, two triangles, whose corners point into the atlas.
The shader multiplies the text color by the coverage, and the whole word goes out in a single draw call.
And there it is: Flutter, on the board, pixel for pixel.
"""),
    ("06 intro", """
Section six: from unsolved, to solved.
Here are three things Flutter's text doesn't do well today, and small packages that fix them, without touching the engine. None of them needs a fork of Flutter.
"""),
    ("06 phrases", """
First: phrase breaking in Japanese. Because Japanese can break almost anywhere, Flutter will happily split a word in the middle of a phrase, and that's hard to read.
The kumihan package finds the phrases, using Budou X, and glues each phrase together with invisible word joiners. So lines only break between phrases.
On the left, plain Text. On the right, KumihanText, with balanced lines that break exactly where a Japanese reader expects.
"""),
    ("06 punctuation", """
Second: punctuation spacing. In Japanese, full-width punctuation carries half an em of blank space. So when two marks meet, like a closing bracket and an opening bracket, the gap should close.
The font feature that would do this automatically isn't in Noto Sans Japanese, or in Hiragino. So kumihan applies the font's halt feature, glyph by glyph, exactly where the marks meet.
"""),
    ("06 slug", """
And third: text on the GPU, with Slug. Instead of rasterizing glyphs into an atlas, Slug draws them straight from their curves, in a fragment shader.
So text stays perfectly sharp at any zoom, any rotation, and any perspective, with no atlas to re-rasterize. And since March twenty twenty-six, the Slug patent is in the public domain, so this is now open to everyone.
"""),
    ("end tradeoff", """
So, to wrap up: the trade-off. Every engine picks a point between owning the stack, and using the platform's.
Figma owns almost everything, and Flutter is right next to it. Android sits in the middle, Chrome leans on the platform, and macOS is the platform.
Flutter chose control, consistency, and effects. And the price is rebuilding what the platform would have given it for free, one package at a time. And as we just saw, a lot of that can be done today, in plain Dart, on top of the engine.
"""),
    ("end thanks", """
That's it from me. Thank you so much for listening. ありがとうございました!
I'd love to hear your questions.
"""),
]
