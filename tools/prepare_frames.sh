#!/bin/zsh
# 从原始 webm 重新抽取帧。用法：./tools/prepare_frames.sh <webm文件> <输出目录名>
#
# 产出：
#   assets/frames/<名字>/sharp/%04d.png   820x60，直接用于合成
#   assets/frames/<名字>/thumb/%04d.png   205x15，接缝柔焦用的失焦版
#
# 为什么 scale=820:70 而不是 820:60：
#   源视频带 SAR 263:240（非方形像素），显示比例是 11.69:1 而不是 1920/180=10.67:1。
#   直接 scale 到 820:70 等于顺手把 SAR 校正进像素，再 crop 成 60 才是正确构图。
set -e
cd "$(dirname "$0")/.."

SRC="$1"
NAME="$2"

[ -n "$NAME" ] || { echo "用法: $0 <webm文件> <输出目录名>"; exit 1; }
[ -f "$SRC" ] || { echo "找不到视频文件：$SRC"; exit 1; }

# ffmpeg 从哪来：优先用仓库自带的（版本验证过），其次用系统装的（brew install ffmpeg）。
# 自带的那个是 arm64 静态二进制，Intel Mac 上跑不起来，所以要真的执行一下才知道能不能用。
FF=""
for cand in "./tools/ffmpeg" "$(command -v ffmpeg 2>/dev/null)"; do
    if [ -n "$cand" ] && [ -x "$cand" ] && "$cand" -version >/dev/null 2>&1; then
        FF="$cand"
        break
    fi
done
[ -n "$FF" ] || { echo "找不到可用的 ffmpeg。装一个：brew install ffmpeg"; exit 1; }

mkdir -p "assets/frames/$NAME/sharp" "assets/frames/$NAME/thumb"

"$FF" -y -v error -i "$SRC" \
      -vf "scale=820:70:flags=lanczos,crop=820:60" \
      -vsync 0 "assets/frames/$NAME/sharp/%04d.png"

"$FF" -y -v error -i "$SRC" \
      -vf "scale=820:70:flags=lanczos,crop=820:60,gblur=sigma=5,scale=205:15" \
      -vsync 0 "assets/frames/$NAME/thumb/%04d.png"

echo "$NAME: $(ls assets/frames/$NAME/sharp | wc -l | tr -d ' ') 帧"
