[CmdletBinding()]
param(
    [switch]$AffordanceGrammar
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PlaylabRoot = Split-Path -Parent $PSScriptRoot
& (Join-Path $PlaylabRoot "tools\open_playtest\scripts\run_open_playtest_interactive.ps1") `
    -AffordanceGrammar:$AffordanceGrammar
exit $LASTEXITCODE
