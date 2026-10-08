"""The city's traffic, made in Blender: a sedan, a taxi (a tall Tokyo cab,
indigo with an amber stripe), a kei car (a tall box), a van and a city bus
(cream, a green stripe, a band of windows, an air-conditioning pod on the
roof). Each is a side profile extruded across the car and bevelled, a
glass cabin narrowing towards its roof, tyres with hubs, bumpers.

Their sizes and the heights of their lamps are the city's (life.dart):
the lamps stay where they were. Front is +x; Blender's y is the city's z
(across), its z up; the origin is the middle of the car on the road.

Body panels are white in the vertex colours (the city paints each car);
glass, trim, tyres, the taxi and the bus have their own colours.

Run headless:
  Blender -b --factory-startup -P tool/blender/vehicles.py -- assets/models [--preview dir]
writes vehicles.glb: one mesh a kind, named sedan, taxi, kei, van, bus.
"""

import math
import sys

import bmesh
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
PREVIEW = argv[argv.index("--preview") + 1] if "--preview" in argv else None


def lin(rgb):
    return tuple(((rgb >> s) & 0xFF) / 255.0 for s in (16, 8, 0))


def lin22(rgb):
    return tuple(c ** 2.2 for c in lin(rgb))


WHITE = (1.0, 1.0, 1.0)
GLASS = lin22(0x1A2C46)
TRIM = lin22(0x2A3344)
TYRE = lin22(0x14171D)
HUB = (0.32, 0.33, 0.35)
INDIGO = lin22(0x1E2C52)
AMBER = lin22(0xFFC66D)
CREAM = lin22(0xF2EEE4)
GREEN = lin22(0x6CE5B1)
ROOFGREY = lin22(0xDCD6C8)

bpy.ops.wm.read_factory_settings(use_empty=True)


def colour(o, rgb):
    me = o.data
    attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    for i in range(len(me.vertices)):
        attr.data[i].color = (rgb[0], rgb[1], rgb[2], 1.0)
    me.color_attributes.active_color = attr
    return o


def bevel(o, width, segments=3):
    m = o.modifiers.new("bevel", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(35)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=m.name)
    return o


