// 「锁 60 帧每次重进都被改回平滑帧数」的兜底修复。
//
// 现象与根因：游戏设置界面里的「锁 60 帧 / 平滑帧数」切换只在**内存**里生效 ——
// 客户端自己的设置存档（SG_SaveGame_Settings.sav）里只有 GraphQuality 一个字段，
// 引擎的 GameUserSettings.ini 里也从来没有 bUseSmoothFrameRate / FrameRateLimit=60
// 落盘（实测见 REVERSE_ENGINEERING.md 14.x），所以每次重启都回到引擎默认的
// 平滑帧数（bUseSmoothFrameRate=true，FrameRateLimit=0）。这是客户端 UMG 的 bug，
// 私服改不了 pak 里的界面（坑 14），但改得动引擎的配置文件。
//
// 做法：每次服务端启动时，把
//     [/Script/GHS.GHSGameUserSettings] / [/Script/Engine.GameUserSettings] 两节里的
//     bUseSmoothFrameRate=False
//     FrameRateLimit=<N>.000000
// 合并进 %LOCALAPPDATA%\Nornium\Saved\Config\Windows\GameUserSettings.ini。
// UE 在启动时 LoadSettings() 会读这两节（游戏自己的分辨率/画质就是从 GHS 节读的，
// 见该文件里已存的 ResolutionSizeX 等键），于是进游戏即是锁定 N 帧 —— 界面上显示
// 哪个开关已经无所谓了，实际帧率以引擎配置为准。
//
// 幂等：值已经正确时不动文件；只改这两个键，其余内容原样保留。游戏自己保存设置时
// 会整份重写该文件（这是引擎行为），所以本修复在**每次服务端启动**时重新钉一遍。
// 想关掉：runtime-config.json 里加 "frame_lock_fps": 0（或 false）。
const fs = require('fs');
const path = require('path');
const log = require('./logger');

const DEFAULT_FPS = 60;

function savedDir() {
  // runtime-config.json 的 saved_dir 由 setup.js 写入（向导里定位过的那个 Saved 目录），
  // 没有就退回 %LOCALAPPDATA% 的标准位置。
  try {
    const cfg = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'runtime-config.json'), 'utf8'));
    if (cfg.saved_dir) return cfg.saved_dir;
  } catch (_) { /* 没有配置文件时走默认 */ }
  const appData = process.env.LOCALAPPDATA;
  return appData ? path.join(appData, 'Nornium', 'Saved') : null;
}

// 解析 frame_lock_fps：60（默认）/ 数字 / 0|false 关闭。
function lockFpsFromConfig() {
  try {
    const cfg = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'runtime-config.json'), 'utf8'));
    if ('frame_lock_fps' in cfg) {
      const v = cfg.frame_lock_fps;
      if (v === false || v === 0 || v === '0') return 0;
      const n = Math.trunc(Number(v));
      if (Number.isFinite(n) && n > 0) return n;
    }
  } catch (_) { /* 走默认 */ }
  return DEFAULT_FPS;
}

// 把 keys 合并进 ini 的指定节（节不存在则追加到文件尾部）。返回是否真的改了内容。
// 保留原文件的行尾风格（UE 写的是 CRLF，别顺手全换成 LF）。
function mergeIniSection(text, section, keys) {
  const eol = text.includes('\r\n') ? '\r\n' : '\n';
  const lines = text.split(/\r?\n/);
  const headerRe = /^\s*\[(.+?)\]\s*$/;
  let secStart = -1;
  let secEnd = lines.length;
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(headerRe);
    if (!m) continue;
    if (secStart >= 0) { secEnd = i; break; } // 下一节开始 = 目标节结束
    if (m[1].trim().toLowerCase() === section.toLowerCase()) secStart = i;
  }
  if (secStart < 0) {
    // 目标节不存在：追加到尾部再写入
    const block = ['', `[${section}]`,
      ...Object.entries(keys).map(([k, v]) => `${k}=${v}`)];
    return { text: `${text.replace(/\s+$/, '')}\n${block.join('\n')}\n`.replace(/\n/g, eol), changed: true };
  }
  const merged = { ...keys };
  let changed = false;
  for (let i = secStart + 1; i < secEnd; i++) {
    const kv = lines[i].match(/^\s*([A-Za-z_]\w*)\s*=([^;]*)/);
    if (!kv || !(kv[1] in merged)) continue;
    if (lines[i] !== `${kv[1]}=${merged[kv[1]]}`) changed = true;
    lines[i] = `${kv[1]}=${merged[kv[1]]}`;
    delete merged[kv[1]];
  }
  const additions = Object.entries(merged);
  if (additions.length) {
    lines.splice(secEnd, 0, ...additions.map(([k, v]) => `${k}=${v}`));
    changed = true;
  }
  return { text: lines.join(eol), changed };
}

// 往 GameUserSettings.ini 钉入帧率配置。返回描述动作的字符串（供日志）。
function pinFrameLock() {
  const fps = lockFpsFromConfig();
  if (!fps) return 'frame_lock_fps=0，跳过（不修改客户端帧率配置）';
  const dir = savedDir();
  if (!dir) return '无法确定客户端 Saved 目录，跳过';
  const iniPath = path.join(dir, 'Config', 'Windows', 'GameUserSettings.ini');

  let text = '';
  try {
    text = fs.readFileSync(iniPath, 'utf8');
  } catch (_) {
    text = ''; // 文件不存在（没跑过游戏）：创建一份只含这两节的
  }

  const sections = ['GHS.GHSGameUserSettings', 'Engine.GameUserSettings'];
  let next = text;
  let changed = false;
  for (const sec of sections) {
    // 键写在「游戏自己的子类节」与「引擎父类节」各一份：UE 的 LoadSettings 读的是
    // 具体子类节（/Script/GHS.GHSGameUserSettings），父类节里那份是给手工排查时
    // 对齐标准 UE 布局的，两份内容一致不会打架。
    const merged = mergeIniSection(next, `/Script/${sec}`, {
      bUseSmoothFrameRate: 'False',
      FrameRateLimit: `${fps}.000000`,
    });
    next = merged.text;
    changed = changed || merged.changed;
  }

  if (!changed) return `帧率锁定已是 ${fps} FPS，无需改动`;
  try {
    fs.mkdirSync(path.dirname(iniPath), { recursive: true });
    fs.writeFileSync(iniPath, next, 'utf8');
    return `已在 GameUserSettings.ini 钉入「锁 ${fps} 帧」（bUseSmoothFrameRate=False, `
      + `FrameRateLimit=${fps}）—— 客户端设置界面的帧率选项不落盘（设置存档里只有`
      + ' GraphQuality），这里每次服务端启动都重新钉一遍';
  } catch (err) {
    return `写入 GameUserSettings.ini 失败：${err.message}`;
  }
}

module.exports = { pinFrameLock, mergeIniSection, lockFpsFromConfig, DEFAULT_FPS };
