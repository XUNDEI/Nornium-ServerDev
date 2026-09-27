// 存档编辑器：/editor 静态页面 + /editor/api/* JSON 接口。
//
// 与游戏客户端共占 9089 端口，但信封互不影响：
//   - 游戏客户端路由（/client/*）在 httpgate.js 里原样保留；
//   - /editor/api/* 用 { code: 0, data } / { code: 1, msg } 自己的信封。
//
// 写档的两条路（在线感知）：
//   - 账号当前在线（handlers/login.js 的 onlineAccounts 里有会话）→ 直接改
//     session.player（就是游戏此刻用的那份内存 doc），savePlayer 落盘，并推送
//     ntf_item_info / ntf_character_info / ntf_mall_info，游戏内**立刻生效**；
//   - 离线 → loadPlayer → 改 → savePlayer，玩家重新登录后生效。
// 编辑器不排空会话、不进维护窗口（只有 export 会进，因为它要一份一致的磁盘快照）。
const fs = require('fs');
const path = require('path');
const store = require('./store');
const gd = require('./gamedata');
const log = require('./logger');
const items = require('./game/items');
const talent = require('./game/talent');
const arsenal = require('./game/arsenal');
const skins = require('./game/skins');
const playerNew = require('./game/player_new');
const mallGame = require('./game/mall');
const weaponData = require('./game/weapon_data');
const { liveSessionCount, kickAllSessions } = require('./session');
const { onlineAccounts } = require('./handlers/login');
const consoleCmds = require('./console');
const { version } = require('../package.json');

const editorDir = path.join(__dirname, '..', 'editor');
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.json': 'application/json; charset=utf-8',
};

function word(id) {
  const row = gd.query('d_word_cn', id);
  return row ? row.text : '';
}

// ------------------------------------------------------------ 目录（给前端选择器）

// 等级 ↔ 经验换算所需的最小数据：让前端能双向换算并显示上限，而不必自己去读 109 张表。
//   role_exp / weapon_exp[rarity] 都是长度 90 的数组，下标 i（0 起）对应 d_*_level 里
//   id = i+1 的那一行，即「从 i+1 级升到 i+2 级所需经验」；等级 1 = 0 经验。
//   caps[break_times] = 该突破次数下的等级上限（两张表实测一致：20/40/50/60/70/80）。
function levelingTables() {
  const roleExp = [];
  for (const [, r] of gd.rows('d_role_level')) roleExp[Number(r.id) - 1] = Number(r.exp) || 0;
  const weaponExp = {};
  for (const [, r] of gd.rows('d_weapon_level')) {
    for (let rarity = 1; rarity <= 7; rarity += 1) {
      const key = `exp${rarity}`;
      if (r[key] === undefined) continue;
      weaponExp[rarity] = weaponExp[rarity] || [];
      weaponExp[rarity][Number(r.id) - 1] = Number(r[key]) || 0;
    }
  }
  const caps = [];
  for (const [, r] of gd.rows('d_role_levelbreak')) caps[Number(r.levelbreak)] = Number(r.level) || 1;
  for (const [, r] of gd.rows('d_weapon_levelbreak')) {
    if (caps[Number(r.levelbreak)] === undefined) caps[Number(r.levelbreak)] = Number(r.level) || 1;
  }
  return {
    caps: caps.map((v) => v || 1),
    max_break: Math.max(0, ...Object.keys(caps).map(Number)),
    role_exp: roleExp,
    weapon_exp: weaponExp,
  };
}

let catalogCache = null;
function catalog() {
  if (catalogCache) return catalogCache;
  const cat = { items: [], weapons: [], furniture: [], characters: [], leveling: levelingTables() };
  for (const [, r] of gd.rows('d_bag_item')) {
    cat.items.push({
      id: r.id, name: word(r.itemName) || `#${r.id}`,
      item_type: r.itemType, sub_type: r.subType, rarity: r.rarity ?? 0,
    });
  }
  for (const [, r] of gd.rows('d_bag_item_weapon')) {
    const wrow = gd.query('d_weapon', r.id) || {};
    cat.weapons.push({
      id: r.id, name: word(r.itemName) || `#${r.id}`, sub_type: r.subType, rarity: r.rarity ?? 0,
      max_refine: Number(wrow.maxRefine) || 4,
      // released=false 的武器在客户端没有模型/图标/技能行，发下去会让武器详情面板崩，
      // 所以编辑器不给发（见 game/weapon_data.js）。
      released: weaponData.isReleasedWeapon(r.id),
    });
  }
  for (const [, r] of gd.rows('d_bag_item_furniture')) {
    cat.furniture.push({ id: r.id, name: word(r.itemName) || `#${r.id}`, rarity: r.rarity ?? 0 });
  }
  for (const [, r] of gd.rows('d_character')) {
    if (!playerNew.isPlayableCharacter(r.id)) continue;
    const talentIds = talent.allTalentIds(r.id);
    cat.characters.push({
      id: r.id, name: word(r.name) || `#${r.id}`,
      profession: r.profession, first_weapon: r.firstWeapon,
      // 该角色的【星位之钉】（= d_character.inbornItem）与星位总数。前端「发放命座」
      // 直接用它们，不需要自己读表（见 game/talent.js）。
      inborn_item: Number(r.inbornItem) || 0,
      talent_total: talentIds.length,
      // 该角色的皮肤总数（战斗/机甲/主城三类；酒店立绘与主城共享解锁，不重复计）。
      // 前端「解锁该角色全部皮肤」按钮与解锁进度用它。
      skin_total: skins.skinTotalForCharacter(r.id),
      // 与该角色武器类型匹配、且已实装的最高稀有度武器（arsenal 的口径），
      // 前端「发放该武器」单发按钮直接用；批量发放走 grant_high_rarity_weapons。
      best_weapon: arsenal.bestWeaponForCharacter(r.id),
    });
  }
  catalogCache = cat;
  return cat;
}

