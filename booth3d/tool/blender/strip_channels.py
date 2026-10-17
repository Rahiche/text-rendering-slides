"""Keeps a motions GLB's rotations and its pelvis's travel, nothing else:
Blender's exporter writes every bone's translation and scale too, and a
translation on every bone would give everyone who plays a clip the
reference body's bone lengths. Repacks the binary so what's dropped doesn't
ship.

  python3 -I tool/blender/strip_channels.py <in.glb> <out.glb> [kept-translation-node ...]
"""

import json
import struct
import sys

src, dst = sys.argv[1], sys.argv[2]
keep_translation = set(sys.argv[3:]) or {"pelvis"}

data = open(src, "rb").read()
_, _, _ = struct.unpack_from("<III", data, 0)
jlen, _ = struct.unpack_from("<II", data, 12)
g = json.loads(data[20:20 + jlen])
blen, _ = struct.unpack_from("<II", data, 20 + jlen)
binary = data[28 + jlen:28 + jlen + blen]

nodes = g["nodes"]
for a in g.get("animations", []):
    kept_channels, kept_samplers, remap = [], [], {}
    for ch in a["channels"]:
        path = ch["target"]["path"]
        name = nodes[ch["target"]["node"]].get("name")
        if path == "rotation" or (path == "translation" and name in keep_translation):
            s = ch["sampler"]
            if s not in remap:
                remap[s] = len(kept_samplers)
                kept_samplers.append(a["samplers"][s])
            kept_channels.append({**ch, "sampler": remap[s]})
    a["channels"], a["samplers"] = kept_channels, kept_samplers

# Only the accessors still used (the samplers'), their views repacked.
used = sorted({s[k] for a in g.get("animations", []) for s in a["samplers"] for k in ("input", "output")})
accessor_map = {old: new for new, old in enumerate(used)}
views, chunks, offset = [], [], 0
new_accessors = []
for old in used:
    acc = dict(g["accessors"][old])
    view = g["bufferViews"][acc["bufferView"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    comps = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[acc["type"]]
    size = {5126: 4, 5123: 2, 5125: 4, 5121: 1, 5120: 1, 5122: 2}[acc["componentType"]]
    stride = view.get("byteStride", comps * size)
    raw = b"".join(binary[start + i * stride:start + i * stride + comps * size] for i in range(acc["count"]))
    pad = (-offset) % 4
    chunks.append(b"\0" * pad)
    offset += pad
    views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(raw)})
    chunks.append(raw)
    offset += len(raw)
    acc["bufferView"] = len(views) - 1
    acc.pop("byteOffset", None)
    new_accessors.append(acc)
for a in g.get("animations", []):
    for s in a["samplers"]:
        s["input"] = accessor_map[s["input"]]
        s["output"] = accessor_map[s["output"]]
g["accessors"] = new_accessors
g["bufferViews"] = views
body = b"".join(chunks)
body += b"\0" * ((-len(body)) % 4)
g["buffers"] = [{"byteLength": len(body)}]

j = json.dumps(g, separators=(",", ":")).encode()
j += b" " * ((-len(j)) % 4)
out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(j) + 8 + len(body))
out += struct.pack("<II", len(j), 0x4E4F534A) + j
out += struct.pack("<II", len(body), 0x004E4942) + body
open(dst, "wb").write(out)
n = sum(len(a["channels"]) for a in g.get("animations", []))
print(f"STRIP {src.rsplit('/', 1)[-1]}: {n} channels kept, {len(data)} -> {len(out)} bytes")
