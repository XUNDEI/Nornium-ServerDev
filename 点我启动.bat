@echo off
setlocal
chcp 65001 >nul 2>nul
title Nornium ServerDev - 本地私服
cd /d "%~dp0server"

echo ================================================================
echo   Nornium ServerDev - 失乐星图本地私服
echo   完全免费开源。如果你是花钱买来的，请联系卖家退款：你被骗了。
echo ================================================================
echo.

where node >nul 2>nul
if errorlevel 1 (
    echo [错误] 没有检测到 Node.js。
    echo        请先安装 Node.js 18 或更高版本： https://nodejs.org/
    echo        装完重新双击本文件即可。
    echo.
    pause
    exit /b 1
)

echo ---- 第 1 步：初始化配置（自动完成，不需要手动拷文件） ----
node setup.js
if errorlevel 1 (
    echo.
    echo [错误] 初始化没完成，服务端未启动。请按上面的提示处理后重试。
    echo.
    pause
    exit /b 1
)

echo.
echo ---- 第 2 步：启动服务端 ----
if exist auto-launch.flag (
    echo 服务端就绪后会用 Steam 拉起游戏，稍等几秒即可看到游戏窗口。
    start "" steam://rungameid/2877160
) else (
    echo 请在 Steam 里手动启动《失乐星图》。
)
echo.
echo 游戏登录界面随便填账号和密码，点「注册」就能进主城。
echo 停止服务请在本窗口输入 stop 回车（或按 Ctrl+C）。
echo ================================================================
echo.

node index.js

echo.
echo 服务端已停止。
pause
endlocal
