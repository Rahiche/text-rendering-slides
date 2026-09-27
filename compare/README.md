# Chrome vs Flutter vs kumihan / slug

A side-by-side harness for Japanese line breaking and punctuation spacing.
Every case in `cases.json` is rendered four ways with the **same font file**
(Noto Sans JP, wght 400), size, width and line height (1.5):

| | default | Japanese typesetting |
| --- | --- | --- |
| **Chrome** (live HTML/CSS) | plain HTML | `word-break: auto-phrase; line-break: strict; text-wrap: balance` |
| **Flutter** (`flutter test` renders) | `Text` | `KumihanText(balance, yakumono)` |

Under each rendering the page shows the line breaks it actually produced
(measured with DOM ranges in Chrome, read from the paragraph in Flutter),
kinsoku violations, the width in em, and whether Flutter's breaks match
Chrome's. The table at the top summarises all cases.

## Slug: zoom & perspective

The second part of the page (`zoom.json`) puts the same text under the same
transform three ways: Chrome (CSS `perspective() rotateX() rotateY() scale()`),
Flutter `Text` and Flutter `SlugText` (same `Matrix4`). The Flutter side is the
web build running live in an iframe in probe mode (`?probe=slug&…`,
`lib/probe/slug_probe.dart`). The page measures Chrome's baseline and passes
it to the probe, because Chrome snaps line metrics to whole pixels and a 1px
difference becomes 40px at 40×. The `anim` case (1× ↔ 24× loop) only shows
live; screenshots skip it.

On the web, Skia already draws large and perspective glyphs as paths, so
`Text` and `SlugText` look alike here. Slug's visible gains are against
Impeller's glyph atlas on native (macOS/iOS/Android): mid-size zoom,
perspective, animated scale.

```bash
./compare/capture.sh           # → compare/out/compare.png + compare/out/compare-zoom.png
./compare/capture.sh --serve   # same, then keeps http://localhost:8765 open for manual screenshots
```

The script fetches the font (SIL OFL) on first run, renders the Flutter side
with `test/compare_render_test.dart` (PNGs + `lines.json` in `out/flutter/`),
builds the web app into `out/app/` for the zoom iframes, then screenshots the
page with headless Chrome through the DevTools protocol (`cdp_shot.py`). Add cases to `cases.json` and
re-run; both sides pick them up.

Notes: `auto-phrase` needs Chrome/Edge 119+ (other browsers show the Japanese
column like the default one). Chrome trims adjacent punctuation by default
(`text-spacing-trim: normal`), so its "default" column already has tight
`」「`; Flutter's doesn't. Flutter renders come from flutter_tester (Skia
software raster): line breaking and shaping are the same SkParagraph as on
devices; anti-aliasing may differ slightly from Impeller.
