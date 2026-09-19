// In-process regression checks for the Universe (肉鸽/星图) run's map binding,
// cell attachments and boss waves.
//
// Regression target 1 — map binding: a run must be priced and laid out from the
// SAME d_srpg_map_base row as its `map_id`. The generic entry picks a map by
// mapType, but `req_new_universe_specific` enters a story map by id — the old
// code overwrote `map_id` afterwards and kept mapType-1's `substitutionCost`.
// The client prices a character swap with
//   Database.Query("d_srpg_map_base", model.mapId).substitutionCost
// (UI_character_exchange_C:96/172), so the mismatch made the client show 0
// while the server charged 50/swap → after the resource ran dry every click
// answered RES_NOT_ENOUGH(4): 「cmd:1018 code:4」.
//
// Regression target 2 — attachments: which cells are building slots / merchants
// is a property of d_srpg_main_pos_base.posModel+nameId, not of the numeric
// prefix of the cell id (see game/universe.js attachForPos). Getting it wrong
// hid the 「管理」 option on every 建筑格, which dead-ends the story tasks
// 「部署1个建筑」/「晋升1个建筑」/「拆除1个建筑」 (100031201/203/205).
//
// Regression target 3 — boss waves: d_srpg_level_boss.appearTime decides when a
// wave shows up. Spawning one at run creation (and replacing it right after each
// kill) kept the 「败者首领」 banner on screen forever (坑 27).
//
// Regression target 4 — effect parameters: a d_srpg_effect_trigger row carries
// `effectConfig`, not `config`. Reading the wrong field silently degraded every
// explore consequence to its hard-coded default (placeholder event 20001, random
// battle level, and — fatally — card selects drawn from all 171 blueprints), so
// the story task 100031203 「晋升1个建筑」 could never be finished: upgrading needs
// two extra copies of the deployed blueprint, and the tutorial only ever hands
// those out through the scripted event 11007 → option 110071 (effectTriggerID
// [6060,6060,6060] → three times the single-card list [10015]).
//
// Regression target 5 — boss movement: the official rule is 「每回合向巡航基地
// 移动1格；抵达后每回合扣取1点生存值」 (d_word_cn 113211012 / 113220008). The
// client never moves a boss itself (it only diffs the hexes it is handed in
// ntf_boss_info), so the walk has to happen server-side.
//
// No server needed. Must run before requiring the server modules: store.js
// reads GHS_DATA_DIR at load time so the saves stay out of the real data/ dir.
const os = require('os');
const fs = require('fs');
const path = require('path');
const tmpDataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ghs-universe-'));
process.env.GHS_DATA_DIR = tmpDataDir;

const { createPlayerDoc } = require('../src/game/player_new');
const { migratePlayer } = require('../src/game/migrate');
const U = require('../src/game/universe');
const gd = require('../src/gamedata');

const STORY_SPECIFIC = 1000309;   // d_srpg_map_specific[1000309].map = 1000309
const STORY_MAP = 1000309;        // d_srpg_map_base[1000309].substitutionCost = [2, 0]
const FREE_MAP = 1000309;
const PAID_MAP = 1;               // d_srpg_map_base[1].substitutionCost = [2, 50]

let failures = 0;
function check(cond, msg) {
  console.log(cond ? `  PASS ${msg}` : `  FAIL ${msg}`);
  if (!cond) failures += 1;
}

function mapParams(over = {}) {
  return { difficulty_value: 1, main_planet_id: 110, map_type: 1, character_ids: [10101], ...over };
}

const cells = (u) => Object.keys(u.main_pos).length;

// total count of an item in a player doc's bag (stackables merge into one entry)
const itemCount = (doc, itemId) => doc.bag.items
  .filter((it) => Number(it.item_id) === Number(itemId))
  .reduce((s, it) => s + Number(it.count || 0), 0);

// ---------------- table assumptions ----------------
// If these fail the game data changed and the fix below needs revisiting.
{
  const story = gd.query('d_srpg_map_base', STORY_MAP);
  const paid = gd.query('d_srpg_map_base', PAID_MAP);
  const spec = gd.query('d_srpg_map_specific', STORY_SPECIFIC);
  check(!!story && JSON.stringify(story.substitutionCost) === '[2,0]',
    `${STORY_MAP} is the free-substitution story map ([2,0])`);
  check(!!paid && JSON.stringify(paid.substitutionCost) === '[2,50]',
    `${PAID_MAP} is a paid-substitution map ([2,50])`);
  check(!!spec && Number(spec.map) === STORY_MAP,
    `${STORY_SPECIFIC} is bound to map ${STORY_MAP}`);
  check(gd.query('d_srpg_map_data', STORY_MAP) != null,
    `map ${STORY_MAP} has its own d_srpg_map_data row`);
}

// ---------------- generic entry still picks by mapType ----------------
{
  const u = U.newUniverse(mapParams({ map_type: 1 }));
  check(u.map_id === PAID_MAP, `generic map_type=1 run picks map ${PAID_MAP}`);
  check(JSON.stringify(u.substitution_cost) === '[2,50]',
    `generic run stores substitutionCost [2,50]`);
}

// ---------------- specific entry binds the whole run to its own map ----------------
{
  const u = U.newUniverse(mapParams(), STORY_MAP);
  check(u.map_id === STORY_MAP, `forced run picks map ${STORY_MAP}`);
  check(JSON.stringify(u.substitution_cost) === '[2,0]',
    `forced run stores the map's own substitutionCost [2,0]`);
  check(cells(u) === (gd.query('d_srpg_map_data', STORY_MAP).mainPosId || []).length,
    `forced run lays out map ${STORY_MAP}'s own hexes (${cells(u)} cells)`);
  check(cells(u) !== cells(U.newUniverse(mapParams({ map_type: 1 }))),
    'story layout differs from the mapType-1 layout (no more borrowed map)');
}

// ---------------- unknown forced id falls back instead of crashing ----------------
{
  const u = U.newUniverse(mapParams(), 99999999);
  check(u.map_id === PAID_MAP && cells(u) > 0,
    'unknown forced map id falls back to the mapType-selected map');
}

