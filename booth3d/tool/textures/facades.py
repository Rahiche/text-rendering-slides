# facades.py <photos dir> <out dir> [size]
#
# Builds the city's facade textures: for each style, an atlas of 8 × 8
# window cells (a bay 1.7 m wide, a storey 2.6 m tall: city_towers.dart
# lays them at that scale), as colour (sRGB), normal (OpenGL) and ARM
# (ambient occlusion, roughness, metal) JPEGs. The walls are Poly Haven
# photographs (CC0, assets/textures/CREDITS.md), resampled to their real
# size and tiled seamlessly across the atlas; the windows are drawn here:
# glass that's dark, smooth and not metallic (so it reflects the sky at a
# glance, as real glass does), frames, mullions, sills, recesses (in the
# normal map and occlusion), and the odd blind or curtain behind.
#
# <photos dir> holds Poly Haven's 1K JPEGs as downloaded:
#   <asset>/<asset>_diff_1k.jpg, _nor_gl_1k.jpg, _arm_1k.jpg
# Run with an interpreter that has numpy (Blender's will do:
#   /Applications/Blender.app/Contents/Resources/<v>/python/bin/python3 -I);
# images go in and out through ffmpeg (never through Blender: it colour-
# manages what it saves).
import os
import subprocess
import sys

import numpy as np

CELLS = 8
CELL_W, CELL_H = 1.7, 2.6  # metres


def read_rgb(path):
    probe = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height', '-of', 'csv=p=0', path], capture_output=True, text=True, check=True)
    w, h = map(int, probe.stdout.strip().split(','))
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'], capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(h, w, 3).astype(np.float64) / 255


def write_jpg(path, rgb, q, chroma444):
    h, w, _ = rgb.shape
    data = (np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8).tobytes()
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{w}x{h}', '-i', '-', '-q:v', str(q), '-pix_fmt', 'yuvj444p' if chroma444 else 'yuvj420p', path], input=data, check=True)


