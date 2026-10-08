"""Name City's trees, made in Blender: a trunk that tapers and leans a
little, branches up into the crown, and the crown itself, overlapping
spheres merged into one shell (voxel remesh), lumped like leaves (a clouds
displacement), smoothed and brought down to about a thousand triangles.
Shading (darker underneath and in the hollows) is baked into the vertex
colours; the city tints each tree (green, sakura pink) per instance.

Run headless:
  Blender -b --factory-startup -P tool/blender/trees.py -- assets/models
writes tree_round.glb, tree_tall.glb and tree_wide.glb there, each with two
nodes: 'trunk' and 'crown'. Optionally a preview render (--preview out.png).
"""

import math
import random
import sys

import bpy
from mathutils import Vector, noise

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
PREVIEW = argv[argv.index("--preview") + 1] if "--preview" in argv else None  # a directory

CROWN_TRIS = 1500


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def apply(obj, mod):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)


def shade(obj, k_of):
    """Vertex colours (greys: the city tints them) from k_of(co, t), t the
    height through the mesh (0 bottom, 1 top)."""
    me = obj.data
    attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    zs = [v.co.z for v in me.vertices]
    z0, z1 = min(zs), max(zs)
    for i, v in enumerate(me.vertices):
        k = k_of(v.co, (v.co.z - z0) / max(1e-6, z1 - z0))
        attr.data[i].color = (k, k, k, 1.0)
    me.color_attributes.active_color = attr
    me.color_attributes.render_color_index = me.color_attributes.active_color_index


def tree(name, seed, trunk_top, branches, blobs, reach, spread=(0.55, 0.8), up=(0.6, 1.0)):
    reset()
    rnd = random.Random(seed)
    # ── The wood: the trunk and its branches, tubes tapering to their tips.
    cu = bpy.data.curves.new(name + " wood", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = 1.0
    cu.bevel_resolution = 2
    cu.use_fill_caps = True

    def spline(pts, radii):
        sp = cu.splines.new("POLY")
        sp.points.add(len(pts) - 1)
        for p, co, r in zip(sp.points, pts, radii):
            p.co = (co[0], co[1], co[2], 1.0)
            p.radius = r

    n = 7
    pts, radii = [], []
    for i in range(n + 1):
        t = i / n
        pts.append((0.07 * math.sin(t * 3.1 + seed), 0.05 * math.cos(t * 2.3 + seed), t * trunk_top))
        radii.append(0.2 * (1 - 0.55 * t) * (1.35 if i == 0 else 1.0))
    spline(pts, radii)
    crown_r = reach
    for b in range(branches):
        a = b / branches * 2 * math.pi + rnd.uniform(-0.45, 0.45)
        h0 = trunk_top * rnd.uniform(0.6, 0.9)
        length = crown_r * rnd.uniform(*spread)
        lift = rnd.uniform(*up)
        start = Vector((0.0, 0.0, h0))
        end = start + Vector((math.cos(a) * length, math.sin(a) * length, length * lift))
        mid = (start + end) / 2 + Vector((0.0, 0.0, 0.15))
        spline([start, mid, end], [0.08, 0.055, 0.03])
    wood = bpy.data.objects.new("trunk", cu)
    bpy.context.collection.objects.link(wood)
    bpy.context.view_layer.objects.active = wood
    wood.select_set(True)
    bpy.ops.object.convert(target="MESH")
    wood = bpy.context.view_layer.objects.active
    wood.name = "trunk"
    bpy.ops.object.shade_smooth()
    shade(wood, lambda co, t: 0.62 + 0.38 * min(1.0, t * 1.6))
    wood.select_set(False)

    # ── The crown: spheres merged into one shell, lumped, smoothed.
    parts = []
    for (c, r) in blobs:
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=r, location=c)
        parts.append(bpy.context.view_layer.objects.active)
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    crown = bpy.context.view_layer.objects.active
    crown.name = "crown"
    m = crown.modifiers.new("remesh", "REMESH")
    m.mode = "VOXEL"
    m.voxel_size = 0.07
    apply(crown, m)
    tex = bpy.data.textures.new(name + " leaves", "CLOUDS")
    tex.noise_scale = 0.24
    tex.noise_depth = 2
    d = crown.modifiers.new("displace", "DISPLACE")
    d.texture = tex
    d.strength = 0.24
    d.mid_level = 0.5
    apply(crown, d)
    s = crown.modifiers.new("smooth", "SMOOTH")
    s.factor = 0.6
    s.iterations = 2
    apply(crown, s)
    tris = sum(len(p.vertices) - 2 for p in crown.data.polygons)
    dec = crown.modifiers.new("decimate", "DECIMATE")
    dec.ratio = min(1.0, CROWN_TRIS / max(1, tris))
    apply(crown, dec)
    bpy.ops.object.shade_smooth()
    # Darker underneath and inside, lighter on top; a little leafy mottle.
    centre = sum((Vector(c) for c, _ in blobs), Vector()) / len(blobs)

    def leafy(co, t):
        out = (co - centre).length / crown_r
        k = (0.55 + 0.45 * t ** 0.8) * (0.78 + 0.22 * min(1.0, out))
        return max(0.0, min(1.0, k * (0.93 + 0.14 * noise.noise(co * 1.7))))

    shade(crown, leafy)

    # ── Out: both meshes, their colours, no materials (the city's own).
    bpy.ops.object.select_all(action="SELECT")
    path = f"{OUT}/tree_{name}.glb"
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
    ct = sum(len(p.vertices) - 2 for p in crown.data.polygons)
    wt = sum(len(p.vertices) - 2 for p in wood.data.polygons)
    print(f"TREE {name}: crown {ct} tris, wood {wt} tris -> {path}")
    if PREVIEW:
        preview(f"{PREVIEW}/tree_{name}.png")
    return wood, crown


def preview(path):
    """A quick Workbench render of the last tree, its vertex colours on."""
    scene = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    cam.location = (0.0, -11.0, 3.2)
    cam.rotation_euler = (math.radians(86), 0.0, 0.0)
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.color_type = "VERTEX"
    scene.display.shading.light = "STUDIO"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def crown(c, rx, rz, n, rnd, rmin, rmax):
    """A crown of clusters: a core, and [n] clusters round an ellipsoid
    (radii rx across, rz up) about [c], more up and out than down."""
    out = [(c, min(rx, rz) * 0.7)]
    for _ in range(n):
        z = rnd.uniform(-0.45, 1.0)
        a = rnd.uniform(0, 2 * math.pi)
        s = math.sqrt(max(0.0, 1 - z * z))
        out.append(((c[0] + s * math.cos(a) * rx * 0.78, c[1] + s * math.sin(a) * rx * 0.78, c[2] + z * rz * 0.78), rnd.uniform(rmin, rmax)))
    return out


# (The trunk runs up into the crown; the branches reach out into it, as
# far as [reach] times the given spread.)
tree("round", 1, 3.55, 4, crown((0, 0, 3.8), 1.5, 1.25, 14, random.Random(1), 0.45, 0.7), 1.5, spread=(0.35, 0.55), up=(0.9, 1.3))
tree("tall", 2, 4.0, 3, crown((0, 0, 4.3), 1.0, 1.7, 12, random.Random(2), 0.4, 0.6), 1.0, spread=(0.4, 0.6), up=(0.9, 1.3))
tree("wide", 3, 3.15, 5, crown((0, 0, 3.4), 1.85, 1.0, 16, random.Random(3), 0.45, 0.7), 1.85, spread=(0.55, 0.85), up=(0.3, 0.55))
