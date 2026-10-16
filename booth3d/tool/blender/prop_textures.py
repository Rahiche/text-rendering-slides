"""The street furniture's textures (tool/blender/props.py makes the meshes):
for each prop's Poly Haven glTF, each material's colour, normal and ARM
(occlusion, roughness, metal) maps, resized to 512 px by ffmpeg as
<out>/<prop>_<material>_{albedo,normal,arm}.jpg. Materials without maps
(a lamp's glass) are skipped: the city gives those plain values.

  python3 -I tool/blender/prop_textures.py <polyhaven dir> <out dir>
"""

import json
import os
import subprocess
import sys

SRC, OUT = sys.argv[1], sys.argv[2]

PROPS = {
    "hydrant": "fire_hydrant",
    "bin": "metal_trash_can",
}
KEEP = {"fire_hydrant": {"fire_hydrant"}, "metal_trash_can": {"metal_trash_can"}}


def save(src, dst, chroma444):
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", src, "-vf", "scale=512:512:flags=lanczos", "-q:v", "3" if chroma444 else "4", "-pix_fmt", "yuvj444p" if chroma444 else "yuvj420p", dst],
        check=True,
    )


for prop, asset in PROPS.items():
    d = os.path.join(SRC, asset)
    g = json.load(open(os.path.join(d, f"{asset}_1k.gltf")))
    images = [i["uri"] for i in g.get("images", [])]
    tex_image = [t["source"] for t in g.get("textures", [])]
    for m in g.get("materials", []):
        name = m.get("name", "")
        if asset in KEEP and name not in KEEP[asset]:
            continue
        pbr = m.get("pbrMetallicRoughness", {})
        maps = {
            "albedo": pbr.get("baseColorTexture"),
            "normal": m.get("normalTexture"),
            "arm": pbr.get("metallicRoughnessTexture"),
        }
        if maps["albedo"] is None:
            print(f"{prop}_{name}: no maps (plain)")
            continue
        for kind, ref in maps.items():
            if ref is None:
                continue
            src = os.path.join(d, images[tex_image[ref["index"]]])
            save(src, os.path.join(OUT, f"{prop}_{name}_{kind}.jpg"), kind != "albedo")
        print(f"{prop}_{name}: {', '.join(k for k, v in maps.items() if v is not None)}")
