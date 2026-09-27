// 角色武器相关的回归断言（无需服务端）：
//   ① 角色武器类型（d_character.profession）与 d_bag_item_weapon.subType 的一致性；
//   ② req_character_equip_weapon / req_character_swap_weapon 的类型校验；
//   ③ 老存档 item_uuid 重复的去重迁移；
//   ④ 「装错武器类型的角色」的迁移修复（莎乐美那把枪，见坑 37）；
//   ⑤ 「未实装武器」（客户端没有模型/图标/技能行的幽灵武器，如 1081601 颂歌）：
//      发放清单不含它们、推荐武器不指向它们、存档里已有的原地换掉（见坑 38）。
// 必须在 require 服务端模块之前设好 GHS_DATA_DIR：store.js 在加载时读它，
// 否则 savePlayer 会写进真实的 server/data/（坑 35）。
const os = require('os');
const fs = require('fs');
const path = require('path');
const tmpDataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ghs-weapon-'));
process.env.GHS_DATA_DIR = tmpDataDir;

const gd = require('../src/gamedata');
const items = require('../src/game/items');
const charH = require('../src/handlers/character');
const { migratePlayer } = require('../src/game/migrate');
const { createPlayerDoc, initialCharacterIds, buildCharacter } = require('../src/game/player_new');

let failures = 0;
function check(cond, msg) {
  console.log(cond ? `  PASS ${msg}` : `  FAIL ${msg}`);
  if (!cond) failures += 1;
}

function makeSession(accountId = 9101) {
  const player = createPlayerDoc(accountId);
  const sent = [];
  return { player, sent, send: (name, msg, result) => sent.push({ name, msg, result }) };
}
const last = (s, name) => [...s.sent].reverse().find((x) => x.name === name);
const charOf = (s, id) => s.player.characters.find((c) => c.character_id === id);

// 莎乐美：角色 10201，武器类型 5（礼器），初始武器 4010100。
const SALOME = 10201;
const SALOME_WEAPON_TYPE = 5;
const GUN = 2020400;        // 枪械（subType 4），4★
const SACRED_LOW = 4011300; // 礼器（subType 5），3★
const SACRED_TOP = 4072601; // 礼器（subType 5），6★  —— 莎乐美的专武档位

// ---------------- ① 表一致性 ----------------
check(items.characterWeaponType(SALOME) === SALOME_WEAPON_TYPE,
  `d_character[${SALOME}].profession = ${SALOME_WEAPON_TYPE}（礼器）`);
check(items.weaponType(GUN) === 4 && items.weaponType(SACRED_TOP) === 5,
  'weaponType(): 2020400=枪械(4)、4072601=礼器(5)');
{
  let bad = [];
  for (const [, row] of gd.rows('d_character')) {
    if (!row.firstWeapon || !items.characterWeaponType(row.id)) continue;
    if (items.weaponType(row.firstWeapon) !== items.characterWeaponType(row.id)) {
      bad.push(`${row.id}: profession=${items.characterWeaponType(row.id)} firstWeapon=${row.firstWeapon}(type ${items.weaponType(row.firstWeapon)})`);
    }
  }
  check(bad.length === 0,
    `每个角色的 firstWeapon 类型都等于 profession（便于迁移兜底）${bad.length ? ' 例外: ' + bad.join('; ') : ''}`);
}
{
  // v0.2.0 起新号只发开局小队（player_new.starterCharacterIds），这里就检查
  // createPlayerDoc 实际给出的那批角色。
  const fresh = createPlayerDoc(9001);
  check(fresh.characters.length === fresh.characters.filter((c) => items.weaponType(c.weapon_info.item_id) === items.characterWeaponType(c.character_id)).length,
    '新号送出的初始武器类型全部与角色匹配');
}

