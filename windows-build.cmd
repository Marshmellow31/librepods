@echo off
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0build-windows.ps1" %*
