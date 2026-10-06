// In-process checks for the "make the console say something meaningful" pass.
//
// Why this exists: a real server.log from this machine was 326 KB / 4475 lines,
// and the top entries were
//
//     [I] [recv] req_ping                          440
//     [I] [recv] req_universe                      316
//     [I] [http] POST /client/marquee/list (2B)    283
//     [I] [conn] accepted 127.0.0.1, session key sent   76
//
// i.e. the client's heartbeat, its polling and the connection churn crowded
// everything a human actually wants to read (logins, editor ops, universe runs)
// out of the window. The fix keeps the information but changes the shape:
//
//   * per-message names ([recv] …) and the HTTP access log go to log.verbose,
//     i.e. they only appear with GHS_VERBOSE=1;
//   * connection open/close likewise;
//   * every 5 minutes src/activity.js prints ONE summary line instead;
//   * a window with no traffic prints nothing at all (an idle server is quiet);
//   * the one thing a human must keep seeing — the wizard's "第 1 步 / 第 2 步"
//     banners and the project homepage — is asserted in setup_check.js.
//
// No server needed: everything here is an in-process module.
const fs = require('fs');
const path = require('path');
const log = require('../src/logger');
const activity = require('../src/activity');
const { dispatch } = require('../src/handlers');

let failures = 0;
function check(cond, msg) {
  console.log(cond ? `  PASS ${msg}` : `  FAIL ${msg}`);
  if (!cond) failures += 1;
}

const SERVER_DIR = path.join(__dirname, '..');
const src = (rel) => fs.readFileSync(path.join(SERVER_DIR, rel), 'utf8');

// ---------------------------------------------------------------- summary line
{
  activity.reset();
  check(activity.summarize(3) === '',
    'a window with no traffic says nothing at all (an idle server is quiet)');
  check(activity.SUMMARY_INTERVAL_MS === 5 * 60 * 1000,
    `the summary window is 5 minutes (${activity.SUMMARY_INTERVAL_MS} ms)`);
  check(activity.SYNC_CMDS.has('req_bag') && activity.SYNC_CMDS.has('req_universe')
    && !activity.SYNC_CMDS.has('req_ping') && !activity.SYNC_CMDS.has('req_character_level_up'),
    'the sync bucket covers the login-sync list but not the heartbeat or real actions');
}

// ---------------------------------------------------------------- counters
{
  activity.reset();
  activity.noteRecv('req_ping');
  activity.noteRecv('req_ping');
  activity.noteRecv('req_ping');
  activity.noteRecv('req_bag');            // initial sync
  activity.noteRecv('req_universe');       // initial sync
  activity.noteRecv('req_character_level_up'); // a real action, not a sync
  activity.noteConn(true);
  activity.noteConn(false);
  activity.noteRecv('');                   // empty name counts for nothing
  const t = activity.total();
  check(t === 6, `total() counts only real inbound messages (${t})`);

  const line = activity.summarize(2, 5);
  console.log(`  info: ${line}`);
  check(/^\[activity\] 近 5 分钟：/.test(line), 'the summary line is prefixed and names the window');
  check(/心跳 3 次/.test(line), 'it counts heartbeats');
  check(/状态同步 2 次/.test(line), 'it counts login state syncs');
  check(/其他请求 1 次/.test(line), 'it counts everything else');
  check(/连接 \+1\/-1/.test(line), 'it counts connection open/close');
  check(/在线 2 人$/.test(line), 'it always ends with the online count');

  const flushed = activity.flush(2, 5);
  check(flushed === line, 'flush() returns the very line it logged');
  check(activity.total() === 0 && activity.summarize(2) === '',
    'flush() resets the window (the next summary starts from zero)');
}

// ---------------------------------------------------------------- zero segments
{
  activity.reset();
  activity.noteRecv('req_ping');
  const line = activity.summarize(0, 5);
  console.log(`  info: ${line}`);
  check(/心跳 1 次/.test(line) && !/状态同步/.test(line) && !/其他请求/.test(line)
    && !/连接/.test(line),
    'segments that are zero are omitted instead of printed as "0 次"');
  activity.reset();
}

