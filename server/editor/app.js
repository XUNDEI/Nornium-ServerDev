/* 失乐星图 · 存档编辑器前端
 *
 * 设计语言：扁平 / 圆角 / 黑白（详见 style.css 顶部注释）。
 *
 * 数据流：GET 拉取档案 → 本地渲染；所有编辑先 stage() 进「待保存清单」
 * （右上角按钮 / 抽屉里可逐条撤销），点「保存修改」一次性
 * POST /editor/api/player/:id/update。在线玩家由服务端直接改内存并推 ntf，游戏内立刻生效。
 *
 * 代码分区：
 *   1. 状态与工具        2. 主题          3. API / Toast / 确认框
 *   4. 名称与等级换算    5. 待保存清单    6. 加载
 *   7. 侧栏与头部        8. 标签页与页面骨架
 *   9. 各页面渲染        10. 事件接线与启动
 */
'use strict';

// ═══════════════════════════ 1. 状态与工具 ═══════════════════════════

const S = {
  players: [],           // /accounts 列表
  catalog: null,         // /catalog（道具/武器/角色目录）
  id: null,              // 当前编辑的 account_id
  doc: null,             // 当前档案
  pending: [],           // 待保存操作
  tab: 'overview',
  saveTab: 'overview',   // 离开「存档管理」工作区前停在哪一页
  zone: 'save',          // 'save' 存档管理 | 'server' 服务器管理
  bagFilter: 'all',
  bagSearch: '',
  catalogCat: 'all',
  pickedItem: null,
  accountQuery: '',      // 侧栏存档搜索
  theme: 'light',
  drawerOpen: false,
  server: null,          // /server 信息
  stopped: false,        // 服务端已被本页停掉（停止轮询 + 显示遮罩）
  pollTimer: null,
  // 服务器控制台：SSE 句柄 + 日志游标 + 本地指令历史（↑/↓ 翻找）
  consoleEs: null,
  consoleSeq: 0,
  consoleAutoScroll: true,
  consoleHistory: [],
  consoleHistoryIdx: -1,
};

const $ = (sel) => document.querySelector(sel);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const fmt = (n) => Number(n || 0).toLocaleString('zh-CN');

// 单色描边图标（16px，颜色随 currentColor）。emoji 全部换成这里的矢量图。
const ICONS = {
  grid: '<path d="M3.5 3.5h7v7h-7zM13.5 3.5h7v7h-7zM13.5 13.5h7v7h-7zM3.5 13.5h7v7h-7z"/>',
  box: '<path d="M4 8h16v11a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1zM9 8V6a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2"/>',
  coin: '<path d="M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM12 16a4 4 0 1 0 0-8 4 4 0 0 0 0 8z"/>',
  flask: '<path d="M9 3h6M10 3v6L5 19a2 2 0 0 0 1.8 3h10.4A2 2 0 0 0 19 19l-5-10V3M7.5 15h9"/>',
  ticket: '<path d="M4 8a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v2a2 2 0 0 0 0 4v2a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-2a2 2 0 0 0 0-4zM13 6v12"/>',
  chart: '<path d="M4 19h16M7 19v-6M12 19v-9M17 19v-4"/>',
  brick: '<path d="M4 6h16v12H4zM4 12h16M12 6v6M8 12v6M16 12v6"/>',
  sofa: '<path d="M5 11V8a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v3M3 11h18v5a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2zM7 18v2M17 18v2"/>',
  weapon: '<path d="M4 20L20 4M20 4h-5.5M20 4v5.5M7.5 13.5l3 3M5 16l3 3"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  trash: '<path d="M4 7h16M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2M6 7l1 13h10l1-13M10 11v6M14 11v6"/>',
  undo: '<path d="M9 14L4 9l5-5M4 9h10a6 6 0 0 1 0 12h-3"/>',
  download: '<path d="M12 3v10m0 0-3.5-3.5M12 13l3.5-3.5M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2"/>',
  warning: '<path d="M12 3.5l9 16H3zM12 9.5v4.5M12 17.5h.01"/>',
  server: '<path d="M4 4h16v6H4zM4 14h16v6H4zM8 7h.01M8 17h.01"/>',
  users: '<path d="M16 20v-1a4 4 0 0 0-4-4H7a4 4 0 0 0-4 4v1M9.5 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7M17 4.6a3.5 3.5 0 0 1 0 6.8M21 20v-1a4 4 0 0 0-3-3.9"/>',
  dice: '<path d="M4 4h16v16H4zM8.5 8.5h.01M15.5 15.5h.01M12 12h.01"/>',
  cart: '<path d="M3 4h2l2.4 10.4a2 2 0 0 0 2 1.6h7.7a2 2 0 0 0 2-1.6L21 7H6M10 20h.01M18 20h.01"/>',
  book: '<path d="M4 5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2zM19 19H6"/>',
  save: '<path d="M5 3h11l3 3v15H5zM8 3v6h7V3M8 21v-6h8v6"/>',
  refresh: '<path d="M20.5 11a8.5 8.5 0 1 0-2.4 5.9M20.5 5v6h-6"/>',
  search: '<path d="M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16zM21 21l-4.3-4.3"/>',
  close: '<path d="M6 6l12 12M18 6L6 18"/>',
  check: '<path d="M20 6L9 17l-5-5"/>',
  help: '<path d="M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM9.6 9.5a2.5 2.5 0 1 1 3.4 2.3c-.6.3-1 .9-1 1.6v.2M12 17h.01"/>',
  power: '<path d="M12 3v9M6.5 6.5a8 8 0 1 0 11 0"/>',
  mark: '<path d="M6 19V5l12 14V5"/>',
  star: '<path d="M12 3.5l2.7 5.4 6 .9-4.3 4.2 1 5.9-5.4-2.8-5.4 2.8 1-5.9L3.3 9.8l6-.9z"/>',
  shirt: '<path d="M8.5 3.5L12 5.5l3.5-2L20 7l-2.8 3v10.5h-11V10L3.5 7zM8.5 3.5a3.5 3.5 0 0 0 7 0"/>',
  term: '<path d="M4 5h16v14H4zM7 9l3 3-3 3M12.5 15H17"/>',
  eraser: '<path d="M20 20H8L3.5 15.5a1.5 1.5 0 0 1 0-2.1l9-9a1.5 1.5 0 0 1 2.1 0l5 5a1.5 1.5 0 0 1 0 2.1L13 18M7 11.5l5.5 5.5"/>',
  send: '<path d="M4 12L20 4l-4 16-4.5-6.5L4 12zM11.5 13.5L20 4"/>',
};
const icon = (name, cls = '') => `<svg class="ic${cls ? ` ${cls}` : ''}" viewBox="0 0 24 24" aria-hidden="true">${ICONS[name] || ''}</svg>`;

const CURRENCIES = [
  { id: 9001, name: '金星贝' },
  { id: 9002, name: '诺伦炬' },
  { id: 9003, name: '败者翼膜' },
  { id: 9004, name: '游历经验' },
  { id: 9005, name: '抽卡银币' },
  { id: 9006, name: '抽卡金币' },
  { id: 9007, name: '诺伦透镜' },
  { id: 9008, name: '家具币' },
];
const WTYPE = ['', '巨刃', '长剑', '佩刀', '枪械', '礼器', '宝轮', '浮塔'];
const POOL_NAMES = { 1: '角色UP池', 2: '武器UP池', 3: '常驻池', 4: '新手池' };

// ═══════════════════════════ 2. 主题 ═══════════════════════════

// 浅色/深色都是纯黑白（见 style.css 的 token），选择记在 localStorage。
function applyTheme(mode) {
  S.theme = mode === 'dark' ? 'dark' : 'light';
  const root = document.documentElement;
  if (root && root.dataset) root.dataset.theme = S.theme;
  const btn = $('#themeBtn');
  if (btn) btn.title = S.theme === 'dark' ? '切换到浅色主题' : '切换到深色主题';
  try { localStorage.setItem('ghs-editor-theme', S.theme); } catch (_) { /* 隐私模式：忽略 */ }
}

function initTheme() {
  let saved = null;
  try { saved = localStorage.getItem('ghs-editor-theme'); } catch (_) { /* 忽略 */ }
  if (saved !== 'light' && saved !== 'dark') {
    const mq = typeof window !== 'undefined' && window && window.matchMedia
      ? window.matchMedia('(prefers-color-scheme: dark)') : null;
    saved = mq && mq.matches ? 'dark' : 'light';
  }
  applyTheme(saved);
}

// ═══════════════════════════ 3. API / Toast / 确认框 ═══════════════════════════

async function api(path, opts) {
  const res = await fetch(path, opts);
  const json = await res.json().catch(() => ({ code: 1, msg: '响应解析失败' }));
  if (json.code !== 0) throw new Error(json.msg || '请求失败');
  return json.data;
}

function toast(msg, type = 'ok') {
  const el = document.createElement('div');
  el.className = `toast ${type}`;
  el.textContent = msg;
  $('#toasts').appendChild(el);
  setTimeout(() => { el.style.opacity = '0'; el.style.transition = 'opacity .4s'; }, 3600);
  setTimeout(() => el.remove(), 4100);
}

// 通用确认弹窗（Promise<bool>）。危险操作要求把 confirmText 原样敲一遍，
// 服务端也会再校验一次同样的字符串（见 editorapi.js 的 restore）。
// 注意：确认框不走全局的 [data-close] 委托（那个只 hidden，不会 resolve，await 会永远挂着），
// 关闭按钮/遮罩/取消都用本函数自己的回调，并且退出时把遮罩上的监听摘掉（否则会累积）。
function askConfirm({ title, body, confirmText = '', okLabel = '确定', danger = false }) {
  return new Promise((resolve) => {
    const need = confirmText;
    const modal = $('#confirmModal');
    $('#confirmModalBody').innerHTML = `
      <div class="modal-head"><h3>${danger ? icon('warning') : ''}${esc(title)}</h3>
        <button class="icon-btn" id="cfClose" title="关闭">${icon('close')}</button></div>
      <div class="modal-body">${body}</div>
      ${need ? `<div class="field" style="margin-top:2px">
          <label>请输入 <b>${esc(need)}</b> 以确认</label>
          <input type="text" id="cfText" placeholder="${esc(need)}" autocomplete="off">
        </div>` : ''}
      <div class="modal-foot">
        <button class="btn" id="cfCancel">取消</button>
        <button class="btn ${danger ? 'danger' : 'primary'}" id="cfOk"${need ? ' disabled' : ''}>${esc(okLabel)}</button>
      </div>`;
    modal.hidden = false;
    const input = $('#cfText');
    const okBtn = $('#cfOk');
    let settled = false;
    const done = (v) => {
      if (settled) return;
      settled = true;
      modal.hidden = true;
      modal.removeEventListener('click', onMaskClick);
      resolve(v);
    };
    const onMaskClick = (e) => { if (e.target === modal) done(false); };
    const refresh = () => { if (need) okBtn.disabled = !input || input.value.trim() !== need; };
    refresh();
    if (input) {
      input.addEventListener('input', refresh);
      input.addEventListener('keydown', (e) => { if (e.key === 'Enter' && !okBtn.disabled) done(true); });
      input.focus();
    }
    okBtn.addEventListener('click', () => { if (!okBtn.disabled) done(true); });
    $('#cfCancel').addEventListener('click', () => done(false));
    $('#cfClose').addEventListener('click', () => done(false));
    modal.addEventListener('click', onMaskClick);
  });
}

// ═══════════════════════════ 4. 名称与等级换算 ═══════════════════════════

const catItem = (id) => S.catalog?.items.find((x) => x.id === Number(id));
const catWeapon = (id) => S.catalog?.weapons.find((x) => x.id === Number(id));
const catChar = (id) => S.catalog?.characters.find((x) => x.id === Number(id));

