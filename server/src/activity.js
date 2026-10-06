// 「有意义的消息」汇总器：把高频的收发/连接流水换成周期性的一行。
//
// 为什么需要它：客户端的心跳（req_ping）和登录/重连后的批量状态同步会以每分钟
// 数百条的频率刷屏（实测 server.log 4475 行里 req_ping 440 条、req_universe 316 条）。
// 逐条 [recv] 明细已经降级成 verbose（GHS_VERBOSE=1 才输出），这里负责把它们
// 每 5 分钟汇总成一行——既保住可观测性，又不会让控制台变成心跳日志。
//
// 只做计数，不做 IO：dispatch() 调 noteRecv、session.js 调 noteConn、
// index.js 调 start()/flush()。窗口内零计数就完全不输出（空闲不刷屏）。
const log = require('./logger');

// handlers/index.js 里「initial sync」一节：登录/重连后客户端主动拉取的只读状态。
// 这些没有自己的语义日志，全归到「状态同步」一桶。
const SYNC_CMDS = new Set([
  'req_player', 'req_bag', 'req_home', 'req_universe', 'req_total_war',
  'req_shop_list', 'req_mall_list', 'req_hard_level', 'req_character_list',
  'req_plot', 'req_activity_list', 'req_gacha', 'req_mail_list',
]);

const SUMMARY_INTERVAL_MS = 5 * 60 * 1000;

let counters = blank();
let timer = null;

function blank() {
  return { ping: 0, sync: 0, other: 0, connOpen: 0, connClose: 0 };
}

// 每条入站消息记一次。req_ping 是纯心跳，单独一桶。
function noteRecv(name) {
  if (!name) return;
  if (name === 'req_ping') counters.ping += 1;
  else if (SYNC_CMDS.has(name)) counters.sync += 1;
  else counters.other += 1;
}

function noteConn(open) {
  if (open) counters.connOpen += 1;
  else counters.connClose += 1;
}

function total() {
  return counters.ping + counters.sync + counters.other;
}

// 一行中文；窗口内一个请求都没有就返回空串（调用方据此保持安静）。
function summarize(onlineCount = 0, windowMinutes = Math.round(SUMMARY_INTERVAL_MS / 60000)) {
  const none = total() === 0 && counters.connOpen === 0 && counters.connClose === 0;
  if (none) return '';
  const parts = [];
  if (counters.ping) parts.push(`心跳 ${counters.ping} 次`);
  if (counters.sync) parts.push(`状态同步 ${counters.sync} 次`);
  if (counters.other) parts.push(`其他请求 ${counters.other} 次`);
  if (counters.connOpen || counters.connClose) parts.push(`连接 +${counters.connOpen}/-${counters.connClose}`);
  parts.push(`在线 ${onlineCount} 人`);
  return `[activity] 近 ${windowMinutes} 分钟：${parts.join(' · ')}`;
}

// 输出并清空窗口。返回打过的那行（没东西可打时返回空串），方便单测断言。
function flush(onlineCount = 0, windowMinutes) {
  const line = summarize(onlineCount, windowMinutes);
  counters = blank();
  if (line) log.info(line);
  return line;
}

// 每 intervalMs 汇总一次（默认 5 分钟）。unref()：不会让 setup.js / 单测因为
// 这个定时器而迟迟不退出。
function start({ intervalMs = SUMMARY_INTERVAL_MS, onlineCount = () => 0 } = {}) {
  if (timer) clearInterval(timer);
  const minutes = Math.max(1, Math.round(intervalMs / 60000));
  timer = setInterval(() => flush(onlineCount(), minutes), intervalMs);
  timer.unref();
  return () => {
    if (timer) clearInterval(timer);
    timer = null;
  };
}

function reset() {
  counters = blank();
}

module.exports = {
  noteRecv,
  noteConn,
  total,
  summarize,
  flush,
  start,
  reset,
  SYNC_CMDS,
  SUMMARY_INTERVAL_MS,
};
