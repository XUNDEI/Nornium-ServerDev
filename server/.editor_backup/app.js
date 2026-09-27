/* 失乐星图 · 存档编辑器前端
 * 数据流：GET 拉取档案 → 本地渲染；所有编辑先 stage() 进「待保存清单」，
 * 点右上「保存修改」一次性 POST /editor/api/player/:id/update。
 * 在线玩家：服务端直接改内存 doc 并推送 ntf，游戏内立刻生效。 */
'use strict';

const S = {
  players: [],           // /accounts 列表
  catalog: null,         // /catalog（道具/武器/角色目录）
  id: null,              // 当前编辑的 account_id
  doc: null,             // 当前档案
  pending: [],           // 待保存操作
  tab: 'overview',
  bagFilter: 'all',
  bagSearch: '',
  catalogCat: 'all',
  pickedItem: null,
  server: null,          // /server 信息
  stopped: false,        // 服务端已被本页停掉（停止轮询 + 显示遮罩）
  pollTimer: null,
};

const $ = (sel) => document.querySelector(sel);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const fmt = (n) => Number(n || 0).toLocaleString('zh-CN');

const CURRENCIES = [
  { id: 9001, name: '金星贝', icon: '🐚' },
  { id: 9002, name: '诺伦炬', icon: '💎' },
  { id: 9003, name: '败者翼膜', icon: '🪶' },
  { id: 9004, name: '游历经验', icon: '📈' },
  { id: 9005, name: '抽卡银币', icon: '🎟️' },
  { id: 9006, name: '抽卡金币', icon: '🎫' },
  { id: 9007, name: '诺伦透镜', icon: '🔭' },
  { id: 9008, name: '家具币', icon: '🛋️' },
];
const WTYPE = ['', '巨刃', '长剑', '佩刀', '枪械', '礼器', '宝轮', '浮塔'];
const POOL_NAMES = { 1: '角色UP池', 2: '武器UP池', 3: '常驻池', 4: '新手池' };