function itemName(id) {
  const c = catItem(id) || catWeapon(id) || (S.catalog?.furniture || []).find((x) => x.id === Number(id));
  return c ? c.name : `道具 #${id}`;
}
function itemRarity(id) {
  const c = catItem(id) || catWeapon(id) || (S.catalog?.furniture || []).find((x) => x.id === Number(id));
  return c ? c.rarity || 0 : 0;
}
const charName = (id) => catChar(id)?.name || `角色 #${id}`;
const itemByUuid = (uuid) => (S.doc?.bag?.items || []).find((x) => Number(x.item_uuid) === Number(uuid));

// 表由 /catalog 的 leveling 块下发（见 editorapi.js 的 levelingTables）：
//   expArr[i]（0 起）= d_*_level 里 id=i+1 那一行 = 从 i+1 级升到 i+2 级所需经验。
// 与客户端 UIUtils.GetCharacterLevel / GetWeaponLevel 同语义。

function expForLevel(expArr, level) {
  if (!expArr) return 0;
  let sum = 0;
  for (let i = 0; i < level - 1 && i < expArr.length; i += 1) sum += expArr[i] || 0;
  return sum;
}

function levelForExp(expArr, exp) {
  if (!expArr) return 1;
  let level = 1;
  let left = Number(exp) || 0;
  for (let i = 0; i < expArr.length; i += 1) {
    if (left < (expArr[i] || 0)) break;
    left -= expArr[i] || 0;
    level += 1;
  }
  return level;
}

const levelCaps = () => S.catalog?.leveling?.caps || [20, 40, 50, 60, 70, 80];
const maxBreak = () => S.catalog?.leveling?.max_break ?? 5;
const capForBreak = (bt) => {
  const caps = levelCaps();
  return caps[Math.min(Math.max(0, Number(bt) || 0), caps.length - 1)] || 20;
};
const roleExpArr = () => S.catalog?.leveling?.role_exp;
const weaponExpArr = (itemId) => {
  const rarity = catWeapon(itemId)?.rarity || 1;
  const t = S.catalog?.leveling?.weapon_exp || {};
  return t[rarity] || t[String(rarity)] || t[1];
};

// ═══════════════════════════ 5. 待保存清单 ═══════════════════════════

// 同一目标的多字段编辑要**合并**而不是互相顶掉：set_weapon_stats 一次只带一个字段，
// 玩家先改光淬再改等级时，后者不能把前者丢掉（旧版 edit_character 的重复 op 就是这个坑）。
// level / exp 互斥：新写入的那个会把另一个删掉，避免合并后「谁赢」变得不可预测。
const MERGE_OPS = new Set(['set_weapon_stats']);

function pendingKey(op) {
  return JSON.stringify([op.op, op.item_id ?? op.item_uuid ?? op.character_id ?? op.pool_type ?? '', op.name ?? '']);
}

function mergeOp(prev, op) {
  const merged = { ...prev, ...op };
  if (Object.prototype.hasOwnProperty.call(op, 'level')) delete merged.exp;
  if (Object.prototype.hasOwnProperty.call(op, 'exp')) delete merged.level;
  return merged;
}

function stage(op) {
  // 同一目标的重复编辑直接替换（比如把货币 9001 先改 100 再改 200，只提交最后那次）
  const key = pendingKey(op);
  const i = S.pending.findIndex((p) => pendingKey(p) === key);
  if (i >= 0 && !['add_item', 'send_mail'].includes(op.op)) {
    S.pending[i] = MERGE_OPS.has(op.op) ? mergeOp(S.pending[i], op) : op;
  } else {
    S.pending.push(op);
  }
  renderPending();
}

function stageAddItem(itemId, count) {
  const i = S.pending.findIndex((p) => p.op === 'add_item' && p.item_id === itemId);
  if (i >= 0) S.pending[i].count += count;
  else S.pending.push({ op: 'add_item', item_id: itemId, count });
  renderPending();
}

// 待保存项 → 人话（抽屉里逐条展示，方便确认自己改了什么）
function describeOp(op) {
  const it = op.item_uuid != null ? itemByUuid(op.item_uuid) : null;
  const wname = it ? itemName(it.item_id) : (op.item_uuid != null ? `uuid ${op.item_uuid}` : '');
  switch (op.op) {
    case 'set_player_name': return { title: '玩家昵称', sub: `→ ${op.name}` };
    case 'set_currency': return { title: `货币 · ${itemName(op.item_id)}`, sub: `→ ${fmt(op.count)}` };
    case 'set_item_count': return { title: `数量 · ${wname}`, sub: `→ ${fmt(op.count)}` };
    case 'remove_item': return { title: `删除道具 · ${wname}`, sub: `uuid ${op.item_uuid}` };
    case 'add_item': return { title: `添加道具 · ${itemName(op.item_id)}`, sub: `× ${fmt(op.count)}` };
    case 'set_weapon_stats': {
      const parts = [];
      if (op.level != null) parts.push(`等级 → ${op.level}`);
      if (op.exp != null) parts.push(`经验 → ${fmt(op.exp)}`);
      if (op.break_times != null) parts.push(`突破 → ${op.break_times}`);
      if (op.refine_level != null) parts.push(`光淬 → ${op.refine_level}`);
      return { title: `武器练度 · ${wname}`, sub: parts.join(' · ') || '（无字段变化）' };
    }
    case 'set_character_level':
      return { title: `角色等级 · ${charName(op.character_id)}`, sub: `Lv.${op.level}${op.break_times != null ? ` · 突破 ${op.break_times}` : ''}` };
    case 'edit_character':
      return { title: `角色经验 · ${charName(op.character_id)}`, sub: `→ ${fmt(op.exp)}${op.break_times != null ? ` · 突破 ${op.break_times}` : ''}` };
    case 'add_character': return { title: `添加角色 · ${charName(op.character_id)}`, sub: '自带初始武器与技能' };
    case 'add_all_characters': return { title: '添加全部角色', sub: '数据表里全部可玩角色' };
    case 'grant_high_rarity_weapons':
      return { title: '发放高稀有度武器', sub: `已实装的 6★/7★ 每种各一把${op.skip_owned ? ' · 跳过已拥有' : ''}` };
    case 'set_gacha_pity':
      return { title: `抽卡保底 · ${POOL_NAMES[op.pool_type] || `池 ${op.pool_type}`}`, sub: `no_up_times → ${fmt(op.no_up_times)}` };
    case 'grant_constellation': {
      const nail = charInborn(op.character_id);
      return {
        title: `发放命座 · ${charName(op.character_id)}`,
        sub: `星位之钉 ${nail ? itemName(nail) : ''}（${nail}）× ${fmt(op.count ?? 1)}`,
      };
    }
    case 'grant_all_constellations':
      return { title: '发放全部角色命座', sub: `每个角色星位之钉 × ${fmt(op.count ?? 1)}` };
    case 'unlock_all_talents':
      return {
        title: '点亮星位',
        sub: op.character_id ? `${charName(op.character_id)} · 全部星位` : '全部已拥有角色 · 全部星位',
      };
    case 'unlock_all_skins':
      return {
        title: '解锁皮肤',
        sub: op.character_id ? `${charName(op.character_id)} · 全部皮肤` : '全部已拥有角色 · 全部皮肤',
      };
    case 'set_charge_point': return { title: '累充积分', sub: `→ ${fmt(op.value)}` };
    case 'set_month_card': return { title: '月卡', sub: op.days ? `延长 ${op.days} 天` : '清空月卡' };
    case 'send_mail': return { title: '发送邮件', sub: op.title || '（自定义邮件）' };
    default: return { title: op.op, sub: JSON.stringify(op) };
  }
}

function renderPending() {
  const n = S.pending.length;
  $('#pendingCount').textContent = n;
  const dc = $('#drawerCount');
  if (dc) dc.textContent = n;
  $('#saveBtn').disabled = n === 0;
  $('#saveBtn').classList.toggle('pulse', n > 0);

  const list = $('#pendingList');
  if (list) {
    list.innerHTML = n
      ? S.pending.map((op, i) => {
        const d = describeOp(op);
        return `<div class="pending-row">
            <div class="pending-main">
              <div class="pending-title">${esc(d.title)}</div>
              <div class="pending-sub">${esc(d.sub)}</div>
            </div>
            <button class="icon-btn" data-undo="${i}" title="撤销这一条">${icon('undo')}</button>
          </div>`;
      }).join('')
      : '<div class="placeholder">还没有待保存的修改。<br>在任意页面改动后会自动出现在这里。</div>';
    list.querySelectorAll('[data-undo]').forEach((b) => b.addEventListener('click', () => {
      S.pending.splice(Number(b.dataset.undo), 1);
      renderPending();
      toast('已撤销 1 项');
    }));
  }
  if (n === 0 && S.drawerOpen) closeDrawer();
}

function clearPending() {
  if (!S.pending.length) return;
  S.pending = [];
  renderPending();
  toast('已清空待保存清单');
}

async function savePending() {
  if (!S.pending.length) return;
  const btn = $('#saveBtn');
  btn.disabled = true;
  try {
    const data = await api(`/editor/api/player/${S.id}/update`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ops: S.pending }),
    });
    for (const n of data.notes) if (n) toast(n, 'ok');
    if (data.error) toast(`部分操作未生效：${data.error}`, 'err');
    else toast(data.live ? '已保存，游戏内即时生效' : '已保存，玩家重新登录后生效', 'ok');
    if (data.relog_note) toast(data.relog_note);
    S.pending = [];
    renderPending();
    await loadDoc(S.id, false);
  } catch (err) {
    toast(err.message, 'err');
  } finally {
    renderPending();
  }
}

function openDrawer() {
  S.drawerOpen = true;
  $('#pendingDrawer').hidden = false;
  const mask = $('#drawerMask');
  if (mask) mask.hidden = false;
}

function closeDrawer() {
  S.drawerOpen = false;
  $('#pendingDrawer').hidden = true;
  const mask = $('#drawerMask');
  if (mask) mask.hidden = true;
}

// ═══════════════════════════ 6. 加载 ═══════════════════════════

async function loadAccounts() {
  try {
    const data = await api('/editor/api/accounts');
    S.players = data.players;
    renderAccounts();
  } catch (err) { toast(err.message, 'err'); }
}

// 左下角指示灯：绿 = 这一页能连上服务端，红 = 连不上/已停服（不要用「黑点」——
// 深色主题下它和白点几乎分不出，浅色主题下更像一个装饰）。
function setServerDot(state) {
  const dot = $('#serverDot');
  if (!dot) return;
  dot.classList.toggle('on', state === 'on');
  dot.classList.toggle('off', state !== 'on');
}

async function loadServer() {
  if (S.stopped) return;
  try {
    const d = await api('/editor/api/server');
    S.server = d;
    setServerDot('on');
    $('#serverStatus').textContent = `服务端运行中 · 在线 ${d.online}`;
    $('#serverMeta').innerHTML = `${d.stats.accounts} 个账号 · ${d.stats.players} 个档案`;
  } catch (_) {
    S.server = null;
    $('#serverStatus').textContent = '无法连接服务端';
    setServerDot('off');
  }
  // 轮询会让「服务器管理」页与主页（未选存档时优先显示服务器状态）一起刷新。
  if (S.tab === 'server') {
    // 30s 轮询会重绘服务页：别把用户正在输入的备份路径冲掉
    const typed = $('#srvLoadPath') ? $('#srvLoadPath').value : '';
    renderTab();
    if (typed && $('#srvLoadPath')) $('#srvLoadPath').value = typed;
  } else if (!S.doc) {
    renderTab();
  }
}

// 服务端被本页停掉之后：停掉轮询、盖一层遮罩，避免每 30s 刷一串失败请求。
function markStopped() {
  S.stopped = true;
  S.server = null;
  if (S.pollTimer) { clearInterval(S.pollTimer); S.pollTimer = null; }
  closeConsoleStream();
  setServerDot('off');
  $('#serverStatus').textContent = '服务端已停止';
  $('#stoppedMask').hidden = false;
}

