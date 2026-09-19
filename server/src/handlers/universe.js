// Universe (Srpg roguelike) message handlers.
const gd = require('../gamedata');
const items = require('../game/items');
const U = require('../game/universe');
const { savePlayer, requirePlayer } = require('./sync');
const log = require('../logger');

const HAND_LEN_MAX = U.HAND_LEN_MAX;
// 未确认语义的 effectType 只提示一次（见 applyEffect 的 default 分支）
const warnedEffectTypes = new Set();

function uni(session) {
  const u = session.player.universe;
  if (!u || !u.active) return null;
  return u;
}

function sendUniverseInfo(session, u, resChanges, hpDelta) {
  // res_value must always decode to a non-empty table client-side — send the
  // full 4-slot delta array even when most entries are 0.
  session.send('ntf_universe_info', {
    res_value: U.resourceDeltas(u, resChanges),
    cur_hp: hpDelta || undefined,
  });
}

function rewardWindow(session, triggerId, fn) {
  const cfg = gd.query('d_srpg_effect_trigger', triggerId);
  session.send('ntf_effect_trigger_begin', { trigger_id: cfg ? triggerId : 101 });
  fn();
  session.send('ntf_effect_trigger_end', {});
}

function grantUniverseItems(session, grants) {
  const ntf = items.grantItems(session.player, grants);
  session.send('ntf_item_info', ntf);
}

function encCardSelect(sel) {
  return {
    select_uuid: String(sel.select_uuid),
    card_ids: sel.card_ids.slice(),
    refresh_times: sel.refresh_times,
    pool_id: sel.pool_id,
  };
}

function sendCardSelect(session, sel) {
  session.send('ntf_add_cards_for_select', { cards_for_select: encCardSelect(sel) });
}

function sendCurioSelect(session, sel) {
  session.send('ntf_add_curios_for_select', {
    curios_for_select: {
      select_uuid: String(sel.select_uuid),
      curio_ids: sel.curio_ids,
      refresh_times: sel.refresh_times,
      pool_id: sel.pool_id,
    },
  });
}

function sendEventInfo(session, ev) {
  session.send('ntf_event_info', {
    event_info: {
      event_uuid: String(ev.event_uuid),
      event_id: ev.event_id,
      options: ev.options.map((o) => ({ option_id: o.option_id, enabled: true })),
    },
  });
}

// d_srpg_level_base[id].winEffectTriggerId / loseEffectTriggerId 是这一关的结算效果
// **列表**（老代码 `list[0]` 只取第一个，于是等级 25 的 [6031,2050] 会白丢 +50 金刚凝胶）。
function levelTriggerIds(levelId, win) {
  const cfg = gd.query('d_srpg_level_base', levelId);
  const ids = cfg ? (win ? cfg.winEffectTriggerId : cfg.loseEffectTriggerId) : null;
  return U.intArray(ids).filter((t) => !!gd.query('d_srpg_effect_trigger', t));
}

// 依次执行一组效果；返回是否有任何一个真的产生了效果（供调用方决定要不要走兜底）。
// 效果可能直接把这一局打结束（生存值归零 → settleRun），所以每一步后都要重新取局。
function applyEffects(session, u, triggerIds) {
  let handled = false;
  for (const tid of triggerIds) {
    if (!session.player.universe) break;
    if (applyEffect(session, u, tid)) handled = true;
  }
  return handled;
}

function triggerFor(kind, levelId, win) {
  const ids = levelTriggerIds(levelId, win);
  return ids[0] ?? (win ? 307 : 5001);
}

