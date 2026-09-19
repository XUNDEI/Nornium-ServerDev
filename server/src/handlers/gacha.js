// Gacha message handlers: create (pre-roll) -> confirm (consume + grant),
// ding (convert a 6-star non-UP into the UP item), choose_card (200-pull bonus).
const gd = require('../gamedata');
const items = require('../game/items');
const { savePlayer, requirePlayer } = require('./sync');
const gacha = require('../game/gacha');

function handleCreate(session, req) {
  if (!requirePlayer(session)) return;
  const listId = Number(req.list_id ?? 0);
  const times = Number(req.times ?? 1);
  // 池 3 是空壳占位行（真常驻池是 gachaId 1）；万一有请求打到它，按池 1 处理
  const effectiveListId = listId === 3 ? 1 : listId;
  const cfg = gd.query('d_gacha_list', effectiveListId);
  if (!cfg || !gacha.inSchedule(effectiveListId)) {
    return session.send('res_gacha_create', {}, gacha.inSchedule(effectiveListId) ? 3 : 1);
  }
  if (times !== 1 && times !== 10) return session.send('res_gacha_create', {}, 6);
  const typeId = gacha.gachaTypeOf(listId);
  const st = gacha.typeState(session.player, typeId);

  // pending on same pool must be confirmed first
  if (session.player.gacha.pending[listId]?.length) {
    return session.send('res_gacha_create', {}, 7); // PENDING_CONFIRM
  }

  // newbie pool (ticket 0) counts pulls instead of tickets
  let freePull = false;
  if (!cfg.ticket) {
    if (st.total_times + times > (cfg.guaranteedTime ?? 500)) {
      // newbie pool exhausted
      session.player.gacha.finished = session.player.gacha.finished || [];
      if (!session.player.gacha.finished.includes(typeId)) session.player.gacha.finished.push(typeId);
      return session.send('res_gacha_create', {}, 5); // LIST_FINISHED
    }
  } else {
    const owned = items.bagCount(session.player, cfg.ticket);
    const now = Math.floor(Date.now() / 1000);
    if (typeId === 3 && times === 1 && dailyFreeAvailable(st.free_seconds ?? 0, now)) {
      freePull = true;
    } else if (owned < times) {
      return session.send('res_gacha_create', {}, 4); // RES_NOT_ENOUGH
    }
  }

  const records = [];
  for (let i = 0; i < times; i++) records.push(gacha.rollOnce(session.player, cfg, st));
  session.player.gacha.pending[listId] = records;
  session.player.gacha.pending_cost = session.player.gacha.pending_cost || {};
  session.player.gacha.pending_cost[listId] = {
    ticket: freePull ? 0 : (cfg.ticket ?? 0) * times,
    times,
    typeId,
  };
  if (freePull) st.free_seconds = String(Math.floor(Date.now() / 1000));

  session.send('res_gacha_create', {
    gacha_pending_record_infos: records,
    free_seconds: String(st.free_seconds ?? 0),
  });
  savePlayer(session);
}

function dailyFreeAvailable(freeSeconds, now) {
  if (!freeSeconds) return true;
  const ref = new Date(now * 1000);
  const today4 = new Date(ref.getFullYear(), ref.getMonth(), ref.getDate(), 4, 0, 0).getTime() / 1000;
  return freeSeconds < today4;
}

function handleConfirm(session, req) {
  if (!requirePlayer(session)) return;
  const listId = Number(req.list_id ?? 0);
  const records = session.player.gacha.pending[listId];
  const cost = (session.player.gacha.pending_cost || {})[listId];
  if (!records || !records.length) return session.send('res_gacha_confirm', {}, 3); // NO_PENDING
  if (cost && cost.ticket > 0) {
    const ticketId = gd.query('d_gacha_list', listId)?.ticket;
    if (ticketId) {
      const ntfCost = items.consumeItems(session.player, [{ item_id: ticketId, count: cost.ticket }]);
      if (ntfCost) session.send('ntf_item_info', ntfCost);
      // tickets vanished mid-flow — still grant (private server leniency)
    }
  }
  const ntfs = gacha.grantRecords(session, records);
  for (const ntf of ntfs) session.send('ntf_item_info', ntf);

  // history: keep last 50 per type
  const st = gacha.typeState(session.player, cost?.typeId ?? gacha.gachaTypeOf(listId));
  st.records = [...(st.records || []), ...records].slice(-50);

  delete session.player.gacha.pending[listId];
  delete session.player.gacha.pending_cost[listId];
  session.send('res_gacha_confirm', {});
  savePlayer(session);
}

function handleDing(session, req) {
  if (!requirePlayer(session)) return;
  const listId = Number(req.list_id ?? 0);
  const index = Number(req.item_index ?? 0);
  const records = session.player.gacha.pending[listId];
  const cfg = gd.query('d_gacha_list', listId);
  if (!records || !records[index]) return session.send('res_gacha_ding', {}, 4); // NO_PENDING
  const rec = records[index];
  if (rec.ding || rec.pool_index !== 1 || !cfg?.upPool) {
    return session.send('res_gacha_ding', {}, 6); // INVALID_RECORD
  }
  const upItemId = gacha.pickFromPool(cfg.upPool);
  const itemCfg = gd.query('d_gacha_item', upItemId) || {};
  rec.gacha_item_id = upItemId;
  rec.gacha_item_type = itemCfg.itemType ?? rec.gacha_item_type;
  rec.gacha_item_rarity = itemCfg.rarity ?? rec.gacha_item_rarity;
  rec.pool_index = 0;
  rec.ding = true;
  session.send('res_gacha_ding', { gacha_record_info: rec });
  savePlayer(session);
}

function handleChooseCard(session, req) {
  if (!requirePlayer(session)) return;
  const listId = Number(req.list_id ?? 0);
  const cfg = gd.query('d_gacha_list', listId);
  const typeId = cfg ? gacha.gachaTypeOf(listId) : 0;
  const st = gacha.typeState(session.player, typeId);
  if (st.choose_times !== 0 || (st.total_times ?? 0) < 200) {
    return session.send('res_gacha_choose_card', {}, 5); // NO_TIMES
  }
  const params = gd.query('d_gacha_params', 2);
  const options = (params && Array.isArray(params.value)) ? params.value : [];
  const pick = Number(req.item_index ?? 0);
  const gachaItemId = options[pick] ?? options[0];
  const itemCfg = gd.query('d_gacha_item', gachaItemId);
  st.choose_times = 1;
  session.send('res_gacha_choose_card', {});
  if (itemCfg) {
    const ntfs = gacha.grantRecords(session, [{
      gacha_seconds: String(Math.floor(Date.now() / 1000)),
      gacha_item_id: gachaItemId,
      gacha_item_type: itemCfg.itemType,
      gacha_item_rarity: itemCfg.rarity,
      pool_index: 0,
      ding: false,
    }]);
    for (const ntf of ntfs) session.send('ntf_item_info', ntf);
  }
  savePlayer(session);
}

function handle(name) {
  const map = {
    req_gacha_create: handleCreate,
    req_gacha_confirm: handleConfirm,
    req_gacha_ding: handleDing,
    req_gacha_choose_card: handleChooseCard,
  };
  return map[name] ?? null;
}

module.exports = { handle };