// ---------------- cell attachments (建筑格 / 游商) ----------------
// The client renders the 「管理」 option only for cells whose
// main_pos_attach_infos carries main_pos_card_pos_info (UI_Menu_C:1367-1376), and
// BuildSystem/CardSelector pick the slot from there; a 建筑格 without it is
// indistinguishable from empty space. The old prefix-based guess also attached
// shops to 819/829/839 (A47_FreeCard = building cells).
{
  const story = U.newUniverse(mapParams(), STORY_MAP);
  const cellsOf = (u, kind) => Object.values(u.main_pos)
    .filter((c) => c.attach && c.attach[`main_pos_${kind}`]);
  const cardCells = (u) => Object.values(u.main_pos).filter((c) => {
    const a = c.attach && c.attach.main_pos_card_pos_info;
    return a && a.card_id === 0;
  });

  // the tutorial's three 建筑格 are d_srpg_main_pos_base 102 (nameId 102000101)
  check(Object.values(story.main_pos).filter((c) => c.main_pos_id === 102).length === 3,
    'the story map has three 建筑格 cells (d_srpg_main_pos_base 102)');
  check(cardCells(story).length === 3,
    'all three 建筑格 carry a card slot (部署1个建筑 becomes clickable)');
  check(cardCells(story).every((c) => c.attach.main_pos_card_pos_info.card_pos_id === 3),
    'story-map slots use d_srpg_card_pos 3 (free recall, [2,0] — 「本次教学中临时免费」)');
  check(cellsOf(story, 'shop_info').length === 2,
    'the story map\'s two A45_MerchantA cells carry a shop');
  check(cellsOf(story, 'shop_info').every((c) => c.attach.main_pos_shop_info.shop_id === 1),
    'the tutorial merchants run d_srpg_shop_base 1 (blueprint merchant)');

  // generic map: A47_FreeCard is a building cell, A45_MerchantA a shop — the old
  // prefix rule had both backwards
  const generic = U.newUniverse(mapParams({ map_type: 1 }));
  check(cardCells(generic).length > 0,
    'generic map exposes building slots where d_srpg_main_pos_base has A47_FreeCard');
  check(cardCells(generic).every((c) => {
    const row = gd.query('d_srpg_main_pos_base', c.main_pos_id) || {};
    // either an explicit building model or the 「建筑格」 name (pos 101, the six
    // cells ringing the base, is nameId 102000101 with a B01_Nothing model)
    return /FreeCard|^A39_Building/.test(String(row.posModel))
      || [102000101, 102000102].includes(Number(row.nameId));
  }), 'only real 建筑格 / A47_FreeCard / A39_Building cells become card slots');
  check(cellsOf(generic, 'shop_info').every((c) => /Merchant/.test(
    (gd.query('d_srpg_main_pos_base', c.main_pos_id) || {}).posModel)),
    'only merchant cells become shops (819/829/839 no longer masquerade as shops)');
  check(cellsOf(generic, 'shop_info').length === 2,
    'the generic map has 2 merchant cells (both A45_MerchantA)');
  check(cardCells(generic).every((c) => c.attach.main_pos_card_pos_info.card_pos_id === 1),
    'non-story maps use the paid slot d_srpg_card_pos 1');

  // add-only repair for saves written by the old server
  const legacy = U.newUniverse(mapParams(), STORY_MAP);
  for (const c of Object.values(legacy.main_pos)) c.attach = null;
  check(U.refreshAttach(legacy) === true, 'refreshAttach rebuilds missing attachments');
  check(cardCells(legacy).length === 3, 'the rebuilt run gets its 3 building slots back');
  check(U.refreshAttach(legacy) === false, 'refreshAttach is idempotent');
  const built = cardCells(legacy)[0];
  built.attach.main_pos_card_pos_info.card_id = 10001;  // an in-progress build
  U.refreshAttach(legacy);
  check(cardCells(legacy).length === 2 && built.attach.main_pos_card_pos_info.card_id === 10001,
    'refreshAttach never disturbs a slot the player already built on');
}

// ---------------- deploy / upgrade / demolish / recall a building ----------------
// The story tasks 100031201（部署1个建筑）/ 100031203（晋升）/ 100031205（拆除）are
// counted client-side from the res of these four handlers (QuestSystem.lua:1204-1226),
// so each one has to answer OK and leave the hand + slot + resources consistent.
{
  const handle = require('../src/handlers/universe').handle;
  const doc = createPlayerDoc(9006);
  const sent = [];
  const session = { player: doc, send: (name, msg, result) => sent.push({ name, msg, result }) };
  const call = (name, req) => { sent.length = 0; handle(name)(session, req || {}); return sent; };

  call('req_new_universe_specific', { specific_id: STORY_SPECIFIC });
  const run = doc.universe;
  const slot = Object.values(run.main_pos).find((c) => c.attach && c.attach.main_pos_card_pos_info);
  check(!!slot, 'the story run exposes a building slot to deploy on');
  check(slot.attach.main_pos_card_pos_info.card_pos_id === 3,
    'the tutorial slot is the free-recall one (d_srpg_card_pos 3)');
  const attachOf = () => U.posAt(run, slot.hex).attach.main_pos_card_pos_info;

  // d_srpg_card_base 10001 → upgradeCard 10101
  run.cards.push(10001, 10001, 10002);

  check(call('req_place_card', { hex: slot.hex, attach_index: 0, index_in_hand: 0 })[0].result === undefined,
    'req_place_card answers OK (部署1个建筑)');
  check(attachOf().card_id === 10001 && run.cards.length === 2,
    'placing moves the blueprint from the hand onto the cell');

  check(call('req_upgrade_card', { hex: slot.hex, attach_index: 0, index_in_hand: [0, 1] })[0].result === undefined,
    'req_upgrade_card answers OK (晋升1个建筑)');
  check(attachOf().card_id === 10101 && attachOf().upgrade_times === 1 && run.cards.length === 0,
    'upgrading consumes the two spare blueprints and swaps in the upgraded card');

  const before = run.res_value.slice();
  check(call('req_recall_card', { hex: slot.hex, attach_index: 0 })[0].result === undefined,
    'req_recall_card answers OK');
  check(attachOf().card_id === 0 && run.cards.includes(10101),
    'recalling returns the building to the hand as its upgraded blueprint');
  check(JSON.stringify(run.res_value) === JSON.stringify(before),
    'the tutorial slot recalls for free (recallCost [2,0])');

  check(call('req_demolition_card', { hex: slot.hex, attach_index: 0 })[0].result === 4,
    'demolishing an empty slot answers CARD_NOT_EXISTS(4) instead of silently succeeding');

  // a non-story map charges the paid slot costs (d_srpg_card_pos 1)
  const paidDoc = createPlayerDoc(9007);
  const paidSent = [];
  const paidSession = { player: paidDoc, send: (n, m, r) => paidSent.push({ name: n, msg: m, result: r }) };
  const paidCall = (n, r) => { paidSent.length = 0; handle(n)(paidSession, r || {}); return paidSent; };
  paidCall('req_new_universe', mapParams({ map_type: 1 }));
  const paidRun = paidDoc.universe;
  const paidSlot = Object.values(paidRun.main_pos).find((c) => c.attach && c.attach.main_pos_card_pos_info);
  check(paidSlot.attach.main_pos_card_pos_info.card_pos_id === 1, 'generic slots use d_srpg_card_pos 1');
  paidRun.cards.push(10001);
  paidCall('req_place_card', { hex: paidSlot.hex, attach_index: 0, index_in_hand: 0 });
  const purse = paidRun.res_value[2];
  paidCall('req_recall_card', { hex: paidSlot.hex, attach_index: 0 });
  check(paidRun.res_value[2] === purse - 20,
    'a generic map charges the paid recallCost (d_srpg_card_pos 1 → [2,20])');
}

