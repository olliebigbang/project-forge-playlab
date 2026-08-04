$ErrorActionPreference = "Stop"

$semanticRoot = Split-Path -Parent $PSScriptRoot
$pythonCommand = Get-Command python -ErrorAction Stop
$hadApiKey = Test-Path Env:ANTHROPIC_API_KEY
$hadModel = Test-Path Env:FORGE_SEMANTIC_MODEL
$savedApiKey = $env:ANTHROPIC_API_KEY
$savedModel = $env:FORGE_SEMANTIC_MODEL
$testExitCode = 1

try {
    Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:FORGE_SEMANTIC_MODEL -ErrorAction SilentlyContinue
    & $pythonCommand.Source -E -S -B (Join-Path $semanticRoot "tests\run_offline_tests.py")
    $testExitCode = $LASTEXITCODE
}
finally {
    if ($hadApiKey) { $env:ANTHROPIC_API_KEY = $savedApiKey }
    if ($hadModel) { $env:FORGE_SEMANTIC_MODEL = $savedModel }
    $savedApiKey = $null
    $savedModel = $null
}
if ($testExitCode -ne 0) {
    throw "Gate A offline tests failed; no real request is allowed."
}

& (Join-Path $PSScriptRoot "verify_no_secrets.ps1")
if ($LASTEXITCODE -ne 0) {
    throw "Gate A secret scan failed; no real request is allowed."
}

Write-Output "GATE_A_OFFLINE_PREFLIGHT=PASS"
exit 0