async function loadCatalog() {
  if (S.catalog) return;
  S.catalog = await api('/editor/api/catalog');
}

async function loadDoc(id, switchTab = true) {
  const data = await api(`/editor/api/player/${id}`);
  S.doc = data.doc;
  S.id = id;
  if (switchTab) setTab(S.tab);
  renderAccounts();
  renderHeader();
  renderTab();
}

// ═══════════════════════════ 7. 侧栏与头部 ═══════════════════════════

function renderAccounts() {
  const box = $('#accountList');
  const count = $('#accountCount');
  if (count) count.textContent = S.players.length;
  const q = S.accountQuery.trim().toLowerCase();
  const rows = S.players.filter((p) => !q
    || String(p.player_name || '').toLowerCase().includes(q)
    || String(p.account_name || '').toLowerCase().includes(q));
  if (!S.players.length) { box.innerHTML = '<div class="placeholder">还没有任何存档</div>'; return; }
  if (!rows.length) { box.innerHTML = '<div class="placeholder">没有匹配的存档</div>'; return; }
  box.innerHTML = rows.map((p) => `
    <button class="account ${p.account_id === S.id ? 'active' : ''}" data-id="${p.account_id}">
      <div class="a-name">${esc(p.player_name)} ${p.online ? '<span class="badge online">在线</span>' : ''}</div>
      <div class="a-sub"><span>${esc(p.account_name)}</span><span>角色 ${p.characters}</span><span>背包 ${p.bag_items}</span></div>
    </button>`).join('');
  box.querySelectorAll('.account').forEach((el) => el.addEventListener('click', () => selectPlayer(Number(el.dataset.id))));
}

async function selectPlayer(id) {
  if (id === S.id) return;
  // 有未保存修改时不允许直接切档：避免改动被静默丢弃（要放弃请在「待保存」抽屉里点「清空」）。
  if (S.pending.length) {
    toast(`还有 ${S.pending.length} 项未保存的修改：请先点「保存修改」，或在「待保存」抽屉里清空`, 'err');
    openDrawer();
    return;
  }
  if (!S.catalog) await loadCatalog().catch(() => {});
  try { await loadDoc(id); } catch (err) { toast(err.message, 'err'); }
}

function renderHeader() {
  if (S.zone === 'server') {
    // 「服务器管理」区与存档无关：标题与徽标改成服务端口径，不给「档案 N」这种误导信息。
    $('#playerName').textContent = '服务器管理';
    const d = S.server;
    $('#playerBadges').innerHTML = d
      ? `<span class="badge online">服务端运行中 · 在线 ${d.online}</span>
         <span class="badge">${d.stats.accounts} 个账号 · ${d.stats.players} 个档案</span>
         <span class="badge">v${esc(d.version)}</span>`
      : '<span class="badge">连不上服务端</span>';
    $('#tabs').hidden = false;
    return;
  }
  const p = S.players.find((x) => x.account_id === S.id);
  $('#playerName').textContent = S.doc?.player?.player_name || `档案 ${S.id}`;
  $('#playerBadges').innerHTML = p ? `
    <span class="badge ${p.online ? 'online' : ''}">${p.online ? '在线 · 修改即时生效' : '离线 · 保存后需重新登录'}</span>
    <span class="badge">账号 ${esc(p.account_name)}</span>
    <span class="badge">ID ${p.account_id}</span>` : '';
  $('#tabs').hidden = false;
}

// ═══════════════════════════ 8. 标签页与页面骨架 ═══════════════════════════

// 每个标签页都带一句「这一页能做什么」，让功能边界一眼可见。
const TABS = {
  overview: { label: '总览', desc: '改玩家昵称与八种货币的数量；改动先进待保存清单，点右上角保存才生效。' },
  bag: { label: '背包', desc: '按分类筛选或搜索道具，改数量、删除、从目录添加；武器还能直接改等级 / 突破 / 光淬。' },
  chars: { label: '角色', desc: '编辑已拥有角色的等级与武器练度，发放角色与高稀有度武器，发放星位之钉（命座）或直接点亮星位。' },
  gacha: { label: '抽卡', desc: '调整各卡池的保底计数（no_up_times = 距上次 UP 六星的累计抽数）。' },
  mall: { label: '商城', desc: '改累充积分与月卡有效期；积分够即可在游戏内领取对应累充档位。' },
  plot: { label: '剧情', desc: '只读查看主线进度与进行中的任务；直接改任务链容易把主线改死，所以不提供编辑。' },
  backup: { label: '备份', desc: '把当前存档导出到指定目录，并查看历史上自动留下的快照。' },
  server: { label: '服务器管理', desc: '服务端状态与运维操作（备份 / 踢人 / 导入 / 清档 / 停服）；这一区不需要先选中存档。' },
  console: { label: '服务器控制台', desc: '实时显示服务端输出，也可以直接执行控制台指令（help 看列表）；清档等危险操作会先要求确认。' },
};

// 工作区切换：'save' 存档管理 | 'server' 服务器管理。
// 两个功能区只在同一个页面里换视图（共用 API、样式与轮询），不是两个割裂的前端。
function setZone(zone) {
  const next = zone === 'server' ? 'server' : 'save';
  if (next === 'server' && S.tab !== 'server') S.saveTab = S.tab;
  S.zone = next;
  document.querySelectorAll('#zoneSwitch .zone-btn').forEach((b) => {
    const on = b.dataset.zone === next;
    b.classList.toggle('active', on);
    b.setAttribute('aria-selected', on ? 'true' : 'false');
  });
  $('#accountsBlock').hidden = next === 'server';
  $('#navSave').hidden = next === 'server';
  $('#navServer').hidden = next !== 'server';
  renderHeader();
  setTab(next === 'server' ? 'server' : (S.saveTab || 'overview'));
}

function setTab(tab) {
  S.tab = tab;
  if (tab !== 'server') S.saveTab = tab;
  document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === tab));
  renderTab();
}

function pageHeadHtml(tab) {
  const def = TABS[tab] || { label: '', desc: '' };
  return `<div class="page-head">
      <div>
        <h2>${esc(def.label)}</h2>
        <p>${esc(def.desc)}</p>
      </div>
    </div>`;
}

// 所有页面共用的骨架：把「标题 + 说明」和正文塞进同一个 wrapper，
// 这样 #content 的子元素 innerHTML 里既有说明也有内容（编辑器前端回归测试依赖这一点）。
function pageEl(el, tab, bodyHtml) {
  const wrap = document.createElement('div');
  wrap.className = 'page';
  wrap.innerHTML = pageHeadHtml(tab) + bodyHtml;
  el.appendChild(wrap);
  return wrap;
}

// 服务器状态卡片（主页优先显示的东西）。S.server 为空 = 连不上服务端。
function serverOverviewHtml() {
  const d = S.server;
  if (!d) {
    return `<div class="card error-card">
      <div class="card-head"><h3>${icon('warning')} 服务器状态</h3>
        <span class="status-line"><span class="dot off"></span>连不上</span></div>
      <p class="hint-line">服务端可能已经停止，或本页不是由它提供的。重新启动请双击仓库根目录的
        <b>点我启动.bat</b>（或在 <code>server\\</code> 下 <code>node index.js</code>）。</p>
      <div class="actions" style="margin-top:14px">
        <button class="btn" id="homeRecheck">${icon('refresh')} 重新检测</button>
        <button class="btn ghost" id="homeToServer">${icon('server')} 打开服务器管理</button>
      </div>
    </div>`;
  }
  return `<div class="card">
      <div class="card-head"><h3>服务器状态</h3>
        <span class="status-line"><span class="dot on"></span>运行中 · v${esc(d.version)}</span></div>
      <div class="grid stats">
        <div class="stat"><div class="k">在线连接</div><div class="v">${d.online}</div></div>
        <div class="stat"><div class="k">运行时长</div><div class="v">${fmtUptime(d.uptime_seconds)}</div></div>
        <div class="stat"><div class="k">账号 / 档案</div><div class="v">${d.stats.accounts} / ${d.stats.players}</div></div>
        <div class="stat"><div class="k">端口（TCP 游戏 / HTTP 门）</div><div class="v">${d.tcp_port ?? '?'} / ${d.http_port ?? '?'}</div></div>
        <div class="stat"><div class="k">历史快照</div><div class="v">${d.backups}</div></div>
        <div class="stat"><div class="k">存档目录</div><div class="v small">${esc(d.data_dir)}</div></div>
      </div>
      <div class="actions" style="margin-top:14px">
        <button class="btn ghost" id="homeToServer">${icon('server')} 打开服务器管理</button>
      </div>
    </div>`;
}

// 未选存档时的引导（排在服务器状态卡片下面）。
function guideHtml() {
  return `<div class="empty">
      <div class="empty-mark">${icon('mark', 'lg')}</div>
      <h2>再从左侧选一个存档</h2>
      <p>三步就能改完一个存档，全程不需要重启服务端。</p>
      <div class="steps">
        <div class="step"><span class="n">1</span><div><div class="t">在左栏点一个玩家存档</div>
          <div class="d">列表来自 <code>server\\data\\players\\</code>，带「在线」标记的玩家改完即时生效。</div></div></div>
        <div class="step"><span class="n">2</span><div><div class="t">在「存档管理」里选一页改</div>
          <div class="d">总览改货币、背包改道具、角色改等级/武器/星位；每一页顶部都写了这一页能做什么。</div></div></div>
        <div class="step"><span class="n">3</span><div><div class="t">点右上角「保存修改」写入</div>
          <div class="d">改动会先进「待保存」清单，可以逐条撤销；在线玩家立刻生效，离线玩家重登后生效。</div></div></div>
      </div>
      <p class="empty-note">只想停服、备份或清档？点左栏顶部的「服务器管理」，不需要选中存档。</p>
    </div>`;
}

// 主页 = 服务器状态优先，其次才是选档引导。
function homeHtml() {
  return `<div class="page">${serverOverviewHtml()}${guideHtml()}</div>`;
}

function wireHome(wrap) {
  const recheck = wrap.querySelector('#homeRecheck');
  if (recheck) recheck.addEventListener('click', async () => {
    S.stopped = false;
    $('#stoppedMask').hidden = true;
    await Promise.all([loadServer(), loadAccounts()]);
    renderTab();
  });
  wrap.querySelectorAll('#homeToServer').forEach((b) => b.addEventListener('click', () => setZone('server')));
}

function renderTab() {
  const el = $('#content');
  // 离开控制台页时断开 SSE（每次重绘也会重建连接，避免旧流继续往死节点里写）
  if (S.tab !== 'console') closeConsoleStream();
  // 主页（未选存档）= 服务器状态优先；控制台与「服务器管理」一样不依赖存档。
  if (!S.doc && S.tab !== 'server' && S.tab !== 'console') {
    el.innerHTML = '';
    const wrap = document.createElement('div');
    wrap.innerHTML = homeHtml();
    el.appendChild(wrap);
    wireHome(wrap);
    el.scrollTop = 0;
    return;
  }
  const render = {
    overview: renderOverview, bag: renderBag, chars: renderChars, gacha: renderGacha,
    mall: renderMall, plot: renderPlot, backup: renderBackup, server: renderServer,
    console: renderConsole,
  }[S.tab];
  el.innerHTML = '';
  // 服务页是 async（要拉快照列表）；渲染期的异常不要变成 unhandled rejection
  const ret = render(el);
  if (ret && typeof ret.catch === 'function') ret.catch((err) => toast(`页面渲染失败：${err.message}`, 'err'));
  el.scrollTop = 0;
}

// 判断某个待保存项是否命中（用来给字段/行打「已修改」标记）
const hasPending = (pred) => S.pending.some(pred);

// ═══════════════════════════ 9. 各页面渲染 ═══════════════════════════

// ══════════ 总览 ══════════

