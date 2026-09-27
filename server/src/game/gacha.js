// Gacha system over d_gacha_* tables.
// list_id = d_gacha_schedule.gachaId = d_gacha_list key; gachaType maps 0 -> 3.
// Roll: rarity by totalWeight, then pool by [poolId, weight] pairs; UP pool
// competes with its own weight (upBaseWeight, upSoftWeight past upSoftTime),
// hard pity at guaranteedTime.
const gd = require('../gamedata');
const items = require('./items');

const ALL_SCHEDULES_OPEN = true; // private server: every pool pullable

function gachaTypeOf(listId) {
  const cfg = gd.query('d_gacha_list', listId);
  const t = cfg ? (cfg.gachaType ?? 0) : 0;
  return t === 0 ? 3 : t;
}

function inSchedule(listId) {
  if (ALL_SCHEDULES_OPEN) return true;
  const row = gd.rows('d_gacha_schedule').map(([, r]) => r).find((r) => r.gachaId === Number(listId));
  return !!row;
}

function typeState(player, typeId) {
  player.gacha.type_infos[typeId] = player.gacha.type_infos[typeId] || {
    no_up_times: 0, no_5p_times: 0, total_times: 0, free_seconds: 0, choose_times: 0, records: [],
  };
  return player.gacha.type_infos[typeId];
}

function buildGachaInfo(player) {
  const gacha_type_infos = [];
  for (const typeId of [1, 2, 3, 4]) {
    const st = player.gacha.type_infos[typeId];
    gacha_type_infos.push({
      type_id: typeId,
      no_up_times: st?.no_up_times ?? 0,
      no_5p_times: st?.no_5p_times ?? 0,
      total_times: st?.total_times ?? 0,
      free_seconds: String(st?.free_seconds ?? 0),
      choose_times: st?.choose_times ?? 0,
      gacha_record_infos: st?.records ?? [],
    });
  }
  const gacha_list_infos = Object.entries(player.gacha.pending).map(([listId, records]) => ({
    list_id: Number(listId),
    gacha_pending_record_infos: records,
  }));
  return {
    gacha_type_infos,
    gacha_list_infos,
    // 0 = d_gacha_list.gachaType 0（池 3：空壳占位行，guaranteedTime=0 无任何权重）。
    // 客户端 IsFinished 按 gachaType 匹配，置 0 即隐藏这个重复的"常驻"页签——
    // 否则该页签显示 0 - no_up_times 的负数保底倒计时。真常驻池是 gachaId 1（gachaType 3）。
    finished_type_ids: [0, ...(player.gacha.finished || [])],
    sit_character_ids: [],
  };
}

function pickWeighted(pairs) {
  // pairs: flat [poolId, weight, poolId, weight, ...]
  let total = 0;
  for (let i = 1; i < pairs.length; i += 2) total += pairs[i];
  let r = Math.random() * total;
  for (let i = 0; i < pairs.length; i += 2) {
    r -= pairs[i + 1];
    if (r <= 0) return pairs[i];
  }
  return pairs[pairs.length - 2];
}

function pickFromPool(poolId) {
  const rows = gd.rows('d_gacha_pool').map(([, r]) => r).filter((r) => r.poolId === poolId);
  if (!rows.length) return null;
  let total = 0;
  for (const r of rows) total += r.weight ?? 1;
  let r = Math.random() * total;
  for (const row of rows) {
    r -= row.weight ?? 1;
    if (r <= 0) return row.gachaItemId;
  }
  return rows[rows.length - 1].gachaItemId;
}

function rollOnce(player, cfg, st) {
  const now = Math.floor(Date.now() / 1000);
  // no_up_times 语义（与客户端 GachaSystem.lua:222-227 一致）：
  // 距上次 UP 6★ 的累计抽数——每次抽卡（无论出什么）+1，抽到 UP 6★ 重置为 0。
  // 硬保底：本次抽取前计数 +1 >= guaranteedTime 时强制出 UP。
  const before = st.no_up_times ?? 0;
  const guaranteed = before + 1 >= (cfg.guaranteedTime ?? 100);

  const total = cfg.totalWeight ?? 10000;
  const w6 = cfg.rarity6Weight ?? 0;
  const w5 = cfg.rarity5Weight ?? 0;
  const r = Math.random() * total;

  let rarity;
  if (guaranteed) rarity = 6; // 硬保底：这一抽必出 6★（再经 up 判定强制 UP）
  else if (r < w6) rarity = 6;
  else if (r < w6 + w5) rarity = 5;
  else rarity = 4;

  let gachaItemId = null;
  let isUp = false;
  if (rarity === 6) {
    const upWeight = before >= (cfg.upSoftTime ?? 0) ? (cfg.upSoftWeight ?? 0) : (cfg.upBaseWeight ?? 0);
    const others = [].concat(cfg.rarity6pool ?? []);
    let totalUp = upWeight;
    for (let i = 1; i < others.length; i += 2) totalUp += others[i];
    let ur = Math.random() * totalUp;
    if (guaranteed) ur = -1; // force UP
    if (ur < upWeight) {
      isUp = true;
      gachaItemId = pickFromPool(cfg.upPool);
    } else {
      ur -= upWeight;
      const poolId = pickWeighted(others);
      gachaItemId = pickFromPool(poolId);
    }
    st.no_up_times = isUp ? 0 : before + 1;
  } else {
    st.no_up_times = before + 1;
  }
  if (rarity === 5) {
    gachaItemId = pickFromPool(pickWeighted([].concat(cfg.rarity5pool ?? [])));
    st.no_5p_times = 0;
  } else if (rarity === 4) {
    gachaItemId = pickFromPool(pickWeighted([].concat(cfg.rarity4pool ?? [])));
    st.no_5p_times = (st.no_5p_times ?? 0) + 1;
  }
  st.total_times = (st.total_times ?? 0) + 1;

  const itemCfg = gd.query('d_gacha_item', gachaItemId) || {};
  return {
    gacha_seconds: String(now),
    gacha_item_id: gachaItemId,
    gacha_item_type: itemCfg.itemType ?? 0,
    gacha_item_rarity: itemCfg.rarity ?? rarity,
    pool_index: isUp ? 0 : (rarity === 6 ? 1 : (rarity === 5 ? 2 : 3)),
    ding: false,
  };
}

