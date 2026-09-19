# Nornium（GHS）本地私服服务端

本目录是服务端实现。总体说明、法律声明与快速开始请先看
[仓库根 README](../README.md)；协议/数据表的说明见 [reference/README.md](../reference/README.md)。
（开发者本地另有一份汇总协议与坑位的 `REVERSE_ENGINEERING.md`，不随仓库发布。）

Node.js（原生 Windows，实测 v24），仅依赖 `protobufjs` + `des.js`。

## 启动

推荐方式：双击仓库根目录的 `点我启动.bat`，它会先跑初始化向导（`setup.js`）再起服务端。

手工方式：

```bat
cd /d <本仓库>\server
npm install
node setup.js     :: 首次启动向导：定位游戏路径 → 写入客户端配置
npm start
```

`setup.js` 会自动定位《失乐星图》的安装目录（Steam 注册表 → `libraryfolders.vdf`
→ 常见盘符扫描，找不到才请你输入路径），然后把
`return {"local_dev", 8101, "127.0.0.1", "8089"}` 写入
`%LOCALAPPDATA%\Nornium\Saved\channel.lua`，同目录 `version.lua` 写
`return {"1.0.1", "cb4_alpha_3_steam", true}`(第三项 `local_build=true` 跳过热更检查)，
**不需要手工拷文件**。

| 参数 | 说明 |
|---|---|
| `--game-path=<dir>` | 非交互模式指定游戏目录（CI/自用） |
| `--yes` | 所有提问取默认值（配合上面的朋友一起用） |
| `--reset` | 忽略缓存的 `runtime-config.json`，重新配置 |

向导产物：`runtime-config.json`（路径缓存）与 `auto-launch.flag`
（存在则 `.bat` 会用 `steam://rungameid/2877160` 自动拉起游戏），两者都已 gitignore。

## 控制台指令

服务端运行时，在启动它的窗口里直接输入指令回车（`.bat` 用 `node index.js` 直启，
stdin 直通；`npm start` 也可以）。实现见 `src/console.js`：

| 指令 | 作用 |
|---|---|
| `restore` | 清空本地存档（先踢掉全部在线连接再删 `accounts.json` + `players/`，并重置内存账号表），服务端继续运行 |
| `load` | 从磁盘重新加载存档（先踢人）。把备份拷回 `data\` 后热加载用，不用重启 |
| `stop` | 踢掉所有在线玩家后优雅退出 |
| `status` | 在线连接数 + 存档数量 |
| `help` | 指令列表 |

`stop` / Ctrl+C / SIGTERM 走同一条 `shutdown()`；`restore` / `load` 在踢人后等 300ms
再动文件（等 socket 真正断开），防止残余会话的 `savePlayer` 把旧档案写回磁盘。
`store.resetData()` 会同时重置内存账号表——否则下一个注册请求会把整张旧账号表写回去。

启动后同时监听：

- **TCP 127.0.0.1:8101** —— 游戏协议（帧格式 + DES 会话加密 + protobuf `ghs.Msg` oneof 总线）
- **HTTP 127.0.0.1:8089** —— 登录门（`/client/system/serverStatus`、公告、走马灯、上报）

客户端需在 `%LOCALAPPDATA%\Nornium\Saved\channel.lua` 写入
`return {"local_dev", 8101, "127.0.0.1", "8089"}`，并从 Steam 启动游戏。
这一步已由首启向导 `setup.js` 自动完成（见上文）。

## 脚本

| 命令 | 说明 |
|---|---|
| `npm start` | 启动服务端 |
| `npm run setup` | 首次启动向导（定位游戏路径 + 写客户端配置） |
| `npm run preflight` | 加密/协议预检（DES 向量、proto 加载、cmd 反射） |
| `npm test` | 全流程协议自测（需先启动服务端） |
| `npm run test:furnace` | 熔炉（炼金/分解/锻造）与存档迁移单测（无需服务端） |
| `npm run test:daily` | 每日危航解锁/扣票/掉落/扫荡单测（无需服务端） |
| `npm run test:newplayer` | 新号初始资源 / 邮件（含开源防骗声明）单测（无需服务端） |
| `npm run test:console` | 控制台指令 restore/load/stop/status 行为单测（无需服务端） |
| `npm run test:persistence` | 重启持久化测试（自行拉起/杀掉服务端，先停手动实例） |

`test/fake_client.js` 完整模拟真实客户端的线协议（HTTP 门、TCP 帧、DES/ISO7816-4 填充、
protobuf oneof、FIFO 请求配对），断言全绿表示服务端侧就绪；最终以真实客户端验收为准。

## 目录结构

```
server/
  index.js                 入口：HTTP 门 + TCP 服务
  setup.js                 首次启动向导：定位游戏目录 + 写客户端 channel/version.lua
  preflight.js             加密/协议预检
  src/
    logger.js              日志（console + logs/server.log，GHS_VERBOSE=1 开启收发明细）
    console.js             控制台指令：restore / load / stop / status / help
    crypt.js               DES-ECB + ISO 7816-4 填充（同源 lua-crypt.c），会话密钥为 8 字节可打印 ASCII
    protos.js              protobufjs 加载 reference/proto（keepCase），反射取 cmd 字段号
    session.js             连接会话：帧编解码、密钥协商、FIFO 请求队列、心跳
    gamedata.js            reference/gamedata/*.json 加载与查询（数字键字符串化兼容）
    store.js               data/accounts.json + data/players/<id>.json 原子写持久化
    httpgate.js            8089 登录门
    game/                  领域逻辑：items(背包/货币)、player_new(新号)、universe(肉鸽)、gacha、shop、mall
    handlers/              消息处理器：login、sync(13 项初始数据)、character、social(剧情/邮件/活动/杂项)、
                           universe、gacha、shop、mall、index(分发与未知消息兜底)
  test/                    fake_client.js / persistence_check.js / verify_fixes.js / furnace_check.js
                           daily_check.js / universe_check.js / plot_check.js / newplayer_check.js
  data/                    运行时生成（accounts.json、players/），已 gitignore
  runtime-config.json      首启向导产物（gitignore）：缓存的游戏路径
  auto-launch.flag         首启向导产物（gitignore）：存在则自动拉起 Steam 游戏
```

## 重置存档

停服后删除 `data/` 目录。
