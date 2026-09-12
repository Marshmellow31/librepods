@echo off
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0windows-build.ps1" %*
