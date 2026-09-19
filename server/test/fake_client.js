// Headless fake client: speaks the exact wire protocol the real client uses
// (HTTP gate + TCP framing + DES + protobuf oneof) and drives a full game
// flow: register/login -> 13 initial requests -> universe run -> gacha ->
// shop -> mall -> mail -> relogin restore.
const net = require('net');
const http = require('http');
const path = require('path');
const protobuf = require('protobufjs');
const DES = require('des.js').DES;

const HOST = '127.0.0.1';
const TCP_PORT = 8101;
const HTTP_PORT = 8089;

const log = (...a) => console.log('[client]', ...a);
let failures = 0;
function check(cond, msg) {
  if (cond) {
    console.log('  PASS', msg);
  } else {
    failures += 1;
    console.log('  FAIL', msg);
  }
}

// ---------- crypt ----------
function desEcb(key, data, type) {
  const des = new DES({ type, key: Array.from(key) });
  des.padding = false; // avoid des.js PKCS unpad choking on ISO 0x80 marker
  const out = des.update(Array.from(data));
  return Buffer.from(type === 'decrypt' ? out.concat(des.final()) : out);
}
function pad(d) {
  const sz = (d.length + 8) & ~7;
  const p = Buffer.alloc(sz);
  d.copy(p);
  p[d.length] = 0x80;
  return p;
}
function unpad(d) {
  for (let i = d.length - 1; i >= d.length - 8; i--) {
    if (d[i] === 0x80) return d.subarray(0, i);
    if (d[i] !== 0) throw new Error('bad pad');
  }
  throw new Error('no marker');
}
const enc = (k, d) => desEcb(k, pad(d), 'encrypt');
const dec = (k, d) => unpad(desEcb(k, d, 'decrypt'));

// ---------- protobuf ----------
const root = new protobuf.Root();
let Msg;
const NO_CRYPT = new Set(['req_ping', 'res_ping', 'ntf_server_time', 'ntf_msg_key']);

// ---------- protocol client ----------
class Client {
  constructor() {
    this.sock = null;
    this.buf = Buffer.alloc(0);
    this.sessionKey = null;
    this.cNo = 0;
    this.sNo = 0;
    this.listeners = [];
    this.waiters = [];
  }

  connect() {
    return new Promise((resolve, reject) => {
      this.sock = net.connect(TCP_PORT, HOST, () => resolve());
      this.sock.on('data', (c) => this.onData(c));
      this.sock.on('error', reject);
    });
  }

  onData(chunk) {
    this.buf = Buffer.concat([this.buf, chunk]);
    while (this.buf.length >= 4) {
      const size = this.buf.readUInt32BE(0);
      if (this.buf.length < size) return;
      const frame = this.buf.subarray(0, size);
      this.buf = this.buf.subarray(size);
      const result = frame.readUInt16BE(4);
      const cmd = frame.readUInt16BE(6);
      const body = frame.subarray(12);
      const field = Object.values(Msg.fields).find((f) => f.id === cmd);
      if (!field) continue;
      let msg = null;
      if (body.length > 0) {
        let plain;
        try {
          plain = NO_CRYPT.has(field.name) ? body : dec(this.sessionKey, body);
        } catch (e) {
          console.log('  [decrypt fail]', field.name, 'bodyLen', body.length,
            'mod8', body.length % 8, 'hex', body.toString('hex').slice(0, 64));
          throw e;
        }
        msg = Msg.decode(plain)[field.name] ?? {};
      }
      this.sNo = frame.readUInt16BE(10);
      this.dispatch(field.name, result, msg);
    }
  }

  dispatch(name, result, msg) {
    // FIFO pairing like the real client: first waiter wanting this name wins
    const i = this.waiters.findIndex((w) => w.name === name);
    if (i >= 0) {
      const w = this.waiters.splice(i, 1)[0];
      w.resolve({ result, msg });
      return;
    }
    this.listeners.forEach((l) => l(name, result, msg));
  }

  wait(name, timeoutMs = 5000) {
    return new Promise((resolve, reject) => {
      const t = setTimeout(() => {
        const i = this.waiters.findIndex((w) => w.resolve === resolve);
        if (i >= 0) this.waiters.splice(i, 1);
        reject(new Error(`timeout waiting ${name}`));
      }, timeoutMs);
      this.waiters.push({ name, resolve: (v) => { clearTimeout(t); resolve(v); } });
    });
  }

  onAny(fn) {
    this.listeners.push(fn);
    return () => { this.listeners = this.listeners.filter((f) => f !== fn); };
  }

