[CmdletBinding()]
param([switch]$Replay, [switch]$Verify)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Replay -and $Verify) { throw 'Choose Replay or Verify, not both.' }
$SunnyRoot = Split-Path -Parent $PSScriptRoot
$SunnyGodot = & (Join-Path $PSScriptRoot 'find_godot.ps1')
$SunnyLogs = Join-Path $SunnyRoot ('.tools/sunny-arena-preview-v1/launch-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $SunnyLogs -Force | Out-Null
# Godot's Windows GUI executable can return before its import process exits.
# Explicitly wait for this hidden helper before the scene preloads new textures.
$SunnyImport = Start-Process -FilePath $SunnyGodot -ArgumentList @('--headless', '--path', ('"' + $SunnyRoot + '"'), '--editor', '--import', '--quit') -WorkingDirectory $SunnyRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $SunnyLogs 'import.stdout.log') -RedirectStandardError (Join-Path $SunnyLogs 'import.stderr.log')
if (-not $SunnyImport.WaitForExit(45000)) {
    $SunnyImport.Kill()
    throw "Preview import timed out; inspect $SunnyLogs"
}
if ($SunnyImport.ExitCode -ne 0) { throw "Preview import failed; inspect $SunnyLogs" }
$SunnyArgs = @('--path', ('"' + $SunnyRoot + '"'), 'res://scenes/sunny_arena_preview_v1.tscn')
if ($Replay) { $SunnyArgs += @('--', '--replay') }
if ($Verify) { $SunnyArgs = @('--headless') + $SunnyArgs + @('--', '--verify') }
# No .env loading, online generation, weapon library or game save writes.
$SunnyOptions = @{
    FilePath = $SunnyGodot
    ArgumentList = $SunnyArgs
    WorkingDirectory = $SunnyRoot
    PassThru = $true
    RedirectStandardOutput = Join-Path $SunnyLogs 'stdout.log'
    RedirectStandardError = Join-Path $SunnyLogs 'stderr.log'
}
if ($Replay -or $Verify) { $SunnyOptions.WindowStyle = 'Hidden' }
$SunnyProcess = Start-Process @SunnyOptions
Write-Host "SunnyLand environment preview: offline; no combat or save changes. PID $($SunnyProcess.Id)"
Write-Host "Logs: $SunnyLogs"
if ($Replay -or $Verify) {
    if (-not $SunnyProcess.WaitForExit(45000)) {
        $SunnyProcess.Kill()
        throw "Only this preview child was stopped after timeout; inspect $SunnyLogs"
    }
    Get-Content -LiteralPath (Join-Path $SunnyLogs 'stdout.log')
    Get-Content -LiteralPath (Join-Path $SunnyLogs 'stderr.log')
    exit $SunnyProcess.ExitCode
}
