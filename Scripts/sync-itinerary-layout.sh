#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB="${1:-$ROOT/../mapannai-public}"
SOURCE="$WEB/src/lib/map/itinerary-card-layout.ts"
"$WEB/node_modules/.bin/esbuild" "$SOURCE" --bundle --format=iife --global-name=ItineraryLayout --target=es2020 --outfile="$ROOT/App/Resources/itinerary-card-layout.js"
shasum -a 256 "$SOURCE" | awk '{print $1}' > "$ROOT/App/Resources/itinerary-card-layout.sha256"