// ------------------------------------------------------------ 档案视图

function accountSummaries() {
  store.loadAccounts();
  const names = {};
  for (const rec of Object.values(store.allAccounts())) {
    names[rec.account_id] = rec.account_name;
  }
  const list = [];
  for (const id of store.listPlayerIds()) {
    let mtime = 0;
    try { mtime = fs.statSync(store.playerPath(id)).mtimeMs; } catch (_) { /* gone */ }
    const doc = store.loadPlayer(id);
    if (!doc) continue;
    list.push({
      account_id: id,
      account_name: names[id] || `#${id}`,
      player_name: doc.player.player_name,
      characters: (doc.characters || []).length,
      bag_items: (doc.bag.items || []).length,
      online: !!(onlineAccounts.get(id) && !onlineAccounts.get(id).closed),
      mtime,
    });
  }
  list.sort((a, b) => b.mtime - a.mtime);
  return list;
}

// ------------------------------------------------------------ 编辑操作

const asInt = (v) => (Number.isFinite(Number(v)) ? Math.trunc(Number(v)) : null);

class OpError extends Error {}

function findChar(doc, charId) {
  const char = (doc.characters || []).find((c) => c.character_id === asInt(charId));
  if (!char) throw new OpError(`角色 ${charId} 不在该存档中`);
  return char;
}

// 按 uuid 找武器/防具实例：先背包后角色装备（与 handlers/character.js 的
// findGearByUuid 同序，保证「客户端点的是哪件，编辑器改的就是哪件」）。
function findGear(doc, uuid) {
  const want = asInt(uuid);
  const inBag = (doc.bag.items || []).find((it) => Number(it.item_uuid) === want);
  if (inBag) return inBag;
  for (const c of doc.characters || []) {
    if (c.weapon_info && Number(c.weapon_info.item_uuid) === want) return c.weapon_info;
    for (const a of c.arm_infos || []) {
      if (Number(a.item_uuid) === want) return a;
    }
  }
  return null;
}

// ------------------------------------------------------------ 等级 ↔ 经验
//
// 与客户端逐字同语义（_Game/Utils/UIUtils.lua）：
//   GetCharacterLevel / GetCharacterAllExp  →  d_role_level[].exp
//   GetWeaponLevel    / GetWeaponAllExp     →  d_weapon_level[].exp<rarity>
// 两张表的行 id = i 表示「从 i 级升到 i+1 级所需经验」，等级 1 = 0 经验，
// 所以等级 L 的最低经验 = Σ(row.id < L) row.exp。
// 等级上限来自突破表：d_role_levelbreak[roleId, levelbreak].level /
// d_weapon_levelbreak[weaponId, levelbreak].level。
function expForLevel(tableName, expKey, level) {
  let sum = 0;
  for (const [, r] of gd.rows(tableName)) {
    if (Number(r.id) < level) sum += Number(r[expKey]) || 0;
  }
  return sum;
}

function levelCapIn(tableName, keyField, keyValue, breakTimes) {
  for (const [, r] of gd.rows(tableName)) {
    if (Number(r[keyField]) !== Number(keyValue)) continue;
    if (Number(r.levelbreak) !== Number(breakTimes)) continue;
    return Number(r.level) || 1;
  }
  return 1;
}

// 经验 → 等级（与客户端 UIUtils.GetWeaponLevel / GetCharacterLevel 的循环同语义）。
function levelFromExp(tableName, expKey, exp) {
  let level = 1;
  let left = Number(exp) || 0;
  const rows = gd.rows(tableName).map(([, r]) => r).sort((a, b) => Number(a.id) - Number(b.id));
  for (const r of rows) {
    const need = Number(r[expKey]) || 0;
    if (left < need) break;
    left -= need;
    level += 1;
  }
  return level;
}

// 角色最大突破次数：客户端 UIUtils.GetCharacterMaxBreakTimes 读的是 d_com_params[12].value2。
function characterMaxBreakTimes() {
  const row = gd.query('d_com_params', 12);
  return Number(row && row.value2) || 5;
}

// 武器最大突破次数：客户端 GetWeaponMaxBreakTimes 扫 d_weapon_levelbreak 里该武器的最大 levelbreak。
function weaponMaxBreakTimes(weaponId) {
  let max = 0;
  for (const [, r] of gd.rows('d_weapon_levelbreak')) {
    if (Number(r.weaponId) !== Number(weaponId)) continue;
    max = Math.max(max, Number(r.levelbreak) || 0);
  }
  return max;
}

function ensureGachaState(doc, typeId) {
  doc.gacha.type_infos[typeId] = doc.gacha.type_infos[typeId] || {
    no_up_times: 0, no_5p_times: 0, total_times: 0, free_seconds: 0, choose_times: 0, records: [],
  };
  return doc.gacha.type_infos[typeId];
}

