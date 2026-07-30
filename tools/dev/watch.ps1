# Keeps ONE playable HoopClone window alive while the game is being worked on.
#
#   Double-click WATCH.bat in the project root, or:
#   powershell -NoProfile -File tools\dev\watch.ps1
#
# WHAT WENT WRONG WITH THE FIRST VERSION, from its own log rather than a theory.
#
# 1. IT RELOADED ON EVERY SINGLE EDIT, two seconds after seeing one. During active
#    work that is a restart every few seconds - the log shows 21:29:49, :54, :59
#    and 21:30:03, four launches in fourteen seconds - so the window was never up
#    long enough to watch or listen to. It now waits for everything to hold still
#    for QuietSeconds and reloads ONCE, at the end of a burst. Files touched in
#    the last two seconds are left out of the reckoning entirely, so a rebuild
#    that takes forty seconds to write cannot look "settled" halfway through.
#
# 2. IT QUIT FOR GOOD THE FIRST TIME THE WINDOW WENT AWAY. Its last log line is
#    "window closed by user; watcher exiting" - and it had not run since. Any
#    crash, or one accidental close, ended the session permanently with no sign
#    of why. A window that dies in its first fifteen seconds is now read as a
#    crash and relaunched; a long-lived window closing is taken as deliberate, and
#    even then the watcher keeps waiting for the next change instead of exiting.
#
# 3. THERE WAS NO WAY TO PAUSE IT. A long asset rebuild yanked the window away
#    mid-play with nothing on screen to explain it. While .reload-hold exists
#    nothing restarts, and the reason written inside that file is shown in the
#    game's own corner panel.
#
# Import sidecars (*.import) are deliberately not watched. They are derived data,
# not source, so a reload triggered by one carries no change worth seeing. Worth
# recording: they were also suspected of causing a self-triggering restart loop -
# start the game, Godot rewrites a sidecar, the watcher restarts the game. That
# was WRONG. Measured with -Probe either side of a real ten-second windowed run:
# the watched set did not move, and no sidecar was rewritten. The bursts above
# were live edits, nothing else.
#
# It only ever kills the process it started itself, by PID - never by name - so
# the editor and everything else on the machine are untouched.

param(
    [string]$Project = "",
    [string]$Godot   = "",
    # How long everything must hold still before a reload. Long enough that a
    # working session with ordinary pauses in it does not bounce the window; the
    # .reload-hold file is what covers a deliberately long rebuild.
    [int]$QuietSeconds = 20,
    # Never reload more often than this, whatever happens.
    [int]$CooldownSeconds = 8,
    # Print a hash of what is being watched and exit, without launching anything.
    # This is how the .import feedback loop was proven fixed: probe, start Godot
    # once, probe again, and check the hash did not move.
    [switch]$Probe
)

$ErrorActionPreference = "SilentlyContinue"

