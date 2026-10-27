. (Join-Path $PSScriptRoot 'environment.ps1')
$godot = Resolve-AceTool 'GODOT_BIN' @('godot','godot4') 'D:\tools\Godot-4.7.2\Godot_v4.7.2-stable_win64.exe'
# This is the interactive editor explicitly requested by the launcher.
Start-Process -FilePath $godot -ArgumentList @('--editor','--path',('"' + $projectRoot + '"')) -WorkingDirectory $projectRoot -WindowStyle Normal
