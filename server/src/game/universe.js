// Roguelike "Universe" (Srpg) domain: map generation, exploration, fights,
// cards, curios, events, boss waves, run settlement.
// Approximation notes: the client tolerates generated maps as long as ids are
// resolvable in d_srpg_* tables and states follow 0/1/2/3 semantics.
const gd = require('../gamedata');

const HEX_NEIGHBORS = [
  { q: 1, r: 0 }, { q: 1, r: -1 }, { q: 0, r: -1 },
  { q: -1, r: 0 }, { q: -1, r: 1 }, { q: 0, r: 1 },
];

function hexKey(hex) {
  return `${hex.q},${hex.r}`;
}

function encHex(hex) {
  return { q: hex.q, r: hex.r };
}

function randomEncounterLevel() {
  const ids = [];
  for (const [id] of gd.rows('d_srpg_level_base')) {
    const n = Number(id);
    if (n >= 1 && n <= 54) ids.push(n);
  }
  return ids[Math.floor(Math.random() * ids.length)];
}

// `d_srpg_main_pos_base.nameId` 102000101/102000102 = 「建筑格」. These are the
// tutorial's deploy-a-building cells (1000309 uses 102 three times); normal maps
// use A47_FreeCard / A39_Building* models for the same purpose.
const CARD_SLOT_NAME_IDS = new Set([102000101, 102000102]);
// d_srpg_card_pos: 1 = normal slot, 3 = free recall (「在本次教学中，临时免费」)
const CARD_SLOT_POS_ID = 1;
const CARD_SLOT_FREE_POS_ID = 3;
// 手牌上限：客户端 CardSelector 的召回按钮要求 `#cardsInHand < 10`
// (CardSelector_C.lua:228)，超过 10 张的新蓝图会进 missed_card_ids 走「替换」面板。
const HAND_LEN_MAX = 10;

// Which shop a merchant cell runs is a property of the cell row, not of its id:
// d_srpg_shop_base rows 1..6 carry the merchant `nameId` (102000701..102000706)
// that cells 701..706 also use; the remaining merchant models (A45_MerchantA /
// A46_MerchantB) map to the blueprint merchant / the survival-value merchant.
function merchantShopIdFor(cfg) {
  for (const [id, row] of gd.rows('d_srpg_shop_base')) {
    if (Number(row.nameId) === Number(cfg.nameId) || Number(row.txtId) === Number(cfg.txtId)) {
      return Number(id);
    }
  }
  return String(cfg.posModel || '') === 'A46_MerchantB' ? 2 : 1;
}

function pickShopForPos(posId, cfg) {
  const shopId = merchantShopIdFor(cfg);
  const shop = gd.query('d_srpg_shop_base', shopId)
    || (gd.rows('d_srpg_shop_base')[0] || [])[1];
  if (!shop) return null;
  const items = (shop.itemList || []).slice(0, shop.itemNumber ?? 4)
    .map((sid) => ({ item_id: sid, sold: false }));
  return { shop_id: shop.id, item_infos: items, refresh_times: 0 };
}

function pickCardPos(posId, cfg, freeRecall = false) {
  const slots = gd.rows('d_srpg_card_pos').map(([, r]) => r);
  const id = freeRecall ? CARD_SLOT_FREE_POS_ID : CARD_SLOT_POS_ID;
  const row = gd.query('d_srpg_card_pos', id) || slots[id - 1] || slots[0];
  return { card_pos_id: row.id, card_id: 0, upgrade_times: 0 };
}

// A cell's attachment (deploy-a-building slot / merchant) comes from its own
// `d_srpg_main_pos_base` row — the `posModel` and `nameId` say what the cell is.
// Guessing from a digit prefix of the id used to give the wrong answer in both
// directions: 819/829/839 (A47_FreeCard = building cells) are prefix 8 and were
// attached as shops, while 20014 (A45_MerchantA = a shop) and the tutorial's
// 建筑格 (102) are prefixes 20/1 and got nothing at all. With no
// `main_pos_card_pos_info` the client never renders the 「管理」 option
// (UI_Menu_C:1367-1376 iterates main_pos_attach_infos), so a visible 建筑格 behaves
// exactly like empty space.
//
// `freeRecall` is a property of the run, not the cell: 1000309 and the other
// story star maps are mapType 0, and the tutorial explicitly hands out free
// recall ("在本次教学中，临时免费" → d_srpg_card_pos 3, recallCost [2,0]).
function attachForPos(posId, cfg = null, freeRecall = false) {
  const cell = cfg || gd.query('d_srpg_main_pos_base', posId) || {};
  const model = String(cell.posModel || '');
  if (/Merchant/.test(model)) {
    const shop = pickShopForPos(posId, cell);
    return shop ? { main_pos_shop_info: shop } : null;
  }
  if (/FreeCard|^A39_Building/.test(model) || CARD_SLOT_NAME_IDS.has(Number(cell.nameId))) {
    return { main_pos_card_pos_info: pickCardPos(posId, cell, freeRecall) };
  }
  return null;
}

// Re-derive missing attachments for a run stored by an older server (see
// game/migrate.js). Add-only: an existing slot keeps whatever the player built
// on it, so this is safe for an in-progress run.
function refreshAttach(u) {
  if (!u || !u.main_pos) return false;
  const freeRecall = isStoryMap(u.map_id);
  let changed = false;
  for (const cell of Object.values(u.main_pos)) {
    if (cell.attach) continue;
    const attach = attachForPos(
      cell.main_pos_id,
      gd.query('d_srpg_main_pos_base', cell.main_pos_id),
      freeRecall,
    );
    if (attach) {
      cell.attach = attach;
      changed = true;
    }
  }
  return changed;
}

