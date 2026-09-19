// In-process regression checks for the daily copy loop (每日危航 / d_levels).
//
// Regression target: the main story task 100030201 「尝试一次每日危航」
// (taskContent 10000 = DailyCopyCount) hangs because the server stub answered
// `res_daily_level_fight{result=2}` (LEVEL_LOCKED) to every 出击. The client
// renders that as "cmd:102 code:2" (Helper/ErrorFormatter.lua:98) and never
// enters the level, so the client-side objective counter never ticks.
//
// The loop implemented here: 出击 -> res_daily_level_fight(0) -> client plays
// the level locally -> req_complete_daily_level_fight{result=true} -> server
// consumes one 危航许可 (1201003, falling back to 杀手朋友券 1201001) and grants
// the d_levels drops through ntf_item_info.
//
// No server needed. Must run before requiring the server modules: store.js
// reads GHS_DATA_DIR at load time so the saves stay out of the real data/ dir.
const os = require('os');
const fs = require('fs');
const path = require('path');
const tmpDataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ghs-daily-'));
process.env.GHS_DATA_DIR = tmpDataDir;

const { createPlayerDoc } = require('../src/game/player_new');
const { migratePlayer } = require('../src/game/migrate');
const daily = require('../src/game/daily');
const items = require('../src/game/items');
const social = require('../src/handlers/social');
const gd = require('../src/gamedata');

// d_levels ids per levelType: type 4 owns 13/14/15 — a convenient 3-stage chain
const TYPE = 4;
const LV1 = 13;
const LV2 = 14;
const LV3 = 15;

let failures = 0;
function check(cond, msg) {
  console.log(cond ? `  PASS ${msg}` : `  FAIL ${msg}`);
  if (!cond) failures += 1;
}

function makeSession(accountId) {
  const player = createPlayerDoc(accountId);
  const sent = [];
  return {
    player,
    sent,
    send: (name, msg, result) => sent.push({ name, msg, result }),
  };
}

const last = (s, name) => [...s.sent].reverse().find((x) => x.name === name);
const resultOf = (s, name) => (last(s, name) || {}).result;
const names = (s) => s.sent.map((x) => x.name);
const countOf = (s, itemId) => items.bagCount(s.player, itemId);

// ---------------- table assumptions ----------------
// If these fail the game data changed and the rules below need revisiting.
{
  const c1 = daily.levelConfig(LV1);
  check(!!c1 && c1.levelType === TYPE, `${LV1} is a levelType ${TYPE} stage`);
  check(daily.minLevelId(TYPE) === LV1, `the smallest levelType-${TYPE} id is ${LV1}`);
  check(daily.levelIdsOfType(TYPE).length === 3, `levelType ${TYPE} owns exactly 3 stages`);
  check(Array.isArray(c1.dropID) && c1.dropID.length === (c1.dropMin || []).length,
    `${LV1} dropID/dropMin are parallel arrays`);
  check(gd.query('d_levels', 9999) == null, 'an unknown level id has no config row');
}

// ---------------- unlock rules (client UI_Daily_Copy_C:UnlockLevel) ----------------
{
  const s = makeSession(9201);
  items.grantItems(s.player, [{ item_id: daily.TICKET, count: 5 }]);

  social.handle('req_daily_level_fight')(s, { fight_level_id: LV1 });
  check(resultOf(s, 'res_daily_level_fight') === undefined,
    'the first stage of a levelType is open to a fresh player');
  check(daily.pendingLevelId(s.player) === LV1,
    'starting a fight records it as the pending daily level');

  social.handle('req_daily_level_fight')(s, { fight_level_id: LV3 });
  check(resultOf(s, 'res_daily_level_fight') === 2,
    'a stage two steps ahead is LEVEL_LOCKED (2)');

  social.handle('req_complete_daily_level_fight')(s, { result: true });
  check(daily.pendingLevelId(s.player) === 0, 'completing a fight clears the pending daily level');
  check(daily.hasPassed(s.player, LV1), 'the cleared stage lands in daily_level_id_passed');

  social.handle('req_daily_level_fight')(s, { fight_level_id: LV2 });
  check(resultOf(s, 'res_daily_level_fight') === undefined, 'the next stage unlocks after passing one');
  social.handle('req_daily_level_fight')(s, { fight_level_id: LV3 });
  check(resultOf(s, 'res_daily_level_fight') === 2, 'the stage after that is still locked');

  social.handle('req_daily_level_fight')(s, { fight_level_id: 9999 });
  check(resultOf(s, 'res_daily_level_fight') === 2, 'an unknown level id is LEVEL_LOCKED');
}