  send(name, sub) {
    const field = Msg.fields[name];
    const payload = {};
    payload[name] = sub || {};
    let body = Buffer.from(Msg.encode(Msg.create(payload)).finish());
    if (!NO_CRYPT.has(name)) body = enc(this.sessionKey, body);
    this.cNo = (this.cNo + 1) & 0xffff;
    const head = Buffer.alloc(10);
    head.writeUInt32BE(10 + body.length, 0);
    head.writeUInt16BE(field.id, 4);
    head.writeUInt16BE(this.cNo, 6);
    head.writeUInt16BE(this.sNo, 8);
    this.sock.write(Buffer.concat([head, body]));
  }
}

function httpPost(path_, body) {
  return new Promise((resolve, reject) => {
    const data = Buffer.from(JSON.stringify(body ?? {}));
    const req = http.request({
      host: HOST, port: HTTP_PORT, path: path_, method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': data.length },
    }, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve({ status: res.statusCode, body: JSON.parse(Buffer.concat(chunks).toString()) }));
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

const num = (v) => (v && typeof v === 'object' && v.toNumber) ? v.toNumber() : Number(v ?? 0);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const nowSec = () => Math.floor(Date.now() / 1000);

// ntf_bag_info ×N → res_bag 时序（同真实客户端）
async function readBag(c) {
  let items = [];
  const off = c.onAny((name, result, msg) => {
    if (name === 'ntf_bag_info') items = items.concat(msg.bag_info.item_infos);
  });
  c.send('req_bag');
  await c.wait('res_bag');
  off();
  return items;
}

async function main() {
  await root.load(path.join(__dirname, '..', '..', 'reference', 'proto', 'msg.proto'), { keepCase: true });
  Msg = root.lookupType('ghs.Msg');

  // ---------- HTTP gate ----------
  const st = await httpPost('/client/system/serverStatus', {});
  check(st.status === 200 && st.body.code === 0 && st.body.data.status === 0, `serverStatus ${JSON.stringify(st.body)}`);
  const notice = await httpPost('/client/notice/list', {});
  check(notice.body.code === 0 && Array.isArray(notice.body.data), 'notice/list data is array');

  // ---------- TCP handshake ----------
  const c = new Client();
  await c.connect();
  const keyMsg = await c.wait('ntf_msg_key');
  c.sessionKey = dec(Buffer.from('kueisoon'), Buffer.from(keyMsg.msg.msg_key, 'latin1'));
  check(c.sessionKey.length === 8, `session key handshake (${c.sessionKey.toString('latin1')})`);

  const acct = `tester${Date.now() % 100000}`;

  // ---------- M0: register/login ----------
  c.send('req_register', { account_name: acct, password: 'pw123', channel: 'local_dev', client_version: '1.0.1' });
  check((await c.wait('res_register')).result === 0, 'res_register ok');
  c.send('req_login', { account_name: acct, password: 'pw123' });
  const login = await c.wait('res_login');
  check(login.result === 0 && num(login.msg.account_id) > 0, `res_login account_id=${num(login.msg.account_id)}`);

  // ---------- M1: 13 initial requests ----------
  c.send('req_player');
  const p = (await c.wait('res_player')).msg;
  check(p?.player_info?.player_name?.length > 0, 'res_player has player_name');
  check(Array.isArray(p.player_info.player_daily_mission_info?.player_mission_infos)
    && p.player_info.player_daily_mission_info.player_mission_infos.length > 0, 'player_daily_mission_info non-empty');
  check(Array.isArray(p.player_info.player_book_mission_infos)
    && p.player_info.player_book_mission_infos.length > 0, 'player_book_mission_infos non-empty');
  check(Array.isArray(p.player_info.blueprint_ids) && p.player_info.blueprint_ids.length > 0,
    `synthesis blueprints seeded (${p.player_info.blueprint_ids.length})`);

  c.send('req_bag');
  let bagItems = [];
  const offBag = c.onAny((name, result, msg) => {
    if (name === 'ntf_bag_info') bagItems = bagItems.concat(msg.bag_info.item_infos);
  });
  const bagRes = await c.wait('res_bag');
  offBag();
  check(bagRes.result === 0, 'res_bag ok');
  check(bagItems.length > 0, `ntf_bag_info delivered ${bagItems.length} items before res_bag`);
  const gold = bagItems.find((i) => i.item_id === 9001);
  check(gold && num(gold.count) >= 500000, `initial gold ${gold ? num(gold.count) : 0}`);
  // 官方每日 04:00 发放 6 张危航许可，登录时补发（发生在背包同步之前）
  const permits = bagItems.find((i) => i.item_id === 1201003);
  check(permits && num(permits.count) === 6,
    `daily reset granted 6 危航许可 (${permits ? num(permits.count) : 0})`);

  c.send('req_home'); check((await c.wait('res_home')).result === 0, 'res_home ok');

  // 家具摆放：req_build_home 是「整份布局替换」，req_home 必须把同样的布局发回来，
  // 否则客户端 BuildSystem 每次登录都把自己清空（主线「放置家具」看着没做）。
  const FURNITURE = 7120201; // d_bag_item_furniture / 主线 100030108 要求的家具
  c.send('req_build_home', {
    home_furniture_infos: [{ item_id: FURNITURE, blob: '{"posIndex":401,"skinId":4120201}' }],
  });
  check((await c.wait('res_build_home')).result === 0, 'res_build_home ok');
  c.send('req_home');
  const homeBack = (await c.wait('res_home')).msg.home_info;
  check(homeBack.home_furniture_infos.length === 1 &&
        num(homeBack.home_furniture_infos[0].item_id) === FURNITURE &&
        homeBack.home_furniture_infos[0].blob.includes('401'),
    'res_home echoes the placed furniture layout');

  // 家具交互产家具币：d_bag_item_furniture[7120201].tokenInteract = 80，
  // 每日上限 d_com_params[25].value2 = 240
  c.send('req_receive_furniture_coin_from_interact', { item_id: FURNITURE });
  check((await c.wait('res_receive_furniture_coin_from_interact')).result === 0,
    'res_receive_furniture_coin_from_interact ok');
  const coinNtf = await c.wait('ntf_item_info');
  check(coinNtf.msg.changed_item_infos.some((i) => num(i.item_id) === 9008 && num(i.count) === 80),
    'furniture interaction pays 80 家具币 into the bag');
  for (let i = 0; i < 2; i++) {
    c.send('req_receive_furniture_coin_from_interact', { item_id: FURNITURE });
    await c.wait('res_receive_furniture_coin_from_interact');
    await c.wait('ntf_item_info');
  }
  c.send('req_receive_furniture_coin_from_interact', { item_id: FURNITURE });
  check((await c.wait('res_receive_furniture_coin_from_interact')).result === 2,
    'a 4th interaction hits the daily cap (RECEIVE_LIMIT)');

  c.send('req_universe');
  const uni0 = await c.wait('res_universe');
  check(uni0.result === 2, 'res_universe EMPTY_UNIVERSE for fresh account');
  c.send('req_total_war');
  const tw = (await c.wait('res_total_war')).msg;
  check(tw?.total_war_info?.fight_info !== null && tw.total_war_info !== null, 'res_total_war has fight_info');
  c.send('req_shop_list');
  const shops = (await c.wait('res_shop_list')).msg.shop_list_info.shop_infos;
  check(shops.length >= 2, `res_shop_list ${shops.length} shops`);
  check(shops.some((s) => s.shop_item_infos.length > 0), 'shop 102 has goods');
  c.send('req_mall_list');
  const malls = (await c.wait('res_mall_list')).msg.mall_list_info.mall_infos;
  check(malls.length >= 5, `res_mall_list ${malls.length} malls`);
  c.send('req_hard_level');
  const hl = (await c.wait('res_hard_level')).msg;
  check(hl?.hard_level_info?.fight_info != null, 'res_hard_level has fight_info');
  c.send('req_character_list');
  const chars = (await c.wait('res_character_list')).msg.character_list_info.character_infos;
  check(chars.length === 10, `res_character_list ${chars.length} characters`);
  check(!chars.some((ch) => num(ch.character_id) === 24002),
    'dev placeholder character 24002 not granted');
  check(chars.every((ch) => ch.weapon_info && num(ch.weapon_info.item_uuid) > 0), 'every character has a weapon');

  // ---------- character level up must persist across a list reload ----------
  // Regression: stackable materials used to share item_uuid 0, so the server
  // resolved the client's {item_uuid, count} to the wrong bag entry and stored
  // a tiny exp gain; reopening the character screen then showed the old level.
  const lvChar = chars[0];
  const expMat = bagItems.find((i) => i.item_id === 1203001);
  check(expMat && num(expMat.item_uuid) > 0, 'stackable exp material has a unique uuid');
  const goldBefore = num((bagItems.find((i) => i.item_id === 9001) || {}).count);
  let lvNtf = null;
  const offLv = c.onAny((name, result, msg) => {
    if (name === 'ntf_item_info') {
      for (const ci of msg.changed_item_infos) if (ci.item_id === 1203001) lvNtf = ci;
    }
  });
  const expBefore = num(lvChar.exp);
  c.send('req_character_level_up', { character_id: lvChar.character_id, item_infos: [{ item_uuid: expMat.item_uuid, count: 1 }] });
  check((await c.wait('res_character_level_up')).result === 0, 'res_character_level_up ok');
  await sleep(50);
  offLv();
  check(lvNtf && num(lvNtf.count) === -1, 'ntf_item_info consumed the exp material');
  c.send('req_character_list');
  const charsReload = (await c.wait('res_character_list')).msg.character_list_info.character_infos;
  const lvReload = charsReload.find((ch) => ch.character_id === lvChar.character_id);
  check(num(lvReload.exp) === expBefore + 1000, `character exp persisted on reload (${expBefore} -> ${num(lvReload.exp)})`);
  c.send('req_bag');
  let bag2 = [];
  const offBag2 = c.onAny((name, result, msg) => {
    if (name === 'ntf_bag_info') bag2 = bag2.concat(msg.bag_info.item_infos);
  });
  await c.wait('res_bag');
  offBag2();
  check(num((bag2.find((i) => i.item_id === 1203001) || {}).count) === 998, 'exp material decremented to 998');
  check(num((bag2.find((i) => i.item_id === 9001) || {}).count) === goldBefore, 'gold untouched by level up');

  c.send('req_plot');
  const plot = (await c.wait('res_plot')).msg;
  check(plot?.plot_info && plot.plot_info.plot_tree_id === 0, 'res_plot fresh (0/0)');
  // client would auto-request the first node here
  c.send('req_play_plot_node', { plot_tree_id: 100010, plot_node_id: 100010 });
  check((await c.wait('res_play_plot_node')).result === 0, 'res_play_plot_node ok');
  const plotMission = await c.wait('ntf_add_plot_mission');
  check(Array.isArray(plotMission.msg.plot_mission_infos) && plotMission.msg.plot_mission_infos.length > 0,
    'ntf_add_plot_mission after play node');
  const pm = plotMission.msg.plot_mission_infos[0];
  const taskRow = JSON.parse(require('fs').readFileSync(path.join(__dirname, '..', '..', 'reference', 'gamedata', 'd_task_story.json')))[String(num(pm.mission_id))];
  check(!!taskRow, `plot mission ${num(pm.mission_id)} exists in d_task_story`);
  c.send('req_activity_list'); check((await c.wait('res_activity_list')).result === 0, 'res_activity_list ok');
  c.send('req_gacha');
  const g0 = (await c.wait('res_gacha')).msg;
  check(Array.isArray(g0?.gacha_info?.gacha_type_infos) && g0.gacha_info.gacha_type_infos.length > 0, 'res_gacha has type infos');
  c.send('req_mail_list');
  const mails = (await c.wait('res_mail_list')).msg.mail_list_info.mail_infos;
  check(mails.length >= 1, `res_mail_list ${mails.length} mails (welcome)`);

  // ping
  c.send('req_ping');
  check((await c.wait('res_ping')).result === 0, 'ping roundtrip');

  // ---------- M2: universe run ----------
  const team = [10101, 10201, 10301];
  c.send('req_new_universe', { difficulty_value: 1, main_planet_id: 110, map_type: 1, character_ids: team });
  const nu = await c.wait('res_new_universe');
  check(nu.result === 0 && nu.msg.universe_info.main_pos_infos.length > 0,
    `res_new_universe ${nu.msg?.universe_info?.main_pos_infos?.length} cells`);
  const ui = nu.msg.universe_info;
  check(ui.universe_fight_data && ui.universe_fight_data.character_fight_datas.length === 3,
    'universe_fight_data present with 3 slots');
  check(num(ui.universe_fight_data.character_fight_datas[0].cur_hp) > 0, 'first character has positive HP');
  // 官方口径：d_srpg_level_boss.appearTime 才是首领出现的探索步数（map 1 / boss 11
  // 是 [2]），开局不该有首领——否则「败者首领在基地附近出现」的横幅从第 1 步就挂着，
  // 而且击杀后立刻补下一波，横幅再也消不掉。见 REVERSE_ENGINEERING.md 坑 27。
  check(ui.boss_infos.length === 0, 'no boss on the map before its appearTime step');

  // find an explorable cell (state 2)
  const cell2 = ui.main_pos_infos.find((m) => m.state === 2);
  check(!!cell2, 'an explorable cell exists at start');
  c.send('req_explore', { hex: cell2.hex });
  check((await c.wait('res_explore')).result === 0, `explore ${cell2.hex.q},${cell2.hex.r}`);

  // expect either a fight or state changes; scan for a fight being offered
  let fightInfo = null;
  const offFight = c.onAny((name, result, msg) => {
    if (name === 'ntf_fight_info') fightInfo = msg.fight_info;
  });
  // explore battle cells (5xx) until a fight appears
  for (let tries = 0; tries < 12 && !fightInfo; tries++) {
    const cur = await currentUniverse(c);
    const next = cur.main_pos_infos.find((m) => m.state === 2);
    if (!next) break;
    c.send('req_explore', { hex: next.hex });
    const r = await c.wait('res_explore');
    if (r.result !== 0) break;
    await sleep(30);
  }
  offFight();
  check(!!fightInfo, `encounter fight offered (level ${fightInfo ? fightInfo.fight_level_id : '-'})`);

  if (fightInfo) {
    c.send('req_universe_fight', { fight_uuid: fightInfo.fight_uuid });
    check((await c.wait('res_universe_fight')).result === 0, 'res_universe_fight ok');
    c.send('req_complete_universe_fight', {
      fight_uuid: fightInfo.fight_uuid,
      result: true,
      universe_fight_data: {
        character_fight_datas: [
          { character_id: team[0], cur_hp: 700 },
          { character_id: team[1], cur_hp: 800 },
          { character_id: team[2], cur_hp: 900 },
        ],
        boat_energy: 40,
      },
    });
    check((await c.wait('res_complete_universe_fight')).result === 0, 'res_complete_universe_fight ok');
  }

  // card select may have appeared after the win
  const cardSelect = await currentUniverse(c);
  const sel = cardSelect.cards_for_selects?.[0];
  if (sel) {
    c.send('req_choose_card', { select_uuid: sel.select_uuid, index: 0 });
    check((await c.wait('res_choose_card')).result === 0, 'res_choose_card ok');
    await sleep(30);
    const after = await currentUniverse(c);
    check(after.card_ids.length === (cardSelect.card_ids.length + 1) || after.card_ids.length > 0,
      `hand now ${after.card_ids.length} cards`);
  }

  // boss fight to clear the run — boss 11 has appearTime [2], so it only exists
  // after the second exploration step
  const beforeBoss = await currentUniverse(c);
  check(beforeBoss.boss_infos.length >= 1,
    `boss wave 0 appeared once its appearTime step was reached (${beforeBoss.boss_infos.length} live)`);
  const bossIdx = beforeBoss.boss_infos[0]?.boss_index ?? 0;
  c.send('req_boss_fight', { boss_index: bossIdx });
  const bf = await c.wait('res_boss_fight');
  check(bf.result === 0 && num(bf.msg.fight_info.fight_uuid) > 0, `res_boss_fight uuid=${num(bf.msg?.fight_info?.fight_uuid)}`);
  c.send('req_complete_boss_fight', {
    boss_index: bossIdx, result: true,
    universe_fight_data: { character_fight_datas: [{ character_id: team[0], cur_hp: 500 }], boat_energy: 10 },
  });
  check((await c.wait('res_complete_boss_fight')).result === 0, 'res_complete_boss_fight ok');
  // boss 11 has path [101] (single wave) → the run is cleared instead of the boss
  // being replaced, which is what lets the 「败者首领」 banner disappear
  await sleep(100);
  const clearOrWave = await currentUniverse(c);
  console.log('  [info] after boss win: bosses =', clearOrWave ? clearOrWave.boss_infos.length : 'universe cleared');
  // finish remaining waves if any
  let guard = 0;
  while (clearOrWave && clearOrWave.boss_infos.length > 0 && guard++ < 5) {
    const b2 = clearOrWave.boss_infos[0].boss_index;
    c.send('req_boss_fight', { boss_index: b2 });
    const r2 = await c.wait('res_boss_fight');
    if (r2.result !== 0) break;
    c.send('req_complete_boss_fight', { boss_index: b2, result: true, universe_fight_data: {} });
    await c.wait('res_complete_boss_fight');
    await sleep(50);
    clearOrWave = await currentUniverse(c);
  }

  // ---------- M3: gacha ----------
  c.send('req_gacha_create', { list_id: 1, times: 10 });
  const gc = await c.wait('res_gacha_create');
  check(gc.result === 0 && gc.msg.gacha_pending_record_infos.length === 10,
    `gacha create 10 records (result=${gc.result})`);
  c.send('req_gacha_confirm', { list_id: 1 });
  check((await c.wait('res_gacha_confirm')).result === 0, 'gacha confirm ok');

  // ---------- M3: furnace (炼金合成 / 分解) ----------
  c.send('req_item_synthetic', { blueprint_id: 3001, count: 1 }); // [1202001 x3] -> 1202002
  check((await c.wait('res_item_synthetic')).result === 0, 'res_item_synthetic ok');
  c.send('req_item_decompose', { item_uuids: [] });
  check((await c.wait('res_item_decompose')).result === 2, 'decompose empty list rejected (INVALID_COUNT)');
  c.send('req_item_decompose', { item_uuids: [999999999] });
  check((await c.wait('res_item_decompose')).result === 1, 'decompose unknown uuid rejected (INVALID_ITEM)');
  // decompose a gacha-obtained gear instance (weapons carry weapon_info)
  c.send('req_bag');
  let bagGear = [];
  const offBag3 = c.onAny((name, result, msg) => {
    if (name === 'ntf_bag_info') bagGear = bagGear.concat(msg.bag_info.item_infos.filter((i) => i.weapon_info || i.arm_info));
  });
  await c.wait('res_bag');
  offBag3();
  if (bagGear.length) {
    c.send('req_item_decompose', { item_uuids: [bagGear[0].item_uuid] });
    check((await c.wait('res_item_decompose')).result === 0, `res_item_decompose ok (${num(bagGear[0].item_id)})`);
  } else {
    console.log('  [info] no bag gear to decompose after gacha — skipped');
  }

  // ---------- M3: shop ----------
  const shop102 = shops.find((s) => s.shop_item_infos.length > 0);
  if (shop102) {
    const it = shop102.shop_item_infos[0];
    c.send('req_shop_buy', { shop_id: shop102.shop_id, shop_item_id: it.shop_item_id, shop_item_count: 1, last_auto_refresh_seconds: 0 });
    check((await c.wait('res_shop_buy')).result === 0, `shop buy item ${it.shop_item_id}`);
  }

  // ---------- M3: mall (IAP instant grant) ----------
  c.send('req_mall_buy', { mall_id: 201, mall_item_id: 1001, mall_item_count: 1 });
  const mb = await c.wait('res_mall_buy');
  check(mb.result === 0 && num(mb.msg.game_order_id) > 0, `mall buy order ${num(mb.msg?.game_order_id)}`);
  const fin = await c.wait('ntf_finish_order');
  check(num(fin.msg.game_order_id) === num(mb.msg.game_order_id), 'ntf_finish_order received');

  // ---------- M4: mail receive ----------
  if (mails.length) {
    c.send('req_mail_receive', { mail_uuid: mails[0].mail_uuid });
    check((await c.wait('res_mail_receive')).result === 0, 'mail receive ok');
  }

  // ---------- M5: daily copy (每日危航 / d_levels) ----------
  // Regression: req_daily_level_fight used to answer LEVEL_LOCKED(2) to every
  // 出击, which the client shows as "cmd:102 code:2"
  // (Helper/ErrorFormatter.lua:98), so the main story task 「尝试一次每日危航」
  // (taskContent 10000) never counted. See also test/daily_check.js.
  // The 6 permits needed here come from the 04:00 daily reset (no GM needed).
  c.send('req_daily_level_fight', { fight_level_id: 15 });
  check((await c.wait('res_daily_level_fight')).result === 2,
    'a daily stage two steps ahead is LEVEL_LOCKED (2)');

  c.send('req_daily_level_fight', { fight_level_id: 13 });
  const dlf = await c.wait('res_daily_level_fight');
  check(dlf.result === 0 && num(dlf.msg.fight_uuid) > 0,
    `res_daily_level_fight uuid=${num(dlf.msg?.fight_uuid)}`);
  let dailyDrops = null;
  const offDaily = c.onAny((name, result, msg) => {
    if (name === 'ntf_item_info') dailyDrops = msg.changed_item_infos;
  });
  c.send('req_complete_daily_level_fight', { result: true });
  check((await c.wait('res_complete_daily_level_fight')).result === 0,
    'res_complete_daily_level_fight ok');
  await sleep(30);
  offDaily();
  check(Array.isArray(dailyDrops) && dailyDrops.some((x) => num(x.item_id) === 1202001),
    'the cleared daily stage paid out its d_levels drops');

  const bagAfterRun = await readBag(c);
  const permitsLeft = bagAfterRun.find((i) => i.item_id === 1201003);
  check(permitsLeft && num(permitsLeft.count) === 5,
    `clearing spent one 危航许可 (${permitsLeft ? num(permitsLeft.count) : 0} left)`);

  // cleared stages are recorded, so the same stage can now be swept
  c.send('req_gm_cmd', { cmd: 'add_item 1201001 2' }); // 杀手朋友券
  await c.wait('res_gm_cmd');
  c.send('req_daily_level_sweep', { fight_level_id: 13 });
  check((await c.wait('res_daily_level_sweep')).result === 0,
    'sweeping a cleared daily stage is OK');

  c.send('req_player');
  const settledInfo = (await c.wait('res_player')).msg.player_info;
  check(settledInfo.daily_level_fight_info != null
    && num(settledInfo.daily_level_fight_info.fight_level_id) === 0,
    'res_player reports an idle daily_level_fight_info once the run is settled');
  check((settledInfo.daily_level_id_passed || []).some((x) => num(x) === 13),
    'the cleared stage is persisted in daily_level_id_passed');

  // ---------- M5: month card (每天 04:00 一次，且不能刷屏报错) ----------
  // Regression: req_mall_receive_month_card was a stub answering NO_CARD(1).
  // The client polls it once per second while its cached month_card_info says
  // "card valid + a 04:00 boundary has passed" (MallSystem:CheckMonthCard), so
  // every poll popped "cmd:13006 code:1". The grant must push the new
  // month_card_info back (NtfMallInfo.month_card_info) or it never stops.
  let mcInfo = null;      // 服务端推下来的权威月卡状态
  let mcBonus = null;     // purchaseReward 9007
  let mcDaily = null;     // dailyReward 9002
  const offMc = c.onAny((name, result, msg) => {
    if (name === 'ntf_mall_info' && msg.month_card_info) mcInfo = msg.month_card_info;
    if (name === 'ntf_item_info') {
      for (const ci of msg.changed_item_infos || []) {
        if (num(ci.item_id) === 9007) mcBonus = ci;
        if (num(ci.item_id) === 9002) mcDaily = ci;
      }
    }
  });

  c.send('req_mall_buy', { mall_id: 202, mall_item_id: 1007, mall_item_count: 1 });
  check((await c.wait('res_mall_buy')).result === 0, 'month card purchase ok');
  await sleep(50);
  check(mcInfo && num(mcInfo.expire_seconds) > nowSec(),
    `ntf_mall_info carries the new month card expiry (${num(mcInfo?.expire_seconds)})`);
  check(mcInfo && num(mcInfo.last_tick_seconds) === 0,
    'buying leaves last_tick_seconds at 0 so the client claims day 1 at once');
  check(mcBonus && num(mcBonus.count) === 300,
    `the month card purchase bonus is granted (9007 x${mcBonus ? num(mcBonus.count) : '-'})`);

  mcInfo = null;
  c.send('req_mall_receive_month_card');
  check((await c.wait('res_mall_receive_month_card')).result === 0, 'month card daily claim ok');
  await sleep(50);
  check(mcDaily && num(mcDaily.count) === 100,
    `the daily month card reward is granted (9002 x${mcDaily ? num(mcDaily.count) : '-'})`);
  check(mcInfo && num(mcInfo.last_tick_seconds) > 0,
    'ntf_mall_info pushes the new last_tick_seconds so the client stops polling');

  c.send('req_mall_receive_month_card');
  check((await c.wait('res_mall_receive_month_card')).result === 2,
    'a second claim on the same day is ALREADY_RECEIVED (2), not NO_CARD');
  offMc();

  // ---------- relogin & universe restore ----------
  c.send('req_new_universe', { difficulty_value: 2, main_planet_id: 110, map_type: 1, character_ids: team });
  const nu2 = await c.wait('res_new_universe');
  check(nu2.result === 0, 'second run started');

  const c2 = new Client();
  await c2.connect();
  const key2 = await c2.wait('ntf_msg_key');
  c2.sessionKey = dec(Buffer.from('kueisoon'), Buffer.from(key2.msg.msg_key, 'latin1'));
  c2.send('req_relogin', { account_id: login.msg.account_id, key: login.msg.key });
  check((await c2.wait('res_relogin')).result === 0, 'res_relogin ok');
  c2.send('req_universe');
  const restore = await c2.wait('res_universe');
  check(restore.result === 0 && restore.msg.universe_info.main_pos_infos.length > 0
    && restore.msg.universe_info.universe_fight_data.character_fight_datas.length === 3,
    'universe restored after relogin');

  // ---------- 星图：具体地图绑定与切换角色定价（坑 25）----------
  // 一局必须「一行到底」：六边形布局、boss、初始资源、切换角色价格都取自同一行
  // d_srpg_map_base。客户端 UI_character_exchange_C.lua:96/172 按
  // d_srpg_map_base[model.mapId].substitutionCost 显示价格并决定「确认」按钮是否
  // 可点，服务端若按另一行的价格收费，资源抽干后就会一直回 RES_NOT_ENOUGH(4)，
  // 客户端表现为「cmd:1018 code:4」刷屏且按钮永远可点。
  const gd = require('../src/gamedata');
  const STORY_SPECIFIC = 1000309;               // d_srpg_map_specific[1000309].map = 1000309
  const storyMap = num(gd.query('d_srpg_map_specific', STORY_SPECIFIC).map);
  const storyCost = gd.query('d_srpg_map_base', storyMap).substitutionCost;
  const storyCells = (gd.query('d_srpg_map_data', storyMap).mainPosId || []).length;

  c2.send('req_new_universe_specific', { specific_id: STORY_SPECIFIC });
  const nus = await c2.wait('res_new_universe_specific');
  check(nus.result === 0 && num(nus.msg.universe_info.map_id) === storyMap,
    `res_new_universe_specific bound to map ${storyMap}`);
  check(nus.msg.universe_info.main_pos_infos.length === storyCells,
    `specific run lays out its own ${storyCells} hexes `
    + `(got ${nus.msg.universe_info.main_pos_infos.length})`);

  // 建筑格必须挂上 main_pos_card_pos_info，客户端才会渲染「管理」选项
  // （UI_Menu_C:1370 只遍历 main_pos_attach_infos）。教学星图的三个「建筑格」是
  // d_srpg_main_pos_base 102（nameId 102000101），旧服务端按 posId 前缀猜类型，
  // 把它们当成普通空地，主线「部署1个建筑」就永远点不动。
  const storySlots = nus.msg.universe_info.main_pos_infos
    .filter((m) => (m.main_pos_attach_infos || []).some((a) => a.main_pos_card_pos_info));
  check(storySlots.length === 3,
    `the story map exposes 3 building slots for 「部署1个建筑」 (got ${storySlots.length})`);
  check(storySlots.every((m) => num(m.main_pos_attach_infos[0].main_pos_card_pos_info.card_pos_id) === 3),
    'story maps use the free-recall card slot (d_srpg_card_pos 3 / recallCost [2,0])');
  const storyShops = nus.msg.universe_info.main_pos_infos
    .map((m) => (m.main_pos_attach_infos || []).find((a) => a.main_pos_shop_info))
    .filter(Boolean);
  check(storyShops.length === 2 && storyShops.every((a) => num(a.main_pos_shop_info.shop_id) === 1),
    `the story map's two merchant cells carry a shop (got ${storyShops.length})`);

  // 换一次角色：服务端扣的量必须等于客户端拿来算价的那张表
  const deltas = [];
  const offUni = c2.onAny((name, _r, msg) => {
    if (name === 'ntf_universe_info') deltas.push((msg.res_value || []).map(num));
  });
  c2.send('req_universe_change_character', { character_id: 10101, character_index: 0 });
  const cc = await c2.wait('res_universe_change_character');
  await sleep(80);
  offUni();
  check(cc.result === 0,
    `res_universe_change_character ok on map ${storyMap} (cost [${storyCost}])`);
  const charged = deltas.at(-1) || [];
  check(storyCost[1] === 0 && charged.every((v) => v === 0),
    `a free-substitution map charges nothing (delta [${charged.join(',')}])`);

  // 付费地图相反：必须真的按表收费，收不动时回 4（而不是默默放行/多收）
  c2.send('req_new_universe', { difficulty_value: 1, main_planet_id: 110, map_type: 1, character_ids: team });
  const paidUi = (await c2.wait('res_new_universe')).msg.universe_info;
  const paidMap = num(paidUi.map_id);
  const paidCost = gd.query('d_srpg_map_base', paidMap).substitutionCost;
  const purse = num(paidUi.res_value[paidCost[0] - 1]);
  const affordable = Math.floor(purse / paidCost[1]);
  let swaps = 0;
  for (let i = 0; i <= affordable; i++) {
    c2.send('req_universe_change_character', { character_id: 10101, character_index: i % 3 });
    const r = await c2.wait('res_universe_change_character');
    if (r.result === 0) { swaps += 1; continue; }
    check(r.result === 4, `an exhausted purse answers RES_NOT_ENOUGH(4) on map ${paidMap}`);
    break;
  }
  check(swaps === affordable,
    `map ${paidMap}: ${purse} points buy exactly ${affordable} swaps (got ${swaps})`);

  // old session should have been kicked (single login)
  await sleep(300);

  console.log(failures === 0 ? '\nALL CHECKS PASSED' : `\n${failures} CHECKS FAILED`);
  process.exit(failures === 0 ? 0 : 1);
}

async function currentUniverse(c) {
  c.send('req_universe');
  const r = await c.wait('res_universe');
  return r.result === 0 ? r.msg.universe_info : null;
}

main().catch((e) => {
  console.error('[client] FATAL', e);
  process.exit(1);
});
