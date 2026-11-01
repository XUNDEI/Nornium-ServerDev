// 直接启动游戏主程序（NULL 模式，见 REVERSE_ENGINEERING.md 坑 13）。
// 「点我启动.bat」在 auto-launch.flag 存在时调用本脚本；也可以手动 `node launch-game.js`。
// 游戏路径来自 runtime-config.json 的 game_path（向导写入），exe 缺失时给人话错误、退出码 1。
// 文案由 Node 打印：bat 必须保持纯 ASCII（坑 36），Node 输出走 Win32 宽字符 API，与代码页无关。
'use strict';

const mods = require('./src/mods');

try {
  const r = mods.launchGame();
  console.log(`已启动游戏：${r.exe}`);
  console.log('游戏登录界面随便填账号和密码，点「注册」就能进服。');
} catch (err) {
  console.error(`启动游戏失败：${err.message}`);
  process.exit(1);
}
