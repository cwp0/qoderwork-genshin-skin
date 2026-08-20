---
name: qoderwork-genshin-skin
description: Installs a Genshin Impact theme skin for the QoderWork desktop app (macOS) — Liyue-gold warm palette, top title bar with elemental icons, right-side character profile card with namecard banner, sidebar character avatar card, and a floating Paimon mascot on the new-task welcome page. Applied via zero-invasive CDP injection + launchd persistence (never modifies app.asar). Use when the user asks to install / apply / customize / uninstall the QoderWork Genshin skin, 原神主题/原神皮肤/璃月金主题.
version: 0.1.0
name_zh: 原神主题皮肤 for QoderWork
---

# QoderWork 原神主题皮肤

把 QoderWork 桌面端换成原神风格配色：璃月金暖色令牌 + 顶部深蓝标题栏（带元素图标）+
右侧角色资料卡（名片横幅/角色立绘/元素Vision/命之座星级/个性签名）+ 侧边栏角色头像卡 +
新任务欢迎页浮动派蒙吉祥物。

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

会 `launchctl unload` 常驻服务、在页面内移除皮肤并刷新还原，然后把 plist 和运行目录
**移入「废纸篓」**（遵循文件保护策略，不使用 `rm`，可随时恢复）。

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

1. **配色**：注入 `<style id="qw-genshin-skin">`，覆盖 `:root[data-theme]` 下的
   璃月金暖色 token（白面板 + 暖米底 + 原神金强调 + 汉仪文黑 + 金色滚动条）。
2. **顶部标题栏**：`position:fixed;height:30px` 的深蓝渐变横条 + "Genshin × QoderWork"
   字标 + 当前元素图标 + 三个装饰按钮（原石/摩拉/体力）。
3. **角色资料卡**：挂在 `.workbench-right-dock-panel` 顶部的可折叠面板
   （名片横幅 / 角色立绘 / Vision / 命座 / 签名），MutationObserver 兜底。
4. **浮动派蒙**：定位官方 hero `div.size-12.relative > canvas` 把 canvas 设 `opacity:0`，
   覆盖一个 `<img src="paimon-mascot.png">` 在 rAF 循环里跑 `Math.sin`：
   `translateY(±10px) rotate(±3°)`，2.5 秒一个周期。

## 元素主题切换（TODO: v2）

计划支持通过命令行参数切换 7 种元素配色：

```bash
node ~/.qoderwork/skin/inject.js --element=pyro    # 火元素：暖红金
node ~/.qoderwork/skin/inject.js --element=hydro   # 水元素：深蓝靛
node ~/.qoderwork/skin/inject.js --element=anemo   # 风元素：薄荷绿
node ~/.qoderwork/skin/inject.js --element=electro # 雷元素：紫罗兰
node ~/.qoderwork/skin/inject.js --element=cryo    # 冰元素：冰蓝白
node ~/.qoderwork/skin/inject.js --element=dendro  # 草元素：翠绿
node ~/.qoderwork/skin/inject.js --element=geo     # 岩元素：琥珀金（默认）
```

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

- 看 `~/.qoderwork/skin/inject.log`，应有：
  - `CSS 注入: "OK: CSS xxxx chars"`
  - `顶栏/资料卡: "titlebar=1, character=1"`
  - `侧边栏头像: "sidebar card=1, observer=active"`
  - `浮动派蒙: "paimon mascot: hosts=1, built=1, observer=active"`（在新任务页时）
- 在 QoderWork 界面应看到：整体璃月金暖色、顶部深蓝标题栏、右侧角色卡、
  侧边栏金框头像 + "探索中..."、新任务页派蒙上下飘浮。
