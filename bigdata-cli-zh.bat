@echo off
setlocal EnableExtensions

REM BigData CLI Windows 包装脚本（中文版）。本文件以 GBK 编码保存，
REM 匹配中文 Windows 的 OEM 代码页(936)，无需 chcp 即可正确显示中文。
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_PATH=%SCRIPT_DIR%bigdata-cli-zh.sh"
set "WSL_SCRIPT_PATH="
set "GIT_BASH_PATH="

where.exe wsl.exe >nul 2>&1
if errorlevel 1 goto :wsl_error

wsl.exe --status >nul 2>&1
if errorlevel 1 goto :wsl_error

where.exe docker.exe >nul 2>&1
if errorlevel 1 goto :docker_error

docker.exe info >nul 2>&1
if errorlevel 1 goto :docker_daemon_error

docker.exe compose version >nul 2>&1
if errorlevel 1 goto :compose_error

for /f "usebackq delims=" %%I in (`wsl.exe wslpath -a "%SCRIPT_PATH%" ^<nul 2^>nul`) do set "WSL_SCRIPT_PATH=%%I"
if not defined WSL_SCRIPT_PATH goto :path_error

wsl.exe docker info <nul >nul 2>&1
if errorlevel 1 goto :try_git_bash
wsl.exe docker compose version <nul >nul 2>&1
if not errorlevel 1 goto :run_with_wsl
wsl.exe docker-compose --version <nul >nul 2>&1
if not errorlevel 1 goto :run_with_wsl

:try_git_bash
if exist "%ProgramFiles%\Git\bin\bash.exe" set "GIT_BASH_PATH=%ProgramFiles%\Git\bin\bash.exe"
if not defined GIT_BASH_PATH if exist "%ProgramFiles%\Git\usr\bin\bash.exe" set "GIT_BASH_PATH=%ProgramFiles%\Git\usr\bin\bash.exe"
if defined GIT_BASH_PATH goto :run_with_git_bash
goto :wsl_docker_error

:run_with_wsl
echo 正在通过 WSL 运行 BigData CLI...
if defined HADOOP_ENVIRONMENT goto :run_with_hadoop_environment

wsl.exe bash "%WSL_SCRIPT_PATH%" %*
exit /b %errorlevel%

:run_with_hadoop_environment
wsl.exe env "HADOOP_ENVIRONMENT=%HADOOP_ENVIRONMENT%" bash "%WSL_SCRIPT_PATH%" %*
exit /b %errorlevel%

:run_with_git_bash
echo WSL 中不可用 Docker，改为通过 Git Bash 运行 BigData CLI...
set "MSYS_NO_PATHCONV=1"
set "MSYS2_ARG_CONV_EXCL=*"
pushd "%SCRIPT_DIR%" >nul
"%GIT_BASH_PATH%" "./bigdata-cli-zh.sh" %*
set "CLI_EXIT_CODE=%errorlevel%"
popd >nul
exit /b %CLI_EXIT_CODE%

:wsl_error
echo 错误：未安装 WSL 2，或未设置默认 Linux 发行版，或无法启动。
echo 请先执行 "wsl --status" 检查并安装一个 Linux 发行版。
exit /b 1

:docker_error
echo 错误：Windows PATH 中找不到 Docker 命令行。
echo 请安装 Docker Desktop 后重新打开终端。
exit /b 1

:docker_daemon_error
echo 错误：Docker 守护进程不可用。
echo 请启动 Docker Desktop，并等待引擎运行后再试。
exit /b 1

:compose_error
echo 错误：Docker Compose V2 不可用。
echo 请使用 "docker compose version" 检查。
exit /b 1

:path_error
echo 错误：无法将项目路径转换为 WSL 路径。
echo 项目脚本："%SCRIPT_PATH%"
exit /b 1

:wsl_docker_error
echo 错误：默认 WSL 发行版内不可用 Docker。
echo 请在 Docker Desktop 中为该发行版启用 WSL 集成，
echo 或安装 Git for Windows，以便本包装脚本可回退使用 Git Bash。
exit /b 1
