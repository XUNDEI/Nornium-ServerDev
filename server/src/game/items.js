// Bag/item domain helpers. All mutations go through grant/revoke which return
// ChangedItemInfo deltas for ntf_item_info; the player doc stays the authority.
const gd = require('../gamedata');

const CURRENCY = {
  GOLD: 9001,        // 金星贝
  DIAMOND: 9002,     // 诺伦炬
  MEMBRANE: 9003,    // 败者翼膜
  EXP: 9004,         // 玩家经验（等级 = f(9004数量)）
  GACHA_LOW: 9005,   // 抽卡银币
  GACHA_HIGH: 9006,  // 抽卡金币
  LENS: 9007,        // 诺伦透镜
  FURNITURE_COIN: 9008,
};

function itemKind(itemId) {
  const id = String(itemId);
  if (gd.table('d_bag_item_weapon')[id]) return 'weapon';
  if (gd.table('d_bag_item_equip')[id]) return 'arm';
  if (gd.table('d_bag_item_furniture')[id]) return 'furniture';
  return 'stack';
}

// Config row for any item id: weapons/equips/furniture live in their own tables
// (each row still carries itemType/rarity/subParam), materials and currency in
// d_bag_item.
function itemConfig(itemId) {
  return gd.query('d_bag_item_weapon', itemId)
    || gd.query('d_bag_item_equip', itemId)
    || gd.query('d_bag_item_furniture', itemId)
    || gd.query('d_bag_item', itemId);
}

// Every bag entry gets a unique non-zero uuid, stackables included. The client
// selects level-up/refine materials as StuffItemInfo{item_uuid, count} with no
// item_id, so a uuid must resolve to exactly one entry — sharing uuid 0 across
// all stacks made the server pick whichever stack came first in the array.
function maxItemUuid(player) {
  let max = 0;
  const consider = (it) => {
    const u = Number(it && it.item_uuid) || 0;
    if (u > max) max = u;
  };
  for (const it of player.bag.items) consider(it);
  for (const c of player.characters || []) {
    if (c.weapon_info) consider(c.weapon_info);
    for (const a of c.arm_infos || []) consider(a);
  }
  return max;
}

function nextItemUuid(player) {
  let seq = Math.max(Number(player.bag.next_uuid) || 0, maxItemUuid(player) + 1, 1000000);
  player.bag.next_uuid = seq + 1;
  return seq;
}

function makeItem(player, itemId, count, extra = {}) {
  const entry = { item_id: itemId, count, item_uuid: nextItemUuid(player) };
  const kind = itemKind(itemId);
  if (kind === 'weapon') {
    entry.weapon_info = { exp: 0, break_times: 0, refine_level: 0, locked: false };
  } else if (kind === 'arm') {
    entry.arm_info = { exp: 0, break_times: 0, arm_random_attribute_infos: [], arm_rune_infos: [], locked: false };
  }
  Object.assign(entry, extra);
  return entry;
}

// Stackables merge into the single entry for that item_id (weapons/arms are
// individual instances and never merge).
function findStackEntry(player, itemId) {
  return player.bag.items.find(
    (it) => it.item_id === itemId && !it.weapon_info && !it.arm_info,
  ) ?? null;
}

function bagCount(player, itemId) {
  return player.bag.items
    .filter((it) => it.item_id === itemId)
    .reduce((s, it) => s + it.count, 0);
}

function findBagEntry(player, itemId, uuid = 0) {
  return player.bag.items.find((it) => it.item_id === itemId && Number(it.item_uuid) === Number(uuid)) ?? null;
}

// grants: [{item_id, count}] — returns ntf_item_info payload (deltas).
// Stackables merge into their existing entry; weapons/arms are new instances.
function grantItems(player, grants) {
  const changed = [];
  for (const g of grants) {
    if (!g.count) continue;
    const kind = itemKind(g.item_id);
    if (kind === 'stack') {
      const entry = findStackEntry(player, g.item_id);
      if (entry) {
        entry.count += g.count;
        changed.push({ item_id: g.item_id, count: g.count, item_uuid: String(entry.item_uuid) });
        if (entry.count <= 0) player.bag.items.splice(player.bag.items.indexOf(entry), 1);
      } else if (g.count > 0) {
        const ne = makeItem(player, g.item_id, g.count);
        player.bag.items.push(ne);
        changed.push({ item_id: g.item_id, count: g.count, item_uuid: String(ne.item_uuid) });
      } else {
        // removing a stack the server doesn't track — nothing to sync
        continue;
      }
    } else {
      if (g.count <= 0) {
        const entry = findBagEntry(player, g.item_id, g.item_uuid);
        if (entry) player.bag.items.splice(player.bag.items.indexOf(entry), 1);
        changed.push({ item_id: g.item_id, count: g.count, item_uuid: String(g.item_uuid) });
        continue;
      }
      const ne = makeItem(player, g.item_id, g.count);
      player.bag.items.push(ne);
      const c = { item_id: g.item_id, count: g.count, item_uuid: String(ne.item_uuid) };
      if (ne.weapon_info) c.weapon_info = ne.weapon_info;
      if (ne.arm_info) c.arm_info = ne.arm_info;
      changed.push(c);
    }
  }
  return { changed_item_infos: changed };
}

// Check + consume. Returns ntf payload or null when insufficient.
function consumeItems(player, costs) {
  for (const c of costs) {
    if (bagCount(player, c.item_id) < c.count) return null;
  }
  const grants = costs.map((c) => ({ item_id: c.item_id, count: -c.count }));
  return grantItems(player, grants);
}

// Migration for saves written before stackables carried unique uuids: give every
// stack entry still at uuid 0 a fresh one. Idempotent; returns true if changed.
function normalizeBag(player) {
  let max = maxItemUuid(player);
  let changed = false;
  for (const it of player.bag.items) {
    if (!it.weapon_info && !it.arm_info && !Number(it.item_uuid)) {
      it.item_uuid = ++max;
      changed = true;
    }
  }
  const next = Math.max(Number(player.bag.next_uuid) || 0, max + 1, 1000000);
  if (next !== Number(player.bag.next_uuid)) {
    player.bag.next_uuid = next;
    changed = true;
  }
  return changed;
}

module.exports = {
  CURRENCY, itemKind, itemConfig, makeItem, nextItemUuid, bagCount, findBagEntry, findStackEntry,
  grantItems, consumeItems, normalizeBag,
};
