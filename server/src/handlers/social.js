// Plot / mail / activity / misc player handlers (M4 scope, implemented as
// plain name -> handler function table).
const gd = require('../gamedata');
const items = require('../game/items');
const plot = require('../game/plot');
const daily = require('../game/daily');
const universe = require('../game/universe');
const log = require('../logger');
const { savePlayer, requirePlayer } = require('./sync');
const store = require('../store');

function grantRewards(session, flat, before = () => {}) {
  // flat: [item_id, type, count, ...] triples as used by config tables
  const grants = [];
  for (let i = 0; i + 2 < flat.length; i += 3) {
    grants.push({ item_id: flat[i], count: flat[i + 2] });
  }
  if (!grants.length) return null;
  const ntf = items.grantItems(session.player, grants);
  before();
  session.send('ntf_item_info', ntf);
  savePlayer(session);
  return ntf;
}

// ---------------- plot ----------------

// d_task_story row helpers
function storyTask(id) {
  return gd.query('d_task_story', id);
}

function sendPlotMissions(session, taskIds) {
  if (!taskIds.length) return;
  session.send('ntf_add_plot_mission', {
    plot_mission_infos: taskIds.map((id) => ({
      mission_id: id,
      mission_record_args: [],
      completed: false,
    })),
  });
}

function handlePlayPlotNode(session, req) {
  const p = session.player.plot;
  p.plot_tree_id = Number(req.plot_tree_id ?? 0);
  p.plot_node_id = Number(req.plot_node_id ?? 0);
  // entering a node resets its in-node progress; node.task is the root task
  // id list of the node (d_story_node.task)
  const node = gd.query('d_story_node', p.plot_node_id);
  // a node's `task` list only seeds the chain; expand each entry with the
  // sub-tasks it declares (see game/plot.js — they are otherwise unreachable)
  const taskIds = plot.withSubTasks(node && node.task);
  p.plot_mission_infos = taskIds.map((id) => ({
    mission_id: id,
    mission_record_args: [],
    completed: false,
  }));
  p.node_completed_mission_ids = [];
  session.send('res_play_plot_node', {});
  sendPlotMissions(session, taskIds);
  savePlayer(session);
}

function handleCompletePlotMission(session, req) {
  const p = session.player.plot;
  const missionId = Number(req.mission_id ?? 0);
  const idx = p.plot_mission_infos.findIndex((m) => m.mission_id === missionId);
  if (idx < 0) {
    // mission not tracked yet (e.g. client re-request after reconnect) — accept
    session.send('res_complete_plot_mission', {});
    return;
  }
  p.plot_mission_infos.splice(idx, 1);
  p.node_completed_mission_ids.push(missionId);
  p.completed_mission_ids.push(missionId);

  session.send('res_complete_plot_mission', {});

  // 主线推进到「晋升1个建筑」这类会**禁用探索/跃迁**的阶段
  // （d_task_story[..].unExplore == 1 → 客户端 QuestSystem:IsExploreBlocked 拒绝发
  // req_explore）时，玩家已经没法再去挣蓝图了：如果场上那张建筑蓝图凑不出 2 张同名
  // 副本，「晋升」按钮就永远点不亮。这里立刻兜底补牌，免得必须重登才恢复。
  const repaired = universe.repairUnupgradableBuilding(session.player);
  if (repaired.length) {
    session.send('ntf_add_card', { card_ids: repaired, missed_card_ids: [] });
    log.info(`[plot] 主线进入锁定阶段，补发同名蓝图 ${repaired.join(',')}`);
  }

  // chain: push next task(s) of this node (client plays them from local tables).
  // Rows that declare `subTaskid` must go out together with their sub-tasks —
  // the client expands nothing on its own and would never see them otherwise.
  const task = storyTask(missionId);
  const pending = new Set(p.plot_mission_infos.map((m) => Number(m.mission_id)));
  const nextIds = plot.withSubTasks(task && task.nextTaskid).filter((id) => !pending.has(id));
  for (const id of nextIds) {
    p.plot_mission_infos.push({ mission_id: id, mission_record_args: [], completed: false });
  }
  sendPlotMissions(session, nextIds);
  // story rewards are server-granted ([item_id, type, count] triples); the client
  // only displays them from ntf_item_info (PlotSystem ShowNodeReward).
  if (task && Array.isArray(task.reward) && task.reward.length) grantRewards(session, task.reward);
  savePlayer(session);
}

