// Nornium (GHS) private server entry: HTTP gate 9089 + TCP game server 8101.
const net = require('net');
const fs = require('fs');
const path = require('path');
const log = require('./src/logger');
const activity = require('./src/activity');
const protos = require('./src/protos');
const { attachServer, drainSessions, liveSessionCount } = require('./src/session');
const { createGate } = require('./src/httpgate');
const { dispatch } = require('./src/handlers');
const store = require('./src/store');
const { startConsole } = require('./src/console');
const { version, homepage } = require('./package.json');

// 默认端口可用环境变量覆盖（测试注入不冲突的端口；正常启动不设就是 8101/9089）。
function intEnv(name, fallback) {
  const n = Math.trunc(Number(process.env[name]));
  return Number.isFinite(n) && n > 0 ? n : fallback;
}
const TCP_PORT = intEnv('GHS_TCP_PORT', 8101);
const HTTP_PORT = intEnv('GHS_HTTP_PORT', 9089);
const HOST = '127.0.0.1';
const STARTED_AT = Date.now();

// 端口被占时的随机兜底范围。避开 Windows 默认动态端口段（49152 起），减少撞车；
// 上下限可用 GHS_PORT_FLOOR / GHS_PORT_CEIL 注入（测试用它把范围缩小到可全部占满）。
const PORT_FLOOR = Math.min(intEnv('GHS_PORT_FLOOR', 20000), 65535);
const PORT_CEIL = Math.max(intEnv('GHS_PORT_CEIL', 45000), PORT_FLOOR);
const MAX_PORT_ATTEMPTS = 20; // 换端口重试上限，全失败就退出

let tcpPort = TCP_PORT; // 实际监听端口（可能因占用而变动），维护窗口重听 / channel.lua 同步都用它
let httpPort = HTTP_PORT;
let gateHandle = null; // createGate() 的返回值，stop 指令 / SIGINT 关它
let shuttingDown = false;
let inMaintenance = false;

// stop 指令 / Ctrl+C / SIGTERM 共用的优雅退出。
// 收尾这句由这里打印而不是启动器（点我启动.bat 现在是纯 ASCII，见 REVERSE_ENGINEERING 坑 36）。
function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  log.info('shutting down');
  try {
    if (gateHandle) gateHandle.close();
  } catch (_) { /* already closed */ }
  try {
    server.close();
  } catch (_) { /* ignore */ }
  activity.flush(liveSessionCount()); // 最后一窗的汇总别丢
  console.log('');
  console.log('>> 服务端已停止。');
  process.exit(0);
}

const server = net.createServer();

// listen 失败时翻译成人话。Windows 上端口可能被 winnat（Hyper-V/WSL）的动态保留段
// 整段划走，症状是 EACCES：没有任何进程占用、重启电脑也不解决。8089 就这样没的。
function listenError(err, port) {
  if (err && err.code === 'EADDRINUSE') {
    return new Error(`端口 ${port} 已被其他程序占用：用 netstat -ano | findstr :${port} 找到占用进程`, { cause: err });
  }
  if (err && err.code === 'EACCES') {
    return new Error(`端口 ${port} 被 Windows 拒绝监听（EACCES）。多半是 winnat/Hyper-V/WSL 把它所在的`
      + '整段端口保留了：用 netsh interface ipv4 show excludedportrange protocol=tcp 查保留范围，'
      + '换一个范围外的端口即可（见 README「配置说明」）', { cause: err });
  }
  return err;
}

// 从兜底范围里挑一个没试过的随机端口。exclude 既当黑名单也当「已试集合」。
function randomPort(exclude) {
  for (;;) {
    const p = PORT_FLOOR + Math.floor(Math.random() * (PORT_CEIL - PORT_FLOOR + 1));
    if (!exclude.has(p)) {
      exclude.add(p);
      return p;
    }
  }
}

