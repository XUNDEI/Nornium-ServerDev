// New player document factory (M1): initial characters, bag, plot, mail, etc.
const gd = require('../gamedata');
const items = require('./items');
const furnace = require('./furnace');

// Playable launch characters: rows in d_character with a first weapon AND a
// localizable name. The name check drops dev placeholder rows 24001/24002
// (name id 611240xx is absent from d_word_cn, so the client renders the
// "看到这个说明没本地化" ghost entry).
function isPlayableCharacter(charId) {
  const cfg = gd.query('d_character', charId);
  if (!cfg || !cfg.firstWeapon) return false;
  return !!gd.query('d_word_cn', cfg.name);
}

function initialCharacterIds() {
  return gd.rows('d_character')
    .filter(([, r]) => isPlayableCharacter(r.id))
    .map(([, r]) => r.id);
}

function characterSkills(charId) {
  const list = [];
  for (const [, s] of gd.rows('d_skill')) {
    if (s.belongCharId === charId && (s.belong === 1 || s.belong === 2)) {
      list.push({ skill_id: s.id, skill_level: 1 });
    }
  }
  return list;
}

function buildCharacter(player, charId) {
  const cfg = gd.query('d_character', charId);
  const char = {
    character_id: charId,
    exp: 0,
    break_times: 0,
    weapon_info: null,
    arm_infos: [],
    skill_infos: characterSkills(charId),
    talent_ids: [],
    character_skin_id: 0,
    mecha_skin_id: 0,
    city_skin_id: 0,
    own_character_skin_ids: [],
    own_mecha_skin_ids: [],
    own_city_skin_ids: [],
  };
  if (cfg.firstWeapon) {
    char.weapon_info = items.makeItem(player, cfg.firstWeapon, 1);
  }
  return char;
}

function buildPlayerInfo(accountId) {
  const now = Math.floor(Date.now() / 1000);
  return {
    player_id: accountId,
    register_seconds: String(now),
    player_name: `旅行者${accountId}`,
    player_sequence_name: `Traveler${accountId}`,
    avatar_id: 10101, // d_character id domain (client uses it as character icon)
    received_level_awards: [],
    daily_level_id_passed: [],
    // 每日危航（d_levels）：进行中的副本。客户端登录时读 fight_level_id > 0
    // 就把玩家送回到那场战斗（BP_GameInstance_C.lua:1319）。空闲时必须显式
    // 编码成全 0（坑 6：子消息缺席= nil 会被客户端无条件访问）。
    daily_level_fight_info: { fight_uuid: '0', fight_level_id: 0, fight_state: 0 },
    // Synthesis blueprints have no unlock item in this build; seed them so the
    // furnace works (see game/furnace.js).
    blueprint_ids: furnace.synthesisBlueprintIds(),
    arm_blueprint_ids: [],
    // QuestSystem:InitDailyQuest dereferences this unconditionally — must exist.
    player_daily_mission_info: {
      player_mission_infos: gd.rows('d_task').map(([id]) => ({
        mission_id: Number(id),
        mission_record_args: [0],
        completed: false,
      })),
      last_auto_refresh_seconds: '0',
      manual_refresh_seconds: '0',
    },
    player_book_mission_infos: gd.table('d_task_book').map((r) => ({
      mission_id: r.id,
      mission_record_args: [0],
      completed: false,
    })),
    player_picking_infos: [],
    player_universe_growth_node_infos: [],
    player_transform_in_scenes: [],
  };
}

