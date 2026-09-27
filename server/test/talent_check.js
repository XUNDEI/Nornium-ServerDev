// 星位（天赋）回归测试：req_character_unlock_talent 的结果码、星位之钉消耗、
// **写盘后重载仍在**（玩家的「星位升级后重启不保存」），以及抽卡重复角色 → 星位之钉
// 的转化口径。不需要服务端：直接建玩家文档驱动 handler。
// 必须在 require 服务端模块之前设好 GHS_DATA_DIR —— store.js 在加载时读它，
// 否则测试存档会落到真实的 server/data/（坑 35）。
const os = require('os');
const fs = require('fs');
const path = require('path');
const tmpDataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ghs-talent-'));
process.env.GHS_DATA_DIR = tmpDataDir;

const { createPlayerDoc, buildCharacter } = require('../src/game/player_new');
const charH = require('../src/handlers/character');
const gachaGame = require('../src/game/gacha');
const talent = require('../src/game/talent');
const { migratePlayer } = require('../src/game/migrate');
const items = require('../src/game/items');
const store = require('../src/store');
const gd = require('../src/gamedata');

let failures = 0;
function check(cond, msg) {
  console.log(cond ? `  PASS ${msg}` : `  FAIL ${msg}`);
  if (!cond) failures += 1;
}

const SALOME = 10201;      // 理事卿莎乐美<礼器>：inbornItem 1207002，图里那把钉
const SALOME_NAIL = 1207002;

function makeSession(accountId = 9001) {
  const player = createPlayerDoc(accountId);
  // 莎乐美不在开局二人组里，用 buildCharacter 补进来（编辑器/GM 同路径）
  player.characters.push(buildCharacter(player, SALOME));
  const sent = [];
  return { player, sent, send: (name, msg, result) => sent.push({ name, msg, result }) };
}
const last = (s, name) => [...s.sent].reverse().find((x) => x.name === name);
const codeOf = (s) => last(s, 'res_character_unlock_talent')?.result;
const unlock = (s, charId, talentId) => {
  s.sent.length = 0;
  charH.reqCharacterUnlockTalent(s, { character_id: charId, talent_id: talentId });
  return codeOf(s);
};
const count = (s, id) => items.bagCount(s.player, id);
const charOf = (s, id) => s.player.characters.find((c) => c.character_id === id);

// ---------------- 数据表口径 ----------------
{
  const rows = talent.rowsFor(SALOME);
  check(rows.length === 23, `莎乐美有 23 个星位（实际 ${rows.length}）`);
  check(Number(rows[0].id) === 1020101 && Number(rows[0].frontHole) === 0, 'hole 1 是根节点（frontHole 0）');
  const nailHoles = rows.filter((r) => talent.costsOf(r).length);
  check(nailHoles.length === 6, `6 个「命座」孔消耗星位之钉（实际 ${nailHoles.length}）`);
  check(nailHoles.every((r) => talent.costsOf(r)[0].item_id === SALOME_NAIL),
    `命座孔消耗的是莎乐美的钉 ${SALOME_NAIL}`);
  check(talent.nailItemId(10101) === 1207001 && talent.nailItemId(11202) === 1207010,
    'd_character.inbornItem 映射正确（10101→1207001，11202→1207010）');
  check(talent.prevTalent(rows[1], SALOME).id === 1020101, 'frontHole 指向的是 hole 而不是 id');
}

