// 远航支援商店（universe growth）—— 点数经济与节点等级。
// 客户端权威实现：reference/client_lua/Module/Player/PlayerSystem.lua:58-129。
// 关键语义：背包里 id 9003（补给配额/败者翼膜）的数量是「远航经验」，查 d_srpg_exp
// 累计得出远航等级；已花费点数 = Σ d_srpg_growth[id].cost × node_rank（记在
// player_info.player_universe_growth_node_infos 里），剩余点数 = 等级 − 已花费。
// 9003 本身**不随购买扣减**——它是永久经验型货币，购买只是虚拟记账。
const gd = require('../gamedata');
const items = require('./items');

// 与客户端 GetSrpgGrowthLevel 同语义：exp 逐行消耗，够一格就升一级。
function growthLevel(player) {
  let exp = items.bagCount(player, 9003);
  let level = 1;
  for (const row of gd.table('d_srpg_exp')) {
    if (exp >= (row.exp ?? 0)) {
      exp -= row.exp ?? 0;
      level += 1;
    } else break;
  }
  return level;
}

function nodeRank(player, nodeId) {
  const infos = player?.player?.player_universe_growth_node_infos;
  if (!Array.isArray(infos)) return 0;
  const info = infos.find((it) => Number(it.node_id) === Number(nodeId));
  return info ? (Number(info.node_rank) || 0) : 0;
}

function spentPoints(player) {
  const infos = player?.player?.player_universe_growth_node_infos;
  if (!Array.isArray(infos)) return 0;
  let sum = 0;
  for (const info of infos) {
    const cfg = gd.query('d_srpg_growth', info.node_id);
    if (cfg) sum += (Number(cfg.cost) || 0) * (Number(info.node_rank) || 0);
  }
  return sum;
}

function freePoints(player) {
  return growthLevel(player) - spentPoints(player);
}

// 升一级并写回存档结构（调用方负责 savePlayer）。返回新的 node_rank。
function levelUpNode(player, nodeId) {
  const infos = player.player.player_universe_growth_node_infos;
  let info = infos.find((it) => Number(it.node_id) === Number(nodeId));
  if (!info) {
    info = { node_id: Number(nodeId), node_rank: 0 };
    infos.push(info);
  }
  info.node_rank = (Number(info.node_rank) || 0) + 1;
  return info.node_rank;
}

module.exports = { growthLevel, nodeRank, spentPoints, freePoints, levelUpNode };
