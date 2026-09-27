// 星位系统（客户端叫 Talent / 星位，UI 上是角色页的「星位」页签）。
//
// 表与语义（全部对照客户端 Lua 与数据表实测确认）：
//   - `d_character_inborn` 是星位表，23 行/角色（roleID）。
//     `hole` = 孔位（1..23）；`frontHole` = **前置孔位**（不是 id，0 = 根节点）；
//     `openNeed` = 解锁条件类型；`openNeedPrice` = 条件参数（扁平 [a,b] 对）。
//   - `openNeed` 全表只用到两种（客户端 `UIUtils.EOpenNeedType`）：
//       30000 CharLevel → `openNeedPrice = [角色id, 等级]`，即「该角色等级 ≥ N」；
//       50004 CostItem  → `openNeedPrice = [道具id, 数量]`，即「消耗 N 个该道具」。
//     实测（以 10201 为例）：hole 1 = 30000 [10201,1]（根节点，免费）；
//     hole 2..7 = 50004 [星位之钉,1]（就是「命座」6 个孔）；hole 8..23 = 30000 [10201,10..80]。
//   - 星位之钉 = `d_character.inbornItem`（10101→1207001 … 11202→1207010，itemType 12，
//     名字如【莎乐美<礼器>】的星位之钉）。每个可玩角色一种钉。
//   - 满命判定（客户端 `CharacterSystem:GetCharacterTalentCount`）：背包里的钉数 +
//     已点亮的「50004 且消耗该钉」的星位数 ≥ 7（= 1 + 6 个命座孔）为满。
//
// 为什么必须有这个模块（坑 40）：`req_character_unlock_talent` 的请求体**只有**
// `character_id` + `talent_id`（`reference/proto/character_list.proto:158`，客户端
// `UI_Panel_TalentDetail_C.lua:295-299`），材料是客户端**自己本地扣**的
// （`CharacterSystem.lua:262-272` 直接改本地背包缓存）。所以服务端必须自己回表算
// 条件、算消耗并落盘，否则就是「客户端亮了星位、存档里什么都没有」，一重登全没。
const gd = require('../gamedata');
const items = require('./items');

// 结果码：0..4 来自 proto 的 ResCharacterUnlockTalent.ResultType，5/6 只定义在客户端
// `CharacterSystem.ErrorCode.UnlockTalent` —— 客户端就是按这套数字分支处理的，照抄。
const CODE = {
  OK: 0,
  NO_CHARACTER: 1,
  TALENT_UNLOCKED: 2,
  INVALID_TALENT_ID: 3,
  PRE_TALENT_LOCKED: 4,
  CHECK_CONDITION_FAILED: 5,
  STUFF_NOT_ENOUGH: 6,
};

const OPEN_NEED_CHAR_LEVEL = 30000;
const OPEN_NEED_COST_ITEM = 50004;

// d_character_inborn 是只读表、星位查询又很频繁（客户端一次能问几十个节点），
// 按 roleID 缓存一份排好序的行。
const rowsCache = new Map();

function rowsFor(characterId) {
  const id = Number(characterId) || 0;
  let rows = rowsCache.get(id);
  if (!rows) {
    rows = gd.rows('d_character_inborn')
      .map(([, r]) => r)
      .filter((r) => Number(r.roleID) === id)
      .sort((a, b) => Number(a.hole) - Number(b.hole));
    rowsCache.set(id, rows);
  }
  return rows;
}

// 星位配置行。给了 characterId 就一并校验归属（防止把 A 的星位点亮到 B 身上）。
function config(talentId, characterId) {
  const row = gd.query('d_character_inborn', talentId);
  if (!row) return null;
  if (characterId !== undefined && Number(row.roleID) !== Number(characterId)) return null;
  return row;
}

// 「星位之钉」道具 id（d_character.inbornItem）。
function nailItemId(characterId) {
  const cfg = gd.query('d_character', characterId);
  return cfg ? Number(cfg.inbornItem) || 0 : 0;
}

// 前置星位：frontHole 指向的是 hole，不是 id。
function prevTalent(row, characterId) {
  const hole = Number(row.frontHole) || 0;
  if (!hole) return null;
  return rowsFor(characterId).find((r) => Number(r.hole) === hole) || null;
}

// openNeedPrice 是扁平数组 [a, b, c, d, ...]。
function pairsOf(price) {
  const arr = Array.isArray(price) ? price : [];
  const out = [];
  for (let i = 0; i + 1 < arr.length; i += 2) {
    const a = Number(arr[i]);
    const b = Number(arr[i + 1]);
    if (a > 0 && b > 0) out.push([a, b]);
  }
  return out;
}

