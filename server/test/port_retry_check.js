// 端口占用兜底回归测试：默认端口被占时换随机端口重试、channel.lua 同步、
// 20 次重试全失败就退出（index.js 的 listenWithRetry / syncClientChannel）。
//
// 起两个真服务端（spawn node index.js），存档 / Saved 目录 / 随机端口范围全部
// 用环境变量注入临时目录，不碰真实 data\ 与客户端 channel.lua（坑 35 同规矩）。
//   - 场景 A：两个默认端口都被占 → 两个监听都挪到随机端口，且客户端 channel.lua
//     被同步成实际端口；连上 TCP 能立刻收到 ntf_msg_key（登录链路第一步）。
//   - 场景 B：把随机兜底范围用 GHS_PORT_FLOOR/CEIL 缩到 20 个端口并全部占满
//     → 服务端按上限放弃，进程以退出码 1 结束。
//
// 端口用 GHS_TCP_PORT/GHS_HTTP_PORT 注入非常用值：测试不该要求 8101/9089 空着
// （玩家很可能正开着真服务端）。
const net = require('net');
const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');
const { spawn } = require('child_process');

const SERVER_DIR = path.join(__dirname, '..');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ghs-port-'));
const SAVED_DIR = path.join(tmp, 'Nornium', 'Saved');
const TEST_TCP = 18101; // 注入给被测服务端的「默认端口」，刻意避开 8101/9089
const TEST_HTTP = 19089; // （玩家机器上真服务端可能正开着）

let failures = 0;
function check(cond, msg) {
  console.log(cond ? `  PASS ${msg}` : `  FAIL ${msg}`);
  if (!cond) failures += 1;
}
function section(name) { console.log(`\n== ${name} ==`); }

// 占住一个端口（模拟「被其他程序占用」），返回带 close() 的占位服务。
function occupy(port) {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.once('error', reject);
    srv.listen(port, '127.0.0.1', () => resolve(srv));
  });
}

function writeChannelLua(tcp, gm) {
  fs.mkdirSync(SAVED_DIR, { recursive: true });
  fs.writeFileSync(path.join(SAVED_DIR, 'channel.lua'), `return {"local_dev", ${tcp}, "127.0.0.1", "${gm}"}\n`, 'utf8');
}

