# Nornium ServerDev

**失乐星图 Nornium（内部代号 GHS）非官方本地私服实现** —— 让已停服的官方客户端重新跑起来的本地服务端，配套完整的逆向工程文档、协议定义与数据表。

目前项目尚处早期阶段，存在大量未完成的部分和bug，如遇到bug请提交issues。**迫于时间关系，当前版本为仓促发布，可能存在主线在某处卡死的bug，我尚未来得及过完主线，抱歉**

**由于项目开发者仅有我且我忙于学业，更新速度无法保证。欢迎有有意向的大佬接手项目**

> ⚠️ **仅供学习与保存性研究。** 本项目不包含任何游戏本体或美术资源，`reference/` 中的内容
> 提取自游戏客户端、版权归原权利人所有。使用前请阅读 [NOTICE.md](NOTICE.md)。
> 您不得使用此项目用于盈利

---

## 目录

- [这是什么](#这是什么)
- [运行原理](#运行原理)
- [快速开始](#快速开始)
- [里程碑与功能](#里程碑与功能)
- [仓库结构](#仓库结构)
- [配置说明](#配置说明)
- [测试](#测试)
- [已知限制](#已知限制)
- [文档](#文档)
- [许可](#许可)

---

## 这是什么

Nornium 官方服务器已停止运营，官方客户端已无法进入游戏。本项目用
**Node.js** 尽可能复刻了官方服务端的行为：

- 完整实现登录门与游戏线协议（TCP 帧格式 + DES 加密 + protobuf `ghs.Msg` oneof 总线）
- 实现登录后的初始数据同步（角色列表、背包、商城、抽卡、主线、活动等 13 项）
- 实现主要玩法：**肉鸽（Universe）**、抽卡、商店/内购、角色养成、主线剧情、邮件、签到等
- 存档持久化到本地 JSON，重启不丢

客户端**无需任何修改**，只需在本机 `Saved` 目录写入一个指向私服的 `channel.lua`。

## 运行原理

```
Steam 启动客户端
   │
   ├─ HTTP POST 127.0.0.1:8089/client/system/serverStatus   ← 登录门（返回 status=0）
   │
   └─ TCP  127.0.0.1:8101                                   ← 游戏协议
        ├─ 服务端主动下发 ntf_msg_key（明文，DES 加密的会话密钥）
        ├─ req_register / req_login        → 建号 / 登录
        └─ 13 项初始请求（req_player、req_bag、req_character_list …）→ 进入主城
```

服务端启动后同时监听：

| 端口 | 协议 | 用途 |
|---|---|---|
| `127.0.0.1:8101` | TCP | 游戏协议（帧 + DES + protobuf） |
| `127.0.0.1:8089` | HTTP | 登录门、公告、走马灯、数据上报 |

## 快速开始

### 前置条件

- Windows（客户端仅支持 Windows）
- **Node.js ≥ 18**（实测 v24）
- 通过 Steam 安装《失乐星图 Nornium》

### 1. 双击根目录的「点我启动.bat」

就这一步。向导会自己完成剩下的工作：

1. 检查 Node.js 版本与 `reference/` 资产是否完整
2. 依赖没装就自动 `npm install`
3. **自动定位游戏安装位置**（读 Steam 注册表与 `libraryfolders.vdf`，也扫常见盘符）；
   找不到时才请你填一句游戏路径，例如 `D:\Steam\steamapps\common\Nornium`
4. 自动把指向私服的 `channel.lua` / `version.lua` 写进 `%LOCALAPPDATA%\Nornium\Saved\`
   —— 不需要你手动拷任何文件
5. 问你要不要在服务端就绪后直接用 Steam 拉起游戏

以后再双击就是秒开：路径缓存存在 `server/runtime-config.json`。想重新配置就删掉它，
或者跑 `cd server && node setup.js --reset`。

> **提示**：游戏也必须从 Steam 启动——直接双击 exe 会被 Steamworks 校验拦下。
> 「自动拉起」用的是 `steam://rungameid/2877160`；不想用了删掉 `server/auto-launch.flag`。

### 2. 启动游戏并注册

在登录界面**任意输入账号 + 密码点注册**即可进入主城。
（渠道必须是 `local_dev`；以 `_steam` 结尾的渠道会走 Steam 自动登录，无法用于私服。）

### 3. 重置存档

停服后删除 `server/data/` 目录即可；或者直接在**服务端窗口里输入 `restore` 回车**
（会先踢掉所有在线玩家，再清空存档，服务端继续运行）。

## 服务端控制台指令

在运行服务端的那个窗口里直接输入、回车执行（`点我启动.bat` 启动的窗口就是）：

| 指令 | 作用 |
|---|---|
| `restore` | **清空本地存档**（accounts.json + players/ 全删），在线玩家全部踢下线，服务端继续运行。发布干净正式版用 |
| `load` | **从磁盘重新加载存档**。把备份的 `accounts.json` / `players\*.json` 拷回 `server\data\` 后执行它即可热加载，不用重启 |
| `stop` | 踢掉所有在线玩家并停止服务端（等同 Ctrl+C，但更优雅） |
| `status` | 查看在线连接数与存档数量（账号/玩家档案） |
| `help` | 指令列表 |

注意：`restore` / `load` 都会先踢人再动文件（约 0.3 秒的断连等待），
所以执行瞬间还挂着的客户端会被顶回登录界面，属于预期行为。

<details>
<summary>想手动操作 / 不能双击 bat 时（点开看手工步骤）</summary>

```bat
cd /d <本仓库>\server
npm install
node setup.js          :: 定位游戏 + 写客户端配置（可加 --reset 重配）
npm start              :: 启动服务端
```

手动放置的接入点与上一节第 4 步等价：

`%LOCALAPPDATA%\Nornium\Saved\channel.lua`
```lua
return {"local_dev", 8101, "127.0.0.1", "8089"}
```

`%LOCALAPPDATA%\Nornium\Saved\version.lua`（第三项 `local_build = true` 跳过热更检查）
```lua
return {"1.0.1", "cb4_alpha_3_steam", true}
```

注意必须是 `%LOCALAPPDATA%` 下的 Saved 目录，pak 内的同名文件会覆盖游戏安装目录中的 loose 文件。

</details>

## 新号初始资源

本服的资源产出/回收链路还没补全（角色升级不扣金币、部分材料缺少补充渠道），
而官服早已停运、没有任何兜底——所以**新号的初始背包按长期实测存档重算并放宽**，
让「资源不够」不成为卡住教程或主线的理由：

| 资源 | 数量 | | 资源 | 数量 |
|---|---|---|---|---|
| 金星贝 | 1,200,000 | | 诺伦机票（限定池） | 100 |
| 诺伦炬 | 100,000 | | 都城机票（常驻池） | 200 |
| 诺伦透镜 | 120,000 | | 杀手朋友券（扫荡/替补门票） | 99 |
| 王宫点数 | 10,000 | | 角色/武器经验道具 | 小×999 中×200 大×50 |
| 游历经验 | 11,600（≈Lv.13） | | 突破材料 | 全部 18 种 ×500 |
| 补给配额 / 时枝化石 / 珊瑚劫灰 | 999 / 9999 / 9999 | | 全部家具 | ×3 |

邮件箱里另有一封可领取的开局物资。
**危航许可（1201003）刻意不预发**：官方口径是每次登录跨过 04:00 才发 6 张，
本服保持一致（`daily.grantDailyPermits`，登录时调用），不足时可用杀手朋友券顶替。

> ⚠️ **本项目完全免费开源，请以实际行动甄别收费骗局。**
> 如果你是通过网购、二手平台、QQ 群或所谓的「一键端」「商业版」花钱买到它的，**你被骗了**
> ——请立刻申请退款并举报该商品。游戏中第一封邮件也会提醒这一点。

## 里程碑与功能

| 里程碑 | 状态 | 内容 |
|---|---|---|
| M0 协议跑通 | ✅ | 登录门、密钥协商、注册/登录/重登、心跳、重复登录踢下线 |
| M1 进入游戏 | ✅ | 13 项初始数据全应答；背包 `ntf_bag_info×N → res_bag`；新号 10 名初始角色；JSON 持久化 |
| M2 肉鸽闭环 | `部分实现` | 六边形地图雾战揭示、`d_srpg_effect_trigger` 驱动的探索后果（事件/遭遇战/资源/卡牌三选一）、首领按 `appearTime` 计步出现且每回合向基地推进 1 格、建筑格（卡牌/蓝图）部署与晋升、卡牌三选一与奇物、局终结算、断线恢复 |
| M3 抽卡与内购 | `部分实现` | 卡池概率/UP/软硬保底、create→confirm 两段式、叮、重复角色折算、NPC 商店、商城直购与累充 |
| M4 剧情与其他 | `部分实现` | 主线剧情树与任务奖励、恶魔熔炉（炼金合成/分解/锻造）、每日危航（日常副本 `d_levels`）、家园家具摆放与交互、欢迎邮件、签到活动、困难关卡；`total_war` 安全空态 |

## 仓库结构

```
ServerDev/
├── README.md                 本文件
├── 点我启动.bat           双击即全动：初始化 → 写客户端配置 → 起服务端 → 拉起游戏
├── CHANGELOG.md              版本变更记录
├── NOTICE.md                 版权与免责声明
├── LICENSE                   代码许可（MIT，不含 reference/）
├── server/                   Node.js 服务端
│   ├── index.js              入口：HTTP 8089 + TCP 8101
│   ├── setup.js              首次启动向导：定位游戏路径 + 写客户端配置
│   ├── src/console.js        服务端控制台指令（restore / load / stop / status / help）
│   ├── package.json
│   ├── preflight.js          加密/协议预检脚本
│   ├── runtime-config.json   向导产物（gitignore）：缓存的游戏路径
│   ├── auto-launch.flag      向导产物（gitignore）：存在则自动拉起 Steam 游戏
│   ├── src/
│   │   ├── crypt.js          DES-ECB + ISO 7816-4 填充
│   │   ├── protos.js         protobufjs 加载 + cmd 反射映射
│   │   ├── session.js        连接会话：帧编解码、密钥协商、FIFO 队列、心跳
│   │   ├── gamedata.js       数据表加载/查询
│   │   ├── store.js          存档原子写持久化
│   │   ├── logger.js         日志
│   │   ├── httpgate.js       HTTP 登录门
│   │   ├── game/             领域逻辑：items / player_new / universe / gacha / shop / mall / daily
│   │   └── handlers/         消息处理器：login / sync / character / universe / gacha / …
│   └── test/                 协议自测（fake_client / persistence_check / verify_fixes / daily_check / universe_check / newplayer_check / console_check）
├── tools/                    逆向辅助脚本
│   ├── gen_proto.py          proto.pb → .proto 还原
│   └── convert_gamedata.py   数据表 Lua → JSON 转换
└── reference/                逆向资产（只读，见 NOTICE.md）
    ├── client_lua/           客户端 Lua 源码（协议唯一权威）
    ├── gamedata/             109 张数据表 JSON（服务端运行时读取）
    ├── proto/                还原的 26 个 .proto 源文件（服务端运行时读取）
    ├── proto.pb              原始 FileDescriptorSet
    └── lua-crypt.c           客户端 DES 同源实现
```

## 配置说明

| 项 | 默认 | 说明 |
|---|---|---|
| TCP 端口 | `8101` | `server/index.js` 中的 `TCP_PORT` |
| HTTP 端口 | `8089` | 同上 `HTTP_PORT` |
| 监听地址 | `127.0.0.1` | 仅本机 |
| `GHS_VERBOSE` | 未设置 | 设为 `1` 时日志输出每条消息的 protobuf 明文摘要 |
| 存档目录 | `server/data/` | `accounts.json` + `players/<id>.json` |
| 游戏路径缓存 | `server/runtime-config.json` | 首次启动向导生成，删掉即重新配置 |
| 自动拉起游戏 | `server/auto-launch.flag` | 存在才拉起（`steam://rungameid/2877160`） |

## 测试

先启动服务端（或在单独窗口运行 `npm start`），然后：

```bat
cd server
npm test                        :: 全流程协议自测（fake_client.js，75+ 项断言）
npm run test:furnace            :: 熔炉/存档迁移单测（无需启动服务端）
npm run test:plot               :: 主线任务链（subTaskid 下发）/旧存档修复单测（无需启动服务端）
npm run test:daily              :: 每日危航（日常副本）解锁/扣票/掉落/扫荡单测（无需启动服务端）
npm run test:universe           :: 星图（肉鸽）地图绑定/建筑格附件/效果参数解读/新号教学链重放/首领波次与推进/存档迁移单测（无需启动服务端）
npm run test:newplayer          :: 新号初始资源下限/突破材料齐全/邮件（含开源声明）与领取流程单测（无需启动服务端）
npm run test:console            :: 服务端控制台指令 restore/load/stop/status 的行为单测（无需启动服务端）
npm run test:fixes              :: 累充/抽卡保底/页签隐藏专项
npm run test:persistence        :: 重启持久化（自行拉起/杀掉服务端，需先停手动实例）
```

`fake_client.js` 完整模拟真实客户端的线协议（HTTP 门、TCP 帧、DES/ISO7816-4 填充、
protobuf oneof、FIFO 请求配对），断言全绿表示服务端侧就绪；最终以真实客户端验收为准。

## 已知限制

- 武器/防具升级、突破、精炼为宽松实现（不严格校验材料，状态会持久化）。
- 恶魔熔炉的炼金合成、分解、锻造已实现；锻造的 `feed_item_uuid` 仅接受不消耗（不生成随机词条）。
- `total_war`（总力战）战斗仅返回安全错误码，未实现战斗闭环。
- 日常副本（每日危航）已实现完整闭环，含官方「每天 04:00 发放 6 张危航许可」的每日重置；
  官方同批发出的 4 个日常任务的每日刷新尚未实现（`d_task` 任务目前常驻可做）。
- 月卡（`d_mall` 1007 / shopType 202）已实现购买续期与每日奖励领取（每日奖励上限由客户端
  按 `d_gacha_monthly_pass.maxLasting` 自行限制）。
- 角色升级目前只消耗经验道具，**未扣升级金币**（客户端仅做本地校验）。
- 肉鸽内任务为简化版；首领按 `d_srpg_level_boss.appearTime` 计步出现，并**每回合沿最短路径向
  巡航基地推进 1 格**，抵达后每回合扣 1 点生存值（官方口径见 `d_word_cn` 113211012）。
  开局生成波次时会把「落点 → 基地」的整条走廊一并揭示为可达格（客户端画首领连线与
  `astar` 取点都需要 `state > 1`）。
- 主线「部署/晋升/拆除1个建筑」期间**客户端会自己禁用探索与跃迁**
  （`QuestSystem:IsExploreBlocked` 读 `d_task_story[..].unExplore == 1`），
  此时若场上的建筑蓝图凑不出 2 张同名副本就会无解。官方的教学轨道是自洽的
  （`11003` 给 1 张、`11007` 再给 3 张同名蓝图，`npm run test:universe` 有整套重放断言），
  但私服没有客户端教学脚本护栏、玩家可能偏离轨道，因此服务端加了一层**教学保险**：
  在「探索已被锁 + 场上蓝图凑不出副本」时补发缺的同名蓝图（幂等，记录在
  `universe.repaired_cards`）。这是私服兜底，不属于官方行为。
- `d_srpg_effect_trigger` 的效果派发已覆盖 1 资源 / 2 生存值 / 3 舰武载弹 / 11、13、15
  卡牌三选一 / 12 异宝三选一 / 20 事件 / 30 遭遇战 / 60 道具 / 201 剧情；
  9/10/17/21/99/100/121/122 的 `effectConfig` 语义未确认，目前忽略（对 100 只会打一次日志，
  不阻塞游玩）。
- 好友/聊天等社交功能未实现（消息兜底为空应答，不阻塞客户端）。
- 单机/少人设计：存储为同步 JSON 文件，未做高并发优化。

### GM 命令（`req_gm_cmd`）

| 命令 | 作用 |
|---|---|
| `add_item <itemId> <count>` | 往背包发道具/货币 |
| `add_character <characterId>` | 直接解锁角色 |
| `add_card <cardId> <count>` | 往**当前远航的蓝图手牌**里塞建筑蓝图（蓝图不在背包，卡死时用这个救） |

### 后续开发建议优先级

日常任务的 04:00 刷新 > 角色升级扣金币 > 星图 `effectType 100/121/122` 语义还原 >
武器精炼严格校验 > `total_war` > 社交。

## 文档

- **[CHANGELOG.md](CHANGELOG.md)** —— 版本变更。
- **[NOTICE.md](NOTICE.md)** —— 版权与免责声明。
- **[reference/README.md](reference/README.md)** —— 逆向资产说明与重新生成方法。

> 开发者在本地另有一份 `REVERSE_ENGINEERING.md`，汇总协议规格、加密细节、数据表说明与
> 完整坑位清单。该文档包含解包密钥等信息，**不随本仓库发布**（已在 `.gitignore` 中排除）。

## 许可

- `server/`、`tools/` 及本项目文档：**MIT**，见 [LICENSE](LICENSE)。
- `reference/`：**不属于本项目**，版权归原权利人所有，仅作研究用途，见 [NOTICE.md](NOTICE.md)。
