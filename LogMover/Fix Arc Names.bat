@echo off
title Fix Arc Names
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix-ArcPrefix.ps1"
pause