function renderOverview(el) {
  const doc = S.doc;
  const nameDirty = hasPending((p) => p.op === 'set_player_name');
  const wrap = pageEl(el, 'overview', `
    <div class="card">
      <div class="card-head"><h3>玩家信息</h3><span class="hint">昵称改动需保存后生效</span></div>
      <div class="row">
        <div class="field grow ${nameDirty ? 'dirty' : ''}"><label>玩家昵称</label>
          <input type="text" id="playerNameInput" value="${esc(doc.player.player_name)}" maxlength="20"></div>
        <button class="btn" id="renameBtn">改名</button>
      </div>
      <p class="hint-line">注册时间：${new Date(Number(doc.player.register_seconds) * 1000).toLocaleString('zh-CN')}
        · 账号 ID ${S.id}</p>
    </div>
    <div class="card">
      <div class="card-head"><h3>货币</h3><span class="hint">直接改数字，保存后生效</span></div>
      <div class="grid cur">
        ${CURRENCIES.map((c) => {
          const cur = doc.bag.items.find((it) => it.item_id === c.id);
          const dirty = hasPending((p) => p.op === 'set_currency' && p.item_id === c.id);
          return `<div class="field ${dirty ? 'dirty' : ''}"><label>${icon('coin')} ${c.name} <span class="dim">(${c.id})</span></label>
            <input type="number" min="0" data-currency="${c.id}" value="${cur ? cur.count : 0}"></div>`;
        }).join('')}
      </div>
    </div>`);

  $('#renameBtn').addEventListener('click', () => {
    const name = $('#playerNameInput').value.trim();
    if (!name) return toast('昵称不能为空', 'err');
    stage({ op: 'set_player_name', name });
    toast('已加入待保存清单');
  });
  wrap.querySelectorAll('input[data-currency]').forEach((inp) => {
    inp.addEventListener('change', () => {
      const v = Math.max(0, Math.trunc(Number(inp.value) || 0));
      inp.value = v;
      stage({ op: 'set_currency', item_id: Number(inp.dataset.currency), count: v });
      toast('已加入待保存清单');
    });
  });
}

// ══════════ 背包 ══════════

const BAG_CATS = [
  ['all', '全部'], ['cur', '货币'], ['mat', '材料'], ['exp', '经验材料'], ['break', '突破材料'],
  ['ticket', '抽卡券'], ['use', '消耗品'], ['skin', '皮肤'], ['furn', '家具'], ['weapon', '武器'],
];
const MATERIAL_SUBTYPE = { 2: '材料', 3: '角色经验', 4: '武器经验', 5: '装备经验', 6: '角色卡', 7: '消耗品', 8: '蓝图', 9: '锻造蓝图' };
const TICKETS = [1200001, 1200002, 1201001, 1201003];
const BAG_ICON = { cur: 'coin', exp: 'chart', break: 'brick', ticket: 'ticket', use: 'flask', skin: 'shirt', furn: 'sofa', weapon: 'weapon', mat: 'box' };

function bagCatOf(entry) {
  if (catWeapon(entry.item_id)) return 'weapon'; // 武器不在 d_bag_item 表里，先查武器表
  const info = catItem(entry.item_id) || {};
  if (info.item_type === 90) return 'cur';
  if (TICKETS.includes(Number(entry.item_id))) return 'ticket';
  if (info.item_type === 92) return 'skin'; // 皮肤卡（40xxxxx/50xxxxx）
  if (info.item_type === 12) {
    const st = Number(info.sub_type);
    if (st === 3 || st === 4 || st === 5) return 'exp';
    if (st === 1) return 'break'; // 1202xxx 突破材料 subType=1
    return 'mat';
  }
  if (info.item_type === 20) return 'use';
  if (info.item_type === 93) return 'furn';
  if (info.item_type === 10) return 'weapon';
  return 'mat';
}

function renderBag(el) {
  const wrap = pageEl(el, 'bag', `
    <div class="toolbar">
      <input class="search" id="bagSearch" type="search" placeholder="搜索背包道具…" value="${esc(S.bagSearch)}" autocomplete="off">
      <div class="seg">${BAG_CATS.map(([v, n]) => `<button class="seg-btn ${S.bagFilter === v ? 'active' : ''}" data-cat="${v}">${n}</button>`).join('')}</div>
      <span class="spacer"></span>
      <button class="btn primary" id="addItemBtn">${icon('plus')} 添加道具</button>
    </div>
    <div class="list" id="bagList"></div>`);

  const renderList = () => {
    const q = S.bagSearch.trim().toLowerCase();
    const rows = S.doc.bag.items
      .map((it) => ({ it, cat: bagCatOf(it) }))
      .filter((r) => S.bagFilter === 'all' || r.cat === S.bagFilter)
      .filter((r) => !q || itemName(r.it.item_id).toLowerCase().includes(q) || String(r.it.item_id).includes(q))
      .sort((a, b) => (catItem(a.it.item_id)?.item_type || 0) - (catItem(b.it.item_id)?.item_type || 0) || a.it.item_id - b.it.item_id);
    $('#bagList').innerHTML = rows.length ? rows.map(({ it, cat }) => {
      const dirty = hasPending((p) => Number(p.item_uuid) === Number(it.item_uuid));
      const wcfg = cat === 'weapon' ? catWeapon(it.item_id) : null;
      if (wcfg && it.weapon_info) {
        // 武器：等级/突破/光淬都能直接改（背包里躺着的也行，不只是身上那把）
        const wi = it.weapon_info;
        const bt = Math.max(0, Math.trunc(Number(wi.break_times) || 0));
        const cap = capForBreak(bt);
        const lv = Math.min(cap, levelForExp(weaponExpArr(it.item_id), wi.exp));
        const maxR = wcfg.max_refine ?? 4;
        return `<div class="list-row ${dirty ? 'dirty' : ''}">
          <div class="row-icon">${icon('weapon')}</div>
          <div class="row-main">
            <div class="row-title"><span class="rarity r${wcfg.rarity}">${wcfg.rarity}★</span> ${esc(itemName(it.item_id))}
              ${wcfg.released === false ? `<span class="tag warn">${icon('warning')} 未实装</span>` : ''}</div>
            <div class="row-sub">ID ${it.item_id} · ${WTYPE[wcfg.sub_type] || ''} 武器 · uuid ${it.item_uuid} · 经验 ${fmt(wi.exp)}</div>
          </div>
          <div class="row-fields">
            <label>光淬<input type="number" min="0" max="${maxR}" data-refine="${it.item_uuid}" value="${wi.refine_level || 0}"></label>
            <label>等级<input type="number" min="1" max="${cap}" data-wlevel="${it.item_uuid}" value="${lv}"></label>
            <label>突破<input type="number" min="0" max="${maxBreak()}" data-wbreak="${it.item_uuid}" value="${bt}"></label>
            <span class="cap">上限 Lv.${cap}</span>
          </div>
          <button class="btn ghost small" data-del="${it.item_uuid}">${icon('trash')} 删除</button>
        </div>`;
      }
      const sub = MATERIAL_SUBTYPE[Number(catItem(it.item_id)?.sub_type)] || `类型 ${catItem(it.item_id)?.item_type ?? '?'}`;
      return `<div class="list-row ${dirty ? 'dirty' : ''}">
        <div class="row-icon">${icon(BAG_ICON[cat] || 'box')}</div>
        <div class="row-main">
          <div class="row-title"><span class="rarity r${itemRarity(it.item_id)}">${itemRarity(it.item_id)}★</span> ${esc(itemName(it.item_id))}</div>
          <div class="row-sub">ID ${it.item_id} · ${sub} · uuid ${it.item_uuid}</div>
        </div>
        <input class="count" type="number" min="0" data-uuid="${it.item_uuid}" value="${it.count}">
        <button class="btn ghost small" data-del="${it.item_uuid}">${icon('trash')} 删除</button>
      </div>`;
    }).join('') : '<div class="placeholder">没有匹配的道具</div>';

    $('#bagList').querySelectorAll('input.count').forEach((inp) => {
      inp.addEventListener('change', () => {
        const v = Math.max(0, Math.trunc(Number(inp.value) || 0));
        inp.value = v;
        stage({ op: 'set_item_count', item_uuid: Number(inp.dataset.uuid), count: v });
        toast('已加入待保存清单');
      });
    });
    // 武器练度：改哪个字段就 stage 哪个（stage 会把同一把武器的多次编辑合并起来）
    const wireWeaponInput = (attr, key, transform) => {
      $('#bagList').querySelectorAll(`input[data-${attr}]`).forEach((inp) => {
        inp.addEventListener('change', () => {
          const v = transform(inp.value);
          inp.value = v;
          stage({ op: 'set_weapon_stats', item_uuid: Number(inp.dataset[attr]), [key]: v });
          toast('已加入待保存清单');
        });
      });
    };
    wireWeaponInput('refine', 'refine_level', (v) => Math.max(0, Math.trunc(Number(v) || 0)));
    wireWeaponInput('wlevel', 'level', (v) => Math.max(1, Math.trunc(Number(v) || 1)));
    wireWeaponInput('wbreak', 'break_times', (v) => Math.min(maxBreak(), Math.max(0, Math.trunc(Number(v) || 0))));
    $('#bagList').querySelectorAll('[data-del]').forEach((btn) => {
      btn.addEventListener('click', () => {
        stage({ op: 'remove_item', item_uuid: Number(btn.dataset.del) });
        toast('已加入待保存清单（删除）');
      });
    });
  };
  renderList();

  $('#bagSearch').addEventListener('input', (e) => { S.bagSearch = e.target.value; renderList(); });
  wrap.querySelectorAll('.seg-btn').forEach((ch) => ch.addEventListener('click', () => {
    S.bagFilter = ch.dataset.cat;
    wrap.querySelectorAll('.seg-btn').forEach((c) => c.classList.toggle('active', c === ch));
    renderList();
  }));
  $('#addItemBtn').addEventListener('click', openItemModal);
}

// ══════════ 添加道具弹窗 ══════════

const CATALOG_CATS = [['all', '全部'], ['cur', '货币'], ['mat', '材料'], ['use', '消耗品'], ['skin', '皮肤'], ['furn', '家具'], ['weapon', '武器']];

function catalogRows() {
  const rows = [];
  for (const it of S.catalog.items) {
    const cat = it.item_type === 90 ? 'cur'
      : it.item_type === 92 ? 'skin'
        : it.item_type === 12 ? 'mat' : it.item_type === 20 ? 'use' : 'mat';
    rows.push({
      ...it, cat,
      kindLabel: { cur: '货币', mat: '材料', use: '消耗品', skin: '皮肤卡' }[cat] || `类型 ${it.item_type}`,
    });
  }
  for (const w of S.catalog.weapons) {
    rows.push({ ...w, cat: 'weapon', kindLabel: `${WTYPE[w.sub_type]}武器`, unreleased: w.released === false });
  }
  for (const f of S.catalog.furniture) rows.push({ ...f, cat: 'furn', kindLabel: '家具' });
  return rows;
}

