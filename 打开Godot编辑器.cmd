@echo off
set "APPDATA=%~dp0.runtime\roaming"
set "LOCALAPPDATA=%~dp0.runtime\local"
set "TEMP=%~dp0.runtime\temp"
set "TMP=%TEMP%"
start "" "D:\tools\Godot-4.7.2\Godot_v4.7.2-stable_win64.exe" --editor --path "%~dp0."
