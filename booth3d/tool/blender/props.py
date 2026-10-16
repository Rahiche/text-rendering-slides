"""Name City's street furniture from Poly Haven (CC0, assets/models/
CREDITS.md): scanned models brought down to a city's budget and exported as
plain meshes with their UVs, a node per material ('<prop>_<material>'),
standing on the origin at their real size. Their textures go beside them,
resized by tool/blender/prop_textures.py (with ffmpeg: never saved through
Blender, which colour-manages what it saves).

Run headless:
  Blender -b --factory-startup -P tool/blender/props.py -- <polyhaven dir> <out dir>
where <polyhaven dir>/<asset>/<asset>_1k.gltf are the downloads.
"""

import os
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]

# prop: (Poly Haven asset, the objects kept (None: all), triangles per
# material at most).
# (Tried and left out: street_lamp_02, an ornate wall lantern, not a
# modern city's; planter_box_01, an empty crate; concrete_road_barrier,
# nowhere it wouldn't stand in someone's way.)
PROPS = {
    "hydrant": ("fire_hydrant", ["fire_hydrant", "fire_hydrant_cap_01", "fire_hydrant_cap_02", "fire_hydrant_cap_03", "fire_hydrant_chain"], 2000),
    "bin": ("metal_trash_can", ["metal_trash_can", "metal_trash_can_lid", "metal_trash_can_handle_left", "metal_trash_can_handle_right"], 1500),
}


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def build(prop, asset, keep, budget):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, asset, f"{asset}_1k.gltf"))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if keep is not None:
        drop = [o for o in meshes if o.name not in keep]
        meshes = [o for o in meshes if o.name in keep]
        for o in drop:
            bpy.data.objects.remove(o, do_unlink=True)
    # Unparent (keeping where they are), apply transforms, join.
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(meshes) > 1:
        bpy.ops.object.join()
    whole = bpy.context.view_layer.objects.active
    before = tris(whole)
    # Standing on the origin, centred over it.
    xs = [v.co.x for v in whole.data.vertices]
    ys = [v.co.y for v in whole.data.vertices]
    zs = [v.co.z for v in whole.data.vertices]
    cx, cy, z0 = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs)
    for v in whole.data.vertices:
        v.co.x -= cx
        v.co.y -= cy
        v.co.z -= z0
    # A part per material, each brought down to the budget.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="MATERIAL")
    bpy.ops.object.mode_set(mode="OBJECT")
    parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    report = []
    for o in parts:
        mat = o.active_material.name if o.active_material else "part"
        o.name = o.data.name = f"{prop}_{mat}"
        n = tris(o)
        if n > budget:
            m = o.modifiers.new("decimate", "DECIMATE")
            m.decimate_type = "COLLAPSE"
            m.ratio = budget / n
            m.use_collapse_triangulate = True
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.modifier_apply(modifier=m.name)
        report.append(f"{o.name} {n}->{tris(o)}")
    bpy.ops.object.select_all(action="SELECT")
    path = os.path.join(OUT, f"{prop}.glb")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_normals=True,
        export_texcoords=True,
        export_materials="NONE",
    )
    size = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
    print(f"PROP {prop}: {before} tris; {', '.join(report)}; size {size[0]:.2f} x {size[1]:.2f} x {size[2]:.2f} m (x, depth, height) -> {path}")


for prop, (asset, keep, budget) in PROPS.items():
    build(prop, asset, keep, budget)
