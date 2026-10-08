"""Name City's people's parts, sculpted (sdf.py: shapes blended like clay,
meshed, brought down to a few thousand triangles, their normals the
sculpture's own): the head (one simple face for everyone: dark ovals for
eyes, a soft nose, brows), the hairstyles, hands, shoes and their soles.

Each part keeps the frame figure.dart poses it in (size 1: a person
1.72 m tall): the head from the neck's pivot, the face to −z; the hand
from the wrist, hanging down −y, its palm to −x (the right hand: the left
is drawn mirrored), the thumb forward; the shoe from the ankle, the toe
to −z. Shading is in the vertex colours (greys: the skin's, the hair's or
the shoes' colour multiplies them; the eyes dark as they are). The parts
people far from the camera wear are simpler ('<name>_far').

Run headless:
  Blender -b --factory-startup -P tool/blender/people.py -- assets/models [--preview dir] [--only head,eyes]
"""

import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sdf as S  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1 :]
OUT = argv[0]
PREVIEW = argv[argv.index("--preview") + 1] if "--preview" in argv else None
ONLY = set(argv[argv.index("--only") + 1].split(",")) if "--only" in argv else None

bpy.ops.wm.read_factory_settings(use_empty=True)
made = []


def wanted(name):
    return ONLY is None or name in ONLY or name.split("_")[0] in ONLY


# ── From a field to a part ───────────────────────────────────────────────────


def part(name, field, lo, hi, step, tris, colour, reach=0.012, far=None):
    """The surface of [field] in the box [lo]…[hi], meshed [step] fine,
    brought down to about [tris] triangles, coloured by [colour](points,
    normals, openness) → (N×3). With [far], a second, simpler one for far
    away ('<name>_far', that many triangles), from the same sculpture."""
    D, origin = S.sample(field, lo, hi, step)
    v, q = S.surface_nets(D, origin, step)
    q = S.orient(field, v, q)
    ob = _finish(name, field, v, q, tris, colour, reach)
    if far:
        _finish(name + "_far", field, v, q, far, colour, reach)
    return ob


def _finish(name, field, v, q, tris, colour, reach):
    me = bpy.data.meshes.new(name)
    # Blender's x, y, z are the city's x, z, y: a mirror, so each face turns
    # round to keep facing out.
    me.from_pydata(v[:, [0, 2, 1]].tolist(), [], q[:, ::-1].tolist())
    me.validate()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    before = sum(len(p.vertices) - 2 for p in me.polygons)
    dec = ob.modifiers.new("decimate", "DECIMATE")
    dec.ratio = min(1.0, tris / max(1, before))
    dec.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=dec.name)
    me = ob.data
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    p = co.reshape(-1, 3)[:, [0, 2, 1]]
    # On the sculpture's surface again, its normals its own.
    p = S.project(field, p)
    nrm = S.normals(field, p)
    me.vertices.foreach_set("co", p[:, [0, 2, 1]].ravel())
    me.update()
    open_ = S.occlusion(field, p, nrm, reach=reach)
    col = np.clip(colour(p, nrm, open_), 0.0, 1.0)
    attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    rgba = np.concatenate([col, np.ones((len(col), 1))], axis=1)
    attr.data.foreach_set("color", rgba.ravel())
    me.color_attributes.active_color = attr
    me.color_attributes.render_color_index = me.color_attributes.active_color_index
    for poly in me.polygons:
        poly.use_smooth = True
    # Each corner's normal the field's a little way into its face: smooth
    # over the curves, crisp along a crease (a hairline, a cut end, a lid).
    tri = np.array([list(poly.vertices) for poly in me.polygons])
    centre = p[tri].mean(axis=1)
    corner = (0.8 * p[tri] + 0.2 * centre[:, None, :]).reshape(-1, 3)
    loop_n = S.normals(field, corner)
    # One normal a vertex (its corners' average) unless it's on a crease,
    # where the corners on each side keep their own: the export then shares
    # the vertex between its faces.
    vi = tri.ravel()
    order = np.argsort(vi, kind="stable")
    bounds = np.searchsorted(vi[order], np.arange(len(p) + 1))
    cos_split = math.cos(math.radians(28))
    for k in range(len(p)):
        idx = order[bounds[k] : bounds[k + 1]]
        groups = []
        for i in idx:
            for g in groups:
                if loop_n[i] @ g[0] > cos_split:
                    g[1].append(i)
                    break
            else:
                groups.append([loop_n[i].copy(), [i]])
        for _, members in groups:
            m = loop_n[members].sum(axis=0)
            loop_n[members] = m / max(1e-9, np.linalg.norm(m))
    me.normals_split_custom_set(loop_n[:, [0, 2, 1]].tolist())
    made.append(ob)
    print(f"PART {name}: {len(me.polygons)} tris, {len(me.vertices)} vertices (from {before})")
    return ob