// ------------------------------------------------------------ API / toast

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
      <div class="modal-head"><h3>${esc(title)}</h3>
        <button class="icon-btn" id="cfClose">✕</button></div>
      <div style="font-size:13px;line-height:2">${body}</div>
      ${need ? `<div class="field" style="margin-top:14px">
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

// ------------------------------------------------------------ 名称查询

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

// ------------------------------------------------------------ 等级 ↔ 经验
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

// ------------------------------------------------------------ 待保存清单

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

function renderPending() {
  $('#pendingCount').textContent = S.pending.length;
  $('#saveBtn').disabled = S.pending.length === 0;
  $('#saveBtn').classList.toggle('pulse', S.pending.length > 0);
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
    else toast(data.live ? '✅ 已保存，游戏内即时生效' : '✅ 已保存，玩家重新登录后生效', 'ok');
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

// ------------------------------------------------------------ 加载

async function loadAccounts() {
  try {
    const data = await api('/editor/api/accounts');
    S.players = data.players;
    renderAccounts();
  } catch (err) { toast(err.message, 'err'); }
}

async function loadServer() {
  if (S.stopped) return;
  try {
    const d = await api('/editor/api/server');
    S.server = d;
    $('#serverDot').classList.add('on');
    $('#serverStatus').textContent = `服务端运行中 · 在线 ${d.online}`;
    $('#serverMeta').innerHTML = `${d.stats.accounts} 个账号 · ${d.stats.players} 个档案`;
  } catch (_) {
    S.server = null;
    $('#serverStatus').textContent = '无法连接服务端';
    $('#serverDot').classList.remove('on');
  }
  if (S.tab === 'server') {
    // 30s 轮询会重绘服务页：别把用户正在输入的备份路径冲掉
    const typed = $('#srvLoadPath') ? $('#srvLoadPath').value : '';
    renderTab();
    if (typed && $('#srvLoadPath')) $('#srvLoadPath').value = typed;
  }
}

// 服务端被本页停掉之后：停掉轮询、盖一层遮罩，避免每 30s 刷一串失败请求。
function markStopped() {
  S.stopped = true;
  S.server = null;
  if (S.pollTimer) { clearInterval(S.pollTimer); S.pollTimer = null; }
  $('#serverDot').classList.remove('on');
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

// ------------------------------------------------------------ 侧栏 / 头部

function renderAccounts() {
  const box = $('#accountList');
  if (!S.players.length) { box.innerHTML = '<div class="placeholder">还没有任何存档</div>'; return; }
  box.innerHTML = S.players.map((p) => `
    <div class="account ${p.account_id === S.id ? 'active' : ''}" data-id="${p.account_id}">
      <div class="a-name">${esc(p.player_name)} ${p.online ? '<span class="badge online">在线</span>' : ''}</div>
      <div class="a-sub"><span>${esc(p.account_name)}</span><span>角色 ${p.characters}</span><span>背包 ${p.bag_items}</span></div>
    </div>`).join('');
  box.querySelectorAll('.account').forEach((el) => el.addEventListener('click', () => selectPlayer(Number(el.dataset.id))));
}

async function selectPlayer(id) {
  if (!S.catalog) await loadCatalog();
  if (S.pending.length && id !== S.id) {
    if (!confirm('当前还有未保存的修改，切换存档将丢弃。继续？')) return;
    S.pending = []; renderPending();
  }
  try { await loadDoc(id); } catch (err) { toast(err.message, 'err'); }
}

function renderHeader() {
  const p = S.players.find((x) => x.account_id === S.id);
  $('#playerName').textContent = S.doc?.player?.player_name || `档案 ${S.id}`;
  $('#playerBadges').innerHTML = p ? `
    <span class="badge ${p.online ? 'online' : ''}">${p.online ? '● 在线 · 修改即时生效' : '离线 · 保存后需重新登录'}</span>
    <span class="badge">账号 ${esc(p.account_name)}</span>` : '';
  $('#tabs').hidden = false;
}

// ------------------------------------------------------------ 标签页

function setTab(tab) {
  S.tab = tab;
  document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === tab));
  renderTab();
}

function renderTab() {
  const el = $('#content');
  // 「服务」页不依赖任何存档，没选玩家也能用（停服/备份/踢人都不需要先选档）。
  if (S.tab !== 'server' && !S.doc) {
    el.innerHTML = `<div class="empty-hint"><div class="empty-icon">🚀</div>
      <p>从左侧选择一个玩家存档开始编辑<br><span class="dim">在线玩家的修改即时生效，无需重新登录</span></p></div>`;
    return;
  }
  const render = {
    overview: renderOverview, bag: renderBag, chars: renderChars, gacha: renderGacha,
    mall: renderMall, plot: renderPlot, backup: renderBackup, server: renderServer,
  }[S.tab];
  el.innerHTML = '';
  // 服务页是 async（要拉快照列表）；渲染期的异常不要变成 unhandled rejection
  const ret = render(el);
  if (ret && typeof ret.catch === 'function') ret.catch((err) => toast(`页面渲染失败：${err.message}`, 'err'));
  el.scrollTop = 0;
}

// ══════════ 总览 ══════════

function renderOverview(el) {
  const doc = S.doc;
  const wrap = document.createElement('div');
  wrap.innerHTML = `
    <div class="card">
      <h3>🧑‍🚀 玩家信息</h3>
      <div class="row" style="display:flex;gap:14px;align-items:end;max-width:420px">
        <div class="field" style="flex:1"><label>玩家昵称</label>
          <input type="text" id="playerNameInput" value="${esc(doc.player.player_name)}" maxlength="20"></div>
        <button class="btn" id="renameBtn">改名</button>
      </div>
      <p class="dim" style="font-size:12px;margin-top:8px">注册时间：${new Date(Number(doc.player.register_seconds) * 1000).toLocaleString('zh-CN')}</p>
    </div>
    <div class="card">
      <h3>💰 货币 <span class="hint">直接改数字，保存后生效</span></h3>
      <div class="grid cur">
        ${CURRENCIES.map((c) => {
          const cur = doc.bag.items.find((it) => it.item_id === c.id);
          return `<div class="field"><label>${c.icon} ${c.name} <span class="dim">(${c.id})</span></label>
            <input type="number" min="0" data-currency="${c.id}" value="${cur ? cur.count : 0}"></div>`;
        }).join('')}
      </div>
    </div>`;
  el.appendChild(wrap);

  $('#renameBtn').addEventListener('click', () => {
    const name = $('#playerNameInput').value.trim();
    if (!name) return toast('昵称不能为空', 'err');
    stage({ op: 'set_player_name', name });
    toast('已加入待保存清单');
  });
  el.querySelectorAll('input[data-currency]').forEach((inp) => {
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
  ['ticket', '抽卡券'], ['use', '消耗品'], ['furn', '家具'], ['weapon', '武器'],
];
const MATERIAL_SUBTYPE = { 2: '材料', 3: '角色经验', 4: '武器经验', 5: '装备经验', 6: '角色卡', 7: '消耗品', 8: '蓝图', 9: '锻造蓝图' };
const TICKETS = [1200001, 1200002, 1201001, 1201003];

function bagCatOf(entry) {
  if (catWeapon(entry.item_id)) return 'weapon'; // 武器不在 d_bag_item 表里，先查武器表
  const info = catItem(entry.item_id) || {};
  if (info.item_type === 90) return 'cur';
  if (TICKETS.includes(Number(entry.item_id))) return 'ticket';
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
  const wrap = document.createElement('div');
  wrap.innerHTML = `
    <div class="bag-toolbar">
      <input class="search" id="bagSearch" placeholder="搜索背包道具…" value="${esc(S.bagSearch)}">
      <div class="chips">${BAG_CATS.map(([v, n]) => `<span class="chip ${S.bagFilter === v ? 'active' : ''}" data-cat="${v}">${n}</span>`).join('')}</div>
      <button class="btn primary small" id="addItemBtn" style="margin-left:auto">＋ 添加道具</button>
    </div>
    <div class="bag-list" id="bagList"></div>`;
  el.appendChild(wrap);

  const renderList = () => {
    const q = S.bagSearch.trim().toLowerCase();
    const rows = S.doc.bag.items
      .map((it) => ({ it, cat: bagCatOf(it) }))
      .filter((r) => S.bagFilter === 'all' || r.cat === S.bagFilter)
      .filter((r) => !q || itemName(r.it.item_id).toLowerCase().includes(q) || String(r.it.item_id).includes(q))
      .sort((a, b) => (catItem(a.it.item_id)?.item_type || 0) - (catItem(b.it.item_id)?.item_type || 0) || a.it.item_id - b.it.item_id);
    $('#bagList').innerHTML = rows.length ? rows.map(({ it, cat }) => {
      const icon = { cur: '💰', exp: '📈', break: '🧱', ticket: '🎫', use: '🧪', furn: '🛋️', weapon: '⚔️' }[cat] || '📦';
      const wcfg = cat === 'weapon' ? catWeapon(it.item_id) : null;
      if (wcfg && it.weapon_info) {
        // 武器：等级/突破/光淬都能直接改（背包里躺着的也行，不只是身上那把）
        const wi = it.weapon_info;
        const bt = Math.max(0, Math.trunc(Number(wi.break_times) || 0));
        const cap = capForBreak(bt);
        const lv = Math.min(cap, levelForExp(weaponExpArr(it.item_id), wi.exp));
        const maxR = wcfg.max_refine ?? 4;
        return `<div class="bag-row">
          <div class="b-icon">${icon}</div>
          <div class="b-name"><div class="n"><span class="r${wcfg.rarity}">${wcfg.rarity}★</span> ${esc(itemName(it.item_id))}
            ${wcfg.released === false ? '<span class="chip-warn">未实装</span>' : ''}</div>
            <div class="s">ID ${it.item_id} · ${WTYPE[wcfg.sub_type] || ''} 武器 · uuid ${it.item_uuid} · 经验 ${fmt(wi.exp)}</div></div>
          <div class="wstats">
            <label>光淬</label><input type="number" min="0" max="${maxR}" data-refine="${it.item_uuid}" value="${wi.refine_level || 0}">
            <label>等级</label><input type="number" min="1" max="${cap}" data-wlevel="${it.item_uuid}" value="${lv}">
            <label>突破</label><input type="number" min="0" max="${maxBreak()}" data-wbreak="${it.item_uuid}" value="${bt}">
            <span class="cap">上限 Lv.${cap}</span>
          </div>
          <button class="btn danger small" data-del="${it.item_uuid}">删除</button>
        </div>`;
      }
      const sub = MATERIAL_SUBTYPE[Number(catItem(it.item_id)?.sub_type)] || `类型 ${catItem(it.item_id)?.item_type ?? '?'}`;
      return `<div class="bag-row">
        <div class="b-icon">${icon}</div>
        <div class="b-name"><div class="n"><span class="r${itemRarity(it.item_id)}">${itemRarity(it.item_id)}★</span> ${esc(itemName(it.item_id))}</div>
          <div class="s">ID ${it.item_id} · ${sub} · uuid ${it.item_uuid}</div></div>
        <input class="count" type="number" min="0" data-uuid="${it.item_uuid}" value="${it.count}">
        <button class="btn danger small" data-del="${it.item_uuid}">删除</button>
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
  wrap.querySelectorAll('.chip').forEach((ch) => ch.addEventListener('click', () => {
    S.bagFilter = ch.dataset.cat;
    wrap.querySelectorAll('.chip').forEach((c) => c.classList.toggle('active', c === ch));
    renderList();
  }));
  $('#addItemBtn').addEventListener('click', openItemModal);
}

