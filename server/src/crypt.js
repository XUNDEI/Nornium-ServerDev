// DES-ECB with the client's non-standard ISO 7816-4 style padding.
// Spec from reference/lua-crypt.c (ldesencode/ldesdecode):
//   encrypt: chunksz = (len + 8) & ~7  -> always append at least one full pad
//            block; tail block = data + 0x80 + zeros.
//   decrypt: last block scanned backwards: skip zeros, 0x80 terminates (and is
//            removed), anything else is invalid.
// Node's built-in crypto disables DES (OpenSSL 3 default), so use des.js.
const crypto = require('crypto');
const DES = require('des.js').DES;

function desEcb(keyBytes, data, type) {
  const des = new DES({ type, key: Array.from(keyBytes) });
  // disable des.js's built-in PKCS-style unpad in final() — it misreads our
  // ISO 7816-4 marker byte (0x80) as a pad length when plaintext len % 8 == 7.
  des.padding = false;
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
  if (data.length === 0 || data.length % 8) throw new Error('bad padded length');
  for (let i = data.length - 1; i >= data.length - 8; i--) {
    if (data[i] === 0x80) return data.subarray(0, i);
    if (data[i] !== 0) throw new Error('bad padding');
  }
  throw new Error('no 0x80 marker');
}

function encrypt(keyBytes, plain) {
  return desEcb(keyBytes, pad(plain), 'encrypt');
}

function decrypt(keyBytes, ct) {
  return unpad(desEcb(keyBytes, ct, 'decrypt'));
}

const INITIAL_KEY = Buffer.from('kueisoon', 'utf8');

// Session key: any 8 random bytes (it never travels through a protobuf
// `string` field — only its DES ciphertext does, via the `bytes` field
// msg_key in gate.proto, which preserves raw bytes on the wire).
function generateSessionKey() {
  return crypto.randomBytes(8);
}

module.exports = { encrypt, decrypt, INITIAL_KEY, generateSessionKey };