function handleReceivePlotTreeAward(session, req) {
  const p = session.player.plot;
  const treeId = Number(req.plot_tree_id ?? 0);
  let info = p.plot_tree_infos.find((t) => t.plot_tree_id === treeId);
  if (!info) {
    info = { plot_tree_id: treeId, received_award_ids: [] };
    p.plot_tree_infos.push(info);
  }
  info.received_award_ids.push(Number(req.award_id ?? 0));
  const tree = gd.query('d_story_tree', treeId);
  const rewardField = `reward${req.award_id}`;
  const flat = tree && Array.isArray(tree[rewardField]) ? tree[rewardField] : [];
  session.send('res_receive_plot_tree_award', {});
  if (flat.length) grantRewards(session, flat);
  savePlayer(session);
}

// ---------------- mail ----------------

function handleMailRead(session, req) {
  const mail = session.player.mail.list.find((m) => Number(m.mail_uuid) === Number(req.mail_uuid));
  if (!mail) return session.send('res_mail_read', {}, 1);
  if (mail.mail_state === 0) mail.mail_state = 1;
  session.send('res_mail_read', {});
  savePlayer(session);
}

function handleMailReceive(session, req) {
  const mail = session.player.mail.list.find((m) => Number(m.mail_uuid) === Number(req.mail_uuid));
  if (!mail) return session.send('res_mail_receive', {}, 1);
  if (mail.mail_state === 2 || !mail.item_infos || !mail.item_infos.length) {
    return session.send('res_mail_receive', {}, mail.mail_state === 2 ? 2 : 3);
  }
  mail.mail_state = 2;
  session.send('res_mail_receive', {});
  const grants = mail.item_infos.map((it) => ({ item_id: it.item_id, count: it.count }));
  const ntf = items.grantItems(session.player, grants);
  session.send('ntf_item_info', ntf);
  savePlayer(session);
}

// ---------------- activity ----------------

function handleActivitySign(session, req) {
  const a = session.player.activity;
  const activityId = Number(req.activity_id ?? 1);
  const now = Math.floor(Date.now() / 1000);
  const times = a.sign_ins[activityId] || 0;
  if (times >= 7) {
    session.send('res_activity_sign', { last_sign_in_seconds: String(a.last_sign_in_seconds || 0) }, 6);
    return;
  }
  a.sign_ins[activityId] = times + 1;
  a.last_sign_in_seconds = now;
  const cfg = gd.query('d_activity_sign', '101') || gd.query('d_activity_sign', 101);
  const flat = cfg ? (cfg[`reward${times + 1}`] || []) : [];
  session.send('res_activity_sign', { last_sign_in_seconds: String(now) });
  if (flat.length) grantRewards(session, flat);
  savePlayer(session);
}

// ---------------- misc player ----------------

function handleChangePlayerName(session, req) {
  const p = session.player.player;
  if (req.player_name) p.player_name = String(req.player_name);
  session.send('res_change_player_name', {});
  savePlayer(session);
}

function handleChangePlayerSequenceName(session, req) {
  const p = session.player.player;
  if (req.player_sequence_name) p.player_sequence_name = String(req.player_sequence_name);
  session.send('res_change_player_sequence_name', {});
  savePlayer(session);
}

function handleChangePlayerAvatar(session, req) {
  session.player.player.avatar_id = Number(req.avatar_id ?? 0);
  session.send('res_change_player_avatar', {});
  savePlayer(session);
}

