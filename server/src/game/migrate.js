// One-time, idempotent migrations applied to a player document on load.
const gd = require('../gamedata');
const items = require('./items');
const furnace = require('./furnace');
const plot = require('./plot');
const daily = require('./daily');
const universe = require('./universe');
const weaponData = require('./weapon_data');
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

// 角色身上这套武器里，同类型中「最好」的那件：稀有度优先，其次练度（武器经验），
// 再次 item_id 小者 —— 后两级只是为了让结果确定（同一个存档每次迁移得到同一件）。
function bestWeaponOfType(doc, type) {
  let best = null;
  for (const it of doc.bag.items) {
    if (items.itemKind(it.item_id) !== 'weapon') continue;
    if (items.weaponType(it.item_id) !== type) continue;
    // 未实装武器不能装到角色身上（详情面板会崩，见 weapon_data.js）。
    if (!weaponData.isReleasedWeapon(it.item_id)) continue;
    if (!best) { best = it; continue; }
    const a = gd.query('d_bag_item_weapon', it.item_id) || {};
    const b = gd.query('d_bag_item_weapon', best.item_id) || {};
    const ra = Number(a.rarity) || 0;
    const rb = Number(b.rarity) || 0;
    if (ra !== rb) { if (ra > rb) best = it; continue; }
    const ea = Number(it.weapon_info && it.weapon_info.exp) || 0;
    const eb = Number(best.weapon_info && best.weapon_info.exp) || 0;
    if (ea !== eb) { if (ea > eb) best = it; continue; }
    if (it.item_id < best.item_id) best = it;
  }
  return best;
}

// 角色装备了「不是自己武器类型」的武器时把它换回同类型武器。
// 为什么会发生：老存档的 item_uuid 有重复（见坑 37），req_character_equip_weapon
// 按 uuid 会命中数组里第一件同名道具，于是玩家点自己的专武（礼器）却装上了一把枪械；
// 而客户端的武器列表是按「当前装备武器的 subType」过滤的（UI_Weapon_Change_C:85-104），
// 装上枪械之后 UI 里只剩枪械可选 —— 玩家自己再也换不回礼器，重登也一样（存进档里了）。
// 修法：把错的武器收回背包，从背包里挑同类型最好的一件装上；背包没有同类型的（极少）
// 就用 d_character.firstWeapon 补一把。幂等，且从不重置玩家存档。
function repairWeaponType(doc, chars) {
  const repaired = [];
  for (const c of chars) {
    const want = items.characterWeaponType(c.character_id);
    if (!want || !c.weapon_info) continue;
    if (items.weaponType(c.weapon_info.item_id) === want) continue;
    const wrong = c.weapon_info;
    const pick = bestWeaponOfType(doc, want);
    if (pick) {
      doc.bag.items.splice(doc.bag.items.indexOf(pick), 1);
      doc.bag.items.push(wrong);
      c.weapon_info = pick;
    } else {
      const starter = (gd.query('d_character', c.character_id) || {}).firstWeapon;
      if (!starter || items.weaponType(starter) !== want) continue;
      doc.bag.items.push(wrong);
      c.weapon_info = items.makeItem(doc, starter, 1);
    }
    repaired.push(`角色 ${c.character_id}：${wrong.item_id}（类型 `
      + `${items.weaponType(wrong.item_id)}）→ ${c.weapon_info.item_id}（类型 ${want}）`);
  }
  return repaired;
}

