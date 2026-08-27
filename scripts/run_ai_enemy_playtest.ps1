[CmdletBinding()]
param(
    [string]$Concept = "",
    [string]$Model = "claude-sonnet-5",
    [string]$EnvFile = "",
    [switch]$ForceAI
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PlaylabRoot = Split-Path -Parent $PSScriptRoot
$Godot = & (Join-Path $PSScriptRoot "find_godot.ps1")
$Python = (Get-Command python -ErrorAction Stop).Source
$HadApiKey = Test-Path Env:ANTHROPIC_API_KEY
$HadModel = Test-Path Env:FORGE_SEMANTIC_MODEL
$SavedApiKey = $env:ANTHROPIC_API_KEY
$SavedModel = $env:FORGE_SEMANTIC_MODEL
$ExitCode = 1

try {
    if ([string]::IsNullOrWhiteSpace($EnvFile)) {
        $DefaultEnvFile = Join-Path $env:USERPROFILE ".env"
        if (Test-Path -LiteralPath $DefaultEnvFile) {
            $EnvFile = $DefaultEnvFile
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($EnvFile)) {
        $ResolvedEnvFile = (Resolve-Path -LiteralPath $EnvFile -ErrorAction Stop).Path
        foreach ($Line in Get-Content -LiteralPath $ResolvedEnvFile) {
            if ($Line -notmatch '^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') { continue }
            $Name = $Matches[1]
            if ($Name -ne "ANTHROPIC_API_KEY") { continue }
            $Value = $Matches[2].Trim()
            if ($Value.Length -ge 2 -and (
                ($Value.StartsWith('"') -and $Value.EndsWith('"')) -or
                ($Value.StartsWith("'") -and $Value.EndsWith("'"))
            )) {
                $Value = $Value.Substring(1, $Value.Length - 2)
            }
            if (-not [string]::IsNullOrWhiteSpace($Value) -and [string]::IsNullOrWhiteSpace($env:ANTHROPIC_API_KEY)) {
                $env:ANTHROPIC_API_KEY = $Value
            }
            $Value = $null
        }
    }
    if ([string]::IsNullOrWhiteSpace($env:ANTHROPIC_API_KEY)) {
        throw "ANTHROPIC_API_KEY_MISSING"
    }
    if ([string]::IsNullOrWhiteSpace($Model)) {
        throw "ENEMY_AI_MODEL_ID_REQUIRED"
    }
    $env:FORGE_SEMANTIC_MODEL = $Model.Trim()
    $Arguments = @(
        "--path", $PlaylabRoot,
        "res://scenes/ai_enemy_playtest.tscn",
        "--",
        "--enemy-ai-python=$Python"
    )
    if (-not [string]::IsNullOrWhiteSpace($Concept)) {
        $Arguments += "--auto-enemy=$($Concept.Trim())"
    }
    if ($ForceAI) {
        $Arguments += "--skip-enemy-cache"
    }
    $NativeArguments = foreach ($Argument in $Arguments) {
        if ($Argument -match '[\s"]') {
            '"' + $Argument.Replace('"', '\"') + '"'
        }
        else {
            $Argument
        }
    }
    $GodotProcess = Start-Process -FilePath $Godot -ArgumentList $NativeArguments -PassThru
    $GodotProcess.WaitForExit()
    $ExitCode = $GodotProcess.ExitCode
}
finally {
    if ($HadApiKey) { $env:ANTHROPIC_API_KEY = $SavedApiKey }
    else { Remove-Item Env:\ANTHROPIC_API_KEY -ErrorAction SilentlyContinue }
    if ($HadModel) { $env:FORGE_SEMANTIC_MODEL = $SavedModel }
    else { Remove-Item Env:\FORGE_SEMANTIC_MODEL -ErrorAction SilentlyContinue }
    $SavedApiKey = $null
    $SavedModel = $null
}

exit $ExitCode
