// 武器数据可用性：区分「能正常显示/使用的武器」与被打包进客户端、但没有实装的幽灵武器。
//
// 背景（2026-09-25 全量核对，复跑工具见 tools/check_weapon_assets.js）：
// 客户端的 d_bag_item_weapon 里有 83 行，其中 10 把是**未实装**的残件——有数据行，
// 但 pak 里既没有模型、也没有图标、也没有展示图；其中 7 把连 d_skill 里的技能行都没有。
//
// 症状（实测 UE 日志 %LOCALAPPDATA%\Nornium\Saved\Logs\Nornium.log）：
//   LogStreaming: Error: Couldn't find file for package /Game/_Game/Blueprints/Weapons/Weapon/W_1081601
//   LogStreaming: Error: Couldn't find file for package .../Bag_weapon_img_res/Frames/img1081601_png
//   LogStreaming: Error: Couldn't find file for package .../Bag_weapon_res/Frames/icon1081601_png
//   LogUnLua: Warning: [Database.lua:37] table d_skill does not contain key 2000101!
//     UIUtils.lua:832: in function 'GetWeaponSkillDesc'
//     UI_Com_BagDetail_C.lua:123: in function 'RefreshUI'
// 最后这三行是致命的：UIUtils.GetWeaponSkillDesc 在 skillInfo 为 nil 时访问
// skillInfo.skillDesc 抛错，而调用点（UI_Com_BagDetail_C.lua:123）后面紧跟的
// SetText / RunePanel:Collapsed / 属性列表刷新全部被跳过，整个详情面板停在上一次状态
// （玩家看到的是 UMG 设计态的「文本块…」「30#星芒名字」，且没有「攻击力」行）。
//
// 官方自己也把这批排除在外：d_com_params[21]（客户端 GM `add_all` 的武器预设）不含它们，
// d_gacha_pool / d_mall / d_shop / 关卡掉落也都不含 —— 正常玩法拿不到，
// 只有本服早期版本的「发专武」（取同类型稀有度最高、并列取 id 最大）会踩中：
// 巨刃（subType 1）里 id 最大的 7★ 正是 1081601「颂歌」。
//
// 服务端无法替客户端补数据表（pak 内的 ClientDatas 覆盖 Saved/ 下的 loose 文件，
// 见 REVERSE_ENGINEERING 坑 14），所以只能：① 别再发放；② 把存档里已有的换掉（migrate）。
//
// 日后若 pak 补齐了这些资源，只需从 UNRELEASED_WEAPON_IDS 里裁掉对应 id ——
// skillHasRow() 这道数据驱动的检查会自动跟上。
const gd = require('../gamedata');

// 三样资源（模型 / 图标 / 展示图）全缺的 10 把。括号里是「所属 6★/7★ 组」。
const UNRELEASED_WEAPON_IDS = new Set([
  1040600, // 酒池的秘密 6★ 巨刃
  1041600, // 酒池的狰狞 7★ 巨刃
  1080601, // 挽歌      6★ 巨刃
  1081601, // 颂歌      7★ 巨刃  ← 本 bug 的当事人
  3050600, // 冥王天的干涉 6★ 长剑
  3051610, // 冥王天的秘语 7★ 长剑
  4061611, // 受命者的视觉 7★ 礼器
  2060600, // 衡量者     6★ 枪械
  4060601, // 医与毒之光  6★ 礼器
  6050601, // 退行的金星  6★ 佩刀
]);