// 「未实装武器」替换（见 game/weapon_data.js）：把存档里已有的幽灵武器换成同类型里
// 已实装的武器。**原地替换**——只改 item_id，item_uuid / weapon_info（exp / break_times /
// refine_level）全部保留，玩家在它身上投入的经验与光淬不丢。
//
// 为什么需要：早期版本的「发专武」按「同类型稀有度最高、并列取 id 最大」发放，巨刃
// （subType 1）里 id 最大的 7★ 正是 1081601「颂歌」，而它没有模型/图标/展示图、也没有
// d_skill 行 —— 一发下去，客户端的武器详情面板就会因为 GetWeaponSkillDesc 抛错而
// 整体停摆（停在 UMG 设计态：满屏「文本块…」「30#星芒名字」，且没有「攻击力」行）。
// 服务端补不了客户端数据表（坑 14），只能把存档里的换掉。
//
// 目标选择：同 subType、已实装、稀有度最接近原武器（同级取 id 最大）。幂等。
function repairUnreleasedWeapons(doc) {
  const replaced = [];
  const swap = (entry, where) => {
    if (!entry || items.itemKind(entry.item_id) !== 'weapon') return;
    if (weaponData.isReleasedWeapon(entry.item_id)) return;
    const cfg = gd.query('d_bag_item_weapon', entry.item_id) || {};
    const pick = weaponData.bestReleasedWeaponOfType(cfg.subType, Number(cfg.rarity) || 0);
    if (!pick || pick === Number(entry.item_id)) return;
    const from = entry.item_id;
    entry.item_id = pick;
    replaced.push(`${from} → ${pick}（${where}，练度保留）`);
  };
  for (const it of doc.bag.items) swap(it, '背包');
  for (const c of doc.characters || []) swap(c.weapon_info, `角色 ${c.character_id}`);
  return replaced;
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

  // 背包/角色装备的 item_uuid 去重（坑 37）。必须排在下面所有「按 uuid 找道具」的
  // 逻辑之前：老存档里同一件 uuid 被分给了多件道具（早期 next_uuid 计数被重置过），
  // 而服务端一律 `find` 取数组里第一个命中，于是「客户端点的是 A、服务端动的是 B」。
  // 莎乐美那把枪就是这么来的：她的专武 4072601（礼器）和 2020400（枪械）共用
  // uuid 43，且枪械排在前 → req_character_equip_weapon 装上了枪械。
  const renamed = items.dedupeItemUuids(doc);
  if (renamed) {
    changed = true;
    log.info(`[migrate] 背包 uuid 去重：${renamed} 件道具重新分配了 item_uuid`
      + '（老存档里同一 uuid 被多件道具共用，按 uuid 的操作会错位）');
  }

  // 星位（d_character_inborn）：早期存档的 talent_ids 可能整个缺失。星位是
  // req_character_unlock_talent 在服务端落盘的内容（见 game/talent.js、坑 40），
  // 缺字段会让 handler 与客户端两侧的数组操作错位，这里补成空数组。幂等。
  for (const c of chars) {
    if (!Array.isArray(c.talent_ids)) {
      c.talent_ids = [];
      changed = true;
    }
  }

  // 抽卡重复角色计数（第 2~7 次 → 星位之钉，第 8 次起只给珊瑚劫灰，见 game/gacha.js）。
  // 老存档没有这个字段，补一个空表；计数是「获得的第几次」，首次重复时懒补 1。
  if (doc.gacha) {
    if (!doc.gacha.char_obtain_times || typeof doc.gacha.char_obtain_times !== 'object') {
      doc.gacha.char_obtain_times = {};
      changed = true;
    }
  } else {
    doc.gacha = { type_infos: {}, records: [], pending: {}, char_obtain_times: {} };
    changed = true;
  }

  // 装备了「非本类型武器」的角色换回本类型武器（见 repairWeaponType）。
  const fixedWeapons = repairWeaponType(doc, chars);
  if (fixedWeapons.length) {
    changed = true;
    log.info(`[migrate] 武器类型修复：${fixedWeapons.join('；')}`);
  }

  // 未实装武器（幽灵武器）换成同类型的已实装武器。排在 repairWeaponType 之后：
  // 后者只保证「类型对」，前者保证「这件武器在客户端能正常显示」。
  const swapped = repairUnreleasedWeapons(doc);
  if (swapped.length) {
    changed = true;
    log.info(`[migrate] 未实装武器替换：${swapped.join('；')}`
      + '（原武器在客户端没有模型/图标/技能行，详情面板会崩）');
  }

  // 幽灵道具清理：任何一张表里都没有配置的 item_id（旧版 req_use_item 曾把「皮肤 id /
  // 角色 id」当成道具 id 发进背包，比如用了皮肤卡后背包里多出 1010101）。客户端渲染
  // 这种道具只会得到一行乱码占位，直接删。幂等。
  const ghosts = [];
  for (let i = doc.bag.items.length - 1; i >= 0; i--) {
    if (items.itemConfig(doc.bag.items[i].item_id)) continue;
    ghosts.push(doc.bag.items[i].item_id);
    doc.bag.items.splice(i, 1);
  }
  if (ghosts.length) {
    changed = true;
    log.info(`[migrate] 清理幽灵道具 ${ghosts.length} 件（表里没有配置的 item_id：`
      + `${[...new Set(ghosts)].join(',')}）`);
  }

  // 皮肤（时装）：解锁列表/穿戴字段兜底 + 默认皮肤（dressInitial==1）+ 背包皮肤卡就地
  // 解锁。皮肤卡的「使用」链路修好之前，玩家可能已经拿到过皮肤卡却一直显示未解锁，
  // 加载时自动补齐（幂等）。见 game/skins.js。
  const skinChars = require('./skins').migrateSkins(doc);
  if (skinChars.length) {
    changed = true;
    log.info(`[migrate] 皮肤解锁补齐：角色 ${skinChars.map((c) => c.character_id).join(',')}`);
  }

  // 主角与剧情同伴必须在场：所有剧情星图的出场角色表（d_srpg_map_specific.character）
  // 只声明了信风(10501)与鱼啄雨(11202)，缺了剧情就没法打。开局没发全角色的存档、
  // 以及任何缺这两个角色的旧档都在这里补齐（幂等）。见 game/player_new.starterCharacterIds。
  const playerNew = require('./player_new');
  for (const charId of playerNew.starterCharacterIds()) {
    if (doc.characters.some((c) => c.character_id === charId)) continue;
    doc.characters.push(playerNew.buildCharacter(doc, charId));
    changed = true;
    log.info(`[migrate] 补开局角色 ${charId}（剧情星图角色表要求在场）`);
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

  // 僵尸剧情局（坑 43）：applyEffect 的 case 99 落地前踩过「终点」格的剧情局不会
  // 结算，客户端又会一直复用这局（不重开），表现为「跃迁到终点没事件 + 血量继承
  // 上一局」。终点已探索（state 3）却还 active 的剧情局只能是这种残留 —— 就地结束，
  // 重登后由 req_new_universe_specific 重新开新局（startHP 满值）。
  if (universe.stuckStoryRun(doc)) {
    log.info(`[migrate] 清除僵尸剧情局 map=${doc.universe.map_id}（终点格已探索但未结算，坑 43）`);
    doc.universe = null;
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

module.exports = { migratePlayer, isStorableCharacter, repairUnreleasedWeapons };
