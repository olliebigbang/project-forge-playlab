$ErrorActionPreference = "Stop"

$comfyRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $comfyRoot "config\forge_comfy_config.local.json"
if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Missing local config: $configPath"
}
$config = [System.IO.File]::ReadAllText($configPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
& $config.python_executable (Join-Path $comfyRoot "test_cases\make_sketches.py")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $config.python_executable (Join-Path $comfyRoot "bridge\run_spike.py") --config $configPath
exit $LASTEXITCODE
