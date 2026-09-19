// 每日危航（日常副本，d_levels）领域逻辑。
//
// 客户端流程（UI_Daily_Copy_C / UI_Fight_Start_C / BP_GameMode_Fight_C /
// UI_Daily_Settlement_C）：
//   进入副本 -> 出击 -> req_daily_level_fight{fight_level_id}
//     res_daily_level_fight{result=0, fight_uuid} -> 客户端自己载入本地关卡战斗
//   打完 -> req_complete_daily_level_fight{result=true}
//     服务端扣 1 张票、按 d_levels 掉落发奖；
//     先 ntf_item_info(掉落) 再 res_complete_daily_level_fight(result=0)
//   结算界面可「再次挑战」（客户端直接重进，不再发 req_daily_level_fight）
//   或「扫荡」-> req_daily_level_sweep{fight_level_id}
//
// 两条必须遵守的客户端约定：
//  1. 解锁规则与 UI_Daily_Copy_C:UnlockLevel 一致：同一 levelType 内
//     「本类型最小 id 永远开放，其余 id <= 本类型已通关最大 id + 1」。
//  2. 扣票要「静默」：结算界面会自己本地扣一张票
//     （UI_Daily_Settlement_C.lua:108 与 :276 的 AddItemCount(-1)），
//     所以服务端扣票不要把这张票放进 ntf_item_info——否则结算奖励列表里会
//     多出一条 -1 的票，而且本地计数会重复扣一次。
const gd = require('../gamedata');
const items = require('./items');

const TICKET = 1201003; // 危航许可
const SWEEP = 1201001;  // 杀手朋友券（许可不足时顶替；也是扫荡用券）

// 官方：每天 04:00 危航调度处发放 4 个日常任务 + 6 张危航许可
// （d_word_cn 3874「【日常任务/每日危航】每天04:00…6张危航许可」）。
const DAILY_PERMITS = 6;
const REFRESH_HOUR = 4;

// 最近一次 04:00 刷新边界，与客户端 UIUtils.GetDailyRefresh 语义一致（本地时区）。
function dailyRefreshBoundary(nowSec) {
  const d = new Date(nowSec * 1000);
  const t = new Date(d.getFullYear(), d.getMonth(), d.getDate(), REFRESH_HOUR, 0, 0, 0);
  if (t.getTime() / 1000 > nowSec) t.setDate(t.getDate() - 1);
  return Math.floor(t.getTime() / 1000);
}

// 跨过 04:00 边界就补发每日危航许可（幂等）。返回 ntf_item_info 载荷；
// 本日已发过则返回 null。进游戏时在初始背包同步之前调用，客户端直接就能看到；
// 长时间在线则由会话定时器调用并推送 ntf。
function grantDailyPermits(player, nowSec = Math.floor(Date.now() / 1000)) {
  const boundary = dailyRefreshBoundary(nowSec);
  if (!player.daily_copy) player.daily_copy = { last_level_id: 0 };
  const last = Number(player.daily_copy.permit_tick_seconds || 0);
  if (last >= boundary) return null;
  player.daily_copy.permit_tick_seconds = boundary;
  return items.grantItems(player, [{ item_id: TICKET, count: DAILY_PERMITS }]);
}

function levelConfig(levelId) {
  return gd.query('d_levels', levelId);
}

function levelIdsOfType(levelType) {
  return gd.rows('d_levels')
    .map(([, r]) => Number(r.id))
    .filter((id) => Number((levelConfig(id) || {}).levelType) === Number(levelType));
}

function minLevelId(levelType) {
  const ids = levelIdsOfType(levelType);
  return ids.length ? Math.min(...ids) : 0;
}

// 本类型里已通关的最大关卡 id（客户端 UnlockLevel 的等价实现）
function maxPassedLevelId(player, levelType) {
  let max = 0;
  for (const raw of player.player.daily_level_id_passed || []) {
    const id = Number(raw);
    const cfg = levelConfig(id);
    if (cfg && Number(cfg.levelType) === Number(levelType) && id > max) max = id;
  }
  return max;
}

