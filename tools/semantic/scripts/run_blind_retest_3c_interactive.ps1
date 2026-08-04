[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$semanticRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $semanticRoot)
$sourceSummary = Join-Path $semanticRoot "reports\limited_retest_3b\limited-retest-3b-20260803T040934865715Z-79738d1b\limited_retest_3b_summary.json"
$secureKey = $null
$keyPointer = [IntPtr]::Zero
$plainKey = $null
$modelId = $null
$runExitCode = 1

try {
    & (Join-Path $PSScriptRoot "test_semantic.ps1")
    if ($LASTEXITCODE -ne 0) {
        throw "Blind Retest 3C stopped before requesting credentials because the semantic offline suite failed."
    }

    $pythonCommand = Get-Command python -ErrorAction Stop
    & $pythonCommand.Source -E -S -B `
        (Join-Path $semanticRoot "tests\test_blind_retest_3c_evaluator.py")
    if ($LASTEXITCODE -ne 0) {
        throw "Blind Retest 3C stopped before requesting credentials because evaluator tests failed."
    }
    & $pythonCommand.Source -E -S -B `
        (Join-Path $semanticRoot "tests\test_blind_retest_3c_runner.py")
    if ($LASTEXITCODE -ne 0) {
        throw "Blind Retest 3C stopped before requesting credentials because runner tests failed."
    }
    & $pythonCommand.Source -E -S -B `
        (Join-Path $semanticRoot "bridge\blind_retest_3c_runner.py") `
        "--repo-root" $repoRoot `
        "--preflight-only"
    if ($LASTEXITCODE -ne 0) {
        throw "Blind Retest 3C stopped before requesting credentials because preflight failed."
    }

    $source = Get-Content -Raw -Encoding UTF8 -LiteralPath $sourceSummary | ConvertFrom-Json
    $modelId = [string]$source.model_id
    if ($modelId -cne "claude-sonnet-5") {
        throw "Blind Retest 3C stopped: frozen source model ID is unavailable or changed."
    }
    Write-Output "Using frozen 3B model ID: $modelId"
    $secureKey = Read-Host "Enter ANTHROPIC_API_KEY for this four-call process only" -AsSecureString
    $keyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
    $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPointer)
    if ([string]::IsNullOrWhiteSpace($plainKey)) {
        throw "Blind Retest 3C stopped: API key was empty."
    }
    $env:ANTHROPIC_API_KEY = $plainKey
    $env:FORGE_SEMANTIC_MODEL = $modelId
    & (Join-Path $PSScriptRoot "invoke_blind_retest_3c_core.ps1")
    $runExitCode = $LASTEXITCODE
}
finally {
    Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:FORGE_SEMANTIC_MODEL -ErrorAction SilentlyContinue
    $plainKey = $null
    $modelId = $null
    if ($keyPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPointer)
    }
    if ($null -ne $secureKey) {
        $secureKey.Dispose()
    }
}

exit $runExitCode

