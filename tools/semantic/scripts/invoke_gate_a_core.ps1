[CmdletBinding()]
param(
    [switch]$ForceNewRun
)

$ErrorActionPreference = "Stop"
$semanticRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $semanticRoot)

if ([string]::IsNullOrWhiteSpace($env:ANTHROPIC_API_KEY)) {
    throw "Gate A stopped: ANTHROPIC_API_KEY is missing. Use run_gate_a_interactive.ps1 or set it only for this process."
}
if ([string]::IsNullOrWhiteSpace($env:FORGE_SEMANTIC_MODEL)) {
    throw "Gate A stopped: FORGE_SEMANTIC_MODEL is missing. The model ID will not be guessed."
}

$pythonCommand = Get-Command python -ErrorAction Stop
$arguments = @(
    (Join-Path $semanticRoot "bridge\gate_a_runner.py"),
    "--repo-root", $repoRoot
)
if ($ForceNewRun) {
    $arguments += "--force-new-run"
}

& $pythonCommand.Source -E -S -B @arguments
exit $LASTEXITCODE
