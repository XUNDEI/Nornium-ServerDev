// HTTP login gate on port 9089 (GM_HOST). The client POSTs JSON and requires
// HTTP 200 + {code: 0, ...}; anything else shows "请检查你的网络".
// Known endpoints (BP_GameInstance_C.lua GMHttpPost/GMHttpUpload):
//   /client/system/serverStatus  -> data.status must be 0 to proceed to TCP login
//   /client/notice/list          -> notice data (safe empty list)
//   /client/marquee/list         -> marquee data (safe empty list)
//   /client/upload/xxx           -> data upload sink (ack only)
const http = require('http');
const log = require('./logger');
const editor = require('./editorapi');

function readBody(req) {
  return new Promise((resolve) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', () => resolve(Buffer.alloc(0)));
  });
}

// hooks.maintenance（可选）来自 index.js 的维护窗口，编辑器的导出接口要用。
// /editor 前缀的请求交给编辑器模块，且不打 info 日志（前端轮询会刷屏），只留 verbose。
function createGate(port, host, hooks = {}) {
  const server = http.createServer(async (req, res) => {
    const body = await readBody(req);
    const url = (req.url || '/').split('?')[0];
    if (url === '/editor' || url.startsWith('/editor/')) {
      log.verbose(`[http] ${req.method} ${url} (${body.length}B)`);
      await editor.handle(req, res, url, body, hooks);
      return;
    }
    log.info(`[http] ${req.method} ${req.url} (${body.length}B)`);
    res.setHeader('Content-Type', 'application/json');

    const ok = (data) => res.end(JSON.stringify({ code: 0, data: data ?? {} }));

    switch (url) {
      case '/client/system/serverStatus':
        return ok({ status: 0, notice: '' });
      // data must be an ARRAY for notice/marquee (client does ipairs(msg.data))
      case '/client/notice/list':
        return ok([]);
      case '/client/marquee/list':
        return ok([]);
      default:
        if (url.startsWith('/client/upload/')) return ok({});
        log.warn(`[http] unknown endpoint ${req.url}`);
        res.statusCode = 200;
        return ok({});
    }
  });
  return new Promise((resolve, reject) => {
    const fail = (err) => reject(err);
    server.once('error', fail);
    server.listen(port, host, () => {
      // listen 成功后换成常驻日志监听，避免之后的错误变成未处理异常直接崩进程
      server.off('error', fail);
      server.on('error', (err) => log.error(`[http] gate server error:`, err.message));
      resolve(server);
    });
  });
}

module.exports = { createGate };
