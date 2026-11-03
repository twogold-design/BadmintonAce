# Pure accounting helpers, also exercised with synthetic counters in tests.
function New-TrafficState {
    return @{ version = 1; buckets = @(); previous = @{}; lastUtc = 0.0; highSeconds = 0.0; stopped = $false; reason = '' }
}

function Assert-TrafficLimits($Limits) {
    foreach ($field in @('hourlyOutboundGB','sustainedOutboundMbps','sustainedSeconds','pollSeconds')) {
        $value = [double]$Limits.$field
        if ([double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -le 0) { throw "Invalid positive traffic limit: $field" }
    }
    if ($Limits.pollSeconds -gt 5 -or $Limits.sustainedSeconds -lt $Limits.pollSeconds) { throw 'Poll interval must be <=5 seconds and <= sustained duration.' }
}

function Update-TrafficState($State, $Counters, [double]$Now, $Limits) {
    Assert-TrafficLimits $Limits
    if ($State.stopped) { return @{ reason = $State.reason; rateMbps = 0.0; hourBytes = 0.0 } }
    if ($State.lastUtc -gt $Now + 2) { throw 'System clock moved backwards; monitoring stopped safely.' }
    $elapsed = $Now - [double]$State.lastUtc
    $bytes = 0.0
    foreach ($name in $Counters.Keys) {
        if ($State.previous.ContainsKey($name)) {
            $change = [double]$Counters[$name] - [double]$State.previous[$name]
            if ($change -lt 0) { throw "Network counter reset for $name; cannot safely continue accounting." }
            $bytes += $change
        } elseif ($State.previous.Count -gt 0) { throw "Network adapter changed: $name" }
    }
    if ($State.previous.Count -gt 0 -and $Counters.Count -ne $State.previous.Count) { throw 'Monitored network adapter disappeared.' }
    if ($Counters.Count -eq 0) { throw 'No usable network counters.' }
    $State.previous = @{}
    foreach ($name in $Counters.Keys) { $State.previous[$name] = [double]$Counters[$name] }
    # One-minute buckets conservatively retain the partial boundary minute:
    # this covers the last 60 to 61 minutes and never drops part of the hour.
    $minute = [math]::Floor($Now / 60)
    $State.buckets = @($State.buckets | Where-Object { [double]$_.minute -ge $minute - 60 })
    if ($bytes -gt 0) {
        if ($State.buckets.Count -gt 0 -and $State.buckets[-1].minute -eq $minute) { $State.buckets[-1].bytes += $bytes }
        else { $State.buckets += @{ minute = $minute; bytes = $bytes } }
    }
    $sum = 0.0
    foreach ($bucket in $State.buckets) { $sum += [double]$bucket.bytes }
    $rate = if ($elapsed -gt 0 -and $State.lastUtc -gt 0) { $bytes * 8 / $elapsed / 1000000 } else { 0.0 }
    # A long monitoring gap cannot establish continuously high traffic.
    if ($elapsed -gt 0 -and $elapsed -le [double]$Limits.pollSeconds * 3 -and $rate -gt [double]$Limits.sustainedOutboundMbps) { $State.highSeconds += $elapsed }
    else { $State.highSeconds = 0.0 }
    $State.lastUtc = $Now
    $reason = ''
    if ($sum -ge [double]$Limits.hourlyOutboundGB * 1000000000) { $reason = 'Hourly outbound traffic reached the configured GB limit.' }
    elseif ($State.highSeconds -ge [double]$Limits.sustainedSeconds) { $reason = 'Outbound rate exceeded the Mbps limit for the configured continuous duration.' }
    if ($reason) { $State.stopped = $true; $State.reason = $reason }
    return @{ reason = $reason; rateMbps = $rate; hourBytes = $sum }
}

function Save-TrafficState($State, [string]$File) {
    $temporary = $File + '.tmp'
    [IO.File]::WriteAllText($temporary,($State | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    if ([IO.File]::Exists($File)) { [IO.File]::Replace($temporary,$File,[NullString]::Value) }
    else { [IO.File]::Move($temporary,$File) }
}

function Read-TrafficState([string]$File) {
    if (-not (Test-Path -LiteralPath $File)) { return (New-TrafficState) }
    $raw = Get-Content -LiteralPath $File -Raw | ConvertFrom-Json
    if ($raw.version -ne 1 -or $raw.previous -isnot [pscustomobject] -or $raw.buckets -isnot [array] -or $raw.stopped -isnot [bool] -or $null -eq $raw.lastUtc) { throw 'Invalid saved traffic state; do not silently reset the traffic budget.' }
    $state = New-TrafficState
    $state.lastUtc = [double]$raw.lastUtc
    $state.stopped = [bool]$raw.stopped
    $state.reason = [string]$raw.reason
    if ([double]::IsNaN($state.lastUtc) -or [double]::IsInfinity($state.lastUtc) -or $state.lastUtc -lt 0) { throw 'Invalid saved timestamp.' }
    # Continuous-rate duration restarts with observation, hourly usage does not.
    foreach ($property in $raw.previous.PSObject.Properties) {
        $value = [double]$property.Value
        if ($null -eq $property.Value -or [double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -lt 0) { throw 'Invalid saved adapter counter.' }
        $state.previous[$property.Name] = $value
    }
    if ($state.lastUtc -gt 0 -and $state.previous.Count -eq 0) { throw 'Saved adapter counters are missing.' }
    $lastMinute = -1.0
    foreach ($bucket in $raw.buckets) {
        foreach ($field in @('bytes','minute')) {
            $value = [double]$bucket.$field
            if ($null -eq $bucket.$field -or [double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -lt 0) { throw 'Invalid traffic history.' }
        }
        if ($bucket.minute -le $lastMinute -or $bucket.minute -ne [math]::Floor($bucket.minute) -or $bucket.minute -gt [math]::Floor($state.lastUtc / 60)) { throw 'Invalid traffic bucket timestamp.' }
        $lastMinute = $bucket.minute
        $state.buckets += @{ minute = [double]$bucket.minute; bytes = [double]$bucket.bytes }
    }
    return $state
}