// Story star maps (剧情星图) are mapType 0; the tutorial grants free recall there.
function isStoryMap(mapId) {
  const base = gd.query('d_srpg_map_base', mapId);
  return !!base && Number(base.mapType) === 0;
}

// A run is always bound to exactly ONE `d_srpg_map_base` row, and *everything*
// map-dependent (hex layout via mapDataId, boss, startHP, initialResourceValue,
// substitutionCost) has to come from that same row. `req_new_universe_specific`
// enters a story map by id, the generic entry picks by mapType — see 坑 25 for
// what happens when a run's map_id and its substitution_cost disagree.
function newUniverse(req, forcedMapId = null) {
  const mapType = Number(req.map_type ?? 1);
  const mapRows = gd.rows('d_srpg_map_base').map(([id, r]) => [Number(id), r]);
  const forced = forcedMapId != null ? Number(forcedMapId) : null;
  const mapRow = (forced != null && mapRows.find(([id]) => id === forced))
    || mapRows.find(([, r]) => r.mapType === mapType)
    || mapRows[0];
  const [mapId, mapBase] = mapRow;
  const dataId = (mapBase.mapDataId || [1])[0];
  const mapData = gd.query('d_srpg_map_data', dataId) || Object.values(gd.table('d_srpg_map_data'))[0];

  const bx = mapData.baseCoordinate?.[0] ?? 0;
  const by = mapData.baseCoordinate?.[1] ?? 0;
  const main_pos = {};
  let baseHex = { q: bx, r: by };
  const ids = mapData.mainPosId || [];
  const coords = mapData.coordinate || [];
  for (let i = 0; i < ids.length; i++) {
    const posId = ids[i];
    const q = (coords[2 * i] ?? 0) + bx;
    const r = (coords[2 * i + 1] ?? 0) + by;
    const cfg = gd.query('d_srpg_main_pos_base', posId) || {};
    const hex = { q, r };
    if (cfg.posModel === 'A37_MainBase') baseHex = hex;
    main_pos[hexKey(hex)] = {
      hex,
      main_pos_id: posId,
      state: cfg.baseState ?? 0,
      attach: attachForPos(posId, cfg, isStoryMap(mapId)),
    };
  }

  // fog-of-war unlock pass: neighbors of the explored base become explorable.
  // Cells with baseState 3 (transit "nothing" cells) auto-explore and cascade.
  revealFrontier(main_pos, baseHex);

  const charIds = (req.character_ids || []).map(Number).filter((c) => c > 0).slice(0, 3);
  const fightDatas = [];
  for (let i = 0; i < 3; i++) {
    const cid = charIds[i] ?? 0;
    fightDatas.push({
      character_id: cid,
      cur_hp: cid ? characterMaxHp(cid) : 0,
    });
  }

  // No boss is placed at run creation. d_srpg_level_boss.appearTime is the step
  // the wave shows up on (11→2, 17→12, 13→15/24/32), i.e. an official run starts
  // with an empty boss list and the warning banner appears later. Spawning wave 0
  // eagerly at the farthest cell is what made the banner show from step 1 and
  // reappear after every kill (the client only learns how to reach a boss through
  // the step budget). See spawnDueBossWaves.

  return {
    active: true,
    difficulty_value: Number(req.difficulty_value ?? 1),
    main_planet_id: Number(req.main_planet_id ?? 101),
    map_id: mapId,
    specific_id: 0,
    res_value: [0, ...(mapBase.initialResourceValue || [100, 100, 100, 100])], // 1-based
    turn: 0,
    step: 0,
    cur_hp: mapBase.startHP ?? 5,
    substitution_cost: mapBase.substitutionCost || [2, 50],
    boss_id: (mapBase.boss || [1])[0],
    boss_wave: -1, // waves appear on their own d_srpg_level_boss.appearTime step
    // Empty until a wave's appearTime is reached — a boss hex that is not a real
    // cell is exactly what makes the client's astar blow up (see 坑 26).
    boss_infos: [],
    fight_infos: [],
    fight_seq: 1,
    main_pos,
    base_hex: baseHex,
    cards: [],
    missed_cards: [],
    curios: [],
    cards_for_select: null,
    // 一次事件可以连发好几次三选一（教学 11007 → [6060,6060,6060]），
    // 除第一次外的那些排在这里，见 addCardSelect。
    extra_card_selects: [],
    curios_for_select: null,
    select_seq: 1,
    events: [],
    event_seq: 1,
    missions: [],
    mission_seq: 1,
    universe_fight_data: {
      character_fight_datas: fightDatas,
      boat_energy: 0,
      character_changed_times: 0,
    },
  };
}

function dist(a, b) {
  const dq = a.q - b.q;
  const dr = a.r - b.r;
  return (Math.abs(dq) + Math.abs(dq + dr) + Math.abs(dr)) / 2;
}

// BFS from an explored cell: neighbors become explorable (state >= 2); cells
// whose baseState is 3 (transit cells) are auto-explored and keep cascading.
// Returns the list of cells whose state changed (for ntf batching).
function revealFrontier(mainPos, fromHex) {
  const changed = [];
  const queue = [fromHex];
  const seen = new Set([hexKey(fromHex)]);
  while (queue.length) {
    const cur = queue.shift();
    for (const d of HEX_NEIGHBORS) {
      const key = hexKey({ q: cur.q + d.q, r: cur.r + d.r });
      if (seen.has(key)) continue;
      seen.add(key);
      const cell = mainPos[key];
      if (!cell) continue;
      const base = gd.query('d_srpg_main_pos_base', cell.main_pos_id);
      const target = Math.max(2, base?.baseState ?? 0);
      if (cell.state < target) {
        cell.state = target;
        changed.push(cell);
      }
      if (cell.state >= 3) queue.push(cell.hex); // auto-explored transit cell
    }
  }
  return changed;
}

