[CmdletBinding()]
param(
    [string]$Model = "claude-sonnet-5",
    [ValidateSet("MOCK", "LOCAL_COMFYUI", "FAL_FIREARM")]
    [string]$VisualProvider = "FAL_FIREARM",
    [string]$EnvFile = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Launcher = Join-Path $PSScriptRoot "run_open_identity_firearm_ai.ps1"
& $Launcher -Model $Model -VisualProvider $VisualProvider -EnvFile $EnvFile
exit $LASTEXITCODE
