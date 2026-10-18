"""Name City's rigged people: MakeHuman bodies and clothes (CC0, via MPFB,
the MakeHuman plugin for Blender; assets/people/CREDITS.md), each on the
same 'game engine' skeleton (pelvis, spine_01-03, neck_01, head, clavicle,
upperarm, lowerarm, hand, thigh, calf, foot, ball, fingers), exported as a
skinned glTF a person. The low-poly body proxy, not the full base mesh; no
MakeHuman head: from the neck up everyone is the city's own one simple head
(people.glb), hung on the 'head' bone in the app, so every face stays the
same. Clothes keep their own textures.

The crew's people also get a hi-vis vest (made here from their top: no
sleeves, a little out from it) with two bands of reflective tape, and work
gloves (over the hands, which stay: the app shows the vest, the tape and
the gloves only on those who wear them, and tints the plain garments: see
atlas.json and rigged.dart).

Run headless (MPFB installed with mpfb_setup.py's packs):
  Blender -b --factory-startup -P tool/blender/humans.py -- <out dir> [name...]
"""

import json
import os
import sys

import addon_utils
import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
ONLY = set(argv[1:])

# (Enabled in this session's preferences, which MPFB reads; a factory-startup
# background run never saves them.)
addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)

from bl_ext.user_default.mpfb.services.humanservice import HumanService  # noqa: E402
from bl_ext.user_default.mpfb.services.locationservice import LocationService  # noqa: E402
from bl_ext.user_default.mpfb.services.targetservice import TargetService  # noqa: E402

# Not CC0 (CC-BY): never used.
DENY = {"culturalibre_heroine_boots_4"}


def asset(kind, name, ext):
    if name in DENY:
        raise ValueError(f"{name} is not CC0")
    return os.path.join(LocationService.get_user_data(kind), name, f"{name}.{ext}")


# name: body (gender 0 female … 1 male, age 0.5 ≈ 25 y, …, race mix), the
# body proxy (male1591, female1605: the light ones), clothes.
def _b(gender, age, muscle, weight, height, asian=0.75, caucasian=0.15, african=0.1, proportions=0.55):
    return dict(gender=gender, age=age, muscle=muscle, weight=weight, height=height, proportions=proportions,
                race=dict(asian=asian, caucasian=caucasian, african=african))


