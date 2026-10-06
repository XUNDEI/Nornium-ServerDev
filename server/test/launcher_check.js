// 启动器（mod 管理）回归测试。不需要真服务端、不需要真游戏目录：
//   - mod 仓库 / 校验 / 导入 / 合并顺序 / 冲突裁决 → 全部在临时目录里跑；
//   - repak 打包 → 本机装了 repak_cli 就真打包一次进假游戏目录（端到端验证管线），
//     没有就跳过并打印 SKIP（CI / 玩家机器上不能因为缺 repak 挂测试）。
//   - 服务端数据表补丁 → 临时 gamedata 目录（mods.js 的 GHS_GAMEDATA_DIR 注入）。
//
// 必须在 require ../src/mods 之前设环境变量（模块加载时就读掉了，坑 35 同规矩）。
const os = require('os');
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ghs-launcher-'));
const MODS_DIR = path.join(tmp, 'mods');
const GAME_ROOT = path.join(tmp, 'game');
const GD_DIR = path.join(tmp, 'gamedata');
const PAKS_DIR = path.join(GAME_ROOT, 'Content', 'Paks');
fs.mkdirSync(PAKS_DIR, { recursive: true });
fs.mkdirSync(path.join(GAME_ROOT, 'Binaries', 'Win64'), { recursive: true });
fs.mkdirSync(GD_DIR, { recursive: true });
fs.writeFileSync(path.join(GAME_ROOT, 'Binaries', 'Win64', 'GHS-Win64-Shipping.exe'), 'fake-exe');
// 假装有一个原版 pak，gameInfo 的 paks 列表要能看到它
fs.writeFileSync(path.join(PAKS_DIR, 'pakchunk0-Windows.pak'), 'fake-pak');

process.env.GHS_MODS_DIR = MODS_DIR;
process.env.GHS_GAME_ROOT = GAME_ROOT;
process.env.GHS_GAMEDATA_DIR = GD_DIR;
// repak 探测顺序：显式 env > 常见安装位 > PATH。这里先不设，让探测逻辑自己找；
// 找不到（CI）时 pack 段自动跳过。

const mods = require('../src/mods');
const zip = require('../src/zip');

let failures = 0;
function check(cond, msg) {
  console.log(cond ? `  PASS ${msg}` : `  FAIL ${msg}`);
  if (!cond) failures += 1;
}
function section(name) { console.log(`\n== ${name} ==`); }

function writeMod(id, opts = {}) {
  const dir = path.join(MODS_DIR, id);
  fs.mkdirSync(dir, { recursive: true });
  const manifest = {
    id, name: opts.name || id, version: opts.version || '1.0.0',
    author: opts.author || 'tester', ...(opts.description ? { description: opts.description } : {}),
  };
  if (opts.manifest) Object.assign(manifest, opts.manifest);
  fs.writeFileSync(path.join(dir, 'mod.json'), JSON.stringify(manifest, null, 1));
  for (const [rel, content] of Object.entries(opts.files || {})) {
    const file = path.join(dir, 'files', ...rel.split('/'));
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, content);
  }
  for (const [name, content] of Object.entries(opts.patches || {})) {
    const file = path.join(dir, 'server_patch', name);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, typeof content === 'string' ? content : JSON.stringify(content));
  }
  return dir;
}

// ══════════════════════════ 1. mod 校验 ══════════════════════════

section('mod 校验');

(() => {
  const dir = writeMod('good-mod', {
    files: { 'Nornium/Content/Script/ClientDatas/d_character.lua': '-- hi' },
  });
  const v = mods.validateMod(dir);
  check(v.ok, '合法 mod 通过校验');
  check(v.file_count === 1, '文件计数正确');
})();

(() => {
  const dir = path.join(MODS_DIR, 'bad-id');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'mod.json'), JSON.stringify({ id: 'BAD ID!', name: 'x', version: '1', author: 'y' }));
  const v = mods.validateMod(dir);
  check(!v.ok, '非法 id 校验不通过');
  check(v.errors.some((e) => e.includes('id')), '报错指出 id 问题');
})();

(() => {
  const dir = path.join(MODS_DIR, 'missing-fields');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'mod.json'), JSON.stringify({ id: 'missing-fields' }));
  const v = mods.validateMod(dir);
  check(!v.ok && ['name', 'version', 'author'].every((f) => v.errors.some((e) => e.includes(f))),
    '缺少 name/version/author 逐项报错');
})();

(() => {
  // 路径穿越防护真正有事的入口是 zip 导入（第 2 段）；files/ 磁盘扫描层面做一层
  // 兜底断言：脱离 Nornium/ 前缀的文件必须报错（非法文件会被构建拒绝）。
  const dir = writeMod('escapes', {});
  fs.mkdirSync(path.join(dir, 'files', 'Other'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'files', 'Other', 'evil.lua'), 'x');
  const v = mods.validateMod(dir);
  check(!v.ok, 'files/ 里出现非 Nornium/ 路径校验不通过');
})();

