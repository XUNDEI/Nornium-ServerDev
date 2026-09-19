// Plot / story mission set assembly for d_task_story.
//
// A row may declare sibling sub-tasks in `subTaskid` (e.g. 100030017
// 「尝试一次炼金与分解」 -> 1000300171 「尝试一次炼金」 + 1000300172
// 「尝试一次分解」). Those sub-tasks are NOT part of the node's nextTaskid
// chain: the only way the client can ever learn about them is from the
// `plot_mission_infos` list the server sends.
//
// Why that matters (both symptoms come from this single omission):
//   1. QuestSystem keeps one QuestInfo entry per mission id it was told about,
//      and objective counters are matched with `config.taskContent == type`
//      (50007 = 熔炉合成, 50002 = 熔炉拆解, ...). Missions the client never
//      received can never be counted, so using the furnace does nothing.
//   2. A row with `taskTargetAmounts > 0` is completed client-side by
//      PlotSystem:CheckParentMission once enough of its `subTaskid` entries are
//      in `node_completed_mission_ids` — and it also drives what the map
//      tracker / City StateTree can point at (SaveGameSpeak.MissionIds +
//      SubMissionIds). With the sub-tasks missing the story dead-ends.
const gd = require('../gamedata');

// tools/convert_gamedata.py turns empty Lua tables into {}, so a "repeated"
// column may arrive as either an array (non-empty) or an object (empty).
function toIdList(value) {
  if (value == null) return [];
  const list = Array.isArray(value) ? value : Object.values(value);
  return list.map(Number).filter((n) => Number.isFinite(n) && n > 0);
}

function storyTask(id) {
  return gd.query('d_task_story', id);
}

function subTaskIds(id) {
  const row = storyTask(id);
  return row ? toIdList(row.subTaskid) : [];
}

// Expand root ids into "root + its sub-tasks (recursively)", deduped, keeping
// every sub-task directly after the row that declares it.
function withSubTasks(...values) {
  const out = [];
  const seen = new Set();
  const emit = (id) => {
    const n = Number(id);
    if (!(n > 0) || seen.has(n)) return;
    seen.add(n);
    out.push(n);
    for (const sub of subTaskIds(n)) emit(sub);
  };
  for (const value of values) for (const id of toIdList(value)) emit(id);
  return out;
}

// Rebuild a stored `plot_mission_infos` array so saves written before
// sub-tasks were delivered get them back. Existing entries are reused by
// identity so in-flight counters are preserved.
function normalizeMissionInfos(list) {
  const byId = new Map();
  for (const info of list || []) {
    if (info && info.mission_id != null) byId.set(Number(info.mission_id), info);
  }
  const out = [];
  const seen = new Set();
  const emit = (id) => {
    const n = Number(id);
    if (!(n > 0) || seen.has(n)) return;
    seen.add(n);
    out.push(byId.get(n) || { mission_id: n, mission_record_args: [], completed: false });
    for (const sub of subTaskIds(n)) emit(sub);
  };
  for (const info of list || []) emit(info && info.mission_id);
  return out;
}

module.exports = { toIdList, storyTask, subTaskIds, withSubTasks, normalizeMissionInfos };
