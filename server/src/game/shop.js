// Shop system (d_shop_type / d_shop). NPC shops 101/102 carry real goods.
const gd = require('../gamedata');

function lastDailyRefresh() {
  // client uses local 4am as the daily refresh boundary
  const now = new Date();
  const ref = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 4, 0, 0);
  if (now < ref) ref.setDate(ref.getDate() - 1);
  return Math.floor(ref.getTime() / 1000);
}

function shopState(player, shopId) {
  player.shop.shops[shopId] = player.shop.shops[shopId] || { purchases: {} };
  return player.shop.shops[shopId];
}

function buildShopListInfo(player) {
  const infos = [];
  for (const [idStr, typeRow] of gd.rows('d_shop_type')) {
    const shopId = Number(idStr);
    // NPC shops (type 1: ids 101/102) always appear; other types only with goods
    const items = gd.rows('d_shop')
      .map(([, r]) => r)
      .filter((r) => r.shopTypeId === shopId);
    if (!items.length && (typeRow.type ?? 0) !== 1) continue;
    const state = shopState(player, shopId);
    infos.push({
      shop_id: shopId,
      shop_item_infos: items.map((r) => ({ shop_item_id: r.id, discount: 100 })),
      last_auto_refresh_seconds: String(lastDailyRefresh()),
      manual_refresh_seconds: '0',
      manual_refresh_times: 0,
      purchase_limit_infos: Object.entries(state.purchases).map(([sid, times]) => ({
        shop_item_id: Number(sid),
        purchase_times: times,
        refresh_seconds: '0',
      })),
    });
  }
  return { shop_infos: infos };
}

module.exports = { buildShopListInfo, shopState, lastDailyRefresh };
