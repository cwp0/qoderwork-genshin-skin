#!/usr/bin/env bash
#
# QoderWork 原神主题皮肤 · 卸载脚本
#
# 用法：  bash uninstall.sh
#
set -euo pipefail

LABEL="com.qoderwork.skin"
SKIN_DIR="$HOME/.qoderwork/skin"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"
STAMP="$(date +%Y%m%d-%H%M%S)"

echo "==> QoderWork 原神主题皮肤 卸载程序"

# 1) 尝试在页面内移除皮肤（若 QoderWork 正在运行）
NODE_BIN="$(command -v node || true)"
if [[ -z "$NODE_BIN" ]]; then
  for c in /opt/homebrew/bin/node /usr/local/bin/node /usr/bin/node; do
    [[ -x "$c" ]] && NODE_BIN="$c" && break
  done
fi
if [[ -n "$NODE_BIN" && -f "$SKIN_DIR/inject.js" ]]; then
  echo "==> 尝试移除页面内皮肤..."
  "$NODE_BIN" "$SKIN_DIR/inject.js" --remove 2>/dev/null || true
fi

# 2) 卸载 launchd 服务
if [[ -f "$PLIST_DST" ]]; then
  echo "==> 卸载常驻服务"
  launchctl unload "$PLIST_DST" 2>/dev/null || true
  # plist 移入废纸篓
  mkdir -p "$HOME/.Trash"
  mv -n "$PLIST_DST" "$HOME/.Trash/$LABEL.plist.$STAMP" 2>/dev/null || true
fi

# 3) 运行目录移入废纸篓（不使用 rm，遵循文件保护策略）
if [[ -d "$SKIN_DIR" ]]; then
  echo "==> 备份皮肤目录到废纸篓: ~/.Trash/qoderwork-skin.$STAMP"
  mkdir -p "$HOME/.Trash"
  mv -n "$SKIN_DIR" "$HOME/.Trash/qoderwork-skin.$STAMP" 2>/dev/null || true
  if [[ -d "$SKIN_DIR" ]]; then
    # mv -n 同名跳过时的兜底
    mv "$SKIN_DIR" "$HOME/.Trash/qoderwork-skin.$STAMP-$$"
  fi
fi

echo ""
echo "✅ 卸载完成！"
echo "   皮肤文件已移入废纸篓，可随时恢复。"
echo "   QoderWork 下次刷新页面将恢复默认外观。"
