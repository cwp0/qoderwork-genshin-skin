#!/usr/bin/env python3
"""
去白底 v2 —— 消除白色光晕 / 白边残留

问题：单纯用阈值把 (R,G,B)>240 设为透明，会在角色轮廓留下一圈
     半透明的浅色像素，在暗色背景下变成一层明显的"毛边光晕"。

做法：
  1. 先把当前 RGBA 合成回白底，还原原始像素
  2. 近白像素(gray>=thr)做连通域分析，只把"与图片边缘连通"的判定为背景
     —— 这样角色身上的白色（派蒙的头发/衣服）不会被打穿
  3. 前景 mask 向内 erode 1~2px，彻底切掉白色轮廓线
  4. 用 dilate 把前景内部颜色向外渗 3px，替换掉边缘残留的白色（去色边）
  5. alpha 做轻微高斯模糊做抗锯齿，但不产生亮边

用法：
  python3 remove_white_bg_v2.py <file-or-dir> [--thr 232] [--erode 2]
"""
import sys
import os
import argparse
import numpy as np
import cv2
from scipy import ndimage


def process(path, thr=232, erode_px=2, feather=1.0, verbose=True):
    bgra = cv2.imread(path, cv2.IMREAD_UNCHANGED)
    if bgra is None:
        print(f"  ! 无法读取: {path}")
        return False

    if bgra.ndim == 2:
        bgra = cv2.cvtColor(bgra, cv2.COLOR_GRAY2BGRA)
    elif bgra.shape[2] == 3:
        bgra = cv2.cvtColor(bgra, cv2.COLOR_BGR2BGRA)

    h, w = bgra.shape[:2]
    bgr = bgra[:, :, :3].astype(np.float32)
    a_in = bgra[:, :, 3].astype(np.float32) / 255.0

    # 1) 合成回白底，还原原图（消除之前处理留下的半透明状态）
    src = bgr * a_in[..., None] + 255.0 * (1.0 - a_in[..., None])
    src = np.clip(src, 0, 255)

    # 2) 近白连通域 → 只有触边的算背景
    gray = cv2.cvtColor(src.astype(np.uint8), cv2.COLOR_BGR2GRAY)
    nearwhite = gray >= thr
    lab, n = ndimage.label(nearwhite)
    border_ids = set(lab[0, :]) | set(lab[-1, :]) | set(lab[:, 0]) | set(lab[:, -1])
    border_ids.discard(0)
    bg = np.isin(lab, list(border_ids)) if border_ids else np.zeros_like(nearwhite)

    fg = (~bg).astype(np.uint8) * 255

    # 3) 前景往内收，切掉白色轮廓线
    if erode_px > 0:
        k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (erode_px * 2 + 1,) * 2)
        fg = cv2.erode(fg, k)

    # 填掉前景内部因阈值误判产生的小孔
    fg = (ndimage.binary_fill_holes(fg > 127).astype(np.uint8)) * 255

    # 4) 把内部颜色向外渗，替换边缘的白色残留（去色边 / de-fringe）
    solid = cv2.erode(fg, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5)))
    inner = src.copy()
    inner[solid < 128] = 0
    bled = inner.copy()
    for _ in range(3):
        bled = cv2.dilate(bled, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3)))
        keep = solid >= 128
        bled[keep] = inner[keep]
    edge_zone = (fg >= 128) & (solid < 128) & (bled.sum(axis=2) > 0)
    out_bgr = src.copy()
    out_bgr[edge_zone] = bled[edge_zone]

    # 5) alpha 轻微羽化做抗锯齿
    alpha = fg.astype(np.float32)
    if feather > 0:
        alpha = cv2.GaussianBlur(alpha, (0, 0), feather)
    # 羽化后再压一次，避免出现大面积半透明
    alpha = np.clip((alpha - 40) * (255.0 / 215.0), 0, 255)

    out = np.dstack([out_bgr.astype(np.uint8), alpha.astype(np.uint8)])
    cv2.imwrite(path, out, [cv2.IMWRITE_PNG_COMPRESSION, 6])

    if verbose:
        tr = int((alpha == 0).sum())
        semi = int(((alpha > 0) & (alpha < 250)).sum())
        print(f"  ✓ {os.path.basename(path)}  透明 {tr*100//(h*w)}%  半透明 {semi}")
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('target', help='PNG 文件或目录')
    ap.add_argument('--thr', type=int, default=232, help='近白阈值(默认232)')
    ap.add_argument('--erode', type=int, default=2, help='前景内收像素(默认2)')
    ap.add_argument('--feather', type=float, default=1.0, help='alpha 羽化半径')
    args = ap.parse_args()

    files = []
    if os.path.isdir(args.target):
        for root, _, names in os.walk(args.target):
            files += [os.path.join(root, n) for n in names if n.lower().endswith('.png')]
    else:
        files = [args.target]

    print(f"处理 {len(files)} 个文件 (thr={args.thr}, erode={args.erode})")
    ok = 0
    for f in sorted(files):
        if process(f, args.thr, args.erode, args.feather):
            ok += 1
    print(f"完成: {ok}/{len(files)}")


if __name__ == '__main__':
    main()
