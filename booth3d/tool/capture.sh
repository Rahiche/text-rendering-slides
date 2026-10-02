#!/usr/bin/env bash
# Renders Name City frames at chosen scene times (no real-time waiting).
#   booth3d/tool/capture.sh --times 10,60,120 [--names "Ana,田中太郎"] [--tag x] [--slot 0]
#     [--define BOOTH3D_LOOK=ex,ey,ez,tx,ty,tz,fov|…]   (any --dart-define, repeatable)
# PNGs (1600×900) land in booth3d/build/capture/<tag>/.
set -euo pipefail
cd "$(dirname "$0")/.."
TIMES="10,40,90" NAMES="" TAG="city" SLOT=0
DEFINES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --times) TIMES="$2"; shift 2 ;;
    --names) NAMES="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --slot) SLOT="$2"; shift 2 ;;
    --define) DEFINES+=("--dart-define=$2"); shift 2 ;;
    *) echo "unknown option $1"; exit 64 ;;
  esac
done
flutter build macos --release --dart-define=BOOTH3D_TIMES="$TIMES" --dart-define=BOOTH3D_NAMES="$NAMES" --dart-define=BOOTH3D_TAG="$TAG" ${DEFINES[@]+"${DEFINES[@]}"} \
  | grep -E "✓|rror" || true
APP=build/macos/Build/Products/Release/booth3d.app/Contents/MacOS/booth3d
mkdir -p build/capture
LOG="build/capture/$TAG.log"
set +e
SLIDES_EXPORT="$SLOT" "$APP" > "$LOG" 2>&1
code=$?
set -e
grep -E "captured|CAPTURE_DONE|rror|xception" "$LOG" | head -40 || true
[ $code -eq 0 ] || { echo "capture failed (exit $code), see $LOG"; exit $code; }
SRC=$(grep CAPTURE_DONE "$LOG" | sed 's/^CAPTURE_DONE //')
rm -rf "build/capture/$TAG"
mkdir -p "build/capture/$TAG"
cp "$SRC"/*.png "build/capture/$TAG/"
echo "PNGs: booth3d/build/capture/$TAG"
