"""The rigged people's roughness, tile by tile of their atlas
(assets/people/atlas.json): skin (and the heads, the hair, the eyes on the
plain white tile) with a soft sheen, shoes and gloves a little shinier
than cloth, cloth matte; the spare white tile, 'plain', a matte cotton
(the makers' lab coats). Writes assets/people/atlas_rough.png (G the
roughness, B the metal: none), a quarter of the atlas's size: every tile
is one value.

    python3 tool/textures/people_rough.py        (from booth3d/; ffmpeg on the PATH)
"""
import json
import os
import subprocess

OUT = os.path.join("assets", "people")
atlas = json.load(open(os.path.join(OUT, "atlas.json")))
cols, rows, tile = atlas["cols"], atlas["rows"], atlas["tile"] // 4
names = {i: n for n, i in atlas["tiles"].items()}


def roughness(name):
    if name in ("white", None):
        # (Skin; None: the spare tiles, matte.)
        return 0.48 if name == "white" else 0.86
    if name == "plain":
        return 0.86
    if "glove" in name:
        return 0.55
    if "cloth_shoes" in name:
        return 0.8
    if "shoes" in name or "boots" in name:
        return 0.5
    if "suit" in name:
        return 0.78
    return 0.86


img = bytearray(rows * tile * cols * tile * 3)
for y in range(rows * tile):
    for c in range(cols):
        g = round(255 * roughness(names.get((y // tile) * cols + c)))
        o = (y * cols * tile + c * tile) * 3
        img[o : o + tile * 3] = bytes((255, g, 0)) * tile
path = os.path.join(OUT, "atlas_rough.png")
subprocess.run(
    ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{cols * tile}x{rows * tile}", "-i", "-", path],
    input=bytes(img),
    check=True,
)
print(f"{path}: {cols * tile}x{rows * tile}, " + ", ".join(f"{names.get(k, '·')} {roughness(names.get(k)):.2f}" for k in range(cols * rows) if k in names))
