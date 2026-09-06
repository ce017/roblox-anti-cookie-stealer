<#  RobloxSessionGuard - clears the Roblox WebView2 cookie stores whenever
    no Roblox process is running.

    Why: the Roblox app keeps .ROBLOSECURITY in its own embedded WebView2 jar,
    and nothing ever clears it. On 2026-09-05 a cookie created at 13:28 and
    valid until 2027 was still sitting there hours later, and was stolen.
    This applies LibreWolf's clear-on-close model to the Roblox app.

    Effect : the session token only exists while you are actually playing.
    Cost   : you sign in again each launch.  #>

$LogDir = "$env:LOCALAPPDATA\RobloxSessionGuard"
$Log    = "$LogDir\guard.log"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
function Log($m){ "$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')  $m" | Out-File $Log -Append -Encoding utf8 }

$RobloxProcs = @('RobloxPlayerBeta','RobloxStudioBeta','RobloxCrashHandler','Roblox')

function Get-CookieStores {
  $root = Join-Path $env:LOCALAPPDATA 'Roblox'
  if (-not (Test-Path $root)) { return @() }
  Get-ChildItem $root -Recurse -Force -Filter 'Cookies' -EA SilentlyContinue |
    Where-Object { -not $_.PSIsContainer -and $_.FullName -match 'WebView2|EBWebView' }
}

function Test-RobloxRunning {
  foreach ($n in $RobloxProcs) {
    if (Get-Process -Name $n -EA SilentlyContinue) { return $true }
  }
  return $false
}

function Clear-Sessions {
  $stores = @(Get-CookieStores)
  if ($stores.Count -eq 0) { return }
  $cleared = 0
  foreach ($s in $stores) {
    try {
      # only act if the store actually holds a session token
      $sz = $s.Length
      Remove-Item $s.FullName -Force -EA Stop
      foreach ($ext in @('-journal','-wal','-shm')) {
        $x = $s.FullName + $ext
        if (Test-Path $x) { Remove-Item $x -Force -EA SilentlyContinue }
      }
      $cleared++
      Log "cleared ($sz bytes): $($s.FullName)"
    } catch { Log "could not clear $($s.FullName): $_" }
  }
  if ($cleared) { Log "=> $cleared Roblox cookie store(s) cleared" }
}

Log "guard started (pid $PID)"
$wasRunning = Test-RobloxRunning
if (-not $wasRunning) { Log "no Roblox running at startup - clearing"; Clear-Sessions }

while ($true) {
  Start-Sleep -Seconds 20
  $now = Test-RobloxRunning
  if ($wasRunning -and -not $now) {
    Log "Roblox closed - clearing session"
    Start-Sleep -Seconds 3           # let it finish flushing to disk
    Clear-Sessions
  }
  $wasRunning = $now
}
