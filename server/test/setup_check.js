// In-process checks for the first-run wizard's launcher + game-directory detection.
//
// Why this exists (two separate bugs, both user-visible):
//
//   1. The wizard's candidate list used to dedup with `found.includes(resolved)` —
//      an exact, case-sensitive string compare. Windows paths are case-insensitive,
//      and Steam writes its own SteamPath with whatever casing it feels like
//      (this machine: HKCU\...\Valve\Steam\SteamPath = "d:/steam", all lowercase
//      and with a forward slash, while the repo lives under "D:\Steam"). So the
//      same install showed up twice:
//
//          找到多个候选目录：
//          1. D:\Steam\steamapps\common\Nornium\Nornium
//          2. d:\steam\steamapps\common\Nornium\Nornium
//
//      and the user was asked to "choose" between two identical directories.
//
//   2. 点我启动.bat used to carry Chinese `echo` lines. cmd.exe can mis-parse a
//      batch file containing multi-byte characters and then try to execute the
//      leftover bytes as a command — symptom, seen on this machine:
//
//          '??' is not recognized as an internal or external command,
//          operable program or batch file.
//
//      The launcher is now pure ASCII and all Chinese text is printed by Node
//      (setup.js / index.js), whose console output goes through the Win32
//      wide-char API and is codepage-independent.
//
//   3. The wizard's "first run: auto npm install" step spawned `npm.cmd`
//      directly. Node >= 18.20.2 / 20.12.2 / 21.7.3 (the CVE-2024-27980
//      hardening) refuses to execute .bat/.cmd via child_process — spawnSync
//      returns EINVAL without ever starting a process, and with
//      `stdio: 'inherit'` the console stays empty, so all a fresh download saw
//      was:
//
//          [1] 检查运行环境
//              OK  Node.js 24.x
//              首次运行：正在安装依赖 protobufjs、des.js …
//              依赖安装失败，请在 server 目录手动执行 npm install 后重试。
//
//      Nobody notices this on a dev machine (node_modules is already there,
//      so ensureDependencies returns early) — but node_modules/ is gitignored,
//      so every fresh clone hits it. The wizard now runs node's own
//      npm-cli.js with the current interpreter instead.
//
// No server needed: setup.js only runs its wizard under `require.main === module`.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const {
  canonicalPath, pathKey, resolveGameRoot, detectCandidates,
  npmCliScript, npmInvocation, npmShellInvocation,
  sourceLooksFixed, collectDoctorReport,
} = require('../setup');

let failures = 0;
function check(cond, msg) {
  console.log(cond ? `  PASS ${msg}` : `  FAIL ${msg}`);
  if (!cond) failures += 1;
}

const SERVER_DIR = path.join(__dirname, '..');
const REPO_ROOT = path.join(SERVER_DIR, '..');
const LAUNCHER = path.join(REPO_ROOT, '点我启动.bat');
const isWin = process.platform === 'win32';

// ---------------- path normalisation ----------------
{
  check(canonicalPath('d:\\steam\\steamapps') === 'D:\\steam\\steamapps',
    'canonicalPath upper-cases the drive letter');
  check(canonicalPath('D:/Steam/steamapps') === 'D:\\Steam\\steamapps',
    'canonicalPath normalises forward slashes');
  check(canonicalPath('D:\\Steam\\x\\..\\y') === 'D:\\Steam\\y',
    'canonicalPath resolves ".." segments');

  const a = 'D:\\Steam\\steamapps\\common\\Nornium\\Nornium';
  const b = 'd:\\steam\\steamapps\\common\\Nornium\\Nornium';
  check(pathKey(a) === pathKey(b),
    'pathKey treats D:\\Steam\\... and d:\\steam\\... as the same directory');
  check(pathKey('D:\\Steam\\x\\') === pathKey('D:/steam/X'),
    'pathKey ignores trailing separators, slashes and case');

  if (!isWin) console.log('  (running on a case-sensitive filesystem; drive-letter rules are Windows-only)');
}

