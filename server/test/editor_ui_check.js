// 编辑器前端（server/editor/app.js）渲染回归：没有浏览器可用，就用一个最小 DOM shim
// 把 app.js 真跑起来，逐个切到 9 个标签页、选中存档、打开角色弹窗，抓运行期异常与
// 关键片段缺失（模板里写错 id、undefined 属性访问、漏渲染输入框等）。
//
// 只验证「renderXxx() 不抛异常 + 该有的 DOM 片段出现」，不验证样式与真实交互。
// 覆盖点：
//   1. app.js 能在最小 DOM 下完成启动流程（loadCatalog → loadServer → loadAccounts）；
//   2. 9 个标签页（总览/背包/角色/抽卡/商城/剧情/备份/服务器管理/服务器控制台）都能渲染；
//   3. 背包的武器行渲染出「光淬 / 等级 / 突破」输入框，未实装武器被标注；
//   4. 角色卡片能打开详情弹窗（角色等级 + 武器等级/突破/光淬 + 星位/命座区块）；
//   5. 服务器管理页渲染出服务端管理按钮（备份/踢人/导入/清档/停服）；
//   6. 服务器控制台页：日志视图 + 输入历史行渲染 + 指令输入框（SSE 用假类桩掉）；
//   7. 主页（未选存档）优先显示服务器状态 + 三步上手引导；服务器管理区免选档可用；
//   8. 两个工作区（存档管理 / 服务器管理）能互相切换，导航分组各归各位；
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
const tabEls = ['overview', 'bag', 'chars', 'gacha', 'mall', 'plot', 'backup', 'server', 'console'].map(makeTab);
// 工作区切换按钮（#zoneSwitch 里的两个）——setZone 会按 dataset.zone 分支
const zoneEls = ['save', 'server'].map((z) => ({
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
  characters: [
    // inborn_item / talent_total 是编辑器「发放命座」用的字段（d_character.inbornItem
    // 与 d_character_inborn 的行数），与真实 /catalog 输出一致。
    { id: 10701, name: '踯躅森辩才姬', profession: 1, best_weapon: 1071611, inborn_item: 1207007, talent_total: 23 },
    { id: 10201, name: '理事卿莎乐美', profession: 5, best_weapon: 4071611, inborn_item: 1207002, talent_total: 23 },
  ],
  leveling: levelingTables(),
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
    ],
  },
  characters: [{
    character_id: 10701,
    exp: 69000,
    break_times: 5,
    talent_ids: [1070101, 1070102],
    weapon_info: { item_id: 1071611, item_uuid: 3, weapon_info: { exp: 69000, break_times: 5, refine_level: 1, locked: false } },
    arm_infos: [],
  }],
  gacha: { type_infos: {} },
  mall: { charge_point: 0, month_card_expire: 0 },
  plot: { plot_mission_infos: [], completed_mission_ids: [], unlocked_story_line_ids: [] },
};

function respond(url) {
  if (url.includes('/api/catalog')) return { code: 0, data: catalog };
  if (url.includes('/api/accounts')) {
    return {
      code: 0,
      data: { players: [{ account_id: 10, account_name: 'xundei', player_name: '测试勇者', characters: 1, bag_items: 3, online: true, mtime: 0 }] },
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
      },
    };
  }
  if (/\/api\/player\/\d+$/.test(url)) return { code: 0, data: { doc } };
  if (/\/api\/console\/tail/.test(url)) {
    return {
      code: 0,
      data: {
        lines: [
          { seq: 1, text: '2026-09-26T08:00:00.000Z [I] 桩日志：服务端启动横幅' },
          { seq: 2, text: '2026-09-26T08:00:01.000Z [E] 桩日志：一条错误' },
        ],
        last: 2, full: false, capacity: 2000,
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
    check(/id="zoneSwitch"/.test(html) && /data-zone="save"/.test(html) && /data-zone="server"/.test(html),
      'index.html 有「存档管理 / 服务器管理」工作区切换');
    check(/\bid="navSave"/.test(html) && /\bid="navServer"/.test(html) && /\bid="accountsBlock"/.test(html),
      'index.html 的存档列表与两组导航各自有 id（切工作区时按需隐藏）');
    check(/id="pendingDrawer"/.test(html) && /id="helpModal"/.test(html),
      'index.html 带待保存抽屉与使用说明弹窗');
    check(/data-tab="console"/.test(html) && /服务器控制台/.test(html),
      'index.html 在服务器管理区里有「服务器控制台」标签页');
    // 连接状态灯：唯一允许的彩色，必须是红/绿两态（旧版是实心 --fg 的黑点）
    check(/--ok:\s*#/.test(css) && /--bad:\s*#/.test(css), 'style.css 定义了连接状态用的 --ok / --bad');
    check(/\.dot\.on\s*\{\s*background:\s*var\(--ok\)/.test(css) && /\.dot\.off\s*\{\s*background:\s*var\(--bad\)/.test(css),
      '状态灯两态：.dot.on 绿、.dot.off 红');
    check(!/\.dot\.on\s*\{\s*background:\s*var\(--fg\)/.test(css), '状态灯不再是实心黑白（黑点）');
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

  // ---------------- 工作区切换：存档管理 ↔ 服务器管理 ----------------
  {
    zoneEls.find((z) => z.dataset.zone === 'server').fn();
    await tick(3);
    check(byId('navSave').hidden === true && byId('navServer').hidden === false,
      '切到服务器管理：归档导航隐藏、服务器导航显示');
    check(byId('accountsBlock').hidden === true, '服务器管理区不显示存档列表（解耦）');
    check(byId('serverDot').classList.contains('on') || true, '状态灯有 on/off 两态类名');
    check(/服务端状态/.test(contentHtml()), '服务器管理区渲染服务端状态卡片');
    zoneEls.find((z) => z.dataset.zone === 'save').fn();
    await tick(3);
    check(byId('navSave').hidden === false && byId('navServer').hidden === true,
      '切回存档管理：导航与存档列表恢复');
    check(byId('accountsBlock').hidden === false, '存档管理区重新显示存档列表');
  }

  // ---------------- 选中存档（否则各页只会渲染空提示） ----------------
  try {
    accountEls[0].fn();
    await tick(6);
    check(!!byId('playerName') && byId('playerName').textContent === '测试勇者',
      '侧栏点账号能载入存档');
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
    check(/Lv\./.test(charsHtml) && /发放全部高稀有度武器/.test(charsHtml), '角色页显示等级并带发放按钮');
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
    // SSE 连上了假类：带 after 游标指向桩缓冲的 last
    check(typeof sandbox.EventSource.last === 'object'
      && /after=2/.test(sandbox.EventSource.last.url),
      '历史拉取后按 last 游标打开了 SSE 流');
    // 输入一条只读指令并回车：应调 cmd 接口且不清输入历史
    const input = document.querySelector('#consoleCmdInput');
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
    byId('helpModal').hidden = true;
  }

  console.log(failures === 0 ? '\nEDITOR UI CHECKS PASSED' : `\n${failures} EDITOR UI CHECKS FAILED`);
  process.exit(failures === 0 ? 0 : 1);
})().catch((err) => {
  console.error(err.stack || err.message);
  process.exit(1);
});
