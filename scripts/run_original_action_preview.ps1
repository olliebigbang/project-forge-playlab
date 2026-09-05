[CmdletBinding()]
param([switch]$Review, [switch]$Test)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ActionProject = Split-Path -Parent $PSScriptRoot
$ActionGodot = & (Join-Path $PSScriptRoot 'find_godot.ps1')
$ActionLogs = Join-Path $ActionProject ('.tools/original-actions/launch-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $ActionLogs -Force | Out-Null
$ActionImport = Start-Process -FilePath $ActionGodot -ArgumentList @('--headless','--path',('"' + $ActionProject + '"'),'--editor','--import','--quit') -WorkingDirectory $ActionProject -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $ActionLogs 'import.stdout.log') -RedirectStandardError (Join-Path $ActionLogs 'import.stderr.log')
if (-not $ActionImport.WaitForExit(60000)) { $ActionImport.Kill(); throw "Preview import helper timed out: $ActionLogs" }
if ($ActionImport.ExitCode -ne 0) { throw "Import failed: $ActionLogs" }
$ActionArgs = @('--path',('"' + $ActionProject + '"'),'res://scenes/original_action_preview.tscn')
if ($Review) { $ActionArgs = @('--path',('"' + $ActionProject + '"'),'--script','res://tests/original_action_render_review.gd') }
if ($Test) { $ActionArgs = @('--headless','--path',('"' + $ActionProject + '"'),'--script','res://tests/test_original_action_preview.gd') }
$ActionOptions = @{FilePath=$ActionGodot;ArgumentList=$ActionArgs;WorkingDirectory=$ActionProject;PassThru=$true;RedirectStandardOutput=(Join-Path $ActionLogs 'stdout.log');RedirectStandardError=(Join-Path $ActionLogs 'stderr.log')}
if ($Review -or $Test) { $ActionOptions.WindowStyle = 'Hidden' }
$ActionProcess = Start-Process @ActionOptions
Write-Output "Original action preview, offline. PID $($ActionProcess.Id); logs: $ActionLogs"
if ($Review -or $Test) {
    if (-not $ActionProcess.WaitForExit(60000)) { throw "Still running PID $($ActionProcess.Id); inspect logs: $ActionLogs" }
    Get-Content -LiteralPath (Join-Path $ActionLogs 'stdout.log'),(Join-Path $ActionLogs 'stderr.log')
    exit $ActionProcess.ExitCode
}
