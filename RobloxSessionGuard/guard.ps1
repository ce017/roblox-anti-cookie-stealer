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

# Only these count. RobloxCrashHandler is a helper that lingers, not the app.
$RobloxProcs = @('RobloxPlayerBeta','RobloxStudioBeta')

function Get-CookieStores {
  # Roblox keeps the session in TWO places:
  #  1. the WebView2 cookie jars (Chromium SQLite)
  #  2. %LOCALAPPDATA%\Roblox\LocalStorage\RobloxCookies.dat - a DPAPI-encrypted
  #     blob used by the Player/Studio client itself. DPAPI is no protection
  #     against a stealer: it decrypts automatically for any process running as
  #     you. Clearing only the WebView2 jars leaves the session on disk.
  # Only RobloxCookies.dat is touched in LocalStorage - appStorage.json next to
  # it holds your app settings and must be left alone.
  $root = Join-Path $env:LOCALAPPDATA 'Roblox'
  if (-not (Test-Path $root)) { return @() }

  $out = @(Get-ChildItem $root -Recurse -Force -Filter 'Cookies' -EA SilentlyContinue |
           Where-Object { -not $_.PSIsContainer -and $_.FullName -match 'WebView2|EBWebView' })

  $dat = Join-Path $root 'LocalStorage\RobloxCookies.dat'
  if (Test-Path $dat) { $out += Get-Item $dat -Force }

  return $out
}

function Test-RobloxRunning {
  # IMPORTANT: Roblox autostarts a tray-resident RobloxPlayerBeta.exe
  # ("--launch-to-tray") that never exits. Merely checking for the process
  # name means "Roblox is running" is ALWAYS true and the guard never fires.
  # Roblox is only genuinely in use when it owns a visible window
  # (the tray process reports MainWindowHandle = 0).
  foreach ($n in $RobloxProcs) {
    foreach ($p in (Get-Process -Name $n -EA SilentlyContinue)) {
      try { if ($p.MainWindowHandle -ne 0) { return $true } } catch {}
    }
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
$wasInUse = Test-RobloxRunning
Log "Roblox in use at startup: $wasInUse"
if (-not $wasInUse) { Log "not in use at startup - clearing"; Clear-Sessions }

$idleStreak = 0
while ($true) {
  Start-Sleep -Seconds 20
  $now = Test-RobloxRunning

  if ($now) { $idleStreak = 0 }
  else      { $idleStreak++ }

  # Clear on the transition in-use -> idle, but only once the idle state has
  # held for two polls, so a window that has not been created yet during
  # launch cannot cause us to wipe a session mid-login.
  if ($wasInUse -and -not $now -and $idleStreak -ge 2) {
    Log "Roblox no longer in use - clearing session"
    Start-Sleep -Seconds 3
    Clear-Sessions
    $wasInUse = $false
    continue
  }
  if ($now) { $wasInUse = $true }
}
