[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$semanticRoot = Split-Path -Parent $PSScriptRoot
$runExitCode = 1
$processApiKey = $env:ANTHROPIC_API_KEY
$processModelId = $env:FORGE_SEMANTIC_MODEL

try {
    # No credential is inherited by any offline test or preflight subprocess.
    Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:FORGE_SEMANTIC_MODEL -ErrorAction SilentlyContinue
    & (Join-Path $PSScriptRoot "test_semantic.ps1")
    if ($LASTEXITCODE -ne 0) {
        throw "Blind Retest 3C stopped before any real call because the semantic offline suite failed."
    }
    $pythonCommand = Get-Command python -ErrorAction Stop
    & $pythonCommand.Source -E -S -B `
        (Join-Path $semanticRoot "tests\test_blind_retest_3c_evaluator.py")
    if ($LASTEXITCODE -ne 0) {
        throw "Blind Retest 3C stopped before any real call because evaluator tests failed."
    }
    & $pythonCommand.Source -E -S -B `
        (Join-Path $semanticRoot "tests\test_blind_retest_3c_runner.py")
    if ($LASTEXITCODE -ne 0) {
        throw "Blind Retest 3C stopped before any real call because runner tests failed."
    }
    if ([string]::IsNullOrWhiteSpace($processApiKey)) {
        throw "Blind Retest 3C stopped: ANTHROPIC_API_KEY is missing. Use the interactive script."
    }
    if ($processModelId -cne "claude-sonnet-5") {
        throw "Blind Retest 3C stopped: FORGE_SEMANTIC_MODEL must exactly match the frozen model."
    }
    $env:ANTHROPIC_API_KEY = $processApiKey
    $env:FORGE_SEMANTIC_MODEL = $processModelId
    & (Join-Path $PSScriptRoot "invoke_blind_retest_3c_core.ps1")
    $runExitCode = $LASTEXITCODE
}
finally {
    Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:FORGE_SEMANTIC_MODEL -ErrorAction SilentlyContinue
    $processApiKey = $null
    $processModelId = $null
}

exit $runExitCode
