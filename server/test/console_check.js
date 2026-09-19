// In-process regression checks for the server console commands (restore/load/stop).
//
// Scope: the console is the release/ops surface typed directly into the server
// window. The dangerous one is `restore` — it wipes server/data while the
// process keeps running, so the invariants here are:
//
//   1. restore really empties accounts.json + players/ (and recreates the dir),
//      while the HTTP/TCP setup is untouched (no server needed for the logic).
//   2. load re-reads the disk, so dropping a backup into server/data and
//      running `load` must make those accounts visible without a restart.
//   3. stop only *reports* the intent (action:'stop'); process.exit stays in
//      index.js so these checks can run it in-process.
//   4. restore/load kick online sessions first and wait for the socket drain
//      window before touching files — otherwise a dying session's savePlayer
//      could resurrect the wiped saves.
//
// No server needed. Must run before requiring the server modules: store.js
// reads GHS_DATA_DIR at load time so the saves stay out of the real data/ dir.
const os = require('os');
const fs = require('fs');
const path = require('path');
const tmpDataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ghs-console-'));
process.env.GHS_DATA_DIR = tmpDataDir;

const store = require('../src/store');
const { handleCommand } = require('../src/console');
const { Session, trackSession, liveSessionCount } = require('../src/session');

let failures = 0;
function check(cond, msg) {
  console.log(cond ? `  PASS ${msg}` : `  FAIL ${msg}`);
  if (!cond) failures += 1;
}
const delay = (ms) => new Promise((r) => setTimeout(r, ms));

// fake live session: only the pieces kickAllSessions()/liveSessionCount() touch
function fakeSession() {
  const s = new Session({ destroy() {}, remoteAddress: '127.0.0.1' }, () => {});
  s.sent = [];
  s.send = (name, msg, result) => s.sent.push({ name, msg, result });
  s.kick = (reason) => {
    s.send('ntf_kick', { reason });
    // 真实实现是 100ms 后 destroy；这里立刻置 closed 模拟断开
    s.closed = true;
    if (s.onCloseHook) s.onCloseHook();
  };
  return s;
}

function seedAccount(name) {
  const rec = store.createAccount(name, 'pw');
  store.savePlayer({
    account_id: rec.account_id,
    bag: { items: [], next_uuid: 1 },
    characters: [],
  });
  return rec;
}

(async () => {
  store.loadAccounts();

  // ---------------- help / status / unknown ----------------
  {
    const help = await handleCommand('help');
    check(/restore/.test(help.reply) && /load/.test(help.reply) && /stop/.test(help.reply),
      'help lists restore / load / stop');
    check(help.action === 'none', 'help does not stop the server');

    const status = await handleCommand('status');
    check(/在线/.test(status.reply) && /存档/.test(status.reply), 'status reports sessions and saves');

    const bogus = await handleCommand('nuke');
    check(/未知指令/.test(bogus.reply) && bogus.action === 'none',
      'an unknown command is rejected without side effects');

    const empty = await handleCommand('   ');
    check(empty.reply === '' && empty.action === 'none', 'an empty line is ignored');
  }

  // ---------------- restore ----------------
  {
    seedAccount('alpha');
    seedAccount('beta');
    const before = store.dataStats();
    check(before.accounts === 2 && before.players === 2,
      `seeding worked (${before.accounts} accounts / ${before.players} players)`);

    const live = fakeSession();
    trackSession(live);
    live.player = store.loadPlayer(1);
    check(live.player !== null, 'a fake online session holds a player doc');
    check(liveSessionCount() >= 1, 'the tracked session shows up in the live count');

    const res = await handleCommand('restore');
    check(res.action === 'none', 'restore keeps the server running');
    check(/清空/.test(res.reply) && /踢下线/.test(res.reply), 'restore reports the wipe and the kick');
    check(live.sent.some((m) => m.name === 'ntf_kick'), 'restore kicked the online session (ntf_kick)');

    const after = store.dataStats();
    check(after.accounts === 0 && after.players === 0,
      `server/data is empty after restore (${after.accounts} accounts / ${after.players} players)`);
    check(fs.existsSync(path.join(tmpDataDir, 'accounts.json')) === false,
      'accounts.json is really gone from disk');
    check(fs.existsSync(path.join(tmpDataDir, 'players')) === true,
      'the players/ directory still exists (recreated empty)');
    check(store.findAccount('alpha') === null, 'the in-memory account table is reset too');

    // 模拟被踢会话残留回写：closed 会话不应再触发 savePlayer 之类副作用
    // （这里只断言 closed 标志，真实的 save 只由显式 handler 调用）
    check(live.closed === true, 'the kicked session is marked closed');
  }

  // ---------------- load (hot-reload a dropped-in backup) ----------------
  {
    // 模拟"把备份拷回 server/data"：手写 accounts.json + 一个玩家档案
    const backupAccounts = {
      next_account_id: 2,
      by_name: {
        hero: { account_id: 1, account_name: 'hero', password: 'pw', key: 'k'.repeat(16) },
      },
    };
    fs.writeFileSync(path.join(tmpDataDir, 'accounts.json'), JSON.stringify(backupAccounts));
    fs.writeFileSync(path.join(tmpDataDir, 'players', '1.json'),
      JSON.stringify({ account_id: 1, bag: { items: [], next_uuid: 1 }, characters: [] }));

    const res = await handleCommand('load');
    check(res.action === 'none', 'load keeps the server running');
    check(/1 个账号/.test(res.reply) && /1 个玩家档案/.test(res.reply),
      'load re-read the dropped-in backup from disk');
    check(store.findAccount('hero') !== null, 'the backup account is usable without a restart');
    check(store.loadPlayer(1) !== null, 'the backup player doc loads after load');
  }

  // ---------------- stop ----------------
  {
    const res = await handleCommand('stop');
    check(res.action === 'stop', 'stop reports the stop intent (index.js performs the exit)');
    check(/踢下线|停止/.test(res.reply), 'stop mentions kicking sessions before exiting');
    // 真实的 process.exit 在 index.js 的 onStop 里，这里不执行
  }

  await delay(10);
  fs.rmSync(tmpDataDir, { recursive: true, force: true });
  console.log(failures === 0 ? '\nCONSOLE CHECKS PASSED' : `\n${failures} CONSOLE CHECKS FAILED`);
  process.exit(failures === 0 ? 0 : 1);
})().catch((err) => {
  console.error(err.stack || err.message);
  process.exit(1);
});
