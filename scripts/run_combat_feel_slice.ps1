param(
    [string]$Weapon = "giant_wooden_spoon",
    [ValidateSet("", "M01", "M02", "M03", "THRUST")]
    [string]$DeveloperFixture = "",
    [string]$OpenPlaytestRound = "",
    [switch]$RequireAffordanceGrammar,
    [string]$SpritePath = "",
    [string]$BlueprintPath = "",
    [string]$AnchorsPath = "",
    # Developer-only affordance override, as a res:// path. Swaps the compiled feel without
    # touching the frozen, hash-pinned sidecar the weapon normally loads, so a contract
    # change can be played against real assets. The run is marked unverified on screen.
    [string]$CombatAffordance = "",
    # Alternative asset sources. The scene resolves motion grammar before recipe before
    # -Weapon, so these are offered as one exclusive choice rather than three flags that
    # silently outrank each other.
    [string]$RecipeAsset = "",
    [string]$MotionGrammarAsset = "",
    # Load a second asset alongside the first and swap between them with TAB, in one
    # session on one enemy. Judging across a relaunch compares against a memory, which
    # three rounds of playtesting showed cannot even separate a sweep from a bash.
    [string]$CompareWith = "",
    # Pair the loaded asset against a deliberately absurd counterpart. If that is
    # indistinguishable the protocol cannot measure anything, and no amount of tuning the
    # real difference will help.
    [switch]$CompareCalibration
)

$ErrorActionPreference = "Stop"
$PlaylabRoot = Split-Path -Parent $PSScriptRoot
$Godot = & (Join-Path $PSScriptRoot "find_godot.ps1")

if ((-not [string]::IsNullOrWhiteSpace($RecipeAsset)) -and (-not [string]::IsNullOrWhiteSpace($MotionGrammarAsset))) {
    throw "Pass only one of -RecipeAsset or -MotionGrammarAsset; the scene would silently ignore the recipe."
}
$SourceArgument = "--live-weapon=$Weapon"
$SourceLabel = $Weapon
if (-not [string]::IsNullOrWhiteSpace($MotionGrammarAsset)) {
    $SourceArgument = "--motion-grammar-asset=$MotionGrammarAsset"
    $SourceLabel = "motion grammar $MotionGrammarAsset"
}
elseif (-not [string]::IsNullOrWhiteSpace($RecipeAsset)) {
    $SourceArgument = "--recipe-asset=$RecipeAsset"
    $SourceLabel = "recipe $RecipeAsset"
}

$Arguments = @(
    "--path", $PlaylabRoot,
    "res://scenes/combat_feel_slice_0.tscn",
    "--",
    "--mode=combat-feel-slice-0",
    $SourceArgument
)
if (-not [string]::IsNullOrWhiteSpace($DeveloperFixture)) { $Arguments += "--developer-fixture=$DeveloperFixture" }
if (-not [string]::IsNullOrWhiteSpace($OpenPlaytestRound)) { $Arguments += "--open-playtest-round=$OpenPlaytestRound" }
if ($RequireAffordanceGrammar) { $Arguments += "--require-affordance-grammar" }
if (-not [string]::IsNullOrWhiteSpace($SpritePath)) { $Arguments += "--combat-sprite=$SpritePath" }
if (-not [string]::IsNullOrWhiteSpace($BlueprintPath)) { $Arguments += "--combat-blueprint=$BlueprintPath" }
if (-not [string]::IsNullOrWhiteSpace($AnchorsPath)) { $Arguments += "--combat-anchors=$AnchorsPath" }
if (-not [string]::IsNullOrWhiteSpace($CombatAffordance)) { $Arguments += "--combat-affordance=$CombatAffordance" }
if (-not [string]::IsNullOrWhiteSpace($CompareWith)) { $Arguments += "--compare-with=$CompareWith" }
if ($CompareCalibration) { $Arguments += "--compare-calibration" }

Write-Output "Starting Forge Combat Feel Slice 0 Revision A ($SourceLabel)."
Write-Output "Default source is a frozen real Live Forge result; developer fixtures require -DeveloperFixture explicitly."
& $Godot @Arguments
exit $LASTEXITCODE
