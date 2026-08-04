$ErrorActionPreference = "Stop"
$PlaylabRoot = Split-Path -Parent $PSScriptRoot
$Godot = & (Join-Path $PSScriptRoot "find_godot.ps1")

$TestOutput = & $Godot --headless --path $PlaylabRoot --script "res://tests/test_combat_feel_slice_0.gd" 2>&1
$TestOutput | ForEach-Object { Write-Output $_ }
if ($LASTEXITCODE -ne 0 -or ($TestOutput -join "`n") -match "SCRIPT ERROR|ERROR: FAIL|failed=[1-9]") { exit 1 }

$ParseOutput = & $Godot --headless --path $PlaylabRoot --script "res://scripts/combat_feel/combat_feel_slice_0.gd" --check-only 2>&1
$ParseOutput | ForEach-Object { Write-Output $_ }
if ($LASTEXITCODE -ne 0 -or ($ParseOutput -join "`n") -match "SCRIPT ERROR|Parse Error|Compile Error") { exit 1 }

Write-Output "COMBAT_FEEL_SLICE_0_GODOT_PARSE=PASS"
exit 0
