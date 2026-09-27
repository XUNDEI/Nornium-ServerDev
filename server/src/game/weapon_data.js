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
  isUnreleasedWeapon,
  isReleasedWeapon,
  skillHasRow,
  releasedWeaponIdsAtLeast,
  bestReleasedWeaponOfType,
};
