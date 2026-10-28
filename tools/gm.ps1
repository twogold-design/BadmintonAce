$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$dataDirectory = if ($env:DATA_DIR) { $env:DATA_DIR } else { Join-Path $projectRoot 'data' }
$serverPort = if ($env:PORT) { $env:PORT } else { '8766' }
$keyFile = Join-Path $dataDirectory 'gm-key.txt'
if (-not (Test-Path -LiteralPath $keyFile)) { throw '请先启动新版 BadmintonAce-Server.exe，再打开 GM 管理。' }
$gmKey = [IO.File]::ReadAllText($keyFile).Trim()
if ($gmKey -notmatch '^[a-f0-9]{64}$') { throw '管理密钥文件不正确。' }
$env:TEMP = Join-Path $projectRoot '.runtime\temp'
$env:TMP = $env:TEMP
$env:APPDATA = Join-Path $projectRoot '.runtime\roaming'
$env:LOCALAPPDATA = Join-Path $projectRoot '.runtime\local'
New-Item -ItemType Directory -Force -Path $env:TEMP,$env:APPDATA,$env:LOCALAPPDATA | Out-Null
$browser = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
if (-not (Test-Path -LiteralPath $browser)) { $browser = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' }
if (-not (Test-Path -LiteralPath $browser)) { throw '请安装 Chrome 或 Edge，或手动在浏览器打开本机 GM 页面并输入密钥。' }
$profilePath = Join-Path $projectRoot '.runtime\gm-browser'
$cachePath = Join-Path $projectRoot '.runtime\gm-browser-cache'
Start-Process -FilePath $browser -ArgumentList @(('--user-data-dir="' + $profilePath + '"'),('--disk-cache-dir="' + $cachePath + '"'),'--disable-crash-reporter','--disable-breakpad','--no-first-run',"--app=http://127.0.0.1:$serverPort/gm#$gmKey")
