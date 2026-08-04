$ErrorActionPreference = "Stop"
$PlaylabRoot = Split-Path -Parent $PSScriptRoot
$Godot = & (Join-Path $PSScriptRoot "find_godot.ps1")
$OutputDirectory = Join-Path $PlaylabRoot "docs\screenshots\combat_feel_slice_0"
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
& $Godot --headless --path $PlaylabRoot "res://scenes/combat_feel_slice_0.tscn" -- --mode=combat-feel-slice-0 --fixture=M01 --capture-dir=$OutputDirectory
exit $LASTEXITCODE