// ---------------- ② 装备武器校验 ----------------
{
  const s = makeSession();
  s.player.characters.push(buildCharacter(s.player, SALOME));
  const c = charOf(s, SALOME);
  const before = c.weapon_info.item_id;
  const gun = items.makeItem(s.player, GUN, 1);
  s.player.bag.items.push(gun);
  charH.reqCharacterEquipWeapon(s, { character_id: SALOME, item_uuid: gun.item_uuid });
  check(last(s, 'res_character_equip_weapon').result === 3,
    '装错武器类型 -> INVALID_ITEM(3)');
  check(c.weapon_info.item_id === before, '拒绝后角色仍持有原武器');
  check(s.player.bag.items.some((i) => Number(i.item_uuid) === Number(gun.item_uuid)),
    '拒绝后错类型武器仍留在背包里（没有被吞掉）');
}
{
  const s = makeSession();
  s.player.characters.push(buildCharacter(s.player, SALOME));
  const c = charOf(s, SALOME);
  const before = c.weapon_info.item_id;
  const good = items.makeItem(s.player, SACRED_TOP, 1);
  s.player.bag.items.push(good);
  charH.reqCharacterEquipWeapon(s, { character_id: SALOME, item_uuid: good.item_uuid });
  check(last(s, 'res_character_equip_weapon').result === undefined,
    '装同类型武器 -> OK');
  check(c.weapon_info.item_id === SACRED_TOP, '同类型武器装备成功');
  check(s.player.bag.items.some((i) => i.item_id === before),
    '被换下的旧武器回到背包');
}
{
  const s = makeSession();
  s.player.characters.push(buildCharacter(s.player, SALOME));
  charH.reqCharacterEquipWeapon(s, { character_id: SALOME, item_uuid: 987654321 });
  check(last(s, 'res_character_equip_weapon').result === 2,
    '未知 uuid -> NO_ITEM(2)');
}

// ---------------- 交换武器校验 ----------------
{
  const s = makeSession();
  // 10101 与 10601（枪械=4）类型不同，且都不在开局二人组里，用
  // buildCharacter 补进来（等价于编辑器/GM 发放路径）。
  s.player.characters.push(buildCharacter(s.player, 10101));
  s.player.characters.push(buildCharacter(s.player, 10601));
  charH.reqCharacterSwapWeapon(s, { character_id: 10101, other_character_id: 10601 });
  check(last(s, 'res_character_swap_weapon').result === 3,
    '不同类型角色之间交换武器 -> INVALID_ITEM(3)');
  check(charOf(s, 10101).weapon_info.item_id === 3011100
    && charOf(s, 10601).weapon_info.item_id === 2011100,
    '拒绝后两边的武器都没有被动过');
}
{
  const s = makeSession();
  // 10801 / 11202 都是浮塔(7)
  s.player.characters.push(buildCharacter(s.player, 10801));
  s.player.characters.push(buildCharacter(s.player, 11202));
  charH.reqCharacterSwapWeapon(s, { character_id: 10801, other_character_id: 11202 });
  check(last(s, 'res_character_swap_weapon').result === undefined,
    '同类型角色之间交换武器 -> OK');
  check(charOf(s, 10801).weapon_info.item_id === 7010100
    && charOf(s, 11202).weapon_info.item_id === 7010100,
    '同型武器的交换结果正确');
}

// ---------------- ③ uuid 去重迁移 ----------------
{
  const doc = createPlayerDoc(9102);
  // 造出一份「老存档」：一件枪械先入包拿到 uuid X，随后礼器专武复用同一个 uuid X，
  // 且莎乐美正穿着另一个相同 uuid 的武器 —— 正是线上那份存档的形状。
  const gun = items.makeItem(doc, GUN, 1);
  doc.bag.items.push(gun);
  const shared = Number(gun.item_uuid);
  const sacred = items.makeItem(doc, SACRED_TOP, 1);
  sacred.item_uuid = shared;
  doc.bag.items.push(sacred);
  doc.characters.push(buildCharacter(doc, SALOME)); // 不在开局二人组里
  const salome = doc.characters.find((c) => c.character_id === SALOME);
  salome.weapon_info.item_uuid = shared;

  // 复现故障：按 uuid 找武器只会命中数组里第一件（枪械）
  const firstHit = doc.bag.items.find((it) => Number(it.item_uuid) === shared && items.itemKind(it.item_id) === 'weapon');
  check(firstHit.item_id === GUN, '前置：重复 uuid 下按 uuid 命中数组里第一件（枪械）');

  const changed = migratePlayer(doc);
  check(changed === true, 'uuid 重复的存档迁移会上报改动');
  const all = [...doc.bag.items];
  for (const c of doc.characters) {
    if (c.weapon_info) all.push(c.weapon_info);
    for (const a of c.arm_infos || []) all.push(a);
  }
  const seen = new Set();
  let dup = 0;
  let zero = 0;
  for (const it of all) {
    const u = Number(it.item_uuid) || 0;
    if (!u) zero += 1;
    if (seen.has(u)) dup += 1;
    seen.add(u);
  }
  check(dup === 0 && zero === 0, `迁移后所有道具 uuid 唯一且非零（${all.length} 件）`);
  check(gun.item_uuid === shared, '第一个出现的条目保留原 uuid（不打乱既有语义）');
  check(Number(sacred.item_uuid) !== shared && Number(salome.weapon_info.item_uuid) !== shared,
    '被遮蔽的副本/装备重新分配了 uuid');
  check(migratePlayer(doc) === false, 'uuid 去重迁移是幂等的');
}