// ---------------- d_srpg_effect_trigger：效果派发 ----------------
//
// 一条「效果」由 `effectType` + `effectConfig` 描述。老代码读的是 `cfg.config`
// （这个字段在表里根本不存在）→ 所有效果都退化成硬编码兜底：探索到的格子永远开占位
// 事件 20001、遭遇战永远随机抽关卡、**卡牌三选一永远从全部 171 张 d_srpg_card_base
// 里抽**。于是教学事件 11007「你获得了3张相同的建筑蓝图」（option 110071 的
// effectTriggerID = [6060,6060,6060]，每次给 10015）永远凑不出同名卡，
// 主线 100031203「晋升1个建筑」永久卡死。
//
// 已逐类核对（全表 482 行按 effectType 统计 + 每类抽样对照表数据）：
//   1   资源增减      effectConfig = [d1,d2,d3,d4]（4 个资源的增量，如 2050 → +50 金刚凝胶）
//   2   生存值        effectConfig = [delta]（5001 → -1）
//   3   舰武载弹      effectConfig = [delta]（4001 → +1）
//   11  卡牌三选一    effectConfig = [d_srpg_card_list 行号 + 1]（如 6049/6031；
//                     ≥100 时改查 d_srpg_card_pool 的合并池）
//   12  异宝三选一    effectConfig = [curioPoolId]
//   13  卡牌三选一    effectConfig = [卡牌 id...]
//   15  卡牌三选一    effectConfig = [卡牌 id...]（游商 6001..6019 / 事件 6049/6060/6231）
//   20  事件          effectConfig = [eventId]（选项 = eventId*10+n）
//   30  遭遇战        effectConfig = [fightLevelId]
//   60  发放道具      effectConfig = [item_id, itemType, count, ...]（可多组）
//   201 剧情          effectConfig = [storyId, ...]（客户端在 ntf_effect_trigger_begin 自己播）
// 其余（9/10/17/21/99/100/121/122）语义未确认，只记日志不处理；其中 121/122 是卡位标记
// （effectConfig 就是 d_srpg_card_pos 的行号），而格子类型已经由 attachForPos 按
// d_srpg_main_pos_base 判定，不需要它。
function applyEffect(session, u, triggerId) {
  const cfg = gd.query('d_srpg_effect_trigger', triggerId);
  if (!cfg) return false;
  const conf = U.intArray(cfg.effectConfig);
  switch (Number(cfg.effectType)) {
    case 1: { // 资源增减
      const deltas = [0, 0, 0, 0];
      for (let i = 0; i < 4; i++) deltas[i] = conf[i] ?? 0;
      if (!deltas.some((d) => d !== 0)) return false;
      for (let i = 0; i < 4; i++) U.changeResource(u, i + 1, deltas[i]);
      session.send('ntf_universe_info', { res_value: deltas });
      return true;
    }
    case 2: { // 生存值
      const delta = conf[0] ?? 0;
      if (!delta) return false;
      u.cur_hp += delta;
      session.send('ntf_universe_info', { res_value: [0, 0, 0, 0], cur_hp: delta });
      if (u.cur_hp <= 0) {
        session.send('ntf_universe_clear', { result: false });
        settleRun(session, false);
      }
      return true;
    }
    case 3: { // 舰武载弹
      const delta = conf[0] ?? 0;
      if (!delta) return false;
      u.universe_fight_data.boat_energy = Math.max(
        0, (u.universe_fight_data.boat_energy || 0) + delta,
      );
      return true;
    }
    case 11: { // 卡牌三选一（按 d_srpg_card_list 行号）
      const cards = U.cardsForEffectConfig(conf[0]);
      if (!cards.length) return false;
      const sel = U.addCardSelect(u, cards);
      rewardWindow(session, triggerId, () => sendCardSelect(session, sel));
      return true;
    }
    case 12: { // 异宝三选一
      const list = U.curioPoolList(conf[0]);
      if (!list.length) return false;
      // 异宝一次只能开一个面板（客户端 SrpgModel.curiosForSelect 也是单槽），
      // 已经有待选的就不再叠一个
      if (u.curios_for_select) return false;
      const sel = U.makeCurioSelect(u, list);
      rewardWindow(session, triggerId, () => sendCurioSelect(session, sel));
      return true;
    }
    case 13:
    case 15: { // 卡牌三选一（按 effectConfig 里显式列出的卡表）
      const cards = U.cardListOf(conf);
      if (!cards.length) return false;
      const sel = U.addCardSelect(u, cards);
      rewardWindow(session, triggerId, () => sendCardSelect(session, sel));
      return true;
    }
    case 20: { // 事件
      const ev = U.makeEvent(u, conf[0]);
      if (!ev) return false;
      sendEventInfo(session, ev);
      return true;
    }
    case 30: { // 遭遇战
      const level = gd.query('d_srpg_level_base', conf[0]) ? conf[0] : U.randomEncounterLevel();
      const f = U.newFight(u, level);
      session.send('ntf_fight_info', {
        fight_info: {
          fight_uuid: String(f.fight_uuid),
          fight_level_id: f.fight_level_id,
          fight_state: f.fight_state,
        },
      });
      return true;
    }
    case 60: { // 发放道具（[item_id, itemType, count] 三元组，可多组）
      const grants = [];
      for (let i = 0; i + 2 < conf.length; i += 3) {
        if (conf[i + 2]) grants.push({ item_id: conf[i], count: conf[i + 2] });
      }
      if (!grants.length) return false;
      rewardWindow(session, triggerId, () => grantUniverseItems(session, grants));
      return true;
    }
    case 201: // 剧情：客户端在 ntf_effect_trigger_begin 里自己播
      rewardWindow(session, triggerId, () => {});
      return true;
    default:
      // 每种未确认的类型只记一次，免得每次探索都刷屏（教学格子上普遍挂着 [2,3]）
      if (!warnedEffectTypes.has(Number(cfg.effectType))) {
        warnedEffectTypes.add(Number(cfg.effectType));
        log.info(`[universe] effectType ${cfg.effectType} has no handler yet (trigger ${triggerId} ignored)`);
      }
      return false;
  }
}

// ---------------- run lifecycle ----------------

function reqNewUniverse(session, req) {
  if (!requirePlayer(session)) return;
  const u = U.newUniverse(req);
  session.player.universe = u;
  U.makeMission(u);
  session.send('res_new_universe', { universe_info: U.buildUniverseInfo(u) });
  session.send('ntf_mission_info', {
    mission_info: {
      mission_uuid: String(u.missions[0].mission_uuid),
      mission_id: u.missions[0].mission_id,
      mission_elapsed: 0,
      mission_result: 0,
      mission_begin_turn: u.missions[0].begin_turn,
      mission_begin_step: u.missions[0].begin_step,
    },
  });
  savePlayer(session);
  log.info(`[universe] new run: map=${u.map_id} boss=${u.boss_id} hp=${u.cur_hp} chars=${JSON.stringify(req.character_ids)}`);
}