def mix(a, b, t):
    t = np.clip(t, 0.0, 1.0)[:, None]
    return a * (1 - t) + b * t


def grey(k):
    return np.repeat(np.asarray(k, dtype=float)[:, None], 3, axis=1)


# ── The head ─────────────────────────────────────────────────────────────────

# The eyes: dark ovals on the face (no whites, no irises: a simple face,
# everyone's the same).
EYE_X, EYE_Y = 0.031, 0.132
EYE_R = (0.0106, 0.0086, 0.006)


def head_field():
    """The head and neck, one for everyone: a smooth skull, the jaw and
    chin, ears, a small soft nose, the mouth a soft crease."""

    def field(p):
        d = S.ellipsoid(p, (0, 0.158, 0.008), (0.077, 0.098, 0.097))
        # The face's mass, the jaw and the chin, softly.
        d = S.smin(d, S.ellipsoid(p, (0, 0.099, -0.03), (0.063, 0.064, 0.067)), 0.03)
        for s in (-1, 1):
            d = S.smin(d, S.round_cone(p, (s * 0.052, 0.076, 0.014), (s * 0.015, 0.032, -0.06), 0.015, 0.0165), 0.03)
        d = S.smin(d, S.ellipsoid(p, (0, 0.031, -0.066), (0.019, 0.018, 0.015)), 0.016)
        # A soft brow, and the eyes set a little under it.
        d = S.smin(d, S.ellipsoid(p, (0, 0.149, -0.081), (0.052, 0.012, 0.013)), 0.02)
        for s in (-1, 1):
            d = S.cut(d, S.ellipsoid(p, (s * EYE_X, 0.133, -0.095), (0.016, 0.011, 0.008)), 0.012)
        # A small soft nose.
        nose = S.smin(S.round_cone(p, (0, 0.138, -0.091), (0, 0.105, -0.107), 0.0072, 0.0092), S.sphere(p, (0, 0.101, -0.1055), 0.0094), 0.006)
        d = S.smin(d, nose, 0.011)
        # The mouth: a soft crease.
        d = S.cut(d, S.ellipsoid(p, (0, 0.068, -0.097), (0.0145, 0.0011, 0.007)), 0.0016)
        # Ears, their bowls hollowed.
        for s in (-1, 1):
            rot = S.rot_y(0.25 * s) @ S.rot_x(0.12)
            ear = S.ellipsoid(p, (s * 0.0785, 0.124, 0.011), (0.0105, 0.0295, 0.0185), rot=rot)
            ear = S.cut(ear, S.ellipsoid(p, (s * 0.0872, 0.122, 0.007), (0.0062, 0.016, 0.0098), rot=rot), 0.003)
            d = S.smin(d, ear, 0.006)
        d = S.smin(d, S.round_cone(p, (0, -0.075, 0.012), (0, 0.06, 0.003), 0.05, 0.047), 0.03)
        return d

    return field


def head_colour(p, n, open_):
    c = grey(0.55 + 0.45 * open_)
    # The mouth's crease a shade darker and warmer.
    m = np.clip(1 - np.hypot(p[:, 0] / 0.016, (p[:, 1] - 0.068) / 0.0032), 0, 1) * (p[:, 2] < -0.09)
    return c * (1 - m[:, None] * np.array([0.3, 0.42, 0.42]))


def eyes():
    """The eyes: two dark ovals, just proud of the face."""
    head = head_field()
    guess = np.array([[s * EYE_X, EYE_Y, -0.12] for s in (-1, 1)], dtype=float)
    on = S.project(head, guess, iters=10)
    nrm = S.normals(head, on)
    centres = [tuple(o - nr * (EYE_R[2] - 0.0015)) for o, nr in zip(on, nrm)]

    def field(p):
        return np.minimum(*[S.ellipsoid(p, c, EYE_R) for c in centres])

    return field


# ── Hair and brows ───────────────────────────────────────────────────────────


