// 皮肤（时装）与新号开局角色单元回归 —— 无需服务端。
//
// 覆盖：
//   1. 新号只发开局教学小队（10101/10201/10301），不再发全部可玩角色；
//   2. buildCharacter 预解锁默认皮肤（dressInitial==1，客户端「默认即解锁」分支被注释）；
//   3. req_use_item 的皮肤卡 / 角色卡 / 锻造蓝图语义（服务端落盘 + 不推消耗 ntf）；
//   4. req_character_change_skin 的解锁校验（NO_SKIN）与 0=默认；
//   5. migrateSkins：老存档自动补默认皮肤 + 背包皮肤卡就地解锁 + 幽灵道具清理，幂等；
//   6. unlockAllSkins 的数量口径；
//   7. 控制台 addchar / allskins；
//   8. framefix.mergeIniSection 的合并语义（CRLF 保留 / 幂等 / 追加节）。
//
// 必须在 require 服务端模块之前设置 GHS_DATA_DIR（store.js 载入时读它），
// 让这些检查的存档落在临时目录，不碰真实的 server/data/。
const os = require('os');
const fs = require('fs');
const path = require('path');
const tmpDataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ghs-skins-'));
process.env.GHS_DATA_DIR = tmpDataDir;

const { createPlayerDoc, initialCharacterIds, starterCharacterIds, buildCharacter, isPlayableCharacter } = require('../src/game/player_new');
const skins = require('../src/game/skins');
const characterH = require('../src/handlers/character');
const { migratePlayer } = require('../src/game/migrate');
const items = require('../src/game/items');
const gd = require('../src/gamedata');
const store = require('../src/store');
const { handleCommand } = require('../src/console');

let failures = 0;
function check(cond, msg) {
  console.log(cond ? `  PASS ${msg}` : `  FAIL ${msg}`);
  if (!cond) failures += 1;
}

function makeSession() {
  const player = createPlayerDoc(9001);
  const sent = [];
  // 真实 Session.send 的帧头 result 缺省为 0（成功），假会话保持同一语义
  return { player, sent, send: (name, msg, result) => sent.push({ name, msg, result: result ?? 0 }) };
}
const last = (s, name) => [...s.sent].reverse().find((x) => x.name === name);
const ntfItemDelta = (s, itemId) => {
  const deltas = [];
  for (const m of s.sent) {
    if (m.name === 'ntf_item_info' && m.msg && m.msg.changed_item_infos) {
      for (const ci of m.msg.changed_item_infos) if (Number(ci.item_id) === Number(itemId)) deltas.push(ci);
    }
  }
  return deltas;
};

// ---------------- 1. 开局角色 ----------------
check(starterCharacterIds().length === 2
  && starterCharacterIds().every((id) => [10501, 11202].includes(id)),
  `starter roster is 信风(10501) + 鱼啄雨(11202) (${starterCharacterIds().join(',')})`);
check(initialCharacterIds().length === 10, 'initialCharacterIds still returns the full playable roster (editor/all)');
{
  const doc = createPlayerDoc(9001);
  check(doc.characters.length === 2, `createPlayerDoc grants exactly 2 characters (got ${doc.characters.length})`);
  check(doc.player.avatar_id === 10501, 'default avatar is the protagonist 信风');
  // 其余资源照旧
  check(items.bagCount(doc, 9002) >= 100000, 'diamonds still granted');
  check(items.bagCount(doc, 1200001) >= 100, 'limited tickets still granted');
}

// ---------------- 2. 默认皮肤 ----------------
{
  const doc = createPlayerDoc(9001);
  for (const char of doc.characters) {
    const defaults = skins.defaultSkinIds(char.character_id);
    check(Object.keys(defaults).length >= 3, `character ${char.character_id} has default skins for 3 dress types`);
    for (const [t, skinId] of Object.entries(defaults)) {
      const ownKey = skins.DRESS_TYPES[t].own;
      check((char[ownKey] || []).some((x) => Number(x) === Number(skinId)),
        `character ${char.character_id}: default skin ${skinId} (dressType ${t}) pre-unlocked`);
    }
    check(char.character_skin_id === 0 && char.mecha_skin_id === 0 && char.city_skin_id === 0,
      `character ${char.character_id}: worn skins default to 0`);
  }
}

