// Character & bag operations available in the main city (M1+).
const gd = require('../gamedata');
const items = require('../game/items');
const talent = require('../game/talent');
const log = require('../logger');
const { savePlayer, requirePlayer } = require('./sync');

function findChar(session, charId) {
  return session.player.characters.find((c) => c.character_id === Number(charId)) ?? null;
}

function ntfCharacter(session, char) {
  session.send('ntf_character_info', { changed_character_infos: [char] });
}

// 每份经验道具提供的经验值：d_bag_item.subParam[0]（如 1203001=1000, 1203003=16000）
function expPerItem(itemId) {
  const cfg = gd.query('d_bag_item', itemId);
  const sp = cfg && Array.isArray(cfg.subParam) ? Number(cfg.subParam[0]) : 0;
  return sp > 0 ? sp : 100;
}

function reqCharacterLevelUp(session, req) {
  if (!requirePlayer(session)) return;
  const char = findChar(session, req.character_id);
  if (!char) return session.send('res_character_level_up', {}, 1);
  // req.item_infos are StuffItemInfo {item_uuid, count} chosen in the UI.
  // Consume them from the bag; each unit gives the exp configured in
  // d_bag_item.subParam[0] (client shows its own cached estimate, we publish
  // the authoritative exp via ntf_character_info).
  const stuff = (req.item_infos || []).map((s) => ({
    uuid: Number(s.item_uuid ?? 0),
    count: Number(s.count ?? 0),
  })).filter((s) => s.count > 0);
  let gained = 0;
  for (const s of stuff) {
    const entry = session.player.bag.items.find((it) => Number(it.item_uuid) === s.uuid);
    if (!entry || entry.count < s.count) {
      return session.send('res_character_level_up', {}, 5); // RES_NOT_ENOUGH
    }
  }
  const consumed = [];
  for (const s of stuff) {
    const entry = session.player.bag.items.find((it) => Number(it.item_uuid) === s.uuid);
    gained += s.count * expPerItem(entry.item_id);
    entry.count -= s.count;
    consumed.push({ item_id: entry.item_id, count: -s.count, item_uuid: String(s.uuid) });
    if (entry.count <= 0) session.player.bag.items.splice(session.player.bag.items.indexOf(entry), 1);
  }
  char.exp += gained;
  session.send('res_character_level_up', {});
  if (consumed.length) session.send('ntf_item_info', { changed_item_infos: consumed });
  ntfCharacter(session, char);
  savePlayer(session);
}

function reqCharacterLevelBreak(session, req) {
  if (!requirePlayer(session)) return;
  const char = findChar(session, req.character_id);
  if (!char) return session.send('res_character_level_break', {}, 1);
  const cfg = gd.query('d_role_levelbreak', null);
  void cfg;
  // materials from d_role_levelbreak[roleId+break_times].material
  const lb = gd.query('d_role_levelbreak', `${char.character_id}`) ||
    gd.rows('d_role_levelbreak').map(([, r]) => r)
      .find((r) => r.roleId === char.character_id && r.levelbreak === char.break_times);
  if (!lb) return session.send('res_character_level_break', {}, 2); // MAX_LEVEL_BREAK
  const mat = lb.material || [];
  const costs = [];
  for (let i = 0; i + 1 < mat.length; i += 2) costs.push({ item_id: mat[i], count: mat[i + 1] });
  const ntf = items.consumeItems(session.player, costs);
  if (!ntf) return session.send('res_character_level_break', {}, 3); // STUFF_NOT_ENOUGH
  char.break_times += 1;
  session.send('res_character_level_break', {});
  session.send('ntf_item_info', ntf);
  ntfCharacter(session, char);
  savePlayer(session);
}

function reqCharacterSkillLevelUp(session, req) {
  if (!requirePlayer(session)) return;
  const char = findChar(session, req.character_id);
  if (!char) return session.send('res_character_skill_level_up', {}, 1);
  let skill = char.skill_infos.find((s) => s.skill_id === Number(req.skill_id));
  if (!skill) {
    skill = { skill_id: Number(req.skill_id), skill_level: 1 };
    char.skill_infos.push(skill);
  }
  const costs = (req.item_infos || [])
    .map((s) => ({ item_id: 9001, count: Number(s.count ?? 0) }))
    .filter((c) => c.count > 0);
  const ntf = items.consumeItems(session.player, costs);
  if (!ntf) return session.send('res_character_skill_level_up', {}, 6);
  skill.skill_level += 1;
  session.send('res_character_skill_level_up', {});
  session.send('ntf_item_info', ntf);
  ntfCharacter(session, char);
  savePlayer(session);
}