// Character max HP: d_character.attr pairs (id 1001 = HitPoint) plus lvAdd per
// level. cur_hp must be an absolute value — the client does min(cur_hp, max)
// with no special case for 0.
function characterMaxHp(charId, exp = 0, breakTimes = 0) {
  const cfg = gd.query('d_character', charId);
  if (!cfg) return 0;
  const flatPairs = (arr, id) => {
    let v = 0;
    const a = arr || [];
    for (let i = 0; i + 1 < a.length; i += 2) if (a[i] === id) v = a[i + 1];
    return v;
  };
  const base = flatPairs(cfg.attr, 1001);
  const perLevel = flatPairs(cfg.lvAdd, 1001);
  // level from d_role_level cumulative requirements
  const levels = gd.table('d_role_level');
  let level = 1;
  let remaining = exp;
  const cap = 20 + breakTimes * 10; // approximation of d_role_levelbreak cap
  for (const row of levels) {
    if (level >= cap) break;
    if (remaining >= (row.exp ?? 0)) {
      remaining -= row.exp ?? 0;
      level += 1;
    } else break;
  }
  return base + perLevel * (level - 1);
}

function adjacent(a, b) {
  return dist(a, b) === 1;
}

// -------- serialization to ghs.UniverseInfo --------

function encMainPos(p) {
  const out = {
    hex: encHex(p.hex),
    main_pos_id: p.main_pos_id,
    state: p.state,
  };
  if (p.attach) {
    if (p.attach.main_pos_card_pos_info) {
      out.main_pos_attach_infos = [{
        main_pos_card_pos_info: {
          card_pos_id: p.attach.main_pos_card_pos_info.card_pos_id,
          card_id: p.attach.main_pos_card_pos_info.card_id,
          upgrade_times: p.attach.main_pos_card_pos_info.upgrade_times,
        },
      }];
    } else if (p.attach.main_pos_shop_info) {
      out.main_pos_attach_infos = [{
        main_pos_shop_info: {
          shop_id: p.attach.main_pos_shop_info.shop_id,
          item_infos: p.attach.main_pos_shop_info.item_infos.map((it) => ({
            item_id: it.item_id, sold: it.sold,
          })),
        },
      }];
    }
  }
  return out;
}

function buildUniverseInfo(u) {
  return {
    res_value: u.res_value.slice(1),
    turn: u.turn,
    step: u.step,
    cur_hp: u.cur_hp,
    difficulty_value: u.difficulty_value,
    specific_id: u.specific_id,
    main_planet_id: u.main_planet_id,
    map_id: u.map_id,
    main_pos_infos: Object.values(u.main_pos).map(encMainPos),
    base_hex: encHex(u.base_hex),
    last_explored_hex: encHex(u.base_hex),
    boss_id: u.boss_id,
    boss_infos: u.boss_infos.map((b) => ({
      boss_index: b.boss_index,
      fight_uuid: String(b.fight_uuid),
      hex: encHex(b.hex),
    })),
    fight_infos: u.fight_infos.map((f) => ({
      fight_uuid: String(f.fight_uuid),
      fight_level_id: f.fight_level_id,
      fight_state: f.fight_state,
    })),
    realtime_buff_infos: [],
    forever_buff_ids: [],
    forever_fight_buff_ids: [],
    card_ids: u.cards.slice(),
    curio_ids: u.curios.slice(),
    cards_for_selects: cardSelects(u).map((s) => ({
      select_uuid: String(s.select_uuid),
      card_ids: s.card_ids.slice(),
      refresh_times: s.refresh_times,
      pool_id: s.pool_id,
    })),
    curios_for_selects: u.curios_for_select ? [{
      select_uuid: String(u.curios_for_select.select_uuid),
      curio_ids: u.curios_for_select.curio_ids,
      refresh_times: u.curios_for_select.refresh_times,
      pool_id: u.curios_for_select.pool_id,
    }] : [],
    missed_card_ids: u.missed_cards.slice(),
    event_infos: u.events.map((e) => ({
      event_uuid: String(e.event_uuid),
      event_id: e.event_id,
      options: e.options.map((o) => ({ option_id: o.option_id, enabled: true })),
      option_id: 0,
    })),
    mission_infos: u.missions.map((m) => ({
      mission_uuid: String(m.mission_uuid),
      mission_id: m.mission_id,
      mission_elapsed: 0,
      mission_result: m.result,
      mission_begin_turn: m.begin_turn,
      mission_begin_step: m.begin_step,
      mission_end_turn: m.end_turn ?? 0,
      mission_end_step: m.end_step ?? 0,
    })),
    universe_fight_data: {
      character_fight_datas: u.universe_fight_data.character_fight_datas.map((c) => ({
        character_id: c.character_id, cur_hp: c.cur_hp,
      })),
      boat_energy: u.universe_fight_data.boat_energy,
      character_changed_times: u.universe_fight_data.character_changed_times,
    },
  };
}

// -------- helpers used by handlers --------

function changeResource(u, index, delta) {
  u.res_value[index] = (u.res_value[index] ?? 0) + delta;
}

function resourceDeltas(u, changes) {
  // changes: {1: +n, 2: -m, ...} -> full delta array for ntf_universe_info
  const out = [0, 0, 0, 0];
  for (const [k, v] of Object.entries(changes)) out[Number(k) - 1] = v;
  return out;
}

function spendResource(u, type, amount) {
  if ((u.res_value[type] ?? 0) < amount) return false;
  changeResource(u, type, -amount);
  return true;
}

