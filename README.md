# Text rendering — interactive slides (Flutter)

**Live (WebAssembly):** https://rahiche.github.io/text-rendering-slides/

Three versions of the same talk, each told inside one world:

| version | link |
| --- | --- |
| Glyph factory | https://rahiche.github.io/text-rendering-slides/factory/ |
| Construction site | https://rahiche.github.io/text-rendering-slides/construction/ |
| Easy vs hard (workers) | https://rahiche.github.io/text-rendering-slides/workers/ |
| Classic blueprint | https://rahiche.github.io/text-rendering-slides/classic/ |

The content slides are shared; each world (`lib/worlds/`) supplies the title,
section dividers, pipeline overview, journey map, outro, ambient scenery, the
progress ruler and the slide transition. Press `w` to switch worlds live, or run
natively with `flutter run -d macos --dart-define=WORLD=factory`.

A Blueprint-themed, fully interactive deck on how text rendering works, why
more scripts make it harder, how Chrome / Figma / macOS / Android do it, what
Flutter can and can't do, and one word's journey from `Text('…')` to GPU pixels.

## Run

```bash
flutter run -d macos     # native, uses Impeller + system fallback fonts
flutter run -d chrome    # web (CanvasKit), fallback fonts download from Google Fonts
```

Deep link on the web: `?slide=<id>` (e.g. `?slide=j-map`, `?slide=shaping`).

Build the WebAssembly site locally (one build, copied per world, plus the landing page):

```bash
./tool/build_pages.sh   # → build/pages
```

## Deploy (Codemagic → GitHub Pages)

`codemagic.yaml` builds `flutter build web --wasm` on every push to `main` and
force-pushes `build/web` to the `gh-pages` branch, which GitHub Pages serves.

One-time setup:
1. In Codemagic, add this repository as an app and choose the `codemagic.yaml` config.
2. Create a fine-grained GitHub token with **Contents: Read and write** on this repo.
3. In the Codemagic app → Environment variables, add it as secure variable
   `GITHUB_TOKEN` in a group named `github_pages`.

The page is served without cross-origin isolation headers (GitHub Pages can't set
them), so Flutter runs the single-threaded Skwasm renderer, and browsers without
WasmGC fall back to the JavaScript build automatically.

## Controls

| key | action |
| --- | --- |
| → / space / page down | next build step, then next slide |
| ← / page up | previous |
| o | overview grid (click a slide to jump) |
| r | replay the current slide's animations |
| w | switch to the next world (version) |
| home / end | first / last slide |
| esc | leave a text field (so arrows drive the deck again) |

Click the progress ruler ticks to jump; hover a tick to see the slide title.

## Structure

- `lib/deck/` — deck engine (navigation, steps, wipe transition), Blueprint theme,
  shared widgets, script itemizer, and a small TrueType parser (`font_data.dart`)
  used to show real cmap lookups, glyph ids, advances and outlines.
- `lib/slides/` — one file per slide; `registry.dart` sets the order.
- `lib/slides/journey/` — section 05: one word's journey. The word is shared by
  every slide in the section; change it on any of them.
- `assets/fonts/` — Space Grotesk, JetBrains Mono, Noto Kufi Arabic (SIL OFL,
  from github.com/google/fonts).
