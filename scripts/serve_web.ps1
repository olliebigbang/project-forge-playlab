$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$webRoot = Join-Path $repoRoot "build\web"
if (-not (Test-Path -LiteralPath (Join-Path $webRoot "index.html"))) {
    throw "Web build not found. Run ./scripts/build_web.ps1 first."
}
Write-Output "Serving Forge Playlab at http://localhost:8060"
python -m http.server 8060 --directory $webRoot

