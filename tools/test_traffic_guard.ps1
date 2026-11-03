param([switch]$JobOwner, [string]$PidFile)
. (Join-Path $PSScriptRoot 'environment.ps1')
. (Join-Path $projectRoot 'deploy/windows-wss/traffic-core.ps1')
. (Join-Path $projectRoot 'deploy/windows-wss/process-job.ps1')
$node = Resolve-AceTool 'ACE_NODE' @('node') 'D:\tools\nodejs2\node.exe'
if ($JobOwner) {
    $job = New-Object AceProcessJob
    $child = Start-Process $node -ArgumentList '-e "setInterval(()=>{},1000)"' -WindowStyle Hidden -PassThru
    $job.Add($child)
    [IO.File]::WriteAllText($PidFile,[string]$child.Id)
    Start-Sleep -Seconds 40
    exit
}
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$limits = Get-Content (Join-Path $projectRoot 'deploy/windows-wss/traffic-limits.json') -Raw | ConvertFrom-Json
$checks = 0
function Check($Condition,[string]$Message) {
    if (-not $Condition) { throw $Message }; $script:checks++
}
function Must-Throw([scriptblock]$Action) {
    $threw = $false; try { & $Action | Out-Null } catch { $threw = $true }
    Check $threw 'Expected fail-closed exception.'
}
function Baseline {
    $s = New-TrafficState
    $null = Update-TrafficState $s @{nic=0} 12000 $limits
    return $s
}
$s = Baseline
$r = Update-TrafficState $s @{nic=999999999} 12001 $limits
Check (-not $s.stopped) 'Must permit less than hourly limit.'
$r = Update-TrafficState $s @{nic=1000000000} 12002 $limits
Check $s.stopped 'Exactly 1 GB must latch.'
Check ($r.hourBytes -eq 1000000000) 'Decimal GB accounting.'
$null = Update-TrafficState $s @{nic=1000000000} 20000 $limits
Check $s.stopped 'Latch must not automatically clear.'
$s = Baseline
for ($i=1;$i -le 29;$i++) { $r = Update-TrafficState $s @{nic=750000*$i} (12000+$i) $limits }
Check (-not $s.stopped -and $r.rateMbps -eq 6) '29 seconds at 6 Mbps must not stop.'
$r = Update-TrafficState $s @{nic=750000*30} 12030 $limits
Check $s.stopped '30 seconds at 6 Mbps must stop.'
$s = Baseline
for ($i=1;$i -le 40;$i++) { $null = Update-TrafficState $s @{nic=625000*$i} (12000+$i) $limits }
Check (-not $s.stopped) 'Exactly 5 Mbps is not above threshold.'
$s = Baseline
$null = Update-TrafficState $s @{nic=750000} 12001 $limits
$null = Update-TrafficState $s @{nic=750000} 12002 $limits
Check ($s.highSeconds -eq 0) 'Low sample resets continuous streak.'
$null = Update-TrafficState $s @{nic=75000000} 12040 $limits
Check ($s.highSeconds -eq 0) 'Unobserved gap must not count as continuous.'
$s = Baseline
$null = Update-TrafficState $s @{nic=500000000} 12059 $limits
$r = Update-TrafficState $s @{nic=500000000} 15659 $limits
Check ($r.hourBytes -eq 500000000) 'Keep partial boundary minute conservatively.'
$r = Update-TrafficState $s @{nic=500000000} 15660 $limits
Check ($r.hourBytes -eq 0) 'Expire bucket after full hour plus boundary minute.'
Must-Throw { Update-TrafficState $s @{nic=1} 15661 $limits }
Must-Throw { Update-TrafficState $s @{other=500000000} 15661 $limits }
Must-Throw { Update-TrafficState $s @{} 15661 $limits }
Must-Throw { Update-TrafficState $s @{nic=500000000} 15000 $limits }
$s = Baseline
$null = Update-TrafficState $s @{nic=600000000} 12001 $limits
$testDir = Join-Path $projectRoot ('.runtime/traffic-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $testDir | Out-Null
$file = Join-Path $testDir 'state.json'
Save-TrafficState $s $file
Save-TrafficState $s $file
$s = Read-TrafficState $file
$r = Update-TrafficState $s @{nic=1000000000} 12002 $limits
Check $s.stopped 'Persisted budget must survive restarting monitor.'
Save-TrafficState $s $file
$s = Read-TrafficState $file
Check $s.stopped 'Stop latch survives disk roundtrip.'
$s.stopped=$false; $s.reason=''; $s.previous=@{}; $s.lastUtc=0
$null = Update-TrafficState $s @{nic=0} 12003 $limits
Check $s.stopped 'Manual resume does not erase hourly usage.'
foreach ($bad in @('{}','{"version":1,"previous":{},"buckets":[],"stopped":"false","lastUtc":0}', '{"version":1,"previous":{"nic":1},"buckets":[{"minute":200,"bytes":"NaN"}],"stopped":false,"lastUtc":12001}')) {
    [IO.File]::WriteAllText($file,$bad)
    Must-Throw { Read-TrafficState $file }
}
$empty = New-TrafficState
Save-TrafficState $empty $file
$roundtrip = Read-TrafficState $file
Check ($roundtrip.buckets.Count -eq 0 -and $roundtrip.previous.Count -eq 0) 'Empty state is valid.'
$job=$null; $owned=$null; $unrelated=$null; $owner=$null; $orphanId=0
try {
    $unrelated = Start-Process $node -ArgumentList '-e "setInterval(()=>{},1000)"' -WindowStyle Hidden -PassThru
    $owned = Start-Process $node -ArgumentList '-e "setInterval(()=>{},1000)"' -WindowStyle Hidden -PassThru
    $job = New-Object AceProcessJob
    $job.Add($owned); $job.Dispose(); $job=$null
    Check ($owned.WaitForExit(3000)) 'Closing job must stop owned process.'
    Check (-not $unrelated.HasExited) 'Unrelated processes must remain alive.'
    $pidPath = Join-Path $testDir 'owned-pid.txt'
    $owner = Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -JobOwner -PidFile "{1}"' -f $PSCommandPath,$pidPath) -WindowStyle Hidden -PassThru
    for ($i=0;$i -lt 100 -and -not (Test-Path $pidPath);$i++) { Start-Sleep -Milliseconds 100 }
    Check (Test-Path $pidPath) 'Job owner must initialize.'
    $orphanId = [int](Get-Content $pidPath)
    $owner.Kill(); $null=$owner.WaitForExit(3000)
    Start-Sleep -Milliseconds 300
    Check ($null -eq (Get-Process -Id $orphanId -ErrorAction SilentlyContinue)) 'Forced monitor termination must stop its owned child.'
    Check (-not $unrelated.HasExited) 'Forced termination must spare unrelated child.'
} finally {
    if ($null -ne $job) { $job.Dispose() }
    foreach ($p in @($owned,$unrelated,$owner)) { if ($null -ne $p -and -not $p.HasExited) { $p.Kill() } }
    if ($orphanId) { $p=Get-Process -Id $orphanId -ErrorAction SilentlyContinue; if ($p) { $p.Kill() } }
}
Write-Host "PASS: $checks traffic accounting, persistence and process ownership assertions."
