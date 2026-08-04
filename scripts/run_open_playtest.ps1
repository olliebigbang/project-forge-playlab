[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PlaylabRoot = Split-Path -Parent $PSScriptRoot
& (Join-Path $PlaylabRoot "tools\open_playtest\scripts\run_open_playtest_interactive.ps1")
exit $LASTEXITCODE
