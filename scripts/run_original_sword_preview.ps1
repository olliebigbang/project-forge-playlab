[CmdletBinding()]
param([switch]$Review)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$SwordProject = Split-Path -Parent $PSScriptRoot
$SwordGodot = & (Join-Path $PSScriptRoot 'find_godot.ps1')
$SwordLogs = Join-Path $SwordProject ('.tools/original-sword/launch-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $SwordLogs -Force | Out-Null
$SwordImport = Start-Process -FilePath $SwordGodot -ArgumentList @('--headless','--path',('"' + $SwordProject + '"'),'--editor','--import','--quit') -WorkingDirectory $SwordProject -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $SwordLogs 'import.stdout.log') -RedirectStandardError (Join-Path $SwordLogs 'import.stderr.log')
if (-not $SwordImport.WaitForExit(60000)) { $SwordImport.Kill(); throw "This preview import helper timed out: $SwordLogs" }
if ($SwordImport.ExitCode -ne 0) { throw "Import failed: $SwordLogs" }
$SwordArgs = @('--path',('"' + $SwordProject + '"'),'res://scenes/original_sword_preview.tscn')
if ($Review) { $SwordArgs = @('--path',('"' + $SwordProject + '"'),'--script','res://tests/original_sword_render_review.gd') }
$SwordOptions = @{FilePath=$SwordGodot;ArgumentList=$SwordArgs;WorkingDirectory=$SwordProject;PassThru=$true;RedirectStandardOutput=(Join-Path $SwordLogs 'stdout.log');RedirectStandardError=(Join-Path $SwordLogs 'stderr.log')}
if ($Review) { $SwordOptions.WindowStyle = 'Hidden' }
$SwordProcess = Start-Process @SwordOptions
Write-Output "Original sword preview, offline. PID $($SwordProcess.Id); logs: $SwordLogs"
if ($Review) {
    if (-not $SwordProcess.WaitForExit(60000)) { $SwordProcess.Kill(); throw "This preview review helper timed out: $SwordLogs" }
    Get-Content -LiteralPath (Join-Path $SwordLogs 'stdout.log'),(Join-Path $SwordLogs 'stderr.log')
    exit $SwordProcess.ExitCode
}
