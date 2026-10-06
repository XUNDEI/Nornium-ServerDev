// 启动器 · Mod 仓库与安装管线（「游戏」工作区的后端）。
//
// Mod 格式（详见 docs/MOD_FORMAT.md）：
//   mods/<mod_id>/
//     mod.json          元信息 { id, name, version, author, description? }
//     files/            按 pak 内路径镜像（Nornium/Content/...）
//     server_patch/     可选：d_xxx.json 服务端数据表合并补丁
//
// 安装模型（为什么是「合并成单个补丁 pak」）：
//   UE 的 pak 挂载顺序按文件名（_P 后缀 +100 优先级，见 REVERSE_ENGINEERING 第 14 节），
//   每个 mod 各打一个 pak 就要跟挂载顺序搏斗；合并成单个 GHSMods_P.pak 则完全绕开 ——
//   冲突在合并阶段就按「启用列表的顺序」裁决（越靠后优先级越高，后合并者覆盖），报告中可查。
//   补丁 pak 不加密、V8B 格式：引擎对同盘未加密 pak 不要求密钥，V8B 是所有 UE5 都认的
//   最保守版本（原版 pak 是 V11 + 自带 path hash seed，那只影响它自己的索引）。
//
// 状态存放：mods/.launcher.json（启用列表 / 排序 / 最近一次构建记录）。
// 不写进每个 mod 的 mod.json —— mod 目录是「作者的产物」，应当保持只读、可整个替换升级；
// 「玩家本地怎么用」属于启动器的状态，两者分开才不会在升级 mod 时互相踩。
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const log = require('./logger');
const zip = require('./zip');

const SERVER_DIR = path.join(__dirname, '..');
const REPO_DIR = path.dirname(SERVER_DIR);
const CONFIG_FILE = path.join(SERVER_DIR, 'runtime-config.json');

// 测试可通过环境变量重定向（与 store.js 的 GHS_DATA_DIR 同一规矩，坑 35）。
const MODS_DIR = process.env.GHS_MODS_DIR || path.join(SERVER_DIR, 'mods');
const GAMEDATA_DIR = process.env.GHS_GAMEDATA_DIR || path.join(REPO_DIR, 'reference', 'gamedata');
const GAME_ROOT = process.env.GHS_GAME_ROOT || null; // 仅测试注入；正常从 runtime-config.json 读
const REPAK = process.env.GHS_REPAK || null;         // 仅测试注入；正常自动探测

const PAK_NAME = 'GHSMods_P.pak';
const STATE_FILE = path.join(MODS_DIR, '.launcher.json');
const BACKUP_DIR = path.join(MODS_DIR, '.gamedata_backup');
const BUILD_DIR = path.join(MODS_DIR, '.build');
const STEAM_RUN_ID = 2877160;
const PAK_PREFIX = 'Nornium/'; // pak 内路径必须以它开头（挂载点 ../../../，见原版 pak 的 info）

const MOD_ID_RE = /^[a-z0-9][a-z0-9_-]{1,39}$/;

// ------------------------------------------------------------ 小工具

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function readRuntimeConfig() {
  try {
    return readJson(CONFIG_FILE);
  } catch (_) {
    return {};
  }
}

function gameRoot() {
  if (GAME_ROOT) return GAME_ROOT;
  const cfg = readRuntimeConfig();
  return cfg.game_path || null;
}

function gameExePath(root) {
  return path.join(root || gameRoot() || '', 'Binaries', 'Win64', 'GHS-Win64-Shipping.exe');
}

function paksDir(root) {
  return path.join(root || gameRoot() || '', 'Content', 'Paks');
}

// repak.exe 探测：显式环境变量 > PATH > 常见安装位置 > 仓库 tools\repak\。
// 打包用的是外部 CLI，找不到时所有构建接口都要给出可操作的人话。
function findRepak() {
  if (REPAK) return REPAK;
  const candidates = [
    'C:\\Program Files\\repak_cli\\bin\\repak.exe',
    path.join(REPO_DIR, 'tools', 'repak', 'repak.exe'),
  ];
  for (const c of candidates) {
    try { if (fs.statSync(c).isFile()) return c; } catch (_) { /* 不在 */ }
  }
  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    if (!dir) continue;
    const c = path.join(dir, 'repak.exe');
    try { if (fs.statSync(c).isFile()) return c; } catch (_) { /* 不在 */ }
  }
  return null;
}

