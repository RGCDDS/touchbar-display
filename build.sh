#!/bin/zsh
# 编译并打包 TouchBarExp.app
#
# 用法：./build.sh [接缝重叠像素，默认 50]
#
# 产物：dist/TouchBarExp.app
#   Contents/MacOS/TouchBarExp     可执行文件
#   Contents/Resources/frames/     9 套帧（内嵌，App 自包含）
#   Contents/Resources/AppIcon.icns
set -e
cd "$(dirname "$0")"

OV="${1:-50}"
APP="dist/TouchBarExp.app"
SRC="src"

echo "▸ 编译（OV=${OV}）"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# -O2 很关键：原来没加优化，合成循环是 -O0 跑的
# 编成通用二进制：Touch Bar 主要存在于 2016–2019 的 Intel 机型上，只出 arm64 等于把大部分用户挡在门外
clang -fobjc-arc -O2 -arch arm64 -arch x86_64 \
      -Wno-objc-method-access -Wno-deprecated-declarations \
      -DTB_OV=${OV}.0 \
      -framework Cocoa -framework ImageIO -framework CoreGraphics \
      -framework Carbon -framework ServiceManagement -framework CoreLocation \
      -o "$APP/Contents/MacOS/TouchBarExp" \
      "$SRC"/*.m

echo "▸ 打包资源"
[ -d assets/frames ] || { echo "缺 assets/frames"; exit 1; }
mkdir -p "$APP/Contents/Resources/frames"
rsync -a assets/frames/ "$APP/Contents/Resources/frames/"

if [ ! -f build/AppIcon.icns ]; then
    echo "▸ 生成图标"
    ./tools/build_icon.sh
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▸ 写 Info.plist"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>          <string>TouchBarExp</string>
    <key>CFBundleIdentifier</key>          <string>com.egc.touchbarexp</string>
    <key>CFBundleName</key>                <string>Touch Bar 装饰屏</string>
    <key>CFBundleDisplayName</key>         <string>Touch Bar 装饰屏</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>CFBundleShortVersionString</key>  <string>1.0</string>
    <key>CFBundleVersion</key>             <string>1</string>
    <key>CFBundleIconFile</key>            <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>      <string>13.0</string>
    <key>LSUIElement</key>                 <false/>
    <key>NSHighResolutionCapable</key>     <true/>
    <key>NSHumanReadableCopyright</key>    <string>本地自用工具</string>
    <key>NSLocationUsageDescription</key>  <string>用来获取你所在城市的天气，决定 Touch Bar 上显示晴、风还是雨。</string>
    <key>NSLocationWhenInUseUsageDescription</key> <string>用来获取你所在城市的天气，决定 Touch Bar 上显示晴、风还是雨。</string>
</dict>
</plist>
PLIST

echo "▸ 签名"
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "  （签名失败，不影响本机运行）"

# 兼容旧命令：./dist/tbexp --trio ...
ln -sf "$PWD/$APP/Contents/MacOS/TouchBarExp" dist/tbexp

SIZE=$(du -sh "$APP" | cut -f1)
echo "✓ built: $APP（${SIZE}，OV=${OV}）"