// ---------------- 3. req_use_item ----------------
{
  const s = makeSession();
  // 皮肤卡 4050101（角色 10501 信风：战斗 1050101 / 机甲 2050101 / 主城 3050101）
  items.grantItems(s.player, [{ item_id: 4050101, count: 1 }]);
  const card = s.player.bag.items.find((it) => it.item_id === 4050101);
  characterH.reqUseItem(s, { item_uuid: card.item_uuid, count: 1 });
  check(last(s, 'res_use_item') && last(s, 'res_use_item').result === 0, 'res_use_item(皮肤卡) OK');
  check(!items.findStackEntry(s.player, 4050101), 'skin card consumed');
  check(ntfItemDelta(s, 4050101).length === 0,
    'no ntf_item_info for the consumed skin card (client decrements locally, delta would double-spend)');
  const mecha = s.player.characters.find((c) => c.character_id === 10501);
  const has = (id) => [mecha.own_character_skin_ids, mecha.own_mecha_skin_ids, mecha.own_city_skin_ids]
    .some((l) => l.some((x) => Number(x) === id));
  check(has(1050101) && has(2050101) && has(3050101), 'all three skins of 4050101 unlocked server-side');
  // 不重复插入
  const before = JSON.stringify(mecha.own_character_skin_ids);
  characterH.reqUseItem(s, { item_uuid: items.grantItems(s.player, [{ item_id: 4050101, count: 1 }]).changed_item_infos[0].item_uuid, count: 1 });
  check(JSON.stringify(mecha.own_character_skin_ids) === before, 're-using the same skin card does not duplicate entries');
}
{
  // 角色卡 6010201（角色 10102）→ 创建角色，且不再产生幽灵道具（item_id 10102）
  const s = makeSession();
  items.grantItems(s.player, [{ item_id: 6010201, count: 1 }]);
  const card = s.player.bag.items.find((it) => it.item_id === 6010201);
  characterH.reqUseItem(s, { item_uuid: card.item_uuid, count: 1 });
  check(last(s, 'res_use_item').result === 0, 'res_use_item(角色卡) OK');
  check(s.player.characters.some((c) => c.character_id === 10102), 'char card created character 10102');
  check(!s.player.bag.items.some((it) => it.item_id === 10102), 'no ghost item 10102 in bag');
  const newChar = s.player.characters.find((c) => c.character_id === 10102);
  check(newChar.weapon_info && items.weaponType(newChar.weapon_info.item_id) === items.characterWeaponType(10102),
    'created character has a type-matched weapon');
  check((newChar.own_character_skin_ids || []).length > 0, 'created character has default skins');
  // 已拥有的角色卡再使用：不重复创建、不再发 ntf_character_info
  items.grantItems(s.player, [{ item_id: 6010201, count: 1 }]);
  const card2 = s.player.bag.items.find((it) => it.item_id === 6010201);
  const charCount = s.player.characters.length;
  characterH.reqUseItem(s, { item_uuid: card2.item_uuid, count: 1 });
  check(s.player.characters.length === charCount, 'duplicate char card does not create a second character');
}
{
  // 锻造蓝图 1209001（subParam [1001,2001,...6001]）→ arm_blueprint_ids
  const s = makeSession();
  items.grantItems(s.player, [{ item_id: 1209001, count: 1 }]);
  const card = s.player.bag.items.find((it) => it.item_id === 1209001);
  characterH.reqUseItem(s, { item_uuid: card.item_uuid, count: 1 });
  check(last(s, 'res_use_item').result === 0, 'res_use_item(锻造蓝图) OK');
  check(s.player.player.arm_blueprint_ids.length === 6, `arm_blueprint_ids seeded (${s.player.player.arm_blueprint_ids.join(',')})`);
}

// ---------------- 4. req_character_change_skin ----------------
{
  const s = makeSession();
  const mecha = s.player.characters.find((c) => c.character_id === 10501);
  items.grantItems(s.player, [{ item_id: 4050101, count: 1 }]);
  const card = s.player.bag.items.find((it) => it.item_id === 4050101);
  characterH.reqUseItem(s, { item_uuid: card.item_uuid, count: 1 });

  characterH.reqCharacterChangeSkin(s, { character_id: 10501, character_skin_id: 1050101, mecha_skin_id: 2050101, city_skin_id: 3050101 });
  check(last(s, 'res_character_change_skin').result === 0, 'wear unlocked skins -> OK');
  check(mecha.character_skin_id === 1050101 && mecha.mecha_skin_id === 2050101 && mecha.city_skin_id === 3050101,
    'worn skin ids persisted on the character doc');

  characterH.reqCharacterChangeSkin(s, { character_id: 10501, character_skin_id: 1050102 });
  check(last(s, 'res_character_change_skin').result === 3, 'locked skin -> NO_SKIN(3)');
  check(mecha.character_skin_id === 1050101, 'rejected change did not touch state');

  characterH.reqCharacterChangeSkin(s, { character_id: 10501, character_skin_id: 0 });
  check(last(s, 'res_character_change_skin').result === 0, 'reset to default (0) -> OK');
  check(mecha.character_skin_id === 0, 'default reset persisted');

  characterH.reqCharacterChangeSkin(s, { character_id: 99999, character_skin_id: 0 });
  check(last(s, 'res_character_change_skin').result === 1, 'unknown character -> NO_CHARACTER(1)');

  // 错位的 dressType 也不接受（把主城皮肤塞进战斗位）
  characterH.reqCharacterChangeSkin(s, { character_id: 10501, character_skin_id: 3050101 });
  check(last(s, 'res_character_change_skin').result === 3, 'city skin in battle slot -> NO_SKIN(3)');
}