def keyed(keys, t):
    """Piecewise linear through (t, value) [keys]."""
    ks = np.asarray(keys, dtype=float)
    return np.interp(t, ks[:, 0], ks[:, 1])


def around(p):
    """The angle round the head (0 at the face, ±π at the back)."""
    return np.abs(np.arctan2(p[:, 0], -(p[:, 2] - 0.01)))


HAIRLINES = {
    # (angle round the head, where the hair stops): its front, the temples,
    # sideburns, over the ears, the nape.
    "short": [(0.0, 0.196), (0.5, 0.192), (0.85, 0.182), (1.05, 0.165), (1.12, 0.122), (1.27, 0.122), (1.34, 0.16), (1.85, 0.16), (2.1, 0.1), (2.6, 0.076), (math.pi, 0.072)],
    "medium": [(0.0, 0.184), (0.6, 0.18), (1.0, 0.162), (1.12, 0.112), (1.3, 0.112), (1.36, 0.13), (1.9, 0.13), (2.2, 0.07), (math.pi, 0.05)],
}
ENDS = {
    "bob": [(0.0, 0.056), (1.2, 0.05), (2.0, 0.058), (math.pi, 0.062)],
    "long": [(0.0, 0.004), (1.55, 0.0), (2.15, -0.16), (math.pi, -0.2)],
}


CRANIUM = ((0, 0.158, 0.008), (0.077, 0.098, 0.097))


def hair_field(style):
    head = head_field()
    flowing = style in ("bob", "long")
    # Clumps round the head (how many), how deep; lumps over them.
    n_clumps, amp, lump = {"short": (34, 0.0012, 0.0016), "medium": (30, 0.0018, 0.002), "bob": (26, 0.0024, 0.0024), "long": (24, 0.0028, 0.0028)}[style]

    def clumps(p):
        phi = np.arctan2(p[:, 0], p[:, 2] - 0.01)
        rho = np.hypot(p[:, 0], p[:, 2] - 0.01)
        wob = S.fbm(p * S.F(14), 2)
        g = 0.5 + 0.5 * np.sin(n_clumps * phi + 1.8 * wob)
        # (None at the crown, where they'd all meet.)
        fade = np.clip((rho - 0.012) / 0.04, 0, 1)
        return (amp * g * fade + lump * (0.5 + 0.5 * S.fbm(p * S.F(9) + S.F(3.1), 2))).astype(S.F)

    def field(p):
        y = p[:, 1]
        a = around(p)
        if flowing:
            # On the skull above its widest; below, falling down (the skull's
            # outline drawn down, the turn into it smooth), over the ears,
            # its ends tucked in a little.
            q = p.copy()
            q[:, 1] = S.smax(y.astype(S.F), np.full_like(y, 0.15, dtype=S.F), 0.035)
            base = S.ellipsoid(q, *CRANIUM)
            t = 0.0175 * np.clip((y - 0.02) / 0.1, 0.45, 1) + 0.004 * np.clip((y - 0.17) / 0.07, 0, 1)
        else:
            base = head(p)
            side, top = (0.0055, 0.0125) if style == "short" else (0.008, 0.0165)
            t = side + (top - side) * np.clip((y - 0.13) / 0.11, 0, 1) ** 1.2
            # Thinning to the hairline (not a helmet's edge), which wanders.
            edge = y - keyed(HAIRLINES[style], around(p)) + 0.003 * S.fbm(p * S.F(60), 2)
            t = t * (0.42 + 0.58 * np.clip(edge / 0.016, 0, 1))
        outer = base - t.astype(S.F) + clumps(p)
        d = S.smax(outer, -(base + S.F(0.003)), 0.0)
        if flowing:
            # Its ends: a blunt cut, the tips turned in a little.
            d = S.smax(d, -(y - keyed(ENDS[style], a)).astype(S.F), 0.006)
            # The face left open under a fringe; long hair falls behind the
            # shoulders, not on them.
            window = np.maximum.reduce([np.abs(p[:, 0]) - 0.064, p[:, 2] - 0.004, y - (0.168 if style == "bob" else 0.188)])
            d = S.smax(d, -window.astype(S.F), 0.008)
            if style == "long":
                d = S.smax(d, -np.maximum(y - 0.025, 0.055 - p[:, 2]).astype(S.F), 0.012)
                # A parting.
                d = d + (0.004 * np.exp(-((p[:, 0] / 0.006) ** 2)) * (y > 0.19) * (p[:, 2] < 0.05)).astype(S.F)
        else:
            d = S.smax(d, -(y - keyed(HAIRLINES[style], a) + 0.003 * S.fbm(p * S.F(60), 2)).astype(S.F), 0.002)
        return d

    return field