function openItemModal() {
  const modal = $('#itemModal');
  modal.hidden = false;
  $('#catalogSearch').value = '';
  S.pickedItem = null;
  $('#itemPickFoot').hidden = true;
  $('#itemPickAdd').disabled = true;

  const cats = $('#catalogCats');
  cats.innerHTML = CATALOG_CATS.map(([v, n]) => `<button class="seg-btn ${v === 'all' ? 'active' : ''}" data-ccat="${v}">${n}</button>`).join('');
  S.catalogCat = 'all';
  cats.querySelectorAll('.seg-btn').forEach((ch) => ch.addEventListener('click', () => {
    S.catalogCat = ch.dataset.ccat;
    cats.querySelectorAll('.seg-btn').forEach((c) => c.classList.toggle('active', c === ch));
    renderCatalog();
  }));

  const renderCatalog = () => {
    const q = $('#catalogSearch').value.trim().toLowerCase();
    const rows = catalogRows()
      .filter((r) => S.catalogCat === 'all' || r.cat === S.catalogCat)
      .filter((r) => !q || r.name.toLowerCase().includes(q) || String(r.id).includes(q))
      .slice(0, 300);
    $('#catalogList').innerHTML = rows.length ? rows.map((r) => `
      <button class="cat-row ${S.pickedItem?.id === r.id ? 'selected' : ''}" data-cid="${r.id}">
        <span class="rarity r${r.rarity || 0}">${r.rarity || '·'}</span>
        <span>${esc(r.name)}</span>
        <span class="kind">${esc(r.kindLabel)}</span>
        ${r.unreleased ? `<span class="tag warn">${icon('warning')} 未实装</span>` : ''}
        <span class="id">${r.id}</span>
      </button>`).join('') : '<div class="placeholder">没有匹配的道具</div>';
    $('#catalogList').querySelectorAll('.cat-row').forEach((row) => row.addEventListener('click', () => {
      S.pickedItem = rows.find((r) => r.id === Number(row.dataset.cid));
      $('#catalogList').querySelectorAll('.cat-row').forEach((r) => r.classList.toggle('selected', r === row));
      $('#itemPickFoot').hidden = false;
      $('#itemPickName').innerHTML = `已选：<b>${esc(S.pickedItem.name)}</b> <span class="dim">(${S.pickedItem.id})</span>`
        + (S.pickedItem.unreleased
          ? `<br><span class="tag warn">${icon('warning')} 未实装武器</span> <span class="dim" style="font-size:12px">`
            + '客户端没有模型/图标/技能行，发下去会让武器详情面板崩，不能发放</span>'
          : '');
      $('#itemPickAdd').disabled = !!S.pickedItem.unreleased;
    }));
  };
  renderCatalog();
  $('#catalogSearch').oninput = renderCatalog;
}

// ══════════ 角色 ══════════

// 「星位」（玩家口中的命座）：每个角色一件专属的【星位之钉】（d_character.inbornItem），
// 游戏内用它点亮 6 个命座孔 —— 数据来自 /catalog 的 inborn_item / talent_total，
// 服务端口径见 src/game/talent.js。
const charInborn = (charId) => catChar(charId)?.inborn_item || 0;
const charTalentTotal = (charId) => catChar(charId)?.talent_total || 0;

// 存档背包里某种道具的总数（跨多堆叠），角色卡片与弹窗的「钉 ×N」用它。
const docItemCount = (itemId) => (S.doc?.bag?.items || [])
  .filter((it) => Number(it.item_id) === Number(itemId))
  .reduce((s, it) => s + Number(it.count || 0), 0);

// 角色已解锁的皮肤数（战斗 + 机甲 + 主城三个列表；酒店立绘与主城共享解锁，不重复计）。
// 服务端口径见 src/game/skins.js。
const skinOwnedCount = (char) => (char.own_character_skin_ids || []).length
  + (char.own_mecha_skin_ids || []).length
  + (char.own_city_skin_ids || []).length;

function renderChars(el) {
  const owned = new Map(S.doc.characters.map((c) => [c.character_id, c]));
  const wrap = pageEl(el, 'chars', `
    <div class="toolbar">
      <button class="btn" id="addAllChars">${icon('plus')} 一键添加全部角色</button>
      <button class="btn" id="grantAllWeapons">${icon('weapon')} 发放全部高稀有度武器</button>
      <label class="check"><input type="checkbox" id="grantSkipOwned" checked> 跳过已拥有的</label>
      <span class="spacer"></span>
      <span class="dim" style="font-size:12px">＝ 已实装的 6★/7★ 武器每种各一把（数据表里没有「角色→专武」关联，不再按类型猜）</span>
    </div>
    <div class="toolbar">
      <button class="btn" id="grantAllNails">${icon('star')} 发放全部角色的星位之钉</button>
      <button class="btn" id="unlockAllTalents">${icon('star')} 点亮全部角色的星位</button>
      <button class="btn" id="unlockAllSkins">${icon('shirt')} 解锁全部角色的皮肤</button>
      <label class="check">每个角色 <input type="number" id="nailCount" min="1" max="99" value="7"> 把钉</label>
      <span class="spacer"></span>
      <span class="dim" style="font-size:12px">＝ 命座。钉是每个角色专属的消耗品（如【莎乐美&lt;礼器&gt;】的星位之钉），
        游戏内点亮 6 个命座孔每孔消耗 1 把；「点亮全部星位」直接写档，跳过消耗与等级条件。</span>
    </div>
    <div class="grid chars">
      ${S.catalog.characters.map((c) => {
        const o = owned.get(c.id);
        const wn = o?.weapon_info ? catWeapon(o.weapon_info.item_id) : null;
        const cap = capForBreak(o?.break_times);
        const lv = o ? Math.min(cap, levelForExp(roleExpArr(), o.exp)) : 0;
        const nail = charInborn(c.id);
        const nails = nail ? docItemCount(nail) : 0;
        const lit = (o?.talent_ids || []).length;
        const skinsOwned = o ? skinOwnedCount(o) : 0;
        const dirty = hasPending((p) => Number(p.character_id) === Number(c.id)
          || p.op === 'add_all_characters'
          || p.op === 'grant_all_constellations'
          || p.op === 'unlock_all_talents'
          || p.op === 'unlock_all_skins');
        return `<button class="char-card ${o ? '' : 'not-owned'} ${dirty ? 'dirty' : ''}" data-char="${c.id}">
          <div class="c-name">${esc(c.name)} ${o ? '' : '<span class="badge">未拥有</span>'}</div>
          <div class="c-sub">${o
            ? `Lv.${lv}（上限 ${cap}） · 突破 ${o.break_times}<br>武器：${wn ? esc(wn.name) : '无'}</div>`
            : `武器类型：${WTYPE[c.profession]}</div>`}
          <div class="c-tags">
            <span class="tag">${WTYPE[c.profession]}</span>
            ${wn ? `<span class="rarity r${wn.rarity}">${wn.rarity}★</span>` : ''}
            ${nail ? `<span class="tag" title="星位之钉 ${nail}">${icon('star')} 星位 ${lit}/${charTalentTotal(c.id)} · 钉 ×${nails}</span>` : ''}
            ${o && c.skin_total ? `<span class="tag" title="战斗/机甲/主城皮肤">${icon('shirt')} 皮肤 ${skinsOwned}/${c.skin_total}</span>` : ''}
          </div>
        </button>`;
      }).join('')}
    </div>`);

  $('#addAllChars').addEventListener('click', () => { stage({ op: 'add_all_characters' }); toast('已加入待保存清单'); });
  $('#grantAllWeapons').addEventListener('click', () => {
    stage({ op: 'grant_high_rarity_weapons', skip_owned: $('#grantSkipOwned').checked });
    toast('已加入待保存清单');
  });
  wrap.querySelectorAll('.char-card').forEach((card) => card.addEventListener('click', () => {
    openCharModal(Number(card.dataset.char));
  }));

  const nailCountOf = () => Math.max(1, Math.min(99, Math.trunc(Number($('#nailCount').value) || 7)));
  $('#nailCount').addEventListener('change', () => { $('#nailCount').value = nailCountOf(); });
  $('#grantAllNails').addEventListener('click', () => {
    stage({ op: 'grant_all_constellations', count: nailCountOf() });
    toast(`已加入待保存清单：全部角色各发放星位之钉 ×${nailCountOf()}`);
  });
  $('#unlockAllTalents').addEventListener('click', () => {
    stage({ op: 'unlock_all_talents' });
    toast('已加入待保存清单：点亮全部角色的星位');
  });
  $('#unlockAllSkins').addEventListener('click', () => {
    stage({ op: 'unlock_all_skins' });
    toast('已加入待保存清单：解锁全部角色的皮肤');
  });
}