if (-not $Project) { $Project = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
if (-not (Test-Path (Join-Path $Project "project.godot"))) {
    $Project = "C:\Users\Kariim\Dev\hoopclone"
}

if (-not $Godot) {
    $candidates = @(
        "C:\Users\Kariim\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe",
        "C:\Users\Kariim\Downloads\Godot_v4.7-stable_win64.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c -PathType Leaf) { $Godot = $c; break } }
    if (-not $Godot) {
        $found = Get-ChildItem "$env:USERPROFILE\Downloads" -Recurse -Depth 2 -Filter "Godot_v4*_win64.exe" |
                 Where-Object { $_.Name -notlike "*console*" } | Select-Object -First 1
        if ($found) { $Godot = $found.FullName }
    }
}
if (-not $Godot -or -not (Test-Path $Godot -PathType Leaf)) {
    Write-Host "Could not find Godot. Pass it explicitly: -Godot <full path to the .exe>"
    exit 1
}

$log       = Join-Path $Project ".watch.log"
$status    = Join-Path $Project ".build_status.txt"
$holdFile  = Join-Path $Project ".reload-hold"
$watchDirs = @("game", "assets", "data", "tests")

# Source files only. NOT *.import - Godot writes those itself on every start, and
# watching them is what made the window bounce every five seconds.
$patterns  = @("*.gd", "*.tscn", "*.tres", "*.json", "*.glb", "*.gltf",
               "*.png", "*.jpg", "*.jpeg", "*.wav", "*.ogg", "*.bvh")

$saidHold = $false

function Say([string]$line) {
    "$(Get-Date -f HH:mm:ss)  $line" | Add-Content $log
    Write-Host "$(Get-Date -f HH:mm:ss)  $line"
}

# What the game shows in its own corner, so the reason a window went away is on
# screen rather than in a terminal nobody is looking at.
function Feed([string]$line) {
    try { Set-Content -Path $status -Value $line -Encoding UTF8 } catch {}
}

function Fingerprint {
    # Returns the state of the watched files AND how many of them were written so
    # recently that they are probably still being written.
    #
    # Both halves matter. Leaving a just-touched file out of the stamp is what
    # stops the game being launched onto a half-written asset. But the count has
    # to come back too: a file that keeps being rewritten every second stays
    # permanently excluded, the stamp therefore stops moving, and the set LOOKS
    # settled while the work is still going on. Measured - that alone reloaded the
    # window in the middle of a burst of edits, which is the whole complaint.
    $cutoff = (Get-Date).ToUniversalTime().AddSeconds(-2)
    $parts = New-Object System.Collections.Generic.List[string]
    $fresh = 0
    foreach ($d in $watchDirs) {
        $full = Join-Path $Project $d
        if (-not (Test-Path $full)) { continue }
        Get-ChildItem $full -Recurse -File -Include $patterns | ForEach-Object {
            if ($_.LastWriteTimeUtc -le $cutoff) {
                $parts.Add("$($_.FullName)|$($_.LastWriteTimeUtc.Ticks)")
            } else {
                $fresh++
            }
        }
    }
    $pg = Join-Path $Project "project.godot"
    if (Test-Path $pg) { $parts.Add("project.godot|$((Get-Item $pg).LastWriteTimeUtc.Ticks)") }
    return @{ Stamp = (($parts | Sort-Object) -join ";"); Fresh = $fresh }
}

function StartGame {
    $p = Start-Process $Godot -ArgumentList '--path', $Project -PassThru
    Say "started game, pid $($p.Id)"
    return @{ Proc = $p; At = Get-Date }
}

if ($Probe) {
    $fp = (Fingerprint).Stamp
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($fp)
    $sha = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    $files = ($fp -split ";").Count
    Write-Host ("PROBE {0} {1} files" -f ([System.BitConverter]::ToString($sha).Replace("-","").Substring(0,16)), $files)
    exit 0
}

Say "watcher up. godot: $Godot"
Say "watching $($watchDirs -join ', ') for source changes; import sidecars ignored"
Say "hold reloads at any time by creating: $holdFile"

$game       = StartGame
$stamp      = (Fingerprint).Stamp
$pendingAt  = $null      # when the current change was first noticed
$lastReload = Get-Date
$crashes    = 0

while ($true) {
    Start-Sleep -Seconds 2

    # --- did the window go away on its own? ---------------------------------
    if ($game.Proc -and $game.Proc.HasExited) {
        $alive = ((Get-Date) - $game.At).TotalSeconds
        if ($alive -lt 15) {
            $crashes++
            Say "game exited after only $([int]$alive)s - treating as a crash (#$crashes)"
            Feed "The game closed on its own after $([int]$alive) seconds.`nRelaunching. If this repeats, the last change broke the boot."
            if ($crashes -ge 5) {
                Say "five quick crashes in a row - stopping rather than hiding it in a restart loop"
                Feed "The game crashed five times in a row on start.`nThe watcher has stopped. The last change needs fixing."
                break
            }
            Start-Sleep -Seconds 3
            $game = StartGame
            continue
        }
        # It ran for a while and then closed. Assume that was deliberate. Do NOT
        # exit - the first version did, which is why the window never came back.
        Say "window closed after $([int]$alive)s; assuming on purpose. Waiting for the next change."
        $game = @{ Proc = $null; At = Get-Date }
    }
    else {
        $crashes = 0
    }

    # --- is somebody mid-rebuild? -------------------------------------------
    # A hold that nobody lifted. A tool can die mid-run, and a permanent hold
    # would look exactly like a watcher that has stopped working.
    if (Test-Path $holdFile) {
        $age = ((Get-Date) - (Get-Item $holdFile).LastWriteTime).TotalMinutes
        if ($age -gt 15) {
            Say "ignoring a stale hold ($([int]$age) minutes old) - whatever set it is gone"
            Remove-Item $holdFile -Force
        }
    }
    if (Test-Path $holdFile) {
        if (-not $saidHold) {
            $why = (Get-Content $holdFile -Raw)
            if ($why) { $why = $why.Trim() }
            if (-not $why) { $why = "a rebuild is running" }
            Say "reloads held: $why"
            Feed "Working: $why`nThis window stays up until it is done."
            $saidHold = $true
        }
        # Swallow the churn while held, so lifting the hold does not fire one
        # reload per file that was rewritten.
        $stamp = (Fingerprint).Stamp
        $pendingAt = $null
        continue
    }
    elseif ($saidHold) {
        # A rebuild just finished, so there IS something new to show. Start the
        # settle clock rather than swallowing it - swallowing left the window
        # playing the OLD asset with no way to ever pick up the new one, which is
        # the opposite of the point.
        Say "hold lifted; will reload once things are quiet"
        $saidHold = $false
        $stamp = (Fingerprint).Stamp
        $pendingAt = Get-Date
    }

    # --- has anything changed, and has it stopped changing? -----------------
    $fp = Fingerprint
    if ($fp.Fresh -gt 0) {
        # Something is being written right now. Not settled, whatever the stamp
        # says.
        if (-not $pendingAt) {
            Say "$($fp.Fresh) file(s) being written; waiting"
            Feed "A change is landing.`nThe window reloads once everything has settled."
        }
        $pendingAt = Get-Date
        continue
    }
    if ($fp.Stamp -ne $stamp) {
        if (-not $pendingAt) {
            Say "change seen; waiting for it to settle"
            Feed "A change is landing.`nThe window reloads once everything has settled."
        }
        $pendingAt = Get-Date
        $stamp = $fp.Stamp
        continue
    }

    if ($pendingAt) {
        $settled = ((Get-Date) - $pendingAt).TotalSeconds
        $sinceReload = ((Get-Date) - $lastReload).TotalSeconds
        if ($settled -ge $QuietSeconds -and $sinceReload -ge $CooldownSeconds) {
            $pendingAt = $null
            $lastReload = Get-Date
            if ($game.Proc -and -not $game.Proc.HasExited) {
                Stop-Process -Id $game.Proc.Id -Force
                Start-Sleep -Milliseconds 500
            }
            Feed "Reloading with the latest change."
            $game = StartGame
        }
    }
}
