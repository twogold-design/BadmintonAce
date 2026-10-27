# Shared local paths. Dot-source before launching Godot, npm or test browsers.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$env:APPDATA = Join-Path $projectRoot '.runtime\roaming'
$env:LOCALAPPDATA = Join-Path $projectRoot '.runtime\local'
$env:TEMP = Join-Path $projectRoot '.runtime\temp'
$env:TMP = $env:TEMP
$env:npm_config_cache = Join-Path $projectRoot '.runtime\npm-cache'
$env:PYTHONDONTWRITEBYTECODE = '1'
$env:PLAYWRIGHT_BROWSERS_PATH = Join-Path $projectRoot '.runtime\playwright'
New-Item -ItemType Directory -Force -Path $env:APPDATA,$env:LOCALAPPDATA,$env:TEMP | Out-Null

function Resolve-AceTool([string]$Variable, [string[]]$Commands, [string]$Fallback) {
    $configured = [Environment]::GetEnvironmentVariable($Variable)
    if ($configured) {
        if (Test-Path -LiteralPath $configured -PathType Leaf) { return (Resolve-Path -LiteralPath $configured).Path }
        throw "$Variable does not point to an executable: $configured"
    }
    foreach ($name in $Commands) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    if ($Fallback -and (Test-Path -LiteralPath $Fallback -PathType Leaf)) { return $Fallback }
    throw "Missing tool. Set environment variable $Variable to its full executable path, or add it to PATH."
}
