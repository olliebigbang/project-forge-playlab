$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$godot = & (Join-Path $PSScriptRoot "find_godot.ps1")
$output = Join-Path $repoRoot "build\web\index.html"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $output) | Out-Null
& $godot --headless --path $repoRoot --export-release "Web" $output
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output)) {
    throw "Web export failed. Confirm that the Godot 4.7.1 Web export templates are installed."
}
Write-Output "Web build: $output"

