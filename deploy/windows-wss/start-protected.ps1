param([switch]$Resume, [switch]$NoCompression)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
Set-Location -LiteralPath $PSScriptRoot
$runtime = Join-Path $PSScriptRoot 'wss-state'
foreach ($folder in @('','temp','roaming','local','data','config','logs')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $runtime $folder) | Out-Null
}
$env:TEMP = Join-Path $runtime 'temp'; $env:TMP = $env:TEMP
$env:APPDATA = Join-Path $runtime 'roaming'; $env:LOCALAPPDATA = Join-Path $runtime 'local'
$env:XDG_DATA_HOME = Join-Path $runtime 'data'; $env:XDG_CONFIG_HOME = Join-Path $runtime 'config'
. (Join-Path $PSScriptRoot 'traffic-core.ps1')
. (Join-Path $PSScriptRoot 'process-job.ps1')
$statePath = Join-Path $runtime 'traffic-state.json'
$logPath = Join-Path $runtime 'logs\traffic-guard.log'
$settingsPath = Join-Path $runtime 'guard-settings.json'
$backend = $null; $gateway = $null; $job = $null; $lock = $null; $state = $null
$requestFile = Join-Path $runtime ('stop-' + [guid]::NewGuid().ToString('N') + '.request')
$started = $false
function Write-GuardLog([string]$Text) {
    $line = [DateTimeOffset]::Now.ToString('yyyy-MM-dd HH:mm:ss zzz') + ' ' + $Text
    Write-Host $line
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}
function Get-Counters($Names) {
    $counters = @{}
    foreach ($name in $Names) {
        $adapter = Get-NetAdapter -Name $name -ErrorAction Stop
        if ($adapter.Status -ne 'Up') { throw "Monitored adapter is not Up: $name" }
        $stats = Get-NetAdapterStatistics -Name $name -ErrorAction Stop
        $counters[[string]$adapter.InterfaceGuid] = [double]$stats.SentBytes
    }
    return $counters
}
function Get-Now { return [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000.0 }
function Stop-OwnedServices {
    # Tell the backend first, so in-progress games are not treated as forfeits.
    if ($null -ne $backend -and -not $backend.HasExited) {
        [IO.File]::WriteAllText($requestFile,'Local protected launcher requested shutdown.')
        if (-not $backend.WaitForExit(3500)) { $backend.Kill(); $backend.WaitForExit(1500) | Out-Null }
    }
    if ($null -ne $gateway -and -not $gateway.HasExited) { $gateway.Kill(); $gateway.WaitForExit(1500) | Out-Null }
}
try {
    # The exclusive handle protects history from a second monitor in this folder.
    $lock = [IO.File]::Open((Join-Path $runtime 'monitor.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $limits = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'traffic-limits.json') -Raw | ConvertFrom-Json
    Assert-TrafficLimits $limits
    $state = Read-TrafficState $statePath
    if ($state.stopped) {
        if (-not $Resume) { throw ('PROTECTION LATCHED: ' + $state.reason + ' Use resume-protected.cmd after investigating.') }
        Write-Host ('Previous stop: ' + $state.reason)
        Write-Host 'Hourly usage will NOT be cleared. Investigate abnormal traffic before resuming.'
        if ((Read-Host 'Type START to resume') -cne 'START') { throw 'Resume cancelled.' }
        $state.stopped = $false; $state.reason = ''; $state.highSeconds = 0.0
        # A manual recovery may follow a reboot or NIC counter reset.
        $state.previous = @{}; $state.lastUtc = 0.0
    }
    $names = @($limits.adapterNames)
    if ($names.Count -eq 0) {
        $indices = @(Get-NetIPConfiguration | Where-Object { $null -ne $_.IPv4DefaultGateway } | ForEach-Object { $_.InterfaceIndex })
        $names = @(Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $indices -contains $_.ifIndex } | ForEach-Object { $_.Name })
    }
    if ($names.Count -eq 0) { throw 'No active default-route adapter. Set adapterNames in traffic-limits.json.' }
    try {
        $reading = Update-TrafficState $state (Get-Counters $names) (Get-Now) $limits
    } catch {
        $state.stopped = $true; $state.reason = $_.Exception.Message
        Save-TrafficState $state $statePath
        throw
    }
    Save-TrafficState $state $statePath
    if ($reading.reason) { throw $reading.reason }
    $serverExe = Join-Path $PSScriptRoot 'BadmintonAce-Server.exe'
    $caddyExe = Join-Path $PSScriptRoot 'caddy.exe'
    foreach ($file in @($serverExe,$caddyExe,(Join-Path $PSScriptRoot 'Caddyfile'))) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing package file: $file" }
    }
    # Never take over or kill another launcher, IIS, or an existing game server.
    $listeners = @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object { $_.LocalPort -in @(80,443,8766) })
    if ($listeners.Count) { throw 'Port 80, 443 or 8766 is already used. Close the old game/WSS windows yourself before starting this launcher.' }
    if (Test-Path -LiteralPath $settingsPath) {
        $dataDirectory = [string](Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json).dataDirectory
        if (-not [IO.Path]::IsPathRooted($dataDirectory) -or -not (Test-Path -LiteralPath $dataDirectory -PathType Container)) { throw 'Saved data directory is unavailable; refusing to start with an empty leaderboard.' }
    } else {
        Write-Host 'Select your PREVIOUS BadmintonAce-Server.exe to preserve its adjacent data folder.'
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = 'Select previous server EXE (keep existing accounts and rankings)'
        $dialog.Filter = 'Badminton server|BadmintonAce-Server.exe|Executable|*.exe'
        $dialog.InitialDirectory = $PSScriptRoot
        try {
            if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { throw 'Data location selection cancelled.' }
            $dataDirectory = Join-Path (Split-Path -Parent $dialog.FileName) 'data'
        } finally { $dialog.Dispose() }
        New-Item -ItemType Directory -Force -Path $dataDirectory | Out-Null
        @{ dataDirectory = $dataDirectory } | ConvertTo-Json | Set-Content -LiteralPath $settingsPath -Encoding UTF8
    }
    $env:DATA_DIR = $dataDirectory
    if ($NoCompression) { $env:ACE_WS_COMPRESSION = '0' }
    $env:PORT = '8766'; $env:SERVE_WEB = '0'; $env:LAN_ONLY = '0'; $env:TRUST_PROXY = '0'
    $env:ACE_STOP_REQUEST = $requestFile
    $job = New-Object AceProcessJob
    $backend = Start-Process -FilePath $serverExe -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtime 'logs\backend-out.log') -RedirectStandardError (Join-Path $runtime 'logs\backend-error.log')
    $job.Add($backend)
    $started = $true
    $ready = $false
    for ($attempt=0; $attempt -lt 30; $attempt++) {
        if ($backend.HasExited) { throw 'Backend exited during startup. See wss-state/logs/backend-error.log.' }
        try {
            $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8766/health' -TimeoutSec 1
            if ($health.ok -and $health.trafficGuardControl) { $ready = $true; break }
        } catch { }
        Start-Sleep -Milliseconds 200
    }
    if (-not $ready) { throw 'Backend does not support controlled shutdown. Use the EXE bundled with this protected package.' }
    $gateway = Start-Process -FilePath $caddyExe -ArgumentList 'run --config Caddyfile --adapter caddyfile' -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtime 'logs\caddy-out.log') -RedirectStandardError (Join-Path $runtime 'logs\caddy-error.log')
    $job.Add($gateway)
    Write-GuardLog ('STARTED: hourly limit {0} GB; >{1} Mbps for {2}s; adapters: {3}' -f $limits.hourlyOutboundGB,$limits.sustainedOutboundMbps,$limits.sustainedSeconds,($names -join ', '))
    Write-Host 'Keep this monitor open. Closing it also stops both managed services.'
    Write-Host 'Traffic is checked every second; routine status is shown every 5 minutes.'
    Write-Host 'Counters include other outbound traffic on these adapters, including Remote Desktop.'
    Write-Host ('Player database directory: ' + $dataDirectory)
    $lastDisplay = 0.0
    while ($true) {
        if ($backend.HasExited -or $gateway.HasExited) { throw 'A managed service exited. Both services will be stopped; check logs.' }
        Start-Sleep -Milliseconds ([int]([double]$limits.pollSeconds * 1000))
        $now = Get-Now
        $reading = Update-TrafficState $state (Get-Counters $names) $now $limits
        Save-TrafficState $state $statePath
        if ($reading.reason) {
            Write-GuardLog ('AUTO STOP: ' + $reading.reason)
            Stop-OwnedServices
            Write-Host 'Game backend and WSS stopped. ECS remains running and billable. Manual resume required.'
            break
        }
        if ($now - $lastDisplay -ge 300) {
            Write-Host ('Outbound {0:N2} Mbps | Last ~hour {1:N3}/{2} GB | High-rate streak {3:N1}/{4}s' -f $reading.rateMbps,($reading.hourBytes/1000000000),$limits.hourlyOutboundGB,$state.highSeconds,$limits.sustainedSeconds)
            $lastDisplay = $now
        }
    }
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    # After we own a service, monitoring/persistence errors fail closed too.
    if ($started -and $null -ne $state) {
        $state.stopped = $true; $state.reason = $_.Exception.Message
        try { Save-TrafficState $state $statePath; Write-GuardLog ('STOP ON ERROR: ' + $state.reason) } catch { }
    }
    $global:LASTEXITCODE = 1
} finally {
    try { Stop-OwnedServices } finally {
        if ($null -ne $job) { $job.Dispose() }
        if ($null -ne $lock) { $lock.Dispose() }
    }
}
