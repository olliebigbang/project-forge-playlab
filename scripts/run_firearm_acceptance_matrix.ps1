[CmdletBinding()]
param(
    [string]$Model = "claude-sonnet-5",
    [string]$EnvFile = "",
    [string]$OutputDirectory = "res://output/firearm-automatic-acceptance-v3",
    [ValidateRange(0, 2)]
    [int]$MaxRetries = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PlaylabRoot = Split-Path -Parent $PSScriptRoot
$Godot = & (Join-Path $PSScriptRoot "find_godot.ps1")
$Python = (Get-Command python -ErrorAction Stop).Source
$HadApiKey = Test-Path Env:ANTHROPIC_API_KEY
$HadFalKey = Test-Path Env:FAL_KEY
$HadModel = Test-Path Env:FORGE_SEMANTIC_MODEL
$SavedApiKey = $env:ANTHROPIC_API_KEY
$SavedFalKey = $env:FAL_KEY
$SavedModel = $env:FORGE_SEMANTIC_MODEL
$ExitCode = 1

try {
    if (-not [string]::IsNullOrWhiteSpace($EnvFile)) {
        $ResolvedEnvFile = (Resolve-Path -LiteralPath $EnvFile -ErrorAction Stop).Path
        foreach ($Line in Get-Content -LiteralPath $ResolvedEnvFile) {
            if ($Line -notmatch '^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') { continue }
            $Name = $Matches[1]
            if ($Name -notin @("ANTHROPIC_API_KEY", "FAL_KEY", "FAL_API_KEY")) { continue }
            $Value = $Matches[2].Trim()
            if ($Value.Length -ge 2 -and (
                ($Value.StartsWith('"') -and $Value.EndsWith('"')) -or
                ($Value.StartsWith("'") -and $Value.EndsWith("'"))
            )) {
                $Value = $Value.Substring(1, $Value.Length - 2)
            }
            if ([string]::IsNullOrWhiteSpace($Value)) { continue }
            if ($Name -eq "ANTHROPIC_API_KEY" -and [string]::IsNullOrWhiteSpace($env:ANTHROPIC_API_KEY)) {
                $env:ANTHROPIC_API_KEY = $Value
            }
            if ($Name -in @("FAL_KEY", "FAL_API_KEY") -and [string]::IsNullOrWhiteSpace($env:FAL_KEY)) {
                $env:FAL_KEY = $Value
            }
            $Value = $null
        }
    }
    if ([string]::IsNullOrWhiteSpace($env:ANTHROPIC_API_KEY)) { throw "ANTHROPIC_API_KEY_MISSING" }
    if ([string]::IsNullOrWhiteSpace($env:FAL_KEY)) { throw "FAL_KEY_MISSING" }
    if ([string]::IsNullOrWhiteSpace($Model)) { throw "FORGE_SEMANTIC_MODEL_MISSING" }
    $env:FORGE_SEMANTIC_MODEL = $Model.Trim()

    Write-Host "Running automatic exact-model acceptance for QBZ-95, M4A1, Type 81 and QSZ-92."
    Write-Host "Each candidate must pass AI visual identity verification and Godot geometry gates; no player confirmation is used."
    $Arguments = @(
        "--headless",
        "--path", $PlaylabRoot,
        "--script", "res://tools/visual/run_firearm_acceptance_matrix.gd",
        "--",
        "--fal-python=$Python",
        "--acceptance-output-dir=$OutputDirectory",
        "--max-retries=$MaxRetries"
    )
    $NativeArguments = foreach ($Argument in $Arguments) {
        if ($Argument -match '[\s"]') { '"' + $Argument.Replace('"', '\"') + '"' }
        else { $Argument }
    }
    $Process = Start-Process -FilePath $Godot -ArgumentList $NativeArguments -PassThru
    $Process.WaitForExit()
    $ExitCode = $Process.ExitCode
}
finally {
    if ($HadApiKey) { $env:ANTHROPIC_API_KEY = $SavedApiKey }
    else { Remove-Item Env:\ANTHROPIC_API_KEY -ErrorAction SilentlyContinue }
    if ($HadFalKey) { $env:FAL_KEY = $SavedFalKey }
    else { Remove-Item Env:\FAL_KEY -ErrorAction SilentlyContinue }
    if ($HadModel) { $env:FORGE_SEMANTIC_MODEL = $SavedModel }
    else { Remove-Item Env:\FORGE_SEMANTIC_MODEL -ErrorAction SilentlyContinue }
    $SavedApiKey = $null
    $SavedFalKey = $null
    $SavedModel = $null
}

exit $ExitCode
