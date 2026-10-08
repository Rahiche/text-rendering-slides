"""The ligature forge's anvil and hammer, made in Blender.

The anvil (a London pattern: stepped feet, a waist, a body flaring up to
its flat face, a horn tapering to a point, a heel) is built from simple
solids, merged into one casting (voxel remesh), its edges softened and
brought down to a few thousand triangles; the polished face is lighter in
its vertex colours than the cast iron. Its origin is the middle of its
feet; its face 0.355 m up; its horn points −x.

The hammer: a turned wooden handle ('handle') and a forged head ('head':
a round striking face, a square cheek, a cross peen), hanging from the
hand: its origin at the grip, the handle down −z, the striking face
towards −y (the city's −z, once exported: Blender's y is the city's z,
its z the city's y).

Run headless:
  Blender -b --factory-startup -P tool/blender/forge.py -- assets/models [--preview dir]
"""

import math
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
PREVIEW = argv[argv.index("--preview") + 1] if "--preview" in argv else None


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def active():
    return bpy.context.view_layer.objects.active


def apply(obj, mod):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)


def frustum(x, y, z0, z1, w0, d0, w1, d1):
    """A square frustum from w0×d0 at z0 up to w1×d1 at z1."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, (z0 + z1) / 2))
    o = active()
    for v in o.data.vertices:
        top = v.co.z > 0
        v.co.x *= w1 if top else w0
        v.co.y *= d1 if top else d0
        v.co.z *= z1 - z0
    return o


def block(x0, x1, y0, y1, z0, z1):
    bpy.ops.mesh.primitive_cube_add(size=1, location=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
    o = active()
    o.scale = (x1 - x0, y1 - y0, z1 - z0)
    bpy.ops.object.transform_apply(scale=True)
    return o


def merge(parts, name, voxel, tris, smooth=0.5):
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    o = active()
    o.name = name
    m = o.modifiers.new("remesh", "REMESH")
    m.mode = "VOXEL"
    m.voxel_size = voxel
    apply(o, m)
    s = o.modifiers.new("smooth", "SMOOTH")
    s.factor = smooth
    s.iterations = 2
    apply(o, s)
    n = sum(len(p.vertices) - 2 for p in o.data.polygons)
    d = o.modifiers.new("decimate", "DECIMATE")
    d.ratio = min(1.0, tris / max(1, n))
    apply(o, d)
    bpy.ops.object.shade_smooth()
    return o


def colours(o, k_of):
    me = o.data
    attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    for i, v in enumerate(me.vertices):
        c = k_of(v.co, v.normal)
        attr.data[i].color = (c[0], c[1], c[2], 1.0)
    me.color_attributes.active_color = attr
    me.color_attributes.render_color_index = me.color_attributes.active_color_index


def export(name):
    bpy.ops.object.select_all(action="SELECT")
    path = f"{OUT}/{name}.glb"
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_normals=True,
        export_texcoords=False,
        export_materials="NONE",
        export_vertex_color="ACTIVE",
        export_active_vertex_color_when_no_material=True,
    )
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.context.scene.objects if o.type == "MESH")
    print(f"MODEL {name}: {tris} tris -> {path}")


def preview(path, at, target, lens=50):
    scene = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = lens
    scene.collection.objects.link(cam)
    cam.location = at
    cam.rotation_euler = (Vector(target) - Vector(at)).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.color_type = "VERTEX"
    scene.display.shading.light = "STUDIO"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 480
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


# ── The anvil ────────────────────────────────────────────────────────────────

reset()
parts = [
    # The feet: a stepped base.
    block(-0.19, 0.19, -0.125, 0.125, 0.0, 0.045),
    frustum(0.0, 0.0, 0.04, 0.1, 0.34, 0.22, 0.24, 0.15),
    # The waist, and the flare up to the body.
    frustum(0.0, 0.0, 0.1, 0.205, 0.22, 0.14, 0.17, 0.105),
    frustum(0.02, 0.0, 0.2, 0.25, 0.17, 0.105, 0.4, 0.13),
    # The body and its face; the heel.
    block(-0.16, 0.25, -0.065, 0.065, 0.245, 0.355),
    block(0.24, 0.31, -0.05, 0.05, 0.26, 0.355),
]
# The horn: a cone along −x, its top close to the face.
bpy.ops.mesh.primitive_cone_add(vertices=32, radius1=0.056, radius2=0.004, depth=0.24, location=(-0.27, 0.0, 0.3), rotation=(0.0, -math.pi / 2 + 0.05, 0.0))
parts.append(active())
anvil = merge(parts, "anvil", voxel=0.0045, tris=3200, smooth=0.35)


def anvil_colour(co, n):
    # Cast iron; the working face and the horn's top polished by use.
    iron = 0.32
    face = 1.0 if (co.z > 0.345 and n.z > 0.8) else 0.0
    horn = 0.55 if (co.x < -0.16 and n.z > 0.5) else 0.0
    k = max(iron, face, horn)
    return (k, k, k * 1.02)


colours(anvil, anvil_colour)
export("anvil")
if PREVIEW:
    preview(f"{PREVIEW}/anvil.png", (0.55, -0.75, 0.55), (0.0, 0.0, 0.2), 45)

# ── The hammer ───────────────────────────────────────────────────────────────

reset()
# The handle: a tapered, slightly oval shaft from the grip down to the head.
bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=1.0, depth=1.0, location=(0.0, 0.0, -0.16))
handle = active()
handle.name = "handle"
for v in handle.data.vertices:
    t = 0.5 - v.co.z  # 0 at the top, 1 at the bottom
    r = 0.017 + 0.004 * t
    v.co.x *= r * 1.15
    v.co.y *= r
    v.co.z *= 0.37
bpy.ops.object.shade_smooth()
colours(handle, lambda co, n: (0.62, 0.42, 0.24))
# The head: round striking face (−y), a square cheek, a cross peen (+y).
hz = -0.34
face = bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.04, depth=0.07, location=(0.0, -0.105, hz), rotation=(math.pi / 2, 0.0, 0.0))
face = active()
cheek = block(-0.036, 0.036, -0.075, 0.02, hz - 0.036, hz + 0.036)
# (A wedge along +y, thinning in z to an edge across x.)
peen = block(-0.034, 0.034, 0.015, 0.085, hz - 0.034, hz + 0.034)
for v in peen.data.vertices:
    if v.co.y > 0.05:
        v.co.z = hz + (v.co.z - hz) * 0.18
head = merge([face, cheek, peen], "head", voxel=0.003, tris=1400, smooth=0.25)
colours(head, lambda co, n: ((0.95, 0.95, 0.97) if co.y < -0.13 else (0.42, 0.43, 0.46)))
export("hammer")
if PREVIEW:
    preview(f"{PREVIEW}/hammer.png", (0.45, -0.35, -0.1), (0.0, -0.03, -0.25), 55)
