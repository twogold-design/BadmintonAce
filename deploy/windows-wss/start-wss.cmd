@echo off
setlocal
cd /d "%~dp0"
title Badminton Ace WSS
if not exist "caddy.exe" (
  echo Missing caddy.exe. Extract the complete WSS package first.
  pause
  exit /b 1
)
rem Keep certificates, keys and runtime files beside this launcher.
set "APPDATA=%~dp0wss-state\roaming"
set "LOCALAPPDATA=%~dp0wss-state\local"
set "XDG_DATA_HOME=%~dp0wss-state\data"
set "XDG_CONFIG_HOME=%~dp0wss-state\config"
set "TEMP=%~dp0wss-state\temp"
set "TMP=%TEMP%"
for %%D in ("%APPDATA%" "%LOCALAPPDATA%" "%XDG_DATA_HOME%" "%XDG_CONFIG_HOME%" "%TEMP%") do if not exist "%%~D" mkdir "%%~D"
echo Start BadmintonAce-Server.exe separately and keep both windows open.
echo Public TCP ports 80 and 443 must reach this computer.
echo Certificate issuance is automatic. Keep this running for renewals.
"%~dp0caddy.exe" run --config "%~dp0Caddyfile" --adapter caddyfile
echo WSS stopped. Check the messages above if this was unexpected.
pause
