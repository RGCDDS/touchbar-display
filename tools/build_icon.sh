#!/bin/zsh
# 生成 build/AppIcon.icns（1024 → iconset → icns）
set -e
cd "$(dirname "$0")/.."

mkdir -p build
clang -fobjc-arc -O2 -framework Cocoa -o build/make_icon tools/make_icon.m
./build/make_icon build/icon-1024.png

ISET=build/AppIcon.iconset
rm -rf "$ISET"
mkdir -p "$ISET"

for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
    px="${spec%% *}"; name="${spec##* }"
    sips -z "$px" "$px" build/icon-1024.png --out "$ISET/icon_${name}.png" >/dev/null
done

iconutil -c icns "$ISET" -o build/AppIcon.icns
echo "icon: build/AppIcon.icns"