// ---------------- boss waves follow d_srpg_level_boss.appearTime ----------------
// SrpgModel:Init/UpdateBossInfo → UpdateBossLines runs
//   astar.path(start, goal, aStarNodes, ...)
// where aStarNodes only contains cells with state > 1 (UniverseUtils.IsReachable).
// A boss on an unrevealed cell makes `start` nil → astar raises
// "table index is nil" → the res_*universe* handler dies mid-way (its
// MessageManager:Broadcast never runs → BP_GameInstance_C never loads
// UniverseMap → endless loading). See 坑 26.
//
// A wave also must not exist before its appearTime step: the client renders the
// 「败者首领」banner purely from `#bossInfo` (UI_Menu_C:774), and since it never
// advances a boss on its own, a boss spawned at creation (or re-spawned right
// after every kill) leaves that banner up forever. See 坑 27.
{
  const bossCells = (u) => u.boss_infos.map((b) => U.posAt(u, { q: b.hex.q, r: b.hex.r }));
  const bossBase = gd.query('d_srpg_level_boss', 11);   // map 1 / generic
  const storyBoss = gd.query('d_srpg_level_boss', 17);  // map 1000309 / story

  for (const [label, u, cfg, time] of [
    ['generic', U.newUniverse(mapParams({ map_type: 1 })), bossBase, bossBase.appearTime[0]],
    ['story-specific', U.newUniverse(mapParams(), STORY_MAP), storyBoss, storyBoss.appearTime[0]],
  ]) {
    check(u.boss_infos.length === 0 && u.boss_wave === -1,
      `${label} run starts with no boss on the map (appearTime ${time} not reached)`);

    u.step = Number(time) - 1;
    check(U.spawnDueBossWaves(u) === null, `${label} no wave before its appearTime step`);

    u.step = Number(time);
    const revealed = U.spawnDueBossWaves(u);
    check(Array.isArray(revealed), `${label} wave spawns on step ${time}`);
    check(u.boss_infos.length === 1 && u.boss_wave === 0, `${label} wave 0 is the only live boss`);
    check(bossCells(u).every((c) => c && c.state > 1),
      `${label} boss stands on a reachable cell (state > 1)`);
    check(bossCells(u).every((c) => c && U.hexKey(c.hex) !== U.hexKey(u.base_hex)),
      `${label} boss does not spawn on the base cell`);
    check(bossCells(u).every((c) => U.dist(c.hex, u.base_hex) === Number(cfg.distance[0])),
      `${label} boss stands on the ring d_srpg_level_boss.distance asks for`);
    check(U.spawnDueBossWaves(u) === null, `${label} spawnDueBossWaves is idempotent`);
  }

  // the base cell itself must stay reachable — it is astar's `goal` node
  const u = U.newUniverse(mapParams(), STORY_MAP);
  const base = U.posAt(u, u.base_hex);
  check(!!base && base.state > 1, 'base cell is reachable (astar goal node)');

  // single-wave boss: killing it finishes the run, it is not replaced
  const solo = U.newUniverse(mapParams({ map_type: 1 }));
  solo.step = Number(bossBase.appearTime[0]);
  U.spawnDueBossWaves(solo);
  solo.turn = 1;                       // what req_complete_boss_fight does on a win
  solo.boss_infos = [];
  check(U.spawnDueBossWaves(solo) === null,
    'a killed final wave is not respawned (banner can finally clear)');

  // multi-wave boss (13 → appearTime [15,24,32]): exploring past two marks leaves
  // both waves alive; killing wave 0 leaves only the wave that is actually due
  const multi = U.newUniverse(mapParams({ difficulty_value: 1, main_planet_id: 110, map_type: 2, character_ids: [10101] }));
  check(multi.boss_id === 13, 'map_type=2 run uses the 3-wave boss (d_srpg_level_boss 13)');
  multi.step = 24;
  U.spawnDueBossWaves(multi);
  check(multi.boss_infos.map((b) => b.boss_index).join(',') === '0,1',
    'two due waves are alive at once');
  multi.turn = 1; multi.boss_infos = multi.boss_infos.filter((b) => b.boss_index !== 0);
  check(U.spawnDueBossWaves(multi) === null, 'killing wave 0 does not respawn it');
  multi.step = 32;
  U.spawnDueBossWaves(multi);
  check(multi.boss_infos.map((b) => b.boss_index).join(',') === '1,2',
    'wave 2 shows up on its own appearTime step');
  check(new Set(multi.boss_infos.map((b) => `${b.hex.q},${b.hex.r}`)).size === multi.boss_infos.length,
    'simultaneous waves never share a cell');

  // old saves: an unrevealed boss cell gets revealed on load, idempotently
  const old = U.newUniverse(mapParams({ map_type: 1 }));
  const oldCell = U.pickBossCell(old, 1);
  check(!!oldCell, 'pickBossCell finds a cell to park an old save\'s boss on');
  oldCell.state = 0;                       // what old servers persisted
  old.boss_infos = [{ boss_index: 0, fight_uuid: '0', hex: { q: oldCell.hex.q, r: oldCell.hex.r } }];
  check(U.ensureBossReachable(old) === true, 'ensureBossReachable reports the fix');
  check(oldCell.state === 2, 'the boss cell is promoted to state 2');
  check(U.ensureBossReachable(old) === false, 'ensureBossReachable is idempotent');
  check(U.ensureBossReachable(null) === false, 'ensureBossReachable tolerates a missing run');
}

// ---------------- pricing always follows map_id, never a stale copy ----------------
{
  const stale = { map_id: FREE_MAP, substitution_cost: [2, 50], res_value: [0, 100, 100, 100, 100] };
  check(JSON.stringify(U.substitutionCostOf(stale)) === '[2,0]',
    'a stale saved substitution_cost is ignored in favour of the map table');

  const live = { map_id: PAID_MAP, substitution_cost: [2, 0], res_value: [0, 100, 100, 100, 100] };
  check(JSON.stringify(U.substitutionCostOf(live)) === '[2,50]',
    'the map table wins even when the saved copy says the swap is free');

  const nobag = { map_id: 99999999, substitution_cost: [2, 50], res_value: [0, 0, 0, 0, 0] };
  check(JSON.stringify(U.substitutionCostOf(nobag)) === '[2,50]',
    'an unresolvable map_id keeps the stored cost');

  // The real failure mode: map says free → the swap must succeed on an empty
  // purse, and must not touch any resource slot.
  const before = [0, 100, 0, 100, 100];
  const u = { map_id: FREE_MAP, substitution_cost: [2, 50], res_value: before.slice() };
  const cost = U.substitutionCostOf(u);
  const amount = Math.max(0, Number(cost[1]) || 0);
  const affordableEnough = amount === 0 ||
    ((u.res_value[cost[0]] ?? 0) >= amount && U.spendResource(u, cost[0], amount));
  check(affordableEnough, 'a free-substitution map never answers RES_NOT_ENOUGH(4)');
  check(JSON.stringify(u.res_value) === JSON.stringify(before),
    'a free swap leaves the resource array untouched');
}

// ---------------- old saves are repaired on load ----------------
{
  const doc = createPlayerDoc(9001);
  doc.universe = {
    active: true,
    map_id: FREE_MAP,
    specific_id: STORY_SPECIFIC,
    substitution_cost: [2, 50],           // what the old server persisted
    res_value: [0, 100, 0, 100, 100],
    cur_hp: 4,
  };
  const snapped = JSON.stringify(doc.universe);
  check(migratePlayer(doc) === true, 'migratePlayer reports the universe fix as a change');
  check(JSON.stringify(doc.universe.substitution_cost) === '[2,0]',
    'in-progress run gets the map table\'s substitutionCost on load');
  check(doc.universe.res_value[2] === 0 && doc.universe.cur_hp === 4 &&
        doc.universe.map_id === FREE_MAP,
    'migration only touches the price — resources/HP/map stay as played');
  check(migratePlayer(doc) === false || JSON.stringify(doc.universe) !== snapped,
    'migration is idempotent');

  const done = createPlayerDoc(9002);
  done.universe = { active: false, map_id: FREE_MAP, substitution_cost: [2, 50] };
  migratePlayer(done);
  check(JSON.stringify(done.universe.substitution_cost) === '[2,50]',
    'a finished (inactive) run is not touched');

  // an old active run with an unrevealed boss cell gets it revealed on load
  const bossy = createPlayerDoc(9003);
  const run = U.newUniverse(mapParams({ map_type: 1 }));
  run.step = Number((gd.query('d_srpg_level_boss', run.boss_id) || {}).appearTime[0] || 1);
  U.spawnDueBossWaves(run);
  const oldBossCell = U.posAt(run, run.boss_infos[0].hex);
  oldBossCell.state = 0;                    // what old servers persisted
  bossy.universe = run;
  check(migratePlayer(bossy) === true, 'migratePlayer repairs the boss cell too');
  check(oldBossCell.state === 2, 'the loaded run\'s boss cell becomes reachable');
  const before2 = JSON.stringify(run);
  migratePlayer(bossy);
  check(JSON.stringify(run) === before2, 'boss-cell migration is idempotent');
}