// ---------------- 5. 迁移 ----------------
{
  // 老存档：角色缺皮肤字段 + 背包里有皮肤卡 + 幽灵道具（旧 req_use_item 的产物）
  const doc = createPlayerDoc(9001);
  for (const c of doc.characters) {
    delete c.own_character_skin_ids; delete c.own_mecha_skin_ids; delete c.own_city_skin_ids;
    delete c.character_skin_id;
  }
  doc.bag.items.push({ item_id: 4050101, count: 2, item_uuid: 5001 });
  doc.bag.items.push({ item_id: 1010101, count: 1, item_uuid: 5002 }); // 幽灵道具（表里没有）
  const beforeItems = doc.bag.items.length;
  const changed = migratePlayer(doc);
  check(changed === true, 'migration reports changes for the legacy skin save');
  const mecha = doc.characters.find((c) => c.character_id === 10501);
  check(Array.isArray(mecha.own_character_skin_ids) && mecha.character_skin_id === 0, 'skin fields restored');
  const has = (id) => [mecha.own_character_skin_ids, mecha.own_mecha_skin_ids, mecha.own_city_skin_ids]
    .some((l) => l.some((x) => Number(x) === id));
  check(has(1050101) && has(2050101) && has(3050101), 'skin card in bag auto-unlocked by migration');
  check(!doc.bag.items.some((it) => it.item_id === 1010101), 'ghost item 1010101 dropped');
  check(doc.bag.items.length === beforeItems - 1, 'exactly one ghost item removed');
  check(doc.bag.items.some((it) => it.item_id === 4050101), 'real skin card kept in bag');

  // 幂等：再跑一遍不再有变化
  const snapshot = JSON.stringify([doc.characters, doc.bag.items]);
  check(migratePlayer(doc) === false, 'second migration run is a no-op');
  check(JSON.stringify([doc.characters, doc.bag.items]) === snapshot, 'second migration did not mutate anything');
}

// ---------------- 5b. 迁移补开局角色 ----------------
{
  // 老档/别的组合开局的小队：剧情星图角色表要求信风(10501)与鱼啄雨(11202)在场
  const doc = createPlayerDoc(9001);
  doc.characters = doc.characters.filter((c) => c.character_id !== 10501);
  const before = doc.characters.length;
  check(migratePlayer(doc) === true, 'missing protagonist is reported as a change');
  check(doc.characters.length === before + 1
    && doc.characters.some((c) => c.character_id === 10501),
    'migration grants the missing protagonist 信风(10501)');
  const mecha = doc.characters.find((c) => c.character_id === 10501);
  check((mecha.own_character_skin_ids || []).length > 0 && mecha.weapon_info,
    'granted protagonist comes with default skins and her first weapon');
  check(migratePlayer(doc) === false, 'starter migration is idempotent');
}

// ---------------- 6. unlockAllSkins ----------------
{
  const doc = createPlayerDoc(9001);
  const totals = doc.characters.reduce((s, c) => s + skins.skinTotalForCharacter(c.character_id), 0);
  const preOwned = doc.characters.reduce((s, c) => s
    + c.own_character_skin_ids.length + c.own_mecha_skin_ids.length + c.own_city_skin_ids.length, 0);
  check(totals > 2 * 3, `skin totals per character are non-trivial (${totals} across the roster)`);
  const { chars, added } = skins.unlockAllSkins(doc);
  check(chars.length === 2 && added + preOwned === totals,
    `unlockAllSkins unlocked everything not yet owned (added ${added}, total ${totals})`);
  const again = skins.unlockAllSkins(doc);
  check(again.added === 0, 'unlockAllSkins is idempotent');
}