def hair_colour(style):
    n_clumps = {"short": 34, "medium": 30, "bob": 26, "long": 24}[style]

    def colour(p, n, open_):
        # Lighter on the clumps, dark between them and underneath.
        phi = np.arctan2(p[:, 0], p[:, 2] - 0.01)
        ridge = 0.5 + 0.5 * np.sin(n_clumps * phi + 1.8 * S.fbm(p.astype(S.F) * S.F(14), 2))
        k = (0.34 + 0.66 * open_) * (0.8 + 0.2 * ridge)
        return grey(k)

    return colour


def brow_field():
    """The brows: a short stroke over each eye, lying on the brow."""
    head = head_field()
    strokes = []
    for s in (-1, 1):
        pts = [(s * 0.013, 0.1505), (s * 0.027, 0.1535), (s * 0.041, 0.1525), (s * 0.049, 0.149)]
        rad = [0.0023, 0.0023, 0.0019, 0.0012]
        guess = np.array([[x, y, -0.12] for x, y in pts], dtype=float)
        on = S.project(head, guess, iters=10)
        nrm = S.normals(head, on)
        strokes.append(([tuple(o + n * r * 0.2) for o, n, r in zip(on, nrm, rad)], rad))

    def field(p):
        return np.minimum(*[S.chain(p, pts, rad) for pts, rad in strokes])

    return field


# ── Hands ────────────────────────────────────────────────────────────────────


def _bend(d, a):
    """Direction [d] (in the hand: down −y) turned [a] towards the palm (−x)."""
    x, y, z = d
    c, s = math.cos(a), math.sin(a)
    return (x * c + y * s, y * c - x * s, z)


def hand_field():
    """A right hand, relaxed: hanging from the wrist (the origin) down −y,
    its palm to −x, the thumb forward (−z); the fingers curled a little."""
    fingers = []
    # (knuckle y, z; the three bones' lengths; radius; the curl at each joint;
    # how far it splays from the middle finger.)
    for ky, kz, lens, r, curl, splay in [
        (-0.094, -0.0255, (0.036, 0.022, 0.018), 0.0087, (0.35, 0.6, 0.35), -0.03),
        (-0.097, -0.0085, (0.04, 0.025, 0.019), 0.009, (0.38, 0.65, 0.38), 0.0),
        (-0.095, 0.0085, (0.037, 0.023, 0.018), 0.0086, (0.42, 0.7, 0.4), 0.03),
        (-0.0885, 0.0245, (0.029, 0.018, 0.016), 0.0075, (0.48, 0.75, 0.42), 0.07),
    ]:
        p = [(0.0, ky, kz)]
        a = 0.0
        for seg, c in zip(lens, curl):
            a += c
            dx, dy, dz = _bend((0.0, -1.0, 0.0), a)
            dz = math.sin(splay)
            n = math.sqrt(dx * dx + dy * dy + dz * dz)
            last = p[-1]
            p.append((last[0] + dx / n * seg, last[1] + dy / n * seg, last[2] + dz / n * seg))
        fingers.append((p, [r, r * 0.93, r * 0.86, r * 0.78]))
    # The thumb: from the heel of the palm, forward and down along the
    # index finger, its tip turned in.
    thumb = [(-0.006, -0.026, -0.024), (-0.017, -0.055, -0.038), (-0.023, -0.077, -0.043), (-0.028, -0.095, -0.042)]
    thumb_r = [0.0112, 0.0097, 0.0087, 0.0076]

    def field(p):
        d = S.smin(S.box(p, (0.0005, -0.056, 0.0), (0.0125, 0.042, 0.036), 0.012), S.ellipsoid(p, (0.0, -0.055, 0.0), (0.0155, 0.046, 0.039)), 0.01)
        # The wrist, and the thumb's muscle on the palm.
        d = S.smin(d, S.ellipsoid(p, (0.0, -0.004, 0.0), (0.0185, 0.026, 0.026)), 0.012)
        d = S.smin(d, S.ellipsoid(p, (-0.01, -0.046, -0.02), (0.012, 0.024, 0.015)), 0.01)
        fing = None
        for pts, rad in fingers:
            f = S.chain(p, pts, rad)
            fing = f if fing is None else np.minimum(fing, f)
        d = S.smin(d, fing, 0.007)
        d = S.smin(d, S.chain(p, thumb, thumb_r), 0.009)
        return d

    return field, fingers