// 端口监听的统一入口：被占（EADDRINUSE）或被 winnat 保留段拒绝（EACCES，症状等同占用，
// 见上方 listenError 注释）时换随机端口重试，共 MAX_PORT_ATTEMPTS 次，仍失败就把
// listenError 翻译过的人话抛回 main 退出。其他错误不重试，直接抛。
// tryListen(port) -> Promise<句柄>；返回实际绑定的 port 与句柄。
async function listenWithRetry(tryListen, initialPort, label, exclude) {
  let port = initialPort;
  for (let attempt = 1; ; attempt++) {
    try {
      const handle = await tryListen(port);
      return { port, handle };
    } catch (err) {
      const retryable = err.code === 'EADDRINUSE' || err.code === 'EACCES';
      if (!retryable || attempt >= MAX_PORT_ATTEMPTS) throw listenError(err, port);
      log.warn(`[port] ${label}端口 ${port} 监听失败（${err.code}），换随机端口重试（第 ${attempt}/${MAX_PORT_ATTEMPTS} 次）`);
      port = randomPort(exclude);
    }
  }
}

// 客户端 Saved 目录（channel.lua 就在那里）。测试注入口 GHS_SAVED_DIR 优先；
// runtime-config.json 的 saved_dir 由 setup.js 写入（向导里定位过的那个 Saved 目录），
// 没有就退回 %LOCALAPPDATA% 的标准位置。
function savedDir() {
  if (process.env.GHS_SAVED_DIR) return process.env.GHS_SAVED_DIR;
  try {
    const cfg = JSON.parse(fs.readFileSync(path.join(__dirname, 'runtime-config.json'), 'utf8'));
    if (cfg.saved_dir) return cfg.saved_dir;
  } catch (_) { /* 没有配置文件时走默认 */ }
  const appData = process.env.LOCALAPPDATA;
  return appData ? path.join(appData, 'Nornium', 'Saved') : null;
}

// 端口偏离默认值时把客户端的 channel.lua 同步成实际端口——游戏是从这个文件读
// TCP 端口和 HTTP 门端口的（REVERSE_ENGINEERING.md 3.1），不改回去就连不上了。
// 渠道名保留文件里已有的（正常都是 local_dev，别因为换端口把渠道改掉）。
function syncClientChannel() {
  const dir = savedDir();
  if (!dir) {
    log.warn('[port] 无法定位客户端 Saved 目录，channel.lua 未同步：游戏将仍连默认端口');
    return;
  }
  const file = path.join(dir, 'channel.lua');
  let channel = 'local_dev';
  try {
    const m = fs.readFileSync(file, 'utf8').match(/return\s*\{\s*"([^"]+)"/);
    if (m) channel = m[1];
  } catch (_) { /* 文件不存在就按默认渠道写 */ }
  try {
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(file, `return {"${channel}", ${tcpPort}, "127.0.0.1", "${httpPort}"}\n`, 'utf8');
    log.info(`[port] 已把客户端 channel.lua 同步为 TCP ${tcpPort} / HTTP ${httpPort}（${file}）。`
      + '如果游戏已经开着，需要重启游戏才会读到新端口');
  } catch (err) {
    log.warn(`[port] channel.lua 写入失败：${err.message}。游戏将仍连默认端口`);
  }
}

// 维护窗口：控制台要改磁盘上的存档（restore / load）时用它包住整个动作。
//
//   停止 accept（server.close 立刻摘掉监听套接字）→ 硬排空在线会话 →
//   执行 fn → 重新 listen
//
// 为什么要这么重：改档前后只要还有任何一个会话活着，它的 savePlayer 就会把内存里
// 的旧 doc 整份写回磁盘，把刚恢复的档覆盖掉（handlers/index.js 的 dailyTick 是
// 60s 定时器，同样会 savePlayer）。所以既不接受"睡 300ms 就动文件"，
// 也不接受"新连接在换档过程中登进来"。
// HTTP 门（9089）不碰存档，维持可用，避免客户端在换档期间弹网络错误。
async function withMaintenance(fn) {
  if (inMaintenance) throw new Error('已有一个维护窗口在进行中，请等它结束再试');
  inMaintenance = true;
  const paused = server.listening;
  let closed = null;
  try {
    if (paused) closed = new Promise((resolve) => server.close(() => resolve()));
    const drain = await drainSessions();
    if (drain.remaining > 0) {
      throw new Error(`仍有 ${drain.remaining} 个连接没能断开；`
        + '为免旧会话回写存档，本次操作已取消，请稍后重试或直接 stop 停服');
    }
    if (closed) await closed; // 等监听套接字真正关闭，换档期间不会有新会话进来
    log.info('[maint] 维护窗口：已停止接入，在线会话已全部断开');
    return await fn(drain);
  } finally {
    inMaintenance = false;
    if (paused && !server.listening) {
      await new Promise((resolve) => server.listen(tcpPort, HOST, resolve));
      log.info(`TCP game server listening on ${HOST}:${tcpPort}`);
    }
  }
}

