// Per-connection protocol session: framing, DES crypt, FIFO request processing.
//
// Client -> server frame: [4B size BE][2B cmd][2B c_no][2B s_no][body]
//   size = 10 + len(body) (includes the size field itself)
// Server -> client frame: [4B size BE][2B result][2B cmd][2B c_no][2B s_no][body]
//   size = 12 + len(body); result 0 = OK
// Plain (never encrypted) cmds: req_ping, res_ping, ntf_server_time, ntf_msg_key.
const net = require('net');
const log = require('./logger');
const crypt = require('./crypt');
const protos = require('./protos');

const NO_CRYPT = new Set(['req_ping', 'res_ping', 'ntf_server_time', 'ntf_msg_key']);

class Session {
  constructor(socket, dispatch) {
    this.socket = socket;
    this.dispatch = dispatch; // async (session, name, msg) => void
    this.sessionKey = null;   // 8 ASCII bytes
    this.sno = 0;             // server sequence number
    this.curCno = 0;          // c_no of the request currently being answered (echo)
    this.account = null;      // accounts.json record
    this.player = null;       // player doc (data/players/<id>.json)
    this.closed = false;
    this.buf = Buffer.alloc(0);
    this.queue = [];          // decoded inbound frames awaiting sequential handling
    this.processing = false;
    this.bindTime = Date.now();
  }

  start() {
    // 1. Handshake: immediately after accept, send ntf_msg_key carrying the
    // session key DES-encrypted under the fixed initial key "kueisoon".
    // msg_key is a `bytes` field in gate.proto: the 16-byte DES ciphertext
    // passes through protobuf as raw bytes (a string field would get UTF-8
    // encoded and corrupt every byte > 0x7F — the real client's lua-protobuf
    // reads string fields as raw bytes and its desdecode then fails).
    this.sessionKey = crypt.generateSessionKey();
    const msgKey = crypt.encrypt(crypt.INITIAL_KEY, this.sessionKey);
    this.sendRaw('ntf_msg_key', { msg_key: msgKey });
    log.info(`[conn] accepted ${this.socket.remoteAddress}, session key sent`);

    this.socket.on('data', (chunk) => this.onData(chunk));
    this.socket.on('error', (err) => log.warn('[conn] socket error:', err.message));
    this.socket.on('close', () => this.onClose());
  }

  onClose() {
    this.closed = true;
    if (this.onCloseHook) this.onCloseHook();
    log.info('[conn] closed');
  }

  close() {
    if (!this.closed) this.socket.destroy();
  }

  kick(reason) {
    try {
      this.send('ntf_kick', { reason });
    } catch (_) { /* ignore */ }
    setTimeout(() => this.close(), 100);
  }

  onData(chunk) {
    this.buf = Buffer.concat([this.buf, chunk]);
    while (true) {
      if (this.buf.length < 4) return;
      const size = this.buf.readUInt32BE(0);
      if (size < 10 || size > 4 * 1024 * 1024) {
        log.error('[conn] insane frame size', size, '- closing');
        this.close();
        return;
      }
      if (this.buf.length < size) return;
      const frame = this.buf.subarray(0, size);
      this.buf = this.buf.subarray(size);
      let parsed = null;
      try {
        parsed = this.parseClientFrame(frame);
      } catch (err) {
        log.error('[conn] frame parse failed:', err.message, frame.toString('hex').slice(0, 80));
        this.close();
        return;
      }
      if (parsed) this.queue.push(parsed);
    }
  }

  parseClientFrame(frame) {
    const cmdNumber = frame.readUInt16BE(4);
    const cNo = frame.readUInt16BE(6);
    const sNo = frame.readUInt16BE(8);
    const body = frame.subarray(10);
    const name = protos.fieldName(cmdNumber);
    if (!name) {
      log.warn(`[conn] unknown cmd number ${cmdNumber}`);
      return null;
    }
    let msg = null;
    if (body.length > 0) {
      let plain = body;
      if (!NO_CRYPT.has(name)) {
        if (!this.sessionKey) throw new Error(`encrypted msg ${name} before key setup`);
        plain = crypt.decrypt(this.sessionKey, body);
      }
      msg = protos.decodeMsg(plain).msg;
    }
    return { name, cNo, sNo, msg };
  }

