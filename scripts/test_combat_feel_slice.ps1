$ErrorActionPreference = "Stop"
$PlaylabRoot = Split-Path -Parent $PSScriptRoot
$Godot = & (Join-Path $PSScriptRoot "find_godot.ps1")

$TestLog = New-TemporaryFile
& $Godot --headless --verbose --path $PlaylabRoot --script "res://tests/test_combat_feel_slice_0.gd" 2>&1 | Tee-Object -FilePath $TestLog.FullName
$TestExit = $LASTEXITCODE
$TestOutput = Get-Content -LiteralPath $TestLog.FullName -Raw
Remove-Item -LiteralPath $TestLog.FullName
if ($TestExit -ne 0 -or $TestOutput -match "SCRIPT ERROR|Parse Error|Compile Error|ERROR: FAIL|failed=[1-9]") { exit 1 }

$MechanismExperimentLog = New-TemporaryFile
& $Godot --headless --verbose --path $PlaylabRoot --script "res://tests/test_perceptible_mechanism_experiment.gd" 2>&1 | Tee-Object -FilePath $MechanismExperimentLog.FullName
$MechanismExperimentExit = $LASTEXITCODE
$MechanismExperimentOutput = Get-Content -LiteralPath $MechanismExperimentLog.FullName -Raw
Remove-Item -LiteralPath $MechanismExperimentLog.FullName
if ($MechanismExperimentExit -ne 0 -or $MechanismExperimentOutput -match "SCRIPT ERROR|Parse Error|Compile Error|ERROR: FAIL|failed=[1-9]") { exit 1 }

$ExperimentSceneLog = New-TemporaryFile
& $Godot --headless --verbose --path $PlaylabRoot "res://scenes/perceptible_mechanism_experiment.tscn" -- --experiment-surface=broad --smoke-seconds=0.2 2>&1 | Tee-Object -FilePath $ExperimentSceneLog.FullName
$ExperimentSceneExit = $LASTEXITCODE
$ExperimentSceneOutput = Get-Content -LiteralPath $ExperimentSceneLog.FullName -Raw
Remove-Item -LiteralPath $ExperimentSceneLog.FullName
if ($ExperimentSceneExit -ne 0 -or $ExperimentSceneOutput -match "SCRIPT ERROR|Parse Error|Compile Error|UNSUPPORTED_AFFORDANCE|MECHANISM_EXPERIMENT_ASSET_INVALID") { exit 1 }

$RecipeLog = New-TemporaryFile
& $Godot --headless --verbose --path $PlaylabRoot --script "res://tests/test_pan_broom_recipe_slice_1b.gd" 2>&1 | Tee-Object -FilePath $RecipeLog.FullName
$RecipeExit = $LASTEXITCODE
$RecipeOutput = Get-Content -LiteralPath $RecipeLog.FullName -Raw
Remove-Item -LiteralPath $RecipeLog.FullName
if ($RecipeExit -ne 0 -or $RecipeOutput -match "SCRIPT ERROR|Parse Error|Compile Error|ERROR: FAIL|failed=[1-9]") { exit 1 }

$MotionGrammarLog = New-TemporaryFile
& $Godot --headless --verbose --path $PlaylabRoot --script "res://tests/test_motion_grammar_slice_1a.gd" 2>&1 | Tee-Object -FilePath $MotionGrammarLog.FullName
$MotionGrammarExit = $LASTEXITCODE
$MotionGrammarOutput = Get-Content -LiteralPath $MotionGrammarLog.FullName -Raw
Remove-Item -LiteralPath $MotionGrammarLog.FullName
if ($MotionGrammarExit -ne 0 -or $MotionGrammarOutput -match "SCRIPT ERROR|Parse Error|Compile Error|ERROR: FAIL|failed=[1-9]") { exit 1 }

$MechanismVisualLog = New-TemporaryFile
& $Godot --headless --verbose --path $PlaylabRoot --script "res://tests/test_mechanism_visual_generation.gd" 2>&1 | Tee-Object -FilePath $MechanismVisualLog.FullName
$MechanismVisualExit = $LASTEXITCODE
$MechanismVisualOutput = Get-Content -LiteralPath $MechanismVisualLog.FullName -Raw
Remove-Item -LiteralPath $MechanismVisualLog.FullName
if ($MechanismVisualExit -ne 0 -or $MechanismVisualOutput -match "SCRIPT ERROR|Parse Error|Compile Error|ERROR: FAIL|failed=[1-9]") { exit 1 }

$RangedWeaponLog = New-TemporaryFile
& $Godot --headless --verbose --path $PlaylabRoot --script "res://tests/test_ranged_weapon_generation.gd" 2>&1 | Tee-Object -FilePath $RangedWeaponLog.FullName
$RangedWeaponExit = $LASTEXITCODE
$RangedWeaponOutput = Get-Content -LiteralPath $RangedWeaponLog.FullName -Raw
Remove-Item -LiteralPath $RangedWeaponLog.FullName
if ($RangedWeaponExit -ne 0 -or $RangedWeaponOutput -match "SCRIPT ERROR|Parse Error|Compile Error|ERROR: FAIL|failed=[1-9]|RANGED WEAPON RESULT:.*[1-9] failed") { exit 1 }

$FirearmAiParserLog = New-TemporaryFile
& $Godot --headless --verbose --path $PlaylabRoot --script "res://tests/test_firearm_identity_ai_parser.gd" 2>&1 | Tee-Object -FilePath $FirearmAiParserLog.FullName
$FirearmAiParserExit = $LASTEXITCODE
$FirearmAiParserOutput = Get-Content -LiteralPath $FirearmAiParserLog.FullName -Raw
Remove-Item -LiteralPath $FirearmAiParserLog.FullName
if ($FirearmAiParserExit -ne 0 -or $FirearmAiParserOutput -match "SCRIPT ERROR|Parse Error|Compile Error|ERROR: FAIL|failed=[1-9]|FIREARM AI PARSER RESULT:.*[1-9] failed") { exit 1 }

