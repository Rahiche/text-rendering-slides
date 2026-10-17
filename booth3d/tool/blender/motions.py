"""Name City's motions: motion clips from Quaternius' Universal Animation
Library 1 and 2 (CC0, assets/people/CREDITS.md), retargeted onto the
people's skeleton (MPFB's 'game engine' rig, as humans.py exports it) and
written as motions.glb: that skeleton with one animation a clip.

Retargeting: both skeletons are put in a T-pose (the libraries rest in
one; MPFB's own T-pose for the rig), which gives each bone a fixed turn from
the source's to the target's; every frame, each target bone takes its
source bone's orientation (armature space) times that turn. Rotations only,
and the pelvis's height and travel (scaled to the target's hips), so any
of the people, whatever their size, can play any clip.

  Blender -b --factory-startup -P tool/blender/motions.py -- \\
      <ual1.glb> <ual2.glb> <person.glb> <game_engine t-pose.json> <out.glb> [preview.glb]

(preview.glb: the person with the clips, on one skeleton, to look at.)
Beside out.glb, out.json: each clip's hip height a frame (metres), and the
frame rate, for the app to lower or raise other bodies by.
"""

import json
import sys

import bpy
from mathutils import Euler, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
UAL1, UAL2, PERSON, TPOSE, OUT = argv[:5]
PREVIEW = argv[5] if len(argv) > 5 else None

# Source bone -> target bone. Library 2 uses the target's own names.
_UE = [
    "pelvis", "spine_01", "spine_02", "spine_03", "neck_01",
    *[f"{b}_{s}" for s in "lr" for b in ("clavicle", "upperarm", "lowerarm", "hand", "thigh", "calf", "foot", "ball")],
    *[f"{f}_0{i}_{s}" for s in "lr" for f in ("index", "middle", "ring", "pinky", "thumb") for i in (1, 2, 3)],
]
MAP2 = {n: n for n in _UE} | {"Head": "head"}
_SIDE = {"L": "l", "R": "r"}
MAP1 = {
    "DEF-hips": "pelvis", "DEF-spine.001": "spine_01", "DEF-spine.002": "spine_02", "DEF-spine.003": "spine_03",
    "DEF-neck": "neck_01", "DEF-head": "head",
    **{f"DEF-{a}.{S}": f"{b}_{s}" for S, s in _SIDE.items() for a, b in (
        ("shoulder", "clavicle"), ("upper_arm", "upperarm"), ("forearm", "lowerarm"), ("hand", "hand"),
        ("thigh", "thigh"), ("shin", "calf"), ("foot", "foot"), ("toe", "ball"))},
    **{f"DEF-f_{f}.0{i}.{S}": f"{f}_0{i}_{s}" for S, s in _SIDE.items() for f in ("index", "middle", "ring", "pinky") for i in (1, 2, 3)},
    **{f"DEF-thumb.0{i}.{S}": f"thumb_0{i}_{s}" for S, s in _SIDE.items() for i in (1, 2, 3)},
}

# (library, source clip, our name)
CLIPS = [
    (1, "Idle_Loop", "idle"),
    (1, "Idle_Talking_Loop", "talk"),
    (1, "Walk_Loop", "walk"),
    (1, "Walk_Formal_Loop", "walk_formal"),
    (1, "Jog_Fwd_Loop", "jog"),
    (1, "Interact", "interact"),
    (1, "PickUp_Table", "pick_up"),
    (1, "Push_Loop", "push"),
    (1, "Fixing_Kneeling", "kneel_fix"),
    (1, "Sitting_Idle_Loop", "sit"),
    (1, "Sitting_Talking_Loop", "sit_talk"),
    (2, "Idle_FoldArms_Loop", "arms_folded"),
    (2, "Idle_TalkingPhone_Loop", "phone"),
    (2, "Idle_No_Loop", "no"),
    (2, "Yes", "yes"),
    (2, "Walk_Carry_Loop", "walk_carry"),
    (2, "TreeChopping_Loop", "hammer"),
    (2, "Consume", "drink"),
]


def import_glb(path, keep_meshes=False):
    before_obj, before_act = set(bpy.data.objects), set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=path)
    objs = set(bpy.data.objects) - before_obj
    arm = next(o for o in objs if o.type == "ARMATURE")
    for o in objs:
        if o.type == "MESH" and not keep_meshes:
            bpy.data.objects.remove(o, do_unlink=True)
    return arm, {a.name: a for a in set(bpy.data.actions) - before_act}


def play(arm, action):
    """Gives [arm] [action] (and the action's slot: Blender 5 animates
    nothing without one)."""
    arm.animation_data_create()
    arm.animation_data.action = action
    if action is not None and getattr(action, "slots", None):
        arm.animation_data.action_slot = action.slots[0]


