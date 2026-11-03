# Rebuild when deployment inputs change; explicit invocation can force a release.
param([switch]$IfChanged)
. (Join-Path $PSScriptRoot 'environment.ps1')
$archive = Join-Path $projectRoot '.runtime/caddy-download/caddy.zip'
$expected = 'c308154504e53755958ffc62d8a2657ab17eefd6dd25c45dbb2c3d93d29519971f77ca652f7d0f2bcb7f980b9ba3822478865e29969d0272d7613550a43152b1'
if (-not (Test-Path $archive)) { throw 'Download caddy_2.11.7_windows_amd64.zip from the official GitHub release to .runtime/caddy-download/caddy.zip first.' }
if ((Get-FileHash $archive -Algorithm SHA512).Hash.ToLowerInvariant() -ne $expected) { throw 'Official Caddy archive checksum mismatch.' }
$node = Resolve-AceTool 'NODE_BIN' @('node') 'D:\tools\nodejs2\node.exe'
. (Join-Path $PSScriptRoot 'server_release_inputs.ps1')
$inputFingerprint = Get-AceServerReleaseFingerprint $projectRoot $node
$releaseStatePath = Join-Path $projectRoot '.runtime/protected-server-release.json'
$publishedFolder = Join-Path $projectRoot 'build/BadmintonAce-WSS-Windows'
if ($IfChanged -and (Test-Path -LiteralPath $releaseStatePath)) {
    $previousRelease = Get-Content -LiteralPath $releaseStatePath -Raw | ConvertFrom-Json
    $previousArchive = Join-Path $projectRoot ('dist/' + $previousRelease.archiveName)
    if ($previousRelease.inputFingerprint -eq $inputFingerprint -and (Test-Path -LiteralPath $previousArchive)) {
        if (-not (Test-Path -LiteralPath $publishedFolder)) {
            Expand-Archive -LiteralPath $previousArchive -DestinationPath (Join-Path $projectRoot 'build')
        }
        Write-Host ('Server unchanged; keeping ' + $previousRelease.archiveName)
        Write-Host ('Server folder: ' + $publishedFolder)
        return
    }
}
$previousServerOutput = $env:ACE_SERVER_OUTPUT
try {
    $env:ACE_SERVER_OUTPUT = Join-Path $projectRoot 'build/server/BadmintonAce-Server.exe'
    & $node (Join-Path $PSScriptRoot 'build_server.cjs')
    if ($LASTEXITCODE -ne 0) { throw 'Backend executable build failed; deployment package was not replaced.' }
} finally {
    $env:ACE_SERVER_OUTPUT = $previousServerOutput
}
$staging = Join-Path $projectRoot ('.runtime/protected-server-' + [guid]::NewGuid().ToString('N'))
$package = Join-Path $staging 'BadmintonAce-WSS-Windows'
$caddy = Join-Path $staging 'verified-caddy'
New-Item -ItemType Directory -Path $package,$caddy | Out-Null
Expand-Archive -LiteralPath $archive -DestinationPath $caddy
Copy-Item (Join-Path $projectRoot 'build/server/BadmintonAce-Server.exe') $package
Copy-Item (Join-Path $caddy 'caddy.exe') $package
Copy-Item (Join-Path $caddy 'LICENSE') (Join-Path $package 'CADDY-LICENSE.txt')
Copy-Item (Join-Path $projectRoot 'docs/NODE-LICENSE.txt') $package
Copy-Item (Join-Path $projectRoot 'server/node_modules/ws/LICENSE') (Join-Path $package 'WS-LICENSE.txt')
$sources = @('Caddyfile','README.md','PROTECTED-SERVER.md','allow-wss.cmd','allow-wss.ps1','start-protected.cmd','resume-protected.cmd','start-protected.ps1','traffic-core.ps1','process-job.ps1','traffic-limits.json')
foreach ($name in $sources) {
    $text = [IO.File]::ReadAllText((Join-Path $projectRoot ('deploy/windows-wss/' + $name)))
    if ($name.EndsWith('.cmd')) { $text = $text.Replace("`r`n","`n").Replace("`n","`r`n") }
    [IO.File]::WriteAllText((Join-Path $package $name),$text,[Text.UTF8Encoding]::new($false))
}
@{caddyVersion='2.11.7'; source='https://github.com/caddyserver/caddy/releases/tag/v2.11.7'; archiveSHA512=$expected} | ConvertTo-Json | Set-Content (Join-Path $package 'CADDY-SOURCE.json') -Encoding UTF8
$builtAt = [DateTimeOffset]::UtcNow
$builtAtChina = $builtAt.ToOffset([TimeSpan]::FromHours(8))
$archiveBase = 'BadmintonAce-Protected-Server-' + $builtAtChina.ToString('yyyyMMdd-HHmmss')
$archiveName = $archiveBase + '.zip'
$output = Join-Path $projectRoot ('dist/' + $archiveName)
$duplicate = 1
while (Test-Path -LiteralPath $output) {
    $archiveName = $archiveBase + '-' + $duplicate + '.zip'
    $output = Join-Path $projectRoot ('dist/' + $archiveName)
    $duplicate++
}
$release = [ordered]@{
    builtAtUtc = $builtAt.ToString('o')
    builtAtChina = $builtAtChina.ToString('o')
    archiveName = $archiveName
    inputFingerprint = $inputFingerprint
    serverSHA256 = (Get-FileHash (Join-Path $package 'BadmintonAce-Server.exe') -Algorithm SHA256).Hash
    clientPackage = 'BadmintonAce-Web.zip'
}
$clientArchive = Join-Path $projectRoot 'dist/BadmintonAce-Web.zip'
if (Test-Path -LiteralPath $clientArchive) { $release.clientSHA256 = (Get-FileHash $clientArchive -Algorithm SHA256).Hash }
$release | ConvertTo-Json | Set-Content (Join-Path $package 'RELEASE.json') -Encoding UTF8
$total = (Get-ChildItem $package -File | Measure-Object Length -Sum).Sum
if ($total -ge 200000000) { throw 'Protected server package exceeds 200 MB uncompressed.' }
$pendingArchive = Join-Path $staging 'BadmintonAce-Protected-Server.zip'
Compress-Archive -LiteralPath $package -DestinationPath $pendingArchive -CompressionLevel Optimal
# Never overwrite or delete an earlier release, including a same-second build.
[IO.File]::Move($pendingArchive,$output,$false)
New-Item -ItemType Directory -Force -Path $publishedFolder | Out-Null
Get-ChildItem -LiteralPath $package -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $publishedFolder $_.Name) -Force
}
@{inputFingerprint=$inputFingerprint;archiveName=$archiveName} | ConvertTo-Json | Set-Content -LiteralPath $releaseStatePath -Encoding UTF8
Write-Host ('Built {0}: {1:N2} MB compressed, {2:N2} MB extracted.' -f $output,((Get-Item $output).Length/1000000),($total/1000000))
Write-Host ('Server folder: ' + $publishedFolder)