function exeFingerprint(root) {
  const exe = gameExePath(root);
  try {
    const st = fs.statSync(exe);
    return { path: exe, size: st.size, mtime_ms: Math.round(st.mtimeMs) };
  } catch (_) {
    return { path: exe, size: null, mtime_ms: null };
  }
}

// ------------------------------------------------------------ 启用状态（.launcher.json）

function loadState() {
  try {
    const st = readJson(STATE_FILE);
    if (Array.isArray(st.enabled)) return st;
  } catch (_) { /* 首次使用 */ }
  return { enabled: [], built: null, server_patch: null };
}

function saveState(state) {
  fs.mkdirSync(MODS_DIR, { recursive: true });
  fs.writeFileSync(STATE_FILE, `${JSON.stringify(state, null, 2)}\n`, 'utf8');
}

// ------------------------------------------------------------ mod 校验

// 校验单个 mod 目录。ok=false 表示有 hard error（不能参与构建）；
// warnings 只是提示（照常参与构建）。errors/warnings 都是人话字符串。
function validateMod(modDir) {
  const errors = [];
  const warnings = [];
  const manifestPath = path.join(modDir, 'mod.json');
  let manifest = null;
  try {
    manifest = readJson(manifestPath);
  } catch (err) {
    errors.push(`mod.json 读取失败：${err.message}`);
    return { ok: false, errors, warnings, manifest: null, file_count: 0, server_patch_tables: [] };
  }
  if (!manifest || typeof manifest !== 'object') {
    errors.push('mod.json 必须是一个 JSON 对象');
    return { ok: false, errors, warnings, manifest: null, file_count: 0, server_patch_tables: [] };
  }
  const id = String(manifest.id || '');
  if (!MOD_ID_RE.test(id)) {
    errors.push(`id "${id}" 不合法：2..40 个小写字母/数字/-/_，字母或数字开头（与目录名一致）`);
  } else if (path.basename(modDir) !== id) {
    errors.push(`目录名 "${path.basename(modDir)}" 与 mod.json 的 id "${id}" 不一致`);
  }
  for (const field of ['name', 'version', 'author']) {
    if (!String(manifest[field] || '').trim()) errors.push(`mod.json 缺少 ${field}`);
  }
  if (manifest.priority !== undefined) {
    warnings.push('mod.json 里的 priority 已废弃：优先级由启动器里的启用顺序决定（越靠下越优先）');
  }

  // files/ 路径审计：路径穿越与错误前缀是 mod 包最常见的两类事故，直接在这里拦。
  const filesDir = path.join(modDir, 'files');
  let fileCount = 0;
  if (fs.existsSync(filesDir)) {
    const walk = (p, rel) => {
      for (const e of fs.readdirSync(p, { withFileTypes: true })) {
        const relName = rel ? `${rel}/${e.name}` : e.name;
        if (e.name === '.DS_Store' || e.name === 'Thumbs.db') continue;
        if (e.isDirectory()) {
          if (e.name === '.' || e.name === '..') continue;
          walk(path.join(p, e.name), relName);
          continue;
        }
        if (e.isSymbolicLink()) {
          errors.push(`files/ 里不允许符号链接：${relName}（mod 包必须是自包含的普通文件）`);
          continue;
        }
        fileCount += 1;
        const norm = relName.replace(/\\/g, '/');
        if (!norm.startsWith(`${PAK_PREFIX}`)) {
          errors.push(`files/ 下的路径必须以 ${PAK_PREFIX} 开头（pak 挂载点决定的）：${norm}`);
          continue;
        }
        const resolved = path.resolve(p, e.name);
        if (!resolved.startsWith(path.resolve(filesDir) + path.sep)) {
          errors.push(`files/ 里的路径穿越（..）：${norm}`);
        }
      }
    };
    walk(filesDir, '');
    if (fileCount === 0) warnings.push('files/ 是空的：这个 mod 不会改任何客户端文件');
  } else {
    warnings.push('没有 files/ 目录：这个 mod 只能带 server_patch（或纯粹是声明性的）');
  }

  // server_patch/ 审计：文件名必须是数据表名，内容必须是可解析 JSON。
  const patchDir = path.join(modDir, 'server_patch');
  const tables = [];
  if (fs.existsSync(patchDir)) {
    for (const e of fs.readdirSync(patchDir, { withFileTypes: true })) {
      if (!e.isFile() || !e.name.endsWith('.json')) {
        errors.push(`server_patch/ 里只允许 <表名>.json（如 d_character.json）：${e.name}`);
        continue;
      }
      tables.push(e.name.slice(0, -5));
      try {
        const patch = readJson(path.join(patchDir, e.name));
        if (!patch || typeof patch !== 'object' || Array.isArray(patch)) {
          errors.push(`server_patch/${e.name} 必须是 { "行id": 行 } 形式的对象`);
        }
      } catch (err) {
        errors.push(`server_patch/${e.name} 不是合法 JSON：${err.message}`);
      }
    }
  }
  return { ok: errors.length === 0, errors, warnings, manifest, file_count: fileCount, server_patch_tables: tables };
}

