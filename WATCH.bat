@echo off
REM Double-click this to PLAY while the game is being worked on.
REM
REM It opens the game and keeps it open. When something changes, it waits for the
REM change to finish landing and then reloads the window once - not five times.
REM If the game crashes it comes straight back, and the reason appears in the
REM panel in the game's top-left corner.
REM
REM Close the game window when you are done; then close this one.
setlocal
cd /d "%~dp0"
echo.
echo ============================================================
echo   HoopClone - PLAY ^(stays open while work is happening^)
echo ============================================================
echo.
echo   Move ......... W A S D  or  Arrow keys
echo   Shoot ........ hold SPACE to charge, release near the top
echo   Quit ......... close the game window
echo.
REM No -ExecutionPolicy override on purpose. This machine is set to RemoteSigned,
REM which already runs a local unsigned script like this one; weakening the policy
REM to launch a dev tool would be a security change nobody asked for.
powershell -NoProfile -File "%~dp0tools\dev\watch.ps1"
echo.
echo Watcher stopped.
pause
endlocal
