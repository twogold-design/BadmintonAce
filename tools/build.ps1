. (Join-Path $PSScriptRoot 'environment.ps1')
New-Item -ItemType Directory -Force -Path $env:APPDATA,$env:LOCALAPPDATA,$env:TEMP,'build\web','dist' | Out-Null
Set-Content -LiteralPath 'dist\.gdignore' -Value ''
$godot = Resolve-AceTool 'GODOT_BIN' @('godot','godot4') 'D:\tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --editor --path $projectRoot --import
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed' }
& $godot --headless --path $projectRoot --export-release Web 'build/web/index.html'
if ($LASTEXITCODE -ne 0) { throw 'Godot export failed' }
$htmlPath = Join-Path $projectRoot 'build\web\index.html'
$html = [IO.File]::ReadAllText($htmlPath)
$html = $html.Replace('<html lang="en">','<html lang="zh-CN">')
$html = $html.Replace('<script src="index.js"></script>','<script src="config.js"></script><script src="local-loader.js"></script><script src="index.js"></script>')
$html = $html.Replace('(function () {', '(async function () {')
$html = $html.Replace('const missing = Engine.getMissingFeatures({', 'setStatusMode(''progress''); try { await window.ACE_LOCAL_READY; } catch (error) { displayFailureNotice(error); return; }' + [Environment]::NewLine + 'const missing = Engine.getMissingFeatures({')
if (-not $html.Contains("setStatusMode('hidden');")) { throw 'Loading completion hook changed; review the scene readiness gate.' }
$html = $html.Replace("setStatusMode('hidden');", "const finishLoading = () => { if (window.badmintonReady) setStatusMode('hidden'); else requestAnimationFrame(finishLoading); }; finishLoading();")
$node = Resolve-AceTool 'NODE_BIN' @('node') 'D:\tools\nodejs2\node.exe'

& $node 'tools/prepare_local.cjs'
if ($LASTEXITCODE -ne 0) { throw 'Local-file resource bundling failed' }
$css = @'
<style>
body,#status{background:#0b1721}#status-splash{display:none!important}
#status:before{content:'谁是羽毛球高手';font:700 38px system-ui;color:#edf3e9;letter-spacing:4px;margin-bottom:22px}
#status:after{content:'正在准备球场…  /  首次加载请稍候';font:15px system-ui;color:#829b9e;margin-top:22px}
#status-progress{position:relative;bottom:auto;width:300px;height:7px;accent-color:#cdf578}
</style>
'@
$html = $html.Replace('</head>', $css + '</head>')
[IO.File]::WriteAllText($htmlPath,$html,[Text.UTF8Encoding]::new($false))
# Keep the root launcher; commit this Web export so fresh checkouts can play.
Copy-Item -LiteralPath 'tools\web-config.js' -Destination 'build\web\config.js' -Force
Copy-Item -LiteralPath 'assets\athletes\ATHLETE-LICENSE.txt' -Destination 'build\web\ATHLETE-LICENSE.txt' -Force
Copy-Item -LiteralPath 'assets\FONT-LICENSE.txt' -Destination 'build\web\FONT-LICENSE.txt' -Force
Copy-Item -LiteralPath 'docs\比赛提交说明.txt' -Destination 'build\web\README.txt' -Force
if (Test-Path -LiteralPath 'docs\GODOT-LICENSE.txt') { Copy-Item -LiteralPath 'docs\GODOT-LICENSE.txt' -Destination 'build\web\GODOT-LICENSE.txt' -Force }
[IO.File]::WriteAllText((Join-Path $projectRoot 'build\web\entry-ready.js'),'window.ACE_WEB_BUILD = 1;',[Text.UTF8Encoding]::new($false))
$files = Get-ChildItem -LiteralPath 'build\web' -File
$totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
if ($totalBytes -ge 200000000) { throw "Web build exceeds 200 MB: $totalBytes bytes" }
$zipPath = Join-Path $projectRoot 'dist\BadmintonAce-Web.zip'
Compress-Archive -Path 'build\web\*' -DestinationPath $zipPath -Force -CompressionLevel Optimal
$zipBytes = (Get-Item -LiteralPath $zipPath).Length
$manifest = [ordered]@{ game='谁是羽毛球高手'; godot='4.7.2'; entry='index.html'; web_bytes=$totalBytes; zip_bytes=$zipBytes; limit_bytes=200000000; files=@($files | ForEach-Object { @{name=$_.Name; bytes=$_.Length; sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash} }) }
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath 'dist\manifest.json' -Encoding UTF8
Write-Output ('WEB: {0:N2} MB / ZIP: {1:N2} MB / LIMIT: 200 MB' -f ($totalBytes/1000000),($zipBytes/1000000))
Write-Output $zipPath