// Cost of swapping an on-field character, as `[resourceIndex, price]`.
//
// The client prices this itself in UI_character_exchange_C:96/172 with
//   Database.Query("d_srpg_map_base", SrpgController.model.mapId).substitutionCost
// and only sends req_universe_change_character when its *local* copy of the
// resource covers that price. So the server must read the very same row — a
// stale copy stored on the run (e.g. saved before the run's map_id was
// finalised) makes the server charge more than the UI shows, and the button
// stays clickable forever while every click answers RES_NOT_ENOUGH(4).
// See 坑 25.
function substitutionCostOf(u) {
  const mapBase = gd.query('d_srpg_map_base', u.map_id) || {};
  const cost = mapBase.substitutionCost || u.substitution_cost;
  return Array.isArray(cost) ? cost : [2, 50];
}

// Invariant required by the client: every `boss_infos` entry must sit on a cell
// the client considers reachable (state > 1). Otherwise SrpgModel:Init /
// UpdateBossInfo → UpdateBossLines → astar.path(nil, ...) throws
// "table index is nil" and aborts the rest of the res_*universe* handler —
// including the MessageManager:Broadcast() that makes BP_GameInstance_C load
// UniverseMap, which is what leaves the player on an endless loading screen
// (see 坑 26). The whole 「boss → base」 corridor has to be reachable for the
// same reason (UpdateBossLines draws that line with astar) and because the boss
// now walks it one cell per turn. Returns true when a cell had to be revealed.
function ensureBossReachable(u) {
  if (!u || !u.main_pos || !Array.isArray(u.boss_infos)) return false;
  let changed = false;
  for (const boss of u.boss_infos) {
    const cell = u.main_pos[hexKey(boss.hex || {})];
    if (cell && typeof cell.state === 'number' && cell.state <= 1) {
      cell.state = 2;
      changed = true;
    }
    for (const p of routeToBase(u, boss.hex)) {
      if (p.state <= 1) {
        p.state = 2;
        changed = true;
      }
    }
  }
  return changed;
}

// ---------------- 首领推进（官方：每回合向巡航基地移动1格） ----------------
//
// 官方口径（d_word_cn 113211012「败者首领」/ 113220008 生存值说明）：
//   首领出现在巡航基地附近，**每回合向巡航基地移动1格**；
//   抵达基地后，**每回合扣取1点生存值**，生存值为 0 时远航失败。
//
// 位置由服务端独家维护：客户端只在收到 ntf_boss_info 后对比同一个 boss_index
// 的前后 hex 才广播 BossMoved / BossArrived（SrpgModel:UpdateBossInfo:506-508），
// 自己从不移动或删除 boss（坑 27）。所以「每回合」在服务端就是每次 req_explore
// （`u.step += 1`，客户端 TickTurn 同样只推进 step）。

// BFS 距离场（以基地为根，只走 main_pos 里真实存在的格子）
function distanceField(u, rootHex) {
  const field = new Map([[hexKey(rootHex), 0]]);
  const queue = [rootHex];
  while (queue.length) {
    const cur = queue.shift();
    const d = field.get(hexKey(cur));
    for (const nb of neighborsOf(u, cur)) {
      const k = hexKey(nb.hex);
      if (field.has(k)) continue;
      field.set(k, d + 1);
      queue.push(nb.hex);
    }
  }
  return field;
}

// 一条「从 fromHex 走到基地」的最短路（含两端）。用于生成波次时把整条走廊
// 揭示成可达，客户端才画得出首领连线、astar 才不会拿到 nil 的 start。
function routeToBase(u, fromHex) {
  const route = [];
  if (!u || !u.main_pos || !fromHex) return route;
  const field = distanceField(u, u.base_hex);
  let cur = u.main_pos[hexKey(fromHex)];
  if (!cur || !field.has(hexKey(cur.hex))) return route;
  route.push(cur);
  while (hexKey(cur.hex) !== hexKey(u.base_hex)) {
    const d = field.get(hexKey(cur.hex));
    const next = neighborsOf(u, cur.hex).find((p) => field.get(hexKey(p.hex)) === d - 1);
    if (!next) break;
    route.push(next);
    cur = next;
  }
  return route;
}

// 走一步：在「离基地更近一圈」的邻格里挑一个没被别的首领占住的
function stepBossTowardsBase(u, boss, field, taken) {
  const cur = posAt(u, boss.hex || {});
  if (!cur) return null;
  const key = hexKey(cur.hex);
  if (key === hexKey(u.base_hex)) return { atBase: true, hex: cur.hex, cell: null };
  const here = field.get(key);
  if (here === undefined) return null;
  for (const nb of neighborsOf(u, cur.hex)) {
    if (field.get(hexKey(nb.hex)) !== here - 1) continue;
    if (taken.has(hexKey(nb.hex))) continue;
    return { atBase: false, hex: nb.hex, cell: nb };
  }
  return null;
}

// 每回合推进一次所有存活首领。返回：
//   changed  —— 是否有首领挪了位（决定要不要推 ntf_boss_info）
//   revealed —— 为让首领落点可达而新揭示的格子（必须先于 ntf_boss_info 下发）
//   arrived  —— 本回合刚抵达基地的首领
//   damage   —— 本回合被扣掉的生存值（已在撞上基地的那一回合之后才计）
//   dead     —— 生存值归零（远航失败）
function advanceBosses(u) {
  const out = { changed: false, revealed: [], arrived: [], damage: 0, dead: false };
  if (!u || !u.main_pos || !Array.isArray(u.boss_infos) || !u.boss_infos.length) return out;
  const baseKey = hexKey(u.base_hex);
  const field = distanceField(u, u.base_hex);
  const taken = new Set(u.boss_infos.map((b) => hexKey(b.hex || {})));
  for (const boss of u.boss_infos) {
    const key = hexKey(boss.hex || {});
    if (key === baseKey) {
      // 「抵达巡航基地后，每回合扣取1点生存值」
      boss.at_base = true;
      out.damage += 1;
      continue;
    }
    taken.delete(key);
    const step = stepBossTowardsBase(u, boss, field, taken);
    if (!step) {
      taken.add(key);
      continue;
    }
    boss.hex = encHex(step.hex);
    taken.add(hexKey(step.hex));
    out.changed = true;
    if (step.cell && step.cell.state <= 1) {
      step.cell.state = 2;
      out.revealed.push(step.cell);
    }
    if (step.atBase) {
      boss.at_base = true;
      out.arrived.push(step.cell || posAt(u, step.hex));
    }
  }
  if (out.damage > 0) {
    u.cur_hp -= out.damage;
    out.changed = true;
    if (u.cur_hp <= 0) out.dead = true;
  }
  return out;
}

