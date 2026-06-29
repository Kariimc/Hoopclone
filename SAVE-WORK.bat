@echo off
REM Double-click this WHEN YOU FINISH working. Saves everything you changed.
cd /d "%~dp0"
echo.
echo Saving your work...
echo.

REM Remove a stray file accidentally named "git" (left over from a mistyped command).
if exist "%~dp0git" del /q "%~dp0git" >nul 2>nul

REM 1) Stage and commit whatever changed (ok if there's nothing new).
git add -A
git commit -m "work session save" >nul 2>nul

REM 2) ALWAYS sync with GitHub BEFORE pushing. This is the part that was missing:
REM    without it, a push is rejected whenever your copy is behind. --autostash
REM    protects anything not yet committed; --rebase keeps history clean.
echo Syncing with GitHub...
git pull --rebase --autostash
if not "%errorlevel%"=="0" (
  echo.
  echo *** Sync needs attention above. Screenshot this window and send it. ***
  echo.
  pause
  exit /b 1
)

REM 3) Now the push can't be rejected for being behind.
git push
if "%errorlevel%"=="0" (
  echo.
  echo Saved and uploaded.
) else (
  echo.
  echo *** Upload failed - screenshot this window and send it. ***
)
echo.
pause
