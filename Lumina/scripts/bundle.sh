#!/bin/zsh
# Build release và đóng gói build/Lumina.app. Dùng --install để cài vào /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --arch arm64
APP=build/Lumina.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --arch arm64 --show-bin-path)/Lumina" "$APP/Contents/MacOS/Lumina"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force -s - "$APP"
echo "Built $APP"
if [[ "${1:-}" == "--install" ]]; then
  DEST=/Applications/Lumina.app
  pkill -x Lumina 2>/dev/null || true
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  rm -rf ~/Applications/Lumina.app          # bản cài cũ ở thư mục riêng
  echo "Installed $DEST"
fi