function handleRecordTransform(session, req) {
  if (req.player_transform_in_scene) {
    const list = session.player.player.player_transform_in_scenes;
    const sceneId = Number(req.player_transform_in_scene.scene_id ?? 0);
    const idx = list.findIndex((t) => Number(t.scene_id) === sceneId);
    if (idx >= 0) list[idx] = req.player_transform_in_scene;
    else list.push(req.player_transform_in_scene);
    savePlayer(session);
  }
  session.send('res_record_player_transform_in_scene', {});
}

function handleRemoveTransform(session, req) {
  const ids = [].concat(req.scene_ids ?? []);
  const list = session.player.player.player_transform_in_scenes;
  session.player.player.player_transform_in_scenes =
    list.filter((t) => !ids.includes(Number(t.scene_id)));
  session.send('res_remove_player_transform_in_scene', {});
  savePlayer(session);
}

function handlePlayerPicking(session, req) {
  // reward from d_com_picking; client shows it from its own config
  const cfg = gd.query('d_com_picking', Number(req.picking_id ?? 0));
  session.send('res_player_picking', {});
  if (cfg && Array.isArray(cfg.reward) && cfg.reward.length) grantRewards(session, cfg.reward);
}

function handlePlayerReceiveLevelAward(session, req) {
  const p = session.player.player;
  const level = Number(req.level ?? 0);
  if (p.received_level_awards[level]) {
    return session.send('res_player_receive_level_award', {}, 1); // RECEIVED
  }
  p.received_level_awards[level] = true;
  session.send('res_player_receive_level_award', {});
  const cfg = gd.query('d_player_levelreward', level);
  if (cfg && Array.isArray(cfg.reward) && cfg.reward.length) grantRewards(session, cfg.reward);
  savePlayer(session);
}

function handleSaveData(session) {
  savePlayer(session);
  session.send('res_save_data', {});
}

function handleGmCmd(session, req) {
  const cmd = String(req.cmd ?? '');
  log.info('[gm]', cmd);
  // minimal GM surface: "add_item <id> <count>", "add_character <id>",
  // "add_card <cardId> <count>"（add_card 进的是**当前远航**的建筑蓝图手牌，
  // 不是背包——蓝图只活在星图里，所以卡死时没法用 add_item 救）
  const parts = cmd.trim().split(/\s+/);
  if (parts[0] === 'add_item' && parts.length >= 3) {
    const ntf = items.grantItems(session.player, [
      { item_id: Number(parts[1]), count: Number(parts[2]) },
    ]);
    session.send('ntf_item_info', ntf);
  } else if (parts[0] === 'add_card' && parts.length >= 2) {
    const cardId = Number(parts[1]);
    const count = Math.max(1, Number(parts[2] ?? 1) || 1);
    const u = session.player.universe;
    if (u && u.active && u.main_pos && gd.query('d_srpg_card_base', cardId)) {
      const cards = new Array(count).fill(cardId);
      u.cards.push(...cards);
      session.send('ntf_add_card', { card_ids: cards, missed_card_ids: [] });
      savePlayer(session);
    } else {
      log.info('[gm] add_card 失败：没有进行中的远航或卡牌 id 无效', cardId);
    }
  } else if (parts[0] === 'add_character' && parts.length >= 2) {
    const { buildCharacter } = require('../game/player_new');
    const charId = Number(parts[1]);
    if (gd.has('d_character', charId)
      && !session.player.characters.find((c) => c.character_id === charId)) {
      const char = buildCharacter(session.player, charId);
      session.player.characters.push(char);
      session.send('ntf_character_info', { changed_character_infos: [char] });
      savePlayer(session);
    }
  }
  session.send('res_gm_cmd', {});
}

// ---------------- home ----------------

