// In-process regression checks for the story (plot) mission chain.
//
// Regression target: d_task_story rows that declare sibling sub-tasks
// (`subTaskid`) must be delivered together with those sub-tasks. The client
// only ever learns mission ids from `plot_mission_infos`, and both the
// objective counters (炼金合成 50007 / 分解 50002) and the parent-completion
// rule (PlotSystem:CheckParentMission, `taskTargetAmounts`) depend on them
// being present. Shipping only the parent froze the main story at
// 100030017 「尝试一次炼金与分解」.
//
// No server needed. Must run before requiring the server modules: store.js
// reads GHS_DATA_DIR at load time so the saves stay out of the real data/ dir.
const os = require('os');
const fs = require('fs');
const path = require('path');
const tmpDataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ghs-plot-'));
process.env.GHS_DATA_DIR = tmpDataDir;

const { createPlayerDoc } = require('../src/game/player_new');
const { migratePlayer } = require('../src/game/migrate');
const plot = require('../src/game/plot');
const social = require('../src/handlers/social');
const gd = require('../src/gamedata');

const ALCHEMY_PARENT = 100030017;   // 「尝试一次炼金与分解」 taskTargetAmounts = 2
const ALCHEMY_SUB = 1000300171;     // 「尝试一次炼金」  taskContent = 50007
const DECOMPOSE_SUB = 1000300172;   // 「尝试一次分解」  taskContent = 50002
const PREDECESSOR = 100030016;      // last plain task before the branch point

let failures = 0;
function check(cond, msg) {
  console.log(cond ? `  PASS ${msg}` : `  FAIL ${msg}`);
  if (!cond) failures += 1;
}

function makeSession() {
  const player = createPlayerDoc(9101);
  const sent = [];
  return { player, sent, send: (name, msg, result) => sent.push({ name, msg, result }) };
}

const last = (s, name) => [...s.sent].reverse().find((x) => x.name === name);
const missionIds = (s) => s.player.plot.plot_mission_infos.map((m) => Number(m.mission_id));

// ---------------- table assumptions ----------------
// If these fail the game data changed and the fix below needs revisiting.
{
  const parent = gd.query('d_task_story', ALCHEMY_PARENT);
  const subA = gd.query('d_task_story', ALCHEMY_SUB);
  const subB = gd.query('d_task_story', DECOMPOSE_SUB);
  check(!!parent && parent.taskTargetAmounts === 2, `${ALCHEMY_PARENT} expects 2 sub-tasks`);
  check(!!subA && subA.taskContent === 50007, `${ALCHEMY_SUB} is the 熔炉合成 objective (50007)`);
  check(!!subB && subB.taskContent === 50002, `${DECOMPOSE_SUB} is the 熔炉拆解 objective (50002)`);
  check(Array.isArray(parent.subTaskid) && parent.subTaskid.length === 2,
    `${ALCHEMY_PARENT}.subTaskid lists exactly the two sub-tasks`);
}

// ---------------- expansion helper ----------------
{
  check(JSON.stringify(plot.withSubTasks([ALCHEMY_PARENT])) ===
    JSON.stringify([ALCHEMY_PARENT, ALCHEMY_SUB, DECOMPOSE_SUB]),
    'withSubTasks expands a parent into parent + its sub-tasks');
  check(plot.withSubTasks([ALCHEMY_PARENT, ALCHEMY_SUB]).length === 3,
    'withSubTasks dedupes an explicitly repeated sub-task');
  check(plot.withSubTasks(undefined).length === 0, 'withSubTasks tolerates an empty node task list');
  check(plot.withSubTasks([{}]).length === 0, 'withSubTasks ignores the {} the JSON conversion emits');
  check(JSON.stringify(plot.withSubTasks([PREDECESSOR])) === JSON.stringify([PREDECESSOR]),
    'a task row without sub-tasks is pushed unchanged');
  check(JSON.stringify(plot.withSubTasks(gd.query('d_task_story', PREDECESSOR).nextTaskid)) ===
    JSON.stringify([ALCHEMY_PARENT, ALCHEMY_SUB, DECOMPOSE_SUB]),
    'the 100030016 -> 100030017 chain edge expands into the full mission set');
}