function reqNewUniverseSpecific(session, req) {
  if (!requirePlayer(session)) return;
  const specific = gd.query('d_srpg_map_specific', Number(req.specific_id ?? 0));
  const charIds = session.player.characters.slice(0, 3).map((c) => c.character_id);
  const params = {
    difficulty_value: specific?.difficulty ?? 1,
    main_planet_id: specific?.universe ?? 101,
    map_type: 1,
    character_ids: charIds,
  };
  // Build the run straight from the specific's own d_srpg_map_base row: layout,
  // boss, startHP, initial resources and substitutionCost must all belong to
  // this map. Previously map_id was overwritten after the fact, so the run kept
  // mapType-1's substitutionCost — see 坑 25.
  const u = U.newUniverse(params, specific?.map ?? null);
  u.specific_id = Number(req.specific_id ?? 0);
  session.player.universe = u;
  U.makeMission(u);
  session.send('res_new_universe_specific', { universe_info: U.buildUniverseInfo(u) });
  savePlayer(session);
}

function settleRun(session, win) {
  const u = session.player.universe;
  if (!u) return;
  const gold = 500 + 300 * u.difficulty_value;
  const exp = 200 + 150 * u.difficulty_value;
  rewardWindow(session, win ? 307 : 5001, () => {
    grantUniverseItems(session, [
      { item_id: items.CURRENCY.GOLD, count: gold },
      { item_id: items.CURRENCY.EXP, count: exp },
      { item_id: items.CURRENCY.DIAMOND, count: win ? 50 : 10 },
    ]);
  });
  session.player.universe = null;
  savePlayer(session);
  log.info(`[universe] run settled win=${win}`);
}

function reqCompleteUniverse(session) {
  if (!requirePlayer(session)) return;
  const u = uni(session);
  if (!u) return session.send('res_complete_universe', {}, 1); // EMPTY_UNIVERSE
  session.send('res_complete_universe', {});
  settleRun(session, false);
  session.send('ntf_universe_clear', { result: false });
}

// ---------------- exploration ----------------

function reqExplore(session, req) {
  if (!requirePlayer(session)) return;
  const u = uni(session);
  if (!u) return session.send('res_explore', {}, 1);
  const hex = { q: Number(req.hex?.q ?? 0), r: Number(req.hex?.r ?? 0) };
  const pos = U.posAt(u, hex);
  if (!pos) return session.send('res_explore', {}, 4); // NO_POS
  if (pos.state !== 2) return session.send('res_explore', {}, 5); // STATE_INVALID

  pos.state = 3;
  u.step += 1;
  session.send('res_explore', {});

  // reveal frontier (cascades through auto-explored transit cells)
  const changed = U.revealFrontier(u.main_pos, hex);
  if (changed.length) {
    session.send('ntf_main_pos_state_change', {
      main_pos_state_changes: changed.map((c) => ({ hex: U.encHex(c.hex), state: c.state })),
    });
  }

  exploreConsequence(session, u, pos);
  if (!session.player.universe) return savePlayer(session);

  // 官方：败者首领「每回合向巡航基地移动1格」，抵达基地后「每回合扣取1点生存值」
  //（d_word_cn 113211012 / 113220008）。「每回合」在这里就是花掉一步的这次 req_explore。
  // 先推进（本回合新出现的波次不会被同时推进，见下），再补发到点的波次。
  const adv = U.advanceBosses(u);
  if (adv.revealed.length) {
    session.send('ntf_main_pos_state_change', {
      main_pos_state_changes: adv.revealed.map((c) => ({ hex: U.encHex(c.hex), state: c.state })),
    });
  }
  if (adv.changed) ntfBossInfo(session, u);
  if (adv.damage > 0) sendUniverseInfo(session, u, {}, -adv.damage);
  if (adv.dead) {
    session.send('ntf_universe_clear', { result: false });
    settleRun(session, false);
    return savePlayer(session);
  }

  // d_srpg_level_boss waves appear on their own appearTime step; check after the
  // step was spent and before the client is told anything else.
  announceDueBossWaves(session, u);

  // mission completion by steps
  for (const m of u.missions) {
    if (m.result === 0 && u.step - m.begin_step >= 5) {
      m.result = 1;
      m.end_turn = u.turn;
      m.end_step = u.step;
      session.send('ntf_mission_result', {
        mission_uuid: String(m.mission_uuid),
        mission_result: 1,
        mission_end_turn: u.turn,
        mission_end_step: u.step,
      });
    }
  }
  savePlayer(session);
}

// 踩到一个格子：挨个执行 onExploreEffectTriggerID 里的效果（见 applyEffect）。
// 一个效果都没触发时，才按格子 id 归属给一点保底资源（原有的风味掉落）。
function exploreConsequence(session, u, pos) {
  const rnd = (a, b) => a + Math.floor(Math.random() * (b - a + 1));
  const posCfg = gd.query('d_srpg_main_pos_base', pos.main_pos_id);
  const triggers = [...new Set(U.intArray(posCfg && posCfg.onExploreEffectTriggerID))];

  if (applyEffects(session, u, triggers)) return;
  if (!session.player.universe) return;

  // fallback flavour by pos id family: minor resource pickups
  const id = pos.main_pos_id;
  if (id >= 20000 && id < 30000) return; // event-family cell already handled or skipped
  const prefix = Math.floor(id / 100);
  if (prefix === 3 || prefix === 9) sendUniverseInfo(session, u, { 3: rnd(20, 40) }, 0);
  else sendUniverseInfo(session, u, { 1: rnd(10, 20) }, 0);
}

