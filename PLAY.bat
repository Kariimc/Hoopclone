@echo off
REM  PLAY - opens the game. That is all it does.
REM
REM  KARIIM'S ORDER, 2026-08-25: "fix PLAY.bat, split the update from the launch".
REM
REM  WHAT IT USED TO DO AND WHY THAT WAS WRONG. Both are standing noes in his own ledger
REM  rather than opinions:
REM
REM   1. IT RAN AN UPDATE FIRST. Double-clicking PLAY pulled from the internet and then
REM      ran whatever came down. That is ledger F-73: a file that updates itself and then
REM      runs is a file that executes somebody else's lines on his machine. Getting the
REM      latest is now a separate, deliberate click: GET-LATEST.bat, which already existed
REM      and already did exactly that job on its own.
REM
REM   2. IT DOWNLOADED AN ENGINE WHEN IT COULD NOT FIND ONE. That is ledger F-64: nothing
REM      installs software on his machine without him saying so. It was also fetching
REM      Godot 4.3 while this project needs 4.7, so the silent "fix" would have opened his
REM      game in the wrong engine and left the game looking broken. Missing Godot is now
REM      reported in plain words, never quietly solved.
REM
REM  To play WHILE agents are working on the game, use PLAY-LIVE.vbs instead. It keeps one
REM  window open, reloads it when work lands, and never takes your keyboard.

setlocal
cd /d "%~dp0"
set "PROJDIR=%~dp0"
set "PROJDIR=%PROJDIR:~0,-1%"

echo.
echo ============================================================
echo   HoopClone - PLAY
echo ============================================================
echo.
echo   This only opens the game.
echo   To get the newest version first, close this window and
echo   double-click GET-LATEST.bat, then come back.
echo.

REM One lookup, shared with the live watcher, so the two can never disagree about where
REM Godot is. It remembers what it finds and finds it again if it ever moves.
set "GODOT="
for /f "usebackq delims=" %%G in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\dev\find-godot.ps1" -Project "%PROJDIR%"`) do set "GODOT=%%G"

if not defined GODOT goto :no_godot
if not exist "%GODOT%" goto :no_godot

echo   Engine: %GODOT%
echo.
echo   Move ......... W A S D  or  Arrow keys
echo   Shoot ........ hold SPACE to charge, release near the top of the meter
echo   Quit ......... close the game window
echo.
echo   Opening the game...
echo.
start "" "%GODOT%" --path "%PROJDIR%"
goto :end

:no_godot
echo.
echo   *** Godot is not on this machine, or it has moved somewhere unusual. ***
echo.
echo   Nothing was downloaded and nothing was changed. Installing things
echo   without being asked is a standing no.
echo.
echo   To fix it: install Godot 4.7, or if you already have it, put the full
echo   path to its .exe on the first line of a file called godot-path.txt in
echo   this folder. Everything here picks it up from there.
echo.

:end
echo.
pause
endlocal