// ---------------- ticket consumption + drops ----------------
{
  const s = makeSession(9202);
  const cfg = daily.levelConfig(LV1);
  items.grantItems(s.player, [{ item_id: daily.TICKET, count: 1 }]);
  const ticketBefore = countOf(s, daily.TICKET);
  const bagBefore = cfg.dropID.map((id) => countOf(s, id));

  social.handle('req_daily_level_fight')(s, { fight_level_id: LV1 });
  check(countOf(s, daily.TICKET) === ticketBefore,
    '出击 itself spends nothing (the client only deducts at settlement)');
  check(last(s, 'res_daily_level_fight').msg.fight_uuid !== undefined,
    'res_daily_level_fight carries a fight_uuid');

  social.handle('req_complete_daily_level_fight')(s, { result: true });
  check(countOf(s, daily.TICKET) === ticketBefore - 1, 'clearing consumes exactly one 危航许可');
  check(resultOf(s, 'res_complete_daily_level_fight') === undefined,
    'res_complete_daily_level_fight answers OK');

  const changed = last(s, 'ntf_item_info').msg.changed_item_infos || [];
  check(names(s).lastIndexOf('ntf_item_info') < names(s).lastIndexOf('res_complete_daily_level_fight'),
    'ntf_item_info is sent before the settlement response');
  check(!changed.some((c) => c.item_id === daily.TICKET || c.item_id === daily.SWEEP),
    'the consumed ticket is kept out of the reward ntf (client deducts it locally)');
  check(changed.every((c) => c.count > 0), 'the reward ntf only carries gains');

  for (let i = 0; i < cfg.dropID.length; i++) {
    const c = changed.find((x) => x.item_id === cfg.dropID[i]);
    check(!!c && c.count >= cfg.dropMin[i] && c.count <= cfg.dropMax[i],
      `drop ${cfg.dropID[i]} lands in [${cfg.dropMin[i]}, ${cfg.dropMax[i]}]`);
    check(countOf(s, cfg.dropID[i]) === bagBefore[i] + (c ? c.count : 0),
      `drop ${cfg.dropID[i]} is credited to the bag`);
  }
}

// ---------------- no ticket -> RES_NOT_ENOUGH ----------------
{
  const s = makeSession(9203);
  s.player.bag.items = s.player.bag.items.filter(
    (it) => it.item_id !== daily.TICKET && it.item_id !== daily.SWEEP,
  );
  social.handle('req_daily_level_fight')(s, { fight_level_id: LV1 });
  check(resultOf(s, 'res_daily_level_fight') === 1,
    'no 危航许可 and no 杀手朋友券 -> RES_NOT_ENOUGH (1)');

  // 杀手朋友券 stands in for 危航许可
  items.grantItems(s.player, [{ item_id: daily.SWEEP, count: 2 }]);
  social.handle('req_daily_level_fight')(s, { fight_level_id: LV1 });
  check(resultOf(s, 'res_daily_level_fight') === undefined, '杀手朋友券 can replace 危航许可');
  social.handle('req_complete_daily_level_fight')(s, { result: true });
  check(countOf(s, daily.SWEEP) === 1, 'clearing spends the substitute ticket instead');
}

// ---------------- loss / cancel ----------------
{
  const s = makeSession(9204);
  items.grantItems(s.player, [{ item_id: daily.TICKET, count: 2 }]);
  social.handle('req_daily_level_fight')(s, { fight_level_id: LV1 });
  social.handle('req_complete_daily_level_fight')(s, { result: false });
  check(countOf(s, daily.TICKET) === 2, 'a lost / cancelled run costs no ticket');
  check(!daily.hasPassed(s.player, LV1), 'a lost / cancelled run records no clear');
  check(daily.pendingLevelId(s.player) === 0, 'a lost / cancelled run clears the pending fight');
  check(resultOf(s, 'res_complete_daily_level_fight') === undefined,
    'the cancel path still answers OK so the client can leave the level');
  check(!s.sent.some((x) => x.name === 'ntf_item_info'), 'the cancel path grants no rewards');
}

// ---------------- 「再次挑战」 restarts without a new fight request ----------------
{
  const s = makeSession(9205);
  items.grantItems(s.player, [{ item_id: daily.TICKET, count: 3 }]);
  social.handle('req_daily_level_fight')(s, { fight_level_id: LV1 });
  social.handle('req_complete_daily_level_fight')(s, { result: true });
  check(daily.lastLevelId(s.player) === LV1, 'the last chosen stage is remembered');

  // the client re-enters the level directly (UI_Fight_Start_C.lua:874) and only
  // reports the outcome afterwards
  s.sent.length = 0;
  social.handle('req_complete_daily_level_fight')(s, { result: true });
  check(countOf(s, daily.TICKET) === 1, 'a restarted run still settles (ticket spent)');
  const changed = (last(s, 'ntf_item_info').msg.changed_item_infos) || [];
  check(changed.length > 0, 'a restarted run still pays out the drops');
  check(daily.hasPassed(s.player, LV1), 'the stage stays passed');
}

