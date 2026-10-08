"""The line-breaking tram's car, made in Blender: an open car the words ride
in (its floor at 0.615 m, as the scene puts them), a green body with a
cream band, two bogies of wheels on the rails, low walls behind and at the
ends, a rail in front, corner posts holding up an arched roof, buffers at
each end. Every edge bevelled; colours in the vertex colours (one
material). Its origin: the middle of the car, on the rails' top.

Blender's x is along the track, its y the city's z (−y the platform's
side), its z up.

Run headless:
  Blender -b --factory-startup -P tool/blender/tram.py -- assets/models [--preview dir]
"""

import math
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
PREVIEW = argv[argv.index("--preview") + 1] if "--preview" in argv else None

GREEN = (0.03, 0.27, 0.15)
CREAM = (0.86, 0.80, 0.66)
DARK = (0.025, 0.027, 0.03)
STEEL = (0.32, 0.33, 0.35)
FLOOR = (0.26, 0.27, 0.29)

L, D = 3.1, 1.5  # the car's length and depth

bpy.ops.wm.read_factory_settings(use_empty=True)
parts = []


def coloured(o, rgb):
    me = o.data
    attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    for i in range(len(me.vertices)):
        attr.data[i].color = (rgb[0], rgb[1], rgb[2], 1.0)
    me.color_attributes.active_color = attr
    parts.append(o)
    return o


def bevel(o, width=0.012, segments=2):
    m = o.modifiers.new("bevel", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=m.name)
    return o


def box(x0, x1, y0, y1, z0, z1, rgb, width=0.012):
    bpy.ops.mesh.primitive_cube_add(size=1, location=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
    o = bpy.context.view_layer.objects.active
    o.scale = (x1 - x0, y1 - y0, z1 - z0)
    bpy.ops.object.transform_apply(scale=True)
    return coloured(bevel(o, min(width, (min(x1 - x0, y1 - y0, z1 - z0)) * 0.3)), rgb)


def cyl(x, y, z, r, depth, rgb, axis="Y", verts=24):
    rot = {"Y": (math.pi / 2, 0, 0), "X": (0, math.pi / 2, 0), "Z": (0, 0, 0)}[axis]
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=(x, y, z), rotation=rot)
    o = bpy.context.view_layer.objects.active
    return coloured(bevel(o, min(0.008, depth * 0.2), 1), rgb)


# ── The running gear: a frame, two bogies, their wheels ──────────────────────
box(-1.4, 1.4, -0.55, 0.55, 0.26, 0.34, DARK)
for bx in (-0.95, 0.95):
    box(bx - 0.42, bx + 0.42, -0.62, 0.62, 0.15, 0.25, DARK)
    for wx in (bx - 0.27, bx + 0.27):
        for wy in (-0.55, 0.55):
            cyl(wx, wy, 0.16, 0.15, 0.07, STEEL)
            cyl(wx, wy - 0.045 * (1 if wy > 0 else -1), 0.16, 0.07, 0.03, DARK)

# ── The body: the green deck, the cream band, the floor ──────────────────────
box(-L / 2, L / 2, -D / 2, D / 2, 0.34, 0.5, GREEN, 0.03)
box(-L / 2 - 0.005, L / 2 + 0.005, -D / 2 - 0.005, D / 2 + 0.005, 0.5, 0.555, CREAM, 0.015)
box(-L / 2, L / 2, -D / 2, D / 2, 0.555, 0.615, FLOOR, 0.015)
# The back wall (away from the platform): cream panels, a green top rail.
box(-L / 2, L / 2, D / 2 - 0.08, D / 2 - 0.02, 0.615, 1.17, CREAM)
box(-L / 2 - 0.01, L / 2 + 0.01, D / 2 - 0.09, D / 2 - 0.01, 1.17, 1.23, GREEN)
# The ends: low walls with a green cap.
for s in (-1, 1):
    x = s * (L / 2 - 0.05)
    box(x - 0.05, x + 0.05, -D / 2, D / 2, 0.615, 1.24, CREAM)
    box(x - 0.065, x + 0.065, -D / 2 - 0.01, D / 2 + 0.01, 1.24, 1.29, GREEN)
# The front rail (the platform's side), on short stanchions.
box(-L / 2, L / 2, -D / 2 + 0.03, -D / 2 + 0.08, 0.66, 0.71, CREAM)
for x in (-0.9, 0.0, 0.9):
    box(x - 0.025, x + 0.025, -D / 2 + 0.03, -D / 2 + 0.08, 0.615, 0.67, CREAM)
# A short skirt over the wheels' tops, both sides (the bogies show below).
for y in (-D / 2 - 0.02, D / 2 + 0.02):
    box(-L / 2 + 0.15, L / 2 - 0.15, y - 0.025, y + 0.025, 0.24, 0.34, DARK, 0.01)

# ── The posts and the arched roof ────────────────────────────────────────────
for x in (-L / 2 + 0.05, L / 2 - 0.05):
    for y in (-D / 2 + 0.07, D / 2 - 0.07):
        cyl(x, y, 1.9, 0.032, 1.35, CREAM, axis="Z", verts=16)
bpy.ops.mesh.primitive_grid_add(x_subdivisions=2, y_subdivisions=14, size=1, location=(0, 0, 0))
roof = bpy.context.view_layer.objects.active
for v in roof.data.vertices:
    v.co.x *= L + 0.14
    v.co.y *= D + 0.16
    t = v.co.y / ((D + 0.16) / 2)
    v.co.z = 2.56 + 0.1 * (1 - t * t)
sol = roof.modifiers.new("solidify", "SOLIDIFY")
sol.thickness = 0.05
bpy.context.view_layer.objects.active = roof
bpy.ops.object.modifier_apply(modifier=sol.name)
bpy.ops.object.shade_smooth()
coloured(bevel(roof, 0.01, 2), GREEN)
# A cream line under the roof's edge.
box(-L / 2 - 0.06, L / 2 + 0.06, -D / 2 - 0.07, D / 2 + 0.07, 2.5, 2.545, CREAM, 0.01)

# ── Buffers at both ends ─────────────────────────────────────────────────────
for s in (-1, 1):
    for y in (-0.42, 0.42):
        cyl(s * (L / 2 + 0.05), y, 0.42, 0.06, 0.1, DARK, axis="X", verts=16)

# ── One mesh, out ────────────────────────────────────────────────────────────
bpy.ops.object.select_all(action="DESELECT")
for o in parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
car = bpy.context.view_layer.objects.active
car.name = "car"
car.data.color_attributes.active_color = car.data.color_attributes["Col"]
car.data.color_attributes.render_color_index = car.data.color_attributes.active_color_index
bpy.ops.export_scene.gltf(
    filepath=f"{OUT}/tram_car.glb",
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
print(f"MODEL tram_car: {sum(len(p.vertices) - 2 for p in car.data.polygons)} tris")

if PREVIEW:
    scene = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 40
    scene.collection.objects.link(cam)
    cam.location = (2.6, -5.2, 2.2)
    cam.rotation_euler = (Vector((0, 0, 1.2)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.color_type = "VERTEX"
    scene.display.shading.light = "STUDIO"
    scene.render.resolution_x = 800
    scene.render.resolution_y = 500
    scene.render.filepath = f"{PREVIEW}/tram_car.png"
    bpy.ops.render.render(write_still=True)
