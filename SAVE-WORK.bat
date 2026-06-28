@echo off
REM Double-click this WHEN YOU FINISH working. Saves everything you changed.
cd /d "%~dp0"
echo.
echo Saving your work...
echo.
git add -A
git commit -m "work session save"
if %errorlevel%==0 (
  git push
  echo.
  echo Saved and uploaded.
) else (
  echo.
  echo Nothing new to save since last time ^(that's fine^).
)
echo.
pause