// ---------------- resolveGameRoot consistency ----------------
{
  const viaRepo = resolveGameRoot(path.join(REPO_ROOT, '..'));
  console.log(`  info: repo-relative game root -> ${viaRepo}`);
  if (viaRepo) {
    check(viaRepo === canonicalPath(viaRepo),
      'resolveGameRoot returns an already-canonical path');
    check(pathKey(resolveGameRoot(path.join(REPO_ROOT, '..', 'Nornium'))) === pathKey(viaRepo),
      'both the steamapps\\common\\Nornium layer and its inner Nornium resolve to one key');
  } else {
    console.log('  (game not installed at the expected location; skipped)');
  }
  check(resolveGameRoot('') === null, 'an empty answer resolves to nothing');
  check(resolveGameRoot('C:\\definitely\\not\\a\\game') === null,
    'a path without Binaries\\Win64\\GHS-Win64-Shipping.exe is rejected');
}

// ---------------- 启动器必须保持纯 ASCII（见文件头第 2 条） ----------------
{
  const exists = fs.existsSync(LAUNCHER);
  check(exists, `the launcher exists (${path.basename(LAUNCHER)})`);
  if (exists) {
    const bytes = fs.readFileSync(LAUNCHER);
    const nonAscii = [];
    bytes.forEach((b, i) => { if (b > 0x7f) nonAscii.push({ i, b: `0x${b.toString(16)}` }); });
    check(nonAscii.length === 0,
      `the launcher is pure ASCII (${nonAscii.length} non-ASCII bytes`
        + `${nonAscii.length ? `, first at ${JSON.stringify(nonAscii[0])}` : ''})`);
    check(bytes[0] !== 0xef, 'the launcher has no UTF-8 BOM (cmd chokes on it)');

    const text = bytes.toString('latin1');
    const lf = (text.match(/\n/g) || []).length;
    const crlf = (text.match(/\r\n/g) || []).length;
    check(lf > 0 && lf === crlf, `the launcher uses CRLF line endings (${crlf}/${lf} lines)`);
    check(!/[\u4e00-\u9fff]/.test(bytes.toString('utf8')),
      'no CJK text is left in the launcher');

    check(/chcp 65001/.test(text), 'the launcher still switches the console to UTF-8 for Node');
    check(/node setup\.js/.test(text), 'the launcher still runs the wizard');
    check(/node index\.js/.test(text), 'the launcher still starts the server');
    check(/where node/.test(text) && /Node\.js not found/.test(text),
      'the launcher still guards against a missing Node.js (in ASCII)');
    check(/auto-launch\.flag/.test(text) && /steam:\/\/rungameid\/2877160/.test(text),
      'the launcher still auto-launches the game via the flag');
    // 中文横幅/提示的归属：Node 侧必须有，"点我启动.bat" 里没有
    const setupSrc = fs.readFileSync(path.join(SERVER_DIR, 'setup.js'), 'utf8');
    const indexSrc = fs.readFileSync(path.join(SERVER_DIR, 'index.js'), 'utf8');
    check(/第 1 步：初始化配置/.test(setupSrc), 'setup.js prints the step-1 banner');
    check(/第 2 步：启动服务端/.test(setupSrc), 'setup.js prints the step-2 banner');
    check(/FROM_BAT/.test(setupSrc), 'setup.js knows it was started from the launcher');
    check(/服务端已停止/.test(indexSrc), 'index.js prints the "server stopped" notice');
    check(/接下来会用 Steam 拉起游戏/.test(setupSrc),
      'the auto-launch hint lives in setup.js');
  }
}

// ---------------- the actual regression: candidate list must not self-duplicate ----------------
{
  const candidates = detectCandidates();
  console.log('  info: detectCandidates() ->', JSON.stringify(candidates));
  const keys = candidates.map(pathKey);
  check(new Set(keys).size === keys.length,
    `detectCandidates() has no case-insensitive duplicates (${keys.length} candidates)`);

  const lowered = candidates.map((c) => c.toLowerCase());
  const dupes = lowered.filter((c, i) => lowered.indexOf(c) !== i);
  check(dupes.length === 0, `no candidate appears twice in any casing (dupes: ${JSON.stringify(dupes)})`);

  for (const c of candidates) {
    check(c === canonicalPath(c), `candidate is stored canonical: ${c}`);
  }
}