// charId from a gacha character itemid: 6 + (charId-10000)*100 + variant
function characterIdOfGachaItem(itemid) {
  return 10000 + Math.floor((itemid % 1000000) / 100);
}

// d_gacha_token：重复/溢出产物的转化表。itemType 用的是「产出的语义类别」，
// 与 d_gacha_item.itemType 不是同一套编号：
//   1 = 重复角色（第 2~7 次）  2 = 重复角色（第 8 次起）
//   3 = 武器                  4 = 家具
// 实测：6★ 武器/家具 → 珊瑚劫灰 20；5★ → 5；4★ → 时枝化石 20；3★ → 10。
function gachaToken(rarity, tokenType) {
  return gd.rows('d_gacha_token').map(([, r]) => r)
    .find((r) => Number(r.rarity) === Number(rarity) && Number(r.itemType) === Number(tokenType)) || null;
}

function tokenGrants(token) {
  const out = [];
  if (!token) return out;
  if (Number(token.goldenToken) > 0) out.push({ item_id: items.CURRENCY.GACHA_HIGH, count: Number(token.goldenToken) });
  if (Number(token.silverToken) > 0) out.push({ item_id: items.CURRENCY.GACHA_LOW, count: Number(token.silverToken) });
  return out;
}

// 「同一角色被获得的次数」——同一角色的不同幻形算同一角色（d_word_cn 1904 的说明）。
// 老存档/新号一开始没有这个计数，按「已经拥有 = 已获得 1 次」起步，于是第一次重复就
// 落到第 2 次 → 给星位之钉，符合官方口径。
function obtainTimes(player, charId, bump) {
  const box = player.gacha.char_obtain_times || (player.gacha.char_obtain_times = {});
  const owned = (player.characters || []).some((c) => Number(c.character_id) === Number(charId));
  let n = Number(box[charId]);
  if (!Number.isFinite(n) || n <= 0) n = owned ? 1 : 0;
  if (bump) n += 1;
  box[charId] = n;
  return n;
}

// Apply a confirmed record batch to the player: returns list of summary strings.
function grantRecords(session, records) {
  const grants = [];
  const newChars = [];
  for (const rec of records) {
    const itemCfg = gd.query('d_gacha_item', rec.gacha_item_id);
    if (!itemCfg) continue;
    if (itemCfg.itemType === 1) {
      const charId = characterIdOfGachaItem(itemCfg.itemid);
      // 同一批十连里出两个同一个新角色也算「重复」，别把他加成两个角色对象。
      const already = session.player.characters.find((c) => c.character_id === charId)
        || newChars.find((c) => c.character_id === charId);
      if (already) {
        // 重复角色：第 2~7 次 → 该角色的【星位之钉】×1 + 珊瑚劫灰×20；
        // 第 8 次及以后 → 珊瑚劫灰×50（d_word_cn 1904）。星位之钉 id = d_character.inbornItem。
        const times = obtainTimes(session.player, charId, true);
        if (times <= 7) {
          const nail = require('./talent').nailItemId(charId);
          if (nail) grants.push({ item_id: nail, count: 1 });
          for (const g of tokenGrants(gachaToken(itemCfg.rarity, 1))) grants.push(g);
        } else {
          for (const g of tokenGrants(gachaToken(itemCfg.rarity, 2))) grants.push(g);
        }
      } else {
        obtainTimes(session.player, charId, true);
        const { buildCharacter } = require('./player_new');
        newChars.push(buildCharacter(session.player, charId));
      }
    } else {
      grants.push({ item_id: itemCfg.itemid, count: 1 });
      // 武器（10）/家具（93）也按官方口径给转化货币（每件都给，重复与否都算获得）。
      const tokenType = itemCfg.itemType === 10 ? 3 : (itemCfg.itemType === 93 ? 4 : 0);
      if (tokenType) for (const g of tokenGrants(gachaToken(itemCfg.rarity, tokenType))) grants.push(g);
    }
  }
  const ntfs = [];
  if (grants.length) ntfs.push(items.grantItems(session.player, grants));
  for (const c of newChars) {
    session.player.characters.push(c);
    session.send('ntf_character_info', { changed_character_infos: [c] });
  }
  return ntfs;
}

module.exports = {
  gachaTypeOf, inSchedule, typeState, buildGachaInfo, rollOnce, grantRecords,
  characterIdOfGachaItem, pickFromPool,
};
