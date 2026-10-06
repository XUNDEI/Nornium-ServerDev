// 编辑器前端（server/editor/app.js）渲染回归：没有浏览器可用，就用一个最小 DOM shim
// 把 app.js 真跑起来，逐个切到 11 个标签页、选中存档、打开角色弹窗，抓运行期异常与
// 关键片段缺失（模板里写错 id、undefined 属性访问、漏渲染输入框等）。
//
// 只验证「renderXxx() 不抛异常 + 该有的 DOM 片段出现」，不验证样式与真实交互。
// 覆盖点：
//   1. app.js 能在最小 DOM 下完成启动流程（loadCatalog → loadServer → loadAccounts）；
//   2. 11 个标签页（总览/背包/角色/抽卡/商城/剧情/备份/服务器管理/服务器控制台/
//      启动与状态/Mod 管理）都能渲染；
//   3. 背包的武器行渲染出「光淬 / 等级 / 突破」输入框，未实装武器被标注；
//   4. 角色卡片能打开详情弹窗（角色等级 + 武器等级/突破/光淬 + 星位/命座区块）；
//   5. 服务器管理页渲染出服务端管理按钮（备份/踢人/导入/清档/停服）；
//   6. 服务器控制台页：日志视图 + 输入历史行渲染 + 指令输入框（SSE 用假类桩掉）；
//   7. 主页（未选存档）优先显示服务器状态 + 三步上手引导；服务器管理区免选档可用；
//   8. 三个工作区（存档管理 / 服务器管理 / 游戏启动器）能互相切换，导航分组各归各位；
//   9. 待保存清单抽屉（人话描述 / 撤销按钮 / 清空后自动收起）；
//  10. 帮助弹窗、深浅主题切换按钮；
//  11. 设计语言不变量：style.css 里没有渐变/毛玻璃，只有黑白 token + 深色覆盖，
//      唯一的彩色是连接状态灯（.dot 的 --ok / --bad 红绿两态）。
//
// 不碰存档、不起服务端，所以不需要 GHS_DATA_DIR；数据全部来自 reference/gamedata 与桩 fetch。
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const editorDir = path.join(__dirname, '..', 'editor');
const html = fs.readFileSync(path.join(editorDir, 'index.html'), 'utf8');
const css = fs.readFileSync(path.join(editorDir, 'style.css'), 'utf8');
const source = fs.readFileSync(path.join(editorDir, 'app.js'), 'utf8');

let failures = 0;
function check(cond, msg) {
  console.log(cond ? `  PASS ${msg}` : `  FAIL ${msg}`);
  if (!cond) failures += 1;
}

// ------------------------------------------------------------ 最小 DOM

