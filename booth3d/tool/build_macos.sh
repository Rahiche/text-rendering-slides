#!/usr/bin/env bash
# Builds Name City (名前の街, the 3D booth) and installs it as
# ~/Applications/Name City.app, plus a zip to share in build/share/.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Name City"
DEST="${1:-$HOME/Applications}"

flutter build macos --release | grep -E "✓|rror" || true
SRC=build/macos/Build/Products/Release/booth3d.app
OUT="build/macos/$NAME.app"
rm -rf "$OUT"
cp -R "$SRC" "$OUT"

PLIST="$OUT/Contents/Info.plist"
plutil -replace CFBundleName -string "$NAME" "$PLIST"
plutil -replace CFBundleDisplayName -string "$NAME" "$PLIST"
plutil -replace CFBundleIdentifier -string dev.slides.nameCity "$PLIST"
# Visitors can't quit/hide/close it with ⌘-shortcuts (staff: Ctrl+Shift+Q).
plutil -replace BoothKiosk -bool true "$PLIST"
codesign --force --deep --sign - --entitlements macos/Runner/Release.entitlements "$OUT" 2>&1 | grep -v "replacing existing signature" || true

mkdir -p "$DEST" ../build/share
rm -rf "$DEST/$NAME.app"
cp -R "$OUT" "$DEST/"
rm -f "../build/share/$NAME.zip"
ditto -c -k --sequesterRsrc --keepParent "$OUT" "../build/share/$NAME.zip"
echo "Installed: $DEST/$NAME.app"
echo "To share:  build/share/$NAME.zip"
