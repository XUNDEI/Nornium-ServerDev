// 服务端控制台指令：在运行服务端的那个窗口里直接敲命令回车。
//
//   restore  清空本地存档（accounts.json + players/），在线玩家全部踢下线。
//            用于发布前把服务端恢复成"干净正式版"。
//   load     从磁盘重新加载存档。把备份拷回 server/data/ 之后用它热加载，不用重启。
//   stop     踢掉所有在线玩家并停止服务端进程。
//   status   看一眼在线人数与存档数量。
//   help     指令列表。
//
// 设计要点：
// - kick 是异步断开（session.js 里 100ms 后才 destroy socket），而 restore/load 会
//   动磁盘上的存档文件，所以先踢人、等 KICK_DRAIN_MS 再动文件，防止残余会话的
//   savePlayer 把内存里的旧档案写回去。
// - handleCommand() 只做决策、返回 { action, reply }，真正 process.exit 由 index.js
//   在收到 action === 'stop' 时执行——这样单测可以全流程跑一遍而不真的退出进程。
const readline = require('readline');
const store = require('./store');
const { kickAllSessions, liveSessionCount } = require('./session');
const log = require('./logger');

const KICK_DRAIN_MS = 300;
const delay = (ms) => new Promise((r) => setTimeout(r, ms));

async function cmdRestore() {
  const before = store.dataStats();
  const kicked = kickAllSessions(1);
  await delay(KICK_DRAIN_MS);
  store.resetData();
  const msg = `>> 存档已全部清空（删除 accounts.json + ${before.players} 个玩家档案），`
    + `在线 ${kicked} 人已踢下线。服务端继续运行，下一位注册的就是全新档案。`;
  log.warn('[console] restore：本地存档已清空');
  return { action: 'none', reply: msg };
}

async function cmdLoad() {
  const kicked = kickAllSessions(1);
  await delay(KICK_DRAIN_MS);
  store.loadAccounts(); // 从磁盘重读 accounts.json，覆盖内存里的账号表
  const stats = store.dataStats();
  log.info(`[console] load：重新加载存档（${stats.accounts} 账号 / ${stats.players} 玩家）`);
  return {
    action: 'none',
    reply: `>> 已从磁盘重新加载存档：${stats.accounts} 个账号 / ${stats.players} 个玩家档案，`
      + `在线 ${kicked} 人已踢下线（重新登录即读到新档）。`
      + `\n>> 提示：把备份的 accounts.json / players\\*.json 拷回 server\\data\\ 后执行 load 即可热加载。`,
  };
}

async function cmdStop() {
  const kicked = kickAllSessions(1);
  await delay(KICK_DRAIN_MS);
  return { action: 'stop', reply: `>> 在线 ${kicked} 人已踢下线，正在停止服务端…` };
}

function cmdStatus() {
  const stats = store.dataStats();
  return {
    action: 'none',
    reply: `>> 在线连接 ${liveSessionCount()} 个；存档：${stats.accounts} 个账号 / ${stats.players} 个玩家档案。`,
  };
}

function cmdHelp() {
  return {
    action: 'none',
    reply: [
      '>> 可用指令（输入后回车）：',
      '>>   restore  清空本地存档（发布干净正式版用，在线玩家会被踢下线）',
      '>>   load     从磁盘重新加载存档（把备份拷回 server\\data\\ 后热加载）',
      '>>   stop     踢掉所有在线玩家并停止服务端',
      '>>   status   查看在线人数与存档数量',
      '>>   help     显示本帮助',
    ].join('\n'),
  };
}

// 解析一行输入。独立导出以便单测（测试里不会有真的进程退出）。
async function handleCommand(raw) {
  const cmd = String(raw ?? '').trim().toLowerCase();
  if (!cmd) return { action: 'none', reply: '' };
  switch (cmd.split(/\s+/)[0]) {
    case 'restore': return cmdRestore();
    case 'load': return cmdLoad();
    case 'stop': return cmdStop();
    case 'status': return cmdStatus();
    case 'help': case '?': case '？': return cmdHelp();
    default:
      return { action: 'none', reply: `>> 未知指令 "${cmd}"。可用：restore / load / stop / status / help` };
  }
}

function startConsole({ onStop }) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    prompt: '',
  });
  rl.on('line', (line) => {
    handleCommand(line)
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
  console.log('>> 控制台指令就绪：restore=清空存档  load=重载存档  stop=停服  status=状态  help=帮助');
  return rl;
}

module.exports = { handleCommand, startConsole };
