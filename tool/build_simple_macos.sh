#!/usr/bin/env bash
# Builds the macOS app of just the talk ("Inside Flutter's Text Pipeline",
# lib/main_simple.dart: no version picker, no other worlds, no labs) and
# installs it as ~/Applications/Inside Flutter's Text Pipeline.app.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Inside Flutter's Text Pipeline"
DEST="${1:-$HOME/Applications}"

flutter build macos --release -t lib/main_simple.dart | grep -E "✓|rror" || true
SRC=build/macos/Build/Products/Release/text_slides.app
OUT="build/macos/$NAME.app"
rm -rf "$OUT"
cp -R "$SRC" "$OUT"

# Its own name and bundle id, so it sits next to the full deck's app.
PLIST="$OUT/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Flutter Text Pipeline" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $NAME" "$PLIST" 2>/dev/null ||
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier dev.slides.textPipeline" "$PLIST"
codesign --force --deep --sign - --entitlements macos/Runner/Release.entitlements "$OUT" 2>&1 | grep -v "replacing existing signature" || true

mkdir -p "$DEST"
rm -rf "$DEST/$NAME.app"
cp -R "$OUT" "$DEST/"
echo "Installed: $DEST/$NAME.app"