// ---------------- fights ----------------

function reqUniverseFight(session, req) {
  const u = uni(session);
  if (!u) return session.send('res_universe_fight', {}, 1);
  const uuid = Number(req.fight_uuid ?? 0);
  const f = u.fight_infos.find((x) => Number(x.fight_uuid) === uuid);
  if (!f) return session.send('res_universe_fight', {}, 2); // NO_FIGHT
  f.fight_state = 1; // idempotent for reconnection re-entry
  session.send('res_universe_fight', {});
}

function applyFightData(u, data) {
  if (!data) return;
  if (Array.isArray(data.character_fight_datas)) {
    const list = data.character_fight_datas.slice(0, 3);
    for (let i = 0; i < 3; i++) {
      const c = list[i];
      if (c && Number(c.character_id) > 0) {
        u.universe_fight_data.character_fight_datas[i] = {
          character_id: Number(c.character_id),
          cur_hp: Number(c.cur_hp ?? 0),
        };
      }
    }
  }
  if (data.boat_energy !== undefined) u.universe_fight_data.boat_energy = Number(data.boat_energy);
  if (data.character_changed_times !== undefined) {
    u.universe_fight_data.character_changed_times = Number(data.character_changed_times);
  }
}

function reqCompleteUniverseFight(session, req) {
  const u = uni(session);
  if (!u) return session.send('res_complete_universe_fight', {}, 1);
  const uuid = Number(req.fight_uuid ?? 0);
  const idx = u.fight_infos.findIndex((x) => Number(x.fight_uuid) === uuid);
  if (idx < 0) return session.send('res_complete_universe_fight', {}, 3); // NO_FIGHT
  const fight = u.fight_infos[idx];
  const win = !!req.result;
  applyFightData(u, req.universe_fight_data);
  u.fight_infos.splice(idx, 1);
  session.send('res_complete_universe_fight', {});

  const triggers = levelTriggerIds(fight.fight_level_id, win);
  if (win) {
    // 这一关的奖励就是 d_srpg_level_base[id].winEffectTriggerId 里的那几条效果
    // （等级 25 → [6031（一张建筑蓝图）, 2050（+50 金刚凝胶）]；等级 101 → [301] 道具）。
    // 老代码只取第 0 条、再叠一份硬编码的金币/经验，还会额外 60% 概率塞一张
    // 「全表随机」的蓝图 —— 那正是玩家手里那一堆凑不出同名的怪卡片的来源。
    // 每条效果自己会发 ntf_effect_trigger_begin/end，所以这里不再套一层窗口。
    const handled = applyEffects(session, u, triggers);
    if (!handled) {
      rewardWindow(session, 307, () => grantUniverseItems(session, [
        { item_id: items.CURRENCY.GOLD, count: 150 + 50 * u.difficulty_value },
        { item_id: items.CURRENCY.EXP, count: 80 },
      ]));
    }
  } else {
    // 失败惩罚同理：loseEffectTriggerId 通常是 [5001]（生存值 -1，归零即终结这一局）
    const handled = applyEffects(session, u, triggers);
    if (!handled) {
      u.cur_hp -= 1;
      sendUniverseInfo(session, u, {}, -1);
      if (u.cur_hp <= 0) {
        session.send('ntf_universe_clear', { result: false });
        settleRun(session, false);
        return;
      }
    }
  }
  savePlayer(session);
}

function bossPath(u) {
  const cfg = gd.query('d_srpg_level_boss', u.boss_id);
  return cfg ? (cfg.path || []) : [];
}

function ntfBossInfo(session, u) {
  session.send('ntf_boss_info', {
    boss_infos: u.boss_infos.map((b) => ({
      boss_index: b.boss_index,
      fight_uuid: String(b.fight_uuid),
      hex: U.encHex(b.hex),
    })),
  });
}

// Announce any d_srpg_level_boss.appearTime wave the current step has reached.
// The reveal must be pushed before ntf_boss_info: SrpgModel:UpdateBossInfo runs
// UpdateBossLines → astar from the boss hex, and a start node the client still
// considers unreachable throws "table index is nil" (坑 26).
function announceDueBossWaves(session, u) {
  const revealed = U.spawnDueBossWaves(u);
  if (!revealed) return false;
  if (revealed.length) {
    session.send('ntf_main_pos_state_change', {
      main_pos_state_changes: revealed.map((c) => ({ hex: U.encHex(c.hex), state: c.state })),
    });
  }
  ntfBossInfo(session, u);
  return true;
}

function reqBossFight(session, req) {
  const u = uni(session);
  if (!u) return session.send('res_boss_fight', {}, 1);
  const bossIndex = Number(req.boss_index ?? 0);
  const boss = u.boss_infos.find((b) => b.boss_index === bossIndex);
  if (!boss) return session.send('res_boss_fight', {}, 3); // NO_BOSS
  const path = bossPath(u);
  const level = path[bossIndex] ?? path[0] ?? 101;
  const f = U.newFight(u, level);
  f.fight_state = 1;
  boss.fight_uuid = f.fight_uuid;
  session.send('res_boss_fight', {
    fight_info: { fight_uuid: String(f.fight_uuid), fight_level_id: level, fight_state: 1 },
  });
  savePlayer(session);
}

