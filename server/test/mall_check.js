// 商城限购回归：每周限购的周重置（周一 04:00）+ 「关闭全部限购」开关。
//
// 背景（REVERSE_ENGINEERING.md 坑）：handlers/mall.js 早期只校验 limitTimes 总量、
// 从不读 limitType，player.mall.purchase 终身累计，客户端（UI_TopUp_Shop_C.lua:540
// 只比较 limitTimes - purchase_times）于是永远显示已售罄——「每周限购过了一周也不重置」。
//
// 规矩（坑 35）：GHS_DATA_DIR / GHS_RUNTIME_CONFIG 指向临时目录，绝不写真实存档与配置。
const os = require('os');
const fs = require('fs');
const path = require('path');
const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'ghs-mall-'));
process.env.GHS_DATA_DIR = path.join(tmpRoot, 'data');
process.env.GHS_RUNTIME_CONFIG = path.join(tmpRoot, 'runtime-config.json');

const store = require('../src/store');
const mall = require('../src/game/mall');
const handlers = require('../src/handlers/mall');

let failures = 0;
function check(cond, msg) {
  console.log(cond ? `  PASS ${msg}` : `  FAIL ${msg}`);
  if (!cond) failures += 1;
}

// d_mall 1012：charge=1（内购，即时发放）、limitTimes=2、limitType=3（每周限购）；
// d_mall 1010：charge=1、limitTimes=1、limitType=1（终身限购，周重置不该碰它）。
const WEEKLY_ITEM = 1012;
const LIFETIME_ITEM = 1010;

(async () => {
  store.loadAccounts();
  const acc = store.createAccount('mallhero', 'pw');
  // 新账号没有档案文件，先手写一份最小文档（与 editor_check.js 的种子同构）
  const doc = {
    account_id: acc.account_id,
    player: { player_name: '商城勇者', register_seconds: '0', player_id: acc.account_id },
    bag: { items: [], next_uuid: 1 },
    characters: [],
    gacha: { type_infos: {}, records: [], pending: null, pending_cost: 0 },
    mall: { purchase: {}, charge_point: 0, received_charge_points: [], month_card_expire: 0, month_card_last_tick: 0 },
    mail: { next_uuid: 1003, list: [] },
  };
  store.savePlayer(doc);

  const sent = [];
  const session = {
    player: store.loadPlayer(acc.account_id),
    send: (n, m, r) => sent.push({ n, m, r }),
  };
  const buy = (itemId, count = 1) => {
    sent.length = 0;
    handlers.handle('req_mall_buy')(session, { mall_item_id: itemId, mall_item_count: count });
    return sent.find((s) => s.n === 'res_mall_buy');
  };

  // ---------------- 基线：每周限购买满 2 次后被挡 ----------------
  let res = buy(WEEKLY_ITEM);
  check(res && res.r === undefined, `第一次购买成功（res_mall_buy 无错误码）`);
  res = buy(WEEKLY_ITEM);
  check(res && res.r === undefined, '第二次购买成功（limitTimes=2）');
  res = buy(WEEKLY_ITEM);
  check(res && res.r === 4, `第三次购买被限购挡下（result 4 = PURCHASE_LIMIT，实际 ${res && res.r}）`);

  // 终身限购的商品也挡（limitType=1，limitTimes=1）
  res = buy(LIFETIME_ITEM);
  check(res && res.r === undefined, '终身限购商品第一次购买成功');
  res = buy(LIFETIME_ITEM);
  check(res && res.r === 4, `终身限购商品第二次被挡（实际 ${res && res.r}）`);

  // 下发列表里带已购次数；周限购条目的 refresh_seconds 指向下次周重置
  let info = mall.buildMallListInfo(session.player);
  const weeklyEntry = info.mall_infos
    .flatMap((m) => m.mall_purchase_limit_infos).find((e) => e.mall_item_id === WEEKLY_ITEM);
  const nowSec = Math.floor(Date.now() / 1000);
  check(weeklyEntry && weeklyEntry.purchase_times === 2,
    `列表下发每周限购的已购次数（${weeklyEntry && weeklyEntry.purchase_times}）`);
  check(Number(weeklyEntry.refresh_seconds) > 0
    && Number(weeklyEntry.refresh_seconds) <= 7 * 86400,
    `周限购条目的 refresh_seconds 指向下次周重置（${weeklyEntry.refresh_seconds}）`);

  // ---------------- 跨周重置：把游标拨回上一周期再触发 ----------------
  // 惰性重置在拉列表 / 购买前发生：把 week_tick 拨到上一周期即等效「过了一周」。
  const lastWeek = mall.weeklyBoundary(nowSec) - 7 * 86400;
  session.player.mall.week_tick_seconds = lastWeek;
  store.savePlayer(session.player);
  res = buy(WEEKLY_ITEM);
  check(res && res.r === undefined, `跨过周一 04:00 后每周限购自动重置，第三次购买成功（result ${res && res.r}）`);
  check(session.player.mall.week_tick_seconds === mall.weeklyBoundary(nowSec),
    'week_tick_seconds 被推进到本周一边界');
  // 终身限购的记录不受周重置影响
  res = buy(LIFETIME_ITEM);
  check(res && res.r === 4, '终身限购不随周重置清零（仍然被挡）');

  // ---------------- weeklyBoundary 的数学：必须是周一 04:00（本地时区） ----------------
  {
    // 挑几个确定性时刻验证：2026-10-07 是周三。
    const monday0400 = new Date(2026, 9, 5, 4, 0, 0).getTime() / 1000; // 2026-10-05 周一 04:00
    const wed = new Date(2026, 9, 7, 15, 0, 0).getTime() / 1000;       // 周三 15:00
    check(mall.weeklyBoundary(wed) === monday0400, '周三的正午落在「本周一 04:00」周期');
    const mon0300 = new Date(2026, 9, 12, 3, 0, 0).getTime() / 1000;   // 下周一 03:00（04:00 之前）
    const lastMonday = new Date(2026, 9, 5, 4, 0, 0).getTime() / 1000;
    check(mall.weeklyBoundary(mon0300) === lastMonday, '周一 04:00 之前仍属于上一周期');
  }

  // ---------------- 关闭全部限购的开关 ----------------
  mall.setLimitConfig({ disabled: true });
  check(mall.limitDisabled() === true, 'setLimitConfig({disabled:true}) 立即生效（免重启）');
  res = buy(WEEKLY_ITEM);
  check(res && res.r === undefined, '限购关闭后超过 limitTimes 也能继续买');
  info = mall.buildMallListInfo(session.player);
  const limitedEntries = info.mall_infos
    .flatMap((m) => m.mall_purchase_limit_infos)
    .filter((e) => e.mall_item_id === WEEKLY_ITEM || e.mall_item_id === LIFETIME_ITEM);
  check(limitedEntries.length === 0,
    '限购关闭时列表不下发任何限购商品的已购条目（客户端解除售罄）');

  mall.setLimitConfig({ disabled: false });
  check(mall.limitDisabled() === false, '重新打开限购开关');
  const savedCfg = JSON.parse(fs.readFileSync(process.env.GHS_RUNTIME_CONFIG, 'utf8'));
  check(savedCfg.mall_limit_disabled === false, '开关状态落盘到 runtime-config.json');
  res = buy(WEEKLY_ITEM);
  check(res && res.r === 4, '开关重开后按累计购买记录恢复限购');

  console.log(failures ? `\n${failures} 项失败` : '\n全部通过');
  process.exit(failures ? 1 : 0);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
