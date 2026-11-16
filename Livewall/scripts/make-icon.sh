#!/bin/bash
# Vẽ lại icon: Resources/AppIcon.icns (đóng vào app) và Resources/Icons/AppIcon-<cỡ>.png (để xem trên GitHub).
# Hình vẽ nằm trong scripts/make-icon.swift; sửa ở đó rồi chạy lại script này.
set -euo pipefail
cd "$(dirname "$0")/.."

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
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns

mkdir -p Resources/Icons
cp "$ICONSET/icon_16x16.png" Resources/Icons/AppIcon-16.png
cp "$ICONSET/icon_32x32.png" Resources/Icons/AppIcon-32.png
cp "$ICONSET/icon_32x32@2x.png" Resources/Icons/AppIcon-64.png
cp "$ICONSET/icon_128x128.png" Resources/Icons/AppIcon-128.png
cp "$ICONSET/icon_256x256.png" Resources/Icons/AppIcon-256.png
cp "$ICONSET/icon_512x512.png" Resources/Icons/AppIcon-512.png
cp "$ICONSET/icon_512x512@2x.png" Resources/Icons/AppIcon-1024.png
echo "Icon → Resources/AppIcon.icns, Resources/Icons/"