// 点亮星位（客户端 UI 上叫「激活」，角色页的「星位」页签）。
//
// 这是过去**完全缺失**的处理器：请求体只有 character_id + talent_id，材料由客户端
// 本地扣（见 game/talent.js 头部与坑 40）。缺失时 dispatcher 的兜底分支会回一个
// **空的 res_character_unlock_talent**（result 默认 0 = OK），于是客户端在本地把星位
// 点亮、材料也扣了，服务端却什么都没记 —— 重登/重启后星位全没（玩家的「星位升级不保存」）。
// 现在按数据表回算：归属校验 → 重复 → 前置孔位 → openNeed 条件 → 扣星位之钉 → 写档。
function reqCharacterUnlockTalent(session, req) {
  if (!requirePlayer(session)) return;
  const char = findChar(session, req.character_id);
  if (!char) return session.send('res_character_unlock_talent', {}, talent.CODE.NO_CHARACTER);
  const res = talent.unlock(session.player, char, Number(req.talent_id ?? 0));
  session.send('res_character_unlock_talent', {}, res.code);
  if (res.code !== talent.CODE.OK) return;
  // 客户端已经自己扣过一遍本地材料，这里推的是**权威**增量，让它对齐服务端。
  if (res.ntf) session.send('ntf_item_info', res.ntf);
  ntfCharacter(session, char);
  savePlayer(session);
  log.info(`[character] 角色 ${char.character_id} 点亮星位 ${req.talent_id}`);
}

// 武器只能装到「同一武器类型」的角色身上（类型 = d_bag_item_weapon.subType =
// d_character.profession）。这条校验必须由服务端做，因为客户端的武器列表是**按当前
// 已装备武器的 subType 过滤的**（UI_Weapon_Change_C.lua:85-104），一旦装错类型，
// 玩家在 UI 里就再也看不到本类型的武器、只能继续装错类型的武器 —— 错误会自我固化且
// 随存档持久化。官方协议里也有这个错误码（ResCharacterEquipWeapon INVALID_ITEM = 3）。
function weaponTypeMismatch(char, weaponInfo) {
  const want = items.characterWeaponType(char.character_id);
  if (!want) return false; // 表里没有类型（开发占位角色）时不拦
  return items.weaponType(weaponInfo.item_id) !== want;
}

function reqCharacterEquipWeapon(session, req) {
  if (!requirePlayer(session)) return;
  const char = findChar(session, req.character_id);
  const uuid = Number(req.item_uuid ?? 0);
  const entry = session.player.bag.items.find(
    (it) => Number(it.item_uuid) === uuid && items.itemKind(it.item_id) === 'weapon',
  );
  if (!char || !entry) return session.send('res_character_equip_weapon', {}, 2);
  if (weaponTypeMismatch(char, entry)) {
    log.warn(`[character] 拒绝装备：武器 ${entry.item_id}（类型 `
      + `${items.weaponType(entry.item_id)}）与角色 ${char.character_id}（类型 `
      + `${items.characterWeaponType(char.character_id)}）不匹配`);
    return session.send('res_character_equip_weapon', {}, 3); // INVALID_ITEM
  }
  // previous weapon back to bag, new one onto the character
  if (char.weapon_info) {
    session.player.bag.items.push(char.weapon_info);
  }
  session.player.bag.items.splice(session.player.bag.items.indexOf(entry), 1);
  char.weapon_info = entry;
  session.send('res_character_equip_weapon', {});
  ntfCharacter(session, char);
  savePlayer(session);
}

function reqCharacterSwapWeapon(session, req) {
  if (!requirePlayer(session)) return;
  const a = findChar(session, req.character_id);
  const b = findChar(session, req.other_character_id);
  if (!a || !b) return session.send('res_character_swap_weapon', {}, 1);
  // 交换后每把武器都必须落在同类型的角色身上；类型不同（或任一方没有武器，
  // 会让另一方变成"无武器"状态，客户端 UI_Weapon_Change_C:87 会直接炸）都拒绝。
  const ta = items.characterWeaponType(a.character_id);
  const tb = items.characterWeaponType(b.character_id);
  if (!a.weapon_info || !b.weapon_info || (ta && tb && ta !== tb)) {
    log.warn(`[character] 拒绝交换武器：角色 ${a.character_id}（类型 ${ta}）/ `
      + `${b.character_id}（类型 ${tb}）`);
    return session.send('res_character_swap_weapon', {}, 3); // INVALID_ITEM
  }
  const tmp = a.weapon_info;
  a.weapon_info = b.weapon_info;
  b.weapon_info = tmp;
  session.send('res_character_swap_weapon', {});
  ntfCharacter(session, a);
  ntfCharacter(session, b);
  savePlayer(session);
}

