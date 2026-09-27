// Simple logger: console + logs/server.log. Set GHS_VERBOSE=1 for frame dumps.
//
// 除写文件外，最近 CAPACITY 行还会留在进程内的环形缓冲里（每行带单调递增的 seq），
// 供存档编辑器的「服务器控制台」页面实时展示：tail(after) 按游标拉历史，
// subscribe(fn) 订阅后续新行（SSE）。
//
// 捕获范围不止 log.info/warn/error：console.log/warn/error 也被包装进同一缓冲，
// 所以启动横幅、控制台指令回显这类裸 console 输出在网页上同样可见。
// write() 必须走 origConsole（绕过包装）并自己入队一次，否则会被双重捕获。
const fs = require('fs');
const path = require('path');

const logDir = path.join(__dirname, '..', 'logs');
try { fs.mkdirSync(logDir, { recursive: true }); } catch (_) { /* ignore */ }
const logFile = path.join(logDir, 'server.log');
const stream = fs.createWriteStream(logFile, { flags: 'a' });

// 环形缓冲：与网页端「客户端只保留最近 2000 行」同量级。
const CAPACITY = 2000;
const buffer = [];      // [{ seq, text }]，最旧的在前
let nextSeq = 1;
const subscribers = new Set();

function push(text) {
  const entry = { seq: nextSeq, text };
  nextSeq += 1;
  buffer.push(entry);
  if (buffer.length > CAPACITY) buffer.splice(0, buffer.length - CAPACITY);
  for (const fn of subscribers) {
    try { fn(entry); } catch (_) { /* 订阅者异常不影响日志本身 */ }
  }
}

// seq > after 的行（最多 limit 行；请求的历史太多时从最旧的一端丢弃，full=true 提示有缺口）。
function tail(after = 0, limit = 500) {
  const min = Number(after) || 0;
  let start = 0;
  while (start < buffer.length && buffer[start].seq <= min) start += 1;
  let full = false;
  if (buffer.length - start > limit) {
    start = buffer.length - limit;
    full = true;
  } else if (start < buffer.length && buffer[start].seq > min + 1) {
    full = true; // 游标指向的行已滚出环形缓冲
  }
  const lines = buffer.slice(start);
  return { lines, last: lines.length ? lines[lines.length - 1].seq : min, full };
}

function subscribe(fn) {
  subscribers.add(fn);
  return () => subscribers.delete(fn);
}

function ts() {
  return new Date().toISOString();
}

// 原始 console 引用：write 与包装器都经由它们输出，避免递归捕获。
const origConsole = {
  log: console.log.bind(console),
  warn: console.warn.bind(console),
  error: console.error.bind(console),
};

function write(level, args) {
  const line = args.map((a) => {
    if (a instanceof Buffer) return a.toString('hex');
    if (typeof a === 'object' && a !== null) {
      try { return JSON.stringify(a); } catch (_) { return String(a); }
    }
    return String(a);
  }).join(' ');
  const full = `${ts()} [${level}] ${line}`;
  push(full);
  stream.write(full + '\n');
  origConsole.log(full);
}

// 裸 console 输出也进缓冲（单条多参以空格拼接；多行文本保持原样，前端按行渲染）。
function wrapConsole(name) {
  console[name] = (...args) => {
    const line = args.map((a) => {
      if (typeof a === 'string') return a;
      if (a instanceof Error) return a.stack || a.message;
      if (typeof a === 'object' && a !== null) {
        try { return JSON.stringify(a); } catch (_) { return String(a); }
      }
      return String(a);
    }).join(' ');
    push(line);
    origConsole[name](...args);
  };
}
wrapConsole('log');
wrapConsole('warn');
wrapConsole('error');

module.exports = {
  info: (...a) => write('I', a),
  warn: (...a) => write('W', a),
  error: (...a) => write('E', a),
  verbose: (...a) => { if (process.env.GHS_VERBOSE) write('V', a); },
  tail,
  subscribe,
  capacity: CAPACITY,
};
