@echo off
rem ============================================================
rem BigData / Docker 管理器 —— 局域网一键启动（带固定令牌）
rem
rem 用法：
rem   start-lan.bat                 用脚本内置令牌启动局域网模式
rem   start-lan.bat mytoken         临时用 mytoken 作令牌
rem   start-lan.bat mytoken 9000    临时用 mytoken + 端口 9000
rem
rem 修改默认令牌：编辑下面 TOKEN= 这一行
rem ============================================================

cd /d "%~dp0"

rem === 默认令牌（改这一行即可更换）===
set "TOKEN=bigdata2026"
set "PORT=8000"

rem 命令行覆盖
if not "%~1"=="" set "TOKEN=%~1"
if not "%~2"=="" set "PORT=%~2"

echo 启动局域网模式：令牌=%TOKEN% 端口=%PORT%
call start.bat lan %TOKEN% %PORT%
