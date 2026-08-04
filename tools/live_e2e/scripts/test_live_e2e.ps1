[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$LiveRoot = Split-Path -Parent $PSScriptRoot
$PythonPath = "C:\AI\ComfyUI-ForgeFlux2\.venv\Scripts\python.exe"
if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
    throw "LIVE_E2E_TEST_PYTHON_MISSING:$PythonPath"
}
& $PythonPath -m unittest discover -s (Join-Path $LiveRoot "tests") -p "test_*.py" -v
if ($LASTEXITCODE -ne 0) { throw "LIVE_E2E_OFFLINE_TESTS_FAILED" }
