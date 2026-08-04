[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$runExitCode = 1

try {
    & (Join-Path $PSScriptRoot "test_semantic.ps1")
    if ($LASTEXITCODE -ne 0) {
        throw "Limited Retest 3B stopped before any real call because offline tests failed."
    }
    & (Join-Path $PSScriptRoot "invoke_limited_retest_3b_core.ps1")
    $runExitCode = $LASTEXITCODE
}
finally {
    Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:FORGE_SEMANTIC_MODEL -ErrorAction SilentlyContinue
}

exit $runExitCode
