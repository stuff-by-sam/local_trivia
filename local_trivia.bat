@echo off
rem TRIVIA launcher (Windows) - double-click to start the server and open the presenter.
if "%~1"=="__open_when_ready__" goto :open_when_ready

setlocal
title TRIVIA
cd /d "%~dp0"

where npm >nul 2>nul
if errorlevel 1 (
  echo Node.js is required but was not found.
  echo Install the LTS version from https://nodejs.org then double-click this again.
  pause
  exit /b 1
)

rem If the server is already running, just open the presenter.
curl -s -o nul --max-time 1 http://localhost:3000/ 2>nul
if not errorlevel 1 (
  echo TRIVIA server is already running - opening the presenter.
  start "" "http://localhost:3000/present"
  exit /b 0
)

rem First run: install dependencies (needs internet once; offline ever after).
if not exist node_modules (
  echo First run - installing dependencies, this can take a minute...
  call npm install
  if errorlevel 1 (
    echo npm install failed.
    pause
    exit /b 1
  )
)

rem In the background: open the presenter as soon as the server answers.
start "" /min cmd /c ""%~f0" __open_when_ready__"

echo Starting TRIVIA - keep this window open while playing. Press Ctrl+C to stop.
call npm start
pause
exit /b 0

:open_when_ready
where curl >nul 2>nul
if errorlevel 1 (
  timeout /t 4 /nobreak >nul
  start "" "http://localhost:3000/present"
  exit
)
for /l %%i in (1,1,120) do (
  curl -s -o nul --max-time 1 http://localhost:3000/ 2>nul && (
    start "" "http://localhost:3000/present"
    exit
  )
  timeout /t 1 /nobreak >nul
)
exit