function handleBuildHome(session, req) {
  // UI_Build_C:SaveBuildInfo walks every placed actor and sends the *whole*
  // layout, and BuildSystem:OnNetCmd_Res_BuildHome then adopts that same list as
  // its local BuildInfo — so this is a full replacement, not a merge. The
  // remaining count in the build menu is derived client-side as
  // `bagCount - BuildSystem:GetBuildCount(item_id)`, so furniture is deliberately
  // not consumed from the bag here.
  const list = Array.isArray(req.home_furniture_infos) ? req.home_furniture_infos : [];
  const seen = new Set();
  const furniture = [];
  for (const f of list) {
    const itemId = Number(f.item_id) || 0;
    if (!itemId || seen.has(itemId)) continue;
    seen.add(itemId);
    furniture.push({ item_id: itemId, blob: String(f.blob ?? '') });
  }
  session.player.home = session.player.home || { interact: {} };
  session.player.home.furniture = furniture;
  session.send('res_build_home', {});
  savePlayer(session);
}

// 家具交互产家具币：每个家具每次交互给 d_bag_item_furniture[item_id].tokenInteract，
// 每日累计上限 d_com_params[25].value2（客户端 BuildSystem:ReqBuildInteract 用同一张表
// 判断「今天还能不能点」，所以服务端必须按同一口径记账，否则客户端显示的剩余次数
// 与实际发放对不上）。跨过 04:00 刷新点后计数归零，语义与 UIUtils.get_daily_refresh 一致。
function handleFurnitureCoin(session, req) {
  const player = session.player;
  const home = player.home || {};
  const interact = home.interact || (home.interact = {});
  const itemId = Number(req.item_id || 0);
  const cfg = gd.query('d_bag_item_furniture', itemId);
  const placed = Array.isArray(home.furniture)
    && home.furniture.some((f) => Number(f.item_id) === itemId);
  if (!cfg || !placed) {
    return session.send('res_receive_furniture_coin_from_interact', {}, 1); // ITEM_NOT_ENOUGH
  }

  const cap = Number((gd.query('d_com_params', 25) || {}).value2) || 240;
  const boundary = daily.dailyRefreshBoundary(Math.floor(Date.now() / 1000));
  if (Number(interact.last_refresh_seconds || 0) < boundary) {
    interact.last_refresh_seconds = boundary;
    interact.received_furniture_coin_from_interact = 0;
  }
  const got = Number(interact.received_furniture_coin_from_interact || 0);
  if (got >= cap) {
    return session.send('res_receive_furniture_coin_from_interact', {}, 2); // RECEIVE_LIMIT
  }

  const amount = Math.min(Number(cfg.tokenInteract) || 0, cap - got);
  interact.received_furniture_coin_from_interact = got + amount;
  session.send('res_receive_furniture_coin_from_interact', {});
  if (amount > 0) {
    session.send('ntf_item_info', items.grantItems(player, [
      { item_id: items.CURRENCY.FURNITURE_COIN, count: amount },
    ]));
  }
  savePlayer(session);
}

// ---------------- daily copy (每日危航 / d_levels) ----------------

// 出击：校验解锁与票，登记一局「进行中」的日常副本。
// 票不在这一步扣——客户端结算时才本地扣票，服务端在结算时同步扣。
function handleDailyLevelFight(session, req) {
  const levelId = Number(req.fight_level_id || 0);
  const cfg = daily.levelConfig(levelId);
  if (!cfg || !daily.isLevelUnlocked(session.player, cfg)) {
    return session.send('res_daily_level_fight', {}, 2); // LEVEL_LOCKED
  }
  if (!daily.pickTicket(session.player)) {
    return session.send('res_daily_level_fight', {}, 1); // RES_NOT_ENOUGH
  }
  daily.setPendingFight(session.player, levelId, nextFightUuid(session));
  daily.setLastLevelId(session.player, levelId);
  session.send('res_daily_level_fight', {
    fight_uuid: daily.pendingFight(session.player).fight_uuid,
  });
  savePlayer(session);
}