// 新号初始背包。数值取自开发者长期实测存档（2026-09）并整体放宽 —— 目的只有一个：
// 「资源不够」绝不能成为玩家体验任何系统的理由。本服的资源产出/回收链路还很粗糙
// （角色升级不扣金币、部分材料无处补充），一旦给少了，玩家会卡在需要消耗资源的
// 教程或主线上，而官方早已停运、没有任何补给渠道。
function initialBagGrants() {
  return [
    // 货币
    { item_id: items.CURRENCY.GOLD, count: 1200000 },     // 金星贝（实测约 101 万）
    { item_id: items.CURRENCY.DIAMOND, count: 100000 },   // 诺伦炬（实测约 0.97 万，这里放宽）
    { item_id: items.CURRENCY.MEMBRANE, count: 999 },     // 补给配额（实测 40）
    { item_id: items.CURRENCY.EXP, count: 11600 },        // 游历经验 → 约 Lv.13（实测同值）
    { item_id: items.CURRENCY.GACHA_LOW, count: 9999 },   // 时枝化石（实测 25）
    { item_id: items.CURRENCY.GACHA_HIGH, count: 9999 },  // 珊瑚劫灰（实测 42）
    { item_id: items.CURRENCY.LENS, count: 120000 },      // 诺伦透镜（实测约 12.1 万）
    { item_id: items.CURRENCY.FURNITURE_COIN, count: 10000 }, // 王宫点数（实测约 1.02 万）
    // 抽卡与副本门票
    { item_id: 1200001, count: 100 },   // 诺伦机票（限定池，实测 70）
    { item_id: 1200002, count: 200 },   // 都城机票（常驻池，实测 137）
    { item_id: 1201001, count: 99 },    // 杀手朋友券（扫荡用；也顶替不足的危航许可）
    // 注意：不要发 1201003 危航许可。官方口径是「每次登录跨过 04:00 才发 6 张」
    // （daily.grantDailyPermits，login.js 每次登录都会调用），新号初始为 0；
    // daily_check.js 里「a fresh account starts with 0 危航许可」守的就是这条。
    // 升级材料（itemType=12 subType=3/4，经验值在 d_bag_item.subParam[0]）：
    // 教程/主线会要求升级角色与武器，必须发放足够的经验道具。
    { item_id: 1203001, count: 999 },  // 角色经验·小 (1000/个)
    { item_id: 1203002, count: 200 },  // 角色经验·中 (4000/个)
    { item_id: 1203003, count: 50 },   // 角色经验·大 (16000/个)
    { item_id: 1204001, count: 999 },  // 武器经验·小 (1000/个)
    { item_id: 1204002, count: 200 },  // 武器经验·中 (4000/个)
    { item_id: 1204003, count: 50 },   // 武器经验·大 (16000/个)
    // 突破材料（1202xxx 系列，d_role_levelbreak/d_weapon_levelbreak 的 material）：
    // 角色与武器每到 20/40/... 级需要对应材料突破，否则卡等级上限。
    // 下面这 17 个 id 就是两张突破表里出现的全部材料（缺一不可）。
    { item_id: 1202001, count: 500 }, { item_id: 1202002, count: 500 },
    { item_id: 1202003, count: 500 }, { item_id: 1202025, count: 500 },
    { item_id: 1202026, count: 500 }, { item_id: 1202027, count: 500 },
    { item_id: 1202031, count: 500 }, { item_id: 1202032, count: 500 },
    { item_id: 1202033, count: 500 }, { item_id: 1202037, count: 500 },
    { item_id: 1202038, count: 500 }, { item_id: 1202039, count: 500 },
    { item_id: 1202043, count: 500 }, { item_id: 1202044, count: 500 },
    { item_id: 1202045, count: 500 }, { item_id: 1202046, count: 500 },
    { item_id: 1202047, count: 500 }, { item_id: 1202048, count: 500 },
    // 技能/练星链路里也会吃到这两个，实测存档里有余量，一并给足。
    { item_id: 1202023, count: 500 }, { item_id: 1202024, count: 500 },
  ];
}

// 全部家具（d_bag_item_furniture，itemType 93）：主线任务会要求放置指定家具
// （如"放置家具【神秘喷雾】" 7120201），家具必须先在背包中才能放置。
function furnitureGrants() {
  return gd.rows('d_bag_item_furniture').map(([, r]) => ({ item_id: r.id, count: 3 }));
}