PEOPLE = {
    # The crew (their hard hats are the city's own): a plain top and work
    # trousers the app tints, boots; the vest, its tape and gloves.
    "worker_a": (_b(1.0, 0.55, 0.62, 0.55, 0.55), "male1591", ["namuhekam_male_polo_shirt", "cortu_cargo_pants", "toigo_ankle_boots_male"], True),
    "worker_b": (_b(1.0, 0.45, 0.7, 0.5, 0.6, asian=0.4, caucasian=0.5, african=0.1), "male1591", ["elvs_crude_t-shirt_male", "cortu_cargo_pants", "shoes03"], True),
    "worker_c": (_b(0.0, 0.55, 0.6, 0.45, 0.5), "female1605", ["joepal_crude_t-shirt_female", "cortu_cargo_pants", "toigo_ankle_boots_female"], True),
    "worker_d": (_b(1.0, 0.75, 0.55, 0.7, 0.45, asian=0.2, caucasian=0.2, african=0.6), "male1591", ["elvs_crude_t-shirt_male", "toigo_wool_pants", "toigo_ankle_boots_male"], True),
    # People in the street: suits, knits, shirts and jeans, a dress, skirts.
    "office_m1": (_b(1.0, 0.5, 0.45, 0.5, 0.55), "male1591", ["toigo_male_suit_3", "shoes04"], False),
    "office_m2": (_b(1.0, 0.7, 0.4, 0.62, 0.5, asian=0.3, caucasian=0.6, african=0.1), "male1591", ["toigo_male_double-breasted_suit", "shoes01"], False),
    "office_m3": (_b(1.0, 0.6, 0.45, 0.55, 0.6), "male1591", ["toigo_male_suit_tie_and_jacket", "shoes04"], False),
    "casual_m1": (_b(1.0, 0.45, 0.5, 0.45, 0.6), "male1591", ["toigo_fisherman_sweater", "toigo_wool_pants", "shoes05"], False),
    "casual_m2": (_b(1.0, 0.5, 0.5, 0.55, 0.5, asian=0.2, caucasian=0.2, african=0.6), "male1591", ["male_casualsuit03", "shoes02"], False),
    "casual_m3": (_b(1.0, 0.4, 0.55, 0.4, 0.65, asian=0.5, caucasian=0.45, african=0.05), "male1591", ["male_casualsuit06", "shoes06"], False),
    "casual_m4": (_b(1.0, 0.55, 0.5, 0.6, 0.45), "male1591", ["elvs_crude_t-shirt_male", "toigo_wool_pants", "shoes05"], False),
    "office_f1": (_b(0.0, 0.55, 0.4, 0.45, 0.5), "female1605", ["toigo_female_suit", "toigo_mj_cloth_shoes"], False),
    "office_f2": (_b(0.0, 0.5, 0.4, 0.4, 0.55, asian=0.4, caucasian=0.55, african=0.05), "female1605", ["female_elegantsuit01", "shoes04"], False),
    "office_f3": (_b(0.0, 0.65, 0.4, 0.5, 0.45), "female1605", ["toigo_female_double-breasted_suit", "toigo_mj_cloth_shoes"], False),
    "casual_f1": (_b(0.0, 0.5, 0.45, 0.45, 0.45), "female1605", ["joepal_crude_t-shirt_female", "toigo_long_full_skirt", "toigo_mj_cloth_shoes"], False),
    "casual_f2": (_b(0.0, 0.55, 0.4, 0.5, 0.5, asian=0.2, caucasian=0.3, african=0.5), "female1605", ["toigo_shift_dress", "toigo_ankle_boots_female"], False),
    "casual_f3": (_b(0.0, 0.5, 0.5, 0.4, 0.55), "female1605", ["female_casualsuit01", "shoes05"], False),
    "casual_f4": (_b(0.0, 0.6, 0.45, 0.55, 0.5, asian=0.5, caucasian=0.45, african=0.05), "female1605", ["toigo_fisherman_sweater", "toigo_wool_pants", "shoes05"], False),
    # The Glyph Works' makers: a lab coat (the skirt suit, jacket and skirt,
    # white in the app: a coat to the knee) over trousers cut off under its
    # hem, and gloves.
    "lab_m": (_b(1.0, 0.5, 0.45, 0.5, 0.55, asian=0.6, caucasian=0.3, african=0.1), "male1591", ["toigo_female_suit", "toigo_wool_pants", "shoes05"], "lab"),
    "lab_f": (_b(0.0, 0.5, 0.45, 0.45, 0.5), "female1605", ["toigo_female_suit", "toigo_wool_pants", "toigo_mj_cloth_shoes"], "lab"),
}

# The crew's gloves (shown only on those who wear them: the hands under them
# stay).
GLOVES = "toigo_gloves_short"

# Triangles at most: the body (what clothes leave showing), each garment
# (shoes and gloves less: they're small).
BODY_TRIS, WEAR_TRIS, SMALL_TRIS = 2500, 3000, 700
SMALL = ("boots", "shoes", "glove", "hat", "cap", "helmet")


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def behead(o, rig, threshold=0.5):
    """Deletes what of [o] hangs from the 'head' bone (the neck stays)."""
    g = o.vertex_groups.get("head")
    if g is None:
        return 0
    doomed = [v.index for v in o.data.vertices if any(e.group == g.index and e.weight >= threshold for e in v.groups)]
    import bmesh

    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.verts[i] for i in doomed], context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    return len(doomed)


