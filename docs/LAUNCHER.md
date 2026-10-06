# 游戏启动器使用说明

> 启动器内嵌在存档编辑器里：打开 `http://127.0.0.1:9089/editor`，
> 左栏顶部切到「**游戏启动器**」。它与存档编辑、服务器管理共用同一个页面与服务端，
> 不需要安装任何额外软件。

---

## 1. 启动与状态

「启动与状态」页回答三个问题：游戏在哪、能不能启动、装了什么。

- **经 Steam 启动游戏**：通过 `steam://rungameid/2877160` 拉起游戏。游戏必须经 Steam
  启动（直接运行 exe 会因 Steamworks 检查退出），这一步没有捷径。
- **游戏目录**：来自 `server/runtime-config.json` 的 `game_path`（首次向导写入的）。
  显示异常时重跑一次仓库根目录的 `点我启动.bat` 向导，再重启服务端。
- **mod 补丁状态**：`GHSMods_P.pak` 是否在游戏 Paks 目录里、构建时间、来自哪些 mod。
  **游戏更新警告**：启动器记录构建时的游戏 exe 指纹（大小 + 修改时间），
  Steam 更新游戏后这里会提示「游戏已更新 · 建议重建」——mod 改的客户端文件可能
  已被官方更新覆盖语义，重建一次并对着 changelog 检查即可。

## 2. Mod 管理

完整格式规范见 [MOD_FORMAT.md](MOD_FORMAT.md)（写给 mod 作者）；
本页只讲玩家侧的操作。

| 操作 | 怎么做 | 说明 |
|---|---|---|
| 导入 | 填 mod 的 zip 或目录路径 → 导入 | 自动校验；id 冲突（同名 mod 已存在）会拒绝 |
| 启用/禁用 | mod 行首的勾选框 | 只有启用中的 mod 参与构建 |
| 调优先级 | ↑ / ↓ 按钮 | **越靠下越优先**：同名文件由更靠下的 mod 提供 |
| 删除 | 行尾垃圾桶 | 需要手输 mod id 确认；只删 mods\ 里的文件，不影响已装补丁 |
| 冲突报告 | 自动 | 列出被多个启用 mod 覆盖的文件、谁赢 |
| 构建安装 | 「合并启用 mod → 安装到游戏」 | repak 打包成 `GHSMods_P.pak` 放进游戏 Paks 目录 |
| 只看预览 | 「只看合并预览」 | 不落盘，看会装哪些文件、冲突怎么裁决 |
| 卸载补丁 | 启动页的「卸载 mod 补丁」 | 删掉那一个 pak 文件，游戏回到纯净状态 |

**生效时机**：构建安装后，**重启游戏**（退出客户端再经 Steam 启动）即可——
pak 只在游戏启动时挂载。服务端不需要重启。

## 3. 服务端数据表补丁

带 `server_patch/` 的 mod 在「应用服务端数据表补丁」后才会影响服务端行为
（编辑器目录、发放逻辑、抽卡池认识 mod 新增的道具/角色）。

- 应用前自动备份原表到 `mods/.gamedata_backup/`（只备份一次，永远是原始版本）；
- 应用后运行中的服务端**热重载**，不需要重启；
- 「还原服务端数据表」一键恢复全部被改的表。

## 4. 依赖

- **repak**（mod 打包必需）：启动器按以下顺序探测
  `GHS_REPAK` 环境变量 → `C:\Program Files\repak_cli\bin\repak.exe` → `PATH` →
  `ServerDev\tools\repak\repak.exe`。找不到时构建按钮禁用并给出提示。
  （本项目作者机：`winget`/GitHub 下载 repak_cli 后解到默认位置即可，oo2core 压缩 dll 随包分发。）
- **Steam**：启动游戏必需（登录 Steam 客户端状态下）。

## 5. 常见问题

**Q：装了 mod 进游戏没变化？**
重启游戏了吗（pak 启动时挂载）？mod 勾了启用、点过「构建安装」吗？
启动页的补丁状态显示「已安装」吗？

**Q：Steam 更新游戏后 mod 失效/出问题？**
启动页会显示黄色「游戏已更新 · 建议重建」。去 Mod 管理页重新构建一次；
还不行说明官方更新改了 mod 覆盖的文件，去该 mod 的发布页等适配。

**Q：mod 改的角色/道具在编辑器里看不到？**
mod 需要带 `server_patch/` 并且你点过「应用服务端数据表补丁」——
客户端的 Lua 表和服务端的 JSON 表是两份，缺一不可（见 MOD_FORMAT.md 第 3/4 节）。

**Q：想彻底恢复原版？**
启动页「卸载 mod 补丁」+ Mod 管理页「还原服务端数据表」。
原版 pak 从未被改动，无需任何修复操作。

## 6. 给维护者 / 二次开发者

- 后端：`server/src/mods.js`（仓库/校验/合并/打包/安装/补丁）+ `server/src/zip.js`
  （零依赖 ZIP 读写）；HTTP 接口在 `server/src/editorapi.js` 的 `handleGameApi`。
- 前端：`server/editor/app.js` 的 `renderGameLaunch` / `renderMods`（「游戏启动器」工作区）。
- 回归测试：`node test\launcher_check.js`（后端全链路，含 repak 端到端——本机没装
  repak 时该段自动 SKIP）与 `node test\editor_ui_check.js`（前端渲染）。
- 技术依据（为什么是补丁 pak / 热更通道现状 / 客户端 Lua 加载规则）：
  `REVERSE_ENGINEERING.md` 第 14 节「Mod 能力调查」（该文档含敏感信息不随仓库分发；
  核心结论已内嵌于本文与 MOD_FORMAT.md）。