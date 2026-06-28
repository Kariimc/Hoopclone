@echo off
REM ============================================================
REM  Double-click this BEFORE you start working on any machine.
REM  It pulls the newest version of the project from GitHub so
REM  you are never editing a stale copy.
REM ============================================================
cd /d "%~dp0\..\.."
echo.
echo Getting the latest version from GitHub...
echo.
git pull
echo.
if %errorlevel%==0 (
  echo Done. You are up to date. You can open the project in Godot now.
) else (
  echo.
  echo *** Something needs attention above. Screenshot this window. ***
)
echo.
pause