// ---------------- next boss wave keeps the same invariant ----------------
// Boss 13 (maps 3/4, map_type 2) has 3 waves with appearTime [15,24,32], so
// winning wave 0 during step 15 hands the client a boss list without wave 0 and
// without a new one (wave 1 is only due at step 24). That is what finally lets
// the 「败者首领」 banner clear. When two waves are due at once the reveal must
// still be pushed before ntf_boss_info so UpdateBossLines has a valid start.
{
  const complete = require('../src/handlers/universe').handle('req_complete_boss_fight');
  const doc = createPlayerDoc(9004);
  const run = U.newUniverse({ difficulty_value: 1, main_planet_id: 110, map_type: 2, character_ids: [10101] });
  const cfg = gd.query('d_srpg_level_boss', run.boss_id);
  check((cfg || {}).path?.length > 1,
    'map_type=2 run uses a multi-wave boss (d_srpg_level_boss 13)');
  doc.universe = run;
  const sent = [];
  const session = { player: doc, send: (name, msg, result) => sent.push({ name, msg, result }) };

  // step 24 with both wave 0 and wave 1 already due and alive
  run.step = Number(cfg.appearTime[1]);
  U.spawnDueBossWaves(run);
  check(run.boss_infos.length === 2, 'waves 0 and 1 are both alive at step 24');

  const target = run.boss_infos[0];
  sent.length = 0;
  complete(session, {
    boss_index: target.boss_index, result: true, universe_fight_data: {},
  });

  check(run.boss_infos.length === 1 && run.boss_infos[0].boss_index === 1,
    'winning wave 0 leaves exactly the still-due wave 1 (no instant respawn)');
  check(run.turn === 1, 'the server counts the kill in `turn`, like the client does');
  const nb = run.boss_infos[0];
  const cell = U.posAt(run, { q: nb.hex.q, r: nb.hex.r });
  check(!!cell && cell.state > 1, 'the surviving boss stands on a reachable cell');
  check(!sent.some((s) => s.name === 'ntf_boss_info'),
    'no ntf_boss_info is pushed when no new wave is due');

  // now a wave does become due: the reveal must precede the announcement
  const doc2 = createPlayerDoc(9005);
  const run2 = U.newUniverse({ difficulty_value: 1, main_planet_id: 110, map_type: 2, character_ids: [10101] });
  doc2.universe = run2;
  const sent2 = [];
  const session2 = { player: doc2, send: (name, msg, result) => sent2.push({ name, msg, result }) };
  run2.step = Number(cfg.appearTime[0]);
  U.spawnDueBossWaves(run2);
  run2.step = Number(cfg.appearTime[1]);
  complete(session2, { boss_index: 0, result: true, universe_fight_data: {} });
  check(run2.boss_infos.length === 1 && run2.boss_infos[0].boss_index === 1,
    'a wave that becomes due while exploring is announced at kill time');

  // Replay the messages as the client sees them: ntf_boss_info runs
  // UpdateBossLines → astar from each boss hex, which needs every boss cell to
  // already be reachable. The server may skip the reveal when the cell happens
  // to be revealed already; what matters is the state at that instant.
  const clientState = new Map(
    Object.values(run2.main_pos).map((c) => [`${c.hex.q},${c.hex.r}`, c.state]),
  );
  let ordered = true;
  let sawBossNtf = false;
  for (const s of sent2) {
    if (s.name === 'ntf_main_pos_state_change') {
      for (const ch of s.msg.main_pos_state_changes) {
        clientState.set(`${ch.hex.q},${ch.hex.r}`, Number(ch.state));
      }
    } else if (s.name === 'ntf_boss_info') {
      sawBossNtf = true;
      for (const b of s.msg.boss_infos) {
        if ((clientState.get(`${b.hex.q},${b.hex.r}`) ?? 0) <= 1) ordered = false;
      }
    }
  }
  check(sawBossNtf, 'the new wave is announced to the client');
  check(ordered, 'every announced boss cell is already reachable client-side');
}

// ---------------- the run only ends once no wave is left ----------------
// Clearing is decided by "no live boss AND no appearTime left to come": killing
// wave 2 while waves 0/1 are still alive must not end the run (they would be
// stranded), and killing the last live boss at the last appearTime must.
{
  const handle = require('../src/handlers/universe').handle;
  const cfg = gd.query('d_srpg_level_boss', 13);
  const build = (id) => {
    const doc = createPlayerDoc(id);
    const run = U.newUniverse({ difficulty_value: 1, main_planet_id: 110, map_type: 2, character_ids: [10101] });
    for (const c of Object.values(run.main_pos)) c.state = 3;
    run.step = Number(cfg.appearTime[cfg.appearTime.length - 1]);
    U.spawnDueBossWaves(run);
    doc.universe = run;
    const sent = [];
    return { doc, run, sent, session: { player: doc, send: (n, m, r) => sent.push({ name: n, msg: m, result: r }) } };
  };

  const a = build(9008);
  check(a.run.boss_infos.length === 3, 'all three waves are alive at step 32');
  handle('req_boss_fight')(a.session, { boss_index: 2 });
  a.sent.length = 0;
  handle('req_complete_boss_fight')(a.session, { boss_index: 2, result: true, universe_fight_data: {} });
  check(a.run.boss_infos.map((b) => b.boss_index).join(',') === '0,1',
    'killing the highest-index wave first leaves the earlier ones alone');
  check(!a.sent.some((s) => s.name === 'ntf_universe_clear'),
    'the run is not cleared while other waves are still alive');

  const b = build(9009);
  for (const idx of [2, 1]) {
    handle('req_boss_fight')(b.session, { boss_index: idx });
    b.sent.length = 0;
    handle('req_complete_boss_fight')(b.session, { boss_index: idx, result: true, universe_fight_data: {} });
    check(!b.sent.some((s) => s.name === 'ntf_universe_clear'),
      `no ntf_universe_clear after killing wave ${idx} with waves left`);
  }
  handle('req_boss_fight')(b.session, { boss_index: 0 });
  b.sent.length = 0;
  handle('req_complete_boss_fight')(b.session, { boss_index: 0, result: true, universe_fight_data: {} });
  const cleared = b.sent.find((s) => s.name === 'ntf_universe_clear');
  check(!!cleared && cleared.msg.result === true,
    'the run clears on the last wave (and the banner can finally clear)');
}

