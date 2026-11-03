# Fingerprint deployment inputs only. Client scenes, models and Web exports do
# not affect the backend archive and must not cause another server release.
function Get-AceServerReleaseFingerprint([string]$Root, [string]$Node) {
    $files = @()
    $files += Get-ChildItem -LiteralPath (Join-Path $Root 'server') -File | Where-Object {
        $_.Extension -in @('.js','.json') -and -not $_.Name.StartsWith('test')
    }
    $files += Get-ChildItem -LiteralPath (Join-Path $Root 'server/node_modules/ws') -File -Recurse
    $files += Get-ChildItem -LiteralPath (Join-Path $Root 'deploy/windows-wss') -File
    foreach ($name in @('assets/challenges.json','docs/NODE-LICENSE.txt','tools/build_server.cjs','tools/build_protected_server.ps1','tools/server_release_inputs.ps1','tools/package-lock.json','.runtime/caddy-download/caddy.zip')) {
        $files += Get-Item -LiteralPath (Join-Path $Root $name)
    }
    $lines = @($files | Sort-Object FullName -Unique | ForEach-Object {
        [IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/') + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    })
    $lines += 'node-runtime:' + (Get-FileHash -LiteralPath $Node -Algorithm SHA256).Hash
    $bytes = [Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}
