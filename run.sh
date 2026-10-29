#!/bin/zsh
# 启动 Touch Bar 装饰屏
#
#   ./run.sh            启动（沿用上次的天气）
#   ./run.sh qing       启动并切到晴天
#   ./run.sh feng       启动并切到刮风
#   ./run.sh yu         启动并切到下雨
#
# 启动后：菜单栏有小图标，点开可切天气 / 进设置 / 退出。
# 快捷键：⌃⌥⌘T 切天气，⌃⌥⌘, 开设置。
set -e
cd "$(dirname "$0")"
ROOT="$(pwd)"
DOMAIN="com.egc.touchbarexp"

case "${1:-}" in
    qing|晴) defaults write "$DOMAIN" weather -int 0 ;;
    feng|风) defaults write "$DOMAIN" weather -int 1 ;;
    yu|雨)   defaults write "$DOMAIN" weather -int 2 ;;
    "")      ;;
    *)       echo "用法: ./run.sh [qing|feng|yu]"; exit 1 ;;
esac

[ -d dist/TouchBarExp.app ] || ./build.sh

# 新旧两代进程都清掉
pkill -f "dist/tbexp" 2>/dev/null || true
pkill -f "TouchBarExp" 2>/dev/null || true
sleep 0.5

# 注意：必须在非沙箱环境下执行，否则 open 会静默失败
open -n "$ROOT/dist/TouchBarExp.app"

sleep 2
echo "已启动。菜单栏应该出现一个小图标。"
echo "日志：~/Library/Logs/tbexp.log"
grep -E "ready|presented|view attached" "$HOME/Library/Logs/tbexp.log" 2>/dev/null | tail -4