// ---------------- explore consequences read effectConfig, not a vanished `config` ----------------
// A d_srpg_effect_trigger row is `effectType` + `effectConfig`. The old code read
// `cfg.config` (a field that does not exist anywhere in the table), so every
// trigger silently fell back to its hard-coded default.
{
  const trig = gd.query('d_srpg_effect_trigger', 11007);
  const opt = gd.query('d_srpg_event_option', 110071);
  check(!('config' in trig), 'd_srpg_effect_trigger rows carry effectConfig, not config');
  check(JSON.stringify(trig.effectConfig) === '[11007]' && Number(trig.effectType) === 20,
    'the story map\'s 10007 cell opens event 11007 (type 20)');

  const scripted = [].concat(opt.effectTriggerID);
  check(scripted.join(',') === '6060,6060,6060',
    'event 11007 option 110071 grants three blueprints (三次 6060)');
  const grant = gd.query('d_srpg_effect_trigger', 6060);
  check(Number(grant.effectType) === 15 && JSON.stringify(grant.effectConfig) === '[10015]',
    'each 6060 offers exactly the single blueprint 10015 (「你获得了3张相同的建筑蓝图」)');

  // type 11 (shop / battle rewards) carries a d_srpg_card_pool id
  check(U.cardsForEffectConfig(7).join(',') === '10006,10009,10020,10023',
    'effectType 11 config 7 resolves to the 燃烧 blueprint list');
  check(U.cardsForEffectConfig(20).join(',') === '10015,10018,10019,10022,10024',
    'effectType 11 config 20 resolves to the 火星 list (shop item 「随机建筑【火星】」)');
  check(U.cardsForEffectConfig(104).length === 12,
    'effectType 11 config 104 resolves to a 12-card merged pool (battle reward 6031)');
  check(U.cardsForEffectConfig(999).length === 0,
    'an unknown effectType-11 config yields no cards instead of throwing');
}

// ---------------- 主线「晋升1个建筑」(100031203) 走通 ----------------
// Regression target 4. The story map's cell 10007 (d_srpg_main_pos_base 10007)
// opens event 11007, whose option hands out three copies of blueprint 10015;
// deploying one and upgrading it with the other two is exactly what the client
// counts as OnMsg_Upgrade_Card → task 100031203.
{
  const handle = require('../src/handlers/universe').handle;
  const doc = createPlayerDoc(9010);
  const sent = [];
  const session = { player: doc, send: (n, m, r) => sent.push({ name: n, msg: m, result: r }) };
  const call = (name, req) => { sent.length = 0; handle(name)(session, req || {}); return sent; };

  call('req_new_universe_specific', { specific_id: STORY_SPECIFIC });
  const run = doc.universe;
  check(run.cards.length === 0, 'a fresh story run starts with an empty blueprint hand');

  // the tutorial's blueprint cell is d_srpg_main_pos_base 10007 (event 11007)
  const lesson = Object.values(run.main_pos).find((c) => c.main_pos_id === 10007);
  check(!!lesson, 'the story map exposes the 10007 cell (「晋升建筑」tutorial)');
  lesson.state = 2;                       // walkable (the fog state machine is covered above)
  const explored = call('req_explore', { hex: lesson.hex });
  const evNtf = explored.find((s) => s.name === 'ntf_event_info');
  check(!!evNtf && Number(evNtf.msg.event_info.event_id) === 11007,
    `exploring 10007 opens event 11007 (got ${evNtf && evNtf.msg.event_info.event_id})`);
  check(!explored.some((s) => s.name === 'ntf_event_info'
      && Number(s.msg.event_info.event_id) === 20001),
    'the placeholder event 20001 is gone');

  const ev = run.events.find((e) => e.event_id === 11007);
  check(ev.options.map((o) => o.option_id).join(',') === '110071',
    'event 11007 offers its scripted option 110071');

  const chosen = call('req_choose_event_option', { event_uuid: ev.event_uuid, index: 0 });
  const selects = chosen.filter((s) => s.name === 'ntf_add_cards_for_select');
  check(selects.length === 3,
    `「获得三张卡牌」 offers three separate picks (got ${selects.length})`);
  check(selects.every((s) => s.msg.cards_for_select.card_ids.join(',') === '10015'),
    'every pick offers only blueprint 10015 (no more all-171 random draw)');
  check(selects.every((s) => s.msg.cards_for_select.card_ids.length === 1),
    'a single-card list is offered as-is instead of being padded');
  check(Number(selects[0].msg.cards_for_select.pool_id) === 1,
    'the pick carries a real d_srpg_card_pool id (the client prices 重选 from it)');

  for (let i = 0; i < 3; i++) {
    const sel = run.cards_for_select;
    check(!!sel, `pick ${i + 1} is live`);
    call('req_choose_card', { select_uuid: sel.select_uuid, index: 0 });
  }
  check(run.cards.join(',') === '10015,10015,10015',
    'the hand ends up with three identical blueprints (凑齐同名卡)');
  check(run.cards_for_select === null && run.extra_card_selects.length === 0,
    'the pick queue drains completely');

  // 部署 → 晋升（客户端就是在这两步之后 AddMissionRecord 20001 / 20010）
  const slot = Object.values(run.main_pos).find((c) => c.attach && c.attach.main_pos_card_pos_info);
  const attachOf = () => U.posAt(run, slot.hex).attach.main_pos_card_pos_info;
  check(call('req_place_card', { hex: slot.hex, attach_index: 0, index_in_hand: 0 })[0].result === undefined,
    'req_place_card answers OK (部署1个建筑 → task 100031201)');
  check(attachOf().card_id === 10015 && run.cards.length === 2,
    'one 10015 sits on the cell, two copies remain in hand');

  const gel = run.res_value[2];
  const up = call('req_upgrade_card', { hex: slot.hex, attach_index: 0, index_in_hand: [0, 1] });
  check(up[0].result === undefined,
    'req_upgrade_card answers OK (晋升1个建筑 → task 100031203 can finally count)');
  check(attachOf().card_id === 10115 && attachOf().upgrade_times === 1 && run.cards.length === 0,
    'the building is upgraded to d_srpg_card_base 10015.upgradeCard = 10115');
  check(run.res_value[2] === gel - 50,
    '晋升 spends 50 金刚凝胶 (d_srpg_card_pos[3].upgradeCost [2,50])');
  check(up.some((s) => s.name === 'ntf_add_curios_for_select'),
    '晋升 also hands out the promised 异宝 (「并获得一个异宝作为奖励」)');
  check(U.curioPoolList(10115).length > 0 && run.curios_for_select.curio_ids
    .every((c) => U.curioPoolList(10115).includes(c)),
    'the 异宝 pick is drawn from the upgraded card\'s own curioPool');
}