function reqCompleteBossFight(session, req) {
  const u = uni(session);
  if (!u) return session.send('res_complete_boss_fight', {}, 1);
  const bossIndex = Number(req.boss_index ?? 0);
  const boss = u.boss_infos.find((b) => b.boss_index === bossIndex);
  if (!boss) return session.send('res_complete_boss_fight', {}, 2); // NO_BOSS
  const fightIdx = u.fight_infos.findIndex((x) => Number(x.fight_uuid) === Number(boss.fight_uuid));
  const win = !!req.result;
  applyFightData(u, req.universe_fight_data);
  if (fightIdx >= 0) u.fight_infos.splice(fightIdx, 1);
  session.send('res_complete_boss_fight', {});

  if (win) {
    // The client does the same bookkeeping itself in
    // SrpgModel:CompleteCurrentBossFight (drops the fight, drops the boss info
    // with that fight_uuid, then `turn = turn + 1`); `turn` is what the banner
    // counts against in GetBossCount(). Keep the server's copy in step so a
    // reconnect does not hand the client a stale counter.
    u.turn += 1;
    u.boss_infos = u.boss_infos.filter((b) => b !== boss);
    const bossLevel = bossPath(u)[bossIndex] ?? bossPath(u)[0] ?? 101;
    // 首领战的奖励同样来自该关的 winEffectTriggerId（老代码只取第 0 条 + 一份
    // 硬编码金币/经验，首领关卡表里的东西全丢了）。applyEffects 自己发触发窗口。
    const handled = applyEffects(session, u, levelTriggerIds(bossLevel, true));
    if (!handled) {
      rewardWindow(session, triggerFor('boss', bossLevel, true), () => {
        grantUniverseItems(session, [
          { item_id: items.CURRENCY.GOLD, count: 400 + 100 * u.difficulty_value },
          { item_id: items.CURRENCY.EXP, count: 200 },
          { item_id: items.CURRENCY.DIAMOND, count: 30 },
        ]);
        sendUniverseInfo(session, u, { 2: 30, 3: 30 }, 0);
      });
    }
    // 击杀首领同样给一个异宝三选一
    if (!u.curios_for_select) sendCurioSelect(session, U.makeCurioSelect(u));
    // The next wave is NOT spawned here: it appears when its own
    // d_srpg_level_boss.appearTime step is reached. Spawning it right away is
    // what kept the 「败者」首领 banner on screen forever after every kill —
    // see game/universe.js spawnDueBossWaves.
    //
    // The run is won when no boss is left AND every wave has already appeared
    // (the player may kill wave 2 while 0/1 are still walking around, so "the
    // highest index is dead" is not enough).
    const path = bossPath(u);
    const moreWavesToCome = u.boss_wave < path.length - 1;
    if (u.boss_infos.length === 0 && !moreWavesToCome) {
      session.send('ntf_universe_clear', { result: true });
      settleRun(session, true);
      return;
    }
    // A later wave may already be due (e.g. the player explored past two
    // appearTime marks before fighting), so announce whatever is now scheduled
    // and push the boss cell reveal ahead of it (坑 26).
    announceDueBossWaves(session, u);
  } else {
    boss.fight_uuid = '0';
    const level = bossPath(u)[bossIndex] ?? bossPath(u)[0] ?? 101;
    if (!applyEffects(session, u, levelTriggerIds(level, false))) {
      u.cur_hp -= 1;
      sendUniverseInfo(session, u, {}, -1);
      if (u.cur_hp <= 0) {
        session.send('ntf_universe_clear', { result: false });
        settleRun(session, false);
      }
    }
  }
  savePlayer(session);
}

// ---------------- cards ----------------
//
// 一次事件可以同时开好几次三选一（教学 11007 → [6060,6060,6060] =「获得三张卡牌」），
// 客户端把 SelectCard 事件排队、一次只弹一个面板，所以这里按 select_uuid 在所有
// 进行中的选择里查（U.findCardSelect / U.dropCardSelect）。

function reqCreateChooseCard(session, req) {
  const u = uni(session);
  if (!u) return session.send('res_create_choose_card', {}, 1);
  const sel = U.findCardSelect(u, req.select_uuid);
  if (!sel) return session.send('res_create_choose_card', {}, 2); // NO_SELECT
  session.send('res_create_choose_card', { card_ids: sel.card_ids });
  savePlayer(session);
}

function reqChooseCard(session, req) {
  const u = uni(session);
  if (!u) return session.send('res_choose_card', {}, 1);
  const sel = U.findCardSelect(u, req.select_uuid);
  if (!sel) return session.send('res_choose_card', {}, 2);
  const cardId = sel.card_ids[Number(req.index ?? 0)];
  U.dropCardSelect(u, sel.select_uuid);
  session.send('res_choose_card', {});
  if (cardId) {
    if (u.cards.length < HAND_LEN_MAX) {
      u.cards.push(cardId);
      session.send('ntf_add_card', { card_ids: [cardId], missed_card_ids: [] });
    } else {
      u.missed_cards.push(cardId);
      session.send('ntf_add_card', { card_ids: [], missed_card_ids: [cardId] });
    }
  }
  savePlayer(session);
}

