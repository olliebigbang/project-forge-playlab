[CmdletBinding()]
param([switch]$Replay)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PlayerRoot = Split-Path -Parent $PSScriptRoot
$PlayerGodot = & (Join-Path $PSScriptRoot 'find_godot.ps1')
$PlayerLogs = Join-Path $PlayerRoot ('.tools/sunny-player/launch-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $PlayerLogs -Force | Out-Null
$PlayerImport = Start-Process -FilePath $PlayerGodot -ArgumentList @('--headless','--path',('"' + $PlayerRoot + '"'),'--editor','--import','--quit') -WorkingDirectory $PlayerRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $PlayerLogs 'import.stdout.log') -RedirectStandardError (Join-Path $PlayerLogs 'import.stderr.log')
# Windows PowerShell 5 must retain the process handle before waiting, or its
# detached Start-Process object can report a null ExitCode after successful import.
$PlayerImportHandle = $PlayerImport.Handle
if (-not $PlayerImport.WaitForExit(60000)) { $PlayerImport.Kill(); throw "Only this preview import helper timed out: $PlayerLogs" }
if ($PlayerImport.ExitCode -ne 0) { throw "Import failed: $PlayerLogs" }
$PlayerArguments = @('--path',('"' + $PlayerRoot + '"'),'res://scenes/sunny_player_preview.tscn')
if ($Replay) { $PlayerArguments = @('--path',('"' + $PlayerRoot + '"'),'--script','res://tests/authored_player_render_review.gd') }
$PlayerOptions = @{ FilePath=$PlayerGodot; ArgumentList=$PlayerArguments; WorkingDirectory=$PlayerRoot; PassThru=$true; RedirectStandardOutput=(Join-Path $PlayerLogs 'stdout.log'); RedirectStandardError=(Join-Path $PlayerLogs 'stderr.log') }
if ($Replay) { $PlayerOptions.WindowStyle = 'Hidden' }
$PlayerProcess = Start-Process @PlayerOptions
$PlayerProcessHandle = $PlayerProcess.Handle
Write-Output "Sunny player preview, offline. PID $($PlayerProcess.Id); logs: $PlayerLogs"
if ($Replay) {
    if (-not $PlayerProcess.WaitForExit(60000)) { $PlayerProcess.Kill(); throw "Only this preview replay timed out: $PlayerLogs" }
    Get-Content -LiteralPath (Join-Path $PlayerLogs 'stdout.log'),(Join-Path $PlayerLogs 'stderr.log')
    exit $PlayerProcess.ExitCode
}
