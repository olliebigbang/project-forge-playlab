$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$godot = & (Join-Path $PSScriptRoot "find_godot.ps1")
& $godot --headless --path $repoRoot --script (Join-Path $repoRoot "tests\run_tests.gd")
exit $LASTEXITCODE