// ---------------- battles use the cell's/level's own triggers ----------------
{
  const handle = require('../src/handlers/universe').handle;

  // exploring a battle cell must offer the fight level the trigger names
  const battleCellOf = (u) => Object.values(u.main_pos).find((c) => {
    const cfg = gd.query('d_srpg_main_pos_base', c.main_pos_id) || {};
    return [].concat(cfg.onExploreEffectTriggerID || []).some((t) => {
      const tr = gd.query('d_srpg_effect_trigger', t);
      return tr && Number(tr.effectType) === 30 && gd.query('d_srpg_level_base', [].concat(tr.effectConfig)[0]);
    });
  });

  const doc = createPlayerDoc(9011);
  const sent = [];
  const session = { player: doc, send: (n, m, r) => sent.push({ name: n, msg: m, result: r }) };
  const call = (name, req) => { sent.length = 0; handle(name)(session, req || {}); return sent; };
  call('req_new_universe', mapParams({ map_type: 1 }));
  const run = doc.universe;
  const battle = battleCellOf(run);
  check(!!battle, 'the generic map has a battle cell (onExploreEffectTriggerID → effectType 30)');
  const cellCfg = gd.query('d_srpg_main_pos_base', battle.main_pos_id);
  const trigId = [].concat(cellCfg.onExploreEffectTriggerID).find((t) => {
    const tr = gd.query('d_srpg_effect_trigger', t);
    return tr && Number(tr.effectType) === 30;
  });
  const wantedLevel = Number([].concat(gd.query('d_srpg_effect_trigger', trigId).effectConfig)[0]);
  battle.state = 2;
  const out = call('req_explore', { hex: battle.hex });
  const fi = out.find((s) => s.name === 'ntf_fight_info');
  check(!!fi && Number(fi.msg.fight_info.fight_level_id) === wantedLevel,
    `the encounter uses effectConfig's level ${wantedLevel} (got ${fi && fi.msg.fight_info.fight_level_id})`);

  // winning pays exactly what d_srpg_level_base[].winEffectTriggerId says — the whole
  // list, not just its first entry (the old code took list[0] and then stapled a
  // hard-coded gold/exp roll on top, plus a 60% chance of an all-171 random blueprint)
  check([].concat(gd.query('d_srpg_level_base', wantedLevel).winEffectTriggerId).length === 2,
    `level ${wantedLevel} wins through a two-entry effect list ([6031, 2050])`);
  const gel0 = run.res_value[2];
  const fightUuid = fi.msg.fight_info.fight_uuid;
  const done = call('req_complete_universe_fight', { fight_uuid: fightUuid, result: true, universe_fight_data: {} });
  check(done.some((s) => s.name === 'res_complete_universe_fight' && s.result === undefined),
    'res_complete_universe_fight answers OK');
  check(run.res_value[2] === gel0 + 50,
    'the second entry of the win list is applied too (2050 → +50 金刚凝胶)');
  check(done.some((s) => s.name === 'ntf_add_cards_for_select'),
    'the first entry (6031) offers a blueprint pick instead of a random hand-out');

  // item grants follow the same table: level 101 (a boss level) → [301] triples
  const doc1b = createPlayerDoc(9015);
  const sent1b = [];
  const session1b = { player: doc1b, send: (n, m, r) => sent1b.push({ name: n, msg: m, result: r }) };
  const call1b = (name, req) => { sent1b.length = 0; handle(name)(session1b, req || {}); return sent1b; };
  call1b('req_new_universe', mapParams({ map_type: 1 }));
  const run1b = doc1b.universe;
  const itemWin = [].concat(gd.query('d_srpg_level_base', 101).winEffectTriggerId).flatMap((t) => {
    const tr = gd.query('d_srpg_effect_trigger', t);
    if (!tr || Number(tr.effectType) !== 60) return [];
    const conf = [].concat(tr.effectConfig);
    const out2 = [];
    for (let i = 0; i + 2 < conf.length; i += 3) out2.push([conf[i], conf[i + 2]]);
    return out2;
  });
  check(itemWin.length === 4, 'breakdown check: level 101\'s win table is 4 item triples');
  const before1b = new Map(itemWin.map(([id]) => [id, itemCount(doc1b, id)]));
  const f1b = U.newFight(run1b, 101);
  call1b('req_complete_universe_fight', { fight_uuid: f1b.fight_uuid, result: true, universe_fight_data: {} });
  check(itemWin.every(([id, n]) => itemCount(doc1b, id) === before1b.get(id) + n),
    `type-60 grants follow effectConfig triples (${itemWin.map(([i, n]) => `${i}x${n}`).join(', ')})`);

  // losing costs one survival point through loseEffectTriggerId ([5001] → -1)
  const doc2 = createPlayerDoc(9012);
  const sent2 = [];
  const session2 = { player: doc2, send: (n, m, r) => sent2.push({ name: n, msg: m, result: r }) };
  const call2 = (name, req) => { sent2.length = 0; handle(name)(session2, req || {}); return sent2; };
  call2('req_new_universe', mapParams({ map_type: 1 }));
  const run2 = doc2.universe;
  const f2 = U.newFight(run2, wantedLevel);
  const hpBefore = run2.cur_hp;
  call2('req_complete_universe_fight', { fight_uuid: f2.fight_uuid, result: false, universe_fight_data: {} });
  check(run2.cur_hp === hpBefore - 1,
    'a lost encounter costs 1 survival point (loseEffectTriggerId 5001)');
}

