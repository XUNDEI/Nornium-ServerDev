// 首次启动向导：让新玩家「输入游戏路径」即可开玩，不再手工拷贝任何文件。
//
// 做三件事（全部幂等，第二次运行会静默跳过）：
//   1. 校验运行环境（Node >= 18、reference/ 数据是否完整、依赖是否装好）
//   2. 定位《失乐星图》的安装目录（自动探测 Steam 库，失败才问用户），
//      并把结果缓存到 server/runtime-config.json
//   3. 把客户端需要的 channel.lua / version.lua 写进
//      %LOCALAPPDATA%\Nornium\Saved\（lox 的接入点，见 REVERSE_ENGINEERING.md 3.1）
//
// 用法：node setup.js [--reset] [--game-path=<dir>] [--yes]

/* eslint-disable no-console */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const readline = require('readline');
const { spawnSync } = require('child_process');

// --- 必须与 index.js 保持一致 ------------------------------------------------
const TCP_PORT = 8101;
const HTTP_PORT = 8089;
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
const CLI_GAME_PATH = flagValue('--game-path');

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
function ask(question) {
  return new Promise((resolve) => rl.question(question, (answer) => resolve(String(answer).trim())));
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

function ensureDependencies() {
  const missing = ['protobufjs', 'des.js']
    .filter((pkg) => !fs.existsSync(path.join(SERVER_DIR, 'node_modules', pkg)));
  if (!missing.length) {
    ok('依赖已就绪（protobufjs / des.js）');
    return true;
  }
  console.log(`    首次运行：正在安装依赖 ${missing.join('、')} …`);
  const npm = os.platform() === 'win32' ? 'npm.cmd' : 'npm';
  const res = spawnSync(npm, ['install'], { cwd: SERVER_DIR, stdio: 'inherit' });
  if (res.status !== 0) {
    console.error('依赖安装失败，请在 server 目录手动执行 npm install 后重试。');
    return false;
  }
  const stillMissing = ['protobufjs', 'des.js']
    .filter((pkg) => !fs.existsSync(path.join(SERVER_DIR, 'node_modules', pkg)));
  if (stillMissing.length) {
    console.error(`依赖仍然缺失：${stillMissing.join('、')}`);
    return false;
  }
  ok('依赖安装完成');
  return true;
}

// ------------------------------------------------------------ 2. 定位游戏目录

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
      if (isGameRoot(c)) return path.resolve(c);
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
  const found = [];
  const add = (dir) => {
    const resolved = resolveGameRoot(dir);
    if (resolved && !found.includes(resolved)) found.push(resolved);
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

async function main() {
  line('=');
  console.log(' Nornium ServerDev —— 首次启动向导');
  console.log(' 完全免费开源 · 若你是付费买到的，请联系卖家退款，你被骗了');
  line('=');

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
    gamePath = path.resolve(cfg.game_path);
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
  console.log(' 配置完成。接下来会启动服务端，然后自动打开游戏。');
  console.log(' 登录界面随便填账号密码，点「注册」即可进入主城。');
  console.log(' 存档在 server\\data\\，删掉它就能重置。');
  line('=');
  return 0;
}

main()
  .then((code) => {
    rl.close();
    process.exit(code);
  })
  .catch((err) => {
    rl.close();
    console.error('初始化失败：', err && (err.stack || err.message));
    process.exit(1);
  });
