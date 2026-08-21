#!/usr/bin/env node
/**
 * QoderWork 原神主题皮肤 · CDP 安全注入器
 *
 * 做法（零侵入，不改 app.asar，不破坏签名）：
 *   1. 通过 DevToolsActivePort 拿到 QoderWork 渲染进程的 CDP 端口
 *   2. Runtime.evaluate 注入原神璃月金配色 CSS（genshin-theme.css）
 *   3. 全页面名片背景（随机取一张 namecard-assets/*.png）+ 亮/暗蒙层保证文字清晰
 *   4. 顶部深蓝标题栏
 *   5. 侧边栏顶部插入角色头像卡（MutationObserver 兜底 React 重渲染）
 *   6. 新任务欢迎页 Rive hero → 替换为浮动派蒙（CSS 动画飘浮）
 *
 * 用法：
 *   node inject.js            # 注入/刷新皮肤（每次随机换一张背景）
 *   node inject.js --remove   # 移除皮肤并刷新页面还原
 *
 * 依赖：Node >= 21（内置全局 WebSocket）。macOS。QoderWork 需已启动。
 *
 * 自定义素材（改完直接重跑 node inject.js 生效）：
 *   genshin/avatar.png           侧边栏头像卡里的头像（建议 128×128+ 方形 PNG）
 *   genshin/character-card.png   右侧角色卡里的立绘（建议 300×500 比例）
 *   genshin/paimon-mascot.png    新任务页浮动派蒙（PNG 需透明通道；80×80 显示）
 *   namecard-assets/*.png        全页面背景池，随机抽一张（建议 1792×1024 横图）
 *   character-gallery/<地区>/    角色图库，想换头像从这里挑一张覆盖 avatar.png
 */

const fs = require('fs');
const path = require('path');
const http = require('http');

const REMOVE = process.argv.includes('--remove');

// --- ID 常量 ---
const SKIN_ID = 'qw-genshin-skin';
const BG_ID = 'qw-genshin-bg-style';
const TITLEBAR_ID = 'qw-genshin-titlebar';
const PROFILE_ID = 'qw-genshin-profile';
const SIDE_CARD_ID = 'qw-genshin-sidecard';
const MASCOT_STAGE_ATTR = 'data-genshin-paimon-stage';
const MASCOT_STYLE_ID = 'qw-genshin-paimon-style';

// --- 文件路径 ---
const PORT_FILE = path.join(
  process.env.HOME, 'Library/Application Support/QoderWork/DevToolsActivePort'
);
const CSS_FILE = path.join(__dirname, 'genshin-theme.css');
const AVATAR_FILE = path.join(__dirname, 'genshin', 'avatar.png');
const CHARACTER_FILE = path.join(__dirname, 'genshin', 'character-card.png');
const PAIMON_FILE = path.join(__dirname, 'genshin', 'paimon-mascot.png');
const VISION_FILES = {
  anemo: path.join(__dirname, 'genshin', 'vision-anemo.png'),
  pyro: path.join(__dirname, 'genshin', 'vision-pyro.png'),
  hydro: path.join(__dirname, 'genshin', 'vision-hydro.png'),
  electro: path.join(__dirname, 'genshin', 'vision-electro.png'),
  cryo: path.join(__dirname, 'genshin', 'vision-cryo.png'),
  dendro: path.join(__dirname, 'genshin', 'vision-dendro.png'),
  geo: path.join(__dirname, 'genshin', 'vision-geo.png'),
};

// 随机选一张名片背景
const NAMECARD_DIR = path.join(__dirname, 'namecard-assets');
function pickNamecard() {
  try {
    const files = fs.readdirSync(NAMECARD_DIR).filter(f => f.endsWith('.png'));
    if (!files.length) return '';
    const pick = files[Math.floor(Math.random() * files.length)];
    return path.join(NAMECARD_DIR, pick);
  } catch (_) { return ''; }
}

// --- 工具函数 ---

function toDataUri(p) {
  if (!fs.existsSync(p)) return '';
  let mime = 'image/png';
  const lower = p.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) mime = 'image/jpeg';
  else if (lower.endsWith('.gif')) mime = 'image/gif';
  else if (lower.endsWith('.webp')) mime = 'image/webp';
  else if (lower.endsWith('.svg')) mime = 'image/svg+xml';
  return 'data:' + mime + ';base64,' + fs.readFileSync(p).toString('base64');
}