function reqRefreshChooseCard(session, req) {
  const u = uni(session);
  if (!u) return session.send('res_refresh_choose_card', {}, 1);
  const sel = U.findCardSelect(u, req.select_uuid);
  if (!sel) return session.send('res_refresh_choose_card', {}, 2);
  const pool = gd.query('d_srpg_card_pool', sel.pool_id) || gd.table('d_srpg_card_pool')[0];
  const cost = pool?.refreshCost || [2, 10];
  const maxTimes = pool?.refreshTime ?? 99;
  if (sel.refresh_times >= maxTimes) return session.send('res_refresh_choose_card', {}, 4); // MAX_TIMES
  if (!U.spendResource(u, cost[0], cost[1])) return session.send('res_refresh_choose_card', {}, 5);
  U.refreshCardSelect(u, sel);
  session.send('res_refresh_choose_card', { card_ids: sel.card_ids });
  sendUniverseInfo(session, u, { [cost[0]]: -cost[1] }, 0);
  savePlayer(session);
}

function cardAttach(u, req) {
  const pos = U.posAt(u, { q: Number(req.hex?.q ?? 0), r: Number(req.hex?.r ?? 0) });
  if (!pos) return null;
  const idx = Number(req.attach_index ?? 0);
  const a = pos.attach && pos.attach.main_pos_card_pos_info ? pos.attach : null;
  return a ? { pos, attach: a.main_pos_card_pos_info } : null;
}

function reqPlaceCard(session, req) {
  const u = uni(session);
  if (!u) return session.send('res_place_card', {}, 1);
  const ca = cardAttach(u, req);
  const handIdx = Number(req.index_in_hand ?? 0);
  if (!ca || ca.attach.card_id !== 0 || u.cards[handIdx] === undefined) {
    return session.send('res_place_card', {}, 5); // CARD_NOT_FOUND
  }
  ca.attach.card_id = u.cards.splice(handIdx, 1)[0];
  session.send('res_place_card', {});
  savePlayer(session);
}

function reqUpgradeCard(session, req) {
  const u = uni(session);
  if (!u) return session.send('res_upgrade_card', {}, 1);
  const ca = cardAttach(u, req);
  const handIdx = [].concat(req.index_in_hand ?? []).map(Number);
  if (!ca || ca.attach.card_id === 0 || handIdx.length !== 2) {
    return session.send('res_upgrade_card', {}, 6); // CARD_NOT_FOUND
  }
  const cfg = gd.query('d_srpg_card_base', ca.attach.card_id);
  if (!cfg || !cfg.upgradeCard) return session.send('res_upgrade_card', {}, 7); // CARD_INVALID
  const posCfg = gd.query('d_srpg_card_pos', ca.attach.card_pos_id);
  const cost = posCfg?.upgradeCost || [2, 50];
  if (!U.spendResource(u, cost[0], cost[1])) return session.send('res_upgrade_card', {}, 8);
  // consume the two hand cards (higher index first)
  for (const i of handIdx.slice().sort((a, b) => b - a)) {
    if (u.cards[i] === undefined) return session.send('res_upgrade_card', {}, 6);
  }
  for (const i of handIdx.slice().sort((a, b) => b - a)) u.cards.splice(i, 1);
  ca.attach.card_id = cfg.upgradeCard;
  ca.attach.upgrade_times += 1;
  session.send('res_upgrade_card', {});
  sendUniverseInfo(session, u, { [cost[0]]: -cost[1] }, 0);
  // 官方教学文案（d_word_cn 113211007）：「当你有3个同样的建筑时，你可以选择晋升1个建筑，
  // 使其变强，**并获得一个异宝作为奖励**」。异宝池挂在卡片自己的 curioPool 上。
  if (!u.curios_for_select) {
    const pool = U.curioPoolList(ca.attach.card_id);
    const sel = U.makeCurioSelect(u, pool.length ? pool : null);
    if (sel) sendCurioSelect(session, sel);
  }
  savePlayer(session);
}

function reqRecallCard(session, req) {
  const u = uni(session);
  if (!u) return session.send('res_recall_card', {}, 1);
  const ca = cardAttach(u, req);
  if (!ca || ca.attach.card_id === 0) return session.send('res_recall_card', {}, 5);
  if (u.cards.length >= HAND_LEN_MAX) return session.send('res_recall_card', {}, 2); // CARD_FULL
  const posCfg = gd.query('d_srpg_card_pos', ca.attach.card_pos_id);
  const cost = posCfg?.recallCost || [2, 20];
  if (!U.spendResource(u, cost[0], cost[1])) return session.send('res_recall_card', {}, 8);
  u.cards.push(ca.attach.card_id);
  ca.attach.card_id = 0;
  ca.attach.upgrade_times = 0;
  session.send('res_recall_card', {});
  sendUniverseInfo(session, u, { [cost[0]]: -cost[1] }, 0);
  savePlayer(session);
}

