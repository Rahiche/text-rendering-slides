"""The rigged people's cloth in one texture (each person is one mesh and one
draw in the app): every garment's colour map (and normal map) a 512 px tile
of an atlas, the first tile white (skin, hair and the head take their
colours from the vertices). The plain garments (a T-shirt, work trousers, a
knit) are made neutral grey, about as light as cloth gets, for the app to
tint each person's (rigged.dart). Images in and out by ffmpeg only.

  python3 -I tool/blender/people_atlas.py <garments.json> <out dir>

Writes atlas.jpg and atlas_normal.jpg (4096 x 2048), their 2048 x 1024
halves (_2k, for the web) and atlas.json: the grid, each garment's tile,
which are tinted.
"""

import json
import os
import subprocess
import sys

TILE, COLS, ROWS = 512, 8, 4

# The plain garments, made grey to be tinted.
TINTED = {
    "namuhekam_male_polo_shirt", "elvs_crude_t-shirt_male", "joepal_crude_t-shirt_female", "cortu_cargo_pants",
    "toigo_wool_pants", "toigo_fisherman_sweater", "toigo_female_suit", "toigo_shift_dress", "toigo_gloves_short",
}

# How light a tinted garment is on average (linear): the tint is its colour
# over this.
GREY = 0.8


def read(path):
    """[path] as TILE x TILE RGB bytes."""
    out = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-vf", f"scale={TILE}:{TILE}:flags=lanczos", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        check=True, capture_output=True,
    ).stdout
    assert len(out) == TILE * TILE * 3, path
    return bytearray(out)


def lin(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def srgb(v):
    v = min(1.0, max(0.0, v))
    return round(255 * (v * 12.92 if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055))


def neutral(px):
    """[px] grey, its cloth (what isn't the background round the pattern
    pieces) GREY light in the middle of its shades, the weave and the folds
    kept."""
    lum = [0.2126 * lin(px[i]) + 0.7152 * lin(px[i + 1]) + 0.0722 * lin(px[i + 2]) for i in range(0, len(px), 3)]
    # The background: the corners' colour (told apart as the eye would: in
    # sRGB steps, so a dark cloth on black still counts).
    corners = sorted(((y * TILE + x) * 3 for y in (2, TILE - 3) for x in (2, TILE - 3)), key=lambda o: sum(px[o:o + 3]))
    bg = px[corners[1]:corners[1] + 3]
    cloth = [lum[i // 3] for i in range(0, len(px), 3) if max(abs(px[i + c] - bg[c]) for c in range(3)) > 6]
    # (Hardly anything but the background: the cloth is all of it.)
    cloth = sorted(cloth if len(cloth) > 0.05 * len(lum) else lum)
    # (Its middle shade: a print or a button doesn't count.)
    mean = cloth[len(cloth) // 2]
    k = GREY / max(mean, 1e-3)
    out = bytearray(len(px))
    for i, v in enumerate(lum):
        g = srgb(v * k)
        out[i * 3] = out[i * 3 + 1] = out[i * 3 + 2] = g
    return out, mean


def write(buf, w, h, path, scale=None, normal=False):
    vf = [f"scale={scale[0]}:{scale[1]}:flags=lanczos"] if scale else []
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{w}x{h}", "-i", "-",
         *(["-vf", ",".join(vf)] if vf else []), "-q:v", "3" if normal else "4", "-pix_fmt", "yuvj444p" if normal else "yuvj420p", path],
        input=bytes(buf), check=True,
    )


manifest, out = json.load(open(sys.argv[1])), sys.argv[2]
names = sorted(manifest)
assert len(names) + 1 <= COLS * ROWS, f"{len(names)} garments: more than the atlas holds"
W, H = COLS * TILE, ROWS * TILE
albedo = bytearray(b"\xff" * (W * H * 3))
normal = bytearray(bytes([128, 128, 255]) * (W * H))


def put(atlas, tile, px):
    col, row = tile % COLS, tile // COLS
    for y in range(TILE):
        o = ((row * TILE + y) * W + col * TILE) * 3
        atlas[o:o + TILE * 3] = px[y * TILE * 3:(y + 1) * TILE * 3]


tiles = {"white": 0}
for i, name in enumerate(names, start=1):
    maps = manifest[name]
    px = read(maps["albedo"])
    note = ""
    if name in TINTED:
        px, mean = neutral(px)
        note = f" (grey, from {mean:.2f})"
    put(albedo, i, px)
    if "normal" in maps:
        put(normal, i, read(maps["normal"]))
    tiles[name] = i
    print(f"{i:2d} {name}{note}{' + normal' if 'normal' in maps else ''}")

# (The next tile's left white, as the atlas is: plain cloth, matte in
# atlas_rough.png: the makers' lab coats.)
tiles["plain"] = len(names) + 1

write(albedo, W, H, os.path.join(out, "atlas.jpg"))
write(albedo, W, H, os.path.join(out, "atlas_2k.jpg"), scale=(W // 2, H // 2))
write(normal, W, H, os.path.join(out, "atlas_normal.jpg"), normal=True)
write(normal, W, H, os.path.join(out, "atlas_normal_2k.jpg"), scale=(W // 2, H // 2), normal=True)
json.dump({"cols": COLS, "rows": ROWS, "tile": TILE, "grey": GREY, "tiles": tiles, "tinted": sorted(TINTED & set(names))}, open(os.path.join(out, "atlas.json"), "w"), indent=1)
print(f"ATLAS {len(names)} garments -> {out}")
