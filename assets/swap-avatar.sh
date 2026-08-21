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

  cp "$src" "$AVATAR_TARGET"
  echo "✅ 头像已换为: $(basename "$src" .png)"
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
cp "$src" "$AVATAR_TARGET"
echo ""
echo "✅ 头像已换为: $region/$char"

# 立即重新注入
if [ -f "$INJECT" ]; then
  echo ""
  echo "正在刷新皮肤..."
  node "$INJECT" 2>&1 | tail -6
fi
