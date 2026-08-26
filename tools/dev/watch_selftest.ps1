# Self-test for the dev watcher. Six checks, about ninety seconds, and it opens
# and closes a real game window while it runs.
#
#   powershell -NoProfile -File tools\dev\watch_selftest.ps1
#
# Every check here exists because the behaviour it covers was broken and cost the
# owner a working session:
#
#   1  it starts a window at all
#   2  a burst of edits reloads ONCE, at the end - not once per edit
#   3  a crash is relaunched, not mistaken for the owner closing the window
#   4  while .reload-hold exists, nothing reloads
#   5  a hold left behind by a dead tool goes stale and is ignored
#   6  when a hold lifts, the finished rebuild IS picked up
#
# Check 2 and check 6 both failed on the first pass of the rewrite, which is the
# reason this file exists rather than a paragraph promising it works.

$proj = "C:\Users\Kariim\Dev\hoopclone"
$log  = Join-Path $proj ".watch.log"
$hold = Join-Path $proj ".reload-hold"
Remove-Item $hold -Force -ErrorAction SilentlyContinue

# THE TEST WAS COUNTING A MONTH OF HISTORY, found 2026-08-25.
#
# Every count below reads the log, and the log was never cleared, so "launches at
# startup: 8 (want 1)" was seven old lines from July plus one new one. The number meant
# nothing and neither did the verdict on it. Worse: on the day the watcher failed to
# start at all, these checks still produced numbers off the stale file and read like
# results. A checker that answers confidently when the thing it checks never ran is worse
# than no checker.
#
# The log is moved aside before the run, so every count is of THIS run and nothing else.
# Moved, not deleted: the history is evidence.
if (Test-Path $log) { Move-Item $log "$log.before-selftest" -Force }
function Launches { if (Test-Path $log) { (Select-String -Path $log -Pattern "started game" -AllMatches).Count } else { 0 } }
function LastPid {
    $m = (Select-String -Path $log -Pattern "started game, pid (\d+)" -AllMatches).Matches
    [int]$m[$m.Count-1].Groups[1].Value
}

$w = Start-Process powershell -ArgumentList '-NoProfile','-File',
     "$proj\tools\dev\watch.ps1",'-QuietSeconds','8','-CooldownSeconds','2' -PassThru
Start-Sleep -Seconds 9

# TEST 0, ADDED 2026-08-25 AND IT IS THE ONE THAT MATTERED. The watcher had been dead for
# nearly a month because it could not find Godot and exited in its first second, and
# nothing here noticed, because the checks below only ever asked "how many launches" and
# the stale log always had an answer. This asks the only question that comes first: did
# the watcher get up at all.
$alive = -not $w.HasExited
$logged = Test-Path $log
Write-Host "TEST 0  watcher still running: $alive  wrote its log: $logged  (want True, True)"
if (-not $logged) {
    Write-Host "        it never started. Everything below would be measuring nothing, so stopping here."
    Write-Host "TEST done"
    exit 1
}

$a = Launches
Write-Host "TEST 1  launches at startup: $a  (want 1)"

# Six edits, one every two seconds. One reload, after they stop.
for ($i=0; $i -lt 6; $i++) {
    (Get-Item "$proj\game\main.gd").LastWriteTimeUtc = (Get-Date).ToUniversalTime()
    Start-Sleep -Seconds 2
}
Start-Sleep -Seconds 18
$b = Launches
Write-Host "TEST 2  launches after a 6-edit burst: $($b - $a)  (want 1)"

# A crash must come back.
Stop-Process -Id (LastPid) -Force
Start-Sleep -Seconds 10
$c = Launches
$crash = (Select-String -Path $log -Pattern "treating as a crash" -AllMatches).Count
Write-Host "TEST 3  crash seen: $crash  relaunched: $($c -gt $b)  (want 1, True)"

# Held: an edit must change nothing.
Set-Content $hold "pretending to rebuild"
Start-Sleep -Seconds 3
(Get-Item "$proj\game\main.gd").LastWriteTimeUtc = (Get-Date).ToUniversalTime()
Start-Sleep -Seconds 16
$d = Launches
Write-Host "TEST 4  launches while held: $($d - $c)  (want 0)"

# A stale hold must be ignored rather than freezing reloads for good.
(Get-Item $hold).LastWriteTime = (Get-Date).AddMinutes(-30)
Start-Sleep -Seconds 5
$stale = (Select-String -Path $log -Pattern "stale hold" -AllMatches).Count
Write-Host "TEST 5  stale hold ignored: $stale  (want 1)  hold file gone: $(-not (Test-Path $hold))"
Start-Sleep -Seconds 14
$e = Launches
Write-Host "TEST 6  reloaded once the hold cleared: $($e -gt $d)  (want True)"

Remove-Item $hold -Force -ErrorAction SilentlyContinue
Stop-Process -Id $w.Id -Force
Stop-Process -Id (LastPid) -Force -ErrorAction SilentlyContinue
Write-Host "TEST done"
