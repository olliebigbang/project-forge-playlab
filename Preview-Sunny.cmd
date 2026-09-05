@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run_sunny_arena_preview_v1.ps1"
if errorlevel 1 pause
