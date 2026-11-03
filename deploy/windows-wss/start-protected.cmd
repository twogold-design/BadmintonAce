@echo off
title Badminton Ace - Protected Server
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0start-protected.ps1" %*
pause
