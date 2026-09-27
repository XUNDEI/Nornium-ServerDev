// Nornium (GHS) private server entry: HTTP gate 9089 + TCP game server 8101.
const net = require('net');
const log = require('./src/logger');
const protos = require('./src/protos');
const { attachServer, drainSessions } = require('./src/session');
const { createGate } = require('./src/httpgate');
const { dispatch } = require('./src/handlers');
const store = require('./src/store');
const { startConsole } = require('./src/console');
const { version } = require('./package.json');

const TCP_PORT = 8101;
const HTTP_PORT = 9089;
const HOST = '127.0.0.1';
const STARTED_AT = Date.now();

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
      await new Promise((resolve) => server.listen(TCP_PORT, HOST, resolve));
      log.info(`TCP game server listening on ${HOST}:${TCP_PORT}`);
    }
  }
}

async function main() {
  log.info(`Nornium ServerDev v${version}`);
  // 锁帧兜底（客户端设置界面的帧率选项不落盘，见 src/framefix.js 头部说明）。
  // 放在端口监听之前：失败（比如 Saved 目录只读）也不该挡住开服。
  try {
    log.info(`[framefix] ${require('./src/framefix').pinFrameLock()}`);
  } catch (err) {
    log.warn(`[framefix] 跳过：${err.message}`);
  }
  await protos.load();
  store.loadAccounts();
  log.info('protos loaded:', protos.allFieldNames().length, 'ghs.Msg fields');

  gateHandle = await createGate(HTTP_PORT, HOST, {
    maintenance: withMaintenance,
    // 编辑器的「停止服务端」按钮用它。onStop 只负责关进程；HTTP 响应由 editorapi
    // 先 res.end() 再延迟调用，保证页面能收到 {stopping:true}。
    onStop: shutdown,
    startedAt: STARTED_AT,
    tcpPort: TCP_PORT,
    httpPort: HTTP_PORT,
  }).catch((err) => { throw listenError(err, HTTP_PORT); });
  log.info(`HTTP gate listening on ${HOST}:${HTTP_PORT}`);
  log.info(`存档编辑器：http://${HOST}:${HTTP_PORT}/editor`);

  attachServer(server, dispatch);
  await new Promise((resolve, reject) => {
    const fail = (err) => reject(listenError(err, TCP_PORT));
    server.once('error', fail);
    server.listen(TCP_PORT, HOST, () => { server.off('error', fail); resolve(); });
  });
  log.info(`TCP game server listening on ${HOST}:${TCP_PORT}`);

  console.log('============================================================');
  console.log(' Nornium ServerDev 已启动（完全免费开源，付费买到即被骗）');
  console.log(' 游戏登录界面随便填账号密码，点「注册」即可进入主城。');
  console.log(` 存档编辑器（网页）：http://${HOST}:${HTTP_PORT}/editor  ← 也可在这里备份/踢人/清档/停服`);
  console.log(' 控制台指令：restore=清空存档  load[ 备份目录]=重载/导入存档  export[ 目录]=导出存档  allweapons[ 账号]=发高稀有度武器  addchar <账号> <角色id|all>=加角色  allskins[ 账号]=解锁全部皮肤  stop=停服  help=帮助');
  console.log('============================================================');

  startConsole({ onStop: shutdown, maintenance: withMaintenance });

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((err) => {
  log.error('fatal:', err.stack || err.message);
  console.log('>> 服务端启动失败：上面这段错误可以发给作者（或贴到 issue 里）。');
  process.exit(1);
});
