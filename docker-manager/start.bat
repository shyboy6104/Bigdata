@echo off
rem BigData / Docker manager one-click launcher (idempotent).
rem If the relay is already running, it only opens the browser.
rem Keep the "BigData Relay" window open while using the page.
rem
rem 用法：
rem   start.bat                 仅本机访问（127.0.0.1）
rem   start.bat lan             局域网可访问（0.0.0.0），不设令牌
rem   start.bat lan mytoken     局域网可访问，并设置访问令牌 mytoken
rem   start.bat lan mytoken 9000  自定义端口+令牌+局域网

cd /d "%~dp0"

set "HOST=127.0.0.1"
set "PORT=8000"
set "TOKEN="

rem 解析参数
if /i "%~1"=="lan" (
    set "HOST=0.0.0.0"
    if not "%~2"=="" set "TOKEN=%~2"
    if not "%~3"=="" set "PORT=%~3"
) else if not "%~1"=="" (
    set "PORT=%~1"
)

netstat -ano | findstr ":%PORT%" | findstr "LISTENING" >nul 2>&1
if %errorlevel%==0 (
    echo Relay 已在端口 %PORT% 上运行
) else (
    echo 启动 relay：主机=%HOST% 端口=%PORT% 令牌=%TOKEN%
    set "RELAY_HOST=%HOST%"
    set "RELAY_TOKEN=%TOKEN%"
    if "%TOKEN%"=="" (
        start "BigData Relay" cmd /k "set RELAY_HOST=%HOST%&& python docker-relay.py %PORT% %HOST%"
    ) else (
        start "BigData Relay" cmd /k "set RELAY_HOST=%HOST%&& set RELAY_TOKEN=%TOKEN%&& python docker-relay.py %PORT% %HOST%"
    )
    timeout /t 2 /nobreak >nul
)

if "%TOKEN%"=="" (
    start "" "http://127.0.0.1:%PORT%/bigdata"
) else (
    start "" "http://127.0.0.1:%PORT%/bigdata?token=%TOKEN%"
)
