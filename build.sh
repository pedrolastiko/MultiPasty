#!/bin/bash
# Assembles MultiPasty.app from the Swift sources in Sources/.
# No package manager, no project file, no dependency: one swiftc call.
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="MultiPasty"
BUNDLE_ID="com.pierrelecalvez.multipasty"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"

echo "→ Cleaning"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

echo "→ Info.plist"
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                  <string>MultiPasty</string>
    <key>CFBundleDisplayName</key>           <string>MultiPasty</string>
    <key>CFBundleIdentifier</key>            <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>            <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>              <string>AppIcon</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleShortVersionString</key>    <string>1.0</string>
    <key>CFBundleVersion</key>               <string>1</string>
    <key>LSMinimumSystemVersion</key>        <string>13.0</string>
    <key>LSUIElement</key>                   <true/>
    <key>NSPrincipalClass</key>              <string>NSApplication</string>
    <key>CFBundleDevelopmentRegion</key>     <string>en</string>
    <key>NSHumanReadableCopyright</key>      <string>MIT licensed</string>
</dict>
</plist>
PLIST

echo "→ Compiling Swift (universal: arm64 + x86_64)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
for ARCH in arm64 x86_64; do
    swiftc \
        -swift-version 5 \
        -O \
        -target "$ARCH-apple-macos13.0" \
        -framework AppKit \
        -framework Carbon \
        -framework ServiceManagement \
        -o "$TMP/$APP_NAME-$ARCH" \
        Sources/*.swift
done
lipo -create -output "$MACOS_DIR/$APP_NAME" "$TMP/$APP_NAME-arm64" "$TMP/$APP_NAME-x86_64"

echo "→ Icon"
if [ ! -f "Resources/AppIcon.icns" ]; then
    ./Tools/make-icon.sh > /dev/null
fi
cp "Resources/AppIcon.icns" "$RES_DIR/AppIcon.icns"

echo "→ Ad-hoc signature"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_DIR" 2>/dev/null \
    || echo "  (signature skipped)"

echo
echo "✅ Built: $(pwd)/$APP_DIR"
