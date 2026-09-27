# Chrome vs Flutter vs kumihan

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

```bash
./compare/capture.sh           # → compare/out/compare.png (one full-page screenshot)
./compare/capture.sh --serve   # same, then keeps http://localhost:8765 open for manual screenshots
```

The script fetches the font (SIL OFL) on first run, renders the Flutter side
with `test/compare_render_test.dart` (PNGs + `lines.json` in `out/flutter/`),
then screenshots the page with headless Chrome. Add cases to `cases.json` and
re-run; both sides pick them up.

Notes: `auto-phrase` needs Chrome/Edge 119+ (other browsers show the Japanese
column like the default one). Chrome trims adjacent punctuation by default
(`text-spacing-trim: normal`), so its "default" column already has tight
`」「`; Flutter's doesn't. Flutter renders come from flutter_tester (Skia
software raster): line breaking and shaping are the same SkParagraph as on
devices; anti-aliasing may differ slightly from Impeller.