function reqDemolitionCard(session, req) {
  const u = uni(session);
  if (!u) return session.send('res_demolition_card', {}, 1);
  const ca = cardAttach(u, req);
  if (!ca || ca.attach.card_id === 0) return session.send('res_demolition_card', {}, 4);
  const posCfg = gd.query('d_srpg_card_pos', ca.attach.card_pos_id);
  const refund = posCfg?.demolitionGet || [2, 30];
  U.changeResource(u, refund[0], refund[1]);
  ca.attach.card_id = 0;
  ca.attach.upgrade_times = 0;
  session.send('res_demolition_card', {});
  sendUniverseInfo(session, u, { [refund[0]]: refund[1] }, 0);
  savePlayer(session);
}

function reqReplaceCard(session, req) {
  const u = uni(session);
  if (!u) return session.send('res_replace_card', {}, 1);
  const replaceIdx = Number(req.replace_index ?? 0);
  const handIdx = Number(req.index ?? -1);
  const replace = !!req.replace;
  const cardId = u.missed_cards[replaceIdx];
  if (cardId === undefined) return session.send('res_replace_card', {}, 3);
  u.missed_cards.splice(replaceIdx, 1);
  if (replace) {
    if (handIdx >= 0 && handIdx < u.cards.length) u.cards[handIdx] = cardId;
    else if (u.cards.length < HAND_LEN_MAX) u.cards.push(cardId);
  }
  session.send('res_replace_card', {});
  savePlayer(session);
}

// ---------------- curios ----------------

function reqCreateChooseCurio(session, req) {
  const u = uni(session);
  if (!u) return session.send('res_create_choose_curio', {}, 1);
  const sel = u.curios_for_select;
  if (!sel || String(sel.select_uuid) !== String(req.select_uuid)) {
    return session.send('res_create_choose_curio', {}, 2);
  }
  session.send('res_create_choose_curio', { curio_ids: sel.curio_ids });
  savePlayer(session);
}

function reqChooseCurio(session, req) {
  const u = uni(session);
  if (!u) return session.send('res_choose_curio', {}, 1);
  const sel = u.curios_for_select;
  if (!sel || String(sel.select_uuid) !== String(req.select_uuid)) {
    return session.send('res_choose_curio', {}, 2);
  }
  const curioId = sel.curio_ids[Number(req.index ?? 0)];
  u.curios_for_select = null;
  if (curioId && !u.curios.includes(curioId)) u.curios.push(curioId);
  session.send('res_choose_curio', {});
  savePlayer(session);
}

function reqRefreshChooseCurio(session, req) {
  const u = uni(session);
  if (!u) return session.send('res_refresh_choose_curio', {}, 1);
  const sel = u.curios_for_select;
  if (!sel || String(sel.select_uuid) !== String(req.select_uuid)) {
    return session.send('res_refresh_choose_curio', {}, 2);
  }
  const pool = gd.query('d_srpg_curio_pool', sel.pool_id) || gd.table('d_srpg_curio_pool')[0];
  const cost = pool?.refreshCost || [2, 20];
  if (sel.refresh_times >= (pool?.refreshTime ?? 99)) {
    return session.send('res_refresh_choose_curio', {}, 4);
  }
  if (!U.spendResource(u, cost[0], cost[1])) return session.send('res_refresh_choose_curio', {}, 5);
  U.refreshCurioSelect(u, sel);
  session.send('res_refresh_choose_curio', { curio_ids: sel.curio_ids });
  sendUniverseInfo(session, u, { [cost[0]]: -cost[1] }, 0);
  savePlayer(session);
}

// ---------------- events ----------------

// 选项的 `effectTriggerID` 是这次选择带来的**效果列表**（教学 11007 的 110071 是
// [6060,6060,6060]，即「获得三张卡牌」→ 三次单卡三选一）。老代码把它丢了，改成按
// `option_id % 5` 摇一个假结果，于是教学星图里所有事件都发不到正确的奖励，
// 玩家永远凑不齐「晋升」需要的同名蓝图。
function reqChooseEventOption(session, req) {
  const u = uni(session);
  if (!u) return session.send('res_choose_event_option', {}, 1);
  const ev = u.events.find((e) => String(e.event_uuid) === String(req.event_uuid));
  if (!ev) return session.send('res_choose_event_option', {}, 2);
  const opt = ev.options[Number(req.index ?? 0)];
  if (!opt) return session.send('res_choose_event_option', {}, 4);
  u.events = u.events.filter((e) => e !== ev);
  const optCfg = gd.query('d_srpg_event_option', opt.option_id) || {};
  session.send('res_choose_event_option', {});
  applyEffects(session, u, U.intArray(optCfg.effectTriggerID));
  savePlayer(session);
}

// ---------------- main pos shop ----------------

function shopAttach(u, req) {
  const pos = U.posAt(u, { q: Number(req.hex?.q ?? 0), r: Number(req.hex?.r ?? 0) });
  if (!pos || !pos.attach || !pos.attach.main_pos_shop_info) return null;
  return { pos, shop: pos.attach.main_pos_shop_info };
}

