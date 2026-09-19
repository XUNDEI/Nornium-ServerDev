// M0: register / login / relogin.
const store = require('../store');
const playerNew = require('../game/player_new');
const daily = require('../game/daily');
const log = require('../logger');

// account_id -> Session (single-login enforcement)
const onlineAccounts = new Map();

function bindOnline(session) {
  const prev = onlineAccounts.get(session.account.account_id);
  if (prev && prev !== session && !prev.closed) {
    log.info(`[login] kicking replaced session of account ${session.account.account_id}`);
    prev.kick(1); // REPLACE
  }
  onlineAccounts.set(session.account.account_id, session);
  session.onCloseHook = (() => {
    const prevHook = session.onCloseHook;
    return () => {
      if (onlineAccounts.get(session.account.account_id) === session) {
        onlineAccounts.delete(session.account.account_id);
      }
      if (prevHook) prevHook();
    };
  })();
}

function register(session, req) {
  const name = req?.account_name ?? '';
  const password = req?.password ?? '';
  if (!name || !password) {
    session.send('res_register', {}, 4); // ACCOUNT_NAME_ILLEGAL
    return;
  }
  if (store.findAccount(name)) {
    session.send('res_register', {}, 6); // ACCOUNT_NAME_EXISTS
    return;
  }
  const rec = store.createAccount(name, password);
  const doc = playerNew.createPlayerDoc(rec.account_id);
  store.savePlayer(doc);
  log.info(`[register] account "${name}" -> id ${rec.account_id}`);
  session.send('res_register', {});
  // Client auto-fires req_login afterwards.
}

function login(session, req) {
  const name = req?.account_name ?? '';
  const password = req?.password ?? '';
  const rec = store.findAccount(name);
  if (!rec) {
    session.send('res_login', {}, 3); // NO_ACCOUNT
    return;
  }
  if (rec.password !== password) {
    session.send('res_login', {}, 4); // PASSWORD_NOT_MATCH
    return;
  }
  session.account = rec;
  session.player = store.loadPlayer(rec.account_id) || playerNew.createPlayerDoc(rec.account_id);
  // 每天 04:00 的危航许可在这里补发：必须发生在客户端发起初始背包同步之前，
  // 这样玩家一进游戏就能直接看到许可数量（否则首次领取会看不到）。
  daily.grantDailyPermits(session.player);
  store.savePlayer(session.player);
  bindOnline(session);
  log.info(`[login] account "${name}" ok (player ${rec.account_id})`);
  session.send('res_login', {
    account_id: String(rec.account_id),
    key: rec.key,
  });
}

function relogin(session, req) {
  const accountId = Number(req?.account_id ?? 0);
  const key = req?.key ?? '';
  const rec = Object.values(store.loadAccounts().by_name)
    .find((r) => r.account_id === accountId) ?? null;
  if (!rec || rec.key !== key) {
    session.send('res_relogin', {}, 2); // KEY_ERROR
    return;
  }
  session.account = rec;
  session.player = store.loadPlayer(rec.account_id) || playerNew.createPlayerDoc(rec.account_id);
  daily.grantDailyPermits(session.player);
  store.savePlayer(session.player);
  bindOnline(session);
  session.send('res_relogin', {});
}

module.exports = { register, login, relogin, onlineAccounts };