// 穿戴皮肤（装扮面板的「装扮」按钮 → req_character_change_skin）。请求体
// {character_id, character_skin_id, mecha_skin_id, city_skin_id}，客户端只在
// result=OK 时把缓存的三个 id 应用到本地角色对象（CharacterSystem.lua:279-296）。
// 服务端必须校验「真的解锁过这张皮肤」：判据是角色 doc 的 own_*_skin_ids 三个列表
// （与客户端 UIUtils.CharSkinIsUnlock 同一套），0 = 默认（客户端自己回退到
// dressInitial==1 的那张）。没解锁回 NO_SKIN(3)，不写档。
function reqCharacterChangeSkin(session, req) {
  if (!requirePlayer(session)) return;
  const char = findChar(session, req.character_id);
  if (!char) return session.send('res_character_change_skin', {}, 1); // NO_CHARACTER
  const skins = require('../game/skins');
  const wants = [
    // [角色 doc 字段, 请求字段, 该字段对应的 dressType]
    ['character_skin_id', req.character_skin_id, 1],
    ['mecha_skin_id', req.mecha_skin_id, 2],
    ['city_skin_id', req.city_skin_id, 3],
  ];
  for (const [field, value, dressType] of wants) {
    if (value === undefined) continue;
    const id = Number(value) || 0;
    if (id === 0) {
      // 0 = 恢复默认：客户端对 0 自己回退到 dressInitial==1 的那张
      // （UIUtils.GetIdolAndCharMeshByCharacterId:2008）。装扮面板实际发的总是具体 id
      // （未改动的那路会发默认 id），0 只来自手工/工具调用。
      char[field] = 0;
      continue;
    }
    const row = skins.clothesRow(id);
    if (!row || Number(row.dressType) !== dressType || !skins.isOwned(char, id)) {
      log.warn(`[character] 拒绝换肤：角色 ${char.character_id} 未解锁皮肤 ${id}（字段 ${field}）`);
      return session.send('res_character_change_skin', {}, 3); // NO_SKIN
    }
    char[field] = id;
  }
  session.send('res_character_change_skin', {});
  ntfCharacter(session, char);
  savePlayer(session);
}

// 使用道具。**不要给被消耗的道具推 ntf_item_info**：客户端在 res_use_item OK 后会本地
// AddItemCount(-count)（BackpackSystem.lua 尾部），而 ntf 的 delta 是加法语义——再推一份
// 就是双重扣减（同坑 23 的「静默扣票」）。各类型在客户端本地做的解锁/创建动作，服务端
// 必须同步落盘，否则重登即丢：
//  - 皮肤卡（itemType 92，subParam = d_char_clothes 皮肤 id）→ 写角色的 own_*_skin_ids
//    （客户端同款逻辑在 BackpackSystem.lua:229-247）
//  - 角色卡（itemType 12 subType 6，subParam[1] = 角色 id）→ 没有就创建角色
//  - 锻造蓝图（subType 9，subParam = 装备蓝图 id）→ 并进 player_info.arm_blueprint_ids
//  （旧实现在这里把 subParam 值当成道具 id 发进背包，制造了一堆幽灵道具——皮肤 id 和
//   角色 id 根本不是道具 id，见 migrate.js 的幽灵道具清理）
function reqUseItem(session, req) {
  if (!requirePlayer(session)) return;
  const uuid = Number(req.item_uuid ?? 0);
  const count = Math.max(1, Number(req.count ?? 1));
  const entry = session.player.bag.items.find((it) => Number(it.item_uuid) === uuid);
  if (!entry || entry.count < count) return session.send('res_use_item', {}, 1); // NO_ITEM
  const cfg = gd.query('d_bag_item', entry.item_id) || {};
  const sub = Array.isArray(cfg.subParam)
    ? cfg.subParam
    : Object.values(cfg.subParam || {});
  const skins = require('../game/skins');

  if (Number(cfg.itemType) === 92) {
    // 皮肤卡：服务端解锁（幂等），整份角色对象推回去（ntf_character_info 是整体替换，
    // 客户端刚在 res 处理器里本地插过一遍，推回去保证两边一致且无重复项）
    for (const char of skins.unlockSkins(session.player, skins.skinItemSkinIds(entry.item_id))) {
      ntfCharacter(session, char);
    }
  } else if (Number(cfg.itemType) === 12 && Number(cfg.subType) === 6) {
    // 角色卡：解锁角色（含专属武器/技能/默认皮肤）。已拥有则无事发生（客户端本来
    // 也会在本地提示「你已有此角色」）。
    const charId = Number(sub[0]) || 0;
    if (charId > 0 && !session.player.characters.some((c) => c.character_id === charId)) {
      const { buildCharacter } = require('../game/player_new');
      const char = buildCharacter(session.player, charId);
      session.player.characters.push(char);
      ntfCharacter(session, char);
      log.info(`[character] 角色卡解锁角色 ${charId}`);
    }
  } else if (Number(cfg.itemType) === 12 && Number(cfg.subType) === 9) {
    // 锻造蓝图（1209xxx）：客户端本地把 subParam 塞进 arm_blueprint_ids，服务端同步
    for (const v of sub) {
      const bp = Number(v);
      if (bp > 0 && !session.player.player.arm_blueprint_ids.some((x) => Number(x) === bp)) {
        session.player.player.arm_blueprint_ids.push(bp);
      }
    }
  }

  entry.count -= count;
  if (entry.count <= 0) session.player.bag.items.splice(session.player.bag.items.indexOf(entry), 1);
  session.send('res_use_item', {});
  savePlayer(session);
}

