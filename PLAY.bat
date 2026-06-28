@echo off
REM Double-click this to TEST the latest build: it gets the newest version,
REM then launches the game in Godot 4. (Godot must be installed on this PC.)
setlocal enabledelayedexpansion
cd /d "%~dp0"

REM Project dir = this folder, without the trailing backslash.
set "PROJDIR=%~dp0"
set "PROJDIR=%PROJDIR:~0,-1%"

echo.
echo ============================================================
echo   HoopClone - PLAY
echo ============================================================
echo.

REM --- 1) Get the newest build (best-effort; never blocks the launch) ---
echo Getting the latest build...
git pull
if not "%errorlevel%"=="0" (
  echo.
  echo  ^(Could not auto-update - launching what you already have.^)
  echo  Tip: run SAVE-WORK.bat to save your changes, then GET-LATEST.bat.
)
echo.

REM --- 2) Find Godot ---------------------------------------------------------
set "GODOT="

REM (a) Your override: put the full path to Godot's .exe on line 1 of this file.
if exist "%~dp0godot-path.txt" set /p GODOT=<"%~dp0godot-path.txt"

REM (b) Already on PATH?
if not defined GODOT (
  for %%E in (godot.exe godot4.exe Godot.exe) do (
    if not defined GODOT where %%E >nul 2>nul && set "GODOT=%%E"
  )
)

REM (c) Sitting next to this script?
if not defined GODOT (
  for /f "delims=" %%G in ('dir /b /a:-d "%~dp0Godot*.exe" 2^>nul') do (
    if not defined GODOT set "GODOT=%~dp0%%G"
  )
)

REM (d) Common install folders (first match wins).
if not defined GODOT (
  for %%D in (
    "C:\Godot"
    "%LOCALAPPDATA%\Programs\Godot"
    "%PROGRAMFILES%\Godot"
    "%USERPROFILE%\Downloads"
    "%USERPROFILE%\Desktop"
  ) do (
    if not defined GODOT (
      for /f "delims=" %%G in ('dir /b /a:-d "%%~D\Godot*.exe" 2^>nul') do (
        if not defined GODOT set "GODOT=%%~D\%%G"
      )
    )
  )
)

if not defined GODOT goto :no_godot

REM --- 3) Controls + launch -------------------------------------------------
echo Found Godot: !GODOT!
echo.
echo Controls:
echo   Move ......... W A S D  or  Arrow keys
echo   Shoot ........ hold SPACE to charge, release near the top of the meter
echo   Quit ......... close the game window  ^(or Alt+F4^)
echo.
echo Launching the game...  (a window will open)
echo.
"!GODOT!" --path "%PROJDIR%"
goto :end

:no_godot
echo.
echo *** Godot was not found on this PC. ***
echo.
echo HoopClone runs in Godot 4. To fix this once:
echo   1^) Install Godot 4   ^(https://godotengine.org/download^)
echo   2^) Make a file next to this one named:   godot-path.txt
echo   3^) Put the FULL path to your Godot .exe on the first line, e.g.:
echo        C:\Godot\Godot_v4.3-stable_win64.exe
echo   Then double-click PLAY.bat again.
echo.

:end
echo.
pause
endlocal
