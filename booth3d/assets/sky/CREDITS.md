# Sky

- `sky_4k.hdr` (the Mac app), `sky_2k.hdr` (the web): **Kloofendal 38°
  Partly Cloudy (Pure Sky)** by Greg Zaal and Jarod Guest, from
  [Poly Haven](https://polyhaven.com/a/kloofendal_38d_partly_cloudy_puresky),
  CC0 (public domain).
- Changed: the sun is lifted out of the image (capped at a few times the sky
  around it) by `tool/sky/sky_sun.py`, which measured it first: the city's
  directional light takes its direction and strength (`lib/world/sky.dart`),
  so the image-based light doesn't count it twice.