// 结算：只有胜利才扣票发奖。失败或中途退出同样走这条消息（UI_Fail_Settlement
// 的 15 秒倒计时与「取消挑战」都发 result=false），此时只清掉进行中的战斗。
// 关卡 id 取自进行中的战斗；「再次挑战」不发 req_daily_level_fight，
// 所以回退到最近一次进入的关卡。
function handleCompleteDailyLevelFight(session, req) {
  const win = !!req.result;
  const player = session.player;
  const levelId = daily.pendingLevelId(player) || daily.lastLevelId(player);
  daily.clearPendingFight(player);

  if (!win) {
    session.send('res_complete_daily_level_fight', {});
    savePlayer(session);
    return;
  }

  const cfg = daily.levelConfig(levelId);
  if (cfg) {
    // 扣票静默处理：结算界面自己会本地扣一张（见 game/daily.js 顶部说明）
    const cost = daily.pickTicket(player);
    if (cost) items.grantItems(player, [{ item_id: cost, count: -1 }]);
    daily.recordPassed(player, levelId);
  }
  const drops = cfg ? daily.rollDrops(cfg) : [];
  // ntf 必须先于 res：结算界面的奖励列表来自 ntf_item_info
  if (drops.length) session.send('ntf_item_info', items.grantItems(player, drops));
  session.send('res_complete_daily_level_fight', {});
  savePlayer(session);
}

// 扫荡：消耗杀手朋友券（1201001），且该关必须已通关。
function handleDailyLevelSweep(session, req) {
  const levelId = Number(req.fight_level_id || 0);
  const cfg = daily.levelConfig(levelId);
  if (!cfg || !daily.hasPassed(session.player, levelId)) {
    return session.send('res_daily_level_sweep', {}, 2); // LEVEL_NOT_PASS
  }
  if (items.bagCount(session.player, daily.SWEEP) < 1) {
    return session.send('res_daily_level_sweep', {}, 1); // RES_NOT_ENOUGH
  }
  items.grantItems(session.player, [{ item_id: daily.SWEEP, count: -1 }]);
  const drops = daily.rollDrops(cfg);
  if (drops.length) session.send('ntf_item_info', items.grantItems(session.player, drops));
  session.send('res_daily_level_sweep', {});
  savePlayer(session);
}