// ---------------- ④ 武器类型修复迁移（莎乐美那把枪） ----------------
{
  const doc = createPlayerDoc(9103);
  doc.characters.push(buildCharacter(doc, SALOME)); // 不在开局二人组里
  const salome = doc.characters.find((c) => c.character_id === SALOME);
  const starter = salome.weapon_info; // 4010100 卷核FX（礼器）
  const gun = items.makeItem(doc, GUN, 1);
  doc.bag.items.push(gun);
  // 模拟被 uuid 错位装上的枪械
  salome.weapon_info = gun;
  doc.bag.items.splice(doc.bag.items.indexOf(gun), 1);
  doc.bag.items.push(starter);
  // 背包里同时有低阶与高阶礼器，应挑稀有度最高的一件（SACRED_TOP 6★）
  doc.bag.items.push(items.makeItem(doc, SACRED_LOW, 1));
  doc.bag.items.push(items.makeItem(doc, SACRED_TOP, 1));

  const changed = migratePlayer(doc);
  check(changed === true, '装错武器类型的存档迁移会上报改动');
  check(salome.weapon_info.item_id === SACRED_TOP,
    `莎乐美被换成背包里最好的礼器 ${SACRED_TOP}（实得 ${salome.weapon_info.item_id}）`);
  check(items.weaponType(salome.weapon_info.item_id) === SALOME_WEAPON_TYPE,
    '修复后武器类型与角色一致');
  check(doc.bag.items.includes(gun), '那把枪械回到背包（没有凭空消失）');
  check(migratePlayer(doc) === false, '武器类型修复是幂等的');
}
{
  // 背包里没有同类型武器时，退回 d_character.firstWeapon
  const doc = createPlayerDoc(9104);
  doc.characters.push(buildCharacter(doc, SALOME)); // 不在开局二人组里
  const salome = doc.characters.find((c) => c.character_id === SALOME);
  salome.weapon_info = items.makeItem(doc, GUN, 1);
  migratePlayer(doc);
  check(salome.weapon_info.item_id === 4010100,
    '背包无同类型武器时退回 firstWeapon（4010100）');
  check(items.weaponType(salome.weapon_info.item_id) === SALOME_WEAPON_TYPE, '退回后类型正确');
}
{
  // 不误伤：武器类型正常的存档不会被改动
  const doc = createPlayerDoc(9105);
  const snapshot = JSON.stringify(doc.characters.map((c) => [c.character_id, c.weapon_info && c.weapon_info.item_id]));
  check(migratePlayer(doc) === false, '武器类型全部正确的存档迁移不做任何修复');
  check(JSON.stringify(doc.characters.map((c) => [c.character_id, c.weapon_info && c.weapon_info.item_id])) === snapshot,
    '未改动任何角色装备');
}

// ---------------- ⑤ 未实装武器（幽灵武器） ----------------
//
// 1081601「颂歌」是 7★ 巨刃，也是巨刃里稀有度最高、id 最大的一把 —— 早期版本按
// 「同类型稀有度最高、并列取 id 大者」发专武时正好选中它。但它在客户端里没有模型、
// 没有图标、也没有 d_skill 行，一发下去武器详情面板就会因为 GetWeaponSkillDesc 抛错
// 而整体停摆（详见 src/game/weapon_data.js）。这里守住「不发 + 存档里已有的换掉」。
const weaponData = require('../src/game/weapon_data');
const arsenal = require('../src/game/arsenal');
const GHOST = 1081601;        // 颂歌      7★ 巨刃（未实装）
const GHOST_6 = 1080601;      // 挽歌      6★ 巨刃（未实装）
const GIANT_OK_7 = 1071611;   // 灼星已现  7★ 巨刃（已实装）
const GIANT_OK_6 = 1072601;   // 余晖之盈  6★ 巨刃（已实装）
const GIANT_CHAR = 10701;     // 踯躅森辩才姬，profession 1（巨刃）

check(weaponData.isUnreleasedWeapon(GHOST) && !weaponData.isReleasedWeapon(GHOST),
  `${GHOST} 颂歌被判定为未实装（d_skill 无 2000101，pak 无模型/图标/展示图）`);
