@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run_original_action_preview.ps1"
if errorlevel 1 pause
