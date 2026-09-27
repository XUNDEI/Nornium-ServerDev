#!/usr/bin/env node
// 武器资源实装性核对：把 d_bag_item_weapon 引用的模型/图标/展示图，与 pak 里的真实条目
// 逐一对照，列出「有数据行但客户端根本没有资源」的幽灵武器。
//
// 为什么需要它：客户端的 ClientDatas 里有 83 把武器，其中 10 把是未实装残件。它们不只是
// 「图标是空的」——其中 7 把连 d_skill 里的技能行都没有，而客户端
// UIUtils.GetWeaponSkillDesc 拿到 nil 后会访问 skillInfo.skillDesc 抛错，
// 把 UI_Com_BagDetail_C:RefreshUI 从中间打断，整个武器详情面板停摆
// （表现为满屏 UMG 设计态的「文本块…」「30#星芒名字」，没有「攻击力」行）。
// 早期版本的「发专武」按「同类型稀有度最高、并列取 id 最大」发放，巨刃正好选中
// 1081601「颂歌」，于是只有巨刃角色踩雷。详见 server/src/game/weapon_data.js。
//
// 用法（pak 清单要先用 repak 导出，见下方命令）：
//   & "C:\Program Files\repak_cli\bin\repak.exe" --aes-key <KEY> list <pak> | Out-File -Encoding utf8 paklist.txt
//   node tools/check_weapon_assets.js <paklist.txt> [<paklist2.txt> ...]
//
// 不给参数时，会去 <仓库>/reference/paklist*.txt 找现成的清单；找不到就打印导出命令。
//
// 退出码：0 = 没有未实装武器；1 = 存在未实装武器（并打印清单）。
const fs = require('fs');
const path = require('path');

const repoRoot = path.join(__dirname, '..');
const gdDir = path.join(repoRoot, 'reference', 'gamedata');

function readPakLists(argv) {
  let files = argv.slice(2).filter(Boolean);
  if (files.length === 0) {
    const refDir = path.join(repoRoot, 'reference');
    files = fs.existsSync(refDir)
      ? fs.readdirSync(refDir).filter((f) => /^paklist.*\.txt$/.test(f)).map((f) => path.join(refDir, f))
      : [];
  }
  const entries = new Set();
  for (const f of files) {
    const text = fs.readFileSync(f, 'utf8');
    for (const line of text.split(/\r?\n/)) {
      const t = line.trim();
      if (t) entries.add(t.toLowerCase());
    }
  }
  return { files, entries };
}

// /Game/_Game/A/B/C.C  ->  Nornium/Content/_Game/A/B/C  （末尾的对象名后缀要去掉）
function hasAsset(entries, gamePath) {
  if (!gamePath) return true;
  const q = String(gamePath)
    .replace(/^\/Game\//, 'Nornium/Content/')
    .replace(/\.[^.]+$/, '')
    .toLowerCase();
  return entries.has(`${q}.uasset`) || entries.has(`${q}.uexp`);
}

function load(name) {
  return JSON.parse(fs.readFileSync(path.join(gdDir, `${name}.json`), 'utf8'));
}

function main() {
  const { files, entries } = readPakLists(process.argv);
  if (entries.size === 0) {
    console.error('没有可用的 pak 清单。先用 repak 导出一份：\n'
      + '  & "C:\\Program Files\\repak_cli\\bin\\repak.exe" --aaes-key <KEY> list <pakchunk0-Windows.pak>'
      + ' | Out-File -Encoding utf8 reference\\paklist.txt\n'
      + '然后把文件名作为参数传给本脚本。');
    process.exit(2);
  }
  console.log(`pak 清单：${files.join(', ')}（共 ${entries.size} 条）`);

  const bw = load('d_bag_item_weapon');
  const wp = load('d_weapon');
  const sk = load('d_skill');
  const word = load('d_word_cn');
  const name = (id) => (word[bw[id].itemName] ? word[bw[id].itemName].text : '?');

  const rows = [];
  for (const id of Object.keys(bw)) {
    const d = wp[id] || {};
    const m = String(d.weaponModel1 || '').match(/'([^']+)'/);
    const skillId = Number(d.skillID) || 0;
    rows.push({
      id,
      rarity: Number(bw[id].rarity) || 0,
      subType: Number(bw[id].subType) || 0,
      name: name(id),
      model: hasAsset(entries, m ? m[1] : ''),
      icon: hasAsset(entries, `/Game/_Game/${bw[id].iconPath}`),
      image: hasAsset(entries, `/Game/_Game/${bw[id].displayPath}`),
      // skillID 0 = 客户端 GetWeaponSkillDesc 直接返回 ''，安全；否则必须能在 d_skill 查到行
      skill: skillId <= 0 || !!sk[skillId],
      skillId,
    });
  }

  const WType = ['', '巨刃', '长剑', '佩刀', '枪械', '礼器', '宝轮', '浮塔'];
  const ghosts = rows.filter((r) => !r.model || !r.icon || !r.image || !r.skill);
  console.log(`\n共 ${rows.length} 把武器，未实装 ${ghosts.length} 把：`);
  for (const r of ghosts) {
    console.log(`  ${r.id}  ${r.rarity}★ ${(WType[r.subType] || '?').padEnd(3)} ${r.name.padEnd(16)}`
      + ` 模型 ${r.model ? 'OK' : '缺'}  图标 ${r.icon ? 'OK' : '缺'}  展示图 ${r.image ? 'OK' : '缺'}`
      + `  技能 ${r.skill ? 'OK' : `缺(d_skill 无 ${r.skillId})`}`);
  }

  // 与黑名单对拍：两边不一致就提示（改过 pak 或改过黑名单时最需要看这条）
  const listed = require(path.join(repoRoot, 'server', 'src', 'game', 'weapon_data.js')).UNRELEASED_WEAPON_IDS;
  const ghostIds = ghosts.map((r) => Number(r.id)).sort((a, b) => a - b);
  const listIds = [...listed].sort((a, b) => a - b);
  const same = ghostIds.length === listIds.length && ghostIds.every((v, i) => v === listIds[i]);
  console.log(`\n与 weapon_data.UNRELEASED_WEAPON_IDS 一致：${same ? '是' : '否'}`);
  if (!same) {
    console.log(`  pak 实测：${ghostIds.join(',') || '（无）'}`);
    console.log(`  黑名单：  ${listIds.join(',') || '（无）'}`);
  }
  process.exit(ghosts.length === 0 ? 0 : 1);
}

main();
