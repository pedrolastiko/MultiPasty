#!/bin/bash
# Generates Resources/AppIcon.icns from Tools/make-icon.swift.
# The .icns is a build artefact, so it is not committed: this script rebuilds it.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift Tools/make-icon.swift "$WORK" > /dev/null

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
cp "$WORK/icon_16.png"   "$ICONSET/icon_16x16.png"
cp "$WORK/icon_32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$WORK/icon_32.png"   "$ICONSET/icon_32x32.png"
cp "$WORK/icon_64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$WORK/icon_128.png"  "$ICONSET/icon_128x128.png"
cp "$WORK/icon_256.png"  "$ICONSET/icon_128x128@2x.png"
cp "$WORK/icon_256.png"  "$ICONSET/icon_256x256.png"
cp "$WORK/icon_512.png"  "$ICONSET/icon_256x256@2x.png"
cp "$WORK/icon_512.png"  "$ICONSET/icon_512x512.png"
cp "$WORK/icon_1024.png" "$ICONSET/icon_512x512@2x.png"

mkdir -p Resources
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Resources/AppIcon.icns"
