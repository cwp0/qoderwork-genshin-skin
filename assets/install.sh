#!/usr/bin/env bash
#
# QoderWork 原神主题皮肤 · 安装脚本
#
# 做法：把皮肤资源拷到 ~/.qoderwork/skin，生成 launchd 常驻服务
# （监听 DevToolsActivePort，QoderWork 每次启动/重启渲染进程都会自动重注入），
# 并立即注入一次。全程零侵入：不改 app.asar、不破坏签名、不动更新。
#
# 用法：  bash install.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.qoderwork.skin"
SKIN_DIR="$HOME/.qoderwork/skin"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"
PORT_FILE="$HOME/Library/Application Support/QoderWork/DevToolsActivePort"
STAMP="$(date +%Y%m%d-%H%M%S)"

echo "==> QoderWork 原神主题皮肤 安装程序"

# 1) 平台检查
if [[ "$(uname)" != "Darwin" ]]; then
  echo "错误: 本皮肤依赖 macOS launchd + CDP，仅支持 macOS。" >&2
  exit 1
fi

# 2) 探测 node（需 >= 21，内置全局 WebSocket）
NODE_BIN="$(command -v node || true)"
if [[ -z "$NODE_BIN" ]]; then
  for c in /opt/homebrew/bin/node /usr/local/bin/node /usr/bin/node; do
    [[ -x "$c" ]] && NODE_BIN="$c" && break
  done
fi
if [[ -z "$NODE_BIN" ]]; then
  echo "错误: 未找到 node。请先安装 Node.js >= 21 (brew install node)。" >&2
  exit 1
fi
NODE_MAJOR="$("$NODE_BIN" -e 'console.log(process.versions.node.split(".")[0])' 2>/dev/null || echo 0)"
if [[ "$NODE_MAJOR" -lt 21 ]]; then
  echo "错误: 检测到 node $("$NODE_BIN" -v)，但本皮肤需要 Node >= 21（内置全局 WebSocket）。" >&2
  echo "      请升级：brew upgrade node" >&2
  exit 1
fi
echo "==> 使用 node: $NODE_BIN ($("$NODE_BIN" -v))"

# 3) 若已有 skin 目录（可能是上一版皮肤），先备份到废纸篓
if [[ -d "$SKIN_DIR" ]]; then
  echo "==> 备份现有皮肤到废纸篓: ~/.Trash/qoderwork-skin.$STAMP"
  mkdir -p "$HOME/.Trash"
  cp -R "$SKIN_DIR" "$HOME/.Trash/qoderwork-skin.$STAMP" 2>/dev/null || true
fi

# 4) 拷贝资源到运行目录
echo "==> 拷贝资源到 $SKIN_DIR"
mkdir -p "$SKIN_DIR/genshin"
cp -f "$SCRIPT_DIR/inject.js"          "$SKIN_DIR/"
cp -f "$SCRIPT_DIR/genshin-theme.css"  "$SKIN_DIR/"
# 换头像 / 换背景 便捷脚本
for helper in swap-avatar.sh swap-background.sh; do
  if [[ -f "$SCRIPT_DIR/$helper" ]]; then
    cp -f "$SCRIPT_DIR/$helper" "$SKIN_DIR/$helper"
    chmod +x "$SKIN_DIR/$helper"
  fi
done
# genshin/ 里的图不覆盖已存在的（保留用户可能已换的 avatar.png 等）
for f in "$SCRIPT_DIR/genshin/"*.png; do
  [[ -f "$f" ]] || continue
  base="$(basename "$f")"
  if [[ ! -f "$SKIN_DIR/genshin/$base" ]]; then
    cp -f "$f" "$SKIN_DIR/genshin/$base"
  fi
done

# 素材库（角色头像选择器 + 名片背景）
# 注意：必须拷贝目录「内容」（src/.），直接 cp -Rf src dst 在 dst 已存在时
# 会把源目录嵌套进去（character-gallery/character-gallery），旧素材永不更新。
if [[ -d "$SCRIPT_DIR/character-gallery" ]]; then
  echo "==> 拷贝角色头像素材库..."
  mkdir -p "$SKIN_DIR/character-gallery"
  cp -Rf "$SCRIPT_DIR/character-gallery/." "$SKIN_DIR/character-gallery/"
fi
if [[ -d "$SCRIPT_DIR/namecard-assets" ]]; then
  echo "==> 拷贝名片素材库..."
  mkdir -p "$SKIN_DIR/namecard-assets"
  cp -Rf "$SCRIPT_DIR/namecard-assets/." "$SKIN_DIR/namecard-assets/"
fi
if [[ -f "$SCRIPT_DIR/namecard-data.json" ]]; then
  cp -f "$SCRIPT_DIR/namecard-data.json" "$SKIN_DIR/namecard-data.json"
fi

# 5) 由模板生成 plist（替换 __NODE__ / __HOME__ 占位符）
echo "==> 生成 launchd 配置: $PLIST_DST"
mkdir -p "$HOME/Library/LaunchAgents"
sed -e "s#__NODE__#$NODE_BIN#g" \
    -e "s#__HOME__#$HOME#g" \
    "$SCRIPT_DIR/com.qoderwork.skin.plist.template" > "$PLIST_DST"

# 6) 加载 launchd 服务（先卸旧的，忽略不存在的报错）
echo "==> 注册常驻服务"
launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load  "$PLIST_DST"

# 7) 立即注入一次（若 QoderWork 已开着，马上生效）
if [[ -f "$PORT_FILE" ]]; then
  echo "==> QoderWork 正在运行，立即注入..."
  "$NODE_BIN" "$SKIN_DIR/inject.js" || echo "   (首次注入未成功，QoderWork 下次刷新时会自动重试)"
else
  echo "==> 未检测到运行中的 QoderWork。启动 QoderWork 后皮肤会自动注入。"
fi

echo ""
echo "✅ 安装完成！"
echo ""
echo "🎨 换头像 (交互挑选):"
echo "   bash ~/.qoderwork/skin/swap-avatar.sh"
echo ""
echo "🖼  换背景 (随机 / 指定):"
echo "   bash ~/.qoderwork/skin/swap-background.sh          # 随机换一张"
echo "   bash ~/.qoderwork/skin/swap-background.sh 3        # 用第 3 张"
echo "   bash ~/.qoderwork/skin/swap-background.sh --list   # 列出所有背景"
echo ""
echo "🔁 手动刷新:  node ~/.qoderwork/skin/inject.js"
echo "🧹 卸载:      bash \"$SCRIPT_DIR/uninstall.sh\""
