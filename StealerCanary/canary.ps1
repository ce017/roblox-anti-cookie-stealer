<#  StealerCanary - detects infostealer staging activity.
    Signature: a freshly-created random-hex directory that rapidly fills with
    copies of browser credential databases. Exactly what C:\ProgramData\fc88195fa9
    was on 2026-09-05.

    ALERTING IS MULTI-CHANNEL ON PURPOSE. A popup alone is not reliable:
      - exclusive-fullscreen games hide it
      - a task running in session 0 cannot draw any UI
      - paths containing an apostrophe break command-string interpolation
    So: sound + popup + desktop marker + log. Sound is the one that survives games.  #>


# ---------------- RESPONSE CONFIG ----------------
# $KillSuspects   : terminate likely-culprit processes immediately (fast, targeted)
# $ShutdownOnAlert: force shutdown as a backstop, after an abortable countdown
# Set $ShutdownOnAlert = $false if a false positive ever costs you unsaved work.
$KillSuspects    = $false
$ShutdownOnAlert = $false
$ShutdownDelaySec = 20
# -------------------------------------------------

$LogDir = "$env:LOCALAPPDATA\StealerCanary"
$Log    = "$LogDir\canary.log"
$EvDir  = "$LogDir\evidence"
New-Item -ItemType Directory -Force -Path $LogDir,$EvDir | Out-Null

$Roots  = @("C:\ProgramData", $env:TEMP, $env:LOCALAPPDATA, $env:APPDATA)
$HexPat = '^[0-9a-fA-F]{8,16}$'
$Seen   = @{}

function Log($m){ "$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')  $m" | Out-File $Log -Append -Encoding utf8 }

function Alert($dir,$why){
  $stamp = Get-Date -f 'yyyyMMdd_HHmmss'
  Log "*** ALERT *** $dir  ($why)"

  # 1. EVIDENCE FIRST - before anything can be cleaned up
  $ev = Join-Path $EvDir $stamp
  New-Item -ItemType Directory -Force -Path $ev | Out-Null
  try { Get-ChildItem $dir -Force -EA SilentlyContinue | Select-Object Name,Length,CreationTime |
          Out-File "$ev\listing.txt" -Encoding utf8 } catch {}
  try { Get-Process | Where-Object { $_.Path } | Select-Object Name,Id,Path,StartTime |
          Sort-Object StartTime -Descending | Out-File "$ev\processes.txt" -Encoding utf8 } catch {}
  "$dir`r`n$why`r`n$(Get-Date)" | Out-File "$ev\what.txt" -Encoding utf8

  # 1b. RESPOND - kill first (milliseconds), it is the only thing that beats an upload
  $culprits = Invoke-Response $dir $why

  # 2. SOUND - the only channel that reliably reaches you inside a fullscreen game
  try { 1..3 | ForEach-Object { [Console]::Beep(1200,250); [Console]::Beep(800,250) } } catch {}
  try { (New-Object Media.SoundPlayer "C:\Windows\Media\Windows Foreground.wav").PlaySync() } catch {}

  # 3. DESKTOP MARKER - persistent, survives a missed popup
  try {
    $mk = [Environment]::GetFolderPath('Desktop')
    "SECURITY ALERT $(Get-Date)`r`n`r`n$dir`r`n$why`r`n`r`nEvidence: $ev`r`nLog: $Log" |
      Out-File (Join-Path $mk "!! STEALER ALERT $stamp.txt") -Encoding utf8
  } catch {}

  # 4. POPUP - message passed as a variable, never string-interpolated into -Command
  try {
    $w = New-Object -ComObject WScript.Shell
    $null = $w.Popup("Possible infostealer activity`n`n$dir`n$why`n`nEvidence saved to:`n$ev", 30,
                     "StealerCanary - SECURITY ALERT", 48)
  } catch { Log "popup failed: $_" }

  Log "evidence -> $ev"

  if ($ShutdownOnAlert) {
    Log "initiating shutdown in ${ShutdownDelaySec}s (abort: shutdown /a)"
    try {
      & shutdown.exe /s /f /t $ShutdownDelaySec /c "StealerCanary: suspected cookie theft blocked. Shutting down to stop upload. Abort with: shutdown /a"
    } catch { Log "shutdown failed: $_" }
  }
}