// ---------------- 7. 控制台指令 ----------------
(async () => {
  const hooks = { maintenance: (fn) => fn({ kicked: 0, remaining: 0 }) };
  store.loadAccounts(); // createAccount 用的是模块级缓存，先从磁盘装载
  const rec = store.createAccount('skinsA', 'pw');
  store.savePlayer(createPlayerDoc(rec.account_id));

  const r1 = await handleCommand(`addchar ${rec.account_name} 10401`, hooks);
  check(/新增角色 1 个/.test(r1.reply) && /10401/.test(r1.reply), `addchar adds one character :: ${r1.reply.split('\n')[0]}`);
  let doc = store.loadPlayer(rec.account_id);
  check(doc.characters.some((c) => c.character_id === 10401), 'addchar persisted character 10401');

  const r2 = await handleCommand(`addchar ${rec.account_name} all`, hooks);
  check(/新增角色 7 个/.test(r2.reply), `addchar all fills the rest of the roster (10 - 3 owned = 7) :: ${r2.reply.split('\n')[0]}`);
  doc = store.loadPlayer(rec.account_id);
  check(doc.characters.length === 10, 'roster complete after addchar all');

  const r3 = await handleCommand(`allskins ${rec.account_name}`, hooks);
  check(/新解锁皮肤 \d+ 个/.test(r3.reply), `allskins unlocks skins :: ${r3.reply.split('\n')[0]}`);
  doc = store.loadPlayer(rec.account_id);
  const ownedAll = doc.characters.every((c) => {
    const t = skins.skinTotalForCharacter(c.character_id);
    return (c.own_character_skin_ids.length + c.own_mecha_skin_ids.length + c.own_city_skin_ids.length) === t;
  });
  check(ownedAll, 'every character has every skin unlocked after allskins');

  const r4 = await handleCommand(`addchar ${rec.account_name} 10401`, hooks);
  check(/没有实际新增任何角色/.test(r4.reply), 'addchar on an owned character reports no-op');

  const r5 = await handleCommand('addchar', hooks);
  check(/用法/.test(r5.reply), 'addchar without args prints usage');

  const bad = await handleCommand('allskins no-such-account', hooks);
  check(/没有叫/.test(bad.reply), 'allskins with unknown account errors clearly');

  // ---------------- 8. framefix.mergeIniSection ----------------
  const ff = require('../src/framefix');
  const crlf = '[/Script/Engine.GameUserSettings]\r\nbUseDesiredScreenHeight=False\r\n\r\n[ScalabilityGroups]\r\nsg.ResolutionQuality=87\r\n';
  const m1 = ff.mergeIniSection(crlf, 'Engine.GameUserSettings', { bUseSmoothFrameRate: 'False', FrameRateLimit: '60.000000' });
  check(m1.changed === true, 'merge changes a plain file');
  check(m1.text.includes('bUseSmoothFrameRate=False') && m1.text.includes('FrameRateLimit=60.000000'), 'keys merged into the right section');
  check(m1.text.includes('\r\n'), 'CRLF line endings preserved');
  check(m1.text.includes('sg.ResolutionQuality=87'), 'other sections untouched');
  const m2 = ff.mergeIniSection(m1.text, 'Engine.GameUserSettings', { bUseSmoothFrameRate: 'False', FrameRateLimit: '60.000000' });
  check(m2.changed === false && m2.text === m1.text, 'merge is idempotent');
  // 已有键被改值
  const withLimit = '[/Script/GHS.GHSGameUserSettings]\r\nFrameRateLimit=0.000000\r\nbUseVSync=False\r\n';
  const m3 = ff.mergeIniSection(withLimit, '/Script/GHS.GHSGameUserSettings', { FrameRateLimit: '60.000000', bUseSmoothFrameRate: 'False' });
  check(m3.changed && m3.text.includes('FrameRateLimit=60.000000') && !m3.text.includes('FrameRateLimit=0.000000'), 'existing key replaced in place');
  check(m3.text.indexOf('FrameRateLimit=60.000000') < m3.text.indexOf('bUseVSync=False'), 'replaced key keeps its position');
  // 节不存在 → 追加
  const m4 = ff.mergeIniSection('[Other]\r\nA=1\r\n', 'Missing.Section', { X: '1' });
  check(m4.text.includes('[Missing.Section]') && m4.text.includes('X=1'), 'missing section appended');

  console.log(failures === 0 ? '\nALL SKINS CHECKS PASSED' : `\n${failures} CHECK(S) FAILED`);
  process.exit(failures === 0 ? 0 : 1);
})().catch((err) => {
  console.error('skins_check crashed:', err.stack || err.message);
  process.exit(1);
});
