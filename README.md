# Inside Flutter's Text Pipeline — interactive slides (Flutter)

**Live (WebAssembly):** https://rahiche.github.io/text-rendering-slides/

**The talk:** https://rahiche.github.io/text-rendering-slides/factory-simple/ —
the Glyph factory, simplified: fewer slides, bigger demos, one idea per slide
(`lib/simple/`). Printed version: `inside-flutters-text-pipeline.pdf` on the site.

```bash
flutter run -d macos -t lib/main_simple.dart              # just the talk, natively
tool/export_slides.sh --pdf build/slides/inside-flutters-text-pipeline.pdf   # PNG per slide + PDF
```

## The booth (conference stall)

Visitors type their name (English or Japanese, via the macOS input method) on a
keyboard at the stall; a world made of text builds it, celebrates it, takes it
down and builds the next one, forever. Fully offline; history of built names is
kept on disk.

| app | what | build |
| --- | --- | --- |
| **Name Factory · 名前工場** | 2D: the glyph factory rasterizes the name into bricks, a crane and builders lay them, a wrecking ball, recycling. Ctrl+Shift+M switches to the **Name Workshop · 名前工房**: one character at a time, each in a different craft (calligraphy, welding, neon, casting, 3D printing, carving, carpentry, bricks, embroidery, laser, concrete, blocks, kintsugi, stencil, light bulbs, topiary). | `tool/build_booth_macos.sh` |
| **Name City · 名前の街** | 3D (flutter_scene, Flutter 3.47+): a crew builds the name letter by letter as a wall of brick pixels — the truck brings the bricks, they kern each pair by hand, plaster the jagged edges smooth (anti-aliasing) and paint the letters — while the Glyph Works next door takes the same name from UTF-8 bytes to pixels; then a team photo, the next name's blueprint, the wrecking ball and the cleanup. Round it, a mini world of the talk's ideas: Script Alley (every script breaks a rule), the tofu shop (font fallback, .notdef), the ligature forge (shaping), the line-break tram (greedy breaking, kinsoku), the bidi works (memory ≠ screen), the glyph atlas, the pixel farm (coverage → grey), the wght gym (variable fonts), a family emoji out for a walk (1 grapheme, 7 code points), the Unicode tower (128 → 172,808), a relay down Flutter's text stack (constraints go down, sizes come up) and the itemize works (one string cut into runs by script, each with its direction and font). Cut together like a broadcast: the stories intercut, close-ups, captions; with no one waiting, every other sample word tours the mini world. | `booth3d/tool/build_macos.sh` |

Web previews: `/booth/` and `/workshop/` on the site.

Operator keys (Ctrl+Shift+…): **S** skip · **⌫** remove last in line · **M** factory ↔ workshop ·
**F** full screen · **↑/↓** fast-forward · **H** help · **R** reset today (twice) · **Q** quit.
The booth apps ignore ⌘Q/⌘W/⌘H/⌘M so visitors can't close them.

Frames at chosen scene times, without waiting in real time:

```bash
tool/booth_capture.sh --times 10,60,120 --names "田中太郎" [--mode craft] [--crafts neon]
booth3d/tool/capture.sh --times 10,60,120 --names "田中太郎"
```

Name City's capture log lists every shot as it's cut to (`SHOT <t> cut|glide <phase> · <shot>`),
and `--define "BOOTH3D_LOOK=ex,ey,ez,tx,ty,tz,fov|…"` pins the camera (a view per captured frame)
to try a framing.

Name City keeps itself smooth on a fanless laptop running all day: the 3D view
renders at 1.5× the 1600×900 design canvas (never finer than the screen shows),
steps down when frames run late on the GPU and back up when there's headroom
(`booth3d/lib/quality.dart`); the sky's lighting is baked once per key hour
as the city starts, not live (`booth3d/lib/tuning.dart`). A perf build prints fps,
frame times, memory, scene size and the render ratio every 5 s, and takes the
render settings from the environment to compare their cost:

```bash
cd booth3d && flutter build macos --release --dart-define=BOOTH3D_PERF=true --dart-define=BOOTH_WINDOWED=true
SLIDES_EXPORT=0 BOOTH3D_SPEED=8 BOOTH3D_RATIO=1.5 build/macos/Build/Products/Release/booth3d.app/Contents/MacOS/booth3d
```

Other versions and experiments, each told inside one world:

| version | link |
| --- | --- |
| Glyph factory (full) | https://rahiche.github.io/text-rendering-slides/factory/ |
| Construction site | https://rahiche.github.io/text-rendering-slides/construction/ |
| Easy vs hard (workers) | https://rahiche.github.io/text-rendering-slides/workers/ |
| The case of 直 (detective) | https://rahiche.github.io/text-rendering-slides/detective/ |
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
  from github.com/google/fonts), plus tiny Noto Sans JP / SC subsets for the
  detective world's Han-unification evidence (SIL OFL, via Google Fonts).
