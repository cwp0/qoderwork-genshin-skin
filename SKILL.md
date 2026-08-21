---
name: qoderwork-genshin-skin
description: Installs a Genshin Impact themed skin for the QoderWork desktop app (macOS). Default preset is Ganyu · Cryo (ice-blue palette + Ganyu Q-chibi avatar + Ganyu namecard background). Ships with a top title bar (元素图标), sidebar character avatar card, and a floating Paimon mascot on the new-task welcome page. Applied via zero-invasive CDP injection + launchd persistence (never modifies app.asar). One-shot install auto-applies the Ganyu preset; uninstall cleanly reverts everything to QoderWork defaults. Use when the user asks to install / apply / customize / uninstall the QoderWork Genshin skin, 原神主题/原神皮肤/甘雨主题/冰系主题.
version: 0.3.0
name_zh: 原神主题皮肤 for QoderWork（甘雨·冰系）
---

# QoderWork 原神主题皮肤（默认预设：甘雨·冰系）

把 QoderWork 桌面端换成原神风格配色。**开箱即用的默认预设是「甘雨·冰系」**：冰蓝
主色令牌（`--color-primary` 家族全部改为 `#78c8e8 / #4aa8d0` 冰蓝）+ 甘雨 Q 版证件照
头像 + 甘雨名片作为聊天区背景 + 顶部深蓝标题栏（带元素图标）+ 侧边栏「旅行者」头像
卡 + 新任务欢迎页浮动派蒙吉祥物。

> 用户安装本 skill 后 QoderWork 立刻切换成甘雨主题；卸载后所有注入的 CSS/DOM 会被清除，
> `~/.qoderwork/skin/` 目录整体移入废纸篓，页面恢复 QoderWork 默认外观。

实现方式是**零侵入**的：通过 CDP（Chrome DevTools Protocol）向渲染进程注入 CSS + DOM，
配合 launchd 常驻服务在每次 QoderWork 启动/刷新时自动重注入。**不改 app.asar、不破坏
签名、不受应用更新影响**，随时可一键卸载还原。

## 前提条件（Prerequisites）

- **macOS**（依赖 launchd + `~/Library/Application Support/QoderWork/DevToolsActivePort`）。
- **Node.js >= 21**（脚本用到内置全局 `WebSocket`）。检查：`node -v`；升级：`brew upgrade node`。
- **QoderWork 已安装**。首次注入需 QoderWork 正在运行（会写出 DevToolsActivePort）；
  若安装时未运行，launchd 会在下次启动时自动注入。

## 安装（Install）

```bash
cd <此 skill 的 assets 目录>
bash install.sh
```

`install.sh` 会自动完成：

1. 探测可用的 `node`（`command -v node` → 常见 Homebrew 路径兜底）并校验版本 >= 21。
2. 若已有旧的 `~/.qoderwork/skin/` 目录（例如上一版 QQ 皮肤），先整目录备份到废纸篓。
3. 把资源拷到 `~/.qoderwork/skin/`（`inject.js`、`genshin-theme.css`、`genshin/*.png`）。
   `genshin/` 里已存在的同名文件**不覆盖**，保留用户自定义（例如你换过的 `avatar.png`）。
4. 用 `com.qoderwork.skin.plist.template` 生成 `~/Library/LaunchAgents/com.qoderwork.skin.plist`
   （用 `sed` 替换 `__NODE__` / `__HOME__` 占位符），并 `launchctl load`。
5. 若 QoderWork 已在运行，立即注入一次。

安装后若首页没立刻变化，点一下「新任务」回到首页即可看到浮动派蒙。

## 卸载（Uninstall）

```bash
cd <此 skill 的 assets 目录>
bash uninstall.sh
```

会 `launchctl unload` 常驻服务、在页面内运行 `inject.js --remove` 移除所有注入的
`<style id="qw-genshin-skin">`、`#qw-genshin-titlebar`、`#qw-genshin-sidecard`、浮动派蒙
DOM 并刷新还原，然后把 plist 和 `~/.qoderwork/skin/` 运行目录**整体移入「废纸篓」**
（遵循文件保护策略，不使用 `rm`，可随时恢复）。卸载后 QoderWork 恢复默认外观，
下次启动也不会再自动注入。

## 手动运行 / 刷新

```bash
node ~/.qoderwork/skin/inject.js            # 注入或刷新皮肤
node ~/.qoderwork/skin/inject.js --remove   # 移除皮肤并刷新页面还原
```