// 每个操作都往 ctx 里累积推送载荷：itemDelta（changed_item_infos）、
// chars（整个角色对象）、mallChanged（需要重推 ntf_mall_info）。
function applyOp(doc, op, ctx) {
  const kind = String(op.op || '');
  const delta = (entry) => ctx.itemDelta.changed_item_infos.push(entry);
  switch (kind) {
    case 'set_currency': {
      const itemId = asInt(op.item_id);
      const count = asInt(op.count);
      if (!itemId || count === null || count < 0) throw new OpError('set_currency 需要 item_id 与非负 count');
      if (items.itemKind(itemId) !== 'stack') throw new OpError(`道具 ${itemId} 不是可堆叠物品`);
      const entry = items.findStackEntry(doc, itemId);
      const old = entry ? entry.count : 0;
      if (!entry && count > 0) {
        const ne = items.makeItem(doc, itemId, count);
        doc.bag.items.push(ne);
        delta({ item_id: itemId, count: count - old, item_uuid: String(ne.item_uuid) });
      } else if (entry) {
        entry.count = count;
        delta({ item_id: itemId, count: count - old, item_uuid: String(entry.item_uuid) });
        if (count === 0) doc.bag.items.splice(doc.bag.items.indexOf(entry), 1);
      }
      return `货币 ${itemId} → ${count}`;
    }
    case 'add_item': {
      const itemId = asInt(op.item_id);
      const count = asInt(op.count);
      if (!itemId || !count) throw new OpError('add_item 需要 item_id 与非零 count');
      if (!items.itemConfig(itemId)) throw new OpError(`未知道具 ${itemId}`);
      if (items.itemKind(itemId) === 'weapon' && !weaponData.isReleasedWeapon(itemId)) {
        throw new OpError(`武器 ${itemId} 未实装（客户端没有模型/图标/技能行，发下去会让武器详情面板崩），已拒绝`);
      }
      if (count < 0 && items.itemKind(itemId) !== 'stack') throw new OpError('武器/装备只支持正向发放');
      const payload = items.grantItems(doc, [{ item_id: itemId, count }]);
      for (const e of payload.changed_item_infos) delta(e);
      return `道具 ${itemId} ×${count > 0 ? '+' : ''}${count}`;
    }
    case 'set_item_count': {
      const uuid = asInt(op.item_uuid);
      const count = asInt(op.count);
      if (!uuid || count === null || count < 0) throw new OpError('set_item_count 需要 item_uuid 与非负 count');
      const entry = doc.bag.items.find((it) => Number(it.item_uuid) === uuid);
      if (!entry) throw new OpError(`背包里没有 uuid=${uuid} 的道具`);
      const old = entry.count;
      if (count === 0) {
        doc.bag.items.splice(doc.bag.items.indexOf(entry), 1);
      } else {
        entry.count = count;
      }
      delta({ item_id: entry.item_id, count: count - old, item_uuid: String(uuid) });
      return `道具 ${entry.item_id} 数量 ${old} → ${count}`;
    }
    case 'remove_item': {
      const uuid = asInt(op.item_uuid);
      if (!uuid) throw new OpError('remove_item 需要 item_uuid');
      const idx = doc.bag.items.findIndex((it) => Number(it.item_uuid) === uuid);
      if (idx < 0) throw new OpError(`背包里没有 uuid=${uuid} 的道具`);
      const [entry] = doc.bag.items.splice(idx, 1);
      delta({ item_id: entry.item_id, count: -entry.count, item_uuid: String(uuid) });
      return `删除道具 ${entry.item_id}`;
    }
    case 'set_player_name': {
      const name = String(op.name || '').trim();
      if (!name || name.length > 20) throw new OpError('昵称需要 1..20 个字符');
      doc.player.player_name = name;
      ctx.relogNote = '昵称在重新登录后显示';
      return `昵称 → ${name}`;
    }
    case 'edit_character': {
      const char = findChar(doc, op.character_id);
      if (op.exp !== undefined) {
        const exp = asInt(op.exp);
        if (exp === null || exp < 0) throw new OpError('exp 必须是非负整数');
        char.exp = exp;
      }
      if (op.break_times !== undefined) {
        const bt = asInt(op.break_times);
        const maxBt = characterMaxBreakTimes();
        if (bt === null || bt < 0 || bt > maxBt) throw new OpError(`break_times 必须 0..${maxBt}`);
        char.break_times = bt;
      }
      if (op.weapon) {
        if (!char.weapon_info) throw new OpError('该角色没有装备武器');
        const w = char.weapon_info;
        if (op.weapon.exp !== undefined) {
          const exp = asInt(op.weapon.exp);
          if (exp === null || exp < 0) throw new OpError('武器 exp 必须是非负整数');
          w.weapon_info.exp = exp;
        }
        if (op.weapon.break_times !== undefined) {
          const bt = asInt(op.weapon.break_times);
          const maxBt = weaponMaxBreakTimes(w.item_id);
          if (bt === null || bt < 0 || bt > maxBt) throw new OpError(`武器 break_times 必须 0..${maxBt}`);
          w.weapon_info.break_times = bt;
        }
        if (op.weapon.refine_level !== undefined) {
          const rl = asInt(op.weapon.refine_level);
          const maxR = (gd.query('d_weapon', w.item_id) || {}).maxRefine ?? 4;
          if (rl === null || rl < 0 || rl > maxR) throw new OpError(`refine_level 必须 0..${maxR}`);
          w.weapon_info.refine_level = rl;
        }
        // 已装备武器：ntf_character_info（下面 ctx.chars）会整份替换客户端角色对象，
        // 已经带上新的 weapon_info；这里不再重复推 ntf_item_info。
      }
      ctx.chars.push(char);
      return `角色 ${op.character_id} 已更新`;
    }
    // 直接按「等级」设置角色（前端更好用）：经验由等级反推，与客户端同一张表、同一套语义。
    case 'set_character_level': {
      const char = findChar(doc, op.character_id);
      let bt = Number(char.break_times) || 0;
      if (op.break_times !== undefined) {
        const v = asInt(op.break_times);
        const maxBt = characterMaxBreakTimes();
        if (v === null || v < 0 || v > maxBt) throw new OpError(`break_times 必须 0..${maxBt}`);
        bt = v;
      }
      let level = asInt(op.level);
      if (level === null || level < 1) throw new OpError('level 必须是 >= 1 的整数');
      const cap = levelCapIn('d_role_levelbreak', 'roleId', char.character_id, bt);
      let note = '';
      if (level > cap) {
        note = `（受突破 ${bt} 的等级上限 ${cap} 限制，已夹取）`;
        level = cap;
      }
      char.break_times = bt;
      char.exp = expForLevel('d_role_level', 'exp', level);
      ctx.chars.push(char);
      return `角色 ${char.character_id} 等级 → ${level}${note}`;
    }
    // 按 uuid 改任意一件武器（背包里躺着的也行）的等级 / 突破 / 光淬阶数。
    case 'set_weapon_stats': {
      const uuid = asInt(op.item_uuid);
      if (!uuid) throw new OpError('set_weapon_stats 需要 item_uuid');
      const gear = findGear(doc, uuid);
      if (!gear) throw new OpError(`存档里没有 uuid=${uuid} 的道具`);
      if (!gear.weapon_info) throw new OpError(`uuid=${uuid} 不是武器（item_id=${gear.item_id}）`);
      const cfg = gd.query('d_bag_item_weapon', gear.item_id) || {};
      const rarity = Number(cfg.rarity) || 1;
      const maxR = (gd.query('d_weapon', gear.item_id) || {}).maxRefine ?? 4;
      const maxBt = weaponMaxBreakTimes(gear.item_id);

      let bt = Number(gear.weapon_info.break_times) || 0;
      if (op.break_times !== undefined) {
        const v = asInt(op.break_times);
        if (v === null || v < 0 || v > maxBt) throw new OpError(`武器 break_times 必须 0..${maxBt}`);
        bt = v;
      }
      const notes = [];
      // level / exp 互斥，exp 优先（它是存档里真正存的值；level 只是换算糖）。
      if (op.level !== undefined && op.exp === undefined) {
        let level = asInt(op.level);
        if (level === null || level < 1) throw new OpError('武器 level 必须是 >= 1 的整数');
        const cap = levelCapIn('d_weapon_levelbreak', 'weaponId', gear.item_id, bt);
        if (level > cap) {
          notes.push(`等级受突破 ${bt} 的上限 ${cap} 限制，已夹取`);
          level = cap;
        }
        gear.weapon_info.exp = expForLevel('d_weapon_level', `exp${rarity}`, level);
        notes.unshift(`等级 → ${level}`);
      } else if (op.exp !== undefined) {
        const exp = asInt(op.exp);
        if (exp === null || exp < 0) throw new OpError('武器 exp 必须是非负整数');
        gear.weapon_info.exp = exp;
        const cap = levelCapIn('d_weapon_levelbreak', 'weaponId', gear.item_id, bt);
        notes.unshift(`经验 → ${exp}（等级 ${Math.min(cap, levelFromExp('d_weapon_level', `exp${rarity}`, exp))}）`);
      }
      if (op.refine_level !== undefined) {
        const rl = asInt(op.refine_level);
        if (rl === null || rl < 0 || rl > maxR) throw new OpError(`光淬阶数必须 0..${maxR}`);
        gear.weapon_info.refine_level = rl;
        notes.push(`光淬 → ${rl} 阶`);
      }
      gear.weapon_info.break_times = bt;
      if (op.break_times !== undefined) notes.push(`突破 → ${bt}`);

      // 在线推送：count=0 才会命中客户端 BackpackSystem.lua:384 的「整条替换」分支
      // （否则 count 会被当成增量累加）；已装备的那件走 :354 分支同样会刷新。
      // count=0 也顺带绕过 :408 起的「道具使用」逻辑，不会误触发消耗品行为。
      ctx.itemDelta.changed_item_infos.push({
        item_id: gear.item_id,
        count: 0,
        item_uuid: String(gear.item_uuid),
        weapon_info: gear.weapon_info,
      });
      return `武器 ${gear.item_id}（uuid ${uuid}）${notes.join('，') || '无改动'}`;
    }
    case 'add_character': {
      const charId = asInt(op.character_id);
      if (!playerNew.isPlayableCharacter(charId)) throw new OpError(`角色 ${charId} 不是可玩角色`);
      if ((doc.characters || []).some((c) => c.character_id === charId)) return `角色 ${charId} 已拥有，跳过`;
      const char = playerNew.buildCharacter(doc, charId);
      doc.characters.push(char);
      ctx.chars.push(char);
      return `新角色 ${charId}（含初始武器与技能）`;
    }
    case 'add_all_characters': {
      const owned = new Set((doc.characters || []).map((c) => c.character_id));
      const added = [];
      for (const charId of playerNew.initialCharacterIds()) {
        if (owned.has(charId)) continue;
        const char = playerNew.buildCharacter(doc, charId);
        doc.characters.push(char);
        ctx.chars.push(char);
        added.push(charId);
      }
      return added.length ? `新增角色 ${added.length} 个` : '全部角色已拥有';
    }
    // 高稀有度武器每种各发一把（已实装的 6★/7★）。旧名 grant_best_weapons 保留为别名，
    // 但行为已按新口径 —— 不再猜「谁的专武」，见 game/arsenal.js。
    case 'grant_high_rarity_weapons':
    case 'grant_best_weapons': {
      const { granted, deltas } = arsenal.grantHighRarityWeapons(doc, { skipOwned: op.skip_owned === true });
      for (const p of deltas) for (const e of p.changed_item_infos) delta(e);
      return granted.length
        ? `发放高稀有度武器 ${granted.length} 把（${granted.filter((g) => g.rarity >= 7).length} 把 7★，入包不自动装备）`
        : '没有需要发放的武器';
    }
    case 'set_gacha_pity': {
      const typeId = asInt(op.pool_type);
      const value = asInt(op.no_up_times);
      if (!typeId || value === null || value < 0) throw new OpError('set_gacha_pity 需要 pool_type 与非负 no_up_times');
      ensureGachaState(doc, typeId).no_up_times = value;
      ctx.relogNote = '保底计数在重新登录后刷新';
      return `${typeId} 号池保底计数 → ${value}`;
    }
    case 'set_charge_point': {
      const value = asInt(op.value);
      if (value === null || value < 0) throw new OpError('set_charge_point 需要非负 value');
      doc.mall.charge_point = value;
      ctx.mallChanged = true;
      return `累充积分 → ${value}`;
    }
    case 'set_month_card': {
      const days = asInt(op.days);
      if (days === null || days < 0 || days > 3650) throw new OpError('set_month_card 需要 0..3650 的 days（0=清空月卡）');
      const now = Math.floor(Date.now() / 1000);
      const base = Math.max(doc.mall.month_card_expire || 0, now);
      doc.mall.month_card_expire = days === 0 ? 0 : base + days * 86400;
      doc.mall.month_card_last_tick = 0; // 当天奖励立即可领（客户端见到 0 会自己来请求）
      ctx.mallChanged = true;
      return days === 0 ? '月卡已清空' : `月卡延长 ${days} 天`;
    }
    case 'send_mail': {
      const title = String(op.title || '').trim();
      const content = String(op.content || '').trim();
      if (!title) throw new OpError('send_mail 需要标题');
      if (!content) throw new OpError('send_mail 需要正文（换行写 @n，见坑 32）');
      const attachments = Array.isArray(op.attachments) ? op.attachments : [];
      const itemInfos = attachments.map((a) => {
        const itemId = asInt(a.item_id);
        const count = asInt(a.count);
        if (!itemId || !count || count <= 0 || !items.itemConfig(itemId)) {
          throw new OpError(`附件不合法：${JSON.stringify(a)}`);
        }
        return { item_id: itemId, count };
      });
      const uuid = doc.mail.next_uuid || 1003;
      doc.mail.next_uuid = uuid + 1;
      doc.mail.list.push({
        send_seconds: String(Math.floor(Date.now() / 1000)),
        mail_uuid: uuid,
        title,
        content,
        type: '系统',
        item_infos: itemInfos,
        mail_state: 0,
      });
      ctx.relogNote = '新邮件在重新登录后可见';
      return `邮件「${title}」已投递（附件 ${itemInfos.length} 项）`;
    }
    // 发放「星位之钉」（玩家口中的命座）：道具 id 来自 d_character.inbornItem，
    // 与角色的武器类型一一对应（莎乐美<礼器> → 1207002 …）。玩家进游戏后在角色页
    // 的「星位」页签用它点亮 6 个命座孔（服务端口径见 game/talent.js）。
    case 'grant_constellation': {
      const charId = asInt(op.character_id);
      const count = asInt(op.count ?? 1);
      if (!charId || count === null || count < 0) throw new OpError('grant_constellation 需要 character_id 与非负 count');
      const nail = talent.nailItemId(charId);
      if (!nail) throw new OpError(`角色 ${charId} 没有星位之钉（d_character.inbornItem 为空）`);
      if (count === 0) return `角色 ${charId}：发放数量为 0，跳过`;
      const ntf = items.grantItems(doc, [{ item_id: nail, count }]);
      for (const e of ntf.changed_item_infos) delta(e);
      return `星位之钉 ${nail}（${word((gd.query('d_character', charId) || {}).name)}）×${count}`;
    }
    case 'grant_all_constellations': {
      const count = asInt(op.count ?? 1);
      if (count === null || count < 0) throw new OpError('grant_all_constellations 需要非负 count');
      if (count === 0) return '发放数量为 0，跳过';
      const granted = [];
      for (const [, r] of gd.rows('d_character')) {
        if (!playerNew.isPlayableCharacter(r.id)) continue;
        const nail = Number(r.inbornItem) || 0;
        if (!nail) continue;
        const ntf = items.grantItems(doc, [{ item_id: nail, count }]);
        for (const e of ntf.changed_item_infos) delta(e);
        granted.push(nail);
      }
      return granted.length
        ? `全部角色各发星位之钉 ×${count}（共 ${granted.length} 种：${granted.join(',')}）`
        : '没有可发放的星位之钉';
    }
    // 直接点亮星位（跳过前置与消耗）。character_id 省略时对全部已拥有角色生效。
    case 'unlock_all_talents': {
      const charId = op.character_id === undefined || op.character_id === null ? null : asInt(op.character_id);
      const targets = charId
        ? [findChar(doc, charId)]
        : (doc.characters || []);
      if (!targets.length) throw new OpError('该存档还没有任何角色');
      let total = 0;
      const names = [];
      for (const char of targets) {
        const added = talent.unlockAll(char);
        if (!added.length) continue;
        total += added.length;
        names.push(`${char.character_id}+${added.length}`);
        if (!ctx.chars.includes(char)) ctx.chars.push(char);
      }
      if (!total) return '所有角色的星位都已点亮';
      return `点亮星位 ${total} 个（角色累计：${names.join('，')}）`;
    }
    // 直接解锁皮肤（不发皮肤卡道具；游戏内角色页「装扮」即可换）。character_id 省略时
    // 对全部已拥有角色生效。写的是角色的 own_character_skin_ids / own_mecha_skin_ids /
    // own_city_skin_ids，客户端 ntf_character_info（整体替换）与重登都会带上。
    case 'unlock_all_skins': {
      const charId = op.character_id === undefined || op.character_id === null ? null : asInt(op.character_id);
      if (charId) findChar(doc, charId); // 存在性校验（与其它 op 同一报错口径）
      if (!charId && !(doc.characters || []).length) throw new OpError('该存档还没有任何角色');
      const { chars, added } = skins.unlockAllSkins(doc, charId);
      for (const char of chars) if (!ctx.chars.includes(char)) ctx.chars.push(char);
      if (!added) return '相关角色的皮肤都已解锁';
      return charId
        ? `角色 ${charId} 新解锁皮肤 ${added} 个`
        : `全部角色新解锁皮肤 ${added} 个（涉及 ${chars.length} 名角色）`;
    }
    default:
      throw new OpError(`未知操作 ${kind}`);
  }
}

