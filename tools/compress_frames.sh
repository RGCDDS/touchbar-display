#!/bin/zsh
# 把抽好的 PNG 帧转成 JPEG（4:4:4，q2），体积约 1/6.5，PSNR ≈ 44dB
#
#   ./tools/compress_frames.sh            # 转换并删除原 PNG
#   ./tools/compress_frames.sh --keep-png # 转换但保留 PNG（对比用）
#
# 为什么是 JPEG 4:4:4 而不是 HEIC：
#   HEIC 走 4:2:0 色度抽样，宽幅画面 PSNR 只有 33dB，且体积不比 JPEG 小。
#   JPEG 4:4:4 q2 是 28KB / 44.4dB，比 HEIC q95 更小也更清楚。
#
# 源视频（~/Pictures/Camera Roll/bilibili壁纸夏）还在，随时能用 prepare_frames.sh 重抽。
set -e
cd "$(dirname "$0")/.."

KEEP=0
[ "$1" = "--keep-png" ] && KEEP=1

# 同 prepare_frames.sh：自带优先，其次系统装的
FF=""
for cand in "./tools/ffmpeg" "$(command -v ffmpeg 2>/dev/null)"; do
    if [ -n "$cand" ] && [ -x "$cand" ] && "$cand" -version >/dev/null 2>&1; then
        FF="$cand"
        break
    fi
done
[ -n "$FF" ] || { echo "找不到可用的 ffmpeg。装一个：brew install ffmpeg"; exit 1; }

BEFORE=$(du -sk assets/frames | cut -f1)

for d in assets/frames/*/sharp assets/frames/*/thumb; do
    [ -d "$d" ] || continue
    n=0
    for f in "$d"/*.png(N); do
        "$FF" -y -v error -i "$f" -pix_fmt yuvj444p -q:v 2 "${f%.png}.jpg"
        n=$((n+1))
    done
    if [ $KEEP -eq 0 ]; then
        rm -f "$d"/*.png
    fi
    echo "  $(dirname $d | xargs basename)/$(basename $d): $n 张"
done

AFTER=$(du -sk assets/frames | cut -f1)
echo "✓ 完成：${BEFORE}KB → ${AFTER}KB（省 $(( (BEFORE - AFTER) * 100 / BEFORE ))%）"
