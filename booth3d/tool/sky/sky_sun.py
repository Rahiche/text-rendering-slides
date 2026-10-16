# sky_sun.py <in.hdr> <out.hdr> <out.json> [glow_cap]
# Lifts the sun out of an equirect Radiance HDR: measures its direction
# (flutter_scene's env convention: row 0 up, lon = atan2(z, x)) and its
# irradiance, then replaces it with the sky around it plus a soft, capped
# glow, so image-based lighting doesn't count it a second time next to the
# directional light that casts the shadows. Writes new-style RLE RGBE.
import json
import math
import sys

import numpy as np


def read_hdr(path):
    data = open(path, 'rb').read()
    pos = 0
    header = []
    while True:
        end = data.index(b'\n', pos)
        line = data[pos:end].decode('ascii', 'replace')
        pos = end + 1
        if line == '':
            break
        header.append(line)
    end = data.index(b'\n', pos)
    res = data[pos:end].decode('ascii').split()
    pos = end + 1
    assert res[0] == '-Y' and res[2] == '+X', res
    h, w = int(res[1]), int(res[3])
    out = np.zeros((h, w, 4), np.uint8)
    buf = memoryview(data)
    for y in range(h):
        if w >= 8 and w < 32768 and buf[pos] == 2 and buf[pos + 1] == 2 and (buf[pos + 2] << 8 | buf[pos + 3]) == w:
            pos += 4
            for c in range(4):
                x = 0
                while x < w:
                    n = buf[pos]
                    pos += 1
                    if n > 128:
                        n -= 128
                        out[y, x:x + n, c] = buf[pos]
                        pos += 1
                    else:
                        out[y, x:x + n, c] = np.frombuffer(buf[pos:pos + n], np.uint8)
                        pos += n
                    x += n
        else:
            out[y] = np.frombuffer(buf[pos:pos + 4 * w], np.uint8).reshape(w, 4)
            pos += 4 * w
    e = out[..., 3].astype(np.int32)
    scale = np.where(e > 0, np.ldexp(1.0, e - 136), 0.0).astype(np.float64)
    rgb = out[..., :3].astype(np.float64) * scale[..., None]
    return rgb, header


def write_hdr(path, rgb):
    h, w, _ = rgb.shape
    m = rgb.max(axis=2)
    mant, exp = np.frexp(m)
    with np.errstate(divide='ignore', invalid='ignore'):
        sc = np.where(m > 1e-32, mant * 256.0 / np.where(m > 1e-32, m, 1), 0)
    rgbe = np.zeros((h, w, 4), np.uint8)
    rgbe[..., :3] = np.clip(rgb * sc[..., None], 0, 255).astype(np.uint8)
    rgbe[..., 3] = np.where(m > 1e-32, exp + 128, 0).astype(np.uint8)
    parts = [b'#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n', f'-Y {h} +X {w}\n'.encode()]
    for y in range(h):
        parts.append(bytes([2, 2, w >> 8, w & 255]))
        for c in range(4):
            parts.append(rle(rgbe[y, :, c]))
    open(path, 'wb').write(b''.join(parts))


def rle(row):
    # Runs of 3+ equal bytes as (128 + n, byte), up to 127 at a time; the
    # bytes between them as literal packets of up to 128.
    n = len(row)
    change = np.flatnonzero(np.diff(row)) + 1
    starts = np.concatenate(([0], change))
    lengths = np.diff(np.concatenate((starts, [n])))
    out = bytearray()

    def literals(a, b):
        while a < b:
            k = min(128, b - a)
            out.extend(bytes([k]))
            out.extend(row[a:a + k].tobytes())
            a += k

    lit = 0
    for s, l in zip(starts[lengths >= 3].tolist(), lengths[lengths >= 3].tolist()):
        literals(lit, s)
        v = int(row[s])
        while l >= 3:
            k = min(127, l)
            out.extend(bytes([128 + k, v]))
            s += k
            l -= k
        lit = s  # (a leftover of 1–2 joins the next literals)
    literals(lit, n)
    return bytes(out)


