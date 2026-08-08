[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$semanticRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $semanticRoot)

if ([string]::IsNullOrWhiteSpace($env:ANTHROPIC_API_KEY)) {
    throw "Targeted Affordance Retest v1.2.1 stopped: ANTHROPIC_API_KEY is missing."
}
if ($env:FORGE_SEMANTIC_MODEL -cne "claude-sonnet-5") {
    throw "Targeted Affordance Retest v1.2.1 stopped: model ID must exactly match claude-sonnet-5."
}

$pythonCommand = Get-Command python -ErrorAction Stop
& $pythonCommand.Source -E -S -B `
    (Join-Path $semanticRoot "bridge\affordance_targeted_retest_v1_2_1_runner.py") `
    "--repo-root" $repoRoot `
    "--execute-approved-four-call-retest"
exit $LASTEXITCODE
