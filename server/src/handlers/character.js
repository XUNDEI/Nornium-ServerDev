// Character & bag operations available in the main city (M1+).
const gd = require('../gamedata');
const items = require('../game/items');
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

function reqCharacterEquipWeapon(session, req) {
  if (!requirePlayer(session)) return;
  const char = findChar(session, req.character_id);
  const uuid = Number(req.item_uuid ?? 0);
  const entry = session.player.bag.items.find(
    (it) => Number(it.item_uuid) === uuid && items.itemKind(it.item_id) === 'weapon',
  );
  if (!char || !entry) return session.send('res_character_equip_weapon', {}, 2);
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
  const tmp = a.weapon_info;
  a.weapon_info = b.weapon_info;
  b.weapon_info = tmp;
  session.send('res_character_swap_weapon', {});
  ntfCharacter(session, a);
  ntfCharacter(session, b);
  savePlayer(session);
}

function reqCharacterChangeSkin(session, req) {
  if (!requirePlayer(session)) return;
  const char = findChar(session, req.character_id);
  if (!char) return session.send('res_character_change_skin', {}, 1);
  if (req.character_skin_id !== undefined) char.character_skin_id = Number(req.character_skin_id);
  if (req.mecha_skin_id !== undefined) char.mecha_skin_id = Number(req.mecha_skin_id);
  if (req.city_skin_id !== undefined) char.city_skin_id = Number(req.city_skin_id);
  session.send('res_character_change_skin', {});
  ntfCharacter(session, char);
  savePlayer(session);
}

function reqUseItem(session, req) {
  if (!requirePlayer(session)) return;
  const uuid = Number(req.item_uuid ?? 0);
  const count = Number(req.count ?? 1);
  const entry = session.player.bag.items.find((it) => Number(it.item_uuid) === uuid);
  if (!entry) return session.send('res_use_item', {}, 1); // NO_ITEM
  const cfg = gd.query('d_bag_item', entry.item_id);
  const grants = [];
  if (cfg && cfg.subParam) {
    // CharCard / BluePrint style items: subParam carries unlock ids
    const sub = Array.isArray(cfg.subParam) ? cfg.subParam : Object.values(cfg.subParam);
    for (const v of sub) if (Number(v) > 0) grants.push({ item_id: Number(v), count: 1 });
  }
  const ntf = items.grantItems(session.player, [{ item_id: entry.item_id, count: -count, item_uuid: entry.item_uuid }]);
  session.send('res_use_item', {});
  if (ntf) session.send('ntf_item_info', ntf);
  if (grants.length) {
    const grantNtf = items.grantItems(session.player, grants);
    session.send('ntf_item_info', grantNtf);
  }
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

function reqWeaponRefine(session, req) {
  if (!requirePlayer(session)) return;
  const gear = findGearByUuid(session, Number(req.item_uuid ?? 0));
  if (!gear || !gear.weapon_info) return session.send('res_weapon_refine', {}, 1);
  gear.weapon_info.refine_level += 1;
  const stuff = findGearByUuid(session, Number(req.stuff_item_uuid ?? 0));
  if (stuff) {
    if (session.player.bag.items.includes(stuff)) {
      session.player.bag.items.splice(session.player.bag.items.indexOf(stuff), 1);
    }
  }
  session.send('res_weapon_refine', { item_infos: [gearToStuff(gear)] });
  savePlayer(session);
}

function gearToStuff(gear) {
  return { item_uuid: String(gear.item_uuid), count: 1 };
}

module.exports = {
  findChar, ntfCharacter,
  reqCharacterLevelUp, reqCharacterLevelBreak, reqCharacterSkillLevelUp,
  reqCharacterEquipWeapon, reqCharacterSwapWeapon, reqCharacterChangeSkin,
  reqCharacterEquipArm, reqCharacterUnequipArm, reqCharacterSwapArm,
  reqUseItem, reqItemLock, reqWeaponLevelUp,
  reqWeaponLevelBreak, reqArmLevelUp, reqArmLevelBreak, reqWeaponRefine,
};
