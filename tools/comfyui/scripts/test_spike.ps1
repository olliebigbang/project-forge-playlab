$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$comfyRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $comfyRoot "config\forge_comfy_config.local.json"
if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Missing local config: $configPath"
}
$config = [System.IO.File]::ReadAllText($configPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
& $config.python_executable -m unittest discover -s (Join-Path $comfyRoot "tests") -p "test_*.py" -v
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $repoRoot "scripts\test.ps1")
exit $LASTEXITCODE