$GeneralizationLog = New-TemporaryFile
& $Godot --headless --verbose --path $PlaylabRoot --script "res://tests/test_motion_grammar_generalization.gd" 2>&1 | Tee-Object -FilePath $GeneralizationLog.FullName
$GeneralizationExit = $LASTEXITCODE
$GeneralizationOutput = Get-Content -LiteralPath $GeneralizationLog.FullName -Raw
Remove-Item -LiteralPath $GeneralizationLog.FullName
if ($GeneralizationExit -ne 0 -or $GeneralizationOutput -match "SCRIPT ERROR|Parse Error|Compile Error|ERROR: FAIL|failed=[1-9]") { exit 1 }

$LegacySceneLog = New-TemporaryFile
& $Godot --headless --verbose --path $PlaylabRoot "res://scenes/combat_feel_slice_0.tscn" -- --mode=combat-feel-slice-0 --live-weapon=giant_wooden_spoon --smoke-seconds=0.2 2>&1 | Tee-Object -FilePath $LegacySceneLog.FullName
$LegacySceneExit = $LASTEXITCODE
$LegacySceneOutput = Get-Content -LiteralPath $LegacySceneLog.FullName -Raw
Remove-Item -LiteralPath $LegacySceneLog.FullName
if ($LegacySceneExit -ne 0 -or $LegacySceneOutput -match "SCRIPT ERROR|Parse Error|Compile Error|UNSUPPORTED") { exit 1 }

foreach ($RecipeAsset in @("frying_pan", "old_mop")) {
    $SceneLog = New-TemporaryFile
    & $Godot --headless --verbose --path $PlaylabRoot "res://scenes/combat_feel_slice_0.tscn" -- --mode=combat-feel-slice-0 --recipe-asset=$RecipeAsset --smoke-seconds=0.2 2>&1 | Tee-Object -FilePath $SceneLog.FullName
    $SceneExit = $LASTEXITCODE
    $SceneOutput = Get-Content -LiteralPath $SceneLog.FullName -Raw
    Remove-Item -LiteralPath $SceneLog.FullName
    if ($SceneExit -ne 0 -or $SceneOutput -match "SCRIPT ERROR|Parse Error|Compile Error") { exit 1 }
}

foreach ($MotionGrammarAsset in @("frying_pan", "old_mop", "shotgun_melee")) {
    $SceneLog = New-TemporaryFile
    & $Godot --headless --verbose --path $PlaylabRoot "res://scenes/combat_feel_slice_0.tscn" -- --mode=combat-feel-slice-0 --motion-grammar-asset=$MotionGrammarAsset --smoke-seconds=0.2 2>&1 | Tee-Object -FilePath $SceneLog.FullName
    $SceneExit = $LASTEXITCODE
    $SceneOutput = Get-Content -LiteralPath $SceneLog.FullName -Raw
    Remove-Item -LiteralPath $SceneLog.FullName
    if ($SceneExit -ne 0 -or $SceneOutput -match "SCRIPT ERROR|Parse Error|Compile Error|UNSUPPORTED_AFFORDANCE") { exit 1 }
}

foreach ($SoftWeaponAsset in @("fishing_rod_builtin", "continuous_lash_builtin", "linked_braid_builtin", "rigid_staff_builtin")) {
    $SoftWeaponSceneLog = New-TemporaryFile
    & $Godot --headless --verbose --path $PlaylabRoot "res://scenes/combat_feel_slice_0.tscn" -- --mode=combat-feel-slice-0 --soft-weapon-asset=$SoftWeaponAsset --smoke-seconds=0.2 2>&1 | Tee-Object -FilePath $SoftWeaponSceneLog.FullName
    $SoftWeaponSceneExit = $LASTEXITCODE
    $SoftWeaponSceneOutput = Get-Content -LiteralPath $SoftWeaponSceneLog.FullName -Raw
    Remove-Item -LiteralPath $SoftWeaponSceneLog.FullName
    if ($SoftWeaponSceneExit -ne 0 -or $SoftWeaponSceneOutput -match "SCRIPT ERROR|Parse Error|Compile Error|UNSUPPORTED_AFFORDANCE|SOFT_WEAPON_.*INVALID|AI_VISUAL_RIG_.*") { exit 1 }
}

foreach ($GeneralizationAsset in @("longsword_generalization", "spear_generalization", "wooden_chair_generalization")) {
    $SceneLog = New-TemporaryFile
    & $Godot --headless --verbose --path $PlaylabRoot "res://scenes/combat_feel_slice_0.tscn" -- --mode=combat-feel-slice-0 --generalization-asset=$GeneralizationAsset --smoke-seconds=0.2 2>&1 | Tee-Object -FilePath $SceneLog.FullName
    $SceneExit = $LASTEXITCODE
    $SceneOutput = Get-Content -LiteralPath $SceneLog.FullName -Raw
    Remove-Item -LiteralPath $SceneLog.FullName
    if ($SceneExit -ne 0 -or $SceneOutput -match "SCRIPT ERROR|Parse Error|Compile Error|UNSUPPORTED_AFFORDANCE|GENERALIZATION_.*INVALID") { exit 1 }
}

Write-Output "COMBAT_FEEL_SLICE_0_GODOT_PARSE=PASS"
exit 0
