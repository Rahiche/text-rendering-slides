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

echo "Rendering Flutter cases …"
flutter test test/compare_render_test.dart --reporter compact

PORT=8765
python3 -m http.server "$PORT" --directory compare >/dev/null 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT
sleep 1

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
echo "Screenshotting Chrome …"
"$CHROME" --headless=new --hide-scrollbars --force-device-scale-factor=2 \
  --window-size=1900,4700 --virtual-time-budget=15000 \
  --screenshot="$PWD/compare/out/compare.png" \
  "http://localhost:$PORT/index.html" 2>/dev/null
echo "→ compare/out/compare.png"

if [ "${1:-}" = "--serve" ]; then
  echo "Live page: http://localhost:$PORT/index.html  (Ctrl+C to stop)"
  wait $SERVER
fi
