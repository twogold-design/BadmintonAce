$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $projectRoot 'BadmintonAce-Server.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw 'Missing server executable.' }
$admin = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator required. Right-click the LAN firewall launcher and select Run as administrator.' }
$ruleName = 'Badminton Ace LAN 8766'
$existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if ($existing) {
    $existing | Set-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -Profile Any -Protocol TCP -LocalPort 8766 -RemoteAddress Any -Program $exe
} else {
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8766 -RemoteAddress Any -Program $exe -Profile Any | Out-Null
}
Write-Output 'Ready: TCP 8766 for this server executable accepts any reachable source address. Firewall stays enabled.'