def finish(o, budget):
    """Applies the masks (the body under clothes), then brings [o] down to
    [budget] triangles; its skin weights come along."""
    bpy.context.view_layer.objects.active = o
    for m in [m for m in o.modifiers if m.type == "MASK"]:
        bpy.ops.object.modifier_move_to_index(modifier=m.name, index=0)
        bpy.ops.object.modifier_apply(modifier=m.name)
    n = tris(o)
    if n > budget:
        m = o.modifiers.new("decimate", "DECIMATE")
        m.decimate_type = "COLLAPSE"
        m.ratio = budget / n
        m.use_collapse_triangulate = True
        bpy.ops.object.modifier_move_to_index(modifier=m.name, index=0)
        bpy.ops.object.modifier_apply(modifier=m.name)
    return n


def maps(name):
    """A garment's colour and normal maps (from the .mhmat its .mhclo names)."""
    out = {}
    clo = asset("clothes", name, "mhclo")
    mat = next((line.split(None, 1)[1].strip() for line in open(clo, encoding="utf-8", errors="replace") if line.startswith("material ")), f"{name}.mhmat")
    path = os.path.join(os.path.dirname(clo), mat)
    for line in open(path, encoding="utf-8", errors="replace"):
        k, _, v = line.strip().partition(" ")
        if k in ("diffuseTexture", "normalmapTexture") and v:
            out["albedo" if k == "diffuseTexture" else "normal"] = os.path.join(os.path.dirname(path), v.strip())
    return out


def vest_from(top, rig, name):
    """A hi-vis vest from [top] (fitted to the body, skinned): no sleeves,
    pushed out a little; and its reflective tape, two bands round it."""
    import bmesh

    def copy(o, label):
        c = o.copy()
        c.data = o.data.copy()
        c.name = c.data.name = label
        bpy.context.collection.objects.link(c)
        return c

    from mathutils import Vector

    vest = copy(top, "hivis_vest")
    inv = vest.matrix_world.inverted()
    # (Metres in the world; the mesh may be in other units.)
    k = 1 / vest.matrix_world.to_scale().x
    # The armholes: straight cuts a little inside the shoulders, the sleeves
    # beyond them gone (a clean edge, not the shirt's triangles').
    reach = 0.85 * abs((rig.matrix_world @ rig.data.bones["upperarm_l"].head_local).x)
    bm = bmesh.new()
    bm.from_mesh(vest.data)
    for side in (-1, 1):
        at = inv @ Vector((side * reach, 0, 0))
        out = (inv.to_3x3() @ Vector((side, 0, 0))).normalized()
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=at, plane_no=out, clear_outer=True)
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * 0.012 * k
    bm.to_mesh(vest.data)
    bm.free()
    # The tape: the vest's faces in two bands (a third and two thirds up
    # from the hips to the shoulders), a little further out.
    hips = (rig.matrix_world @ rig.data.bones["thigh_l"].head_local).z
    shoulders = (rig.matrix_world @ rig.data.bones["upperarm_l"].head_local).z
    bands = [(hips + f * (shoulders - hips), hips + (f + 0.1) * (shoulders - hips)) for f in (0.3, 0.6)]
    # (The vest cut along the bands' edges first, so they run clean.)
    from mathutils import Vector

    inv = vest.matrix_world.inverted()
    bm = bmesh.new()
    bm.from_mesh(vest.data)
    for lo, hi in bands:
        for z in (lo, hi):
            at = inv @ Vector((0, 0, z))
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=at, plane_no=(inv.to_3x3() @ Vector((0, 0, 1))).normalized())
    bm.to_mesh(vest.data)
    bm.free()
    tape = copy(vest, "hivis_tape")
    bm = bmesh.new()
    bm.from_mesh(tape.data)
    keep = {f for f in bm.faces if any(lo <= (vest.matrix_world @ f.calc_center_median()).z <= hi for lo, hi in bands)}
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f not in keep], context="FACES")
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * 0.004 * k
    bm.to_mesh(tape.data)
    bm.free()
    return vest, tape


