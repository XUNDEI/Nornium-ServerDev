// In-process regression checks for the furnace (炼金合成/分解/锻造) handlers,
// starter roster and save migrations. No server needed: builds a player doc and
// drives the handlers directly, asserting on res result codes and bag deltas.
// Must run before requiring the server modules: store.js reads GHS_DATA_DIR at
// load time so saves from these checks stay out of the real data/ directory.
const os = require('os');
const fs = require('fs');
const path = require('path');
const tmpDataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ghs-furnace-'));
process.env.GHS_DATA_DIR = tmpDataDir;

const { createPlayerDoc, initialCharacterIds } = require('../src/game/player_new');
const furnaceH = require('../src/handlers/furnace');
const { migratePlayer } = require('../src/game/migrate');
const items = require('../src/game/items');
const gd = require('../src/gamedata');

let failures = 0;
function check(cond, msg) {
  console.log(cond ? `  PASS ${msg}` : `  FAIL ${msg}`);
  if (!cond) failures += 1;
}

function makeSession() {
  const player = createPlayerDoc(9001);
  const sent = [];
  return { player, sent, send: (name, msg, result) => sent.push({ name, msg, result }) };
}
const count = (s, id) => items.bagCount(s.player, id);
const last = (s, name) => [...s.sent].reverse().find((x) => x.name === name);

// ---------------- roster / blueprints ----------------
const ids = initialCharacterIds();
check(ids.length === 10, `starter roster has 10 characters (got ${ids.length})`);
check(!ids.includes(24002) && !ids.includes(24001), 'dev placeholder characters 24001/24002 excluded');

{
  const s = makeSession();
  check(Array.isArray(s.player.player.blueprint_ids) && s.player.player.blueprint_ids.length > 0,
    `new player seeded with synthesis blueprints (${s.player.player.blueprint_ids.length})`);
}

// ---------------- 炼金合成 ----------------
{
  const s = makeSession();
  const before = count(s, 1202001);
  furnaceH.reqItemSynthetic(s, { blueprint_id: 3001, count: 2 }); // [1202001 x3] -> 1202002
  check(last(s, 'res_item_synthetic')?.result === undefined || last(s, 'res_item_synthetic')?.result === 0,
    'synthetic material recipe result OK');
  check(count(s, 1202001) === before - 6, `synthetic consumed 6x 1202001 (${before} -> ${count(s, 1202001)})`);
  check(count(s, 1202002) === 502, `synthetic granted 2x 1202002 (got ${count(s, 1202002)})`);
  check(last(s, 'ntf_item_info')?.msg?.changed_item_infos?.length >= 2, 'synthetic emitted ntf_item_info deltas');
}
{
  const s = makeSession();
  items.grantItems(s.player, [{ item_id: 9005, count: 10 }]);
  furnaceH.reqItemSynthetic(s, { blueprint_id: 2001, count: 1 }); // [9005x10, 1202031x3] -> weapon 1011100
  const weapon = s.player.bag.items.find((i) => i.item_id === 1011100 && i.weapon_info);
  check(!!weapon, 'synthetic weapon recipe produced an instance with weapon_info');
}
{
  const s = makeSession();
  furnaceH.reqItemSynthetic(s, { blueprint_id: 999999, count: 1 });
  check(last(s, 'res_item_synthetic')?.result === 1, 'unknown blueprint -> NO_BLUEPRINT(1)');
  furnaceH.reqItemSynthetic(s, { blueprint_id: 3001, count: 0 });
  check(last(s, 'res_item_synthetic')?.result === 3, 'count 0 -> INVALID_COUNT(3)');
}

// ---------------- 分解 ----------------
{
  const s = makeSession();
  const weapon = items.makeItem(s.player, 3011100, 1); // rarity 1 weapon
  s.player.bag.items.push(weapon);
  furnaceH.reqItemDecompose(s, { item_uuids: [weapon.item_uuid] });
  check(last(s, 'res_item_decompose')?.result === undefined || last(s, 'res_item_decompose')?.result === 0,
    'decompose weapon result OK');
  check(!s.player.bag.items.find((i) => Number(i.item_uuid) === Number(weapon.item_uuid)),
    'decomposed weapon removed from bag');
  const ntf = last(s, 'ntf_item_info')?.msg?.changed_item_infos || [];
  check(ntf.some((c) => c.item_id === 1204001 && Number(c.count) > 0), 'decompose granted rolled weapon-exp reward');
}
{
  const s = makeSession();
  furnaceH.reqItemDecompose(s, { item_uuids: [] });
  check(last(s, 'res_item_decompose')?.result === 2, 'empty list -> INVALID_COUNT(2)');
  furnaceH.reqItemDecompose(s, { item_uuids: [123456789] });
  check(last(s, 'res_item_decompose')?.result === 1, 'unknown uuid -> INVALID_ITEM(1)');
  const mat = s.player.bag.items.find((i) => i.item_id === 1202001);
  furnaceH.reqItemDecompose(s, { item_uuids: [mat.item_uuid] });
  check(last(s, 'res_item_decompose')?.result === 1, 'non-decomposable material -> INVALID_ITEM(1)');
}

// ---------------- 锻造 ----------------
{
  const s = makeSession();
  items.grantItems(s.player, [{ item_id: 1202024, count: 6 }, { item_id: 9001, count: 50000 }]);
  furnaceH.reqArmForge(s, { blueprint_id: 1001, count: 1 }); // [1202024x6, 9001x50000] -> 1101001
  const equip = s.player.bag.items.find((i) => i.item_id === 1101001 && i.arm_info);
  check(!!equip, 'forge produced the equip instance');
  furnaceH.reqArmForge(s, { blueprint_id: 999999, count: 1 });
  check(last(s, 'res_arm_forge')?.result === 1, 'unknown forge blueprint -> NO_BLUEPRINT(1)');
}

// ---------------- migration ----------------
{
  const doc = createPlayerDoc(9002);
  // simulate a legacy save: ghost character, uuid-0 stacks, no blueprints
  doc.characters.push({ character_id: 24002, exp: 0, break_times: 0, weapon_info: items.makeItem(doc, 4010100, 1), arm_infos: [] });
  const stack = doc.bag.items.find((i) => i.item_id === 1203001);
  stack.item_uuid = 0;
  doc.player.blueprint_ids = [];
  const changed = migratePlayer(doc);
  check(changed === true, 'migration reports a change for a legacy save');
  check(!doc.characters.some((c) => c.character_id === 24002), 'migration drops the ghost character 24002');
  check(doc.bag.items.some((i) => i.item_id === 4010100), 'ghost character gear returned to the bag');
  check(!doc.bag.items.some((i) => !i.weapon_info && !i.arm_info && !Number(i.item_uuid)), 'stacks got unique uuids');
  check(doc.player.blueprint_ids.length > 0, 'migration seeds synthesis blueprints');
  check(migratePlayer(doc) === false, 'migration is idempotent');
  const gachaChar = { character_id: 10901, exp: 0, break_times: 0, weapon_info: null, arm_infos: [] };
  doc.characters.push(gachaChar);
  migratePlayer(doc);
  check(doc.characters.includes(gachaChar), 'migration keeps gacha-owned characters (firstWeapon 0 but localized)');
}

fs.rmSync(tmpDataDir, { recursive: true, force: true });
console.log(failures === 0 ? '\nFURNACE CHECKS PASSED' : `\n${failures} FURNACE CHECKS FAILED`);
process.exit(failures === 0 ? 0 : 1);
