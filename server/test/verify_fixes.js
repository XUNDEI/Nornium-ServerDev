// 专项验证：累充奖励 + 抽卡保底语义 + finished_type_ids
const net = require('net');
const protobuf = require('protobufjs');
const DES = require('des.js').DES;
const gd = require('../src/gamedata');
const gacha = require('../src/game/gacha');

const root = new protobuf.Root();
root.loadSync(require('path').join(__dirname, '..', '..', 'reference', 'proto', 'msg.proto'), { keepCase: true });
const Msg = root.lookupType('ghs.Msg');
const nameToNum = {}, numToName = {};
for (const f of Object.values(Msg.fields)) { nameToNum[f.name] = f.id; numToName[f.id] = f.name; }
const NO_CRYPT = new Set(['req_ping', 'res_ping', 'ntf_server_time', 'ntf_msg_key']);

function desEcb(key, data, type) {
  const d = new DES({ type, key: Array.from(key) }); d.padding = false;
  const out = d.update(Array.from(data));
  return Buffer.from(type === 'decrypt' ? out.concat(d.final()) : out);
}
function pad(d) { const c = (d.length + 8) & ~7; const p = Buffer.alloc(c); d.copy(p); p[d.length] = 0x80; return p; }
function unpad(d) { for (let i = d.length - 1; i >= d.length - 8; i--) { if (d[i] === 0x80) return d.subarray(0, i); if (d[i] !== 0) throw new Error('bad pad'); } throw new Error('no marker'); }
const enc = (k, d) => desEcb(k, pad(d), 'encrypt'), dec = (k, d) => unpad(desEcb(k, d, 'decrypt'));

const sock = net.connect(8101, '127.0.0.1');
let buf = Buffer.alloc(0); let sessionKey = null; let sno = 0;
const pending = [];
sock.on('data', (chunk) => {
  buf = Buffer.concat([buf, chunk]);
  while (buf.length >= 4) {
    const size = buf.readUInt32BE(0);
    if (buf.length < size) break;
    const frame = buf.subarray(0, size); buf = buf.subarray(size);
    const cmd = frame.readUInt16BE(6);
    const name = numToName[cmd]; const body = frame.subarray(12);
    let msg = null;
    if (body.length > 0) msg = Msg.decode(NO_CRYPT.has(name) ? body : dec(sessionKey, body));
    if (msg) pending.push({ name, result: frame.readUInt16BE(4), msg: msg[msg.sub_msg] });
  }
});
function send(name, payload) {
  const body = Msg.encode(Msg.create({ [name]: payload || {} })).finish();
  const data = NO_CRYPT.has(name) ? body : enc(sessionKey, body);
  sno++;
  const head = Buffer.alloc(10);
  head.writeUInt32BE(10 + data.length, 0);
  head.writeUInt16BE(nameToNum[name], 4);
  head.writeUInt16BE(0, 6); head.writeUInt16BE(sno, 8);
  sock.write(Buffer.concat([head, data]));
}
function wait(name, timeout = 5000) {
  return new Promise((resolve, reject) => {
    const t0 = Date.now();
    const check = () => {
      const i = pending.findIndex(p => p.name === name);
      if (i >= 0) return resolve(pending.splice(i, 1)[0]);
      if (Date.now() - t0 > timeout) return reject(new Error('timeout ' + name));
      setTimeout(check, 30);
    };
    check();
  });
}

(async () => {
  const keyMsg = await wait('ntf_msg_key');
  sessionKey = dec(Buffer.from('kueisoon'), Buffer.from(keyMsg.msg.msg_key));
  const acct = 'verify' + (Date.now() % 100000);
  send('req_register', { account_name: acct, password: 'pw', channel: 'local_dev', client_version: '1.0.1' });
  await wait('res_register');
  send('req_login', { account_name: acct, password: 'pw' });
  await wait('res_login');

  // check 1: finished_type_ids 含 0（隐藏占位池页签）
  send('req_gacha');
  const g = await wait('res_gacha');
  const fin = Array.from(g.msg.gacha_info.finished_type_ids || []);
  console.log('check1 finished_type_ids:', JSON.stringify(fin), fin.includes(0) ? 'PASS' : 'FAIL');

  // check 2: 买 charge 商品攒积分后领取累充奖励
  const chargeItem = gd.rows('d_mall').map(([, r]) => r).find(r => r.charge === 1 && (r.chargePoint ?? 0) >= 9900);
  send('req_create_order', { order_item_id: chargeItem.id, order_item_count: 1 });
  await wait('res_create_order');
  await wait('ntf_item_info', 3000).catch(() => { });
  send('req_mall_receive_charge_point_reward', { charge_point_id: 1 });
  const r1 = await wait('res_mall_receive_charge_point_reward');
  console.log('check2 charge reward result:', r1.result, r1.result === 0 ? 'PASS' : 'FAIL');
  await wait('ntf_item_info', 3000).catch(() => { });

  // check 3: 重复领取被拒
  send('req_mall_receive_charge_point_reward', { charge_point_id: 1 });
  const r2 = await wait('res_mall_receive_charge_point_reward');
  console.log('check3 duplicate rejected:', r2.result !== 0 ? 'PASS' : 'FAIL');

  // check 4: 保底语义——常驻池 100 抽内必出 UP 且计数归零
  const doc = { gacha: { type_infos: {} } };
  const st = gacha.typeState(doc, 3);
  const cfg = gd.query('d_gacha_list', 1);
  let upAt = -1;
  for (let i = 1; i <= 100; i++) {
    const beforeUp = st.no_up_times;
    gacha.rollOnce(doc, cfg, st);
    if (beforeUp >= 99 && st.no_up_times === 0) { upAt = i; break; }
    if (st.no_up_times === 0) { upAt = i; break; } // 途中自然出 UP 也算（重置=拿到 UP）
  }
  console.log('check4 pity:', upAt > 0 ? `PASS (UP at pull ${upAt})` : 'FAIL');

  sock.destroy(); process.exit(0);
})().catch(e => { console.error('VERIFY FAILED:', e.message); process.exit(1); });
