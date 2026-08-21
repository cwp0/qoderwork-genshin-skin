#!/usr/bin/env bash
# QoderWork 原神皮肤 · 一键换背景
#
# 用法:
#   bash swap-background.sh          # 随机换一张
#   bash swap-background.sh --list   # 列出所有背景
#   bash swap-background.sh 3        # 用第 3 张

set -euo pipefail

SKIN_DIR="${HOME}/.qoderwork/skin"
BG_DIR="${SKIN_DIR}/namecard-assets"
INJECT="${SKIN_DIR}/inject.js"

if [ ! -d "$BG_DIR" ]; then
  echo "❌ 未找到背景池: $BG_DIR"
  exit 1
fi

bgs=()
for f in "$BG_DIR"/*.png; do
  [ -f "$f" ] || continue
  bgs+=("$f")
done

if [ ${#bgs[@]} -eq 0 ]; then
  echo "❌ 背景池为空"
  exit 1
fi

if [ "${1:-}" = "--list" ] || [ "${1:-}" = "-l" ]; then
  echo "可用背景 (${#bgs[@]} 张):"
  i=1
  for f in "${bgs[@]}"; do
    printf "  [%d] %s\n" "$i" "$(basename "$f")"
    i=$((i+1))
  done
  exit 0
fi

# 注入器每次运行都会随机挑一张，我们只需要重跑注入即可
# 但如果用户指定了序号，我们通过临时"隔离"其他背景来实现固定
if [ -n "${1:-}" ] && [[ "$1" =~ ^[0-9]+$ ]]; then
  idx="$1"
  if [ "$idx" -lt 1 ] || [ "$idx" -gt ${#bgs[@]} ]; then
    echo "❌ 序号超出范围 (1-${#bgs[@]})"
    exit 1
  fi
  target="${bgs[$((idx-1))]}"
  echo "指定背景: $(basename "$target")"
  # 用一个"锁定"文件夹保存其他背景，然后只留目标
  LOCK_DIR="${SKIN_DIR}/.namecard-hidden"
  mkdir -p "$LOCK_DIR"
  # 先把之前锁定的还原
  find "$LOCK_DIR" -maxdepth 1 -name '*.png' -exec mv {} "$BG_DIR"/ \; 2>/dev/null || true
  # 把非目标背景移入 lock
  for f in "$BG_DIR"/*.png; do
    if [ "$f" != "$target" ]; then
      mv "$f" "$LOCK_DIR/"
    fi
  done
  echo "(其他背景已临时移到 $LOCK_DIR，用 --restore 恢复池)"
elif [ "${1:-}" = "--restore" ]; then
  LOCK_DIR="${SKIN_DIR}/.namecard-hidden"
  if [ -d "$LOCK_DIR" ]; then
    find "$LOCK_DIR" -maxdepth 1 -name '*.png' -exec mv {} "$BG_DIR"/ \; 2>/dev/null || true
    rmdir "$LOCK_DIR" 2>/dev/null || true
    echo "✅ 背景池已恢复完整 ($(ls "$BG_DIR"/*.png | wc -l | tr -d ' ') 张)"
  else
    echo "无需恢复。"
  fi
else
  echo "随机换一张背景..."
fi

if [ -f "$INJECT" ]; then
  node "$INJECT" 2>&1 | tail -6
fi
