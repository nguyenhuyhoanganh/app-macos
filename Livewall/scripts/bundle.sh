#!/bin/bash
# Builds dist/Livewall.app with Command Line Tools only (no Xcode project).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --build-system native
BIN="$(swift build -c release --build-system native --show-bin-path)/Livewall"

APP=dist/Livewall.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Livewall"
cp Resources/Info.plist "$APP/Contents/Info.plist"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
swift scripts/make-icon.swift "$WORK/icon.png"
ICONSET="$WORK/AppIcon.iconset"
mkdir "$ICONSET"
for points in 16 32 128 256 512; do
    sips -z "$points" "$points" "$WORK/icon.png" --out "$ICONSET/icon_${points}x${points}.png" >/dev/null
    double=$((points * 2))
    sips -z "$double" "$double" "$WORK/icon.png" --out "$ICONSET/icon_${points}x${points}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - --timestamp=none "$APP"

# Keep this build out of Launch Services, or macOS may open videos with it
# instead of the copy in /Applications.
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -u "$PWD/$APP" 2>/dev/null || true

echo "Built $APP"