// 旧存档的 boss 落点/走廊补齐成 state ≥ 2（add-only，幂等）
function revealBossRoute(u, fromHex) {
  const revealed = [];
  for (const p of routeToBase(u, fromHex)) {
    if (p.state <= 1) {
      p.state = 2;
      revealed.push(p);
    }
  }
  return revealed;
}

// Official wave timing: d_srpg_level_boss.appearTime[i] is the exploration step
// wave i shows up on (d_srpg_level_boss 11 → [2], 17 → [12], 13 → [15,24,32];
// the overview UI draws the step axis exactly this way, UI_OverView_C:158). The
// spawn cell is `distance[i]` rings out from the base.
//
// Wave 0 arriving only at step 2 is why the banner is NOT on screen from step 1
// in the official client — and it is also the only reason it can go away after a
// kill. The client never moves bosses server-side: `GetBossCount() = turn +
// #bossInfo` and `turn` only advances when a boss actually reaches the base
// (SrpgModel.lua:403, UI_Menu_C:768). So a boss that is spawned "next to the
// base" and killed is replaced by the next wave immediately, the banner comes
// straight back, and it never disappears for good — exactly the reported symptom.
//
// Returns the cells whose state was raised (an empty array is a valid "waves
// spawned but every cell was already reachable") or null when nothing is due —
// the caller uses null to skip pushing ntf_boss_info entirely.
//
// The whole 「spawn cell → base」 corridor is revealed as well: the boss walks it
// one cell per turn (advanceBosses) and the client draws it as the boss line via
// astar over state > 1 cells (SrpgModel:UpdateBossLines).
function spawnDueBossWaves(u) {
  if (!u || !u.main_pos) return null;
  const cfg = gd.query('d_srpg_level_boss', u.boss_id);
  const path = Array.isArray(cfg?.path) ? cfg.path : [];
  const times = Array.isArray(cfg?.appearTime) ? cfg.appearTime : [];
  const distances = Array.isArray(cfg?.distance) ? cfg.distance : [];
  const revealed = [];
  let spawned = false;
  if (!Array.isArray(u.boss_infos)) u.boss_infos = [];
  if (!Number.isFinite(u.boss_wave)) u.boss_wave = -1;

  for (let i = 0; i < path.length; i++) {
    if (i <= u.boss_wave) continue;
    const dueStep = Number(times[i] ?? times[times.length - 1] ?? i + 1);
    if (u.step < dueStep) break;
    // The client can only path to cells it considers reachable, so the ring the
    // wave spawns on is revealed before the boss is parked on it. Two waves can
    // be due at once, so cells already taken by a live boss are skipped.
    const ring = Number(distances[i] ?? 1);
    const taken = new Set(u.boss_infos.map((b) => hexKey(b.hex || {})));
    const cell = pickBossCell(u, ring, taken);
    if (!cell) continue;
    if (cell.state <= 1) {
      cell.state = 2;
      revealed.push(cell);
    }
    for (const p of revealBossRoute(u, cell.hex)) {
      if (!revealed.includes(p)) revealed.push(p);
    }
    u.boss_wave = i;
    u.boss_infos.push({ boss_index: i, fight_uuid: '0', hex: encHex(cell.hex), at_base: false });
    spawned = true;
  }
  return spawned ? revealed : null;
}

// Rebuild the boss list of a run that was stored while the server still spawned
// wave 0 eagerly at run creation (its banner never went away — see
// spawnDueBossWaves). `turn` counts waves the client already killed and
// `appearTime` says how many should have shown up by `step`, so the waves still
// alive are exactly the indices in [turn, appearedCount). Existing entries are
// reused by index so an in-flight fight_uuid survives. Returns true if changed.
function reconcileBossWaves(u) {
  if (!u || !u.main_pos || !Array.isArray(u.boss_infos)) return false;
  const cfg = gd.query('d_srpg_level_boss', u.boss_id);
  const times = Array.isArray(cfg?.appearTime) ? cfg.appearTime : [];
  if (!times.length) return false;
  const appeared = times.filter((t) => u.step >= Number(t)).length;
  const killed = Math.max(0, Math.min(Number(u.turn) || 0, appeared));
  const want = [];
  for (let i = killed; i < appeared; i++) want.push(i);

  const byIndex = new Map();
  for (const b of u.boss_infos) byIndex.set(Number(b.boss_index), b);
  const next = [];
  let changed = false;
  for (const i of want) {
    const existing = byIndex.get(i);
    if (existing) { next.push(existing); continue; }
    const taken = new Set(next.map((b) => hexKey(b.hex || {})));
    const cell = pickBossCell(u, Number((cfg.distance || [])[i] ?? 1), taken);
    if (!cell) continue;
    if (cell.state <= 1) cell.state = 2;
    revealBossRoute(u, cell.hex);
    next.push({ boss_index: i, fight_uuid: '0', hex: encHex(cell.hex), at_base: false });
    changed = true;
  }
  if (next.length !== u.boss_infos.length) changed = true;
  else if (next.some((b, i) => b !== u.boss_infos[i])) changed = true;
  const wave = want.length ? want[want.length - 1] : killed - 1;
  if (u.boss_wave !== wave) changed = true;
  if (changed) {
    u.boss_infos = next;
    u.boss_wave = wave;
  }
  return changed;
}

