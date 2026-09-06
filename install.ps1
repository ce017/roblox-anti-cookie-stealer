<#  Installs StealerCanary and RobloxSessionGuard as per-user scheduled tasks.
    No admin required. Nothing is downloaded. Read the two .ps1 files first -
    that is the entire point of shipping this as source rather than an .exe.

    Usage:   powershell -ExecutionPolicy Bypass -File install.ps1
             powershell -ExecutionPolicy Bypass -File install.ps1 -CanaryOnly
             powershell -ExecutionPolicy Bypass -File install.ps1 -GuardOnly  #>
param([switch]$CanaryOnly, [switch]$GuardOnly)

$ErrorActionPreference = 'Stop'
$src  = Split-Path -Parent $MyInvocation.MyCommand.Path
$dest = Join-Path $env:LOCALAPPDATA 'RobloxAntiCookieStealer'
$user = "$env:USERDOMAIN\$env:USERNAME"

Write-Host "Installing to $dest" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path "$dest\StealerCanary","$dest\RobloxSessionGuard" | Out-Null
Copy-Item "$src\StealerCanary\canary.ps1"      "$dest\StealerCanary\canary.ps1"      -Force
Copy-Item "$src\RobloxSessionGuard\guard.ps1"  "$dest\RobloxSessionGuard\guard.ps1"  -Force

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 `
            -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable -MultipleInstances IgnoreNew
# Interactive is required: a task running in session 0 cannot display any alert.
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $user

function Install-Task($name,$script) {
  # stop any previous copy so we don't end up with duplicate watchers
  Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -match [regex]::Escape($script) } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

  $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
  Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger `
                         -Principal $principal -Settings $settings | Out-Null
  Start-ScheduledTask -TaskName $name
  Write-Host "  [+] $name installed and started" -ForegroundColor Green
}

if (-not $GuardOnly)  { Install-Task 'StealerCanary'      "$dest\StealerCanary\canary.ps1" }
if (-not $CanaryOnly) { Install-Task 'RobloxSessionGuard' "$dest\RobloxSessionGuard\guard.ps1" }

Start-Sleep -Seconds 3
Write-Host "`nRunning:" -ForegroundColor Cyan
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -match 'canary\.ps1|guard\.ps1' } |
  ForEach-Object {
    $n = if ($_.CommandLine -match 'canary') { 'StealerCanary' } else { 'RobloxSessionGuard' }
    Write-Host "  $n (pid $($_.ProcessId))"
  }
Write-Host "`nLogs:" -ForegroundColor Cyan
Write-Host "  $env:LOCALAPPDATA\StealerCanary\canary.log"
Write-Host "  $env:LOCALAPPDATA\RobloxSessionGuard\guard.log"
Write-Host "`nActive response (process kill / shutdown) is OFF by default." -ForegroundColor Yellow
Write-Host "See the README before enabling it.`n" -ForegroundColor Yellow
