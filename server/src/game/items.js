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

// 武器类型 = d_bag_item_weapon.subType（1..7，见客户端 UIUtils.ItemWeaponType：
// 1 巨刃 / 2 长剑 / 3 佩刀 / 4 枪械 / 5 礼器 / 6 宝轮 / 7 浮塔）。
function weaponType(itemId) {
  const cfg = gd.query('d_bag_item_weapon', itemId);
  return cfg ? (Number(cfg.subType) || 0) : 0;
}

// 角色能用的武器类型 = d_character.profession（同一个 1..7 枚举，不是"职业"）。
// 依据（客户端）：
//  - UI_Panel_Detail_C.lua:70 用它拼武器类型图标 weapons_%s_png；
//  - UI_Team_List_C.lua:196 用它给编队做武器类型筛选；
//  - d_character.firstWeapon 全部是同类型的武器（10 个初始角色实测一致）。
// 官方服务端同样会校验：ResCharacterEquipWeapon.ResultType 里有 INVALID_ITEM = 3。
function characterWeaponType(charId) {
  const cfg = gd.query('d_character', charId);
  return cfg ? (Number(cfg.profession) || 0) : 0;
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

// 老存档里 item_uuid 重复（同一件 uuid 被分给了多件道具），而服务端所有按 uuid
// 定位的入口都用 `Array.prototype.find`（取数组里**第一个**命中），于是「客户端点的是
// A，服务端操作的是 B」。典型症状：换武器换上了另一件（甚至另一武器类型的）武器、
// 升级材料加错、精炼吃掉别的道具。见 REVERSE_ENGINEERING 坑 37。
//
// 修法：按稳定顺序（先背包数组顺序、再角色装备）遍历全部道具实例，每个 uuid 的
// **第一次出现保持原样**（那正是历史上所有既有 `find` 会命中的那件，改它会改变
// 已有语义），之后的重复项/零 uuid 项一律重新分配新 uuid。
// 幂等：没有重复时不做任何改动、返回 0。
function dedupeItemUuids(player) {
  const seen = new Set();
  const ordered = [];
  for (const it of player.bag.items) ordered.push(it);
  for (const c of player.characters || []) {
    if (c.weapon_info) ordered.push(c.weapon_info);
    for (const a of c.arm_infos || []) ordered.push(a);
  }
  let renamed = 0;
  for (const it of ordered) {
    const uuid = Number(it.item_uuid) || 0;
    if (uuid > 0 && !seen.has(uuid)) {
      seen.add(uuid);
      continue;
    }
    let fresh = nextItemUuid(player);
    while (seen.has(fresh)) fresh = nextItemUuid(player);
    it.item_uuid = fresh;
    seen.add(fresh);
    renamed += 1;
  }
  return renamed;
}

module.exports = {
  CURRENCY, itemKind, itemConfig, makeItem, nextItemUuid, bagCount, findBagEntry, findStackEntry,
  grantItems, consumeItems, normalizeBag, dedupeItemUuids, weaponType, characterWeaponType,
};
