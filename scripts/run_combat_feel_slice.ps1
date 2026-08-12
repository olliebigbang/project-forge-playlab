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
    [string]$CombatAffordance = ""
)

$ErrorActionPreference = "Stop"
$PlaylabRoot = Split-Path -Parent $PSScriptRoot
$Godot = & (Join-Path $PSScriptRoot "find_godot.ps1")
$Arguments = @(
    "--path", $PlaylabRoot,
    "res://scenes/combat_feel_slice_0.tscn",
    "--",
    "--mode=combat-feel-slice-0",
    "--live-weapon=$Weapon"
)
if (-not [string]::IsNullOrWhiteSpace($DeveloperFixture)) { $Arguments += "--developer-fixture=$DeveloperFixture" }
if (-not [string]::IsNullOrWhiteSpace($OpenPlaytestRound)) { $Arguments += "--open-playtest-round=$OpenPlaytestRound" }
if ($RequireAffordanceGrammar) { $Arguments += "--require-affordance-grammar" }
if (-not [string]::IsNullOrWhiteSpace($SpritePath)) { $Arguments += "--combat-sprite=$SpritePath" }
if (-not [string]::IsNullOrWhiteSpace($BlueprintPath)) { $Arguments += "--combat-blueprint=$BlueprintPath" }
if (-not [string]::IsNullOrWhiteSpace($AnchorsPath)) { $Arguments += "--combat-anchors=$AnchorsPath" }
if (-not [string]::IsNullOrWhiteSpace($CombatAffordance)) { $Arguments += "--combat-affordance=$CombatAffordance" }

Write-Output "Starting Forge Combat Feel Slice 0 Revision A ($Weapon)."
Write-Output "Default source is a frozen real Live Forge result; developer fixtures require -DeveloperFixture explicitly."
& $Godot @Arguments
exit $LASTEXITCODE