function isLevelUnlocked(player, cfg) {
  if (!cfg) return false;
  if (Number(cfg.id) === minLevelId(cfg.levelType)) return true;
  return Number(cfg.id) <= maxPassedLevelId(player, cfg.levelType) + 1;
}

function hasPassed(player, levelId) {
  return (player.player.daily_level_id_passed || [])
    .some((x) => Number(x) === Number(levelId));
}

// 出击/扫荡要用的票：危航许可优先，不足时用杀手朋友券顶替。
function pickTicket(player) {
  if (items.bagCount(player, TICKET) > 0) return TICKET;
  if (items.bagCount(player, SWEEP) > 0) return SWEEP;
  return 0;
}

// d_levels 的 dropID / dropMin / dropMax / dropOdds 是四组等长平行数组：
// 第 i 项以 dropOdds[i]/10000 的概率掉落 dropMin[i]..dropMax[i] 个。
function rollDrops(cfg) {
  const ids = cfg.dropID || [];
  const min = cfg.dropMin || [];
  const max = cfg.dropMax || [];
  const odds = cfg.dropOdds || [];
  const merged = new Map();
  for (let i = 0; i < ids.length; i++) {
    const chance = odds[i] === undefined ? 10000 : Number(odds[i]);
    if (chance < 10000 && Math.random() * 10000 >= chance) continue;
    const lo = Number(min[i] === undefined ? 0 : min[i]);
    const hi = Number(max[i] === undefined ? lo : max[i]);
    const count = hi > lo ? lo + Math.floor(Math.random() * (hi - lo + 1)) : lo;
    if (count <= 0) continue;
    const itemId = Number(ids[i]);
    merged.set(itemId, (merged.get(itemId) || 0) + count);
  }
  return [...merged].map(([item_id, count]) => ({ item_id, count }));
}

// 记录通关。返回 true 表示这次是新通关（客户端自己也会本地 insert 一次）。
function recordPassed(player, levelId) {
  const id = Number(levelId);
  if (!id) return false;
  const list = player.player.daily_level_id_passed;
  if (!Array.isArray(list)) {
    player.player.daily_level_id_passed = [id];
    return true;
  }
  if (list.some((x) => Number(x) === id)) return false;
  list.push(id);
  return true;
}

function idleFightInfo() {
  return { fight_uuid: '0', fight_level_id: 0, fight_state: 0 };
}

// 进行中的日常副本。登录时客户端读 player_info.daily_level_fight_info，
// fight_level_id > 0 就把玩家送回该关卡（BP_GameInstance_C.lua:1319）。
function pendingFight(player) {
  return player.player.daily_level_fight_info || idleFightInfo();
}

function pendingLevelId(player) {
  return Number(pendingFight(player).fight_level_id || 0);
}

function setPendingFight(player, levelId, uuid) {
  player.player.daily_level_fight_info = {
    fight_uuid: String(uuid),
    fight_level_id: Number(levelId),
    fight_state: 1, // FIGHT_STATE_FIGHTING
  };
}

function clearPendingFight(player) {
  player.player.daily_level_fight_info = idleFightInfo();
}

// 最近一次进入的关卡。客户端「再次挑战」不会再发 req_daily_level_fight
// （UI_Fight_Start_C.lua:874 fightRestart 直接进关），所以结算时必须能靠它
// 还原关卡 id，否则重开一局打完不知道怎么结算。
function lastLevelId(player) {
  return Number((player.daily_copy || {}).last_level_id || 0);
}

function setLastLevelId(player, levelId) {
  if (!player.daily_copy) player.daily_copy = { last_level_id: 0 };
  player.daily_copy.last_level_id = Number(levelId) || 0;
}

module.exports = {
  TICKET, SWEEP, DAILY_PERMITS, REFRESH_HOUR,
  dailyRefreshBoundary, grantDailyPermits,
  levelConfig, levelIdsOfType, minLevelId, maxPassedLevelId, isLevelUnlocked,
  hasPassed, pickTicket, rollDrops, recordPassed,
  idleFightInfo, pendingFight, pendingLevelId, setPendingFight, clearPendingFight,
  lastLevelId, setLastLevelId,
};