function openCharModal(charId) {
  const c = catChar(charId);
  const owned = S.doc.characters.find((x) => x.character_id === charId);
  const best = c?.best_weapon || 0;
  const wName = best ? (catWeapon(best)?.name || `#${best}`) : '无';

  const html = owned ? (() => {
    const bt = Math.max(0, Math.trunc(Number(owned.break_times) || 0));
    const cap = capForBreak(bt);
    const lv = Math.min(cap, levelForExp(roleExpArr(), owned.exp));
    const w = owned.weapon_info;
    const wcfg = w ? catWeapon(w.item_id) : null;
    const wbt = w ? Math.max(0, Math.trunc(Number(w.weapon_info.break_times) || 0)) : 0;
    const wcap = capForBreak(wbt);
    const wlv = w ? Math.min(wcap, levelForExp(weaponExpArr(w.item_id), w.weapon_info.exp)) : 0;
    // 星位（命座）：钉 id/名字来自目录，数量从存档背包实时数，已点亮数取 talent_ids。
    const nail = charInborn(charId);
    const nails = nail ? docItemCount(nail) : 0;
    const nailName = nail ? itemName(nail) : '';
    const talentTotal = charTalentTotal(charId);
    const lit = (owned.talent_ids || []).length;
    return `
    <div class="modal-head"><h3>${esc(c.name)} <span class="dim" style="font-size:12px">${WTYPE[c.profession]}</span></h3>
      <button class="icon-btn" data-close="charModal" title="关闭">${icon('close')}</button></div>
    <div class="modal-body">
      <div class="row">
        <div class="field grow"><label>等级（上限 ${cap}）</label>
          <input type="number" min="1" max="${cap}" id="cLevel" value="${lv}"></div>
        <div class="field grow"><label>突破次数（0-${maxBreak()}）</label>
          <input type="number" min="0" max="${maxBreak()}" id="cBreak" value="${bt}"></div>
        <div class="field grow"><label>经验（由等级反推，可手改）</label>
          <input type="number" min="0" id="cExp" value="${owned.exp}"></div>
      </div>
      ${w ? `
      <div class="card" style="margin:14px 0 0">
        <div class="card-head"><h4 style="font-size:13px">已装备武器：${esc(wcfg?.name || w.item_id)}
          <span class="rarity r${wcfg?.rarity}">${wcfg?.rarity}★</span></h4></div>
        <div class="row">
          <div class="field grow"><label>等级（上限 ${wcap}）</label>
            <input type="number" min="1" max="${wcap}" id="wLevel" value="${wlv}"></div>
          <div class="field grow"><label>突破（0-${maxBreak()}）</label>
            <input type="number" min="0" max="${maxBreak()}" id="wBreak" value="${wbt}"></div>
          <div class="field grow"><label>光淬（0-${wcfg?.max_refine ?? 4}）</label>
            <input type="number" min="0" max="${wcfg?.max_refine ?? 4}" id="wRefine" value="${w.weapon_info.refine_level || 0}"></div>
          <div class="field grow"><label>经验（由等级反推，可手改）</label>
            <input type="number" min="0" id="wExp" value="${w.weapon_info.exp}"></div>
        </div>
      </div>` : '<p class="hint-line">该角色没有装备武器</p>'}
      ${nail ? `
      <div class="card" style="margin:14px 0 0">
        <div class="card-head"><h4 style="font-size:13px">${icon('star')} 星位（命座）</h4>
          <span class="hint">已点亮 ${lit}/${talentTotal} · 背包里 ${esc(nailName)} ×${nails}</span></div>
        <p class="hint-line">专属星位之钉：<b>${esc(nailName)}</b>（${nail}）。
          游戏内点亮 6 个命座孔每孔消耗 1 把；其余星位按角色等级解锁。</p>
        <div class="row">
          <div class="field grow"><label>发放数量（把，1-99）</label>
            <input type="number" min="1" max="99" id="mNailCount" value="7"></div>
          <div class="field grow" style="align-self:flex-end">
            <button class="btn" id="grantNail">${icon('star')} 发放星位之钉</button></div>
        </div>
        <div class="actions" style="margin-top:10px">
          <button class="btn ghost" id="unlockTalentsOne">${icon('star')} 点亮该角色全部星位（跳过消耗与等级）</button>
        </div>
      </div>` : ''}
      ${c.skin_total ? `
      <div class="card" style="margin:14px 0 0">
        <div class="card-head"><h4 style="font-size:13px">${icon('shirt')} 皮肤（战斗 / 机甲 / 主城）</h4>
          <span class="hint">已解锁 ${skinOwnedCount(owned)}/${c.skin_total}</span></div>
        <p class="hint-line">解锁后游戏内角色页的「装扮」面板即可换装；也可以给该角色发皮肤卡道具，
          玩家在背包里「使用」同样会解锁。主城住宅的偶像立绘与主城皮肤共享解锁。</p>
        <div class="actions" style="margin-top:10px">
          <button class="btn ghost" id="unlockSkinsOne">${icon('shirt')} 解锁该角色全部皮肤</button>
        </div>
      </div>` : ''}
      ${best ? `<p class="hint-line">同类型推荐武器（最高稀有度且已实装）：${esc(wName)}（${best}）</p>` : ''}
    </div>
    <div class="modal-foot">
      <div class="left">${best ? `<button class="btn" id="grantOne">${icon('weapon')} 发放该武器</button>` : ''}</div>
      <button class="btn primary" id="charSave">加入待保存清单</button>
    </div>`;
  })() : `
    <div class="modal-head"><h3>${esc(c.name)} <span class="badge">未拥有</span></h3>
      <button class="icon-btn" data-close="charModal" title="关闭">${icon('close')}</button></div>
    <div class="modal-body">
      <p>武器类型：${WTYPE[c.profession]}。添加后自带初始武器与技能。</p>
      ${charInborn(charId) ? `<p class="hint-line">星位（命座）：专属星位之钉是 <b>${esc(itemName(charInborn(charId)))}</b>（${charInborn(charId)}），
        共 ${charTalentTotal(charId)} 个星位。想直接发放钉请用「发放该角色的钉」，
        或回到角色页用「发放全部角色的星位之钉」。</p>` : ''}
    </div>
    <div class="modal-foot">
      <div class="left">${best ? `<button class="btn" id="grantOne">${icon('weapon')} 发放推荐武器</button>` : ''}
        ${charInborn(charId) ? `<button class="btn" id="charGrantNail">${icon('star')} 发放该角色的钉 ×7</button>` : ''}</div>
      <button class="btn primary" id="charAdd">添加该角色</button>
    </div>`;

  $('#charModalBody').innerHTML = html;
  $('#charModal').hidden = false;

  const addBtn = $('#charAdd');
  if (addBtn) addBtn.addEventListener('click', () => {
    stage({ op: 'add_character', character_id: charId });
    toast('已加入待保存清单');
    $('#charModal').hidden = true;
    loadDoc(S.id, false).then(renderTab);
  });
  const grantBtn = $('#grantOne');
  if (grantBtn && best) grantBtn.addEventListener('click', () => {
    stageAddItem(best, 1);
    toast(`已加入待保存清单：${wName} ×1`);
    $('#charModal').hidden = true;
  });

  // 星位（命座）：发钉 / 直接点亮。发钉不要求已拥有该角色，点亮则必须（要写 talent_ids）。
  const nailBtn = $('#grantNail');
  if (nailBtn) nailBtn.addEventListener('click', () => {
    const n = Math.max(1, Math.min(99, Math.trunc(Number($('#mNailCount').value) || 7)));
    $('#mNailCount').value = n;
    stage({ op: 'grant_constellation', character_id: charId, count: n });
    toast(`已加入待保存清单：星位之钉 ×${n}`);
    $('#charModal').hidden = true;
  });
  const unlockOneBtn = $('#unlockTalentsOne');
  if (unlockOneBtn) unlockOneBtn.addEventListener('click', () => {
    stage({ op: 'unlock_all_talents', character_id: charId });
    toast('已加入待保存清单：点亮该角色全部星位');
    $('#charModal').hidden = true;
  });
  const unlockSkinsOneBtn = $('#unlockSkinsOne');
  if (unlockSkinsOneBtn) unlockSkinsOneBtn.addEventListener('click', () => {
    stage({ op: 'unlock_all_skins', character_id: charId });
    toast('已加入待保存清单：解锁该角色全部皮肤');
    $('#charModal').hidden = true;
  });
  // 未拥有角色时也能先把钉发好（钉是背包道具，与角色是否拥有无关）。
  const notOwnedNailBtn = $('#charGrantNail');
  if (notOwnedNailBtn) notOwnedNailBtn.addEventListener('click', () => {
    stage({ op: 'grant_constellation', character_id: charId, count: 7 });
    toast('已加入待保存清单：星位之钉 ×7');
    $('#charModal').hidden = true;
  });

  // 等级/突破/经验三者联动：改等级就把经验一起写掉（服务端按等级反推经验）；
  // 只改经验时不发等级，服务端只认经验。提交时用**两个不同的 op**
  // （set_character_level + set_weapon_stats），键不同所以不会互相顶掉。
  if ($('#cLevel')) {
    const syncFromLevel = () => {
      const v = Math.min(capForBreak($('#cBreak').value), Math.max(1, Math.trunc(Number($('#cLevel').value) || 1)));
      $('#cLevel').value = v;
      $('#cExp').value = expForLevel(roleExpArr(), v);
      $('#cExp').dataset.derived = '1';
    };
    const syncFromExp = () => {
      const v = Math.max(0, Math.trunc(Number($('#cExp').value) || 0));
      $('#cExp').value = v;
      $('#cLevel').value = Math.min(capForBreak($('#cBreak').value), levelForExp(roleExpArr(), v));
      delete $('#cExp').dataset.derived;
    };
    $('#cLevel').addEventListener('change', syncFromLevel);
    $('#cBreak').addEventListener('change', () => {
      const bt = Math.min(maxBreak(), Math.max(0, Math.trunc(Number($('#cBreak').value) || 0)));
      $('#cBreak').value = bt;
      if ($('#cExp').dataset.derived) syncFromLevel(); else syncFromExp();
    });
    $('#cExp').addEventListener('change', syncFromExp);
  }
  if ($('#wLevel')) {
    const wCap = () => capForBreak($('#wBreak').value);
    const syncFromLevel = () => {
      const v = Math.min(wCap(), Math.max(1, Math.trunc(Number($('#wLevel').value) || 1)));
      $('#wLevel').value = v;
      $('#wExp').value = expForLevel(weaponExpArr(owned.weapon_info.item_id), v);
      $('#wExp').dataset.derived = '1';
    };
    const syncFromExp = () => {
      const v = Math.max(0, Math.trunc(Number($('#wExp').value) || 0));
      $('#wExp').value = v;
      $('#wLevel').value = Math.min(wCap(), levelForExp(weaponExpArr(owned.weapon_info.item_id), v));
      delete $('#wExp').dataset.derived;
    };
    $('#wLevel').addEventListener('change', syncFromLevel);
    $('#wBreak').addEventListener('change', () => {
      const bt = Math.min(maxBreak(), Math.max(0, Math.trunc(Number($('#wBreak').value) || 0)));
      $('#wBreak').value = bt;
      if ($('#wExp').dataset.derived) syncFromLevel(); else syncFromExp();
    });
    $('#wExp').addEventListener('change', syncFromExp);
  }

  const saveBtn = $('#charSave');
  if (saveBtn) saveBtn.addEventListener('click', () => {
    const bt = Math.min(maxBreak(), Math.max(0, Math.trunc(Number($('#cBreak').value) || 0)));
    // 经验被手改过就以经验为准（不发 level）；否则按等级让服务端反推经验。
    if ($('#cExp').dataset.derived) {
      stage({ op: 'set_character_level', character_id: charId, level: Math.trunc(Number($('#cLevel').value) || 1), break_times: bt });
    } else {
      stage({ op: 'edit_character', character_id: charId, exp: Math.max(0, Math.trunc(Number($('#cExp').value) || 0)), break_times: bt });
    }
    if ($('#wLevel')) {
      const uuid = owned.weapon_info.item_uuid;
      const wbt = Math.min(maxBreak(), Math.max(0, Math.trunc(Number($('#wBreak').value) || 0)));
      const stat = { op: 'set_weapon_stats', item_uuid: Number(uuid), break_times: wbt, refine_level: Math.trunc(Number($('#wRefine').value) || 0) };
      if ($('#wExp').dataset.derived) stat.level = Math.trunc(Number($('#wLevel').value) || 1);
      else stat.exp = Math.max(0, Math.trunc(Number($('#wExp').value) || 0));
      stage(stat);
    }
    toast('已加入待保存清单');
    $('#charModal').hidden = true;
  });
}

// ══════════ 抽卡 ══════════

function renderGacha(el) {
  const infos = S.doc.gacha.type_infos || {};
  const keys = [...new Set([...Object.keys(infos), '1', '2', '3', '4'])].sort();
  const wrap = pageEl(el, 'gacha', `
    <div class="card">
      <div class="card-head"><h3>抽卡保底</h3>
        <span class="hint">no_up_times = 距上次 UP 六星的累计抽数，保存后需重新登录</span></div>
      <div class="grid cur">
        ${keys.map((k) => {
          const st = infos[k] || {};
          const dirty = hasPending((p) => p.op === 'set_gacha_pity' && Number(p.pool_type) === Number(k));
          return `<div class="field ${dirty ? 'dirty' : ''}"><label>${POOL_NAMES[k] || `池 ${k}`} · 累计 ${fmt(st.total_times || 0)} 抽</label>
            <input type="number" min="0" data-pool="${k}" value="${st.no_up_times || 0}"></div>`;
        }).join('')}
      </div>
    </div>`);
  wrap.querySelectorAll('input[data-pool]').forEach((inp) => {
    inp.addEventListener('change', () => {
      const v = Math.max(0, Math.trunc(Number(inp.value) || 0));
      inp.value = v;
      stage({ op: 'set_gacha_pity', pool_type: Number(inp.dataset.pool), no_up_times: v });
      toast('已加入待保存清单');
    });
  });
}

// ══════════ 商城 ══════════

function renderMall(el) {
  const m = S.doc.mall;
  const expire = Number(m.month_card_expire || 0);
  const active = expire > Date.now() / 1000;
  const cpDirty = hasPending((p) => p.op === 'set_charge_point');
  const mcDirty = hasPending((p) => p.op === 'set_month_card');
  const wrap = pageEl(el, 'mall', `
    <div class="card">
      <div class="card-head"><h3>累充积分</h3><span class="hint">改完即可在游戏内累充奖励页领取对应档位</span></div>
      <div class="row">
        <div class="field grow ${cpDirty ? 'dirty' : ''}"><label>当前积分：${fmt(m.charge_point)}</label>
          <input type="number" min="0" id="chargeInput" value="${m.charge_point}"></div>
        <button class="btn" id="chargeBtn">设置</button>
      </div>
    </div>
    <div class="card">
      <div class="card-head"><h3>月卡</h3>
        <span class="hint">${active ? `到期：${new Date(expire * 1000).toLocaleString('zh-CN')}` : '未持有'}</span></div>
      <div class="row ${mcDirty ? 'dirty' : ''}">
        <div class="field grow"><label>延长天数</label><input type="number" min="0" id="monthDays" value="30"></div>
        <button class="btn" id="monthAdd">延长</button>
        <button class="btn danger" id="monthClear">清空月卡</button>
      </div>
      <p class="hint-line">每日奖励游标会一并重置，保存后当天即可领取。</p>
    </div>`);
  $('#chargeBtn').addEventListener('click', () => {
    const v = Math.max(0, Math.trunc(Number($('#chargeInput').value) || 0));
    $('#chargeInput').value = v;
    stage({ op: 'set_charge_point', value: v });
    toast('已加入待保存清单');
  });
  $('#monthAdd').addEventListener('click', () => {
    const days = Math.max(0, Math.trunc(Number($('#monthDays').value) || 0));
    if (!days) return toast('天数要大于 0', 'err');
    stage({ op: 'set_month_card', days });
    toast('已加入待保存清单');
  });
  $('#monthClear').addEventListener('click', () => {
    stage({ op: 'set_month_card', days: 0 });
    toast('已加入待保存清单');
  });
}

