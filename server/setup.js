// 首次启动向导：让新玩家「输入游戏路径」即可开玩，不再手工拷贝任何文件。
//
// 做三件事（全部幂等，第二次运行会静默跳过）：
//   1. 校验运行环境（Node >= 18、reference/ 数据是否完整、依赖是否装好）
//   2. 定位《失乐星图》的安装目录（自动探测 Steam 库，失败才问用户），
//      并把结果缓存到 server/runtime-config.json
//   3. 把客户端需要的 channel.lua / version.lua 写进
//      %LOCALAPPDATA%\Nornium\Saved\（lox 的接入点，见 REVERSE_ENGINEERING.md 3.1）
//
// 用法：node setup.js [--reset] [--game-path=<dir>] [--yes] [--from-bat]
//
// --from-bat：由「点我启动.bat」调用的。启动器本身是纯 ASCII（cmd.exe 解析含多字节
// 字符的批处理会错位，见 REVERSE_ENGINEERING 坑 36），所以**所有中文提示都在这里打印**，
// 并且「第 2 步」的文案只有从 bat 调用时才出现（手工跑 `node setup.js` 时那段"接下来会
// 拉起游戏"的话不成立）。

/* eslint-disable no-console */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const readline = require('readline');
const { spawnSync } = require('child_process');

// --- 必须与 index.js 保持一致 ------------------------------------------------
const TCP_PORT = 8101;
const HTTP_PORT = 9089;
const CHANNEL = 'local_dev';
const CLIENT_VERSION = '1.0.1';
const CHANNEL_CODE = 'cb4_alpha_3_steam';
const STEAM_APP_ID = '2877160';
// 游戏主程序相对安装根目录的路径，用来判定用户给的路径对不对
const GAME_EXE_REL = path.join('Binaries', 'Win64', 'GHS-Win64-Shipping.exe');

const SERVER_DIR = __dirname;
const REPO_ROOT = path.join(SERVER_DIR, '..');
const CONFIG_FILE = path.join(SERVER_DIR, 'runtime-config.json');
const AUTO_LAUNCH_FLAG = path.join(SERVER_DIR, 'auto-launch.flag');

function savedDir() {
  const appData = process.env.LOCALAPPDATA
    || (os.platform() === 'win32' ? path.join(os.homedir(), 'AppData', 'Local') : null);
  if (!appData) return null;
  return path.join(appData, 'Nornium', 'Saved');
}

// ---------------------------------------------------------------- args / io

const argv = process.argv.slice(2);
const hasFlag = (name) => argv.includes(name);
const flagValue = (name) => {
  const hit = argv.find((a) => a.startsWith(`${name}=`));
  return hit ? hit.slice(name.length + 1) : null;
};
const RESET = hasFlag('--reset') || hasFlag('-r');
const ASSUME_YES = hasFlag('--yes') || hasFlag('-y');
const FROM_BAT = hasFlag('--from-bat');
const CHECK = hasFlag('--check') || hasFlag('--doctor');   // 只读环境自查，见 collectDoctorReport
const CLI_GAME_PATH = flagValue('--game-path');

// stdin/stdout 只在真的要提问时才接（被 require 进单测时不该抢 stdin）
let rl = null;
function ask(question) {
  if (!rl) rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => rl.question(question, (answer) => resolve(String(answer).trim())));
}
function closeRl() {
  if (rl) { rl.close(); rl = null; }
}

function line(char = '-') {
  console.log(char.repeat(64));
}
function step(n, text) {
  console.log(`\n[${n}] ${text}`);
}
function ok(text) {
  console.log(`    OK  ${text}`);
}
function warn(text) {
  console.log(`    ~~  ${text}`);
}

// ------------------------------------------------------------------- 1. 环境

function checkNode() {
  const major = Number(process.versions.node.split('.')[0]);
  if (Number.isFinite(major) && major >= 18) return true;
  console.error(`当前 Node.js 版本为 ${process.versions.node}，服务端要求 >= 18。`);
  console.error('请到 https://nodejs.org/ 安装 LTS 版本后重试。');
  return false;
}