// ---------------- 首领每回合向基地推进一格 ----------------
// Regression target 5. SrpgModel:UpdateBossInfo only broadcasts BossMoved/BossArrived
// by diffing the hexes it is handed, so the server owns the walk. Every step of the
// route has to stay client-reachable (state > 1) or the boss line's astar blows up
// (坑 26), and a boss parked on the base drains 1 survival per further turn.
{
  const cfg = gd.query('d_srpg_level_boss', 17);          // story: distance [2], appearTime [12]
  const u = U.newUniverse(mapParams(), STORY_MAP);
  u.step = Number(cfg.appearTime[0]);
  const revealed = U.spawnDueBossWaves(u);
  check(Array.isArray(revealed) && u.boss_infos.length === 1, 'the wave spawns on its appearTime step');

  const startHex = { q: u.boss_infos[0].hex.q, r: u.boss_infos[0].hex.r };
  check(U.dist(startHex, u.base_hex) === Number(cfg.distance[0]),
    `the boss starts on ring distance[0] = ${cfg.distance[0]}`);
  const route = U.routeToBase(u, startHex);
  check(route.length === Number(cfg.distance[0]) + 1
      && U.hexKey(route[route.length - 1].hex) === U.hexKey(u.base_hex),
    `a ${route.length}-cell route leads from the spawn cell to the base`);
  check(route.every((c) => c.state > 1),
    'the whole boss→base corridor is reachable (客户端 astar 的 start/goal 都不会是 nil)');
  check(revealed.every((c) => c.state === 2),
    'every cell revealed for the wave is pushed as a state change first');

  // 每回合推进一格
  let steps = 0;
  let arrivalDamage = null;
  while (U.hexKey(u.boss_infos[0].hex) !== U.hexKey(u.base_hex) && steps < 10) {
    const adv = U.advanceBosses(u);
    steps += 1;
    check(adv.changed, `turn ${steps}: the boss moved one cell toward the base`);
    if (U.hexKey(u.boss_infos[0].hex) === U.hexKey(u.base_hex)) arrivalDamage = adv.damage;
  }
  check(U.hexKey(u.boss_infos[0].hex) === U.hexKey(u.base_hex),
    `the boss walks to the base in ${steps} turns (every turn exactly one cell)`);
  check(arrivalDamage === 0 && u.cur_hp === 5,
    'the turn it arrives costs nothing yet (「抵达后」每回合扣)');
  check(U.advanceBosses(u).arrived.length === 0, 'it stays put once it is parked on the base');
  check(u.cur_hp === 4, 'each further turn drains 1 survival (「每回合扣取1点生存值」)');
  check(U.advanceBosses(u).damage === 1 && u.cur_hp === 3, 'the drain keeps ticking');

  u.cur_hp = 1;
  const fatal = U.advanceBosses(u);
  check(fatal.dead === true && u.cur_hp <= 0, 'survival 0 is reported as a run-ending hit');

  // no bosses → nothing happens at all
  const quiet = U.newUniverse(mapParams(), STORY_MAP);
  const none = U.advanceBosses(quiet);
  check(!none.changed && none.damage === 0 && none.dead === false,
    'a run without a live boss is untouched');
  check(U.advanceBosses(null).damage === 0, 'advanceBosses tolerates a missing run');

  // the same wave order the client sees: reveal first, then ntf_boss_info
  const handle = require('../src/handlers/universe').handle;
  const doc = createPlayerDoc(9013);
  const sent = [];
  const session = { player: doc, send: (n, m, r) => sent.push({ name: n, msg: m, result: r }) };
  const call = (name, req) => { sent.length = 0; handle(name)(session, req || {}); return sent; };
  call('req_new_universe_specific', { specific_id: STORY_SPECIFIC });
  const run = doc.universe;
  const explorable = () => Object.values(run.main_pos).find((c) => c.state === 2);
  const stepOnce = () => {
    const cell = explorable();
    check(!!cell, `a cell is explorable at step ${run.step}`);
    cell.state = 2;
    return call('req_explore', { hex: cell.hex });
  };

  run.step = Number(cfg.appearTime[0]) - 1;
  let out = stepOnce();
  check(Number(run.step) === Number(cfg.appearTime[0]) && run.boss_infos.length === 1,
    'req_explore spawns the wave on its appearTime step');
  const spawned = out.find((s) => s.name === 'ntf_boss_info');
  check(!!spawned && spawned.msg.boss_infos.length === 1, 'ntf_boss_info announces the wave');

  out = stepOnce();
  const moved = out.find((s) => s.name === 'ntf_boss_info');
  check(!!moved && U.hexKey(moved.msg.boss_infos[0].hex) !== U.hexKey(spawned.msg.boss_infos[0].hex),
    'the next explore pushes the boss one cell closer (客户端据此广播 BossMoved)');
  check(U.dist({ q: moved.msg.boss_infos[0].hex.q, r: moved.msg.boss_infos[0].hex.r }, run.base_hex)
    === Number(cfg.distance[0]) - 1, 'the announced hex is one ring closer to the base');

  out = stepOnce();
  check(U.hexKey(run.boss_infos[0].hex) === U.hexKey(run.base_hex),
    'the following explore lands it on the base (客户端据此广播 BossArrived)');
  check(!out.some((s) => s.name === 'ntf_universe_info' && Number(s.msg.cur_hp) < 0),
    'no survival is lost on the arrival turn');

  const hp0 = run.cur_hp;
  out = stepOnce();
  const dmg = out.find((s) => s.name === 'ntf_universe_info' && Number(s.msg.cur_hp) < 0);
  check(run.cur_hp === hp0 - 1 && !!dmg && Number(dmg.msg.cur_hp) === -1,
    'a parked boss drains 1 survival per explore, announced via ntf_universe_info');

  // replay the frames as the client sees them: the reveal must precede ntf_boss_info
  const clientState = new Map(Object.values(run.main_pos).map((c) => [U.hexKey(c.hex), c.state]));
  let ordered = true;
  for (const s of out) {
    if (s.name === 'ntf_main_pos_state_change') {
      for (const ch of s.msg.main_pos_state_changes) clientState.set(U.hexKey(ch.hex), Number(ch.state));
    } else if (s.name === 'ntf_boss_info') {
      for (const b of s.msg.boss_infos) if ((clientState.get(U.hexKey(b.hex)) ?? 0) <= 1) ordered = false;
    }
  }
  check(ordered, 'every announced boss cell is already reachable when the client sees it');

  // an old save whose boss cell was never revealed gets the corridor revealed too
  const legacy = createPlayerDoc(9014);
  const oldRun = U.newUniverse(mapParams(), STORY_MAP);
  oldRun.step = Number(cfg.appearTime[0]);
  U.spawnDueBossWaves(oldRun);
  for (const c of Object.values(oldRun.main_pos)) c.state = 0;   // what老服务端 persisted
  legacy.universe = oldRun;
  check(migratePlayer(legacy) === true, 'migratePlayer repairs a legacy boss run');
  check(U.routeToBase(oldRun, oldRun.boss_infos[0].hex).every((c) => c.state > 1),
    'the loaded run\'s whole boss corridor becomes reachable');
  const snap = JSON.stringify(oldRun);
  migratePlayer(legacy);
  check(JSON.stringify(oldRun) === snap, 'boss-corridor migration is idempotent');
}

// ---------------- 新号走完教学链：不靠保险也能通关（避免新存档再踩坑） ----------------
// Regression target 6 — the tutorial rail. d_task_story[].unExplore == 1 makes the
// CLIENT refuse req_explore (QuestSystem:IsExploreBlocked → UI_Menu_C:1190), and the
// only three rows with that flag are the building trio:
//   100031201 部署1个建筑 / 100031203 晋升1个建筑 / 100031205 拆除1个建筑.
// So during those phases the player cannot farm blueprints, and because
// CardSelector needs 2 extra copies of the deployed blueprint (CardSelector_C:210)
// the chain must hand them out on rails:
//   100031003 探索星图 (3 步) → 踩到 10003 → 事件 11003 → 1 张 10015
//   100031201 部署 → 放下那张 10015
//   100031202 探索星图 (2 步) → 踩到 10007 → 事件 11007 → 3 张 10015
//   100031203 晋升 → 用掉 2 张
//   100031204 探索星图 (2 步)  → 100031205 拆除
// Everything here goes through the real handlers, so a broken card source shows up.
{
  const handle = require('../src/handlers/universe').handle;
  check(U.intArray(gd.query('d_task_story', 100031201).taskNumber).join(',') === '1'
    && U.intArray(gd.query('d_task_story', 100031202).taskNumber).join(',') === '2'
    && U.intArray(gd.query('d_task_story', 100031203).taskNumber).join(',') === '1',
    'the tutorial chain asks for 1 deploy / 2 explores / 1 upgrade');

  const locked = ['100031201', '100031203', '100031205'];
  const allLocked = Object.entries(gd.table('d_task_story'))
    .filter(([, r]) => Number(r.unExplore) === 1).map(([id]) => id).sort();
  check(allLocked.join(',') === locked.join(','),
    'only 部署/晋升/拆除 lock exploration (客户端 IsExploreBlocked 的触发集)');

  const doc = createPlayerDoc(9016);
  const sent = [];
  const session = { player: doc, send: (n, m, r) => sent.push({ name: n, msg: m, result: r }) };
  const call = (name, req) => { sent.length = 0; handle(name)(session, req || {}); return sent; };

  call('req_new_universe_specific', { specific_id: STORY_SPECIFIC });
  const run = doc.universe;

  // 事件与三选一都按「点第一个选项 / 选第一张」处理，模拟玩家走轨道
  const drain = () => {
    for (let guard = 0; guard < 40; guard++) {
      const ev = run.events[0];
      if (ev) { call('req_choose_event_option', { event_uuid: ev.event_uuid, index: 0 }); continue; }
      const sel = run.cards_for_select;
      if (!sel) break;
      call('req_choose_card', { select_uuid: sel.select_uuid, index: 0 });
    }
  };
  const exploreOne = (label) => {
    const cell = Object.values(run.main_pos).find((c) => c.state === 2);
    check(!!cell, `${label}: an explorable cell exists (step ${run.step})`);
    if (!cell) return null;
    const out = call('req_explore', { hex: cell.hex });
    check(out.some((s) => s.name === 'res_explore' && s.result === undefined), `${label}: req_explore ok`);
    drain();
    return cell;
  };

  // —— 100031003「探索星图」3 步 ——
  const visited = [];
  for (let i = 0; i < 3; i++) visited.push(exploreOne(`探索星图 #${i + 1}`));
  check(visited.map((c) => c && c.main_pos_id).join(',') === '10001,10002,10003',
    'the rail forces 10001 → 10002 → 10003 (只有一条路)');
  check(run.cards.join(',') === '10015',
    '事件 11003 「获得一张卡牌」 hands over the single blueprint 10015');

  // —— 100031201「部署1个建筑」——
  const slot = Object.values(run.main_pos).find((c) => c.attach && c.attach.main_pos_card_pos_info);
  const slotCard = () => U.posAt(run, slot.hex).attach.main_pos_card_pos_info;
  check(call('req_place_card', { hex: slot.hex, attach_index: 0, index_in_hand: 0 })[0].result === undefined,
    '部署1个建筑: req_place_card ok');
  check(slotCard().card_id === 10015, 'the deployed building is 10015');

  // —— 100031202「探索星图」2 步 ——
  exploreOne('探索星图 #4');
  exploreOne('探索星图 #5');
  check(run.cards.join(',') === '10015,10015,10015',
    '事件 11007 「获得三张卡牌」 hands over three more copies (三次 [6060])');
  check(run.repaired_cards === undefined || run.repaired_cards.length === 0,
    'the rail needs no safety net (repaired_cards stayed empty)');

  // —— 100031203「晋升1个建筑」——
  const pair = [];
  run.cards.forEach((c, k) => { if (c === slotCard().card_id) pair.push(k); });
  check(call('req_upgrade_card', { hex: slot.hex, attach_index: 0, index_in_hand: pair.slice(0, 2) })[0].result === undefined,
    '晋升1个建筑: req_upgrade_card ok (the button the screenshot showed greyed out)');
  check(slotCard().card_id === 10115 && run.cards.join(',') === '10015',
    'the building becomes 10115 and one spare blueprint is left');

  // —— 100031204 探索 ×2 → 100031205「拆除1个建筑」——
  exploreOne('探索星图 #6');
  exploreOne('探索星图 #7');
  check(call('req_demolition_card', { hex: slot.hex, attach_index: 0 })[0].result === undefined,
    '拆除1个建筑: req_demolition_card ok');
  check(run.repaired_cards === undefined || run.repaired_cards.length === 0,
    'no safety net was involved anywhere in the whole chain');
}