// ══════════ 剧情（只读） ══════════

function renderPlot(el) {
  const p = S.doc.plot;
  const missions = p.plot_mission_infos || [];
  pageEl(el, 'plot', `
    <div class="card">
      <div class="card-head"><h3>主线进度</h3>
        <span class="hint">只读展示 · 任务进度由游戏内行为驱动，直接改易破坏任务链</span></div>
      <div class="kv">
        <span class="k">剧情树 ID</span><span class="v">${p.plot_tree_id ?? 0}　节点 ${p.plot_node_id ?? 0}</span>
        <span class="k">进行中任务</span><span class="v">${missions.length} 个</span>
        <span class="k">已完成任务</span><span class="v">${(p.completed_mission_ids || []).length} 个</span>
        <span class="k">已解锁故事线</span><span class="v">${(p.unlocked_story_line_ids || []).length} 条</span>
      </div>
    </div>
    ${missions.length ? `
    <div class="card">
      <div class="card-head"><h3>进行中的任务</h3></div>
      <div class="kv">${missions.slice(0, 40).map((mm) => `<span class="k">任务 ${mm.mission_id ?? mm}</span><span class="v dim">计数 ${mm.count ?? 0}</span>`).join('')}</div>
    </div>` : ''}`);
}

// ══════════ 备份 ══════════

async function renderBackup(el) {
  const wrap = pageEl(el, 'backup', `
    <div class="card">
      <div class="card-head"><h3>导出当前存档</h3><span class="hint">导出会短暂踢下线在线玩家（保证快照一致）</span></div>
      <div class="row">
        <div class="field grow"><label>目标目录（留空 = 默认备份位置）</label>
          <input type="text" id="exportPath" placeholder="例如 D:\\Nornium_backup"></div>
        <button class="btn primary" id="exportBtn">${icon('download')} 导出</button>
      </div>
    </div>
    <div class="card">
      <div class="card-head"><h3>历史快照</h3><span class="hint">server 目录旁的 data_* 文件夹</span></div>
      <div id="backupList"><div class="skeleton"><i></i><i></i><i></i></div></div>
    </div>`);

  $('#exportBtn').addEventListener('click', async () => {
    const p = $('#exportPath').value.trim();
    try {
      const d = await api('/editor/api/export', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(p ? { path: p } : {}),
      });
      toast(`已导出到 ${d.dir}（${d.players} 个档案）`);
      renderTab();
    } catch (err) { toast(err.message, 'err'); }
  });

  try {
    const d = await api('/editor/api/backups');
    $('#backupList').innerHTML = d.backups.length
      ? d.backups.map((b) => `<div class="backup-row">
          <div><div>${esc(b.name)}</div><div class="path">${esc(b.path)}</div></div>
          <span class="badge">${new Date(b.mtime).toLocaleString('zh-CN')}</span>
        </div>`).join('')
      : '<div class="placeholder">还没有快照。restore / load / export 时会自动生成。</div>';
  } catch (_) { $('#backupList').innerHTML = '<div class="placeholder">快照列表加载失败</div>'; }
  return wrap;
}

// ══════════ 服务（服务端管理） ══════════

function fmtUptime(sec) {
  const s = Math.max(0, Math.trunc(sec || 0));
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  const ss = s % 60;
  if (d) return `${d} 天 ${h} 小时`;
  if (h) return `${h} 小时 ${m} 分`;
  if (m) return `${m} 分 ${ss} 秒`;
  return `${ss} 秒`;
}

async function renderServer(el) {
  const d = S.server;
  const wrap = document.createElement('div');
  wrap.className = 'page';

  if (!d) {
    wrap.innerHTML = `${pageHeadHtml('server')}
      <div class="card error-card"><div class="card-head"><h3>${icon('warning')} 无法连接服务端</h3>
        <span class="status-line"><span class="dot off"></span>连不上</span></div>
      <p class="hint-line">服务端可能已经停止，或本页不是由它提供的。
      重新启动请双击仓库根目录的 <b>点我启动.bat</b>。</p>
      <div class="actions" style="margin-top:14px">
        <button class="btn" id="srvRecheck">${icon('refresh')} 重新检测</button></div></div>`;
    el.appendChild(wrap);
    $('#srvRecheck').addEventListener('click', async () => {
      S.stopped = false;
      $('#stoppedMask').hidden = true;
      await Promise.all([loadServer(), loadAccounts()]);
      renderTab();
    });
    return;
  }

  let backups = [];
  try { backups = (await api('/editor/api/backups')).backups || []; } catch (_) { /* 忽略 */ }

  wrap.innerHTML = `${pageHeadHtml('server')}
    <div class="card">
      <div class="card-head"><h3>服务端状态</h3>
        <span class="status-line"><span class="dot on"></span>运行中 · v${esc(d.version)}</span></div>
      <div class="grid stats">
        <div class="stat"><div class="k">在线连接</div><div class="v">${d.online}</div></div>
        <div class="stat"><div class="k">运行时长</div><div class="v">${fmtUptime(d.uptime_seconds)}</div></div>
        <div class="stat"><div class="k">账号 / 档案</div><div class="v">${d.stats.accounts} / ${d.stats.players}</div></div>
        <div class="stat"><div class="k">端口（TCP 游戏 / HTTP 门）</div><div class="v">${d.tcp_port ?? '?'} / ${d.http_port ?? '?'}</div></div>
        <div class="stat"><div class="k">存档目录</div><div class="v small">${esc(d.data_dir)}</div></div>
        <div class="stat"><div class="k">历史快照</div><div class="v">${d.backups}</div></div>
      </div>
    </div>

    <div class="card">
      <div class="card-head"><h3>日常操作</h3><span class="hint">不影响存档内容</span></div>
      <div class="actions">
        <button class="btn" id="srvBackup">${icon('save')} 立即备份一份</button>
        <button class="btn" id="srvKick">${icon('power')} 踢出所有在线玩家</button>
        <button class="btn" id="srvReload">${icon('refresh')} 刷新状态</button>
      </div>
      <p class="hint-line">备份落在 <code>server\data_manual_&lt;时间戳&gt;\</code>；踢人后玩家重新登录即可（存档不受影响）。</p>
    </div>

    <div class="card">
      <div class="card-head"><h3>从快照导入存档</h3>
        <span class="hint">会短暂踢下线在线玩家，保证换档期间没有旧会话回写</span></div>
      <div class="row">
        <div class="field grow"><label>快照 / 备份目录</label>
          <input type="text" id="srvLoadPath" list="srvBackupList" placeholder="data_wipe_20260925-143000 或 D:\\Nornium_backup"></div>
        <button class="btn primary" id="srvLoad">导入并热重载</button>
      </div>
      <datalist id="srvBackupList">${backups.map((b) => `<option value="${esc(b.path)}">${esc(b.name)}</option>`).join('')}</datalist>
      <p class="hint-line">覆盖式导入：只覆盖备份里有的文件，不会删除当前存档里多出来的档案；导入前会自动留一份 <code>data_preimport_*</code>。</p>
    </div>

    <div class="card danger-zone">
      <div class="card-head"><h3>${icon('warning')} 危险操作</h3><span class="hint">清空存档需手动输入确认文字</span></div>
      <div class="actions">
        <button class="btn danger" id="srvRestore">${icon('trash')} 清空全部存档</button>
        <button class="btn danger" id="srvStop">${icon('power')} 停止服务端</button>
      </div>
      <p class="hint-line">
        <b>清空存档</b>：删掉 <code>data\accounts.json</code> + 全部玩家档案（删前自动留一份 <code>data_wipe_*</code> 快照），
        服务端继续运行，下一位注册的就是全新档案。<br>
        <b>停止服务端</b>：踢出所有在线玩家并结束进程，游戏与编辑器都会离线；重启请双击 <b>点我启动.bat</b>。</p>
    </div>`;
  el.appendChild(wrap);

  $('#srvBackup').addEventListener('click', async () => {
    try {
      const r = await api('/editor/api/server/backup', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
      toast(`已备份到 ${r.dir}（${r.players} 个档案）`);
      renderTab();
    } catch (err) { toast(err.message, 'err'); }
  });

  $('#srvKick').addEventListener('click', async () => {
    if (!await askConfirm({
      title: '踢出所有在线玩家',
      body: '所有在线玩家会立刻掉线（客户端提示「账号在其他地方登录」）。<br>存档不受影响，重新登录即可继续。',
      okLabel: '踢出',
    })) return;
    try {
      const r = await api('/editor/api/server/kick', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
      toast(`已踢出 ${r.kicked} 个连接`);
      await loadServer();
    } catch (err) { toast(err.message, 'err'); }
  });

  $('#srvReload').addEventListener('click', async () => { await Promise.all([loadServer(), loadAccounts()]); toast('已刷新'); });

  $('#srvLoad').addEventListener('click', async () => {
    const p = $('#srvLoadPath').value.trim();
    if (!p) return toast('先填一个备份目录', 'err');
    if (!await askConfirm({
      title: '从备份导入存档',
      body: `将把 <code>${esc(p)}</code> 里的 <code>accounts.json</code> 与玩家档案覆盖到当前存档目录，<br>
        在线玩家会被踢下线。导入前会自动留一份快照。`,
      okLabel: '导入',
      danger: true,
    })) return;
    try {
      const r = await api('/editor/api/server/load', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ path: p }),
      });
      toast(`已导入 ${r.players} 个档案${r.accounts ? '（含账号表）' : ''}`);
      if (r.snapshot) toast(`导入前的旧档已备份到 ${r.snapshot}`);
      await Promise.all([loadServer(), loadAccounts()]);
      S.doc = null; S.id = null;
      renderTab();
    } catch (err) { toast(err.message, 'err'); }
  });

  $('#srvRestore').addEventListener('click', async () => {
    if (!await askConfirm({
      title: '清空全部存档',
      body: '这会删掉 <b>所有账号与玩家档案</b>，且不可撤销（删前会自动留一份 <code>data_wipe_*</code> 快照，可手工回滚）。<br>'
        + '在线玩家会被踢下线，服务端继续运行。',
      confirmText: '清空存档',
      okLabel: '清空存档',
      danger: true,
    })) return;
    try {
      const r = await api('/editor/api/server/restore', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ confirm: '清空存档' }),
      });
      toast(`已清空 ${r.before.accounts} 个账号 / ${r.before.players} 个档案`);
      if (r.snapshot) toast(`清空前已备份到 ${r.snapshot}`);
      S.doc = null; S.id = null; S.pending = []; renderPending();
      await Promise.all([loadServer(), loadAccounts()]);
      renderTab();
    } catch (err) { toast(err.message, 'err'); }
  });

  $('#srvStop').addEventListener('click', async () => {
    if (!await askConfirm({
      title: '停止服务端',
      body: '服务端进程会结束：游戏与这个编辑器页面都会离线，本页将无法再连接。<br>'
        + '存档不受影响；要重新开服请双击仓库根目录的 <b>点我启动.bat</b>。',
      okLabel: '停止服务端',
      danger: true,
    })) return;
    try {
      await api('/editor/api/server/stop', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
    } catch (_) { /* 服务端可能已经先断了，忽略 */ }
    markStopped();
  });
  return wrap;
}

// ══════════ 服务器控制台 ══════════

// 客户端视图也只留最近 2000 行（与服务端环形缓冲同量级）
const CONSOLE_MAX_LINES = 2000;

