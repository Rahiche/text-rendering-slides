# hdr_preview.py <in.hdr> <out.ppm> [exposure] : a tone-mapped LDR preview (PPM; convert with ffmpeg).
import sys

import numpy as np

sys.path.insert(0, sys.argv[0].rsplit('/', 1)[0])
from sky_sun import read_hdr  # noqa: E402  (main() only runs as a script)

rgb, _ = read_hdr(sys.argv[1])
exposure = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0
x = rgb * exposure
x = x / (1 + x)  # Reinhard
x = np.power(np.clip(x, 0, 1), 1 / 2.2)
img = (x * 255 + 0.5).astype(np.uint8)
h, w, _ = img.shape
with open(sys.argv[2], 'wb') as f:
    f.write(f'P6\n{w} {h}\n255\n'.encode())
    f.write(img.tobytes())
