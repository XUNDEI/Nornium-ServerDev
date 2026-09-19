// Mall (direct-purchase shop) builder over d_mall.
const gd = require('../gamedata');

// 月卡：d_mall id 1007（shopType 202）对应 d_gacha_monthly_pass 1007。
// 客户端同样硬编码这个 id（MallSystem.lua:214）。
const MONTH_CARD_ITEM_ID = 1007;
const MONTH_CARD_DAYS = 30;

// 月卡的权威状态。必须和 res_mall_list / ntf_mall_info 一起下发：
// 客户端每秒轮询 MallSystem:CheckMonthCard，只看这份本地缓存决定要不要发
// req_mall_receive_month_card，不把权威状态推下去就会出现"每秒重发+每秒报错"。
function monthCardInfo(player) {
  return {
    expire_seconds: String(player.mall.month_card_expire || 0),
    last_tick_seconds: String(player.mall.month_card_last_tick || 0),
  };
}

function buildMallListInfo(player) {
  const byShop = new Map();
  for (const [idStr, row] of gd.rows('d_mall')) {
    const mallId = row.shopType;
    if (!byShop.has(mallId)) byShop.set(mallId, []);
    byShop.get(mallId).push({ id: Number(idStr), order: row.order ?? 0 });
  }
  const mall_infos = [];
  for (const [mallId, entries] of byShop) {
    entries.sort((a, b) => a.order - b.order);
    mall_infos.push({
      mall_id: mallId,
      mall_item_infos: entries.map((e) => ({ mall_item_id: e.id })),
      last_auto_refresh_seconds: '0',
      mall_purchase_limit_infos: Object.entries(player.mall.purchase)
        .filter(([mid]) => {
          const cfg = gd.query('d_mall', mid);
          return cfg && cfg.shopType === mallId;
        })
        .map(([mid, times]) => ({ mall_item_id: Number(mid), purchase_times: times, refresh_seconds: '0' })),
    });
  }
  return {
    mall_infos,
    month_card_info: monthCardInfo(player),
    charge_point_info: {
      charge_point: player.mall.charge_point,
      received_charge_point_ids: player.mall.received_charge_points,
    },
  };
}

module.exports = { buildMallListInfo, monthCardInfo, MONTH_CARD_ITEM_ID, MONTH_CARD_DAYS };
