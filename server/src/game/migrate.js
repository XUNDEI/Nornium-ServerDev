// One-time, idempotent migrations applied to a player document on load.
const gd = require('../gamedata');
const items = require('./items');
const furnace = require('./furnace');
const plot = require('./plot');
const daily = require('./daily');
const universe = require('./universe');
const log = require('../logger');

// A stored character is legitimate as long as its d_character row has a
// localizable name. Rows 24001/24002 are dev placeholders (name id 611240xx is
// absent from d_word_cn) that leaked into saves through the old starter filter.
// Note: gacha-owned characters (e.g. 10901) have firstWeapon 0 but do have a
// name, so the check must not look at firstWeapon.
function isStorableCharacter(charId) {
  const cfg = gd.query('d_character', charId);
  return !!(cfg && cfg.name && gd.query('d_word_cn', cfg.name));
}

function migratePlayer(doc) {
  if (!doc || !doc.bag || !Array.isArray(doc.bag.items)) return false;
  let changed = items.normalizeBag(doc);

  // Drop dev placeholder characters, returning their gear to the bag.
  const chars = Array.isArray(doc.characters) ? doc.characters : [];
  for (let i = chars.length - 1; i >= 0; i--) {
    if (isStorableCharacter(chars[i].character_id)) continue;
    const c = chars.splice(i, 1)[0];
    for (const gear of [c.weapon_info, ...(c.arm_infos || [])]) {
      if (gear) doc.bag.items.push(gear);
    }
    changed = true;
  }

  // Synthesis recipes have no in-game unlock item in this build — seed the
  // player's blueprint list so the furnace is usable (see game/furnace.js).
  const p = doc.player;
  if (p) {
    if (!Array.isArray(p.blueprint_ids)) {
      p.blueprint_ids = [];
      changed = true;
    }
    const have = new Set(p.blueprint_ids.map(Number));
    for (const id of furnace.synthesisBlueprintIds()) {
      if (!have.has(id)) {
        p.blueprint_ids.push(id);
        changed = true;
      }
    }
  }

  // Older saves only ever received the root task of the current story node, so
  // declared sub-tasks were missing from `plot_mission_infos` and the story
  // dead-ended (100030017 「尝试一次炼金与分解」 never counted the two furnace
  // actions). Re-expand the list in place — see game/plot.js.
  if (doc.plot && Array.isArray(doc.plot.plot_mission_infos)) {
    const before = doc.plot.plot_mission_infos;
    const after = plot.normalizeMissionInfos(before);
    const same = after.length === before.length
      && after.every((m, i) => m === before[i]);
    if (!same) {
      doc.plot.plot_mission_infos = after;
      changed = true;
    }
  }

  // 每日危航（d_levels）：老存档没有这几个字段。daily_level_fight_info 必须
  // 显式写成空闲态（客户端登录时读 fight_level_id），daily_copy 用于「再次挑战」
  // 时还原关卡 id，daily_level_id_passed 是解锁判定的依据。
  if (p) {
    if (!Array.isArray(p.daily_level_id_passed)) {
      p.daily_level_id_passed = [];
      changed = true;
    }
    if (!p.daily_level_fight_info) {
      p.daily_level_fight_info = daily.idleFightInfo();
      changed = true;
    }
  }
  if (!doc.daily_copy || typeof doc.daily_copy.last_level_id !== 'number') {
    doc.daily_copy = { last_level_id: 0 };
    changed = true;
  }

  // 进行中的星图（肉鸽）局：切换角色的价格必须以 d_srpg_map_base[map_id] 为准。
  // 客户端 UI_character_exchange_C:96/172 就是这么读表的，而早期服务端在
  // req_new_universe_specific 里先按 mapType 选图、再回头改 map_id，于是存档里
  // 留下了「map_id=1000309（表里 [2,0]）但 substitution_cost=[2,50]」的组合：
  // 客户端显示 0 元、按钮永远可点，服务端却每次收 50，扣干后一直回
  // RES_NOT_ENOUGH(4)（「cmd:1018 code:4」）。见 坑 25。
  // 只同步这一个标量，不重建地图布局，以免打断进行中的局。
  const uni = doc.universe;
  if (uni && uni.active) {
    const cost = (gd.query('d_srpg_map_base', uni.map_id) || {}).substitutionCost;
    if (Array.isArray(cost) &&
        JSON.stringify(cost) !== JSON.stringify(uni.substitution_cost)) {
      uni.substitution_cost = cost.slice();
      changed = true;
    }

    // 星图首领必须站在客户端视为「可达」的格子上（state > 1）。旧存档里 boss 落点
    // 是离基地最远的未揭示格子（state 0），客户端 SrpgModel:Init 里的
    // UpdateBossLines → astar.path(nil, ...) 会抛「table index is nil」，把
    // res_*universe* 处理器从中间打断（后面的 Broadcast 不执行 → 不 LoadLevel →
    // 无限转圈卡 loading）。见 坑 26。
    if (universe.ensureBossReachable(uni)) changed = true;

    // 建筑格（可放置卡牌的格子）缺失时补回来。旧服务端按「posId 数字前缀」猜格子
    // 类型，于是教学星图的三个「建筑格」（d_srpg_main_pos_base 102，nameId
    // 102000101）和常规图的游商格（20014）什么都没挂，而 819/829/839 被错挂成商店。
    // 没有 main_pos_card_pos_info 时客户端不会渲染「管理」选项，主线「部署1个建筑」
    // 就永远点不动。add-only：已放置的卡位保持原样。
    if (universe.refreshAttach(uni)) changed = true;

    // 首领波次改为按 d_srpg_level_boss.appearTime 计步出现（见 game/universe.js
    // spawnDueBossWaves）。旧存档开局就把第 0 波放在「离基地最远」的格子上且击杀后
    // 立刻补下一波，于是「败者首领在基地附近出现」的横幅从第 1 步挂着再也消不掉。
    // 这里按 turn（已击杀波数）与 step（已到出现步数的波数）重建存活波次列表，
    // 保留仍在打的 fight_uuid。
    if (universe.reconcileBossWaves(uni)) changed = true;
  }

  // 教学保险：主线「部署/晋升/拆除1个建筑」期间客户端会禁用探索与跃迁
  // （QuestSystem:IsExploreBlocked 读 d_task_story[..].unExplore == 1），玩家没法再去
  // 挣蓝图；若场上那张蓝图凑不出 2 张同名副本，主线 100031203 就永远推不动。
  // 早期版本把三选一做成全表随机（见坑 29），因此所有老存档都会被顶到这个死胡同里——
  // 这里在加载时把缺的同名蓝图补进手牌（幂等，补过的卡记进 universe.repaired_cards）。
  const repaired = universe.repairUnupgradableBuilding(doc);
  if (repaired.length) {
    changed = true;
    log.info(`[migrate] 主线「晋升1个建筑」卡死保险：补发蓝图 ${repaired.join(',')}`
      + `（手牌凑不出同名副本，且当前主线已锁探索）`);
  }
  return changed;
}

module.exports = { migratePlayer, isStorableCharacter };