async function main() {
  log.info(`Nornium ServerDev v${version}`);
  await protos.load();
  store.loadAccounts();
  log.verbose('protos loaded:', protos.allFieldNames().length, 'ghs.Msg fields');

  // 先起 TCP 再起 HTTP 门：编辑器状态页要显示两个实际端口，TCP 先落定才能一次传对。
  attachServer(server, dispatch);
  const usedPorts = new Set([TCP_PORT, HTTP_PORT]);
  const tcp = await listenWithRetry(
    (port) => new Promise((resolve, reject) => {
      const fail = (err) => reject(err);
      server.once('error', fail);
      server.listen(port, HOST, () => { server.off('error', fail); resolve(true); });
    }),
    TCP_PORT, 'TCP 游戏服务', usedPorts,
  );
  tcpPort = tcp.port;
  log.info(`TCP game server listening on ${HOST}:${tcpPort}`);

  const gate = await listenWithRetry(
    (port) => createGate(port, HOST, {
      maintenance: withMaintenance,
      // 编辑器的「停止服务端」按钮用它。onStop 只负责关进程；HTTP 响应由 editorapi
      // 先 res.end() 再延迟调用，保证页面能收到 {stopping:true}。
      onStop: shutdown,
      startedAt: STARTED_AT,
      tcpPort,
      httpPort: port,
    }),
    HTTP_PORT, 'HTTP 登录门', usedPorts,
  );
  httpPort = gate.port;
  gateHandle = gate.handle;
  log.info(`HTTP gate listening on ${HOST}:${httpPort}`);
  log.info(`存档编辑器：http://${HOST}:${httpPort}/editor`);

  if (tcpPort !== TCP_PORT || httpPort !== HTTP_PORT) {
    log.warn(`默认端口被占用，已改用其他端口：TCP ${TCP_PORT}→${tcpPort}，HTTP ${HTTP_PORT}→${httpPort}`);
    syncClientChannel();
  }

  // 启动横幅：只留「怎么用 + 去哪看代码」，细节交给 help / README（以前 6 行里
  // 有一整行指令清单，每次开服都在刷同一段）。REPO_URL 来自 package.json.homepage，
  // 全项目单一来源。
  const REPO_URL = homepage || 'https://github.com/XUNDEI/Nornium-ServerDev';
  console.log('============================================================');
  console.log(` Nornium ServerDev v${version} · 失乐星图本地私服（完全免费开源）`);
  console.log(` 网页编辑器 http://${HOST}:${httpPort}/editor    项目主页 ${REPO_URL}`);
  console.log(' 控制台：help=帮助 stop=停服 ｜ 游戏登录界面随便填账号密码，点「注册」进主城');
  console.log('============================================================');

  // 每 5 分钟把心跳/同步/连接流水汇总成一行（零流量则完全不出声）。
  activity.start({ onlineCount: liveSessionCount });

  startConsole({ onStop: shutdown, maintenance: withMaintenance });

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((err) => {
  log.error('fatal:', err.stack || err.message);
  console.log('>> 服务端启动失败：上面这段错误可以发给作者（或贴到 issue 里）。');
  process.exit(1);
});
