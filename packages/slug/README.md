# slug

Resolution-independent GPU text for Flutter: glyphs are drawn straight from
their TrueType outlines in a fragment shader, using the Slug algorithm
(Eric Lengyel, "GPU-Centered Font Rendering Directly from Glyph Outlines",
[JCGT 2017](https://jcgt.org/published/0006/02/02/)).

Flutter normally rasterizes glyphs into an atlas at a quantized scale and
re-rasterizes them when the scale changes. Slug computes exact per-pixel
coverage from the quadratic curves every frame, so text stays sharp at any
zoom, rotation or perspective, with no re-rasterization.

```dart
final latin = await SlugFont.load('assets/fonts/SpaceGrotesk.ttf');
final jp = await SlugFont.load('assets/fonts/NotoSansJP-case.ttf');

SlugText([
  SlugSpan('直', font: jp, style: const TextStyle(fontSize: 96)),
  SlugSpan(' Text', font: latin, style: const TextStyle(fontSize: 96)),
])
```

How it works:
- A pure-Dart encoder reads `glyf` quadratic outlines, splits each glyph into
  horizontal and vertical bands of curves (sorted for early exit) and packs
  them into an RGBA8 data texture (16-bit values in byte pairs, so it runs on
  the web too).
- `shaders/slug.frag` casts a horizontal and a vertical ray per pixel, solves
  the curve roots and integrates coverage. Pixels-per-em comes from the
  transform, differentiated analytically — exact under perspective, and no
  `fwidth()` (not available on the web).
- Debug views: bands, curves and a per-pixel heat map of curves tested.

Limits: no hinting (use normal `Text` for small body text), no color glyphs,
TrueType (`glyf`) fonts only, simple left-to-right shaping.

Credits: Slug shader code © 2017 Eric Lengyel, MIT License (see `LICENSE`);
ported with Flutter-specific changes documented in `shaders/slug.frag`. The
Slug patent (US 10,373,352) was dedicated to the public domain on
17 March 2026 ([A Decade of Slug](https://terathon.com/blog/decade-slug.html)).
