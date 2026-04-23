@echo off
REM 大数据平台CLI管理工具 - Windows批处理包装器

REM 设置脚本目录
set SCRIPT_DIR=%~dp0

REM 检查WSL是否可用
wsl --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: WSL not found or not properly installed
    echo Please install Windows Subsystem for Linux
    exit /b 1
)

REM 检查Docker是否可用
docker --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Docker not found
    echo Please install Docker and ensure it's running
    exit /b 1
)

REM 检查Docker Compose是否可用
docker-compose --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Docker Compose not found
    echo Please install Docker Compose
    exit /b 1
)

REM 运行WSL中的shell脚本
echo Running BigData CLI via WSL...
wsl bash "%SCRIPT_DIR%bigdata-cli.sh" %*