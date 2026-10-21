"""Holds the narration's clips still where script.py's PAUSES say, for the
picture to play out: silence put into the take at gaps between sentences.
After gen.py, before timing.py:

    python3 tool/narration/pace.py        (from booth3d/; ffmpeg on the PATH)

A clip's pauses are measured on one take: each must fall in a silence of
it, or nothing's changed (and the take's gaps are listed, to measure them
again). A clip already held (its take's length plus its pauses) is left
as it is, so running this again does nothing.
"""
import os, re, subprocess, sys, tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from script import BEATS, PAUSES  # noqa: E402

OUT = os.path.join('assets', 'narration')


def seconds(path):
    out = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', path], capture_output=True, text=True, check=True)
    return float(out.stdout)


def gaps(path):
    """The take's silences (start, end), between and within sentences."""
    err = subprocess.run(['ffmpeg', '-hide_banner', '-i', path, '-af', 'silencedetect=noise=-38dB:d=0.15', '-f', 'null', '-'], capture_output=True, text=True).stderr
    starts = [float(x) for x in re.findall(r'silence_start: ([\d.]+)', err)]
    ends = [float(x) for x in re.findall(r'silence_end: ([\d.]+)', err)]
    return list(zip(starts, ends))


names = [beat for beat, _ in BEATS]
for beat, (take, holds) in PAUSES.items():
    path = os.path.join(OUT, f'{names.index(beat):02d}.mp3')
    now, held = seconds(path), take + sum(s for _, s in holds)
    if abs(now - held) < 0.15:
        print(f'{path} {beat}: held already ({now:.2f} s)')
        continue
    found = gaps(path)
    listed = ', '.join(f'{a:.2f}–{b:.2f}' for a, b in found)
    if abs(now - take) > 0.05:
        sys.exit(f'{path} {beat}: {now:.3f} s, not the {take} s take its pauses are for; measure them again on its gaps: {listed}')
    for at, _ in holds:
        if not any(a + 0.03 <= at <= b - 0.03 for a, b in found):
            sys.exit(f'{path} {beat}: {at} s is not in a silence; its gaps: {listed}')
    # The take cut at each pause, each piece followed by its silence.
    cuts = [0.0] + [at for at, _ in holds]
    parts = []
    for k, start in enumerate(cuts):
        end = f':end={cuts[k + 1]}' if k + 1 < len(cuts) else ''
        pad = f',apad=pad_dur={holds[k][1]}' if k < len(holds) else ''
        parts.append(f'[0]atrim=start={start}{end},asetpts=PTS-STARTPTS{pad}[p{k}]')
    graph = ';'.join(parts) + ';' + ''.join(f'[p{k}]' for k in range(len(cuts))) + f'concat=n={len(cuts)}:v=0:a=1'
    fd, tmp = tempfile.mkstemp(suffix='.mp3', dir=OUT)
    os.close(fd)
    try:
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', path, '-filter_complex', graph, '-ar', '44100', '-c:a', 'libmp3lame', '-b:a', '128k', tmp], check=True)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    print(f'{path} {beat}: {take:.2f} s → {seconds(path):.2f} s, held at ' + ', '.join(f'{at:.2f} (+{s} s)' for at, s in holds))
