// 存档编辑器（/editor）回归检查：静态页 + JSON API + 编辑操作 + 导出 + 服务器控制台。
//
// 无需游戏客户端：直接在进程内起 HTTP 门（随机端口），用 fetch 打接口。
// 覆盖：
//   1. /editor 静态页可访问，路径穿越被拒绝；
//   2. 游戏客户端路由（/client/*）在改动后行为不变（登录门仍返回 status 0）；
//   3. accounts/player/catalog/server/backups 接口返回真实数据；
//   4. update 操作：改货币 / 加道具 / 发专武 / 改角色，部分失败也要落盘已生效部分；
//   5. export 接口（默认位置 + 自定义目录）；
//   6. 服务器控制台：日志缓冲 tail / SSE 实时流 / 网页端执行控制台指令。
//
// 规矩（坑 35）：GHS_DATA_DIR 指向临时目录，测试绝不写真实的 server\data\。
const os = require('os');
const fs = require('fs');
const path = require('path');
const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'ghs-editor-'));
const tmpDataDir = path.join(tmpRoot, 'data');
process.env.GHS_DATA_DIR = tmpDataDir;
// runtime-config.json 同样隔离（资源自动补发开关的读写测试写这里，绝不碰真实配置）
process.env.GHS_RUNTIME_CONFIG = path.join(tmpRoot, 'runtime-config.json');

const store = require('../src/store');
const gd = require('../src/gamedata');
const { createGate } = require('../src/httpgate');

let failures = 0;
function check(cond, msg) {
  console.log(cond ? `  PASS ${msg}` : `  FAIL ${msg}`);
  if (!cond) failures += 1;
}

const API = async (port, p, opts) => {
  const res = await fetch(`http://127.0.0.1:${port}${p}`, opts);
  let body = null;
  try { body = await res.json(); } catch (_) { /* 非 JSON（静态页） */ }
  return { status: res.status, headers: res.headers, body };
};
const post = (port, p, data) => API(port, p, {
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data),
});

