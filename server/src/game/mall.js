// Mall (direct-purchase shop) builder over d_mall.
const gd = require('../gamedata');
const runtimeConfig = require('../runtime-config');
const { dailyRefreshBoundary } = require('./daily');

// 月卡：d_mall id 1007（shopType 202）对应 d_gacha_monthly_pass 1007。
// 客户端同样硬编码这个 id（MallSystem.lua:214）。
const MONTH_CARD_ITEM_ID = 1007;
const MONTH_CARD_DAYS = 30;

// ---- 限购 ----
//
// d_mall.limitType：1=终身限购、2=每日、3=每周、4=每月（客户端
// UI_TopUp_Shop_C.lua:519-548 硬编码）。客户端判定「已售罄」只比较
// limitTimes - purchase_times（UI_TopUp_Shop_C.lua:540），服务端不下发新的
// purchase_times 它就永远卡在售罄——所以每周限购的重置必须由服务端清零
// mall.purchase 里对应条目（limitType=3）后再随列表下发。
// 私服开关：runtime-config.json 的 "mall_limit_disabled": true 时跳过所有限购
// 校验，且不下发已购次数（客户端显示 0/limit，全部可买）。

function limitDisabled() {
  return !!runtimeConfig.read().mall_limit_disabled;
}

// 编辑器「关闭商城限购」开关的写入口（合并写回，保留其余键，改完即时生效）。
// disabled 未提供时不改动现状。
function setLimitConfig({ disabled } = {}) {
  if (disabled !== undefined) runtimeConfig.write({ mall_limit_disabled: !!disabled });
  return { disabled: limitDisabled() };
}

// 本周期周一 04:00（本地时区），与日常刷新（dailyRefreshBoundary）同一时刻起点，
// 往回走到周一为止。周一 04:00 前属于上一个周期。
function weeklyBoundary(nowSec) {
  const t = new Date(dailyRefreshBoundary(nowSec) * 1000);
  while (t.getDay() !== 1) t.setDate(t.getDate() - 1);
  return Math.floor(t.getTime() / 1000);
}

// 跨过周一 04:00 就把每周限购（limitType=3）商品的已购次数清零（幂等、惰性：
// 在拉商城列表 / 购买前调用，不需要定时器）。返回是否有清零发生。
// 每月限购（limitType=4，仅 3 个商品）暂不重置，扩展时照抄本函数换边界即可。
function refreshWeeklyLimits(player, nowSec = Math.floor(Date.now() / 1000)) {
  const mall = player.mall;
  if (!mall) return false;
  const boundary = weeklyBoundary(nowSec);
  if (Number(mall.week_tick_seconds || 0) >= boundary) return false;
  mall.week_tick_seconds = boundary;
  mall.purchase = mall.purchase || {};
  for (const mid of Object.keys(mall.purchase)) {
    const cfg = gd.query('d_mall', mid);
    if (cfg && Number(cfg.limitType) === 3) delete mall.purchase[mid];
  }
  return true;
}

// 月卡的权威状态。必须和 res_mall_list / ntf_mall_info 一起下发：
// 客户端每秒轮询 MallSystem:CheckMonthCard，只看这份本地缓存决定要不要发
// req_mall_receive_month_card，不把权威状态推下去就会出现"每秒重发+每秒报错"。
function monthCardInfo(player) {
  return {
    expire_seconds: String(player.mall.month_card_expire || 0),
    last_tick_seconds: String(player.mall.month_card_last_tick || 0),
  };
}

function buildMallListInfo(player, nowSec = Math.floor(Date.now() / 1000)) {
  const byShop = new Map();
  for (const [idStr, row] of gd.rows('d_mall')) {
    const mallId = row.shopType;
    if (!byShop.has(mallId)) byShop.set(mallId, []);
    byShop.get(mallId).push({ id: Number(idStr), order: row.order ?? 0 });
  }
  const nextWeek = weeklyBoundary(nowSec) + 7 * 86400; // 下次周重置时刻
  const limitOff = limitDisabled();
  const mall_infos = [];
  for (const [mallId, entries] of byShop) {
    entries.sort((a, b) => a.order - b.order);
    mall_infos.push({
      mall_id: mallId,
      mall_item_infos: entries.map((e) => ({ mall_item_id: e.id })),
      last_auto_refresh_seconds: '0',
      // 限购关闭时不带任何已购条目：客户端把缺席视为 0 次购买，售罄全部解除。
      // 周限购条目的 refresh_seconds 带距下次重置的秒数（客户端不依赖它重置，
      // 只用于展示；终身/每月限购维持 '0'）。
      mall_purchase_limit_infos: Object.entries(player.mall.purchase)
        .filter(([mid]) => {
          const cfg = gd.query('d_mall', mid);
          if (!cfg || cfg.shopType !== mallId) return false;
          if (limitOff) return (cfg.limitTimes ?? 0) <= 0; // 关限购：有配置的条目全部隐去
          return true;
        })
        .map(([mid, times]) => {
          const cfg = gd.query('d_mall', mid) || {};
          const refresh = !limitOff && Number(cfg.limitType) === 3
            ? String(Math.max(0, nextWeek - nowSec))
            : '0';
          return { mall_item_id: Number(mid), purchase_times: times, refresh_seconds: refresh };
        }),
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

module.exports = {
  buildMallListInfo, monthCardInfo, MONTH_CARD_ITEM_ID, MONTH_CARD_DAYS,
  limitDisabled, setLimitConfig, weeklyBoundary, refreshWeeklyLimits,
};