function reqItemLock(session, req, unlock) {
  if (!requirePlayer(session)) return;
  const uuid = Number(req.item_uuid ?? 0);
  const entry = session.player.bag.items.find((it) => Number(it.item_uuid) === uuid)
    || session.player.characters.map((c) => c.weapon_info).find((w) => w && Number(w.item_uuid) === uuid);
  if (!entry) return session.send(unlock ? 'res_item_unlock' : 'res_item_lock', {}, 1);
  const info = entry.weapon_info || entry.arm_info;
  if (info) info.locked = !unlock;
  session.send(unlock ? 'res_item_unlock' : 'res_item_lock', {});
  savePlayer(session);
}

function reqWeaponLevelUp(session, req) {
  if (!requirePlayer(session)) return;
  const uuid = Number(req.item_uuid ?? 0);
  const target = session.player.bag.items.find((it) => Number(it.item_uuid) === uuid)
    || session.player.characters.map((c) => c.weapon_info).find((w) => w && Number(w.item_uuid) === uuid);
  if (!target) return session.send('res_weapon_level_up', {}, 1);
  // req.item_infos are StuffItemInfo {item_uuid, count}: consume the actual
  // weapon-exp materials (1204xxx) from the bag and add exp per d_bag_item.subParam[0].
  const stuff = (req.item_infos || []).map((s) => ({
    uuid: Number(s.item_uuid ?? 0),
    count: Number(s.count ?? 0),
  })).filter((s) => s.count > 0);
  const consumed = [];
  let gained = 0;
  for (const s of stuff) {
    const entry = session.player.bag.items.find((it) => Number(it.item_uuid) === s.uuid);
    if (!entry || entry.count < s.count) {
      return session.send('res_weapon_level_up', {}, 5); // RES_NOT_ENOUGH
    }
  }
  for (const s of stuff) {
    const entry = session.player.bag.items.find((it) => Number(it.item_uuid) === s.uuid);
    gained += s.count * expPerItem(entry.item_id);
    entry.count -= s.count;
    consumed.push({ item_id: entry.item_id, count: -s.count, item_uuid: String(s.uuid) });
    if (entry.count <= 0) session.player.bag.items.splice(session.player.bag.items.indexOf(entry), 1);
  }
  target.weapon_info.exp += gained;
  session.send('res_weapon_level_up', {});
  if (consumed.length) session.send('ntf_item_info', { changed_item_infos: consumed });
  savePlayer(session);
}

