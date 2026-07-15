#!/bin/zsh
# Regenerate scripts/AppIcon.icns from scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

swift scripts/make-icon.swift "$tmp/icon_1024.png"

iconset="$tmp/AppIcon.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
    sips -z $size $size "$tmp/icon_1024.png" --out "$iconset/icon_${size}x${size}.png" > /dev/null
    double=$((size * 2))
    sips -z $double $double "$tmp/icon_1024.png" --out "$iconset/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$iconset" -o scripts/AppIcon.icns

echo "Wrote scripts/AppIcon.icns"
