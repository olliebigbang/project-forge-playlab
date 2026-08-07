param(
    [ValidateSet("Pan", "Broom", "ShotgunMelee")]
    [string]$Asset = "Pan"
)

$ErrorActionPreference = "Stop"
$PlaylabRoot = Split-Path -Parent $PSScriptRoot
$Godot = & (Join-Path $PSScriptRoot "find_godot.ps1")
$MotionGrammarAsset = @{
    Pan = "frying_pan"
    Broom = "old_mop"
    ShotgunMelee = "shotgun_melee"
}[$Asset]

$Arguments = @(
    "--path", $PlaylabRoot,
    "res://scenes/combat_feel_slice_0.tscn",
    "--",
    "--mode=combat-feel-slice-0",
    "--motion-grammar-asset=$MotionGrammarAsset"
)

Write-Output "Starting Motion Grammar Slice 1A ($Asset)."
if ($Asset -eq "ShotgunMelee") {
    Write-Output "Developer-only melee intent override; the frozen ranged Blueprint is not modified."
}
& $Godot @Arguments
exit $LASTEXITCODE
