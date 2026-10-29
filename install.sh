#!/bin/zsh
# 把 App 装到 /Applications —— 只有装在应用程序目录里，启动台和聚焦才能找到它
#
#   ./install.sh          编译（如果有改动）并安装
#   ./install.sh --build  强制重新编译
set -e
cd "$(dirname "$0")"

APP="TouchBarExp.app"
DEST="/Applications/$APP"

if [ "$1" = "--build" ] || [ ! -d "dist/$APP" ]; then
    ./build.sh
fi

echo "▸ 停掉正在跑的实例"
pkill -f "TouchBarExp" 2>/dev/null || true
sleep 0.6

echo "▸ 拷贝到 $DEST"
rm -rf "$DEST"
cp -R "dist/$APP" "$DEST"

LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# 反复 build 会在 LaunchServices 里堆一堆旧登记：删掉的 App 被系统挪进垃圾桶后还会继续登记，
# 垃圾桶里的副本只要还在就会被反复扫回来。这里把「在垃圾桶里」和「路径已不存在」的都注销。
echo "▸ 清理失效的旧登记"
$LSREG -dump 2>/dev/null | grep "path:.*$APP" \
    | sed 's/^ *path: *//; s/ (0x[0-9a-f]*)//' | sort -u \
    | while IFS= read -r p; do
        case "$p" in
            */.Trash/*) $LSREG -u "$p" 2>/dev/null ;;
            *)          [ -d "$p" ] || $LSREG -u "$p" 2>/dev/null ;;
        esac
    done

echo "▸ 让启动台/聚焦立刻认得它"
$LSREG -f "$DEST" 2>/dev/null || true

open "$DEST"
echo "✓ 已安装。现在能在启动台、聚焦（⌘+空格）和应用程序文件夹里找到它。"
echo
echo "  注意：如果之前开过「开机自启」，它记的是旧的 dist/ 路径，"
echo "        请在设置里把开关关掉再打开一次，让它重新指向 /Applications。"
