## 问题与方案

根因：Windows winnat（Hyper-V/WSL 动态端口保留）把 TCP 7992–8091 划入排除范围，8089 落在其中，任何程序 listen 都报 `EACCES`，重启无效。已确认无进程占用、TCP 游戏端口 8101 不受影响。

方案：把 HTTP 登录门端口从 8089 改为 9089（已用 `netsh interface ipv4 show excludedportrange protocol=tcp` 复核 9089 不在任何保留范围内）。

## 改动内容

**代码（3 个文件的常量 + 注释）：**
1. `server/index.js:13` — `HTTP_PORT = 8089` → `9089`；同步更新第 1 行、第 48 行注释中的端口描述（79/80/81/90 行引用变量，无需改）。
2. `server/setup.js:28` — `HTTP_PORT = 8089` → `9089`（第 293 行生成 channel.lua、第 406 行写 runtime-config 均引用此变量，自动生效）。
3. `server/test/fake_client.js:13` — `HTTP_PORT = 8089` → `9089`（测试客户端）。

**顺带更新注释中的旧端口：**
4. `server/src/httpgate.js:1`、`server/src/editorapi.js:3` 的注释 8089 → 9089。

**配置：**
5. `server/runtime-config.json:7` — `http_port` 改为 9089（重跑 setup 也会自动重写，这里直接改掉保证一致）。

**文档：**
6. `README.md`（约 8 处）、`server/README.md`（3 处）、`CHANGELOG.md`（4 处）中的 8089 → 9089。

**channel.lua 自动重写（无需手工改）：**
`setup.js` 生成的 channel.lua 四元组含 HTTP 端口，旧值 8089 与新模板不匹配，下次启动 setup 会自动重写以下两个文件：
- `D:\Steam\steamapps\common\Nornium\Nornium\Content\Script\channel.lua`
- `C:\Users\xundei\AppData\Local\Nornium\Saved\channel.lua`

**小加固（防止同类问题再次静默崩溃）：**
7. `server/index.js` 的 listen 处补一个 `error` 事件处理：捕获 `EACCES`/`EADDRINUSE` 时打印人话提示（端口被 Windows 保留或被占用，附上 `netsh interface ipv4 show excludedportrange protocol=tcp` 排查命令），而不是抛未处理异常直接崩掉。

## 验证

1. 跑 `点我启动.bat`（setup + index），确认日志输出 `HTTP gate listening on 127.0.0.1:9089`，无报错。
2. 确认两处 channel.lua 已被自动重写为 `return {"local_dev", 8101, "127.0.0.1", "9089"}`。
3. 游戏能正常登录进主城（TCP 8101 不变）。
4. 运行 `node server/test/fake_client.js`（如项目原有测试入口）验证 HTTP 门可用。