// ------------------------------------------------------------ HTTP 处理

function sendJson(res, obj, status = 200) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(obj));
}

const ok = (res, data) => sendJson(res, { code: 0, data: data ?? {} });
const fail = (res, msg, status = 200) => sendJson(res, { code: 1, msg: String(msg) }, status);

async function handleUpdate(req, res, accountId, body) {
  const ops = body && Array.isArray(body.ops) ? body.ops : null;
  if (!ops || ops.length === 0) return fail(res, '缺少 ops 数组');
  if (ops.length > 200) return fail(res, '一次最多 200 个操作');

  const session = onlineAccounts.get(accountId);
  const live = !!(session && !session.closed);
  const doc = live ? session.player : store.loadPlayer(accountId);
  if (!doc) return fail(res, `账号 ${accountId} 还没有玩家档案`);

  const ctx = { itemDelta: { changed_item_infos: [] }, chars: [], mallChanged: false, relogNote: null };
  const notes = [];
  let error = null;
  // 部分应用也要落盘：在线会话的内存 doc 里前几个操作已经生效（dailyTick 迟早把它写回），
  // 只有「磁盘 = 内存」才不会出现两边不一致的档。出错的操作本身在改内存前就已抛出。
  for (const op of ops) {
    try {
      notes.push(applyOp(doc, op, ctx));
    } catch (err) {
      if (err instanceof OpError) { error = err.message; break; }
      throw err;
    }
  }

  store.savePlayer(doc);

  if (live) {
    if (ctx.itemDelta.changed_item_infos.length > 0) {
      session.send('ntf_item_info', ctx.itemDelta);
    }
    for (const char of ctx.chars) {
      session.send('ntf_character_info', { changed_character_infos: [char] });
    }
    if (ctx.mallChanged) {
      // ntf_mall_info 必须整体带 month_card_info（坑 24），直接复用 mall 的构建器
      const info = mallGame.buildMallListInfo(doc);
      session.send('ntf_mall_info', { mall_infos: info.mall_infos, month_card_info: info.month_card_info });
    }
  }

  log.info(`[editor] 账号 ${accountId}：${ops.length} 个操作（${error ? '部分' : '全部'}应用，${live ? '在线生效' : '离线写档'}）`);
  ok(res, { live, notes, error, relog_note: ctx.relogNote });
}

