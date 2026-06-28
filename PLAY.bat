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

REM (e) Still nothing? Download Godot ourselves, once, into a gitignored folder.
REM     (Matches the project's Godot 4.3; ~60 MB the first time, then reused.)
set "GODOT_BIN=%~dp0.godot-bin\Godot_v4.3-stable_win64.exe"
if not defined GODOT if exist "%GODOT_BIN%" set "GODOT=%GODOT_BIN%"
if not defined GODOT (
  echo Godot isn't installed here - downloading it once ^(~60 MB^), please wait...
  if not exist "%~dp0.godot-bin" mkdir "%~dp0.godot-bin"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $u='https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_win64.exe.zip'; $z='%~dp0.godot-bin\godot.zip'; Invoke-WebRequest -Uri $u -OutFile $z; Expand-Archive -Path $z -DestinationPath '%~dp0.godot-bin' -Force; Remove-Item $z" 2>nul
  if exist "%GODOT_BIN%" (
    set "GODOT=%GODOT_BIN%"
    echo Got it.
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
echo *** Couldn't get Godot running automatically. ***
echo.
echo This almost always means no internet right now (or a firewall/antivirus
echo blocked the download). Reconnect and double-click PLAY.bat again - it will
echo finish downloading Godot itself. Nothing for you to install.
echo.

:end
echo.
pause
endlocal