def main():
    src, dst, info_path = sys.argv[1:4]
    glow_cap = float(sys.argv[4]) if len(sys.argv) > 4 else 6.0
    rgb, _ = read_hdr(src)
    h, w, _ = rgb.shape
    lum = rgb @ np.array([0.2126, 0.7152, 0.0722])
    v = (np.arange(h) + 0.5) / h
    u = (np.arange(w) + 0.5) / w
    lat = (0.5 - v) * math.pi
    lon = (u - 0.5) * 2 * math.pi
    clat, slat = np.cos(lat)[:, None], np.sin(lat)[:, None]
    dirs = np.stack([clat * np.cos(lon)[None, :], np.broadcast_to(slat, (h, w)), clat * np.sin(lon)[None, :]], axis=-1)
    domega = (2 * math.pi / w) * (math.pi / h) * np.cos(lat)[:, None] * np.ones((1, w))
    upper = lat[:, None] > 0
    sky_med = float(np.median(lum[np.broadcast_to(upper, (h, w))]))
    peak = np.unravel_index(np.argmax(lum), lum.shape)
    sun0 = dirs[peak]
    # Background: the sky on a ring 6–10° from the brightest pixel.
    ang = np.degrees(np.arccos(np.clip(dirs @ sun0, -1, 1)))
    ring = (ang > 6) & (ang < 10)
    bg = np.median(rgb[ring], axis=0)
    bg_l = float(bg @ np.array([0.2126, 0.7152, 0.0722]))
    # The sun: what's well above that background within 6°.
    region = (ang < 6) & (lum > 4 * bg_l)
    excess = np.clip(rgb - bg, 0, None) * region[..., None]
    e_rgb = (excess * domega[..., None]).sum(axis=(0, 1))  # irradiance, per channel
    wsum = (excess @ np.array([0.2126, 0.7152, 0.0722])) * domega
    sun = (dirs * wsum[..., None]).sum(axis=(0, 1))
    sun /= np.linalg.norm(sun)
    ang = np.degrees(np.arccos(np.clip(dirs @ sun, -1, 1)))
    # Replace it: everything within 6° capped at 4× the sky around it, up
    # to glow_cap× in the middle (a soft bright patch, no dark ring: what's
    # under the cap is left as it is).
    cap = np.maximum(4.0, glow_cap * np.exp(-(ang / 1.6) ** 2))[..., None] * bg[None, None, :]
    soft = np.where((ang < 6)[..., None], np.minimum(rgb, cap), rgb)
    write_hdr(dst, soft)
    # Sky irradiance on the ground (upper hemisphere, cos-weighted), the
    # horizon's and the zenith's colours.
    cosw = np.clip(dirs[..., 1], 0, None) * domega
    e_sky = (soft * cosw[..., None]).sum(axis=(0, 1))
    hz = (lat[:, None] > np.radians(1)) & (lat[:, None] < np.radians(6))
    horizon = soft[np.broadcast_to(hz, (h, w))].mean(axis=0)
    zen = soft[lat > np.radians(75)].reshape(-1, 3).mean(axis=0)
    el = math.degrees(math.asin(sun[1]))
    az = math.degrees(math.atan2(sun[2], sun[0]))
    info = {
        'size': [w, h],
        'sun_env_dir': [round(float(x), 5) for x in sun],
        'sun_elevation_deg': round(el, 2),
        'sun_lon_deg': round(az, 2),
        'sun_irradiance_rgb': [round(float(x), 3) for x in e_rgb],
        'sun_pixels': int(region.sum()),
        'sun_peak_lum': round(float(lum[peak]), 1),
        'sky_median_lum': round(sky_med, 4),
        'sky_irradiance_rgb': [round(float(x), 4) for x in e_sky],
        'horizon_rgb': [round(float(x), 4) for x in horizon],
        'zenith_rgb': [round(float(x), 4) for x in zen],
        'glow_cap': glow_cap,
    }
    json.dump(info, open(info_path, 'w'), indent=1)
    print(json.dumps(info))


if __name__ == '__main__':
    main()
