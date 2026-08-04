[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$semanticRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $semanticRoot)

if ([string]::IsNullOrWhiteSpace($env:ANTHROPIC_API_KEY)) {
    throw "Limited Retest 3B stopped: ANTHROPIC_API_KEY is missing. Use run_limited_retest_3b_interactive.ps1."
}
if ([string]::IsNullOrWhiteSpace($env:FORGE_SEMANTIC_MODEL)) {
    throw "Limited Retest 3B stopped: FORGE_SEMANTIC_MODEL is missing."
}

$pythonCommand = Get-Command python -ErrorAction Stop
& $pythonCommand.Source -E -S -B `
    (Join-Path $semanticRoot "bridge\limited_retest_3b_runner.py") `
    "--repo-root" $repoRoot
exit $LASTEXITCODE
