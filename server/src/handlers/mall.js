// Mall purchase + IAP order handlers. No Steam payment: purchases grant
// immediately ("点击购买直接到账").
const gd = require('../gamedata');
const items = require('../game/items');
const daily = require('../game/daily');
const { savePlayer, requirePlayer } = require('./sync');
const {
  buildMallListInfo, monthCardInfo, MONTH_CARD_ITEM_ID, MONTH_CARD_DAYS,
} = require('../game/mall');

let orderId = Math.floor(Date.now() / 1000) % 100000000;

function grantGoods(session, tripleFlat) {
  const grants = [];
  for (let i = 0; i + 2 < tripleFlat.length; i += 3) {
    grants.push({ item_id: tripleFlat[i], count: tripleFlat[i + 2] });
  }
  return grants;
}

// ntf_mall_info 必须把月卡状态一起推下去（NtfMallInfo.month_card_info），
// 否则客户端本地那份 month_card_info 永远是买卡之前的值。
function pushMallInfo(session) {
  const info = buildMallListInfo(session.player);
  session.send('ntf_mall_info', {
    mall_infos: info.mall_infos,
    month_card_info: info.month_card_info,
  });
}

// 月卡购买（shopType 202）：续期 30 天 + 发放 d_gacha_monthly_pass.purchaseReward。
// last_tick_seconds 置 0 表示"这一天的奖励还没领"——客户端见到 0 会立刻发起
// req_mall_receive_month_card（MallSystem.lua:89 的"第一次申请月卡奖励"），
// 因此买卡当天就能拿到第一份每日奖励。
function applyMonthCardPurchase(session) {
  const mall = session.player.mall;
  const now = Math.floor(Date.now() / 1000);
  const base = Math.max(now, Number(mall.month_card_expire || 0));
  mall.month_card_expire = base + MONTH_CARD_DAYS * 86400;
  mall.month_card_last_tick = 0;
  const pass = gd.query('d_gacha_monthly_pass', MONTH_CARD_ITEM_ID);
  return grantGoods(session, (pass && pass.purchaseReward) || []);
}

// 月卡每日奖励：客户端每秒轮询，在「有卡 + 已跨过 04:00 刷新点」时发这条请求
// （MallSystem:CheckMonthCard）。服务端领完必须把新的 last_tick_seconds 推回客户端，
// 否则客户端会一直重发、每次都被判失败 → 刷屏 "cmd:13006 code:1"。
function handleReceiveMonthCard(session) {
  if (!requirePlayer(session)) return;
  const mall = session.player.mall;
  const now = Math.floor(Date.now() / 1000);
  const expire = Number(mall.month_card_expire || 0);

  if (!expire || now > expire) {
    // 没卡 / 卡已过期：顺手把过期状态清掉再推给客户端，避免它继续按旧状态轮询
    if (expire && now > expire) mall.month_card_expire = 0;
    pushMallInfo(session);
    savePlayer(session);
    return session.send('res_mall_receive_month_card', {}, 1); // NO_CARD
  }

  const boundary = daily.dailyRefreshBoundary(now);
  if (Number(mall.month_card_last_tick || 0) >= boundary) {
    // 今天已经领过：同步权威状态（客户端多半是本地 last_tick 过期了）
    pushMallInfo(session);
    return session.send('res_mall_receive_month_card', {}, 2); // ALREADY_RECEIVED
  }

  mall.month_card_last_tick = now;
  const pass = gd.query('d_gacha_monthly_pass', MONTH_CARD_ITEM_ID);
  const grants = grantGoods(session, (pass && pass.dailyReward) || []);
  session.send('res_mall_receive_month_card', {});
  if (grants.length) session.send('ntf_item_info', items.grantItems(session.player, grants));
  pushMallInfo(session);
  savePlayer(session);
}

function purchase(session, req, viaOrder) {
  if (!requirePlayer(session)) return null;
  const itemId = Number(req.order_item_id ?? req.mall_item_id ?? 0);
  const count = Math.max(1, Number(req.order_item_count ?? req.mall_item_count ?? 1));
  const cfg = gd.query('d_mall', itemId);
  if (!cfg) {
    session.send(viaOrder ? 'res_create_order' : 'res_mall_buy', {}, 1);
    return null;
  }
  const times = session.player.mall.purchase[itemId] || 0;
  if ((cfg.limitTimes ?? 0) > 0 && times + count > cfg.limitTimes) {
    session.send(viaOrder ? 'res_create_order' : 'res_mall_buy', {}, 4); // PURCHASE_LIMIT
    return null;
  }
  return cfg;
}

