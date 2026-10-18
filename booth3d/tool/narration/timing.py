"""Times the presentation (booth3d/lib/talk/presentation.dart) from the
narration's clips: each beat stays on for its clip, started a moment in,
and a breath after it, the breaths even, so that the whole talk, from the
title to the end of the thanks, takes exactly [TOTAL] seconds. Writes
assets/narration/narration.json.

    python3 tool/narration/timing.py        (from booth3d/; ffprobe on the PATH)
"""
import json, os, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from script import BEATS  # noqa: E402

TOTAL = 25 * 60.0
LEAD = 0.6  # the voice comes in as the camera sets off
OUT = os.path.join('assets', 'narration')


def seconds(path):
    out = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', path], capture_output=True, text=True, check=True)
    return float(out.stdout)


clips = [(beat, f'{i:02d}.mp3', seconds(os.path.join(OUT, f'{i:02d}.mp3'))) for i, (beat, _) in enumerate(BEATS)]
spoken = sum(LEAD + s for _, _, s in clips)
breath = (TOTAL - spoken) / (len(clips) - 1)
if not 0.8 <= breath <= 4.0:
    sys.exit(f'{spoken:.1f} s spoken: a breath of {breath:.2f} s between beats; lengthen or shorten the narration')
out = {
    'total': TOTAL,
    'clips': [
        {'beat': beat, 'file': f, 'start': LEAD, 'seconds': round(s, 3), 'dwell': round(LEAD + s + (breath if i + 1 < len(clips) else 0), 3)}
        for i, (beat, f, s) in enumerate(clips)
    ],
}
json.dump(out, open(os.path.join(OUT, 'narration.json'), 'w'), indent=1, ensure_ascii=False)
print(f'{len(clips)} clips, {spoken - LEAD * len(clips):.1f} s of voice, a {breath:.2f} s breath between beats: {sum(c["dwell"] for c in out["clips"]) / 60:.3f} min')
