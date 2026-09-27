// 军械库发放：给玩家发「高稀有度武器」。
//
// 口径变更（2026-09-25 与服主确认，取代早期版本）：
// 早期版本按「每个可玩角色发一把与其武器类型（d_character.profession ==
// d_bag_item_weapon.subType）匹配的最高稀有度武器，并列取 id 大者」发放。两个问题：
//
//   ① **数据表里根本没有「角色 → 专属武器」这个关联**。d_character 里唯一的官方字段
//      是 firstWeapon，那只是出生自带的 1★ 白板（人人已有）；6★ 专武（如莎乐美的
//      「梦魇之灯」4072601）在 d_character / d_weapon / d_skill / 抽卡 UP 排期里都
//      没有可反推的字段能关联到角色。所以「每人一把同类型最高稀有度」只是一个猜测。
//   ② 这个猜测会踩到**未实装武器**：巨刃（subType 1）里 id 最大的 7★ 是
//      `1081601 颂歌`，而它没有模型/图标/展示图、也没有 d_skill 行 —— 发下去之后
//      客户端的武器详情面板会因为 GetWeaponSkillDesc 抛错而整体停摆
//      （截图里的「文本块…」「30#星芒名字」）。详见 game/weapon_data.js 的注释。
//
// 新口径：**不再猜「谁的专武」，改为把「已实装的高稀有度武器」每种各发一把**
// （默认 rarity >= 6，即 6★ 与 7★）。玩家自己在游戏里按武器类型装即可。
// 未实装武器一律不发（isReleasedWeapon 过滤）。
const gd = require('../gamedata');
const items = require('./items');
const playerNew = require('./player_new');
const weaponData = require('./weapon_data');

// 默认发放门槛：6★ 与 7★。
const DEFAULT_MIN_RARITY = 6;

// 该角色的「推荐武器」：同类型、已实装、稀有度最高（并列取 id 大者）。
// 只用于编辑器的展示与「发放推荐武器」单发按钮，不再作为批量发放的依据。
function bestWeaponForCharacter(charId) {
  const want = items.characterWeaponType(charId);
  if (!want) return 0;
  let best = null;
  for (const [, w] of gd.rows('d_bag_item_weapon')) {
    if (Number(w.subType) !== want) continue;
    if (!weaponData.isReleasedWeapon(w.id)) continue;
    if (!best
      || Number(w.rarity) > Number(best.rarity)
      || (Number(w.rarity) === Number(best.rarity) && Number(w.id) > Number(best.id))) {
      best = w;
    }
  }
  return best ? Number(best.id) : 0;
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

// 兼容旧调用点的别名（行为已按新口径）。新代码请直接用 grantHighRarityWeapons。
const grantCharacterWeapons = grantHighRarityWeapons;

module.exports = {
  DEFAULT_MIN_RARITY,
  bestWeaponForCharacter,
  highRarityWeaponIds,
  grantHighRarityWeapons,
  grantCharacterWeapons,
  ownedCount,
  isReleasedWeapon: weaponData.isReleasedWeapon,
  isUnreleasedWeapon: weaponData.isUnreleasedWeapon,
  UNRELEASED_WEAPON_IDS: weaponData.UNRELEASED_WEAPON_IDS,
};
