// Loads reference/gamedata/*.json (109 tables) into memory on demand.
// JSON conversion rule: numeric keys are stringified ("10101"), sequential-key
// Lua tables became arrays. query() hides that difference.
const fs = require('fs');
const path = require('path');

const gdDir = path.join(__dirname, '..', '..', 'reference', 'gamedata');
const cache = new Map();

function table(name) {
  let t = cache.get(name);
  if (!t) {
    const file = path.join(gdDir, `${name}.json`);
    t = JSON.parse(fs.readFileSync(file, 'utf8'));
    cache.set(name, t);
  }
  return t;
}

// Query a row by id: object tables use String(id), array tables match on row.id.
function query(name, id) {
  const t = table(name);
  if (Array.isArray(t)) {
    const n = Number(id);
    return t.find((r) => r.id === n) ?? t[n - 1] ?? null;
  }
  return t[String(id)] ?? null;
}

// All rows as an array of [id, row] pairs (string ids for object tables).
function rows(name) {
  const t = table(name);
  if (Array.isArray(t)) return t.map((r) => [String(r.id ?? ''), r]);
  return Object.entries(t);
}

function has(name, id) {
  return query(name, id) !== null;
}

module.exports = { table, query, rows, has };
