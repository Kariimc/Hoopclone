@echo off
REM ============================================================
REM  Double-click this WHEN YOU FINISH working on any machine.
REM  It saves everything you changed (including art assets) up
REM  to GitHub, so the other machine can GET-LATEST and have it.
REM ============================================================
cd /d "%~dp0\..\.."
echo.
echo Saving your work to GitHub...
echo.
git add -A
git commit -m "work session save"
if %errorlevel%==0 (
  git push
  echo.
  echo Saved and uploaded. The other machine can now Get-Latest.
) else (
  echo.
  echo Nothing new to save since last time ^(that's fine^).
)
echo.
pause
