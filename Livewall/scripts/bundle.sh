#!/bin/bash
# Build release và đóng gói dist/Livewall.app, chỉ cần Command Line Tools (không cần Xcode).
# Dùng --install để cài vào /Applications, thay bản cũ.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --build-system native
BIN="$(swift build -c release --build-system native --show-bin-path)/Livewall"

APP=dist/Livewall.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Livewall"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - --timestamp=none "$APP"

# Keep this build out of Launch Services, or macOS may open videos with it
# instead of the copy in /Applications.
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -u "$PWD/$APP" 2>/dev/null || true

echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    DEST=/Applications/Livewall.app
    # ⌘Q and the Dock only close Livewall's window, so stop it with a signal.
    pkill -x Livewall 2>/dev/null || true
    while pgrep -x Livewall >/dev/null; do sleep 0.2; done
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    echo "Installed $DEST"
fi