check(!weaponData.skillHasRow(GHOST), '未实装武器的 skillID 在 d_skill 里查不到行');
check(weaponData.isReleasedWeapon(GIANT_OK_7) && weaponData.isReleasedWeapon(GIANT_OK_6),
  '同类型的 1071611 / 1072601 是已实装武器');
{
  // 黑名单不能误伤：这 10 把之外，所有武器的 skillID 都必须在 d_skill 里
  const bad = [];
  for (const [id, w] of gd.rows('d_bag_item_weapon')) {
    if (weaponData.isUnreleasedWeapon(id)) continue;
    if (!weaponData.skillHasRow(id)) bad.push(id);
  }
  check(bad.length === 0, `黑名单外的武器技能行都齐全${bad.length ? ' 例外: ' + bad.join(',') : ''}`);
}
{
  // 任何角色的「推荐武器」都不能是未实装武器（巨刃以前正好踩中 1081601）
  const bad = [];
  for (const [, row] of gd.rows('d_character')) {
    if (!row.firstWeapon) continue;
    const pick = arsenal.bestWeaponForCharacter(row.id);
    if (pick && !weaponData.isReleasedWeapon(pick)) bad.push(`${row.id}->${pick}`);
  }
  check(bad.length === 0, `bestWeaponForCharacter 从不返回未实装武器${bad.length ? ' 例外: ' + bad.join('; ') : ''}`);
  check(arsenal.bestWeaponForCharacter(GIANT_CHAR) === GIANT_OK_7,
    `巨刃角色改推荐 ${GIANT_OK_7}（实得 ${arsenal.bestWeaponForCharacter(GIANT_CHAR)}）`);
}
{
  // 发放清单：每种已实装的 6★/7★ 各一把，且不含任何未实装武器
  const ids = arsenal.highRarityWeaponIds();
  check(ids.length === 36, `高稀有度发放清单 36 把（实得 ${ids.length}）`);
  check(!ids.includes(GHOST) && !ids.includes(GHOST_6), '发放清单里没有未实装武器');
  check(ids.every((id) => weaponData.isReleasedWeapon(id)), '发放清单全部已实装');
  check(new Set(ids).size === ids.length, '发放清单无重复 id');
  check(ids.every((id) => Number(gd.query('d_bag_item_weapon', id).rarity) >= 6), '发放清单全部 >= 6★');
  const doc = createPlayerDoc(9106);
  const { granted } = arsenal.grantHighRarityWeapons(doc);
  check(granted.length === ids.length
    && doc.bag.items.filter((it) => it.weapon_info).length === ids.length,
  'grantHighRarityWeapons 每种各发一把');
  const { granted: again } = arsenal.grantHighRarityWeapons(doc, { skipOwned: true });
  check(again.length === 0, 'skipOwned 时不会重复发放');
}
{
  // 迁移：存档里的幽灵武器原地换成同类型已实装武器，练度（uuid/exp/突破/光淬）保留
  const doc = createPlayerDoc(9107);
  // 10701（踯躅森辩才姬）不在开局小队里，用 buildCharacter 补进来
  doc.characters.push(buildCharacter(doc, GIANT_CHAR));
  const giant = doc.characters.find((c) => c.character_id === GIANT_CHAR);
  const ghost = items.makeItem(doc, GHOST, 1);
  ghost.weapon_info.exp = 12345;
  ghost.weapon_info.break_times = 3;
  ghost.weapon_info.refine_level = 2;
  const uuidBefore = Number(ghost.item_uuid);
  giant.weapon_info = ghost;
  doc.bag.items.splice(doc.bag.items.indexOf(ghost), 1);
  doc.bag.items.push(items.makeItem(doc, GHOST_6, 1));

  const changed = migratePlayer(doc);
  check(changed === true, '含未实装武器的存档迁移会上报改动');
  check(giant.weapon_info.item_id === GIANT_OK_7,
    `7★ 幽灵武器被换成 ${GIANT_OK_7}（实得 ${giant.weapon_info.item_id}）`);
  check(Number(giant.weapon_info.item_uuid) === uuidBefore, '替换是原地的：item_uuid 不变');
  check(giant.weapon_info.weapon_info.exp === 12345
    && giant.weapon_info.weapon_info.break_times === 3
    && giant.weapon_info.weapon_info.refine_level === 2,
  '替换保留练度（经验/突破/光淬）');
  const bagGhost = doc.bag.items.find((it) => it.item_id === GHOST_6);
  check(!bagGhost, '背包里的 6★ 幽灵武器也被换掉了');
  check(doc.bag.items.some((it) => it.item_id === GIANT_OK_6), `背包里的挽歌换成了 ${GIANT_OK_6}`);
  check(migratePlayer(doc) === false, '未实装武器替换是幂等的');
}
{
  // 不误伤：全是没有幽灵武器的正常存档
  const doc = createPlayerDoc(9108);
  check(migratePlayer(doc) === false, '不含未实装武器的存档迁移不做任何修复');
}

fs.rmSync(tmpDataDir, { recursive: true, force: true });
console.log(failures === 0 ? '\nWEAPON CHECKS PASSED' : `\n${failures} WEAPON CHECKS FAILED`);
process.exit(failures === 0 ? 0 : 1);