// 「角色 → 专属武器」官方映射。每名可玩角色一个专武族，族内 6★（基础形态）与
// 7★（光淬/最终形态，d_weapon 数值与 6★ 完全相同，见 REVERSE_ENGINEERING 坑 39）
// 各一行；发放口径取 7★（d_character_trial 里骆十四娘的试用配枪就是 7★ 7070611）。
//
// 这张表不是猜的，四条游戏内证据交叉验证（2026-10-03，全部可复查）：
//   ① d_word_cn 的武器描述词条（id = 54 + 武器id）直接写明归属：
//      541070601「信风专武描述」、541060601「辩才姬专武描述」、543060601「折光专武描述」、
//      542050601「折光2专武描述」、544070601/544071611「理事卿专武描述」、
//      546060601「眠眠专武描述」、545070601/545071611「老板娘专武描述」
//      （老板娘=逆戟雀：她是唯一宝轮角色，其试用配枪 5040500 的描述就是「老板娘暂用描述」）；
//      542040601 是写好的正式文案「豌豆公主定做的专用步枪，这把名为青鸟的步枪……」。
//   ② d_character_trial.firstWeapon（试用配枪）：10101→3060601、10102→2050601、
//      10201→4070601、10401→6060601、10501→1070601、10601→2040601、10701→1060601、
//      10801→7070611。与 ① 完全吻合。
//   ③ d_gacha_schedule 武器UP池（2001-2004）的 upName 都成对出现同族 6★+7★
//      （如 [537070601, 537070611]），证实 6★/7★ 是同一把专武的两个形态。
//   ④ 11202 鱼啄雨→708 族（理线者/断线者）由排除法锁定：十族专武与十名可玩角色
//      一一对应，其余九族均已被 ①② 占用；她的试用配枪是通用 4★（解码之塔），无描述词条。
//
// 注意：1060601 的正式名是「惑人的蛇舌」（社区表格常误作「蛇音」）；10801 是「骆十四娘」。
const CHARACTER_EXCLUSIVE_WEAPONS = {
  10101: { base: 3060601, seven: 3060611 }, // 仿钻折光(长剑)：阿特拉斯™耀目 → 阿特拉斯™眩光
  10102: { base: 2050601, seven: 2051611 }, // 仿钻折光(枪械)：最初之泪 → 最初的蒸发
  10201: { base: 4070601, seven: 4071611 }, // 理事卿莎乐美(礼器)：受命者的视觉 → 总控者的视觉
  10301: { base: 5070601, seven: 5071611 }, // 逆戟雀(宝轮)：染掌之花 → 染掌之影
  10401: { base: 6060601, seven: 6061611 }, // 清凉院眠眠(佩刀)：羚辉 → 羚辉之辉
  10501: { base: 1070601, seven: 1071611 }, // 信风(巨刃)：将至必至之兆 → 灼星已现
  10601: { base: 2040601, seven: 2041611 }, // 豌豆公主(枪械)：青鸟 → 雨后青鸟
  10701: { base: 1060601, seven: 1060611 }, // 踯躅森辩才姬(巨刃)：惑人的蛇舌 → 蛇毒聚流
  10801: { base: 7070601, seven: 7070611 }, // 骆十四娘(浮塔)：智剑<浮沉> → 仁剑<红天>
  11202: { base: 7080611, seven: 7081611 }, // 鱼啄雨(浮塔)：理线者 → 断线者
};

function weaponConfig(itemId) {
  return gd.query('d_bag_item_weapon', itemId);
}

// 客户端 GetWeaponSkillDesc 会不会炸：d_weapon 行必须在，且它引用的 skillID 要么是 0
// （函数直接返回 ''，安全），要么能在 d_skill 里查到行。
function skillHasRow(itemId) {
  const w = gd.query('d_weapon', itemId);
  if (!w) return false; // 客户端 InitRefineData 也是直接用 d_weapon[item_id]，缺行同样崩
  const skillId = Number(w.skillID) || 0;
  if (skillId <= 0) return true;
  return !!gd.query('d_skill', skillId);
}

function isUnreleasedWeapon(itemId) {
  return UNRELEASED_WEAPON_IDS.has(Number(itemId));
}

// 这把武器能不能安全地发到玩家背包里（资源齐全 + 技能行存在）。
function isReleasedWeapon(itemId) {
  if (!weaponConfig(itemId)) return false;
  if (isUnreleasedWeapon(itemId)) return false;
  return skillHasRow(itemId);
}

// 已实装武器里稀有度 >= minRarity 的全部 id（升序，便于稳定复现）。
function releasedWeaponIdsAtLeast(minRarity = 6) {
  const out = [];
  for (const [id, row] of gd.rows('d_bag_item_weapon')) {
    if (Number(row.rarity) < minRarity) continue;
    if (!isReleasedWeapon(id)) continue;
    out.push(Number(id));
  }
  return out.sort((a, b) => a - b);
}

// 同类型里已实装、稀有度最接近 preferRarity 的一把（同级取 id 最大）。
// 未实装武器原地替换（migrate）与专武发放都用它，保证结果确定、可复现。
function bestReleasedWeaponOfType(subType, preferRarity = 0) {
  const want = Number(subType) || 0;
  if (!want) return 0;
  let best = null;
  for (const [id, row] of gd.rows('d_bag_item_weapon')) {
    if (Number(row.subType) !== want) continue;
    if (!isReleasedWeapon(id)) continue;
    const cand = { id: Number(id), rarity: Number(row.rarity) || 0 };
    if (!best) { best = cand; continue; }
    const dRarity = Math.abs(cand.rarity - preferRarity) - Math.abs(best.rarity - preferRarity);
    if (dRarity < 0) { best = cand; continue; }
    if (dRarity > 0) continue;
    if (cand.id > best.id) best = cand;
  }
  return best ? best.id : 0;
}

module.exports = {
  UNRELEASED_WEAPON_IDS,
  CHARACTER_EXCLUSIVE_WEAPONS,
  isUnreleasedWeapon,
  isReleasedWeapon,
  skillHasRow,
  releasedWeaponIdsAtLeast,
  bestReleasedWeaponOfType,
};
