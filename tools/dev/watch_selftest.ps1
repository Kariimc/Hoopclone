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
function Launches { (Select-String -Path $log -Pattern "started game" -AllMatches).Count }
function LastPid {
    $m = (Select-String -Path $log -Pattern "started game, pid (\d+)" -AllMatches).Matches
    [int]$m[$m.Count-1].Groups[1].Value
}

$w = Start-Process powershell -ArgumentList '-NoProfile','-File',
     "$proj\tools\dev\watch.ps1",'-QuietSeconds','8','-CooldownSeconds','2' -PassThru
Start-Sleep -Seconds 9
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