async function handleExport(req, res, body, hooks) {
  const destInput = body ? body.path : null;
  const run = () => {
    if (destInput) {
      const result = store.exportData(destInput);
      return { dir: result.dir, players: result.players, accounts: result.accounts };
    }
    const snapshot = store.snapshotData('export');
    if (!snapshot) return null;
    return { dir: snapshot.dir, players: snapshot.players, accounts: true };
  };
  try {
    let result;
    if (hooks && typeof hooks.maintenance === 'function') {
      result = await hooks.maintenance(run);
    } else {
      result = run();
    }
    if (!result) return fail(res, '存档是空的，没有可导出的内容');
    log.info(`[editor] 存档已导出到 ${result.dir}`);
    ok(res, result);
  } catch (err) {
    fail(res, err.message);
  }
}

// ------------------------------------------------------------ 服务端管理
//
// 浏览器里的「服务」标签页用这几个接口。两条铁律：
//   ① 任何**动磁盘存档**的动作（清档 / 导入）必须走 index.js 注入的维护窗口
//      （停止 accept → 硬排空在线会话 → 改档 → 重新监听）。只 sleep 一小段是挡不住
//      残余会话的 savePlayer 回写的（见 REVERSE_ENGINEERING 坑 34）。
//   ② 「停止服务端」必须先把这个 HTTP 响应发出去，再关进程 —— 否则前端只会看到
//      连接被重置，玩家会以为按钮坏了。