(() => {
  const dir = writeMod('no-prefix', { files: { 'Content/Script/x.lua': 'x' } });
  const v = mods.validateMod(dir);
  check(!v.ok, '缺少 Nornium/ 前缀的文件路径校验不通过');
})();

(() => {
  const dir = writeMod('with-patch', { patches: { 'd_character.json': { 10101: { name: 'x' } }, 'not-a-table.txt': 'x' } });
  const v = mods.validateMod(dir);
  check(!v.ok, 'server_patch 里的非 json 文件报错');
})();

// ══════════════════════════ 2. zip 导入（含冲突 / 穿越防护） ══════════════════════════

section('zip 导入');

(() => {
  // 源目录名与 mod id 不同，验证 id 以 mod.json 为准（zip 里的目录名不重要）
  const srcDir = writeMod('zippy-src', {
    manifest: { id: 'zippy' }, description: '来自 zip',
    files: { 'Nornium/Content/Script/a.lua': 'A' },
  });
  const buf = zip.zipDir(srcDir, 'zippy-src/'); // 模拟资源管理器压缩出的带顶层目录 zip
  const r = mods.importFromZipBuffer(buf);
  check(r.id === 'zippy', '从 zip 导入成功（id 取自 mod.json，自动剥顶层目录）');
  check(fs.existsSync(path.join(MODS_DIR, 'zippy', 'files', 'Nornium', 'Content', 'Script', 'a.lua')),
    '导入的文件落在正确位置');
  const again = (() => { try { mods.importFromZipBuffer(buf); return null; } catch (e) { return e; } })();
  check(again && /已经存在/.test(again.message), '重复导入同名 id 报「已经存在」');
})();

(() => {
  const bad = zip.writeZip({ 'mod.json': Buffer.from('{"id":"ok id"}') });
  const err = (() => { try { mods.importFromZipBuffer(bad); return null; } catch (e) { return e; } })();
  check(err && /不合法/.test(err.message), '非法 id 的 zip 被拒');
})();

(() => {
  const noManifest = zip.writeZip({ 'stuff/a.lua': Buffer.from('A') });
  const err = (() => { try { mods.importFromZipBuffer(noManifest); return null; } catch (e) { return e; } })();
  check(err && /mod.json/.test(err.message), '没有 mod.json 的 zip 被拒');
})();

(() => {
  const evil = zip.writeZip({
    'mod.json': Buffer.from('{"id":"evil","name":"e","version":"1","author":"a"}'),
    'a/../../evil.lua': Buffer.from('boom'),
  });
  const err = (() => { try { mods.importFromZipBuffer(evil); return null; } catch (e) { return e; } })();
  check(err && /不安全/.test(err.message), 'zip 内路径穿越被拒');
})();

// ══════════════════════════ 3. 启用 / 排序 / 冲突裁决 ══════════════════════════

section('启用 / 排序 / 冲突');

(() => {
  writeMod('m-one', { files: { 'Nornium/Content/Script/shared.lua': 'ONE' } });
  writeMod('m-two', { files: { 'Nornium/Content/Script/shared.lua': 'TWO' } });
  mods.setEnabled('m-one', true);
  mods.setEnabled('m-two', true);
  let info = mods.gameInfo();
  check(info.enabled_order.length === 2, '两个 mod 都启用');
  check(info.conflicts.length === 1 && info.conflicts[0].file === 'Nornium/Content/Script/shared.lua',
    '同名文件的冲突被报告');

  // m-two 在启用列表更后面 → m-two 赢
  check(info.conflicts[0].winner === 'm-two', '默认顺序下 m-two 是胜者');

  // 重排：m-two 放前面 → m-one 赢
  mods.setOrder(['m-two', 'm-one']);
  info = mods.gameInfo();
  check(info.conflicts[0].winner === 'm-one', '重排后优先级跟着顺序走');
  check(info.enabled_order[1] === 'm-one', '排序落盘');
})();

// ══════════════════════════ 4. 服务端数据表补丁 ══════════════════════════

section('服务端数据表补丁');