// ---------------- 解锁流程与错误码 ----------------
{
  const s = makeSession();
  const char = charOf(s, SALOME);
  check(Array.isArray(char.talent_ids) && char.talent_ids.length === 0, '新号星位为空');

  check(unlock(s, SALOME, 1020101) === talent.CODE.OK, '根节点星位可以点亮（无条件）');
  check(!last(s, 'ntf_item_info'), '根节点不消耗道具（没有 ntf_item_info）');
  check(last(s, 'ntf_character_info'), '点亮后下发 ntf_character_info');

  check(unlock(s, SALOME, 1020101) === talent.CODE.TALENT_UNLOCKED, '重复点亮 -> TALENT_UNLOCKED(2)');
  check(unlock(s, SALOME, 1020103) === talent.CODE.PRE_TALENT_LOCKED, '跳过前置 -> PRE_TALENT_LOCKED(4)');
  check(unlock(s, SALOME, 1020102) === talent.CODE.STUFF_NOT_ENOUGH, '没有星位之钉 -> STUFF_NOT_ENOUGH(6)');
  check(unlock(s, SALOME, 1010101) === talent.CODE.INVALID_TALENT_ID, '别的角色的星位 -> INVALID_TALENT_ID(3)');
  check(unlock(s, SALOME, 99999999) === talent.CODE.INVALID_TALENT_ID, '不存在的星位 -> INVALID_TALENT_ID(3)');
  check(unlock(s, 11202, 1020101) === talent.CODE.INVALID_TALENT_ID, '把 A 的星位点到 B 身上 -> INVALID_TALENT_ID(3)');
  check(unlock(s, 99999, 1020101) === talent.CODE.NO_CHARACTER, '不存在的角色 -> NO_CHARACTER(1)');

  // 6 个命座孔：每点一个消耗 1 把钉（不是每个 1 把共 6 把）
  items.grantItems(s.player, [{ item_id: SALOME_NAIL, count: 6 }]);
  for (let hole = 2; hole <= 7; hole += 1) {
    const tid = talent.rowsFor(SALOME)[hole - 1].id;
    check(unlock(s, SALOME, tid) === talent.CODE.OK, `命座孔 hole ${hole} 点亮成功`);
  }
  check(count(s, SALOME_NAIL) === 0, `6 个命座孔共消耗 6 把钉（剩 ${count(s, SALOME_NAIL)}）`);
  check(charOf(s, SALOME).talent_ids.length === 7, `已点亮 7 个星位（1 根 + 6 命座）`);
  // 满命判定与客户端 CharacterSystem:GetCharacterTalentCount 逐字同语义：
  //   背包里该角色的钉数 + 已点亮的「消耗该钉」星位数 + 1 >= 7
  const nailHolesLit = charOf(s, SALOME).talent_ids.filter((id) => {
    const row = talent.config(id, SALOME);
    return row && talent.costsOf(row).some((c) => c.item_id === SALOME_NAIL);
  }).length;
  const fullCount = count(s, SALOME_NAIL) + nailHolesLit;
  check(nailHolesLit === 6, `已点亮的命座孔恰好 6 个（实际 ${nailHolesLit}）`);
  check(fullCount + 1 >= 7, `满命口径成立：钉 ${count(s, SALOME_NAIL)} + 命座孔 ${nailHolesLit} + 1 >= 7`);

  // 等级门（hole 9 需要角色 Lv.10）
  const lv10 = talent.rowsFor(SALOME).find((r) => Number(r.hole) === 9).id;
  check(unlock(s, SALOME, lv10) === talent.CODE.CHECK_CONDITION_FAILED, '等级不够 -> CHECK_CONDITION_FAILED(5)');
  charOf(s, SALOME).exp = 99999999; // 直接把经验拉到上限（等级换算再由突破夹取）
  charOf(s, SALOME).break_times = 5;
  check(talent.characterLevel(charOf(s, SALOME)) === 80, `经验拉满 + 突破 5 -> Lv.80（实际 ${talent.characterLevel(charOf(s, SALOME))}）`);
  check(unlock(s, SALOME, lv10) === talent.CODE.OK, '等级达标后同一星位可以点亮');
}

// ---------------- 持久化：这才是「重启不保存」的回归点 ----------------
{
  const s = makeSession(9010);
  items.grantItems(s.player, [{ item_id: SALOME_NAIL, count: 3 }]);
  unlock(s, SALOME, 1020101);
  unlock(s, SALOME, 1020102);
  unlock(s, SALOME, 1020103);
  store.savePlayer(s.player);

  const reloaded = store.loadPlayer(9010); // 等价于服务端重启后重新读档
  const char = reloaded.characters.find((c) => c.character_id === SALOME);
  check(Array.isArray(char.talent_ids) && char.talent_ids.length === 3,
    `重载后仍是 3 个已点亮星位（实际 ${char.talent_ids && char.talent_ids.length}）`);
  check(char.talent_ids.includes(1020102) && char.talent_ids.includes(1020103),
    '重载后命座孔仍在（过去这里恒为空 → 玩家的星位升级消失）');
  check(items.bagCount(reloaded, SALOME_NAIL) === 1, '重载后星位之钉只被扣掉 2 把');
  // res_character_list 原样下发 characters（handlers/sync.js），所以 down 到客户端的
  // talent_ids 就是磁盘里这份 —— 再点亮一次必须报「已点亮」而不是重新扣材料。
  const replay = makeSession(9010);
  replay.player = reloaded;
  check(unlock(replay, SALOME, 1020102) === talent.CODE.TALENT_UNLOCKED,
    '重载后重复点亮同一星位 -> TALENT_UNLOCKED(2)，不会再扣钉');
}

// ---------------- 一键点亮（编辑器口径） ----------------
{
  const s = makeSession();
  const char = charOf(s, SALOME);
  const added = talent.unlockAll(char);
  check(added.length === 23, `一键点亮补了 23 个星位（实际 ${added.length}）`);
  check(talent.unlockAll(char).length === 0, '一键点亮是幂等的');
  const p = talent.progress(char);
  check(p.unlocked === 23 && p.total === 23, `进度显示 23/23（实际 ${p.unlocked}/${p.total}）`);
}

