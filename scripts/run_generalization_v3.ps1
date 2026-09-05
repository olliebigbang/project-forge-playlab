[CmdletBinding()]
param(
    [switch]$AllowLiveSemantic,
    [string]$EnvFile = "",
    [string]$Model = "claude-sonnet-5",
    [string]$SampleIds = "",
    [string]$ResultsFrom = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$RunRoot = Join-Path $ProjectRoot (".tools/generalization-v3/" + [guid]::NewGuid().ToString("N"))
$Manifest = Join-Path $ProjectRoot "data/sunny_generalization_matrix_v3.json"
$Runner = Join-Path $ProjectRoot "tools/semantic/bridge/generalization_v3_matrix.py"
$Bridge = Join-Path $ProjectRoot "tools/semantic/bridge/general_object_ai_bridge.py"
$PreviousKey = [Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY", "Process")
$PreviousModel = [Environment]::GetEnvironmentVariable("FORGE_SEMANTIC_MODEL", "Process")
[Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", $null, "Process")
[Environment]::SetEnvironmentVariable("FORGE_SEMANTIC_MODEL", $null, "Process")
New-Item -ItemType Directory -Path $RunRoot -Force | Out-Null
try {
    $Arguments = @("-B", $Runner, "--manifest", $Manifest, "--output-dir", $RunRoot)
    if ($AllowLiveSemantic -and -not [string]::IsNullOrWhiteSpace($ResultsFrom)) { throw "Live semantic mode and offline recheck are mutually exclusive." }
    if (-not [string]::IsNullOrWhiteSpace($ResultsFrom)) {
        foreach ($Source in $ResultsFrom.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)) {
            $Arguments += @("--results-from", $Source.Trim())
        }
        Write-Output "V3 offline evidence recheck: zero online requests."
    }
    if ($AllowLiveSemantic) {
        if ([string]::IsNullOrWhiteSpace($EnvFile)) { $EnvFile = Join-Path $env:USERPROFILE ".env" }
        foreach ($Line in Get-Content -LiteralPath $EnvFile) {
            if ($Line -notmatch '^\s*(?:export\s+)?ANTHROPIC_API_KEY\s*=\s*(.*?)\s*$') { continue }
            $Value = $Matches[1].Trim().Trim('"').Trim("'")
            if (-not [string]::IsNullOrWhiteSpace($Value)) { [Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", $Value, "Process") }
            $Value = $null
        }
        if (-not $env:ANTHROPIC_API_KEY) { throw "ANTHROPIC_API_KEY missing; value is never logged." }
        if ([string]::IsNullOrWhiteSpace($Model)) { throw "Semantic model id is required." }
        [Environment]::SetEnvironmentVariable("FORGE_SEMANTIC_MODEL", $Model, "Process")
        $Arguments += @("--allow-live-semantic", "--bridge", $Bridge)
        if (-not [string]::IsNullOrWhiteSpace($SampleIds)) { $Arguments += @("--sample-ids", $SampleIds) }
        Write-Output "V3 live semantic matrix: bounded selected entry requests, zero image requests."
    } elseif ([string]::IsNullOrWhiteSpace($ResultsFrom)) {
        Write-Output "V3 offline plan: zero online requests."
    }
    & python @Arguments
    $Exit = $LASTEXITCODE
    Write-Output "Evidence: $RunRoot"
    exit $Exit
}
finally {
    [Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", $PreviousKey, "Process")
    [Environment]::SetEnvironmentVariable("FORGE_SEMANTIC_MODEL", $PreviousModel, "Process")
    $Value = $null
}