// ---------------- 首次运行自动 npm install：绝不直接 spawn .cmd（见文件头第 3 条） ----------------
{
  const inv = npmInvocation(['install']);
  console.log(`  info: npmInvocation() -> ${inv.label}`);

  check(!/\.(cmd|bat)$/i.test(inv.command),
    `the wizard never spawns a .cmd/.bat directly (command: ${inv.command})`);

  const cli = npmCliScript();
  console.log(`  info: npmCliScript() -> ${cli || '(not found next to node)'}`);
  if (inv.command === process.execPath) {
    check(!!cli && inv.args[0] === cli, 'it runs the current node with node\'s own npm-cli.js');
    check(fs.existsSync(inv.args[0]), `that npm-cli.js really exists (${inv.args[0]})`);
    check(inv.args[1] === 'install', 'the npm subcommand is `install`');
  } else {
    check(/npm install/.test(inv.args.join(' ')),
      `no npm-cli.js next to node → the shell fallback still runs npm install (${inv.args.join(' ')})`);
  }

  if (isWin) {
    // 复现用户反馈：Node 出于 CVE-2024-27980 的加固，直接 spawn .cmd 只会得到 EINVAL
    const raw = spawnSync('npm.cmd', ['-v'], { encoding: 'utf8' });
    const rawCode = raw.error ? raw.error.code : `status ${raw.status}`;
    check(raw.error && raw.error.code === 'EINVAL',
      `a bare npm.cmd spawn is rejected by Node itself (got ${rawCode}) — this is the reported bug`);

    const fallback = npmShellInvocation(['install']);
    check(path.basename(fallback.command).toLowerCase() === 'cmd.exe',
      `the Windows fallback goes through cmd.exe (${fallback.command}), which finds npm on PATH`);
  }

  // 我们自己的调用方式不该被 Node 的 EINVAL 校验拦下
  // （沙箱里真进程可能被拦成 EBUSY，那不算失败；本地机器上应当拿到 status 0）
  const probeArgs = inv.command === process.execPath
    ? ['-e', 'process.exit(0)']
    : (isWin ? ['/d', '/s', '/c', 'exit 0'] : ['--version']);
  const probe = spawnSync(inv.command, probeArgs, { cwd: SERVER_DIR, encoding: 'utf8' });
  const probeCode = probe.error ? probe.error.code : `status ${probe.status}`;
  check(!probe.error || probe.error.code !== 'EINVAL',
    `our invocation style is accepted by Node (${probeCode})`);
}

// ---------------- 环境自查（node setup.js --check） ----------------
{
  // 「这份 setup.js 是不是修好的」判据必须先剥注释再匹配 —— 修好的文件里恰好引用了
  // 旧写法当反面教材，不剥离就会把新版自己判成旧版（实现完第一次跑就踩了这个）。
  check(sourceLooksFixed(fs.readFileSync(path.join(SERVER_DIR, 'setup.js'), 'utf8')),
    'this repo\'s setup.js is recognised as the fixed version');
  check(sourceLooksFixed(`
// 首次运行：正在安装依赖
const npm = os.platform() === 'win32' ? 'npm.cmd' : 'npm';
const res = spawnSync(npm, ['install'], { cwd: SERVER_DIR, stdio: 'inherit' });
`) === false, 'the pre-fix shape (bare npm.cmd spawn) is recognised as NOT fixed');
  check(sourceLooksFixed(`
// 旧实现：spawnSync('npm.cmd', ['install']) 只会拿到 EINVAL，进程根本没起来
function npmCliScript() {}
const inv = npmInvocation(['install']);
`) === true, 'quoting the old line inside a comment does not misjudge a fixed file');

  const rep = collectDoctorReport();
  const doctorCli = npmCliScript();
  console.log(`  info: doctor -> npm=${rep.npm.mode} deps.present=${JSON.stringify(rep.deps.present)}`
    + ` missing=${JSON.stringify(rep.deps.missing)} ready=${rep.ready}`);

  check(rep.node.ok, `doctor: node is new enough (v${rep.node.version})`);
  check(!/\.(cmd|bat)$/i.test(rep.npm.command),
    `doctor: the npm command it prints is not a .cmd/.bat (${rep.npm.command})`);
  check(rep.npm.mode === (doctorCli ? 'cli' : 'shell'),
    `doctor: npm mode "${rep.npm.mode}" matches whether npm-cli.js was found`);
  check(rep.assets.ok, `doctor: reference/ assets are complete (gamedata ${rep.assets.gamedata} / proto ${rep.assets.proto})`);
  check(rep.deps.present.length + rep.deps.missing.length === 2,
    'doctor: the dependency list covers both packages');
  for (const pkg of rep.deps.present) {
    check(fs.existsSync(path.join(SERVER_DIR, 'node_modules', pkg)),
      `doctor: says ${pkg} is installed, and it is`);
  }
  for (const pkg of rep.deps.missing) {
    check(!fs.existsSync(path.join(SERVER_DIR, 'node_modules', pkg)),
      `doctor: says ${pkg} is missing, and it is`);
  }
  check(rep.wizard.clientFiles.length === 2, 'doctor: checks both client lua files');
  check(rep.serverDir === SERVER_DIR,
    'doctor: tells the user to open the very server dir the wizard installs into');
  check(rep.ready === (rep.node.ok && rep.assets.ok && (rep.code.fixed || rep.deps.ready)),
    'doctor: the verdict follows its own rule (node + assets + (fixed || deps ready))');
}

