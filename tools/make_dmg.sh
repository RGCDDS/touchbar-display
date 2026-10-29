#!/bin/zsh
# 生成可分发的 DMG 磁盘映像
#
#   ./tools/make_dmg.sh          用 dist/ 里现成的 App
#   ./tools/make_dmg.sh --build  先重新编译
#
# 产物：dist/TouchBarDisplay-<版本>.dmg
set -e
cd "$(dirname "$0")/.."

APP="TouchBarExp.app"
STAGE="build/dmg-stage"

if [ "$1" = "--build" ] || [ ! -d "dist/$APP" ]; then
    ./build.sh
fi

VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "dist/$APP/Contents/Info.plist")
NAME="TouchBarDisplay-$VER"
OUT="dist/$NAME.dmg"

# 检查一下是不是通用二进制，别把只支持 arm64 的包发出去
ARCHS=$(lipo -info "dist/$APP/Contents/MacOS/TouchBarExp" 2>/dev/null)
case "$ARCHS" in
    *x86_64*arm64*|*arm64*x86_64*) ;;
    *) echo "⚠ 警告：这个二进制只支持 $ARCHS，Intel 机器用不了";;
esac

echo "▸ 准备 DMG 内容"
rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE"
cp -R "dist/$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
[ -f "docs/安装说明.txt" ] && cp "docs/安装说明.txt" "$STAGE/"

echo "▸ 打包"
hdiutil create \
    -volname "Touch Bar 装饰屏 $VER" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$OUT" >/dev/null

rm -rf "$STAGE"

echo "✓ $OUT  ($(du -h "$OUT" | cut -f1))"
