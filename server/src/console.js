// 服务端控制台指令：在运行服务端的那个窗口里直接敲命令回车。
//
//   restore          清空本地存档（accounts.json + players/），在线玩家全部踢下线。
//                    用于发布前把服务端恢复成"干净正式版"。删之前自动快照一份。
//   load [<备份目录>] 从磁盘重新加载存档。不带参数＝重读 server\data\；
//                    带参数＝把该备份目录（或它的下级 data\）覆盖式导入 server\data\，
//                    再热加载，不用重启、也不用手工拷文件。
//   export [目录]     把当前存档整份导出到指定目录；不带参数＝导到默认备份位置
//                    （server\data_export_<时间戳>\）。在线玩家会被踢下线以保证快照一致。
//   allweapons [账号] 给玩家档案发放「高稀有度武器」：已实装的 6★/7★ 武器每种各一把，
//                    入包不自动装备。不带参数＝只发默认账号（见 DEFAULT_ALLWEAPONS_ACCOUNT_ID）；
//                    可给账号 ID / 账号名 / all。
//                    （早期版本是「每个角色发一把同类型最高稀有度」，会发到未实装武器
//                     1081601「颂歌」上去 —— 那把没有模型/图标/技能行，见 game/weapon_data.js。）
//   allexclusive [账号]
//                    给玩家档案发放「专武」：每名可玩角色的 7★ 专属武器各一把（映射与
//                    证据见 game/weapon_data.js 的 CHARACTER_EXCLUSIVE_WEAPONS）。
//                    目标账号解析与 allweapons 相同。
//   addchar <账号> <角色id|all>
//                    给玩家档案添加角色（含专属武器/技能/默认皮肤）。新号开局只发教学
//                    三人小队（game/player_new.js 的 starterCharacterIds），其余角色靠
//                    抽卡/这条指令/编辑器补。
//   allskins [账号]   给玩家档案解锁全部已拥有角色的全部皮肤（直接写 own_*_skin_ids，
//                    不发皮肤卡道具；游戏内角色页「装扮」即可换）。
//   addres [账号] <1..4> <数量>
//                    给「进行中的远航」补肉鸽资源（res_value，1..4 号），数量可负。
//                    没有进行中的远航就跳过——资源只存在于局内，背包指令救不了它。
//                    平时更方便的是游戏内 GM 指令 add_res（即时生效不用下线）。
//   stop             踢掉所有在线玩家并停止服务端进程。
//   status           看一眼在线人数与存档数量。
//   help             指令列表。
//
// 设计要点：
// - **动磁盘存档前必须硬排空在线会话**（drainSessions）并停止接受新连接，
//   这是由 index.js 注入的维护窗口（hooks.maintenance）负责的：
//     停止 accept → 排空 → 改档 → 恢复监听。
//   为什么不能只 sleep 一小段：任何残余会话的 savePlayer 都会把内存里的旧 doc 整份
//   写回磁盘，覆盖掉刚恢复的档；而且 handlers/index.js 的 dailyTick 是 60s 定时器，
//   同样会 savePlayer——固定的短窗口挡不住它。
// - handleCommand() 只做决策、返回 { action, reply }，真正 process.exit 由 index.js
//   在收到 action === 'stop' 时执行——这样单测可以全流程跑一遍而不真的退出进程。
const path = require('path');
const fs = require('fs');
const readline = require('readline');
const store = require('./store');
const { drainSessions, liveSessionCount } = require('./session');
const log = require('./logger');
const arsenal = require('./game/arsenal');

// 项目主页：单一来源是 package.json.homepage（编辑器网页 / 启动器 / 服务端横幅同源）。
const REPO_URL = require('../package.json').homepage
  || 'https://github.com/XUNDEI/Nornium-ServerDev';

// allweapons / allexclusive 不带参数时只发这一个账号（服主本人的主档 xundei，2026-09-25 确认）。
// 想发给别的档用 `allweapons <账号ID|账号名|all>` 或 `allexclusive <账号ID|账号名|all>`。
const DEFAULT_ALLWEAPONS_ACCOUNT_ID = 10;