def cut_under(trousers, coat, overlap=0.06):
    """[trousers] cut off a little above [coat]'s hem: only what shows
    under it stays (none of it through the coat as the legs move)."""
    import bmesh
    from mathutils import Vector

    hem = min((coat.matrix_world @ v.co).z for v in coat.data.vertices)
    inv = trousers.matrix_world.inverted()
    bm = bmesh.new()
    bm.from_mesh(trousers.data)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=inv @ Vector((0, 0, hem + overlap)), plane_no=(inv.to_3x3() @ Vector((0, 0, 1))).normalized(), clear_outer=True)
    bm.to_mesh(trousers.data)
    bm.free()
    return hem


def build(name, body, proxy, wear, crew):
    clear()
    macro = TargetService.get_default_macro_info_dict()
    for k, v in body.items():
        if k == "race":
            macro["race"].update(v)
        else:
            macro[k] = v
    base = HumanService.create_human(macro_detail_dict=macro, scale=0.1, feet_on_ground=True)
    rig = HumanService.add_builtin_rig(base, "game_engine", import_weights=True)
    body_mesh = HumanService.add_mhclo_asset(asset("proxymeshes", proxy, "proxy"), base, asset_type="Proxymeshes", subdiv_levels=0, material_type="NONE")
    clothes = [HumanService.add_mhclo_asset(asset("clothes", c, "mhclo"), base, asset_type="Clothes", subdiv_levels=0, material_type="MAKESKIN") for c in wear]
    extra = []
    if crew:
        # Gloves over the hands, which stay (not everyone wears them).
        gloves = HumanService.add_mhclo_asset(asset("clothes", GLOVES, "mhclo"), base, asset_type="Clothes", subdiv_levels=0, material_type="MAKESKIN")
        for m in [m for m in body_mesh.modifiers if m.type == "MASK" and GLOVES in m.name]:
            body_mesh.modifiers.remove(m)
        gloves.name = gloves.data.name = GLOVES
        # The crew's hi-vis vest; a lab coat's trousers, only under it.
        extra = [gloves] if crew == "lab" else [gloves, *vest_from(clothes[0], rig, name)]
        if crew == "lab":
            print(f"HUMAN {name}: trousers cut above the coat's hem at {cut_under(clothes[1], clothes[0]):.3f}")
    cut = behead(body_mesh, rig)
    body_mesh.name = body_mesh.data.name = f"{name}_body"
    report = [f"body {finish(body_mesh, BODY_TRIS)}->{tris(body_mesh)}"]
    for c, o in zip(wear, clothes):
        o.name = o.data.name = c
        small = any(k in c for k in SMALL)
        report.append(f"{c} {finish(o, SMALL_TRIS if small else WEAR_TRIS)}->{tris(o)}")
    for o in extra:
        report.append(f"{o.name} {finish(o, SMALL_TRIS if o.name != 'hivis_vest' else WEAR_TRIS)}->{tris(o)}")
    # Out: the skeleton, the body, the clothes (not the base mesh).
    bpy.ops.object.select_all(action="DESELECT")
    for o in [rig, body_mesh, *clothes, *extra]:
        o.select_set(True)
    bpy.context.view_layer.objects.active = rig
    path = os.path.join(OUT, f"{name}.glb")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_skins=True,
        export_def_bones=True,
        export_animations=False,
        export_materials="NONE",
        export_tangents=True,
    )
    print(f"HUMAN {name}: bones {len(rig.data.bones)}; {'; '.join(report)} tris; head cut {cut} verts -> {path}")
    return {c: maps(c) for c in [*wear, *([GLOVES] if crew else [])]}


# Each garment's maps, for people_textures.py (resized by ffmpeg, not Blender).
manifest = {}
for name, (body, proxy, wear, crew) in PEOPLE.items():
    if not ONLY or name in ONLY:
        manifest.update(build(name, body, proxy, wear, crew))
json.dump(manifest, open(os.path.join(OUT, "garments.json"), "w"), indent=1)
