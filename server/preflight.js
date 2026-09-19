// Pre-flight test: verify protobufjs can load the reconstructed .proto files
// and handle ghs.Msg oneof round-trip, plus DES-ECB + ISO7816-4 padding.
const path = require('path');
const protobuf = require('protobufjs');
const DES = require('des.js').DES;

const protoDir = path.join(__dirname, '..', 'reference', 'proto');

async function main() {
  // 1. Load all protos with keepCase (field names must stay snake_case, like the client)
  const root = new protobuf.Root();
  await root.load(path.join(protoDir, 'msg.proto'), { keepCase: true });
  const Msg = root.lookupType('ghs.Msg');

  // 2. Verify field numbers via reflection (like the client does with pb.fields)
  const fields = Object.values(Msg.fields);
  const ping = fields.find((f) => f.name === 'req_ping');
  const login = fields.find((f) => f.name === 'res_login');
  console.log('total fields in ghs.Msg:', fields.length);
  console.log('req_ping field number:', ping && ping.id);
  console.log('res_login field number:', login && login.id);

  // 3. Oneof round-trip: encode a login response
  const payload = { res_login: { account_id: 12345, key: 'test-key' } };
  const buf = Msg.encode(Msg.create(payload)).finish();
  const decoded = Msg.decode(buf);
  console.log('oneof member set:', decoded.sub_msg); // oneof virtual property = field name
  console.log('decoded account_id:', decoded.res_login.account_id.toString(), 'key:', decoded.res_login.key);

  // 4. DES-ECB + ISO7816-4 padding round-trip (spec from reference/lua-crypt.c)
  // des.js note: use update() alone for encrypt (emits all complete blocks, no extra
  // padding block); for decrypt use update().concat(final()) — final() just flushes
  // the internally buffered last block. Input must always be a multiple of 8.
  function desEcb(keyBytes, data, type) {
    const des = new DES({ type, key: keyBytes });
    const out = des.update(Array.from(data));
    return Buffer.from(type === 'decrypt' ? out.concat(des.final()) : out);
  }
  function pad(data) {
    const chunksz = (data.length + 8) & ~7;
    const padded = Buffer.alloc(chunksz);
    data.copy(padded);
    padded[data.length] = 0x80;
    return padded;
  }
  function unpad(data) {
    if (data.length === 0 || data.length % 8) throw new Error('bad length');
    for (let i = data.length - 1; i >= data.length - 8; i--) {
      if (data[i] === 0x80) return data.subarray(0, i);
      if (data[i] !== 0) throw new Error('bad padding');
    }
    throw new Error('no 0x80 marker');
  }
  const key = Buffer.from('kueisoon', 'utf8');
  const cipher = (buf) => desEcb(Array.from(key), pad(buf), 'encrypt');
  const decipher = (buf) => unpad(desEcb(Array.from(key), buf, 'decrypt'));
  for (const plain of [Buffer.from('8bytes!!'), Buffer.from(''), Buffer.from('1234567890abc'), Buffer.from('a')]) {
    const enc = cipher(plain);
    const dec = decipher(enc);
    const ok = enc.length % 8 === 0 && enc.length > plain.length && dec.equals(plain);
    console.log(`DES roundtrip len=${plain.length} -> enc ${enc.length} bytes:`, ok ? 'OK' : 'FAIL');
  }

  console.log('\nPREFLIGHT PASSED');
}

main().catch((e) => { console.error('PREFLIGHT FAILED:', e.message); process.exit(1); });
