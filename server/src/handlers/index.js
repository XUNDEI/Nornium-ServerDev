// Central message dispatcher: name -> handler(session, reqMsg).
// Unknown req_* get an empty res_* (when one exists) so the client's
// serial-wait queue never stalls.
const log = require('../logger');
const login = require('./login');
const sync = require('./sync');
const character = require('./character');
const social = require('./social');   // plot / mail / activity / misc / daily copy
const furnace = require('./furnace'); // 炼金合成 / 分解 / 锻造
const { handle: universeHandle } = require('./universe');
const { handle: gachaHandle } = require('./gacha');
const { handle: shopHandle } = require('./shop');
const { handle: mallHandle } = require('./mall');
const protos = require('../protos');

const handlers = {
  // gate
  req_register: login.register,
  req_login: login.login,
  req_relogin: login.relogin,
  req_ping: sync.reqPing,

  // initial sync
  req_player: sync.reqPlayer,
  req_bag: sync.reqBag,
  req_home: sync.reqHome,
  req_universe: sync.reqUniverse,
  req_total_war: sync.reqTotalWar,
  req_shop_list: sync.reqShopList,
  req_mall_list: sync.reqMallList,
  req_hard_level: sync.reqHardLevel,
  req_character_list: sync.reqCharacterList,
  req_plot: sync.reqPlot,
  req_activity_list: sync.reqActivityList,
  req_gacha: sync.reqGacha,
  req_mail_list: sync.reqMailList,

  // character / bag ops
  req_character_level_up: character.reqCharacterLevelUp,
  req_character_level_break: character.reqCharacterLevelBreak,
  req_character_skill_level_up: character.reqCharacterSkillLevelUp,
  req_character_equip_weapon: character.reqCharacterEquipWeapon,
  req_character_swap_weapon: character.reqCharacterSwapWeapon,
  req_character_equip_arm: character.reqCharacterEquipArm,
  req_character_unequip_arm: character.reqCharacterUnequipArm,
  req_character_swap_arm: character.reqCharacterSwapArm,
  req_character_change_skin: character.reqCharacterChangeSkin,
  req_use_item: character.reqUseItem,
  req_item_lock: (s, r) => character.reqItemLock(s, r, false),
  req_item_unlock: (s, r) => character.reqItemLock(s, r, true),
  req_weapon_level_up: character.reqWeaponLevelUp,
  req_weapon_level_break: character.reqWeaponLevelBreak,
  req_weapon_refine: character.reqWeaponRefine,
  req_arm_level_up: character.reqArmLevelUp,
  req_arm_level_break: character.reqArmLevelBreak,

  // furnace (炼金合成 / 分解 / 锻造)
  req_item_synthetic: furnace.reqItemSynthetic,
  req_item_decompose: furnace.reqItemDecompose,
  req_arm_forge: furnace.reqArmForge,
};

async function dispatch(session, name, msg) {
  log.info(`[recv] ${name}`);
  log.verbose('[recv payload]', msg || {});
  try {
    const h = handlers[name] || universeHandle(name) || gachaHandle(name)
      || shopHandle(name) || mallHandle(name) || social.handle(name);
    if (h) {
      await h(session, msg || {});
      return;
    }
    if (name.startsWith('req_')) {
      const resName = `res_${name.slice(4)}`;
      if (protos.allFieldNames().includes(resName)) {
        log.warn(`[dispatch] no handler for ${name}, replying empty ${resName}`);
        session.send(resName, {});
        return;
      }
      log.warn(`[dispatch] no handler for ${name} (no ${resName} either) — ignored`);
      return;
    }
    log.warn(`[dispatch] unexpected message ${name}`);
  } catch (err) {
    log.error(`[dispatch] handler ${name} threw:`, err.stack || err.message);
  }
}

// Periodic per-session tick (session.js calls this every 60s). Used for things
// that must happen at a wall-clock boundary while the player stays online —
// currently the 04:00 daily 危航许可 grant, which the client would otherwise
// only pick up on the next login/relogin. Idempotent.
function dailyTick(session) {
  if (!session.player) return;
  const ntf = require('../game/daily').grantDailyPermits(session.player);
  if (!ntf) return;
  session.send('ntf_item_info', ntf);
  sync.savePlayer(session);
}

module.exports = { dispatch, dailyTick };
