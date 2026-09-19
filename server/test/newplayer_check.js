// In-process regression checks for the new-player starter kit (初始资源 + 邮件).
//
// Regression target: the private server's resource economy is unfinished, so a
// new account must never be blocked by materials. The starter bag is hand-tuned
// against a long-lived playtester save, and the mailbox carries both a bundle
// and the "this project is free and open source" anti-scam notice. These checks
// pin the numbers and, more importantly, the two client-side traps:
//
//   1. 危航许可 (1201003) must NOT be seeded — officially it is granted 6/day on
//      login (daily.grantDailyPermits ← login.js), and daily_check.js asserts a
//      fresh account starts at 0.
//   2. Mail text goes through MailModel's format() on the client, where `@` is an
//      escape prefix (@n = newline). A stray `@` silently mangles the notice.
//
// No server needed. Must run before requiring the server modules: store.js reads
// GHS_DATA_DIR at load time so the saves stay out of the real data/ dir.
const os = require('os');
const fs = require('fs');
const path = require('path');
const tmpDataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ghs-newplayer-'));
process.env.GHS_DATA_DIR = tmpDataDir;

const { createPlayerDoc } = require('../src/game/player_new');
const items = require('../src/game/items');
const daily = require('../src/game/daily');
const gd = require('../src/gamedata');
const social = require('../src/handlers/social');

let failures = 0;
function check(cond, msg) {
  console.log(cond ? `  PASS ${msg}` : `  FAIL ${msg}`);
  if (!cond) failures += 1;
}

function makeSession(accountId) {
  const player = createPlayerDoc(accountId);
  const sent = [];
  return {
    player,
    sent,
    send: (name, msg, result) => sent.push({ name, msg, result }),
  };
}
const last = (s, name) => [...s.sent].reverse().find((x) => x.name === name);
const countOf = (s, itemId) => items.bagCount(s.player, itemId);

// Replica of the client's MailModel.format() (reference/client_lua/Module/Mail/
// MailModel.lua) — the authority for how mail strings are interpreted.
const QUOTE_CHARS = { '@': '@', s: ' ', n: '\n' };
function clientFormat(str) {
  let res = '';
  let escaped = false;
  for (const ch of String(str)) {
    if (escaped) {
      res += QUOTE_CHARS[ch] !== undefined ? QUOTE_CHARS[ch] : `@${ch}`;
      escaped = false;
    } else if (ch === '@') {
      escaped = true;
    } else {
      res += ch;
    }
  }
  return escaped ? `${res}@` : res;
}

// ---------------- starter bag: currencies ----------------
{
  const s = makeSession(9401);
  // 对照的是 2026-09 的长期实测存档；这里只卡下限，允许以后继续放宽。
  const floor = [
    [items.CURRENCY.GOLD, 1000000, 'gold (金星贝)'],
    [items.CURRENCY.DIAMOND, 100000, 'diamonds (诺伦炬)'],
    [items.CURRENCY.LENS, 100000, 'lenses (诺伦透镜)'],
    [items.CURRENCY.FURNITURE_COIN, 10000, 'furniture coins (王宫点数)'],
    [items.CURRENCY.EXP, 11600, 'player exp (游历经验 → ~Lv.13)'],
    [1200001, 100, 'limited gacha tickets (诺伦机票)'],
    [1200002, 200, 'standard gacha tickets (都城机票)'],
    [1201001, 99, 'sweep tickets (杀手朋友券)'],
  ];
  for (const [id, min, label] of floor) {
    check(countOf(s, id) >= min, `a fresh account carries >= ${min} ${label} (got ${countOf(s, id)})`);
  }
  // 玩家等级：累计经验 10690 起就是 Lv.13（d_player_level），实测存档同水位
  check(items.bagCount(s.player, items.CURRENCY.EXP) >= 10690,
    'the starter exp is enough for level 13 (cumulative threshold 10690)');
}

// ---------------- starter bag: materials ----------------
{
  const s = makeSession(9402);
  // 角色/武器双双拉满所需的全部突破材料，一张都不能少，否则会卡等级上限。
  const mats = new Map();
  for (const table of ['d_role_levelbreak', 'd_weapon_levelbreak']) {
    for (const [, r] of gd.rows(table)) {
      const flat = r.material || [];
      for (let i = 0; i + 1 < flat.length; i += 2) mats.set(flat[i], true);
    }
  }
  mats.delete(items.CURRENCY.GOLD); // 金币已在上面单独断言
  const missing = [...mats.keys()].filter((id) => countOf(s, id) < 300);
  check(missing.length === 0,
    `all ${mats.size} levelbreak materials are seeded (>=300) (missing: ${missing.join(',') || 'none'})`);

  for (const [id, label] of [[1203001, '角色经验'], [1204001, '武器经验']]) {
    check(countOf(s, id) >= 500, `a fresh account can raise ${label} (>= 500 of ${id})`);
  }
  // 家具：主线「放置家具」任务要求背包里先有该家具
  const furniture = gd.rows('d_bag_item_furniture');
  const missingFurniture = furniture.filter(([, r]) => countOf(s, r.id) < 1);
  check(missingFurniture.length === 0,
    `all ${furniture.length} furniture items are in the bag for the plot task`);
}