function reqCharacterEquipArm(session, req) {
  if (!requirePlayer(session)) return;
  const char = findChar(session, req.character_id);
  const uuid = Number(req.item_uuid ?? 0);
  const entry = session.player.bag.items.find((it) => Number(it.item_uuid) === uuid);
  if (!char || !entry || items.itemKind(entry.item_id) !== 'arm') {
    return session.send('res_character_equip_arm', {}, 2);
  }
  // same-slot equipped arm goes back to the bag
  const slotCfg = gd.query('d_bag_item_equip', entry.item_id);
  const slot = slotCfg ? slotCfg.subType : 0;
  for (let i = 0; i < char.arm_infos.length; i++) {
    const cur = char.arm_infos[i];
    const curCfg = gd.query('d_bag_item_equip', cur.item_id);
    if ((curCfg ? curCfg.subType : 0) === slot) {
      session.player.bag.items.push(char.arm_infos.splice(i, 1)[0]);
      break;
    }
  }
  session.player.bag.items.splice(session.player.bag.items.indexOf(entry), 1);
  char.arm_infos.push(entry);
  session.send('res_character_equip_arm', {});
  ntfCharacter(session, char);
  savePlayer(session);
}

function reqCharacterUnequipArm(session, req) {
  if (!requirePlayer(session)) return;
  const char = findChar(session, req.character_id);
  const uuid = Number(req.item_uuid ?? 0);
  if (!char) return session.send('res_character_unequip_arm', {}, 1);
  const idx = char.arm_infos.findIndex((a) => Number(a.item_uuid) === uuid);
  if (idx < 0) return session.send('res_character_unequip_arm', {}, 2);
  session.player.bag.items.push(char.arm_infos.splice(idx, 1)[0]);
  session.send('res_character_unequip_arm', {});
  ntfCharacter(session, char);
  savePlayer(session);
}

function reqCharacterSwapArm(session, req) {
  if (!requirePlayer(session)) return;
  const a = findChar(session, req.character_id);
  const b = findChar(session, req.other_character_id);
  if (!a || !b) return session.send('res_character_swap_arm', {}, 1);
  const slot = Number(req.item_slot ?? 0);
  if (slot < 0 || slot >= a.arm_infos.length) return session.send('res_character_swap_arm', {}, 2);
  const fromA = a.arm_infos[slot];
  const cfg = gd.query('d_bag_item_equip', fromA.item_id);
  const subType = cfg ? cfg.subType : 0;
  const idxB = b.arm_infos.findIndex((arm) => {
    const c = gd.query('d_bag_item_equip', arm.item_id);
    return (c ? c.subType : 0) === subType;
  });
  const fromB = idxB >= 0 ? b.arm_infos.splice(idxB, 1)[0] : null;
  a.arm_infos[slot] = fromB || fromA;
  if (fromB) b.arm_infos.push(fromA);
  session.send('res_character_swap_arm', {});
  ntfCharacter(session, a);
  if (fromB) ntfCharacter(session, b);
  savePlayer(session);
}

function findGearByUuid(session, uuid) {
  const inBag = session.player.bag.items.find((it) => Number(it.item_uuid) === uuid);
  if (inBag) return inBag;
  for (const c of session.player.characters) {
    if (c.weapon_info && Number(c.weapon_info.item_uuid) === uuid) return c.weapon_info;
    const arm = c.arm_infos.find((a) => Number(a.item_uuid) === uuid);
    if (arm) return arm;
  }
  return null;
}

// lenient break handlers: client drives the flow with cached values; the
// server just records the new state so it survives relogin.
function reqWeaponLevelBreak(session, req) {
  if (!requirePlayer(session)) return;
  const gear = findGearByUuid(session, Number(req.item_uuid ?? 0));
  if (!gear || !gear.weapon_info) return session.send('res_weapon_level_break', {}, 1);
  gear.weapon_info.break_times += 1;
  session.send('res_weapon_level_break', {});
  savePlayer(session);
}

function reqArmLevelUp(session, req) {
  if (!requirePlayer(session)) return;
  const gear = findGearByUuid(session, Number(req.item_uuid ?? 0));
  if (!gear || !gear.arm_info) return session.send('res_arm_level_up', {}, 1);
  gear.arm_info.exp += 100 * (req.item_infos || []).length;
  session.send('res_arm_level_up', {});
  savePlayer(session);
}

function reqArmLevelBreak(session, req) {
  if (!requirePlayer(session)) return;
  const gear = findGearByUuid(session, Number(req.item_uuid ?? 0));
  if (!gear || !gear.arm_info) return session.send('res_arm_level_break', {}, 1);
  gear.arm_info.break_times += 1;
  session.send('res_arm_level_break', {});
  savePlayer(session);
}

