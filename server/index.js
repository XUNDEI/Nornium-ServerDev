// Nornium (GHS) private server entry: HTTP gate 8089 + TCP game server 8101.
const net = require('net');
const log = require('./src/logger');
const protos = require('./src/protos');
const { attachServer } = require('./src/session');
const { createGate } = require('./src/httpgate');
const { dispatch } = require('./src/handlers');
const store = require('./src/store');
const { startConsole } = require('./src/console');
const { version } = require('./package.json');

const TCP_PORT = 8101;
const HTTP_PORT = 8089;
const HOST = '127.0.0.1';

let gateHandle = null; // createGate() 的返回值，stop 指令 / SIGINT 关它
let shuttingDown = false;

// stop 指令 / Ctrl+C / SIGTERM 共用的优雅退出
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
  process.exit(0);
}

const server = net.createServer();

async function main() {
  log.info(`Nornium ServerDev v${version}`);
  await protos.load();
  store.loadAccounts();
  log.info('protos loaded:', protos.allFieldNames().length, 'ghs.Msg fields');

  gateHandle = await createGate(HTTP_PORT, HOST);
  log.info(`HTTP gate listening on ${HOST}:${HTTP_PORT}`);

  attachServer(server, dispatch);
  await new Promise((resolve) => server.listen(TCP_PORT, HOST, resolve));
  log.info(`TCP game server listening on ${HOST}:${TCP_PORT}`);

  console.log('============================================================');
  console.log(' Nornium ServerDev 已启动（完全免费开源，付费买到即被骗）');
  console.log(' 游戏登录界面随便填账号密码，点「注册」即可进入主城。');
  console.log(' 控制台指令：restore=清空存档  load=重载存档  stop=停服  help=帮助');
  console.log('============================================================');

  startConsole({ onStop: shutdown });

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((err) => {
  log.error('fatal:', err.stack || err.message);
  process.exit(1);
});
