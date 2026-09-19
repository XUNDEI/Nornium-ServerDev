// Simple logger: console + logs/server.log. Set GHS_VERBOSE=1 for frame dumps.
const fs = require('fs');
const path = require('path');

const logDir = path.join(__dirname, '..', 'logs');
try { fs.mkdirSync(logDir, { recursive: true }); } catch (_) { /* ignore */ }
const logFile = path.join(logDir, 'server.log');
const stream = fs.createWriteStream(logFile, { flags: 'a' });

function ts() {
  return new Date().toISOString();
}

function write(level, args) {
  const line = args.map((a) => {
    if (a instanceof Buffer) return a.toString('hex');
    if (typeof a === 'object' && a !== null) {
      try { return JSON.stringify(a); } catch (_) { return String(a); }
    }
    return String(a);
  }).join(' ');
  const full = `${ts()} [${level}] ${line}`;
  // eslint-disable-next-line no-console
  console.log(full);
  stream.write(full + '\n');
}

module.exports = {
  info: (...a) => write('I', a),
  warn: (...a) => write('W', a),
  error: (...a) => write('E', a),
  verbose: (...a) => { if (process.env.GHS_VERBOSE) write('V', a); },
};