  // Sequential FIFO processing: the client matches responses to its
  // send_caches[1] strictly in order, so responses must keep request order.
  pump() {
    if (this.processing || this.closed) return;
    const item = this.queue.shift();
    if (!item) return;
    this.processing = true;
    this.curCno = item.cNo;
    Promise.resolve()
      .then(() => this.dispatch(this, item.name, item.msg))
      .catch((err) => {
        log.error(`[dispatch] error handling ${item.name}:`, err.stack || err.message);
      })
      .then(() => {
        this.processing = false;
        if (!this.closed) this.pump();
      });
  }

  // Send a response/notify. result only matters for res_* (frame header field).
  send(name, payload, result = 0) {
    const cNo = result === 0 && name.startsWith('res_') ? this.curCno : 0;
    return this.sendRaw(name, payload, result, cNo);
  }

  sendRaw(name, payload, result = 0, cNo = 0) {
    if (this.closed) return;
    const body = protos.encodeMsg(name, payload || {});
    const cryptBody = !NO_CRYPT.has(name) && this.sessionKey;
    const enc = cryptBody ? crypt.encrypt(this.sessionKey, body) : body;
    this.sno = (this.sno + 1) & 0xffff;
    const head = Buffer.alloc(12);
    head.writeUInt32BE(12 + enc.length, 0);
    head.writeUInt16BE(result, 4);
    head.writeUInt16BE(protos.fieldNumber(name), 6);
    head.writeUInt16BE(cNo & 0xffff, 8);
    head.writeUInt16BE(this.sno, 10);
    this.socket.write(Buffer.concat([head, enc]));
    log.verbose(`->send ${name} (${enc.length}B body)`);
  }
}

// 全部还活着的连接（含未登录的），控制台 restore/load/stop 踢人用
const liveSessions = new Set();

// attachServer 与单测共同使用：把一条连接纳入踢人管理的名册
function trackSession(session) {
  liveSessions.add(session);
}

function attachServer(server, dispatch) {
  server.on('connection', (socket) => {
    const session = new Session(socket, dispatch);
    trackSession(session);
    session.start();
    session.pumpInterval = setInterval(() => session.pump(), 5);
    // periodic plaintext server time sync (matches client's ntf_server_time)
    session.timeInterval = setInterval(() => {
      if (!session.closed) {
        session.sendRaw('ntf_server_time', { server_seconds: String(Math.floor(Date.now() / 1000)) });
        // 跨过 04:00 边界时补发每日危航许可等"到点发放"的内容（幂等，无变化时不发包）
        try {
          require('./handlers').dailyTick(session);
        } catch (err) {
          log.error('[tick]', err.stack || err.message);
        }
      }
    }, 60_000);
    session.onCloseHook = () => {
      liveSessions.delete(session);
      clearInterval(session.pumpInterval);
      clearInterval(session.timeInterval);
    };
    // ntf arrive asynchronously (timers etc.) — pump() is a no-op when idle,
    // sends are safe anytime; inbound processing stays FIFO via the queue.
  });
}

// 踢掉所有在线连接（reason=1 REPLACE，客户端会弹"账号在其他地方登录"并回登录界面）。
// 返回踢掉的数量。踢是异步的（kick 后 100ms 才断 socket）——调用方若要紧接着
// 改存档（console.js 的 restore/load），应再等一小段延时，避免残余会话回写。
function kickAllSessions(reason = 1) {
  let kicked = 0;
  for (const s of [...liveSessions]) {
    if (s.closed) {
      liveSessions.delete(s);
      continue;
    }
    s.kick(reason);
    kicked += 1;
  }
  return kicked;
}

function liveSessionCount() {
  let n = 0;
  for (const s of liveSessions) if (!s.closed) n += 1;
  return n;
}

module.exports = { Session, attachServer, trackSession, kickAllSessions, liveSessionCount };
