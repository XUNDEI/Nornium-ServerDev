// JSON file persistence: data/accounts.json + data/players/<account_id>.json.
// Single-process, low traffic — writes are synchronous with atomic rename.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// GHS_DATA_DIR overrides the save location (tests point it at a temp dir).
const dataDir = process.env.GHS_DATA_DIR
  ? path.resolve(process.env.GHS_DATA_DIR)
  : path.join(__dirname, '..', 'data');
const playersDir = path.join(dataDir, 'players');

function ensureDirs() {
  fs.mkdirSync(playersDir, { recursive: true });
}

function atomicWrite(file, obj) {
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(obj));
  fs.renameSync(tmp, file);
}

let accounts = null;

function loadAccounts() {
  ensureDirs();
  const file = path.join(dataDir, 'accounts.json');
  if (fs.existsSync(file)) {
    accounts = JSON.parse(fs.readFileSync(file, 'utf8'));
  } else {
    accounts = { next_account_id: 1, by_name: {} };
  }
  return accounts;
}

function saveAccounts() {
  atomicWrite(path.join(dataDir, 'accounts.json'), accounts);
}

function findAccount(name) {
  return accounts.by_name[String(name)] ?? null;
}

// 全部账号记录（编辑器把 account_id 映射到账号名用）。未 loadAccounts 时为空表。
function allAccounts() {
  return (accounts && accounts.by_name) || {};
}

// account record: { account_id, account_name, password, key }
function createAccount(name, password) {
  const rec = {
    account_id: accounts.next_account_id++,
    account_name: String(name),
    password: String(password),
    key: crypto.randomBytes(8).toString('hex'),
  };
  accounts.by_name[String(name)] = rec;
  saveAccounts();
  return rec;
}

function saveAccount(rec) {
  accounts.by_name[String(rec.account_name)] = rec;
  saveAccounts();
}

function playerPath(accountId) {
  return path.join(playersDir, `${accountId}.json`);
}

function loadPlayer(accountId) {
  const file = playerPath(accountId);
  if (!fs.existsSync(file)) return null;
  const doc = JSON.parse(fs.readFileSync(file, 'utf8'));
  // One-time migrations (unique item uuids, drop dev placeholder characters,
  // seed synthesis blueprints, re-expand story sub-tasks). Idempotent.
  if (doc && require('./game/migrate').migratePlayer(doc)) savePlayer(doc);
  return doc;
}

function savePlayer(doc) {
  ensureDirs();
  atomicWrite(playerPath(doc.account_id), doc);
}

function listPlayerIds() {
  ensureDirs();
  return fs.readdirSync(playersDir)
    .filter((f) => f.endsWith('.json'))
    .map((f) => Number(path.basename(f, '.json')))
    .filter((n) => Number.isFinite(n));
}

// 存档概况（控制台 status / load / restore 的回显用）
function dataStats() {
  let players = 0;
  try {
    players = fs.readdirSync(playersDir).filter((f) => f.endsWith('.json')).length;
  } catch (_) { /* players 目录还没建 */ }
  // 外层的 accounts 变量在未 loadAccounts 时为 null
  const accountCount = accounts ? Object.keys(accounts.by_name || {}).length : 0;
  return { accounts: accountCount, players };
}

// 清空本地存档：删 accounts.json + players/ 全部内容，然后重建空目录，
// 并把内存里的账号表一并重置——否则下一次 createAccount 会把旧账号整表写回磁盘。
// 运行中的会话必须先由调用方排空（见 console.js 的维护窗口），
// 否则残余会话的 savePlayer 会立刻把内存里的旧档案写回来。
// 删之前一定先 snapshotData('wipe')：这是唯一一个会不可逆丢数据的动作。
function resetData() {
  const snapshot = snapshotData('wipe');
  const file = path.join(dataDir, 'accounts.json');
  if (fs.existsSync(file)) fs.rmSync(file, { force: true });
  if (fs.existsSync(playersDir)) fs.rmSync(playersDir, { recursive: true, force: true });
  ensureDirs();
  accounts = { next_account_id: 1, by_name: {} };
  return snapshot;
}

// ------------------------------------------------------------ 备份 / 导入

function dataDirPath() {
  return dataDir;
}

// 本地时间戳，给备份目录起名用（人能直接读：20260924-220500）
function localStamp(d = new Date()) {
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}`
    + `-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

function listPlayerFiles(dir) {
  try {
    return fs.readdirSync(dir).filter((f) => f.endsWith('.json'));
  } catch (_) {
    return [];
  }
}