function Get-Suspects {
  # Heuristic culprit: started recently, running from a user-writable location,
  # and NOT signed by Microsoft. Deliberately conservative to limit false kills.
  $cut = (Get-Date).AddSeconds(-180)
  $badPath = '\Downloads\|\Temp\|\ProgramData\|\Desktop\|\AppData\Local\Temp\'
  $out = @()
  foreach ($p in (Get-Process -EA SilentlyContinue | Where-Object { $_.Path })) {
    try {
      if ($p.Id -eq $PID) { continue }
      if ($p.StartTime -lt $cut) { continue }
      if ($p.Path -notmatch $badPath) { continue }
      $sig = Get-AuthenticodeSignature $p.Path -EA SilentlyContinue
      if ($sig -and $sig.Status -eq 'Valid' -and $sig.SignerCertificate.Subject -match 'Microsoft') { continue }
      $out += $p
    } catch {}
  }
  return $out
}

function Invoke-Response($dir,$why){
  $names = @()
  $suspects = @(Get-Suspects)
  foreach ($s in $suspects) { $names += ("{0} (pid {1}) -> {2}" -f $s.Name,$s.Id,$s.Path) }
  Log ("suspects: " + $(if($names){$names -join ' | '}else{'none identified'}))

  if ($KillSuspects -and $suspects.Count -gt 0) {
    foreach ($s in $suspects) {
      try { Stop-Process -Id $s.Id -Force -EA Stop; Log "KILLED $($s.Name) pid $($s.Id)" }
      catch { Log "kill failed $($s.Name): $_" }
    }
  }

  # Boot-time notice - the canary shows this next time it starts
  $pend = Join-Path $LogDir "pending_alert.txt"
  $body = @"
BLOCKED a suspected credential/cookie theft

When      : $(Get-Date -f 'yyyy-MM-dd HH:mm:ss')
Staging   : $dir
Detected  : $why

Program(s) responsible:
$(if($names){$names -join "`r`n"}else{'  <could not identify - check processes.txt in the evidence folder>'})

ACTION REQUIRED
  1. UNINSTALL the program(s) above immediately - do not run them again.
  2. Change passwords + sign out all sessions for any account you were
     logged into (Google and Roblox first).
  3. Evidence: $EvDir
"@
  $body | Out-File $pend -Encoding utf8
  return $names
}

function Show-PendingAlert {
  $pend = Join-Path $LogDir "pending_alert.txt"
  if (-not (Test-Path $pend)) { return }
  $txt = Get-Content $pend -Raw
  try { 1..4 | ForEach-Object { [Console]::Beep(1200,250); [Console]::Beep(800,250) } } catch {}
  try {
    $w = New-Object -ComObject WScript.Shell
    $null = $w.Popup($txt, 0, "StealerCanary - THEFT BLOCKED - ACTION REQUIRED", 16)
  } catch {}
  try { Start-Process notepad.exe $pend } catch {}
  $ack = Join-Path $LogDir ("acknowledged_" + (Get-Date -f 'yyyyMMdd_HHmmss') + ".txt")
  Move-Item $pend $ack -Force -EA SilentlyContinue
  Log "pending alert shown and acknowledged -> $ack"
}

function Get-FileSignals($path) {
  # All checks are CONTENT based, never filename based: staged copies are
  # routinely renamed to random hex with no extension (as in the 2026-09-05
  # incident), so extensions tell you nothing.
  $sig = @{ Sqlite=$false; LevelDb=$false; DiscordToken=$false; LocalState=$false }
  try {
    $fs = [IO.File]::OpenRead($path)
    try {
      $len = $fs.Length
      if ($len -lt 16) { return $sig }
      $head = New-Object byte[] ([Math]::Min(64,$len))
      $null = $fs.Read($head,0,$head.Length)
      if ($head.Length -ge 15 -and [Text.Encoding]::ASCII.GetString($head,0,15) -eq 'SQLite format 3') {
        $sig.Sqlite = $true
      }
      # LevelDB SSTable footer magic (0xdb4775248b80fb57 little-endian) at EOF
      if ($len -ge 48) {
        $null = $fs.Seek($len-48, 'Begin')
        $tail = New-Object byte[] 48
        $null = $fs.Read($tail,0,48)
        $magic = [byte[]](0x57,0xfb,0x80,0x8b,0x24,0x75,0x47,0xdb)
        for ($i=0; $i -le 40 -and -not $sig.LevelDb; $i++) {
          $m = $true
          for ($j=0; $j -lt 8; $j++) { if ($tail[$i+$j] -ne $magic[$j]) { $m=$false; break } }
          if ($m) { $sig.LevelDb = $true }
        }
      }
      # Only scan bodies that are plausibly credential stores, to stay fast
      if ($sig.LevelDb -or $len -lt 2MB) {
        $cap = [int][Math]::Min($len, 8MB)
        $null = $fs.Seek(0,'Begin')
        $body = New-Object byte[] $cap
        $null = $fs.Read($body,0,$cap)
        $txt = [Text.Encoding]::ASCII.GetString($body)
        if ($txt.Contains('dQw4w9WgXcQ:')) { $sig.DiscordToken = $true }
        if ($txt.Contains('os_crypt') -or $txt.Contains('encrypted_key')) { $sig.LocalState = $true }
      }
    } finally { $fs.Close() }
  } catch {}
  return $sig
}

