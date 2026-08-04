[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$semanticRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $semanticRoot)
$sourceSummary = Join-Path $semanticRoot "reports\runs\gate-a-20260802T232039017356Z-fddde20a\gate_a_summary.json"
$secureKey = $null
$keyPointer = [IntPtr]::Zero
$plainKey = $null
$modelId = $null
$runExitCode = 1

try {
    & (Join-Path $PSScriptRoot "test_semantic.ps1")
    if ($LASTEXITCODE -ne 0) {
        throw "Limited Retest 3B stopped before requesting credentials because offline tests failed."
    }

    $pythonCommand = Get-Command python -ErrorAction Stop
    & $pythonCommand.Source -E -S -B `
        (Join-Path $semanticRoot "bridge\limited_retest_3b_runner.py") `
        "--repo-root" $repoRoot `
        "--preflight-only"
    if ($LASTEXITCODE -ne 0) {
        throw "Limited Retest 3B stopped before requesting credentials because preflight failed."
    }

    $source = Get-Content -Raw -Encoding UTF8 -LiteralPath $sourceSummary | ConvertFrom-Json
    $modelId = [string]$source.model_id
    if ([string]::IsNullOrWhiteSpace($modelId)) {
        throw "Limited Retest 3B stopped: frozen source model ID is unavailable."
    }
    Write-Output "Using frozen Gate A model ID: $modelId"
    $secureKey = Read-Host "Enter ANTHROPIC_API_KEY for this six-call process only" -AsSecureString
    $keyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
    $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPointer)
    if ([string]::IsNullOrWhiteSpace($plainKey)) {
        throw "Limited Retest 3B stopped: API key was empty."
    }
    $env:ANTHROPIC_API_KEY = $plainKey
    $env:FORGE_SEMANTIC_MODEL = $modelId
    & (Join-Path $PSScriptRoot "invoke_limited_retest_3b_core.ps1")
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
