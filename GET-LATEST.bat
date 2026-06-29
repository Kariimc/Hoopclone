@echo off
REM Double-click this BEFORE you start working. Gets the newest version.
cd /d "%~dp0"
echo.
echo Getting the latest version...
echo.
REM --autostash protects any work-in-progress so the update can't be blocked.
git pull --rebase --autostash
echo.
if %errorlevel%==0 (
  echo Done. You are up to date. Open the project in Godot now.
) else (
  echo *** Something needs attention above. Screenshot this window. ***
)
echo.
pause
