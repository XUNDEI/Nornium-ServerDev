// 角色武器相关的回归断言（无需服务端）：
//   ① 角色武器类型（d_character.profession）与 d_bag_item_weapon.subType 的一致性；
//   ② req_character_equip_weapon / req_character_swap_weapon 的类型校验；
//   ③ 老存档 item_uuid 重复的去重迁移；
//   ④ 「装错武器类型的角色」的迁移修复（莎乐美那把枪，见坑 37）；
//   ⑤ 「未实装武器」（客户端没有模型/图标/技能行的幽灵武器，如 1081601 颂歌）：
//      发放清单不含它们、专武映射不指向它们、存档里已有的原地换掉（见坑 38）。
//   ⑥ 「角色 → 7★ 专武」官方映射（weapon_data.js 的 CHARACTER_EXCLUSIVE_WEAPONS）：
//      十人逐一断言 + 专武发放/跳过已拥有。
//   ⑦ 光淬 req_weapon_refine：ntf_item_info 先于 res（效果变动弹窗靠它读新阶数）、
//      repeated 素材逐个扣除并 count=-1 同步客户端、maxRefine 到顶拒绝；
//      严格校验：无素材/非同族/锁定素材/金币不足整单拒绝（result=4），合法才升阶扣料扣费。
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
const SACRED_TOP = 4072601; // 礼器（subType 5），6★  —— 莎乐美专武族的特殊 6★ 变体（梦魇之灯）

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
  // 专武映射：每名可玩角色一把 7★ 专武（映射与四条证据见 weapon_data.js 的注释）。
  // 旧版按「同类型最高稀有度」猜，会把 10102/10601 都指到 2061610、10501/10701 都指到
  // 1071611 —— 其中辩才姬（10701）被指到信风的武器上，是玩家实测报错的那类问题。
  const EXPECTED = {
    10101: 3060611, // 阿特拉斯™眩光
    10102: 2051611, // 最初的蒸发
    10201: 4071611, // 总控者的视觉
    10301: 5071611, // 染掌之影
    10401: 6061611, // 羚辉之辉
    10501: 1071611, // 灼星已现
    10601: 2041611, // 雨后青鸟
    10701: 1060611, // 蛇毒聚流
    10801: 7070611, // 仁剑<红天>
    11202: 7081611, // 断线者
  };
  const bad = [];
  for (const [charId, weaponId] of Object.entries(EXPECTED)) {
    const got = arsenal.exclusiveWeaponForCharacter(Number(charId));
    if (got !== weaponId) bad.push(`${charId}→${got}(期望 ${weaponId})`);
    const w = gd.query('d_bag_item_weapon', weaponId);
    if (!w || Number(w.rarity) !== 7) bad.push(`${weaponId} 不是 7★`);
    const prof = Number(gd.query('d_character', charId).profession);
    if (Number(w.subType) !== prof) bad.push(`${weaponId} 类型 ${w.subType} ≠ 角色 ${charId} 的 ${prof}`);
    if (!weaponData.isReleasedWeapon(weaponId)) bad.push(`${weaponId} 未实装`);
  }
  check(bad.length === 0, `十人专武映射逐一吻合且全部已实装 7★${bad.length ? ' 例外: ' + bad.join('; ') : ''}`);
  check(arsenal.exclusiveWeaponForCharacter(10901) === 0
    && arsenal.exclusiveWeaponForCharacter(99999) === 0,
    '映射外角色（profession=0 / 不存在）返回 0');
}
{
  // 映射表本体：10 条、base（6★）与 seven（7★）同族（id 前 3 位）且全部已实装
  const mapping = weaponData.CHARACTER_EXCLUSIVE_WEAPONS;
  const bad = [];
  for (const [charId, e] of Object.entries(mapping)) {
    if (Math.floor(e.base / 10000) !== Math.floor(e.seven / 10000)) bad.push(`${charId} base/seven 不同族`);
    if (!weaponData.isReleasedWeapon(e.base) || !weaponData.isReleasedWeapon(e.seven)) {
      bad.push(`${charId} 有形态未实装`);
    }
    if (arsenal.exclusiveWeaponBaseForCharacter(charId) !== e.base) bad.push(`${charId} base 查询不符`);
  }
  check(Object.keys(mapping).length === 10 && bad.length === 0,
    `映射表 10 条、6★/7★ 同族且全部已实装${bad.length ? ' 例外: ' + bad.join('; ') : ''}`);
}
{
  // 专武发放：每人一把 7★ 各发一次，skipOwned 幂等，且是高稀有度清单的子集
  const ids = arsenal.exclusiveWeaponIds();
  check(ids.length === 10, `专武发放清单 10 把（实得 ${ids.length}）`);
  check(ids.every((id) => Number(gd.query('d_bag_item_weapon', id).rarity) === 7), '专武清单全部 7★');
  const all = arsenal.highRarityWeaponIds();
  check(ids.every((id) => all.includes(id)), '专武清单 ⊆ 高稀有度清单');
  check(!ids.includes(GHOST) && !ids.includes(GHOST_6), '专武清单里没有未实装武器');
  const doc = createPlayerDoc(9108);
  const { granted } = arsenal.grantExclusiveWeapons(doc);
  check(granted.length === 10
    && doc.bag.items.filter((it) => it.weapon_info).length === 10,
  'grantExclusiveWeapons 每人各发一把');
  const { granted: again } = arsenal.grantExclusiveWeapons(doc, { skipOwned: true });
  check(again.length === 0, '专武 skipOwned 时不会重复发放');
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

// ---------------- ⑦ 光淬（req_weapon_refine）----------------
{
  // 背包武器升阶：ntf_item_info（带新阶数）必须先于 res_weapon_refine 到达 ——
  // 客户端的效果变动弹窗在 res 广播瞬间从背包缓存读 refine_level，背包缓存只随
  // ntf_item_info 更新，顺序反了就是「光淬0阶 → 光淬0阶」。
  // 素材必须是 d_weapon.refinedWeapon 同族（4072601 的族 = [4072601, 4070601]），
  // 并扣 refinedCost 金星贝（9001）。
  const SACRED_STUFF = 4070601; // 莎乐美专武族的 6★ 本体（refinedWeapon 同族素材）
  const s = makeSession();
  const gear = items.makeItem(s.player, SACRED_TOP, 1);
  s.player.bag.items.push(gear);
  const stuff = items.makeItem(s.player, SACRED_STUFF, 1);
  s.player.bag.items.push(stuff);
  const goldBefore = items.bagCount(s.player, 9001);
  charH.reqWeaponRefine(s, { item_uuid: gear.item_uuid, stuff_item_uuid: [stuff.item_uuid] });
  const ntfIdx = s.sent.findIndex((x) => x.name === 'ntf_item_info');
  const resIdx = s.sent.findIndex((x) => x.name === 'res_weapon_refine');
  check(ntfIdx >= 0 && resIdx >= 0 && ntfIdx < resIdx, '先推 ntf_item_info 再回 res_weapon_refine');
  check(last(s, 'res_weapon_refine').result === undefined, '同族素材 + 金币充足 -> OK');
  check(gear.weapon_info.refine_level === 1, 'refine_level +1');
  const changed = s.sent[ntfIdx].msg.changed_item_infos;
  const target = changed.find((c) => String(c.item_uuid) === String(gear.item_uuid));
  check(target && target.count === 0 && target.weapon_info === gear.weapon_info,
    '目标武器 count=0 + 完整 weapon_info（命中客户端「整条替换」分支）');
  const eaten = changed.find((c) => String(c.item_uuid) === String(stuff.item_uuid));
  check(eaten && eaten.count === -1, '被吃的素材以 count=-1 推给客户端');
  check(!s.player.bag.items.some((it) => String(it.item_uuid) === String(stuff.item_uuid)),
    '素材已从服务端背包扣除');
  check(items.bagCount(s.player, 9001) === goldBefore - 5000,
    `refinedCost 5000 金星贝已扣除（${goldBefore} -> ${items.bagCount(s.player, 9001)}）`);
}
{
  // 多素材：repeated stuff_item_uuid 逐个扣除（旧实现 Number(array) 多选时为 NaN）
  const SACRED_STUFF = 4070601;
  const s = makeSession();
  const gear = items.makeItem(s.player, SACRED_TOP, 1);
  const stuffA = items.makeItem(s.player, SACRED_STUFF, 1);
  const stuffB = items.makeItem(s.player, SACRED_STUFF, 1);
  s.player.bag.items.push(gear, stuffA, stuffB);
  charH.reqWeaponRefine(s, {
    item_uuid: gear.item_uuid,
    stuff_item_uuid: [stuffA.item_uuid, stuffB.item_uuid],
  });
  check(last(s, 'res_weapon_refine').result === undefined, '多素材全部同族 -> OK');
  const changed = last(s, 'ntf_item_info').msg.changed_item_infos;
  const eaten = changed.filter((c) => c.count === -1);
  check(eaten.length === 2
    && eaten.some((c) => String(c.item_uuid) === String(stuffA.item_uuid))
    && eaten.some((c) => String(c.item_uuid) === String(stuffB.item_uuid)),
    '两个素材各有一条 count=-1');
  check(s.player.bag.items.some((it) => String(it.item_uuid) === String(gear.item_uuid)),
    '目标武器还在背包');
  check(!s.player.bag.items.some((it) => String(it.item_uuid) === String(stuffA.item_uuid))
    && !s.player.bag.items.some((it) => String(it.item_uuid) === String(stuffB.item_uuid)),
    '两个素材都已从背包扣除');
}
{
  // 已装备的武器同样要能升阶（findGearByUuid 落在角色身上）；
  // 莎乐美初始武器 4010100 的同族素材还是 4010100。
  const s = makeSession();
  s.player.characters.push(buildCharacter(s.player, SALOME));
  const c = charOf(s, SALOME);
  const stuff = items.makeItem(s.player, 4010100, 1);
  s.player.bag.items.push(stuff);
  charH.reqWeaponRefine(s, { item_uuid: c.weapon_info.item_uuid, stuff_item_uuid: [stuff.item_uuid] });
  check(last(s, 'res_weapon_refine').result === undefined, '已装备武器 + 同族素材 -> OK');
  check(c.weapon_info.weapon_info.refine_level === 1, '已装备武器 refine_level +1');
  const changed = last(s, 'ntf_item_info').msg.changed_item_infos;
  check(changed.some((x) => x.count === 0 && x.weapon_info === c.weapon_info.weapon_info),
    '已装备武器走同一份 count=0 + weapon_info 载荷（客户端 item_extra 分支原地刷新）');
  check(!s.player.bag.items.some((it) => String(it.item_uuid) === String(stuff.item_uuid)),
    '素材从背包扣除，已装备的目标本身不受影响');
}
{
  // 严格校验：空素材 -> STUFF_NOT_ENOUGH(4)，白嫖升阶被堵死
  const s = makeSession();
  const gear = items.makeItem(s.player, SACRED_TOP, 1);
  s.player.bag.items.push(gear);
  charH.reqWeaponRefine(s, { item_uuid: gear.item_uuid, stuff_item_uuid: [] });
  check(last(s, 'res_weapon_refine').result === 4, '无素材 -> STUFF_NOT_ENOUGH(4)');
  check(gear.weapon_info.refine_level === 0, '拒绝后 refine_level 不变');
  check(!s.sent.some((x) => x.name === 'ntf_item_info'), '拒绝不推任何 ntf');
  check(items.bagCount(s.player, 9001) === 1200000, '拒绝不扣金币');
}
{
  // 严格校验：素材不在 refinedWeapon 同族 -> 拒绝（4011300 不是 4072601 的族）
  const s = makeSession();
  const gear = items.makeItem(s.player, SACRED_TOP, 1);
  const stuff = items.makeItem(s.player, SACRED_LOW, 1);
  s.player.bag.items.push(gear, stuff);
  charH.reqWeaponRefine(s, { item_uuid: gear.item_uuid, stuff_item_uuid: [stuff.item_uuid] });
  check(last(s, 'res_weapon_refine').result === 4, '非同族素材 -> STUFF_NOT_ENOUGH(4)');
  check(gear.weapon_info.refine_level === 0, '拒绝后 refine_level 不变');
  check(s.player.bag.items.some((it) => String(it.item_uuid) === String(stuff.item_uuid)),
    '拒绝后素材仍留在背包（没有被吞掉）');
  check(items.bagCount(s.player, 9001) === 1200000, '拒绝不扣金币');
}
{
  // 严格校验：锁定素材 -> 拒绝
  const SACRED_STUFF = 4070601;
  const s = makeSession();
  const gear = items.makeItem(s.player, SACRED_TOP, 1);
  const stuff = items.makeItem(s.player, SACRED_STUFF, 1);
  stuff.weapon_info.locked = true;
  s.player.bag.items.push(gear, stuff);
  charH.reqWeaponRefine(s, { item_uuid: gear.item_uuid, stuff_item_uuid: [stuff.item_uuid] });
  check(last(s, 'res_weapon_refine').result === 4, '锁定素材 -> STUFF_NOT_ENOUGH(4)');
  check(s.player.bag.items.some((it) => String(it.item_uuid) === String(stuff.item_uuid)),
    '拒绝后锁定素材仍留在背包');
}
{
  // 严格校验：金星贝不足 -> 拒绝（refinedCost=5000）
  const SACRED_STUFF = 4070601;
  const s = makeSession();
  const gear = items.makeItem(s.player, SACRED_TOP, 1);
  const stuff = items.makeItem(s.player, SACRED_STUFF, 1);
  s.player.bag.items.push(gear, stuff);
  s.player.bag.items.find((it) => it.item_id === 9001).count = 4999;
  charH.reqWeaponRefine(s, { item_uuid: gear.item_uuid, stuff_item_uuid: [stuff.item_uuid] });
  check(last(s, 'res_weapon_refine').result === 4, '金币不足 -> STUFF_NOT_ENOUGH(4)');
  check(gear.weapon_info.refine_level === 0, '拒绝后 refine_level 不变');
  check(s.player.bag.items.some((it) => String(it.item_uuid) === String(stuff.item_uuid)),
    '拒绝后素材仍留在背包');
}
{
  // 到顶拒绝：d_weapon.maxRefine=4，超顶后客户端查 d_skill_fight_level 会落空
  const s = makeSession();
  const gear = items.makeItem(s.player, SACRED_TOP, 1);
  gear.weapon_info.refine_level = 4;
  s.player.bag.items.push(gear);
  charH.reqWeaponRefine(s, { item_uuid: gear.item_uuid, stuff_item_uuid: [] });
  check(last(s, 'res_weapon_refine').result === 3, '光淬已达 maxRefine -> 拒绝（result=3）');
  check(gear.weapon_info.refine_level === 4, '到顶后 refine_level 不再上涨');
  check(!s.sent.some((x) => x.name === 'ntf_item_info'), '到顶拒绝不推任何 ntf');
}
{
  // 未知 uuid：沿用旧约定的 result=1，不崩
  const s = makeSession();
  charH.reqWeaponRefine(s, { item_uuid: 987654321, stuff_item_uuid: [] });
  check(last(s, 'res_weapon_refine').result === 1, '未知武器 uuid -> result=1');
}

fs.rmSync(tmpDataDir, { recursive: true, force: true });
console.log(failures === 0 ? '\nWEAPON CHECKS PASSED' : `\n${failures} WEAPON CHECKS FAILED`);
process.exit(failures === 0 ? 0 : 1);
