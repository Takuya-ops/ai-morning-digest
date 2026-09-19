#!/bin/sh
# Run from the repository root on macOS. The source is opaque and square;
# iOS/PWA apply their own corner masks, so none are baked into the artwork.
set -eu
source_icon=design/app-icon-source.png
sips -z 1024 1024 "$source_icon" --out ios/AIDigest/Assets.xcassets/AppIcon.appiconset/AppIcon.png >/dev/null
for destination in static/icons docs/icons; do
  sips -z 512 512 "$source_icon" --out "$destination/icon-512.png" >/dev/null
  sips -z 512 512 "$source_icon" --out "$destination/icon-maskable-512.png" >/dev/null
  sips -z 192 192 "$source_icon" --out "$destination/icon-192.png" >/dev/null
  sips -z 180 180 "$source_icon" --out "$destination/apple-touch-icon.png" >/dev/null
done