// 没有 index.js（单测）时的降级：只排空，不动监听套接字
function runGated(hooks, fn) {
  const maintenance = hooks && hooks.maintenance;
  if (typeof maintenance === 'function') return maintenance(fn);
  return drainSessions().then((drain) => fn(drain));
}

function relToData(target) {
  return path.relative(path.dirname(store.dataDirPath()), target);
}

function fmtStats(stats) {
  return `${stats.accounts} 个账号 / ${stats.players} 个玩家档案`;
}

async function cmdRestore(hooks) {
  const before = store.dataStats();
  return runGated(hooks, async (drain) => {
    const snapshot = store.resetData(); // 内部先快照再删
    log.warn('[console] restore：本地存档已清空');
    let msg = `>> 存档已全部清空（删除 accounts.json + ${before.players} 个玩家档案），`
      + `在线 ${drain.kicked} 人已踢下线。服务端继续运行，下一位注册的就是全新档案。`;
    if (snapshot) {
      msg += `\n>> 清空前已自动备份到 ${relToData(snapshot.dir)}`
        + `（要撤销就把里面的 accounts.json / players\\*.json 拷回 server\\data\\ 再 load）。`;
    }
    return { action: 'none', reply: msg };
  });
}

// 校验用户给的备份来源。返回 { srcDir } 或 { error }（校验放在排空之前，
// 路径写错了当场就说，不要白等一次维护窗口）。
function checkLoadSource(input) {
  if (!input) return { srcDir: null };
  const srcDir = store.resolveBackupSource(input);
  if (!srcDir) {
    return {
      error: `>> × 在 "${input}" 里没找到 accounts.json，不像是存档备份目录。\n`
        + '>>   请指向含 accounts.json 与 players\\ 的那一层（给它的上级也行，我会自动找 data\\）。\n'
        + '>>   或者按老办法：把文件拷进 server\\data\\ 后直接输入 load。',
    };
  }
  if (path.resolve(srcDir) === path.resolve(store.dataDirPath())) {
    return { error: `>> × "${srcDir}" 就是当前存档目录本身，没有可导入的内容。` };
  }
  return { srcDir };
}

async function cmdLoad(sourceInput, hooks) {
  const { srcDir, error } = checkLoadSource(sourceInput);
  if (error) return { action: 'none', reply: error };

  return runGated(hooks, async (drain) => {
    let snapshot = null;
    let imported = null;
    if (srcDir) {
      snapshot = store.snapshotData('preimport'); // 覆盖前兜底
      imported = store.importData(srcDir);
    }
    store.loadAccounts(); // 从磁盘重读 accounts.json，覆盖内存里的账号表

    const stats = store.dataStats();
    log.info(`[console] load：重新加载存档（${stats.accounts} 账号 / ${stats.players} 玩家）`
      + (srcDir ? `，来源 ${srcDir}` : ''));

    const lines = [];
    if (srcDir) {
      lines.push(`>> 已从 "${srcDir}" 导入：${imported.accounts ? '账号表 1 份' : '（没有 accounts.json）'}`
        + ` / ${imported.players} 个玩家档案。`);
      if (snapshot) lines.push(`>> 导入前的旧档已备份到 ${relToData(snapshot.dir)}。`);
    }
    lines.push(`>> 已从磁盘重新加载存档：${fmtStats(stats)}，`
      + `在线 ${drain.kicked} 人已踢下线（重新登录即读到新档）。`);
    if (!srcDir) {
      lines.push('>> 提示：把备份的 accounts.json / players\\*.json 拷回 server\\data\\ 后执行 load 即可热加载；'
        + '也可以直接 load <备份目录>，由我来拷。');
    }
    if (stats.accounts === 0 && stats.players === 0) {
      lines.push('>> 注意：server\\data\\ 现在是空的（发布前清过档是正常的）。'
        + '要恢复旧档就用 load <备份目录>，或手工把文件拷进 server\\data\\。');
    }
    return { action: 'none', reply: lines.join('\n') };
  });
}

async function cmdStop() {
  const drain = await drainSessions();
  return { action: 'stop', reply: `>> 在线 ${drain.kicked} 人已踢下线，正在停止服务端…` };
}

