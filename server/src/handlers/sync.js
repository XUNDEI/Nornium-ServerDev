// M1: the 13 initial-data responses fired after res_login.
// Order matters: bag must be N x ntf_bag_info BEFORE res_bag (BackpackSystem
// accumulates NtfBagInfo until res_bag arrives); req_mail_list must be the
// last response (client uses it as "initial load done" marker — guaranteed by
// FIFO processing of the client's request order).
const gd = require('../gamedata');

function requirePlayer(session) {
  if (!session.player) {
    // Not logged in on this connection — satisfy with an error result so the
    // client doesn't hang; normally unreachable because login gates the flow.
    return false;
  }
  return true;
}

function savePlayer(session) {
  require('../store').savePlayer(session.player);
}

function reqPlayer(session) {
  if (!requirePlayer(session)) return;
  session.send('res_player', { player_info: session.player.player });
}

function reqBag(session) {
  if (!requirePlayer(session)) return;
  const items = session.player.bag.items;
  // chunk into groups of 40 entries per ntf to keep frames modest
  for (let i = 0; i < items.length; i += 40) {
    session.send('ntf_bag_info', { bag_info: { item_infos: items.slice(i, i + 40) } });
  }
  session.send('res_bag', {});
}

function reqHome(session) {
  if (!requirePlayer(session)) return;
  // `home_furniture_infos` is the authoritative layout: BuildSystem:OnNetCmd_Res_Home
  // assigns it straight into BuildInfo, and ParseBuildInfo reads posIndex/skinId
  // out of each `blob`. Answering with an empty list (as this used to) silently
  // wipes the client's copy on every login, so furniture placed via
  // req_build_home vanished and the story task 「放置家具」 looked undone.
  const home = session.player.home || {};
  const furniture = Array.isArray(home.furniture) ? home.furniture : [];
  const interact = home.interact || {};
  session.send('res_home', {
    home_info: {
      home_furniture_infos: furniture.map((f) => ({
        item_id: Number(f.item_id) || 0,
        blob: String(f.blob ?? ''),
      })),
      home_furniture_interact_info: {
        last_refresh_seconds: String(interact.last_refresh_seconds || 0),
        received_furniture_coin_from_interact:
          Number(interact.received_furniture_coin_from_interact || 0),
      },
    },
  });
}

function reqUniverse(session) {
  if (!requirePlayer(session)) return;
  const universe = session.player.universe;
  if (universe && universe.active) {
    const { buildUniverseInfo } = require('../game/universe');
    session.send('res_universe', { universe_info: buildUniverseInfo(universe) });
  } else {
    session.send('res_universe', {}, 2); // EMPTY_UNIVERSE — silently skipped client-side
  }
}

function reqTotalWar(session) {
  if (!requirePlayer(session)) return;
  session.send('res_total_war', {
    total_war_info: {
      schedule_id: session.player.total_war.schedule_id || 0,
      boss_infos: session.player.total_war.bosses,
      character_infos: [],
      fight_boss_id: 0,
      fight_info: session.player.total_war.pending_fight || { fight_uuid: 0, fight_level_id: 0, fight_state: 0 },
      reward_infos: session.player.total_war.rewards || [],
    },
  });
}

function reqShopList(session) {
  if (!requirePlayer(session)) return;
  const { buildShopListInfo } = require('../game/shop');
  session.send('res_shop_list', { shop_list_info: buildShopListInfo(session.player) });
}

function reqMallList(session) {
  if (!requirePlayer(session)) return;
  const { buildMallListInfo } = require('../game/mall');
  session.send('res_mall_list', { mall_list_info: buildMallListInfo(session.player) });
}

function reqHardLevel(session) {
  if (!requirePlayer(session)) return;
  const hl = session.player.hard_level;
  // fight_info must always be encoded — the client reads .fight_uuid on login
  // to re-enter unfinished fights (BP_GameInstance_C.lua:1341).
  session.send('res_hard_level', {
    hard_level_info: {
      passed_level_id: hl.passed_level_id,
      stars: hl.stars,
      fight_info: hl.pending_fight || { fight_uuid: 0, fight_level_id: 0, fight_state: 0 },
    },
  });
}

function reqCharacterList(session) {
  if (!requirePlayer(session)) return;
  session.send('res_character_list', {
    character_list_info: { character_infos: session.player.characters },
  });
}

function reqPlot(session) {
  if (!requirePlayer(session)) return;
  const p = session.player.plot;
  session.send('res_plot', {
    plot_info: {
      plot_tree_infos: p.plot_tree_infos,
      plot_mission_infos: p.plot_mission_infos,
      completed_mission_ids: p.completed_mission_ids,
      plot_tree_id: p.plot_tree_id,
      plot_node_id: p.plot_node_id,
      node_completed_mission_ids: p.node_completed_mission_ids,
      unlocked_story_line_ids: p.unlocked_story_line_ids,
    },
  });
}

function reqActivityList(session) {
  if (!requirePlayer(session)) return;
  // activity_id must be 1-based and contiguous (client ipairs); the sign-in
  // UI dereferences activity_sign_in_info unconditionally.
  const a = session.player.activity;
  a.sign_ins[1] = a.sign_ins[1] || 0;
  session.send('res_activity_list', {
    activity_list_info: {
      activity_infos: [{
        activity_id: 1,
        activity_sign_in_info: {
          sign_in_times: a.sign_ins[1],
          last_sign_in_seconds: String(a.last_sign_in_seconds || 0),
        },
      }],
    },
  });
}

function reqGacha(session) {
  if (!requirePlayer(session)) return;
  const { buildGachaInfo } = require('../game/gacha');
  session.send('res_gacha', { gacha_info: buildGachaInfo(session.player) });
}

function reqMailList(session) {
  if (!requirePlayer(session)) return;
  session.send('res_mail_list', { mail_list_info: { mail_infos: session.player.mail.list } });
}

function reqPing(session) {
  session.send('res_ping', {});
}

function noopResponse(session, name) {
  // Generic OK for messages whose handlers are trivial in a private server.
  session.send(name, {});
}

module.exports = {
  reqPlayer, reqBag, reqHome, reqUniverse, reqTotalWar, reqShopList,
  reqMallList, reqHardLevel, reqCharacterList, reqPlot, reqActivityList,
  reqGacha, reqMailList, reqPing, noopResponse, savePlayer, requirePlayer,
};