// 维护窗口的降级包装（单测里没有 index.js 时只做一次 kick，不真的关进程）。
function runGated(hooks, fn) {
  const maintenance = hooks && hooks.maintenance;
  if (typeof maintenance === 'function') return maintenance(fn);
  const kicked = kickAllSessions(1);
  return Promise.resolve(fn({ kicked, remaining: 0 }));
}

function serverInfo(hooks) {
  const startedAt = Number(hooks && hooks.startedAt) || 0;
  return {
    online: liveSessionCount(),
    stats: store.dataStats(),
    data_dir: store.dataDirPath(),
    version,
    tcp_port: Number(hooks && hooks.tcpPort) || null,
    http_port: Number(hooks && hooks.httpPort) || null,
    started_at: startedAt,
    uptime_seconds: startedAt ? Math.floor((Date.now() - startedAt) / 1000) : 0,
    backups: store.listBackups().length,
    can_stop: typeof (hooks && hooks.onStop) === 'function',
    unreleased_weapons: weaponData.UNRELEASED_WEAPON_IDS.size,
  };
}

// ------------------------------------------------------------ 服务器控制台（网页端）

// GET /editor/api/console/tail?after=N：拉取缓冲里的日志历史（logger.tail 负责游标与截断）。
function handleConsoleTail(req, res) {
  const after = Number(new URL(req.url, 'http://x').searchParams.get('after')) || 0;
  const { lines, last, full } = log.tail(after);
  return ok(res, { lines, last, full, capacity: log.capacity });
}

