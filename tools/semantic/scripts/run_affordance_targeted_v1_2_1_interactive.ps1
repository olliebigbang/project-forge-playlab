[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$semanticRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $semanticRoot)
$secureKey = $null
$keyPointer = [IntPtr]::Zero
$plainKey = $null
$runExitCode = 1

try {
    $pythonCommand = Get-Command python -ErrorAction Stop
    & $pythonCommand.Source -E -S -B (Join-Path $semanticRoot "tests\test_affordance_contract_v1_2_1.py")
    if ($LASTEXITCODE -ne 0) { throw "v1.2.1 offline regressions failed before credential entry." }
    & $pythonCommand.Source -E -S -B (Join-Path $semanticRoot "bridge\secret_scan.py") "--root" $repoRoot
    if ($LASTEXITCODE -ne 0) { throw "Secret scan failed before credential entry." }
    & $pythonCommand.Source -E -S -B `
        (Join-Path $semanticRoot "bridge\affordance_targeted_retest_v1_2_1_runner.py") `
        "--repo-root" $repoRoot `
        "--preflight-only"
    if ($LASTEXITCODE -ne 0) { throw "Targeted v1.2.1 preflight failed before credential entry." }

    Write-Output "Using frozen model ID: claude-sonnet-5"
    Write-Output "Approved cases: A03, A07, A08, A09. Exactly one call each; zero retries."
    $secureKey = Read-Host "Enter ANTHROPIC_API_KEY for this four-call process only" -AsSecureString
    $keyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
    $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPointer)
    if ([string]::IsNullOrWhiteSpace($plainKey)) { throw "API key was empty." }
    $env:ANTHROPIC_API_KEY = $plainKey
    $env:FORGE_SEMANTIC_MODEL = "claude-sonnet-5"
    & (Join-Path $PSScriptRoot "invoke_affordance_targeted_v1_2_1_core.ps1")
    $runExitCode = $LASTEXITCODE
}
finally {
    Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:FORGE_SEMANTIC_MODEL -ErrorAction SilentlyContinue
    $plainKey = $null
    if ($keyPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPointer) }
    if ($null -ne $secureKey) { $secureKey.Dispose() }
}

exit $runExitCode
