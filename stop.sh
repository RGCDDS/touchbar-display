#!/bin/zsh
# 停止并交还 Touch Bar 控制权（系统 Control Strip 会自动回来）
pkill -f "TouchBarExp" 2>/dev/null || pkill -f "dist/tbexp" 2>/dev/null
if pgrep -f "TouchBarExp" >/dev/null 2>&1 || pgrep -f "dist/tbexp" >/dev/null 2>&1; then
    echo "还在跑，可能需要重试"
else
    echo "已停止"
fi
