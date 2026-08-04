[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$semanticRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $semanticRoot)

if ([string]::IsNullOrWhiteSpace($env:ANTHROPIC_API_KEY)) {
    throw "Blind Retest 3C stopped: ANTHROPIC_API_KEY is missing. Use run_blind_retest_3c_interactive.ps1."
}
if ([string]::IsNullOrWhiteSpace($env:FORGE_SEMANTIC_MODEL)) {
    throw "Blind Retest 3C stopped: FORGE_SEMANTIC_MODEL is missing."
}

$pythonCommand = Get-Command python -ErrorAction Stop
& $pythonCommand.Source -E -S -B `
    (Join-Path $semanticRoot "bridge\blind_retest_3c_runner.py") `
    "--repo-root" $repoRoot
exit $LASTEXITCODE

