# WHERE GODOT IS, ANSWERED IN ONE PLACE.
#
# Two things needed this answer and each had its own copy: the live watcher and PLAY.bat.
# One of those copies looked in Downloads and nowhere else, Godot moved out of Downloads
# some time after 30 July 2026, and the watcher was dead from that day until 25 August
# without anything saying so. A second copy of a lookup is a second thing to go stale.
#
# IT NEVER DOWNLOADS ANYTHING. The old PLAY.bat fetched a Godot off the internet and ran
# it when it could not find one, which is a standing no in Kariim's ledger (F-64): nothing
# installs software on his machine without him saying so. It was also fetching 4.3 while
# this project needs 4.7, so the silent "fix" would have opened the game in the wrong
# engine. Missing Godot is now reported, never quietly solved.
#
# It REMEMBERS what it found, in godot-path.txt beside the project, and checks that the
# remembered answer still exists before trusting it. So the next time it moves, nothing
# breaks: it searches again and writes down the new answer.
#
#   $g = & "$PSScriptRoot\find-godot.ps1" -Project "C:\path\to\project"
#   returns the full path, or an empty string if there is genuinely none on this machine.

param([string]$Project = "")

if (-not $Project) { $Project = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$remember = Join-Path $Project "godot-path.txt"

if (Test-Path $remember) {
    $saved = (Get-Content $remember -TotalCount 1 -ErrorAction SilentlyContinue)
    if ($saved) { $saved = $saved.Trim() }
    if ($saved -and (Test-Path $saved -PathType Leaf)) { return $saved }
}

# The console build is deliberately the last resort. It opens a black command window
# beside the game on every launch, and his rule of 2026-08-25 is that testing his game
# does not cover the screen in command windows.
$roots = @("$env:USERPROFILE\Documents", "$env:USERPROFILE\Downloads",
           "$env:USERPROFILE\Desktop", "$env:USERPROFILE\OneDrive\Desktop",
           "$env:LOCALAPPDATA\Programs", "C:\Godot", "$env:PROGRAMFILES")
# -File matters more than it looks. The download unzips into a FOLDER literally named
# "Godot_v4.7-stable_win64.exe", with the real program inside it. Without this, the search
# hands back the folder, every check that only asks "does this exist" passes, and the
# launch opens a folder in Explorer instead of the game. Caught by running it, 2026-08-25.
$hits = foreach ($r in $roots) {
    if (Test-Path $r) {
        Get-ChildItem $r -Recurse -Depth 2 -File -Filter "Godot*win64*.exe" -ErrorAction SilentlyContinue
    }
}
$pick = $hits | Where-Object { $_.Name -notlike "*console*" } | Sort-Object Name -Descending | Select-Object -First 1
if (-not $pick) { $pick = $hits | Sort-Object Name -Descending | Select-Object -First 1 }

$found = ""
if ($pick) { $found = $pick.FullName }
if (-not $found) {
    $onPath = Get-Command godot.exe, godot4.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($onPath) { $found = $onPath.Source }
}
if ($found) { Set-Content -Path $remember -Value $found -Encoding utf8 }
return $found
