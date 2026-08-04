param(
    [string]$SpriteDirectory = "",
    [switch]$LoadReviewTargets
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$godot = & (Join-Path $repoRoot "scripts\find_godot.ps1")
$godotArguments = @(
    "--path",
    $repoRoot,
    "res://scenes/semantic_anchor_spike.tscn",
    "--"
)

if (-not [string]::IsNullOrWhiteSpace($SpriteDirectory)) {
    $godotArguments += "--sprite-dir=$SpriteDirectory"
}

if ($LoadReviewTargets) {
    $godotArguments += "--calibration-targets=res://tools/comfyui/anchor_calibration/test_cases/calibration_targets.json"
}

Write-Host "Starting the training-only Semantic Anchor Spike 1. This command does not start ComfyUI."
& $godot @godotArguments
exit $LASTEXITCODE
