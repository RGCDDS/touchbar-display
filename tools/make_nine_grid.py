#!/usr/bin/env python3
"""把 9 个 clip 的中间帧拼成一张九宫格对照图（行=天气，列=时段）。"""
import os, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FRAMES = os.path.join(ROOT, "assets", "frames")
TMP = "/tmp/tb_montage"
OUT = os.path.join(ROOT, "docs", "preview", "nine-grid.png")

# 行 = 天气，列 = 时段
GRID = [
    ["qing_z", "qing_m", "qing_w"],   # 晴
    ["feng_z", "feng_m", "feng_w"],   # 风
    ["yu_z",   "yu_m",   "yu_w"],     # 雨
]

shutil.rmtree(TMP, ignore_errors=True)
os.makedirs(TMP, exist_ok=True)

picked = []
for row in GRID:
    for name in row:
        sharp = os.path.join(FRAMES, name, "sharp")
        files = sorted(f for f in os.listdir(sharp) if f.endswith(".png"))
        if not files:
            sys.exit("缺帧: " + name)
        mid = files[len(files) // 2]
        dst = os.path.join(TMP, f"{name}.png")
        shutil.copy2(os.path.join(sharp, mid), dst)
        picked.append(dst)
        print(f"  {name:8s} {len(files):3d} 帧  取 {mid}")

os.makedirs(os.path.dirname(OUT), exist_ok=True)
# 3x3 拼接，每格 820x60 → 2460x180
layout = "|".join(f"{(i % 3) * 820}_{(i // 3) * 60}" for i in range(9))
cmd = [os.path.join(ROOT, "tools", "ffmpeg"), "-y", "-v", "error"]
for p in picked:
    cmd += ["-i", p]
cmd += ["-filter_complex",
        "".join(f"[{i}]" for i in range(9)) + f"xstack=inputs=9:layout={layout}:fill=black",
        "-frames:v", "1", OUT]
subprocess.run(cmd, check=True)
print("输出:", OUT)
