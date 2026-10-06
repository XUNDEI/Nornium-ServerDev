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
//   3. load <dir> imports that backup directory for you (accounts.json +
//      players\*.json) instead of silently ignoring the argument — the original
//      bug: `case 'load': return cmdLoad();` threw the path away, so typing
//      `load C:\...\backup` behaved exactly like a bare `load` and always
//      reported the (empty) server\data\ as "0 accounts / 0 players".
//   4. anything that rewrites the saves snapshots the old ones first, and a bad
//      path is rejected *before* the maintenance window opens.
//   5. stop only *reports* the intent (action:'stop'); process.exit stays in
//      index.js so these checks can run it in-process.
//   6. restore/load kick online sessions and wait for them to really close
//      (drainSessions) before touching files — otherwise a dying session's
//      savePlayer could resurrect the wiped saves.
//
// No server needed. Must run before requiring the server modules: store.js
// reads GHS_DATA_DIR at load time so the saves stay out of the real data/ dir.
const os = require('os');
const fs = require('fs');
const path = require('path');
// 存档目录故意放在 <tmp>/data 下一层：快照会落在 <tmp> 里，删 <tmp> 就是全清
const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'ghs-console-'));
const tmpDataDir = path.join(tmpRoot, 'data');
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

// 造一份"桌面上那种备份目录"
function makeBackup(dir, { accountId, accountName, extraPlayers = [] }) {
  fs.mkdirSync(path.join(dir, 'players'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'accounts.json'), JSON.stringify({
    next_account_id: accountId + 1,
    by_name: {
      [accountName]: {
        account_id: accountId, account_name: accountName, password: 'pw', key: 'k'.repeat(16),
      },
    },
  }));
  fs.writeFileSync(path.join(dir, 'players', `${accountId}.json`),
    JSON.stringify({ account_id: accountId, bag: { items: [], next_uuid: 1 }, characters: [] }));
  for (const id of extraPlayers) {
    fs.writeFileSync(path.join(dir, 'players', `${id}.json`),
      JSON.stringify({ account_id: id, bag: { items: [], next_uuid: 1 }, characters: [] }));
  }
}

