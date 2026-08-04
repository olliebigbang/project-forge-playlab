[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$OpenRoot = Split-Path -Parent $PSScriptRoot
$PlaylabRoot = Split-Path -Parent (Split-Path -Parent $OpenRoot)
$DocumentsRoot = Split-Path -Parent $PlaylabRoot
$PythonPath = "C:\AI\ComfyUI-ForgeFlux2\.venv\Scripts\python.exe"
$GodotConsolePath = Join-Path $DocumentsRoot "project forge\.tools\Godot_v4.7.1-stable_win64_console.exe"

if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) { throw "OPEN_PLAYTEST_PYTHON_MISSING" }
if (-not (Test-Path -LiteralPath $GodotConsolePath -PathType Leaf)) { throw "OPEN_PLAYTEST_GODOT_MISSING" }

& $PythonPath -m unittest discover -s (Join-Path $OpenRoot "tests") -p "test_*.py" -v
if ($LASTEXITCODE -ne 0) { throw "OPEN_PLAYTEST_PYTHON_TESTS_FAILED" }

& $PythonPath -m py_compile `
    (Join-Path $OpenRoot "bridge\open_playtest_session.py") `
    (Join-Path $OpenRoot "bridge\open_playtest_server.py") `
    (Join-Path $OpenRoot "bridge\open_playtest_cleanup.py") `
    (Join-Path $PlaylabRoot "tools\live_e2e\bridge\live_orchestrator.py")
if ($LASTEXITCODE -ne 0) { throw "OPEN_PLAYTEST_PYTHON_COMPILE_FAILED" }

& $GodotConsolePath --headless --path $PlaylabRoot --script "res://tools/open_playtest/godot/open_playtest.gd" --check-only
if ($LASTEXITCODE -ne 0) { throw "OPEN_PLAYTEST_GODOT_PARSE_FAILED" }

Write-Host "OPEN_PLAYTEST_OFFLINE_TESTS=PASS"