(async () => {
  store.loadAccounts();

  // 注入假钩子：maintenance 只记账不真的改监听，onStop 只记账不真的退进程
  // （index.js 注入的是真的维护窗口与 shutdown）。
  const hookCalls = { maintenance: 0, stop: 0 };
  const gate = await createGate(0, '127.0.0.1', {
    maintenance: async (fn) => { hookCalls.maintenance += 1; return fn({ kicked: 0, remaining: 0 }); },
    onStop: () => { hookCalls.stop += 1; },
    startedAt: Date.now() - 5000,
    tcpPort: 8101,
    httpPort: 9089,
  });
  const port = gate.address().port;
  check(Number.isFinite(port) && port > 0, `gate listens on a random port (${port})`);

  // ---------------- 静态页与路径穿越 ----------------
  {
    const page = await fetch(`http://127.0.0.1:${port}/editor`);
    const html = await page.text();
    check(page.status === 200 && /存档编辑器/.test(html), '/editor serves the editor page');
    check(page.headers.get('content-type').includes('text/html'), 'index.html has the html MIME type');

    const css = await fetch(`http://127.0.0.1:${port}/editor/style.css`);
    check(css.status === 200 && css.headers.get('content-type').includes('text/css'),
      '/editor/style.css serves with the css MIME type');

    const trav = await fetch(`http://127.0.0.1:${port}/editor/..%2F..%2Fsrc%2Fstore.js`);
    check(trav.status === 403 || trav.status === 404, `path traversal is rejected (${trav.status})`);

    const missing = await fetch(`http://127.0.0.1:${port}/editor/nope.js`);
    check(missing.status === 404, 'a missing static file is a plain 404');
  }

  // ---------------- 游戏客户端路由不受影响 ----------------
  {
    const r = await post(port, '/client/system/serverStatus');
    check(r.body && r.body.code === 0 && r.body.data.status === 0,
      'the game login gate still answers {code:0,data:{status:0}}');
    const n = await post(port, '/client/notice/list');
    check(Array.isArray(n.body.data), 'notice/list still returns an array');
  }

  // ---------------- 只读接口 ----------------
  {
    const seed = store.createAccount('editorhero', 'pw');
    store.savePlayer({
      account_id: seed.account_id,
      player: { player_name: '编辑勇者', register_seconds: '0', player_id: seed.account_id },
      bag: { items: [{ item_id: 9002, count: 10, item_uuid: 5001 }], next_uuid: 5002 },
      characters: [],
      gacha: { type_infos: {}, records: [], pending: null, pending_cost: 0 },
      mall: { purchase: {}, charge_point: 0, received_charge_points: [], month_card_expire: 0, month_card_last_tick: 0 },
      mail: { next_uuid: 1003, list: [] },
    });

    const accounts = await API(port, '/editor/api/accounts');
    check(accounts.body.code === 0 && accounts.body.data.players.length === 1,
      'accounts lists the seeded player');
    check(accounts.body.data.players[0].player_name === '编辑勇者',
      'the account summary carries the player name');

    const srv = await API(port, '/editor/api/server');
    check(srv.body.code === 0 && srv.body.data.stats.players === 1, 'server info reports the stats');

    const cat = await API(port, '/editor/api/catalog');
    check(cat.body.code === 0 && cat.body.data.weapons.length === 83
      && cat.body.data.characters.length === 10,
      `catalog carries weapons + playable characters (${cat.body.data.weapons.length}/${cat.body.data.characters.length})`);
    const salome = cat.body.data.characters.find((c) => c.id === 10201);
    // 10201 的专武是礼器族 4070601「受命者的视觉」，7★ 形态 4071611「总控者的视觉」。
    // 注意武器 id 首位不是 subType（坑 37：4072601 首位是 4 却是礼器）。
    check(salome && salome.exclusive_weapon === 4071611
      && salome.exclusive_weapon_base === 4070601 && Number(salome.profession) === 5,
      `character 10201 maps to her exclusive weapon ${salome ? salome.exclusive_weapon : '?'}`);
    // 专武映射抽查：旧版按「同类型最高稀有度」猜，10102/10601 都指到 2061610、
    // 10701 被指到信风的 1071611、10801 被指到鱼啄雨的 7081611 —— 逐一锁死。
    const expectMap = { 10101: 3060611, 10102: 2051611, 10601: 2041611, 10701: 1060611, 10801: 7070611, 11202: 7081611 };
    const mapBad = [];
    for (const [cid, wid] of Object.entries(expectMap)) {
      const c = cat.body.data.characters.find((x) => x.id === Number(cid));
      if (!c || c.exclusive_weapon !== wid) mapBad.push(`${cid}→${c ? c.exclusive_weapon : '缺角色'}`);
    }
    check(mapBad.length === 0, `catalog 专武映射与官方口径一致${mapBad.length ? ' 例外: ' + mapBad.join('; ') : ''}`);
    // 回归：任何专武都不能指向未实装武器（1081601「颂歌」等）
    const ghostTarget = cat.body.data.characters
      .filter((c) => c.exclusive_weapon === 1081601 || c.exclusive_weapon_base === 1081601);
    check(ghostTarget.length === 0,
      'no character is pointed at the unreleased 1081601');
    const unreleased = cat.body.data.weapons.filter((w) => w.released === false);
    check(unreleased.length === 10 && unreleased.some((w) => w.id === 1081601),
      `catalog flags exactly the 10 unreleased weapons (${unreleased.length})`);
    const leveling = cat.body.data.leveling;
    check(leveling && leveling.caps.join(',') === '20,40,50,60,70,80' && leveling.max_break === 5
      && leveling.role_exp.length === 90 && leveling.weapon_exp[7].length === 90,
      'catalog carries the level/exp tables the editor needs');

    const player = await API(port, `/editor/api/player/${seed.account_id}`);
    check(player.body.code === 0 && player.body.data.doc.player.player_name === '编辑勇者',
      'player returns the whole doc');

    const missing = await API(port, '/editor/api/player/9999');
    check(missing.body.code === 1, 'player/:id for a missing account fails cleanly');

    const unknown = await API(port, '/editor/api/whatever');
    check(unknown.body.code === 1, 'an unknown api path fails cleanly');
  }

  // ---------------- update 操作 ----------------
  {
    const id = 1; // 第一个种下的账号
    const r1 = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'set_currency', item_id: 9002, count: 555 },
      { op: 'add_item', item_id: 1200001, count: 3 },
      { op: 'grant_high_rarity_weapons' },
      { op: 'add_all_characters' },
    ] });
    check(r1.body.code === 0 && r1.body.data.notes.length === 4,
      `a mixed batch applies (${(r1.body.data.notes || []).join(' | ')})`);

    const doc = store.loadPlayer(id);
    const diamond = doc.bag.items.find((it) => it.item_id === 9002);
    check(diamond && diamond.count === 555, 'set_currency wrote 555 diamonds');
    const ticket = doc.bag.items.find((it) => it.item_id === 1200001);
    check(ticket && ticket.count === 3, 'add_item stacked 3 tickets');
    const weapons = doc.bag.items.filter((it) => it.weapon_info);
    check(weapons.length === 36, `grant_high_rarity_weapons created 36 weapon instances (${weapons.length})`);
    check(!weapons.some((w) => w.item_id === 1081601),
      'the unreleased 1081601 颂歌 is never granted');
    check(doc.characters.length === 10, 'add_all_characters created the launch roster');
    check(new Set(doc.bag.items.map((it) => it.item_uuid)).size === doc.bag.items.length,
      'no duplicate item uuids after the batch');

    // 未实装武器不能通过 add_item 塞进背包
    const rGhost = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'add_item', item_id: 1081601, count: 1 },
    ] });
    check(rGhost.body.code === 0 && /未实装/.test(rGhost.body.data.error || ''),
      `adding an unreleased weapon is rejected (${rGhost.body.data && rGhost.body.data.error})`);

    // 专武发放（新档）：每人一把 7★ 专武共 10 把；skip_owned 下重复执行幂等
    const seed2 = store.createAccount('exclusivehero', 'pw');
    store.savePlayer({
      account_id: seed2.account_id,
      player: { player_name: '专武勇者', register_seconds: '0', player_id: seed2.account_id },
      bag: { items: [], next_uuid: 6001 },
      characters: [],
      gacha: { type_infos: {}, records: [], pending: null, pending_cost: 0 },
      mall: { purchase: {}, charge_point: 0, received_charge_points: [], month_card_expire: 0, month_card_last_tick: 0 },
      mail: { next_uuid: 1003, list: [] },
    });
    const rEx = await post(port, `/editor/api/player/${seed2.account_id}/update`, { ops: [
      { op: 'grant_exclusive_weapons', skip_owned: true },
    ] });
    check(rEx.body.code === 0 && /发放专武 10 把/.test(rEx.body.data.notes.join()),
      `grant_exclusive_weapons grants 10 signature weapons (${rEx.body.data.notes.join(' | ')})`);
    const exWeapons = store.loadPlayer(seed2.account_id).bag.items.filter((it) => it.weapon_info);
    check(exWeapons.length === 10, `the fresh bag now holds 10 weapon instances (${exWeapons.length})`);
    check(exWeapons.every((w) => Number(gd.query('d_bag_item_weapon', w.item_id).rarity) === 7),
      'every granted exclusive weapon is a 7★');
    const rEx2 = await post(port, `/editor/api/player/${seed2.account_id}/update`, { ops: [
      { op: 'grant_exclusive_weapons', skip_owned: true },
    ] });
    check(rEx2.body.code === 0 && /没有需要发放的专武/.test(rEx2.body.data.notes.join()),
      'grant_exclusive_weapons with skip_owned is idempotent');

    // 部分失败：最后一个操作引用不存在的 uuid，前面的仍要生效并报告 error
    const r2 = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'set_currency', item_id: 9001, count: 123 },
      { op: 'remove_item', item_uuid: 424242 },
    ] });
    check(r2.body.code === 0 && r2.body.data.error && /没有 uuid/.test(r2.body.data.error),
      'a failing op is reported as data.error, not a 500');
    check(store.loadPlayer(id).bag.items.find((it) => it.item_id === 9001).count === 123,
      'the ops before the failure are still applied and saved');

    const r3 = await post(port, `/editor/api/player/${id}/update`, { ops: [{ op: 'explode' }] });
    check(r3.body.code === 0 && /未知操作/.test(r3.body.data.error),
      'an unknown op type is reported as data.error');

    const r4 = await post(port, `/editor/api/player/${id}/update`, {});
    check(r4.body.code === 1 && /ops/.test(r4.body.msg), 'a body without ops is rejected');

    // ---------------- 宇宙资源（set_universe_res）----------------
    // 资源只存在于进行中的远航：没开局先报错；开局后按 1..4 改并落数。
    const noRun = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'set_universe_res', res_type: 2, count: 500 },
    ] });
    check(noRun.body.code === 0 && /远航/.test(noRun.body.data.error || ''),
      `set_universe_res without an active run is rejected (${noRun.body.data && noRun.body.data.error})`);

    const U = require('../src/game/universe');
    const doc1 = store.loadPlayer(id);
    const sent = [];
    require('../src/handlers/universe').handle('req_new_universe')(
      { player: doc1, send: (n, m, r) => sent.push({ n, m, r }) },
      { difficulty_value: 1, main_planet_id: 110, map_type: 1, character_ids: [doc1.characters[0].character_id] },
    );
    store.savePlayer(doc1);
    check(doc1.universe && doc1.universe.active, 'a run was created for the resource tests');

    const rRes = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'set_universe_res', res_type: 2, count: 999 },
      { op: 'set_universe_res', res_type: 1, count: 12 },
    ] });
    check(rRes.body.code === 0 && !rRes.body.data.error,
      `set_universe_res applies (${(rRes.body.data.notes || []).join(' | ')})`);
    const runDoc = store.loadPlayer(id);
    check(Number(runDoc.universe.res_value[2]) === 999 && Number(runDoc.universe.res_value[1]) === 12,
      `the run's res_value was written (${JSON.stringify(runDoc.universe.res_value)})`);

    const badType = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'set_universe_res', res_type: 9, count: 1 },
    ] });
    check(badType.body.code === 0 && /1\.\.4/.test(badType.body.data.error || ''),
      'res_type outside 1..4 is rejected');

    // ---------------- 资源自动补发开关（universe_grant 端点）----------------
    // 写的是 GHS_RUNTIME_CONFIG 指向的临时文件，不碰真实 runtime-config.json。
    const srvInfo = await API(port, '/editor/api/server');
    check(srvInfo.body.data.universe_grant && srvInfo.body.data.universe_grant.enabled === true
      && Number(srvInfo.body.data.universe_grant.floor) === 100,
      `server info exposes the default grant state (${JSON.stringify(srvInfo.body.data.universe_grant)})`);

    const gOff = await post(port, '/editor/api/server/universe_grant', { enabled: false, floor: 50 });
    check(gOff.body.code === 0 && gOff.body.data.enabled === false && gOff.body.data.floor === 50,
      'POST universe_grant toggles the switch');
    const savedCfg = JSON.parse(fs.readFileSync(process.env.GHS_RUNTIME_CONFIG, 'utf8'));
    check(savedCfg.universe_auto_grant === false && savedCfg.universe_resource_floor === 50,
      'the runtime config file carries the new keys');
    check(require('../src/handlers/universe').grantCfg().on === false,
      'grantCfg (live spend path) sees the change without a restart');
    const gOn = await post(port, '/editor/api/server/universe_grant', { enabled: true });
    check(gOn.body.data.enabled === true && gOn.body.data.floor === 50,
      'floor survives a toggle-only update');
  }

  // ---------------- 等级 / 光淬编辑 ----------------
  {
    const id = 1;
    const gd = require('../src/gamedata');
    let doc = store.loadPlayer(id);
    const char = doc.characters.find((c) => c.weapon_info);
    const charId = char.character_id;
    const weaponUuid = Number(char.weapon_info.item_uuid);
    const weaponId = char.weapon_info.item_id;

    // 等级 → 经验：测试自己按表算一遍期望值（与客户端 UIUtils.GetCharacterAllExp 同语义）
    const expForLevel = (table, key, level) => {
      let sum = 0;
      for (const [, r] of gd.rows(table)) if (Number(r.id) < level) sum += Number(r[key]) || 0;
      return sum;
    };

    // 突破 0 时上限 20：直接要 80 级应被夹到 20
    const clamp = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'set_character_level', character_id: charId, level: 80 },
    ] });
    check(clamp.body.code === 0 && /夹取/.test((clamp.body.data.notes || []).join(' ')),
      `a level above the break cap is clamped (${(clamp.body.data.notes || []).join(' | ')})`);
    doc = store.loadPlayer(id);
    check(doc.characters.find((c) => c.character_id === charId).exp === expForLevel('d_role_level', 'exp', 20),
      'the clamped level 20 was written as the matching exp');

    // 先突破到 5，再设 80 级
    const r = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'set_character_level', character_id: charId, level: 80, break_times: 5 },
      { op: 'set_weapon_stats', item_uuid: weaponUuid, level: 80, break_times: 5, refine_level: 4 },
    ] });
    check(r.body.code === 0 && !r.body.data.error, `level batch applies (${(r.body.data.notes || []).join(' | ')})`);
    doc = store.loadPlayer(id);
    const after = doc.characters.find((c) => c.character_id === charId);
    check(after.exp === expForLevel('d_role_level', 'exp', 80), 'character level 80 written as exp');
    check(after.break_times === 5, 'character break_times updated');
    const wcfg = gd.query('d_bag_item_weapon', weaponId);
    check(after.weapon_info.weapon_info.exp
      === expForLevel('d_weapon_level', `exp${wcfg.rarity}`, 80), 'weapon level 80 written as exp');
    check(after.weapon_info.weapon_info.refine_level === 4, 'weapon 光淬 (refine_level) set to 4');
    check(after.weapon_info.weapon_info.break_times === 5, 'weapon break_times updated');

    // 光淬越界 / 不存在的 uuid
    const badRefine = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'set_weapon_stats', item_uuid: weaponUuid, refine_level: 99 },
    ] });
    check(badRefine.body.code === 0 && /光淬阶数/.test(badRefine.body.data.error || ''),
      'an out-of-range refine level is rejected');
    const badUuid = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'set_weapon_stats', item_uuid: 424242, refine_level: 1 },
    ] });
    check(badUuid.body.code === 0 && /没有 uuid/.test(badUuid.body.data.error || ''),
      'editing an unknown weapon uuid fails cleanly');

    // 背包里的武器（没装备）也能改
    doc = store.loadPlayer(id);
    const bagWeapon = doc.bag.items.find((it) => it.weapon_info && Number(it.item_uuid) !== weaponUuid);
    const bagUuid = Number(bagWeapon.item_uuid);
    const bagRes = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'set_weapon_stats', item_uuid: bagUuid, level: 40, break_times: 1, refine_level: 2 },
    ] });
    check(bagRes.body.code === 0 && !bagRes.body.data.error, 'a bag weapon can be edited too');
    const bagAfter = store.loadPlayer(id).bag.items.find((it) => Number(it.item_uuid) === bagUuid);
    check(bagAfter.weapon_info.refine_level === 2 && bagAfter.weapon_info.break_times === 1
      && bagAfter.weapon_info.exp === expForLevel('d_weapon_level',
        `exp${gd.query('d_bag_item_weapon', bagAfter.item_id).rarity}`, 40),
    'the bag weapon kept its uuid and got the new 光淬/突破/等级');
  }

  // ---------------- 命座（星位之钉）与星位点亮 ----------------
  {
    const id = 1;
    const cat = await API(port, '/editor/api/catalog');
    const salome = cat.body.data.characters.find((c) => c.id === 10201);
    check(salome && salome.inborn_item === 1207002 && salome.talent_total === 23,
      `catalog carries each character's 星位之钉 + talent count（10201 → ${salome && salome.inborn_item}/${salome && salome.talent_total}）`);

    // 单角色发钉：item_id 由 d_character.inbornItem 推出来，调用方只给角色 id
    const r1 = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'grant_constellation', character_id: 10201, count: 7 },
    ] });
    check(r1.body.code === 0 && !r1.body.data.error && /星位之钉/.test((r1.body.data.notes || []).join(' ')),
      `grant_constellation grants the character's nail (${(r1.body.data.notes || []).join(' | ')})`);
    let doc = store.loadPlayer(id);
    const nail = doc.bag.items.find((it) => it.item_id === 1207002);
    check(nail && nail.count === 7, `莎乐美的星位之钉 1207002 ×7 in the bag (${nail && nail.count})`);

    const badChar = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'grant_constellation', character_id: 99999, count: 1 },
    ] });
    check(badChar.body.code === 0 && /星位之钉/.test(badChar.body.data.error || ''),
      'granting a nail for a character without inbornItem fails cleanly');

    // 一键全角色发钉：10 个可玩角色 → 10 种钉
    const r2 = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'grant_all_constellations', count: 2 },
    ] });
    check(r2.body.code === 0 && !r2.body.data.error && /10 种/.test((r2.body.data.notes || []).join(' ')),
      `grant_all_constellations covers all playable characters (${(r2.body.data.notes || []).join(' | ')})`);
    doc = store.loadPlayer(id);
    const nails = doc.bag.items.filter((it) => it.item_id >= 1207001 && it.item_id <= 1207010);
    // 10201 的钉在上一段已经发过 7 把，这里每人再 +2 → 1207002 是 9，其余都是 2
    check(nails.length === 10 && nails.every((it) => it.count === (it.item_id === 1207002 ? 9 : 2)),
      `each of the 10 nails stacked to 2（1207002 为 7+2=9）(${nails.map((n) => `${n.item_id}x${n.count}`).join(',')})`);

    // 直接点亮该角色全部星位（跳过消耗与等级）
    const r3 = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'unlock_all_talents', character_id: 10201 },
    ] });
    check(r3.body.code === 0 && !r3.body.data.error && /点亮星位 23 个/.test((r3.body.data.notes || []).join(' ')),
      `unlock_all_talents lights every star position (${(r3.body.data.notes || []).join(' | ')})`);
    doc = store.loadPlayer(id);
    const salomeChar = doc.characters.find((c) => c.character_id === 10201);
    check(Array.isArray(salomeChar.talent_ids) && salomeChar.talent_ids.length === 23,
      `10201 has 23 talent_ids persisted (${salomeChar.talent_ids.length})`);
    check(salomeChar.talent_ids.includes(1020101) && salomeChar.talent_ids.includes(1020123),
      'the persisted list covers the root and the last star position');

    // 幂等 + 全角色版本
    const r4 = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'unlock_all_talents', character_id: 10201 },
    ] });
    check(/都已点亮/.test((r4.body.data.notes || []).join(' ')), 'unlocking twice is a no-op');
    const r5 = await post(port, `/editor/api/player/${id}/update`, { ops: [{ op: 'unlock_all_talents' }] });
    check(r5.body.code === 0 && !r5.body.data.error, `unlock_all_talents without a character works (${(r5.body.data.notes || []).join(' | ')})`);
    doc = store.loadPlayer(id);
    check(doc.characters.every((c) => (c.talent_ids || []).length === 23),
      'every owned character ends up with all 23 star positions');
    // 重新登录下发的一定是磁盘这份（res_character_list 原样带 characters），所以钉没被白扣
    check(store.loadPlayer(id).bag.items.find((it) => it.item_id === 1207002).count === 9,
      '直接点亮不消耗星位之钉（仍是 7+2 把）');
  }

  // ---------------- 角色精细化：逐孔星位 / 逐件皮肤 / 穿戴 / 技能 / 机甲 ----------------
  {
    const id = 1;
    const cat = await API(port, '/editor/api/catalog');
    const data = cat.body.data;
    const yu = data.characters.find((c) => c.id === 10201);
    check(Array.isArray(yu.talents) && yu.talents.length === 23 && yu.talents[0].hole === 1
      && yu.talents[0].need_kind === 'level' && yu.talents[0].need_value === 1,
    `catalog carries per-hole talent details（${yu.talents.length} 孔，首孔 ${yu.talents[0].need_kind}=${yu.talents[0].need_value}）`);
    check(yu.skins && yu.skins[1].filter((s) => s.default).length === 1
      && yu.skins[2].filter((s) => s.default).length === 1 && yu.skins[3].length > 0,
    `catalog carries the skin groups with exactly one default per class（${yu.skins[1].length}/${yu.skins[2].length}/${yu.skins[3].length}）`);
    check(Array.isArray(yu.skills) && yu.skills.length > 0 && yu.skills.some((s) => s.max_level > 0),
      `catalog carries the skill list with max levels（${yu.skills.length} 条，最大 ${Math.max(...yu.skills.map((s) => s.max_level))}）`);
    check(Array.isArray(data.equips) && data.equips.length === 60
      && data.equips.every((e) => e.slot >= 1 && e.slot <= 6 && e.name),
    `catalog carries all 60 机甲 with their six slots`);

    const readChar = () => store.loadPlayer(id).characters.find((c) => c.character_id === 10201);
    const root = yu.talents[0].id;
    const second = yu.talents[1].id;

    // 逐孔点亮：只留前两个（重复项要去重、顺序按孔位）
    const r1 = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'set_talents', character_id: 10201, talent_ids: [second, root, second] },
    ] });
    check(r1.body.code === 0 && !r1.body.data.error && /2\/23/.test((r1.body.data.notes || []).join(' ')),
      `set_talents lights exactly the listed holes（${(r1.body.data.notes || []).join(' | ')}）`);
    let ch = readChar();
    check(ch.talent_ids.length === 2 && ch.talent_ids[0] === root && ch.talent_ids[1] === second,
      `talent_ids are deduped and sorted by hole（${ch.talent_ids.join(',')}）`);

    // 别的角色的星位 id 必须被拒
    const badTal = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'set_talents', character_id: 10201, talent_ids: [1070101] },
    ] });
    check(badTal.body.code === 0 && /不属于角色/.test(badTal.body.data.error || ''),
      'set_talents rejects a talent that belongs to another character');
    check(readChar().talent_ids.length === 2, 'the rejected batch left the previous selection intact');

    // 皮肤：只勾一件非默认 → 默认皮肤必须被自动并回来
    const def1 = yu.skins[1].find((s) => s.default).id;
    const extra = yu.skins[1].find((s) => !s.default).id;
    const r2 = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'set_skins', character_id: 10201, dress_type: 1, skin_ids: [extra] },
    ] });
    check(r2.body.code === 0 && !r2.body.data.error && /2 件/.test((r2.body.data.notes || []).join(' ')),
      `set_skins writes the listed skins（${(r2.body.data.notes || []).join(' | ')}）`);
    ch = readChar();
    check(ch.own_character_skin_ids.length === 2
      && ch.own_character_skin_ids.includes(def1) && ch.own_character_skin_ids.includes(extra),
    `the default skin is forced back into the unlock list（${ch.own_character_skin_ids.join(',')}）`);

    const r3 = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'set_skins', character_id: 10201, dress_type: 1, skin_ids: [] },
    ] });
    check(r3.body.code === 0 && readChar().own_character_skin_ids.length === 1
      && readChar().own_character_skin_ids[0] === def1,
    'an empty skin list collapses to just the default');

    const badSkin = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'set_skins', character_id: 10201, dress_type: 2, skin_ids: [extra] },
    ] });
    check(badSkin.body.code === 0 && /不属于角色/.test(badSkin.body.data.error || ''),
      'set_skins rejects a skin from the wrong class');

    // 穿戴：未解锁的皮肤会自动补进解锁列表；0 = 恢复默认
    const r4 = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'set_worn_skin', character_id: 10201, dress_type: 1, skin_id: extra },
    ] });
    ch = readChar();
    check(r4.body.code === 0 && !r4.body.data.error && ch.character_skin_id === extra
      && ch.own_character_skin_ids.includes(extra),
    `set_worn_skin equips and auto-unlocks（character_skin_id=${ch.character_skin_id}）`);
    const r5 = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'set_worn_skin', character_id: 10201, dress_type: 1, skin_id: 0 },
    ] });
    check(r5.body.code === 0 && readChar().character_skin_id === 0, 'wearing 0 falls back to the default skin');

    // 技能：等级夹到 d_skill_fight_level 的上限
    const sk = yu.skills.find((s) => s.max_level > 0);
    const r6 = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'set_character_skills', character_id: 10201, skills: [{ skill_id: sk.id, skill_level: 9999 }] },
    ] });
    ch = readChar();
    const info = (ch.skill_infos || []).find((s) => Number(s.skill_id) === sk.id);
    check(r6.body.code === 0 && !r6.body.data.error && info && info.skill_level === sk.max_level
      && /夹到上限/.test((r6.body.data.notes || []).join(' ')),
    `set_character_skills clamps to the table max（${sk.id} → ${info && info.skill_level}/${sk.max_level}）`);
    const badSkill = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'set_character_skills', character_id: 10201, skills: [{ skill_id: 99999, skill_level: 2 }] },
    ] });
    check(badSkill.body.code === 0 && /不属于角色/.test(badSkill.body.data.error || ''),
      'set_character_skills rejects a skill that belongs to another character');

    // 机甲：发放 → 装备（同槽位换装）→ 卸下
    const slot1 = data.equips.filter((e) => e.slot === 1);
    const armA = slot1[0].id;
    const armB = slot1[1].id;
    await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'add_item', item_id: armA, count: 1 },
      { op: 'add_item', item_id: armB, count: 1 },
    ] });
    let doc = store.loadPlayer(id);
    const findArm = (itemId) => doc.bag.items.find((it) => Number(it.item_id) === Number(itemId));
    const uuidA = findArm(armA).item_uuid;
    const uuidB = findArm(armB).item_uuid;
    check(findArm(armA).arm_info && typeof findArm(armA).arm_info.break_times === 'number',
      'a granted 机甲 carries arm_info (客户端要靠它显示属性)');

    const r7 = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'equip_arm', character_id: 10201, item_uuid: uuidA },
    ] });
    doc = store.loadPlayer(id);
    ch = doc.characters.find((c) => c.character_id === 10201);
    check(r7.body.code === 0 && !r7.body.data.error && ch.arm_infos.length === 1
      && Number(ch.arm_infos[0].item_uuid) === Number(uuidA)
      && !doc.bag.items.some((it) => Number(it.item_uuid) === Number(uuidA)),
    `equip_arm moves the 机甲 from the bag onto the character（${(r7.body.data.notes || []).join(' | ')}）`);

    // 同槽位换装：旧件回背包，身上仍然只挂一件
    const r8 = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'equip_arm', character_id: 10201, item_uuid: uuidB },
    ] });
    doc = store.loadPlayer(id);
    ch = doc.characters.find((c) => c.character_id === 10201);
    check(r8.body.code === 0 && ch.arm_infos.length === 1
      && Number(ch.arm_infos[0].item_uuid) === Number(uuidB)
      && doc.bag.items.some((it) => Number(it.item_uuid) === Number(uuidA)),
    'equipping another 机甲 of the same slot sends the old one back to the bag');

    const r9 = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'unequip_arm', character_id: 10201, item_uuid: uuidB },
    ] });
    doc = store.loadPlayer(id);
    ch = doc.characters.find((c) => c.character_id === 10201);
    check(r9.body.code === 0 && ch.arm_infos.length === 0
      && doc.bag.items.some((it) => Number(it.item_uuid) === Number(uuidB)),
    'unequip_arm puts the 机甲 back into the bag');

    const stackUuid = doc.bag.items.find((it) => it.item_id === 9001).item_uuid;
    const notArm = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'equip_arm', character_id: 10201, item_uuid: stackUuid },
    ] });
    check(notArm.body.code === 0 && /不是机甲/.test(notArm.body.data.error || ''),
      'equip_arm refuses a bag entry that is not a 机甲');
    const ghostArm = await post(port, `/editor/api/player/${id}/update`, { ops: [
      { op: 'unequip_arm', character_id: 10201, item_uuid: 987654 },
    ] });
    check(ghostArm.body.code === 0 && /没有 uuid=987654 的机甲/.test(ghostArm.body.data.error || ''),
      'unequip_arm reports a missing 机甲 cleanly');
  }

  // ---------------- export 接口 ----------------
  {
    const r1 = await post(port, '/editor/api/export', {});
    check(r1.body.code === 0 && /data_export_/.test(r1.body.data.dir),
      `export without a path lands in the default backup location (${r1.body.data && r1.body.data.dir})`);

    const dest = path.join(tmpRoot, 'editor-export');
    const r2 = await post(port, '/editor/api/export', { path: dest });
    check(r2.body.code === 0 && fs.existsSync(path.join(dest, 'accounts.json')),
      'export with a path writes accounts.json there');
    check(fs.readdirSync(path.join(dest, 'players')).length === store.dataStats().players,
      'export with a path copies every player doc');

    const r3 = await post(port, '/editor/api/export', { path: tmpDataDir });
    check(r3.body.code === 1, 'exporting onto the live data dir is rejected');

    const backups = await API(port, '/editor/api/backups');
    check(backups.body.code === 0 && backups.body.data.backups.some((b) => b.name.startsWith('data_export_')),
      'backups lists the snapshot created by the bare export');
  }

  // ---------------- 服务端管理（服务页） ----------------
  {
    // 前面的导出接口也走维护窗口，所以这里只比较增量
    const maintBefore = hookCalls.maintenance;
    const srv = await API(port, '/editor/api/server');
    const d = srv.body.data;
    check(d.version && d.uptime_seconds >= 4 && d.tcp_port === 8101 && d.http_port === 9089,
      `server info carries version/ports/uptime (v${d.version}, ${d.uptime_seconds}s)`);
    check(d.can_stop === true && d.unreleased_weapons === 10,
      'server info reports the stop hook and the unreleased-weapon count');
    check(d.repo_url === require('../package.json').homepage
      && /^https:\/\/github\.com\//.test(d.repo_url),
    `server info carries the project homepage for the editor footer (${d.repo_url})`);

    const kick = await post(port, '/editor/api/server/kick', {});
    check(kick.body.code === 0 && kick.body.data.kicked === 0, 'kick with no live sessions reports 0');

    const backup = await post(port, '/editor/api/server/backup', {});
    check(backup.body.code === 0 && /data_manual_/.test(backup.body.data.dir || ''),
      `manual backup lands in a data_manual_* snapshot (${backup.body.data && backup.body.data.dir})`);

    // 危险操作必须带确认串
    const noConfirm = await post(port, '/editor/api/server/restore', {});
    check(noConfirm.body.code === 1 && /confirm/.test(noConfirm.body.msg),
      'restore without the confirm string is rejected');
    const wrongLoad = await post(port, '/editor/api/server/load', { path: path.join(tmpRoot, 'nope') });
    check(wrongLoad.body.code === 1 && /accounts\.json/.test(wrongLoad.body.msg),
      'load from a directory without accounts.json is rejected');
    check(hookCalls.maintenance === maintBefore, 'a rejected maintenance action never opens the maintenance window');

    // 停服：先回响应，再调 onStop
    const stop = await post(port, '/editor/api/server/stop', {});
    check(stop.body.code === 0 && stop.body.data.stopping === true, 'stop answers {stopping:true} first');
    await new Promise((r) => setTimeout(r, 400));
    check(hookCalls.stop === 1, 'stop then invokes the injected onStop hook exactly once');

    // 清档 → 从导出的备份导回来
    const playersBefore = store.dataStats().players;
    const restore = await post(port, '/editor/api/server/restore', { confirm: '清空存档' });
    check(restore.body.code === 0 && restore.body.data.after.players === 0
      && restore.body.data.after.accounts === 0,
    `restore wipes every account/player (was ${playersBefore})`);
    check(hookCalls.maintenance === maintBefore + 1, 'restore runs inside the maintenance window');
    check(store.dataStats().players === 0, 'the wipe really hit the disk');

    const reload = await post(port, '/editor/api/server/load', { path: path.join(tmpRoot, 'editor-export') });
    check(reload.body.code === 0 && reload.body.data.players === playersBefore,
      `load imports the backup back (${reload.body.data && reload.body.data.players} docs)`);
    check(hookCalls.maintenance === maintBefore + 2, 'load runs inside the maintenance window');
    check(store.dataStats().players === playersBefore && store.dataStats().accounts === playersBefore,
      'the imported save is on disk again');
  }

  // ---------------- 服务器控制台（日志缓冲 / SSE / 网页指令） ----------------
  {
    // tail：缓冲行 seq 严格递增，裸 console.log 也被捕获，游标之后无重复
    const before = await API(port, '/editor/api/console/tail?after=0');
    check(before.body.code === 0 && Array.isArray(before.body.data.lines)
      && before.body.data.lines.length > 0, 'tail returns buffered log lines');
    const lines = before.body.data.lines;
    check(lines.every((l, i) => i === 0 || l.seq > lines[i - 1].seq),
      'buffered lines carry strictly increasing seq numbers');

    const marker = `console-check-tail-${Date.now()}`;
    console.log(marker); // 裸 console 输出（不走 log.*）也要进缓冲
    const after0 = await API(port, '/editor/api/console/tail?after=0');
    check(after0.body.data.lines.some((l) => l.text.includes(marker)),
      'bare console.log output is captured into the buffer');

    const cursor = after0.body.data.last;
    // 注意：check() 自己也走 console.log（同样被捕获进缓冲），所以两次 fetch 之间
    // 一定会有新的 PASS 行——不能断言「游标后没有新行」，只能断言旧行不重放。
    const atCursor = await API(port, `/editor/api/console/tail?after=${cursor}`);
    check(!atCursor.body.data.lines.some((l) => l.text.includes(marker)),
      'tail after the cursor never replays earlier lines');
    const markerB = `console-check-tailb-${Date.now()}`;
    console.log(markerB);
    const pastCursor = await API(port, `/editor/api/console/tail?after=${cursor}`);
    check(pastCursor.body.data.lines.some((l) => l.text.includes(markerB))
      && !pastCursor.body.data.lines.some((l) => l.text.includes(marker)),
      'a line written after the cursor is returned exactly once');

    // 客户端的轮询端点（marquee/notice/serverStatus）不再进 info：实测它能占掉日志的
    // 1/16（283 条），可人工排查时毫无信息量。明细留给 GHS_VERBOSE=1；未知端点仍 warn。
    const pollBefore = await API(port, '/editor/api/console/tail?after=0');
    const pollCursor = pollBefore.body.data.last;
    const poll = await post(port, '/client/marquee/list', {});
    const pollAfter = await API(port, `/editor/api/console/tail?after=${pollCursor}`);
    check(!pollAfter.body.data.lines.some((l) => /\[http\] POST \/client\/marquee\/list/.test(l.text)),
      'client polling no longer writes an [http] access line into the log');
    check(poll.status === 200, 'the polling endpoint itself still answers normally');

    // SSE：首块是 retry 提示，开流前的日志行会重放，随后 marker 实时到达
    const sseMarker = `console-check-sse-${Date.now()}`;
    console.log(sseMarker);
    const ctrl = new AbortController();
    const sse = await fetch(`http://127.0.0.1:${port}/editor/api/console/stream?after=0`, { signal: ctrl.signal });
    check(sse.status === 200 && sse.headers.get('content-type').includes('text/event-stream'),
      'the SSE endpoint responds as text/event-stream');
    const reader = sse.body.getReader();
    let acc = '';
    let chunk = await reader.read();
    check(chunk.value && Buffer.from(chunk.value).toString('utf8').startsWith('retry:'),
      'the stream starts with a retry hint');
    acc = Buffer.from(chunk.value).toString('utf8');
    for (let i = 0; i < 50 && !acc.includes(sseMarker); i += 1) {
      chunk = await reader.read();
      if (chunk.done) break;
      acc += Buffer.from(chunk.value).toString('utf8');
    }
    check(acc.includes(sseMarker), 'log lines written before (and during) the stream arrive as data events');
    ctrl.abort();
  }

  // ---------------- 控制台指令（网页端 = 黑窗口同口径） ----------------
  {
    const playersNow = store.dataStats().players;
    const maintNow = hookCalls.maintenance;

    const status = await post(port, '/editor/api/console/cmd', { command: 'status' });
    check(status.body.code === 0 && /在线连接/.test(status.body.data.reply),
      'cmd status replies with online/save counts');
    const help = await post(port, '/editor/api/console/cmd', { command: 'help' });
    check(help.body.code === 0 && /restore/.test(help.body.data.reply), 'cmd help lists the commands');
    const unknown = await post(port, '/editor/api/console/cmd', { command: 'nonsense now' });
    check(unknown.body.code === 0 && /未知指令/.test(unknown.body.data.reply),
      'an unknown command comes back as a reply, not an error');
    const empty = await post(port, '/editor/api/console/cmd', { command: '   ' });
    check(empty.body.code === 1, 'an empty command is rejected');
    check(hookCalls.maintenance === maintNow, 'read-only commands never open the maintenance window');

    // 危险指令走维护窗口（与 stdin 控制台一致），restore 会再清一次档、load 再导回来
    const restore = await post(port, '/editor/api/console/cmd', { command: 'restore' });
    check(restore.body.code === 0 && /存档已全部清空/.test(restore.body.data.reply),
      'cmd restore wipes the save and says so in the reply');
    check(hookCalls.maintenance === maintNow + 1, 'cmd restore runs inside the maintenance window');
    const reload = await post(port, '/editor/api/console/cmd', { command: `load ${path.join(tmpRoot, 'editor-export')}` });
    check(reload.body.code === 0 && /已从/.test(reload.body.data.reply),
      'cmd load imports the backup back');
    check(hookCalls.maintenance === maintNow + 2, 'cmd load runs inside the maintenance window');
    check(store.dataStats().players === playersNow, 'the save is back on disk after cmd restore/load');

    // stop：先回响应（action=stop），再触发 onStop
    const stopBefore = hookCalls.stop;
    const stop = await post(port, '/editor/api/console/cmd', { command: 'stop' });
    check(stop.body.code === 0 && stop.body.data.action === 'stop', 'cmd stop answers action=stop first');
    await new Promise((r) => setTimeout(r, 400));
    check(hookCalls.stop === stopBefore + 1, 'cmd stop then invokes the onStop hook exactly once');
  }

  gate.close();
  fs.rmSync(tmpRoot, { recursive: true, force: true });
  console.log(failures === 0 ? '\nEDITOR CHECKS PASSED' : `\n${failures} EDITOR CHECKS FAILED`);
  process.exit(failures === 0 ? 0 : 1);
})().catch((err) => {
  console.error(err.stack || err.message);
  process.exit(1);
});