// ------------------------------------------------------------ mod 仓库

function modDir(id) {
  return path.join(MODS_DIR, id);
}

// 扫描全部 mod，附带启用状态与冲突报告。冲突判定只对「启用中的 mod」做，
// 胜者 = 启用列表里更靠后的那个（与构建时的合并顺序一致，报告不说谎）。
function listMods() {
  const state = loadState();
  const mods = [];
  let ids = [];
  try {
    ids = fs.readdirSync(MODS_DIR, { withFileTypes: true })
      .filter((e) => e.isDirectory() && !e.name.startsWith('.'))
      .map((e) => e.name);
  } catch (_) { /* mods 目录还不存在 */ }

  const enabledOrder = state.enabled.filter((id) => ids.includes(id));
  const entries = [];
  for (const id of ids) {
    const dir = modDir(id);
    const v = validateMod(dir);
    const enabledIdx = enabledOrder.indexOf(id);
    entries.push({
      id,
      dir,
      enabled: enabledIdx >= 0,
      order: enabledIdx >= 0 ? enabledIdx : null,
      manifest: v.manifest,
      validation: { ok: v.ok, errors: v.errors, warnings: v.warnings },
      file_count: v.file_count,
      server_patch_tables: v.server_patch_tables,
    });
  }
  // 启用的排前面，其次按目录名。前端按 order 渲染启用优先级。
  entries.sort((a, b) => (a.enabled === b.enabled)
    ? a.id.localeCompare(b.id)
    : (a.enabled ? -1 : 1));

  // 冲突报告：relPath → [modId 按合并顺序]，>1 个才算冲突，最后一个赢。
  const mergedOrder = enabledOrder;
  const ownership = new Map();
  const conflicts = [];
  for (const id of mergedOrder) {
    const filesDir = path.join(modDir(id), 'files');
    if (!fs.existsSync(filesDir)) continue;
    const walk = (p, rel) => {
      for (const e of fs.readdirSync(p, { withFileTypes: true })) {
        const relName = rel ? `${rel}/${e.name}` : e.name;
        if (e.isDirectory()) walk(path.join(p, e.name), relName);
        else if (e.isFile()) {
          const norm = relName.replace(/\\/g, '/');
          const owners = ownership.get(norm) || [];
          owners.push(id);
          ownership.set(norm, owners);
        }
      }
    };
    walk(filesDir, '');
  }
  for (const [file, owners] of ownership) {
    if (owners.length > 1) {
      conflicts.push({ file, winner: owners[owners.length - 1], losers: owners.slice(0, -1) });
    }
  }
  conflicts.sort((a, b) => a.file.localeCompare(b.file));

  return { mods: entries, enabled_order: enabledOrder, conflicts, state };
}

// ------------------------------------------------------------ 导入（zip / 目录）

// 把 mod.json 里的 id 归一成安全目录名；与校验规则一致，不是合法 id 的 mod 导不进来。
function sanitizeId(raw) {
  const id = String(raw || '').trim().toLowerCase();
  if (!MOD_ID_RE.test(id)) return null;
  return id;
}

