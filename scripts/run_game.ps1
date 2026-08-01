$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$godot = & (Join-Path $PSScriptRoot "find_godot.ps1")
& $godot --path $repoRoot @args
exit $LASTEXITCODE

