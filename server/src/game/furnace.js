// Furnace (炼金/分解/锻造) recipe lookups driven by the client data tables.
const gd = require('../gamedata');

// d_furnace_synthesis is keyed by recipe id; the client sends that id as
// `blueprint_id` and compares it against PlayerInfo.blueprint_ids.
function synthesisRecipe(blueprintId) {
  return gd.query('d_furnace_synthesis', blueprintId);
}

// There is no BluePrint-typed item in this build (d_bag_item has no subType 8
// rows), so synthesis recipes have no in-game unlock source. Hand them all to
// the player; without this the furnace's synthesize button stays disabled and
// the "尝试一次炼金" story task can never be completed.
function synthesisBlueprintIds() {
  return gd.rows('d_furnace_synthesis').map(([id]) => Number(id)).filter((n) => Number.isFinite(n));
}

// d_furnace_decompose rows match on (itemType, itemRarity); `obtain` is a flat
// [item_id, min, max, ...] triple list.
function decomposeRecipe(itemType, rarity) {
  return gd.rows('d_furnace_decompose')
    .map(([, r]) => r)
    .find((r) => r.itemType === Number(itemType) && r.itemRarity === Number(rarity)) ?? null;
}

// d_equip_forge rows: { id, item: [cost_id, cost_count, ...], equipId }.
function forgeRecipe(blueprintId) {
  return gd.query('d_equip_forge', blueprintId);
}

// Flat [id, count, id, count, ...] -> [{item_id, count}].
function parseCostPairs(flat) {
  const out = [];
  const arr = Array.isArray(flat) ? flat : [];
  for (let i = 0; i + 1 < arr.length; i += 2) {
    const item_id = Number(arr[i]);
    const count = Number(arr[i + 1]);
    if (item_id > 0 && count > 0) out.push({ item_id, count });
  }
  return out;
}

module.exports = {
  synthesisRecipe, synthesisBlueprintIds, decomposeRecipe, forgeRecipe, parseCostPairs,
};