def hand_colour(fingers):
    def colour(p, n, open_):
        c = grey(0.5 + 0.5 * open_)
        # Nails: paler, on the backs of the fingertips.
        tips = np.zeros(len(p))
        for pts, rad in fingers:
            a, b = np.array(pts[-2]), np.array(pts[-1])
            ax = (b - a) / np.linalg.norm(b - a)
            t = np.clip((p - a) @ ax / np.linalg.norm(b - a), 0, 1)
            near_tip = np.linalg.norm(p - (a + np.outer(t, b - a)), axis=1) < rad[-1] * 1.6
            back = n @ np.array([0.9, -0.1, 0.0]) > 0.35
            tips = np.maximum(tips, near_tip * back * (t > 0.25))
        c = mix(c, c * np.array([1.06, 1.0, 1.0]) + 0.06, tips)
        return c

    return colour


# ── Shoes ────────────────────────────────────────────────────────────────────

SOLE_TOP, SOLE_BOTTOM = -0.067, -0.08


def shoe_upper(p):
    """A shoe's upper, from the ankle (the origin), the toe to −z."""
    d = S.ellipsoid(p, (0, -0.05, 0.026), (0.035, 0.031, 0.041))
    d = S.smin(d, S.ellipsoid(p, (0, -0.055, -0.06), (0.041, 0.026, 0.07)), 0.02)
    d = S.smin(d, S.ellipsoid(p, (0, -0.063, -0.146), (0.042, 0.0175, 0.056)), 0.02)
    # The instep and the tongue, up to a low collar round the ankle.
    d = S.smin(d, S.round_cone(p, (0, -0.03, 0.006), (0, -0.05, -0.092), 0.027, 0.018), 0.015)
    return S.smax(d, -(p[:, 1] - SOLE_TOP + 0.002), 0.002)


def sole_field(p):
    """Its sole: the upper's outline a little wider, with a heel, the toe
    turned up a touch."""
    q = p.copy()
    q[:, 1] = -0.06
    toe = np.clip((-p[:, 2] - 0.13) / 0.08, 0, 1) ** 2 * 0.012
    outline = shoe_upper(q) - 0.0035
    y = p[:, 1] - toe.astype(S.F)
    slab = np.abs(y - (SOLE_TOP + SOLE_BOTTOM) / 2) - (SOLE_TOP - SOLE_BOTTOM) / 2
    return S.smax(outline, slab.astype(S.F), 0.003)


def shoe_colour(p, n, open_):
    c = grey(0.45 + 0.55 * open_)
    # A little darker at the toe cap's seam and the heel's counter.
    seam = np.clip(1 - np.abs(np.hypot(p[:, 0] / 0.043, (p[:, 2] + 0.12) / 0.03) - 1) / 0.08, 0, 1) * (p[:, 1] > -0.06)
    return c * (1 - 0.12 * seam)[:, None]


if wanted("hand"):
    hf, fingers = hand_field()
    part("hand", hf, (-0.075, -0.205, -0.07), (0.035, 0.035, 0.05), 0.0007, 1600, hand_colour(fingers), reach=0.01, far=300)
if wanted("shoe"):
    part("shoe", shoe_upper, (-0.05, -0.08, -0.22), (0.05, 0.03, 0.09), 0.001, 1100, shoe_colour, reach=0.01, far=260)
    part("sole", sole_field, (-0.055, -0.085, -0.225), (0.055, -0.045, 0.095), 0.0008, 500, lambda p, n, o: grey(0.55 + 0.45 * o), reach=0.006, far=120)

if wanted("head"):
    part("head", head_field(), (-0.11, -0.13, -0.13), (0.11, 0.275, 0.125), 0.0011, 2400, head_colour, far=600)
if wanted("eyes"):
    part("eyes", eyes(), (-0.05, 0.115, -0.115), (0.05, 0.15, -0.08), 0.0004, 300, lambda p, n, o: np.tile([0.035, 0.028, 0.025], (len(p), 1)))
if wanted("brows"):
    part("brows", brow_field(), (-0.07, 0.135, -0.11), (0.07, 0.17, -0.06), 0.0005, 360, lambda p, n, o: grey(0.45 + 0.4 * o))
