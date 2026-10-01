#!/usr/bin/env bash
# Renders booth frames at chosen scene times (no real-time waiting).
#
#   tool/booth_capture.sh --times 5,40,120,160 [--names "Ana,田中太郎"] [--tag x] [--slot 0]
#
# PNGs (1600×900) land in build/booth/<tag>/. A small window appears in the
# screen's bottom-right corner while it runs; keep it uncovered.
set -euo pipefail
cd "$(dirname "$0")/.."
TIMES="5,30,90" NAMES="" TAG="booth" SLOT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --times) TIMES="$2"; shift 2 ;;
    --names) NAMES="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --slot) SLOT="$2"; shift 2 ;;
    *) echo "unknown option $1"; exit 64 ;;
  esac
done
flutter build macos --release -t lib/main_booth_capture.dart \
  --dart-define=BOOTH_TIMES="$TIMES" --dart-define=BOOTH_NAMES="$NAMES" --dart-define=BOOTH_TAG="$TAG" \
  | grep -E "✓|rror" || true
APP=build/macos/Build/Products/Release/text_slides.app/Contents/MacOS/text_slides
mkdir -p build/booth
LOG="build/booth/$TAG.log"
set +e
SLIDES_EXPORT="$SLOT" "$APP" > "$LOG" 2>&1
code=$?
set -e
grep -E "captured|CAPTURE_DONE|rror|xception" "$LOG" | head -40 || true
[ $code -eq 0 ] || { echo "capture failed (exit $code), see $LOG"; exit $code; }
SRC=$(grep CAPTURE_DONE "$LOG" | sed 's/^CAPTURE_DONE //')
rm -rf "build/booth/$TAG"
mkdir -p "build/booth/$TAG"
cp "$SRC"/*.png "build/booth/$TAG/"
echo "PNGs: build/booth/$TAG"
