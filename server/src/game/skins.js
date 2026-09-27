// 皮肤（时装）领域逻辑。
//
// 客户端口径（reference/client_lua）：
//  - 皮肤定义在 d_char_clothes：charBelong 归属角色、dressType 1=战斗服装 / 2=机甲涂装 /
//    3=主城 / 4=主城住宅偶像立绘（酒店页解锁状态 = 同角色 dressType 3 那张的 id-1000000，
//    与主城皮肤共享解锁，所以服务端不用单独记 dressType 4）。
//  - 角色身上的解锁列表：own_character_skin_ids / own_mecha_skin_ids / own_city_skin_ids
//    （CharacterInfo 字段 11/12/13），当前穿戴：character_skin_id / mecha_skin_id /
//    city_skin_id（字段 8/9/10，0 = 默认，客户端会自己回退到 dressInitial==1 的那张，
//    见 UIUtils.GetIdolAndCharMeshByCharacterId:2008）。
//  - 客户端 UIPanel 判解锁只查上面三个列表（UIUtils.CharSkinIsUnlock:2723）——包括
//    dressInitial==1 的默认皮肤；「默认皮肤自动解锁」的分支在客户端里被注释掉了
//    （UI_Panel_Dress_C:IsUnlockSkinId:719），所以**默认皮肤也必须由服务端写进列表**，
//    否则装扮面板里连初始服装都是锁着的。
//  - 皮肤道具 = d_bag_item itemType 92（皮肤卡）：subParam 就是 d_char_clothes 的皮肤 id
//    列表（40xxxxx 的卡同时给 1/2/3 三类，50xxxxx 只给机甲）。玩家在背包点「使用」
//    （UI_Com_BagDetail_C:48 的 canUse 白名单包含 Skin）→ 客户端发 req_use_item，并在
//    res OK 后本地插入解锁列表；**持久化只能靠服务端**把解锁写进角色 doc 并随
//    res_character_list / ntf_character_info 下发。
const gd = require('../gamedata');

// 三类皮肤：dressType → 角色 doc 上的解锁列表 / 穿戴字段名。
const DRESS_TYPES = {
  1: { own: 'own_character_skin_ids', worn: 'character_skin_id' },
  2: { own: 'own_mecha_skin_ids', worn: 'mecha_skin_id' },
  3: { own: 'own_city_skin_ids', worn: 'city_skin_id' },
};

function clothesRow(skinId) {
  return gd.query('d_char_clothes', Number(skinId)) || null;
}

// 某个皮肤道具（itemType 92）能解锁的皮肤 id 列表；不是皮肤道具返回 []。
function skinItemSkinIds(itemId) {
  const cfg = gd.query('d_bag_item', itemId);
  if (!cfg || Number(cfg.itemType) !== 92) return [];
  const sub = Array.isArray(cfg.subParam) ? cfg.subParam : Object.values(cfg.subParam || {});
  return sub.map(Number).filter((id) => Number(id) > 0);
}

// 角色的默认皮肤（d_char_clothes.dressInitial == 1）。返回 {1: id, 2: id, 3: id}。
function defaultSkinIds(charId) {
  const out = {};
  for (const [, r] of gd.rows('d_char_clothes')) {
    if (Number(r.charBelong) !== Number(charId)) continue;
    if (Number(r.dressInitial) !== 1) continue;
    const t = Number(r.dressType);
    if (DRESS_TYPES[t]) out[t] = Number(r.id);
  }
  return out;
}

function ownList(char, dressType) {
  const key = DRESS_TYPES[dressType] && DRESS_TYPES[dressType].own;
  if (!key) return null;
  if (!Array.isArray(char[key])) char[key] = [];
  return char[key];
}

function isOwned(char, skinId) {
  const row = clothesRow(skinId);
  if (!row) return false;
  const list = ownList(char, Number(row.dressType));
  return !!list && list.some((id) => Number(id) === Number(skinId));
}

