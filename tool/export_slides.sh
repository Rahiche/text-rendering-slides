#!/usr/bin/env bash
# Exports slides as PNG (final state of each slide) from the real macOS app,
# and optionally assembles them into a PDF.
#
#   tool/export_slides.sh [--world factory-simple] [--only id1,id2] [--tag name]
#                         [--slot 0] [--pdf out.pdf]
#
# PNGs (3200×1800) land in build/slides/<tag>/, plus 1600×900 previews in
# build/slides/<tag>/preview/. While it runs, a small window in the screen's
# bottom-right corner walks the deck; it must stay visible (macOS stops
# drawing covered windows), so don't cover it. Never kill other exports.
set -euo pipefail
cd "$(dirname "$0")/.."

WORLD=factory-simple ONLY="" TAG="" SLOT=0 PDF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --world) WORLD="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --slot) SLOT="$2"; shift 2 ;;
    --pdf) PDF="$2"; shift 2 ;;
    *) echo "unknown option $1"; exit 64 ;;
  esac
done
TAG="${TAG:-$WORLD}"

flutter build macos --release -t lib/main_export.dart \
  --dart-define=WORLD="$WORLD" --dart-define=EXPORT_ONLY="$ONLY" --dart-define=EXPORT_TAG="$TAG" \
  | grep -E "✓|rror" || true
APP=build/macos/Build/Products/Release/text_slides.app/Contents/MacOS/text_slides
LOG="build/slides/$TAG.log"
mkdir -p build/slides
set +e
SLIDES_EXPORT="$SLOT" "$APP" > "$LOG" 2>&1
code=$?
set -e
grep -E "exported|EXPORT_DONE|export:" "$LOG" || true
[ $code -eq 0 ] || { echo "export failed (exit $code), see $LOG"; exit $code; }

SRC=$(grep EXPORT_DONE "$LOG" | sed 's/^EXPORT_DONE //')
OUT="build/slides/$TAG"
rm -rf "$OUT"
mkdir -p "$OUT/preview"
cp "$SRC"/*.png "$OUT/"
for f in "$OUT"/*.png; do sips -Z 1600 "$f" --out "$OUT/preview/$(basename "$f")" >/dev/null; done
echo "PNGs: $OUT"

if [ -n "$PDF" ]; then
  swift tool/slides_pdf.swift "$PDF" "$OUT"/*.png
fi