function log(msg) {
  const ts = new Date().toLocaleTimeString('zh-CN', { hour12: false });
  console.log(`[${ts}] [QW-Genshin] ${msg}`);
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

if (typeof WebSocket === 'undefined') {
  log('错误: 当前 Node 缺少全局 WebSocket，请升级到 Node >= 21');
  process.exit(1);
}

// --- CDP 通信层 ---

async function getDebugPort(retries = 10) {
  for (let i = 0; i < retries; i++) {
    try {
      const content = fs.readFileSync(PORT_FILE, 'utf-8').trim();
      const port = parseInt(content.split('\n')[0], 10);
      if (port > 0) return port;
    } catch (_) {}
    log(`等待 QoderWork 启动... (${i + 1}/${retries})`);
    await sleep(2000);
  }
  throw new Error('无法读取 DevToolsActivePort，QoderWork 可能未启动');
}

function httpGet(url) {
  return new Promise((resolve, reject) => {
    http.get(url, res => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => resolve(JSON.parse(data)));
    }).on('error', reject);
  });
}

async function findMainPage(port, retries = 20) {
  for (let i = 0; i < retries; i++) {
    try {
      const targets = await httpGet(`http://127.0.0.1:${port}/json`);
      const main = targets.find(t => t.title === 'QoderWork' && t.type === 'page');
      if (main) return main.webSocketDebuggerUrl;
    } catch (_) {}
    log(`等待 QoderWork 主页面就绪... (${i + 1}/${retries})`);
    await sleep(1500);
  }
  throw new Error('未找到 QoderWork 主页面');
}

function cdpEval(wsUrl, expression) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    const msgId = 1;
    ws.onopen = () => {
      ws.send(JSON.stringify({
        id: msgId,
        method: 'Runtime.evaluate',
        params: { expression, returnByValue: true }
      }));
    };
    ws.onmessage = (event) => {
      const msg = JSON.parse(event.data);
      if (msg.id === msgId) {
        ws.close();
        if (msg.error) reject(new Error(msg.error.message));
        else resolve(msg.result);
      }
    };
    ws.onerror = (err) => reject(err);
    setTimeout(() => { ws.close(); reject(new Error('CDP 超时')); }, 10000);
  });
}

function cdpSend(wsUrl, method, params = {}) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    const msgId = 1;
    ws.onopen = () => ws.send(JSON.stringify({ id: msgId, method, params }));
    ws.onmessage = (event) => {
      const msg = JSON.parse(event.data);
      if (msg.id === msgId) { ws.close(); resolve(msg.result); }
    };
    ws.onerror = (err) => reject(err);
    setTimeout(() => { ws.close(); resolve(null); }, 8000);
  });
}

// --- 清理表达式 ---

function cleanupExpr() {
  return `
    (function() {
      ['${SKIN_ID}','${BG_ID}','${TITLEBAR_ID}','${PROFILE_ID}','${SIDE_CARD_ID}',
       '${MASCOT_STYLE_ID}',
       'qw-luigi-skin','qw-luigi-pipe-style','qw-mario-deco',
       'qw-qq-titlebar','qw-qq-profile','qw-qq-sidecard','qw-qq-surf-style'
      ].forEach(function(id){
        var el = document.getElementById(id); if (el) el.remove();
      });
      document.querySelectorAll('[data-genshin-inject],[${MASCOT_STAGE_ATTR}],[data-luigi-stage],[data-qq-inject],[data-qq-surf-stage]').forEach(function(s){ s.remove(); });
      document.querySelectorAll('div.size-12.relative').forEach(function(host){
        host.style.width = '';
        host.style.height = '';
        host.style.overflow = '';
        var c = host.querySelector('canvas'); if (c) c.style.opacity='';
      });
      ['__qwMascotObs','__qwDecoObs','__qwGenshinObs','__qwPaimonObs','__qwQQObs','__qwSurfObs'].forEach(function(k){
        if (window[k]) { try{window[k].disconnect();}catch(e){} window[k]=null; }
      });
      if (window.__qwPaimonRAF) { try { cancelAnimationFrame(window.__qwPaimonRAF); } catch(e){} window.__qwPaimonRAF = null; }
      if (window.__qwGenshinResize) { window.removeEventListener('resize', window.__qwGenshinResize); window.__qwGenshinResize=null; }
      return 'cleaned';
    })();
  `;
}