// ---------------- 抽卡重复角色 → 星位之钉 ----------------
{
  const s = makeSession();
  // 记录里的 gacha_item_id 是 d_gacha_item 的**行 id**（d_gacha_pool.gachaItemId 就是它），
  // 不是行里的 itemid —— 别搞混（搞混时 itemCfg 查不到，抽卡会静默什么都不发）。
  const record = (row) => ({
    gacha_seconds: '0', gacha_item_id: row.id, gacha_item_type: row.itemType,
    gacha_item_rarity: row.rarity, pool_index: 0, ding: false,
  });
  const gachaRows = () => gd.rows('d_gacha_item').map(([, r]) => r);
  const salomeRow = gachaRows().find((r) => r.itemType === 1 && gachaGame.characterIdOfGachaItem(r.itemid) === SALOME);
  check(!!salomeRow, `找到莎乐美的角色池行（gacha_item id ${salomeRow && salomeRow.id}）`);
  const golden0 = count(s, 9006);   // 珊瑚劫灰

  // 第 2 次获得（已拥有 → 第一次重复）→ 该角色的钉 ×1 + 珊瑚劫灰 ×20
  gachaGame.grantRecords(s, [record(salomeRow)]);
  check(count(s, SALOME_NAIL) === 1, `重复角色给 1 把星位之钉（实际 ${count(s, SALOME_NAIL)}）`);
  check(count(s, 9006) === golden0 + 20, `重复角色给珊瑚劫灰 ×20（实际 +${count(s, 9006) - golden0}）`);
  check(s.player.gacha.char_obtain_times[SALOME] === 2, `获得次数记为 2（实际 ${s.player.gacha.char_obtain_times[SALOME]}）`);

  // 第 8 次及以后只给珊瑚劫灰 ×50
  s.player.gacha.char_obtain_times[SALOME] = 7;
  const goldenBefore = count(s, 9006);
  const nailBefore = count(s, SALOME_NAIL);
  gachaGame.grantRecords(s, [record(salomeRow)]);
  check(count(s, SALOME_NAIL) === nailBefore, '第 8 次不再给星位之钉');
  check(count(s, 9006) === goldenBefore + 50, `第 8 次起给珊瑚劫灰 ×50（实际 +${count(s, 9006) - goldenBefore}）`);

  // 武器 / 家具也按官方口径给转化货币（d_gacha_token itemType 3 / 4）
  const weaponRow = gachaRows().find((r) => r.itemType === 10 && r.rarity === 6);
  const g0 = count(s, 9006);
  gachaGame.grantRecords(s, [record(weaponRow)]);
  check(count(s, 9006) === g0 + 20, `6★ 武器给珊瑚劫灰 ×20（实际 +${count(s, 9006) - g0}）`);

  // 一次十连里出现两个同一个「新角色」：只建一个角色，第二次按重复给钉
  const s2 = makeSession();
  const target = gachaRows().find((r) => r.itemType === 1 && r.rarity === 6);
  const cid = gachaGame.characterIdOfGachaItem(target.itemid);
  s2.player.characters = s2.player.characters.filter((c) => c.character_id !== cid);
  gachaGame.grantRecords(s2, [record(target), record(target)]);
  const dupes = s2.player.characters.filter((c) => c.character_id === cid);
  check(dupes.length === 1, `同一批里重复抽到新角色只建 1 个角色对象（实际 ${dupes.length}）`);
  check(count(s2, talent.nailItemId(cid)) === 1,
    `第二个同角色按重复处理，给了角色 ${cid} 的星位之钉 ${talent.nailItemId(cid)}`);

  // 全新角色（未拥有）第一次获得不给钉
  const s3 = makeSession();
  s3.player.characters = s3.player.characters.filter((c) => c.character_id !== cid);
  gachaGame.grantRecords(s3, [record(target)]);
  check(count(s3, talent.nailItemId(cid)) === 0, '首次获得某角色不给星位之钉');
}

// ---------------- 迁移 ----------------
{
  const doc = createPlayerDoc(9011);
  doc.characters.push(buildCharacter(doc, SALOME)); // 莎乐美不在开局二人组里
  for (const c of doc.characters) delete c.talent_ids;
  delete doc.gacha.char_obtain_times;
  const changed = migratePlayer(doc);
  check(changed === true, '迁移对缺字段的老存档报告改动');
  check(doc.characters.every((c) => Array.isArray(c.talent_ids)), '迁移补齐 characters[].talent_ids');
  check(doc.gacha.char_obtain_times && typeof doc.gacha.char_obtain_times === 'object',
    '迁移补齐 gacha.char_obtain_times');
  check(migratePlayer(doc) === false, '迁移是幂等的');
  const s = makeSession(9011);
  s.player = doc;
  check(unlock(s, SALOME, 1020101) === talent.CODE.OK, '迁移后的老存档可以正常点亮星位');
}

fs.rmSync(tmpDataDir, { recursive: true, force: true });
console.log(failures === 0 ? '\nTALENT CHECKS PASSED' : `\n${failures} TALENT CHECKS FAILED`);
process.exit(failures === 0 ? 0 : 1);
