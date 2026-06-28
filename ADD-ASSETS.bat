@echo off
REM Double-click this to put your art into the game. It opens a file picker for
REM each piece — pick the image from your computer, or hit Cancel to skip one.
REM It copies them into the project and uploads them to GitHub. The game then
REM uses them automatically (no renaming, no paths to remember).
setlocal enabledelayedexpansion
cd /d "%~dp0"
if not exist "assets\textures" mkdir "assets\textures"

echo.
echo ============================================================
echo   HoopClone - ADD ART
echo   A picker opens for each item. Choose the file, or Cancel
echo   to skip anything you don't have yet.
echo ============================================================
echo.

call :pick "COURT FLOOR (hardwood)"        "court_floor"
call :pick "BASKETBALL (leather photo)"    "ball_albedo"
call :pick "CRIMSON WOLVES jersey"         "crw_jersey_albedo"
call :pick "STORM jersey"                  "stm_jersey_albedo"
call :pick "BAYSIDE jersey"                "bay_jersey_albedo"
call :pick "TEAM LOGO (crimson wolf)"      "crw_logo"

echo.
echo Saving to GitHub...
git add -A
git commit -m "assets: add art via ADD-ASSETS.bat" && git push
echo.
echo Done. Anything you added is uploaded; double-click PLAY.bat to see it.
echo.
pause
exit /b

:pick
REM %1 = label shown in the dialog,  %2 = target file base name
set "FILE="
for /f "usebackq delims=" %%F in (`powershell -NoProfile -STA -Command "Add-Type -AssemblyName System.Windows.Forms ^| Out-Null; $d=New-Object System.Windows.Forms.OpenFileDialog; $d.Title='Pick your %~1 image  (Cancel = skip)'; $d.Filter='Images (*.png;*.jpg;*.jpeg;*.webp)^|*.png;*.jpg;*.jpeg;*.webp'; if($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){[Console]::WriteLine($d.FileName)}"`) do set "FILE=%%F"
if not defined FILE (
  echo   - skipped %~1
  goto :eof
)
for %%I in ("!FILE!") do set "EXT=%%~xI"
copy /y "!FILE!" "assets\textures\%~2!EXT!" >nul
echo   + added %~1  ^=^>  assets\textures\%~2!EXT!
goto :eof