// 买到的就是商品自己的 `itemEffectTriggerID`（「随机建筑（1星）」→ 6001 → 卡表
// [10002,10011,10018,10023]），而不是老代码那套「50% 资源 / 30% 全表随机蓝图 /
// 20% 金币」的假奖励。
function reqMainPosShopBuy(session, req) {
  const u = uni(session);
  if (!u) return session.send('res_main_pos_shop_buy', {}, 1);
  const sa = shopAttach(u, req);
  if (!sa) return session.send('res_main_pos_shop_buy', {}, 5); // SHOP_NOT_FOUND
  const itemIdx = Number(req.item_index ?? 0);
  const item = sa.shop.item_infos[itemIdx];
  if (!item) return session.send('res_main_pos_shop_buy', {}, 6); // ITEM_NOT_FOUND
  if (item.sold) return session.send('res_main_pos_shop_buy', {}, 7); // ITEM_SOLD
  const cfg = gd.query('d_srpg_shop_item', item.item_id) || {};
  const cost = cfg.itemCost || [2, 30];
  if (!U.spendResource(u, cost[0], cost[1])) return session.send('res_main_pos_shop_buy', {}, 4);
  item.sold = true;
  session.send('res_main_pos_shop_buy', {});
  sendUniverseInfo(session, u, { [cost[0]]: -cost[1] }, 0);
  applyEffects(session, u, U.intArray(cfg.itemEffectTriggerID));
  savePlayer(session);
}

function reqMainPosShopRefresh(session, req) {
  const u = uni(session);
  if (!u) return session.send('res_main_pos_shop_refresh', {}, 1);
  const sa = shopAttach(u, req);
  if (!sa) return session.send('res_main_pos_shop_refresh', {}, 5);
  const cfg = gd.query('d_srpg_shop_base', sa.shop.shop_id) || {};
  const cost = cfg.refreshCost || [2, 25];
  if (!U.spendResource(u, cost[0], cost[1])) return session.send('res_main_pos_shop_refresh', {}, 4);
  const items = (cfg.itemList || []).map((sid) => ({ item_id: sid, sold: false }));
  const shuffled = items.sort(() => Math.random() - 0.5).slice(0, cfg.itemNumber ?? 4);
  sa.shop.item_infos = shuffled;
  session.send('res_main_pos_shop_refresh', {
    item_infos: shuffled.map((it) => ({ item_id: it.item_id, sold: it.sold })),
  });
  sendUniverseInfo(session, u, { [cost[0]]: -cost[1] }, 0);
  savePlayer(session);
}

// ---------------- misc ----------------

function reqUniverseChangeCharacter(session, req) {
  const u = uni(session);
  if (!u) return session.send('res_universe_change_character', {}, 1);
  const charId = Number(req.character_id ?? 0);
  const index = Number(req.character_index ?? 0);
  if (index < 0 || index > 2) return session.send('res_universe_change_character', {}, 2); // INDEX_INVALID
  if (!session.player.characters.find((c) => c.character_id === charId)) {
    return session.send('res_universe_change_character', {}, 3); // NO_CHARACTER
  }
  // Price with the same table row the client's exchange UI reads
  // (d_srpg_map_base[map_id].substitutionCost) — never with a stale copy stored
  // on the run, or the UI stays clickable after the server has gone broke.
  const cost = U.substitutionCostOf(u);
  const type = Number(cost[0]) || 0;
  const amount = Math.max(0, Number(cost[1]) || 0);
  if (amount > 0 && (!(type >= 1 && type <= 4) || !U.spendResource(u, type, amount))) {
    return session.send('res_universe_change_character', {}, 4); // RES_NOT_ENOUGH
  }
  u.universe_fight_data.character_fight_datas[index] = {
    character_id: charId,
    cur_hp: U.characterMaxHp(charId),
  };
  u.universe_fight_data.character_changed_times += 1;
  session.send('res_universe_change_character', {});
  sendUniverseInfo(session, u, amount > 0 ? { [type]: -amount } : {}, 0);
  savePlayer(session);
}

function reqPlayerUniverseGrowth(session) {
  session.send('res_player_universe_growth', {}, 1); // MAX_RANK: growth tree stub
}

function handle(name) {
  const map = {
    req_new_universe: reqNewUniverse,
    req_new_universe_specific: reqNewUniverseSpecific,
    req_complete_universe: reqCompleteUniverse,
    req_explore: reqExplore,
    req_universe_fight: reqUniverseFight,
    req_complete_universe_fight: reqCompleteUniverseFight,
    req_boss_fight: reqBossFight,
    req_complete_boss_fight: reqCompleteBossFight,
    req_create_choose_card: reqCreateChooseCard,
    req_choose_card: reqChooseCard,
    req_refresh_choose_card: reqRefreshChooseCard,
    req_place_card: reqPlaceCard,
    req_upgrade_card: reqUpgradeCard,
    req_recall_card: reqRecallCard,
    req_demolition_card: reqDemolitionCard,
    req_replace_card: reqReplaceCard,
    req_create_choose_curio: reqCreateChooseCurio,
    req_choose_curio: reqChooseCurio,
    req_refresh_choose_curio: reqRefreshChooseCurio,
    req_choose_event_option: reqChooseEventOption,
    req_main_pos_shop_buy: reqMainPosShopBuy,
    req_main_pos_shop_refresh: reqMainPosShopRefresh,
    req_universe_change_character: reqUniverseChangeCharacter,
    req_player_universe_growth: reqPlayerUniverseGrowth,
  };
  return map[name] ?? null;
}

module.exports = { handle };