// 把「{ zip内路径: Buffer }」里的 mod 提取到 mods/<id>/。
// zip 里允许包一层顶层目录（作者从资源管理器压缩文件夹的习惯），
// 以 mod.json 的位置为准剥壳。
function importModPayload(payload) {
  const keys = Object.keys(payload);
  const manifestKey = keys.find((k) => k === 'mod.json')
    || keys.find((k) => k.endsWith('/mod.json') && k.indexOf('/', 0) === k.lastIndexOf('/'));
  if (!manifestKey) {
    throw new Error('zip 里没找到 mod.json（要在压缩包根目录或一层目录里）');
  }
  const strip = manifestKey === 'mod.json' ? '' : manifestKey.slice(0, -'mod.json'.length);
  const manifestBuf = payload[manifestKey];
  let manifest;
  try {
    manifest = JSON.parse(manifestBuf.toString('utf8'));
  } catch (err) {
    throw new Error(`mod.json 不是合法 JSON：${err.message}`);
  }
  const id = sanitizeId(manifest && manifest.id);
  if (!id) {
    throw new Error(`mod.json 的 id "${manifest && manifest.id}" 不合法（2..40 个小写字母/数字/-/_）`);
  }
  const dest = modDir(id);
  if (fs.existsSync(dest)) {
    throw new Error(`mod "${id}" 已经存在（同名 id 的 mod 不能重复导入；要更新就先删旧的）`);
  }
  const taken = {};
  for (const [name, buf] of Object.entries(payload)) {
    if (!name.startsWith(strip)) continue;
    const rel = name.slice(strip.length);
    if (!rel || rel.endsWith('/')) continue;
    // 统一 / 分隔并拒绝任何形式的路径穿越
    const norm = path.normalize(rel.replace(/\\/g, '/')).replace(/\\/g, '/');
    if (norm.startsWith('..') || norm.includes('/../') || path.isAbsolute(norm)) {
      throw new Error(`zip 里的路径不安全：${name}`);
    }
    taken[norm] = buf;
  }
  fs.mkdirSync(dest, { recursive: true });
  for (const [rel, buf] of Object.entries(taken)) {
    const file = path.join(dest, rel);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, buf);
  }
  const v = validateMod(dest);
  if (!v.ok) {
    // 校验不过也保留文件（作者可以修好它），但把问题如实报出来
    log.warn(`[mods] 导入的 mod "${id}" 校验未通过：${v.errors.join('；')}`);
  } else {
    log.info(`[mods] 导入 mod "${id}" v${v.manifest.version}（${v.file_count} 个文件）`);
  }
  return { id, validation: { ok: v.ok, errors: v.errors, warnings: v.warnings } };
}

function importFromZipBuffer(buf) {
  return importModPayload(zip.readAll(buf));
}

function importFromZipFile(file) {
  return importFromZipBuffer(fs.readFileSync(file));
}

function importFromDir(dir) {
  const payload = {};
  const walk = (p, rel) => {
    for (const e of fs.readdirSync(p, { withFileTypes: true })) {
      const relName = rel ? `${rel}/${e.name}` : e.name;
      if (e.isDirectory()) walk(path.join(p, e.name), relName);
      else if (e.isFile()) payload[relName] = fs.readFileSync(path.join(p, e.name));
    }
  };
  walk(dir, '');
  return importModPayload(payload);
}

// ------------------------------------------------------------ 启用 / 排序 / 删除

function setEnabled(id, enabled) {
  const state = loadState();
  const set = new Set(state.enabled);
  if (enabled) {
    if (!fs.existsSync(modDir(id))) throw new Error(`mod "${id}" 不存在`);
    if (!set.has(id)) state.enabled.push(id);
  } else {
    set.delete(id);
    state.enabled = state.enabled.filter((x) => x !== id);
  }
  saveState(state);
  return state.enabled;
}

// 整条重排启用顺序（数组即优先级，越靠后越优先）。数组里可以有未启用的 id，
// 只保留存在的；缺失的启用 mod 追加到末尾（不会因为前端漏传而悄悄失联）。
function setOrder(ids) {
  const state = loadState();
  const known = new Set(state.enabled);
  const next = [];
  for (const raw of Array.isArray(ids) ? ids : []) {
    const id = String(raw);
    if (known.has(id) && !next.includes(id)) next.push(id);
  }
  for (const id of state.enabled) if (!next.includes(id)) next.push(id);
  state.enabled = next;
  saveState(state);
  return next;
}

