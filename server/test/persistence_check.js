// Persistence check: register + login + spend state, restart the server
// process, relogin and verify the data survived. Run with the server DOWN
// (this script manages the server process itself).
const { execSync, spawn } = require('child_process');
const path = require('path');
const net = require('net');
const protobuf = require('protobufjs');
const DES = require('des.js').DES;

const SERVER_DIR = path.join(__dirname, '..');
let failures = 0;
const check = (c, m) => { console.log(c ? '  PASS ' + m : '  FAIL ' + m); if (!c) failures++; };

function desEcb(key, data, type) {
  const des = new DES({ type, key: Array.from(key) });
  des.padding = false;
  const out = des.update(Array.from(data));
  return Buffer.from(type === 'decrypt' ? out.concat(des.final()) : out);
}
const padb = (d) => { const p = Buffer.alloc((d.length + 8) & ~7); d.copy(p); p[d.length] = 0x80; return p; };
const enc = (k, d) => desEcb(k, padb(d), 'encrypt');
const dec = (k, d) => { const o = desEcb(k, d, 'decrypt'); for (let i = o.length - 1; i >= o.length - 8; i--) { if (o[i] === 0x80) return o.subarray(0, i); if (o[i] !== 0) throw new Error('bad pad'); } throw new Error('no marker'); };

// 初始金星贝从新号发放表里取（player_new.initialBagGrants），别再硬编码——
// 上次 starter 金币从 50 万调到 120 万时这条断言就悄悄过期了。
const STARTER_GOLD = require('../src/game/player_new')
  .createPlayerDoc(0).bag.items.filter((i) => i.item_id === 9001)
  .reduce((s, i) => s + i.count, 0);

const root = new protobuf.Root();
let Msg;

class C {
  constructor() { this.buf = Buffer.alloc(0); this.waiters = []; }
  connect() {
    return new Promise((res, rej) => {
      this.sock = net.connect(8101, '127.0.0.1', res);
      this.sock.on('error', rej);
      this.sock.on('data', (c) => this.onData(c));
    });
  }
  onData(chunk) {
    this.buf = Buffer.concat([this.buf, chunk]);
    while (this.buf.length >= 4) {
      const size = this.buf.readUInt32BE(0);
      if (this.buf.length < size) return;
      const f = this.buf.subarray(0, size);
      this.buf = this.buf.subarray(size);
      const cmd = f.readUInt16BE(6);
      const field = Object.values(Msg.fields).find((x) => x.id === cmd);
      if (!field) continue;
      const body = f.subarray(12);
      let msg = {};
      if (body.length > 0) {
        const plain = ['req_ping', 'res_ping', 'ntf_server_time', 'ntf_msg_key'].includes(field.name)
          ? body : dec(this.key, body);
        msg = Msg.decode(plain)[field.name] ?? {};
      }
      const i = this.waiters.findIndex((w) => w.n === field.name);
      if (i >= 0) this.waiters.splice(i, 1)[0].r({ result: f.readUInt16BE(4), msg });
    }
  }
  wait(n) {
    return new Promise((res, rej) => {
      const t = setTimeout(() => rej(new Error('timeout ' + n)), 5000);
      this.waiters.push({ n, r: (v) => { clearTimeout(t); res(v); } });
    });
  }
  send(n, sub) {
    const f = Msg.fields[n];
    const p = {}; p[n] = sub || {};
    let body = Buffer.from(Msg.encode(Msg.create(p)).finish());
    if (!['req_ping', 'res_ping', 'ntf_server_time', 'ntf_msg_key'].includes(n)) body = enc(this.key, body);
    const h = Buffer.alloc(10);
    h.writeUInt32BE(10 + body.length, 0);
    h.writeUInt16BE(f.id, 4); h.writeUInt16BE(1, 6); h.writeUInt16BE(0, 8);
    this.sock.write(Buffer.concat([h, body]));
  }
}
const num = (v) => (v && typeof v === 'object' && v.toNumber) ? v.toNumber() : Number(v ?? 0);

