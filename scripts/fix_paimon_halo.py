#!/usr/bin/env python3
"""
修复派蒙图标的白色光晕 / 半透明白边问题。
方法：对半透明像素做 premultiply 去白色泄漏，
     并对边缘做 erode 去掉剩余白边。
"""
import sys
import numpy as np
from PIL import Image

def fix_white_halo(src_path, dst_path=None):
    if dst_path is None:
        dst_path = src_path
    
    im = Image.open(src_path).convert('RGBA')
    data = np.array(im, dtype=np.float64)
    
    r, g, b, a = data[...,0], data[...,1], data[...,2], data[...,3]
    
    # 对半透明像素(alpha 1~254)，削弱白色分量
    # 思路：如果 RGB 接近白色(亮度>220)且 alpha 偏低，这些是"白色泄漏"像素
    # 直接将它们的 alpha 压低，使白色晕边消失
    mask_semi = (a > 0) & (a < 255)
    brightness = (r + g + b) / 3.0
    
    # 对半透明 + 高亮度像素：按比例削减 alpha
    # 亮度越高 → alpha 削减越多
    white_leak = mask_semi & (brightness > 180)
    if white_leak.any():
        # 亮度 180->1.0 衰减, 255->0.1 衰减
        factor = np.clip((255 - brightness[white_leak]) / 75.0, 0.05, 1.0)
        a[white_leak] = a[white_leak] * factor
    
    # 额外：对极低 alpha (< 30) 且亮度高的直接清零
    faint_white = (a > 0) & (a < 30) & (brightness > 200)
    a[faint_white] = 0
    
    data[...,3] = np.clip(a, 0, 255)
    
    result = Image.fromarray(data.astype(np.uint8), 'RGBA')
    result.save(dst_path)
    
    print(f"Fixed: {src_path} -> {dst_path}")
    total_px = a.size
    transparent = int((data[...,3] == 0).sum())
    print(f"  transparent: {transparent}/{total_px} ({transparent*100//total_px}%)")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python fix_paimon_halo.py <input.png> [output.png]")
        sys.exit(1)
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else src
    fix_white_halo(src, dst)
