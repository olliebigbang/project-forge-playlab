[CmdletBinding()]
param(
    [switch]$ForceNewRun
)

$ErrorActionPreference = "Stop"
$modelId = $null
$secureKey = $null
$keyPointer = [IntPtr]::Zero
$plainKey = $null
$runExitCode = 1

try {
    & (Join-Path $PSScriptRoot "test_semantic.ps1")
    if ($LASTEXITCODE -ne 0) {
        throw "Gate A stopped before requesting credentials because offline preflight failed."
    }

    $modelId = Read-Host "Enter the exact approved Claude model ID"
    if ([string]::IsNullOrWhiteSpace($modelId)) {
        throw "Gate A stopped: model ID is required and will not be guessed."
    }
    $secureKey = Read-Host "Enter ANTHROPIC_API_KEY for this process only" -AsSecureString
    $keyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
    $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPointer)
    if ([string]::IsNullOrWhiteSpace($plainKey)) {
        throw "Gate A stopped: API key was empty."
    }
    $env:ANTHROPIC_API_KEY = $plainKey
    $env:FORGE_SEMANTIC_MODEL = $modelId.Trim()
    & (Join-Path $PSScriptRoot "invoke_gate_a_core.ps1") -ForceNewRun:$ForceNewRun
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