// Best cell for a boss of ring `wantRing`. `d_srpg_level_boss.distance[i]` is the
// requested hex distance from the base. Preference order:
//   1. a reachable cell on that ring (the boss line renders, and the banner's
//      「攻击」 button can move the player there),
//   2. any cell on that ring (revealed before ntf_boss_info — the boss is meant
//      to be visible through the fog),
//   3. the farthest reachable cell, so a wave is never skipped outright.
// Cells already holding a live boss are skipped so two simultaneous waves (boss
// 13 appears at steps 15/24/32) do not stack on one hex.
function pickBossCell(u, wantRing, taken = new Set()) {
  const base = u.base_hex;
  const all = Object.values(u.main_pos)
    .filter((c) => hexKey(c.hex) !== hexKey(base) && !taken.has(hexKey(c.hex)));
  if (!all.length) return null;
  const onRing = (c) => Math.abs(dist(c.hex, base) - wantRing) < 1e-6;
  const reachableOnRing = all.find((c) => c.state > 1 && onRing(c));
  if (reachableOnRing) return reachableOnRing;
  const anyOnRing = all.find(onRing);
  if (anyOnRing) return anyOnRing;
  const reachable = all.filter((c) => c.state > 1);
  const pool = reachable.length ? reachable : all;
  pool.sort((a, b) => dist(a.hex, base) - dist(b.hex, base));
  return pool[pool.length - 1];
}

// effectType 11 的 effectConfig[0] 是 `d_srpg_card_pool` 的行号：池 N 的 cardList 指向
// `d_srpg_card_list` 的行，那才是卡表。逐条核对过：
//   配置 7  （游商「随机建筑<燃烧>」）  → card_list 7  = 燃烧的 1★ 四张 [10006,10009,10020,10023]
//   配置 20 （游商「随机建筑【火星】」）→ card_list 20 = 火星（race 20001）[10015,10018,10019,10022,10024]
//   配置 104（关卡 25 的战斗奖励 6031）→ 池 104 的合并表 = card_list 1+2+3 共 12 张
// 若某个取值在卡池表里没有对应行，再退回按 `d_srpg_card_list` 行号直接查一次。
function cardsForEffectConfig(value) {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return [];
  const fromPool = cardsOfPool(n);
  if (fromPool.length) return fromPool;
  const list = gd.query('d_srpg_card_list', n);
  return list ? cardListOf(list.cardList) : [];
}

function posAt(u, hex) {
  return u.main_pos[hexKey(hex)] ?? null;
}

function neighborsOf(u, hex) {
  const list = [];
  for (const d of HEX_NEIGHBORS) {
    const p = posAt(u, { q: hex.q + d.q, r: hex.r + d.r });
    if (p) list.push(p);
  }
  return list;
}

function newFight(u, levelId) {
  const f = { fight_uuid: u.fight_seq++, fight_level_id: levelId, fight_state: 0 };
  u.fight_infos.push(f);
  return f;
}

// ---------------- 教学保险：不让「晋升1个建筑」把存档卡死 ----------------
//
// 客户端的「探索 / 跃迁」在特定主线阶段是**客户端自己**禁用的：
//   QuestSystem:IsExploreBlocked()（QuestSystem.lua:1149）在**任何未完成**的
//   d_task_story 行 `unExplore == 1` 时返回 true，UI_Menu_C:1190 于是拒绝发
//   req_explore，只弹一句「现在不能这么做」。
// 全表 `unExplore == 1` 只有三条，正是教学三连：
//   100031201「部署1个建筑」/ 100031203「晋升1个建筑」/ 100031205「拆除1个建筑」。
//
// 于是「晋升1个建筑」阶段玩家**没有任何办法再去挣蓝图**（探索、跃迁、拆除全被锁）。
// 而客户端要点亮「晋升」按钮，要求**手牌里有 2 张与被部署建筑同名的蓝图**
// （CardSelector_C.lua:210 的 `countBy(cards, card_id) >= 2`）。只要场上那张蓝图
// 凑不出副本，主线 100031203 就永远推进不下去 —— 任何让玩家在部署阶段拿到
// 「另一张」蓝图的路径都会踩到这里：游商买卡、战斗奖励（6031 三选一）、
// 以及早期版本把三选一做成全表随机（见坑 29）。
//
// 官方教学本不需要这个保险：那条轨道是死板的（3 步探索 → 事件 11003 给 1 张 10015 →
// 部署 → 2 步探索 → 事件 11007 给 3 张 10015 → 晋升用掉 2 张），实测每一步都成立。
// 但私服没有客户端的教学脚本护栏，玩家可以偏离轨道；此时服务端兜底：把缺的同名蓝图
// 补进手牌（只补到刚好够一次晋升），并把补过的卡记进 `universe.repaired_cards`
// 以免重复补发。这是**私服保险，不属于官方行为**，每次触发都会写日志。

// 与 QuestSystem:IsExploreBlocked() 同语义：有没有一条未完成的主线在上锁探索
function exploreLockedByStory(player) {
  const infos = (player && player.plot && player.plot.plot_mission_infos) || [];
  for (const info of infos) {
    if (!info || info.completed) continue;
    const cfg = gd.query('d_task_story', info.mission_id);
    if (cfg && Number(cfg.unExplore) === 1) return true;
  }
  return false;
}