// 服务端运行时要读的两份逆向资产必须随仓库一起分发，缺了会一到 load 就炸
function checkReferenceAssets() {
  const missing = [];
  for (const rel of ['reference/gamedata', 'reference/proto']) {
    const dir = path.join(REPO_ROOT, rel);
    if (!fs.existsSync(dir) || fs.readdirSync(dir).length === 0) missing.push(rel);
  }
  if (missing.length) {
    console.error('缺少服务端必需的逆向资产目录：' + missing.join('、'));
    console.error('请确认下载的是完整仓库（reference/ 目录不能被删）。');
    return false;
  }
  return true;
}

// ------------------------------------------------------------ 依赖自动安装
//
// 「怎么调 npm」比看起来麻烦：Windows 上 `npm` 只是一个 npm.cmd 垫片，而 Node 从
// 18.20.2 / 20.12.2 / 21.7.3 起（CVE-2024-27980 的修复）**禁止 child_process 直接执行
// .bat/.cmd** —— `spawnSync('npm.cmd', ['install'])` 不会启动任何进程，只回一个 EINVAL，
// 而且 stdio: 'inherit' 下连一行输出都没有，看起来就像"什么都没发生"。
//
// 这在开发机上是隐形的（node_modules 早就在了，ensureDependencies 第一行就短路返回），
// 但**每一个全新下载仓库的玩家**都会撞上它：`node_modules/` 是 gitignore 的，
// 首次启动必然走这条安装路径 → 一进游戏就「依赖安装失败」（见 REVERSE_ENGINEERING 坑 47）。
//
// 所以：优先用**当前这个 node** 去跑它自带的 npm-cli.js（不过 PATH、不过 cmd.exe、不受
// 上面那条限制）；只有找不到 CLI 脚本时才退回 shell（Windows 交给 cmd.exe 自己从 PATH
// 上找 npm）。两条路径都不直接 spawn .cmd。

function npmCliScript() {
  const exeDir = path.dirname(process.execPath);
  const candidates = [
    // Windows / nvm-windows / 绿色压缩包：node.exe 旁边就是 npm
    path.join(exeDir, 'node_modules', 'npm', 'bin', 'npm-cli.js'),
    // Linux / macOS 的前缀布局
    path.join(exeDir, '..', 'lib', 'node_modules', 'npm', 'bin', 'npm-cli.js'),
  ];
  return candidates.find((p) => {
    try { return fs.existsSync(p); } catch (_) { return false; }
  }) || null;
}

// Windows 一律走 cmd.exe（**不要**把 npm.cmd 直接塞进 spawn，见上面那段说明）。
function npmShellInvocation(npmArgs) {
  if (os.platform() === 'win32') {
    const comspec = process.env.ComSpec || 'cmd.exe';
    return {
      command: comspec,
      args: ['/d', '/s', '/c', ['npm', ...npmArgs].join(' ')],
      label: `cmd /c npm ${npmArgs.join(' ')}`,
    };
  }
  return { command: 'npm', args: npmArgs, label: `npm ${npmArgs.join(' ')}` };
}

function npmInvocation(npmArgs) {
  const cli = npmCliScript();
  if (cli) {
    return {
      command: process.execPath,
      args: [cli, ...npmArgs],
      label: `node "${cli}" ${npmArgs.join(' ')}`,
    };
  }
  return npmShellInvocation(npmArgs);
}

function tailLines(text, n) {
  return String(text).trimEnd().split(/\r?\n/).slice(-n);
}

// 安装失败时给的「怎么办」。玩家最常问的是「npm install 在哪？」——
// 它是一条**命令**，不是文件，也不是 Node 安装目录里的东西，所以这里把话说死。
function manualInstallHelp() {
  console.log('    手动装一次就好（只有首次麻烦，之后不会再出现这一步）：');
  console.log(`      1. 打开文件夹：${SERVER_DIR}`);
  console.log('      2. 在资源管理器地址栏里输入 cmd 再回车（或 Shift+右键 → 在此处打开终端）');
  console.log('      3. 执行：npm install');
  console.log('      4. 装好后重新双击「点我启动.bat」');
  console.log('    注意：npm install 是要在上面那个 server 目录里敲的一条命令，');
  console.log('          不是文件、也不是安装包——不要去 Node 的安装目录里找它（那里没有）。');
  console.log("    若提示「'npm' 不是内部或外部命令」：装 Node.js 时没勾选 Add to PATH，");
  console.log('      重装 LTS 版并勾选它（https://nodejs.org/）。');
  console.log('    若只是下载慢 / 超时：换国内镜像重试');
  console.log('      npm install --registry=https://registry.npmmirror.com');
}

