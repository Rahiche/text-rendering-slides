#!/usr/bin/env bash
# Builds the conference-stall loop ("Name Factory · 名前工場",
# lib/main_booth.dart) as its own macOS app and installs it as
# ~/Applications/Name Factory.app. Also leaves a zip to share in build/share/.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Name Factory"
DEST="${1:-$HOME/Applications}"

flutter build macos --release -t lib/main_booth.dart | grep -E "✓|rror" || true
SRC=build/macos/Build/Products/Release/text_slides.app
OUT="build/macos/$NAME.app"
rm -rf "$OUT"
cp -R "$SRC" "$OUT"

PLIST="$OUT/Contents/Info.plist"
plutil -replace CFBundleName -string "$NAME" "$PLIST"
plutil -replace CFBundleDisplayName -string "$NAME" "$PLIST"
plutil -replace CFBundleIdentifier -string dev.slides.nameFactory "$PLIST"
codesign --force --deep --sign - --entitlements macos/Runner/Release.entitlements "$OUT" 2>&1 | grep -v "replacing existing signature" || true

mkdir -p "$DEST" build/share
rm -rf "$DEST/$NAME.app"
cp -R "$OUT" "$DEST/"
rm -f "build/share/$NAME.zip"
ditto -c -k --sequesterRsrc --keepParent "$OUT" "build/share/$NAME.zip"
echo "Installed: $DEST/$NAME.app"
echo "To share:  build/share/$NAME.zip"
