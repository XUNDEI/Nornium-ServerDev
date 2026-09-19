// Shop purchase handler.
const gd = require('../gamedata');
const items = require('../game/items');
const { savePlayer, requirePlayer } = require('./sync');
const { buildShopListInfo, shopState } = require('../game/shop');

function handle(name) {
  if (name !== 'req_shop_buy' && name !== 'req_shop_refresh') return null;
  if (name === 'req_shop_refresh') {
    // manual refresh: shops are static on this server, report refresh limit
    return (session) => session.send('res_shop_refresh', {}, 2); // REFRESH_LIMIT
  }
  return (session, req) => {
    if (!requirePlayer(session)) return;
    const shopId = Number(req.shop_id ?? 0);
    const shopItemId = Number(req.shop_item_id ?? 0);
    const count = Math.max(1, Number(req.shop_item_count ?? 1));
    const cfg = gd.query('d_shop', shopItemId);
    if (!cfg || cfg.shopTypeId !== shopId) {
      return session.send('res_shop_buy', {}, 2); // NO_SHOP_ITEM
    }
    const state = shopState(session.player, shopId);
    const bought = state.purchases[shopItemId] || 0;
    if ((cfg.limitType ?? 0) === 1 && bought + count > (cfg.limitPrice ?? 1)) {
      return session.send('res_shop_buy', {}, 4); // PURCHASE_LIMIT
    }
    const discount = 100;
    const cost = Math.floor(cfg.money * discount / 100) * count;
    const ntfCost = items.consumeItems(session.player, [{ item_id: cfg.moneyType, count: cost }]);
    if (!ntfCost) return session.send('res_shop_buy', {}, 5); // RES_NOT_ENOUGH
    state.purchases[shopItemId] = bought + count;
    const grants = [];
    for (let i = 0; i < count; i++) grants.push({ item_id: cfg.goodsId, count: cfg.sellNum ?? 1 });
    const ntfGain = items.grantItems(session.player, grants);
    session.send('ntf_item_info', {
      changed_item_infos: [...ntfCost.changed_item_infos, ...ntfGain.changed_item_infos],
    });
    session.send('res_shop_buy', {});
    session.send('ntf_shop_info', { shop_infos: buildShopListInfo(session.player).shop_infos.filter((s) => s.shop_id === shopId) });
    savePlayer(session);
  };
}

module.exports = { handle };
