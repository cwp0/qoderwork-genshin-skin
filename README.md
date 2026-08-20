# QoderWork 原神主题皮肤

零侵入（不改 app.asar，不破坏签名）的 QoderWork 桌面端原神风格皮肤。通过 Chrome DevTools Protocol (CDP) 注入，launchd 监听 QoderWork 启动自动生效。

## 效果

- 全页面名片背景（随机从背景池抽取）+ 亮/暗色磨砂蒙层
- 顶部原神风格标题栏（元素色圆点装饰）
- 侧边栏角色头像卡
- 新任务欢迎页浮动派蒙
- 璃月金色调（亮色）/ 深渊星空（暗色）自适应配色
- 原神金滚动条 & 焦点环

## 安装

```bash
# 确保 Node >= 21（需要内置全局 WebSocket）
node --version

# 克隆仓库
git clone https://github.com/cwp0/qoderwork-genshin-skin.git
cd qoderwork-genshin-skin

# 一键安装（复制素材 + 注册 launchd 自启 + 立即注入）
bash assets/install.sh
```

安装后 QoderWork 每次启动/重启都会自动注入皮肤。

## 卸载

```bash
bash assets/uninstall.sh
```

这会：
1. 移除 launchd 定时任务（停止自动注入）
2. 通过 CDP 清除已注入的皮肤元素并刷新页面
3. 把 `~/.qoderwork/skin/` 移到废纸篓（不会永久删除）

## 自定义

所有素材文件位于 `~/.qoderwork/skin/`（安装后的运行时目录）。修改后重跑一次注入即可生效：

```bash
node ~/.qoderwork/skin/inject.js
```

### 换头像

替换 `~/.qoderwork/skin/genshin/avatar.png`，建议 128×128 以上的方形 PNG（透明底）。

角色图库里有预置的 Q 版角色可选：

```bash
# 查看可用角色
ls ~/.qoderwork/skin/character-gallery/

# 比如换成雷电将军
cp ~/.qoderwork/skin/character-gallery/稻妻/raiden-shogun.png \
   ~/.qoderwork/skin/genshin/avatar.png

# 重新注入
node ~/.qoderwork/skin/inject.js
```

### 换背景

背景池目录：`~/.qoderwork/skin/namecard-assets/`

每次注入会从该目录随机抽一张作为全页面背景。你可以：

```bash
# 添加新背景（建议 1792×1024 横向图片）
cp your-image.png ~/.qoderwork/skin/namecard-assets/

# 删除不想要的背景
mv ~/.qoderwork/skin/namecard-assets/unwanted.png ~/.Trash/

# 重新注入（会随机选一张新的）
node ~/.qoderwork/skin/inject.js
```

如果只想用特定一张背景，把其余的都移出目录只留那一张即可。

### 换派蒙

替换 `~/.qoderwork/skin/genshin/paimon-mascot.png`（需要透明底 PNG，显示尺寸 80×80）。

### 手动触发

如果背景没出来或想换一张，直接重跑：

```bash
node ~/.qoderwork/skin/inject.js
```

### 完全移除（不卸载，只是暂时关掉）

```bash
node ~/.qoderwork/skin/inject.js --remove
```

这会清除注入并刷新页面恢复原样，但 launchd 仍在，下次重启 QoderWork 又会自动注入。

## 技术细节

- **注入方式**：通过 `~/Library/Application Support/QoderWork/DevToolsActivePort` 获取 CDP 端口，WebSocket 连接后 `Runtime.evaluate` 注入
- **持久化**：launchd `WatchPaths` 监听 DevToolsActivePort 文件变化，QoderWork 启动时文件更新即触发注入
- **防 React 重渲染**：MutationObserver + double requestAnimationFrame 确保侧边栏卡片不被 React reconcile 吞掉
- **亮暗适配**：运行时读取 `document.documentElement.getAttribute('data-theme')` 判断，CSS 变量 + 注入 style 双重覆盖

## 目录结构

```
assets/
├── inject.js                  # CDP 注入器主逻辑
├── genshin-theme.css          # 原神配色 CSS（亮+暗）
├── install.sh                 # 安装脚本
├── uninstall.sh               # 卸载脚本
├── com.qoderwork.skin.plist.template  # launchd 模板
├── genshin/                   # 核心素材
│   ├── avatar.png             # 头像
│   ├── character-card.png     # 立绘
│   ├── paimon-mascot.png      # 派蒙
│   └── vision-*.png           # 元素图标
├── namecard-assets/           # 背景池（随机抽取）
│   └── namecard-*.png
└── character-gallery/         # 角色图库（按地区分）
    ├── 蒙德/
    ├── 璃月/
    ├── 稻妻/
    ├── 须弥/
    ├── 枫丹/
    └── 纳塔/
```

## 系统要求

- macOS（launchd + CDP）
- Node.js >= 21（内置全局 WebSocket）
- QoderWork 桌面端

## License

MIT