def find_action(actions, clip):
    # (The importer names an action after its animation, sometimes with the
    # armature's name after it.)
    for name, a in actions.items():
        if name == clip or name.startswith(clip + "_") or name.startswith(clip + "."):
            return a
    raise KeyError(clip)


for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
tgt, _ = import_glb(PERSON, keep_meshes=True)
src1, act1 = import_glb(UAL1)
src2, act2 = import_glb(UAL2)
scene = bpy.context.scene


def world(arm, bone):
    return arm.matrix_world @ arm.pose.bones[bone].matrix


# ── Calibration: both in a T-pose ────────────────────────────────────────────
for pb in tgt.pose.bones:
    pb.rotation_mode = "QUATERNION"
    pb.matrix_basis = Matrix.Identity(4)
tpose = json.load(open(TPOSE))["bone_rotations"]
for name, e in tpose.items():
    pb = tgt.pose.bones.get(name)
    if pb is not None:
        pb.rotation_quaternion = Euler(e, "XYZ").to_quaternion()
for src in (src1, src2):
    src.animation_data_clear()
    for pb in src.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()
turn = {}
for src, mapping in ((src1, MAP1), (src2, MAP2)):
    for s, t in mapping.items():
        if s in src.pose.bones and t in tgt.pose.bones:
            turn[(src.name, t)] = world(src, s).to_quaternion().inverted() @ world(tgt, t).to_quaternion()
# The hips' height, for the pelvis's travel.
hip_t = tgt.data.bones["pelvis"].head_local.z
hip_s = {src1.name: src1.data.bones["DEF-hips"].head_local.z, src2.name: src2.data.bones["pelvis"].head_local.z}

# ── Each clip, baked onto the target ─────────────────────────────────────────
order = []


def visit(b):
    order.append(b)
    for c in b.children:
        visit(c)


for b in tgt.data.bones:
    if b.parent is None:
        visit(b)
tgt.animation_data_create()
made = []
hips = {}
for lib, clip, ours in CLIPS:
    src, mapping, actions = (src1, MAP1, act1) if lib == 1 else (src2, MAP2, act2)
    inverse = {t: s for s, t in mapping.items()}
    action = find_action(actions, clip)
    play(src, action)
    f0, f1 = (int(round(x)) for x in action.frame_range)
    out = bpy.data.actions.new(ours)
    play(tgt, out)
    heights = hips[ours] = []
    for f in range(f0, f1 + 1):
        scene.frame_set(f)
        desired = {}
        for b in order:
            pb = tgt.pose.bones[b.name]
            rest = b.matrix_local
            if b.parent is None:
                place = rest.copy()
            else:
                place = desired[b.parent.name] @ (b.parent.matrix_local.inverted() @ rest)
            s = inverse.get(b.name)
            if s is not None and s in src.pose.bones:
                q = world(src, s).to_quaternion() @ turn[(src.name, b.name)]
                m = q.to_matrix().to_4x4()
                if b.name == "pelvis":
                    m.translation = world(src, s).translation * (hip_t / hip_s[src.name])
                else:
                    m.translation = place.translation
            else:
                m = place
            desired[b.name] = m
            parent = Matrix.Identity(4) if b.parent is None else desired[b.parent.name] @ b.parent.matrix_local.inverted()
            pb.matrix_basis = (parent @ rest).inverted() @ m
            pb.keyframe_insert("rotation_quaternion", frame=f - f0 + 1)
            if b.name == "pelvis":
                pb.keyframe_insert("location", frame=f - f0 + 1)
                heights.append(round(m.translation.z, 4))
    track = tgt.animation_data.nla_tracks.new()
    track.name = ours
    track.strips.new(ours, 1, out)
    track.mute = True
    made.append(f"{ours} {f1 - f0 + 1}f")
tgt.animation_data.action = None


def export(path, with_meshes):
    bpy.ops.object.select_all(action="DESELECT")
    tgt.select_set(True)
    if with_meshes:
        for o in tgt.children:
            o.select_set(True)
    bpy.context.view_layer.objects.active = tgt
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_skins=with_meshes,
        export_materials="NONE",
        export_def_bones=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        # (Only what was keyed: rotations, the pelvis's place. A sampled
        # translation on every bone would give everyone this body's lengths.)
        export_force_sampling=False,
        export_optimize_animation_size=True,
    )


export(OUT, False)
json.dump({"fps": scene.render.fps / scene.render.fps_base, "hips": round(tgt.data.bones["pelvis"].head_local.z, 4), "clips": hips}, open(OUT.rsplit(".", 1)[0] + ".json", "w"))
if PREVIEW:
    export(PREVIEW, True)
print(f"MOTIONS {len(made)}: {', '.join(made)} -> {OUT}")
