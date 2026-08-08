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
    & $pythonCommand.Source -E -S -B (Join-Path $semanticRoot "tests\test_affordance_contract_v1_2.py")
    if ($LASTEXITCODE -ne 0) { throw "Candidate contract tests failed before credential entry." }
    & $pythonCommand.Source -E -S -B (Join-Path $semanticRoot "tests\test_affordance_retest_v1_2.py")
    if ($LASTEXITCODE -ne 0) { throw "Candidate runner tests failed before credential entry." }
    & $pythonCommand.Source -E -S -B (Join-Path $semanticRoot "bridge\secret_scan.py") "--root" $repoRoot
    if ($LASTEXITCODE -ne 0) { throw "Secret scan failed before credential entry." }
    & $pythonCommand.Source -E -S -B `
        (Join-Path $semanticRoot "bridge\affordance_retest_v1_2_runner.py") `
        "--repo-root" $repoRoot "--preflight-only"
    if ($LASTEXITCODE -ne 0) { throw "Affordance Retest v1.2 preflight failed before credential entry." }

    Write-Output "Using frozen model ID: claude-sonnet-5"
    Write-Output "This process permits exactly 12 calls, one per frozen case, with zero retries."
    $secureKey = Read-Host "Enter ANTHROPIC_API_KEY for this 12-call process only" -AsSecureString
    $keyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
    $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPointer)
    if ([string]::IsNullOrWhiteSpace($plainKey)) { throw "API key was empty." }
    $env:ANTHROPIC_API_KEY = $plainKey
    $env:FORGE_SEMANTIC_MODEL = "claude-sonnet-5"
    & (Join-Path $PSScriptRoot "invoke_affordance_retest_v1_2_core.ps1")
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
