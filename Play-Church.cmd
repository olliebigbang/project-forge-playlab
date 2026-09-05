@echo off
powershell.exe -NoProfile -File "%~dp0scripts\run_church_ai_forge.ps1"
if errorlevel 1 pause