function ensureDependencies() {
  const deps = ['protobufjs', 'des.js'];
  const missingDeps = () => deps.filter((p) => !fs.existsSync(path.join(SERVER_DIR, 'node_modules', p)));

  if (!missingDeps().length) {
    ok('依赖已就绪（protobufjs / des.js）');
    return true;
  }

  console.log(`    首次运行：正在安装依赖 ${missingDeps().join('、')} …`);
  const inv = npmInvocation(['install']);
  console.log(`    （${inv.label}）`);
  // 输出**抓下来**再打：万一失败要能说清是哪一步坏的（旧实现用 stdio: 'inherit'，
  // spawn 都没起来时控制台上一条线索都没有）。
  const res = spawnSync(inv.command, inv.args, { cwd: SERVER_DIR, encoding: 'utf8' });
  const output = `${res.stdout || ''}${res.stderr || ''}`.trim();
  const left = missingDeps();

  if (!res.error && res.status === 0 && !left.length) {
    if (output) console.log(tailLines(output, 8).map((l) => `      ${l}`).join('\n'));
    ok('依赖安装完成');
    return true;
  }

  console.error('    依赖安装失败。');
  if (res.error) console.error(`    原因：${res.error.code} ${res.error.message}`);
  else if (res.status !== 0) console.error(`    原因：npm 退出码 ${res.status}`);
  else console.error(`    原因：npm 报告成功，但 ${left.join('、')} 仍然不在 node_modules 里`);
  if (output) {
    console.error('    npm 的最后几行输出：');
    for (const l of tailLines(output, 12)) console.error(`      ${l}`);
  }
  manualInstallHelp();
  return false;
}

// ------------------------------------------------------------ 2. 定位游戏目录