// ---------------- 教学保险：已经卡死的老存档能被救回来 ----------------
// The client will not even send req_explore while a lock mission is unfinished, so a
// save whose deployed blueprint has no spare copies in hand has NO way out by itself.
// repairUnupgradableBuilding tops the hand up (only up to the 2 the upgrade needs)
// and records the card in `universe.repaired_cards` so it never repeats.
{
  const scene = (over = {}) => {
    const doc = createPlayerDoc(9017 + Math.floor(Math.random() * 500));
    const run = U.newUniverse(mapParams(), STORY_MAP);
    const slot = Object.values(run.main_pos).find((c) => c.attach && c.attach.main_pos_card_pos_info);
    slot.attach.main_pos_card_pos_info.card_id = 30121;   // d_srpg_card_base 30121 → upgradeCard 40121
    run.cards = over.cards ? over.cards.slice() : [30617, 30612];
    if (over.repaired) run.repaired_cards = over.repaired.slice();
    doc.universe = run;
    doc.plot = {
      plot_mission_infos: (over.missions || [100031203]).map(
        (id) => ({ mission_id: id, mission_record_args: [], completed: false }),
      ),
    };
    return { doc, run, slot };
  };

  const locked = scene();
  check(U.exploreLockedByStory(locked.doc) === true,
    'the story lock is detected from the unfinished mission list');
  check(JSON.stringify(U.unupgradableBuilding(locked.run)) === '{"card_id":30121,"missing":2}',
    'the deployed 30121 is reported as 2 copies short');

  const granted = U.repairUnupgradableBuilding(locked.doc);
  check(granted.join(',') === '30121,30121', 'the safety net grants exactly the 2 missing copies');
  check(locked.run.cards.join(',') === '30617,30612,30121,30121', 'they land in the hand');
  check(locked.run.repaired_cards.join(',') === '30121', 'the card is recorded as repaired');
  check(U.repairUnupgradableBuilding(locked.doc).length === 0, 'the safety net is idempotent');

  // …and the rescue actually unblocks the mission through the real handler
  const handle = require('../src/handlers/universe').handle;
  const sent = [];
  const session = { player: locked.doc, send: (n, m, r) => sent.push({ name: n, msg: m, result: r }) };
  const pair = locked.run.cards
    .map((c, k) => (c === 30121 ? k : -1)).filter((k) => k >= 0);
  sent.length = 0;
  handle('req_upgrade_card')(session, { hex: locked.slot.hex, attach_index: 0, index_in_hand: pair.slice(0, 2) });
  check(sent[0].result === undefined,
    'after the top-up the upgrade answers OK (主线 100031203 可以继续)');

  // 不该触发的情形
  const healthy = scene({ cards: [30121, 30121] });
  check(U.repairUnupgradableBuilding(healthy.doc).length === 0,
    'a hand that already holds the copies gets nothing extra');

  const unlocked = scene({ missions: [100031202] });   // 探索星图 = 未上锁
  check(U.exploreLockedByStory(unlocked.doc) === false && U.repairUnupgradableBuilding(unlocked.doc).length === 0,
    'while exploration is still allowed the player can farm, so nothing is handed out');

  const topTier = scene();
  Object.values(topTier.run.main_pos).forEach((c) => {
    if (c.attach && c.attach.main_pos_card_pos_info) c.attach.main_pos_card_pos_info.card_id = 40095;
  });
  check(U.unupgradableBuilding(topTier.run) === null,
    'a top-tier blueprint (upgradeCard === itself, e.g. 40095) is never "repaired"');

  const fullHand = scene({ cards: new Array(U.HAND_LEN_MAX).fill(30617) });
  check(U.repairUnupgradableBuilding(fullHand.doc).length === 0,
    'a full hand is left alone (the GM add_card command is the manual way out)');

  const idle = scene();
  idle.run.active = false;
  check(U.repairUnupgradableBuilding(idle.doc).length === 0, 'a finished run is never touched');

  // GM：add_card 把蓝图塞进当前远航的手牌（蓝图不在背包里，add_item 救不了）
  const gm = require('../src/handlers/social').handle;
  const gmDoc = createPlayerDoc(9500);
  const gmSent = [];
  const gmSession = { player: gmDoc, send: (n, m, r) => gmSent.push({ name: n, msg: m, result: r }) };
  handle('req_new_universe_specific')(gmSession, { specific_id: STORY_SPECIFIC });
  gmSent.length = 0;
  gm('req_gm_cmd')(gmSession, { cmd: 'add_card 10015 3' });
  check(gmDoc.universe.cards.join(',') === '10015,10015,10015',
    'GM 「add_card <cardId> <count>」 seeds the blueprint hand');
  check(gmSent.some((s) => s.name === 'ntf_add_card' && s.msg.card_ids.length === 3),
    'and pushes ntf_add_card so the client sees them immediately');
  gmSent.length = 0;
  gm('req_gm_cmd')(gmSession, { cmd: 'add_card 999999 1' });
  check(gmDoc.universe.cards.length === 3, 'an unknown card id is ignored');
}

fs.rmSync(tmpDataDir, { recursive: true, force: true });
console.log(failures ? `\n${failures} check(s) FAILED` : '\nall universe checks passed');
process.exit(failures ? 1 : 0);