function removeMod(id) {
  const dir = modDir(id);
  if (!fs.existsSync(dir)) throw new Error(`mod "${id}" 不存在`);
  fs.rmSync(dir, { recursive: true, force: true });
  setEnabled(id, false);
  log.info(`[mods] 已删除 mod "${id}"`);
}

// ------------------------------------------------------------ 合并 + repak 打包 + 安装

// 合并所有启用 mod 的 files/：返回 { files: [{rel, src, mod}], conflicts }。
// 合并顺序 = state.enabled 顺序，越靠后越优先（覆盖前面的同名文件）。
function mergeFiles() {
  const { enabled_order: order, conflicts } = listMods();
  const map = new Map();
  const modOf = new Map();
  for (const id of order) {
    const v = validateMod(modDir(id));
    if (!v.ok) throw new Error(`mod "${id}" 校验未通过，先解决它再构建：${v.errors[0]}`);
    const filesDir = path.join(modDir(id), 'files');
    if (!fs.existsSync(filesDir)) continue;
    const walk = (p, rel) => {
      for (const e of fs.readdirSync(p, { withFileTypes: true })) {
        const relName = rel ? `${rel}/${e.name}` : e.name;
        if (e.isDirectory()) walk(path.join(p, e.name), relName);
        else if (e.isFile()) {
          const norm = relName.replace(/\\/g, '/');
          map.set(norm, path.join(p, e.name));
          modOf.set(norm, id);
        }
      }
    };
    walk(filesDir, '');
  }
  const files = [...map.entries()].map(([rel, src]) => ({ rel, src, mod: modOf.get(rel) }));
  files.sort((a, b) => a.rel.localeCompare(b.rel));
  return { files, conflicts };
}

function runRepak(repakPath, buildDir, outPak) {
  const attempt = (compression) => spawnSync(repakPath, [
    'pack', '--quiet', '--version', 'V8B', '--compression', compression,
    '--mount-point', '../../../', buildDir, outPak,
  ], { encoding: 'utf8' });
  let res = attempt('Oodle'); // 与原版 pak 相同的压缩（oo2core dll 随 repak_cli 分发）
  if (res.error || res.status !== 0) {
    log.warn(`[mods] repak Oodle 打包失败（${(res.error && res.error.code) || res.status || '?'}），退回 Zlib 重试`);
    res = attempt('Zlib');
  }
  if (res.error) throw new Error(`repak 无法启动：${res.error.message}`);
  if (res.status !== 0) {
    throw new Error(`repak 打包失败（退出码 ${res.status}）：${String(res.stderr || res.stdout || '').slice(0, 400)}`);
  }
}

// 构建 + 安装。dryRun=true 只算清单不落盘（测试与前端预览用）。
function buildInstalled({ dryRun = false } = {}) {
  const { files, conflicts } = mergeFiles();
  const state = loadState();
  const plan = {
    file_count: files.length,
    mods: state.enabled.slice(),
    conflicts,
    // 给前端预览 / 测试用：文件 → 来源 mod 的映射（src 是本机绝对路径，不下发前端）
    files: files.map((f) => ({ rel: f.rel, mod: f.mod })),
    pak: PAK_NAME,
  };
  if (dryRun) return { ...plan, dry_run: true, installed: false };

  const repakPath = findRepak();
  if (!repakPath) {
    throw new Error('找不到 repak.exe：请安装 repak_cli（默认 C:\\Program Files\\repak_cli\\bin\\），'
      + '或把 repak.exe 放进 ServerDev\\tools\\repak\\');
  }
  const root = gameRoot();
  if (!root || !fs.existsSync(gameExePath(root))) {
    throw new Error(`游戏目录无效（${root || '未配置'}）：先跑一次 setup 向导，再回来构建 mod`);
  }
  const outPak = path.join(paksDir(root), PAK_NAME);
  const fingerprint = exeFingerprint(root);

  fs.rmSync(BUILD_DIR, { recursive: true, force: true });
  fs.mkdirSync(BUILD_DIR, { recursive: true });
  for (const f of files) {
    const dest = path.join(BUILD_DIR, ...f.rel.split('/'));
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(f.src, dest);
  }
  try {
    runRepak(repakPath, BUILD_DIR, outPak);
  } finally {
    fs.rmSync(BUILD_DIR, { recursive: true, force: true });
  }
  state.built = {
    at: Date.now(),
    pak: outPak,
    file_count: files.length,
    mods: state.enabled.slice(),
    game_fingerprint: fingerprint,
    conflicts: conflicts.length,
  };
  saveState(state);
  log.info(`[mods] 补丁 pak 已安装：${outPak}（${files.length} 个文件，来自 ${state.enabled.length} 个 mod，冲突 ${conflicts.length} 处）`);
  return { ...plan, installed: true, dry_run: false };
}