async function session(acct, pass) {
  const c = new C();
  await c.connect();
  const k = await c.wait('ntf_msg_key');
  c.key = dec(Buffer.from('kueisoon'), Buffer.from(k.msg.msg_key, 'latin1'));
  c.send('req_login', { account_name: acct, password: pass });
  const r = await c.wait('res_login');
  if (r.result !== 0) throw new Error('login failed ' + r.result);
  return c;
}

function stopServer() {
  try {
    const out = execSync('netstat -ano').toString();
    for (const line of out.split('\n')) {
      if (line.includes(':8101') && line.includes('LISTENING')) {
        execSync(`taskkill /F /PID ${line.trim().split(/\s+/).pop()}`);
      }
    }
  } catch (_) { /* ignore */ }
}

async function main() {
  await root.load(path.join(SERVER_DIR, '..', 'reference', 'proto', 'msg.proto'), { keepCase: true });
  Msg = root.lookupType('ghs.Msg');

  const acct = `persist${Date.now() % 100000}`;
  stopServer();
  await new Promise((r) => setTimeout(r, 500));
  const srv1 = spawn('node', ['index.js'], { cwd: SERVER_DIR, stdio: 'ignore' });
  await new Promise((r) => setTimeout(r, 1500));

  const c0 = new C();
  await c0.connect();
  const k0 = await c0.wait('ntf_msg_key');
  c0.key = dec(Buffer.from('kueisoon'), Buffer.from(k0.msg.msg_key, 'latin1'));
  c0.send('req_register', { account_name: acct, password: 'pw' });
  check((await c0.wait('res_register')).result === 0, 'register');
  c0.sock.destroy();

  const c1 = await session(acct, 'pw');
  c1.send('req_shop_list');
  const shops = (await c1.wait('res_shop_list')).msg.shop_list_info.shop_infos;
  const shop = shops.find((s) => s.shop_item_infos.length > 0);
  c1.send('req_shop_buy', { shop_id: shop.shop_id, shop_item_id: shop.shop_item_infos[0].shop_item_id, shop_item_count: 1 });
  const buy = await c1.wait('res_shop_buy');
  check(buy.result === 0, 'shop buy before restart');
  const spent = shop.shop_item_infos[0] && 10000; // item 201 costs 10000 gold
  check(spent === 10000, 'known price assumption');
  // Let the server finish the handler's atomic save (write tmp + rename) before
  // killing it, otherwise the kill can land between the two and lose the write.
  await new Promise((r) => setTimeout(r, 400));
  c1.sock.destroy();
  srv1.kill();
  await new Promise((r) => setTimeout(r, 800));

  const srv2 = spawn('node', ['index.js'], { cwd: SERVER_DIR, stdio: 'ignore' });
  await new Promise((r) => setTimeout(r, 1500));
  const c2 = await session(acct, 'pw');
  check(true, 'relogin after server restart');
  c2.send('req_bag');
  let bagItems = [];
  const resBag = await new Promise((res, rej) => {
    const t = setTimeout(() => rej(new Error('no res_bag')), 5000);
    c2.waiters.push({ n: 'ntf_bag_info', r: (v) => { bagItems = bagItems.concat(v.msg.bag_info.item_infos); } });
    c2.waiters.push({ n: 'res_bag', r: (v) => { clearTimeout(t); res(v); } });
  });
  check(resBag.result === 0, 'res_bag after restart');
  const gold = bagItems.filter((i) => i.item_id === 9001).reduce((s, i) => s + num(i.count), 0);
  check(gold === STARTER_GOLD - 10000, `gold persisted after purchase+restart (${gold})`);
  c2.send('req_character_list');
  const chars = (await c2.wait('res_character_list')).msg.character_list_info.character_infos;
  check(chars.length === 10, `characters persisted (${chars.length})`);

  stopServer();
  srv2.kill();
  console.log(failures === 0 ? 'PERSISTENCE PASSED' : `${failures} FAILED`);
  process.exit(failures ? 1 : 0);
}

main().catch((e) => { console.error('FATAL', e); stopServer(); process.exit(1); });
