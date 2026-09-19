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
// 运行中的会话必须先由调用方踢下线（见 console.js），
// 否则残余会话的 savePlayer 会立刻把内存里的旧档案写回来。
function resetData() {
  const file = path.join(dataDir, 'accounts.json');
  if (fs.existsSync(file)) fs.rmSync(file, { force: true });
  if (fs.existsSync(playersDir)) fs.rmSync(playersDir, { recursive: true, force: true });
  ensureDirs();
  accounts = { next_account_id: 1, by_name: {} };
}

module.exports = {
  loadAccounts, saveAccounts, findAccount, createAccount, saveAccount,
  loadPlayer, savePlayer, listPlayerIds, dataStats, resetData,
};
