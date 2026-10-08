"""Signed distance fields in numpy, meshed by surface nets: how Name City's
people (people.py) are sculpted. A shape is a function from points (N×3,
metres) to distances (negative inside); smooth unions blend the parts the
way clay does. Coordinates are the city's: x across, y up, z back (a face
looks towards −z).
"""

import math

import numpy as np

F = np.float32


def vec(a):
    return np.asarray(a, dtype=F)


def length(q):
    return np.sqrt(np.einsum("ij,ij->i", q, q))


# ── Shapes ───────────────────────────────────────────────────────────────────


def sphere(p, c, r):
    return length(p - vec(c)) - F(r)


def ellipsoid(p, c, r, rot=None):
    """An ellipsoid of radii [r] about [c] ([rot]: its axes, columns)."""
    q = p - vec(c)
    if rot is not None:
        q = q @ rot
    r = vec(r)
    k0 = length(q / r)
    k1 = length(q / (r * r))
    return k0 * (k0 - 1.0) / np.maximum(k1, F(1e-9))


def round_cone(p, a, b, r1, r2):
    """A tapered capsule from [a] (radius [r1]) to [b] (radius [r2])."""
    a, b = vec(a), vec(b)
    ba = b - a
    l2 = float(ba @ ba)
    rr = r1 - r2
    a2 = l2 - rr * rr
    il2 = 1.0 / l2
    pa = p - a
    y = pa @ ba
    z = y - l2
    xv = pa * l2 - np.outer(y, ba)
    x2 = np.einsum("ij,ij->i", xv, xv)
    y2 = y * y * l2
    z2 = z * z * l2
    k = math.copysign(1.0, rr) * rr * rr * x2 if rr != 0 else np.zeros_like(x2)
    d_b = np.sqrt(x2 + z2) * il2 - r2
    d_a = np.sqrt(x2 + y2) * il2 - r1
    d_m = (np.sqrt(np.maximum(x2 * a2 * il2, 0)) + y * rr) * il2 - r1
    return np.where(np.sign(z) * a2 * z2 > k, d_b, np.where(np.sign(y) * a2 * y2 < k, d_a, d_m)).astype(F)


def capsule(p, a, b, r):
    return round_cone(p, a, b, r, r)


def chain(p, pts, radii):
    """Round cones through [pts] (a finger, a strand), [radii] at each."""
    d = None
    for i in range(len(pts) - 1):
        e = round_cone(p, pts[i], pts[i + 1], radii[i], radii[i + 1])
        d = e if d is None else np.minimum(d, e)
    return d


def box(p, c, h, r=0.0, rot=None):
    """A box of half sizes [h] about [c], its edges rounded by [r]."""
    q = p - vec(c)
    if rot is not None:
        q = q @ rot
    q = np.abs(q) - (vec(h) - F(r))
    return length(np.maximum(q, 0)) + np.minimum(np.max(q, axis=1), 0) - F(r)


def plane(p, n, o):
    """The half space behind the plane through [o] facing [n]."""
    n = vec(n) / np.linalg.norm(n)
    return (p - vec(o)) @ n


# ── Blends ───────────────────────────────────────────────────────────────────


def smin(a, b, k):
    if k <= 0:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def cut(a, b, k=0.0):
    """[a] with [b] carved out of it."""
    return smax(a, -b, k)


# ── Frames ───────────────────────────────────────────────────────────────────


def rot_x(t):
    c, s = math.cos(t), math.sin(t)
    return vec([[1, 0, 0], [0, c, -s], [0, s, c]])


def rot_y(t):
    c, s = math.cos(t), math.sin(t)
    return vec([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rot_z(t):
    c, s = math.cos(t), math.sin(t)
    return vec([[c, -s, 0], [s, c, 0], [0, 0, 1]])


# ── Noise ────────────────────────────────────────────────────────────────────


def _hash(ix, iy, iz):
    h = (ix * 374761393 + iy * 668265263 + iz * 1274126177) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1103515245) & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 0xFFFF).astype(F) * F(2.0 / 65535.0) - F(1.0)


def noise(p):
    """Value noise in [-1, 1], one cell a unit."""
    i = np.floor(p)
    f = (p - i).astype(F)
    i = i.astype(np.int64)
    u = f * f * (3 - 2 * f)
    out = np.zeros(len(p), dtype=F)
    for dx in (0, 1):
        wx = u[:, 0] if dx else 1 - u[:, 0]
        for dy in (0, 1):
            wy = u[:, 1] if dy else 1 - u[:, 1]
            for dz in (0, 1):
                wz = u[:, 2] if dz else 1 - u[:, 2]
                out += wx * wy * wz * _hash(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz)
    return out


def fbm(p, octaves=3):
    out = np.zeros(len(p), dtype=F)
    a = 1.0
    for o in range(octaves):
        out += F(a) * noise(p * F(2**o) + F(17.3 * o))
        a *= 0.5
    return out


# ── Meshing ──────────────────────────────────────────────────────────────────

_CORNERS = np.array([[i, j, k] for i in (0, 1) for j in (0, 1) for k in (0, 1)])
_EDGES = [(a, b) for a in range(8) for b in range(a + 1, 8) if np.abs(_CORNERS[a] - _CORNERS[b]).sum() == 1]


