#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="Packages/NexusUI/Sources/NexusUI/Resources/Wallpaper"
mkdir -p "$OUT"

if ! command -v rsvg-convert >/dev/null 2>&1; then
    echo "ERROR: rsvg-convert not installed. brew install librsvg" >&2
    exit 1
fi

# Grain at 1x/2x/3x (240x240 base)
rsvg-convert -w 240 -h 240 tools/wallpaper-grain.svg > "$OUT/Wallpaper-Grain.png"
rsvg-convert -w 480 -h 480 tools/wallpaper-grain.svg > "$OUT/Wallpaper-Grain@2x.png"
rsvg-convert -w 720 -h 720 tools/wallpaper-grain.svg > "$OUT/Wallpaper-Grain@3x.png"

echo "Wallpaper assets baked into $OUT"
