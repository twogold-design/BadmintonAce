# Real launcher, real packaged backend, simulated counters and gateway.
# No changes to firewall, public services, ports 80/443/8766, or player data.
. (Join-Path $PSScriptRoot 'environment.ps1')
$ErrorActionPreference = 'Stop'
$testRoot = Join-Path $projectRoot ('.runtime/supervisor-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot,(Join-Path $testRoot 'wss-state'),(Join-Path $testRoot 'player-data') | Out-Null
Copy-Item (Join-Path $projectRoot 'deploy/windows-wss/*.ps1') $testRoot
Copy-Item (Join-Path $projectRoot 'deploy/windows-wss/traffic-limits.json') $testRoot
Copy-Item (Join-Path $projectRoot 'deploy/windows-wss/Caddyfile') $testRoot
# Marker files satisfy existence checks; the process shim selects actual tools.
New-Item -ItemType File -Path (Join-Path $testRoot 'BadmintonAce-Server.exe'),(Join-Path $testRoot 'caddy.exe') | Out-Null
@{dataDirectory=(Join-Path $testRoot 'player-data')} | ConvertTo-Json | Set-Content (Join-Path $testRoot 'wss-state/guard-settings.json')
$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0)
$listener.Start(); $global:aceGuardTest_testPort=$listener.LocalEndpoint.Port; $listener.Stop()
$global:aceGuardTest_sample = 0; $global:aceGuardTest_children = @(); $global:aceGuardTest_launches=0
$global:aceGuardTest_testNode = 'D:\tools\nodejs2\node.exe'
$global:aceGuardTest_testBackend = Join-Path $projectRoot 'build/server/BadmintonAce-Server.exe'
function Get-NetIPConfiguration { [pscustomobject]@{IPv4DefaultGateway='test';InterfaceIndex=1} }
function Get-NetAdapter { param($Name,$ErrorAction) [pscustomobject]@{Name='Test';Status='Up';ifIndex=1;InterfaceGuid='test-nic'} }
function Get-NetAdapterStatistics {
    param($Name,$ErrorAction)
    $global:aceGuardTest_sample++
    [pscustomobject]@{SentBytes=$(if ($global:aceGuardTest_sample -eq 1) {0} else {1000000000})}
}
function Get-NetTCPConnection { param($State,$ErrorAction) @() }
function Invoke-RestMethod {
    param($Uri,$TimeoutSec)
    Microsoft.PowerShell.Utility\Invoke-RestMethod -Uri "http://127.0.0.1:$global:aceGuardTest_testPort/health" -TimeoutSec $TimeoutSec
}
function Start-Process {
    param($FilePath,$WorkingDirectory,$WindowStyle,[switch]$PassThru,$RedirectStandardOutput,$RedirectStandardError,$ArgumentList)
    $global:aceGuardTest_launches++
    if ($FilePath.EndsWith('BadmintonAce-Server.exe')) {
        $env:PORT=[string]$global:aceGuardTest_testPort
        $child=Microsoft.PowerShell.Management\Start-Process -FilePath $global:aceGuardTest_testBackend -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -PassThru -RedirectStandardOutput $RedirectStandardOutput -RedirectStandardError $RedirectStandardError
    } else {
        $child=Microsoft.PowerShell.Management\Start-Process -FilePath $global:aceGuardTest_testNode -ArgumentList '-e "setInterval(()=>{},1000)"' -WindowStyle Hidden -PassThru -RedirectStandardOutput $RedirectStandardOutput -RedirectStandardError $RedirectStandardError
    }
    $global:aceGuardTest_children += $child
    return $child
}
try {
    & (Join-Path $testRoot 'start-protected.ps1')
    $state=Get-Content (Join-Path $testRoot 'wss-state/traffic-state.json') -Raw | ConvertFrom-Json
    if (-not $state.stopped -or $state.reason -notlike 'Hourly*') { throw 'Supervisor did not persist hourly stop.' }
    if ($global:aceGuardTest_launches -ne 2) { throw 'Supervisor did not start both services.' }
    foreach ($child in $global:aceGuardTest_children) { if (-not $child.HasExited) { throw 'Owned service survived protection stop.' } }
    $log=Get-Content (Join-Path $testRoot 'wss-state/logs/backend-out.log') -Raw
    if ($log -notlike '*Local traffic supervisor requested shutdown*') { throw 'Backend was not stopped gracefully.' }
    & (Join-Path $testRoot 'start-protected.ps1')
    if ($global:aceGuardTest_launches -ne 2) { throw 'Latched launcher restarted services.' }
    Write-Host 'PASS: protected launcher starts both, stops both on simulated 1 GB, requests graceful stop and refuses automatic restart.'
} finally {
    foreach ($child in $global:aceGuardTest_children) { if (-not $child.HasExited) { $child.Kill() } }
}