// Windows 路径大小写不敏感：D:\Steam\... 与 d:\steam\... 指向同一个目录。
// 但 Steam 注册表里的 SteamPath 与本仓库所在路径的大小写**经常不一致**
// （详见下面的 detectCandidates），字符串比较会把同一个目录算成两个候选，
// 于是向导列出「1. D:\...  2. d:\...」两条一模一样的路径让用户选。
// canonicalPath：展示用——盘符统一大写、分隔符统一反斜杠；
// pathKey：去重用——再叠一层小写（Windows 文件系统大小写不敏感）。
function canonicalPath(p) {
  const abs = path.resolve(String(p));
  if (os.platform() !== 'win32') return abs;
  return abs.replace(/\//g, '\\').replace(/^([a-z]):/, (_, d) => `${d.toUpperCase()}:`);
}

function pathKey(p) {
  return canonicalPath(p).toLowerCase();
}

function isGameRoot(dir) {
  try {
    return fs.existsSync(path.join(dir, GAME_EXE_REL));
  } catch (_) {
    return false;
  }
}

// 用户可能给的是 Steam 根目录 / steamapps / common，也可能是 Nornium 目录本身，
// 甚至可能误选到 Binaries。统一折上去 / 折下来试几次。
function resolveGameRoot(input) {
  if (!input) return null;
  let p = String(input).replace(/^["']|["']$/g, '').replace(/[\\/]+$/, '');
  if (!p) return null;
  const candidates = [
    p,
    path.join(p, 'Nornium'),
    path.join(p, 'steamapps', 'common', 'Nornium'),
    path.join(p, 'Steam', 'steamapps', 'common', 'Nornium'),
    path.dirname(p),                 // 误选到 Nornium 内部的子目录
    path.dirname(path.dirname(p)),   // 误选到 Binaries/Win64
  ];
  for (const c of candidates) {
    try {
      if (isGameRoot(c)) return canonicalPath(c);
    } catch (_) { /* ignore bad segments */ }
  }
  return null;
}

// Steam 自身的安装位置 → 里面可能有多个库
function steamPathsFromRegistry() {
  if (os.platform() !== 'win32') return [];
  const keys = [
    ['HKEY_CURRENT_USER\\Software\\Valve\\Steam', 'SteamPath'],
    ['HKEY_LOCAL_MACHINE\\SOFTWARE\\WOW6432Node\\Valve\\Steam', 'InstallPath'],
    ['HKEY_LOCAL_MACHINE\\SOFTWARE\\Valve\\Steam', 'InstallPath'],
  ];
  const found = [];
  for (const [key, valueName] of keys) {
    const res = spawnSync('reg', ['query', key, '/v', valueName], { encoding: 'utf8' });
    if (res.status !== 0 || !res.stdout) continue;
    const m = res.stdout.match(/(?:SteamPath|InstallPath)\s+REG_SZ\s+(.+)/);
    if (m) found.push(m[1].trim());
  }
  return found;
}

// libraryfolders.vdf 里登记了所有 Steam 库（含外置硬盘）
function steamLibraries() {
  const roots = steamPathsFromRegistry();
  const libs = new Set(roots);
  for (const root of roots) {
    const vdf = path.join(root, 'steamapps', 'libraryfolders.vdf');
    if (!fs.existsSync(vdf)) continue;
    try {
      const text = fs.readFileSync(vdf, 'utf8');
      for (const m of text.matchAll(/"path"\s*"([^"]+)"/g)) {
        libs.add(m[1].replace(/\\\\/g, '\\'));
      }
    } catch (_) { /* unreadable vdf — ignore */ }
  }
  return [...libs];
}

function detectCandidates() {
  // Steam 的安装目录与本作的「游戏根目录」不一定重合：本机的 Steam installdir 是
  // …\steamapps\common\Nornium，真正的游戏根是它里面的 …\Nornium（有 Binaries/Win64）。
  // 两种都支持。
  //
  // 去重必须用 pathKey（大小写无关）：本仓库躺在 D:\Steam\…，而 Steam 注册表里的
  // SteamPath 常常写成 d:\steam\…，两个来源会解析出同一个目录的不同大小写写法，
  // 字符串比较就会把它当成两个候选列出来。
  const found = [];
  const seen = new Set();
  const add = (dir) => {
    const resolved = resolveGameRoot(dir);
    if (!resolved) return;
    const key = pathKey(resolved);
    if (seen.has(key)) return;
    seen.add(key);
    found.push(resolved);
  };

  // 本项目就躺在游戏目录里 (…\steamapps\common\Nornium\ServerDev)，先试它
  add(path.join(REPO_ROOT, '..'));

  for (const lib of steamLibraries()) {
    add(path.join(lib, 'steamapps', 'common', 'Nornium'));
  }

  // 兜底：扫一遍各盘符下的常见 Steam 位置
  for (const drive of ['C', 'D', 'E', 'F', 'G']) {
    for (const mid of [
      'Steam',
      'SteamLibrary',
      'Program Files (x86)\\Steam',
      'Program Files\\Steam',
      'Games\\Steam',
      'Games\\SteamLibrary',
    ]) {
      add(path.join(`${drive}:\\`, mid, 'steamapps', 'common', 'Nornium'));
    }
  }
  return found;
}

async function promptGamePath(candidates) {
  if (candidates.length === 1) {
    console.log(`    自动找到游戏安装目录：${candidates[0]}`);
    if (ASSUME_YES) return candidates[0];
    const ans = (await ask('    直接用它吗？回车确认，输入 n 手动指定 > ')).toLowerCase();
    if (!ans || ans === 'y' || ans === 'yes') return candidates[0];
    console.log('    请填游戏根目录（内含 Binaries\\Win64\\GHS-Win64-Shipping.exe 那一层）');
    return await ask('    游戏路径 > ');
  }
  if (candidates.length > 1) {
    console.log('    找到多个候选目录：');
    candidates.forEach((c, i) => console.log(`      ${i + 1}. ${c}`));
    if (!ASSUME_YES) {
      const ans = await ask('    输入序号选择（直接回车用 1，或手填路径）> ');
      const idx = Number(ans);
      if (Number.isInteger(idx) && idx >= 1 && idx <= candidates.length) return candidates[idx - 1];
      if (ans) return ans;
      return candidates[0];
    }
    return candidates[0];
  }

  console.log('    没有自动找到游戏安装目录。');
  console.log('    请填游戏根目录（内含 Binaries\\Win64\\GHS-Win64-Shipping.exe 那一层），');
  console.log('    例如：D:\\Steam\\steamapps\\common\\Nornium');
  return await ask('    游戏路径 > ');
}

// ------------------------------------------------------- 3. 写客户端接入文件

function clientFileSpecs() {
  return [
    {
      name: 'channel.lua',
      // return { channel, port, host, gm_port }
      body: `return {"${CHANNEL}", ${TCP_PORT}, "127.0.0.1", "${HTTP_PORT}"}\n`,
    },
    {
      name: 'version.lua',
      // return { client_version, channel_code, local_build }
      // local_build=true → 客户端跳过热更检查
      body: `return {"${CLIENT_VERSION}", "${CHANNEL_CODE}", true}\n`,
    },
  ];
}

function writeClientFiles(dir) {
  fs.mkdirSync(dir, { recursive: true });
  const written = [];
  for (const spec of clientFileSpecs()) {
    const file = path.join(dir, spec.name);
    if (fs.existsSync(file) && fs.readFileSync(file, 'utf8') === spec.body) continue;
    fs.writeFileSync(file, spec.body, 'utf8');
    written.push(spec.name);
  }
  return written;
}

// ------------------------------------------------------------------- config

function loadConfig() {
  if (RESET) return null;
  try {
    return JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
  } catch (_) {
    return null;
  }
}

function saveConfig(cfg) {
  fs.writeFileSync(CONFIG_FILE, `${JSON.stringify(cfg, null, 2)}\n`, 'utf8');
}

// --------------------------------------------------------- 环境自查（--check）
//
// `node setup.js --check`：**只读**排查，不改文件、不装依赖、不写客户端配置。
// 回答三个最常被问到的问题：
//   1. 我这份代码是修好的吗？（旧版的依赖自动安装 100% 失败，见坑 47）
//   2. 我机器上的依赖到底装了没？下次启动会不会再走安装那一步？
//   3. 游戏目录 / 客户端 channel.lua 还对不对？
// 刻意做成零依赖、且不 spawn 任何外部命令 —— 依赖缺失时也必须能跑起来
// （`preflight.js` 反过来，它 require protobufjs，依赖没装就直接崩，没法用来排查这种问题）。

// 判据：新写法引入了 `npmCliScript()` 调用，且不再裸 spawn npm（旧版是
// `spawnSync('npm.cmd', ...)`）。最小、最抗混淆的两个特征。
//
// **必须先把注释剥掉再匹配**：修复后的文件里恰好**引用**了旧写法（注释里拿它当反面教材、
// 上面「依赖自动安装」那一段就写着 `spawnSync('npm.cmd', ['install'])`），
// 不剥注释会把修好的文件自己判成旧版 —— 这个自检第一次跑就踩了这个坑。
function sourceLooksFixed(src) {
  const code = String(src)
    .replace(/\/\*[\s\S]*?\*\//g, '')          // 块注释
    .replace(/(^|[^:])\/\/[^\n]*/g, '$1');     // 行注释（前面不是 ':' 才算，别误伤 http://）
  return /npmCliScript\s*\(/.test(code) && !/spawnSync\s*\(\s*['"`]npm/i.test(code);
}

function countFiles(dir) {
  try { return fs.readdirSync(dir).length; } catch (_) { return -1; }
}

function collectDoctorReport() {
  const gamedata = countFiles(path.join(REPO_ROOT, 'reference', 'gamedata'));
  const proto = countFiles(path.join(REPO_ROOT, 'reference', 'proto'));

  const deps = ['protobufjs', 'des.js'];
  const present = deps.filter((pkg) => fs.existsSync(path.join(SERVER_DIR, 'node_modules', pkg)));
  const missing = deps.filter((pkg) => !present.includes(pkg));

  const inv = npmInvocation(['install']);
  let src = '';
  try { src = fs.readFileSync(__filename, 'utf8'); } catch (_) { /* unreadable: assume unknown */ }

  const cfg = (() => { try { return JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8')); } catch (_) { return null; } })();
  const dirSaved = savedDir();
  const clientFiles = clientFileSpecs().map((spec) => {
    const out = { name: spec.name, path: dirSaved ? path.join(dirSaved, spec.name) : null, state: 'unknown' };
    if (!dirSaved) return out;
    try {
      if (!fs.existsSync(out.path)) out.state = 'missing';
      else out.state = fs.readFileSync(out.path, 'utf8') === spec.body ? 'current' : 'stale';
    } catch (_) { out.state = 'unreadable'; }
    return out;
  });

  const node = {
    version: process.versions.node,
    exe: process.execPath,
    ok: Number(process.versions.node.split('.')[0]) >= 18,
  };
  const assetsOk = gamedata > 0 && proto > 0;
  const fixed = sourceLooksFixed(src);

  return {
    node,
    npm: {
      mode: inv.command === process.execPath ? 'cli' : 'shell',
      cli: npmCliScript(),
      command: inv.command,
      args: inv.args,
      label: inv.label,
    },
    assets: { gamedata, proto, ok: assetsOk },
    deps: { present, missing, ready: missing.length === 0 },
    wizard: {
      configPath: CONFIG_FILE,
      configured: !!cfg,
      gamePath: cfg ? cfg.game_path : null,
      gamePathValid: !!(cfg && isGameRoot(cfg.game_path)),
      savedDir: dirSaved,
      clientFiles,
    },
    code: { fixed, path: __filename },
    serverDir: SERVER_DIR,
    // 能不能「双击就开玩」：Node 够新 + 资产在 + （代码已修 或 依赖本来就齐）
    ready: node.ok && assetsOk && (fixed || missing.length === 0),
  };
}

function printDoctor(rep) {
  const tick = (good, text) => console.log(`   ${good ? 'OK ' : '~~ '} ${text}`);
  line('=');
  console.log(' 环境自查（--check，只读：不改文件、不装依赖、不写配置）');
  line('=');
  console.log('');

  console.log(' [1] Node.js');
  tick(rep.node.ok, rep.node.ok
    ? `v${rep.node.version}`
    : `v${rep.node.version} —— 太旧了，请到 https://nodejs.org/ 装 LTS 版（要求 >= 18）`);
  console.log(`        ${rep.node.exe}`);

  console.log('');
  console.log(' [2] npm（装依赖时要用）');
  if (rep.npm.mode === 'cli') {
    tick(true, '用当前这个 node 跑它自带的 npm-cli.js（不经过 cmd.exe，不依赖 PATH）');
    console.log(`        ${rep.npm.cli}`);
  } else {
    tick(true, '当前 node 旁边没有 npm-cli.js，会退回 cmd.exe 去 PATH 上找 npm');
  }
  console.log('        下次装依赖会执行：');
  console.log(`          ${rep.npm.label}`);

  console.log('');
  console.log(' [3] 逆向资产（reference/）');
  tick(rep.assets.ok, rep.assets.ok
    ? `gamedata ${rep.assets.gamedata} 个文件 / proto ${rep.assets.proto} 个文件`
    : `缺文件（gamedata ${rep.assets.gamedata} / proto ${rep.assets.proto}）—— 请确认下载的是完整仓库，reference/ 不能被删`);

  console.log('');
  console.log(' [4] 依赖（server/node_modules）');
  if (rep.deps.ready) {
    tick(true, `${rep.deps.present.join('、')} 都在 → 启动时会**跳过**安装步骤（不会联网、不会碰 npm）`);
  } else {
    tick(false, `缺 ${rep.deps.missing.join('、')} → 启动时会自动安装；装不上就手动来：`);
    console.log(`          打开 ${rep.serverDir} → 地址栏输入 cmd 回车 → npm install`);
  }

  console.log('');
  console.log(' [5] 向导状态');
  if (rep.wizard.gamePathValid) {
    tick(true, `游戏目录：${rep.wizard.gamePath}`);
  } else if (rep.wizard.configured) {
    tick(false, `server/runtime-config.json 里记的游戏目录已失效（${rep.wizard.gamePath}）→ 下次启动会重新问你`);
  } else {
    tick(false, '还没配置过（没有 server/runtime-config.json）→ 下次启动会探测/询问游戏目录');
  }
  if (!rep.wizard.savedDir) {
    tick(false, '找不到 %LOCALAPPDATA%，无法写入客户端配置');
  } else {
    for (const f of rep.wizard.clientFiles) {
      const state = {
        current: '已是私服配置（无需改动）',
        stale: '内容不对（指向别处）→ 启动时会被覆盖',
        missing: '不存在 → 启动时会写入',
        unreadable: '读不了（权限？）',
        unknown: '无法判断',
      }[f.state] || f.state;
      tick(f.state === 'current', `${f.name}：${state}`);
    }
    console.log(`        ${rep.wizard.savedDir}`);
  }

  console.log('');
  console.log(' [6] 这份代码是不是修好的版本');
  if (rep.code.fixed) {
    tick(true, 'setup.js 含依赖自动安装修复（坑 47）→ 首次启动的 npm install 会全自动完成');
  } else {
    console.log('   !!  这份 setup.js 还是**修复前**的写法（直接 spawn npm.cmd）：');
    console.log('        缺依赖时首次启动必定报「依赖安装失败」（Node >= 18.20.2 会拒绝执行 .cmd）。');
    console.log(`        救急：打开 ${rep.serverDir} → 地址栏输入 cmd → npm install；
        长期：换成本仓库最新版。`);
  }
  console.log(`        检查的文件：${rep.code.path}`);

  console.log('');
  line('=');
  if (rep.ready) {
    console.log(' 结论：环境就绪 —— 直接双击「点我启动.bat」即可'
      + (rep.deps.ready ? '。' : '（缺依赖会自动装）。'));
  } else {
    console.log(' 结论：还有问题，先按上面的 ~~ / !! 处理，再双击「点我启动.bat」。');
  }
  line('=');
  return rep.ready;
}

async function main() {
  // --check / --doctor：只读自查，跑完即走（不碰任何文件，也不启动服务端）
  if (CHECK) {
    const rep = collectDoctorReport();
    const ready = printDoctor(rep);
    return ready ? 0 : 1;
  }

  // 启动器（点我启动.bat）是纯 ASCII，中文横幅由这里打印，见文件头注释
  line('=');
  console.log(' Nornium ServerDev - 失乐星图本地私服');
  console.log(' 完全免费开源 · 若你是付费买到的，请联系卖家退款，你被骗了');
  line('=');
  console.log('');
  console.log('---- 第 1 步：初始化配置（自动完成，不需要手动拷文件） ----');

  step(1, '检查运行环境');
  if (!checkNode() || !checkReferenceAssets()) return 1;
  ok(`Node.js ${process.versions.node}`);
  if (!ensureDependencies()) return 1;

  const dirSaved = savedDir();
  if (!dirSaved) {
    console.error('无法确定 %LOCALAPPDATA% 目录，无法写入客户端配置。');
    return 1;
  }

  step(2, '定位《失乐星图》安装目录');
  let gamePath = null;
  const cfg = loadConfig();
  if (CLI_GAME_PATH) {
    gamePath = resolveGameRoot(CLI_GAME_PATH);
    if (!gamePath) {
      console.error(`给定路径下没有找到游戏主程序：${CLI_GAME_PATH}`);
      return 1;
    }
  } else if (cfg && isGameRoot(cfg.game_path)) {
    gamePath = canonicalPath(cfg.game_path);
    console.log(`    使用已保存的配置：${gamePath}`);
  } else {
    if (cfg) warn(`已保存的路径失效了（${cfg.game_path}），重新配置。`);
    let answer = await promptGamePath(detectCandidates());
    gamePath = resolveGameRoot(answer);
    while (!gamePath) {
      console.log(`    × "${answer}" 下没有 ${GAME_EXE_REL}，这不像游戏根目录。`);
      answer = await ask('    重填游戏路径（或留空退出）> ');
      if (!answer) return 1;
      gamePath = resolveGameRoot(answer);
    }
  }
  ok(`游戏目录 ${gamePath}`);

  step(3, `写入客户端配置 ${dirSaved}`);
  const written = writeClientFiles(dirSaved);
  if (written.length) ok(`已写入 ${written.join('、')}`);
  else ok('channel.lua / version.lua 已是私服配置，无需改动');

  step(4, '是否自动拉起游戏');
  // 已经有配置时不再重复提问（双击就该直接开玩）：沿用上次的选择，
  // 除非显式 --reset。
  // 有配置就沿用上次的选择；没有配置时默认开启（搭配 --yes 用于无人值守）。
  let autoLaunch = cfg ? Boolean(cfg.auto_launch) : true;
  if (!ASSUME_YES && !cfg) {
    const ans = (await ask('    服务端起来后自动用 Steam 拉起游戏吗？回车=是，输入 n 取消 > '))
      .toLowerCase();
    autoLaunch = !ans || ans === 'y' || ans === 'yes';
  }
  console.log(`    ${autoLaunch ? '已开启' : '未开启'}自动拉起`);
  if (autoLaunch) {
    fs.writeFileSync(AUTO_LAUNCH_FLAG, `steam://rungameid/${STEAM_APP_ID}\n`, 'utf8');
    console.log(`    （不想用了就删掉 ${path.relative(REPO_ROOT, AUTO_LAUNCH_FLAG)}）`);
  } else if (fs.existsSync(AUTO_LAUNCH_FLAG)) {
    fs.rmSync(AUTO_LAUNCH_FLAG, { force: true });
    ok('已删除 auto-launch.flag');
  }

  saveConfig({
    game_path: gamePath,
    saved_dir: dirSaved,
    channel: CHANNEL,
    client_version: CLIENT_VERSION,
    tcp_port: TCP_PORT,
    http_port: HTTP_PORT,
    auto_launch: autoLaunch,
    configured_at: new Date().toISOString(),
  });
  console.log(`    配置已保存到 ${path.relative(REPO_ROOT, CONFIG_FILE)}`);

  line('=');
  console.log(' 配置完成。');
  line('=');
  console.log('');
  if (FROM_BAT) {
    // 启动器只会在本脚本成功返回后再 node index.js，所以这里说明的是"接下来"
    console.log('---- 第 2 步：启动服务端 ----');
    console.log(autoLaunch
      ? ' 接下来会用 Steam 拉起游戏（服务端同时启动），稍等几秒即可看到游戏窗口。'
      : ' 请在 Steam 里手动启动《失乐星图》。');
    console.log(' 游戏登录界面随便填账号和密码，点「注册」就能进主城。');
    console.log(' 停止服务请在本窗口输入 stop 回车（或按 Ctrl+C）。');
    console.log(' 存档在 server\\data\\，删掉它就能重置；');
    console.log(' 想找回旧存档：在本窗口输入 load <备份目录>（见 README）。');
    line('=');
  } else {
    console.log(' 接下来启动服务端：cd server 后 npm start，或直接双击根目录的「点我启动.bat」。');
    console.log(' 存档在 server\\data\\，删掉它就能重置；');
    console.log(' 想找回旧存档：在服务端窗口输入 load <备份目录>（见 README）。');
    line('=');
  }
  return 0;
}

// 被 require 进单测时不要执行向导（setup_check.js 会拿 canonicalPath/detectCandidates 做断言）
if (require.main === module) {
  main()
    .then((code) => {
      closeRl();
      process.exit(code);
    })
    .catch((err) => {
      closeRl();
      console.error('初始化失败：', err && (err.stack || err.message));
      process.exit(1);
    });
}

module.exports = {
  canonicalPath,
  pathKey,
  resolveGameRoot,
  detectCandidates,
  isGameRoot,
  // 依赖自动安装的调用方式（test/setup_check.js 断言「绝不直接 spawn .cmd」，坑 47）
  npmCliScript,
  npmInvocation,
  npmShellInvocation,
  // 环境自查（--check）：sourceLooksFixed 用来判断「这份 setup.js 是不是修好的」
  sourceLooksFixed,
  collectDoctorReport,
};
