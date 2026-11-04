@echo off
rem BigData / Docker manager one-click launcher (idempotent).
rem If the relay is already running, it only opens the browser.
rem Keep the "BigData Relay" window open while using the page.

cd /d "%~dp0"

netstat -ano | findstr ":8000" | findstr "LISTENING" >nul 2>&1
if %errorlevel%==0 (
    echo Relay is already running on http://127.0.0.1:8000
) else (
    echo Starting relay on http://127.0.0.1:8000 ...
    start "BigData Relay" cmd /k python docker-relay.py 8000
    timeout /t 2 /nobreak >nul
)

start "" "http://127.0.0.1:8000/bigdata"
