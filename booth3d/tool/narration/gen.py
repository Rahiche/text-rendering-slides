"""Speaks the narration (script.py) in the presenter's cloned voice with
ElevenLabs, a clip per beat (assets/narration/NN.mp3), each told its
neighbours' words so the voice runs on from one to the next; then
pace.py holds them still where the picture needs it, and timing.py times
the presentation to them.

    ELEVENLABS_API_KEY=… python3 tool/narration/gen.py [beat numbers…]   (from booth3d/)

The key comes from the environment only (never into the repo). The clips
are the presenter's voice: they stay out of git and off the public site
(.gitignore; the site's deploy leaves them out), in the Mac app only.
"""
import json, os, sys, time, urllib.error, urllib.request
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from script import BEATS  # noqa: E402

VOICE = 'PjgSXvy6ykK0dpUEMwNx'  # "Raouf" (an instant clone)
MODEL = 'eleven_multilingual_v2'  # (ElevenLabs': best for voice-overs)
SETTINGS = {'stability': 0.55, 'similarity_boost': 0.8, 'style': 0.0, 'use_speaker_boost': True, 'speed': 1.0}
OUT = os.path.join('assets', 'narration')
texts = [' '.join(t.split()) for _, t in BEATS]


def speak(i, key):
    body = {'text': texts[i], 'model_id': MODEL, 'voice_settings': SETTINGS}
    if i > 0:
        body['previous_text'] = texts[i - 1]
    if i + 1 < len(texts):
        body['next_text'] = texts[i + 1]
    for attempt in range(4):
        try:
            req = urllib.request.Request(
                f'https://api.elevenlabs.io/v1/text-to-speech/{VOICE}?output_format=mp3_44100_128',
                data=json.dumps(body).encode(),
                headers={'xi-api-key': key, 'Content-Type': 'application/json', 'Accept': 'audio/mpeg'},
            )
            with urllib.request.urlopen(req, timeout=240) as r:
                open(os.path.join(OUT, f'{i:02d}.mp3'), 'wb').write(r.read())
            return f'{i:02d} {BEATS[i][0]}: ok'
        except urllib.error.HTTPError as e:
            if e.code not in (429, 500, 502, 503):
                return f'{i:02d} {BEATS[i][0]}: HTTP {e.code} {e.read().decode(errors="replace")[:200]}'
        except OSError:
            pass
        time.sleep(5 * (attempt + 1))
    return f'{i:02d} {BEATS[i][0]}: failed'


if __name__ == '__main__':
    key = os.environ.get('ELEVENLABS_API_KEY') or sys.exit('ELEVENLABS_API_KEY is not set')
    os.makedirs(OUT, exist_ok=True)
    which = [int(a) for a in sys.argv[1:]] or range(len(texts))
    with ThreadPoolExecutor(3) as ex:
        for line in ex.map(lambda i: speak(i, key), which):
            print(line, flush=True)