function readChannelLua() {
  // 注意格式与 setup.js 一致：TCP 端口是数字，gm_port 是带引号的字符串
  const m = fs.readFileSync(path.join(SAVED_DIR, 'channel.lua'), 'utf8')
    .match(/return\s*\{\s*"([^"]*)"\s*,\s*(\d+)\s*,\s*"([^"]*)"\s*,\s*"(\d+)"/);
  return m ? { channel: m[1], tcp: Number(m[2]), host: m[3], gm: Number(m[4]) } : null;
}

// 起服务端并等 stdout 里出现两条 listening 日志，返回 { proc, tcpPort, httpPort, output }。
function startServer(extraEnv = {}, timeoutMs = 30000) {
  const proc = spawn('node', ['index.js'], {
    cwd: SERVER_DIR,
    env: {
      ...process.env,
      GHS_DATA_DIR: path.join(tmp, 'data'),
      GHS_SAVED_DIR: SAVED_DIR,
      GHS_TCP_PORT: String(TEST_TCP),
      GHS_HTTP_PORT: String(TEST_HTTP),
      LOCALAPPDATA: tmp, // 兜底：别让任何模块顺着真 LOCALAPPDATA 摸到真 Saved
      ...extraEnv,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let output = '';
  proc.stdout.on('data', (d) => { output += d; });
  proc.stderr.on('data', (d) => { output += d; });
  const waitListening = () => new Promise((resolve, reject) => {
    const started = Date.now();
    const timer = setInterval(() => {
      const tcp = output.match(/TCP game server listening on 127\.0\.0\.1:(\d+)/);
      const gate = output.match(/HTTP gate listening on 127\.0\.0\.1:(\d+)/);
      if (tcp && gate) {
        clearInterval(timer);
        resolve({ tcpPort: Number(tcp[1]), httpPort: Number(gate[1]) });
      } else if (Date.now() - started > timeoutMs) {
        clearInterval(timer);
        reject(new Error(`等待监听日志超时，输出：\n${output}`));
      }
    }, 100);
  });
  return { proc, output: () => output, waitListening };
}

function delay(ms) { return new Promise((r) => setTimeout(r, ms)); }

// TCP accept 后服务端立即下发 ntf_msg_key（明文），能收到即链路第一步通。
function expectMsgKey(port) {
  return new Promise((resolve, reject) => {
    const sock = net.connect(port, '127.0.0.1');
    const timer = setTimeout(() => { sock.destroy(); reject(new Error('5s 内没收到 ntf_msg_key')); }, 5000);
    sock.once('data', () => { clearTimeout(timer); sock.destroy(); resolve(); });
    sock.once('error', (e) => { clearTimeout(timer); reject(e); });
  });
}

function postStatus(port) {
  return new Promise((resolve, reject) => {
    const req = http.request({
      host: '127.0.0.1', port, path: '/client/system/serverStatus', method: 'POST', timeout: 5000,
    }, (res) => {
      let body = '';
      res.on('data', (c) => { body += c; });
      res.on('end', () => resolve(body));
    });
    req.on('error', reject);
    req.end();
  });
}

async function stopServer(proc) {
  if (proc.exitCode === null && proc.signalCode === null) proc.kill();
  await delay(300);
}

async function scenarioA() {
  section('场景 A：默认端口被占 → 挪随机端口 + channel.lua 同步');
  writeChannelLua(TEST_TCP, TEST_HTTP);
  const occTcp = await occupy(TEST_TCP);
  const occHttp = await occupy(TEST_HTTP);
  const srv = startServer();
  try {
    const { tcpPort, httpPort } = await srv.waitListening();
    check(tcpPort !== TEST_TCP, `TCP 挪到随机端口 ${tcpPort}（≠${TEST_TCP}）`);
    check(httpPort !== TEST_HTTP, `HTTP 挪到随机端口 ${httpPort}（≠${TEST_HTTP}）`);

    // channel.lua 的同步在两条 listening 日志之后才发生，轮询等它落盘。
    let ch = null;
    const deadline = Date.now() + 5000;
    while (Date.now() < deadline) {
      ch = readChannelLua();
      if (ch && ch.tcp === tcpPort && ch.gm === httpPort) break;
      await delay(100);
    }
    check(!!ch && ch.tcp === tcpPort && ch.gm === httpPort,
      `channel.lua 已同步为 TCP ${ch && ch.tcp} / HTTP ${ch && ch.gm}`);
    check(!!ch && ch.channel === 'local_dev', 'channel 渠道名保持 local_dev 不被换端口动作改掉');

    await expectMsgKey(tcpPort);
    check(true, `连接 TCP ${tcpPort} 立即收到 ntf_msg_key`);

    const body = await postStatus(httpPort);
    const ok = (() => { try { return JSON.parse(body).code === 0; } catch (_) { return false; } })();
    check(ok, `HTTP 门 ${httpPort} serverStatus 返回 code=0`);

    check(/已改用其他端口/.test(srv.output()), '日志给出端口变更摘要');
    check(/channel\.lua 同步/.test(srv.output()), '日志说明 channel.lua 已同步');
  } catch (err) {
    check(false, `异常：${err.message}`);
  } finally {
    await stopServer(srv.proc);
    occTcp.close();
    occHttp.close();
    await delay(200);
  }
}

async function scenarioB() {
  section('场景 B：20 次重试全失败 → 放弃并退出');
  // 兜底范围缩到恰好 20 个端口（GHS_PORT_FLOOR..CEIL），连同两个默认端口全部占满。
  const FLOOR = 39500;
  const CEIL = FLOOR + 20 - 1; // listenWithRetry 的上限就是 20 次
  const occupants = [];
  try {
    occupants.push(await occupy(TEST_TCP), await occupy(TEST_HTTP));
    for (let p = FLOOR; p <= CEIL; p++) occupants.push(await occupy(p));
  } catch (err) {
    check(false, `占位失败（本机端口被别的程序抢了？）：${err.message}`);
    occupants.forEach((o) => o.close());
    return;
  }
  const srv = startServer({ GHS_PORT_FLOOR: String(FLOOR), GHS_PORT_CEIL: String(CEIL) });
  const exited = new Promise((resolve) => srv.proc.once('exit', (code) => resolve(code)));
  try {
    const code = await Promise.race([
      exited,
      delay(30000).then(() => 'timeout'),
    ]);
    check(code === 1, `进程以退出码 1 终止（实际：${code}）`);
    check(/监听失败.*换随机端口重试/.test(srv.output()), '日志记录了重试过程');
    check(/端口 .* 已被其他程序占用|EACCES/.test(srv.output()), '最终错误是端口类失败的人话翻译');
  } finally {
    await stopServer(srv.proc);
    occupants.forEach((o) => o.close());
  }
}

(async () => {
  console.log('端口占用兜底测试（真服务端，临时目录隔离）');
  await scenarioA();
  await scenarioB();
  console.log(`\n${failures === 0 ? '全部通过' : `${failures} 项失败`}`);
  fs.rmSync(tmp, { recursive: true, force: true });
  process.exit(failures === 0 ? 0 : 1);
})();
