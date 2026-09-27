#!/usr/bin/env bash
# Builds the deck once as WebAssembly and assembles the GitHub Pages site:
#   <base>/               landing page (pick a version)
#   <base>/factory/       glyph factory
#   <base>/construction/  construction site
#   <base>/workers/       easy vs hard
#   <base>/detective/     the case of 直
#   <base>/classic/       plain blueprint deck
# Each folder is the same build; the app picks its world from the URL path.
set -euo pipefail

BASE="${BASE_PATH:-/text-rendering-slides/}"
WORLDS=(factory construction workers detective classic)
PLACEHOLDER="/__world_base__/"

flutter build web --wasm --release --base-href "$PLACEHOLDER"

rm -rf build/pages
mkdir -p build/pages
cp tool/pages/index.html build/pages/index.html
for w in "${WORLDS[@]}"; do
  cp -R build/web "build/pages/$w"
  # Only index.html carries the base href.
  sed -i.bak "s#${PLACEHOLDER}#${BASE}${w}/#" "build/pages/$w/index.html"
  rm "build/pages/$w/index.html.bak"
done
# The Chrome vs Flutter comparison page, when its renders exist
# (./compare/capture.sh generates them).
if [ -f compare/out/flutter/lines.json ] && [ -f compare/fonts/NotoSansJP.ttf ]; then
  mkdir -p build/pages/compare/out build/pages/compare/fonts
  cp compare/index.html compare/compare.css compare/compare.js compare/cases.json build/pages/compare/
  cp -R compare/out/flutter build/pages/compare/out/
  cp compare/fonts/NotoSansJP.ttf build/pages/compare/fonts/
fi
touch build/pages/.nojekyll
echo "Site assembled in build/pages (${WORLDS[*]})"