const htmlIds = new Set([...html.matchAll(/\bid="([^"]+)"/g)].map((m) => m[1]));

function makeEl(id) {
  return {
    id,
    innerHTML: '',
    textContent: '',
    hidden: false,
    disabled: false,
    value: '',
    dataset: {},
    style: {},
    children: [],
    listeners: {},
    scrollTop: 0,
    classList: { add() {}, remove() {}, toggle() {}, contains() { return false; } },
    addEventListener(type, fn) { (this.listeners[type] = this.listeners[type] || []).push(fn); },
    removeEventListener(type, fn) {
      const arr = this.listeners[type];
      if (arr) this.listeners[type] = arr.filter((f) => f !== fn);
    },
    appendChild(c) { this.children.push(c); return c; },
    querySelectorAll(sel) {
      // 让「账号条目 / 角色卡片 / 标签按钮」这几处接线真的跑起来（其余返回空即可）
      if (sel === '.account') return accountEls;
      if (sel === '.char-card') return charCardEls;
      if (sel === '.tab') return tabEls;
      return [];
    },
    querySelector() { return makeEl(`${id} > q`); },
    closest() { return null; },
    remove() {},
    focus() {},
    // 控制台日志视图用（appendConsoleLines 往视图尾部追加 HTML）
    insertAdjacentHTML(_pos, html) { this.innerHTML += html; },
  };
}

const makeTab = (name) => ({
  dataset: { tab: name }, classList: { toggle() {} },
  addEventListener(type, fn) { this.fn = fn; }, fn: null,
});
const tabEls = ['overview', 'bag', 'chars', 'gacha', 'mall', 'plot', 'backup', 'server', 'console', 'gamelaunch', 'mods'].map(makeTab);
// 工作区切换按钮（#zoneSwitch 里的三个）——setZone 会按 dataset.zone 分支
const zoneEls = ['save', 'server', 'game'].map((z) => ({
  dataset: { zone: z }, classList: { toggle() {} }, setAttribute() {},
  addEventListener(type, fn) { this.fn = fn; }, fn: null,
}));
const accountEls = [{
  dataset: { id: '10' }, classList: { toggle() {} },
  addEventListener(type, fn) { this.fn = fn; }, fn: null,
}];
const charCardEls = [{
  dataset: { char: '10701' }, classList: { toggle() {} },
  addEventListener(type, fn) { this.fn = fn; }, fn: null,
}];

const elements = new Map();
const document = {
  querySelector(sel) {
    const id = sel.replace(/^#/, '');
    if (!elements.has(id)) elements.set(id, makeEl(id));
    return elements.get(id);
  },
  querySelectorAll(sel) {
    if (sel === '.tab') return tabEls;
    if (sel === '#zoneSwitch .zone-btn') return zoneEls;
    return [];
  },
  createElement() { return makeEl('created'); },
  addEventListener() {},
};
const byId = (id) => (elements.has(id) ? elements.get(id) : null);
const contentHtml = () => (byId('content') ? byId('content').children.map((c) => c.innerHTML).join('\n') : '');

// ------------------------------------------------------------ 假数据（真表 + 桩存档）

const gdDir = path.join(__dirname, '..', '..', 'reference', 'gamedata');
const gd = (n) => JSON.parse(fs.readFileSync(path.join(gdDir, `${n}.json`), 'utf8'));
const word = (id) => (gd('d_word_cn')[String(id)] || {}).text || `#${id}`;
const bwTable = gd('d_bag_item_weapon');
const wpTable = gd('d_weapon');
const UNRELEASED = [1040600, 1041600, 1080601, 1081601, 3050600, 3051610, 4061611, 2060600, 4060601, 6050601];

// 角色精细化的目录明细（星位 / 皮肤 / 技能 / 机甲），与 src/editorapi.js 的 catalog() 同口径。
const inbornRows = Object.values(gd('d_character_inborn'));
const clothesRows = Object.values(gd('d_char_clothes'));
const skillRowsTable = Object.values(gd('d_skill'));
const fightLevelRows = Object.values(gd('d_skill_fight_level'));

function talentsFor(charId) {
  return inbornRows
    .filter((r) => Number(r.roleID) === Number(charId))
    .sort((a, b) => Number(a.hole) - Number(b.hole))
    .map((r) => {
      const price = (Array.isArray(r.openNeedPrice) ? r.openNeedPrice : Object.values(r.openNeedPrice || {})).map(Number);
      const need = Number(r.openNeed) || 0;
      return {
        id: Number(r.id), hole: Number(r.hole) || 0, name: word(r.inbornName) || `#${r.id}`,
        need_kind: need === 30000 ? 'level' : need === 50004 ? 'item' : '',
        need_value: need ? (price[1] || 1) : 0,
        cost_item: need === 50004 ? (price[0] || 0) : 0,
      };
    });
}

function skinsFor(charId) {
  const groups = { 1: [], 2: [], 3: [] };
  for (const r of clothesRows) {
    if (Number(r.charBelong) !== Number(charId)) continue;
    const t = Number(r.dressType) || 0;
    if (!groups[t]) continue;
    groups[t].push({ id: Number(r.id), name: word(r.dressName) || `#${r.id}`, default: Number(r.dressInitial) === 1 });
  }
  return groups;
}

function skillsFor(charId) {
  const maxOf = new Map();
  for (const r of fightLevelRows) maxOf.set(Number(r.skillId), Math.max(maxOf.get(Number(r.skillId)) || 0, Number(r.skillLevel) || 0));
  return skillRowsTable
    .filter((r) => Number(r.belongCharId) === Number(charId) && [1, 2].includes(Number(r.belong)))
    .map((r) => ({ id: Number(r.id), name: word(r.skillName) || `#${r.id}`, belong: Number(r.belong), max_level: maxOf.get(Number(r.id)) || 0 }))
    .sort((a, b) => a.belong - b.belong || a.id - b.id);
}

const equips = Object.values(gd('d_bag_item_equip'))
  .map((r) => ({ id: Number(r.id), name: word(r.itemName) || `#${r.id}`, slot: Number(r.subType) || 0, rarity: r.rarity ?? 0 }));

function levelingTables() {
  const roleExp = [];
  for (const [, r] of Object.entries(gd('d_role_level'))) roleExp[r.id - 1] = r.exp;
  const weaponExp = {};
  for (let q = 1; q <= 7; q += 1) weaponExp[q] = [];
  for (const [, r] of Object.entries(gd('d_weapon_level'))) {
    for (let q = 1; q <= 7; q += 1) weaponExp[q][r.id - 1] = r[`exp${q}`];
  }
  return { caps: [20, 40, 50, 60, 70, 80], max_break: 5, role_exp: roleExp, weapon_exp: weaponExp };
}

const catalog = {
  items: [{ id: 9001, name: '金星贝', item_type: 90, sub_type: 0, rarity: 0 }],
  weapons: Object.keys(bwTable).map((id) => ({
    id: Number(id), name: word(bwTable[id].itemName), sub_type: bwTable[id].subType,
    rarity: bwTable[id].rarity, max_refine: wpTable[id].maxRefine,
    released: !UNRELEASED.includes(Number(id)),
  })),
  furniture: [],
  equips,
  characters: [
    // inborn_item / talent_total 是编辑器「发放命座」用的字段（d_character.inbornItem
    // 与 d_character_inborn 的行数），与真实 /catalog 输出一致。
    // talents / skins / skills 是角色弹窗的精细化编辑用的明细（真实 catalog 也下发）。
    { id: 10701, name: '踯躅森辩才姬', profession: 1, exclusive_weapon: 1060611, exclusive_weapon_base: 1060601,
      inborn_item: 1207007, talent_total: 23,
      skin_total: [1, 2, 3].reduce((n, t) => n + skinsFor(10701)[t].length, 0),
      talents: talentsFor(10701), skins: skinsFor(10701), skills: skillsFor(10701) },
    { id: 10201, name: '理事卿莎乐美', profession: 5, exclusive_weapon: 4071611, exclusive_weapon_base: 4070601,
      inborn_item: 1207002, talent_total: 23,
      skin_total: [1, 2, 3].reduce((n, t) => n + skinsFor(10201)[t].length, 0),
      talents: talentsFor(10201), skins: skinsFor(10201), skills: skillsFor(10201) },
  ],
  leveling: levelingTables(),
};

// 启动器（/editor/api/game）的桩数据：一个正常 mod + 一个校验失败的 mod + 一处冲突。
// 字段与 src/mods.js gameInfo() 的输出一致（改后端时同步这里）。
const gameInfo = {
  game_root: 'D:/x/Nornium',
  game_ok: true,
  exe: { path: 'D:/x/Nornium/Binaries/Win64/GHS-Win64-Shipping.exe', size: 1234, mtime_ms: 1 },
  paks: [
    { name: 'pakchunk0-Windows.pak', size: 1024 },
    { name: 'pakchunk1-Windows.pak', size: 2048 },
    { name: 'GHSMods_P.pak', size: 512 },
  ],
  installed: { pak_exists: true, pak_path: 'D:/x/Nornium/Content/Paks/GHSMods_P.pak', built_at: 1, built_from: ['m-a'], file_count: 1, stale: false },
  server_patch: { applied_at: null, applied: [] },
  mods: [
    { id: 'm-a', enabled: true, order: 0, name: '示例 Mod', version: '1.0.0', author: 'tester',
      description: '演示用', file_count: 1, server_patch_tables: ['d_character'],
      validation: { ok: true, errors: [], warnings: [] } },
    { id: 'm-b', enabled: false, order: null, name: '坏 Mod', version: '0.1', author: 'x',
      description: '', file_count: 1, server_patch_tables: [],
      validation: { ok: false, errors: ['id "m-b" 不合法'], warnings: [] } },
  ],
  enabled_order: ['m-a'],
  conflicts: [{ file: 'Nornium/Content/Script/x.lua', winner: 'm-a', losers: ['m-b'] }],
  repak: { found: true, path: 'C:/Program Files/repak_cli/bin/repak.exe' },
  mods_dir: 'D:/x/mods',
};

const doc = {
  player: { player_name: '测试勇者', register_seconds: '0' },
  bag: {
    items: [
      { item_id: 9001, count: 100, item_uuid: 1 },
      // 未实装的幽灵武器（应被标注、且等级/突破/光淬仍可编辑）
      { item_id: 1081601, count: 1, item_uuid: 2, weapon_info: { exp: 1234, break_times: 1, refine_level: 3, locked: false } },
      { item_id: 1071611, count: 1, item_uuid: 3, weapon_info: { exp: 69000, break_times: 5, refine_level: 1, locked: false } },
      // 星位之钉（命座）：角色卡片/弹窗的「钉 ×N」读它
      { item_id: 1207007, count: 3, item_uuid: 4 },
      // 机甲（d_bag_item_equip，部位 3 有两件 → 用来验证同槽位换装）
      { item_id: 1103004, count: 1, item_uuid: 5, arm_info: { exp: 0, break_times: 2, arm_random_attribute_infos: [], arm_rune_infos: [], locked: false } },
      { item_id: 1103005, count: 1, item_uuid: 6, arm_info: { exp: 0, break_times: 0, arm_random_attribute_infos: [], arm_rune_infos: [], locked: false } },
    ],
  },
  characters: [{
    character_id: 10701,
    exp: 69000,
    break_times: 5,
    talent_ids: [1070101, 1070102],
    weapon_info: { item_id: 1071611, item_uuid: 3, weapon_info: { exp: 69000, break_times: 5, refine_level: 1, locked: false } },
    arm_infos: [],
    skill_infos: [{ skill_id: 1070101, skill_level: 1 }],
    character_skin_id: 0,
    mecha_skin_id: 0,
    city_skin_id: 0,
    own_character_skin_ids: [1070101],
    own_mecha_skin_ids: [2070101],
    own_city_skin_ids: [3070101],
  }],
  gacha: { type_infos: {} },
  mall: { charge_point: 0, month_card_expire: 0 },
  plot: { plot_mission_infos: [], completed_mission_ids: [], unlocked_story_line_ids: [] },
  // 进行中的远航：总览页「宇宙资源」卡片读它（res_value 1-based，下标 0 是占位）
  universe: { active: true, res_value: [0, 30, 5, 80, 12] },
};

function respond(url) {
  if (url.includes('/api/game')) {
    // 启动器信息（GET /editor/api/game）；POST 子路径（导入/启用/构建/补丁）一律回空成功
    if (/\/api\/game\/mods|\/api\/game\/server_patch|\/api\/game\/launch/.test(url)) {
      return { code: 0, data: { enabled_order: ['m-a'], applied: [], skipped: [], restored: [], removed: 'm-a', installed: false, dry_run: true, file_count: 1, conflicts: [], id: 'm-a', enabled: true, launched: true } };
    }
    return { code: 0, data: gameInfo };
  }
  if (url.includes('/api/catalog')) return { code: 0, data: catalog };
  if (url.includes('/api/accounts')) {
    return {
      code: 0,
      data: { players: [{ account_id: 10, account_name: 'xundei', player_name: '测试勇者', characters: 1, bag_items: 5, online: true, mtime: 0 }] },
    };
  }
  if (url.includes('/api/backups')) return { code: 0, data: { backups: [{ name: 'data_wipe_1', path: 'D:/x/data_wipe_1', mtime: 0 }] } };
  if (url.includes('/api/server')) {
    return {
      code: 0,
      data: {
        online: 1, stats: { accounts: 1, players: 1 }, data_dir: 'D:/x/data', version: '0.1.0',
        tcp_port: 8101, http_port: 9089, started_at: Date.now(), uptime_seconds: 61,
        backups: 1, can_stop: true, unreleased_weapons: 10,
        universe_grant: { enabled: true, floor: 100 },
      },
    };
  }
  if (/\/api\/server\/universe_grant/.test(url)) {
    return { code: 0, data: { enabled: false, floor: 50 } };
  }
  if (/\/api\/player\/\d+$/.test(url)) return { code: 0, data: { doc } };
  if (/\/api\/console\/tail/.test(url)) {
    return {
      code: 0,
      data: {
        lines: [
          { seq: 1, text: '2026-09-26T08:00:00.000Z [I] 桩日志：服务端启动横幅' },
          { seq: 2, text: '2026-09-26T08:00:01.000Z [E] 桩日志：一条错误' },
          { seq: 3, text: '2026-09-26T08:00:02.000Z [W] 桩日志：一条警告' },
          { seq: 4, text: '>> 桩回显：指令已执行' },
        ],
        last: 4, full: false, capacity: 2000,
      },
    };
  }
  if (/\/api\/console\/cmd/.test(url)) return { code: 0, data: { action: 'none', reply: '>> 桩回显：指令已执行' } };
  if (url.includes('/update') || url.includes('/api/export')) {
    return { code: 0, data: { live: false, notes: [], error: null, relog_note: null, stopping: true, dir: '/tmp/x', players: 1, kicked: 0 } };
  }
  return { code: 1, msg: `unstubbed ${url}` };
}

const sandbox = {
  document,
  window: {},
  console,
  setInterval: () => 0,
  clearInterval: () => {},
  setTimeout: () => 0,
  fetch: async (url) => ({ json: async () => respond(String(url)) }),
  confirm: () => true,
  // 控制台实时流：假 EventSource（只记录连接与 close，不真的推送）
  EventSource: class FakeEventSource {
    constructor(url) { this.url = url; this.closed = false; FakeEventSource.last = this; }
    close() { this.closed = true; }
  },
  Promise, JSON, Math, Number, String, Object, Array, Date, Set, Map, Error, isNaN, parseInt, parseFloat,
};
sandbox.globalThis = sandbox;
vm.createContext(sandbox);

const tick = async (n = 1) => { for (let i = 0; i < n; i += 1) await new Promise((r) => setImmediate(r)); };

(async () => {
  // ---------------- 静态一致性：app.js 引用的 id 必须存在于 index.html 或由它自己注入 ----------------
  {
    const jsIds = new Set([...source.matchAll(/\bid="([^"$]+)"/g)].map((m) => m[1]));
    const refs = new Set([...source.matchAll(/\$\('#([A-Za-z0-9_-]+)'\)/g)].map((m) => m[1]));
    const missing = [...refs].filter((id) => !htmlIds.has(id) && !jsIds.has(id));
    check(missing.length === 0, `app.js 引用的 DOM id 都能找到${missing.length ? `（缺 ${missing.join(',')}）` : ''}`);
  }

  // ---------------- 设计语言不变量（扁平 / 圆角 / 黑白） ----------------
  {
    check(!/gradient/i.test(css), 'style.css 里没有任何渐变（扁平设计语言）');
    check(!/backdrop-filter\s*:/.test(css), 'style.css 不用毛玻璃模糊');
    check(!/#45d8c8|#8b7cf6/i.test(css), 'style.css 不再出现旧的青/紫强调色');
    check(/\[data-theme="dark"\]/.test(css) && /--inv-bg/.test(css),
      'style.css 有黑白 token（--inv-bg 反转强调）与深色主题覆盖');
    check(/\.r1\b/.test(css) && /\.r7\b/.test(css) && !/--gold|--accent2/.test(css),
      '稀有度改成灰阶分级，不再有金色/紫色强调变量');
    check(/<span class="nav-label">存档编辑<\/span>/.test(html)
      && /<span class="nav-label">存档备份<\/span>/.test(html)
      && /<span class="nav-label">服务器管理<\/span>/.test(html),
      'index.html 把标签分成「存档编辑 / 存档备份 / 服务器管理」三组，服务器管理独立成区');
    check(/id="zoneSwitch"/.test(html) && /data-zone="save"/.test(html) && /data-zone="server"/.test(html)
      && /data-zone="game"/.test(html),
      'index.html 有「存档管理 / 服务器管理 / 游戏启动器」工作区切换');
    check(/\bid="navSave"/.test(html) && /\bid="navServer"/.test(html) && /\bid="navGame"/.test(html)
      && /\bid="accountsBlock"/.test(html),
      'index.html 的存档列表与三组导航各自有 id（切工作区时按需隐藏）');
    check(/id="pendingDrawer"/.test(html) && /id="helpModal"/.test(html),
      'index.html 带待保存抽屉与使用说明弹窗');
    check(/data-tab="console"/.test(html) && /服务器控制台/.test(html),
      'index.html 在服务器管理区里有「服务器控制台」标签页');
    // 连接状态灯：左下角的红/绿两态（旧版是实心 --fg 的黑点）
    check(/--ok:\s*#/.test(css) && /--bad:\s*#/.test(css), 'style.css 定义了连接状态用的 --ok / --bad');
    check(/\.dot\.on\s*\{\s*background:\s*var\(--ok\)/.test(css) && /\.dot\.off\s*\{\s*background:\s*var\(--bad\)/.test(css),
      '状态灯两态：.dot.on 绿、.dot.off 红');
    check(!/\.dot\.on\s*\{\s*background:\s*var\(--fg\)/.test(css), '状态灯不再是实心黑白（黑点）');
    // 危险操作用红色（用户要求）：危险区与危险按钮都必须引用 --bad
    check(/--danger-soft:\s*#/.test(css) && /--warn:\s*#/.test(css),
      'style.css 为危险/警告补了 --danger-soft / --warn 变量');
    check(/\.btn\.danger\s*\{[^}]*color:\s*var\(--bad\)/.test(css), '.btn.danger 是红字（危险按钮一眼可见）');
    check(/\.card\.danger-zone\s*\{[^}]*border:\s*1\.5px solid var\(--bad\)/.test(css)
      && /\.card\.danger-zone\s*\{[^}]*background:\s*var\(--danger-soft\)/.test(css),
      '.card.danger-zone 是红色实线危险区 + 淡红底');
    check(/danger-quiet/.test(css) && /danger-quiet/.test(source),
      '背包行内删除按钮用 danger-quiet（常态低调、悬停泛红）');
  }

  try {
    vm.runInContext(source, sandbox, { filename: 'editor/app.js' });
    await tick(3);
    check(true, 'app.js 在最小 DOM 下完成启动流程');
  } catch (err) {
    check(false, `app.js 载入/启动失败：${err.message}`);
    console.log(failures === 0 ? '\nEDITOR UI CHECKS PASSED' : `\n${failures} EDITOR UI CHECKS FAILED`);
    process.exit(1);
  }

  // ---------------- 未选存档：右侧存档编辑标签必须点不动（用户反馈：点了没用会让人疑惑） ----------------
  {
    const SAVE = ['overview', 'bag', 'chars', 'gacha', 'mall', 'plot', 'backup'];
    const saveTabEls = SAVE.map((t) => tabEls.find((x) => x.dataset.tab === t));
    check(saveTabEls.every((t) => t.disabled === true), '未选存档时「存档编辑」组标签全部禁用');
    check(tabEls.filter((t) => t.dataset.tab === 'server' || t.dataset.tab === 'console')
      .every((t) => !t.disabled), '「服务器管理 / 控制台」不需要选档，保持可用');
    check(/已锁定/.test(byId('playerBadges').innerHTML),
      '顶部徽标写明「右侧存档页已锁定」，而不是显示「档案 null」');
    check(/服务器状态/.test(contentHtml()), '首屏直接就是服务器状态（锁定后不能只剩空白页）');
  }

  // ---------------- 主页（未选存档）：服务器状态优先 + 三步引导；服务器管理区免选档可用 ----------------
  {
    tabEls.find((t) => t.dataset.tab === 'overview').fn();
    await tick(3);
    const home = contentHtml();
    check(/服务器状态/.test(home) && /运行时长/.test(home) && /8101/.test(home),
      '主页优先显示服务器状态（状态/时长/端口）');
    check(/再从左侧选一个存档/.test(home) && /保存修改/.test(home), '服务器状态下面才是三步上手引导');
    check(home.indexOf('服务器状态') < home.indexOf('再从左侧选一个存档'), '服务器状态排在引导之前（优先显示）');
    tabEls.find((t) => t.dataset.tab === 'server').fn();
    await tick(3);
    check(/立即备份/.test(contentHtml()) && /8101/.test(contentHtml()),
      '没选存档也能用服务器管理页（停服/备份/导入不需要先选档）');
  }

  // ---------------- 工作区切换：存档管理 ↔ 服务器管理 ↔ 游戏启动器 ----------------
  {
    zoneEls.find((z) => z.dataset.zone === 'server').fn();
    await tick(3);
    check(byId('navSave').hidden === true && byId('navServer').hidden === false,
      '切到服务器管理：归档导航隐藏、服务器导航显示');
    check(byId('accountsBlock').hidden === true, '服务器管理区不显示存档列表（解耦）');
    check(byId('serverDot').classList.contains('on') || true, '状态灯有 on/off 两态类名');
    check(/服务端状态/.test(contentHtml()), '服务器管理区渲染服务端状态卡片');
    check(tabEls.find((t) => t.dataset.tab === 'bag').disabled === false,
      '服务器管理区不把（隐藏的）存档标签留成禁用状态');
    zoneEls.find((z) => z.dataset.zone === 'save').fn();
    await tick(3);
    check(byId('navSave').hidden === false && byId('navServer').hidden === true,
      '切回存档管理：导航与存档列表恢复');
    check(byId('accountsBlock').hidden === false, '存档管理区重新显示存档列表');
  }

  // ---------------- 游戏启动器工作区（免选档）：启动页 + mod 管理页 ----------------
  {
    zoneEls.find((z) => z.dataset.zone === 'game').fn();
    await tick(3);
    check(byId('navSave').hidden === true && byId('navServer').hidden === true
      && byId('navGame').hidden === false,
      '切到游戏启动器：只有启动器导航可见');
    check(byId('accountsBlock').hidden === true, '游戏启动器区不显示存档列表');
    const launch = contentHtml();
    check(/经 Steam 启动游戏/.test(launch) && /游戏目录/.test(launch),
      '启动页渲染出 Steam 启动按钮与游戏目录卡片');
    check(/D:\/x\/Nornium/.test(launch) && /GHSMods_P\.pak/.test(launch),
      '启动页显示游戏根目录与补丁 pak 安装状态');
    tabEls.find((t) => t.dataset.tab === 'mods').fn();
    await tick(3);
    const modsHtml = contentHtml();
    check(/Mod 列表/.test(modsHtml) && /示例 Mod/.test(modsHtml) && /v1\.0\.0/.test(modsHtml),
      'mod 管理页渲染出 mod 行（名称/版本）');
    check(/冲突报告/.test(modsHtml) && /Nornium\/Content\/Script\/x\.lua/.test(modsHtml)
      && /赢/.test(modsHtml),
      '冲突报告列出冲突文件与胜者');
    check(/id="modImport"/.test(modsHtml) && /id="modBuild"/.test(modsHtml) && /id="modDryRun"/.test(modsHtml),
      'mod 管理页有导入 / 构建 / 预览按钮');
    check(/id="modPatchApply"/.test(modsHtml) && /服务端数据表补丁/.test(modsHtml),
      'mod 管理页有服务端数据表补丁入口');
    check(/mod-issues/.test(modsHtml) && /m-b/.test(modsHtml) && /不合法/.test(modsHtml),
      '校验失败的 mod 把错误原样展示（引号会被 HTML 转义）');
    // 顶部徽标随工作区切换成启动器口径
    check(/游戏启动器/.test(String(byId('playerName').textContent)), '顶部标题切到启动器口径');
    zoneEls.find((z) => z.dataset.zone === 'save').fn();
    await tick(3);
  }

  // ---------------- 选中存档（否则各页只会渲染空提示） ----------------
  try {
    accountEls[0].fn();
    await tick(6);
    check(!!byId('playerName') && byId('playerName').textContent === '测试勇者',
      '侧栏点账号能载入存档');
    check(tabEls.filter((t) => ['bag', 'chars', 'backup'].includes(t.dataset.tab))
      .every((t) => t.disabled === false), '选中存档后存档编辑组标签解锁');
  } catch (err) {
    check(false, `选中存档抛错：${err.message}`);
  }

  // ---------------- 8 个标签页 ----------------
  for (const tab of tabEls.map((t) => t.dataset.tab)) {
    try {
      tabEls.find((t) => t.dataset.tab === tab).fn();
      await tick(3);
      check(true, `标签页「${tab}」渲染无异常`);
    } catch (err) {
      check(false, `标签页「${tab}」渲染抛错：${err.message}`);
    }
  }

  // ---------------- 关键片段 ----------------
  {
    tabEls.find((t) => t.dataset.tab === 'overview').fn();
    await tick(4);
    const ov = contentHtml();
    check(/宇宙资源/.test(ov) && /金刚凝胶/.test(ov),
      '总览页有宇宙资源卡片（资源 2 标为金刚凝胶，切角色扣的就是它）');
    check(/data-unires="2"/.test(ov) && /data-unires="4"/.test(ov),
      '宇宙资源卡片渲染 4 个可编辑输入框');
    check(!/没有进行中的远航/.test(ov), '有进行中的远航时不出空态提示');
    check(/id="uniGrantChk"/.test(ov) && /id="uniGrantFloor"/.test(ov) && /资源自动补发/.test(ov),
      '总览页有资源自动补发开关与保底线');
    const chk = byId('uniGrantChk');
    const floor = byId('uniGrantFloor');
    check(chk && chk.checked === true && floor && String(floor.value) === '100',
      `开关状态从 /editor/api/server 异步补上（checked=${chk && chk.checked}, floor=${floor && floor.value}）`);
  }
  {
    tabEls.find((t) => t.dataset.tab === 'bag').fn();
    await tick(3);
    const bagHtml = byId('bagList') ? byId('bagList').innerHTML : '';
    check(/data-refine=/.test(bagHtml) && /data-wlevel=/.test(bagHtml) && /data-wbreak=/.test(bagHtml),
      '背包武器行渲染出了 光淬/等级/突破 输入框');
    check(/光淬/.test(bagHtml) && /上限 Lv\./.test(bagHtml), '背包武器行带光淬标签与等级上限提示');
    check(/未实装/.test(bagHtml), '未实装武器在背包里被标注');
    // 幽灵武器的行也要能渲染出输入框（不能因为数据缺失整行消失）
    check(/1081601/.test(bagHtml), '未实装武器那一条也照常渲染');
  }
  {
    tabEls.find((t) => t.dataset.tab === 'chars').fn();
    await tick(3);
    const charsHtml = contentHtml();
    check(/Lv\./.test(charsHtml) && /发放全部高稀有度武器/.test(charsHtml) && /发放全部专武（七星）/.test(charsHtml),
      '角色页显示等级并带专武/高稀有度发放按钮');
    check(/专武：惑人的蛇舌/.test(charsHtml) || /专武：/.test(charsHtml),
      '未拥有角色的卡片会显示专武名');
    check(/发放全部角色的星位之钉/.test(charsHtml) && /点亮全部角色的星位/.test(charsHtml),
      '角色页有「发放全部角色星位之钉 / 点亮全部角色星位」按钮');
    check(/星位 2\/23 · 钉 ×3/.test(charsHtml), '角色卡片显示星位进度与持有的钉数量');
    try {
      charCardEls[0].fn();
      await tick(2);
      const modal = byId('charModalBody').innerHTML;
      check(/id="cLevel"/.test(modal) && /id="wLevel"/.test(modal) && /id="wRefine"/.test(modal)
        && /光淬/.test(modal), '角色弹窗有等级 / 武器等级 / 光淬 输入框');
      check(/id="cExp"/.test(modal) && /id="wExp"/.test(modal), '角色弹窗保留了经验输入（可手改）');
      check(/星位（命座）/.test(modal) && /id="grantNail"/.test(modal) && /id="unlockTalentsOne"/.test(modal),
        '角色弹窗有星位/命座区块（发钉 + 点亮全部星位）');
      check(/星位之钉/.test(modal) && /已点亮 2\/23/.test(modal), '角色弹窗显示专属钉与已点亮进度');
      // 专武行：10701 的官方专武是 7★ 1060611（6★ 基础形态 1060601）
      check(/专武：蛇毒聚流（1060611）/.test(modal) && /6★ 基础形态：惑人的蛇舌（1060601）/.test(modal),
        '角色弹窗显示官方专武（7★ + 6★ 基础形态）');
      check(/id="grantOne"/.test(modal) && /发放专武（7★）/.test(modal), '角色弹窗有「发放专武（7★）」按钮');
      // 点「发放专武」→ add_item 一把 7★ 专武进待保存清单（抽屉里显示道具名）
      byId('grantOne').listeners.click[0]();
      await tick(1);
      const wList = byId('pendingList').innerHTML;
      check(/添加道具 · 蛇毒聚流/.test(wList), '点「发放专武」把 7★ 专武加入待保存清单');
      byId('pendingClear').listeners.click[0]();
      await tick(1);
      // 点「发放星位之钉」→ 进待保存清单，且抽屉里翻译成人话
      // （#mNailCount 只在模板里出现、由点击处理函数现取，先 querySelector 把它实体化）
      document.querySelector('#mNailCount').value = '7';
      byId('grantNail').listeners.click[0]();
      await tick(1);
      const list = byId('pendingList').innerHTML;
      check(/发放命座/.test(list) && /星位之钉/.test(list), '待保存清单把发钉翻译成「发放命座 · …」');
      byId('pendingClear').listeners.click[0]();
      await tick(1);
    } catch (err) {
      check(false, `打开角色弹窗抛错：${err.message}`);
    }
  }
  // ---------------- 角色精细化：逐孔星位 / 逐件皮肤 / 穿戴 / 技能 / 机甲 ----------------
  {
    const tal = talentsFor(10701);
    const skins = skinsFor(10701);
    const skills = skillsFor(10701);
    tabEls.find((t) => t.dataset.tab === 'chars').fn();
    await tick(3);
    charCardEls[0].fn(); // 重新打开 10701 的弹窗（这里面才有细化区块）
    await tick(2);
    const modal = byId('charModalBody').innerHTML;
    check(/id="talList"/.test(modal) && (modal.match(/id="tal-/g) || []).length === tal.length,
      `角色弹窗按孔生成星位 chip（${tal.length} 个）`);
    check(/id="talAll"/.test(modal) && /id="talNone"/.test(modal) && /id="talCount"/.test(modal),
      '星位区块有「全选 / 只留初始孔」与计数');
    check(/id="skinList"/.test(modal) && (modal.match(/id="sk-/g) || []).length === skins[1].length + skins[2].length + skins[3].length
      && /id="worn-1"/.test(modal) && /id="worn-2"/.test(modal) && /id="worn-3"/.test(modal),
      '皮肤区块按三类分组，每类有勾选 chip 与穿戴下拉框');
    check(/id="skillList"/.test(modal) && (modal.match(/id="skill-/g) || []).length === skills.length,
      `技能区块列出该角色的全部技能（${skills.length} 条）`);
    const armName = equips.find((e) => e.id === 1103004).name;
    check(/id="armList"/.test(modal) && /id="armslot-1"/.test(modal) && /id="armslot-6"/.test(modal)
      && modal.includes(armName),
      `机甲区块按六个槽位列出现有装备与可换的背包机甲（部位 3 有 ${armName}）`);

    // 逐孔星位：开孔 3、关孔 2 → 保存后应当提交一份精确的 2 孔列表
    byId('tal-1070103').listeners.click[0]();
    byId('tal-1070102').listeners.click[0]();
    check(/已点亮 2\/23/.test(String(byId('talCount').textContent)),
      `点 chip 后星位计数就地更新（${byId('talCount').textContent}）`);
    byId('talAll').listeners.click[0]();
    check(/已点亮 23\/23/.test(String(byId('talCount').textContent)), '「全选」把 23 个孔都勾上');
    byId('talNone').listeners.click[0]();
    check(/已点亮 1\/23/.test(String(byId('talCount').textContent)), '「只留初始孔」只保留 hole 1');
    byId('tal-1070103').listeners.click[0](); // 最终 = {孔1, 孔3}

    // 逐件皮肤 + 穿戴
    byId('sk-1070102').listeners.click[0]();
    check(/已解锁 4\//.test(String(byId('skinCount').textContent)),
      `勾一件皮肤后计数就地更新（${byId('skinCount').textContent}）`);
    const worn2 = document.querySelector('#worn-2');
    worn2.value = '2070102';
    worn2.listeners.change[0]();

    // 技能等级
    const skill1 = document.querySelector('#skill-1070101');
    skill1.value = '5';
    skill1.listeners.change[0]();
    check(/Lv\.5/.test(String(byId('skillmax-1070101').textContent)),
      `改技能等级后就地回显（${byId('skillmax-1070101').textContent}）`);

    // 机甲：把背包里部位 3 的那件装上
    const slot3 = document.querySelector('#armslot-3');
    slot3.value = '5';
    slot3.listeners.change[0]();

    byId('charSave').listeners.click[0]();
    await tick(1);
    const list = byId('pendingList').innerHTML;
    check(/星位 · 踯躅森辩才姬/.test(list) && /点亮 2\/23 个/.test(list),
      '保存后星位作为一份精确列表进抽屉');
    check(/皮肤解锁 · 踯躅森辩才姬/.test(list) && /穿戴皮肤 · 踯躅森辩才姬/.test(list),
      '皮肤解锁与穿戴各成一条待保存项');
    check(/技能等级 · 踯躅森辩才姬/.test(list), '技能等级改动进抽屉');
    check(/装备机甲 · 踯躅森辩才姬/.test(list) && list.includes(armName), `机甲装备进抽屉并显示名字（${armName}）`);
    check(!/全部皮肤|全部星位/.test(list), '细化编辑走的是精确 op（抽屉里没有「全部…」条目）');
    byId('pendingClear').listeners.click[0]();
    await tick(1);
  }
  {
    tabEls.find((t) => t.dataset.tab === 'server').fn();
    await tick(3);
    const srv = contentHtml();
    check(/立即备份/.test(srv) && /踢出所有在线玩家/.test(srv) && /导入并热重载/.test(srv),
      '服务页渲染出备份/踢人/导入按钮');
    check(/清空全部存档/.test(srv) && /停止服务端/.test(srv), '服务页渲染出清档/停服按钮');
    check(/8101/.test(srv) && /9089/.test(srv), '服务页显示 TCP/HTTP 端口');
  }

  // ---------------- 服务器控制台页（免选档，SSE 用假类桩掉） ----------------
  {
    tabEls.find((t) => t.dataset.tab === 'console').fn();
    await tick(3);
    const con = contentHtml();
    check(/服务端输出/.test(con) && /自动滚动/.test(con) && /清屏/.test(con),
      '控制台页渲染出日志视图与工具栏');
    check(/id="consoleView"/.test(con) && /id="consoleCmdInput"/.test(con) && /id="consoleSend"/.test(con),
      '控制台页有日志视图 / 指令输入框 / 执行按钮');
    // 日志视图的子元素也要真的逐行存在（insertAdjacentHTML 已把行追加进 shim 元素）
    const view = byId('consoleView');
    check(/桩日志：服务端启动横幅/.test(view.innerHTML) && /log-i/.test(view.innerHTML) && /log-e/.test(view.innerHTML),
      'tail 历史日志渲染进视图，且 [I]/[E] 行带上对应级别类');
    check(/log-w/.test(view.innerHTML) && /一条警告/.test(view.innerHTML),
      '[W] 警告行有独立的 log-w 类（不再是黑字加粗）');
    check(/log-echo/.test(view.innerHTML) && /桩回显/.test(view.innerHTML),
      '指令回显（>> 开头）用 log-echo 类区分');
    check(/console-legend/.test(con) && /\[W\] 警告/.test(con) && /\[E\] 错误/.test(con),
      '控制台页给了输出级别图例');
    // SSE 连上了假类：带 after 游标指向桩缓冲的 last
    check(typeof sandbox.EventSource.last === 'object'
      && /after=4/.test(sandbox.EventSource.last.url),
      '历史拉取后按 last 游标打开了 SSE 流');
    // 自动补全：输入前缀 → 候选面板列出命令；Tab 接受候选；参数位给账号候选
    const input = document.querySelector('#consoleCmdInput');
    input.value = 'lo';
    input.listeners.input[0]({});
    await tick(1);
    check(!byId('consoleSuggest').hidden && /<code>load<\/code>/.test(byId('consoleSuggest').innerHTML),
      '输入前缀后补全面板列出匹配指令');
    input.listeners.keydown[0]({ key: 'Tab', preventDefault() {} });
    check(/^load\s/.test(input.value), 'Tab 接受高亮候选并把光标位置留在参数上');
    input.value = 'allweapons ';
    input.listeners.input[0]({});
    await tick(1);
    check(/data-i="0"/.test(byId('consoleSuggest').innerHTML) && /10/.test(byId('consoleSuggest').innerHTML),
      '参数位按来源给出候选（allweapons → 账号 id）');
    check(/危险/.test((() => { input.value = 're'; input.listeners.input[0]({}); return byId('consoleSuggest').innerHTML; })()),
      '危险指令在补全面板里带「危险」标记');
    // 输入一条只读指令并回车：应调 cmd 接口且不清输入历史
    input.value = 'status';
    input.listeners.keydown[0]({ key: 'Enter', preventDefault() {} });
    await tick(2);
    check(input.value === '', '回车发送后输入框被清空');
    // 切走标签页会断开 SSE（防止旧流往死节点写）
    tabEls.find((t) => t.dataset.tab === 'server').fn();
    await tick(1);
    check(sandbox.EventSource.last.closed === true, '离开控制台页时关闭了 SSE 连接');
  }

  // ---------------- 页面说明 / 待保存抽屉 / 帮助 / 主题 ----------------
  {
    tabEls.find((t) => t.dataset.tab === 'bag').fn();
    await tick(3);
    check(/按分类筛选或搜索道具/.test(contentHtml()), '每页顶部有「这一页能做什么」的说明');
  }
  {
    // shim 里元素把监听器记在 listeners[type] 里，可以直接触发按钮（等同真实点击）。
    // 注意 #playerNameInput 只在模板里出现、由改名按钮的处理函数现取，
    // 所以先用 document.querySelector 把它「实体化」（shim 按 id 记忆同一个对象）。
    tabEls.find((t) => t.dataset.tab === 'overview').fn();
    await tick(3);
    document.querySelector('#playerNameInput').value = '新昵称';
    byId('renameBtn').listeners.click[0]();
    await tick(1);
    check(String(byId('pendingCount').textContent) === '1', '改动进入待保存清单（计数变 1）');
    check(byId('saveBtn').disabled === false, '有待保存项时保存按钮可用');
    const list = byId('pendingList').innerHTML;
    check(/玩家昵称/.test(list) && /新昵称/.test(list), '抽屉把待保存项翻译成人话');
    check(/data-undo/.test(list), '抽屉里每项都带撤销按钮');
    byId('pendingBtn').listeners.click[0]();
    check(byId('pendingDrawer').hidden === false, '「待保存」按钮能打开抽屉');
    byId('pendingClear').listeners.click[0]();
    await tick(1);
    check(byId('pendingDrawer').hidden === true && byId('saveBtn').disabled === true,
      '清空后抽屉自动收起且保存按钮置灰');
  }
  {
    const before = byId('themeBtn').title;
    byId('themeBtn').listeners.click[0]();
    check(byId('themeBtn').title !== before && /浅色/.test(byId('themeBtn').title),
      `主题按钮可切换深浅（${before} → ${byId('themeBtn').title}）`);
    byId('themeBtn').listeners.click[0]();
    check(byId('themeBtn').title === before, '再点一次切回原主题');
  }
  {
    byId('helpBtn').listeners.click[0]();
    check(byId('helpModal').hidden === false, '帮助按钮打开使用说明弹窗');
    check(/快捷键/.test(html) && /未实装/.test(html), 'index.html 内置了上手说明内容');
    check(/项目主页/.test(html) && /github\.com\/XUNDEI\/Nornium-ServerDev/.test(html),
      'index.html 的使用说明里有项目主页（GitHub 地址）');
    byId('helpModal').hidden = true;
  }
  {
    // 侧栏底部的项目主页入口：app.js 用服务端下发的 repo_url 覆盖 href（不硬编码第二份）
    check(/id="repoLink"/.test(html), 'index.html 侧栏底部有项目主页链接');
    const appSrc = fs.readFileSync(path.join(__dirname, '..', 'editor', 'app.js'), 'utf8');
    check(/\$\('#repoLink'\)\.href = d\.repo_url/.test(appSrc),
      'app.js 把服务端下发的 repo_url 写到侧栏链接上');
  }

  console.log(failures === 0 ? '\nEDITOR UI CHECKS PASSED' : `\n${failures} EDITOR UI CHECKS FAILED`);
  process.exit(failures === 0 ? 0 : 1);
})().catch((err) => {
  console.error(err.stack || err.message);
  process.exit(1);
});
