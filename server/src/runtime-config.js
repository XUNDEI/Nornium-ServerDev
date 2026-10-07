// server/src/runtime-config.json 的统一读写口（运行时开关：宇宙资源自动补发、
// 商城限购开关等）。注意与 server/runtime-config.json（setup.js 的启动向导
// 配置：game_path/端口等）是两个不同的文件。
// 每次调用都重读文件，所以开关改完立即生效，无需重启；写入口都是「合并写回」，
// 保留调用方没提到的键。
const fs = require('fs');
const path = require('path');

const FILE = process.env.GHS_RUNTIME_CONFIG
  || path.join(__dirname, 'runtime-config.json');

function read() {
  try {
    return JSON.parse(fs.readFileSync(FILE, 'utf8')) || {};
  } catch (_) {
    return {}; // 没有配置文件 / 内容非法时走各开关自己的默认值
  }
}

function write(patch) {
  const cfg = Object.assign(read(), patch);
  fs.writeFileSync(FILE, JSON.stringify(cfg, null, 2) + '\n');
  return cfg;
}

module.exports = { FILE, read, write };
