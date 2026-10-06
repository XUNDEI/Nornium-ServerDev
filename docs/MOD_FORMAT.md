# Nornium Mod 格式规范（v1）

> 适用范围：失乐星图 ServerDev 启动器（「游戏启动器 → Mod 管理」）。
> 本文写给 mod 作者与分发者。校验工具：`node tools/validate_mod.js <目录或zip>`
> （与启动器导入用的是**同一份校验器**，这里通过 = 那里一定通过）。

---

## 1. 一个 mod 是什么

一个 mod 就是**一个文件夹 + 一份清单**，不需要任何构建工具：

```
my-mod/
├── mod.json                 ← 必需：元信息清单
├── files/                   ← 可选：客户端文件覆盖（按 pak 内路径镜像）
│   └── Nornium/
│       └── Content/
│           └── Script/
│               └── ClientDatas/
│                   └── d_character.lua
└── server_patch/            ← 可选：服务端数据表合并补丁
    └── d_character.json
```

两种 mod 类型可以单独存在，也可以组合：

- **客户端 mod**（`files/`）：覆盖游戏 pak 里的任意文件。游戏 Lua、数据表（`ClientDatas/*.lua`）、
  乃至美术资产（烘焙好的 uasset/uexp/ubulk）都在此列。启动器把所有启用 mod 的 `files/`
  合并打包成单个 `GHSMods_P.pak` 放进游戏 Paks 目录 —— 原版 pak 一个字节不动。
- **服务端 mod**（`server_patch/`）：把改动合并进私服的 `reference/gamedata/*.json` 数据表，
  让编辑器目录、发放逻辑、抽卡池「认识」mod 新增的道具/角色。

## 2. mod.json 字段

```json
{
  "id": "my-mod",
  "name": "我的 Mod",
  "version": "1.0.0",
  "author": "你的名字",
  "description": "一句话说明它改了什么（可选）"
}
```

| 字段 | 必需 | 规则 |
|---|---|---|
| `id` | ✅ | 2..40 个字符，小写字母/数字/`-`/`_`，字母或数字开头；**必须与目录名一致** |
| `name` | ✅ | 任意非空字符串，启动器里显示的名字 |
| `version` | ✅ | 建议语义化（`1.2.0`） |
| `author` | ✅ | 作者署名 |
| `description` | — | 一句话描述 |
| `priority` | ⚠️ 废弃 | 优先级由启动器里的**启用顺序**决定（越靠下越优先），字段会被忽略并警告 |

## 3. files/ —— 客户端覆盖

规则只有两条：

1. **路径必须以 `Nornium/` 开头**（pak 的挂载点是 `../../../`，游戏内路径都是
   `Nornium/Content/...`）。对照方法：用 repak 列出原版 pak 找准路径——

   ```powershell
   & "C:\Program Files\repak_cli\bin\repak.exe" --aes-key 0x7626646E82C7F641D07C231173E9643452537CC27BF2FF6C8484E1674EB2C760 list .\Nornium\Content\Paks\pakchunk0-Windows.pak
   ```

   （原版 pak 的加密参数等背景见项目的逆向文档 `REVERSE_ENGINEERING.md` 第 1 节；
   该文档含敏感信息不随仓库分发，打包 mod 本身不需要它 —— 你只需要原文件的路径。）

2. **必须是文件级整文件覆盖**：覆盖 `d_character.lua` 就是整份替换这张表，
   不能只写「想改的那一行」。想基于原版改？先用 repak 把原文件解出来当底稿。

安全约束（校验器会拦）：不允许 `..` 路径穿越、不允许符号链接、
`files/` 之外的文件（如 `mod.json`）不会被打进 pak。

### 客户端 Lua / 数据表速查

- 全部游戏逻辑与数据表都在 pak 内 `Nornium/Content/Script/` 下（451 个明文 Lua，
  其中 `ClientDatas/` 是数据表）。改数据表 = 改 `ClientDatas/d_xxx.lua`，
  它们就是 Lua 源文件，返回一张表。