// --- 移除模式 ---

async function remove() {
  log('正在移除原神皮肤...');
  const port = await getDebugPort(3);
  const wsUrl = await findMainPage(port);
  await cdpEval(wsUrl, cleanupExpr());
  await cdpSend(wsUrl, 'Page.reload', { ignoreCache: false });
  log('已移除皮肤并刷新页面。');
}

// --- 主注入逻辑 ---

async function main() {
  log('正在注入原神主题皮肤...');

  if (!fs.existsSync(CSS_FILE)) throw new Error(`皮肤文件不存在: ${CSS_FILE}`);
  const css = fs.readFileSync(CSS_FILE, 'utf-8');

  const avatarUri = toDataUri(AVATAR_FILE);
  const characterUri = toDataUri(CHARACTER_FILE);
  const paimonUri = toDataUri(PAIMON_FILE);
  const namecardUri = toDataUri(pickNamecard());

  const port = await getDebugPort();
  log(`CDP 端口: ${port}`);
  const wsUrl = await findMainPage(port);
  log(`目标: ${wsUrl}`);

  // 先清理旧残留
  await cdpEval(wsUrl, cleanupExpr());

  // 第一步：注入 CSS 令牌
  const cssCode = `
    (function() {
      var SKIN_ID = '${SKIN_ID}';
      var old = document.getElementById(SKIN_ID);
      if (old) old.remove();
      var s = document.createElement('style');
      s.id = SKIN_ID;
      s.textContent = ${JSON.stringify(css)};
      document.head.appendChild(s);
      return 'OK: CSS ' + s.textContent.length + ' chars';
    })();
  `;
  const r1 = await cdpEval(wsUrl, cssCode);
  log(`CSS 注入: ${JSON.stringify(r1?.result?.value || r1)}`);

  // 第一步半：注入全页面名片背景（固定层 + 亮/暗蒙层）
  const bgCode = `
    (function() {
      var BG_ID = '${BG_ID}';
      var namecardUri = '${namecardUri}';
      var old = document.getElementById(BG_ID);
      if (old) old.remove();
      if (!namecardUri) return 'no namecard';

      var isDark = (document.documentElement.getAttribute('data-theme') || '').includes('dark');
      // 蒙层：暗 50~58% / 亮 42~52%，让背景清晰可见但文字仍有对比
      var mask = isDark
        ? 'linear-gradient(rgba(10,14,26,0.50),rgba(10,14,26,0.58))'
        : 'linear-gradient(rgba(245,240,232,0.42),rgba(245,240,232,0.52))';

      var s = document.createElement('style');
      s.id = BG_ID;
      s.textContent =
        // 背景挂在 body 的伪元素上，固定铺满整个窗口
        'body::before{content:"";position:fixed;inset:0;z-index:0;pointer-events:none;' +
          'background:' + mask + ', url(' + namecardUri + ') center/cover no-repeat fixed;}' +
        // 让主容器 + 内容区 + chat 面板 + 内部卡片全透明，露出背景
        ':root[data-theme] .agents-layout-root,' +
        ':root[data-theme] .agents-content-area,' +
        ':root[data-theme] .agents-chat-panel,' +
        ':root[data-theme] .workbench-card:not(.workbench-aux-card):not(.workbench-right-dock-panel){' +
          'background:transparent !important;}' +
        // 侧边栏 / 右侧栏保留半透明玻璃底，保证按钮与列表文字对比
        (isDark
          ? ':root[data-theme] .agents-sidebar{background:rgba(15,19,32,0.55) !important;backdrop-filter:blur(10px);}' +
            ':root[data-theme] .workbench-right-dock-panel{background:rgba(19,24,40,0.55) !important;backdrop-filter:blur(10px);}'
          : ':root[data-theme] .agents-sidebar{background:rgba(250,248,242,0.60) !important;backdrop-filter:blur(10px);}' +
            ':root[data-theme] .workbench-right-dock-panel{background:rgba(250,248,242,0.60) !important;backdrop-filter:blur(10px);}') +
        // 保证真实内容在背景之上
        ':root[data-theme] .agents-layout-root{position:relative;z-index:1;}';
      document.head.appendChild(s);
      return 'bg=1, dark=' + isDark;
    })();
  `;
  const r1b = await cdpEval(wsUrl, bgCode);
  log(`全页背景: ${JSON.stringify(r1b?.result?.value || r1b)}`);


  // 第二步：注入标题栏（自动适配亮暗主题）
  const titlebarCode = `
    (function() {
      var TITLEBAR_ID = '${TITLEBAR_ID}';
      var old = document.getElementById(TITLEBAR_ID);
      if (old) old.remove();

      var isDark = (document.documentElement.getAttribute('data-theme') || '').includes('dark');
      var bgGradient = isDark
        ? 'linear-gradient(90deg,#0a0e1a 0%,#1a2035 50%,#0a0e1a 100%)'
        : 'linear-gradient(90deg,#1b2838 0%,#2d4156 50%,#1b2838 100%)';
      var accentColor = isDark ? '#a0d8ee' : '#4aa8d0';       // 冰蓝，替换旧金色 goldColor
      var borderColor = isDark ? '#2a3f55' : '#a0d8ee';       // 边框：冰蓝

      var bar = document.createElement('div');
      bar.id = TITLEBAR_ID;
      bar.style.cssText = 'position:fixed;top:0;left:0;right:0;height:30px;z-index:99999;' +
        'background:' + bgGradient + ';' +
        'display:flex;align-items:center;padding:0 12px;-webkit-app-region:drag;' +
        'border-bottom:1px solid ' + borderColor + ';';
      bar.innerHTML = '<span style="color:' + accentColor + ';font-size:12px;font-weight:600;letter-spacing:1px;">✦ Genshin × QoderWork</span>' +
        '<span style="margin-left:auto;display:flex;gap:8px;-webkit-app-region:no-drag;">' +
        '<span style="width:12px;height:12px;border-radius:50%;background:#88dac2;display:inline-block;" title="风"></span>' +
        '<span style="width:12px;height:12px;border-radius:50%;background:' + accentColor + ';display:inline-block;" title="冰"></span>' +
        '<span style="width:12px;height:12px;border-radius:50%;background:#b88ae8;display:inline-block;" title="雷"></span>' +
        '</span>';
      document.body.prepend(bar);

      return 'titlebar=1, dark=' + isDark;
    })();
  `;
  const r2 = await cdpEval(wsUrl, titlebarCode);
  log(`顶部标题栏: ${JSON.stringify(r2?.result?.value || r2)}`);

  // 第三步：注入侧边栏头像卡（含名片背景）
  const sideCardCode = `
    (function() {
      var SIDE_CARD_ID = '${SIDE_CARD_ID}';
      var avatarUri = '${avatarUri}';

      function buildSideCard() {
        var old = document.getElementById(SIDE_CARD_ID);
        if (old) old.remove();

        // 找侧边栏容器（QoderWork 用 Tailwind group/sidebar）
        var nav = document.querySelector('[class*="group/sidebar"]');
        if (!nav) return 'sidebar not found';

        var isDark = (document.documentElement.getAttribute('data-theme') || '').includes('dark');
        var textColor = isDark ? '#eef2f7' : '#2a3040';       // 冷白 / 深墨
        var subColor = isDark ? '#a0d8ee' : '#4aa8d0';        // 冰蓝副文字
        var borderColor = isDark ? '#2a5570' : '#a0d8ee';     // 冰蓝描边
        var cardBg = isDark
          ? 'linear-gradient(135deg,rgba(26,32,53,0.85),rgba(15,19,32,0.9))'
          : 'linear-gradient(135deg,rgba(240,248,253,0.92),rgba(220,236,247,0.95))';

        var card = document.createElement('div');
        card.id = SIDE_CARD_ID;
        card.setAttribute('data-genshin-inject', '1');
        card.style.cssText = 'position:relative;padding:12px 10px;margin:4px 8px 8px;border-radius:8px;overflow:hidden;' +
          'border:1px solid ' + borderColor + ';background:' + cardBg + ';backdrop-filter:blur(6px);';

        card.innerHTML =
          '<div style="display:flex;align-items:center;gap:8px;">' +
            '<div style="width:40px;height:40px;border-radius:8px;border:2px solid ' + borderColor + ';overflow:hidden;flex-shrink:0;background:' + (isDark ? '#1a2035' : '#f5f0e8') + ';">' +
            (avatarUri ? '<img src="' + avatarUri + '" style="width:100%;height:100%;object-fit:cover;" />' : '') +
            '</div>' +
            '<div>' +
              '<div style="font-size:12px;color:' + textColor + ';font-weight:600;">旅行者</div>' +
              '<div style="font-size:10px;color:' + subColor + ';margin-top:2px;">✦ 探索中...</div>' +
            '</div>' +
          '</div>';

        // 插入到第一个子元素（顶部拖拽区/留白）之后，而非 prepend
        if (nav.children.length > 1) {
          nav.insertBefore(card, nav.children[1]);
        } else {
          nav.prepend(card);
        }
        return 'sidebar card=1';
      }

      var result = buildSideCard();

      // MutationObserver 兜底 React 重渲染
      if (window.__qwGenshinObs) { window.__qwGenshinObs.disconnect(); }
      window.__qwGenshinObs = new MutationObserver(function() {
        if (!document.getElementById(SIDE_CARD_ID)) {
          requestAnimationFrame(function() { requestAnimationFrame(buildSideCard); });
        }
      });
      window.__qwGenshinObs.observe(document.body, { childList: true, subtree: true });

      return result + ', observer=active';
    })();
  `;
  const r3 = await cdpEval(wsUrl, sideCardCode);
  log(`侧边栏头像: ${JSON.stringify(r3?.result?.value || r3)}`);

  // 第四步：注入浮动派蒙（欢迎页公仔）
  const paimonCode = `
    (function() {
      var MASCOT_STAGE_ATTR = '${MASCOT_STAGE_ATTR}';
      var MASCOT_STYLE_ID = '${MASCOT_STYLE_ID}';
      var paimonUri = '${paimonUri}';

      // 注入动画样式
      var oldStyle = document.getElementById(MASCOT_STYLE_ID);
      if (oldStyle) oldStyle.remove();
      var style = document.createElement('style');
      style.id = MASCOT_STYLE_ID;
      style.textContent = '@keyframes paimon-float { 0%,100%{transform:translateY(0) rotate(0deg)} 25%{transform:translateY(-10px) rotate(3deg)} 50%{transform:translateY(0) rotate(0deg)} 75%{transform:translateY(10px) rotate(-3deg)} }';
      document.head.appendChild(style);

      function buildPaimon() {
        // 找 Rive hero 容器
        var hosts = document.querySelectorAll('div.size-12.relative');
        if (!hosts.length) return 'hosts=0';

        var built = 0;
        hosts.forEach(function(host) {
          if (host.querySelector('[' + MASCOT_STAGE_ATTR + ']')) return;
          var canvas = host.querySelector('canvas');
          if (canvas) canvas.style.opacity = '0';
          host.style.width = '96px';
          host.style.height = '96px';
          host.style.overflow = 'visible';

          var stage = document.createElement('div');
          stage.setAttribute(MASCOT_STAGE_ATTR, '1');
          stage.style.cssText = 'position:absolute;inset:0;display:flex;align-items:center;justify-content:center;pointer-events:none;';
          stage.innerHTML = paimonUri
            ? '<img src="' + paimonUri + '" style="width:80px;height:80px;object-fit:contain;animation:paimon-float 2.5s ease-in-out infinite;" />'
            : '<div style="width:80px;height:80px;border-radius:50%;background:#c6a855;animation:paimon-float 2.5s ease-in-out infinite;"></div>';
          host.appendChild(stage);
          built++;
        });

        return 'paimon mascot: hosts=' + hosts.length + ', built=' + built;
      }

      var result = buildPaimon();

      // MutationObserver 兜底
      if (window.__qwPaimonObs) { window.__qwPaimonObs.disconnect(); }
      window.__qwPaimonObs = new MutationObserver(function() {
        var hosts = document.querySelectorAll('div.size-12.relative');
        hosts.forEach(function(host) {
          if (!host.querySelector('[' + MASCOT_STAGE_ATTR + ']')) {
            requestAnimationFrame(function() { requestAnimationFrame(buildPaimon); });
          }
        });
      });
      window.__qwPaimonObs.observe(document.body, { childList: true, subtree: true });

      return result + ', observer=active';
    })();
  `;
  const r4 = await cdpEval(wsUrl, paimonCode);
  log(`浮动派蒙: ${JSON.stringify(r4?.result?.value || r4)}`);

  log('原神主题皮肤注入完成！');
}

// --- 入口 ---
(REMOVE ? remove() : main()).catch(err => {
  log(`错误: ${err.message}`);
  process.exit(1);
});
