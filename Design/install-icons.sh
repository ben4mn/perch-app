#!/bin/sh
# Copies freshly rendered icons into the app asset catalogs and the Design folder.
# Usage: swift Design/render-icon.swift Design/out [palette] && Design/install-icons.sh Design/out
set -eu
cd "$(dirname "$0")/.."
OUT="${1:-Design/out}"
MAC=Apps/Mac/Assets.xcassets/AppIcon.appiconset
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$OUT/icon-mac.png" --out "$MAC/icon_${size}@1x.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$OUT/icon-mac.png" --out "$MAC/icon_${size}@2x.png" >/dev/null
done
cp "$OUT/icon-ios.png" Apps/iOS/App/Assets.xcassets/AppIcon.appiconset/icon.png
cp "$OUT/mark.png" Apps/Mac/Assets.xcassets/PerchMark.imageset/mark.png
cp "$OUT/mark.png" Apps/iOS/App/Assets.xcassets/PerchMark.imageset/mark.png
cp "$OUT/icon-mac.png" Design/perch-icon.png
cp "$OUT/mark.png" Design/perch-mark.png
echo "Icons installed."