def sample(sdf, lo, hi, step, chunk=1_500_000):
    """[sdf] on a grid from [lo] to [hi] (step apart): (values, origin)."""
    lo, hi = np.asarray(lo, float), np.asarray(hi, float)
    n = np.ceil((hi - lo) / step).astype(int) + 1
    xs, ys, zs = (lo[k] + step * np.arange(n[k]) for k in range(3))
    out = np.empty(n, dtype=F)
    per = max(1, chunk // (n[1] * n[2]))
    for i0 in range(0, n[0], per):
        i1 = min(n[0], i0 + per)
        X, Y, Z = np.meshgrid(xs[i0:i1], ys, zs, indexing="ij")
        pts = np.stack([X.ravel(), Y.ravel(), Z.ravel()], axis=1).astype(F)
        out[i0:i1] = sdf(pts).reshape(i1 - i0, n[1], n[2])
    return out, lo


def surface_nets(D, origin, step):
    """The zero surface of the grid [D]: vertices (M×3) and quads (K×4),
    not yet facing any particular way (see [orient])."""
    nx, ny, nz = D.shape
    S = D < 0
    c0 = S[:-1, :-1, :-1]
    active = np.zeros((nx - 1, ny - 1, nz - 1), dtype=bool)
    for dx, dy, dz in _CORNERS[1:]:
        active |= S[dx : nx - 1 + dx, dy : ny - 1 + dy, dz : nz - 1 + dz] != c0
    idx = np.argwhere(active)
    vid = np.full((nx - 1, ny - 1, nz - 1), -1, dtype=np.int64)
    vid[idx[:, 0], idx[:, 1], idx[:, 2]] = np.arange(len(idx))
    cv = np.stack([D[idx[:, 0] + dx, idx[:, 1] + dy, idx[:, 2] + dz] for dx, dy, dz in _CORNERS], axis=1)
    acc = np.zeros((len(idx), 3), dtype=np.float64)
    cnt = np.zeros(len(idx), dtype=np.float64)
    for a, b in _EDGES:
        da, db = cv[:, a].astype(np.float64), cv[:, b].astype(np.float64)
        m = (da < 0) != (db < 0)
        t = np.where(m, da / np.where(m, da - db, 1.0), 0.0)
        pa, pb = _CORNERS[a], _CORNERS[b]
        acc[m] += pa + t[m, None] * (pb - pa)
        cnt[m] += 1
    verts = origin + (idx + acc / cnt[:, None]) * step
    quads = []
    # Across each grid edge where the sign changes: the four cells round it.
    for axis in range(3):
        sl0, sl1 = [slice(None)] * 3, [slice(None)] * 3
        sl0[axis], sl1[axis] = slice(0, -1), slice(1, None)
        e = np.argwhere(S[tuple(sl0)] != S[tuple(sl1)])
        o = [a for a in range(3) if a != axis]
        keep = (e[:, o[0]] >= 1) & (e[:, o[1]] >= 1) & (e[:, o[0]] <= D.shape[o[0]] - 2) & (e[:, o[1]] <= D.shape[o[1]] - 2)
        e = e[keep]

        def cell(du, dv):
            c = e.copy()
            c[:, o[0]] -= du
            c[:, o[1]] -= dv
            return vid[c[:, 0], c[:, 1], c[:, 2]]

        quads.append(np.stack([cell(1, 1), cell(0, 1), cell(0, 0), cell(1, 0)], axis=1))
    quads = np.concatenate(quads)
    quads = quads[(quads >= 0).all(axis=1)]
    return verts.astype(np.float64), quads


def orient(sdf, verts, faces):
    """[faces] each wound to face out (counter-clockwise seen from where
    the field is positive)."""
    v = verts[faces]
    n = np.cross(v[:, 2] - v[:, 0], v[:, -1] - v[:, 1]) if faces.shape[1] == 4 else np.cross(v[:, 1] - v[:, 0], v[:, 2] - v[:, 0])
    g = gradient(sdf, v.mean(axis=1))
    flip = np.einsum("ij,ij->i", n, g) < 0
    faces = faces.copy()
    faces[flip] = faces[flip][:, ::-1]
    return faces


def gradient(sdf, p, eps=2e-4):
    p = p.astype(F)
    g = np.zeros_like(p)
    for k in range(3):
        d = np.zeros(3, dtype=F)
        d[k] = eps
        g[:, k] = (sdf(p + d) - sdf(p - d)) / (2 * eps)
    return g


def project(sdf, p, iters=3):
    """Points moved onto the surface (Newton steps along the gradient)."""
    p = p.astype(np.float64)
    for _ in range(iters):
        d = sdf(p.astype(F)).astype(np.float64)
        g = gradient(sdf, p).astype(np.float64)
        gl = np.maximum(np.einsum("ij,ij->i", g, g), 1e-9)
        p = p - (d / gl)[:, None] * g
    return p


def normals(sdf, p):
    g = gradient(sdf, p).astype(np.float64)
    return g / np.maximum(np.linalg.norm(g, axis=1), 1e-9)[:, None]


def occlusion(sdf, p, n, reach=0.02, steps=5, k=1.0):
    """How open each point is (1 open … 0 shut in), from the distances
    out along its normal."""
    occ = np.zeros(len(p), dtype=np.float64)
    w = 1.0
    for i in range(1, steps + 1):
        h = reach * i / steps
        d = sdf((p + n * h).astype(F)).astype(np.float64)
        occ += w * np.maximum(0.0, h - d) / reach
        w *= 0.6
    return np.clip(1.0 - k * occ * 2.2, 0.0, 1.0)
