[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^blind-retest-3c-[0-9]{8}T[0-9]{12}Z-[0-9a-f]{8}$')]
    [string]$RunId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ReviewJson
)

$ErrorActionPreference = "Stop"
$semanticRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $semanticRoot)
$reviewPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReviewJson)

if (-not (Test-Path -LiteralPath $reviewPath -PathType Leaf)) {
    throw "Blind Retest 3C review finalization stopped: review JSON does not exist."
}

# Finalization is strictly offline and must never inherit a provider credential.
Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
Remove-Item Env:FORGE_SEMANTIC_MODEL -ErrorAction SilentlyContinue

$pythonCommand = Get-Command python -ErrorAction Stop
& $pythonCommand.Source -E -S -B `
    (Join-Path $semanticRoot "bridge\blind_retest_3c_reporting.py") `
    "--repo-root" $repoRoot `
    "--run-id" $RunId `
    "--review-json" $reviewPath
exit $LASTEXITCODE