// ---------------------------------------------------------------- the timer
{
  const stop = activity.start({ intervalMs: 60 * 60 * 1000, onlineCount: () => 0 });
  check(typeof stop === 'function', 'activity.start() hands back a stop function');
  stop();
  stop(); // 幂等：重复停不该抛
  check(true, 'stopping the summary timer twice does not throw');
  activity.reset();
}

// ---------------------------------------------------------------- logger levels
{
  // 逐条请求名必须走 verbose。dispatch 是异步的，但它记日志发生在 await 之前，
  // 所以这里同步断言即可（handler 本身只调 session.send）。
  const before = log.tail(0).lines.length;
  dispatch({ send() {} }, 'req_ping', {}).catch(() => {});
  const lines = log.tail(0).lines.slice(before).map((l) => l.text);
  check(!lines.some((t) => t.includes('[recv] req_ping')),
    `dispatching req_ping adds no [recv] line to the log (added ${lines.length})`);
  check(activity.total() === 1,
    'the same dispatch still bumps the heartbeat counter (it is not simply dropped)');

  const n0 = log.tail(0).lines.length;
  log.verbose('[recv] this-is-verbose-only');
  if (process.env.GHS_VERBOSE) {
    console.log('  (GHS_VERBOSE is set; verbose lines are expected to be visible)');
  } else {
    check(log.tail(0).lines.length === n0,
      'log.verbose stays out of the log unless GHS_VERBOSE=1');
  }

  // 控制台/编辑器的 reply 走裸 console.log（没有 [级别] 前缀）——前端把它当 log-i，
  // 所以它必须照旧进缓冲，不能被这次降噪顺手弄丢。
  console.log('>> 裸输出仍然要进环形缓冲');
  check(log.tail(0).lines.some((l) => l.text === '>> 裸输出仍然要进环形缓冲'),
    'a bare console.log (console replies, editor notices) still reaches the ring buffer');
  check(typeof log.capacity === 'number' && log.capacity === 2000,
    `the ring buffer still holds 2000 lines (${log.capacity})`);
  activity.reset();
}

// ---------------------------------------------------------------- source wiring
{
  const handlers = src('src/handlers/index.js');
  check(/log\.verbose\(`\[recv\] \$\{name\}`\)/.test(handlers),
    'handlers/index.js logs the per-message name via log.verbose');
  check(!/log\.info\(`\[recv\]/.test(handlers),
    'no log.info([recv] …) is left in handlers/index.js');
  check(/activity\.noteRecv\(name\)/.test(handlers),
    'handlers/index.js feeds every inbound message to the activity counters');

  const gate = src('src/httpgate.js');
  check(/log\.verbose\(`\[http\]/.test(gate), 'httpgate.js logs the HTTP access line via log.verbose');
  check(!/log\.info\(`\[http\]/.test(gate), 'no log.info([http] …) is left in httpgate.js');

  const session = src('src/session.js');
  check(/activity\.noteConn\(true\)/.test(session) && /activity\.noteConn\(false\)/.test(session),
    'session.js feeds connection open/close to the activity counters');
  check(/log\.verbose\(`\[conn\] accepted/.test(session) && /log\.verbose\('\[conn\] closed'\)/.test(session),
    'connection open/close lines are verbose now');

  const index = src('index.js');
  check(/activity\.start\(/.test(index), 'index.js starts the periodic summary');
  check(/activity\.flush\(/.test(index),
    'index.js flushes the last window on shutdown (so the final counts are not lost)');
  check(!/log\.info\('protos loaded/.test(index),
    'the "protos loaded" line is no longer info (it repeats on every restart)');

  // --check/--doctor 是显式命令，不受输出档位影响
  const setup = src('setup.js');
  check(/if \(CHECK\)/.test(setup) && /collectDoctorReport\(\)/.test(setup),
    'node setup.js --check still runs the full doctor report');
}

console.log(failures === 0 ? '\nLOG CHECKS PASSED' : `\n${failures} LOG CHECKS FAILED`);
process.exit(failures === 0 ? 0 : 1);
