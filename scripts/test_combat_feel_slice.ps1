$ErrorActionPreference = "Stop"
$PlaylabRoot = Split-Path -Parent $PSScriptRoot
$Godot = & (Join-Path $PSScriptRoot "find_godot.ps1")

$TestLog = New-TemporaryFile
& $Godot --headless --verbose --path $PlaylabRoot --script "res://tests/test_combat_feel_slice_0.gd" 2>&1 | Tee-Object -FilePath $TestLog.FullName
$TestExit = $LASTEXITCODE
$TestOutput = Get-Content -LiteralPath $TestLog.FullName -Raw
Remove-Item -LiteralPath $TestLog.FullName
if ($TestExit -ne 0 -or $TestOutput -match "SCRIPT ERROR|Parse Error|Compile Error|ERROR: FAIL|failed=[1-9]") { exit 1 }

$RecipeLog = New-TemporaryFile
& $Godot --headless --verbose --path $PlaylabRoot --script "res://tests/test_pan_broom_recipe_slice_1b.gd" 2>&1 | Tee-Object -FilePath $RecipeLog.FullName
$RecipeExit = $LASTEXITCODE
$RecipeOutput = Get-Content -LiteralPath $RecipeLog.FullName -Raw
Remove-Item -LiteralPath $RecipeLog.FullName
if ($RecipeExit -ne 0 -or $RecipeOutput -match "SCRIPT ERROR|Parse Error|Compile Error|ERROR: FAIL|failed=[1-9]") { exit 1 }

foreach ($RecipeAsset in @("frying_pan", "old_mop")) {
    $SceneLog = New-TemporaryFile
    & $Godot --headless --verbose --path $PlaylabRoot "res://scenes/combat_feel_slice_0.tscn" -- --mode=combat-feel-slice-0 --recipe-asset=$RecipeAsset --smoke-seconds=0.2 2>&1 | Tee-Object -FilePath $SceneLog.FullName
    $SceneExit = $LASTEXITCODE
    $SceneOutput = Get-Content -LiteralPath $SceneLog.FullName -Raw
    Remove-Item -LiteralPath $SceneLog.FullName
    if ($SceneExit -ne 0 -or $SceneOutput -match "SCRIPT ERROR|Parse Error|Compile Error") { exit 1 }
}

Write-Output "COMBAT_FEEL_SLICE_0_GODOT_PARSE=PASS"
exit 0