// 场上有没有「已部署、还能晋升、但手牌凑不出 2 张副本」的蓝图
function unupgradableBuilding(u) {
  if (!u || !u.main_pos) return null;
  const have = new Map();
  for (const c of u.cards || []) have.set(c, (have.get(c) || 0) + 1);
  for (const cell of Object.values(u.main_pos)) {
    const attach = cell.attach && cell.attach.main_pos_card_pos_info;
    if (!attach || !attach.card_id) continue;
    const id = Number(attach.card_id);
    const cfg = gd.query('d_srpg_card_base', id);
    // `upgradeCard === id` 是顶层蓝图（如 40095 / 10091），本来就不可晋升，别管它
    if (!cfg || Number(cfg.upgradeCard) === id) continue;
    const missing = 2 - (have.get(id) || 0);
    if (missing > 0) return { card_id: id, missing };
  }
  return null;
}

// 返回补发的蓝图 id 列表（空数组 = 什么都没做）。幂等：补过的卡记进 repaired_cards。
function repairUnupgradableBuilding(player) {
  if (!exploreLockedByStory(player)) return [];
  const u = player && player.universe;
  if (!u || !u.active) return [];
  if (!Array.isArray(u.repaired_cards)) u.repaired_cards = [];
  const need = unupgradableBuilding(u);
  if (!need || u.repaired_cards.includes(need.card_id)) return [];
  if ((u.cards || []).length + need.missing > HAND_LEN_MAX) return [];  // 手牌放不下，交给 GM
  for (let i = 0; i < need.missing; i++) u.cards.push(need.card_id);
  u.repaired_cards.push(need.card_id);
  return new Array(need.missing).fill(need.card_id);
}

// ---------------- 建筑蓝图（卡牌）三选一 ----------------
//
// 可出的卡表来自 `d_srpg_effect_trigger.effectConfig`，**不是**「全表随机」：
//   d_srpg_shop_item.itemEffectTriggerID → 6001..6019/60xx（游商卖蓝图）
//   事件选项的 effectTriggerID            → 6049/6050/6060/6231…（事件给蓝图）
// 表里 `effectConfig` 就是本次可出的卡牌 id 列表（6001 → 卡池 1 的
// [10002,10011,10018,10023]；6060 → 单卡 [10015]）。
//
// 客户端画「重选」按钮时读 `d_srpg_card_pool[pool_id]`（UI_Panel_ChooseReward_C:148-168），
// 所以 pool_id 必须指向真实存在的卡池行；`d_srpg_card_pool[N].cardList` 装的是
// `d_srpg_card_list` 的行号，`d_srpg_card_list[M].cardList` 才是卡牌 id。
const CARD_SELECT_MAX = 3;
const DEFAULT_CARD_POOL_ID = 1;

function shuffle(list) {
  const out = list.slice();
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    const t = out[i]; out[i] = out[j]; out[j] = t;
  }
  return out;
}

// Lua 里的空表会被转成 `{}`（对象），repeated 字段也可能是对象 —— 统一成数组。
// 注意**不去重**：效果列表是有序多集（教学 11007 的 option 110071 就是
// [6060,6060,6060] = 三次「获得一张卡牌」，去重会只剩下一次）。
function intArray(value) {
  const raw = Array.isArray(value) ? value
    : (value && typeof value === 'object' ? Object.values(value) : []);
  const out = [];
  for (const v of raw) {
    const n = Number(v);
    if (Number.isFinite(n)) out.push(n);
  }
  return out;
}

// effectConfig 里的卡牌 id 列表（过滤掉表里不存在的 id，并按 id 去重）
function cardListOf(value) {
  const out = [];
  for (const c of intArray(value)) {
    if (c > 0 && gd.query('d_srpg_card_base', c) && !out.includes(c)) out.push(c);
  }
  return out;
}

function cardsOfPool(poolId) {
  const pool = gd.query('d_srpg_card_pool', poolId);
  const out = [];
  for (const ref of intArray(pool && pool.cardList)) {
    const list = gd.query('d_srpg_card_list', ref);
    for (const c of cardListOf(list && list.cardList)) if (!out.includes(c)) out.push(c);
  }
  return out;
}

// 卡表 → 卡池 id：优先与某个池的卡表**完全一致**的那一行（6001 → 池 1），
// 否则退回默认池（教学事件 11007 的 [10015] 单卡表在卡池里没有对应行）。
function poolIdForCards(cards) {
  const want = new Set(cards);
  for (const [id] of gd.rows('d_srpg_card_pool')) {
    const list = cardsOfPool(id);
    if (list.length && list.length === want.size && list.every((c) => want.has(c))) {
      return Number(id);
    }
  }
  return DEFAULT_CARD_POOL_ID;
}

function newCardSelect(u, fromCardIds = null) {
  const source = cardListOf(fromCardIds);
  // fromCardIds 为空（调用方没给卡表）才退化为全表随机
  const pool = source.length ? source : gd.rows('d_srpg_card_base').map(([id]) => Number(id));
  const poolRows = gd.rows('d_srpg_card_pool').map(([, r]) => r);
  return {
    select_uuid: u.select_seq++,
    card_ids: shuffle(pool).slice(0, CARD_SELECT_MAX),
    refresh_times: 0,
    pool_id: source.length ? poolIdForCards(source) : (poolRows[0] || { id: 1 }).id,
    // 服务端自己用：客户端重选时从同一张卡表里重摇（不发给客户端）
    source_card_ids: source,
  };
}

function makeCardSelect(u, fromCardIds = null) {
  u.cards_for_select = newCardSelect(u, fromCardIds);
  if (!Array.isArray(u.extra_card_selects)) u.extra_card_selects = [];
  return u.cards_for_select;
}

// 追加一次三选一。一次事件可以给好几次（教学事件 11007 的 option 110071 是
// [6060,6060,6060]，即「获得三张卡牌」= 三次单卡选择），客户端把 SelectCard
// 事件排队、一次只开一个面板（SrpgModel:AddEvent/PopEvent + SrpgController:UpdateEvent），
// 所以服务端要把每一次都下发：最早的那次沿用 u.cards_for_select（老存档兼容），
// 其余进 u.extra_card_selects。
function addCardSelect(u, fromCardIds = null) {
  if (!u.cards_for_select) return makeCardSelect(u, fromCardIds);
  if (!Array.isArray(u.extra_card_selects)) u.extra_card_selects = [];
  const sel = newCardSelect(u, fromCardIds);
  u.extra_card_selects.push(sel);
  return sel;
}

