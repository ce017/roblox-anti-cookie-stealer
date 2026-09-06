<#  Removes both scheduled tasks, stops the watchers and deletes installed files.
    Logs and captured evidence are kept unless you pass -Purge. #>
param([switch]$Purge)

foreach ($t in 'StealerCanary','RobloxSessionGuard') {
  Stop-ScheduledTask     -TaskName $t -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
  Write-Host "[-] $t removed"
}
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -match 'canary\.ps1|guard\.ps1' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Remove-Item (Join-Path $env:LOCALAPPDATA 'RobloxAntiCookieStealer') -Recurse -Force -ErrorAction SilentlyContinue
if ($Purge) {
  Remove-Item "$env:LOCALAPPDATA\StealerCanary","$env:LOCALAPPDATA\RobloxSessionGuard" -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host "[-] logs and evidence purged"
} else {
  Write-Host "[i] logs/evidence kept in %LOCALAPPDATA%\StealerCanary and \RobloxSessionGuard"
}
# cancel a pending shutdown if one was armed
& shutdown.exe /a 2>$null | Out-Null
Write-Host "Uninstalled."
