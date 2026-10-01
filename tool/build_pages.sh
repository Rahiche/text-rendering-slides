#!/usr/bin/env bash
# Builds the deck once as WebAssembly and assembles the GitHub Pages site:
#   <base>/               landing page (pick a version)
#   <base>/factory-simple/  the talk: "Inside Flutter's Text Pipeline"
#   <base>/factory/       glyph factory
#   <base>/construction/  construction site
#   <base>/workers/       easy vs hard
#   <base>/detective/     the case of 直
#   <base>/classic/       plain blueprint deck
# Each folder is the same build; the app picks its world from the URL path.
set -euo pipefail

BASE="${BASE_PATH:-/text-rendering-slides/}"
WORLDS=(factory-simple factory construction workers detective classic)
PLACEHOLDER="/__world_base__/"

flutter build web --wasm --release --base-href "$PLACEHOLDER"

rm -rf build/pages
mkdir -p build/pages
cp tool/pages/index.html build/pages/index.html
# The conference-stall loop (main.dart routes /booth/ and /workshop/ to it).
for b in booth workshop; do
  cp -R build/web "build/pages/$b"
  sed -i.bak "s#${PLACEHOLDER}#${BASE}$b/#" "build/pages/$b/index.html"
  rm "build/pages/$b/index.html.bak"
done
for w in "${WORLDS[@]}"; do
  cp -R build/web "build/pages/$w"
  # Only index.html carries the base href.
  sed -i.bak "s#${PLACEHOLDER}#${BASE}${w}/#" "build/pages/$w/index.html"
  rm "build/pages/$w/index.html.bak"
done
# The printed deck (tool/export_slides.sh --pdf …), when it exists.
PDF=build/slides/inside-flutters-text-pipeline.pdf
if [ -f "$PDF" ]; then
  cp "$PDF" build/pages/
else
  # No PDF: drop its link from the landing page.
  sed -i.bak 's#<!--PDF-->.*<!--/PDF-->##' build/pages/index.html && rm build/pages/index.html.bak
fi
# The Chrome vs Flutter comparison page, when its renders exist
# (./compare/capture.sh generates them).
if [ -f compare/out/flutter/lines.json ] && [ -f compare/fonts/NotoSansJP.ttf ]; then
  mkdir -p build/pages/compare/out build/pages/compare/fonts
  cp compare/index.html compare/compare.css compare/compare.js compare/cases.json compare/zoom.json build/pages/compare/
  cp assets/fonts/SpaceGrotesk.ttf assets/fonts/NotoSansJP-case.ttf build/pages/compare/fonts/
  cp -R compare/out/flutter build/pages/compare/out/
  cp compare/fonts/NotoSansJP.ttf build/pages/compare/fonts/
fi
touch build/pages/.nojekyll
echo "Site assembled in build/pages (${WORLDS[*]})"