// 解锁一批皮肤 id。只处理已拥有角色名下的 1/2/3 类（酒店第 4 类与主城共享，不用记）。
// 幂等；返回发生变化的角色列表（去重）。
function unlockSkins(doc, skinIds) {
  const changed = [];
  for (const skinId of skinIds) {
    const row = clothesRow(skinId);
    if (!row) continue;
    const dressType = Number(row.dressType);
    const slot = DRESS_TYPES[dressType];
    if (!slot) continue; // dressType 4（酒店立绘）跟随主城皮肤，不单独解锁
    const char = (doc.characters || []).find((c) => Number(c.character_id) === Number(row.charBelong));
    if (!char) continue; // 还没抽到/添加这个角色：皮肤先记不下，等角色到手再解锁
    const list = ownList(char, dressType);
    if (list.some((id) => Number(id) === Number(skinId))) continue;
    list.push(Number(skinId));
    if (!changed.includes(char)) changed.push(char);
  }
  return changed;
}

// 解锁某角色的全部皮肤（编辑器/控制台用）。省略 charId 时对全部已拥有角色生效。
// 返回 { chars, added }：chars 是发生变化的角色，added 是新解锁的皮肤数量。
function unlockAllSkins(doc, charId = null) {
  const targets = charId
    ? (doc.characters || []).filter((c) => Number(c.character_id) === Number(charId))
    : (doc.characters || []).slice();
  const chars = [];
  let added = 0;
  for (const char of targets) {
    const ids = [];
    for (const [, r] of gd.rows('d_char_clothes')) {
      if (Number(r.charBelong) !== Number(char.character_id)) continue;
      if (!DRESS_TYPES[Number(r.dressType)]) continue; // 第 4 类跟随主城
      ids.push(Number(r.id));
    }
    const before = countOwned(char);
    unlockSkins(doc, ids);
    const delta = countOwned(char) - before;
    if (delta > 0) {
      added += delta;
      if (!chars.includes(char)) chars.push(char);
    }
  }
  return { chars, added };
}

function countOwned(char) {
  return (char.own_character_skin_ids || []).length
    + (char.own_mecha_skin_ids || []).length
    + (char.own_city_skin_ids || []).length;
}

// 某角色可解锁的皮肤总数（战斗/机甲/主城三类；酒店第 4 类与主城共享解锁，不计入）。
// 编辑器目录用它画解锁进度。
function skinTotalForCharacter(charId) {
  let total = 0;
  for (const [, r] of gd.rows('d_char_clothes')) {
    if (Number(r.charBelong) !== Number(charId)) continue;
    if (DRESS_TYPES[Number(r.dressType)]) total += 1;
  }
  return total;
}

// 迁移（幂等）：① 兜底四个皮肤字段（老存档可能整段缺失）；
// ② 把 dressInitial==1 的默认皮肤写进解锁列表（客户端把「默认也判解锁」的分支注释掉了）；
// ③ 背包里躺着的皮肤卡全部就地解锁 —— 皮肤卡的「使用」链路修好之前玩家可能已经拿到过
//    皮肤卡却一直显示未解锁（本次修复的原始诉求），加载时自动补齐，不用玩家重新点使用。
// 返回发生变化的角色列表。
function migrateSkins(doc) {
  const changed = [];
  const touch = (char) => { if (!changed.includes(char)) changed.push(char); };
  // 背包里全部皮肤卡能解锁的皮肤 id（一次收集，别按角色重复扫背包）
  const bagSkinIds = new Set();
  for (const it of (doc.bag && Array.isArray(doc.bag.items) ? doc.bag.items : [])) {
    for (const id of skinItemSkinIds(it.item_id)) bagSkinIds.add(id);
  }
  for (const char of doc.characters || []) {
    const before = JSON.stringify([
      char.own_character_skin_ids, char.own_mecha_skin_ids, char.own_city_skin_ids,
      char.character_skin_id, char.mecha_skin_id, char.city_skin_id,
    ]);
    for (const slot of Object.values(DRESS_TYPES)) {
      if (!Array.isArray(char[slot.own])) char[slot.own] = [];
      if (char[slot.worn] === undefined || char[slot.worn] === null) char[slot.worn] = 0;
    }
    unlockSkins(doc, Object.values(defaultSkinIds(char.character_id)));
    unlockSkins(doc, [...bagSkinIds]);
    const after = JSON.stringify([
      char.own_character_skin_ids, char.own_mecha_skin_ids, char.own_city_skin_ids,
      char.character_skin_id, char.mecha_skin_id, char.city_skin_id,
    ]);
    if (before !== after) touch(char);
  }
  return changed;
}

module.exports = {
  DRESS_TYPES, skinItemSkinIds, defaultSkinIds, isOwned,
  unlockSkins, unlockAllSkins, migrateSkins, clothesRow, skinTotalForCharacter,
};