function Inspect($dir){
  Start-Sleep -Milliseconds 1500
  $files = @(Get-ChildItem $dir -File -Force -EA SilentlyContinue)
  if ($files.Count -lt 3) { return }
  $sqlite=0; $leveldb=0; $token=0; $localstate=0
  foreach ($f in ($files | Select-Object -First 60)) {
    $s = Get-FileSignals $f.FullName
    if ($s.Sqlite)       { $sqlite++ }
    if ($s.LevelDb)      { $leveldb++ }
    if ($s.DiscordToken) { $token++ }
    if ($s.LocalState)   { $localstate++ }
  }
  $cred = $sqlite + $leveldb + $localstate
  if     ($token -ge 1)   { Alert $dir "$($files.Count) files - DISCORD SESSION TOKEN found in a staged copy ($token file(s))" }
  elseif ($sqlite -ge 2)  { Alert $dir "$($files.Count) files, $sqlite SQLite DBs (browser credential stores)" }
  elseif ($leveldb -ge 3) { Alert $dir "$($files.Count) files, $leveldb LevelDB segments (Discord / Chromium token stores)" }
  elseif ($cred -ge 3)    { Alert $dir "$($files.Count) files, $cred credential-store artifacts (sqlite=$sqlite leveldb=$leveldb localstate=$localstate)" }
  elseif ($files.Count -ge 40) { Alert $dir "$($files.Count) files created at once in a random-hex directory" }
}

Show-PendingAlert {
  $pend = Join-Path $LogDir "pending_alert.txt"
  if (-not (Test-Path $pend)) { return }
  $txt = Get-Content $pend -Raw
  try { 1..4 | ForEach-Object { [Console]::Beep(1200,250); [Console]::Beep(800,250) } } catch {}
  try {
    $w = New-Object -ComObject WScript.Shell
    $null = $w.Popup($txt, 0, "StealerCanary - THEFT BLOCKED - ACTION REQUIRED", 16)
  } catch {}
  try { Start-Process notepad.exe $pend } catch {}
  $ack = Join-Path $LogDir ("acknowledged_" + (Get-Date -f 'yyyyMMdd_HHmmss') + ".txt")
  Move-Item $pend $ack -Force -EA SilentlyContinue
  Log "pending alert shown and acknowledged -> $ack"
}

function Inspect($dir){
  Start-Sleep -Milliseconds 1500
  $files = @(Get-ChildItem $dir -File -Force -EA SilentlyContinue)
  if ($files.Count -lt 3) { return }
  $sqlite = 0
  foreach ($f in ($files | Select-Object -First 60)) {
    try {
      $fs = [IO.File]::OpenRead($f.FullName)
      $b = New-Object byte[] 15; $null = $fs.Read($b,0,15); $fs.Close()
      if ([Text.Encoding]::ASCII.GetString($b) -eq 'SQLite format 3') { $sqlite++ }
    } catch {}
  }
  if     ($sqlite -ge 2)      { Alert $dir "$($files.Count) files, $sqlite SQLite DBs (browser credential stores)" }
  elseif ($files.Count -ge 40){ Alert $dir "$($files.Count) files created at once in a random-hex directory" }
}

Show-PendingAlert
Log "canary started (pid $PID, session $((Get-Process -Id $PID).SessionId))"
foreach ($r in $Roots) {
  Get-ChildItem $r -Directory -Force -EA SilentlyContinue |
    Where-Object { $_.Name -match $HexPat } | ForEach-Object { $Seen[$_.FullName] = $true }
}
while ($true) {
  foreach ($r in $Roots) {
    Get-ChildItem $r -Directory -Force -EA SilentlyContinue |
      Where-Object { $_.Name -match $HexPat -and -not $Seen.ContainsKey($_.FullName) } |
      ForEach-Object { $Seen[$_.FullName] = $true; Log "new hex dir: $($_.FullName)"; Inspect $_.FullName }
  }
  Start-Sleep -Seconds 5
}