// 光淬（精炼）。效果变动弹窗在 res 到达瞬间从背包缓存读「新阶数」（UI_Weapon_Refined_C
// 的 OnMsg_Req_Strengthen_Weapon_Success），而客户端对 res_weapon_refine 本身不解析任何
// 数据、也不像升级那样本地预测结果 —— 背包缓存只随 ntf_item_info 更新。所以必须
// **先推 ntf 再回 res**，顺序反了弹窗就会显示「光淬0阶 → 光淬0阶」（新旧同值）。
function reqWeaponRefine(session, req) {
  if (!requirePlayer(session)) return;
  const gear = findGearByUuid(session, Number(req.item_uuid ?? 0));
  if (!gear || !gear.weapon_info) return session.send('res_weapon_refine', {}, 1);
  const weaponCfg = gd.query('d_weapon', gear.item_id) || {};
  const maxRefine = weaponCfg.maxRefine ?? 4;
  if (gear.weapon_info.refine_level >= maxRefine) return session.send('res_weapon_refine', {}, 3);

  // stuff_item_uuid 是 repeated 字段：遍历逐个解析（Number(array) 只对单元素碰巧可用，
  // 多选素材会得到 NaN）。先校验后应用，任何一项不过就整单拒绝、不产生状态变更。
  const stuffUuids = Array.isArray(req.stuff_item_uuid)
    ? req.stuff_item_uuid
    : (req.stuff_item_uuid != null ? [req.stuff_item_uuid] : []);
  const family = Array.isArray(weaponCfg.refinedWeapon) ? weaponCfg.refinedWeapon : [gear.item_id];
  const stuffs = [];
  for (const raw of stuffUuids) {
    const stuff = findGearByUuid(session, Number(raw ?? 0));
    if (!stuff || stuff === gear) continue; // 目标自己/已装备同件武器：不是素材，静默跳过
    const ok = session.player.bag.items.includes(stuff)
      && !!stuff.weapon_info
      && family.includes(stuff.item_id)
      && !stuff.weapon_info.locked;
    if (!ok) return session.send('res_weapon_refine', {}, 4); // STUFF_NOT_ENOUGH
    stuffs.push(stuff);
  }
  if (!stuffs.length) return session.send('res_weapon_refine', {}, 4);

  const cost = Number(weaponCfg.refinedCost) || 0;
  const ntfCost = cost > 0
    ? items.consumeItems(session.player, [{ item_id: 9001, count: cost }])
    : { changed_item_infos: [] };
  if (!ntfCost) return session.send('res_weapon_refine', {}, 4);

  gear.weapon_info.refine_level += 1;
  // count=0 才命中客户端背包的「整条替换」分支（BackpackSystem.lua:384），count 非 0
  // 会被当成数量增量；已装备的武器则走 item_extra=='weapon_info' 分支原地刷新（:354）。
  const changed = [{
    item_id: gear.item_id,
    count: 0,
    item_uuid: String(gear.item_uuid),
    weapon_info: gear.weapon_info,
  }];
  // 素材的扣除没有任何本地预测（CachedStuffItemUuid 缓存后从未被消费），
  // 必须以 count=-1 推给客户端，背包里被吃的武器才即时消失。
  for (const stuff of stuffs) {
    session.player.bag.items.splice(session.player.bag.items.indexOf(stuff), 1);
    changed.push({ item_id: stuff.item_id, count: -1, item_uuid: String(stuff.item_uuid) });
  }
  session.send('ntf_item_info', { changed_item_infos: [...changed, ...ntfCost.changed_item_infos] });
  session.send('res_weapon_refine', { item_infos: [gearToStuff(gear)] });
  savePlayer(session);
}

function gearToStuff(gear) {
  return { item_uuid: String(gear.item_uuid), count: 1 };
}

module.exports = {
  findChar, ntfCharacter,
  reqCharacterLevelUp, reqCharacterLevelBreak, reqCharacterSkillLevelUp,
  reqCharacterUnlockTalent,
  reqCharacterEquipWeapon, reqCharacterSwapWeapon, reqCharacterChangeSkin,
  reqCharacterEquipArm, reqCharacterUnequipArm, reqCharacterSwapArm,
  reqUseItem, reqItemLock, reqWeaponLevelUp,
  reqWeaponLevelBreak, reqArmLevelUp, reqArmLevelBreak, reqWeaponRefine,
};