function handleMallBuy(session, req) {
  const cfg = purchase(session, req, false);
  if (!cfg) return;
  const itemId = Number(req.mall_item_id);
  const orderIdStr = String(++orderId);
  session.player.mall.purchase[itemId] = (session.player.mall.purchase[itemId] || 0) + Math.max(1, Number(req.mall_item_count ?? 1));

  // res first (client caches chargeInfo from it), then the reward stream.
  session.send('res_mall_buy', { game_order_id: orderIdStr });

  if ((cfg.charge ?? 0) === 1) {
    // paid item: grant + accumulate charge point; ntf_finish_order triggers
    // the success popup client-side.
    session.player.mall.charge_point += cfg.chargePoint ?? 0;
    let grants = grantGoods(session, cfg.goods || []);
    if (cfg.shopType === 202) {
      grants = grants.concat(applyMonthCardPurchase(session)); // 月卡：续期 + 购买奖励
    }
    if (grants.length) {
      const ntf = items.grantItems(session.player, grants);
      session.send('ntf_item_info', ntf);
    }
    pushMallInfo(session);
    session.send('ntf_finish_order', { game_order_id: orderIdStr });
  } else {
    // currency purchase: charge the wallet, then grant
    const price = (cfg.price && cfg.price[0]) || 0;
    const ntfCost = items.consumeItems(session.player, [{ item_id: cfg.currency, count: price * Math.max(1, Number(req.mall_item_count ?? 1)) }]);
    if (!ntfCost) {
      session.player.mall.purchase[itemId] -= Math.max(1, Number(req.mall_item_count ?? 1));
      session.send('res_mall_buy', {}, 5); // RES_NOT_ENOUGH
      return;
    }
    const grants = grantGoods(session, cfg.goods || []);
    const ntfGain = items.grantItems(session.player, grants);
    session.send('ntf_item_info', {
      changed_item_infos: [...ntfCost.changed_item_infos, ...ntfGain.changed_item_infos],
    });
    pushMallInfo(session);
  }
  savePlayer(session);
}

function handleCreateOrder(session, req) {
  const cfg = purchase(session, req, true);
  if (!cfg) return;
  const orderIdStr = String(++orderId);
  const count = Math.max(1, Number(req.order_item_count ?? 1));
  session.player.mall.purchase[Number(req.order_item_id)] =
    (session.player.mall.purchase[Number(req.order_item_id)] || 0) + count;
  session.send('res_create_order', { game_order_id: orderIdStr });
  session.player.mall.charge_point += (cfg.chargePoint ?? 0) * count;
  let grants = grantGoods(session, cfg.goods || []);
  if (cfg.shopType === 202) grants = grants.concat(applyMonthCardPurchase(session));
  if (grants.length) {
    const ntf = items.grantItems(session.player, grants);
    session.send('ntf_item_info', ntf);
  }
  pushMallInfo(session);
  session.send('ntf_finish_order', { game_order_id: orderIdStr });
  savePlayer(session);
}

// 累充奖励：d_gacha_vip 每档 chargeRank 为充值积分门槛，normalReward/focusedReward
// 为 [item_id, itemType, count] 三元组（与 d_mall.goods 同构）。
function handleReceiveChargePointReward(session, req) {
  if (!requirePlayer(session)) return;
  const id = Number(req.charge_point_id ?? 0);
  const cfg = gd.query('d_gacha_vip', id);
  const mall = session.player.mall;
  mall.received_charge_points = mall.received_charge_points || [];
  if (!cfg) return session.send('res_mall_receive_charge_point_reward', {}, 1); // NO_CONFIG
  if (mall.charge_point < (cfg.chargeRank ?? 0)) {
    return session.send('res_mall_receive_charge_point_reward', {}, 2); // NOT_ENOUGH_CHARGE
  }
  if (mall.received_charge_points.includes(id)) {
    return session.send('res_mall_receive_charge_point_reward', {}, 3); // ALREADY_RECEIVED
  }
  mall.received_charge_points.push(id);
  const grants = grantGoods(session, [].concat(cfg.normalReward || [], cfg.focusedReward || []));
  // 客户端收到 res 后自行把 charge_point_id 插入本地已领列表（MallSystem.lua:206），
  // 服务端只需发放奖励并持久化。
  session.send('res_mall_receive_charge_point_reward', {});
  if (grants.length) {
    const ntf = items.grantItems(session.player, grants);
    session.send('ntf_item_info', ntf);
  }
  savePlayer(session);
}

function handle(name) {
  const map = {
    req_mall_buy: handleMallBuy,
    req_create_order: handleCreateOrder,
    req_finish_order: (s) => s.send('res_finish_order', {}),
    req_mall_receive_month_card: handleReceiveMonthCard,
    req_mall_receive_charge_point_reward: handleReceiveChargePointReward,
  };
  return map[name] ?? null;
}

module.exports = { handle };
