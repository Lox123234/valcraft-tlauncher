@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0ValCraft-TLauncher.ps1" -Action Start
if errorlevel 1 (pause & exit /b 1)