// 把当前存档整份拷成**兄弟目录** <data>_<tag>_<stamp>（为了 restore 之后还能找回原档）。
// 空的就不建目录，免得每次操作都堆一堆空备份。返回 { dir, players } 或 null。
function snapshotData(tag = 'backup') {
  const accountsFile = path.join(dataDir, 'accounts.json');
  const hasAccounts = fs.existsSync(accountsFile);
  const playerFiles = listPlayerFiles(playersDir);
  if (!hasAccounts && playerFiles.length === 0) return null;

  const base = `${path.basename(dataDir)}_${tag}_${localStamp()}`;
  const parent = path.dirname(dataDir);
  let dest = path.join(parent, base);
  // 同秒内连点两次也要各留一份，不互相覆盖
  for (let i = 2; fs.existsSync(dest); i += 1) dest = path.join(parent, `${base}-${i}`);

  fs.mkdirSync(path.join(dest, 'players'), { recursive: true });
  if (hasAccounts) fs.copyFileSync(accountsFile, path.join(dest, 'accounts.json'));
  for (const f of playerFiles) {
    fs.copyFileSync(path.join(playersDir, f), path.join(dest, 'players', f));
  }
  return { dir: dest, players: playerFiles.length };
}

// 用户在控制台给的「备份来源」允许两种写法：备份目录本身，或它下面那层 data\
// （有些人备份的是整个 server 目录）。找到含 accounts.json 的那层才算数。
function resolveBackupSource(input) {
  const raw = String(input || '').trim().replace(/^["']|["']$/g, '').replace(/[\\/]+$/, '');
  if (!raw) return null;
  for (const cand of [raw, path.join(raw, 'data')]) {
    try {
      if (fs.existsSync(path.join(cand, 'accounts.json'))) return path.resolve(cand);
    } catch (_) { /* 路径里有非法字符，试下一个 */ }
  }
  return null;
}

// 导出当前存档到用户指定的目录（export 指令 / 编辑器备份页用）。
// 与 snapshotData 的区别：snapshot 落在固定的兄弟目录（名字带时间戳），
// 这里写到调用方给的任意路径；目录不存在就创建，已有同名文件直接覆盖。
function exportData(destDir) {
  const dest = path.resolve(String(destDir || '').trim().replace(/^["']|["']$/g, ''));
  if (!dest) throw new Error('目标目录为空');
  if (path.resolve(dest) === path.resolve(dataDir)) {
    throw new Error('目标目录不能是当前存档目录本身');
  }
  ensureDirs();
  fs.mkdirSync(path.join(dest, 'players'), { recursive: true });
  const accountsFile = path.join(dataDir, 'accounts.json');
  const hasAccounts = fs.existsSync(accountsFile);
  if (hasAccounts) fs.copyFileSync(accountsFile, path.join(dest, 'accounts.json'));
  const playerFiles = listPlayerFiles(playersDir);
  for (const f of playerFiles) {
    fs.copyFileSync(path.join(playersDir, f), path.join(dest, 'players', f));
  }
  return { dir: dest, accounts: hasAccounts, players: playerFiles.length };
}

// 列出 data 目录旁边的所有快照（snapshotData 生成的 data_<tag>_<stamp>\），
// 给编辑器「备份」页展示用。按修改时间倒序。
function listBackups() {
  const parent = path.dirname(dataDir);
  const prefix = `${path.basename(dataDir)}_`;
  let names = [];
  try {
    names = fs.readdirSync(parent).filter((n) => n.startsWith(prefix)
      && fs.statSync(path.join(parent, n)).isDirectory());
  } catch (_) { return []; }
  return names.map((name) => {
    const st = fs.statSync(path.join(parent, name));
    return { name, path: path.join(parent, name), mtime: st.mtimeMs };
  }).sort((a, b) => b.mtime - a.mtime);
}

// 覆盖式导入：只覆盖「备份里有」的文件，**不删除**目标里多出来的档案
// （宁可留一份脏数据，也不误删玩家档）。返回导入统计。
function importData(srcDir) {
  ensureDirs();
  let accounts = false;
  let players = 0;
  const srcAccounts = path.join(srcDir, 'accounts.json');
  if (fs.existsSync(srcAccounts)) {
    fs.copyFileSync(srcAccounts, path.join(dataDir, 'accounts.json'));
    accounts = true;
  }
  const srcPlayers = path.join(srcDir, 'players');
  for (const f of listPlayerFiles(srcPlayers)) {
    fs.copyFileSync(path.join(srcPlayers, f), path.join(playersDir, f));
    players += 1;
  }
  return { accounts, players };
}

module.exports = {
  loadAccounts, saveAccounts, findAccount, allAccounts, createAccount, saveAccount,
  loadPlayer, savePlayer, listPlayerIds, dataStats, resetData,
  dataDirPath, snapshotData, resolveBackupSource, importData,
  exportData, listBackups,
};
