@echo off
rem ============================================================
rem BigData / Docker 管理器 —— 局域网一键启动（账号登录模式）
rem
rem 用法：
rem   start-lan.bat                 局域网可访问，不设令牌（推荐，学生用账号登录）
rem   start-lan.bat mytoken         可选：设置令牌（带令牌的请求视为管理员）
rem   start-lan.bat mytoken 9000    可选：自定义端口
rem
rem 注意：不要把令牌发给学生！带正确令牌的请求会被视为管理员，
rem       可创建/删除账号并操作宿主机全部容器。
rem ============================================================

cd /d "%~dp0"

rem === 默认配置（编辑这两行即可更改）===
set "TOKEN="
set "PORT=8000"

rem 命令行覆盖
if not "%~1"=="" set "TOKEN=%~1"
if not "%~2"=="" set "PORT=%~2"

echo 局域网模式：端口=%PORT%  令牌=%TOKEN%
if "%TOKEN%"=="" (
    call start.bat lan "" %PORT%
) else (
    call start.bat lan %TOKEN% %PORT%
)