- 客户端侧的背景知识（角色管线、动画组织、表字段语义）见
  `REVERSE_ENGINEERING.md` 第 8/14 节 —— 加角色、改模型前必读第 14 节。
- **改动客户端数据表时记得同步 `server_patch/`**（第 4 节）：服务端用的 JSON 表
  与客户端 Lua 表是两份，编辑器与发放逻辑只认 JSON 那份。

## 4. server_patch/ —— 服务端数据表补丁

目录下每个 `<表名>.json`（如 `d_character.json`）描述对私服数据表的**增量合并**：

```json
{
  "10101": { "name": "改名了", "profession": 5 },
  "99901": { "id": 99901, "name": "全新角色", "profession": 1, "firstWeapon": 3011100 }
}
```

合并语义：

- 键 = 数据表行 id（字符串化的数字，与 `reference/gamedata/*.json` 一致）；
- 行存在 → **深合并**（补丁没提的字段保留原值）；行不存在 → 新增；
- 数组一律整体替换；
- 多个启用 mod 改同一张表时按启用顺序合并（越靠下越优先）。

应用方式：启动器「Mod 管理 → 应用服务端数据表补丁」。首次应用前自动把原表备份到
`mods/.gamedata_backup/`，「还原服务端数据表」可精确恢复。应用后运行中的服务端
**热重载**，不需要重启。

> 放示例的这张表是 `d_character`（角色表），但同样适用于全部 109 张表（`d_bag_item`、
> `d_gacha_pool`、`d_word_cn`……）。表清单见 `REVERSE_ENGINEERING.md` 第 9.2 节。

## 5. 冲突与优先级

- 两个启用 mod 覆盖同一个文件时**不报错**：按启用顺序裁决，越靠下的赢，
  「冲突报告」面板会列出每处冲突与胜者。mod 作者无需（也无法）在文件层面做兼容垫片。
- 校验有**错误**的 mod 不参与构建；有**警告**的照常参与（警告只是提示）。

## 6. 分发

1. 把 mod 文件夹压缩成 zip（根目录直接放 `mod.json`，或包一层文件夹都行——
   启动器与校验工具都会自动剥顶层目录）；
2. 发布前跑一遍 `node tools/validate_mod.js your-mod.zip`，确认零错误；
3. 在发布页写明：适配的服务端/游戏版本、是否需要配合某个其它 mod、
   `server_patch` 改了哪些表（方便服主评估要不要应用）。

玩家侧：编辑器 → 游戏启动器 → Mod 管理 → 导入（填 zip 路径）→ 启用 → 构建安装。

## 7. 卸载与恢复（为什么这个方案对玩家友好）

- 卸载 mod 补丁 = 删除游戏 Paks 目录里**一个文件**（`GHSMods_P.pak`），
  原版 pak 从未被改动，Steam 校验完整性也不会清除 mod（它是新增文件）；
- 服务端数据表随时一键还原；
- mod 启用/禁用/重排后点「构建」即可重新生成补丁 pak，不用重装任何东西。

## 8. 设计决策（给未来的维护者）

- **为什么合并成单个 pak**：UE 按 pak 文件名决定挂载优先级（`_P` 后缀 +100），
  每个 mod 一个 pak 就要跟挂载顺序搏斗；单文件从根上消灭这个问题。
- **为什么 V8B 不加密**：原版 pak 是 V11 + 自带 path hash seed + 加密索引；
  引擎对同目录未加密 pak 不要求密钥，V8B 是所有 UE5 都认的最保守格式。
- **为什么启用状态不写进 mod.json**：mod 目录是「作者的产物」，应保持只读、可整目录替换；
  「玩家本地怎么用」是启动器状态（`mods/.launcher.json`），两者分开升级互不踩。
- 测试：`server/test/launcher_check.js`（校验/导入/合并/冲突/补丁/repak 端到端）。