#!/usr/bin/env node
// Mod 格式校验工具（给 mod 作者与分发者的命令行入口）。
//
//   node tools/validate_mod.js <mod 目录或 zip>
//
// 校验规则与启动器导入时完全同一份（src/mods.js 的 validateMod）——
// 这里通过 = 启动器导入时校验也一定通过，两边永不出现两套口径。
// 退出码：0 = 通过（可有警告）；1 = 有错误；2 = 用法/读文件失败。
const fs = require('fs');
const path = require('path');

// tools/ 里跑要能找到 server/src —— 直接按相对路径 require。
const modRoot = path.join(__dirname, '..', 'server');
const mods = require(path.join(modRoot, 'src', 'mods'));

const target = process.argv[2];
if (!target) {
  console.log('用法：node tools/validate_mod.js <mod 目录或 zip>');
  console.log('校验规则见 docs/MOD_FORMAT.md；与启动器导入时用的是同一份校验器。');
  process.exit(2);
}

const abs = path.resolve(target);
let result;
try {
  const st = fs.statSync(abs);
  if (st.isDirectory()) {
    // 目录：就地校验（若目录名与 id 不一致会报出来，与启动器同一行为）
    result = mods.validateMod(abs);
  } else {
    // zip：解到临时目录再校验（与启动器导入的流程一致）
    const os = require('os');
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'mod-validate-'));
    try {
      const zipMod = require(path.join(modRoot, 'src', 'zip'));
      const payload = zipMod.readAll(fs.readFileSync(abs));
      const keys = Object.keys(payload);
      const manifestKey = keys.find((k) => k === 'mod.json')
        || keys.find((k) => k.endsWith('/mod.json') && k.indexOf('/') === k.lastIndexOf('/'));
      if (!manifestKey) throw new Error('zip 里没找到 mod.json');
      const strip = manifestKey === 'mod.json' ? '' : manifestKey.slice(0, -'mod.json'.length);
      for (const [name, buf] of Object.entries(payload)) {
        if (!name.startsWith(strip) || name === manifestKey) continue;
        const rel = name.slice(strip.length);
        const file = path.join(tmp, rel);
        fs.mkdirSync(path.dirname(file), { recursive: true });
        fs.writeFileSync(file, buf);
      }
      result = mods.validateMod(tmp);
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true });
    }
  }
} catch (err) {
  console.error(`无法读取 ${abs}：${err.message}`);
  process.exit(2);
}

const m = result.manifest || {};
console.log(`mod.json:  id=${m.id || '?'}  name=${m.name || '?'}  version=${m.version || '?'}  author=${m.author || '?'}`);
console.log(`files/:    ${result.file_count} 个客户端文件`);
console.log(`server_patch/: ${result.server_patch_tables.length ? result.server_patch_tables.join(', ') : '（无）'}`);
console.log('');
for (const e of result.errors) console.log(`  [错误] ${e}`);
for (const w of result.warnings) console.log(`  [警告] ${w}`);
console.log('');
if (result.ok) {
  console.log(result.warnings.length ? '通过（带警告）—— 启动器可以导入并构建它。' : '通过 —— 启动器可以导入并构建它。');
  process.exit(0);
}
console.log('未通过 —— 先解决上面的错误再分发（警告不拦路）。规则见 docs/MOD_FORMAT.md。');
process.exit(1);