def prism(name, xz, half, top_half=None, rgb=WHITE, bev=0.05, segs=3):
    """A side profile [xz] (counter-clockwise, x along the car, z up)
    extruded across ±[half]; its upper vertices pulled in to ±[top_half]
    (a cabin narrowing to its roof)."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    front = [bm.verts.new((x, -half, z)) for x, z in xz]
    back = [bm.verts.new((x, half, z)) for x, z in xz]
    n = len(xz)
    bm.faces.new(list(reversed(front)))
    bm.faces.new(back)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([front[i], front[j], back[j], back[i]])
    if top_half is not None:
        zs = [z for _, z in xz]
        z0, z1 = min(zs), max(zs)
        for v in bm.verts:
            t = (v.co.z - z0) / max(1e-6, z1 - z0)
            s = (half + (top_half - half) * t) / half
            v.co.y *= s
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    if bev > 0:
        bevel(o, bev, segs)
    for p in o.data.polygons:
        p.use_smooth = True
    return colour(o, rgb)


def _box(name, x0, x1, y0, y1, z0, z1, rgb, bev):
    bpy.ops.mesh.primitive_cube_add(size=1, location=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.scale = (x1 - x0, y1 - y0, z1 - z0)
    bpy.ops.object.transform_apply(scale=True)
    if bev > 0:
        bevel(o, min(bev, 0.3 * min(x1 - x0, y1 - y0, z1 - z0)), 2)
    return colour(o, rgb)


def wheels(xs, half, r, width=0.22):
    out = []
    for x in xs:
        for s in (-1, 1):
            y = s * (half - width / 2 + 0.02)
            bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=r, depth=width, location=(x, y, r), rotation=(math.pi / 2, 0, 0))
            t = bpy.context.view_layer.objects.active
            bevel(t, 0.04, 2)
            out.append(colour(t, TYRE))
            bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=r * 0.58, depth=0.02, location=(x, y + s * (width / 2 + 0.005), r), rotation=(math.pi / 2, 0, 0))
            out.append(colour(bpy.context.view_layer.objects.active, HUB))
    return out


def join(name, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.data.name = name
    me = o.data
    me.color_attributes.active_color = me.color_attributes["Col"]
    me.color_attributes.render_color_index = me.color_attributes.active_color_index
    return o


cars = []

# ── Sedan: 4.4 × 1.78 ────────────────────────────────────────────────────────
L = 2.2
cars.append(join("sedan", [
    prism("body", [(-L, 0.26), (L, 0.26), (L, 0.74), (L - 0.35, 0.86), (0.95, 0.95), (-1.35, 0.95), (-L + 0.25, 0.9), (-L, 0.78)], 0.89, rgb=WHITE, bev=0.09),
    prism("cabin", [(-1.35, 0.93), (1.0, 0.93), (0.45, 1.4), (-0.95, 1.4)], 0.8, top_half=0.66, rgb=GLASS, bev=0.04),
    prism("roof", [(-0.98, 1.38), (0.48, 1.38), (0.44, 1.45), (-0.94, 1.45)], 0.67, rgb=WHITE, bev=0.025),
    _box("bumper f", L - 0.06, L + 0.03, -0.86, 0.86, 0.26, 0.46, TRIM, 0.03),
    _box("bumper r", -L - 0.03, -L + 0.06, -0.86, 0.86, 0.26, 0.46, TRIM, 0.03),
    *wheels([-1.35, 1.35], 0.86, 0.32),
]))

# ── Taxi: 4.5 × 1.74, tall, indigo, an amber stripe; roof at 1.47 ────────────
L = 2.25
cars.append(join("taxi", [
    prism("body", [(-L, 0.26), (L, 0.26), (L, 0.76), (L - 0.4, 0.9), (1.05, 0.97), (-1.6, 0.97), (-L, 0.92)], 0.87, rgb=INDIGO, bev=0.09),
    prism("cabin", [(-1.62, 0.95), (1.08, 0.95), (0.6, 1.43), (-1.5, 1.43)], 0.8, top_half=0.68, rgb=GLASS, bev=0.04),
    prism("roof", [(-1.52, 1.41), (0.62, 1.41), (0.58, 1.47), (-1.48, 1.47)], 0.69, rgb=INDIGO, bev=0.025),
    _box("stripe", -L + 0.04, L - 0.04, -0.885, 0.885, 0.56, 0.64, AMBER, 0.01),
    _box("bumper f", L - 0.06, L + 0.03, -0.84, 0.84, 0.26, 0.46, TRIM, 0.03),
    _box("bumper r", -L - 0.03, -L + 0.06, -0.84, 0.84, 0.26, 0.46, TRIM, 0.03),
    *wheels([-1.4, 1.4], 0.84, 0.32),
]))

# ── Kei car: 3.4 × 1.48, a tall box ──────────────────────────────────────────
L = 1.7
cars.append(join("kei", [
    prism("body", [(-L, 0.28), (L, 0.28), (L, 0.92), (L - 0.18, 1.06), (-L, 1.06)], 0.74, rgb=WHITE, bev=0.09),
    prism("cabin", [(-L + 0.02, 1.04), (L - 0.2, 1.04), (1.0, 1.72), (-L + 0.06, 1.72)], 0.7, top_half=0.66, rgb=GLASS, bev=0.04),
    prism("roof", [(-L + 0.04, 1.7), (1.02, 1.7), (0.98, 1.79), (-L + 0.08, 1.79)], 0.67, rgb=WHITE, bev=0.03),
    _box("bumper f", L - 0.05, L + 0.03, -0.72, 0.72, 0.28, 0.48, TRIM, 0.03),
    _box("bumper r", -L - 0.03, -L + 0.05, -0.72, 0.72, 0.28, 0.48, TRIM, 0.03),
    *wheels([-1.1, 1.1], 0.72, 0.28),
]))

# ── Van: 4.8 × 1.8, a box with a short nose, a band of windows ───────────────
L = 2.4
cars.append(join("van", [
    prism("body", [(-L, 0.3), (L, 0.3), (L, 1.08), (L - 0.42, 1.9), (-L, 1.95)], 0.9, rgb=WHITE, bev=0.1),
    _box("windows", -2.05, 1.7, -0.905, 0.905, 1.24, 1.74, GLASS, 0.02),
    prism("windscreen", [(L - 0.06, 1.12), (L, 1.12), (L - 0.42, 1.86), (L - 0.48, 1.86)], 0.86, rgb=GLASS, bev=0.0),
    _box("bumper f", L - 0.05, L + 0.04, -0.88, 0.88, 0.3, 0.52, TRIM, 0.03),
    _box("bumper r", -L - 0.04, -L + 0.05, -0.88, 0.88, 0.3, 0.52, TRIM, 0.03),
    *wheels([-1.55, 1.55], 0.88, 0.33),
]))

# ── Bus: 10.5 × 2.5, cream, a green stripe, windows all round ────────────────
L = 5.25
cars.append(join("bus", [
    prism("body", [(-L, 0.32), (L, 0.32), (L, 3.05), (-L, 3.05)], 1.25, rgb=CREAM, bev=0.22, segs=4),
    _box("windows", -L + 0.35, L - 0.25, -1.262, 1.262, 1.55, 2.62, GLASS, 0.03),
    _box("windscreen", L - 0.02, L + 0.012, -1.1, 1.1, 1.1, 2.8, GLASS, 0.02),
    _box("rear window", -L - 0.012, -L + 0.02, -0.95, 0.95, 1.9, 2.75, GLASS, 0.02),
    _box("stripe", -L + 0.1, L - 0.1, -1.262, 1.262, 0.68, 0.88, GREEN, 0.01),
    _box("aircon", -2.6, 2.2, -0.85, 0.85, 3.02, 3.26, ROOFGREY, 0.06),
    _box("bumper f", L - 0.05, L + 0.06, -1.2, 1.2, 0.32, 0.6, TRIM, 0.04),
    _box("bumper r", -L - 0.06, -L + 0.05, -1.2, 1.2, 0.32, 0.6, TRIM, 0.04),
    *wheels([-3.6, 3.4], 1.18, 0.5, 0.3),
]))

bpy.ops.object.select_all(action="DESELECT")
for o in cars:
    o.select_set(True)
bpy.ops.export_scene.gltf(
    filepath=f"{OUT}/vehicles.glb",
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
for o in cars:
    print(f"MODEL {o.name}: {sum(len(p.vertices) - 2 for p in o.data.polygons)} tris")

if PREVIEW:
    for i, o in enumerate(cars):
        o.location.y = [-10.5, -6.5, -2.8, 0.8, 6.0][i]
    scene = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 32
    scene.collection.objects.link(cam)
    cam.location = (11.0, -15.0, 6.0)
    cam.rotation_euler = (Vector((0, -2.5, 1.0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.color_type = "VERTEX"
    scene.display.shading.light = "STUDIO"
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 560
    scene.render.filepath = f"{PREVIEW}/vehicles.png"
    bpy.ops.render.render(write_still=True)