for style, tris, far, lo, hi in [
    ("short", 1800, 420, (-0.105, 0.05, -0.125), (0.105, 0.29, 0.135)),
    ("medium", 2200, 500, (-0.11, 0.03, -0.125), (0.11, 0.295, 0.14)),
    ("bob", 2600, 600, (-0.115, 0.03, -0.125), (0.115, 0.295, 0.14)),
    ("long", 3200, 760, (-0.115, -0.23, -0.125), (0.115, 0.295, 0.145)),
]:
    if wanted("hair_" + style):
        part("hair_" + style, hair_field(style), lo, hi, 0.0012, tris, hair_colour(style), reach=0.018, far=far)


# ── Out ──────────────────────────────────────────────────────────────────────


def export(path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in made:
        o.select_set(True)
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
    print(f"MODEL people: {sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in made)} tris -> {path}")


if ONLY is None:
    export(f"{OUT}/people.glb")


TINTS = {"head": (0.86, 0.66, 0.53), "brows": (0.16, 0.11, 0.08), "hair": (0.17, 0.12, 0.09)}


def tinted(ob):
    """A copy of [ob] for the previews, its greys tinted as the city would."""
    key = ob.name.split("_")[0]
    if key not in TINTS:
        return ob
    cp = ob.copy()
    cp.data = ob.data.copy()
    cp.name = ob.name + " preview"
    bpy.context.collection.objects.link(cp)
    attr = cp.data.color_attributes["Col"]
    t = TINTS[key]
    for d in attr.data:
        c = d.color
        d.color = (c[0] * t[0], c[1] * t[1], c[2] * t[2], 1.0)
    return cp


def preview(path, at, target, lens, objects, size=(640, 640)):
    scene = bpy.context.scene
    for o in bpy.context.scene.objects:
        o.hide_render = o.type == "MESH" and o not in objects
    cam = bpy.data.objects.get("cam") or bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    if cam.name not in scene.collection.objects:
        scene.collection.objects.link(cam)
    cam.data.lens = lens
    cam.location = at
    cam.rotation_euler = (Vector(target) - Vector(at)).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.color_type = "VERTEX"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.show_cavity = False
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


if PREVIEW:
    byname = {o.name: o for o in made}
    eye = [byname["eyes"]] if "eyes" in byname else []
    views = [
        ((0.0, -0.8, 0.12), (0, 0, 0.1)),
        ((0.5, -0.6, 0.14), (0, 0, 0.1)),
        ((0.8, 0.0, 0.12), (0, 0, 0.1)),
        ((0.0, 0.8, 0.14), (0, 0, 0.1)),
    ]
    looks = [("head", None, "brows")] + [("head", "hair_" + st, "brows") for st in ("short", "medium", "bob", "long")]
    for name, views2 in [
        ("hand", [((-0.45, -0.1, -0.08), (0, 0, -0.08)), ((0.45, -0.1, -0.08), (0, 0, -0.08)), ((0.0, -0.45, -0.08), (0, 0, -0.08)), ((-0.25, -0.25, -0.2), (0, 0, -0.08))]),
        ("shoe", [((0.45, 0.0, 0.0), (0, -0.06, -0.04)), ((0.3, -0.4, 0.15), (0, -0.06, -0.04)), ((0.0, -0.45, 0.05), (0, -0.06, -0.04)), ((0.25, 0.3, -0.2), (0, -0.06, -0.04))]),
    ]:
        if name not in byname:
            continue
        objs = [byname[name]] + ([byname["sole"]] if name == "shoe" and "sole" in byname else [])
        for k, (at, tgt) in enumerate(views2):
            preview(f"{PREVIEW}/{name}_{k}.png", at, tgt, 85, objs, (480, 480))
    for h, hair, brow in looks:
        if h not in byname or (hair and hair not in byname):
            continue
        objs = [tinted(o) for o in [byname[h], *eye] + ([byname[hair]] if hair else []) + ([byname[brow]] if brow in byname else [])]
        tag = hair or h
        for k, (at, tgt) in enumerate(views):
            preview(f"{PREVIEW}/{tag}_{k}.png", at, tgt, 85, objs, (480, 560))
        preview(f"{PREVIEW}/{tag}_face.png", (0.0, -0.42, 0.125), (0, 0, 0.11), 85, objs, (560, 560))
