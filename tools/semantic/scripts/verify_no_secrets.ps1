$ErrorActionPreference = "Stop"

$semanticRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $semanticRoot)
$pythonCommand = Get-Command python -ErrorAction Stop
$hadApiKey = Test-Path Env:ANTHROPIC_API_KEY
$hadModel = Test-Path Env:FORGE_SEMANTIC_MODEL
$savedApiKey = $env:ANTHROPIC_API_KEY
$savedModel = $env:FORGE_SEMANTIC_MODEL
$scanExitCode = 1

try {
    Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:FORGE_SEMANTIC_MODEL -ErrorAction SilentlyContinue
    & $pythonCommand.Source -E -S -B (Join-Path $semanticRoot "bridge\secret_scan.py") --root $repoRoot
    $scanExitCode = $LASTEXITCODE
}
finally {
    if ($hadApiKey) { $env:ANTHROPIC_API_KEY = $savedApiKey }
    if ($hadModel) { $env:FORGE_SEMANTIC_MODEL = $savedModel }
    $savedApiKey = $null
    $savedModel = $null
}
exit $scanExitCode
