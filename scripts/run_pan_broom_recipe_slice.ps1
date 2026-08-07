param(
    [ValidateSet("Pan", "Broom")]
    [string]$Asset = "Pan"
)

$ErrorActionPreference = "Stop"
$PlaylabRoot = Split-Path -Parent $PSScriptRoot
$Godot = & (Join-Path $PSScriptRoot "find_godot.ps1")
$RecipeAsset = @{
    Pan = "frying_pan"
    Broom = "old_mop"
}[$Asset]

$Arguments = @(
    "--path", $PlaylabRoot,
    "res://scenes/combat_feel_slice_0.tscn",
    "--",
    "--mode=combat-feel-slice-0",
    "--recipe-asset=$RecipeAsset"
)

Write-Output "Starting Pan vs Broom Recipe Slice 1B ($Asset)."
Write-Output "Loading frozen player-confirmed Open Playtest evidence and its compiled ComboRecipe."
& $Godot @Arguments
exit $LASTEXITCODE