function cardSelects(u) {
  const out = [];
  if (!u) return out;
  if (u.cards_for_select) out.push(u.cards_for_select);
  if (Array.isArray(u.extra_card_selects)) out.push(...u.extra_card_selects);
  return out;
}

function findCardSelect(u, uuid) {
  return cardSelects(u).find((s) => String(s.select_uuid) === String(uuid)) || null;
}

function dropCardSelect(u, uuid) {
  if (u.cards_for_select && String(u.cards_for_select.select_uuid) === String(uuid)) {
    u.cards_for_select = null;
  }
  if (Array.isArray(u.extra_card_selects)) {
    u.extra_card_selects = u.extra_card_selects.filter(
      (s) => String(s.select_uuid) !== String(uuid),
    );
  }
  // u.cards_for_select 始终指向剩下的最早一次，存档与建包的顺序才稳定
  if (!u.cards_for_select && u.extra_card_selects.length) {
    u.cards_for_select = u.extra_card_selects.shift();
  }
  if (!u.cards_for_select) u.extra_card_selects = [];
}

// 重选：从这次选择自己的卡表里重摇（而不是全表随机）
function refreshCardSelect(u, sel) {
  const source = cardListOf(sel.source_card_ids);
  const pool = source.length ? source : gd.rows('d_srpg_card_base').map(([id]) => Number(id));
  sel.card_ids = shuffle(pool).slice(0, CARD_SELECT_MAX);
  sel.refresh_times += 1;
  return sel.card_ids;
}

function makeCurioSelect(u, fromCurioIds = null) {
  const source = intArray(fromCurioIds).filter((c) => !!gd.query('d_srpg_curio_base', c));
  const allCurios = source.length ? source : gd.rows('d_srpg_curio_base').map(([id]) => Number(id));
  u.curios_for_select = {
    select_uuid: u.select_seq++,
    curio_ids: shuffle(allCurios).slice(0, CARD_SELECT_MAX),
    refresh_times: 0,
    pool_id: (gd.rows('d_srpg_curio_pool')[0] || { id: 1 })[1].id,
    source_curio_ids: source,
  };
  return u.curios_for_select;
}

// 异宝重选：同样从这次选择自己的池子里重摇
function refreshCurioSelect(u, sel) {
  const source = intArray(sel.source_curio_ids).filter((c) => !!gd.query('d_srpg_curio_base', c));
  const pool = source.length ? source : gd.rows('d_srpg_curio_base').map(([id]) => Number(id));
  sel.curio_ids = shuffle(pool).slice(0, CARD_SELECT_MAX);
  sel.refresh_times += 1;
  return sel.curio_ids;
}

// 异宝（奇物）池：`d_srpg_card_base[card].curioPool` → `d_srpg_curio_pool[pool].curioList`
// → `d_srpg_curio_list[list].curioList` 才是真正的异宝 id。官方口径见教学文案
// 「晋升1个建筑……并获得一个异宝作为奖励」（d_word_cn 113211007）。
function curioPoolList(cardId) {
  const card = gd.query('d_srpg_card_base', cardId);
  const pool = card ? gd.query('d_srpg_curio_pool', card.curioPool) : null;
  const out = [];
  for (const ref of intArray(pool && pool.curioList)) {
    const list = gd.query('d_srpg_curio_list', ref);
    for (const c of intArray(list && list.curioList)) if (!out.includes(c)) out.push(c);
  }
  return out;
}

// 事件与事件选项的 id 规则：选项 = 事件 id * 10 + 序号（1..6）。
// 全表 280 条选项都能被这套规则归到某个 d_srpg_event_base 行上（无一孤儿）。
function makeEvent(u, eventId) {
  const event = gd.query('d_srpg_event_base', eventId);
  if (!event) return null;
  const options = [];
  for (let n = 1; n <= 6; n++) {
    const oid = eventId * 10 + n;
    if (gd.query('d_srpg_event_option', oid)) options.push({ option_id: oid });
  }
  if (!options.length) return null;
  const e = { event_uuid: u.event_seq++, event_id: eventId, options };
  u.events.push(e);
  return e;
}

function makeMission(u) {
  const m = {
    mission_uuid: u.mission_seq++,
    mission_id: 1, // d_srpg_mission[1]
    begin_turn: u.turn,
    begin_step: u.step,
    result: 0,
    end_turn: 0,
    end_step: 0,
  };
  u.missions.push(m);
  return m;
}

module.exports = {
  HEX_NEIGHBORS, hexKey, encHex, newUniverse, buildUniverseInfo, revealFrontier,
  changeResource, resourceDeltas, spendResource, substitutionCostOf, ensureBossReachable,
  attachForPos, refreshAttach, spawnDueBossWaves, reconcileBossWaves, pickBossCell,
  posAt, neighborsOf,
  newFight, makeCardSelect, addCardSelect, cardSelects, findCardSelect, dropCardSelect,
  refreshCardSelect, intArray, cardListOf, cardsOfPool, poolIdForCards, cardsForEffectConfig,
  HAND_LEN_MAX, exploreLockedByStory, unupgradableBuilding, repairUnupgradableBuilding,
  makeCurioSelect, refreshCurioSelect, curioPoolList, makeEvent, makeMission,
  randomEncounterLevel, adjacent, dist, characterMaxHp,
  distanceField, routeToBase, revealBossRoute, advanceBosses, stepBossTowardsBase,
};