// GET /editor/api/console/stream：SSE。先补 ?after= 之后的缓冲行，再实时推送；
// 每行是 logger 缓冲的原始条目 { seq, text }。req/res 任一端断开都要退订，
// 否则泄漏的订阅会把每一行日志写给一个死连接。
function handleConsoleStream(req, res) {
  const after = Number(new URL(req.url, 'http://x').searchParams.get('after')) || 0;
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/event-stream; charset=utf-8');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  if (typeof res.flushHeaders === 'function') res.flushHeaders();
  res.write('retry: 2000\n\n');
  for (const entry of log.tail(after).lines) {
    res.write(`data: ${JSON.stringify(entry)}\n\n`);
  }
  const unsubscribe = log.subscribe((entry) => {
    res.write(`data: ${JSON.stringify(entry)}\n\n`);
  });
  const heartbeat = setInterval(() => res.write(': ping\n\n'), 15000);
  const cleanup = () => {
    clearInterval(heartbeat);
    unsubscribe();
  };
  req.once('close', cleanup);
  res.once('close', cleanup);
}

// POST /editor/api/console/cmd { command }：网页端执行控制台指令，
// 决策与危险操作的维护窗口全部复用 src/console.js 的 handleCommand（与黑窗口同口径）。
// reply 同时打到 stdout（进日志缓冲），黑窗口与网页两个入口互相可见。
async function handleConsoleCmd(res, body, hooks) {
  const command = body && typeof body.command === 'string' ? body.command : '';
  if (!command.trim()) return fail(res, '指令不能为空');
  log.info(`[editor] 网页控制台执行：${command}`);
  const { action, reply } = await consoleCmds.handleCommand(command, hooks);
  if (reply) console.log(reply);
  if (action === 'stop') {
    const onStop = hooks && hooks.onStop;
    if (typeof onStop !== 'function') {
      return ok(res, { action: 'none', reply: `${reply}\n>> 当前进程没有提供停服钩子，无法停止（单测/嵌入模式）` });
    }
    // 与 /server/stop 相同的顺序：先回响应再退出，否则前端只会看到连接被重置。
    res.once('finish', () => setTimeout(() => {
      try { onStop(); } catch (err) { log.error('[editor] onStop 失败:', err.stack || err.message); }
    }, 150));
  }
  return ok(res, { action: action || 'none', reply: reply || '' });
}

async function handleServerAction(req, res, url, body, hooks) {
  const method = req.method || 'GET';
  if (method !== 'POST') return fail(res, '请用 POST');

  // 踢出所有在线玩家（reason=1 REPLACE：客户端会弹「账号在其他地方登录」并回登录界面）
  if (url === '/editor/api/server/kick') {
    const kicked = kickAllSessions(1);
    log.info(`[editor] 踢出全部在线玩家：${kicked} 个连接`);
    return ok(res, { kicked });
  }

  // 立即打一份快照（不进维护窗口：快照只是拷贝，不需要一致性保证）
  if (url === '/editor/api/server/backup') {
    const snapshot = store.snapshotData('manual');
    if (!snapshot) return fail(res, '存档是空的（没有 accounts.json 也没有玩家档案），没有可备份的内容');
    log.info(`[editor] 手动快照 → ${snapshot.dir}`);
    return ok(res, { dir: snapshot.dir, players: snapshot.players });
  }

  // 从快照/备份目录导入并热重载
  if (url === '/editor/api/server/load') {
    const input = body ? body.path : null;
    if (!input) return fail(res, '缺少 path（备份目录，或其上级）');
    const srcDir = store.resolveBackupSource(input);
    if (!srcDir) return fail(res, `在 "${input}" 里没找到 accounts.json，不像是存档备份目录`);
    if (path.resolve(srcDir) === path.resolve(store.dataDirPath())) {
      return fail(res, '那就是当前存档目录本身，没有可导入的内容');
    }
    try {
      const result = await runGated(hooks, () => {
        const snapshot = store.snapshotData('preimport');
        const imported = store.importData(srcDir);
        store.loadAccounts();
        return { imported, snapshot, stats: store.dataStats() };
      });
      log.info(`[editor] 从 ${srcDir} 导入存档：${result.imported.players} 个档案`);
      return ok(res, {
        dir: srcDir,
        accounts: result.imported.accounts,
        players: result.imported.players,
        snapshot: result.snapshot ? result.snapshot.dir : null,
        stats: result.stats,
      });
    } catch (err) {
      return fail(res, err.message);
    }
  }

  // 清空存档（危险）：必须显式带 confirm 字符串
  if (url === '/editor/api/server/restore') {
    if (!body || body.confirm !== '清空存档') {
      return fail(res, '危险操作：请在请求里带 confirm="清空存档"');
    }
    try {
      const before = store.dataStats();
      const result = await runGated(hooks, () => {
        // store.resetData 内部已经先 snapshotData('wipe')，不要再快照一次（会多留一份空目录）
        const snapshot = store.resetData();
        return { snapshot, stats: store.dataStats() };
      });
      log.warn('[editor] 存档已清空（网页端触发）');
      return ok(res, {
        before,
        after: result.stats,
        snapshot: result.snapshot ? result.snapshot.dir : null,
      });
    } catch (err) {
      return fail(res, err.message);
    }
  }

  // 停止服务端：先回响应，再关进程
  if (url === '/editor/api/server/stop') {
    const onStop = hooks && hooks.onStop;
    if (typeof onStop !== 'function') {
      return fail(res, '当前进程没有提供停服钩子（单测/嵌入模式下不可用）');
    }
    const kicked = kickAllSessions(1);
    log.warn(`[editor] 收到网页端停服请求：踢出 ${kicked} 个连接，即将退出`);
    // res.end() 之后 'finish' 才触发；再留 150ms 让内核把响应真正送出去。
    res.once('finish', () => setTimeout(() => {
      try { onStop(); } catch (err) { log.error('[editor] onStop 失败:', err.stack || err.message); }
    }, 150));
    return ok(res, { stopping: true, kicked });
  }

  return fail(res, `未知服务端接口 ${url}`);
}