// 卸载 = 删掉那一个 pak 文件 + 清掉构建记录。游戏目录瞬间回到纯净态。
function uninstall() {
  const state = loadState();
  const root = gameRoot();
  if (root) {
    const pak = path.join(paksDir(root), PAK_NAME);
    try { fs.rmSync(pak, { force: true }); } catch (_) { /* 不在 */ }
  }
  state.built = null;
  saveState(state);
  log.info('[mods] 补丁 pak 已卸载');
}

// ------------------------------------------------------------ 服务端数据表补丁

// 深合并：行是对象 → 递归合并（保留基表里补丁没提的字段）；否则整行替换。
// 表本身约定为 { "行id": 行 }（convert_gamedata.py 的产物，数字键一律字符串化）。
function mergeTable(base, patch) {
  const out = { ...base };
  for (const [key, val] of Object.entries(patch)) {
    const cur = out[key];
    out[key] = (cur && typeof cur === 'object' && !Array.isArray(cur)
      && val && typeof val === 'object' && !Array.isArray(val))
      ? mergeTable(cur, val)
      : val;
  }
  return out;
}

// 把所有启用 mod 的 server_patch/ 按启用顺序合并进 reference/gamedata。
// 首次改动某张表前，把原表整份备份到 mods/.gamedata_backup/（只备份一次 = 永远 pristine）。
// 改完调用 gamedata.reload() 让运行中的服务端立刻生效，不需要重启。
function applyServerPatches() {
  const gd = require('./gamedata'); // 延迟 require：避免 mods.js 被 gamedata 的测试环境加载时序绑死
  const { enabled_order: order } = listMods();
  const applied = [];
  const skipped = [];
  fs.mkdirSync(BACKUP_DIR, { recursive: true });
  for (const id of order) {
    const patchDir = path.join(modDir(id), 'server_patch');
    if (!fs.existsSync(patchDir)) continue;
    for (const e of fs.readdirSync(patchDir, { withFileTypes: true })) {
      if (!e.isFile() || !e.name.endsWith('.json')) continue;
      const table = e.name.slice(0, -5);
      const target = path.join(GAMEDATA_DIR, e.name);
      if (!fs.existsSync(target)) {
        skipped.push({ mod: id, table, reason: '基准表不存在' });
        continue;
      }
      let patch;
      try {
        patch = readJson(path.join(patchDir, e.name));
      } catch (err) {
        throw new Error(`mod "${id}" 的 server_patch/${e.name} 不是合法 JSON：${err.message}`);
      }
      const backup = path.join(BACKUP_DIR, e.name);
      if (!fs.existsSync(backup)) fs.copyFileSync(target, backup);
      const merged = mergeTable(readJson(target), patch);
      fs.writeFileSync(target, `${JSON.stringify(merged, null, 1)}\n`, 'utf8');
      gd.reload(table);
      applied.push({ mod: id, table });
    }
  }
  const state = loadState();
  state.server_patch = { at: Date.now(), applied };
  saveState(state);
  log.info(`[mods] 服务端数据表补丁已应用：${applied.length} 张表（来自 ${order.length} 个启用 mod）`);
  return { applied, skipped };
}

