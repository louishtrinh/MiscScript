@echo off
title LogMover
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0LogMover.ps1"
if errorlevel 1 pause