def box_down(img, f):
    """Averages f × f blocks (f divides the size): the photo filtered before
    it's resampled down to a facade's scale."""
    h, w = img.shape[:2]
    return img[:h - h % f, :w - w % f].reshape(h // f, f, w // f, f, -1).mean(axis=(1, 3))


def tile_photo(img, size, tiles_x, tiles_y):
    """The photo laid tiles_x × tiles_y times across a size² atlas, sampled
    bilinearly (wrapping, so the atlas tiles seamlessly too)."""
    h, w = img.shape[:2]
    # Pre-filter to about twice the resampled size.
    target = size / tiles_x
    f = max(1, int(w / (2 * target)))
    while w % f or h % f:
        f -= 1
    img = box_down(img, f) if f > 1 else img
    h, w = img.shape[:2]
    ys = (np.arange(size) + 0.5) / size * tiles_y * h - 0.5
    xs = (np.arange(size) + 0.5) / size * tiles_x * w - 0.5
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    fy = (ys - y0)[:, None, None]
    fx = (xs - x0)[None, :, None]
    y0m, y1m = y0 % h, (y0 + 1) % h
    x0m, x1m = x0 % w, (x0 + 1) % w
    a = img[y0m][:, x0m]
    b = img[y0m][:, x1m]
    c = img[y1m][:, x0m]
    d = img[y1m][:, x1m]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def normals_from_height(hgt, px_per_m_x, px_per_m_y, strength=1.0):
    """OpenGL normals of a height field (metres), image rows going down."""
    dx = (np.roll(hgt, -1, axis=1) - np.roll(hgt, 1, axis=1)) * px_per_m_x / 2
    drow = (np.roll(hgt, -1, axis=0) - np.roll(hgt, 1, axis=0)) * px_per_m_y / 2
    n = np.stack([-dx * strength, drow * strength, np.ones_like(hgt)], axis=-1)
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


def blend_normals(base, detail):
    """Whiteout blend of two unit normal fields."""
    n = np.stack([base[..., 0] + detail[..., 0], base[..., 1] + detail[..., 1], base[..., 2] * detail[..., 2]], axis=-1)
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


def srgb(hexrgb):
    return np.array([(hexrgb >> 16) & 255, (hexrgb >> 8) & 255, hexrgb & 255], np.float64) / 255


class Atlas:
    def __init__(self, size, seed):
        self.size = size
        self.cell = size // CELLS
        self.ppm_x = size / (CELLS * CELL_W)
        self.ppm_y = size / (CELLS * CELL_H)
        self.rng = np.random.default_rng(seed)
        s = size
        self.color = np.zeros((s, s, 3))
        self.height = np.zeros((s, s))
        self.rough = np.ones((s, s))
        self.metal = np.zeros((s, s))
        self.ao = np.ones((s, s))
        self.wall = np.ones((s, s), bool)  # where the wall photo shows

    def wall_photo(self, photos, name, tile_m, tint=None, contrast=1.0):
        d = os.path.join(photos, name)
        tx = round(CELLS * CELL_W / tile_m[0])
        ty = round(CELLS * CELL_H / tile_m[1])
        col = tile_photo(read_rgb(os.path.join(d, f'{name}_diff_1k.jpg')), self.size, tx, ty)
        if contrast != 1.0:
            mean = col.reshape(-1, 3).mean(axis=0)
            col = mean + (col - mean) * contrast
        if tint is not None:
            col = col * tint
        nor = tile_photo(read_rgb(os.path.join(d, f'{name}_nor_gl_1k.jpg')), self.size, tx, ty) * 2 - 1
        nor /= np.linalg.norm(nor, axis=-1, keepdims=True)
        arm = tile_photo(read_rgb(os.path.join(d, f'{name}_arm_1k.jpg')), self.size, tx, ty)
        self.color[:] = col
        self.wall_normal = nor
        self.ao[:] = arm[..., 0]
        self.rough[:] = arm[..., 1]
        self.metal[:] = 0

    def rect(self, x0, y0, x1, y1, color, rough, metal=0.0, height=None, wall=False):
        """Fills [x0, x1) × [y0, y1) (pixels within the atlas)."""
        sl = (slice(y0, y1), slice(x0, x1))
        self.color[sl] = color
        self.rough[sl] = rough
        self.metal[sl] = metal
        if height is not None:
            self.height[sl] = height
        self.wall[sl] = wall

    def glass(self, x0, y0, x1, y1, depth):
        """A pane: dark tinted glass, smooth; now and then a blind or a
        curtain behind it (lighter, rougher, its slats in the relief)."""
        r = self.rng.random()
        tint = srgb(0x1C2A30) * (0.75 + 0.5 * self.rng.random())
        if r < 0.16:
            # A blind, part drawn.
            down = y0 + int((y1 - y0) * (0.3 + 0.7 * self.rng.random()))
            self.rect(x0, y0, x1, y1, tint, 0.05, height=-depth)
            slats = srgb(0xB9B6AE) * (0.55 + 0.25 * self.rng.random())
            self.rect(x0, y0, x1, down, slats, 0.32, height=-depth)
            for y in range(y0, down, 3):
                self.color[y, x0:x1] *= 0.8
        elif r < 0.26:
            curtain = [srgb(0xD9D2C3), srgb(0xA8B4BE), srgb(0xC8B49A)][self.rng.integers(3)] * 0.6
            self.rect(x0, y0, x1, y1, curtain, 0.22, height=-depth)
        else:
            self.rect(x0, y0, x1, y1, tint, 0.04 + 0.03 * self.rng.random(), height=-depth)
        # A faint gradient inside (the room's darker at the top).
        g = np.linspace(0.85, 1.05, y1 - y0)[:, None, None]
        self.color[y0:y1, x0:x1] *= g

    def recess_ao(self, x0, y0, x1, y1, width, strength):
        """Darker towards a recess's edges (occlusion)."""
        yy, xx = np.mgrid[y0:y1, x0:x1]
        dist = np.minimum.reduce([xx - x0, x1 - 1 - xx, yy - y0, y1 - 1 - yy]).astype(np.float64)
        self.ao[y0:y1, x0:x1] *= 1 - strength * np.exp(-dist / width)

    def finish(self, out_dir, name, frame_strength=1.0):
        relief = normals_from_height(self.height, self.ppm_x, self.ppm_y, frame_strength)
        base = np.where(self.wall[..., None], self.wall_normal, np.array([0.0, 0.0, 1.0]))
        n = blend_normals(base, relief)
        write_jpg(os.path.join(out_dir, f'{name}_albedo.jpg'), self.color, 4, False)
        write_jpg(os.path.join(out_dir, f'{name}_normal.jpg'), n * 0.5 + 0.5, 3, True)
        write_jpg(os.path.join(out_dir, f'{name}_arm.jpg'), np.stack([self.ao, self.rough, self.metal], axis=-1), 4, True)


def curtain_wall(photos, out, size):
    """Glass towers: storey-high vision glass between slim aluminium
    mullions, a dark spandrel band at each floor."""
    a = Atlas(size, 11)
    a.wall_normal = np.zeros((size, size, 3))
    a.wall_normal[..., 2] = 1
    c = a.cell
    alu = srgb(0xA7ACB0)
    a.rect(0, 0, size, size, alu, 0.35, metal=1.0, height=0.0)
    for cy in range(CELLS):
        for cx in range(CELLS):
            x0, y0 = cx * c, cy * c
            m = max(2, c // 32)
            # Spandrel (the floor's edge) below the vision glass.
            sp = int(c * 0.2)
            a.rect(x0 + m, y0 + c - sp, x0 + c - m, y0 + c - m, srgb(0x1A2024), 0.18, height=-0.02)
            a.glass(x0 + m, y0 + m, x0 + c - m, y0 + c - sp - m, 0.03)
    a.finish(out, 'facade_glass', 1.0)


def punched(photos, out, size, name, wall, tile_m, *, tint=None, contrast=1.0, win=(0.16, 0.12, 0.84, 0.72), frame=0x2B2E31, sill=0xC9C4BA, depth=0.18, seed=21):
    """A wall photograph with a window punched in each cell: a reveal
    (recessed, shaded), a frame, a sill."""
    a = Atlas(size, seed)
    a.wall_photo(photos, wall, tile_m, tint=tint, contrast=contrast)
    c = a.cell
    fw = max(2, c // 40)
    for cy in range(CELLS):
        for cx in range(CELLS):
            x0 = cx * c + int(win[0] * c)
            x1 = cx * c + int(win[2] * c)
            y0 = cy * c + int(win[1] * c)
            y1 = cy * c + int(win[3] * c)
            # The reveal, then the frame, then the glass (and a mullion).
            a.rect(x0, y0, x1, y1, srgb(frame), 0.45, metal=0.6, height=-depth * 0.6)
            a.glass(x0 + fw, y0 + fw, x1 - fw, y1 - fw, depth)
            mid = (x0 + x1) // 2
            a.rect(mid - fw // 2, y0, mid + fw // 2 + 1, y1, srgb(frame), 0.45, metal=0.6, height=-depth * 0.6)
            a.recess_ao(x0, y0, x1, y1, max(2, c // 24), 0.45)
            # The sill, a little proud of the wall.
            a.rect(x0 - fw, y1, x1 + fw, y1 + max(2, c // 26), srgb(sill), 0.6, height=0.03)
    a.finish(out, name, 1.0)


def ribbon(photos, out, size, name, wall, tile_m, *, tint=None, band=(0.22, 0.7), mullions=2, frame=0x34383C, seed=31):
    """A wall photograph with a ribbon of windows along each floor."""
    a = Atlas(size, seed)
    a.wall_photo(photos, wall, tile_m, tint=tint)
    c = a.cell
    fw = max(2, c // 40)
    for cy in range(CELLS):
        y0 = cy * c + int(band[0] * c)
        y1 = cy * c + int(band[1] * c)
        a.rect(0, y0, size, y1, srgb(frame), 0.4, metal=0.7, height=-0.06)
        for cx in range(CELLS):
            for k in range(mullions):
                x0 = cx * c + k * c // mullions
                x1 = cx * c + (k + 1) * c // mullions
                a.glass(x0 + fw, y0 + fw, x1 - fw, y1 - fw, 0.09)
        a.recess_ao(0, y0, size, y1, max(2, c // 30), 0.35)
    a.finish(out, name, 1.0)


def main():
    photos, out = sys.argv[1], sys.argv[2]
    size = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
    curtain_wall(photos, out, size)
    # Dark panelled offices (rectangular facade tiles, 2 m).
    punched(photos, out, size, 'facade_panel', 'rectangular_facade_tiles', (2, 2), win=(0.1, 0.1, 0.9, 0.74), frame=0x1F2225, sill=0x8E8A84, depth=0.14, seed=23)
    # Pale cladding, ribbon windows (exterior wall cladding, 2 m).
    ribbon(photos, out, size, 'facade_clad', 'exterior_wall_cladding_03', (2, 2), mullions=2, seed=33)
    # Old stone (the weathered concrete, its stains calmed, warmed; 3 m),
    # tall windows in deep reveals.
    punched(photos, out, size, 'facade_stone', 'concrete_wall_003', (3, 3), tint=np.array([1.0, 0.96, 0.9]), contrast=0.3, win=(0.24, 0.1, 0.76, 0.78), frame=0x3A3026, sill=0xD8CFC0, depth=0.26, seed=27)
    # Concrete tiles, punched (concrete tile facade, 2 m).
    punched(photos, out, size, 'facade_tile', 'concrete_tile_facade', (2, 2), tint=np.array([1.35, 1.35, 1.35]), win=(0.18, 0.14, 0.82, 0.7), frame=0x5B5F63, sill=0xBDB8AF, depth=0.16, seed=29)


if __name__ == '__main__':
    main()
