@echo off
title Badminton Ace - Resume Protected Server
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0start-protected.ps1" -Resume %*
pause