// exported as a name->handler lookup for the dispatcher
function handle(name) {
  const map = {
    req_play_plot_node: handlePlayPlotNode,
    req_complete_plot_mission: handleCompletePlotMission,
    req_receive_plot_tree_award: handleReceivePlotTreeAward,
    req_unlock_story_line: (s, r) => {
      const ids = [].concat(r.story_line_ids ?? []);
      const p = s.player.plot;
      for (const id of ids) if (!p.unlocked_story_line_ids.includes(Number(id))) {
        p.unlocked_story_line_ids.push(Number(id));
      }
      s.send('res_unlock_story_line', {});
      savePlayer(s);
    },
    req_mail_read: handleMailRead,
    req_mail_receive: handleMailReceive,
    req_activity_sign: handleActivitySign,
    req_refresh_player_daily_mission: (s) => s.send('res_refresh_player_daily_mission', {}, 1), // REFRESHED
    req_complete_player_daily_mission: (s, r) => {
      const info = s.player.player.player_daily_mission_info;
      const m = info.player_mission_infos.find((x) => x.mission_id === Number(r.mission_id ?? 0));
      if (!m || m.completed) return s.send('res_complete_player_daily_mission', {}, m ? 2 : 1);
      m.completed = true;
      s.send('res_complete_player_daily_mission', {});
      const task = gd.query('d_task', m.mission_id);
      if (task && Array.isArray(task.reward) && task.reward.length) grantRewards(s, task.reward);
      savePlayer(s);
    },
    req_complete_player_book_mission: (s, r) => {
      const list = s.player.player.player_book_mission_infos;
      const m = list.find((x) => x.mission_id === Number(r.mission_id ?? 0));
      if (!m || m.completed) return s.send('res_complete_player_book_mission', {}, m ? 2 : 1);
      m.completed = true;
      s.send('res_complete_player_book_mission', {});
      const task = gd.table('d_task_book').find((x) => x.id === m.mission_id);
      if (task && Array.isArray(task.reward) && task.reward.length) grantRewards(s, task.reward);
      savePlayer(s);
    },
    req_change_player_name: handleChangePlayerName,
    req_change_player_sequence_name: handleChangePlayerSequenceName,
    req_change_player_avatar: handleChangePlayerAvatar,
    req_record_player_transform_in_scene: handleRecordTransform,
    req_remove_player_transform_in_scene: handleRemoveTransform,
    req_player_picking: handlePlayerPicking,
    req_player_receive_level_award: handlePlayerReceiveLevelAward,
    req_save_data: handleSaveData,
    req_gm_cmd: handleGmCmd,
    req_build_home: handleBuildHome,
    req_receive_furniture_coin_from_interact: handleFurnitureCoin,
    // safe no-op responses for rarely used systems
    req_player_universe_growth_reset: (s) => s.send('res_player_universe_growth_reset', {}),
    // 月卡每日奖励在 handlers/mall.js（req_mall_receive_month_card）
    req_receive_total_war_reward: (s) => s.send('res_receive_total_war_reward', {}, 1), // NO_REWARD
    req_total_war_rank: (s) => s.send('res_total_war_rank', {
      total_war_rank_info: {
        total_war_rank_boss_score_infos: [],
        total_war_rank_total_score_info: { total_war_rank_total_score_item_infos: [], self_rank: 0 },
        total_war_rank_record_infos: [],
        total_war_rank_record_info_boss_ranks: [],
      },
      last_total_war_ranking_data_seconds: String(Math.floor(Date.now() / 1000)),
    }),
    req_daily_level_fight: handleDailyLevelFight,
    req_complete_daily_level_fight: handleCompleteDailyLevelFight,
    req_daily_level_sweep: handleDailyLevelSweep,
    req_hard_level_fight: (s, r) => {
      const hl = s.player.hard_level;
      const levelId = Number(r.fight_level_id ?? 0);
      const cfg = gd.query('d_levels_challenge', levelId);
      if (!cfg || (cfg.switch ?? 0) > 0 || levelId > hl.passed_level_id + 1) {
        return s.send('res_hard_level_fight', {}, 1); // LEVEL_LOCKED
      }
      hl.pending_fight = { fight_uuid: String(nextFightUuid(s)), fight_level_id: levelId, fight_state: 1 };
      s.send('res_hard_level_fight', { fight_uuid: hl.pending_fight.fight_uuid });
      savePlayer(s);
    },
    req_complete_hard_level_fight: (s, r) => {
      const hl = s.player.hard_level;
      const win = !!r.result;
      if (win && hl.pending_fight) {
        const levelId = Number(hl.pending_fight.fight_level_id);
        hl.passed_level_id = Math.max(hl.passed_level_id, levelId);
        const stars = [].concat(r.stars ?? []);
        for (let i = 0; i < 3; i++) {
          const slot = (levelId - 1) * 3 + i;
          if (stars[i] && !hl.stars[slot]) hl.stars[slot] = true;
        }
        const cfg = gd.query('d_levels_challenge', levelId);
        if (cfg) {
          for (let i = 0; i < 3; i++) {
            if (stars[i]) {
              const flat = cfg[`reward${i + 1}`];
              if (Array.isArray(flat) && flat.length) grantRewards(s, flat);
            }
          }
        }
      }
      hl.pending_fight = { fight_uuid: 0, fight_level_id: 0, fight_state: 0 };
      s.send('res_complete_hard_level_fight', {});
      savePlayer(s);
    },
  };
  return map[name] ?? null;
}

function nextFightUuid(session) {
  session.player.fight_seq = (session.player.fight_seq || 1000) + 1;
  return session.player.fight_seq;
}

module.exports = { handle, grantRewards, nextFightUuid };
