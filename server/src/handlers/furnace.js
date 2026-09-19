// 恶魔熔炉 / Demon Furnace: 炼金合成 (req_item_synthetic), 分解
// (req_item_decompose) and 锻造 (req_arm_forge). Server-authoritative: recipes
// come from d_furnace_synthesis / d_furnace_decompose / d_equip_forge, and item
// movement is reported through ntf_item_info after the res (client order).
const items = require('../game/items');
const furnace = require('../game/furnace');
const { savePlayer, requirePlayer } = require('./sync');

function mergeNtf(...parts) {
  return {
    changed_item_infos: parts.flatMap((p) => (p && p.changed_item_infos) || []),
  };
}

// req_item_synthetic { blueprint_id = d_furnace_synthesis id, count }
function reqItemSynthetic(session, req) {
  if (!requirePlayer(session)) return;
  const recipe = furnace.synthesisRecipe(req.blueprint_id);
  if (!recipe) return session.send('res_item_synthetic', {}, 1); // NO_BLUEPRINT
  const times = Number(req.count ?? 1);
  if (!Number.isInteger(times) || times <= 0) {
    return session.send('res_item_synthetic', {}, 3); // INVALID_COUNT
  }
  const costs = furnace.parseCostPairs(recipe.item).map((c) => ({ item_id: c.item_id, count: c.count * times }));
  const consumed = items.consumeItems(session.player, costs);
  if (!consumed) return session.send('res_item_synthetic', {}, 4); // RES_NOT_ENOUGH
  const granted = items.grantItems(session.player, [{ item_id: recipe.targetID, count: times }]);
  session.send('res_item_synthetic', {});
  session.send('ntf_item_info', mergeNtf(consumed, granted));
  savePlayer(session);
}

// req_item_decompose { item_uuids: [...] }
function reqItemDecompose(session, req) {
  if (!requirePlayer(session)) return;
  const uuids = [...new Set((req.item_uuids || []).map(Number).filter((u) => u > 0))];
  if (!uuids.length) return session.send('res_item_decompose', {}, 2); // INVALID_COUNT

  const selected = [];
  for (const uuid of uuids) {
    const entry = session.player.bag.items.find((it) => Number(it.item_uuid) === uuid);
    if (!entry) return session.send('res_item_decompose', {}, 1); // INVALID_ITEM
    const cfg = items.itemConfig(entry.item_id);
    const recipe = cfg && furnace.decomposeRecipe(cfg.itemType, cfg.rarity);
    if (!recipe) return session.send('res_item_decompose', {}, 1); // INVALID_ITEM
    selected.push({ entry, recipe });
  }

  const removed = [];
  const grants = [];
  for (const { entry, recipe } of selected) {
    session.player.bag.items.splice(session.player.bag.items.indexOf(entry), 1);
    removed.push({ item_id: entry.item_id, count: -Number(entry.count || 1), item_uuid: String(entry.item_uuid) });
    const flat = Array.isArray(recipe.obtain) ? recipe.obtain : [];
    for (let i = 0; i + 2 < flat.length; i += 3) {
      const min = Number(flat[i + 1]);
      const max = Number(flat[i + 2]);
      const n = min + Math.floor(Math.random() * (Math.max(min, max) - min + 1));
      if (n > 0) grants.push({ item_id: Number(flat[i]), count: n });
    }
  }
  const granted = grants.length ? items.grantItems(session.player, grants) : { changed_item_infos: [] };
  session.send('res_item_decompose', {});
  session.send('ntf_item_info', { changed_item_infos: [...removed, ...granted.changed_item_infos] });
  savePlayer(session);
}

// req_arm_forge { blueprint_id = d_equip_forge id, feed_item_uuid, count }
// feed_item_uuid is accepted but not consumed (lenient, like the other gear
// paths: it only feeds random attributes in the official server).
function reqArmForge(session, req) {
  if (!requirePlayer(session)) return;
  const recipe = furnace.forgeRecipe(req.blueprint_id);
  if (!recipe) return session.send('res_arm_forge', {}, 1); // NO_BLUEPRINT
  const times = Number(req.count ?? 1);
  if (!Number.isInteger(times) || times <= 0) {
    return session.send('res_arm_forge', {}, 3); // INVALID_COUNT
  }
  const costs = furnace.parseCostPairs(recipe.item).map((c) => ({ item_id: c.item_id, count: c.count * times }));
  const consumed = items.consumeItems(session.player, costs);
  if (!consumed) return session.send('res_arm_forge', {}, 4); // RES_NOT_ENOUGH
  const granted = items.grantItems(session.player, [{ item_id: recipe.equipId, count: times }]);
  session.send('res_arm_forge', {});
  session.send('ntf_item_info', mergeNtf(consumed, granted));
  savePlayer(session);
}

module.exports = { reqItemSynthetic, reqItemDecompose, reqArmForge };