(async () => {
  store.loadAccounts();

  // ---------------- help / status / unknown ----------------
  {
    const help = await handleCommand('help');
    check(/restore/.test(help.reply) && /load/.test(help.reply) && /stop/.test(help.reply),
      'help lists restore / load / stop');
    check(/load <备份目录>/.test(help.reply), 'help documents the optional backup-directory argument');
    check(help.action === 'none', 'help does not stop the server');
    check(help.reply.includes(require('../package.json').homepage),
      'help shows the project homepage (so a stuck user can find the repo)');

    const status = await handleCommand('status');
    check(/在线/.test(status.reply) && /存档/.test(status.reply), 'status reports sessions and saves');
    check(/项目主页/.test(status.reply) && status.reply.includes(require('../package.json').homepage),
      'status also surfaces the project homepage');

    const bogus = await handleCommand('nuke');
    check(/未知指令/.test(bogus.reply) && bogus.action === 'none',
      'an unknown command is rejected without side effects');

    // 回显必须保留用户输入的大小写（曾经整行 toLowerCase，路径被改写成全小写）
    const cased = await handleCommand('Nuke C:\\Some\\Case\\Path');
    check(cased.reply.includes('Nuke C:\\Some\\Case\\Path'),
      'the unknown-command echo preserves the original casing');

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
    check(/已自动备份/.test(res.reply), 'restore says where the pre-wipe snapshot went');
    check(live.sent.some((m) => m.name === 'ntf_kick'), 'restore kicked the online session (ntf_kick)');

    const after = store.dataStats();
    check(after.accounts === 0 && after.players === 0,
      `server/data is empty after restore (${after.accounts} accounts / ${after.players} players)`);
    check(fs.existsSync(path.join(tmpDataDir, 'accounts.json')) === false,
      'accounts.json is really gone from disk');
    check(fs.existsSync(path.join(tmpDataDir, 'players')) === true,
      'the players/ directory still exists (recreated empty)');
    check(store.findAccount('alpha') === null, 'the in-memory account table is reset too');

    // 删之前必须先快照，否则 restore 就是不可逆操作
    const wipes = fs.readdirSync(tmpRoot).filter((f) => f.startsWith('data_wipe_'));
    check(wipes.length === 1, `restore left exactly one wipe snapshot (${wipes.join(', ') || 'none'})`);
    const wipeDir = wipes.length === 1 ? path.join(tmpRoot, wipes[0]) : null;
    check(!!wipeDir && fs.existsSync(path.join(wipeDir, 'accounts.json')),
      'the wipe snapshot holds the deleted accounts.json');
    check(!!wipeDir && fs.readdirSync(path.join(wipeDir, 'players')).length === 2,
      'the wipe snapshot holds both deleted player docs');

    // 模拟被踢会话残留回写：closed 会话不应再触发 savePlayer 之类副作用
    // （这里只断言 closed 标志，真实的 save 只由显式 handler 调用）
    check(live.closed === true, 'the kicked session is marked closed');

    // 空档下裸 load：必须提示"要恢复旧档就用 load <备份目录>"，而不是干巴巴报 0/0
    const hint = await handleCommand('load');
    check(/注意/.test(hint.reply) && /load <备份目录>/.test(hint.reply),
      'load on an empty data dir hints at load <backup dir>');
    check(/0 个账号/.test(hint.reply), 'load still reports the real (empty) numbers');
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

  // ---------------- load <备份目录>（取代手工拷文件） ----------------
  {
    const backupDir = path.join(tmpRoot, 'Nornium_save_backup_2026-09-19');
    makeBackup(backupDir, { accountId: 8, accountName: 'veteran' });

    // 1) 路径里没有 accounts.json → 明确报错，而且**不许动**现有存档
    const beforeBad = store.dataStats();
    const bad = await handleCommand('load C:\\definitely\\not\\a\\backup');
    check(/没找到 accounts.json/.test(bad.reply), 'load <missing dir> reports a clear error');
    check(store.dataStats().accounts === beforeBad.accounts
      && store.dataStats().players === beforeBad.players,
    'a rejected load leaves the existing saves untouched');

    // 2) 空目录（存在但没有 accounts.json）同样要拒绝
    const emptyDir = path.join(tmpRoot, 'empty-dir');
    fs.mkdirSync(emptyDir, { recursive: true });
    const bad2 = await handleCommand(`load ${emptyDir}`);
    check(/没找到 accounts.json/.test(bad2.reply), 'a directory without accounts.json is rejected');

    // 3) 正常导入：引号、结尾反斜杠、混写大小写都要能吃进去
    const playersBeforeImport = store.dataStats().players;
    const ok = await handleCommand(`load "${backupDir}\\`);
    check(ok.action === 'none', 'load <dir> keeps the server running');
    check(/1 个玩家档案/.test(ok.reply), 'load <dir> imports the player files');
    check(/已备份到/.test(ok.reply), 'load <dir> snapshots the pre-import saves first');
    check(store.findAccount('veteran') !== null,
      'the imported account is usable without a restart');
    check(store.loadPlayer(8) !== null, 'the imported player doc loads after load');
    check(store.dataStats().players === playersBeforeImport + 1,
      `the import added exactly one player doc (${playersBeforeImport} -> ${store.dataStats().players})`);

    const preimports = fs.readdirSync(tmpRoot).filter((f) => f.startsWith('data_preimport_'));
    check(preimports.length === 1, `load <dir> left one pre-import snapshot (${preimports.join(', ') || 'none'})`);

    // 4) 允许给备份目录的上一级（有些人备份的是整个 server 目录），要自动进 data\
    const wrapped = path.join(tmpRoot, 'wrapped-backup');
    makeBackup(path.join(wrapped, 'data'), { accountId: 9, accountName: 'wrapped' });
    const wrappedRes = await handleCommand(`load ${wrapped}`);
    check(store.findAccount('wrapped') !== null,
      'a backup root whose saves live in <dir>\\data\\ is understood too');
    check(/9 个玩家档案|1 个玩家档案/.test(wrappedRes.reply), 'the wrapped import reports its own count');

    // 5) 覆盖式而非镜像式：目标里多出来的档案不许被删掉
    fs.writeFileSync(path.join(tmpDataDir, 'players', '99.json'),
      JSON.stringify({ account_id: 99, bag: { items: [], next_uuid: 1 }, characters: [] }));
    await handleCommand(`load ${backupDir}`);
    check(fs.existsSync(path.join(tmpDataDir, 'players', '99.json')),
      'importing never deletes player docs that the backup does not contain');

    // 6) 把 data\ 自己传进去没有意义，要拒绝
    const self = await handleCommand(`load ${tmpDataDir}`);
    check(/就是当前存档目录本身/.test(self.reply), 'loading the live data dir itself is rejected');
  }

  // ---------------- export（存档导出到指定目录 / 默认备份位置） ----------------
  {
    const before = store.dataStats();
    check(before.players >= 1, `there is something to export (${before.players} player docs)`);

    // 1) 导出到 data 目录本身 → 当场拒绝，不许动存档
    const self = await handleCommand(`export ${tmpDataDir}`);
    check(/不能导出到这里|就是当前存档目录本身/.test(self.reply), 'export to the live data dir itself is rejected');

    // 2) 导出到自定义目录（带引号、结尾反斜杠）
    const dest = path.join(tmpRoot, 'my-export');
    const res = await handleCommand(`export "${dest}\\"`);
    check(res.action === 'none', 'export keeps the server running');
    check(fs.existsSync(path.join(dest, 'accounts.json')), 'export wrote accounts.json to the custom dir');
    check(fs.readdirSync(path.join(dest, 'players')).length === before.players,
      `export copied all ${before.players} player docs`);

    // 3) 裸 export → 默认备份位置（data_export_<stamp>）
    const res2 = await handleCommand('export');
    check(/已导出到/.test(res2.reply), 'bare export reports the destination');
    const exportsDirs = fs.readdirSync(tmpRoot).filter((f) => f.startsWith('data_export_'));
    check(exportsDirs.length === 1, `bare export created one data_export_* snapshot (${exportsDirs.join(', ') || 'none'})`);
    check(exportsDirs.length === 1
      && fs.existsSync(path.join(tmpRoot, exportsDirs[0], 'accounts.json')),
    'the default export holds accounts.json');
  }

  // ---------------- allweapons（高稀有度武器发放） ----------------
  {
    const gd = require('../src/gamedata');
    const weaponData = require('../src/game/weapon_data');

    // 测试自己算期望值，不复制实现：已实装、稀有度 >= 6 的全部武器 id
    const expected = [];
    for (const [id, w] of gd.rows('d_bag_item_weapon')) {
      if (Number(w.rarity) < 6) continue;
      if (!weaponData.isReleasedWeapon(id)) continue;
      expected.push(Number(id));
    }
    expected.sort((a, b) => a - b);

    // 1) 账号名写错 → 明确报错
    const bad = await handleCommand('allweapons no-such-account');
    check(/没有叫/.test(bad.reply), 'allweapons with an unknown account name is rejected');

    // 2) 默认目标（账号 10）在本临时档里不存在 → 明确说跳过，而不是崩
    const skip = await handleCommand('allweapons');
    check(/跳过|没有实际发放/.test(skip.reply), 'allweapons with no arg reports the default target skip');

    // 3) 按账号 ID 发放
    const res = await handleCommand('allweapons 1');
    check(res.action === 'none', 'allweapons keeps the server running');
    const doc = store.loadPlayer(1);
    const weapons = doc.bag.items.filter((it) => it.weapon_info);
    check(weapons.length === expected.length,
      `one of every released 6★/7★ weapon (${weapons.length} granted, ${expected.length} expected)`);
    check(new Set(weapons.map((w) => w.item_uuid)).size === weapons.length,
      'every granted weapon got a unique item_uuid');
    check(new Set(weapons.map((w) => Number(w.item_id))).size === weapons.length,
      'no weapon id was granted twice');
    check(weapons.every((w) => expected.includes(Number(w.item_id))),
      'every granted weapon is a released high-rarity weapon');
    // 回归：早期版本会发出未实装的 1081601「颂歌」（客户端没有模型/图标/技能行）
    check(!weapons.some((w) => weaponData.isUnreleasedWeapon(w.item_id)),
      'no unreleased weapon is ever granted');
    check(weapons.every((w) => w.item_uuid >= 1000000), 'granted uuids came from the allocator, not from 0');
    check(weapons.every((w) => Number(gd.query('d_bag_item_weapon', w.item_id).rarity) >= 6),
      'nothing below 6★ is granted');

    // 4) all = 全部玩家档案
    const all = await handleCommand('allweapons all');
    check(/发出 \d+ 把/.test(all.reply), 'allweapons all reports per-account grants');
  }

  // ---------------- allexclusive（每人一把 7★ 专武） ----------------
  {
    const gd = require('../src/gamedata');
    const weaponData = require('../src/game/weapon_data');

    // 测试自己算期望值：映射表里全部已实装的 7★ 形态
    const expected = Object.values(weaponData.CHARACTER_EXCLUSIVE_WEAPONS)
      .map((e) => Number(e.seven))
      .filter((id) => weaponData.isReleasedWeapon(id))
      .sort((a, b) => a - b);

    // 1) 账号名写错 → 明确报错
    const bad = await handleCommand('allexclusive no-such-account');
    check(/没有叫/.test(bad.reply), 'allexclusive with an unknown account name is rejected');

    // 2) 按账号 ID 发放：十把 7★ 专武各一把（该档在前面的 allweapons 段已拿到过
    //    同 id 的武器，所以按「新增实例」统计）
    const countEx = (d) => d.bag.items.filter((it) => expected.includes(Number(it.item_id))).length;
    const beforeEx = countEx(store.loadPlayer(1));
    const res = await handleCommand('allexclusive 1');
    check(res.action === 'none', 'allexclusive keeps the server running');
    const doc = store.loadPlayer(1);
    check(countEx(doc) === beforeEx + expected.length,
      `every character's 7★ exclusive weapon granted once more (+${countEx(doc) - beforeEx}/${expected.length})`);
    const exWeapons = doc.bag.items.filter((it) => expected.includes(Number(it.item_id)));
    check(exWeapons.every((w) => Number(gd.query('d_bag_item_weapon', w.item_id).rarity) === 7),
      'allexclusive grants only 7★ weapons');
    check(!exWeapons.some((w) => weaponData.isUnreleasedWeapon(w.item_id)),
      'allexclusive never grants an unreleased weapon');
    const before = doc.bag.items.filter((it) => it.weapon_info).length;

    // 3) 回归：旧版把辩才姬（10701）指到信风的 1071611 —— 专武清单必须包含她的
    //    1060611（蛇毒聚流）与 10102 的 2051611（最初的蒸发）
    const ids = exWeapons.map((w) => Number(w.item_id));
    check(ids.includes(1060611) && ids.includes(2051611) && ids.includes(7070611),
      'allexclusive covers the corrected 10102/10701/10801 exclusives');
    // 控制台发放没有 skipOwned 语义（每次全量入包），重复执行总量按一份专武递增
    await handleCommand('allexclusive 1');
    const doc2 = store.loadPlayer(1);
    check(doc2.bag.items.filter((it) => it.weapon_info).length === before + expected.length,
      'repeat run adds another full set (console grant has no skip_owned)');
  }

  // ---------------- stop ----------------
  {
    const res = await handleCommand('stop');
    check(res.action === 'stop', 'stop reports the stop intent (index.js performs the exit)');
    check(/踢下线|停止/.test(res.reply), 'stop mentions kicking sessions before exiting');
    // 真实的 process.exit 在 index.js 的 onStop 里，这里不执行
  }

  await delay(10);
  fs.rmSync(tmpRoot, { recursive: true, force: true });
  console.log(failures === 0 ? '\nCONSOLE CHECKS PASSED' : `\n${failures} CONSOLE CHECKS FAILED`);
  process.exit(failures === 0 ? 0 : 1);
})().catch((err) => {
  console.error(err.stack || err.message);
  process.exit(1);
});