(() => {
  fs.writeFileSync(path.join(GD_DIR, 'd_character.json'),
    JSON.stringify({ 10101: { id: 10101, name: '原版', profession: 2 }, 10102: { id: 10102, name: '不动' } }, null, 1));
  writeMod('m-one', { patches: { 'd_character.json': { 10101: { name: '补丁一' } } } });
  writeMod('m-two', { patches: { 'd_character.json': { 10101: { profession: 5, added: 'tw' } } } });
  const r = mods.applyServerPatches();
  check(r.applied.length === 2, `两张补丁都应用（${r.applied.length}）`);
  const merged = JSON.parse(fs.readFileSync(path.join(GD_DIR, 'd_character.json'), 'utf8'));
  check(merged['10101'].name === '补丁一', '启靠前的 mod 先合并（name 来自 m-one）');
  check(merged['10101'].profession === 5 && merged['10101'].added === 'tw',
    '靠后的 mod 覆盖同名字段并新增字段');
  check(merged['10101'].id === 10101, '深合并保留基表里补丁没提的字段');
  check(merged['10102'].name === '不动', '没被补丁的行原样保留');
  check(fs.existsSync(path.join(MODS_DIR, '.gamedata_backup', 'd_character.json')), '首次改动前备份了原表');

  // gamedata.reload 后查询生效
  const gd = require('../src/gamedata');
  check(gd.query('d_character', 10101).name === '补丁一', 'gd.query 拿到补丁数据（热重载）');

  // 还原
  mods.revertServerPatches();
  const restored = JSON.parse(fs.readFileSync(path.join(GD_DIR, 'd_character.json'), 'utf8'));
  check(restored['10101'].name === '原版' && restored['10101'].profession === 2 && !restored['10101'].added,
    'revert 精确还原原表');
})();

// ══════════════════════════ 5. 构建清单（dry run，不依赖 repak） ══════════════════════════

section('构建清单（dry run）');

(() => {
  const plan = mods.buildInstalled({ dryRun: true });
  check(plan.dry_run === true, 'dry_run 标记');
  // 启用的只有 m-two / m-one，两者各贡献同一个 shared.lua → 合并后 1 个文件
  check(plan.file_count === 1, `合并文件数正确（${plan.file_count}）`);
  check(plan.conflicts.length === 1, '冲突随计划返回');
  const shared = plan.files.find((f) => f.rel.endsWith('shared.lua'));
  check(shared.mod === 'm-one', '合并结果里 shared.lua 归 m-one（胜者）');
  check(!fs.existsSync(path.join(PAKS_DIR, 'GHSMods_P.pak')), 'dry run 不落盘');
})();

// ══════════════════════════ 6. repak 端到端（本机有 repak 才跑） ══════════════════════════

section('repak 打包 + 安装（可选）');

(() => {
  const repak = mods.findRepak();
  if (!repak) {
    console.log('  SKIP 找不到 repak.exe（安装 repak_cli 后重跑可覆盖这一段）');
    return;
  }
  console.log(`  （使用 ${repak}）`);
  const result = mods.buildInstalled({});
  check(result.installed === true, 'buildInstalled 安装成功');
  const pak = path.join(PAKS_DIR, 'GHSMods_P.pak');
  check(fs.existsSync(pak), 'GHSMods_P.pak 落进游戏 Paks 目录');
  check(fs.statSync(pak).size > 0, 'pak 非空');

  // 用 repak 自己 list 校验产物可读 + 条目路径正确（这是引擎挂载能否成功的前提）
  const out = execFileSync(repak, ['list', pak], { encoding: 'utf8' });
  const lines = out.split(/\r?\n/).filter(Boolean);
  check(lines.length === 1, `pak 里有 ${lines.length} 个条目（两个 mod 的同名文件合并成了一个）`);
  check(lines.every((l) => l.startsWith('Nornium/')), '条目路径都带 Nornium/ 前缀');
  check(lines.includes('Nornium/Content/Script/shared.lua'), 'shared.lua 在 pak 里');
  const winner = (() => {
    const buf = execFileSync(repak, ['get', pak, 'Nornium/Content/Script/shared.lua'], { encoding: null });
    return buf.toString('utf8').trim();
  })();
  check(winner === 'ONE', `pak 里 shared.lua 的内容是胜者 m-one（实际 "${winner}"）`);
  check(!fs.existsSync(path.join(MODS_DIR, '.build')) || fs.readdirSync(path.join(MODS_DIR, '.build')).length === 0,
    '构建临时目录已清理');

  // 安装状态与卸载
  let info = mods.gameInfo();
  check(info.installed.pak_exists === true && info.installed.built_from.length === 2, 'gameInfo 报告已安装');
  check(info.paks.some((p) => p.name === 'GHSMods_P.pak'), 'paks 列表里能看到补丁 pak');
  check(info.repak.found === true, 'repak 探测成功');

  mods.uninstall();
  check(!fs.existsSync(pak), 'uninstall 删除了补丁 pak');
  info = mods.gameInfo();
  check(info.installed.pak_exists === false, '安装状态复位');
})();

// ══════════════════════════ 7. mod 删除 ══════════════════════════

section('mod 删除');

(() => {
  mods.removeMod('m-two');
  check(!fs.existsSync(path.join(MODS_DIR, 'm-two')), '目录被删除');
  const info = mods.gameInfo();
  check(info.mods.every((m) => m.id !== 'm-two'), '列表里消失');
  check(info.enabled_order.includes('m-one'), '其余 mod 的启用状态不受影响');
})();

console.log(failures === 0 ? '\nLAUNCHER CHECKS PASSED' : `\n${failures} LAUNCHER CHECKS FAILED`);
process.exit(failures === 0 ? 0 : 1);