// ---------------- chain advancement ----------------
// Completing 100030016 must deliver the branch point AND both sub-tasks, which
// is what lets the furnace actions count and gives the tracker something to
// point at.
{
  const s = makeSession();
  s.player.plot.plot_tree_id = 100010;
  s.player.plot.plot_node_id = 100030;
  s.player.plot.plot_mission_infos = [
    { mission_id: PREDECESSOR, mission_record_args: [], completed: false },
  ];
  social.handle('req_complete_plot_mission')(s, { mission_id: PREDECESSOR });

  check(missionIds(s).includes(ALCHEMY_PARENT), 'advancing past 100030016 delivers the parent task');
  check(missionIds(s).includes(ALCHEMY_SUB) && missionIds(s).includes(DECOMPOSE_SUB),
    'advancing past 100030016 also delivers 1000300171/1000300172');

  const ntf = last(s, 'ntf_add_plot_mission');
  const ntfIds = (ntf?.msg?.plot_mission_infos || []).map((m) => Number(m.mission_id));
  check(ntfIds.includes(ALCHEMY_SUB) && ntfIds.includes(DECOMPOSE_SUB),
    'ntf_add_plot_mission carries the sub-tasks too');
  check(!(ntf?.msg?.plot_mission_infos || []).some((m) => m.completed),
    'pushed missions are marked not-completed');
  check((last(s, 'res_complete_plot_mission') || {}).result === undefined,
    'res_complete_plot_mission still answers OK');
}

// ---------------- both furnace objectives then finish the parent ----------------
{
  const s = makeSession();
  s.player.plot.plot_tree_id = 100010;
  s.player.plot.plot_node_id = 100030;
  s.player.plot.plot_mission_infos = [
    { mission_id: PREDECESSOR, mission_record_args: [], completed: false },
  ];
  social.handle('req_complete_plot_mission')(s, { mission_id: PREDECESSOR });

  const complete = social.handle('req_complete_plot_mission');
  complete(s, { mission_id: ALCHEMY_SUB });
  check(!missionIds(s).includes(ALCHEMY_SUB), '炼金 sub-task is cleared once completed');
  check(missionIds(s).includes(DECOMPOSE_SUB), '分解 sub-task stays pending');
  check(missionIds(s).includes(ALCHEMY_PARENT), 'parent stays pending until both sub-tasks are done');

  complete(s, { mission_id: DECOMPOSE_SUB });
  check(missionIds(s).includes(ALCHEMY_PARENT), 'parent is still tracked (client completes it)');
  check(s.player.plot.node_completed_mission_ids.includes(ALCHEMY_SUB)
    && s.player.plot.node_completed_mission_ids.includes(DECOMPOSE_SUB),
    'both sub-task ids land in node_completed_mission_ids for CheckParentMission');

  // the client, having seen both sub-tasks in node_completed_mission_ids,
  // sends the parent completion itself
  complete(s, { mission_id: ALCHEMY_PARENT });
  check(!missionIds(s).includes(ALCHEMY_PARENT), 'parent is cleared after the client completes it');
  check(missionIds(s).includes(100030018), 'the chain resumes at 100030018');
}

// ---------------- node re-entry ----------------
{
  const s = makeSession();
  social.handle('req_play_plot_node')(s, { plot_tree_id: 100010, plot_node_id: 100010 });
  check(missionIds(s).includes(100010001), 'req_play_plot_node still seeds a node root task');
}

// ---------------- save migration ----------------
{
  const doc = createPlayerDoc(9102);
  const stuck = { mission_id: ALCHEMY_PARENT, mission_record_args: [1], completed: false };
  doc.plot.plot_mission_infos = [stuck];
  doc.plot.plot_node_id = 100030;

  check(migratePlayer(doc) === true, 'migration reports a change for a pre-sub-task save');
  const ids = doc.plot.plot_mission_infos.map((m) => Number(m.mission_id));
  check(ids.includes(ALCHEMY_SUB) && ids.includes(DECOMPOSE_SUB),
    'stuck save gets 1000300171/1000300172 back on load');
  check(doc.plot.plot_mission_infos.find((m) => Number(m.mission_id) === ALCHEMY_PARENT) === stuck,
    'migration keeps the existing entry (and its counter) by identity');
  check(ids.indexOf(ALCHEMY_SUB) === ids.indexOf(ALCHEMY_PARENT) + 1,
    'sub-tasks are placed right after the row that declares them');
  check(migratePlayer(doc) === false, 'plot migration is idempotent');

  const fresh = createPlayerDoc(9103);
  check(migratePlayer(fresh) === false, 'a fresh account (no node entered) is untouched');
}

fs.rmSync(tmpDataDir, { recursive: true, force: true });
console.log(failures === 0 ? '\nPLOT CHECKS PASSED' : `\n${failures} PLOT CHECKS FAILED`);
process.exit(failures === 0 ? 0 : 1);
