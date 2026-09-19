# reference/ — 逆向资产（只读）

本目录保存从 Nornium 客户端提取/还原的资产，是服务端运行与协议分析的基础。
**内容版权归原权利人所有，不属于本项目**，详见仓库根目录的 [NOTICE.md](../NOTICE.md)。

> 除非在重新解包游戏，否则**不要修改本目录**。

## 内容

| 路径 | 内容 | 服务端运行时是否读取 |
|---|---|---|
| `proto/` | 由 `proto.pb` 还原的 26 个 `.proto` 源文件（proto3，package `ghs`） | ✅ `src/protos.js` 加载 `proto/msg.proto` |
| `proto.pb` | 客户端内嵌的原始 `FileDescriptorSet` | ❌（还原 `proto/` 的输入） |
| `gamedata/` | 109 张数据表的 JSON 版（由 `client_lua/ClientDatas/*.lua` 转换） | ✅ `src/gamedata.js` 按需加载 |
| `client_lua/` | 客户端全部 Lua 脚本（协议与逻辑的唯一权威） | ❌（逆向分析用） |
| `lua-crypt.c` | 客户端内嵌 DES 的同源 C 实现（填充行为权威依据） | ❌ |

## 如何重新生成

### 提取客户端 Lua 与描述符

从自己的游戏安装目录用 repak 解包 pak（`repak unpack --aes-key <你的密钥> -o <输出目录> -i <包含路径> ...`），
把 Lua 脚本放到 `client_lua/`，描述符放到 `proto.pb`。pak 的 AES 密钥请自行从游戏文件中获取，
不随本仓库提供。

> ⚠️ 提取二进制文件不要用 PowerShell `>` 重定向（会转码损坏内容）。

### proto.pb → proto/

```bash
pip install protobuf
python tools/gen_proto.py
```

### ClientDatas/*.lua → gamedata/

```bash
pip install lupa
python tools/convert_gamedata.py
```

转换规则：键恰为连续 `1..n` 的 Lua 表转为 JSON 数组，其余转为对象且键字符串化。
服务端 `gamedata.query()` 已封装该差异。