## 换头像 / 换角色立绘（Change avatar / character）

皮肤里所有可视素材都是 `~/.qoderwork/skin/genshin/` 下的 PNG 文件。**换任意一张后，
重跑 `node ~/.qoderwork/skin/inject.js` 就能生效**（因为图片是每次注入时 base64 内联到 DOM 的）。

| 文件 | 出现在哪 | 建议规格 |
| --- | --- | --- |
| `genshin/avatar.png` | 侧边栏顶部头像卡里的那张小方图 | 方形 PNG，128×128 以上；金色边框自动生成 |
| `genshin/character-card.png` | 右侧角色卡里的立绘 | 竖版 PNG，300×500 比例最佳；透明底效果最好 |
| `genshin/paimon-mascot.png` | 新任务欢迎页的浮动派蒙 | **必须**透明底 PNG；显示尺寸 96×96，源图 200×200~400×400 都行 |
| `genshin/vision-*.png` | 角色卡里的元素图标 | 32×32 像素 PNG |

## 皮肤四大部分（改动点）

1. **配色（甘雨·冰系）**：注入 `<style id="qw-genshin-skin">`，把 `--color-primary`
   家族（含 `-hover/-active/-text/-bg/-border`）、`--color-warning`、`--color-border*`
   全部改为冰蓝（暗色 `#78c8e8`，亮色 `#4aa8d0`），并在 `[data-modal]/[data-agents-page]/`
   `[data-agents-channel]/[data-scope]` 等作用域容器里重复整套覆盖，防止 QoderWork
   在这些容器里把 `--color-primary` 重新定义成绿色。同时显式修 `.text-warning`
   （思考中）、`.text-primary-active`（待办对勾）、`::selection`、`.bg-bg-highlight`
   （白底 pill 按钮，暗色模式下强制黑字，防止白底白字）。
2. **顶部标题栏**：`position:fixed;height:30px` 的深蓝渐变横条 + "Genshin × QoderWork"
   字标 + 元素装饰点（风/冰/雷）。
3. **侧边栏头像卡**：挂在 `.agents-sidebar > [class*="group/sidebar"]` 第二个子元素
   之前的可折叠卡片（头像 + "旅行者" + "✦ 探索中..."），MutationObserver 兜底 React 重渲染。
4. **浮动派蒙**：定位官方 hero `div.size-12.relative > canvas` 把 canvas 设 `opacity:0`，
   覆盖一个 `<img src="paimon-mascot.png">` 在 `@keyframes paimon-float` 里跑
   `translateY(±10px) rotate(±3°)`，2.5 秒一个周期。

## 与 qoderwork-qq2007-skin 的关系

两个皮肤共用同一个 launchd label（`com.qoderwork.skin`）和同一个运行目录
`~/.qoderwork/skin/`。**同一时间只能启用一个**：运行另一个皮肤的 `install.sh`
会先把当前运行目录备份到废纸篓，再放入新皮肤的文件。想切回来重跑对应
skill 的 `install.sh` 即可。

## 常见问题（Pitfalls）

- 派蒙显示白框：源图不是透明 PNG。用支持透明背景的工具重导一次。
- 角色卡显示不全 / 消失：右侧停靠面板被折叠了。展开即可。
- `hosts=0`：当前不在首页/欢迎页。回到「新任务」首页即可。
- 缺 `WebSocket`：Node < 21。升级 Node 后重跑。
- 找不到 DevToolsActivePort：QoderWork 未运行。启动后重试。
- 应用更新后皮肤消失：正常。launchd 会在下次启动自动重注入。

## 验证（Verification）

- 安装脚本或 `node ~/.qoderwork/skin/inject.js` 的输出（launchd 触发时写入
  `~/.qoderwork/skin/inject.log`）应有这两行：
  - `CSS 注入: "OK: CSS 21693 chars"`（字符数随版本变化，非 0 即正常）
  - `皮肤 DOM: "bootstrap: theme=dark, paimonHosts=1, observers=active"`
  - `paimonHosts=0` 表示当前不在新任务欢迎页，属正常；切到「新任务」页后重跑即为 1。
- 在 QoderWork 界面应看到：整体冰蓝主色（无绿色/金色残留）、顶部深蓝标题栏、
  侧边栏「旅行者」头像卡 + "✦ 探索中..."、甘雨立绘背景、新任务页派蒙上下飘浮。
- 切换亮/暗主题，背景应各自换到 `-light` / `-dark` 名片，主色随之切到
  `#4aa8d0` / `#78c8e8`。
