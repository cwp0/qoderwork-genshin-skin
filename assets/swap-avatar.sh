#!/usr/bin/env bash
# QoderWork 原神皮肤 · 一键换头像
#
# 用法:
#   bash swap-avatar.sh                # 交互式挑选
#   bash swap-avatar.sh 稻妻/raiden-shogun    # 直接指定角色路径（相对 character-gallery）
#   bash swap-avatar.sh --list         # 只列出所有可用角色

set -euo pipefail

SKIN_DIR="${HOME}/.qoderwork/skin"
GALLERY="${SKIN_DIR}/character-gallery"
AVATAR_TARGET="${SKIN_DIR}/genshin/avatar.png"
INJECT="${SKIN_DIR}/inject.js"

# 自动头像裁剪：把全身立绘裁到「头+双角」方形，避免头像卡里只看到身体
crop_to_head() {
  local src="$1" dst="$2"
  python3 - "$src" "$dst" <<'PY'
import sys
from PIL import Image
import numpy as np

src, dst = sys.argv[1], sys.argv[2]
img = Image.open(src).convert('RGBA')
w, h = img.size
arr = np.array(img)
alpha = arr[:, :, 3]
nz = np.where(alpha > 10)
if len(nz[0]) == 0:
    # 全透明兜底：直接拷原图
    img.save(dst); sys.exit(0)
top, bottom = int(nz[0].min()), int(nz[0].max())
left, right = int(nz[1].min()), int(nz[1].max())
body_h = bottom - top
# 头部（含发/角/耳）大约占顶部 42%
head_h = int(body_h * 0.42)
crop_top = max(0, top - int(body_h * 0.03))
crop_bottom = top + head_h
cx = (left + right) // 2
side = crop_bottom - crop_top
half = side // 2
crop_left = max(0, cx - half)
crop_right = min(w, cx + half)
final_side = min(crop_right - crop_left, crop_bottom - crop_top)
crop_right = crop_left + final_side
crop_bottom = crop_top + final_side
out = img.crop((crop_left, crop_top, crop_right, crop_bottom)).resize((512, 512), Image.LANCZOS)
out.save(dst)
PY
}

# 兜底：没有 python3 / PIL 时退回直接拷贝
copy_or_crop() {
  local src="$1" dst="$2"
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import PIL, numpy' >/dev/null 2>&1; then
    crop_to_head "$src" "$dst" || cp "$src" "$dst"
  else
    cp "$src" "$dst"
  fi
}

if [ ! -d "$GALLERY" ]; then
  echo "❌ 未找到角色图库: $GALLERY"
  echo "   请先运行 bash assets/install.sh 完成安装"
  exit 1
fi

# 列出所有可用角色
list_all() {
  local region
  for region in "$GALLERY"/*/; do
    [ -d "$region" ] || continue
    local rname
    rname=$(basename "$region")
    echo ""
    echo "── $rname ──"
    ls "$region"*.png 2>/dev/null | while read -r f; do
      echo "  $rname/$(basename "$f" .png)"
    done
  done
}

if [ "${1:-}" = "--list" ] || [ "${1:-}" = "-l" ]; then
  list_all
  exit 0
fi

# ============ 直接指定 ============
if [ -n "${1:-}" ]; then
  # 支持 "稻妻/raiden-shogun" 或 "raiden-shogun"
  arg="$1"
  # 去掉可能的 .png 后缀
  arg="${arg%.png}"

  src=""
  if [[ "$arg" == */* ]]; then
    src="${GALLERY}/${arg}.png"
  else
    # 只给了名字，全库搜
    found=$(find "$GALLERY" -name "${arg}.png" -maxdepth 2 2>/dev/null | head -1)
    if [ -n "$found" ]; then src="$found"; fi
  fi

  if [ -z "$src" ] || [ ! -f "$src" ]; then
    echo "❌ 找不到角色: $arg"
    echo "   用 bash swap-avatar.sh --list 查看所有可选"
    exit 1
  fi

  copy_or_crop "$src" "$AVATAR_TARGET"
  echo "✅ 头像已换为: $(basename "$src" .png)（已自动裁到头部）"
  echo "   ($src)"
  if [ -f "$INJECT" ]; then
    node "$INJECT" 2>&1 | tail -3
  fi
  exit 0
fi

# ============ 交互式挑选 ============
echo "═══════════════════════════════════════"
echo "  QoderWork 原神主题 · 换头像"
echo "═══════════════════════════════════════"

# 收集所有 region
regions=()
for d in "$GALLERY"/*/; do
  [ -d "$d" ] || continue
  regions+=("$(basename "$d")")
done

if [ ${#regions[@]} -eq 0 ]; then
  echo "❌ 图库为空"
  exit 1
fi

# 让用户选地区
echo ""
echo "选择地区："
i=1
for r in "${regions[@]}"; do
  # 数一下该地区多少角色
  n=$(ls "$GALLERY/$r"/*.png 2>/dev/null | wc -l | tr -d ' ')
  printf "  [%d] %s (%s 位角色)\n" "$i" "$r" "$n"
  i=$((i+1))
done
echo ""
read -r -p "输入序号 (1-${#regions[@]}): " region_idx

if ! [[ "$region_idx" =~ ^[0-9]+$ ]] || [ "$region_idx" -lt 1 ] || [ "$region_idx" -gt ${#regions[@]} ]; then
  echo "❌ 无效序号"
  exit 1
fi

region="${regions[$((region_idx-1))]}"
echo ""
echo "── 地区: $region ──"
echo ""

# 列出该地区角色
chars=()
i=1
for f in "$GALLERY/$region"/*.png; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .png)
  chars+=("$name")
  printf "  [%2d] %s\n" "$i" "$name"
  i=$((i+1))
done

echo ""
read -r -p "输入角色序号 (1-${#chars[@]}): " char_idx

if ! [[ "$char_idx" =~ ^[0-9]+$ ]] || [ "$char_idx" -lt 1 ] || [ "$char_idx" -gt ${#chars[@]} ]; then
  echo "❌ 无效序号"
  exit 1
fi

char="${chars[$((char_idx-1))]}"
src="$GALLERY/$region/$char.png"
copy_or_crop "$src" "$AVATAR_TARGET"
echo ""
echo "✅ 头像已换为: $region/$char（已自动裁到头部）"

# 立即重新注入
if [ -f "$INJECT" ]; then
  echo ""
  echo "正在刷新皮肤..."
  node "$INJECT" 2>&1 | tail -6
fi