// ---------------- 危航许可 must stay unseeded ----------------
{
  const s = makeSession(9403);
  check(countOf(s, daily.TICKET) === 0,
    `a fresh account starts with 0 危航许可 (got ${countOf(s, daily.TICKET)}) — it is granted at login`);
}

// ---------------- mailbox: bundle + free/open-source notice ----------------
{
  const s = makeSession(9404);
  const mails = s.player.mail.list;
  check(mails.length === 2, `a fresh account has exactly 2 mails (got ${mails.length})`);

  const bundle = mails.find((m) => m.mail_uuid === 1001);
  check(!!bundle && Array.isArray(bundle.item_infos) && bundle.item_infos.length > 0,
    'the welcome mail carries a claimable bundle');
  check(!!bundle && bundle.mail_state === 0, 'the welcome mail starts unread');

  const notice = mails.find((m) => m.mail_uuid === 1002);
  check(!!notice && /开源/.test(notice.title) && /免费/.test(notice.title),
    'the notice mail title says it is free and open source');
  check(!!notice && /被骗/.test(notice.content) && /退款/.test(notice.content),
    'the notice tells paying victims to get a refund');
  check(!!notice && Array.isArray(notice.item_infos) && notice.item_infos.length === 0,
    'the notice mail has no attachment (the client then hides the claim button)');
  // 客户端按 send_seconds 倒序排，欢迎邮件要在最上面
  check(!!notice && Number(bundle.send_seconds) > Number(notice.send_seconds),
    'the welcome mail sorts above the notice (newest first)');

  // mail_uuid 必须互不相同，否则客户端 GetMailByUUID 取错信
  const uuids = mails.map((m) => Number(m.mail_uuid));
  check(new Set(uuids).size === uuids.length, 'mail uuids are unique');
  check(s.player.mail.next_uuid > Math.max(...uuids),
    'mail.next_uuid stays clear of the seeded uuids');

  // 客户端 MailModel 的转义预案：正文里除了 @n/@s/@@ 不能有裸 @
  for (const m of mails) {
    for (const [field, value] of [['title', m.title], ['content', m.content], ['type', m.type]]) {
      const stripped = String(value).replace(/@[ns@]/g, '');
      check(!stripped.includes('@'),
        `mail ${m.mail_uuid} ${field} has no unescaped @ left for the client parser`);
      check(!/@$/.test(String(value)),
        `mail ${m.mail_uuid} ${field} does not end with a dangling @`);
    }
    check(clientFormat(m.content).includes('\n'),
      `mail ${m.mail_uuid} content really renders line breaks through @n`);
    check(!clientFormat(m.content).includes('@'),
      `mail ${m.mail_uuid} content survives the client format() with no leftover @`);
  }
}

// ---------------- claiming the bundle ----------------
{
  const s = makeSession(9405);
  const before = s.player.mail.list.find((m) => m.mail_uuid === 1001).mail_state;
  const mail = s.player.mail.list.find((m) => m.mail_uuid === 1001);
  const goldBefore = countOf(s, items.CURRENCY.GOLD);

  social.handle('req_mail_read')(s, { mail_uuid: 1001 });
  check(mail.mail_state === 1, 'req_mail_read marks the mail READ (0 -> 1)');

  social.handle('req_mail_receive')(s, { mail_uuid: 1001 });
  check(mail.mail_state === 2, 'req_mail_receive marks the mail RECEIVED (1 -> 2)');
  check(!!last(s, 'ntf_item_info'), 'claiming pushes ntf_item_info so the client shows the reward');
  check(countOf(s, items.CURRENCY.GOLD) > goldBefore,
    'claiming really adds the bundled items to the bag');

  social.handle('req_mail_receive')(s, { mail_uuid: 1001 });
  check(last(s, 'res_mail_receive').result === 2,
    'claiming twice answers MAIL_STATE_INVALID (2) without granting again');
  check(before === 0, 'the bundle mail was unread before the test touched it');

  // 无附件的声明邮件：领取应报 NO_ITEMS(3)，而不是悄悄发空气
  social.handle('req_mail_receive')(s, { mail_uuid: 1002 });
  check(last(s, 'res_mail_receive').result === 3,
    'claiming the attachment-free notice answers NO_ITEMS (3)');

  social.handle('req_mail_read')(s, { mail_uuid: 999999 });
  check(last(s, 'res_mail_read').result === 1, 'reading an unknown mail answers NO_MAIL (1)');
}

fs.rmSync(tmpDataDir, { recursive: true, force: true });
console.log(failures === 0 ? '\nNEW PLAYER CHECKS PASSED' : `\n${failures} NEW PLAYER CHECKS FAILED`);
process.exit(failures === 0 ? 0 : 1);
