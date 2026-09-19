// protobufjs loader for the reconstructed .proto set (keepCase: field names
// must stay snake_case to match the client's lua-protobuf usage).
const path = require('path');
const protobuf = require('protobufjs');

const root = new protobuf.Root();
const Msg = root.lookupTypeOrThrow; // placeholder to force sync init order below

let loaded = false;

async function load() {
  if (loaded) return;
  await root.load(path.join(__dirname, '..', '..', 'reference', 'proto', 'msg.proto'), {
    keepCase: true,
  });
  loaded = true;
}

function getMsg() {
  if (!loaded) throw new Error('protos not loaded yet');
  return root.lookupType('ghs.Msg');
}

// name <-> field number maps over the ghs.Msg oneof, built from reflection
// (mirrors the client's pb.fields("ghs.Msg") usage — never hardcode cmd ids).
let nameToNumber = null;
let numberToName = null;

function buildMaps() {
  if (nameToNumber) return;
  nameToNumber = {};
  numberToName = {};
  for (const f of Object.values(getMsg().fields)) {
    nameToNumber[f.name] = f.id;
    numberToName[f.id] = f.name;
  }
}

function fieldNumber(name) {
  buildMaps();
  const n = nameToNumber[name];
  if (n === undefined) throw new Error(`unknown ghs.Msg field: ${name}`);
  return n;
}

function fieldName(number) {
  buildMaps();
  return numberToName[number] || null;
}

function allFieldNames() {
  buildMaps();
  return Object.keys(nameToNumber);
}

// Encode { [fieldName]: subMessage } into protobuf bytes for the ghs.Msg bus.
function encodeMsg(name, payload) {
  const MsgT = getMsg();
  const obj = {};
  obj[name] = payload || {};
  return Buffer.from(MsgT.encode(MsgT.create(obj)).finish());
}

// Decode ghs.Msg bytes -> { name, msg } using the oneof virtual property.
function decodeMsg(buf) {
  const decoded = getMsg().decode(buf);
  const name = decoded.sub_msg;
  if (!name) return { name: null, msg: null };
  return { name, msg: decoded[name] };
}

// protobufjs returns Long objects for 64-bit fields; normalize to JS numbers
// (all uuids/timestamps in this game fit well below 2^53).
function num64(v) {
  if (v === null || v === undefined) return 0;
  if (typeof v === 'number') return v;
  if (typeof v === 'string') return Number(v);
  if (typeof v === 'object' && typeof v.toNumber === 'function') return v.toNumber();
  return Number(v);
}

module.exports = { load, getMsg, fieldNumber, fieldName, allFieldNames, encodeMsg, decodeMsg, num64 };
