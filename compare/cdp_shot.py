#!/usr/bin/env python3
"""Full-page screenshot of a page once it (and its Flutter iframes) finished
rendering, via the Chrome DevTools Protocol. Python standard library only.

    python3 compare/cdp_shot.py <url> <out.png> [--width 1900] [--settle 4]

Waits for `document.body.dataset.ready === '1'` (set by compare.js) and for
every <iframe> on the page to contain a <flutter-view>, then lets the page
settle a few seconds (fonts, first frames) and captures the whole page.
"""
import base64
import hashlib
import json
import os
import socket
import struct
import subprocess
import sys
import tempfile
import time
import urllib.request

CHROME = os.environ.get('CHROME', '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
PORT = 9333


class WebSocket:
    """Minimal RFC 6455 client: text frames, masking, large payloads."""

    def __init__(self, url):
        assert url.startswith('ws://')
        hostport, path = url[5:].split('/', 1)
        host, port = hostport.split(':')
        self.sock = socket.create_connection((host, int(port)))
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall((
            f'GET /{path} HTTP/1.1\r\nHost: {hostport}\r\nUpgrade: websocket\r\n'
            f'Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n'
        ).encode())
        resp = b''
        while b'\r\n\r\n' not in resp:
            resp += self.sock.recv(4096)
        head, self.buf = resp.split(b'\r\n\r\n', 1)
        accept = base64.b64encode(hashlib.sha1((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest())
        assert b'101' in head.split(b'\r\n')[0] and accept in head, head

    def send(self, text):
        data = text.encode()
        header = bytearray([0x81])
        n = len(data)
        if n < 126:
            header.append(0x80 | n)
        elif n < 65536:
            header += bytes([0x80 | 126]) + struct.pack('>H', n)
        else:
            header += bytes([0x80 | 127]) + struct.pack('>Q', n)
        mask = os.urandom(4)
        self.sock.sendall(bytes(header) + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))

    def _read(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(1 << 20)
            if not chunk:
                raise ConnectionError('socket closed')
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def recv(self):
        message = b''
        while True:
            b0, b1 = self._read(2)
            n = b1 & 0x7F
            if n == 126:
                n = struct.unpack('>H', self._read(2))[0]
            elif n == 127:
                n = struct.unpack('>Q', self._read(8))[0]
            payload = self._read(n)
            opcode = b0 & 0x0F
            if opcode in (0x1, 0x0):
                message += payload
                if b0 & 0x80:
                    return message.decode()
            elif opcode == 0x8:
                raise ConnectionError('closed by peer')
            # ping/pong/binary: ignore


class Tab:
    def __init__(self, ws):
        self.ws = ws
        self.next_id = 0

    def call(self, method, **params):
        self.next_id += 1
        my_id = self.next_id
        self.ws.send(json.dumps({'id': my_id, 'method': method, 'params': params}))
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get('id') == my_id:
                if 'error' in msg:
                    raise RuntimeError(f'{method}: {msg["error"]}')
                return msg.get('result', {})

    def eval(self, expr):
        r = self.call('Runtime.evaluate', expression=expr, returnByValue=True, awaitPromise=True)
        return r.get('result', {}).get('value')


READY_JS = """(() => {
  if (document.body.dataset.ready !== '1' && document.querySelector('#summary')) return false;
  const frames = [...document.querySelectorAll('iframe')];
  return frames.every((f) => {
    try { return !!f.contentDocument.querySelector('flutter-view'); } catch (_) { return false; }
  });
})()"""


def main():
    args = sys.argv[1:]
    url, out = args[0], args[1]
    width = int(args[args.index('--width') + 1]) if '--width' in args else 1900
    settle = float(args[args.index('--settle') + 1]) if '--settle' in args else 4

    profile = tempfile.mkdtemp(prefix='cdp-shot-')
    chrome = subprocess.Popen([
        CHROME, '--headless=new', f'--remote-debugging-port={PORT}', f'--user-data-dir={profile}',
        '--hide-scrollbars', '--no-first-run', f'--window-size={width},1200',
        # Flutter web needs WebGL; headless Chrome has no GPU context by default.
        '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist',
        'about:blank',
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(100):
            try:
                pages = json.load(urllib.request.urlopen(f'http://127.0.0.1:{PORT}/json/list'))
                page = next(p for p in pages if p.get('type') == 'page')
                break
            except Exception:
                time.sleep(0.1)
        tab = Tab(WebSocket(page['webSocketDebuggerUrl']))
        tab.call('Emulation.setDeviceMetricsOverride', width=width, height=1200, deviceScaleFactor=2, mobile=False)
        tab.call('Page.enable')
        tab.call('Page.navigate', url=url)

        deadline = time.time() + 90
        while time.time() < deadline and not tab.eval(READY_JS):
            time.sleep(0.5)
        time.sleep(settle)  # fonts, first Flutter frames, shader compiles

        height = int(tab.eval('Math.ceil(document.documentElement.scrollHeight)'))
        tab.call('Emulation.setDeviceMetricsOverride', width=width, height=height, deviceScaleFactor=2, mobile=False)
        time.sleep(1.5)
        shot = tab.call('Page.captureScreenshot', format='png', captureBeyondViewport=True)
        with open(out, 'wb') as f:
            f.write(base64.b64decode(shot['data']))
        print(f'{out}  ({width}×{height} css px)')
    finally:
        chrome.terminate()


if __name__ == '__main__':
    main()
