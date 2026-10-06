// 军械库发放：给玩家发「高稀有度武器」与「角色专武」。
//
// 口径（2026-10-03 修订，取代 2026-09-25 的「不猜专武」版本）：
// 「角色 → 专属武器」的官方关联**找到了**（此前版本断言数据表里没有，是错的）——
// 它藏在两处不起眼的地方：d_word_cn 的武器描述占位文本（如「信风专武描述」「理事卿专武
// 描述」，id = 54 + 武器id）和 d_character_trial 的试用配枪 firstWeapon。四条证据交叉
// 验证出的完整映射见 game/weapon_data.js 的 CHARACTER_EXCLUSIVE_WEAPONS。
//
// 因此发放分两档：
//   ① **专武**（本文件 exclusiveWeaponForCharacter / grantExclusiveWeapons）：
//      每名可玩角色一把 7★ 专武（6★/7★ 数值相同，7★ 是最终形态；试用表里骆十四娘
//      配的就是 7★ 7070611）。编辑器「发放专武 / 发放全部专武」与控制台 allexclusive 走这里。
//   ② **全部高稀有度武器**（grantHighRarityWeapons）：已实装的 6★/7★ 每种各一把
//      （默认 rarity >= 6，共 36 把），泛用武器也包含在内。未实装武器一律不发
//      （isReleasedWeapon 过滤）。
const gd = require('../gamedata');
const items = require('./items');
const playerNew = require('./player_new');
const weaponData = require('./weapon_data');

// 默认发放门槛：6★ 与 7★。
const DEFAULT_MIN_RARITY = 6;

// 该角色的专属武器：返回 7★（最终形态）id。
// 映射外角色（含 profession=0 的抽卡角色）返回 0；映射值万一失去实装资格也返回 0，
// 不再像旧版那样退回「同类型最高稀有度」去猜。
function exclusiveWeaponForCharacter(charId) {
  const entry = weaponData.CHARACTER_EXCLUSIVE_WEAPONS[Number(charId)];
  if (!entry) return 0;
  return weaponData.isReleasedWeapon(entry.seven) ? Number(entry.seven) : 0;
}

// 该角色专武的 6★ 基础形态 id（编辑器展示用；同样过未实装守卫，异常时返回 0）。
function exclusiveWeaponBaseForCharacter(charId) {
  const entry = weaponData.CHARACTER_EXCLUSIVE_WEAPONS[Number(charId)];
  if (!entry) return 0;
  return weaponData.isReleasedWeapon(entry.base) ? Number(entry.base) : 0;
}

// 全部专武（7★）清单，升序。
function exclusiveWeaponIds() {
  const out = [];
  for (const entry of Object.values(weaponData.CHARACTER_EXCLUSIVE_WEAPONS)) {
    if (weaponData.isReleasedWeapon(entry.seven)) out.push(Number(entry.seven));
  }
  return out.sort((a, b) => a - b);
}

// 发放清单：已实装、稀有度 >= minRarity 的全部武器各一把。
function highRarityWeaponIds(minRarity = DEFAULT_MIN_RARITY) {
  return weaponData.releasedWeaponIdsAtLeast(minRarity);
}

function ownedCount(player, itemId) {
  let n = player.bag.items.filter((it) => it.item_id === itemId).length;
  for (const c of player.characters || []) {
    if (c.weapon_info && c.weapon_info.item_id === itemId) n += 1;
  }
  return n;
}

// 每种高稀有度（已实装）武器各发一把，入包不自动装备。
// 返回 { granted, deltas }：granted 是发放清单（{item_id, rarity}），
// deltas 是合并好的 ntf_item_info 载荷（在线会话推送用）。
// opts.minRarity 默认 6；opts.skipOwned = true 时，背包/角色身上已有该 id 的武器就跳过。
function grantHighRarityWeapons(player, opts = {}) {
  const minRarity = Number(opts.minRarity) || DEFAULT_MIN_RARITY;
  const granted = [];
  const deltas = [];
  for (const weaponId of highRarityWeaponIds(minRarity)) {
    if (opts.skipOwned && ownedCount(player, weaponId) > 0) continue;
    const row = gd.query('d_bag_item_weapon', weaponId) || {};
    deltas.push(items.grantItems(player, [{ item_id: weaponId, count: 1 }]));
    granted.push({ item_id: weaponId, rarity: Number(row.rarity) || 0 });
  }
  return { granted, deltas };
}

// 每名可玩角色的 7★ 专武各发一把，入包不自动装备。返回值结构同 grantHighRarityWeapons。
// opts.skipOwned = true 时跳过背包/角色身上已有的。
function grantExclusiveWeapons(player, opts = {}) {
  const granted = [];
  const deltas = [];
  for (const weaponId of exclusiveWeaponIds()) {
    if (opts.skipOwned && ownedCount(player, weaponId) > 0) continue;
    const row = gd.query('d_bag_item_weapon', weaponId) || {};
    deltas.push(items.grantItems(player, [{ item_id: weaponId, count: 1 }]));
    granted.push({ item_id: weaponId, rarity: Number(row.rarity) || 0 });
  }
  return { granted, deltas };
}

// 兼容旧调用点的别名（行为已按新口径）。新代码请直接用 grantHighRarityWeapons。
const grantCharacterWeapons = grantHighRarityWeapons;

module.exports = {
  DEFAULT_MIN_RARITY,
  exclusiveWeaponForCharacter,
  exclusiveWeaponBaseForCharacter,
  exclusiveWeaponIds,
  highRarityWeaponIds,
  grantHighRarityWeapons,
  grantExclusiveWeapons,
  grantCharacterWeapons,
  ownedCount,
  isReleasedWeapon: weaponData.isReleasedWeapon,
  isUnreleasedWeapon: weaponData.isUnreleasedWeapon,
  UNRELEASED_WEAPON_IDS: weaponData.UNRELEASED_WEAPON_IDS,
  CHARACTER_EXCLUSIVE_WEAPONS: weaponData.CHARACTER_EXCLUSIVE_WEAPONS,
};
