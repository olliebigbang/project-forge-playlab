param(
    [ValidateSet("", "Pan", "Broom", "Shotgun", "ShotgunMelee")]
    [string]$Asset = ""
)

$ErrorActionPreference = "Stop"
$PlaylabRoot = Split-Path -Parent $PSScriptRoot
$Godot = & (Join-Path $PSScriptRoot "find_godot.ps1")

if ([string]::IsNullOrWhiteSpace($Asset)) {
    Write-Output "Select a real Motion Grammar asset:"
    Write-Output "  1. Pan"
    Write-Output "  2. Broom"
    Write-Output "  3. Shotgun melee (developer-only intent override)"
    $Selection = Read-Host "Enter 1, 2, or 3"
    $Asset = @{
        "1" = "Pan"
        "2" = "Broom"
        "3" = "ShotgunMelee"
    }[$Selection]
    if ([string]::IsNullOrWhiteSpace($Asset)) {
        throw "Invalid selection. Enter 1, 2, or 3."
    }
}

if ($Asset -eq "Shotgun") {
    $Asset = "ShotgunMelee"
}

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