// 校验 export 的目标目录：空参数走默认快照位置；目录已是文件 / 就是存档目录本身都当场拒绝
//（校验放在排空之前，路径写错了不要白等一次维护窗口）。
function checkExportDest(input) {
  if (!input) return { dest: null };
  const dest = path.resolve(String(input).trim().replace(/^["']|["']$/g, ''));
  if (dest === path.resolve(store.dataDirPath())) {
    return { error: `>> × "${dest}" 就是当前存档目录本身，不能导出到这里。` };
  }
  try {
    if (fs.existsSync(dest) && !fs.statSync(dest).isDirectory()) {
      return { error: `>> × "${dest}" 已存在且不是目录。` };
    }
  } catch (_) { /* 当作不存在的目录处理，exportData 会创建 */ }
  return { dest };
}

async function cmdExport(destInput, hooks) {
  const { dest, error } = checkExportDest(destInput);
  if (error) return { action: 'none', reply: error };

  return runGated(hooks, async (drain) => {
    let result;
    let where;
    if (dest) {
      result = store.exportData(dest);
      where = result.dir;
    } else {
      // 默认备份位置：server\data_export_<时间戳>\（与快照同一套命名规则）
      const snapshot = store.snapshotData('export');
      if (!snapshot) {
        return { action: 'none', reply: '>> 存档是空的（没有 accounts.json 也没有玩家档案），没有可导出的内容。' };
      }
      result = { accounts: true, players: snapshot.players };
      where = snapshot.dir;
    }
    log.info(`[console] export：存档已导出到 ${where}`);
    return {
      action: 'none',
      reply: `>> 存档已导出到 ${where}\n`
        + `>>   内容：${result.accounts ? 'accounts.json' : '（没有 accounts.json）'} + ${result.players} 个玩家档案；`
        + `在线 ${drain.kicked} 人已踢下线（重新登录即可）。`,
    };
  });
}

// 把 allweapons/addchar/allskins 的目标账号解析成 [{id, name}]。返回 { targets } 或 { error }。
// 不带参数＝默认账号（服主本人的主档）；可给账号 ID / 账号名 / all（全部档案）。
function resolveTargets(arg, what) {
  store.loadAccounts();
  const input = String(arg || '').trim();
  if (!input) {
    const rec = store.findAccount(DEFAULT_ALLWEAPONS_ACCOUNT_ID)
      || { account_id: DEFAULT_ALLWEAPONS_ACCOUNT_ID, account_name: `#${DEFAULT_ALLWEAPONS_ACCOUNT_ID}` };
    return { targets: [{ id: DEFAULT_ALLWEAPONS_ACCOUNT_ID, name: rec.account_name }] };
  }
  if (/^(all|全部)$/i.test(input)) {
    const ids = store.listPlayerIds();
    if (ids.length === 0) return { error: `>> × 现在没有任何玩家档案，没东西可${what}。` };
    const names = {};
    for (const rec of Object.values(store.loadAccounts().by_name || {})) {
      names[rec.account_id] = rec.account_name;
    }
    return { targets: ids.map((id) => ({ id, name: names[id] || `#${id}` })) };
  }
  if (/^\d+$/.test(input)) {
    const id = Number(input);
    const rec = store.findAccount(id) || { account_id: id, account_name: `#${id}` };
    return { targets: [{ id, name: rec.account_name }] };
  }
  const rec = store.findAccount(input);
  if (!rec) return { error: `>> × 没有叫 "${input}" 的账号。可用账号 ID、账号名或 all（全部档案）。` };
  return { targets: [{ id: rec.account_id, name: rec.account_name }] };
}

// allweapons 的老解析函数保留为别名（语义完全一致，只是换了名字）。
const resolveWeaponTargets = resolveTargets;

// allweapons / allexclusive 共用的发放主体。mode = 'high_rarity' 发全部已实装 6★/7★，
// mode = 'exclusive' 发每名可玩角色的 7★ 专武。
async function cmdGrantWeapons(arg, hooks, mode) {
  const { targets, error } = resolveTargets(arg, '发');
  if (error) return { action: 'none', reply: error };

  const label = mode === 'exclusive' ? 'allexclusive' : 'allweapons';
  const noun = mode === 'exclusive' ? '专武' : '高稀有度武器';
  const grant = mode === 'exclusive'
    ? (doc) => arsenal.grantExclusiveWeapons(doc)
    : (doc) => arsenal.grantHighRarityWeapons(doc);

  return runGated(hooks, async (drain) => {
    const lines = [];
    let total = 0;
    for (const { id, name } of targets) {
      const doc = store.loadPlayer(id);
      if (!doc) {
        lines.push(`>>   ${name}：该账号还没有玩家档案，跳过。`);
        continue;
      }
      const { granted } = grant(doc);
      store.savePlayer(doc);
      total += granted.length;
      const brief = granted
        .map((g) => `${g.item_id}(${g.rarity}★)`)
        .join(' ');
      lines.push(`>>   ${name}（档案 ${id}）：发出 ${granted.length} 把  ${brief}`);
    }
    log.info(`[console] ${label}：目标 ${targets.length} 个档案，共发放 ${total} 把${noun}`);
    if (total === 0) lines.push('>>   （没有实际发放任何武器）');
    lines.push('>> 只进背包、不会自动装备；在线玩家已踢下线，重新登录后到背包领取。');
    return { action: 'none', reply: lines.join('\n') };
  });
}

async function cmdAllWeapons(arg, hooks) {
  return cmdGrantWeapons(arg, hooks, 'high_rarity');
}

// allexclusive <账号>：每名可玩角色的 7★ 专属武器各一把（十把，映射与证据见
// game/weapon_data.js 的 CHARACTER_EXCLUSIVE_WEAPONS）。入包不自动装备。
async function cmdAllExclusive(arg, hooks) {
  return cmdGrantWeapons(arg, hooks, 'exclusive');
}

// addchar <账号> <角色id|all>：给玩家档案添加角色（不再随开局自动发放全部角色后的
// 指令入口之一，编辑器「一键加全角色」是另一个）。all = 全部可玩角色。
async function cmdAddChar(arg, hooks) {
  const parts = String(arg || '').trim().split(/\s+/).filter(Boolean);
  if (parts.length < 2) {
    return { action: 'none', reply: '>> 用法：addchar <账号ID|账号名|all> <角色id|all>\n'
      + '>>   例：addchar xundei 10401   addchar 10 all' };
  }
  const { targets, error } = resolveTargets(parts[0], '发');
  if (error) return { action: 'none', reply: error };

  const playerNew = require('./game/player_new');
  let charIds;
  if (/^(all|全部)$/i.test(parts[1])) {
    charIds = playerNew.initialCharacterIds();
  } else {
    const id = Number(parts[1]);
    if (!playerNew.isPlayableCharacter(id)) {
      return { action: 'none', reply: `>> × 角色 ${parts[1]} 不是可玩角色（可用 all 发全部）。` };
    }
    charIds = [id];
  }

  return runGated(hooks, async (drain) => {
    const lines = [];
    let total = 0;
    for (const { id, name } of targets) {
      const doc = store.loadPlayer(id);
      if (!doc) {
        lines.push(`>>   ${name}：该账号还没有玩家档案，跳过。`);
        continue;
      }
      const added = [];
      for (const charId of charIds) {
        if (doc.characters.some((c) => c.character_id === charId)) continue;
        doc.characters.push(playerNew.buildCharacter(doc, charId));
        added.push(charId);
      }
      store.savePlayer(doc);
      total += added.length;
      lines.push(`>>   ${name}（档案 ${id}）：新增角色 ${added.length} 个${added.length ? `：${added.join(', ')}` : ''}`);
    }
    log.info(`[console] addchar：目标 ${targets.length} 个档案，共新增 ${total} 个角色`);
    if (total === 0) lines.push('>>   （没有实际新增任何角色——可能都已经拥有了）');
    lines.push('>> 含专属武器/技能/默认皮肤；在线玩家已踢下线，重新登录后生效。');
    return { action: 'none', reply: lines.join('\n') };
  });
}

// addres [账号ID|账号名|all] <1..4> <数量>：给「进行中的远航」补肉鸽资源
// （res_value 1..4 号，可给负数扣减）。切角色/游商/晋升都从这 4 个资源扣，
// 资源见底时用这条（或游戏内 GM add_res）救急。资源只存在于局内——没有
// active 远航的档案没有东西可加，会被跳过。
async function cmdAddRes(arg, hooks) {
  const parts = String(arg || '').trim().split(/\s+/).filter(Boolean);
  let targetArg = '';
  let typeArg = '';
  let countArg = '';
  if (parts.length >= 3) [targetArg, typeArg, countArg] = parts;
  else if (parts.length === 2) [typeArg, countArg] = parts;
  else {
    return { action: 'none', reply: '>> 用法：addres [账号ID|账号名|all] <资源1..4> <数量>\n'
      + '>>   例：addres 2 500（默认账号的资源2 +500）   addres xundei 1 -50' };
  }
  const { targets, error } = resolveTargets(targetArg, '发');
  if (error) return { action: 'none', reply: error };
  const type = Number(typeArg);
  const delta = Math.trunc(Number(countArg));
  if (!(type >= 1 && type <= 4) || !Number.isFinite(delta) || delta === 0) {
    return { action: 'none', reply: `>> × 资源号必须是 1..4，数量必须是非零整数（收到 "${typeArg} ${countArg}"）。` };
  }

  return runGated(hooks, async () => {
    const lines = [];
    let touched = 0;
    for (const { id, name } of targets) {
      const doc = store.loadPlayer(id);
      if (!doc || !doc.universe || !doc.universe.active) {
        lines.push(`>>   ${name}：没有进行中的远航，跳过（资源只在局内，先开局再来）。`);
        continue;
      }
      const before = doc.universe.res_value[type] ?? 0;
      doc.universe.res_value[type] = before + delta;
      store.savePlayer(doc);
      touched += 1;
      lines.push(`>>   ${name}（档案 ${id}）：资源${type} ${before} → ${doc.universe.res_value[type]}`);
    }
    log.info(`[console] addres：目标 ${targets.length} 个档案，实际改动 ${touched} 局`);
    if (touched === 0) lines.push('>>   （没有实际改动任何一局远航）');
    lines.push('>> 在线玩家已被请下线，重新登录后远航会带着新资源恢复。');
    return { action: 'none', reply: lines.join('\n') };
  });
}

// allskins [账号|all]：给玩家档案解锁全部已拥有角色的全部皮肤（战斗/机甲/主城）。
// 直接写角色的 own_*_skin_ids，不发皮肤卡道具。
async function cmdAllSkins(arg, hooks) {
  const { targets, error } = resolveTargets(arg, '发');
  if (error) return { action: 'none', reply: error };

  return runGated(hooks, async (drain) => {
    const lines = [];
    let total = 0;
    for (const { id, name } of targets) {
      const doc = store.loadPlayer(id);
      if (!doc) {
        lines.push(`>>   ${name}：该账号还没有玩家档案，跳过。`);
        continue;
      }
      const skins = require('./game/skins');
      const { chars, added } = skins.unlockAllSkins(doc);
      store.savePlayer(doc);
      total += added;
      lines.push(`>>   ${name}（档案 ${id}）：新解锁皮肤 ${added} 个（涉及角色 `
        + `${chars.map((c) => c.character_id).join(',') || '无'}）`);
    }
    log.info(`[console] allskins：目标 ${targets.length} 个档案，共解锁 ${total} 个皮肤`);
    if (total === 0) lines.push('>>   （没有实际解锁任何皮肤——可能都已经解锁，或没有任何角色）');
    lines.push('>> 只对已拥有的角色生效；在线玩家已踢下线，重新登录后在角色页「装扮」里换。');
    return { action: 'none', reply: lines.join('\n') };
  });
}

function cmdStatus() {
  const stats = store.dataStats();
  return {
    action: 'none',
    reply: `>> 在线连接 ${liveSessionCount()} 个；存档：${stats.accounts} 个账号 / ${stats.players} 个玩家档案。\n>> 项目主页：${REPO_URL}`,
  };
}

function cmdHelp() {
  return {
    action: 'none',
    reply: [
      '>> 可用指令（输入后回车）：',
      '>>   restore           清空本地存档（发布干净正式版用，在线玩家会被踢下线，清空前自动备份）',
      '>>   load              从磁盘重新加载存档（把备份拷回 server\\data\\ 后热加载）',
      '>>   load <备份目录>    直接把备份目录导入 server\\data\\ 再热加载，不用手工拷文件',
      '>>   export [目录]     把当前存档整份导出（不带参数＝导到默认备份位置）',
      '>>   allweapons [账号]  给玩家发放全部高稀有度武器（已实装的 6★/7★ 各一把；不带参数＝默认账号；可给 ID/账号名/all）',
      '>>   allexclusive [账号] 给玩家发放全部专武（每名可玩角色一把 7★ 专属武器；目标账号写法同 allweapons）',
      '>>   addchar <账号> <角色id|all>  给玩家添加角色（含专属武器/技能；新号不再自动发全角色，用这个补）',
      '>>   allskins [账号]    给玩家解锁全部已拥有角色的全部皮肤（可给 ID/账号名/all）',
      '>>   addres [账号] <1..4> <数量>  给进行中的远航补肉鸽资源（数量可负）',
      '>>   stop              踢掉所有在线玩家并停止服务端',
      '>>   status            查看在线人数与存档数量',
      '>>   help              显示本帮助',
      `>> 项目主页：${REPO_URL}`,
    ].join('\n'),
  };
}

// 解析一行输入。独立导出以便单测（测试里不会有真的进程退出）。
// 注意：只有命令名参与匹配时小写，后面的参数（可能是 Windows 路径）原样传给处理器，
// 报错回显也用原文，避免出现"我明明打的是大写，报错里却全小写"的困惑。
async function handleCommand(raw, hooks) {
  const line = String(raw ?? '').trim();
  if (!line) return { action: 'none', reply: '' };
  const parts = line.split(/\s+/);
  const name = parts[0].toLowerCase();
  const arg = parts.slice(1).join(' ').trim();
  switch (name) {
    case 'restore': return cmdRestore(hooks);
    case 'load': return cmdLoad(arg, hooks);
    case 'export': return cmdExport(arg, hooks);
    case 'allweapons': return cmdAllWeapons(arg, hooks);
    case 'allexclusive': return cmdAllExclusive(arg, hooks);
    case 'addchar': case 'add_character': return cmdAddChar(arg, hooks);
    case 'allskins': case 'allskins_unlock': return cmdAllSkins(arg, hooks);
    case 'addres': case 'add_res': return cmdAddRes(arg, hooks);
    case 'stop': return cmdStop();
    case 'status': return cmdStatus();
    case 'help': case '?': case '？': return cmdHelp();
    default:
      return { action: 'none', reply: `>> 未知指令 "${line}"。可用：restore / load / export / allweapons / allexclusive / addchar / allskins / addres / stop / status / help` };
  }
}

function startConsole({ onStop, maintenance } = {}) {
  const hooks = { maintenance };
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    prompt: '',
  });
  rl.on('line', (line) => {
    handleCommand(line, hooks)
      .then(({ action, reply }) => {
        if (reply) console.log(reply);
        if (action === 'stop') {
          try { rl.close(); } catch (_) { /* ignore */ }
          onStop();
        }
      })
      .catch((err) => console.error(`>> 指令执行出错：${err.stack || err.message}`));
  });
  // stdin 被关闭（如重定向/管道 EOF）时保持服务端运行，指令功能静默失效
  rl.on('close', () => {
    log.info('[console] 标准输入已关闭，控制台指令不可用（服务端继续运行）');
  });
  // 一行足矣：完整清单由 help 提供，启动时不必再刷一遍（以前这行 300+ 字符）。
  console.log('>> 控制台已就绪：输入 help 查看全部指令（stop 停服）。');
  return rl;
}

module.exports = { handleCommand, startConsole };
