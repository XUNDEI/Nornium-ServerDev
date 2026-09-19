# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/) 与
[Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 格式。

## [Unreleased]

### Added

- **服务端控制台指令**（`src/console.js`）：在运行服务端的窗口里直接输入指令回车——
  `restore` 清空本地存档（先踢掉全部在线连接，等 300ms 断连排空后再删
  `accounts.json` + `players/`，并同步重置内存账号表，服务端继续运行，发布干净正式版用）；
  `load` 从磁盘热加载存档（把备份拷回 `server\data\` 后不用重启即可生效）；`stop` 优雅停服；
  `status` / `help`。配套回归测试 `server/test/console_check.js`
  （`npm run test:console`），其中一条专门守住「resetData 必须重置内存账号表，
  否则下一个注册请求会把旧账号整表写回磁盘」这个坑。
- **首次启动向导 `server/setup.js`**：新玩家不再需要手工往
  `%LOCALAPPDATA%\Nornium\Saved\` 拷贝任何文件，双击根目录的 `点我启动.bat` 即可：
  向导会检查 Node 版本（>=18）与 `reference/` 资产完整性、缺依赖自动跑 `npm install`、
  然后从 Steam 注册表 + `libraryfolders.vdf` + 常见盘符自动探测游戏安装位置
  （找不到才让用户输入路径），最后自动写入 `channel.lua`（`local_dev` + 8101/8089）
  与 `version.lua`（`local_build=true` 跳过热更）。结果缓存在
  `server/runtime-config.json`，第二次运行静默复用；`node setup.js --reset` 可重配。
  **注意**：本机的 Steam installdir 是 `…\steamapps\common\Nornium`，而真正的游戏根是它
  里面那层 `…\Nornium`（`Binaries\Win64\GHS-Win64-Shipping.exe` 在那层），两种写法都会被接受。
- **自动拉起游戏**：向导询问后写 `server/auto-launch.flag`，`.bat` 在启动服务端的同时
  调用 `steam://rungameid/2877160`。删掉这个 flag 文件即可关闭。
- **新号物资**：初始背包按 2026-09 的长期实测存档重算并放宽（金星贝 120 万、诺伦炬 10 万、
  诺伦透镜 12 万、王宫点数 1 万、游历经验 11600≈Lv.13、限定/常驻机票 100/200、
  杀手朋友券 99，外加 `d_role_levelbreak`+`d_weapon_levelbreak` 里出现的全部 18 种突破材料各 500）。
  理由：本服资源产出/回收尚未完善（角色升级不扣金币、部分材料没有补充渠道），
  一旦给少玩家会卡在需要消耗资源的教程/主线上，而没有官服能兜底。
- **邮件里的开源声明**：welcome 邮件之外新增一封《【必读】本项目完全免费开源》，
  明确告知本项目 MIT 开源永久免费、在不同渠道花钱买到就是被骗、应立即申请退款并举报。
  同时所有新号邮件正文改用客户端 `MailModel` 的转义写法（`@n` 换行），
  避免出现裸 `@` 被当转义符吃掉。
- 回归测试 `server/test/newplayer_check.js`（`npm run test:newplayer`），
  覆盖初始资源下限、突破材料齐全、`危航许可` 初始为 0、两封邮件的标题/附件/排序/uuid 唯一、
  以及正文过客户端 `format()` 后没有残留 `@` 与领取流程的状态机（READ → RECEIVED → INVALID/NO_ITEMS）。

### Changed

- 发布前清掉了仓库里的本地测试存档（`server/data/`：33 个账号），服务端回到全新状态。

## [0.1.0] - 2026-09-12

首个公开版本。客户端可基本正常登录并游玩。

### Added

- **M0 协议层**：HTTP 登录门（`/client/system/serverStatus`、公告、走马灯、上报）、
  TCP 帧编解码、`ntf_msg_key` 密钥协商、注册/登录/重登、心跳、重复登录踢下线。
- **M1 初始同步**：登录后 13 项初始数据，背包走 `ntf_bag_info×N → res_bag` 时序；
  新号发放 11 名初始角色（含专属武器与技能）、初始货币、经验/突破材料、全部家具与欢迎邮件；
  JSON 存档持久化。
- **M2 肉鸽闭环**：按 `map_type` 开局、六边形地图雾战揭示（含 `baseState=3` 连锁）、
  战斗/事件/资源按 `onExploreEffectTriggerID` 驱动、Boss 波次、卡牌三选一/升级/拆解、
  奇物三选一、肉鸽商店、换人、局终结算、断线重连恢复。
- **M3 抽卡 / 商店 / 内购**：卡池概率与 UP、软硬保底、`create → confirm` 两段式、
  “叮”转换、重复角色按 `d_gacha_token` 折算；NPC 商店购买/限购/折扣；
  商城直购与内购即时到账、累充积分与累充奖励领取。
- **M4 剧情与其他**：主线剧情树推进、邮件与附件领取、签到活动、困难关卡；
  `total_war`/`home` 返回安全空态。
- 协议定义 `reference/proto/`、数据表 `reference/gamedata/`、还原脚本 `tools/`。
- 协议自测 `server/test/fake_client.js`、持久化测试 `server/test/persistence_check.js`、
  专项验证 `server/test/verify_fixes.js`、熔炉/存档迁移单测 `server/test/furnace_check.js`。

### Fixed

- **恶魔熔炉卡主线**：`req_item_synthetic`（炼金合成）、`req_item_decompose`（分解）、
  `req_arm_forge`（锻造）此前一律返回失败码，导致主线「尝试一次炼金与分解」无法完成。
  现已按 `d_furnace_synthesis` / `d_furnace_decompose` / `d_equip_forge` 实现：
  合成按配方消耗材料并产出目标物、分解按 `(itemType, 稀有度)` 匹配配方并随机产出、
  锻造消耗配方材料产出装备；全部先扣后发并通过 `ntf_item_info` 同步。
- **合成蓝图无法解锁**：本版本 `d_bag_item` 中不存在 `subType=8`（蓝图）道具，合成配方
  没有任何游戏内解锁来源，熔炉「合成」按钮永远置灰。现由服务端在 `player_info.blueprint_ids`
  中下发全部合成配方 id；旧存档加载时自动补齐。
- **幽灵角色「看到这个说明没本地化」**：初始角色筛选此前只判断 `firstWeapon != 0`，
  把开发占位行 24002（`name=61124002` 无本地化、`systemAnimPath` 为空）也发给了客户端。
  现要求角色必须同时具备可本地化名称；旧存档加载时自动移除占位角色并将其装备退回背包。
- **主线任务奖励未发放**：`req_complete_plot_mission` 此前只推进任务链，不发放
  `d_task_story.reward`（如「尝试一次炼金」前一步应给 9005×10 与武器）。现按
  `[item_id, type, count]` 三元组发放并通过 `ntf_item_info` 下发。
- **角色升级后等级不保存**：背包中所有可堆叠道具此前共用 `item_uuid = 0`，而客户端升级请求
  只携带 `{item_uuid, count}`。服务端按 uuid 查背包时误命中列表中的第一件道具（通常是金币），
  导致加错经验、扣错道具，升级结果未真正写入，重开角色界面又变回原等级。
  现在每件背包道具都分配唯一非零 `item_uuid`，可堆叠道具按 `item_id` 合并；
  同一问题也顺带修复了 `req_use_item`、武器升级等所有按 uuid 定位道具的处理器。
  旧存档在加载时自动迁移（为 `uuid = 0` 的堆叠补发 uuid）。

### Known limitations

见 [README 的“已知限制”](README.md#已知限制)。
