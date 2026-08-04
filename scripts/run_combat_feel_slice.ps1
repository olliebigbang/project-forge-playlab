param(
    [ValidateSet("M01", "M02", "M03", "THRUST")]
    [string]$Fixture = "M01",
    [string]$SpritePath = "",
    [string]$BlueprintPath = "",
    [string]$AnchorsPath = ""
)

$ErrorActionPreference = "Stop"
$PlaylabRoot = Split-Path -Parent $PSScriptRoot
$Godot = & (Join-Path $PSScriptRoot "find_godot.ps1")
$BuiltExecutable = Join-Path $PlaylabRoot "build\windows\ForgeCombatFeelSlice0.exe"
$Arguments = @(
    "--path", $PlaylabRoot,
    "res://scenes/combat_feel_slice_0.tscn",
    "--",
    "--mode=combat-feel-slice-0",
    "--fixture=$Fixture"
)
if (-not [string]::IsNullOrWhiteSpace($SpritePath)) { $Arguments += "--combat-sprite=$SpritePath" }
if (-not [string]::IsNullOrWhiteSpace($BlueprintPath)) { $Arguments += "--combat-blueprint=$BlueprintPath" }
if (-not [string]::IsNullOrWhiteSpace($AnchorsPath)) { $Arguments += "--combat-anchors=$AnchorsPath" }

Write-Output "Starting Forge Combat Feel Slice 0 ($Fixture)."
Write-Output "Developer fixtures are clearly marked and do not impersonate Live generation."
if ((Test-Path -LiteralPath $BuiltExecutable) -and (Test-Path -LiteralPath (Join-Path $PlaylabRoot "build\windows\ForgeCombatFeelSlice0.pck"))) {
    $PackedArguments = @("--", "--mode=combat-feel-slice-0", "--fixture=$Fixture")
    if (-not [string]::IsNullOrWhiteSpace($SpritePath)) { $PackedArguments += "--combat-sprite=$SpritePath" }
    if (-not [string]::IsNullOrWhiteSpace($BlueprintPath)) { $PackedArguments += "--combat-blueprint=$BlueprintPath" }
    if (-not [string]::IsNullOrWhiteSpace($AnchorsPath)) { $PackedArguments += "--combat-anchors=$AnchorsPath" }
    & $BuiltExecutable @PackedArguments
} else {
    & $Godot @Arguments
}
exit $LASTEXITCODE