// ---------------- sweep ----------------
{
  const s = makeSession(9206);
  items.grantItems(s.player, [{ item_id: daily.SWEEP, count: 3 }]);
  social.handle('req_daily_level_sweep')(s, { fight_level_id: LV1 });
  check(resultOf(s, 'res_daily_level_sweep') === 2, 'sweeping an uncleared stage is LEVEL_NOT_PASS (2)');

  social.handle('req_daily_level_fight')(s, { fight_level_id: LV1 });
  social.handle('req_complete_daily_level_fight')(s, { result: true });
  const before = countOf(s, daily.SWEEP);
  social.handle('req_daily_level_sweep')(s, { fight_level_id: LV1 });
  check(resultOf(s, 'res_daily_level_sweep') === undefined, 'sweeping a cleared stage is OK');
  check(countOf(s, daily.SWEEP) === before - 1, 'sweeping spends one 杀手朋友券');
  const changed = (last(s, 'ntf_item_info').msg.changed_item_infos) || [];
  check(changed.length > 0 && !changed.some((c) => c.item_id === daily.SWEEP),
    'sweep rewards go out without the sweep coupon');
  check(names(s).lastIndexOf('ntf_item_info') < names(s).lastIndexOf('res_daily_level_sweep'),
    'sweep sends ntf_item_info before the response');

  s.player.bag.items = s.player.bag.items.filter((it) => it.item_id !== daily.SWEEP);
  social.handle('req_daily_level_sweep')(s, { fight_level_id: LV1 });
  check(resultOf(s, 'res_daily_level_sweep') === 1, 'no 杀手朋友券 left -> RES_NOT_ENOUGH (1)');
}

// ---------------- 04:00 daily permit reset ----------------
// 官方：每天 04:00 危航调度处发 4 个日常任务 + 6 张危航许可（d_word_cn 3874）。
{
  const at = (d, h, m) => Math.floor(new Date(2026, 8, d, h, m, 0).getTime() / 1000);
  check(daily.dailyRefreshBoundary(at(14, 3, 0)) === at(13, 4, 0),
    'before 04:00 the current boundary is yesterday 04:00');
  check(daily.dailyRefreshBoundary(at(14, 4, 0)) === at(14, 4, 0),
    'exactly 04:00 is the current boundary');
  check(daily.dailyRefreshBoundary(at(14, 23, 0)) === at(14, 4, 0),
    'after 04:00 the current boundary is today 04:00');

  const p = createPlayerDoc(9301);
  check(items.bagCount(p, daily.TICKET) === 0, 'a fresh account starts with 0 危航许可');
  const first = daily.grantDailyPermits(p, at(13, 7, 0));
  check(!!first && first.changed_item_infos.some(
    (c) => c.item_id === daily.TICKET && c.count === daily.DAILY_PERMITS),
  `the first login after 04:00 grants ${daily.DAILY_PERMITS} 危航许可`);
  check(items.bagCount(p, daily.TICKET) === daily.DAILY_PERMITS, 'the permits land in the bag');
  check(daily.pickTicket(p) === daily.TICKET, 'the granted permits are usable as fight tickets');
  check(daily.grantDailyPermits(p, at(13, 23, 0)) === null, 'same day: no second grant');
  check(daily.grantDailyPermits(p, at(14, 3, 59)) === null,
    'the grant window ends at 04:00, not midnight');
  check(!!daily.grantDailyPermits(p, at(14, 4, 1)), 'after the next 04:00 a new grant goes out');
  check(items.bagCount(p, daily.TICKET) === daily.DAILY_PERMITS * 2, 'permits accumulate day to day');
}

// ---------------- online across 04:00 (session tick hook) ----------------
{
  const handlers = require('../src/handlers');
  const s = makeSession(9303);
  s.player.daily_copy = { last_level_id: 0 };
  handlers.dailyTick(s);
  const ntf = last(s, 'ntf_item_info');
  check(!!ntf && ntf.msg.changed_item_infos.some((c) => c.item_id === daily.TICKET),
    'the session tick grants the daily permits and pushes ntf_item_info');
  s.sent.length = 0;
  handlers.dailyTick(s);
  check(s.sent.length === 0, 'the session tick is a no-op once today has been granted');
  handlers.dailyTick({ player: null, send: () => { throw new Error('must not send'); } });
  check(true, 'the session tick tolerates a connection without a player');
}

// ---------------- save migration ----------------
{
  const doc = createPlayerDoc(9207);
  delete doc.player.daily_level_fight_info;
  delete doc.player.daily_level_id_passed;
  delete doc.daily_copy;

  check(migratePlayer(doc) === true, 'migration reports a change for a pre-daily-copy save');
  check(doc.player.daily_level_fight_info.fight_level_id === 0,
    'old saves get an idle daily_level_fight_info');
  check(Array.isArray(doc.player.daily_level_id_passed), 'old saves get a daily_level_id_passed array');
  check(doc.daily_copy.last_level_id === 0, 'old saves get the daily_copy marker');
  check(migratePlayer(doc) === false, 'daily migration is idempotent');

  const fresh = createPlayerDoc(9208);
  check(migratePlayer(fresh) === false, 'a fresh account needs no migration');
}

fs.rmSync(tmpDataDir, { recursive: true, force: true });
console.log(failures === 0 ? '\nDAILY CHECKS PASSED' : `\n${failures} DAILY CHECKS FAILED`);
process.exit(failures === 0 ? 0 : 1);
