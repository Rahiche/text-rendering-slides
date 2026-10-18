"""Listens to the narration's clips (ElevenLabs speech to text) and lists
where what was said differs from script.py: a word dropped or added, a name
said wrong. (Numbers come back as digits, spellings vary: read the list.)

    ELEVENLABS_API_KEY=… python3 tool/narration/check.py [beat numbers…]   (from booth3d/)
"""
import difflib, json, os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from script import BEATS  # noqa: E402

OUT = os.path.join('assets', 'narration')


def words(s):
    return re.findall(r"[a-z0-9']+|[぀-ヿ一-鿿]+", s.lower().replace('-', ' '))


def heard(i, key):
    r = subprocess.run(
        ['curl', '-s', '-m', '180', 'https://api.elevenlabs.io/v1/speech-to-text', '-H', f'xi-api-key: {key}', '-F', 'model_id=scribe_v1', '-F', f'file=@{OUT}/{i:02d}.mp3'],
        capture_output=True, text=True,
    )
    said = json.loads(r.stdout).get('text', '')
    a, b = words(' '.join(BEATS[i][1].split())), words(said)
    ops = difflib.SequenceMatcher(None, a, b).get_opcodes()
    return i, [(op, ' '.join(a[i1:i2]), ' '.join(b[j1:j2])) for op, i1, i2, j1, j2 in ops if op != 'equal']


if __name__ == '__main__':
    key = os.environ.get('ELEVENLABS_API_KEY') or sys.exit('ELEVENLABS_API_KEY is not set')
    which = [int(a) for a in sys.argv[1:]] or range(len(BEATS))
    with ThreadPoolExecutor(3) as ex:
        for i, diffs in ex.map(lambda i: heard(i, key), which):
            print(f'{i:02d} {BEATS[i][0]}' + ''.join(f'\n    {op}: [{x}] → [{y}]' for op, x, y in diffs), flush=True)