// 断开 SSE（离开页面 / 停服时调用；重复调用安全）
function closeConsoleStream() {
  if (S.consoleEs) {
    try { S.consoleEs.close(); } catch (_) { /* ignore */ }
    S.consoleEs = null;
  }
}

// 一行日志 → <div>。级别从行首的 [I/W/E/V] 标记识别（logger 的格式）；
// 裸 console 输出（启动横幅、指令回显）没有标记，按普通行渲染。
function consoleLineHtml(text) {
  const s = String(text ?? '');
  const m = s.match(/\[([IWEV])\]/);
  const lv = m ? m[1].toLowerCase() : 'i';
  return `<div class="console-line log-${lv}">${esc(s) || '&nbsp;'}</div>`;
}

function appendConsoleLines(view, entries) {
  if (!entries || !entries.length) return;
  if (view.querySelector('.placeholder')) view.innerHTML = '';
  view.insertAdjacentHTML('beforeend', entries.map((e) => consoleLineHtml(e.text)).join(''));
  while (view.children.length > CONSOLE_MAX_LINES) view.removeChild(view.firstChild);
  $('#consoleCount').textContent = `${view.children.length} 行`;
  if (S.consoleAutoScroll) view.scrollTop = view.scrollHeight;
}

// 网页端执行的指令清单（与 src/console.js 的 handleCommand 同一份口径）。
// restore / stop / load / export 动磁盘或退进程，执行前先弹确认框。
const CONSOLE_DANGER = {
  restore: { body: '将<b>清空全部存档</b>（删前自动留 <code>data_wipe_*</code> 快照），在线玩家全部踢下线，服务端继续运行。', confirmText: '清空存档' },
  load: { body: '将从磁盘重新加载 / 导入存档，在线玩家会被踢下线。' },
  export: { body: '将导出当前存档（在线玩家会被短暂踢下线以保证快照一致）。' },
  stop: { body: '服务端进程会结束：游戏与这个编辑器页面都会离线。重启请双击 <b>点我启动.bat</b>。' },
};

async function renderConsole(el) {
  closeConsoleStream(); // 重绘（如主题切换外的重进）也要先断旧流
  const wrap = pageEl(el, 'console', `
    <div class="card console-card">
      <div class="card-head">
        <h3>${icon('term')} 服务端输出</h3>
        <span class="hint" id="consoleCount"></span>
        <div class="console-tools">
          <label class="console-follow"><input type="checkbox" id="consoleFollow" ${S.consoleAutoScroll ? 'checked' : ''}> 自动滚动</label>
          <button class="btn ghost" id="consoleClear" title="只清空这里的显示，不影响服务端与日志文件">${icon('eraser')} 清屏</button>
        </div>
      </div>
      <div class="console-view" id="consoleView"><div class="placeholder">正在拉取服务端输出…</div></div>
      <div class="console-input">
        <span class="console-prompt">&gt;</span>
        <input type="text" id="consoleCmdInput" placeholder="输入指令后回车（help 查看列表）" autocomplete="off" spellcheck="false">
        <button class="btn primary" id="consoleSend">${icon('send')} 执行</button>
      </div>
      <p class="hint-line">指令与服务端黑窗口同口径：restore / load / export / allweapons / stop / status / help；
      执行回显会实时出现在上方输出里，黑窗口同样可见。清档等危险操作会先要求确认。</p>
    </div>`);

  const view = $('#consoleView');

  // 用户往上翻就暂停自动滚动（勾选框同步），翻回底部（或手动勾上）恢复
  view.addEventListener('scroll', () => {
    const stick = view.scrollHeight - view.scrollTop - view.clientHeight < 40;
    if (!stick && S.consoleAutoScroll) {
      S.consoleAutoScroll = false;
      const cb = $('#consoleFollow');
      if (cb) cb.checked = false;
    }
  });
  $('#consoleFollow').addEventListener('change', (e) => {
    S.consoleAutoScroll = e.target.checked;
    if (S.consoleAutoScroll) view.scrollTop = view.scrollHeight;
  });
  $('#consoleClear').addEventListener('click', () => {
    view.innerHTML = '<div class="placeholder">已清屏（只影响这里的显示）</div>';
    $('#consoleCount').textContent = '';
  });

  // 指令历史：↑/↓ 翻找
  const input = $('#consoleCmdInput');
  input.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
      if (!S.consoleHistory.length) return;
      e.preventDefault();
      if (S.consoleHistoryIdx === -1 && e.key === 'ArrowUp') S.consoleHistoryIdx = S.consoleHistory.length;
      S.consoleHistoryIdx += e.key === 'ArrowUp' ? -1 : 1;
      S.consoleHistoryIdx = Math.max(0, Math.min(S.consoleHistory.length, S.consoleHistoryIdx));
      input.value = S.consoleHistory[S.consoleHistoryIdx] ?? '';
    } else if (e.key === 'Enter') {
      sendConsoleCommand(view);
    }
  });
  $('#consoleSend').addEventListener('click', () => sendConsoleCommand(view));

  // 先拉缓冲里的历史，再开 SSE 增量。await 期间可能已经切走标签页，别再接线。
  let tail;
  try {
    tail = await api('/editor/api/console/tail?after=0');
  } catch (err) {
    view.innerHTML = `<div class="placeholder">拉取服务端输出失败：${esc(err.message)}</div>`;
    return;
  }
  if (S.tab !== 'console' || S.stopped) return;
  S.consoleSeq = tail.last;
  appendConsoleLines(view, tail.lines);
  if (!tail.lines.length) view.innerHTML = '<div class="placeholder">暂无输出（服务端刚启动时这里会陆续出现日志）</div>';
  view.scrollTop = view.scrollHeight;

  if (typeof EventSource !== 'function') return; // 极简环境（UI 回归 shim）只验历史，不验实时流
  const es = new EventSource(`/editor/api/console/stream?after=${S.consoleSeq}`);
  S.consoleEs = es;
  es.onmessage = (e) => {
    let entry;
    try { entry = JSON.parse(e.data); } catch (_) { return; }
    if (!entry || typeof entry.seq !== 'number') return;
    if (entry.seq <= S.consoleSeq) return; // SSE 重连补发时跳过已有的行
    S.consoleSeq = entry.seq;
    appendConsoleLines(view, [entry]);
  };
  es.onerror = () => {
    // EventSource 会自动重连；停服场景由 markStopped 主动 close
    $('#consoleCount').textContent = '连接中断，自动重连中…';
  };
}

async function sendConsoleCommand(view) {
  const input = $('#consoleCmdInput');
  const cmd = (input ? input.value : '').trim();
  if (!cmd) return toast('先输入一条指令', 'err');
  const name = cmd.split(/\s+/)[0].toLowerCase();
  const danger = CONSOLE_DANGER[name];
  if (danger && !await askConfirm({
    title: `执行指令 ${name}`,
    body: danger.body,
    confirmText: danger.confirmText,
    okLabel: '执行',
    danger: true,
  })) return;

  input.value = '';
  S.consoleHistory.push(cmd);
  if (S.consoleHistory.length > 50) S.consoleHistory.shift();
  S.consoleHistoryIdx = -1;
  try {
    const r = await api('/editor/api/console/cmd', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ command: cmd }),
    });
    // reply 由服务端 console.log 回显进日志流（SSE 会送到上方视图），这里不重复渲染
    if (r.reply && !view.querySelector('.console-line')) {
      appendConsoleLines(view, [{ seq: 0, text: r.reply }]); // SSE 断开时的兜底显示
    }
    if (r.action === 'stop') markStopped();
  } catch (err) {
    toast(err.message, 'err');
  }
}

// ═══════════════════════════ 10. 事件接线与启动 ═══════════════════════════

function closeTopLayer() {
  let closed = false;
  document.querySelectorAll('.modal-mask').forEach((m) => { if (!m.hidden) { m.hidden = true; closed = true; } });
  if (S.drawerOpen) { closeDrawer(); closed = true; }
  return closed;
}

function focusSearch() {
  const el = { bag: '#bagSearch', server: '#srvLoadPath', backup: '#exportPath', console: '#consoleCmdInput' }[S.tab];
  const target = (el && $(el)) || $('#accountSearch');
  if (target && target.focus) target.focus();
}

function wireStaticEvents() {
  document.querySelectorAll('.tab').forEach((t) => t.addEventListener('click', () => setTab(t.dataset.tab)));
  document.querySelectorAll('#zoneSwitch .zone-btn').forEach((b) => b.addEventListener('click', () => setZone(b.dataset.zone)));
  $('#saveBtn').addEventListener('click', savePending);
  $('#pendingSave').addEventListener('click', savePending);
  $('#pendingClear').addEventListener('click', clearPending);
  $('#pendingBtn').addEventListener('click', () => (S.drawerOpen ? closeDrawer() : openDrawer()));
  $('#drawerClose').addEventListener('click', closeDrawer);
  $('#drawerMask').addEventListener('click', closeDrawer);
  $('#refreshBtn').addEventListener('click', () => { loadAccounts(); loadServer(); });
  $('#accountSearch').addEventListener('input', (e) => { S.accountQuery = e.target.value; renderAccounts(); });
  $('#helpBtn').addEventListener('click', () => { $('#helpModal').hidden = false; });
  $('#themeBtn').addEventListener('click', () => applyTheme(S.theme === 'dark' ? 'light' : 'dark'));

  $('#itemPickAdd').addEventListener('click', () => {
    if (!S.pickedItem) return;
    if (S.pickedItem.unreleased) return toast('未实装武器不能发放（客户端缺模型/图标/技能行）', 'err');
    const count = Math.max(1, Math.trunc(Number($('#itemPickCount').value) || 1));
    stageAddItem(S.pickedItem.id, count);
    toast(`已加入待保存清单：${S.pickedItem.name} ×${count}`);
    $('#itemModal').hidden = true;
  });

  $('#stoppedRecheck').addEventListener('click', async () => {
    S.stopped = false;
    $('#stoppedMask').hidden = true;
    await Promise.all([loadServer(), loadAccounts()]);
    if (!S.pollTimer) S.pollTimer = setInterval(() => { loadServer(); loadAccounts(); }, 30000);
    renderTab();
  });

  document.querySelectorAll('.stepper button').forEach((b) => b.addEventListener('click', () => {
    const inp = $('#itemPickCount');
    inp.value = Math.max(1, (Number(inp.value) || 1) + Number(b.dataset.step));
  }));

  // [data-close] 的关闭按钮可能是动态渲染的（角色弹窗整体重绘），必须用事件委托
  document.addEventListener('click', (e) => {
    const btn = e.target.closest ? e.target.closest('[data-close]') : null;
    if (btn) $(`#${btn.dataset.close}`).hidden = true;
  });

  document.querySelectorAll('.modal-mask').forEach((mask) => mask.addEventListener('click', (e) => {
    if (e.target === mask) mask.hidden = true;
  }));

  document.addEventListener('keydown', (e) => {
    if (!e || !e.key) return;
    if (e.key === 'Escape') { closeTopLayer(); return; }
    if ((e.ctrlKey || e.metaKey) && (e.key === 's' || e.key === 'S')) {
      e.preventDefault();
      savePending();
      return;
    }
    const tag = e.target && e.target.tagName ? String(e.target.tagName).toLowerCase() : '';
    const typing = tag === 'input' || tag === 'textarea' || (e.target && e.target.isContentEditable);
    if (e.key === '/' && !typing) {
      e.preventDefault();
      focusSearch();
    }
  });
}

// 启动
(async () => {
  initTheme();
  wireStaticEvents();
  renderPending();
  await loadCatalog().catch(() => {});
  await Promise.all([loadServer(), loadAccounts()]);
  // 标签栏一直可见：「服务器管理」区不依赖存档，没选玩家也能停服/备份/导入。
  $('#tabs').hidden = false;
  S.pollTimer = setInterval(() => { loadServer(); loadAccounts(); }, 30000);
})();
