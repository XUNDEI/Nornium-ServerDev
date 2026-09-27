@echo off
setlocal
chcp 65001 >nul 2>nul
title Nornium ServerDev - local private server
cd /d "%~dp0server"

REM ==========================================================================
REM  This launcher is intentionally PURE ASCII. Do not add any Chinese here.
REM
REM  cmd.exe mis-parses a .bat containing multi-byte characters: it can end up
REM  executing the leftover bytes of a character as a command, which shows up as
REM  "'??' is not recognized as an internal or external command" out of nowhere.
REM  (Reported on this machine on the line right after the "step 2" banner.)
REM
REM  So every human-readable message lives in the Node scripts instead:
REM    - setup.js prints the wizard, the "step 1 / step 2" banners and the hints
REM      (it knows whether the game will be auto-launched, so no if/else here)
REM    - index.js prints the server banner and the "server stopped" notice
REM  Non-ASCII output from Node is safe: Node writes to the console via the
REM  Win32 wide-char API, independent of the active code page.
REM
REM  server/test/setup_check.js asserts this file stays ASCII-only.
REM ==========================================================================

where node >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Node.js not found.
    echo         Please install Node.js 18 or newer: https://nodejs.org/
    echo         Then double-click this file again.
    echo.
    pause
    exit /b 1
)

node setup.js --from-bat
if errorlevel 1 (
    echo.
    echo [ERROR] Setup did not finish, so the server was not started.
    echo         Fix the problem reported above, then run this file again.
    echo.
    pause
    exit /b 1
)

REM setup.js already printed the step-2 hints; launch the game via Steam only
REM when the wizard left the flag (single-line if on purpose: no block parsing).
if exist auto-launch.flag start "" steam://rungameid/2877160

node index.js

echo.
pause
endlocal
