#!/usr/bin/env bash
# One command: render every case in Flutter (Text vs KumihanText) and in
# Chrome (default vs Japanese CSS), then screenshot the comparison page.
#
#   ./compare/capture.sh            → compare/out/compare.png
#   ./compare/capture.sh --serve    → also keep the live page at http://localhost:8765
set -euo pipefail
cd "$(dirname "$0")/.."

FONT=compare/fonts/NotoSansJP.ttf
if [ ! -f "$FONT" ]; then
  echo "Fetching Noto Sans JP (SIL OFL) …"
  mkdir -p compare/fonts
  curl -sSL -o "$FONT" "https://github.com/google/fonts/raw/main/ofl/notosansjp/NotoSansJP%5Bwght%5D.ttf"
fi

# The zoom section's HTML side uses the deck's own fonts.
cp assets/fonts/SpaceGrotesk.ttf assets/fonts/NotoSansJP-case.ttf compare/fonts/

echo "Rendering Flutter cases …"
flutter test test/compare_render_test.dart --reporter compact

# The zoom section embeds the real Flutter web app (probe mode) in iframes.
echo "Building the Flutter web app (Wasm) for the zoom section …"
flutter build web --wasm --release --base-href /out/app/ -o "$PWD/compare/out/app" 2>&1 | grep -E "✓|rror" || true

PORT=8765
python3 -m http.server "$PORT" --directory compare >/dev/null 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT
sleep 1

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
# Full-page screenshots once the page and its Flutter iframes have rendered
# (Chrome DevTools Protocol, Python standard library only).
shoot() { # url, output
  CHROME="$CHROME" python3 compare/cdp_shot.py "http://localhost:$PORT/$1" "$2"
}
echo "Screenshotting Chrome …"
shoot "index.html?part=type" compare/out/compare.png
shoot "index.html?part=zoom&static=1" compare/out/compare-zoom.png
echo "→ compare/out/compare.png, compare/out/compare-zoom.png"

if [ "${1:-}" = "--serve" ]; then
  echo "Live page: http://localhost:$PORT/index.html  (Ctrl+C to stop)"
  wait $SERVER
fi