// ══════════ 添加道具弹窗 ══════════

const CATALOG_CATS = [['all', '全部'], ['cur', '货币'], ['mat', '材料'], ['use', '消耗品'], ['furn', '家具'], ['weapon', '武器']];

function catalogRows() {
  const rows = [];
  for (const it of S.catalog.items) {
    const cat = it.item_type === 90 ? 'cur' : it.item_type === 12 ? 'mat' : it.item_type === 20 ? 'use' : 'mat';
    rows.push({ ...it, cat, kindLabel: { cur: '货币', mat: '材料', use: '消耗品' }[cat] || `类型 ${it.item_type}` });
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
  cats.innerHTML = CATALOG_CATS.map(([v, n]) => `<span class="chip ${v === 'all' ? 'active' : ''}" data-ccat="${v}">${n}</span>`).join('');
  S.catalogCat = 'all';
  cats.querySelectorAll('.chip').forEach((ch) => ch.addEventListener('click', () => {
    S.catalogCat = ch.dataset.ccat;
    cats.querySelectorAll('.chip').forEach((c) => c.classList.toggle('active', c === ch));
    renderCatalog();
  }));

  const renderCatalog = () => {
    const q = $('#catalogSearch').value.trim().toLowerCase();
    const rows = catalogRows()
      .filter((r) => S.catalogCat === 'all' || r.cat === S.catalogCat)
      .filter((r) => !q || r.name.toLowerCase().includes(q) || String(r.id).includes(q))
      .slice(0, 300);
    $('#catalogList').innerHTML = rows.length ? rows.map((r) => `
      <div class="cat-row ${S.pickedItem?.id === r.id ? 'selected' : ''}" data-cid="${r.id}">
        <span class="r${r.rarity || 0}">${r.rarity || '·'}</span>
        <span>${esc(r.name)}</span>
        <span class="dim" style="font-size:11px">${esc(r.kindLabel)}</span>
        ${r.unreleased ? '<span class="chip-warn">未实装</span>' : ''}
        <span class="id">${r.id}</span>
      </div>`).join('') : '<div class="placeholder">没有匹配的道具</div>';
    $('#catalogList').querySelectorAll('.cat-row').forEach((row) => row.addEventListener('click', () => {
      S.pickedItem = rows.find((r) => r.id === Number(row.dataset.cid));
      $('#catalogList').querySelectorAll('.cat-row').forEach((r) => r.classList.toggle('selected', r === row));
      $('#itemPickFoot').hidden = false;
      $('#itemPickName').innerHTML = `已选：<b>${esc(S.pickedItem.name)}</b> <span class="dim">(${S.pickedItem.id})</span>`
        + (S.pickedItem.unreleased
          ? '<br><span class="chip-warn">未实装武器</span> <span class="dim" style="font-size:12px">'
            + '客户端没有模型/图标/技能行，发下去会让武器详情面板崩，不能发放</span>'
          : '');
      $('#itemPickAdd').disabled = !!S.pickedItem.unreleased;
    }));
  };
  renderCatalog();
  $('#catalogSearch').oninput = renderCatalog;
}

$('#itemPickAdd').addEventListener('click', () => {
  if (!S.pickedItem) return;
  if (S.pickedItem.unreleased) return toast('未实装武器不能发放（客户端缺模型/图标/技能行）', 'err');
  const count = Math.max(1, Math.trunc(Number($('#itemPickCount').value) || 1));
  stageAddItem(S.pickedItem.id, count);
  toast(`已加入待保存清单：${S.pickedItem.name} ×${count}`);
  $('#itemModal').hidden = true;
});

// ══════════ 角色 ══════════

function renderChars(el) {
  const owned = new Map(S.doc.characters.map((c) => [c.character_id, c]));
  const wrap = document.createElement('div');
  wrap.innerHTML = `
    <div class="chars-actions">
      <button class="btn" id="addAllChars">＋ 一键添加全部角色</button>
      <button class="btn" id="grantAllWeapons">⚔️ 发放全部高稀有度武器</button>
      <label class="dim" style="font-size:12px;align-self:center;display:flex;gap:6px;align-items:center">
        <input type="checkbox" id="grantSkipOwned" checked> 跳过已拥有的</label>
      <span class="dim" style="font-size:12px;align-self:center">＝ 已实装的 6★/7★ 武器每种各一把（数据表里没有「角色→专武」关联，不再按类型猜）</span>
    </div>
    <div class="grid chars">
      ${S.catalog.characters.map((c) => {
        const o = owned.get(c.id);
        const wn = o?.weapon_info ? catWeapon(o.weapon_info.item_id) : null;
        const cap = capForBreak(o?.break_times);
        const lv = o ? Math.min(cap, levelForExp(roleExpArr(), o.exp)) : 0;
        return `<div class="char-card ${o ? '' : 'not-owned'}" data-char="${c.id}">
          <div class="c-name">${esc(c.name)} ${o ? '' : '<span class="badge">未拥有</span>'}</div>
          <div class="c-sub">${o
            ? `Lv.${lv}（上限 ${cap}） · 突破 ${o.break_times}<br>武器：${wn ? esc(wn.name) : '无'}</div>`
            : `武器类型：${WTYPE[c.profession]}</div>`}
          <div class="c-tags">
            <span class="wtype">${WTYPE[c.profession]}</span>
            ${wn ? `<span class="r${wn.rarity}">${wn.rarity}★</span>` : ''}
          </div>
        </div>`;
      }).join('')}
    </div>`;
  el.appendChild(wrap);

  $('#addAllChars').addEventListener('click', () => { stage({ op: 'add_all_characters' }); toast('已加入待保存清单'); });
  $('#grantAllWeapons').addEventListener('click', () => {
    stage({ op: 'grant_high_rarity_weapons', skip_owned: $('#grantSkipOwned').checked });
    toast('已加入待保存清单');
  });
  wrap.querySelectorAll('.char-card').forEach((card) => card.addEventListener('click', () => {
    openCharModal(Number(card.dataset.char));
  }));
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
    return `
    <div class="modal-head"><h3>${esc(c.name)} <span class="dim" style="font-size:12px">${WTYPE[c.profession]}</span></h3>
      <button class="icon-btn" data-close="charModal">✕</button></div>
    <div class="char-detail">
      <div class="row">
        <div class="field"><label>等级（上限 ${cap}）</label>
          <input type="number" min="1" max="${cap}" id="cLevel" value="${lv}"></div>
        <div class="field"><label>突破次数（0-${maxBreak()}）</label>
          <input type="number" min="0" max="${maxBreak()}" id="cBreak" value="${bt}"></div>
        <div class="field"><label>经验（由等级反推，可手改）</label>
          <input type="number" min="0" id="cExp" value="${owned.exp}"></div>
      </div>
      ${w ? `
      <div class="weapon-box">
        <h4>⚔️ 已装备武器：${esc(wcfg?.name || w.item_id)}
          <span class="r${wcfg?.rarity}">${wcfg?.rarity}★</span></h4>
        <div class="row">
          <div class="field"><label>等级（上限 ${wcap}）</label>
            <input type="number" min="1" max="${wcap}" id="wLevel" value="${wlv}"></div>
          <div class="field"><label>突破（0-${maxBreak()}）</label>
            <input type="number" min="0" max="${maxBreak()}" id="wBreak" value="${wbt}"></div>
          <div class="field"><label>光淬（0-${wcfg?.max_refine ?? 4}）</label>
            <input type="number" min="0" max="${wcfg?.max_refine ?? 4}" id="wRefine" value="${w.weapon_info.refine_level || 0}"></div>
          <div class="field"><label>经验（由等级反推，可手改）</label>
            <input type="number" min="0" id="wExp" value="${w.weapon_info.exp}"></div>
        </div>
      </div>` : '<p class="dim" style="font-size:12px">该角色没有装备武器</p>'}
      ${best ? `<p class="dim" style="font-size:12px">同类型推荐武器（最高稀有度且已实装）：${esc(wName)}（${best}）</p>` : ''}
      <div class="modal-foot">
        ${best ? `<button class="btn" id="grantOne" style="margin-right:auto">⚔️ 发放该武器</button>` : ''}
        <button class="btn primary" id="charSave">加入待保存清单</button>
      </div>
    </div>`;
  })() : `
    <div class="modal-head"><h3>${esc(c.name)} <span class="badge">未拥有</span></h3>
      <button class="icon-btn" data-close="charModal">✕</button></div>
    <p class="dim" style="font-size:13px">武器类型：${WTYPE[c.profession]}。添加后自带初始武器与技能。</p>
    <div class="modal-foot">
      ${best ? `<button class="btn" id="grantOne" style="margin-right:auto">⚔️ 发放推荐武器</button>` : ''}
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
  const wrap = document.createElement('div');
  wrap.innerHTML = `
    <div class="card">
      <h3>🎰 抽卡保底 <span class="hint">no_up_times = 距上次 UP 六星的累计抽数，保存后需重新登录</span></h3>
      <div class="grid cur">
        ${keys.map((k) => {
          const st = infos[k] || {};
          return `<div class="field"><label>${POOL_NAMES[k] || `池 ${k}`} · 累计 ${fmt(st.total_times || 0)} 抽</label>
            <input type="number" min="0" data-pool="${k}" value="${st.no_up_times || 0}"></div>`;
        }).join('')}
      </div>
    </div>`;
  el.appendChild(wrap);
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
  const wrap = document.createElement('div');
  wrap.innerHTML = `
    <div class="card">
      <h3>💳 累充积分 <span class="hint">改完即可在累充奖励页领取对应档位</span></h3>
      <div class="row" style="display:flex;gap:14px;align-items:end;max-width:360px">
        <div class="field" style="flex:1"><label>当前积分：${fmt(m.charge_point)}</label>
          <input type="number" min="0" id="chargeInput" value="${m.charge_point}"></div>
        <button class="btn" id="chargeBtn">设置</button>
      </div>
    </div>
    <div class="card">
      <h3>🌙 月卡 <span class="hint">${active ? `到期：${new Date(expire * 1000).toLocaleString('zh-CN')}` : '未持有'}</span></h3>
      <div class="row" style="display:flex;gap:10px;align-items:end;max-width:520px">
        <div class="field" style="flex:1"><label>延长天数</label><input type="number" min="0" id="monthDays" value="30"></div>
        <button class="btn" id="monthAdd">延长</button>
        <button class="btn danger" id="monthClear">清空月卡</button>
      </div>
      <p class="dim" style="font-size:12px;margin-top:10px">每日奖励游标会一并重置，保存后当天即可领取。</p>
    </div>`;
  el.appendChild(wrap);
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
  const wrap = document.createElement('div');
  wrap.innerHTML = `
    <div class="card">
      <h3>📖 主线进度 <span class="hint">只读展示 · 任务进度由游戏内行为驱动，直接改易破坏任务链</span></h3>
      <div class="kv">
        <span class="k">剧情树 ID</span><span class="v">${p.plot_tree_id ?? 0}　节点 ${p.plot_node_id ?? 0}</span>
        <span class="k">进行中任务</span><span class="v">${missions.length} 个</span>
        <span class="k">已完成任务</span><span class="v">${(p.completed_mission_ids || []).length} 个</span>
        <span class="k">已解锁故事线</span><span class="v">${(p.unlocked_story_line_ids || []).length} 条</span>
      </div>
    </div>
    ${missions.length ? `
    <div class="card">
      <h3>🎯 进行中的任务</h3>
      <div class="kv">${missions.slice(0, 40).map((mm) => `<span class="k">任务 ${mm.mission_id ?? mm}</span><span class="v dim">计数 ${mm.count ?? 0}</span>`).join('')}</div>
    </div>` : ''}`;
  el.appendChild(wrap);
}

// ══════════ 备份 ══════════

async function renderBackup(el) {
  const wrap = document.createElement('div');
  wrap.innerHTML = `
    <div class="card">
      <h3>📤 导出当前存档 <span class="hint">导出会短暂踢下线在线玩家（保证快照一致）</span></h3>
      <div class="row" style="display:flex;gap:14px;align-items:end;max-width:560px">
        <div class="field" style="flex:1"><label>目标目录（留空 = 默认备份位置）</label>
          <input type="text" id="exportPath" placeholder="例如 D:\\Nornium_backup"></div>
        <button class="btn primary" id="exportBtn">导出</button>
      </div>
    </div>
    <div class="card">
      <h3>🗄️ 历史快照（server 目录旁的 data_* 文件夹）</h3>
      <div id="backupList"><div class="placeholder">加载中…</div></div>
    </div>`;
  el.appendChild(wrap);

  $('#exportBtn').addEventListener('click', async () => {
    const p = $('#exportPath').value.trim();
    try {
      const d = await api('/editor/api/export', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(p ? { path: p } : {}),
      });
      toast(`✅ 已导出到 ${d.dir}（${d.players} 个档案）`);
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

  if (!d) {
    wrap.innerHTML = `<div class="card"><h3>🔌 无法连接服务端</h3>
      <p class="dim" style="font-size:13px">服务端可能已经停止，或本页不是由它提供的。
      重新启动请双击仓库根目录的 <b>点我启动.bat</b>。</p>
      <div class="modal-foot" style="justify-content:flex-start">
        <button class="btn" id="srvRecheck">重新检测</button></div></div>`;
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

  wrap.innerHTML = `
    <div class="card">
      <h3>🖥️ 服务端状态 <span class="hint">v${esc(d.version)}</span></h3>
      <div class="stat-grid">
        <div class="stat"><div class="k">在线连接</div><div class="v">${d.online}</div></div>
        <div class="stat"><div class="k">运行时长</div><div class="v">${fmtUptime(d.uptime_seconds)}</div></div>
        <div class="stat"><div class="k">账号 / 档案</div><div class="v">${d.stats.accounts} / ${d.stats.players}</div></div>
        <div class="stat"><div class="k">端口（TCP 游戏 / HTTP 门）</div><div class="v">${d.tcp_port ?? '?'} / ${d.http_port ?? '?'}</div></div>
        <div class="stat"><div class="k">存档目录</div><div class="v small">${esc(d.data_dir)}</div></div>
        <div class="stat"><div class="k">历史快照</div><div class="v">${d.backups}</div></div>
      </div>
    </div>

    <div class="card">
      <h3>🧰 日常操作</h3>
      <div class="actions">
        <button class="btn" id="srvBackup">💾 立即备份一份</button>
        <button class="btn" id="srvKick">🚪 踢出所有在线玩家</button>
        <button class="btn" id="srvReload">🔄 刷新状态</button>
      </div>
      <p class="dim" style="font-size:12px;margin-top:12px">
        备份落在 <code>server\data_manual_&lt;时间戳&gt;\</code>；踢人后玩家重新登录即可（存档不受影响）。</p>
    </div>

    <div class="card">
      <h3>📥 从快照导入存档 <span class="hint">会短暂踢下线在线玩家，保证换档期间没有旧会话回写</span></h3>
      <div class="row" style="display:flex;gap:10px;align-items:end;max-width:760px;flex-wrap:wrap">
        <div class="field" style="flex:1;min-width:280px"><label>快照 / 备份目录</label>
          <input type="text" id="srvLoadPath" list="srvBackupList" placeholder="data_wipe_20260925-143000 或 D:\\Nornium_backup"></div>
        <button class="btn primary" id="srvLoad">导入并热重载</button>
      </div>
      <datalist id="srvBackupList">${backups.map((b) => `<option value="${esc(b.path)}">${esc(b.name)}</option>`).join('')}</datalist>
      <p class="dim" style="font-size:12px;margin-top:12px">
        覆盖式导入：只覆盖备份里有的文件，不会删除当前存档里多出来的档案；导入前会自动留一份 <code>data_preimport_*</code>。</p>
    </div>

    <div class="card danger-zone">
      <h3>⚠️ 危险操作</h3>
      <div class="actions">
        <button class="btn danger" id="srvRestore">🗑️ 清空全部存档</button>
        <button class="btn danger" id="srvStop">⏻ 停止服务端</button>
      </div>
      <p class="dim" style="font-size:12px;margin-top:12px">
        <b>清空存档</b>：删掉 <code>data\accounts.json</code> + 全部玩家档案（删前自动留一份 <code>data_wipe_*</code> 快照），
        服务端继续运行，下一位注册的就是全新档案。<br>
        <b>停止服务端</b>：踢出所有在线玩家并结束进程，游戏与编辑器都会离线；重启请双击 <b>点我启动.bat</b>。</p>
    </div>`;
  el.appendChild(wrap);

  $('#srvBackup').addEventListener('click', async () => {
    try {
      const r = await api('/editor/api/server/backup', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
      toast(`✅ 已备份到 ${r.dir}（${r.players} 个档案）`);
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
      toast(`✅ 已导入 ${r.players} 个档案${r.accounts ? '（含账号表）' : ''}`);
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
      confirmText: '停服',
      okLabel: '停止服务端',
      danger: true,
    })) return;
    try {
      await api('/editor/api/server/stop', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
    } catch (_) { /* 服务端可能已经先断了，忽略 */ }
    markStopped();
  });
}

// ------------------------------------------------------------ 事件接线
document.querySelectorAll('.tab').forEach((t) => t.addEventListener('click', () => setTab(t.dataset.tab)));
$('#saveBtn').addEventListener('click', savePending);
$('#refreshBtn').addEventListener('click', () => { loadAccounts(); loadServer(); });
$('#stoppedRecheck').addEventListener('click', async () => {
  S.stopped = false;
  $('#stoppedMask').hidden = true;
  await Promise.all([loadServer(), loadAccounts()]);
  if (!S.pollTimer) S.pollTimer = setInterval(() => { loadServer(); loadAccounts(); }, 30000);
  renderTab();
});

// [data-close] 的关闭按钮可能是动态渲染的（角色弹窗整体重绘），必须用事件委托
document.addEventListener('click', (e) => {
  const btn = e.target.closest('[data-close]');
  if (btn) $(`#${btn.dataset.close}`).hidden = true;
});
document.querySelectorAll('.modal-mask').forEach((mask) => mask.addEventListener('click', (e) => {
  if (e.target === mask) mask.hidden = true;
}));

$('#itemPickCount') && null;
document.querySelectorAll('.stepper button').forEach((b) => b.addEventListener('click', () => {
  const inp = $('#itemPickCount');
  inp.value = Math.max(1, (Number(inp.value) || 1) + Number(b.dataset.step));
}));

// 启动
(async () => {
  await loadCatalog().catch(() => {});
  await Promise.all([loadServer(), loadAccounts()]);
  // 标签栏一直可见：「服务」页不依赖存档，没选玩家也能停服/备份/导入。
  $('#tabs').hidden = false;
  S.pollTimer = setInterval(() => { loadServer(); loadAccounts(); }, 30000);
})();