// 邮件正文会被客户端 MailModel 的 format() 重新解读：`@` 是转义符，
// `@n` = 换行、`@s` = 空格、`@@` = 字面 @（其他组合原样输出）。所以换行必须写
// `@n`，并且正文中不要出现裸 @（尤其别写成 email / @某人）。
function buildStarterBundleMail(nowSec) {
  return {
    send_seconds: String(nowSec),
    mail_uuid: 1001,
    title: '欢迎来到诺尼姆',
    content: '亲爱的旅行者：@n@n'
      + '欢迎来到这台小小的私服。为了让新旅行者不必在资源上耗时间，初始背包已经'
      + '放了相当充足的一批物资，随信邮件里再补一份。@n@n'
      + '另外务必看一看另外一封《【必读】本项目完全免费开源》——'
      + '如果你是花钱买到它的，请联系卖家退款，你被骗了。@n@n'
      + '祝你在这片星图上玩得开心。@n—— Nornium ServerDev',
    type: '系统',
    item_infos: [
      { item_id: items.CURRENCY.DIAMOND, count: 20000 },
      { item_id: items.CURRENCY.GOLD, count: 500000 },
      { item_id: 1200001, count: 50 },   // 诺伦机票（限定池）
      { item_id: 1200002, count: 50 },   // 都城机票（常驻池）
      { item_id: items.CURRENCY.LENS, count: 20000 },
    ],
    mail_state: 0,
  };
}

// 防骗声明。没有附件（客户端会自动隐藏「领取」按钮），纯粹是一封说明信。
function buildOpenSourceNoticeMail(nowSec) {
  return {
    send_seconds: String(nowSec - 1), // 排在欢迎邮件之后（客户端按 send_seconds 倒序）
    mail_uuid: 1002,
    title: '【必读】本项目完全免费开源',
    content: '【重要提醒 · 请花一分钟读完】@n@n'
      + '你正在使用的 Nornium ServerDev（失乐星图本地私服）是完全开源、并且永久免费的，'
      + '代码以 MIT 协议公开发布，作者从未在任何平台上收取过一分钱。@n@n'
      + '所以：如果你是通过网店、二手平台、社交群组、网盘付费链接，或者所谓的一键端、'
      + '商业版、定制版、包更新版花钱买到它的 —— 你被骗了。'
      + '请立刻申请退款并向平台举报该商品。@n@n'
      + '本项目不绑定账号、不依赖联网、也不需要任何激活码，任何人都可以在自己的机器上'
      + '按 README 的步骤搭起来。有人向你出售服务端、账号、激活码或收费技术支持，'
      + '就是在拿别人免费的劳动成果卖钱。@n@n'
      + '遇到 bug 请到项目仓库提 issue。修理一款已经停运的游戏，本来就该是免费的。@n@n'
      + '感谢你愿意用正确的渠道使用这个项目。',
    type: '系统',
    item_infos: [],
    mail_state: 0,
  };
}

function createPlayerDoc(accountId) {
  const nowSec = Math.floor(Date.now() / 1000);
  const doc = {
    account_id: accountId,
    created: nowSec,
    player: buildPlayerInfo(accountId),
    bag: { items: [], next_uuid: 1 },
    characters: [],
    universe: null,
    gacha: {
      type_infos: {},  // type_id -> {no_up_times, no_5p_times, total_times, free_seconds, choose_times}
      records: [],     // global history ring (per type kept in type_infos)
      pending: {},     // list_id -> [GachaRecordInfo]
    },
    shop: { shops: {}, next_refresh: 0 },
    mall: { purchase: {}, charge_point: 0, received_charge_points: [], month_card_expire: 0, month_card_last_tick: 0 },
    plot: {
      plot_tree_infos: [],
      plot_mission_infos: [],       // in-progress mission ids (current node)
      completed_mission_ids: [],
      plot_tree_id: 0,
      plot_node_id: 0,
      node_completed_mission_ids: [],
      unlocked_story_line_ids: [],
    },
    mail: { next_uuid: 1003, list: [buildStarterBundleMail(nowSec), buildOpenSourceNoticeMail(nowSec)] },
    activity: { sign_ins: {} },
    hard_level: { passed_level_id: 0, stars: [] },
    // 每日危航的最近一次选择（「再次挑战」不会再发 req_daily_level_fight，
    // 结算时需要靠它还原关卡 id）。
    daily_copy: { last_level_id: 0 },
    total_war: { schedule_id: 0, bosses: [], scores: {}, reward_received: false },
    home: { furniture: [], interact: {} },
  };
  for (const id of initialCharacterIds()) {
    doc.characters.push(buildCharacter(doc, id));
  }
  items.grantItems(doc, initialBagGrants());
  items.grantItems(doc, furnitureGrants());
  return doc;
}

module.exports = { createPlayerDoc, initialCharacterIds, buildCharacter, isPlayableCharacter };
