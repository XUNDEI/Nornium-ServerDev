// HTTP login gate on port 8089 (GM_HOST). The client POSTs JSON and requires
// HTTP 200 + {code: 0, ...}; anything else shows "请检查你的网络".
// Known endpoints (BP_GameInstance_C.lua GMHttpPost/GMHttpUpload):
//   /client/system/serverStatus  -> data.status must be 0 to proceed to TCP login
//   /client/notice/list          -> notice data (safe empty list)
//   /client/marquee/list         -> marquee data (safe empty list)
//   /client/upload/xxx           -> data upload sink (ack only)
const http = require('http');
const log = require('./logger');

function readBody(req) {
  return new Promise((resolve) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', () => resolve(Buffer.alloc(0)));
  });
}

function createGate(port, host) {
  const server = http.createServer(async (req, res) => {
    const body = await readBody(req);
    log.info(`[http] ${req.method} ${req.url} (${body.length}B)`);
    res.setHeader('Content-Type', 'application/json');

    const ok = (data) => res.end(JSON.stringify({ code: 0, data: data ?? {} }));

    switch (req.url) {
      case '/client/system/serverStatus':
        return ok({ status: 0, notice: '' });
      // data must be an ARRAY for notice/marquee (client does ipairs(msg.data))
      case '/client/notice/list':
        return ok([]);
      case '/client/marquee/list':
        return ok([]);
      default:
        if (req.url.startsWith('/client/upload/')) return ok({});
        log.warn(`[http] unknown endpoint ${req.url}`);
        res.statusCode = 200;
        return ok({});
    }
  });
  return new Promise((resolve) => {
    server.listen(port, host, () => resolve(server));
  });
}

module.exports = { createGate };
