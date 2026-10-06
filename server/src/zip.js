// 零依赖 ZIP 读写（mod 导入要解 zip、导出要打 zip，不值得为此引入新依赖 ——
// 本项目的原则是运行时只依赖 protobufjs / des.js，见 REVERSE_ENGINEERING 坑 47 的教训）。
//
// 只覆盖 mod 分发需要的子集，够用且可测：
//   读： STORE(0) 与 DEFLATE(8)，单卷、无 Zip64（mod 包超过 4GB 属于事故，直接报错）。
//   写： 全部 STORE（mod 里的 lua/json 本来就是文本，玩家机器上没有压缩收益的痛点；
//        换取 60 行以内、无任何分支的实现）。压缩交给 mod 作者自己 7z/zip。
//
// 格式参考：PKWARE APPNOTE.TXT（central directory + local file header）。
const fs = require('fs');
const zlib = require('zlib');

const SIG_LOCAL = 0x04034b50;
const SIG_CD = 0x02014b50;
const SIG_EOCD = 0x06054b50;

function findEocd(buf) {
  // EOCD 注释区最长 65535 字节，从尾部往前扫签名
  const min = Math.max(0, buf.length - 65557);
  for (let i = buf.length - 22; i >= min; i -= 1) {
    if (buf.readUInt32LE(i) === SIG_EOCD) return i;
  }
  return -1;
}

// 列出 zip 里全部条目：{ name, method, compressedSize, size, offset }
function listEntries(buf) {
  const eocd = findEocd(buf);
  if (eocd < 0) throw new Error('不是合法的 zip（找不到 central directory 结尾标记）');
  const count = buf.readUInt16LE(eocd + 10);
  let p = buf.readUInt32LE(eocd + 16); // central directory 偏移
  const entries = [];
  for (let i = 0; i < count; i += 1) {
    if (p + 46 > buf.length || buf.readUInt32LE(p) !== SIG_CD) {
      throw new Error('zip 的 central directory 损坏或包含不支持的 Zip64 结构');
    }
    const method = buf.readUInt16LE(p + 10);
    const compressedSize = buf.readUInt32LE(p + 20);
    const size = buf.readUInt32LE(p + 24);
    const nameLen = buf.readUInt16LE(p + 28);
    const extraLen = buf.readUInt16LE(p + 30);
    const commentLen = buf.readUInt16LE(p + 32);
    const offset = buf.readUInt32LE(p + 42);
    const name = buf.slice(p + 46, p + 46 + nameLen).toString('utf8');
    entries.push({ name, method, compressedSize, size, offset });
    p += 46 + nameLen + extraLen + commentLen;
  }
  return entries;
}

// 解出单个条目的内容（Buffer）
function extractEntry(buf, entry) {
  const nameLen = buf.readUInt16LE(entry.offset + 26);
  const extraLen = buf.readUInt16LE(entry.offset + 28);
  const dataStart = entry.offset + 30 + nameLen + extraLen;
  const raw = buf.slice(dataStart, dataStart + entry.compressedSize);
  if (entry.method === 0) return raw;
  if (entry.method === 8) return zlib.inflateRawSync(raw);
  throw new Error(`zip 条目 ${entry.name} 使用了不支持的压缩方式 ${entry.method}（只支持 store/deflate）`);
}

// 解包整个 zip：返回 { name: Buffer }（目录条目跳过）。`filter(name)` 可选，
// 返回 false 的条目直接丢弃（mod 导入用它剥掉包在 zip 里的顶层目录）。
function readAll(buf, filter) {
  const out = {};
  for (const entry of listEntries(buf)) {
    if (entry.name.endsWith('/')) continue;
    if (filter && !filter(entry.name)) continue;
    out[entry.name] = extractEntry(buf, entry);
  }
  return out;
}

// ------------------------------------------------------------ 写（全部 STORE）

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i += 1) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

// files: { name: Buffer }（name 用 / 分隔；目录不需要单独给，按文件的父路径自动建）
// 返回 Buffer。名字统一按 UTF-8 记（general purpose bit 11 置位，声明 UTF-8 文件名）。
function writeZip(files) {
  const names = Object.keys(files);
  const chunks = [];
  const central = [];
  let offset = 0;
  for (const name of names) {
    const data = files[name];
    const crc = crc32(data);
    const nameBuf = Buffer.from(name, 'utf8');
    const local = Buffer.alloc(30);
    local.writeUInt32LE(SIG_LOCAL, 0);
    local.writeUInt16LE(20, 4);          // version needed
    local.writeUInt16LE(0x0800, 6);      // bit 11: UTF-8 名字
    local.writeUInt16LE(0, 8);           // method = STORE
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(data.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(nameBuf.length, 26);
    chunks.push(local, nameBuf, data);
    const cd = Buffer.alloc(46);
    cd.writeUInt32LE(SIG_CD, 0);
    cd.writeUInt16LE(20, 4);             // version made by
    cd.writeUInt16LE(20, 6);             // version needed
    cd.writeUInt16LE(0x0800, 8);
    cd.writeUInt16LE(0, 10);             // method
    cd.writeUInt32LE(crc, 16);
    cd.writeUInt32LE(data.length, 20);
    cd.writeUInt32LE(data.length, 24);
    cd.writeUInt16LE(nameBuf.length, 28);
    cd.writeUInt32LE(offset, 42);
    central.push(cd, nameBuf);
    offset += 30 + nameBuf.length + data.length;
  }
  const centralBuf = Buffer.concat(central);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(SIG_EOCD, 0);
  eocd.writeUInt16LE(names.length, 8);
  eocd.writeUInt16LE(names.length, 10);
  eocd.writeUInt32LE(centralBuf.length, 12);
  eocd.writeUInt32LE(offset, 16);
  return Buffer.concat([...chunks, centralBuf, eocd]);
}

// 把一个目录打成 zip（用于「导出 mod」），等价 writeZip 的目录便捷版。
// prefix: zip 内的顶层目录名（如 'my-mod/'；空串 = 不带顶层目录）。
function zipDir(dir, prefix = '') {
  const files = {};
  const walk = (p, rel) => {
    for (const e of fs.readdirSync(p, { withFileTypes: true })) {
      const abs = `${p}/${e.name}`;
      const relName = rel ? `${rel}/${e.name}` : e.name;
      if (e.isDirectory()) walk(abs, relName);
      else files[prefix + relName] = fs.readFileSync(abs);
    }
  };
  walk(dir, '');
  return writeZip(files);
}

module.exports = { listEntries, extractEntry, readAll, writeZip, zipDir };