async function handleApi(req, res, url, body, hooks) {
  const method = req.method || 'GET';
  if (url.startsWith('/editor/api/server/')) {
    return handleServerAction(req, res, url, body, hooks);
  }
  if (method === 'GET' && url === '/editor/api/server') {
    return ok(res, serverInfo(hooks));
  }
  if (method === 'GET' && url === '/editor/api/accounts') {
    return ok(res, { players: accountSummaries() });
  }
  if (method === 'GET' && url === '/editor/api/catalog') {
    return ok(res, catalog());
  }
  if (method === 'GET' && url === '/editor/api/backups') {
    return ok(res, { backups: store.listBackups() });
  }
  if (method === 'GET' && url === '/editor/api/console/tail') {
    return handleConsoleTail(req, res);
  }
  if (method === 'POST' && url === '/editor/api/console/cmd') {
    return handleConsoleCmd(res, body, hooks);
  }
  const playerMatch = url.match(/^\/editor\/api\/player\/(\d+)\/?(update)?$/);
  if (playerMatch) {
    const accountId = Number(playerMatch[1]);
    const session = onlineAccounts.get(accountId);
    const doc = (session && !session.closed) ? session.player : store.loadPlayer(accountId);
    if (!doc) return fail(res, `账号 ${accountId} 还没有玩家档案`);
    if (!playerMatch[2]) {
      return ok(res, { doc });
    }
    if (method !== 'POST') return fail(res, '请用 POST');
    return handleUpdate(req, res, accountId, body);
  }
  if (url === '/editor/api/export') {
    if (method !== 'POST') return fail(res, '请用 POST');
    return handleExport(req, res, body, hooks);
  }
  return fail(res, `未知接口 ${method} ${url}`);
}

function serveStatic(req, res, url) {
  let rel = url === '/editor' || url === '/editor/' ? 'index.html' : url.slice('/editor/'.length);
  rel = decodeURIComponent(rel).replace(/\\/g, '/').replace(/^\/+/, '');
  const file = path.resolve(editorDir, rel);
  if (!file.startsWith(editorDir + path.sep)) {
    return fail(res, 'forbidden', 403);
  }
  let data;
  try {
    data = fs.readFileSync(file);
  } catch (_) {
    res.statusCode = 404;
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    return res.end('404 Not Found');
  }
  const ext = path.extname(file).toLowerCase();
  res.setHeader('Content-Type', MIME[ext] || 'application/octet-stream');
  res.end(data);
}

// httpgate.js 把 /editor 前缀的请求全部交到这里。返回 true 表示已处理。
async function handle(req, res, url, body, hooks) {
  try {
    // SSE 不是 JSON 信封，必须在通用解析之前拦截（长连接，读 body 也没有意义）
    if (url === '/editor/api/console/stream' && (req.method || 'GET') === 'GET') {
      handleConsoleStream(req, res);
      return true;
    }
    if (url === '/editor/api/export' || url.startsWith('/editor/api/')) {
      let parsed = null;
      if (body && body.length > 0 && (req.method === 'POST' || req.method === 'PUT')) {
        try {
          parsed = JSON.parse(body.toString('utf8'));
        } catch (_) {
          return fail(res, '请求体不是合法 JSON');
        }
      }
      await handleApi(req, res, url, parsed, hooks);
    } else if (req.method === 'GET' || req.method === 'HEAD') {
      serveStatic(req, res, url);
    } else {
      fail(res, 'method not allowed', 405);
    }
    return true;
  } catch (err) {
    log.error('[editor] 处理失败:', err.stack || err.message);
    if (!res.writableEnded) fail(res, `服务器内部错误：${err.message}`);
    return true;
  }
}

module.exports = { handle };
