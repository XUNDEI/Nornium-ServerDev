# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/) 与
[Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 格式。

## [Unreleased]

### Added

- **「角色 → 7★ 专武」官方映射落地，专武发放全面修正**：
  - 此前版本断言数据表里没有「角色→专武」关联，按「同类型最高稀有度」猜推荐武器 ——
    十人里指错四个（10102/10601 都指到「游侠的准绳」2061610、10501/10701 都指到
    「灼星已现」1071611，辩才姬因此被指到信风的武器上）。本次在数据表里找到了官方关联：
    `d_word_cn` 的武器描述占位文本（**id = 54 + 武器id**，如「信风专武描述」「理事卿专武描述」，
    豌豆公主的 2040601「青鸟」甚至是写好的正式文案）与 `d_character_trial.firstWeapon`
    （试用配枪，骆十四娘直接配 7★ 7070611）；`d_gacha_schedule` 武器UP池成对出现同族
    6★+7★ 佐证两形态同源；11202→708 族由「十族专武与十人一一对应」排除法锁定。
    映射与证据注释见 `game/weapon_data.js` 的 `CHARACTER_EXCLUSIVE_WEAPONS`。
  - 发放：新增 `grantExclusiveWeapons`（每人一把 7★ 专武，共 10 把）与编辑器操作
    `grant_exclusive_weapons`、控制台指令 **`allexclusive [账号|all]`**；编辑器角色页新增
    「发放全部专武（七星）」按钮，角色弹窗改为显示「专武：<7★ 名>（id）· 6★ 基础形态：<名>（id）」，
    「发放专武（7★）」按钮单发。6★/7★ 数值完全相同（坑 39），7★ 是最终形态。
  - 目录接口字段 `best_weapon` 改名 `exclusive_weapon`（7★）并新增 `exclusive_weapon_base`（6★）；
    「同类型最高稀有度」的猜测式 `bestWeaponForCharacter` 移除。
  - 测试：`test/weapon_check.js` 新增专武映射段（十人逐一断言、全部已实装 7★、类型匹配、
    6★/7★ 同族）与 `grantExclusiveWeapons` 幂等段；`test/editor_check.js` 断言 catalog
    专武值与新操作端到端；`test/editor_ui_check.js` 断言专武按钮/弹窗文案/待保存清单；
    `test/console_check.js` 断言 `allexclusive` 指令。

- **端口被占自动换随机端口（最多重试 20 次）**：TCP 8101 / HTTP 9089 任一监听失败
  （`EADDRINUSE` 被占用，或 `EACCES` 被 winnat/Hyper-V 保留段拒绝）时，自动换随机端口
  重试（20000–45000，避开 Windows 动态端口段），20 次全失败才带人话报错退出；
  维护窗口重听、编辑器状态页、启动横幅都用实际端口。端口偏离默认值时自动把客户端
  `channel.lua` 同步成实际端口（游戏重启后生效），渠道名保持原值不动。
  测试：`test/port_retry_check.js`（`npm run test:port`）——默认端口被占两个监听都挪走 +
  channel.lua 同步 + `ntf_msg_key`/`serverStatus` 可用；兜底范围用
  `GHS_PORT_FLOOR/CEIL` 缩到 20 个端口并全部占满，断言进程以退出码 1 终止。
  默认端口可用 `GHS_TCP_PORT`/`GHS_HTTP_PORT` 环境变量覆盖（测试注入口）。

- **星图资源自动补发（肉鸽便利功能，解决「宇宙里切几次角色货币就不够」）**：
  - 远航中的 4 种肉鸽资源（`res_value`）在任何消耗（切换角色 `substitutionCost`、游商
    购买/刷新、建筑晋升/召回、卡牌/异宝三选一重掷）后低于保底线（默认 **100** = 开局资源）
    时自动补回，低于本次费用时先补足再扣——**切角色不再弹 `cmd:1018 code:4`**。
    补发通过 `ntf_universe_info` 增量推给客户端（客户端按本地副本决定按钮可不可点，
    只在服务端记账客户端永远看不到，见坑 25 的对称约束）。
  - 开关与保底线：`server/runtime-config.json` 加 `"universe_auto_grant": false`（恢复官方
    经济，扣不动回 `RES_NOT_ENOUGH(4)`）或 `"universe_resource_floor": <数值>`；
    **编辑器「总览」页的宇宙资源卡片里也有同一个开关**（改完立即生效，无需重启）。
  - 手动发放：**编辑器「总览」页新增「宇宙资源」卡片**（进行中的远航才有，资源 2 =
    金刚凝胶，直接改数字进待保存清单；在线存档保存后游戏内即时生效并推送，
    离线存档重登后生效）；游戏内 GM 指令 **`add_res <1..4> <数量>`**（负数即扣减）；
    服务端控制台 **`addres [账号|all] <1..4> <数量>`**（走维护窗口，重登后生效）。
  - 测试：`test/universe_check.js` 新增自动补发段落（满资源/空钱包/反复切换/关开关恢复
    官方行为/GM 指令，环境变量 `GHS_UNIVERSE_GRANT` 注入配置避免依赖开发机
    runtime-config.json）；`test/editor_check.js` 新增 `set_universe_res` 操作与
    `/editor/api/server/universe_grant` 端点断言（`GHS_RUNTIME_CONFIG` 隔离配置文件）；
    `test/editor_ui_check.js` 断言总览页卡片渲染与开关状态回填；
    `test/fake_client.js` 的付费图换角色断言改为「3 次全部成功 +
    扣费与补发增量成对出现（净 0）」；其余段落默认在关闭状态下跑以继续守护官方经济数值。

- **游戏启动器（编辑器新增「游戏启动器」工作区，M5）**：
  - **启动与状态页**：一键经 Steam 拉起游戏（`steam://rungameid/2877160`）、游戏目录与
    主程序指纹、Paks 目录与 mod 补丁（`GHSMods_P.pak`）安装状态；游戏更新后提示「建议重建」。
  - **Mod 管理页**：导入（zip/目录，零依赖 ZIP 解析）、启用/禁用、↑↓ 调优先级
    （**越靠下越优先**）、删除（手输 id 确认）、自动冲突报告（同名文件按优先级裁决并列出胜者）、
    「合并启用 mod → 安装到游戏」（repak 打成单个 V8B 不加密补丁 pak 放进游戏 Paks 目录，
    **原版 pak 零改动**，卸载 = 删一个文件）与「只看合并预览」。
  - **服务端数据表补丁**：启用 mod 的 `server_patch/*.json` 按 id 深合并进
    `reference/gamedata/`（首次应用前自动备份原表，可一键精确还原）；应用后
    `gamedata.reload()` 热重载，运行中的服务端即时生效，无需重启。
  - 新模块：`server/src/mods.js`（仓库/校验/合并/打包/安装/补丁）、`server/src/zip.js`
    （零依赖 ZIP 读写）；HTTP 接口 `/editor/api/game*`（editorapi.js `handleGameApi`）。
  - mod 格式规范 **`docs/MOD_FORMAT.md`**（开放格式：`mod.json` + `files/` +
    `server_patch/`，文本编辑器即可写数据 mod）+ 第三方校验工具 **`tools/validate_mod.js`**
    （与启动器导入同一份校验器）；使用说明 **`docs/LAUNCHER.md`**。
  - 测试：`npm run test:launcher`（校验/导入/穿越防护/冲突裁决/补丁应用还原/
    repak 端到端——本机没装 repak 时该段自动 SKIP）；`editor_ui_check` 扩展到
    11 个标签页与三工作区切换。
  - `REVERSE_ENGINEERING.md` 新增第 14 节「Mod 能力调查」：补丁 pak / 热更通道
    （Update.lua + UChunkCore + GHSChunkDownloader）/ Saved 注入边界的完整证据链，
    以及加新角色的数据驱动管线（`d_char_clothes` 换装、fightModelPath 反查、
    每角色私有骨架与动画库、变身=独立机甲网格体）。


- **角色页支持单角色精细化编辑**（点角色卡片打开弹窗，原先只有「全部解锁」这种粗粒度开关）：
  - **逐孔勾选星位**（`#talList`，23 个 chip，悬停显示「孔 N · 名字 · 条件」，另有
    「全选 / 只留初始孔」）；不再只有「点亮全部星位」。
  - **逐件勾选皮肤 + 指定穿戴**（战斗 / 机甲 / 主城三类各自成组，每件一个 chip，
    另有该类的穿戴下拉框，0 = 默认）。
  - **逐个技能改等级**（列出该角色全部主动/被动技能，超过 `d_skill_fight_level`
    的上限时自动夹住并在结果里说明）。
  - **机甲换装**（六个部位：显示当前装备 + 该部位背包里的候选；卸下的回背包，
    同部位换装时旧件自动回背包）。
  - 服务端新增六个精确 op：`set_talents` / `set_skins` / `set_worn_skin` /
    `set_character_skills` / `equip_arm` / `unequip_arm`，全部沿用既有
    `/editor/api/player/:id/update` 通道（在线即时生效、离线写档），
    `equip_arm` / `unequip_arm` 的载荷口径与 `req_character_equip_arm` 一致。
  - `/editor/api/catalog` 的角色条目新增 `talents` / `skins` / `skills` 明细，
    顶层新增 `equips`（六个部位共 60 件机甲），编辑器因此能显示机甲名字，
    背包也多了「机甲」分类。
  - 在线推送顺序改为**先 `ntf_character_info` 再 `ntf_item_info`**：客户端
    `BackpackSystem.lua:345` 只在载荷带 `item_extra` 时按 uuid 在**当前**已装备列表里
    找它（`bEquipped`），同部位换装时若道具先到，客户端会认为换下的那件还在身上、
    于是永远不进背包，随后角色 ntf 又把它移出装备列表——机甲在界面上凭空消失。
- **网页控制台的自动补全与输出分级**：
  - 输入框支持 **Tab 补全**（指令名 / 账号 / 快照目录 / 角色 id，`addchar` 支持两个参数位）、
    ↑↓ 在候选面板里移动（面板没开时仍是翻历史）、危险指令在候选里带「危险」标签。
  - 输出按级别着色：普通 / 调试 / **警告**（橙色） / **错误**（红色） / «指令回显»，
    级别的判定仍是服务端日志里的 `[I]/[V]/[W]/[E]` 前缀，裸 `>>` 行视为指令回显。
- **危险操作改为红色**：危险区（清空存档 / 停止服务端）用红色实线框 + 淡红底，
  危险按钮（清档 / 停服 / 清空月卡 / 背包行内删除）用红色描边与文字，
  确认弹窗的手输框也会变红。仍然保留「手输确认串」这一道语义闸门。
  `style.css` 的设计语言注释同步更新：彩色只剩两处——连接状态灯与危险操作。
- **服务器 GitHub 地址（<https://github.com/XUNDEI/Nornium-ServerDev>）在四个入口可见**：
  服务端启动横幅、控制台 `help` / `status`、网页编辑器侧栏底部（`#repoLink`，
  链接文本由 `/editor/api/server` 的 `repo_url` 驱动）、编辑器「使用说明」。
  `server/package.json` 新增 `homepage` 字段作为单一来源。
- **日志降噪**：`req_ping` 心跳、13 条初始状态同步、HTTP 轮询（`/client/marquee/list` 等）
  不再逐条写 `info`（改成 `log.verbose`，需要时用 `GHS_VERBOSE=1` 打开）；
  新增 `src/activity.js` 每 5 分钟汇总一行
  `[activity] 近 5 分钟：心跳 N 次 · 状态同步 M 次 · 其他请求 K 次 · 连接 +a/-b · 在线 c 人`
  （零流量时不打），停服前会把最后一窗 flush 掉。
- **一键启动的紧凑输出**：`点我启动.bat` 在「配置已存在 + 依赖已装 + 客户端配置没变」时
  只打横幅 + 「环境已就绪…（配置未改动）」+ 第 2 步提示（约 14 行，原 ~30 行）；
  首次运行/配置变化/依赖缺失时仍是原来那份逐步骤的完整输出。

### Removed

- **移除锁帧兜底（`src/framefix.js`）**：客户端设置界面的帧率选项不落盘是客户端自身的
  持久化 bug（8.13/坑 45），私服不再在服务端启动时往客户端 ini 里钉锁帧键。
  跑过旧版本的机器上，曾写入的键**不会自动消失**：`GameUserSettings.ini` 两个
  GameUserSettings 节的 `FrameRateLimit=60.000000`、`Engine.ini` 的
  `[/Script/Engine.Engine] bSmoothFrameRate=False` 与 `[SystemSettings] t.MaxFPS=60`
  —— 想还原引擎默认帧率就手动删掉这几行，保留则等于继续锁 60 帧。
  `index.js` 使用的 `savedDir()`（channel.lua 端口同步依赖）已内联进 index.js。

### Fixed

- **星图「额外建筑格」探索后无法部署建筑（图 3~7）**：额外建筑格
  （`d_srpg_main_pos_base` 104，B01_Nothing，nameId 11310104「提供额外的可用建筑格！」）
  官方语义是**开局无卡位、踩上探索时**由探索效果 trigger 122（effectType 122，
  `effectConfig [1]` = `d_srpg_card_pos` 普通卡位）把该格变成可用建筑格。旧服务端
  `attachForPos` 只认 A47_FreeCard / A39_Building* / nameId 102000101/102000102
  （初始建筑格 101 命中、额外格不命中），`applyEffect` 又把 121/122 标为「语义未确认」
  忽略 —— 格子永远没有 `main_pos_card_pos_info`，客户端不显示「部署建筑」（坑 28 同机制）。
  图 1/2 的布局只有初始建筑格所以此前未暴露；mapdata 17/18（图 3~7）是
  「101×2~3 初始格 + 104×6 额外格」布局。修复：`applyEffect` 新增 case 122 ——
  挂卡位并推 `ntf_main_pos_add_attach`（客户端 `SrpgController.lua:279` 原生追加进格子；
  已有卡位时幂等跳过，不覆盖已部署建筑），`refreshAttach` 给旧存档里**已探索**的
  额外格补卡位（未探索的保持空位；`cardPosAttach` 行号缺省时返回 null 而不是兜底
  卡位 1，否则剧情图基地格会被误挂）。effectType 121（仅游商格携带、config 1..6
  超出卡位表 3 行）维持未确认。详见坑 48。
  测试：`test/universe_check.js` 新增额外建筑格段（探索解锁 + `ntf_main_pos_add_attach`
  内容 + 解锁后可部署 + 初始格 122 触发不覆盖原卡位 + 旧档修复幂等）。

- **武器光淬（精炼）后客户端显示「光淬0阶 → 光淬0阶」、前后效果描述相同**：
  服务端 `reqWeaponRefine` 只把 `refine_level` +1 并存档，从不推送 `ntf_item_info`；
  而客户端收到 `res_weapon_refine` 只广播「成功」，效果变动弹窗从背包缓存读新阶数，
  背包缓存只随 `ntf_item_info` 更新 —— 于是新旧阶都读到旧值，两段描述自然相同。
  现在升阶成功后**先推 `ntf_item_info`**（目标武器 `count=0` + 完整 `weapon_info`，
  命中客户端背包「整条替换」分支；已装备武器走 `item_extra` 分支原地刷新），再回
  `res_weapon_refine`。同时补上 `d_weapon.maxRefine` 上限守卫（到顶回 result=1，
  不再无限升阶 —— 超顶后客户端查 `d_skill_fight_level` 会落空）。
- **光淬素材消耗的两个伴随问题**：① `req.stuff_item_uuid` 是 repeated 字段，
  旧实现 `Number(array)` 在多选素材时得到 NaN、一个都不扣；现在遍历数组逐个扣除。
  ② 服务端扣掉的素材从不推给客户端，背包里被吃的武器要重登才消失；现在每个被消耗
  的素材以 `count=-1` 并进同一次 `ntf_item_info`，客户端即时同步。
  回归断言：`test/weapon_check.js` 光淬段（ntf 先于 res / 多素材全扣 / 到顶拒绝）。
- **锁 60 帧兜底修正（坑 14 的续集）**：上一版往 `Saved\Config\Windows\GameUserSettings.ini`
  写 `bUseSmoothFrameRate=False` 的做法**在这个 UE 构建里根本没人读** —— 用 repak 解出
  pak 内的 `DefaultEngine.ini` / 默认 `GameUserSettings.ini` 后确认：游戏自己的
  `[/Script/Engine.GameUserSettings]` 序列化里从来没有这个键，冷前端指向的
  `SetUseSmoothFrameRate` / `ApplyFrameRateLimit` 等 BP 函数才是真正写 `t.MaxFPS` 的地方，
  而它们只在游戏内改设置时被调用一次。所以真正能兜住的是引擎侧的两处配置：
  `Saved\Config\Windows\Engine.ini` 的 `[/Script/Engine.Engine] bSmoothFrameRate=False`
  与 `[SystemSettings] t.MaxFPS=<N>`（Saved 覆盖 pak 内的默认值），再保留
  `GameUserSettings.ini` 的 `FrameRateLimit=<N>`。三个键仍然幂等、保留 CRLF、
  只动这几行，`frame_lock_fps: 0` 依旧是总开关；下一次启动游戏时生效。
- **修复 `mergeIniSection()` 追加新节时把已有 CRLF 变成 `\r\r\n` 的老 bug**：追加分支原本对
  整段文本做了一次 `\n → \r\n` 全局替换，于是第二遍执行时行尾已经坏掉、幂等性失效
  （写 `t.MaxFPS` 到 `[SystemSettings]` 时第一次踩到）。现在只对新增块用文件的 EOL。
- **修复编辑器「死键」残留**：不再写 `bUseSmoothFrameRate`，并把它从两节里删掉
  （老存档里被上一版写进去的那行会在下次启动时清掉），避免误导后来人。
- **`node setup.js --check`（别名 `--doctor`）：只读环境自查**。回答玩家/作者最常问的三件事：
  ① 我这份代码是修好的吗（旧版的依赖自动安装 100% 失败，坑 47）；
  ② 我机器上的依赖到底装了没、下次启动会不会再走安装那一步；
  ③ 游戏目录与客户端 `channel.lua` / `version.lua` 还对不对。**不改文件、不装依赖、不写配置、
  不 spawn 任何外部命令**，所以依赖缺失时也能跑起来（`preflight.js` 反过来——它 require
  protobufjs，依赖没装就直接崩，正是不该用它排查这类问题的原因）。
  输出六段：Node / npm（含"下次装依赖会执行哪条命令"）/ 逆向资产 / 依赖状态 /
  向导状态（游戏目录是否仍有效、两个 lua 是"已是私服配置/内容不对/不存在"）/ 代码版本判定，
  最后给一句结论；就绪返回 0，有问题返回 1（可脚本化）。
- 版本判定 `sourceLooksFixed()`：匹配 `npmCliScript(` 且不再出现裸 `spawnSync('npm'…)`。
  **必须先剥掉注释再匹配**——修复后的文件里恰好引用了旧写法当反面教材（本文件自己的注释里
  就写着 `spawnSync('npm.cmd', ['install'])`），不剥离会把修好的文件判成旧版（自检第一次跑
  就踩了这个坑，已写进注释与断言）。

- **全新下载后「首次运行正在安装依赖 → 依赖安装失败」——向导根本没把 npm 起起来（坑 47）**。
  玩家反馈：双击「点我启动.bat」后停在
  `首次运行：正在安装依赖 protobufjs、des.js …` → `依赖安装失败，请在 server 目录手动执行
  npm install 后重试。`，且**中间一行 npm 输出都没有**。
  - 根因：`ensureDependencies()` 用 `spawnSync('npm.cmd', ['install'], {stdio:'inherit'})`。
    Node 从 18.20.2 / 20.12.2 / 21.7.3 起（CVE-2024-27980 的加固）**禁止 child_process
    直接执行 .bat/.cmd**：`spawnSync` 连进程都不会创建，只回 `EINVAL`，于是
    `res.status !== 0` 命中「安装失败」分支——控制台上因此一个字都没有。实测（本机
    Node 22.22.2 与 24.15.0 均复现）：`spawnSync('npm.cmd', ['-v'])` → `error.code === 'EINVAL'`。
  - 为什么开发时没发现：本仓库 `node_modules/` 是 gitignore 的，开发机早就装好了，
    `ensureDependencies()` 第一行就短路返回。**只有全新下载仓库的玩家会走这条路**，
    所以这是"每个新玩家必踩"的首次启动失败。
  - 复现要点（2026-09-30 实测，容易误判成"这 bug 不存在"）：**发行压缩包自带
    `node_modules`**（`Nornium-ServerDev-v0.2.0` 里就有，4.1 MB），第 1 步直接打印
    「OK 依赖已就绪」，压根不走安装分支 → 解压即玩的人不可复现。
    会中招的是**从源码拿包的人**（`git clone` / GitHub `Download ZIP` 都不含 node_modules）
    以及手动删过依赖、被安全软件吞掉的人。**想复现：把 `server\node_modules` 改名再启动**，
    旧版会逐字打印玩家那一屏（`首次运行：正在安装依赖 …` → `依赖安装失败，请…npm install 后重试。`，
    中间一条 npm 输出都没有）。
  - 修法：新增 `npmCliScript()` / `npmInvocation()` / `npmShellInvocation()`，
    优先用**当前这个 node** 执行它自带的 `node_modules/npm/bin/npm-cli.js`
    （不过 PATH、不过 cmd.exe，正是 `npm.cmd` 垫片内部做的事，见 `D:\nodejs\npm.cmd` 最后一行）；
    找不到 CLI 脚本时才退回 `ComSpec /d /s /c "npm install"`，让 cmd.exe 自己从 PATH 找 npm。
    两条路径都不直接 spawn `.cmd`。
  - 同时补上**诊断信息**：改为捕获 npm 的 stdout/stderr，失败时打印 `res.error` 的
    code/message（或退出码）与 npm 最后 12 行输出；失败提示改成可照做的四步
    （打开 server 文件夹 → 地址栏输入 cmd → `npm install` → 重跑启动器），并顺带回答玩家
    最容易问错的「npm install 在哪」——它是命令不是文件，不在 Node 安装目录里；
    另附 `'npm' 不是内部或外部命令`（安装时没勾 Add to PATH）与超时换
    `registry.npmmirror.com` 两条建议。
  - 断言：`test/setup_check.js` 新增一段——在生产 Node 上直接 spawn `npm.cmd` 必须拿到
    `EINVAL`（把用户报的现象钉住）、向导的调用方式不得以 `.cmd/.bat` 结尾、
    `npm-cli.js` 必须真实存在且子命令是 `install`、Windows 兜底必须经 `cmd.exe`。

### Changed

- **没选存档时，右侧的存档页标签直接置灰、点不动**（总览/背包/角色/抽卡/商城/剧情/备份 7 个），
  鼠标悬停提示「先从左栏选一个存档」；「服务器管理」「服务器控制台」两个标签不受影响
  （它们本来就不需要存档）。以前点这些标签会静默退回主页，容易让人以为界面坏了。
  主页在未选档时显示「未选中存档 · 请先从左侧选一个存档」。
- **启动器/向导输出**：横幅第二行改为「完全免费开源（付费买到即被骗）· 项目主页 <地址>」；
  服务端启动横幅从 6 行压到 4 行（版本/网页编辑器/项目主页/控制台提示），
  控制台就绪提示从一整行指令清单压成一句「输入 help 查看全部指令（stop 停服）」。
  完整的指令表仍在 `README.md` 与控制台的 `help` 里。
- **`test:skins` / `test:editor-ui` / `test:setup` 的描述与断言同步更新**（新增
  `test:log`；`editor_ui_check` 覆盖锁定标签、危险红、控制台补全与分级着色、
  角色精细化区块、仓库地址入口；`setup_check` 覆盖紧凑输出档位与仓库地址）。

## [0.2.0] - 2026-09-27

### Added

- **皮肤（时装）系统全链路落地**：此前服务端完全没有皮肤概念 —— 皮肤卡（itemType 92）用不了、
  解锁状态不落盘，抽到/领到皮肤在装扮面板里也永远显示未解锁。现按客户端口径完整实现：
  - 皮肤定义在 `d_char_clothes`（dressType 1 战斗 / 2 机甲 / 3 主城；4=主城住宅偶像立绘，
    与主城皮肤共享解锁，id−1000000 同源）。解锁列表 = 角色的
    `own_character_skin_ids / own_mecha_skin_ids / own_city_skin_ids`，
    穿戴 = `character_skin_id / mecha_skin_id / city_skin_id`（0=默认）。
    新模块 `server/src/game/skins.js`（解锁/校验/默认皮肤/迁移）。
  - `req_use_item` 支持皮肤卡「使用」：subParam 即皮肤 id 列表，服务端解锁并随
    `ntf_character_info`（整体替换）推回；**不再给被消耗的道具推 ntf_item_info**
    （客户端 res OK 后自己本地扣，ntf 的 delta 是加法语义，再推一份就是双重扣减，同坑 23）。
  - `req_character_change_skin` 按解锁列表校验：没解锁回 `NO_SKIN(3)`，0=恢复默认。
  - 默认皮肤（`dressInitial==1`）在建号/建角色时就写进解锁列表 —— 客户端
    `UI_Panel_Dress_C:IsUnlockSkinId:719` 把「默认即解锁」的分支注释掉了，不写的话
    装扮面板里连初始服装都是锁着的。
  - 迁移（幂等）：老存档自动补默认皮肤 + **背包里已有的皮肤卡就地解锁**
    （本次修复的原始诉求：以前拿到的皮肤显示未解锁），重登即生效。
  - 发放入口：控制台 `allskins [账号|all]`（解锁全部已拥有角色的全部皮肤）、编辑器
    角色页「解锁该角色全部皮肤 / 解锁全部角色的皮肤」（`unlock_all_skins` op）、
    背包目录新增「皮肤」分类可直接发皮肤卡道具（`/catalog` 角色条目新增 `skin_total`）。
  - 断言：`test/skins_check.js`（新增）+ `test/fake_client.js` 皮肤段落（线协议层全程）。
- **锁 60 帧兜底（`src/framefix.js`）**：客户端设置界面的「锁 60 帧 / 平滑帧数」只在内存里
  生效 —— 引擎的 GameUserSettings.ini 里从未落盘 `bUseSmoothFrameRate`，游戏的设置存档
  （SG_SaveGame_Settings.sav）里只有 GraphQuality 一个字段，于是每次重进游戏都被改回
  平滑帧数。客户端 UMG 的 bug 私服改不了（坑 14），但改得动引擎配置：服务端每次启动把
  `bUseSmoothFrameRate=False` + `FrameRateLimit=60` 合并进
  `%LOCALAPPDATA%\Nornium\Saved\Config\Windows\GameUserSettings.ini`（幂等，
  只动这两个键，保留 CRLF 与其余内容）。想关掉：`server/runtime-config.json` 里加
  `"frame_lock_fps": 0`。
  > **已更正（见 Unreleased / Fixed）**：`bUseSmoothFrameRate` 在这个 UE 构建里不是
  > `UGameUserSettings` 的属性（pak 内的默认 ini 与 exe 的 BP 函数名表都没有它），
  > 写进去没人读。现在改成写 `Engine.ini` 的 `bSmoothFrameRate=False` +
  > `[SystemSettings] t.MaxFPS=N`（Saved 覆盖 pak 默认），并保留
  > `GameUserSettings.ini` 的 `FrameRateLimit=N`；上一版写下的 `bUseSmoothFrameRate`
  > 会被清掉。`frame_lock_fps: 0` 仍是总开关。
- **控制台新指令**：`addchar <账号> <角色id|all>`（添加角色，含专属武器/技能/默认皮肤）、
  `allskins [账号]`。配套把 allweapons 的账号解析抽成共用的 `resolveTargets()`。

- **存档编辑器新增「服务器控制台」页**（服务器管理工作区，免选档）：在浏览器里实时看服务端输出、
  直接执行控制台指令，不用再回到那个黑窗口。
  - `src/logger.js`：新增 **2000 行进程内环形缓冲**（每行 `{seq, text}`）+ `tail(after)` 游标取增量 +
    `subscribe(fn)` 订阅；同时包装了 `console.log/warn/error`，启动横幅与指令回显这类
    裸 console 输出也进缓冲（`write()` 走原始 console 引用并自行入队，避免双重捕获）。
  - `src/editorapi.js` 三接口：`GET /editor/api/console/tail?after=N`（JSON 历史）、
    `GET /editor/api/console/stream`（**SSE 实时流**：先重放游标后的缓冲行，再实时推送，
    `retry` + 15s 心跳，断开即退订）、`POST /editor/api/console/cmd`（复用 `console.js`
    `handleCommand`，与 stdin 黑窗口同一份口径与维护窗口；reply 回显进日志流，
    `action=stop` 先回响应再延迟调 `hooks.onStop`）。
  - 前端 `editor/`：服务器管理区新增「服务器控制台」标签页；先 tail 再 EventSource 增量追加，
    按 `[I/W/E/V]` 级别渲染（黑白语言内：E/W 加粗、V 淡化）；客户端只留 2000 行；
    上滚自动暂停跟随、翻回底部恢复；指令输入框支持 ↑/↓ 历史与回车发送，
    restore/stop/load/export 执行前弹确认框（restore 手输「清空存档」）；
    离开页面或停服时主动断开 SSE。
  - 测试：`test/editor_check.js` 补 tail 游标/SSE 首块与重放/cmd 全套断言；
    `test/editor_ui_check.js` 标签页 8 → 9、控制台页骨架与断流行为（假 EventSource）。

- **剧情星图「终点」通关闭环（主线推进修复，坑 43）**：「终点」格
  （`d_srpg_main_pos_base` 99999）的 `onExploreEffectTriggerID` 首项是触发器 99
  （`effectType 99, effectDisplay [10]` = 客户端 `SpecialDisplay.SetAbort`），
  而服务端 `applyEffect` 没有 effectType 99 的分支 —— 踩到终点什么都没发生、局永不结算：
  ① 主线 60005「完成某个剧情星图」（100031008「前往水星天」）推不动；
  ② 未结算的旧局被客户端复用（`RequestSpecialSrpgLevel` 见到剧情局直接 LoadLevel），
  表现为「血量继承上一局」且终点格已探索、无法再触发。
  现在 `applyEffect` 新增 `case 99`：`ntf_effect_trigger_begin(99)` →
  `ntf_universe_clear{result:true}` → `ntf_effect_trigger_end`（begin 必须先于 clear ——
  客户端在 NTF_UNIVERSE_CLEAR 处理器里读当前打开 trigger 的 effectDisplay 改判
  EndReason，SrpgController.lua:299-326）→ `settleRun`。客户端随后记 60005、主线自动推进。
  同时新增僵尸剧情局迁移（`U.stuckStoryRun` + `migrate.js`）：剧情图（mapType 0）+
  终点格已探索（state 3）+ 仍 active 的残留局在加载时就地清除（幂等，正常进行中的局
  不受影响），重登即恢复新局满血。回归断言 `test/universe_check.js`「endpoint cell」段。

- **星位（天赋 / 命座）解锁闭环**：`req_character_unlock_talent` 过去**根本没有处理器** ——
  `handlers/index.js` 的兜底分支替它回了一个**空的** `res_character_unlock_talent`（帧头 result=0 = OK），
  于是客户端在本地把星位点亮、把材料扣了，服务端一个字节没写：**玩家点亮星位后一重启全没**
  （实测所有存档 `characters[].talent_ids` 恒为 `[]`、背包 0 把星位之钉）。
  现在按 `d_character_inborn` 回表实现：归属校验 → 重复 → 前置孔位（`frontHole` 指向 `hole`）→
  `openNeed` 条件（30000 角色等级 / 50004 消耗道具）→ 扣【星位之钉】（= `d_character.inbornItem`，
  如莎乐美 → 1207002）→ 写 `characters[].talent_ids` → `savePlayer`。
  错误码逐条对齐官方：0 OK / 1 NO_CHARACTER / 2 TALENT_UNLOCKED / 3 INVALID_TALENT_ID /
  4 PRE_TALENT_LOCKED / 5 CHECK_CONDITION_FAILED / 6 STUFF_NOT_ENOUGH（后两个只定义在客户端）。
  新模块 `server/src/game/talent.js`；回归断言 `test/talent_check.js`（含「写盘后重载仍在」哨兵）。
- **抽卡重复角色 → 星位之钉**（命座的唯一官方来源，`d_word_cn` 1904）：第 2~7 次获得相同角色，
  每次转化为该角色的【星位之钉】×1 + 【珊瑚劫灰】×20；第 8 次及以后只给珊瑚劫灰 ×50
  （同一角色的不同幻形算同一角色）。转化表 `d_gacha_token` 用的是自己的 itemType 编号
  （1/2 = 重复角色第 2~7 次 / 第 8 次起，3 = 武器，4 = 家具），顺手把武器/家具的转化货币也补上
  （6★ 20 / 5★ 5 / 4★ 20 时枝化石 / 3★ 10）。计数落在 `gacha.char_obtain_times`。
  顺带修掉「同一批十连里抽到两个同一个新角色会建两个角色对象」。
- **编辑器：发放命座（星位之钉）与直接点亮星位**。`/catalog` 的角色条目新增
  `inborn_item`（该角色的钉）与 `talent_total`（星位数）；新增三个编辑操作
  `grant_constellation{character_id, count}`、`grant_all_constellations{count}`、
  `unlock_all_talents{character_id?}`（省略即全部已拥有角色，直接写完整 `talent_ids`，跳过消耗与等级）。
  前端角色页卡片显示「星位 n/23 · 钉 ×k」，工具栏加「发放全部角色的星位之钉 / 点亮全部角色的星位」，
  角色弹窗加「专属星位之钉 + 发放数量 + 发钉 / 点亮该角色全部星位」。断言在 `test/editor_check.js`。
- **编辑器工作区分区 + 主页优先显示服务器状态 + 红绿连接灯**（前端回归断言同步更新）：
  左栏顶部新增「存档管理 / 服务器管理」工作区切换（同一个前端里换视图，共用 API/样式/轮询）；
  服务器管理不再和存档编辑混在同一组标签里，且**不显示存档列表、不需要先选存档**；
  未选存档时的主页第一屏是「服务器状态」卡片（运行中/连不上 + 版本 + 在线数 + 运行时长 +
  账号/档案 + 端口 + 快照数 + 存档目录），下面才是选档引导；
  左下角指示灯从「实心黑点 / 无色描边」改成**绿（连得上）/ 红（连不上或已停服）**两态。
- **远航支援商店闭环**：`req_player_universe_growth` 此前是「永远返回 MAX_RANK(1)」的桩，
  每次购买都报「cmd:302 code:1」。现按客户端 `PlayerSystem.lua` 的官方口径实现：
  远航经验 = 背包 9003（补给配额）数量查 `d_srpg_exp` 得等级，剩余点数 = 等级 − Σ
  `d_srpg_growth.cost × node_rank`（9003 不扣减，购买是虚拟记账）；校验满级/点数后写入
  `player_universe_growth_node_infos`。重置接口同步实现（清空即退点）。
  type 1 增益在新开局生效（`U.applyGrowthBonuses`）：金刚凝胶/生存值加进开局资源与 HP、
  「建筑蓝图 +1」每级从卡池 100 随机一张进开局手牌。type 2 战斗属性节点（攻/防 %）
  客户端无消费点，不接入（见 REVERSE_ENGINEERING.md 8.10）。
  新模块 `server/src/game/growth.js`；回归断言在 `test/universe_check.js` growth 段。

### Changed

- **新号开局不再发放全部角色**：`createPlayerDoc` 现在只发开局二人组
  **信风(10501，玩家扮演的主角) / 鱼啄雨(11202，小鱼)**，其余 8 名角色经由**抽卡**、
  控制台 `addchar`、编辑器「一键加全角色」或游戏内 GM `add_character` 补齐。
  开局阵容是数据驱动的：全部剧情星图的角色表（`d_srpg_map_specific.character`）的并集
  就是这两个人（教学图 1000309 只要 [10501]；1000301 是两人组；1001001 只有 [11202]），
  且新手池（d_gacha_schedule gachaId 2 → block1pool 601）里**没有信风**（常驻池才有）——
  即「主角开局就有、不能抽」。初始背包/邮件等资源发放**完全不变**。
  抽到重复角色 → 星位之钉的转化口径不受影响（`gacha.char_obtain_times` 按
  「已拥有 = 已获得 1 次」起步）。新号默认头像同步改为信风（`avatar_id: 10501`）。
- **剧情星图按配置出队（坑 46）**：`req_new_universe_specific` 过去无视
  `d_srpg_map_specific.character`，一律用「已拥有角色的前 3 个」当队伍 ——
  全角色发放的年代里，教学图实际带的是仿钻折光/莎乐美/逆戟雀而不是信风。
  现在取配置声明的角色与已拥有角色的交集（客户端没有 character_info 的角色渲染不出），
  声明为空或全部未拥有时才退回旧口径。迁移同时给缺主角/鱼啄雨的老档补齐这两个角色。

### Fixed

- **req_use_item 把 subParam 值当成道具 id 发放**：旧实现不分类别地把
  `d_bag_item.subParam` 里的数字当 `item_id` 塞进背包 —— 用皮肤卡会多出
  item_id=1010101 的幽灵道具（四张表里都没有这行，客户端渲染成乱码占位），用角色卡
  会多出 item_id=10101 的幽灵道具。现按类型正确落盘（皮肤卡→解锁列表、角色卡→创建角色、
  锻造蓝图→`arm_blueprint_ids`），并由迁移把存档里已有的幽灵道具清掉。

- **星图隐藏格永不出现（除开局可见格外整张图几乎全黑，探索揭示的格子也不出现）**。
  根因：私服开局把**整张图全部格子**一次性下发（`buildUniverseInfo` 直接 `map(encMainPos)`，
  `state` 抄 `d_srpg_main_pos_base.baseState`，267 行里 252 行是 0），而客户端
  `BP_Map_Planet_C:IsVisible() = mainPosInfo.state > 0`、`UpdateMapPlanet` 对 state 0
  **整只 actor `SetActorHiddenInGame(true)`**；之后服务端只发
  `ntf_main_pos_state_change`，其客户端处理（`SrpgController.lua:222-232` →
  `SrpgModel:UpdateMainPos`）只改 state + 重算连线，`UpdateMapItems` 只刷特效**从不碰可见性**
  ——state 0 的格子因此永远黑暗。真正让格子「出现」的唯一路径是 `ntf_main_pos_info`
  （`AddMainPos` 重建 actor + `Dissolve` 动画 + 重抓战争迷雾 `Capture_FOW`，
  `BP_PlayerController_Universe_C.lua:732-771`），私服从未发过这条消息（实测存档
  3 次 `req_explore` 全程 0 次 `NtfMainPosInfo`）。修法（坑 42，硬不变量
  **客户端已知格子集合 ≡ 服务端 state > 0 的格子集合**）：
  ① `buildUniverseInfo` 快照只下发 `state > 0` 的格子（boss 落点格兜底强制可达并 WARN）；
  ② 新增 `raiseState(cell, target)` 统一分流：`0 → ≥1` 的格子必须走
  `ntf_main_pos_info`（客户端「造格子」），`≥1 → 更高` 才走 `ntf_main_pos_state_change`；
  **绝对禁止**对客户端没学过的 hex 发 `ntf_main_pos_state_change`（客户端
  `SrpgModel:GetMainPos` 返回 nil 直接 index 报错）；
  ③ `revealFrontier` / `revealBossRoute` / `advanceBosses` / `spawnDueBossWaves`
  全部改按 `raiseState` 返回 `{ fresh, changed }`，`handlers/universe.js` 新增
  `sendPosInfo/sendPosStateChange/sendReveal` 统一下发（info 永远先于同格 state_change、
  所有 pos 消息永远先于 `ntf_boss_info`）。存档结构不动（`universe.main_pos` 仍存全图），
  过滤只发生在下发时，老玩家重进地图由快照重建自动对齐。
  回归断言：`test/universe_check.js` 新增「格子下发不变量」段（快照过滤 / fresh-changed
  分流 / 双图线序回放），`test/fake_client.js` 加 `posTracker` 客户端视角对拍器。
- **星位升级后重启不保存**：根因见上（缺处理器 + 兜底分支把「未实现」伪装成成功）。
  `migrate.js` 同时补上 `characters[].talent_ids` 与 `gacha.char_obtain_times` 两个字段的幂等迁移，
  老存档照常能继续玩。
- **编辑器「服务」页（服务端管理）**：`/editor` 新增一个不依赖存档的页面，可以直接
  查看服务端状态（版本/运行时长/在线连接数/账号与档案数/TCP 与 HTTP 端口/存档目录/快照数），
  并执行：立即备份一份（`data_manual_*`）、踢出所有在线玩家、从快照或备份目录导入并热重载、
  清空全部存档（要求手输「清空存档」确认，服务端二次校验，清前自动留 `data_wipe_*`）、
  **停止服务端**（停掉后前端停轮询并显示遮罩，重新开服双击 `点我启动.bat`）。
  接口 `GET /editor/api/server` + `POST /editor/api/server/{kick,backup,load,restore,stop}`；
  `load`/`restore` 走 index.js 注入的维护窗口（先停止 accept → 硬排空会话 → 改档 → 重新监听），
  `stop` 先回 HTTP 响应再延迟调用 `hooks.onStop`（`createGate` 新增
  `{ maintenance, onStop, startedAt, tcpPort, httpPort }` 钩子）。
- **编辑器可直接改「等级」与「光淬阶数」**：新增两个编辑操作
  `set_character_level`（角色等级 → 经验，逐字复刻客户端 `d_role_level` 换算，超上限自动夹取）
  与 `set_weapon_stats`（按 uuid 改**任意一件**武器的等级/突破/光淬——背包里没装备的也行；
  等级换算用 `d_weapon_level` 的 `exp<rarity>` 列）。`/catalog` 增加 `leveling`
  （caps / max_break / role_exp / weapon_exp）供前端双向换算，武器条目增加 `max_refine`。
  前端：背包的武器行多了「光淬 / 等级 / 突破」三个输入框；角色弹窗改为按等级编辑
  （经验自动换算，也可手改经验），并把「精炼」改称「光淬」。在线推送武器练度用
  `ntf_item_info` + `count: 0` + `weapon_info`（`count: 0` 才会命中客户端
  `BackpackSystem.lua:384` 的整条替换分支）。
- **`tools/check_weapon_assets.js`**：把 83 把武器引用的模型/图标/展示图与 pak 条目逐一对照，
  列出「未实装武器」并与服务端黑名单对拍（需要先用 repak 导出 `reference/paklist*.txt`，
  命令见脚本头部；清单已 gitignore）。
- **`test/editor_ui_check.js`（`npm run test:editor-ui`）**：编辑器前端的渲染回归 ——
  用一个最小 DOM shim 在 Node 里把 `editor/app.js` 真跑起来，切遍 8 个标签页、切换两个工作区、
  选中存档、打开角色弹窗，断言不抛异常且关键 DOM 片段都在（武器练度输入框、未实装标注、
  角色等级/光淬输入框、星位/命座区块、服务器管理页按钮、主页的服务器状态排在上手引导之前），
  并校验连接状态灯的 CSS 是红绿两态、`app.js` 引用的 DOM id 都存在于 `index.html`。
  无需浏览器、无需服务端。
- **`test/talent_check.js`（`npm run test:talent`）**：星位（命座）回归 ——
  解锁的六个错误码、前置孔位链、等级门、星位之钉消耗、**写盘后重载仍在**（「升级后重启不保存」
  的哨兵）、一键点亮、抽卡重复角色→钉（含第 8 次起只给珊瑚劫灰、同批重复新角色只建一个角色对象）、
  缺字段老存档的迁移。不需要服务端。

### Changed

- **编辑器信息架构：存档管理与服务器管理正式分区**。左栏顶部新增工作区切换
  （`S.zone` = `'save'` / `'server'`），标签页从「存档编辑 / 运维」两组改成
  「存档管理（存档编辑 + 存档备份）/ 服务器管理」两个工作区 —— 服务器管理不再和存档编辑
  挤在同一组标签里，也不在存档列表下，切过去时顶栏标题与徽标一起换成服务端口径。
  主页（未选存档）第一屏改为「服务器状态」卡片，选档引导退到它下面。
  左下角连接状态灯改红绿两态（`--ok` / `--bad`，整套黑白设计里唯一的彩色）。
  接口、存档格式、编辑语义与确认串一律未改；`test/editor_ui_check.js` 增加工作区切换、
  主页顺序、状态灯 CSS、星位区块的断言。
- **存档编辑器前端整体重构（扁平 / 圆角 / 黑白）**：`server/editor/` 三件套重写，去掉深色星空主题
  （渐变、毛玻璃、青紫强调色、emoji 图标），改成纯黑白灰的扁平设计 —— 1px 描边卡片、
  10/14/16px 三档圆角、实心黑（深色主题下是实心白）作为唯一强调，图标全部换成内联单色 SVG，
  稀有度改成 7 级灰阶。深浅两套主题由 `<html data-theme>` 切换（默认跟随系统、顶栏可切、
  选择记在 `localStorage`，`index.html` 内联脚本在首帧前定好主题以免闪白）。
  信息架构重排：顶栏（当前存档 / 在线状态 / 服务端状态 / 使用说明 / 主题 / 待保存 / 保存修改）、
  左栏存档列表（带搜索与计数）、标签页按工作区分组（当时是「存档编辑（总览/背包/角色/抽卡/商城/剧情）」
  与「运维（备份/服务）」两组，随后进一步拆成「存档管理 / 服务器管理」两个工作区，见本节第一条），
  每页顶部写明「这一页能做什么」，未选存档时显示上手引导。
  新增交互：**待保存清单抽屉**（把每个 op 翻译成人话，可逐条撤销 / 清空 / 保存）、
  字段与列表行的「已修改」标记、顶栏 `?` 使用说明弹窗、`Ctrl/Cmd+S` 保存 / `/` 聚焦搜索 /
  `Esc` 关弹窗、toast 移到屏幕底部居中（不再盖住抽屉按钮）。
  一处**有意的行为变更**：还有未保存修改时不再允许直接切换存档（旧版弹 `confirm` 直接丢弃），
  改为提示并打开抽屉，要放弃请在抽屉里点「清空」——避免误丢改动。危险操作仍是黑白：
  虚线危险区 + 加粗描边按钮 + 手输确认串（`清空存档` / `停服`，服务端二次校验不变）。
  接口、存档格式、编辑语义与确认串一律未改；`test/editor_ui_check.js` 相应扩了 20 条断言
  （设计语言不变量、分组导航、上手引导、待保存抽屉、帮助弹窗、主题切换）。
  改造前的旧版三件套留在 `server\.editor_backup\`（本仓库没有版本控制，留一份方便回滚），
  确认新版没问题后可以直接删掉整个目录。
- **武器发放口径改为「已实装的高稀有度武器每种各一把」**（`src/game/arsenal.js`）。
  早期版本是「每个可玩角色发一把与其武器类型匹配的最高稀有度武器，并列取 id 大者」，
  但数据表里根本没有「角色 → 专属武器」的关联（`firstWeapon` 只是 1★ 白板），
  而且这个猜测会让**巨刃角色拿到未实装的 `1081601 颂歌`**（见 Fixed）。
  现在 `allweapons` 指令与编辑器「发放全部高稀有度武器」按钮发放的是
  已实装的 6★/7★ 各一把（共 36 把），编辑器按钮新增「跳过已拥有的」勾选项。
  `bestWeaponForCharacter` 保留（编辑器单发按钮与目录 `best_weapon` 用），但已过滤未实装武器。

### Fixed

- **`1081601 颂歌`（以及同批 9 把）武器详情面板满屏「文本块…」的根因**：
  客户端 83 把武器里有 10 把是**未实装残件** —— pak 里既没有模型
  （`Blueprints/Weapons/Weapon/W_<id>`）、也没有图标（`Icon<id>_png`）与展示图
  （`img<id>_png`），其中 7 把连 `d_weapon.skillID = 2000101` 在 `d_skill` 里都没有对应行。
  客户端 `UIUtils.GetWeaponSkillDesc` 在查不到技能行时访问 `nil.skillDesc` 抛错，
  把 `UI_Com_BagDetail_C:RefreshUI` 从中间打断（后续的 `SetText` / `RunePanel:Collapsed` /
  属性列表刷新全被跳过），面板就停在了 UMG 设计态：满屏「文本块…」「30#星芒名字」、
  没有「攻击力」行。因为巨刃里 id 最大的 7★ 正好是颂歌，所以只有巨刃角色中招。
  修法：新增 `src/game/weapon_data.js`（`UNRELEASED_WEAPON_IDS` 黑名单 + `isReleasedWeapon()`
  = 黑名单 ∪ `d_skill` 有行），发放清单与 `bestWeaponForCharacter` 全部过滤；
  `migrate.js` 新增 `repairUnreleasedWeapons()`，加载存档时把已有的幽灵武器**原地**换成
  同类型、稀有度最接近的已实装武器（只改 `item_id`，`item_uuid`/经验/突破/光淬全部保留，
  幂等）；编辑器 `add_item` 直接拒绝未实装武器、目录里标「未实装」并禁用「加入清单」。
  实测玩家档：角色 10701 身上的颂歌 → `1071611 灼星已现`，练度不变。
- **编辑器角色弹窗保存时「角色经验/突破」会被「武器编辑」顶掉**：旧版把两者都写成
  `edit_character`，而去重键只按 `(op, character_id)` 取，后一个把前一个替换了，
  于是同一次保存里角色那半永远不生效。现在角色用 `set_character_level` / `edit_character`、
  武器用 `set_weapon_stats`（不同 op），并且 `stage()` 对 `set_weapon_stats` 按字段**合并**
  （改光淬再改等级不会互相顶掉，`level`/`exp` 互斥且新写的赢）。
- `REVERSE_ENGINEERING.md` 里把私服 HTTP 门写成 8089 的过期描述统一改成 9089
  （官服 `channel.lua` 里的 8089 是原始数据，保留）。

- **网页存档编辑器 `/editor`**：服务端起来后浏览器打开 `http://127.0.0.1:9089/editor`
  （与登录门共占 9089，`/client/*` 路由原样保留），本质上是一个带界面的存档编辑器：
  总览（昵称/八种货币）、背包（分类筛选 + 搜索 + 改数量/删除/按目录添加道具、武器等级与光淬）、
  角色（一键加全角色、按等级或经验编辑、武器等级突破光淬、发放高稀有度武器）、抽卡（保底计数）、
  商城（累充积分/月卡）、剧情（只读）、备份（一键导出 + 快照列表）、服务（服务端管理，见上）。
  纯 vanilla 三件套（`server/editor\`，深色星空主题，无构建步骤、零新依赖）。
  写档走「在线感知」：目标账号在线就直接改内存 doc 并推 ntf（游戏内**即时生效**），
  离线则直接写盘（重登生效）；所有编辑先进待保存清单、一键提交，部分失败也会落盘
  已生效部分并单独报错。实现 `src/editorapi.js` + `test/editor_check.js`
  （`npm run test:editor`）。
- **控制台指令 `export [<目录>]`**：把当前存档整份导出——带参数拷到指定目录，
  不带参数落到默认备份位置 `server\data_export_<时间戳>\`；与 restore/load 一样
  走维护窗口（先踢人排空再拷贝，保证快照一致）。配套 `store.exportData` / `store.listBackups`。
- **控制台指令 `allweapons [<账号|all>]` 与武器发放**：给玩家档案发放**已实装的高稀有度武器**
  （6★/7★ 每种各一把，共 36 把），入包不自动装备。早期版本是「每个可玩角色一把与其武器类型
  （`d_character.profession`）匹配的最高稀有度武器（并列取 id 大者）」，但数据表里
  「角色→专属武器」唯一官方字段只有 `firstWeapon`（1★ 白板），6★ 专属武器没有任何字段与角色关联，
  而且这个猜测会选中未实装的 `1081601 颂歌` —— 口径已改，详见本版 Changed/Fixed。
  不带参数默认只发服主主档（账号 10，xundei）。实现 `src/game/arsenal.js`，
  编辑器「发放全部高稀有度武器」按钮共用同一逻辑。
- **服务端控制台指令**（`src/console.js`）：在运行服务端的窗口里直接输入指令回车——
  `restore` 清空本地存档（先踢掉全部在线连接，断连排空后再删
  `accounts.json` + `players/`，并同步重置内存账号表，服务端继续运行，发布干净正式版用）；
  `load [<备份目录>]` 热加载存档（把备份拷回 `server\data\` 后不用重启即可生效，
  也可以直接给备份目录由服务端导入）；`stop` 优雅停服；
  `status` / `help`。配套回归测试 `server/test/console_check.js`
  （`npm run test:console`），其中一条专门守住「resetData 必须重置内存账号表，
  否则下一个注册请求会把旧账号整表写回磁盘」这个坑。
- **首次启动向导 `server/setup.js`**：新玩家不再需要手工往
  `%LOCALAPPDATA%\Nornium\Saved\` 拷贝任何文件，双击根目录的 `点我启动.bat` 即可：
  向导会检查 Node 版本（>=18）与 `reference/` 资产完整性、缺依赖自动跑 `npm install`、
  然后从 Steam 注册表 + `libraryfolders.vdf` + 常见盘符自动探测游戏安装位置
  （找不到才让用户输入路径），最后自动写入 `channel.lua`（`local_dev` + 8101/9089）
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
- **`load <备份目录>`：一条指令把旧存档捞回来**（`src/console.js` / `src/store.js`）。
  以前 `load` 只重读 `server\data\`，恢复备份必须手工把 `accounts.json` / `players\*.json`
  拷进去再执行——现在可以直接 `load C:\Users\xxx\Desktop\Nornium_save_backup_2026-09-19`，
  服务端自己完成校验与导入。给备份目录的上一级也行（会在其 `data\` 里找）。
  校验不通过（目录不存在、里面没有 `accounts.json`、或指到了当前存档目录本身）会**明确报错**，
  并且是在开维护窗口之前就报，不会白等一次。
  导入语义是**覆盖式而非镜像式**：只覆盖备份里有的文件，不删除目标里多出来的玩家档案
  （宁可留一份脏数据，也不误删玩家档）。
- **`restore` / `load` 动档前自动快照**：`store.snapshotData()` 把当前 `accounts.json` +
  `players\*.json` 整份拷到 `server\data_wipe_<时间戳>\` / `server\data_preimport_<时间戳>\`
  （同秒内连点两次也不会互相覆盖；空的就不建目录）。回显里会打印快照路径，
  要回滚就把里面的文件拷回 `server\data\` 再 `load`。`restore` 是全项目唯一不可逆的动作，
  以前是直接 `rm`，误按一次就真没了。
- 回归测试 `server/test/setup_check.js`（`npm run test:setup`），
  覆盖路径归一化与本机候选目录不得因大小写自我重复（见下方 Fixed 第 2 条）；
  `server/test/console_check.js` 追加 22 项断言，覆盖 `load <备份目录>` 的成功/失败/快照/
  覆盖语义/`data\` 上级写法/`0 账号 0 玩家` 提示与「报错回显保留原始大小写」。
- 回归测试 `server/test/weapon_check.js`（`npm run test:weapon`，26 条断言，无需服务端）：
  角色 `d_character.profession` 与武器 `d_bag_item_weapon.subType` 的一致性、
  装备/交换武器的类型校验（含拒绝后不吞道具）、`item_uuid` 去重迁移、
  「装错武器类型」的迁移修复与幂等（见下方 Fixed 第 1、2 条）。

### Changed

- **老存档的 `item_uuid` 在加载时去重**（`src/game/items.js` 的 `dedupeItemUuids`，
  由 `src/game/migrate.js` 调用）：早期版本的 `next_uuid` 计数被重置过，同一件 uuid 被
  分给了多件道具（本机实测账号 10 的背包里 260 件道具中有 50 件是重复 uuid）。
  服务端所有「按 uuid 定位」的入口都用 `find` 取数组里**第一件**命中，于是出现
  「客户端点的是 A、服务端动的是 B」。去重时**第一次出现的条目保留原 uuid**
  （那正是历史上所有既有 `find` 会命中的那件，改它会改变已有语义），只给被遮蔽的
  重复项重新分配新 uuid。幂等、不动任何道具本身。
- **角色装备了「非本类型武器」时在加载时自动换回本类型武器**
  （`src/game/migrate.js` 的 `repairWeaponType`，私服保险）：把错的武器收回背包，
  从背包里挑**同类型、稀有度最高**的一件装上（背包没有同类型武器时退回
  `d_character.firstWeapon`）。之所以必须由服务端兜底：客户端的武器列表是按
  「当前已装备武器的 `subType`」过滤的（`UI_Weapon_Change_C.lua:85-104`），
  一旦装错类型，玩家在 UI 里只剩错类型的武器可选，**自己再也换不回来，重登也一样**
  （已经写进存档了）。修复前后都会写服务端日志（`[migrate] …`）。
- **控制台改档不再"睡 300ms 就动手"，改为真正的维护窗口**（`index.js` 的
  `withMaintenance` + `session.drainSessions()`）：`server.close()` 立刻停止接受新连接 →
  踢掉所有会话并**等到 `liveSessionCount() === 0`**（超时才强断，仍不空就放弃本次操作）→
  改文件 → 重新 `listen`。HTTP 门（9089）不碰存档，全程保持可用。
  原因见下方 Fixed 第 4 条。
- **`点我启动.bat` 改为纯 ASCII，中文提示全部搬进 Node**：启动器里多了非 ASCII 字节
  会让 cmd.exe 解析错位，凭空报一行
  `'??' is not recognized as an internal or external command, operable program or batch file.`
  （不影响功能，但很吓人）。现在 bat 只剩结构性命令（`where node` 检查、
  `node setup.js --from-bat`、`if exist auto-launch.flag start "" steam://…`、`node index.js`），
  中文横幅 / 「第 1 步 / 第 2 步」标题 / 自动拉起提示由 `setup.js` 打印，
  `>> 服务端已停止。` 由 `index.js` 打印（Node 输出走 Windows 宽字符 API，与代码页无关）。
  唯一留在 bat 里的是 `where node` 失败分支——那时还没有 Node 可用，只能写 ASCII 英文。
  顺带：bat 里那个 `if exist … ( echo 中文 / start … ) else ( echo 中文 )` 多行块
  收敛成一行无条件分支，少一处解析风险；`.gitattributes` / `.editorconfig` 给 `*.bat`
  锁上 `eol=crlf`；`server/test/setup_check.js` 加了「bat 必须零非 ASCII 字节 / 无 BOM / 全 CRLF
  / 中文只能在 Node 侧」的断言，防止以后又被人加回去。
- **`test/persistence_check.js` 改用临时存档目录**：它 `spawn('node index.js')` 时没传
  `GHS_DATA_DIR`，测试账号一直落在真实的 `server\data\` 里。（见 Fixed 第 5 条）
- 向导收尾提示补上「想找回旧存档：在服务端窗口输入 `load <备份目录>`」。
- 发布前清掉了仓库里的本地测试存档（`server/data/`：33 个账号），服务端回到全新状态。

### Fixed

- **启动即崩：`listen EACCES: permission denied 127.0.0.1:8089`**：Windows 的 winnat
  （Hyper-V / WSL 动态端口保留）会把一段段 TCP 端口划进排除范围
  （`netsh interface ipv4 show excludedportrange protocol=tcp` 可查），实测本机保留了
  7992–8091，HTTP 门端口 8089 正好落在里面——任何程序 listen 都会报 `EACCES`，
  且没有任何进程占用、重启电脑也不解决（保留范围重启后还会漂移）。
  HTTP 门端口改为 `9089`（`index.js` / `setup.js` 两处常量 + 测试客户端），
  `setup.js` 下次运行会自动把两处 `channel.lua` 重写成新端口，无需手工改客户端配置。
  TCP 游戏端口 8101 不受影响。`index.js` 的监听也补了 `error` 事件兜底：
  再撞上 `EACCES` / `EADDRINUSE` 时打印排查指引而不是抛未处理异常直接崩掉。
- **「明明点的是自己的专武，却装上了一把别的武器（甚至别武器类型的）」，而且怎么点都换不回来、
  重进游戏也没恢复**（根因，本机实测账号复现）：
  1. 老存档里 `item_uuid` 有大量重复（同一 uuid 被多件道具共用）。
     `req_character_equip_weapon`（`src/handlers/character.js`）按
     `player.bag.items.find(it => it.item_uuid === uuid && kind === 'weapon')` 定位武器，
     命中的是数组里**第一件**同 uuid 的道具。实测证据（桌面 `Nornium_save_backup_2026-09-19`
     里的账号 10）：莎乐美（角色 10201，武器类型 5 礼器）身上是 `4010100 卷核FX`（uuid 43），
     而背包里 `bag[53] = 2020400 XF300「夜鸣」（枪械，类型 4）` 与
     `bag[209] = 4072601 梦魇之灯（礼器，类型 5，6★）` **共用 uuid 43 且枪械排在前** ——
     玩家在换武器界面点的是那件 6★ 礼器，客户端发 `item_uuid = 43`，服务端却装上了枪械。
  2. 服务端此前**从不校验武器类型**。客户端的武器列表是按「当前已装备武器的 `subType`」
     过滤的（`UI_Weapon_Change_C.lua:85-104`），于是装上枪械之后 UI 里只剩枪械可选，
     玩家想换回礼器都做不到 —— 错误被就地固化，`res_character_list` 每次登录都把它发回去，
     所以重进游戏也不恢复（游戏内症状：「她的武器类型变成了枪械」）。
  3. 修法：① 加载存档时消除重复 uuid（见上方 Changed）；②
     `req_character_equip_weapon` / `req_character_swap_weapon` 增加类型校验
     （`d_bag_item_weapon.subType` 必须等于 `d_character.profession`），不匹配回
     `INVALID_ITEM(3)` 并记 `[character] 拒绝…` 日志 —— 官方协议里本就有这个错误码；
     ③ 已被装错的角色在加载存档时自动换回背包里同类型最好的武器（见上方 Changed）。
     验证：实机账号 10 迁移后莎乐美拿到 `4072601 梦魇之灯`（正是当初点的那件），
     枪械 `2020400` 回到背包；另有角色 10701（巨刃）被同类 bug 换成
     `5010300 16-3型诺伦环`（宝轮），也一并修正为 `1072601 余晖之盈`。
- **`load` 忽略参数，恒报 `0 账号 / 0 玩家`**（根因）：`console.js` 的
  `handleCommand` 用 `switch (cmd.split(/\s+/)[0])` 分派，`case 'load': return cmdLoad();`
  只透传命令名，而 `cmdLoad()`（`console.js:35`）**形参表是空的** —— 路径在分派处就被丢了。
  证据：在 `GHS_DATA_DIR=<临时目录>` 下直接调 `handleCommand('load <真实备份目录>')`，
  输出与裸 `load` **逐字相同**（`0 个账号 / 0 个玩家档案`），备份目录里的 35 个账号
  一个都没被读。使用者看到的是「指令没报错、数字也对，就是没效果」。
  现在参数会被解析、校验、使用；没有参数的 `load` 行为不变。
- **向导把同一个游戏目录列成两个候选**：`detectCandidates()` 用
  `if (resolved && !found.includes(resolved))` 去重，是**大小写敏感**的字符串比较；
  而 Windows 路径大小写不敏感，本机 Steam 注册表的 `SteamPath` 写的是 `d:\steam`、
  仓库却在 `D:\Steam`，于是弹出：
  `1. D:\Steam\steamapps\common\Nornium\Nornium` /
  `2. d:\steam\steamapps\common\Nornium\Nornium` 让用户"二选一"。
  新增 `canonicalPath()`（盘符转大写 + 分隔符统一）与 `pathKey()`（再整体小写）做去重键，
  展示路径也一并归一化；现在本机 `detectCandidates()` 只返回 1 个候选。
- **`restore` 是唯一不可逆操作却没有任何兜底**：见上方 Added 的「`restore` / `load` 动档前自动快照」。
- **固定 300ms 排空挡不住残留会话回写**：`restore`/`load` 原先「kick → `await delay(300)` → 改文件」。
  `kick()` 只是 100ms 后 destroy socket，而 `savePlayer` 有 100+ 个调用点、都是把内存里的
  **整份** doc 写回，`handlers/index.js` 的 `dailyTick` 还是 60s 定时器同样会写 ——
  撞上就是「刚恢复的档被旧档覆盖」。见上方 Changed 第 1 条。
- **`test/persistence_check.js` 污染真实存档**：两次 `spawn('node', ['index.js'], {cwd: server})`
  都没传 `GHS_DATA_DIR`，测试账号直接写进 `server\data\` —— 历史上"发布前需要清档"
  多半就是它造成的，而玩家跑过测试再开服，自己的档里会多出一个 `persistXXXXX` 账号。
  现在用 `mkdtempSync` 的临时目录，跑完删除。
- 控制台 `>> 未知指令 "..."` 的回显不再把整行改小写（`console.js` 原先整行 `toLowerCase()`，
  `C:\Users\...` 会显示成 `c:\users\...`，看起来像另一条路径）。只有命令名参与匹配时小写。
- **`点我启动.bat` 里凭空出现的 `'??' is not recognized ...`**：见上方 Changed 的启动器条目
  （根因是 cmd.exe 解析含多字节字符的批处理会错位；修法是让 bat 里一个非 ASCII 字节都不剩）。

### Removed

- 无（本次没有移除任何对外行为；`load` 无参数时的语义与原先完全一致）。

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
