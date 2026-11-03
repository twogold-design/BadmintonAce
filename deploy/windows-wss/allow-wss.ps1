$ErrorActionPreference = 'Stop'
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run allow-wss.cmd as administrator on the CLOUD SERVER.'
}
$gatewayExe = Join-Path $PSScriptRoot 'caddy.exe'
if (-not (Test-Path -LiteralPath $gatewayExe -PathType Leaf)) { throw 'Missing caddy.exe.' }
$ruleName = 'Badminton Ace WSS TCP 80 443'
$rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if ($rule) {
    $rule | Set-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -Protocol TCP -LocalPort 80,443 -RemoteAddress Any -Program $gatewayExe -Profile Any
} else {
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort 80,443 -RemoteAddress Any -Program $gatewayExe -Profile Any | Out-Null
}
Write-Output 'Ready: Caddy TCP 80/443 allowed. Also configure Alibaba Cloud security group.'
Write-Output 'No other firewall rules changed. After WSS works, remove public TCP 8766 access.'
