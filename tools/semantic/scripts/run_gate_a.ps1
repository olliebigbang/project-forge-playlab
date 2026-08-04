[CmdletBinding()]
param(
    [switch]$ForceNewRun
)

$ErrorActionPreference = "Stop"
$runExitCode = 1

try {
    & (Join-Path $PSScriptRoot "test_semantic.ps1")
    if ($LASTEXITCODE -ne 0) {
        throw "Gate A stopped before any real call because offline preflight failed."
    }

    & (Join-Path $PSScriptRoot "invoke_gate_a_core.ps1") -ForceNewRun:$ForceNewRun
    $runExitCode = $LASTEXITCODE
}
finally {
    Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:FORGE_SEMANTIC_MODEL -ErrorAction SilentlyContinue
}

exit $runExitCode
