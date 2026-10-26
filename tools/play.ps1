$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$env:APPDATA = Join-Path $projectRoot '.runtime\roaming'
$env:LOCALAPPDATA = Join-Path $projectRoot '.runtime\local'
$env:TEMP = Join-Path $projectRoot '.runtime\temp'
$env:TMP = $env:TEMP
$env:PORT = '8766'
$env:LAN_ONLY = '1'
New-Item -ItemType Directory -Force -Path $env:APPDATA,$env:LOCALAPPDATA,$env:TEMP,'artifacts' | Out-Null
$exe = Join-Path $projectRoot 'BadmintonAce-Server.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw 'Missing BadmintonAce-Server.exe. Extract the complete server package.' }
$running = $false
try { $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8766/health' -TimeoutSec 2; $running = $health.ok -and $health.app -eq 'badminton-ace' -and $health.version -eq 2 -and $health.lanOnly } catch {}
if (-not $running) {
    $proc = Start-Process -FilePath $exe -WorkingDirectory $projectRoot -WindowStyle Hidden -RedirectStandardOutput 'artifacts\lan-server.log' -RedirectStandardError 'artifacts\lan-server-error.log' -PassThru
    $proc.Id | Set-Content -LiteralPath '.runtime\lan-server.pid'
    for ($i=0;$i -lt 30;$i++) {
        Start-Sleep -Milliseconds 200
        try { $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8766/health' -TimeoutSec 1; if ($health.ok -and $health.app -eq 'badminton-ace' -and $health.version -eq 2 -and $health.lanOnly) { $running=$true; break } } catch {}
    }
    if (-not $running) { throw 'Server did not start. See artifacts/lan-server-error.log.' }
}
$browser = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
if (-not (Test-Path -LiteralPath $browser)) { $browser = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' }
$profilePath = Join-Path $projectRoot '.runtime\play-browser'
$cachePath = Join-Path $projectRoot '.runtime\browser-cache'
Start-Process -FilePath $browser -ArgumentList @(('--user-data-dir="' + $profilePath + '"'),('--disk-cache-dir="' + $cachePath + '"'),'--disable-crash-reporter','--disable-breakpad','--no-first-run','--app=http://127.0.0.1:8766')
Write-Output 'Game opened. Browser profile, cache, and server logs are stored inside the project.'
