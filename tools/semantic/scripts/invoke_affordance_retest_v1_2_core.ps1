[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$semanticRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $semanticRoot)

if ([string]::IsNullOrWhiteSpace($env:ANTHROPIC_API_KEY)) {
    throw "Affordance Retest v1.2 stopped: ANTHROPIC_API_KEY is missing. Use the interactive script."
}
if ($env:FORGE_SEMANTIC_MODEL -cne "claude-sonnet-5") {
    throw "Affordance Retest v1.2 stopped: model ID must exactly match claude-sonnet-5."
}

$pythonCommand = Get-Command python -ErrorAction Stop
& $pythonCommand.Source -E -S -B `
    (Join-Path $semanticRoot "bridge\affordance_retest_v1_2_runner.py") `
    "--repo-root" $repoRoot
exit $LASTEXITCODE