// ---------------- 输出档位：热启动不再把向导每一步都念一遍 ----------------
{
  const { depsPresent, clientFilesCurrent, shouldCompactStartup } = require('../setup');

  const warm = { fromBat: true, cfgValid: true, clientConfigCurrent: true, depsInstalled: true };
  check(shouldCompactStartup(warm) === true,
    'a warm launcher start (config valid, client files current, deps installed) compacts the output');
  for (const miss of ['fromBat', 'cfgValid', 'clientConfigCurrent', 'depsInstalled']) {
    check(shouldCompactStartup({ ...warm, [miss]: false }) === false,
      `...but not when ${miss} is false (first run / --reset / game update / missing deps)`);
  }
  check(shouldCompactStartup() === false,
    'no arguments means no compaction (never silently shrink a first run)');
  check(typeof depsPresent() === 'boolean', `depsPresent() answers with a boolean (${depsPresent()})`);

  // clientFilesCurrent 必须与 writeClientFiles 同一判据，否则会出现「说不用写、其实要写」
  check(clientFilesCurrent(path.join(os.tmpdir(), 'nornium-definitely-not-here')) === false,
    'clientFilesCurrent() rejects a directory whose client files are missing');
  let cfgSaved = null;
  try {
    cfgSaved = JSON.parse(fs.readFileSync(path.join(SERVER_DIR, 'runtime-config.json'), 'utf8')).saved_dir;
  } catch (_) { /* 没有配置就跳过这一条 */ }
  if (cfgSaved && fs.existsSync(cfgSaved)) {
    check(clientFilesCurrent(cfgSaved) === true,
      `clientFilesCurrent() accepts this machine's already-configured game dir (${cfgSaved})`);
  } else {
    console.log('  (no runtime-config.json saved_dir on this machine; the positive case was skipped)');
  }

  // 简化输出时也必须留下两个步骤标题（启动器是纯 ASCII，中文只在 Node 侧打印）
  const setupSrc2 = fs.readFileSync(path.join(SERVER_DIR, 'setup.js'), 'utf8');
  check(/第 1 步：初始化配置/.test(setupSrc2) && /第 2 步：启动服务端/.test(setupSrc2),
    'the compact path still prints both step banners');
  check(/QUIET/.test(setupSrc2) && /shouldCompactStartup\(/.test(setupSrc2),
    'setup.js actually wires the compact-output switch in');
}

// ---------------- 项目主页：仓库地址在四个出口都能看到 ----------------
{
  const pkg = require('../package.json');
  const REPO = 'https://github.com/XUNDEI/Nornium-ServerDev';
  check(pkg.homepage === REPO, `package.json.homepage is the single source (${pkg.homepage})`);

  const files = {
    'setup.js': path.join(SERVER_DIR, 'setup.js'),
    'index.js': path.join(SERVER_DIR, 'index.js'),
    'src/console.js': path.join(SERVER_DIR, 'src', 'console.js'),
    'src/editorapi.js': path.join(SERVER_DIR, 'src', 'editorapi.js'),
  };
  for (const [label, file] of Object.entries(files)) {
    const src = fs.readFileSync(file, 'utf8');
    const mentions = /package\.json/.test(src) && /homepage/.test(src);
    const literal = src.includes(REPO);
    check(mentions || literal, `${label} surfaces the project homepage (via package.json or literal)`);
  }
  const indexSrc2 = fs.readFileSync(path.join(SERVER_DIR, 'index.js'), 'utf8');
  check(/REPO_URL/.test(indexSrc2) && /网页编辑器/.test(indexSrc2),
    'the server banner shows both the editor URL and the repo URL');
}

console.log(failures === 0 ? '\nSETUP CHECKS PASSED' : `\n${failures} SETUP CHECKS FAILED`);
process.exit(failures === 0 ? 0 : 1);
