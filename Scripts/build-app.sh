#!/bin/bash
# Builds build/Overview.app from the Swift package.
#
#   Scripts/build-app.sh              build for this Mac
#   Scripts/build-app.sh --universal  build for Apple silicon and Intel (needs Xcode)
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH_FLAGS=""
if [[ "${1:-}" == "--universal" ]]; then
    ARCH_FLAGS="--arch arm64 --arch x86_64"
fi

# shellcheck disable=SC2086
swift build -c release $ARCH_FLAGS --product Overview
# shellcheck disable=SC2086
BINARY="$(swift build -c release $ARCH_FLAGS --show-bin-path)/Overview"

APP="build/Overview.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Overview"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/en.lproj Resources/nl.lproj Resources/Sounds "$APP/Contents/Resources/"
cp Resources/Hero.png "$APP/Contents/Resources/"

# The icon: one PNG scaled to every size macOS asks for.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" Resources/AppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    sips -z "$((SIZE * 2))" "$((SIZE * 2))" Resources/AppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

plutil -lint "$APP/Contents/Info.plist" "$APP"/Contents/Resources/*.lproj/*.strings >/dev/null

# Ad-hoc signature: enough to run on this Mac. Distributing the app to other
# people needs a Developer ID signature and notarization.
codesign --force --sign - "$APP"

echo "Built $APP"
