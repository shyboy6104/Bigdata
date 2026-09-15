@echo off
setlocal EnableExtensions

REM BigData CLI Windows wrapper. Keep this file ASCII-compatible for cmd.exe.
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_PATH=%SCRIPT_DIR%bigdata-cli.sh"
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
echo Running BigData CLI via WSL...
if defined HADOOP_ENVIRONMENT goto :run_with_hadoop_environment

wsl.exe bash "%WSL_SCRIPT_PATH%" %*
exit /b %errorlevel%

:run_with_hadoop_environment
wsl.exe env "HADOOP_ENVIRONMENT=%HADOOP_ENVIRONMENT%" bash "%WSL_SCRIPT_PATH%" %*
exit /b %errorlevel%

:run_with_git_bash
echo Docker is unavailable in WSL; running BigData CLI via Git Bash...
set "MSYS_NO_PATHCONV=1"
set "MSYS2_ARG_CONV_EXCL=*"
pushd "%SCRIPT_DIR%" >nul
"%GIT_BASH_PATH%" "./bigdata-cli.sh" %*
set "CLI_EXIT_CODE=%errorlevel%"
popd >nul
exit /b %CLI_EXIT_CODE%

:wsl_error
echo ERROR: WSL 2 is not installed, has no default Linux distribution, or cannot start.
echo Run "wsl --status" and install a Linux distribution first.
exit /b 1

:docker_error
echo ERROR: Docker CLI was not found in Windows PATH.
echo Install Docker Desktop and reopen the terminal.
exit /b 1

:docker_daemon_error
echo ERROR: Docker daemon is not available.
echo Start Docker Desktop and wait until the engine is running.
exit /b 1

:compose_error
echo ERROR: Docker Compose V2 is not available.
echo Check with "docker compose version".
exit /b 1

:path_error
echo ERROR: Failed to convert the project path to a WSL path.
echo Project script: "%SCRIPT_PATH%"
exit /b 1

:wsl_docker_error
echo ERROR: Docker is not available inside the default WSL distribution.
echo Enable Docker Desktop WSL Integration for that distribution,
echo or install Git for Windows so this wrapper can use Git Bash as a fallback.
exit /b 1