// 还原服务端数据表（从 .gamedata_backup 拷回）。备份只进不改，所以这是精确还原。
function revertServerPatches() {
  const gd = require('./gamedata');
  if (!fs.existsSync(BACKUP_DIR)) return { restored: [] };
  const restored = [];
  for (const e of fs.readdirSync(BACKUP_DIR, { withFileTypes: true })) {
    if (!e.isFile()) continue;
    const target = path.join(GAMEDATA_DIR, e.name);
    if (!fs.existsSync(target)) continue;
    fs.copyFileSync(path.join(BACKUP_DIR, e.name), target);
    gd.reload(e.name.slice(0, -5));
    restored.push(e.name);
  }
  fs.rmSync(BACKUP_DIR, { recursive: true, force: true });
  const state = loadState();
  state.server_patch = null;
  saveState(state);
  log.info(`[mods] 服务端数据表已还原：${restored.length} 张`);
  return { restored };
}

// ------------------------------------------------------------ 总览信息（GET /editor/api/game）

function gameInfo() {
  const root = gameRoot();
  const hasRoot = !!(root && fs.existsSync(gameExePath(root)));
  const state = loadState();
  const { mods, enabled_order: order, conflicts } = listMods();
  const pakPath = hasRoot ? path.join(paksDir(root), PAK_NAME) : null;
  const pakInstalled = !!(pakPath && fs.existsSync(pakPath));
  const fingerprint = hasRoot ? exeFingerprint(root) : null;
  const stale = !!(pakInstalled && state.built && fingerprint && state.built.game_fingerprint
    && (state.built.game_fingerprint.size !== fingerprint.size
      || state.built.game_fingerprint.mtime_ms !== fingerprint.mtime_ms));
  const repakPath = findRepak();
  const paks = [];
  if (hasRoot) {
    try {
      for (const e of fs.readdirSync(paksDir(root), { withFileTypes: true })) {
        if (e.isFile() && e.name.endsWith('.pak')) {
          paks.push({ name: e.name, size: fs.statSync(path.join(paksDir(root), e.name)).size });
        }
      }
    } catch (_) { /* Paks 目录不可读 */ }
  }
  return {
    game_root: root || null,
    game_ok: hasRoot,
    exe: fingerprint,
    paks,
    installed: {
      pak_exists: pakInstalled,
      pak_path: pakPath,
      built_at: state.built ? state.built.at : null,
      built_from: state.built ? state.built.mods : [],
      file_count: state.built ? state.built.file_count : 0,
      stale, // 构建后游戏更新过 exe → mod 可能不兼容
    },
    server_patch: {
      applied_at: state.server_patch ? state.server_patch.at : null,
      applied: state.server_patch ? state.server_patch.applied : [],
    },
    mods: mods.map((m) => ({
      id: m.id,
      enabled: m.enabled,
      order: m.order,
      name: (m.manifest && m.manifest.name) || m.id,
      version: (m.manifest && m.manifest.version) || '?',
      author: (m.manifest && m.manifest.author) || '',
      description: (m.manifest && m.manifest.description) || '',
      file_count: m.file_count,
      server_patch_tables: m.server_patch_tables,
      validation: m.validation,
    })),
    enabled_order: order,
    conflicts,
    repak: repakPath ? { found: true, path: repakPath } : { found: false },
    mods_dir: MODS_DIR,
  };
}

// ------------------------------------------------------------ 启动游戏

// 只能经 Steam 拉起（直接跑 exe 会因 Steamworks 检查退出，见坑 13）。
// start "" "steam://..."：cmd 的 start 需要窗口标题占位，否则带引号的 URL 会被当标题。
function launchGame() {
  const res = spawnSync('cmd.exe', ['/d', '/s', '/c', 'start', '', `steam://rungameid/${STEAM_RUN_ID}`],
    { encoding: 'utf8', timeout: 15000 });
  if (res.error) throw new Error(`无法调起 Steam：${res.error.message}`);
  log.info(`[mods] 已请求 Steam 启动游戏（appid ${STEAM_RUN_ID}）`);
  return { launched: true, steam_url: `steam://rungameid/${STEAM_RUN_ID}` };
}

module.exports = {
  PAK_NAME, PAK_PREFIX, MODS_DIR, STEAM_RUN_ID,
  validateMod, listMods, importFromZipBuffer, importFromZipFile, importFromDir,
  setEnabled, setOrder, removeMod,
  mergeFiles, buildInstalled, uninstall,
  applyServerPatches, revertServerPatches,
  gameInfo, launchGame, findRepak, gameRoot,
};
