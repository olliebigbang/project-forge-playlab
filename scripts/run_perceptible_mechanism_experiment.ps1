param(
    [ValidateSet("Edge", "Point", "Broad", "WholeBody")]
    [string]$Surface = "WholeBody",
    [string]$CaptureDirectory = ""
)

$ErrorActionPreference = "Stop"
$PlaylabRoot = Split-Path -Parent $PSScriptRoot
$Godot = & (Join-Path $PSScriptRoot "find_godot.ps1")
$SurfaceIds = @{
    Edge = "edge"
    Point = "point"
    Broad = "broad"
    WholeBody = "whole_body"
}
$Arguments = @(
    "--path", $PlaylabRoot,
    "res://scenes/perceptible_mechanism_experiment.tscn",
    "--",
    "--experiment-surface=$($SurfaceIds[$Surface])"
)
if (-not [string]::IsNullOrWhiteSpace($CaptureDirectory)) {
    $Arguments += "--mechanism-capture-dir=$CaptureDirectory"
}

Write-Output "Starting perceptible mechanism experiment at the $Surface contact-surface level."
Write-Output "Switch live with 1=Edge, 2=Point, 3=Broad, 4=WholeBody. The concrete objects are replaceable samples."
Write-Output "WASD moves, Space/J attacks, Shift/K dodges."
& $Godot @Arguments
exit $LASTEXITCODE