// 消耗型星位（50004）的材料清单。
function costsOf(row) {
  if (Number(row.openNeed) !== OPEN_NEED_COST_ITEM) return [];
  return pairsOf(row.openNeedPrice).map(([itemId, count]) => ({ item_id: itemId, count }));
}

// 角色等级：与客户端 `UIUtils.GetCharacterLevel(roleId, breakTimes, exp)` 同语义 ——
// 沿 `d_role_level.exp` 累进，再夹到 `d_role_levelbreak[roleId, breakTimes].level`。
function characterLevel(char) {
  const charId = char.character_id;
  let level = 1;
  let left = Number(char.exp) || 0;
  const rows = gd.rows('d_role_level').map(([, r]) => r)
    .sort((a, b) => Number(a.id) - Number(b.id));
  for (const r of rows) {
    const need = Number(r.exp) || 0;
    if (left < need) break;
    left -= need;
    level += 1;
  }
  const breakTimes = Number(char.break_times) || 0;
  let cap = 0;
  for (const [, r] of gd.rows('d_role_levelbreak')) {
    if (Number(r.roleId) !== Number(charId)) continue;
    if (Number(r.levelbreak) !== breakTimes) continue;
    cap = Number(r.level) || 0;
    break;
  }
  return cap > 0 ? Math.min(level, cap) : level;
}

// 解锁条件判定。只实现本表实际出现的两种；未知类型放行（客户端本来就自己拦，
// 服务端多拦反而会出现「客户端放行、服务端拒绝」的刷屏，见坑 7）。
//
// 注意 50004（消耗道具）**不在这里**判材料够不够：材料不足要报 STUFF_NOT_ENOUGH(6)，
// 与「条件不满足」CHECK_CONDITION_FAILED(5) 是两个不同的错误码，客户端也是分开处理的。
function conditionOk(player, char, row) {
  const need = Number(row.openNeed);
  if (need === OPEN_NEED_CHAR_LEVEL) {
    for (const [charId, lv] of pairsOf(row.openNeedPrice)) {
      if (charId === Number(char.character_id)) {
        if (characterLevel(char) < lv) return false;
        continue;
      }
      // 本表没有跨角色条件；真出现时按「拥有该角色且等级达标」处理。
      const other = (player.characters || []).find((c) => Number(c.character_id) === charId);
      if (!other || characterLevel(other) < lv) return false;
    }
    return true;
  }
  return true;
}

// 该角色全部星位 id（按孔位顺序 = 前置链的自然顺序）。
function allTalentIds(characterId) {
  return rowsFor(characterId).map((r) => Number(r.id));
}

// 已点亮 / 总数，给编辑器显示进度用。
function progress(char) {
  const ids = new Set((char.talent_ids || []).map(Number));
  const all = allTalentIds(char.character_id);
  return { unlocked: all.filter((id) => ids.has(id)).length, total: all.length };
}

// 点亮一个星位。返回 { code, ntf? }（ntf = ntf_item_info 载荷，扣材料时才有）。
function unlock(player, char, talentId) {
  const row = config(talentId, char.character_id);
  if (!row) return { code: CODE.INVALID_TALENT_ID };
  if (!Array.isArray(char.talent_ids)) char.talent_ids = [];
  const list = char.talent_ids.map(Number);
  if (list.includes(Number(talentId))) return { code: CODE.TALENT_UNLOCKED };

  const prev = prevTalent(row, char.character_id);
  if (prev && !list.includes(Number(prev.id))) return { code: CODE.PRE_TALENT_LOCKED };
  if (!conditionOk(player, char, row)) return { code: CODE.CHECK_CONDITION_FAILED };

  const costs = costsOf(row);
  let ntf = null;
  if (costs.length) {
    ntf = items.consumeItems(player, costs);
    if (!ntf) return { code: CODE.STUFF_NOT_ENOUGH };
  }
  char.talent_ids.push(Number(talentId));
  return { code: CODE.OK, ntf };
}

// 一键点亮全部星位（编辑器用）：跳过前置与消耗，直接写入完整列表。
// 顺序按孔位，保证存档里的 talent_ids 是稳定可比较的。
function unlockAll(char) {
  const ids = allTalentIds(char.character_id);
  const before = new Set((char.talent_ids || []).map(Number));
  const added = ids.filter((id) => !before.has(id));
  char.talent_ids = ids.slice();
  return added;
}

module.exports = {
  CODE, OPEN_NEED_CHAR_LEVEL, OPEN_NEED_COST_ITEM,
  rowsFor, config, nailItemId, prevTalent, costsOf, characterLevel,
  conditionOk, allTalentIds, progress, unlock, unlockAll,
};
